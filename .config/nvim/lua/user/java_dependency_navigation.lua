local M = {}
local accessor_anchors = {}

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
      else vim.notify("Lathe: 当前索引未能返回引用", vim.log.levels.WARN) end
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

local function show_bytecode(class, lines, row, anchor)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable, vim.bo[buf].readonly = false, true
  vim.cmd("normal! m'")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  vim.keymap.set("n", "gr", function()
    if vim.api.nvim_win_get_cursor(0)[1] ~= row then
      vim.notify("请在已定位的声明行查询引用", vim.log.levels.WARN)
    elseif not find_call_usages({ anchor }, "Find Usages — " .. anchor.symbol) then
      vim.notify("引用查询位置已变化，请从项目调用处重新跳转", vim.log.levels.WARN)
    end
  end, { buffer = buf, nowait = true, desc = "Find usages of the resolved JAR symbol" })
  vim.notify("JAR bytecode · " .. class, vim.log.levels.INFO)
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

local function imported_class(node, buf)
  if node:type() ~= "identifier" and node:type() ~= "type_identifier" then return end
  local name = node_text(node, buf)
  local root = node
  while root:parent() do root = root:parent() end
  for child in root:iter_children() do
    if child:type() == "import_declaration" then
      local path = node_text(child, buf):match("^import%s+([%w_$%.]+)%s*;$")
      if path and vim.endswith(path, "." .. name) then return path, name end
    end
  end
end

local function resolve_class(client, node, bufnr, winid, done)
  local class, name = imported_class(node, bufnr)
  if not class then return end
  local params = vim.lsp.util.make_position_params(winid, client.offset_encoding)
  local anchor = { bufnr = bufnr, client_id = client.id, symbol = name,
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    params = vim.tbl_extend("force", params, { context = { includeDeclaration = false } }) }
  local cancelled, job = false, nil
  local sent, id = client:request("textDocument/hover", params, function(err, result)
    if cancelled then return end
    local group, artifact, version = M.hover_artifact(result)
    local declaration = hover_text(result):match("```java\n([^\n]+)\n```") or ""
    local kind, selected = declaration:match("^([%a@]+)%s+([%w_$]+)")
    if err or not group or selected ~= name or not vim.tbl_contains({ "class", "interface", "enum", "record", "@interface" }, kind) then
      done()
      return
    end
    local options = require("user.lathe_config")
    local jar = binary_jar(vim.fs.joinpath(options.resources, "vim-trial", "m2"), group, artifact, version)
    if not jar then done(); return end
    job = vim.system({ options.runtime_jdk .. "/bin/javap", "-p", "-c", "-classpath", jar, class },
      { text = true, timeout = 5000 }, vim.schedule_wrap(function(output)
        job = nil
        if cancelled then return end
        if output.code ~= 0 then done(); return end
        local lines = vim.split(vim.trim(output.stdout or ""), "\n", { plain = true })
        for row, line in ipairs(lines) do
          if line:match("%s" .. vim.pesc(class) .. "[%s<{]") then
            done(nil, function() show_bytecode(class, lines, row, anchor) end)
            return
          end
        end
        done()
      end))
  end, bufnr)
  if not sent then return end
  return function()
    cancelled = true
    client:cancel_request(id)
    if job then pcall(job.kill, job, 15) end
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
  if not member or not member:equal(node) or not object or object:type() ~= "identifier" or not args then return end
  local method, receiver = node_text(member, bufnr), node_text(object, bufnr)
  local arity = 0
  for child in args:iter_children() do
    if child:named() and not child:extra() then arity = arity + 1 end
  end
  local params = vim.lsp.util.make_position_params(winid, client.offset_encoding)
  local anchor = { bufnr = bufnr, client_id = client.id, symbol = method .. "()", changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    params = vim.tbl_extend("force", params, { context = { includeDeclaration = false } }) }
  local row, col = object:start()
  local text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  local at_receiver = { textDocument = params.textDocument, position = {
    line = row, character = vim.str_utfindex(text, client.offset_encoding, col),
  } }
  local cancelled, ids, job = false, {}, nil
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
    if not group or not selected then done(); return end
    request("hover", at_receiver, function(owner)
      local signature = hover_text(owner):match("```java\n([^\n]+)\n```") or ""
      local class = signature:match("^([%w_%.%$]+)%s+" .. vim.pesc(receiver) .. "$")
      if not class or not class:find(".", 1, true) then done(); return end
      local options = require("user.lathe_config")
      local jar = binary_jar(vim.fs.joinpath(options.resources, "vim-trial", "m2"), group, artifact, version)
      if not jar then done(); return end
      job = vim.system({ options.runtime_jdk .. "/bin/javap", "-p", "-c", "-classpath", jar, class },
        { text = true, timeout = 5000 }, vim.schedule_wrap(function(output)
          job = nil
          if cancelled then return end
          if output.code ~= 0 then done(); return end
          local lines = vim.split(vim.trim(output.stdout or ""), "\n", { plain = true })
          local target
          for i, line in ipairs(lines) do
            local arguments = line:match("^  %S.*%;$") and signature_parameters(line, method)
            if arguments == selected then
              if target then done(); return end -- Equal simple names can still come from different packages.
              target = i
            end
          end
          if not target then done(); return end
          local field = M.accessor_field(lines, target, method, arity)
          local function show_binary() show_bytecode(class, lines, target, anchor) end
          if not field then done(nil, show_binary); return end
          request("typeDefinition", at_receiver, function(locations)
            local location = locations and (locations.uri and locations or locations[1])
            local source_ok, answer = pcall(source_field, location, class:match("[^%.%$]+$"), field)
            if source_ok and answer then
              local start = answer.range.start
              local by_line = accessor_anchors[answer.uri] or {}
              local by_column = by_line[start.line] or {}
              local slot = by_column[start.character] or { field = field, column = start.character, anchors = {} }
              slot.anchors[method] = anchor
              by_column[start.character], by_line[start.line], accessor_anchors[answer.uri] = slot, by_column, by_line
              done(answer)
              return
            end
            done(nil, show_binary)
          end)
        end))
    end)
  end)
  return function()
    cancelled = true
    for _, id in ipairs(ids) do client:cancel_request(id) end
    if job then pcall(job.kill, job, 15) end
  end
end

return M
