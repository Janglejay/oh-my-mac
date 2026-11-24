local M = {}
local accessor_anchors = {}
local bytecode_cache, bytecode_order = {}, {}

local function file_version(path)
  local s = vim.uv.fs_stat(path)
  if not s then return end
  return table.concat({ s.dev, s.ino, s.size, s.mtime.sec, s.mtime.nsec, s.ctime.sec, s.ctime.nsec }, ":")
end

-- Cache the disassembly, not the resolved symbol: Lathe still attributes every call.
local function disassemble(jdk, binary_path, class, callback)
  local javap = jdk .. "/bin/javap"
  local function versions()
    local binary, tool, modules = file_version(binary_path), file_version(javap), file_version(jdk .. "/lib/modules")
    return binary and tool and modules and table.concat({ binary, tool, modules }, "/") or nil
  end
  local key = table.concat({ javap, binary_path, class }, "\0")
  local cancelled, job
  vim.schedule(function()
    if cancelled then return end
    local version = versions()
    local hit = bytecode_cache[key]
    if version and hit and hit.version == version then
      callback(hit.output)
      return
    end
    local command = { javap, "-p", "-c" }
    vim.list_extend(command, class and { "-classpath", binary_path, class } or { binary_path })
    job = vim.system(command,
      { text = true, timeout = 5000 }, vim.schedule_wrap(function(output)
        job = nil
        if cancelled then return end
        if output.code == 0 and version and versions() == version and #(output.stdout or "") <= 256 * 1024 then
          if not bytecode_cache[key] then
            bytecode_order[#bytecode_order + 1] = key
            if #bytecode_order > 24 then bytecode_cache[table.remove(bytecode_order, 1)] = nil end
          end
          bytecode_cache[key] = { version = version, output = output }
        end
        callback(output)
      end))
  end)
  return function()
    cancelled = true
    if job then pcall(job.kill, job, 15) end
  end
end

local function node_text(node, source)
  return vim.treesitter.get_node_text(node, source)
end

local function hover_text(result)
  local contents = result and result.contents
  return type(contents) == "table" and contents.value or ""
end

function M.hover_artifact(result)
  return hover_text(result):match("%*source: ([%w_%.%-]+):([%w_%.%-]+):([%w_%.%+%-]+)%*")
end

local function signature_parameters(signature, method)
  local params = signature:match(" " .. vim.pesc(method) .. "%(([^()]*)%)")
  if not params or params:find("...", 1, true) then return end
  local types = vim.split(params:gsub("%b<>", ""), ",", { plain = true })
  for i, param in ipairs(types) do
    local without_name = vim.trim(param):gsub("%s+[%a_$][%w_$]*$", "")
    types[i] = without_name:gsub("%s+", ""):gsub("[%w_$.]+", function(name)
      return name:match("[^%.]+$") or name
    end)
  end
  return table.concat(types, ",")
end

local function file_location(uri, row, column)
  local pos = { line = row, character = column }
  return { uri = uri, range = { start = pos, ["end"] = pos } }
end

local function source_field(location, class, field)
  local uri = location and (location.uri or location.targetUri)
  if not uri or not vim.startswith(uri, "file:") then return end
  local path = vim.uri_to_fname(uri)
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "file" or stat.size > 1024 * 1024 then return end
  local code = table.concat(vim.fn.readfile(path), "\n")
  local range = location.targetSelectionRange or location.range
  if not range then return end
  local tree = vim.treesitter.get_string_parser(code, "java"):parse()[1]
  local row = range.start.line
  local node = tree:root():named_descendant_for_range(row, 0, row, 0)
  -- Library positions are sometimes before the declaration's indentation.
  local names = vim.treesitter.query.parse("java", "(class_declaration name: (identifier) @class)")
  for _, name in names:iter_captures(tree:root(), code, row, row + 1) do
    if node_text(name, code) == class then node = name:parent(); break end
  end
  if not node or node:type() ~= "class_declaration" then return end
  local name, body = node:field("name")[1], node:field("body")[1]
  if not name or not body or node_text(name, code) ~= class then return end
  for child in body:iter_children() do
    if child:type() == "field_declaration" then
      for _, declarator in ipairs(child:field("declarator")) do
        local id = declarator:field("name")[1]
        if id and node_text(id, code) == field then
          local r, c = id:start()
          return file_location(uri, r, c)
        end
      end
    end
  end
end

local function find_call_usages(anchors, title)
  local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local items, seen, pending, incomplete = {}, {}, 0, false
  local function complete(encoding, result, failed)
    vim.schedule(function()
      pending = pending - 1
      incomplete = incomplete or failed
      if vim.api.nvim_get_current_win() ~= win or vim.api.nvim_get_current_buf() ~= buf
          or not vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor) then return end
      for _, loc in ipairs(vim.lsp.util.locations_to_items(result, encoding)) do
        local key = ("%s:%d:%d"):format(loc.filename, loc.lnum, loc.col)
        if not seen[key] then
          seen[key] = true
          items[#items + 1] = {
            file = loc.filename, pos = { loc.lnum, loc.col - 1 },
            text = ("%s:%d  %s"):format(vim.fn.fnamemodify(loc.filename, ":t"), loc.lnum, loc.text or ""),
          }
        end
      end
      if pending ~= 0 then return end
      if incomplete then title = title .. " · Partial LSP results" end
      if #items > 0 then require("user.navigation").usage_items(title, items)
      else vim.notify("Lathe: The current index returned no references", vim.log.levels.WARN) end
    end)
  end
  for _, anchor in pairs(anchors) do
    local b, client = anchor.bufnr, vim.lsp.get_client_by_id(anchor.client_id)
    if client and not client:is_stopped() and vim.api.nvim_buf_is_loaded(b) and vim.lsp.buf_is_attached(b, client.id)
        and vim.api.nvim_buf_get_changedtick(b) == anchor.changedtick then
      local sent = client:request("textDocument/references", anchor.params, function(err, result)
        local locations = not err and type(result) == "table" and result or {}
        local pos = anchor.params.position
        local already_present = vim.iter(locations):any(function(loc)
          return loc.uri == anchor.params.textDocument.uri and loc.range.start.line == pos.line
            and loc.range.start.character <= pos.character and loc.range["end"].character >= pos.character
        end)
        if not already_present then
          -- The call was already resolved before the jump; unsaved calls may be absent from the index.
          locations[#locations + 1] = file_location(anchor.params.textDocument.uri, pos.line, pos.character)
        end
        complete(client.offset_encoding, locations, err ~= nil)
      end, b)
      if sent then pending = pending + 1 end
    end
  end
  return pending > 0
end

function M.references_at_field()
  local by_line = accessor_anchors[vim.uri_from_bufnr(0)]
  if not by_line then return false end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  for _, slot in pairs(by_line[row - 1] or {}) do
    if col >= slot.column and col < slot.column + #slot.field
        and vim.api.nvim_get_current_line():sub(slot.column + 1, slot.column + #slot.field) == slot.field then
      return find_call_usages(slot.anchors, "Find Usages — Verified Accessors of " .. slot.field)
    end
  end
  return false
end

local function show_dependency(class, lines, pos, anchor, label, java, related)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if java then
    -- The preview has no project file for Java filetype hooks to attach to.
    vim.api.nvim_buf_call(buf, function() vim.cmd("noautocmd setlocal filetype=java") end)
    pcall(vim.treesitter.start, buf, "java")
  end
  vim.bo[buf].modifiable, vim.bo[buf].readonly = false, true
  vim.cmd("normal! m'")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, pos)
  vim.cmd("normal! zz")
  local function references(target)
    if not target then
      vim.notify("Place the cursor on the resolved declaration to find references", vim.log.levels.WARN)
    elseif not find_call_usages({ target }, "Find Usages — " .. target.symbol) then
      vim.notify("The reference lookup location changed. Reopen the declaration from a call site in the project", vim.log.levels.WARN)
    end
  end
  local function target_at_cursor(exact)
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local function matches(position, symbol)
      return position[1] == row and (not java
        or (col >= position[2] and col < position[2] + #symbol:gsub("%(%)$", "")))
    end
    if matches(pos, anchor.symbol) then return anchor end
    for _, target in ipairs(related or {}) do
      if matches(target.pos, target.anchor.symbol) then return target.anchor end
    end
    if not exact and row == pos[1] then return anchor end
  end
  vim.keymap.set("n", "gr", function()
    references(target_at_cursor(false))
  end, { buffer = buf, nowait = true, desc = "Find usages of the resolved JAR symbol" })
  vim.keymap.set("n", "gd", function()
    local target = target_at_cursor(true)
    if target then references(target) else vim.cmd("normal! gd") end
  end, { buffer = buf, nowait = true, desc = "Find usages at a dependency declaration" })
  vim.notify(label .. " · " .. class, vim.log.levels.INFO)
end

local function java_position(code, root, class, member, signature)
  local owner = root
  local classes = vim.split(class:match("[^.]+$"), "$", { plain = true })
  local class_name
  for _, name in ipairs(classes) do
    local declaration
    for child in owner:iter_children() do
      local id = child:field("name")[1]
      if child:field("body")[1] and child:type():match("_declaration$")
          and id and node_text(id, code) == name then
        declaration, class_name = child, id
        break
      end
    end
    if not declaration then return end
    owner = declaration:field("body")[1]
  end

  local target = class_name
  if member then
    target = nil
    local function scan(body)
      for child in body:iter_children() do
        if child:type() == "enum_body_declarations" then
          scan(child)
        else
          local id = child:field("name")[1]
          if id and node_text(id, code) == member then
            if signature and child:type() == "method_declaration" then
              local parameters = child:field("parameters")[1]
              local declaration = " " .. member .. node_text(parameters, code)
              if signature_parameters(declaration, member) == signature then
                target = target == nil and id or false
              end
            elseif not signature and child:type() == "enum_constant" then
              target = id
            end
          end
        end
      end
    end
    scan(owner)
  end
  if not target then return end
  local row, col = target:start()
  return { row + 1, col }
end

-- Read the same artifact version first. CFR reads one class from the local JAR.
local function open_java(jdk, jar, class, member, signature, anchor, done, fallback, related)
  local name = class:match("^[^$]+")
  local sources = jar:gsub("%.jar$", "-sources.jar")
  local cfr = vim.fs.joinpath(vim.fn.stdpath("data"), "tools", "cfr-0.152.jar")
  local cancelled, job
  local function run(argv, label, miss)
    local ok, process = pcall(vim.system, argv, { text = true, timeout = 5000 }, vim.schedule_wrap(function(output)
      job = nil
      if cancelled then return end
      local code = output.stdout or ""
      if output.code == 0 and #code > 0 and #code <= 1024 * 1024 then
        local parsed, pos, targets = pcall(function()
          local tree = vim.treesitter.get_string_parser(code, "java"):parse()[1]
          if not tree then return end
          local root = tree:root()
          local position = java_position(code, root, class, member, signature)
          if not position then return end
          local matches = {}
          for _, entry in ipairs(related or {}) do
            local related_pos = java_position(code, root, class, entry.member)
            if related_pos then matches[#matches + 1] = { pos = related_pos, anchor = entry.anchor } end
          end
          return position, matches
        end)
        if parsed and pos then
          local lines = vim.split(code:gsub("\n$", ""), "\n", { plain = true })
          done(nil, function() show_dependency(class, lines, pos, anchor, label, true, targets) end)
          return
        end
      end
      miss()
    end))
    if ok then job = process else miss() end
  end
  local function decompile()
    if vim.fn.filereadable(cfr) == 1 then
      run({ jdk .. "/bin/java", "-Xmx256m", "-jar", cfr, name, "--extraclasspath", jar, "--silent", "true" },
        "Decompiled Java", fallback)
    else
      fallback()
    end
  end
  vim.schedule(function()
    if cancelled then return end
    if vim.fn.filereadable(sources) == 1 then
      run({ "unzip", "-p", sources, name:gsub("%.", "/") .. ".java" }, "JAR source", decompile)
    else
      decompile()
    end
  end)
  return function()
    cancelled = true
    if job then pcall(job.kill, job, 15) end
  end
end

local function binary_jar(repository, group, artifact, version)
  if group:find("..", 1, true) or group:match("^%.") or group:match("%.$")
      or artifact == "." or artifact == ".." or version == "." or version == ".." then return end
  local dir = vim.fs.joinpath(repository, group:gsub("%.", "/"), artifact, version)
  if not vim.uv.fs_stat(dir) then return end
  local prefix, jar = artifact .. "-" .. version, nil
  for name, kind in vim.fs.dir(dir) do
    if kind == "file" and (name == prefix .. ".jar" or vim.startswith(name, prefix .. "-"))
        and vim.endswith(name, ".jar") and not name:match("%-sources%.jar$") and not name:match("%-javadoc%.jar$")
        and not name:match("%-tests%.jar$") then
      if jar then return end -- Maven coordinates alone do not disambiguate classifier variants.
      jar = vim.fs.joinpath(dir, name)
    end
  end
  return jar
end

function M.accessor_field(lines, row, method, arity)
  if not (lines[row + 2] or ""):match("^%s+0: aload_0%s*$") then return end
  if arity == 0 and (method:match("^get%u") or method:match("^is%u"))
      and (lines[row + 4] or ""):match("^%s+4: [ailfd]return%s*$") then
    return (lines[row + 3] or ""):match("^%s+1: getfield%s+#%d+%s+// Field ([%w_$]+):")
  end
  if arity == 1 and method:match("^set%u") and (lines[row + 3] or ""):match("^%s+1: [ailfd]load_1%s*$")
      and ((lines[row + 5] or ""):match("^%s+5: return%s*$")
        or ((lines[row + 5] or ""):match("^%s+5: aload_0%s*$")
          and (lines[row + 6] or ""):match("^%s+6: areturn%s*$"))) then
    return (lines[row + 4] or ""):match("^%s+2: putfield%s+#%d+%s+// Field ([%w_$]+):")
  end
end

local function bytecode_method(output, method, signature)
  if output.code ~= 0 then return end
  local lines = vim.split(vim.trim(output.stdout or ""), "\n", { plain = true })
  local target
  for i, line in ipairs(lines) do
    local arguments = line:match("^  %S.*%;$") and signature_parameters(line, method)
    if arguments == signature then
      if target then return end -- Equal simple names can still come from different packages.
      target = i
    end
  end
  if target then return lines, target end
end

local function accessor_location(location, class, field, method, anchor)
  local ok, answer = pcall(source_field, location, class:match("[^.$]+$"), field)
  if not ok or not answer then return end
  local start = answer.range.start
  local by_line = accessor_anchors[answer.uri] or {}
  local by_column = by_line[start.line] or {}
  local slot = by_column[start.character] or { field = field, column = start.character, anchors = {} }
  slot.anchors[method] = anchor
  by_column[start.character], by_line[start.line], accessor_anchors[answer.uri] = slot, by_column, by_line
  return answer
end

local function project_class_file(client, location, class)
  local ctx = require("user.lathe_live").from_client(client.id)
  local uri = location and (location.uri or location.targetUri)
  if not ctx or ctx.status ~= "ready" or not uri or not vim.startswith(uri, "file:") then return end
  local path = vim.uri_to_fname(uri)
  if not vim.startswith(path, ctx.source .. "/") then return end
  local module = vim.fs.root(path, "pom.xml")
  if not module or (module ~= ctx.source and not vim.startswith(module, ctx.source .. "/")) then return end
  local binary = vim.fs.joinpath(ctx.analysis, ".lathe", module:sub(#ctx.source + 2), "classes",
    class:gsub("%.", "/") .. ".class")
  local source_version, binary_version = file_version(path), file_version(binary)
  if not source_version or not binary_version then return end
  local function current()
    local buf = vim.fn.bufnr(path)
    return ctx.status == "ready" and (buf == -1 or not vim.bo[buf].modified)
      and file_version(path) == source_version and file_version(binary) == binary_version
  end
  -- Only use the captured class if the original source still matches the build input.
  local built = vim.fs.joinpath(ctx.build, path:sub(#ctx.source + 2))
  local ok, matches = pcall(function()
    return current() and vim.deep_equal(vim.fn.readfile(path, "b"), vim.fn.readfile(built, "b"))
  end)
  if ok and matches then return binary, current end
end

local function imported_class(node, buf, name)
  if node:type() ~= "identifier" and node:type() ~= "type_identifier" then return end
  name = name or node_text(node, buf)
  local root = node
  while root:parent() do root = root:parent() end
  for child in root:iter_children() do
    if child:type() == "import_declaration" then
      local path = node_text(child, buf):match("^import%s+([%w_$%.]+)%s*;$")
      if path and vim.endswith(path, "." .. name) then
        local qualified = child:named_child(0)
        return path, name, qualified and qualified:field("name")[1]
      end
    end
  end
end

local function position_at(params, node, bufnr, client)
  local row, col = node:start()
  local text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  return { textDocument = params.textDocument, position = {
    line = row, character = vim.str_utfindex(text, client.offset_encoding, col),
  } }
end

local function related_reference(anchor, client, node, member)
  local params = position_at(anchor.params, node, anchor.bufnr, client)
  params.context = anchor.params.context
  return {
    member = member,
    anchor = vim.tbl_extend("force", anchor, { params = params, symbol = node_text(node, anchor.bufnr) }),
  }
end

local function resolve_class(client, node, bufnr, winid, done)
  local class, name = imported_class(node, bufnr)
  local params = vim.lsp.util.make_position_params(winid, client.offset_encoding)
  local hover_params, member, field_access = params, nil, node:parent()
  local qualifier, field
  if field_access and field_access:type() == "field_access" then
    qualifier, field = field_access:field("object")[1], field_access:field("field")[1]
    if qualifier and field and (node:equal(field) or node:equal(qualifier)) then
      class, name = imported_class(qualifier, bufnr)
      if node:equal(field) then member = node_text(field, bufnr) end
      hover_params = position_at(params, field, bufnr, client)
    end
  end
  if not class then return end
  local anchor = { bufnr = bufnr, client_id = client.id, symbol = member or name,
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    params = vim.tbl_extend("force", params, { context = { includeDeclaration = false } }) }
  local cancelled, cancel_preview = false, nil
  local sent, id = client:request("textDocument/hover", hover_params, function(err, result)
    if cancelled then return end
    local group, artifact, version = M.hover_artifact(result)
    local declaration = hover_text(result):match("```java\n([^\n]+)\n```") or ""
    local kind, selected = declaration:match("^([%a@]+)%s+([%w_$]+)")
    local attributed = selected == name and vim.tbl_contains({ "class", "interface", "enum", "record", "@interface" }, kind)
    if hover_params ~= params then
      local owner, constant = declaration:match("^([%w_.$]+)%s+([%w_$]+)$")
      attributed = owner == class and constant == node_text(field, bufnr)
    end
    if err or not group or not attributed then
      done()
      return
    end
    local options = require("user.lathe_config")
    local jar = binary_jar(vim.fs.joinpath(options.resources, "vim-trial", "m2"), group, artifact, version)
    if not jar then done(); return end
    local function show_binary()
      cancel_preview = disassemble(options.runtime_jdk, jar, class, function(output)
        cancel_preview = nil
        if cancelled then return end
        if output.code ~= 0 then done(); return end
        local lines = vim.split(vim.trim(output.stdout or ""), "\n", { plain = true })
        for row, line in ipairs(lines) do
          local matched = not member and line:match("%s" .. vim.pesc(class) .. "[%s<{]")
            or member and line:match("^  .* static final " .. vim.pesc(class) .. " " .. vim.pesc(member) .. ";$")
          if matched then
            done(nil, function() show_dependency(class, lines, { row, 0 }, anchor, "JAR bytecode") end)
            return
          end
        end
        done()
      end)
    end
    local related
    if hover_params ~= params then
      related = { member and related_reference(anchor, client, qualifier)
        or related_reference(anchor, client, field, node_text(field, bufnr)) }
    end
    cancel_preview = open_java(options.runtime_jdk, jar, class, member, nil, anchor, done, show_binary, related)
  end, bufnr)
  if not sent then return end
  return function()
    cancelled = true
    client:cancel_request(id)
    if cancel_preview then cancel_preview() end
  end
end

-- Use the attributed receiver and artifact from Lathe. Follow an accessor back
-- to a field only when its bytecode proves the direct read or write.
function M.resolve(client, bufnr, winid, done)
  if client.name ~= "lathe" or vim.bo[bufnr].filetype ~= "java" then return end
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
  local call = ok and node and node:parent()
  if not call then return end
  if call:type() ~= "method_invocation" then return resolve_class(client, node, bufnr, winid, done) end
  local member = call:field("name")[1]
  local object, args = call:field("object")[1], call:field("arguments")[1]
  if not member or not member:equal(node) or not object or not args then return end
  local receiver = object:type() == "field_access" and object:field("field")[1] or object
  if not receiver or receiver:type() ~= "identifier" then return end
  local method, receiver_name = node_text(member, bufnr), node_text(receiver, bufnr)
  local arity = 0
  for child in args:iter_children() do
    if child:named() and not child:extra() then arity = arity + 1 end
  end
  local params = vim.lsp.util.make_position_params(winid, client.offset_encoding)
  local anchor = { bufnr = bufnr, client_id = client.id, symbol = method .. "()", changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    params = vim.tbl_extend("force", params, { context = { includeDeclaration = false } }) }
  local at_receiver = position_at(params, receiver, bufnr, client)
  local cancelled, ids, cancel_preview = false, {}, nil
  local function request(name, at, callback)
    local sent, id = client:request("textDocument/" .. name, at, function(err, result)
      if not cancelled then
        if err then callback(nil) else callback(result) end
      end
    end, bufnr)
    if sent then ids[#ids + 1] = id else callback(nil) end
  end
  request("hover", params, function(result)
    local hover = hover_text(result)
    local group, artifact, version = M.hover_artifact(result)
    local selected = signature_parameters(hover:match("```java\n([^\n]+)\n```") or "", method)
    if not selected or (not group and (arity ~= 0 or not (method:match("^get%u") or method:match("^is%u")))) then
      done()
      return
    end
    request("hover", at_receiver, function(owner)
      local signature = hover_text(owner):match("```java\n([^\n]+)\n```") or ""
      local class = signature:match("^([%w_%.%$]+)%s+" .. vim.pesc(receiver_name) .. "$")
      if not class or not class:find(".", 1, true) then done(); return end
      local options = require("user.lathe_config")
      if not group then
        request("typeDefinition", at_receiver, function(locations)
          local location = locations and (locations.uri and locations or locations[1])
          local binary, current = project_class_file(client, location, class)
          if not binary then done(); return end
          cancel_preview = disassemble(options.runtime_jdk, binary, nil, function(output)
            if cancelled then return end
            local lines, row = bytecode_method(output, method, selected)
            local field = row and current() and M.accessor_field(lines, row, method, arity)
            done(field and accessor_location(location, class, field, method, anchor) or nil)
          end)
        end)
        return
      end
      local jar = binary_jar(vim.fs.joinpath(options.resources, "vim-trial", "m2"), group, artifact, version)
      if not jar then done(); return end
      local related
      local qualifier = object:type() == "field_access" and object:field("object")[1]
      if qualifier and imported_class(qualifier, bufnr) == class then
        related = { related_reference(anchor, client, qualifier), related_reference(anchor, client, receiver, receiver_name) }
      else
        local imported, _, import_name = imported_class(member, bufnr, class:match("[^.$]+$"))
        if import_name and imported == class:gsub("%$", ".") then
          related = { related_reference(anchor, client, import_name) }
        end
      end
      cancel_preview = disassemble(options.runtime_jdk, jar, class, function(output)
          cancel_preview = nil
          if cancelled then return end
          local lines, target = bytecode_method(output, method, selected)
          if not target then done(); return end
          local field = M.accessor_field(lines, target, method, arity)
          local function show_java()
            cancel_preview = open_java(options.runtime_jdk, jar, class, method, selected, anchor, done, function()
              done(nil, function() show_dependency(class, lines, { target, 0 }, anchor, "JAR bytecode") end)
            end, related)
          end
          if not field then show_java(); return end
          request("typeDefinition", at_receiver, function(locations)
            local location = locations and (locations.uri and locations or locations[1])
            local answer = accessor_location(location, class, field, method, anchor)
            if answer then done(answer) else show_java() end
          end)
        end)
    end)
  end)
  return function()
    cancelled = true
    for _, id in ipairs(ids) do client:cancel_request(id) end
    if cancel_preview then cancel_preview() end
  end
end

return M
