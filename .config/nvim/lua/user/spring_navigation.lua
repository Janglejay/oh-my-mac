local M = {}
local source = require("user.spring_source")
local bridge = require("user.spring_tools")
local xml = require("user.spring_xml")
local profile_sets, requests = {}, {}
local navigation_timeout = 3000

local function active_profiles(ctx)
  if profile_sets[ctx.analysis] then return profile_sets[ctx.analysis] end
  local active = {}
  for name in (vim.env.SPRING_PROFILES_ACTIVE or ""):gmatch("[^,%s]+") do active[name] = true end
  if not next(active) then active.default = true end
  return active
end

local function location_key(fact)
  return ("%s:%d:%d"):format(fact.file, fact.pos[1], fact.pos[2])
end

local function origin(buf)
  local win, pos = vim.api.nvim_get_current_win(), vim.api.nvim_win_get_cursor(0)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  return pos, function()
    return vim.api.nvim_get_current_win() == win and vim.api.nvim_get_current_buf() == buf
      and vim.api.nvim_buf_get_changedtick(buf) == tick and vim.deep_equal(vim.api.nvim_win_get_cursor(win), pos)
  end
end

local function sort(items)
  table.sort(items, function(a, b)
    if a.file ~= b.file then return a.file < b.file end
    if a.pos[1] ~= b.pos[1] then return a.pos[1] < b.pos[1] end
    return a.pos[2] < b.pos[2]
  end)
end

local function as_item(fact)
  return { file = fact.file, pos = fact.pos,
    text = ("%s:%d  %s  %s"):format(vim.fs.basename(fact.file), fact.pos[1], fact.id, fact.type or "") }
end

local function jump(items, title)
  if #items == 1 then
    local item = items[1]
    local pos = { line = item.pos[1] - 1, character = item.pos[2] }
    local review = package.loaded["user.codediff_review"]
    local in_review = vim.wo.diff or (review and review.is_open())
    vim.lsp.util.show_document({ uri = vim.uri_from_fname(item.file), range = { start = pos, ["end"] = pos } },
      "utf-8", { focus = true, reuse_win = not in_review })
    vim.cmd("normal! zz")
  else
    sort(items)
    require("user.navigation").usage_items(title, items)
  end
end

local function read(state, path)
  local stat = vim.uv.fs_stat(path)
  if not stat then return end
  local buf = vim.fn.bufnr(path)
  local tick = buf > 0 and vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_changedtick(buf)
  local key = ("%d:%d:%d:%d:%s:%s"):format(stat.ino, stat.size, stat.mtime.sec, stat.mtime.nsec,
    tick and buf or "", tick or "")
  state.spring_sources = state.spring_sources or {}
  local entry = state.spring_sources[path]
  if entry and entry.key == key then return entry.data end
  local data = (vim.endswith(path, ".xml") and xml or source).read(path)
  state.spring_sources[path] = { key = key, data = data }
  return data
end

local function discover(model, callback, registrations_only)
  local files, jobs = {}, 2
  local function find(args, roots)
    local paths = vim.tbl_keys(roots)
    if #paths == 0 then jobs = jobs - 1; if jobs == 0 then callback(files) end; return end
    vim.list_extend(args, paths)
    vim.system(args, { text = true, timeout = 7000 }, vim.schedule_wrap(function(result)
      for _, file in ipairs(vim.split(result.stdout or "", "\0", { trimempty = true })) do files[file] = true end
      jobs = jobs - 1
      if jobs == 0 then callback(files) end
    end))
  end
  if vim.fn.executable("rg") ~= 1 then callback(files); return end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local file = vim.api.nvim_buf_get_name(buf)
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified
        and (vim.endswith(file, ".xml") or vim.endswith(file, ".java")) and bridge.module(model, file) then
      files[file] = true
    end
  end
  find({ "rg", "--files-with-matches", "--null", "--no-ignore", "-g", "*.xml", "--", "springframework\\.org/schema/beans" }, model.resource_roots)
  local annotations = registrations_only and "Import" or "Import|Component|Service|Repository|Controller|RestController|Configuration|SpringBootApplication"
  local calls = registrations_only and "" or "registerSingleton|registerBeanDefinition|registerAlias|\\b(?:registerBean|getBean)\\s*\\(|"
  find({ "rg", "--files-with-matches", "--null", "--no-ignore", "-g", "*.java", "--",
    calls .. "@(?:[\\w.]+\\.)?(?:" .. annotations .. ")\\b" },
    model.java_roots)
