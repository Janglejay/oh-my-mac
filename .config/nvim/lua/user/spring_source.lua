local M = {}
local registration = require("user.spring_registration")
local java_types = { class_declaration = true, record_declaration = true, interface_declaration = true }
local spring_packages = {
  Bean = "org.springframework.context.annotation", Configuration = "org.springframework.context.annotation",
  Profile = "org.springframework.context.annotation", Primary = "org.springframework.context.annotation",
  Fallback = "org.springframework.context.annotation",
  Autowired = "org.springframework.beans.factory.annotation", Qualifier = "org.springframework.beans.factory.annotation",
  Component = "org.springframework.stereotype", Repository = "org.springframework.stereotype",
  Service = "org.springframework.stereotype", Controller = "org.springframework.stereotype",
  RestController = "org.springframework.web.bind.annotation", SpringBootApplication = "org.springframework.boot.autoconfigure",
  Resource = "javax.annotation", Import = "org.springframework.context.annotation",
  RequiredArgsConstructor = "lombok", AllArgsConstructor = "lombok", NoArgsConstructor = "lombok",
  Data = "lombok", Value = "lombok", NonNull = "lombok", Builder = "lombok", NonFinal = "lombok.experimental",
}
local stereotypes = { Component = true, Repository = true, Service = true, Controller = true,
  RestController = true, Configuration = true, SpringBootApplication = true }
local java_lang = { String = true, Object = true, Boolean = true, Byte = true, Short = true, Integer = true,
  Long = true, Float = true, Double = true, Character = true, Number = true, Runnable = true, Class = true }

local function text(node, source)
  return vim.treesitter.get_node_text(node, source)
end

local function child(node, kind)
  for c in node:iter_children() do if c:type() == kind then return c end end
end

local function contents(path)
  local buf = vim.fn.bufnr(path)
  if buf > 0 and vim.api.nvim_buf_is_loaded(buf) then return buf end
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "file" or stat.size > 1024 * 1024 then return end
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and table.concat(lines, "\n") or nil
end

local function copies_qualifier(path)
  local target = "org.springframework.beans.factory.annotation.Qualifier"
  local function config(file, visited)
    if visited[file] then return nil, false end
    visited[file] = true
    if vim.fn.filereadable(file) ~= 1 then return nil, false end
    local result, stop
    for _, line in ipairs(vim.fn.readfile(file)) do
      local import = line:match("^%s*import%s+([^#]-)%s*$")
      local op, value = line:match("^%s*lombok%.copyableAnnotations%s*([+-])=%s*([^%s#]+)")
      if import and not import:find("!", 1, true) then
        local nested = vim.fs.normalize(import:sub(1, 1) == "/" and import or vim.fs.dirname(file) .. "/" .. import)
        local choice = config(nested, visited)
        if choice ~= nil then result = choice end
      elseif op and value == target then result = op == "+"
      elseif line:match("^%s*clear%s+lombok%.copyableAnnotations%s*$") then result = false
      elseif line:match("^%s*config%.stopBubbling%s*=%s*true%s*$") then stop = true end
    end
    return result, stop
  end
  for directory in vim.fs.parents(path) do
    local value, stop = config(directory .. "/lombok.config", {})
    if value ~= nil then return value end
    if stop then break end
  end
  return false
end

