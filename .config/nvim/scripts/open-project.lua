-- Entry point for the interactive `vim` shell command.
vim.opt.runtimepath:prepend(vim.fn.stdpath("config"))
local project = require("user.project")
local windows = require("user.project_windows")

local function launch(args, root)
  local command = { "neovide", "--reuse-instance", "--new-window", "--no-tabs", "--no-system-native-tabs", "--fork" }
  if root then vim.list_extend(command, { "--chdir", root }) end
  vim.list_extend(command, args)
  return vim.system(command, { detach = true, stdout = false, stderr = false }, function() end)
end

local function open(root, files, fallback)
  windows.with_launch_lock(root, function()
    local existing = windows.find(root)
    if existing then
      local ok, err = windows.focus(existing, files, true)
      if ok then return end
      if windows.find(root, existing.pid) then
        error(err ~= "" and err or "The existing project window is not responding.")
      end
    end
    local entry = #files == 0 and (fallback or project.entry_file(root)) or nil
    launch(entry and { entry } or (#files > 0 and files or { root }), root)
    if not vim.wait(10000, function() return windows.find(root) ~= nil end, 60) then
      error("Neovide started, but the project window did not register.")
    end
  end)
end

local function main()
  if #arg == 0 then
    local recent = windows.recent()
    if recent then
      local file = type(recent.file) == "string" and vim.fn.filereadable(recent.file) == 1
        and project.find_project_root(recent.file) == recent.root and recent.file or nil
      open(recent.root, {}, file)
    else
      launch({})
    end
    return
  end
  for _, value in ipairs(arg) do
    if value:match("^[-+]") then launch(arg); return end
  end
  local groups, by_root = {}, {}
  for _, value in ipairs(arg) do
    local path = vim.fn.fnamemodify(value, ":p")
    local root = project.find_project_root(path)
    if not root then launch(arg); return end
    local group = by_root[root]
    if not group then
      group = { root = root, files = {} }
      by_root[root], groups[#groups + 1] = group, group
    end
    if vim.fn.isdirectory(path) == 0 then group.files[#group.files + 1] = path end
  end
  for _, group in ipairs(groups) do open(group.root, group.files) end
end

local ok, err = pcall(main)
if not ok then
  io.stderr:write("vim: " .. tostring(err) .. "\n")
  vim.cmd.cquit(1)
end
