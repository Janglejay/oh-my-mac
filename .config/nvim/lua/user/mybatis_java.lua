local M = {}
local type_nodes = { class_declaration = true, interface_declaration = true, record_declaration = true }

local function property(name, prefix)
  local rest = name:match("^" .. prefix .. "(%u[%w_$]*)$")
  if not rest then return end
  return rest:match("^%u%u") and rest or rest:sub(1, 1):lower() .. rest:sub(2)
end

local function type_parts(value)
  local base, rest = vim.trim(value):match("^([%w_$.]+)%s*(.*)$")
  if not base then return end
  local args, start, depth = {}, 1, 0
  local inner = rest:match("^<(.+)>")
  if inner then
    for i = 1, #inner do
      local char = inner:sub(i, i)
      if char == "<" then depth = depth + 1 end
      if char == ">" then depth = depth - 1 end
      if char == "," and depth == 0 then
        args[#args + 1], start = vim.trim(inner:sub(start, i - 1)), i + 1
      end
    end
    args[#args + 1] = vim.trim(inner:sub(start))
    rest = rest:sub(#inner + 3)
  end
  local _, dimensions = rest:gsub("%[%s*%]", "")
  return base, args, dimensions
end

function M.new(files, syntax)
  local index = { types = {}, files = {}, by_name = {}, aliases = {} }
  local text, first, target = syntax.text, syntax.first, syntax.target
  for file in pairs(files) do
    local name = vim.fs.basename(file):match("^(.+)%.java$")
    if name then
      index.by_name[name] = index.by_name[name] or {}
      table.insert(index.by_name[name], file)
    end
  end

  local function read(file)
    if index.files[file] then return end
    local source = syntax.contents(file)
    local tree = source and syntax.parse(source, "java")
    local imports, pkg = {}, ""
    index.files[file] = {}
    if not tree then return end
    for node in tree:iter_children() do
      if node:type() == "package_declaration" then
        pkg = text(node, source):match("package%s+([%w_$.]+)") or ""
      elseif node:type() == "import_declaration" then
        local path = text(node, source):match("import%s+([%w_$.*]+)%s*;")
        if path then imports[#imports + 1] = path end
      end
    end

    local function declared(node, outer)
      if not type_nodes[node:type()] then return end
      local name, body = node:field("name")[1], node:field("body")[1]
      if not name or not body then return end
      local prefix = outer and outer.name or pkg
      local name_value = text(name, source)
      local qualified = prefix == "" and name_value or prefix .. "." .. name_value
      local owner = { name = qualified, pkg = pkg, imports = imports, outer = outer, file = file,
        fields = {}, accessors = {}, methods = {}, parents = {} }
      index.files[file][#index.files[file] + 1] = owner
      local previous = index.types[qualified]
      if previous == nil then index.types[qualified] = owner
      elseif previous ~= owner then index.types[qualified] = false end
      local function add_parent(parent)
        for child in parent:iter_children() do
          if child:type() == "type_list" then add_parent(child)
          elseif child:named() and not child:extra() then
            owner.parents[#owner.parents + 1] = text(child, source)
          end
        end
      end
      for child in node:iter_children() do
        if child:type() == "superclass" or child:type() == "super_interfaces" or child:type() == "extends_interfaces" then
          add_parent(child)
        end
      end
      local function member(id, kind)
        local item = target(file, id)
        item.width, item.raw, item.owner = #text(id, source), kind, owner
        return item
      end
      for child in body:iter_children() do
        local kind, type_node = child:type(), child:field("type")[1]
        if kind == "field_declaration" and type_node then
          local modifiers = first(child, "modifiers")
          if not modifiers or not text(modifiers, source):match("%f[%w]static%f[%W]") then
            for _, variable in ipairs(child:field("declarator")) do
              local id = variable:field("name")[1]
              if id then owner.fields[text(id, source)] = member(id, text(type_node, source)) end
            end
          end
        elseif kind == "method_declaration" and type_node then
          local id, params = child:field("name")[1], child:field("parameters")[1]
          if id and params then
            local id_text, parameters = text(id, source), {}
            for param in params:iter_children() do
              local t, n = param:field("type")[1], param:field("name")[1]
              if param:type() == "spread_parameter" then
                n = first(param, "variable_declarator")
                n = n and n:field("name")[1]
                t = param:named_child(0)
                if t and t:type() == "modifiers" then t = param:named_child(1) end
              end
              if n and t then
                local raw = text(t, source) .. (param:type() == "spread_parameter" and "[]" or "")
                local p = member(n, raw)
                local annotation = first(param, "modifiers")
                if annotation then
                  for annotation_name, value in text(annotation, source):gmatch('@([%w_$.]+)%s*%(%s*"([^"]+)"%s*%)') do
                    if annotation_name == "Param" or annotation_name == "org.apache.ibatis.annotations.Param" then
                      p.alias = value
                    end
                  end
                end
                p.name = text(n, source)
                parameters[#parameters + 1] = p
              end
            end
            local result = text(type_node, source)
            local method = { args = parameters, owner = owner }
            owner.methods[id_text] = owner.methods[id_text] or {}
            table.insert(owner.methods[id_text], method)
            local modifiers = first(child, "modifiers")
            local mod = modifiers and text(modifiers, source) or ""
            local bean
            if not mod:match("%f[%w]static%f[%W]") then
              if #parameters == 0 and result ~= "void" then
                bean = property(id_text, "get")
                  or ((result == "boolean" or result == "Boolean") and property(id_text, "is"))
              elseif #parameters == 1 then
                local setter = property(id_text, "set")
                if setter then
                  local entry = owner.accessors[setter] or { names = {} }
                  entry.names[#entry.names + 1] = member(id, parameters[1].raw)
                  if entry.write == nil then entry.write = entry.names[#entry.names]
                  else entry.write = false end
                  owner.accessors[setter] = entry
                end
              end
            end
            if bean then
              local entry = owner.accessors[bean] or { names = {} }
              local accessor = member(id, result)
              accessor.method = id_text
              entry.names[#entry.names + 1] = accessor
              if not entry.read or id_text:match("^is") then entry.read = accessor end
              owner.accessors[bean] = entry
            end
          end
        else
          declared(child, owner)
        end
      end
    end
    for child in tree:iter_children() do declared(child) end
  end

  local function lookup(name)
    for part in name:gmatch("[^%.]+") do
      for _, file in ipairs(index.by_name[part] or {}) do read(file) end
    end
    return index.types[name] or nil
  end

  local collections = { List = true, Collection = true, Set = true, Iterable = true, ArrayList = true,
    LinkedList = true, HashSet = true, SortedSet = true, Queue = true, Deque = true, Stream = true }
  local maps = { Map = true, HashMap = true, LinkedHashMap = true, TreeMap = true, SortedMap = true }
  local function type_for(raw, owner)
    local base, args, dimensions = type_parts((raw or ""):gsub("%$", "."))
    if not base then return end
    local alias = not owner and index.aliases[base:lower()]
    local resolved = lookup(alias or base)
    if not resolved and owner then
      local current = owner
      while current and not resolved do
        resolved = lookup(current.name .. "." .. base)
        current = current.outer
      end
      local first_name = base:match("^[^.]+")
      for _, path in ipairs(owner.imports) do
        local candidate
        if path:sub(-2) == ".*" then candidate = path:sub(1, -2) .. base
        elseif vim.fs.basename(path:gsub("%.", "/")) == first_name then
          candidate = path .. base:sub(#first_name + 1)
        end
        if candidate then resolved = resolved or lookup(candidate) end
      end
      if not resolved and owner.pkg ~= "" then resolved = lookup(owner.pkg .. "." .. base) end
    end
    local simple = base:match("[^.]+$")
    return { owner = resolved, raw = raw, context = owner, args = args, dimensions = dimensions,
      collection = not resolved and collections[simple], map = not resolved and maps[simple] }
  end
  index.type_for = type_for

  function index.element(t)
    if not t or not t.dimensions then return end
    if t.dimensions > 0 then return type_for((t.raw:gsub("%[%s*%]%s*$", "", 1)), t.context) end
    local raw = (t.map and t.args[2]) or (t.collection and t.args[1])
    return raw and type_for((raw:gsub("^%?%s+extends%s+", "")), t.context)
  end

  function index.member(t, name, method, seen)
    local owner = t and t.owner
    if not owner or not name or t.dimensions > 0 then return end
    seen = seen or {}
    if seen[owner] then return end
    seen[owner] = true
    local field, access = owner.fields[name], owner.accessors[name]
    local read_access = access and access.read
    if method and access then
      read_access = nil
      for _, accessor in ipairs(access.names) do
        if accessor.method == method then read_access = accessor; break end
      end
    end
    local declaration = field or read_access or (access and access.write)
    if declaration and (not method or read_access and read_access.method == method) then
      return declaration, type_for((read_access or declaration).raw, owner)
    end
    for _, raw in ipairs(owner.parents) do
      local found, value = index.member(type_for(raw, owner), name, method, seen)
      if found then return found, value end
    end
  end

  function index.mapper_method(namespace, name)
    local owner, seen = lookup(namespace), {}
    local function find(current)
      if not current or seen[current] then return end
      seen[current] = true
      local methods = current.methods[name]
      if methods then return #methods == 1 and methods[1] or false end
      local result
      for _, raw in ipairs(current.parents) do
        local p = type_for(raw, current)
        local method = p and find(p.owner)
        if method == false or method and result and result ~= method then return false end
        result = method or result
      end
      return result
    end
    return find(owner)
  end

  local function at(item, row, col)
    return item.pos[1] == row and item.pos[2] <= col and col < item.pos[2] + item.width
  end
  function index.declaration_at(file, row, col)
    read(file)
    for _, owner in ipairs(index.files[file]) do
      for _, item in pairs(owner.fields) do if at(item, row, col) then return item end end
      for name, access in pairs(owner.accessors) do
        for _, item in ipairs(access.names) do
          if at(item, row, col) then return owner.fields[name] or access.read or access.write end
        end
      end
      for _, overloads in pairs(owner.methods) do
        for _, method in ipairs(overloads) do
          for _, arg in ipairs(method.args) do if at(arg, row, col) then return arg end end
        end
      end
    end
  end
  return index
end

return M
