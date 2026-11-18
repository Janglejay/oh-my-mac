local M = { font = "JetBrainsMono Nerd Font Mono,Symbols Nerd Font Mono:h16" }

-- Load optional UI modules only when a shortcut is used, after lazy.nvim setup.
local function merge_session()
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  local session = lifecycle and lifecycle.get_session(vim.api.nvim_get_current_tabpage())
  if session and session.result_bufnr then
    local buf = vim.api.nvim_get_current_buf()
    if buf == session.original_bufnr or buf == session.modified_bufnr or buf == session.result_bufnr then
      return session
    end
  end
end

local function editable()
  if vim.bo.modifiable and not vim.bo.readonly then return true end
  vim.notify("This editor is read-only. Edit the Result pane or a working file.", vim.log.levels.WARN)
  return false
end

local function copy_line()
  -- Code editors conventionally copy the current line when nothing is selected.
  vim.fn.setreg("+", { vim.api.nvim_get_current_line() }, "V")
end

local function history(direction)
  if merge_session() then
    require("user.codediff_merge_controls").history(direction)
  elseif editable() then
    vim.cmd(direction)
  end
end

local function save()
  if not editable() then return end
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" then
    vim.notify("This is a tool window. Save a working file or the Result pane.", vim.log.levels.WARN)
    return
  end
  local function write(path)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
      if path then vim.cmd("write " .. vim.fn.fnameescape(path)) else vim.cmd.write() end
    end)
    if not ok then vim.notify(tostring(err), vim.log.levels.WARN) end
  end
  if vim.api.nvim_buf_get_name(buf) == "" then
    vim.ui.input({ prompt = "Save As: ", completion = "file" }, function(path)
      if path and path ~= "" then write(path) end
    end)
  else
    write()
  end
end

local function project_root()
  return require("user.navigation").root()
end

local function open_file()
  vim.cmd.stopinsert()
  Snacks.picker.files({ cwd = project_root(), title = "Open File" })
end

local function new_file()
  vim.cmd.stopinsert()
  vim.cmd.enew()
end

local function open_project()
  vim.cmd.stopinsert()
  vim.ui.input({
    prompt = "Open Project Directory: ",
    default = vim.fn.getcwd(),
    completion = "dir",
  }, function(input)
    if not input or input == "" then return end
    local directory = vim.fn.fnamemodify(vim.fn.expand(input), ":p")
    local stat = vim.uv.fs_stat(directory)
    if not stat or stat.type ~= "directory" then
      vim.notify("Project directory does not exist: " .. directory, vim.log.levels.ERROR)
      return
    end
    vim.schedule(function()
      vim.api.nvim_set_current_dir(directory)
      Snacks.picker.files({ cwd = directory, title = "Open File — " .. vim.fn.fnamemodify(directory, ":~") })
    end)
  end)
end

local function setup_shortcuts()
  local function map(modes, key, action, desc)
    vim.keymap.set(modes, key, action, { silent = true, desc = desc })
  end
  map({ "n", "i", "t" }, "<D-c>", copy_line, "Copy Line")
  map("x", "<D-c>", '\"+y', "Copy")
  map("c", "<D-c>", function() vim.fn.setreg("+", vim.fn.getcmdline()) end, "Copy Command Line")
  map({ "n", "i", "x", "c", "t" }, "<D-v>", function()
    local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
    if mode ~= "c" and mode ~= "t" and not editable() then return end
    local clipboard = vim.fn.getreginfo("+")
    vim.api.nvim_paste(vim.fn.getreg("+"), true, -1)
    -- Replacing a selection must not replace the system clipboard with deleted text.
    if mode == "v" or mode == "V" or mode == "\22" then vim.fn.setreg("+", clipboard) end
  end, "Paste")
  map({ "n", "i" }, "<D-x>", function()
    if editable() then vim.cmd.normal({ args = { '\"+dd' }, bang = true }) end
  end, "Cut Line")
  map("x", "<D-x>", function()
    if editable() then vim.cmd.normal({ args = { '\"+d' }, bang = true }) end
  end, "Cut")
  map("n", "<D-a>", "ggVG", "Select All")
  map("i", "<D-a>", "<C-\\><C-n>ggVG", "Select All")
  map("x", "<D-a>", "<Esc>ggVG", "Select All")
  map({ "n", "i", "x" }, "<D-s>", save, "Save")
  map({ "n", "i", "x" }, "<D-z>", function() history("undo") end, "Undo")
  map({ "n", "i", "x" }, "<D-S-z>", function() history("redo") end, "Redo")
  map({ "n", "i", "x" }, "<D-n>", new_file, "New File")
  map({ "n", "i", "x" }, "<D-o>", open_file, "Open File")
  map({ "n", "i", "x" }, "<D-p>", open_file, "Quick Open")
  map({ "n", "i", "x" }, "<D-S-o>", open_project, "Open Project")
  map({ "n", "i", "x" }, "<D-S-p>", function()
    vim.cmd.stopinsert()
    Snacks.picker.commands()
  end, "Command Palette")
  map("n", "<D-f>", "/", "Find")
  map("i", "<D-f>", "<C-\\><C-n>/", "Find")
  map("x", "<D-f>", "<Esc>/", "Find")
  map({ "n", "i", "x" }, "<D-w>", function()
    local review = package.loaded["user.codediff_review"]
    if review and review.is_open() then
      review.close_review()
    else
      Snacks.bufdelete()
    end
  end, "Close Editor")
end

function M.setup()
  if not vim.g.neovide then
    return
  end

  -- Reuse the existing system font and the same Neovim/plugin keymaps.
  vim.o.guifont = M.font
  vim.o.linespace = 0
  vim.o.winblend = 0
  vim.o.pumblend = 0
  vim.g.transparent_enabled = false
  vim.g.neovide_opacity = 1.0
  vim.g.neovide_normal_opacity = 1.0
  vim.g.neovide_window_blurred = false
  vim.g.neovide_floating_blur_amount_x = 0.0
  vim.g.neovide_floating_blur_amount_y = 0.0
  -- Keep normal-mode navigation immediate: no cursor easing or trailing motion.
  vim.g.neovide_cursor_animation_length = 0
  vim.g.neovide_cursor_short_animation_length = 0
  vim.g.neovide_scroll_animation_length = 0.10
  vim.g.neovide_position_animation_length = 0.08
  vim.g.neovide_cursor_animate_in_insert_mode = false
  vim.g.neovide_cursor_vfx_mode = ""
  setup_shortcuts()
end

return M
