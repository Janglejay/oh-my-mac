local M = {}
local pending = {}

local function argument_at(loc, class, arity, slot)
  local path = loc.filename
  if not path or not vim.endswith(path, ".java") then return end
  local buf = vim.fn.bufnr(path)
  local text
  local ok, root = pcall(function()
    if buf > 0 and vim.api.nvim_buf_is_loaded(buf) then
      text = buf
      return vim.treesitter.get_parser(buf, "java"):parse()[1]:root()
    end
    text = table.concat(vim.fn.readfile(path), "\n")
    return vim.treesitter.get_string_parser(text, "java"):parse()[1]:root()
  end)
  if not ok then return end

  local row, col = loc.lnum - 1, loc.col - 1
  local node = root:named_descendant_for_range(row, col, row, col)
  while node and node:type() ~= "object_creation_expression" do node = node:parent() end
  if not node then return end
  local name, args = node:field("type")[1], node:field("arguments")[1]
  if not name or not args then return end
  if name:type() == "generic_type" then name = name:named_child(0) end
  if name and name:type() == "scoped_type_identifier" then name = name:named_child(name:named_child_count() - 1) end
  if not name or vim.treesitter.get_node_text(name, text) ~= class then return end
  local r, c, er, ec = name:range()
  if row ~= r or row ~= er or col < c or col >= ec then return end

  local parameters = {}
  for child in args:iter_children() do
    if child:named() and not child:extra() then parameters[#parameters + 1] = child end
  end
  if #parameters ~= arity then return end
  local param = parameters[slot]
  local line, byte = param:start()
  local expression = vim.trim((vim.treesitter.get_node_text(param, text):gsub("%s+", " ")))
  return { file = path, pos = { line + 1, byte },
    text = ("%s:%d  %s  ·  构造器参数 %d"):format(vim.fs.basename(path), line + 1, expression, slot) }
end

function M.at_field(done)
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf })
  local parent = ok and node and node:parent()
  local name = parent and parent:type() == "variable_declarator" and parent:field("name")[1]
  if not name or not name:equal(node) or parent:parent():type() ~= "field_declaration" then return false end
  local client = vim.lsp.get_clients({ bufnr = buf, name = "lathe", method = "textDocument/references" })[1]
  if not client then return false end

  local data = require("user.spring_source").read(vim.api.nvim_buf_get_name(buf))
  local row, col = name:start()
  local owner, index
  for _, class in pairs(data and data.classes or {}) do
    for slot, span in ipairs(class.constructor_fields or {}) do
      if row == span[1] and col == span[2] then owner, index = class, slot; break end
    end
    if owner then break end
  end
  if not owner then return false end

  if pending[buf] then pending[buf]() end
  local cursor, tick = vim.api.nvim_win_get_cursor(win), vim.api.nvim_buf_get_changedtick(buf)
  local line = vim.api.nvim_buf_get_lines(buf, owner.pos[1] - 1, owner.pos[1], false)[1]
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
    position = { line = owner.pos[1] - 1, character = vim.str_utfindex(line, client.offset_encoding, owner.pos[2], false) },
    context = { includeDeclaration = false },
  }
  local timer, request
  local function cancel()
    pending[buf] = nil
    if timer and not timer:is_closing() then timer:stop(); timer:close() end
    if request then client:cancel_request(request) end
  end
  local function finish(extra)
    if pending[buf] ~= cancel then return end
    cancel()
    if vim.api.nvim_get_current_buf() == buf and vim.api.nvim_get_current_win() == win
        and vim.api.nvim_buf_get_changedtick(buf) == tick and vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor) then
      done(extra)
    end
  end
  pending[buf] = cancel
  local sent
  sent, request = client:request("textDocument/references", params, vim.schedule_wrap(function(err, result)
    if pending[buf] ~= cancel then return end
    request = nil
    local items, seen = {}, {}
    if not err and type(result) == "table" then
      for _, loc in ipairs(vim.lsp.util.locations_to_items(result, client.offset_encoding)) do
        local item = argument_at(loc, owner.id, #owner.constructor_fields, index)
        if item then
          local key = ("%s:%d:%d"):format(item.file, item.pos[1], item.pos[2])
          if not seen[key] then seen[key] = true; items[#items + 1] = item end
        end
      end
    end
    finish(items)
  end), buf)
  if not sent then cancel(); return false end
  timer = vim.defer_fn(function() finish() end, 10000)
  return true
end

return M
