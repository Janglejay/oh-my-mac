local M = {}
local instances, models = {}, {}
local version = "2.4.1"
local sandbox = "/usr/bin/sandbox-exec"

local function read(path)
  local ok, value = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(path), "\n")) end)
  return ok and value or nil
end

local function within(path, root)
  return path == root or vim.startswith(path, root .. "/")
end

-- The capture is the only source of module/source-set membership and classpaths.
function M.model(ctx)
  local root = ctx.analysis .. "/.lathe"
  local stamp = vim.uv.fs_stat(root .. "/workspace.json")
  if not stamp then return nil, "The Lathe project model is not ready" end
  local previous = models[ctx.analysis]
  local marker = ("%d:%d:%d:%d"):format(stamp.ino, stamp.size, stamp.mtime.sec, stamp.mtime.nsec)
  if previous and previous.marker == marker then return previous end
  local w = read(root .. "/workspace.json")
  if not w then return nil, "Could not read the Lathe project model" end
  local model = { marker = marker, modules = {}, java_roots = {}, resource_roots = {} }
  local jdk = w.jdk or {}
  local java = jdk.home or ""
  local system = {}
  for _, relative in ipairs({ "/jre/lib/rt.jar", "/lib/rt.jar", "/lib/jrt-fs.jar" }) do
    local path = java .. relative
    if java ~= "" and vim.uv.fs_stat(path) then system[#system + 1] = path end
  end
  if #system == 0 then return nil, "No supported system libraries found in the project JDK" end

  local outputs = {}
  for _, entry in ipairs(w.outputs or {}) do
    if type(entry.path) == "string" and type(entry.module) == "string" then
      outputs[entry.path] = entry.module
      local path = vim.uv.fs_realpath(entry.path)
      if path then outputs[path] = entry.module end
    end
  end
  local classpaths = vim.fn.globpath(root, "**/lsp-params-*.json", false, true)
  for _, file in ipairs(classpaths) do
    local p = read(file)
    if p and type(p.sourceRoots) == "table" and type(p.outputDir) == "string" then
      local dir = vim.fs.dirname(file)
      local key = dir == root and "." or dir:sub(#root + 2)
      local module = model.modules[key] or { root = vim.fs.normalize(ctx.source .. "/" .. key),
        name = key, entries = {}, roots = {}, upstream = {}, seen = {} }
      model.modules[key] = module
      local test = p.sourceTree == "test-classes"
      if not test then module.parameter_names = p.parameters == true end
      local function add(entry)
        local identity = entry.kind .. ":" .. entry.path
        if not module.seen[identity] and vim.uv.fs_stat(entry.path) then
          module.seen[identity] = true
          module.entries[#module.entries + 1] = entry
        end
      end
      local function source(path, java_source, output)
        add({ kind = "source", path = path, outputFolder = output, isOwn = true,
          isTest = test, isJavaContent = java_source })
        if vim.uv.fs_stat(path) and within(path, ctx.source) then
          module.roots[path] = test and "test" or "main"
          local roots = java_source and model.java_roots or model.resource_roots
          roots[path] = true
        end
      end
      for _, path in ipairs(p.sourceRoots) do source(path, true, p.outputDir) end
      if p.generatedSourcesDir then source(p.generatedSourcesDir, true, p.outputDir) end
      for _, list in ipairs({ p.classpath or {}, p.modulepath or {} }) do
        for _, path in ipairs(list) do
          local owner = outputs[path]
          if not owner then owner = outputs[vim.uv.fs_realpath(path) or path] end
          if owner and owner ~= key then module.upstream[owner] = true end
          add({ kind = "binary", path = path, isTest = test })
        end
      end
      for _, path in ipairs(system) do add({ kind = "binary", path = path, isSystem = true }) end
      for _, entry in ipairs(w.resourceRoots or {}) do
        if entry.module == key and type(entry.directory) == "string" and type(entry.outputDir) == "string"
            and ((entry.outputDir:match("/test%-classes$") ~= nil) == test) then
          source(entry.directory, false, entry.outputDir)
        end
      end
    end
  end
  for key, module in pairs(model.modules) do
    if not next(module.roots) then model.modules[key] = nil
    else
      local uri = vim.uri_from_fname(module.root)
      module.project = key == "." and vim.fs.basename(module.root) or key
      module.event = { uri, module.project, false,
        { entries = module.entries, jre = { version = jdk.version or "", installationPath = java } },
        vim.NIL, vim.empty_dict() }
    end
  end
  if not next(model.modules) then return nil, "No source modules found in the Lathe project model" end
  models[ctx.analysis] = model
  return model
end

function M.module(model, file)
  local selected, length, scope
  for _, module in pairs(model.modules) do
    for path, kind in pairs(module.roots) do
      if within(file, path) and (not length or #path > length) then selected, length, scope = module, #path, kind end
    end
  end
  return selected, scope
end

local function finish(state, err)
  local pending = state.pending
  state.pending = {}
  for _, callback in ipairs(pending) do callback(err, not err and state or nil) end
end

local function synchronize(state)
  if not state.initialized or not state.listener or state.syncing then return end
  if state.classpath_sent then finish(state); return end
  local events = {}
  for _, module in pairs(state.model.modules) do events[#events + 1] = module.event end
  state.syncing = true
  local sent = state.rpc.request("workspace/executeCommand", { command = state.listener, arguments = events },
    vim.schedule_wrap(function(failure)
      state.syncing = false
      if failure then finish(state, failure.message or "Spring Tools rejected the Lathe classpath"); return end
      state.classpath_sent = true
      finish(state)
    end))
  if not sent then
    state.syncing = false
    finish(state, "Could not send the Lathe classpath")
  end
end

local function launch(ctx, model)
  local dir = vim.fn.stdpath("data") .. "/spring-tools/" .. version
  local jars = vim.fn.globpath(dir, "*-exec.jar", false, true)
  if #jars ~= 1 then return nil, "Spring Boot Tools " .. version .. " language server is not installed locally" end
  if vim.fn.executable(sandbox) ~= 1 then return nil, "Spring Tools requires macOS network sandboxing" end
  local java = require("user.lathe_config").runtime_jdk .. "/bin/java"
  local home = ctx.state .. "/spring-tools"
  vim.fn.mkdir(home, "p", 448)
  local state = { model = model, pending = {}, documents = {} }
  local rpc = vim.lsp.rpc.start({
    sandbox, "-p", "(version 1)(allow default)(deny network*)", java,
    "-Xmx1g", "-Duser.home=" .. home, "-Dsts.lsp.client=vscode", "-Dspring.main.web-application-type=none",
    "-Dspring.profiles.active=file-logging", "-Dlogging.file.name=" .. home .. "/server.log",
    "-jar", jars[1],
  }, {
    server_request = function(method, params)
      if method == "sts/addClasspathListener" then
        state.listener = params.callbackCommandId
        vim.schedule(function() synchronize(state) end)
      elseif method == "workspace/configuration" then
        return vim.tbl_map(function() return vim.NIL end, params.items or {})
      elseif method == "workspace/workspaceFolders" then
        return { { uri = vim.uri_from_fname(ctx.source), name = vim.fs.basename(ctx.source) } }
      end
      return vim.NIL
    end,
    on_exit = vim.schedule_wrap(function()
      if instances[ctx.analysis] == state then instances[ctx.analysis] = nil end
      finish(state, "Spring Tools exited. See " .. home .. "/server.log")
    end),
  }, { cwd = ctx.source })
  if not rpc then return nil, "Could not start Spring Tools" end
  state.rpc = rpc
  instances[ctx.analysis] = state
  local uri = vim.uri_from_fname(ctx.source)
  rpc.request("initialize", {
    processId = vim.uv.os_getpid(), rootUri = uri,
    workspaceFolders = { { uri = uri, name = vim.fs.basename(ctx.source) } },
    capabilities = { textDocument = vim.empty_dict(), workspace = { executeCommand = { dynamicRegistration = false } } },
  }, vim.schedule_wrap(function(err)
    if err then finish(state, err.message); M.stop(ctx); return end
    state.initialized = true
    rpc.notify("initialized", vim.empty_dict())
    synchronize(state)
  end))
  return state
end

function M.ready(ctx, callback)
  local state = instances[ctx.analysis]
  local model, err = M.model(ctx)
  if not model then callback(err); return end
  if state and state.model ~= model then
    -- The library paths can stay the same while their compiled contents change.
    M.stop(ctx)
    state = nil
  end
  if not state or state.rpc.is_closing() then state, err = launch(ctx, model) end
  if not state then callback(err); return end
  state.pending[#state.pending + 1] = callback
  synchronize(state)
end

function M.document(state, buf)
  local uri = vim.uri_from_bufnr(buf)
  local version_now = vim.api.nvim_buf_get_changedtick(buf)
  local existing = state.documents[uri]
  if existing == version_now then return end
  local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  if not existing then
    state.rpc.notify("textDocument/didOpen", { textDocument = {
      uri = uri, version = version_now, languageId = vim.bo[buf].filetype, text = content,
    } })
  else
    state.rpc.notify("textDocument/didChange", { textDocument = { uri = uri, version = version_now },
      contentChanges = { { text = content } } })
  end
  state.documents[uri] = version_now
end

function M.close_document(buf)
  local uri = vim.uri_from_bufnr(buf)
  for _, state in pairs(instances) do
    if state.documents[uri] then
      state.documents[uri] = nil
      state.rpc.notify("textDocument/didClose", { textDocument = { uri = uri } })
    end
  end
end

function M.saved(buf)
  local uri, path = vim.uri_from_bufnr(buf), vim.api.nvim_buf_get_name(buf)
  for _, state in pairs(instances) do
    if state.model and M.module(state.model, path) and not state.rpc.is_closing() then
      if state.documents[uri] then
        M.document(state, buf)
        state.rpc.notify("textDocument/didSave", { textDocument = { uri = uri } })
      end
      state.rpc.notify("workspace/didChangeWatchedFiles", { changes = { { uri = uri, type = 2 } } })
    end
  end
end

function M.stop(ctx)
  local state = instances[ctx.analysis]
  instances[ctx.analysis] = nil
  if not state or state.rpc.is_closing() then return end
  state.rpc.request("shutdown", nil, vim.schedule_wrap(function()
    state.rpc.notify("exit")
  end))
  vim.defer_fn(function() if not state.rpc.is_closing() then state.rpc.terminate() end end, 2000)
end

function M.stop_all()
  for _, state in pairs(instances) do
    if not state.rpc.is_closing() then state.rpc.terminate() end
  end
  instances, models = {}, {}
end

return M
