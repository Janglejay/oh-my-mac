-- Run with Neovim's normal configuration: nvim --headless -i NONE -n '+luafile scripts/test-java-navigation.lua'
local root = vim.fn.tempname()
local cwd = vim.fn.getcwd()
vim.fn.mkdir(root, "p")

local ok, err = xpcall(function()
  local origin = root .. "/Example.java"
  local other = root .. "/Other.java"
  local line = "class Example { /* 中文 */ int size() { return 1; } int invoke() { return size(); } }"
  local declaration = assert(line:find("size", 1, true)) - 1
  local call = assert(line:find("size", declaration + 5, true)) - 1
  vim.fn.writefile({ line }, origin)
  vim.fn.writefile({ "class Other { int size() { return 2; } }" }, other)
  vim.fn.writefile({ "class PrivateMethod { private java.util.Map<String, Integer> lookup() { return null; } }" },
    root .. "/PrivateMethod.java")
  vim.fn.mkdir(root .. "/src/test/java", "p")
  vim.fn.writefile({ "class TestMethod { private void lookup() {} }" }, root .. "/src/test/java/TestMethod.java")
  vim.cmd.cd(root)
  vim.cmd.edit(origin)
  local buf = vim.api.nvim_get_current_buf()
  origin = vim.api.nvim_buf_get_name(buf)

  local search = assert(vim.fn.maparg(",f", "n", false, true).callback())
  assert(vim.wait(1000, function() return search.input.win.buf ~= nil end, 10), "Search did not open")
  assert(search.input:get() == "scope:!test ", "Type a query directly after the scope prefix")
  local function search_count(pattern)
    search.input:set(pattern, "")
    search:find({ refresh = false })
    assert(vim.wait(1000, function()
      return not search.finder:running() and not search.matcher.task:running()
    end, 10), "Java symbol search timed out")
    return search.list:count()
  end
  assert(search_count("scope:!test lookup") == 1, "Search must find the private method in main sources")
  assert(search_count("lookup") == 2, "Removing the scope must include test methods")
  search:close()
  assert(vim.wait(1000, function() return vim.api.nvim_get_current_buf() == buf end, 10))

  local client = { id = 1, offset_encoding = "utf-16", server_capabilities = {} }
  local results, requests, usages, candidates = {}, 0, 0, nil
  vim.lsp.get_clients = function() return { client } end
  vim.lsp.get_client_by_id = function() return client end
  vim.lsp.buf_request_all = function(_, method, _, callback)
    assert(method == "textDocument/definition")
    requests = requests + 1
    vim.schedule(function() callback({ [client.id] = { result = results } }) end)
    return function() end
  end
  local navigation = require("user.navigation")
  navigation.references = function() usages = usages + 1 end
  local picker = Snacks.picker
  Snacks.picker = setmetatable({
    lsp_definitions = function(opts) candidates = opts.finder() end,
  }, { __index = picker })
  require("user.lsp.handlers").on_attach(client, buf)

  local function location(path, text, byte)
    local pos = { line = 0, character = vim.str_utfindex(text, client.offset_encoding, byte) }
    return { uri = vim.uri_from_fname(path), range = { start = pos, ["end"] = pos } }
  end
  local target = location(origin, line, declaration)
  local function gd(col)
    vim.api.nvim_win_set_cursor(0, { 1, col })
    vim.fn.maparg("gd", "n", false, true).callback()
  end
  results = { target }
  gd(call)
  assert(vim.wait(1000, function()
    return vim.api.nvim_win_get_cursor(0)[2] == declaration
  end, 10), "gd must jump from a call to a declaration on the same line")
  assert(usages == 0)
  gd(declaration + 2)
  assert(vim.wait(1000, function() return usages == 1 end, 10), "gd on the declaration must find usages")

  local line_other = vim.fn.readfile(other)[1]
  results = { target, location(other, line_other, assert(line_other:find("size", 1, true)) - 1) }
  gd(call + 1)
  gd(call + 1)
  assert(vim.wait(1000, function() return candidates ~= nil end, 10), "gd must show both definitions")
  assert(#candidates == 2, "The picker dropped a valid same-line definition")
  assert(requests == 3, "The picker or a repeated key ran an extra request")

  print("Java navigation: private methods, search scope, same-line definition, usages, multiple targets, UTF-16 and request deduplication passed")
end, debug.traceback)
vim.cmd.cd(cwd)
vim.fn.delete(root, "rf")
if not ok then print(err); vim.cmd.cquit(1) else vim.cmd("qa!") end
