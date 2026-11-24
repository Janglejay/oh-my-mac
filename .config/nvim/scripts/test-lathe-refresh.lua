-- Run with the normal config: nvim --headless -i NONE -n '+luafile scripts/test-lathe-refresh.lua'
vim.schedule(function()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  root = assert(vim.uv.fs_realpath(root))
  local state, analysis = root .. "/state", root .. "/analysis"
  local pom = root .. "/pom.xml"
  local dependency = root .. "/dependency.pom"
  local function write(path, data)
    vim.fn.writefile({ vim.json.encode(data) }, path)
  end

  local live = require("user.lathe_live")
  local system = vim.system
  local ok, err = xpcall(function()
    vim.fn.mkdir(state, "p")
    vim.fn.mkdir(analysis .. "/.lathe", "p")
    write(analysis .. "/.lathe/workspace.json", {})
    vim.fn.writefile({ "<project/>" }, pom)
    live.stop()
    live.setup()
    local requests = {}
    vim.system = function(cmd, opts, callback)
      if not (cmd[2] and vim.endswith(cmd[2], "/lathe-model.py")) then return system(cmd, opts, callback) end
      requests[#requests + 1] = { action = cmd[3], clean = vim.tbl_contains(cmd, "--clean"), callback = callback }
      return { kill = function() end, wait = function() return {} end }
    end
    local function press(key)
      vim.fn.maparg(key, "n", false, true).callback()
    end
    local function take(action, clean)
      assert(vim.wait(1000, function() return #requests > 0 end, 5), "Missing request: " .. action)
      local request = table.remove(requests, 1)
      assert(request.action == action and request.clean == clean, vim.inspect(request))
      return function(code, data)
        request.callback({ code = code, stdout = vim.json.encode(data), stderr = "" })
      end
    end
    local function tick()
      live.tick()
      live.tick()
    end
    local ready = { status = "ready", watch = { dependency }, watch_values = { dependency .. ":missing" } }
    local failed = { status = "failed", missing_dependency = "example:dependency:1", watch = ready.watch,
      watch_values = ready.watch_values }
    local inspect = vim.tbl_extend("force", ready, {
      id = "fixture", source = root, state = state, analysis = analysis, cache = root .. "/cache",
    })
    write(state .. "/state.json", ready)
    vim.cmd.edit(pom)
    local attached = false
    live.ensure(0, function() attached = true end)
    press(",lR")
    take("inspect", false)(0, inspect)
    take("prepare", true)(0, ready)
    local ctx = live.context(0)
    assert(vim.wait(1000, function() return ctx.status == "ready" end, 5))
    assert(attached, "The manual rebuild must not replace a pending attachment callback")
    assert(live.status() == "ready", "A published model is ready even before a Java client attaches")
    ctx.partial_model = true
    assert(live.status() == "warning", "A partial model should be a warning")
    ctx.partial_model = false
    ctx.navigation_only = true
    assert(live.status() == "warning", "Compilation errors with a usable index should be a warning")
    ctx.navigation_only = false

    -- A clean request during an incremental job runs afterward.
    press(",lr")
    local incremental = take("prepare", false)
    assert(live.status() == "busy")
    press(",lR")
    incremental(0, ready)
    local clean = take("prepare", true)

    -- A stale state from another process must not absorb the clean request.
    clean(75, { status = "busy" })
    assert(vim.wait(1000, function() return ctx.waiting end, 5))
    tick()
    take("prepare", true)(1, failed)
    assert(vim.wait(1000, function() return ctx.status == "failed" end, 5))
    local level, label = live.status()
    assert(level == "error" and label:find("using previous model", 1, true)
      and label:find("example:dependency:1", 1, true))
    assert(live.root(0) == analysis, "The failed refresh must keep the last usable model")
    tick()
    assert(#requests == 0, "An unchanged missing dependency must not cause a retry loop")

    -- A missing POM arriving in the cache triggers one retry even in a POM-only editor.
    ctx.dormant = true
    vim.fn.writefile({ "<project/>" }, dependency)
    tick()
    local stat = assert(vim.uv.fs_stat(dependency))
    ready.watch_values = { ("%s:%d:%d:%d"):format(dependency, stat.size, stat.mtime.sec, stat.mtime.nsec) }
    take("prepare", false)(0, ready)
    assert(vim.wait(1000, function() return ctx.status == "ready" end, 5))
    assert(not ctx.missing_dependency)
    tick()
    assert(#requests == 0)

    -- Another editor's completed incremental run can satisfy this request.
    press(",lr")
    take("prepare", false)(75, { status = "busy" })
    assert(vim.wait(1000, function() return ctx.waiting end, 5))
    write(state .. "/state.json", ready)
    tick()
    assert(ctx.status == "ready" and #requests == 0)
    print("Lathe refresh: POM routing, queued clean, busy retry and reuse, last model and dependency recovery passed")
  end, debug.traceback)
  live.stop()
  vim.system = system
  vim.fn.delete(root, "rf")
  if not ok then print(err); vim.cmd.cquit(1) else vim.cmd("qa!") end
end)