local function matches(expression, active)
  local tokens, offset = {}, 1
  while true do
    local start, stop, token = expression:find("([!|&()])", offset)
    local from, last, name = expression:find("([^%s!|&()]+)", offset)
    if from and (not start or from < start) then start, stop, token = from, last, name end
    if not start then break end
    tokens[#tokens + 1], offset = token, stop + 1
  end
  local pos = 1
  local function evaluate(nested)
    local current, mode, invert, expect = nil, nil, false, true
    while tokens[pos] do
      local token = tokens[pos]
      pos = pos + 1
      if token == ")" then
        if nested and not expect then return current end
        return nil
      elseif token == "!" and expect then
        invert = not invert
      elseif (token == "&" or token == "|") and not expect and (not mode or token == mode) then
        mode, expect = token, true
      elseif expect and token ~= "&" and token ~= "|" then
        local value
        if token == "(" then
          value = evaluate(true)
          if value == nil then return end
        else
          value = active[token] == true
        end
        if invert then value = not value end
        if mode == "&" then current = current and value
        elseif mode == "|" then current = current or value
        else current = value end
        invert, expect = false, false
      else
        return
      end
    end
    if not nested and not expect then return current end
  end
  return evaluate(false) == true and pos == #tokens + 1
end

function M.enabled(groups, active)
  for _, group in ipairs(groups) do
    if not vim.iter(group):any(function(p) return matches(p, active) end) then return false end
  end
  return true
end

function M.at(facts, row, col)
  for _, fact in ipairs(facts) do
    for _, span in ipairs(fact.spans) do
      local r, c, er, ec = unpack(span)
      if (row > r or row == r and col >= c) and (row < er or row == er and col < ec) then return fact end
    end
  end
end

function M.read(path)
  local source = contents(path)
  if not source then return end
  local registration_calls = type(source) == "number" or source:find("register", 1, true) or source:find("getBean", 1, true)
  local ok, root = pcall(function()
    local parser = type(source) == "number" and vim.treesitter.get_parser(source, "java")
      or vim.treesitter.get_string_parser(source, "java")
    return parser:parse()[1]:root()
  end)
  if not ok then return end
  local pkg, imports, wildcards = "", {}, {}
  for node in root:iter_children() do
    if node:type() == "package_declaration" then pkg = text(node, source):match("package%s+([%w_$.]+)") or ""
    elseif node:type() == "import_declaration" then
      local full = text(node, source):match("import%s+([%w_$.]+)%s*;")
      local wildcard = text(node, source):match("import%s+([%w_$.]+)%.%*%s*;")
      if full then imports[full:match("[^.]+$")] = full
      elseif wildcard then wildcards[wildcard] = true end
    end
  end
  local function raw_type(node)
    local raw = text(node, source)
    local name = raw:match("^([%w_$.]+)")
    if not name or raw:match("%[%s*%]") or raw:find("<", 1, true) then return end
    if name:find(".", 1, true) then
      local leading = name:match("^[^.]+")
      return imports[leading] and imports[leading] .. name:sub(#leading + 1) or name
    end
    local framework = registration.types[name]
    return imports[name] or (framework and wildcards[framework:match("^(.+)%.%w+$")] and framework)
      or (java_lang[name] and "java.lang." .. name) or (pkg ~= "" and pkg .. "." .. name or name)
  end
  local function annotation_is(original, short)
    local owner = spring_packages[short]
    local function in_package(package)
      return original == package .. "." .. short or original == short
        and (imports[short] == package .. "." .. short or not imports[short] and wildcards[package])
    end
    return owner and (in_package(owner) or short == "Resource" and in_package("jakarta.annotation"))
  end
  local function annotations(node)
    local found = {}
    local mods = child(node, "modifiers")
    if not mods then return found end
    for ann in mods:iter_children() do
      if ann:type() == "annotation" or ann:type() == "marker_annotation" then
        local name_node = ann:field("name")[1]
        local original = name_node and text(name_node, source)
        local short = original and original:match("[^.]+$")
        if short and annotation_is(original, short) then
          local info = { names = {}, spans = {}, classes = {} }
          found[short] = info
          local function value(value_node)
            if value_node:type() == "string_literal" then
              local s = text(value_node, source):match('^"([^"\\]+)"$')
              if s then
                info.names[#info.names + 1] = s
                info.spans[#info.spans + 1] = { value_node:range() }
              end
            elseif value_node:type() == "element_value_array_initializer" then
              for i in value_node:iter_children() do value(i) end
            elseif value_node:type() == "class_literal" and short == "Import" then
              local ty = value_node:named_child(0)
              local fqn = ty and raw_type(ty)
              if fqn then info.classes[#info.classes + 1] = { node = value_node, type = fqn } end
            end
          end
          local args = child(ann, "annotation_argument_list")
          if args then
            for arg in args:iter_children() do
              if arg:type() == "element_value_pair" then
                local key, v = arg:field("key")[1], arg:field("value")[1]
                local k = key and text(key, source)
                if v and (k == "name" or k == "value") then info.explicit_name = true; value(v)
                elseif v and k == "autowireCandidate" and text(v, source) == "false" then info.excluded = true end
                if v and (k == "onConstructor" or k == "onConstructor_") then
                  local function annotated(n)
                    local name = n:field("name")[1]
                    if (n:type() == "annotation" or n:type() == "marker_annotation") and name
                        and annotation_is(text(name, source), "Autowired") then return true end
                    for c in n:iter_children() do if c:named() and annotated(c) then return true end end
                    return false
                  end
                  info.autowired = annotated(v)
                end
              elseif arg:named() and not arg:extra() then info.explicit_name = true; value(arg) end
            end
          end
        end
      end
    end
    return found
  end
  local facts, parents, classes = {}, {}, {}
  local function append(kind, id, type_node, anns, groups, extra)
    local row, col = id:start()
    local fact = { kind = kind, file = path, pos = { row + 1, col }, id = text(id, source),
      type = type_node and raw_type(type_node), profiles = groups, spans = { { id:range() } } }
    local qualifier = anns.Qualifier
    if qualifier then
      fact.qualifier = qualifier.names[1]
      fact.unknown_qualifier = not fact.qualifier
      vim.list_extend(fact.spans, qualifier.spans)
    end
    local resource = anns.Resource
    if resource and kind == "injection" then
      fact.resource = true
      fact.by_name = resource.names[1]
      fact.unknown_qualifier = resource.explicit_name and not fact.by_name
      vim.list_extend(fact.spans, resource.spans)
    end
    if anns.Bean then vim.list_extend(fact.spans, anns.Bean.spans) end
    facts[#facts + 1] = extra and vim.tbl_extend("force", fact, extra) or fact
    return facts[#facts]
  end
  local function profiles(groups, anns)
    if not anns.Profile then return groups end
    local result = vim.list_extend({}, groups)
    result[#result + 1] = anns.Profile.names
    return result
  end
  local function class(node, prefix, inherited)
    if not java_types[node:type()] then return end
    local id, body = node:field("name")[1], node:field("body")[1]
    if not id or not body then return end
    local declared = text(id, source)
    local fqn = prefix == "" and declared or prefix .. "." .. declared
    local all = {}
    local function hierarchy(n)
      for c in n:iter_children() do
        if c:type() == "type_list" then hierarchy(c)
        elseif c:named() and not c:extra() then
          local p = raw_type(c)
          if p then all[#all + 1] = p end
        end
      end
    end
    for c in node:iter_children() do
      if c:type() == "superclass" or c:type() == "super_interfaces" or c:type() == "extends_interfaces" then hierarchy(c) end
    end
    parents[fqn] = all
    local row, col = id:start()
    classes[fqn] = { file = path, id = declared, type = fqn, pos = {row + 1, col}, spans = { {id:range()} } }
    local anns, registrations = annotations(node), {}
    for key, ann in pairs(anns) do if stereotypes[key] then registrations[#registrations + 1] = ann end end
    local registered = #registrations > 0
    local groups = profiles(inherited, anns)
    local owner = not registered and fqn or nil
    classes[fqn].profiles = groups
    if anns.Import then
      for _, imported in ipairs(anns.Import.classes) do
        append("import", imported.node, nil, {}, groups, { type = imported.type, owner = owner })
      end
    end
    if registered then
      local names = {}
      for _, ann in ipairs(registrations) do vim.list_extend(names, ann.names) end
      if #names == 0 then
        names[1] = declared:match("^%u%u") and declared or declared:sub(1, 1):lower() .. declared:sub(2)
      end
      append("bean", id, nil, anns, groups, { names = names, type = fqn, primary = anns.Primary ~= nil,
        fallback = anns.Fallback ~= nil })
    end
    local constructors = 0
    for c in body:iter_children() do if c:type() == "constructor_declaration" then constructors = constructors + 1 end end
    local generated = anns.AllArgsConstructor or anns.RequiredArgsConstructor
    if not generated and constructors == 0 and not anns.NoArgsConstructor then generated = anns.Value or anns.Data or anns.Builder end
    local implicit = generated and constructors == 0 and not anns.NoArgsConstructor
      and not (anns.AllArgsConstructor and anns.RequiredArgsConstructor)
    local use_generated = generated and (generated.autowired or implicit)
    local constructor_fields = generated and constructors == 0 and not (anns.AllArgsConstructor and anns.RequiredArgsConstructor) and {}
    classes[fqn].constructor_fields = constructor_fields or nil
    local copy_qualifier
    for c in body:iter_children() do
      local kind = c:type()
      if kind == "method_declaration" or kind == "constructor_declaration" or kind == "field_declaration" then
        local members = annotations(c)
        local member_profiles = profiles(groups, members)
        local name, ty = c:field("name")[1], c:field("type")[1]
        if kind == "method_declaration" and members.Bean and name then
          local names = members.Bean.names
          if #names == 0 and not members.Bean.explicit_name then names = { text(name, source) } end
          append("bean", name, ty, members, member_profiles, { names = names,
            factory = true, primary = members.Primary ~= nil, fallback = members.Fallback ~= nil,
            excluded = members.Bean.excluded, owner = owner })
        end
        if kind == "field_declaration" and ty then
          local mods = child(c, "modifiers")
          local static = mods and child(mods, "static")
          local final = not members.NonFinal and (mods and child(mods, "final") or anns.Value)
          for _, decl in ipairs(c:field("declarator")) do
            local var = decl:field("name")[1]
            local initialized = decl:field("value")[1]
            if var and not static then
              local parameter = not (final and initialized) and (anns.AllArgsConstructor or anns.Value or anns.Builder
                or not initialized and (final or members.NonNull))
              if constructor_fields and parameter then
                constructor_fields[#constructor_fields + 1] = { var:range() }
              end
              if members.Autowired or members.Resource then
                append("injection", var, ty, members, member_profiles, { field = true, owner = owner })
              elseif use_generated and parameter then
                if members.Qualifier and copy_qualifier == nil then copy_qualifier = copies_qualifier(path) end
                append("injection", var, ty, copy_qualifier and members or {}, member_profiles,
                  { lombok = true, owner = owner })
              end
            end
          end
        elseif members.Autowired or members.Bean or members.Resource
            or kind == "constructor_declaration" and constructors == 1 and not generated and not anns.NoArgsConstructor then
            local params = c:field("parameters")[1]
            if params then
              for p in params:iter_children() do
                local var, t = p:field("name")[1], p:field("type")[1]
                if var and t then
                  local parameter = annotations(p)
                  local property = members.Resource and name and text(name, source):match("^set(%u.*)$")
                  if property then parameter.Resource = members.Resource end
                  append("injection", var, t, parameter, member_profiles, {
                    owner = owner,
                    resource_name = property and (property:match("^%u%u") and property or property:sub(1, 1):lower() .. property:sub(2)),
                  })
                end
              end
            end
        end
        if registration_calls and kind == "method_declaration" then
          registration.scan(c, all, source, raw_type, append, member_profiles, fqn)
        end
      elseif java_types[kind] then class(c, fqn, groups) end
    end
  end
  for node in root:iter_children() do class(node, pkg, {}) end
  return { facts = facts, parents = parents, classes = classes }
end

return M
