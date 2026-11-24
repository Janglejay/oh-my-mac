-- Neovide runs one Neovim server per native window. Only live UI servers are switchable.
local M = {}
local uv = vim.uv
local directory = vim.fn.stdpath("state") .. "/project-windows"
local recent_file = directory .. "/recent.json"
local windows = directory .. "/open"
local record = windows .. "/" .. uv.os_getpid() .. ".json"

local function read(path)
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  end)
  if ok and type(data) == "table" then return data end
end

local function write(path, data)
  vim.fn.mkdir(vim.fs.dirname(path), "p", 448)
  local temporary = path .. "." .. uv.os_getpid() .. ".tmp"
  if vim.fn.writefile({ vim.json.encode(data) }, temporary, "s") ~= 0 then return end
  local ok = uv.fs_rename(temporary, path)
  if not ok then uv.fs_unlink(temporary) end
  return ok
end

function M.recent()
  local item = read(recent_file)
  local stat = item and type(item.root) == "string" and uv.fs_stat(item.root)
  if stat and stat.type == "directory" then return item end
end

function M.remember(root, file)
  return write(recent_file, { root = root, file = file })
end

local function neovide_ui()
  for _, ui in ipairs(vim.api.nvim_list_uis()) do
    local client = vim.api.nvim_get_chan_info(ui.chan).client
    if client and client.name == "neovide" then return ui.chan end
  end
end

function M.register(root, file)
  local ui = neovide_ui()
  if not ui or vim.v.servername == "" then return end
  local first = not M.ui
  M.root, M.ui = root, ui
  if file then M.file = file end
  if first or not uv.fs_stat(record) then
    write(record, { root = root, pid = uv.os_getpid(), socket = vim.v.servername })
    M.remember(root, M.file)
  else
    local recent = M.recent()
    if file and recent and recent.root == root and recent.file ~= file then M.remember(root, file) end
  end
end

function M.unregister(channel)
  if channel and channel ~= M.ui then return end
  M.ui = nil
  uv.fs_unlink(record)
end

function M.open()
  local result = {}
  if not uv.fs_stat(windows) then return result end
  for name, kind in vim.fs.dir(windows) do
    if kind == "file" and name:match("^%d+%.json$") then
      local item = read(windows .. "/" .. name)
      local socket = item and type(item.socket) == "string" and uv.fs_stat(item.socket)
      if socket and socket.type == "socket" and type(item.root) == "string"
          and item.pid == tonumber(name:match("^%d+")) and uv.kill(item.pid, 0) == 0 then
        result[#result + 1] = item
      end
    end
  end
  table.sort(result, function(a, b)
    if a.root == b.root then return a.pid < b.pid end
    return a.root:lower() < b.root:lower()
  end)
  return result
end

function M.find(root, pid)
  for _, item in ipairs(M.open()) do
    if item.root == root and (not pid or item.pid == pid) then return item end
  end
end

function M.receive(request)
  if not M.root or M.root ~= request.root or not neovide_ui()
      or vim.fn.exists(":NeovideFocus") ~= 2 then return 0 end
  vim.cmd.NeovideFocus()
  local files = request.files or {}
  if #files > 0 then
    if vim.bo.buftype ~= "" or vim.wo.diff then
      local editor = vim.iter(vim.api.nvim_tabpage_list_wins(0)):find(function(win)
        return vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "" and not vim.wo[win].diff
      end)
      if editor then vim.api.nvim_set_current_win(editor) else vim.cmd.tabnew() end
    end
    for i = 2, #files do vim.cmd.badd({ args = { files[i] }, magic = { file = false, bar = false } }) end
    if vim.api.nvim_buf_get_name(0) ~= files[1] then
      vim.cmd.edit({ args = { files[1] }, mods = { hide = true }, magic = { file = false, bar = false } })
    end
  end
  if request.remember then
    local file = files[1] and uv.fs_realpath(files[1])
    M.remember(M.root, file or M.file)
  end
  return 1
end

function M.focus(item, files, remember)
  local request = { root = item.root, files = files, remember = remember }
  if item.pid == uv.os_getpid() then return M.receive(request) == 1 end
  local data = vim.json.encode(request):gsub("'", "''")
  local expr = "luaeval('require(\"user.project_windows\").receive(_A)', json_decode('" .. data .. "'))"
  local ok, result = pcall(function()
    return vim.system({ vim.v.progpath, "--server", item.socket, "--remote-expr", expr },
      { text = true, timeout = 2000 }):wait()
  end)
  return ok and result.code == 0 and vim.trim(result.stdout or "") == "1", ok and vim.trim(result.stderr or "") or result
end

-- Serialize starts of the same project until its UI registers. The owner is the
-- launcher process, so an interrupted launcher does not leave a permanent lock.
function M.with_launch_lock(root, fn)
  local path = directory .. "/launch-" .. vim.fn.sha256(root)
  vim.fn.mkdir(directory, "p", 448)
  local acquired, err, code
  local started = uv.hrtime()
  repeat
    acquired, err, code = uv.fs_symlink(tostring(uv.os_getpid()), path)
    if not acquired then
      if code ~= "EEXIST" then error(err) end
      local owner = tonumber(uv.fs_readlink(path) or "")
      if owner and uv.kill(owner, 0) ~= 0 and tonumber(uv.fs_readlink(path) or "") == owner then
        uv.fs_unlink(path)
      end
      vim.wait(50, function() return false end)
    end
  until acquired or uv.hrtime() - started > 12e9
  if not acquired then error("A project window is still starting. Try again shortly.") end
  local ok, value = xpcall(fn, debug.traceback)
  uv.fs_unlink(path)
  if not ok then error(value, 0) end
  return value
end

return M
