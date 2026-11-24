-- Maven discovery, per-project model preparation and live review lifecycle.
local M = { contexts = {} }
local uv = vim.uv
local options = require("user.lathe_config")
local script = vim.fn.expand("~/.config/nvim/scripts/lathe-model.py")
local by_pom, by_analysis, inspecting, inspection_jobs, queue = {}, {}, {}, {}, {}
local timer, active, stopped, last_context, ticks

local function canonical(path)
  return vim.fs.normalize(uv.fs_realpath(path) or path)
end
local function inside(path, root)
  return path == root or vim.startswith(path, root .. "/")
end
local function filename(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return nil end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or name:match("^%a[%w+.-]*://") then return nil end
  return canonical(name)
end
local function nearest_pom(path)
  local found = vim.fs.root(path, "pom.xml")
  return found and canonical(found)
end
local function command(action, args)
  local cmd = { options.python, script, action, "--state-root", options.state_root,
    "--worktree-root", options.worktree_root, "--resources", options.resources }
  vim.list_extend(cmd, args or {})
  return cmd
end
local function read_json(path)
  local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(path), "\n")) end)
  return ok and data or nil
end
local function model_exists(ctx)
  return uv.fs_stat(ctx.analysis .. "/.lathe/workspace.json") ~= nil
end
local function state_version(ctx)
  local stat = uv.fs_stat(ctx.state .. "/state.json")
  return stat and ("%s:%s:%s"):format(stat.ino, stat.mtime.sec, stat.mtime.nsec) or ""