end

-- Use the Spring symbol set, model-scoped configuration documents, and targeted Java candidates.
local function collect(model, symbols, current, discovered, expired, visible)
  local paths, definitions, injections, graph = { [current] = true }, {}, {}, {}
  local classes, imports, aliases = {}, {}, {}
  for file in pairs(discovered) do paths[file] = true end
  for _, symbol in ipairs(symbols) do
    local uri = symbol.location and symbol.location.uri
    if uri and vim.startswith(uri, "file:") then
      local file = vim.uri_to_fname(uri)
      if vim.endswith(file, ".java") or vim.endswith(file, ".xml") then paths[file] = true end
    end
  end
  local function include(path)
    local module, scope = bridge.module(model, path)
    local data = module and (not visible or visible[module.name]) and read(model, path)
    if data then
      for name, parents in pairs(data.parents) do
        graph[name] = graph[name] or {}
        for _, parent in ipairs(parents) do graph[name][parent] = true end
      end
      for _, fact in ipairs(data.facts) do
        if fact.kind ~= "class_ref" then
          local item = vim.tbl_extend("force", fact, { module = module.name, test = scope == "test",
            named = fact.field or module.parameter_names })
          local targets = ({ bean = definitions, alias = aliases, import = imports })[fact.kind] or injections
          targets[#targets + 1] = item
        end
      end
      if not vim.endswith(path, ".xml") then
        for name, decl in pairs(data.classes) do
          classes[name] = classes[name] or {}
          classes[name][#classes[name] + 1] = vim.tbl_extend("force", decl, { module = module.name, test = scope == "test" })
        end
      end
      return data
    end
  end
  local wanted = {}
  for path in pairs(paths) do
    if expired() then return end
    local data = include(path)
    if data and vim.endswith(path, ".xml") then
      for _, ty in ipairs(data.classes) do wanted[ty] = true end
    end
  end
  for _, item in ipairs(imports) do wanted[item.type] = true end
  for _, item in ipairs(injections) do if item.type then wanted[item.type] = true end end
  for name in pairs(wanted) do
    if expired() then return end
    local path = name:gsub("%$.*$", ""):gsub("%.", "/") .. ".java"
    for dir in pairs(model.java_roots) do
      local full = dir .. "/" .. path
      if not paths[full] and vim.uv.fs_stat(full) then paths[full] = true; include(full) end
    end
  end
  return { definitions = definitions, injections = injections, graph = graph, aliases = aliases,
    imports = imports, classes = classes, model = model }
end

local function visible_modules(dataset, module)
  dataset.visible = dataset.visible or {}
  if dataset.visible[module] then return dataset.visible[module] end
  local visible = { [module] = true }
  local function visit(name)
    local current = dataset.model.modules[name]
    for upstream in pairs(current and current.upstream or {}) do
      if not visible[upstream] then visible[upstream] = true; visit(upstream) end
    end
  end
  visit(module)
  dataset.visible[module] = visible
  return visible
end

local function allowed(site, candidate, visible, profiles)
  return visible[candidate.module] and (not candidate.test or site.test and candidate.module == site.module)
    and source.enabled(candidate.profiles, profiles)
end

local function same_context(a, b)
  return not a.local_context and not b.local_context or a.local_context == b.local_context and a.file == b.file
end

local function active(site, item, dataset, visible, profiles)
  if not allowed(site, item, visible, profiles) then return false end
  if not item.owner then return true end
  for _, registration in ipairs(dataset.owners[item.owner] or {}) do
    if allowed(site, registration, visible, profiles) then return true end
  end
  return false
end

local function activate(dataset, profiles)
  local owners = {}
  dataset.owners = owners
  local function register(item)
    local ty = item.type
    if not ty or item.owner or item.runtime or item.abstract or item.factory then return end
    owners[ty] = owners[ty] or {}
    owners[ty][#owners[ty] + 1] = item
  end
  for _, item in ipairs(dataset.definitions) do register(item) end
  local pending = vim.list_extend({}, dataset.imports)
  local changed = true
  while changed do
    changed = false
    for i = #pending, 1, -1 do
      local item = pending[i]
      local visible = visible_modules(dataset, item.module)
      if active(item, item, dataset, visible, profiles) then
        table.remove(pending, i)
        local targets = vim.tbl_filter(function(c) return allowed(item, c, visible, profiles) end, dataset.classes[item.type] or {})
        if #targets == 1 then
          local class = targets[1]
          local registration = vim.tbl_extend("force", item, { owner = nil })
          register(registration)
          local framework = vim.iter(dataset.graph[item.type] or {}):any(function(_, parent)
            return parent == "org.springframework.context.annotation.ImportBeanDefinitionRegistrar"
              or parent == "org.springframework.context.annotation.ImportSelector"
              or parent == "org.springframework.context.annotation.DeferredImportSelector"
          end)
          if not framework and not vim.iter(dataset.definitions):any(function(bean)
            return location_key(bean) == location_key(class)
          end) then
            dataset.definitions[#dataset.definitions + 1] = vim.tbl_extend("force", class,
              { kind = "bean", names = { item.type }, registration = registration })
          end
          dataset.injections[#dataset.injections + 1] = item
          changed = true
        end
      end
    end
  end
end

local function bean_lookup(dataset, profiles)
  local names, types, aliases = {}, {}, {}
  local function add(list, key, value)
    list[key] = list[key] or {}
    list[key][#list[key] + 1] = value
  end
  for _, bean in ipairs(dataset.definitions) do
    for _, name in ipairs(bean.names) do add(names, name, bean) end
  end
  local function inherit(bean, visiting)
    if bean.type or not bean.parent_name or visiting[bean] then return bean.type end
    visiting[bean] = true
    local type_name
    for _, parent in ipairs(names[bean.parent_name] or {}) do
      if parent.module == bean.module and source.enabled(parent.profiles, profiles) then
        local candidate = inherit(parent, visiting)
        if not candidate or type_name and type_name ~= candidate then return end
        type_name = candidate
      end
    end
    visiting[bean] = nil
    return type_name
  end
  for _, bean in ipairs(dataset.definitions) do
    local seen = {}
    local function types_of(name)
      if not name or seen[name] then return end
      seen[name] = true
      add(types, name, bean)
      for parent in pairs(dataset.graph[name] or {}) do types_of(parent) end
    end
    types_of(inherit(bean, {}))
  end
  for _, alias in ipairs(dataset.aliases) do add(aliases, alias.id, alias) end
  dataset.by_name, dataset.by_type, dataset.aliases_by_name = names, types, aliases
end

local function resolve(site, dataset, profiles)
  if site.unknown_qualifier or not source.enabled(site.profiles, profiles) then return {} end
  local visible = visible_modules(dataset, site.module)
  if not active(site, site, dataset, visible, profiles) then return {} end
  local function names(name, seen)
    if not name or seen[name] then return end
    seen[name] = true
    for _, alias in ipairs(dataset.aliases_by_name[name] or {}) do
      if same_context(site, alias) and active(site, alias, dataset, visible, profiles) then names(alias.by_name, seen) end
    end
  end
  local matched_names = {}
  names(site.by_name or site.qualifier or site.resource and (site.resource_name or site.id), matched_names)
  local candidates = {}
  if site.by_name or site.resource then
    for name in pairs(matched_names) do
      for _, bean in ipairs(dataset.by_name[name] or {}) do candidates[bean] = true end
    end
  end
  if not site.by_name then
    for _, bean in ipairs(dataset.by_type[site.type] or {}) do candidates[bean] = true end
  end
  local matches, primary, named, regular = {}, {}, {}, {}
  for bean in pairs(candidates) do
    local named_match = vim.iter(bean.names):any(function(name) return matched_names[name] end)
    local qualified = not site.qualifier or named_match or bean.qualifier == site.qualifier
      or vim.tbl_contains(bean.qualifiers or {}, site.qualifier)
    local eligible = active(site, bean, dataset, visible, profiles)
      and same_context(site, bean)
      and (not bean.registration or allowed(site, bean.registration, visible, profiles))
      and (not bean.abstract or site.parent)
    if eligible and (((site.by_name or site.resource) and named_match)
        or (site.kind == "import" and site.type == bean.type)
        or (not site.by_name and site.kind ~= "import" and not bean.excluded and site.type and qualified)) then
      matches[#matches + 1] = bean
      if bean.primary then primary[#primary + 1] = bean end
      if not bean.fallback then regular[#regular + 1] = bean end
      if site.resource and named_match or site.named and vim.tbl_contains(bean.names, site.id) then named[#named + 1] = bean end
    end
  end
  if site.by_name or site.kind == "import" then return matches end
  if site.resource and #named > 0 then return named end
  if #primary > 0 then return primary end
  if #regular == 1 then return regular end
  if #named == 1 then return named end
  return matches
end

local function notify_missing(profiles)
  local names = vim.tbl_keys(profiles)
  table.sort(names)
  vim.notify("Spring: No statically resolvable bean definitions or references for profiles: " .. table.concat(names, ", "),
    vim.log.levels.INFO)
end

local function destination(model, symbols, discovered, here, profiles, go, expired)
  local module, scope = bridge.module(model, here.file)
  if not module then return end
  local workspace, candidates = { model = model }
  if here.kind == "bean" then
    candidates = {}
    -- Only consumers that can see this Bean can inject it. Keep their upstream
    -- candidates too so ambiguous injections still resolve correctly.
    for name in pairs(model.modules) do
      local visible = visible_modules(workspace, name)
      if visible[module.name] then
        for dependency in pairs(visible) do candidates[dependency] = true end
      end
    end
  elseif go then
    candidates = visible_modules(workspace, module.name)
  end
  local dataset = collect(model, symbols, here.file, discovered, expired, candidates)
  if not dataset then return end
  dataset.visible = workspace.visible
  if not go and here.kind == "class_ref" then here = here.definition end
  here.module, here.test, here.named = module.name, scope == "test", here.field or module.parameter_names
  activate(dataset, profiles)
  bean_lookup(dataset, profiles)
  if not source.enabled(here.profiles, profiles) then return function() notify_missing(profiles) end end
  local visible = visible_modules(dataset, here.module)
  if not active(here, here, dataset, visible, profiles) then
    -- An XML file in a consuming module can activate a class in its upstream module.
    if here.kind ~= "bean" or not dataset.owners[here.owner] then return end
  end
  if go and (here.kind == "import" or here.kind == "class_ref") then
    local name = here.type:gsub("%$", ".")
    local classes = vim.tbl_filter(function(c) return allowed(here, c, visible, profiles) end, dataset.classes[name] or {})
    if #classes > 0 then return function() jump(vim.tbl_map(as_item, classes), "Spring — Bean classes") end end
    if here.kind == "class_ref" then return end
  end
  local selected = here.kind == "bean" and { here } or resolve(here, dataset, profiles)
  if #selected == 0 then return end
  if go and here.kind ~= "bean" then
    return function() jump(vim.tbl_map(as_item, selected), "Spring — Beans") end
  end
  local keys = {}
  for _, bean in ipairs(selected) do keys[location_key(bean)] = true end
  local refs = {}
  for _, site in ipairs(dataset.injections) do
    if expired() then return end
    local targets = resolve(site, dataset, profiles)
    if #targets == 1 and keys[location_key(targets[1])] then refs[#refs + 1] = as_item(site) end
  end
  if #refs == 0 then return end
  sort(refs)
  return function() require("user.navigation").usage_items("Spring — Bean usages", refs) end
end

function M.run(go, fallback)
  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].filetype
  if (ft ~= "java" and ft ~= "xml") or vim.bo[buf].buftype ~= "" then return false end
  if ft == "java" then
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf })
    local call = ok and node and node:parent()
    -- Spring facts cover declarations and registration/lookup arguments, never a call's method name.
    if call and call:type() == "method_invocation" then
      local name = call:field("name")[1]
      if name and name:equal(node) then return false end
    end
  end
  local ctx = require("user.lathe_live").context(buf)
  if not ctx or not ctx.ready then return false end
  local file = vim.api.nvim_buf_get_name(buf)
  if not vim.startswith(file, ctx.source .. "/") then return false end
  local pos, matches = origin(buf)
  local data = (ft == "xml" and xml or source).read(file)
  local at = data and source.at(data.facts, pos[1] - 1, pos[2])
  if not at then return false end

  local model = bridge.model(ctx)
  if not model then return false end
  local request = {}
  local deadline = vim.uv.hrtime() + navigation_timeout * 1000000
  requests[buf] = request
  local function pending() return requests[buf] == request and matches() end
  local function expired() return vim.uv.hrtime() >= deadline end
  local function complete(action)
    if requests[buf] ~= request then return end
    requests[buf] = nil
    if matches() then (not expired() and action or fallback)() end
  end
  local function scan(task, done)
    local slice_end
    local co = coroutine.create(function()
      return task(function()
        if not expired() and vim.uv.hrtime() >= slice_end then coroutine.yield() end
        return expired()
      end)
    end)
    local function step()
      if not pending() then return end
      if expired() then complete(); return end
      slice_end = vim.uv.hrtime() + 12000000
      local ok, result = coroutine.resume(co)
      if not ok then
        complete()
        vim.notify(tostring(result), vim.log.levels.WARN)
      elseif coroutine.status(co) == "dead" then
        done(result)
      else
        vim.defer_fn(step, 1)
      end
    end
    step()
  end
  vim.defer_fn(function() complete() end, navigation_timeout)
  local profiles = active_profiles(ctx)
  local function query_beans()
    discover(model, function(files)
      if not pending() then return end
      scan(function(checkpoint) return destination(model, {}, files, at, profiles, go, checkpoint) end, function(action)
        if action or expired() then complete(action); return end
        -- Spring Tools supplements the source search with whatever symbols are available.
        bridge.ready(ctx, function(err, state)
          if not pending() then return end
          if err or expired() then complete(); return end
          bridge.document(state, buf)
          local sent = state.rpc.request("workspace/symbol", { query = "@+" }, vim.schedule_wrap(function(error, symbols)
            if not pending() then return end
            if error or type(symbols) ~= "table" or #symbols == 0 then complete(); return end
            scan(function(checkpoint)
              return destination(model, symbols, files, at, profiles, go, checkpoint)
            end, complete)
          end))
          if not sent then complete() end
        end)
      end)
    end)
  end
  if not at.owner then
    query_beans()
  else
    -- Lombok can generate constructors in ordinary Java classes. Check XML and
    -- @Import registrations before claiming such a field as a Spring injection.
    discover(model, function(files)
      if not pending() then return end
      scan(function(checkpoint) return collect(model, {}, file, files, checkpoint) end, function(dataset)
        if not dataset then complete(); return end
        activate(dataset, profiles)
        if dataset.owners[at.owner] and not expired() then query_beans() else complete() end
      end)
    end, true)
  end
  return true
end

function M.setup()
  local group = vim.api.nvim_create_augroup("SpringNavigation", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", { group = group, pattern = { "*.java", "*.xml" }, callback = function(ev)
    bridge.saved(ev.buf)
  end })
  vim.api.nvim_create_autocmd("FileType", { group = group, pattern = "xml", callback = function(ev)
    local parsed = xml.read(vim.api.nvim_buf_get_name(ev.buf))
    if not parsed then return end
    require("user.lathe_live").ensure(ev.buf)
    for _, key in ipairs({ "gd", "gr" }) do
      vim.keymap.set("n", key, function()
        local function fallback() vim.notify("Spring XML: No statically resolvable bean under the cursor", vim.log.levels.INFO) end
        if not M.run(key == "gd", fallback) then fallback() end
      end, { buffer = ev.buf, desc = key == "gd" and "Go to Spring Bean" or "Find Spring Bean usages" })
    end
  end })
  vim.api.nvim_create_user_command("SpringProfiles", function(opts)
    local ctx = require("user.lathe_live").context(0)
    if not ctx then vim.notify("Spring: Open a Java file in a Lathe project first", vim.log.levels.WARN); return end
    if opts.bang then profile_sets[ctx.analysis] = nil
    elseif #opts.fargs > 0 then
      local selected = {}
      for name in table.concat(opts.fargs, ","):gmatch("[^,%s]+") do selected[name] = true end
      if next(selected) then profile_sets[ctx.analysis] = selected end
    end
    local names = vim.tbl_keys(active_profiles(ctx))
    table.sort(names)
    vim.notify("Spring Profiles · " .. table.concat(names, ", "))
  end, { nargs = "*", bang = true, desc = "Select Spring navigation profiles for this Lathe project" })
end

return M
