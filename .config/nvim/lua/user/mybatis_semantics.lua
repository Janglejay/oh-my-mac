local M = {}
local active = {}
local cached
local statements = { select = true, insert = true, update = true, delete = true }
local property_attrs = { test = true, collection = true, value = true }
local sql_text = { CharData = true, CData = true }

local function range_item(file, source, node, offset, width, syntax)
  local item = syntax.target(file, node)
  local prefix = syntax.text(node, source):sub(1, offset)
  local lines = vim.split(prefix, "\n", { plain = true })
  item.pos[1] = item.pos[1] + #lines - 1
  item.pos[2] = (#lines == 1 and item.pos[2] or 0) + #lines[#lines]
  item.width = width
  item.text = ("%s:%d  %s"):format(vim.fs.basename(file), item.pos[1],
    syntax.text(node, source):sub(offset + 1, offset + width))
  return item
end

local function location_key(item)
  return ("%s:%d:%d"):format(item.file, item.pos[1], item.pos[2])
end

local function ids(kind, namespace, value)
  if not value:match("^[%w_$][%w_$.-]*$") or value:find("..", 1, true) or value:sub(-1) == "." then return end
  return kind .. ":" .. (value:find(".", 1, true) and value or namespace .. "." .. value)
end

local function bean_name(method)
  local stem = method:match("^get(%u[%w_$]*)$") or method:match("^is(%u[%w_$]*)$")
  return stem and (stem:match("^%u%u") and stem or stem:sub(1, 1):lower() .. stem:sub(2))
end

local function expression(raw, scope, java, report)
  local function mask(s) return (" "):rep(#s) end
  local prepared = raw:gsub("&quot;.-&quot;", mask):gsub("&apos;.-&apos;", mask)
    :gsub("'[^']*'", mask):gsub('"[^"]*"', mask)
    :gsub("&[%w#]+;", mask)
  local resolved
  local cursor = 1
  while true do
    local start, stop, word = prepared:find("([%a_$][%w_$]*)", cursor)
    if not start then break end
    cursor = stop + 1
    local before = prepared:sub(start - 1, start - 1)
    local static_call = before == "@" or prepared:sub(cursor):match("^[%w_$.]*@")
    local prev = prepared:sub(1, start - 1):match("([^%s])%s*$")
    if not static_call and prev ~= "." and prev ~= "@" then
      local binding = scope.bindings[word]
      local item, t
      if binding ~= nil then
        if binding then item, t = binding.item, binding.type end
      elseif prepared:sub(cursor):match("^%s*%(%s*%)") then
        item, t = java.member(scope.default, bean_name(word), word)
        cursor = cursor + #prepared:sub(cursor):match("^%s*%(%s*%)")
      elseif not prepared:sub(cursor):match("^%s*%(") then
        item, t = java.member(scope.default, word)
      end
      if item then report(item, start, stop) end
      while true do
        local after = prepared:sub(cursor)
        local bracket, open = after:match("^(%s*()%b[])")
        if bracket then
          local inner_start = cursor + open
          local inner = raw:sub(inner_start, cursor + #bracket - 2)
          local from, key = inner:match("^%s*['\"]()([%w_$]+)['\"]%s*$")
          local alias = t and t.bindings and key and t.bindings[key]
          if alias then
            if alias.item then report(alias.item, inner_start + from - 1, inner_start + from + #key - 2) end
            t = alias.type
          else
            expression(inner, scope, java, function(decl, start, stop)
              report(decl, inner_start + start - 1, inner_start + stop - 1)
            end)
            t = java.element(t)
          end
          cursor = cursor + #bracket
        else
          local fragment, key = after:match("^(%s*%.%s*([%a_$][%w_$]*))")
          if not fragment then break end
          local next_pos = cursor + #fragment
          local method, prop = nil, key
          local tail = prepared:sub(next_pos)
          local empty_call = tail:match("^%s*%(%s*%)")
          if empty_call then
            method = key
            prop = bean_name(key)
          elseif tail:match("^%s*%(") then
            prop = nil
          end
          if t and t.bindings then
            local binding = not method and t.bindings[prop]
            item, t = binding and binding.item, binding and binding.type
          elseif t and t.map and not method and prop then
            item, t = nil, java.element(t)
          else
            item, t = java.member(t, prop, method)
          end
          if item then report(item, next_pos - #key, next_pos - 1) end
          cursor = next_pos + #(empty_call or "")
        end
      end
      if prepared:sub(1, start - 1):match("^%s*$") and prepared:sub(cursor):match("^%s*$") then resolved = t end
    end
  end
  return resolved
end

local function build(files, syntax)
  local java = require("user.mybatis_java").new(files, syntax)
  local defs, refs, by_file, sql, mappers = {}, {}, {}, {}, {}
  local text, first, tag, attribute = syntax.text, syntax.first, syntax.tag, syntax.attribute
  local function add(keys, item, key, declaration)
    local rows = keys[key] or {}
    keys[key] = rows
    local id = location_key(item)
    if rows[id] then return end
    rows[id] = item
    if item.file:sub(-4) == ".xml" then
      item.key, item.declaration = key, declaration
      by_file[item.file] = by_file[item.file] or {}
      table.insert(by_file[item.file], item)
    end
  end
  local function each(element, fn)
    local content = first(element, "content")
    if not content then return end
    for node in content:iter_children() do fn(node) end
  end

  for file in pairs(files) do
    if vim.endswith(file, ".xml") then
      local source = syntax.contents(file)
      local parsed = source and syntax.parse(source, "xml")
      local namespace, element = syntax.mapper(parsed, source)
      if namespace then
        local doc = { file = file, source = source, namespace = namespace, root = element }
        mappers[#mappers + 1] = doc
        each(element, function(node)
          if node:type() ~= "element" then return end
          local kind, start = tag(node, source)
          if kind ~= "sql" and kind ~= "resultMap" then return end
          local id, value = attribute(start, "id", source)
          local key = id and ids(kind, namespace, id)
          if not key then return end
          add(defs, range_item(file, source, value, 1, #id, syntax), key, true)
          if kind == "sql" then
            sql[key] = sql[key] or {}
            table.insert(sql[key], { doc = doc, node = node })
          end
        end)
      elseif parsed then
        local config = parsed:field("root")[1]
        if tag(config, source) == "configuration" then
          each(config, function(section)
            if section:type() ~= "element" or tag(section, source) ~= "typeAliases" then return end
            each(section, function(node)
              if node:type() ~= "element" then return end
              local kind, start = tag(node, source)
              if kind ~= "typeAlias" then return end
              local class = attribute(start, "type", source)
              if not class or not class:match("^[%a_$][%w_$.]*$") then return end
              local alias = (attribute(start, "alias", source) or class:match("[^.$]+$")):lower()
              local known = java.aliases[alias]
              if known == nil then java.aliases[alias] = class:gsub("%$", ".")
              elseif known ~= class:gsub("%$", ".") then java.aliases[alias] = false end
            end)
          end)
        end
      end
    end
  end

  local function record_expr(doc, node, raw, offset, scope)
    return expression(raw, scope, java, function(decl, start, stop)
      local key = location_key(decl)
      add(defs, decl, key, true)
      add(refs, range_item(doc.file, doc.source, node, offset + start - 1, stop - start + 1, syntax), key)
    end)
  end
  local function attr_ref(doc, name, start, kind, variables)
    local value, node = attribute(start, name, doc.source)
    if not value then return end
    local match
    for from, raw in value:gmatch("()([^,%s]+)") do
      local expanded = raw:gsub("%$%{([%w_.$-]+)%}", function(k) return variables and variables[k] end)
      local key = ids(kind, doc.namespace, expanded)
      if key then
        add(refs, range_item(doc.file, doc.source, node, from, #raw, syntax), key)
        match = key
      end
    end
    return match
  end
  local function statement_scope(doc, start)
    local name = attribute(start, "id", doc.source)
    local method = name and java.mapper_method(doc.namespace, name)
    local scope, parameters = { bindings = {}, variables = {}, visited = {} }, {}
    local param_type = attribute(start, "parameterType", doc.source)
    if method == false then return scope end
    for _, param in ipairs(method and method.args or {}) do
      local base = param.raw:match("([%w_]+)$")
      if base ~= "RowBounds" and base ~= "ResultHandler" then parameters[#parameters + 1] = param end
    end
    if #parameters == 1 and not parameters[1].alias then
      local value = parameters[1]
      scope.default = java.type_for(value.raw, value.owner)
      local binding = { item = value, type = scope.default }
      scope.bindings._parameter = binding
      if scope.default and scope.default.dimensions > 0 then
        scope.bindings.array = binding
      elseif scope.default and scope.default.collection then
        scope.bindings.collection = binding
        if value.raw:match("List%s*<") then scope.bindings.list = binding end
      end
    elseif #parameters == 0 then
      scope.default = java.type_for(param_type)
    else
      for i, p in ipairs(parameters) do
        local binding = { item = p, type = java.type_for(p.raw, p.owner) }
        local key = "param" .. i
        scope.bindings[key] = binding
      end
      for _, p in ipairs(parameters) do
        if p.alias then scope.bindings[p.alias] = { item = p, type = java.type_for(p.raw, p.owner) } end
      end
      scope.bindings._parameter = { type = { bindings = vim.tbl_extend("force", {}, scope.bindings) } }
    end
    return scope
  end

  local seen_xml = {}
  local function visit(doc, node, scope, bean)
    if sql_text[node:type()] then
      if not scope then return end
      for from, raw in text(node, doc.source):gmatch("()[#$]%{([^}]+)%}") do
        record_expr(doc, node, raw:match("^[^,]+") or raw, from + 1, scope)
      end
      return
    end
    if node:type() == "CDSect" then
      for child in node:iter_children() do visit(doc, child, scope, bean) end
      return
    end
    if node:type() ~= "element" then return end
    local source = doc.source
    local kind, start = tag(node, source)
    if not start then return end
    local variables = scope and scope.variables
    attr_ref(doc, "resultMap", start, "resultMap", variables)
    local child_scope = scope
    if statements[kind] then
      child_scope = statement_scope(doc, start)
    elseif kind == "resultMap" then
      attr_ref(doc, "extends", start, "resultMap", variables)
      bean = java.type_for((attribute(start, "type", source)))
    elseif kind == "include" then
      local key = attr_ref(doc, "refid", start, "sql", variables)
      if scope and key and not scope.visited[key] then
        local include_scope = vim.tbl_extend("force", scope, { variables = vim.tbl_extend("force", scope.variables, {}) })
        each(node, function(child)
          if child:type() ~= "element" then return end
          local name, child_start = tag(child, source)
          if name == "property" then
            local variable = attribute(child_start, "name", source)
            local value = attribute(child_start, "value", source)
            if variable and value then
              include_scope.variables[variable] = value:gsub("%$%{([%w_.$-]+)%}", function(k) return variables[k] end)
            end
          end
        end)
        scope.visited[key] = true
        for _, fragment in ipairs(sql[key] or {}) do visit(fragment.doc, fragment.node, include_scope, nil) end
        scope.visited[key] = nil
      end
    end

    local prop, prop_node = attribute(start, (kind == "idArg" or kind == "arg") and "name" or "property", source)
    local value_type
    if bean and prop and prop:match("^[%w_$.]+$") then
      value_type = record_expr(doc, prop_node, prop, 1, { bindings = {}, default = bean })
    end
    if kind == "association" then
      bean = java.type_for((attribute(start, "javaType", source))) or value_type
    elseif kind == "collection" then
      bean = java.type_for((attribute(start, "ofType", source))) or java.element(value_type)
    end

    if child_scope then
      local resolved = {}
      for attr in pairs(property_attrs) do
        if attr == "test" or (attr == "collection" and kind == "foreach") or (attr == "value" and kind == "bind") then
          local raw, value = attribute(start, attr, source)
          if raw then resolved[attr] = record_expr(doc, value, raw, 1, child_scope) end
        end
      end
      if kind == "foreach" then
        child_scope = vim.tbl_extend("force", child_scope, { bindings = vim.tbl_extend("force", child_scope.bindings, {}) })
        local item, index = attribute(start, "item", source), attribute(start, "index", source)
        if item then child_scope.bindings[item] = { type = java.element(resolved.collection) } end
        if index then child_scope.bindings[index] = false end
      elseif kind == "bind" then
        local name = attribute(start, "name", source)
        if name then child_scope.bindings[name] = { type = resolved.value } end
      end
    end
    each(node, function(child) visit(doc, child, child_scope, bean) end)
  end
  for _, doc in ipairs(mappers) do
    if not seen_xml[doc.file] then
      seen_xml[doc.file] = true
      each(doc.root, function(child) visit(doc, child) end)
    end
  end
  return defs, refs, by_file, java
end

local function stamp(file)
  local buf = vim.fn.bufnr(file)
  if buf > 0 and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified then
    return ("%d:%d"):format(buf, vim.api.nvim_buf_get_changedtick(buf))
  end
  local stat = vim.uv.fs_stat(file)
  if stat then return ("%d:%d:%d:%d"):format(stat.ino, stat.size, stat.mtime.sec, stat.mtime.nsec) end
  return "missing"
end

local function workspace(root, paths, syntax)
  if cached and cached.root == root and vim.deep_equal(paths, cached.paths) then
    local valid = true
    for file, previous in pairs(cached.stamps) do
      if stamp(file) ~= previous then valid = false; break end
    end
    if valid then return cached end
  end
  local defs, refs, by_file, java = build(paths, syntax)
  cached = { root = root, paths = paths, defs = defs, refs = refs, by_file = by_file, java = java, stamps = {} }
  for file in pairs(paths) do
    if vim.endswith(file, ".xml") or java.files[file] then cached.stamps[file] = stamp(file) end
  end
  return cached
end

local function list_paths(root, file, done)
  local function run(args, callback)
    return vim.system(args, { cwd = root, text = true, timeout = 7000 }, vim.schedule_wrap(callback))
  end
  -- Use the XML header only to shortlist files. All semantic matches use Tree-sitter nodes.
  return run({ "rg", "--no-config", "-0", "-l", "-g", "*.xml", "-g", "!**/target/**",
    "--", "<(mapper|typeAliases)\\b", "." },
    function(result)
      if result.code ~= 0 and result.code ~= 1 then done(nil); return end
      local paths = { [file] = true }
      local function add(output)
        for path in (output or ""):gmatch("[^%z]+") do paths[vim.fs.normalize(root .. "/" .. path)] = true end
      end
      add(result.stdout)
      run({ "rg", "--no-config", "-0", "--files", "-g", "*.java", "-g", "!**/target/**" }, function(java)
        if java.code ~= 0 and java.code ~= 1 then done(nil); return end
        add(java.stdout)
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          local name = vim.api.nvim_buf_get_name(b)
          if vim.api.nvim_buf_is_loaded(b) and vim.startswith(name, root .. "/")
              and (vim.endswith(name, ".xml") or vim.endswith(name, ".java")) then paths[name] = true end
        end
        done(paths)
      end)
    end)
end

local function order(items)
  table.sort(items, function(a, b)
    if a.file ~= b.file then return a.file < b.file end
    return a.pos[1] == b.pos[1] and a.pos[2] < b.pos[2] or a.pos[1] < b.pos[1]
  end)
end

local function show(items, title, definition)
  if #items == 0 then
    vim.notify(definition and "MyBatis: No statically resolvable definition found"
      or "MyBatis: No statically resolvable references found", vim.log.levels.INFO)
  elseif definition and #items == 1 then
    local item = items[1]
    local pos = { line = item.pos[1] - 1, character = item.pos[2] }
    vim.lsp.util.show_document({ uri = vim.uri_from_fname(item.file), range = { start = pos, ["end"] = pos } },
      "utf-8", { focus = true, reuse_win = not vim.wo.diff })
    vim.cmd("normal! zz")
  else
    order(items)
    return require("user.navigation").usage_items(title, items)
  end
end

function M.run(buf, root, definition, syntax, fallback, extra)
  local file = vim.api.nvim_buf_get_name(buf)
  local pos = vim.api.nvim_win_get_cursor(0)
  local valid = syntax.origin(buf)
  local request = {}
  active[buf] = request
  list_paths(root, file, function(paths)
    if active[buf] ~= request or not valid() then return end
    active[buf] = nil
    if not paths then fallback(); return end
    local model = workspace(root, paths, syntax)
    local defs, refs, by_file, java = model.defs, model.refs, model.by_file, model.java
    local at, keys = false, {}
    if vim.bo[buf].filetype == "java" then
      local decl = java.declaration_at(file, pos[1], pos[2])
      local key = decl and location_key(decl)
      if key and refs[key] then keys[key], at = true, true end
    else
      for _, item in ipairs(by_file[file] or {}) do
        if item.pos[1] == pos[1] and item.pos[2] <= pos[2] and pos[2] < item.pos[2] + item.width then
          keys[item.key], at = true, at or item.declaration
        end
      end
    end
    if not next(keys) then fallback(); return end
    local jump = definition and not at
    local items, dedup = {}, {}
    local function add(item)
      local key = location_key(item)
      if not dedup[key] then dedup[key] = true; items[#items + 1] = item end
    end
    for key in pairs(keys) do
      for _, item in pairs((jump and defs or refs)[key] or {}) do add(item) end
    end
    for _, item in ipairs(extra or {}) do add(item) end
    local title = jump and "MyBatis — Definition" or "MyBatis — Usages"
    if not jump and vim.bo[buf].filetype == "java"
        and #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/references" }) > 0 then
      local picker, cancel
      local origin_win = vim.api.nvim_get_current_win()
      local changedtick = vim.api.nvim_buf_get_changedtick(buf)
      local timer = vim.defer_fn(function()
        if cancel then cancel() end
        if picker and not picker.closed then
          picker.title = title .. " · Java LSP timed out · Test paths last"
          picker:update_titles()
        end
      end, 30000)
      cancel = vim.lsp.buf_request_all(buf, "textDocument/references", function(client)
        local params = vim.lsp.util.make_position_params(origin_win, client.offset_encoding)
        params.context = { includeDeclaration = false }
        return params
      end, vim.schedule_wrap(function(result)
        if timer:is_closing() then return end
        timer:stop()
        timer:close()
        if not picker or picker.closed or not vim.api.nvim_buf_is_valid(buf)
            or vim.api.nvim_buf_get_changedtick(buf) ~= changedtick then return end
        local incomplete = false
        for id, response in pairs(result) do
          local client = vim.lsp.get_client_by_id(id)
          incomplete = incomplete or response.err ~= nil
          if client and type(response.result) == "table" then
            for _, loc in ipairs(vim.lsp.util.locations_to_items(response.result, client.offset_encoding)) do
              add({ file = loc.filename, pos = { loc.lnum, loc.col - 1 },
                text = ("%s:%d  %s"):format(vim.fs.basename(loc.filename), loc.lnum, loc.text or "") })
            end
          end
        end
        order(items)
        picker.opts.items = items
        picker.title = title .. (incomplete and " · Partial Java LSP results" or "") .. " · Test paths last"
        picker:find()
      end))
      picker = show(items, title .. " · Querying Java LSP", false)
      if picker then
        picker.opts.on_close = function()
          if timer:is_closing() then return end
          timer:stop()
          timer:close()
          if cancel then cancel() end
        end
      end
    else
      show(items, title, jump)
    end
  end)
end

return M