end
local function signature(ctx)
  local values = {}
  for _, path in ipairs(ctx.watch or {}) do
    local s = uv.fs_stat(path)
    values[#values + 1] = s and (path .. ":" .. s.size .. ":" .. s.mtime.sec .. ":" .. s.mtime.nsec) or path .. ":missing"
  end
  return vim.fn.sha256(table.concat(values, "\n"))
end
local function update(ctx, data)
  if not data then return end
  if data.status then ctx.missing_dependency = data.missing_dependency end
  for _, key in ipairs({ "watch", "watch_values", "status", "error", "log", "java_releases", "navigation_only",
    "partial_model", "dependency_override_count" }) do
    if data[key] ~= nil then ctx[key] = data[key] end
  end
  ctx.ready = model_exists(ctx)
  if data.watch_values then ctx.attempted = vim.fn.sha256(table.concat(data.watch_values, "\n")) end
end
local function changed()
  pcall(vim.cmd, "redrawstatus")
end

function M.context(buf)
  local name = filename(buf or 0)
  if not name then return nil end
  for _, ctx in pairs(M.contexts) do
    if inside(name, ctx.cache) or inside(name, ctx.analysis) then last_context = ctx; return ctx end
  end
  local root = nearest_pom(name)
  local ctx = root and by_pom[root]
  if ctx then last_context = ctx end
  return ctx
end
function M.root(buf)
  local ctx = M.context(buf or 0)
  return ctx and ctx.ready and ctx.analysis or nil
end
function M.from_client(client_id)
  local c = vim.lsp.get_client_by_id(client_id)
  return c and by_analysis[c.config.root_dir] or nil
end

local function attach_waiters(ctx)
  if not ctx.ready then return end
  local waiters = ctx.waiters or {}; ctx.waiters = {}
  for buf, callbacks in pairs(waiters) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
      for _, callback in ipairs(callbacks) do callback(ctx) end
      M.attach(buf)
    end
  end
end
local function finish(ctx, result)
  local ok, data = pcall(vim.json.decode, result.stdout or "", { luanil = { object = true, array = true } })
  if not ok or type(data) ~= "table" then data = nil end
  update(ctx, data)
  ctx.ready = model_exists(ctx)
  if result.code == 75 then
    ctx.status, ctx.waiting = "waiting", true
  elseif result.code == 0 and data and data.status == "ready" and ctx.ready then
    ctx.status, ctx.waiting, ctx.error = "ready", false, nil
    attach_waiters(ctx)
  else
    ctx.status, ctx.waiting = "failed", false
    ctx.error = (data and data.error) or (result.stderr ~= "" and result.stderr)
      or "Preparation did not publish a usable model"
    if not ctx.attempted then ctx.attempted = signature(ctx) end
    M.last_failure = ctx
    -- Keep failures non-blocking; full output is available on explicit request.
    local message = ctx.missing_dependency and ("Lathe: Maven dependency unavailable offline: " .. ctx.missing_dependency
      .. ". Check :LatheLog and retry after the exact artifact is cached.")
      or "Lathe preparation failed. Run :LatheLog for details."
    vim.api.nvim_echo({ { message, "WarningMsg" } }, true, {})
  end
  changed()
end
local enqueue
local function pump()
  if stopped or active or #queue == 0 then return end
  local ctx = table.remove(queue, 1)
  ctx.queued, ctx.status = false, "preparing"
  ctx.attempted = signature(ctx)
  active = ctx
  local cmd = command("prepare", { "--root", ctx.source })
  local before, clean = state_version(ctx), ctx.clean
  if clean then cmd[#cmd + 1] = "--clean" end
  ctx.job = vim.system(cmd, { text = true }, vim.schedule_wrap(function(result)
    ctx.job, active = nil, nil
    if stopped then return end
    local ok, err = pcall(finish, ctx, result)
    if not ok then ctx.status, ctx.error = "failed", tostring(err); changed() end
    local followup = ctx.followup_clean
    ctx.followup_clean = nil
    if ctx.waiting then
      ctx.waiting_version, ctx.waiting_clean = before, clean or followup
    elseif followup then
      enqueue(ctx, true)
    end
    pump()
  end))
  changed()
end
enqueue = function(ctx, clean)
  if stopped then return end
  if ctx.job then
    if clean and not ctx.clean then ctx.followup_clean = true end
    return
  end
  if ctx.queued then
    ctx.clean = ctx.clean or clean
    return
  end
  if ctx.waiting then
    ctx.waiting_clean = ctx.waiting_clean or clean
    return
  end
  ctx.clean, ctx.queued, ctx.status = clean, true, "queued"
  queue[#queue + 1] = ctx
  pump()
end

local function ensure_path(name, buf, callback, clean)
  if stopped then return end
  if not name then return end
  if inside(name, options.state_root) then
    -- Generated and extracted sources belong to the client that produced them.
    -- Reuse that model without discovering or building a second project.
    local ctx = buf and M.context(buf)
    if ctx and ctx.ready then
      ctx.dormant = false
      if callback then callback(ctx) else M.attach(buf) end
      if clean ~= nil then enqueue(ctx, clean) end
      return
    end
    local key = name:match("^" .. vim.pesc(options.state_root) .. "/projects/(%x+)/cache/deps/")
    if key then
      local state = options.state_root .. "/projects/" .. key
      local identity = read_json(state .. "/identity.json")
      if identity and identity.id == key and identity.cache == state .. "/cache"
          and type(identity.source) == "string" and not inside(canonical(identity.source), options.state_root)
          and uv.fs_stat(identity.source .. "/pom.xml") then
        ensure_path(canonical(identity.source .. "/pom.xml"), buf, callback, clean)
      end
    end
    return
  end
  -- A managed build copy must not recursively create another analysis worktree.
  local key = name:match("^" .. vim.pesc(canonical(options.worktree_root)) .. "/lathe%-(%x+)/")
  if key then
    local identity = read_json(options.state_root .. "/projects/" .. key .. "/identity.json")
    if identity and inside(name, identity.build_repository) then return end
  end
  local root = nearest_pom(name)
  if not root then return end
  local ctx = by_pom[root]
  if ctx then
    ctx.dormant = false
    last_context = ctx
    if clean ~= nil then enqueue(ctx, clean) end
    if ctx.ready then if callback then callback(ctx) end; return end
    ctx.waiters = ctx.waiters or {}
    if buf then
      ctx.waiters[buf] = ctx.waiters[buf] or {}
      if callback then ctx.waiters[buf][#ctx.waiters[buf] + 1] = callback end
    end
    if ctx.status ~= "failed" and not ctx.waiting then enqueue(ctx, false) end
    return
  end
  if inspecting[root] then
    local request = inspecting[root]
    if buf and (callback or request.waiters[buf] == nil) then request.waiters[buf] = callback or false end
    if clean ~= nil then request.clean = request.clean or clean end
    return
  end
  inspecting[root] = { waiters = buf and { [buf] = callback or false } or {}, clean = clean }
  inspection_jobs[root] = vim.system(command("inspect", { "--file", name }), { text = true }, vim.schedule_wrap(function(result)
    inspection_jobs[root] = nil
    local request = inspecting[root]; inspecting[root] = nil
    if stopped then return end
    local ok, data = pcall(vim.json.decode, result.stdout or "")
    if not ok or result.code ~= 0 or not data.id then
      vim.notify("Lathe: Could not detect the Maven project: " .. (ok and data.error or result.stderr or "unknown error"), vim.log.levels.WARN)
      return
    end
    ctx = M.contexts[data.id]
    if not ctx then
      ctx = data; M.contexts[ctx.id] = ctx; by_analysis[ctx.analysis] = ctx
      ctx.waiters = {}; update(ctx, data)
      ctx.waiting = ctx.status == "preparing"
      if ctx.ready and not ctx.status then update(ctx, read_json(ctx.analysis .. "/live-state.json")); ctx.status = "ready" end
    end
    by_pom[root] = ctx; last_context = ctx
    for b, cb in pairs(request.waiters) do
      ctx.waiters[b] = ctx.waiters[b] or {}
      if cb then ctx.waiters[b][#ctx.waiters[b] + 1] = cb end
    end
    if ctx.ready then attach_waiters(ctx) end
    if request.clean ~= nil or not ctx.ready or data.needs_analysis_refresh then enqueue(ctx, request.clean or false) end
  end))
end
function M.ensure(buf, callback)
  if not buf or buf == 0 then buf = vim.api.nvim_get_current_buf() end
  ensure_path(filename(buf), buf, callback)
end
function M.ensure_directory(path)
  ensure_path(canonical(path) .. "/pom.xml", nil, nil)
end
function M.attach(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "java" then return end
  local root = M.root(buf)
  if not root then return end
  local c = vim.lsp.get_clients({ name = "lathe", bufnr = buf })
  if #c == 0 then require("lathe").start(buf) end
end
function M.refresh(buf, clean)
  if not buf or buf == 0 then buf = vim.api.nvim_get_current_buf() end
  local ctx = M.context(buf)
  local name = filename(buf)
  if not ctx and name then
    ensure_path(name, buf, nil, clean == true)
    return
  end
  ctx = ctx or last_context
  if not ctx then return end
  ctx.dormant = false
  enqueue(ctx, clean == true)
end
function M.model_changed(client_id)
  local ctx = M.from_client(client_id)
  if ctx and signature(ctx) ~= ctx.attempted then enqueue(ctx, false) end
end
function M.log()
  local current = M.context(0)
  local ctx = current or M.last_failure or last_context
  if not ctx then return end
  vim.cmd("botright split " .. vim.fn.fnameescape(ctx.state .. "/logs/capture.log"))
  vim.bo.readonly = true
end
function M.status()
  local ctx = M.context(0) or last_context
  if not ctx then return "none", "Lathe · Open a Java file in a Maven project to start" end
  local name = vim.fs.basename(ctx.source)
  if ctx.status == "preparing" then return "busy", "Lathe Preparing project model · " .. name end
  if ctx.status == "queued" or ctx.waiting then return "busy", "Lathe Waiting to prepare project model · " .. name end
  if ctx.status == "failed" then
    local state = ctx.ready and "Update failed (using previous model)" or "Setup failed"
    local subject = ctx.missing_dependency or name
    local hint = ctx.missing_dependency and " · See :LatheLog" or " · ,lr to retry"
    return "error", "Lathe " .. state .. " · " .. subject .. hint
  end
  local note = ctx.partial_model and " · Partial index (Maven errors)"
    or (ctx.navigation_only and " · Source compilation errors" or "")
  local level = note ~= "" and "warning" or "ready"
  if (ctx.dependency_override_count or 0) > 0 then note = note .. " · Dependency overrides active" end
  local cs = vim.lsp.get_clients({ name = "lathe" })
  for _, c in ipairs(cs) do
    if c.config.root_dir == ctx.analysis then
      local releases = ctx.java_releases or { 8 }
      local java = #releases > 0 and "Java " .. table.concat(releases, "/") .. " · " or ""
      return c.initialized and level or "busy", "Lathe · " .. java .. name .. note
    end
  end
  if ctx.ready then return level, "Lathe Project model ready · " .. name .. note end
  return "none", "Lathe · No project model · " .. name
end

function M.check_buffers()
  if vim.api.nvim_get_mode().mode:match("^[ictRr!]") then return end
  local seen = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(win)
    if not seen[b] and vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" and not vim.bo[b].modified then
      seen[b] = true
      local name = filename(b)
      if name and M.context(b) and uv.fs_stat(name) then vim.api.nvim_buf_call(b, function() vim.cmd("silent! checktime") end) end
    end
  end
end
function M.tick()
  if stopped then return end
  ticks = (ticks or 0) + 1; M.check_buffers()
  if ticks % 2 ~= 0 then return end
  local lib = package.loaded["diffview.lib"]; local view = lib and lib.get_current_view()
  if view and view.update_files then view:update_files() end
  local current = M.context(0)
  for _, ctx in pairs(M.contexts) do
    if (not ctx.dormant or ctx == current or ctx.waiting_clean) and not ctx.job and not ctx.queued then
      if ctx.waiting then
        local data = read_json(ctx.state .. "/state.json")
        local running = data and data.status == "preparing" and type(data.pid) == "number" and uv.kill(data.pid, 0) == 0
        if not running then
          local fresh = data and (data.status == "ready" or data.status == "failed")
            and state_version(ctx) ~= ctx.waiting_version
          local clean = ctx.waiting_clean
          ctx.waiting, ctx.waiting_clean, ctx.waiting_version = false, nil, nil
          if fresh and not clean then
            update(ctx, data)
            attach_waiters(ctx)
            changed()
          else
            enqueue(ctx, clean)
          end
        end
      elseif ctx.attempted and signature(ctx) ~= ctx.attempted then
        enqueue(ctx, false)
      end
    end
  end
end
function M.stop()
  stopped = true; queue = {}
  local spring = package.loaded["user.spring_tools"]
  if spring then spring.stop_all() end
  if timer then timer:stop(); timer:close(); timer = nil end
  if active and active.job then active.job:kill(15); active.job:wait(5000) end
  for _, job in pairs(inspection_jobs) do job:kill(15); job:wait(1000) end
end
function M.setup()
  if timer then return end
  stopped, ticks = false, 0
  local group = vim.api.nvim_create_augroup("LatheLiveSource", { clear = true })
  vim.api.nvim_create_autocmd("VimEnter", { group = group, once = true, callback = function()
    vim.schedule(function()
      local first = vim.fn.argv(0)
      if first ~= "" then
        local path = canonical(vim.fn.fnamemodify(first, ":p"))
        ensure_path(uv.fs_stat(path) and uv.fs_stat(path).type == "directory" and (path .. "/pom.xml") or path, nil, nil)
      else M.ensure_directory(vim.fn.getcwd()) end
    end)
  end })
  vim.api.nvim_create_autocmd("DirChanged", { group = group, callback = function() M.ensure_directory(vim.fn.getcwd()) end })
  vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, { group = group, callback = function(ev)
    local spring = package.loaded["user.spring_tools"]
    if spring then spring.close_document(ev.buf) end
    vim.schedule(function()
      if stopped then return end
      for _, ctx in pairs(M.contexts) do
        local live = false
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "java" and M.context(b) == ctx then live = true; break end
        end
        ctx.dormant = not live
        if not live then
          for _, c in ipairs(vim.lsp.get_clients({ name = "lathe" })) do if c.config.root_dir == ctx.analysis then c:stop() end end
          if spring then spring.stop(ctx) end
        end
      end
    end)
  end })
  vim.api.nvim_create_autocmd("FileChangedShell", { group = group, callback = function(ev)
    if M.context(ev.buf) then
      vim.v.fcs_choice = (not vim.bo[ev.buf].modified and uv.fs_stat(vim.api.nvim_buf_get_name(ev.buf))) and "reload" or ""
    end
  end })
  vim.api.nvim_create_autocmd("FocusGained", { group = group, callback = M.check_buffers })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.stop })
  timer = assert(uv.new_timer()); timer:start(1000, 1000, vim.schedule_wrap(M.tick))
end
return M
