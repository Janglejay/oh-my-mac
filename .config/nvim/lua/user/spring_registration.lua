local M = {}
local bean_factory = "org.springframework.beans.factory."
local support = bean_factory .. "support."
local context = "org.springframework.context."
local postprocessors = {
  [bean_factory .. "config.BeanFactoryPostProcessor"] = { postProcessBeanFactory = bean_factory .. "config.ConfigurableListableBeanFactory" },
  [support .. "BeanDefinitionRegistryPostProcessor"] = {
    postProcessBeanDefinitionRegistry = support .. "BeanDefinitionRegistry",
    postProcessBeanFactory = bean_factory .. "config.ConfigurableListableBeanFactory",
  },
  [context .. "annotation.ImportBeanDefinitionRegistrar"] = { registerBeanDefinitions = support .. "BeanDefinitionRegistry" },
}
local registries = {
  [support .. "BeanDefinitionRegistry"] = true, [support .. "DefaultListableBeanFactory"] = true,
  [context .. "support.GenericApplicationContext"] = true, [context .. "annotation.AnnotationConfigApplicationContext"] = true,
}
local application_contexts = {
  [context .. "support.GenericApplicationContext"] = true,
  [context .. "annotation.AnnotationConfigApplicationContext"] = true,
}
local singleton_factories = {
  [bean_factory .. "config.ConfigurableListableBeanFactory"] = true, [bean_factory .. "config.ConfigurableBeanFactory"] = true,
  [bean_factory .. "config.SingletonBeanRegistry"] = true, [support .. "DefaultListableBeanFactory"] = true,
}
local lookup_factories = vim.tbl_extend("force", {}, registries, singleton_factories, {
  [bean_factory .. "BeanFactory"] = true, [bean_factory .. "ListableBeanFactory"] = true,
  [context .. "ApplicationContext"] = true, [context .. "ConfigurableApplicationContext"] = true,
})
lookup_factories[support .. "BeanDefinitionRegistry"] = nil
lookup_factories[bean_factory .. "config.SingletonBeanRegistry"] = nil
M.types = {}
for fqn in pairs(vim.tbl_extend("force", {}, postprocessors, registries, singleton_factories, lookup_factories, {
  [support .. "RootBeanDefinition"] = true, [support .. "BeanDefinitionBuilder"] = true,
  [context .. "annotation.ImportSelector"] = true, [context .. "annotation.DeferredImportSelector"] = true,
})) do
  M.types[fqn:match("[^.]+$")] = fqn
end

