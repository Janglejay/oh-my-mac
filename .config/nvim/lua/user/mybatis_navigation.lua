local M = {}
local statements = { select = true, insert = true, update = true, delete = true }

local function parse(source, lang)
  local ok, tree = pcall(function()
    local parser = type(source) == "number" and vim.treesitter.get_parser(source, lang)
      or vim.treesitter.get_string_parser(source, lang)
    return parser:parse()[1]:root()
  end)
  return ok and tree or nil
end

local function text(node, source)
  return vim.treesitter.get_node_text(node, source)
end

local function first(node, kind)
  if node then
    for child in node:iter_children() do
      if child:type() == kind then return child end
    end
  end
end

local function tag(element, source)
  local start = first(element, "STag") or first(element, "EmptyElemTag")
  local name = first(start, "Name")
  return name and text(name, source), start
end

local function attribute(start, key, source)
  for node in start:iter_children() do
    if node:type() == "Attribute" then
      local name, value = first(node, "Name"), first(node, "AttValue")
      if name and value and text(name, source) == key then
        return text(value, source):sub(2, -2), value
      end
    end
  end
end

local function mapper(tree, source)
  local element = tree and tree:field("root")[1]
  local kind, start = tag(element, source)
  if kind ~= "mapper" then return end
  local namespace = attribute(start, "namespace", source)
  if namespace and namespace:match("^[%a_$][%w_$.]*$") and not namespace:find("..", 1, true)
      and not namespace:match("%.$") then return namespace, element end
end

local function java_namespace(tree, interface, source)
  if not interface or interface:type() ~= "interface_declaration" or not interface:parent():equal(tree) then return end
  local name = interface:field("name")[1]
  local package = first(tree, "package_declaration")
  local package_name = first(package, "scoped_identifier") or first(package, "identifier")
  if name then return (package_name and text(package_name, source) .. "." or "") .. text(name, source) end
end

local function java_declaration(tree, source, row, col)
  local node = tree:named_descendant_for_range(row, col, row, col)
  local method = node and node:parent()
  if not method or method:type() ~= "method_declaration" then return end
  local name = method:field("name")[1]
  if not name or not name:equal(node) then return end
  local namespace = java_namespace(tree, method:parent():parent(), source)
  if namespace then return namespace, text(name, source) end
end

local function target(file, node, offset)
  local row, col = node:start()
  return { file = file, pos = { row + 1, col + (offset or 0) }, text = vim.fn.fnamemodify(file, ":~:.") .. ":" .. (row + 1) }
end

