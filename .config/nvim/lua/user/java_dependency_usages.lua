local M = {}
local dependency = require("user.java_dependency_navigation")
local pending, sequence = {}, 0

vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout" }, {
  group = vim.api.nvim_create_augroup("UserDependencyFieldUsages", { clear = true }),
  callback = function(ev)
    if pending[ev.buf] then pending[ev.buf]() end
  end,
})

local function field_under_cursor(buf, path)
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf })
  if not ok or not node then return end
  local declarator = node:parent()
  if not declarator or declarator:type() ~= "variable_declarator" then return end
  local field = declarator:parent()
  local name = declarator:field("name")[1]
  if not name or not name:equal(node) or not field or field:type() ~= "field_declaration" then return end
  local owner = field:parent():parent()
  local names = {}
  while owner and (owner:type() == "class_declaration" or owner:type() == "enum_declaration") do
    local id = owner:field("name")[1]
    if not id then return end
    table.insert(names, 1, vim.treesitter.get_node_text(id, buf))
    owner = owner:parent()
    if owner and owner:type() == "class_body" then owner = owner:parent() end
  end
  local pkg, file = path:match("^(.*)/([^/]+)%.java$")
  if file ~= names[1] or not owner or owner:type() ~= "program" then return end
  return pkg:gsub("/", ".") .. "." .. table.concat(names, "$"), vim.treesitter.get_node_text(name, buf)
end

local function source_sets(ctx, group, artifact, version)
  local roots, jars, included = {}, {}, {}
  local suffix = "/" .. group:gsub("%.", "/") .. "/" .. artifact .. "/" .. version
  local patterns = { "lsp-params-*.json", "*/lsp-params-*.json" }
  for _, pattern in ipairs(patterns) do
    for _, path in ipairs(vim.fn.globpath(ctx.analysis .. "/.lathe", pattern, false, true)) do
      local ok, model = pcall(function()
        return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
      end)
      if ok and type(model.sourceRoots) == "table" then
        local matched = false
        for _, entries in ipairs({ model.classpath or {}, model.modulepath or {} }) do
          for _, entry in ipairs(entries) do
            if vim.endswith(entry, ".jar") and vim.endswith(vim.fs.dirname(entry), suffix)
                and vim.uv.fs_stat(entry) then
              jars[vim.uv.fs_realpath(entry) or entry] = true
              matched = true
            end
          end
        end
        if matched then
          local probe_root
          for _, root in ipairs(model.sourceRoots) do
            if vim.startswith(root, ctx.source .. "/") and vim.fn.isdirectory(root) == 1 then
              included[root] = true
              probe_root = probe_root or root
            end
          end
          if probe_root then roots[probe_root] = true end
          if type(model.generatedSourcesDir) == "string" then included[model.generatedSourcesDir] = true end
          for _, kind in ipairs({ "generated-sources", "generated-test-sources" }) do
            included[vim.fs.dirname(path) .. "/" .. kind] = true
          end
        end
      end
    end
  end
  return vim.tbl_keys(roots), vim.tbl_keys(jars), included
end

