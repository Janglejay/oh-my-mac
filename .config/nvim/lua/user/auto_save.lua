local M = {}
local api, uv = vim.api, vim.uv
local pending, stamps = {}, {}

local function stamp(path)
  local s = uv.fs_stat(path)
  if not s then return "missing" end
  return table.concat({ s.dev, s.ino, s.size, s.mtime.sec, s.mtime.nsec, s.ctime.sec, s.ctime.nsec }, ":")
end

local function merge_result(buf)
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  if not lifecycle then return false end
  for _, tab in ipairs(api.nvim_list_tabpages()) do
    local session = lifecycle.get_session(tab)
    if session and (session.merge or next(session.conflict_files or {})) and session.result_bufnr == buf then
      return true
    end
  end
  return false
end

local function eligible(buf)
  if not api.nvim_buf_is_valid(buf) or not api.nvim_buf_is_loaded(buf) then return false end
  local opt = vim.bo[buf]
  local name = api.nvim_buf_get_name(buf)
  return name ~= "" and not name:match("^%a[%w+.-]*://") and opt.buftype == ""
    and opt.modifiable and not opt.readonly and opt.modified and not merge_result(buf)
end

local function save(buf)
  if not eligible(buf) then return true end
  local name = api.nvim_buf_get_name(buf)
  if stamps[buf] and stamps[buf] ~= stamp(name) then
    vim.notify("Auto-save paused: the file changed on disk. Review " .. name, vim.log.levels.WARN)
    return false
  end
  local ok, err = pcall(api.nvim_buf_call, buf, function() vim.cmd("silent update") end)
  if not ok then
    vim.notify("Auto-save failed: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  return not vim.bo[buf].modified
end

function M.flush()
  local ok = true
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if not save(buf) then ok = false end
  end
  return ok
end

function M.setup()
  local group = api.nvim_create_augroup("UserAutoSave", { clear = true })
  api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "FileChangedShellPost", "BufNewFile" }, {
    group = group,
    callback = function(ev) stamps[ev.buf] = stamp(api.nvim_buf_get_name(ev.buf)) end,
  })
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
    group = group,
    callback = function(ev)
      if pending[ev.buf] then return end
      pending[ev.buf] = true
      vim.schedule(function()
        pending[ev.buf] = nil
        save(ev.buf)
      end)
    end,
  })
  api.nvim_create_autocmd({ "InsertLeave", "FocusLost" }, {
    group = group,
    callback = function() M.flush() end,
  })
  api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev) stamps[ev.buf] = nil end,
  })
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) and api.nvim_buf_get_name(buf) ~= "" and not stamps[buf] then
      stamps[buf] = stamp(api.nvim_buf_get_name(buf))
    end
  end
end

return M
