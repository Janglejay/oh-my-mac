local M = {}
local api, uv = vim.api, vim.uv
local timers = {}

local function snapshot(buf)
  if not api.nvim_buf_is_loaded(buf) then return end
  local opts = vim.bo[buf]
  local path = api.nvim_buf_get_name(buf)
  if path == "" or opts.buftype ~= "" or not opts.modified or opts.binary or opts.endoffile
      or (opts.fileencoding ~= "" and opts.fileencoding ~= "utf-8") then return end

  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  for _, line in ipairs(lines) do
    if line:find("\n", 1, true) or line:find("\0", 1, true) then return end
  end
  local eol = ({ unix = "\n", dos = "\r\n", mac = "\r" })[opts.fileformat]
  local bom = opts.bomb and "\239\187\191" or ""
  local text = bom .. table.concat(lines, eol) .. (opts.endofline and eol or "")
  local empty = #lines == 1 and lines[1] == "" and not opts.bomb
  return path, text, empty
end

local function same_file(a, b)
  return b and a.dev == b.dev and a.ino == b.ino and a.size == b.size
    and a.mtime.sec == b.mtime.sec and a.mtime.nsec == b.mtime.nsec
    and a.ctime.sec == b.ctime.sec and a.ctime.nsec == b.ctime.nsec
end

local function clear_if_saved(buf)
  local path, text, empty = snapshot(buf)
  if not path then return end
  local tick = api.nvim_buf_get_changedtick(buf)
  local stat = uv.fs_stat(path)
  if not stat or stat.type ~= "file" or (stat.size ~= #text and not (stat.size == 0 and empty)) then return end

  uv.fs_open(path, "r", 0, function(err, fd)
    if err then return end
    if not same_file(stat, uv.fs_fstat(fd)) then uv.fs_close(fd); return end
    local function compare(read_err, bytes)
      local stable = same_file(stat, uv.fs_fstat(fd))
      uv.fs_close(fd)
      if read_err or not stable or (bytes ~= text and not (bytes == "" and empty)) then return end
      vim.schedule(function()
        if not api.nvim_buf_is_loaded(buf) or api.nvim_buf_get_changedtick(buf) ~= tick then return end
        local current_path, current_text, current_empty = snapshot(buf)
        if current_path == path and current_text == text and current_empty == empty and same_file(stat, uv.fs_stat(path)) then
          vim.bo[buf].modified = false
          vim.cmd.redrawtabline()
        end
      end)
    end
    if stat.size == 0 then compare(nil, "") else uv.fs_read(fd, stat.size, 0, compare) end
  end)
end

function M.setup()
  local group = api.nvim_create_augroup("SavedBufferState", { clear = true })
  local function queue(args)
    local buf = args.buf
    if not api.nvim_buf_is_loaded(buf) or not vim.bo[buf].modified or vim.bo[buf].buftype ~= "" then return end
    local previous = timers[buf]
    if previous and not previous:is_closing() then previous:close() end
    local timer
    timer = vim.defer_fn(function()
      if timers[buf] ~= timer then return end
      timers[buf] = nil
      clear_if_saved(buf)
    end, 160)
    timers[buf] = timer
  end
  api.nvim_create_autocmd({ "BufEnter", "InsertLeave", "TextChanged", "TextChangedI", "TextChangedP" }, {
    group = group,
    callback = queue,
  })
  api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = { "fileformat", "fileencoding", "binary", "bomb", "endofline", "endoffile" },
    callback = queue,
  })
  for _, buf in ipairs(api.nvim_list_bufs()) do queue({ buf = buf }) end
end

return M
