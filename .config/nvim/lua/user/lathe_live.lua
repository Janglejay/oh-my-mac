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
  for _, key in ipairs({ "watch", "watch_values", "status", "error", "log" }) do
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
  local data = result.stdout and vim.json.decode(result.stdout, { luanil = { object = true, array = true } }) or nil
  update(ctx, data)
  ctx.ready = model_exists(ctx)
  if result.code == 75 then
    ctx.status, ctx.waiting = "waiting", true
  elseif result.code == 0 then
    ctx.status, ctx.waiting, ctx.error = "ready", false, nil
    attach_waiters(ctx)
  else
    ctx.status, ctx.waiting = "failed", false
    ctx.error = (data and data.error) or result.stderr or "Preparation failed"
    if not ctx.attempted then ctx.attempted = signature(ctx) end
    M.last_failure = ctx
    -- Keep failures non-blocking; full output is available on explicit request.
    vim.api.nvim_echo({ { "Lathe 准备失败；,lr 重试，:LatheLog 查看日志", "WarningMsg" } }, true, {})
  end
  changed()
end
local function pump()
  if stopped or active or #queue == 0 then return end
  local ctx = table.remove(queue, 1)
  ctx.queued, ctx.status = false, "preparing"
  ctx.attempted = signature(ctx)
  active = ctx
  local cmd = command("prepare", { "--root", ctx.source })
  if ctx.clean then cmd[#cmd + 1] = "--clean" end
  ctx.clean = nil
  ctx.job = vim.system(cmd, { text = true }, vim.schedule_wrap(function(result)
    ctx.job, active = nil, nil
    if stopped then return end
    local ok, err = pcall(finish, ctx, result)
    if not ok then ctx.status, ctx.error = "failed", tostring(err); changed() end
    pump()
  end))
  changed()
end
local function enqueue(ctx, clean)
  if stopped or ctx.job or ctx.queued then return end
  ctx.clean, ctx.queued, ctx.status = clean, true, "queued"
  queue[#queue + 1] = ctx
  pump()
end

local function ensure_path(name, buf, callback)
  if stopped then return end
  if not name then return end
  if inside(name, options.state_root) then
    -- Generated and extracted sources belong to the client that produced them.
    -- Reuse that model without discovering or building a second project.
    local ctx = buf and M.context(buf)
    if ctx and ctx.ready then
      ctx.dormant = false
      if callback then callback(ctx) else M.attach(buf) end
      return
    end
    local key = name:match("^" .. vim.pesc(options.state_root) .. "/projects/(%x+)/cache/deps/")
    if key then
      local state = options.state_root .. "/projects/" .. key
      local identity = read_json(state .. "/identity.json")
      if identity and identity.id == key and identity.cache == state .. "/cache"
          and type(identity.source) == "string" and not inside(canonical(identity.source), options.state_root)
          and uv.fs_stat(identity.source .. "/pom.xml") then
        ensure_path(canonical(identity.source .. "/pom.xml"), buf, callback)
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
    if ctx.ready then if callback then callback(ctx) end; return end
    ctx.waiters = ctx.waiters or {}
    if buf then
      ctx.waiters[buf] = ctx.waiters[buf] or {}
      if callback then ctx.waiters[buf][#ctx.waiters[buf] + 1] = callback end
    end
    if ctx.status ~= "failed" and not ctx.waiting then enqueue(ctx, false) end
    return
  end
  if inspecting[root] then if buf then inspecting[root][buf] = callback or false end; return end
  inspecting[root] = buf and { [buf] = callback or false } or {}
  inspection_jobs[root] = vim.system(command("inspect", { "--file", name }), { text = true }, vim.schedule_wrap(function(result)
    inspection_jobs[root] = nil
    local waiters = inspecting[root]; inspecting[root] = nil
    if stopped then return end
    local ok, data = pcall(vim.json.decode, result.stdout or "")
    if not ok or result.code ~= 0 or not data.id then
      vim.notify("Lathe: Maven 工程识别失败：" .. (ok and data.error or result.stderr or "unknown error"), vim.log.levels.WARN)
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
    for b, cb in pairs(waiters or {}) do
      ctx.waiters[b] = ctx.waiters[b] or {}
      if cb then ctx.waiters[b][#ctx.waiters[b] + 1] = cb end
    end
    if ctx.ready then attach_waiters(ctx) end
    if not ctx.ready or data.needs_analysis_refresh then enqueue(ctx, false) end
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
  if not ctx and filename(buf) and vim.bo[buf].filetype == "java" then M.ensure(buf); return end
  ctx = ctx or last_context
  if not ctx then M.ensure(buf or 0); return end
  ctx.waiting = false
  enqueue(ctx, clean)
end
function M.model_changed(client_id)
  local ctx = M.from_client(client_id)
  if ctx and signature(ctx) ~= ctx.attempted then enqueue(ctx, false) end
end
function M.log()
  local current = M.context(0)
  local ctx = (current and current.status == "failed" and current) or M.last_failure or current or last_context
  if not ctx then return end
  vim.cmd("botright split " .. vim.fn.fnameescape(ctx.state .. "/logs/capture.log"))
  vim.bo.readonly = true
end
function M.status()
  local ctx = M.context(0) or last_context
  if not ctx then return "none", "Lathe · 打开 Maven Java 文件自动准备" end
  local name = vim.fs.basename(ctx.source)
  if ctx.status == "preparing" then return "busy", "Lathe 准备模型 · " .. name end
  if ctx.status == "queued" or ctx.waiting then return "busy", "Lathe 等待准备 · " .. name end
  if ctx.status == "failed" then
    local state = ctx.ready and "更新失败（旧模型）" or "准备失败"
    local subject = ctx.missing_dependency or name
    return "error", "Lathe " .. state .. " · " .. subject .. " · ,lr 重试"
  end
  local cs = vim.lsp.get_clients({ name = "lathe" })
  for _, c in ipairs(cs) do
    if c.config.root_dir == ctx.analysis then return c.initialized and "ready" or "busy", "Lathe · Java 8 · " .. name end
  end
  return "none", "Lathe 模型已准备 · " .. name
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
  for _, ctx in pairs(M.contexts) do
    if not ctx.dormant and not ctx.job and not ctx.queued then
      if ctx.waiting then
        local data = read_json(ctx.state .. "/state.json")
        if data and data.status ~= "preparing" then update(ctx, data); ctx.waiting = false; attach_waiters(ctx) end
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