function M.scan(method, parents, source, raw_type, append, profiles, owner)
  local function value(node) return node and vim.treesitter.get_node_text(node, source) end
  local body, method_id = method:field("body")[1], value(method:field("name")[1])
  local code = value(body)
  if not code or not (code:find("register", 1, true) or code:find("getBean", 1, true)) then return end
  local expected
  for _, parent in ipairs(parents) do
    if postprocessors[parent] then expected = expected or postprocessors[parent][method_id] end
  end
  local parameters = method:field("parameters")[1]
  local receivers, registration = {}, {}
  if parameters then
    for node in parameters:iter_children() do
      local name, ty = value(node:field("name")[1]), node:field("type")[1]
      if name and ty then
        receivers[name] = raw_type(ty)
        if receivers[name] and receivers[name] == expected then registration[name] = true end
      end
    end
  end
  local function args(node)
    local all = {}
    if node then for c in node:iter_children() do if c:named() and not c:extra() then all[#all + 1] = c end end end
    return all
  end
  local function class_literal(node)
    if node and node:type() == "class_literal" then return raw_type(node:named_child(0)) end
  end
  local function creation(node)
    if node and node:type() == "object_creation_expression" then return raw_type(node:field("type")[1]) end
  end
  local function definition(node)
    if not node then return end
    if creation(node) == support .. "RootBeanDefinition" then
      return class_literal(args(node:field("arguments")[1])[1])
    end
    if node:type() ~= "method_invocation" or value(node:field("name")[1]) ~= "getBeanDefinition" then return end
    local builder = node:field("object")[1]
    if not builder or builder:type() ~= "method_invocation" then return end
    local factory, called = builder:field("object")[1], value(builder:field("name")[1])
    if factory and raw_type(factory) == support .. "BeanDefinitionBuilder"
        and (called == "genericBeanDefinition" or called == "rootBeanDefinition") then
      return class_literal(args(builder:field("arguments")[1])[1])
    end
  end
  local declarations, bean_definitions, written, local_contexts = {}, {}, {}, {}
  -- Resolve only method parameters and direct locals. Nested shadowing and arbitrary assignments
  -- make source-only receiver/product inference ambiguous.
  local function writes(node)
    local kind = node:type()
    if kind == "assignment_expression" then
      local left = node:field("left")[1]
      if left and left:type() == "identifier" then written[value(left)] = true end
    elseif kind == "variable_declarator" and not node:parent():parent():equal(body) or kind == "formal_parameter"
        or kind == "catch_formal_parameter" or kind == "enhanced_for_statement" then
      local id = value(node:field("name")[1])
      if id then written[id] = true end
    end
    for _, c in ipairs(args(node)) do writes(c) end
  end
  writes(body)
  local function call(node)
    if node:type() ~= "method_invocation" then return end
    local object, id = node:field("object")[1], value(node:field("name")[1])
    local name = object and object:type() == "identifier" and value(object)
    local receiver = name and not written[name] and receivers[name]
    if not receiver then return end
    local arguments = args(node:field("arguments")[1])
    local key, product = arguments[1], arguments[2]
    local literal = key and key:type() == "string_literal" and value(key):match('^"([%w_.$/-]+)"$')
    local local_context = local_contexts[name]
    if id == "getBean" and lookup_factories[receiver] then
      local ty = class_literal(key)
      if literal or ty then append("injection", key, nil, {}, profiles,
        { by_name = literal, type = ty or class_literal(product), local_context = local_context }) end
      return
    end
    if not local_context and not registration[name] then return end
    if literal and product and id == "registerAlias" and registries[receiver] then
      local alias = product:type() == "string_literal" and value(product):match('^"([%w_.$/-]+)"$')
      if alias then
        local binding = { by_name = literal, local_context = local_context, owner = not local_context and owner or nil }
        append("alias", product, nil, {}, profiles, vim.tbl_extend("force", binding, { id = alias }))
        append("injection", key, nil, {}, profiles, binding)
      end
      return
    end
    local ty
    if id == "registerBean" and application_contexts[receiver] then
      ty = class_literal(literal and product or key)
      literal = literal or ty
    elseif literal and product and id == "registerSingleton" and singleton_factories[receiver] then
      ty = creation(product)
      if not ty and product:type() == "identifier" then
        local var = value(product)
        ty = not written[var] and declarations[var]
      end
    elseif literal and product and id == "registerBeanDefinition" and registries[receiver] then
      ty = definition(product)
      if not ty and product:type() == "identifier" then
        local var = value(product)
        ty = not written[var] and bean_definitions[var]
      end
    end
    if ty and literal then append("bean", key, nil, {}, profiles,
      { names = {literal}, type = ty, runtime = true, owner = not local_context and owner or nil, local_context = local_context }) end
  end
  for _, stmt in ipairs(args(body)) do
    if stmt:type() == "local_variable_declaration" then
      local ty = stmt:field("type")[1]
      for _, var in ipairs(stmt:field("declarator")) do
        local name = value(var:field("name")[1])
        if name then
          receivers[name] = ty and raw_type(ty)
          local initialized = var:field("value")[1]
          declarations[name] = creation(initialized)
          bean_definitions[name] = definition(initialized)
          if application_contexts[declarations[name]] then
            -- File identity is added by the resolver, so different contexts stay separate.
            local_contexts[name] = tostring(method:start()) .. ":" .. name
            receivers[name] = declarations[name]
          end
        end
      end
    end
    -- Registration eligibility is limited to an unguarded statement in the Spring callback.
    if stmt:type() == "expression_statement" then call(stmt:named_child(0)) end
    -- Lookups can also appear in a return or local initializer.
    if stmt:type() == "return_statement" then
      local child = stmt:named_child(0)
      if child and value(child:field("name")[1]) == "getBean" then call(child) end
    elseif stmt:type() == "local_variable_declaration" then
      for _, var in ipairs(stmt:field("declarator")) do
        local child = var:field("value")[1]
        if child and value(child:field("name")[1]) == "getBean" then call(child) end
      end
    end
  end
end

return M