local function xml_targets(file, source, namespace, method, targets)
  local actual, element = mapper(parse(source, "xml"), source)
  if actual ~= namespace then return end
  local content = first(element, "content")
  if not content then return end
  for child in content:iter_children() do
    if child:type() == "element" then
      local kind, start = tag(child, source)
      if statements[kind] then
        local id, node = attribute(start, "id", source)
        if id == method then targets[#targets + 1] = target(file, node, 1) end
      end
    end
  end
end

local function java_targets(file, source, namespace, method, targets)
  local tree = parse(source, "java")
  if not tree then return end
  for interface in tree:iter_children() do
    if java_namespace(tree, interface, source) == namespace then
      if not method then targets[#targets + 1] = target(file, interface:field("name")[1]); return end
      local body = interface:field("body")[1]
      if not body then return end
      for child in body:iter_children() do
        local name = child:type() == "method_declaration" and child:field("name")[1]
        if name and text(name, source) == method then targets[#targets + 1] = target(file, name) end
      end
    end
  end
end

local function contents(file)
  local b = vim.fn.bufnr(file)
  if b > 0 and vim.api.nvim_buf_is_loaded(b) then return b end
  local stat = vim.uv.fs_stat(file)
  if stat and stat.type == "file" and stat.size <= 2 * 1024 * 1024 then
    local ok, lines = pcall(vim.fn.readfile, file)
    if ok then return table.concat(lines, "\n") end
  end
end

local function origin(buf)
  local win, cursor = vim.api.nvim_get_current_win(), vim.api.nvim_win_get_cursor(0)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  return function()
    return vim.api.nvim_get_current_win() == win and vim.api.nvim_get_current_buf() == buf
      and vim.api.nvim_buf_get_changedtick(buf) == tick and vim.deep_equal(cursor, vim.api.nvim_win_get_cursor(win))
  end
end

local function search(root, namespace, method, to_xml, valid, fallback)
  if vim.fn.executable("rg") ~= 1 then fallback(); return end
  local class = namespace:match("[^%.]+$")
  local args = { "rg", "--no-config", "-0", "-g", "!**/target/**" }
  if to_xml then vim.list_extend(args, { "-l", "-F", "-g", "*.xml", "--", namespace, "." })
  else vim.list_extend(args, { "--files", "-g", class .. ".java" }) end
  vim.system(args, { cwd = root, text = true, timeout = 4500 }, vim.schedule_wrap(function(result)
    if not valid() then return end
    local candidates, targets = {}, {}
    for file in (result.stdout or ""):gmatch("[^%z]+") do
      candidates[vim.fs.normalize(root .. "/" .. file)] = true
    end
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(b)
      if vim.api.nvim_buf_is_loaded(b) and vim.startswith(name, root .. "/")
          and (to_xml and vim.endswith(name, ".xml") or not to_xml and vim.endswith(name, "/" .. class .. ".java")) then
        candidates[name] = true
      end
    end
    for _, file in ipairs(vim.tbl_keys(candidates)) do
      local source = contents(file)
      if source then
        if to_xml then xml_targets(file, source, namespace, method, targets)
        else java_targets(file, source, namespace, method, targets) end
      end
    end
    if #targets == 0 then fallback(); return end
    if #targets > 1 then
      table.sort(targets, function(a, b) return a.text < b.text end)
      require("user.navigation").items("MyBatis — " .. (method or class), targets)
      return
    end
    local item = targets[1]
    local pos = { line = item.pos[1] - 1, character = item.pos[2] }
    vim.lsp.util.show_document({ uri = vim.uri_from_fname(item.file), range = { start = pos, ["end"] = pos } },
      "utf-8", { focus = true, reuse_win = not vim.wo.diff })
    vim.cmd("normal! zz")
  end))
end

local function project(buf)
  return vim.fs.root(buf, ".git") or vim.fs.root(buf, { "pom.xml", "settings.gradle", "settings.gradle.kts" })
end

local syntax = {
  parse = parse, text = text, first = first, tag = tag, attribute = attribute,
  mapper = mapper, contents = contents, target = target, origin = origin,
}

function M.java_references(fallback)
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "java" or vim.bo[buf].buftype ~= "" then return false end
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf })
  if not ok or not node or node:type() ~= "identifier" then return false end
  local parent = node:parent()
  local grandparent = parent and parent:parent()
  local kind = parent and parent:type()
  local name = parent and parent:field("name")[1]
  local symbol = text(node, buf)
  local bean = kind == "method_declaration"
    and (symbol:match("^get%u") or symbol:match("^is%u") or symbol:match("^set%u"))
  local field = kind == "variable_declarator" and grandparent and grandparent:type() == "field_declaration"
  local param = (kind == "formal_parameter" or kind == "spread_parameter")
    and grandparent and grandparent:parent() and grandparent:parent():type() == "method_declaration"
  if not name or not name:equal(node) or not (bean or field or param) then return false end
  local root = project(buf)
  if not root then return false end
  require("user.mybatis_semantics").run(buf, root, false, syntax, fallback)
  return true
end

function M.jump_from_java(fallback)
  local buf = vim.api.nvim_get_current_buf()
  local tree = vim.bo[buf].filetype == "java" and parse(buf, "java")
  if not tree then return false end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local namespace, method = java_declaration(tree, buf, row - 1, col)
  local root = namespace and project(buf)
  if not root then return false end
  search(root, namespace, method, true, origin(buf), fallback)
  return true
end

function M.implementation(fallback)
  local buf = vim.api.nvim_get_current_buf()
  local tree = vim.bo[buf].filetype == "java" and parse(buf, "java")
  local root = tree and project(buf)
  if not root then return false end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local node = tree:named_descendant_for_range(row - 1, col, row - 1, col)
  local call = node and node:parent()
  local name = call and call:type() == "method_invocation" and call:field("name")[1]
  if not name or not name:equal(node) then return false end
  local client = vim.lsp.get_clients({ bufnr = buf, name = "lathe", method = "textDocument/definition" })[1]
  if not client then return false end
  local valid = origin(buf)
  return client:request("textDocument/definition", vim.lsp.util.make_position_params(0, client.offset_encoding),
    function(err, result)
      vim.schedule(function()
        if not valid() then return end
        local loc = not err and type(result) == "table"
          and ((result.uri or result.targetUri) and result or #result == 1 and result[1])
        local uri = loc and (loc.uri or loc.targetUri)
        local file = uri and vim.startswith(uri, "file:") and vim.uri_to_fname(uri)
        local source = file and vim.startswith(file, root .. "/") and contents(file)
        local dest = source and parse(source, "java")
        local range = loc and (loc.targetSelectionRange or loc.range)
        if not dest or not range then fallback(); return end
        local start = range.start
        local line = type(source) == "number" and vim.api.nvim_buf_get_lines(source, start.line, start.line + 1, false)[1]
          or vim.split(source, "\n", { plain = true })[start.line + 1]
        local byte = vim.str_byteindex(line or "", client.offset_encoding, start.character, false)
        local namespace, method = java_declaration(dest, source, start.line, byte)
        if namespace then search(root, namespace, method, true, valid, fallback) else fallback() end
      end)
    end, buf)
end

function M.setup()
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("UserMyBatisNavigation", { clear = true }), pattern = "xml",
    callback = function(ev)
      local b = ev.buf
      if not mapper(parse(b, "xml"), b) then return end
      local function mapper_jump()
        local tree = parse(b, "xml")
        local namespace, element = mapper(tree, b)
        local root = namespace and project(b)
        if not root then return end
        local row, col = unpack(vim.api.nvim_win_get_cursor(0))
        local node = tree:named_descendant_for_range(row - 1, col, row - 1, col)
        local method
        while node and not node:equal(element) do
          if node:type() == "Attribute" then
            local name = first(node, "Name")
            local key = name and text(name, b)
            if vim.tbl_contains({ "resultMap", "extends", "refid", "test", "collection", "property", "value" }, key) then
              vim.notify("MyBatis: 未找到可静态确认的定义", vim.log.levels.INFO)
              return
            end
          elseif node:type() == "CharData" or node:type() == "CData" then
            local line = vim.api.nvim_get_current_line()
            for from, value, finish in line:gmatch("()[#$]%{([^}]+)%}()") do
              if col >= from - 1 and col < finish - 1 and value ~= "" then
                vim.notify("MyBatis: 未找到可静态确认的定义", vim.log.levels.INFO)
                return
              end
            end
          end
          local kind, start = tag(node, b)
          if statements[kind] then method = attribute(start, "id", b); break end
          node = node:parent()
        end
        search(root, namespace, method, false, origin(b), function()
          vim.notify("MyBatis: 未找到对应的 Java Mapper 声明", vim.log.levels.WARN)
        end)
      end
      local function run(definition)
        local root = project(b)
        if not root then return end
        require("user.mybatis_semantics").run(b, root, definition, syntax, definition and mapper_jump or function()
          vim.notify("MyBatis: 光标处没有可静态确认的引用", vim.log.levels.INFO)
        end)
      end
      vim.keymap.set("n", "gd", function() run(true) end, { buffer = b, desc = "Go to MyBatis definition" })
      vim.keymap.set("n", "gr", function() run(false) end, { buffer = b, desc = "Find MyBatis usages" })
    end,
  })
end

return M