local function operations(lines, field)
  local calls = {}
  for row, line in ipairs(lines) do
    local method, params = line:match("^  public .- ([%w_$]+)%(([^()]*)%).*;$")
    if method then
      params = vim.trim(params:gsub("%b<>", ""))
      local param_type = params:match("^([%w_$.]+[%[%]]*)$")
      local arity = params == "" and 0 or (param_type and 1)
      if arity and dependency.accessor_field(lines, row, method, arity) == field then
        local arg = ""
        if param_type then
          local bare = param_type:gsub("%$", ".")
          local primitive = ({ byte = true, short = true, int = true, long = true, float = true,
            double = true, char = true })[bare]
          arg = "(" .. bare .. ") " .. (bare == "boolean" and "false" or (primitive and "0" or "null"))
        end
        calls[#calls + 1] = "value." .. method .. "(" .. arg .. ");"
      end
    elseif line:match("^  public ") and not line:match("^  public .*%f[%w]static%f[%W]")
        and line:match(" " .. vim.pesc(field) .. ";$") then
      calls[#calls + 1] = "Object ignored = value." .. field .. ";"
    end
  end
  return calls
end

local function find_usages(buf, client, ctx, class, field, group, artifact, version)
  if pending[buf] then pending[buf]() end
  local win, cursor = vim.api.nvim_get_current_win(), vim.api.nvim_win_get_cursor(0)
  local roots, jars, included = source_sets(ctx, group, artifact, version)
  if #roots == 0 or #jars ~= 1 then
    vim.notify("Lathe: 未能从当前工程模型确认该字段的依赖版本", vim.log.levels.WARN)
    return
  end

  local job, timer, remaining, resolved, partial = nil, nil, 0, 0, false
  local requests, probes, locations, seen = {}, {}, {}, {}
  local active = true
  local function close(uri)
    client:notify("textDocument/didClose", { textDocument = { uri = uri } })
    probes[uri] = nil
  end
  local function cleanup()
    active, pending[buf] = false, nil
    if timer then timer:stop(); timer:close(); timer = nil end
    if job then pcall(job.kill, job, 15) end
    for id in pairs(requests) do client:cancel_request(id) end
    for uri in pairs(probes) do close(uri) end
  end
  pending[buf] = cleanup

  local function finish(message)
    cleanup()
    if vim.api.nvim_get_current_win() ~= win or vim.api.nvim_get_current_buf() ~= buf
        or not vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor) then return end
    local items = {}
    for _, loc in ipairs(vim.lsp.util.locations_to_items(locations, client.offset_encoding)) do
      items[#items + 1] = {
        file = loc.filename, pos = { loc.lnum, loc.col - 1 },
        text = ("%s:%d  %s"):format(vim.fs.basename(loc.filename), loc.lnum, loc.text or ""),
      }
    end
    if #items > 0 then
      local title = "Find Usages — " .. class:match("[^%.]+$") .. "." .. field
      require("user.navigation").items(partial and title .. " · 部分结果" or title, items)
    else
      vim.notify("Lathe: " .. (message or (resolved == 0 and "未能确认此依赖字段或访问器"
        or "当前索引未返回该字段及访问器的项目引用")), vim.log.levels.WARN)
    end
  end
  vim.api.nvim_echo({ { "  Lathe 正在查询依赖字段及访问器…", "Comment" } }, false, {})
  timer = vim.defer_fn(function()
    partial = true
    finish("依赖字段引用查询超时，可稍后重试")
  end, 45000)

  local function request(method, params, callback)
    local sent, id
    sent, id = client:request("textDocument/" .. method, params, function(err, result)
      if not active then return end
      if id then requests[id] = nil end
      callback(err, result)
    end, buf)
    if sent then requests[id] = true else callback(true) end
  end
  local function collect(result)
    for _, loc in ipairs(result) do
      if type(loc.uri) == "string" and vim.startswith(loc.uri, "file:") and loc.range then
        local path = vim.uri_to_fname(loc.uri)
        local pos = loc.range.start
        local key = ("%s:%d:%d"):format(loc.uri, pos.line, pos.character)
        if not seen[key] and not vim.fs.basename(path):match("^__LatheFieldRefs_%d+_%d+%.java$")
            and vim.iter(included):any(function(root)
          return vim.startswith(path, root .. "/")
        end) then
          seen[key] = true
          locations[#locations + 1] = loc
        end
      end
    end
  end
  -- Lathe searches from the requesting source set. An unsaved synthetic
  -- document gives each eligible module a typed reference to the same JAR.
  local function probe(root, calls)
    local name, path
    repeat
      sequence = sequence + 1
      name = ("__LatheFieldRefs_%d_%d"):format(vim.uv.os_getpid(), sequence)
      path = root .. "/" .. name .. ".java"
    until not vim.uv.fs_stat(path)
    local uri = vim.uri_from_fname(path)
    local lines = { "class " .. name .. " {", "void probe(" .. class:gsub("%$", ".") .. " value) {" }
    vim.list_extend(lines, calls)
    vim.list_extend(lines, { "}", "}" })
    local left = #calls
    local function done()
      left, remaining = left - 1, remaining - 1
      if left == 0 and probes[uri] then close(uri) end
      if remaining == 0 then finish(partial and "未完成全部模块的引用查询" or nil) end
    end
    if not client:notify("textDocument/didOpen", { textDocument = {
      uri = uri, languageId = "java", version = 1, text = table.concat(lines, "\n"),
    } }) then
      partial = true
      for _ in ipairs(calls) do done() end
      return
    end
    probes[uri] = true
    for index, call in ipairs(calls) do
      local params = { textDocument = { uri = uri }, position = { line = index + 1,
        character = call:find("value.", 1, true) + #"value." - 1 } }
      request("hover", params, function(err, hover)
        local g, a, v = dependency.hover_artifact(hover)
        if err or g ~= group or a ~= artifact or v ~= version then
          partial = true
          done()
          return
        end
        resolved = resolved + 1
        params.context = { includeDeclaration = false }
        request("references", params, function(ref_error, result)
          if ref_error then partial = true
          elseif type(result) == "table" then collect(result) end
          done()
        end)
      end)
    end
  end
  local javap = require("user.lathe_config").runtime_jdk .. "/bin/javap"
  job = vim.system({ javap, "-p", "-c", "-classpath", jars[1], class }, { text = true, timeout = 5000 },
    vim.schedule_wrap(function(output)
      job = nil
      if not active then return end
      if output.code ~= 0 then finish("无法读取依赖 class 的字段"); return end
      local calls = operations(vim.split(output.stdout or "", "\n", { plain = true }), field)
      if #calls == 0 then finish("该字段没有可确认的公开访问器"); return end
      remaining = #roots * #calls
      for _, root in ipairs(roots) do probe(root, calls) end
    end))
end

function M.at_field()
  local buf = vim.api.nvim_get_current_buf()
  local state = require("user.lathe_config").state_root
  local filename = vim.api.nvim_buf_get_name(buf)
  local group, artifact, version, file =
    filename:match("^" .. vim.pesc(state) .. "/projects/%x+/cache/deps/([^/]+)/([^/]+)/([^/]+)/(.+)$")
  if not file then return false end
  local class, field = field_under_cursor(buf, file)
  if not field then return false end
  local live = require("user.lathe_live")
  local ctx = live.context(buf)
  if not ctx then
    live.ensure(buf)
    vim.notify("Lathe: 正在恢复依赖来源工程，连接后可重试", vim.log.levels.INFO)
    return true
  end
  local client = vim.lsp.get_clients({ bufnr = buf, name = "lathe", method = "textDocument/references" })[1]
  if not client then
    live.ensure(buf)
    vim.notify("Lathe: 正在连接依赖来源工程，连接后可重试", vim.log.levels.INFO)
    return true
  end
  find_usages(buf, client, ctx, class, field, group, artifact, version)
  return true
end

return M
