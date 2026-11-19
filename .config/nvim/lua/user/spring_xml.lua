local M = {}
local xml = require("user.mybatis_navigation").xml_syntax
local beans = "http://www.springframework.org/schema/beans"
local shortcut = { ["http://www.springframework.org/schema/p"] = true, ["http://www.springframework.org/schema/c"] = true }
local entity = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }

local function decoded(raw)
  local known = true
  local value = raw:gsub("&([^;]+);", function(key)
    if not entity[key] then known = false end
    return entity[key]
  end)
  return known and value or nil
end

local function tokens(value)
  local result = {}
  for start, raw, stop in value.raw:gmatch("()([^,%s;]+)()") do
    local literal = decoded(raw)
    if literal and not literal:find("[${}#]") then
      local row, col = value.node:start()
      local function at(offset)
        local before = value.raw:sub(1, offset - 1)
        local _, lines = before:gsub("\n", "")
        if lines == 0 then return row, col + offset end
        return row + lines, #before:match("[^\n]*$")
      end
      local r, c = at(start)
      local er, ec = at(stop)
      result[#result + 1] = { name = literal, span = {r, c, er, ec}, pos = {r + 1, c} }
    end
  end
  return result
end

function M.read(path)
  local source = xml.contents(path)
  local tree = source and xml.parse(source, "xml")
  local root = tree and tree:field("root")[1]
  if not root then return end
  local facts, classes = {}, {}
  local function walk(node, namespaces, groups, inner)
    local tag, start = xml.tag(node, source)
    if not start then return end
    local attrs = {}
    namespaces = vim.tbl_extend("force", {}, namespaces)
    for child in start:iter_children() do
      if child:type() == "Attribute" then
        local name, value = xml.first(child, "Name"), xml.first(child, "AttValue")
        if name and value then
          local key, raw = xml.text(name, source), xml.text(value, source):sub(2, -2)
          attrs[key] = { raw = raw, node = value }
          if key == "xmlns" then namespaces[""] = raw
          else
            local prefix = key:match("^xmlns:(.+)$")
            if prefix then namespaces[prefix] = raw end
          end
        end
      end
    end
    local prefix, kind = tag:match("^(.-):(.+)$")
    kind = kind or tag
    local spring = namespaces[prefix or ""] == beans
    if node:equal(root) and not (spring and kind == "beans") then return end
    if spring and kind == "beans" and attrs.profile then
      local profiles = {}
      local raw = decoded(attrs.profile.raw)
      if raw then for name in raw:gmatch("[^,%s;]+") do profiles[#profiles + 1] = name end end
      groups = vim.list_extend(vim.list_extend({}, groups), { profiles })
    end
    local function values(key) return attrs[key] and tokens(attrs[key]) or {} end
    local function one(key)
      local vals = values(key)
      if #vals == 1 then return vals[1] end
    end
    local function fact(kind, entry, extra)
      local item = vim.tbl_extend("force", { kind = kind, id = entry.name, spans = { entry.span },
        file = path, pos = entry.pos, profiles = groups, xml = true }, extra or {})
      facts[#facts + 1] = item
      return item
    end
    local function ref(key, parent)
      for _, target in ipairs(values(key)) do fact("injection", target, { by_name = target.name, parent = parent }) end
    end
    if spring and kind == "bean" then
      local names = vim.list_extend(values("id"), values("name"))
      local class = one("class")
      -- The implementation type of a factory method is unrelated to its product type.
      local ty = class and not attrs["factory-method"] and class.name
      if class then classes[#classes + 1] = class.name end
      if names[1] and not inner then
        local aliases, spans = {}, {}
        for _, name in ipairs(names) do
          aliases[#aliases + 1], spans[#spans + 1] = name.name, name.span
        end
        local qualifier = xml.first(node, "content")
        local qualifier_names = {}
        if qualifier then
          for q in qualifier:iter_children() do
            if q:type() == "element" then
              local qtag, qstart = xml.tag(q, source)
              if qtag == "qualifier" or qtag == (prefix or "") .. ":qualifier" then
                local value = xml.attribute(qstart, "value", source)
                if value and value:match("^[%w_.$-]+$") then qualifier_names[#qualifier_names + 1] = value end
              end
            end
          end
        end
        local definition = fact("bean", names[1], { names = aliases, spans = spans, type = ty, qualifiers = qualifier_names,
          primary = attrs.primary and attrs.primary.raw == "true", abstract = attrs.abstract and attrs.abstract.raw == "true",
          excluded = attrs["autowire-candidate"] and attrs["autowire-candidate"].raw == "false",
          parent_name = one("parent") and one("parent").name })
        if class then fact("class_ref", class, { type = class.name, definition = definition }) end
      elseif ty and not inner then
        local definition = fact("bean", class, { names = {}, type = ty })
        table.remove(facts)
        fact("class_ref", class, { type = class.name, definition = definition })
        facts[#facts + 1] = definition
      end
      ref("parent", true)
      ref("factory-bean")
      ref("depends-on")
      for key in pairs(attrs) do
        local pp = key:match("^(.-):.+%-ref$")
        if pp and shortcut[namespaces[pp]] then ref(key) end
      end
    elseif spring and kind == "alias" then
      local alias, target = one("alias"), one("name")
      if alias and target then
        fact("alias", alias, { by_name = target.name })
        fact("injection", target, { by_name = target.name })
      end
    elseif spring and (kind == "property" or kind == "constructor-arg" or kind == "entry") then
      ref("ref")
      if kind == "entry" then ref("key-ref"); ref("value-ref") end
    elseif spring and (kind == "ref" or kind == "idref") then
      ref("bean")
      ref("local")
    end
    local content = xml.first(node, "content")
    if content then
      for child in content:iter_children() do
        if child:type() == "element" then walk(child, namespaces, groups, inner or spring and kind == "bean") end
      end
    end
  end
  walk(root, {}, {}, false)
  return { facts = facts, classes = classes, parents = {} }
end

return M
