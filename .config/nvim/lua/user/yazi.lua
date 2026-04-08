local M = {}

local ok_terminal, Terminal = pcall(require, "toggleterm.terminal")
if not ok_terminal then
  return M
end

Terminal = Terminal.Terminal

local defaults = {
  direction = "vertical", -- "vertical" (NERDTree-like), "horizontal", or "float"
  win_size = 35, -- width for vertical / height for horizontal
  win_pos = "left", -- "left" or "right" (only for vertical)
  chdir = true, -- update Neovim cwd from yazi --cwd-file
  extra_args = {}, -- additional CLI args for yazi (advanced; keep empty by default)
  hijack_netrw = false, -- open yazi when entering a directory buffer
}

local function read_global(name, fallback)
  local value = vim.g[name]
  if value == nil then
    return fallback
  end
  return value
end

local function normalize_config()
  M.config = M.config or vim.tbl_deep_extend("force", {}, defaults)
  M.config.direction = read_global("yazi_direction", M.config.direction)
  M.config.win_size = read_global("yazi_win_size", M.config.win_size)
  M.config.win_pos = read_global("yazi_win_pos", M.config.win_pos)
  M.config.chdir = read_global("yazi_chdir", M.config.chdir)
  M.config.extra_args = read_global("yazi_extra_args", M.config.extra_args)
  M.config.hijack_netrw = read_global("yazi_hijack_netrw", M.config.hijack_netrw)
end

local function shellescape(value)
  return vim.fn.shellescape(value)
end

local function read_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= "table" then
    return {}
  end
  return lines
end

local function read_first_line(path)
  local lines = read_lines(path)
  return lines[1]
end

local function safe_remove(path)
  if not path or path == "" then
    return
  end
  pcall(vim.fn.delete, path)
end

local function open_selected_files(chooser_file)
  local lines = read_lines(chooser_file)
  if #lines == 0 then
    return
  end

  -- First selection opens in current window; additional selections open in tabs.
  local first = lines[1]
  if first and first ~= "" then
    vim.cmd(("edit %s"):format(vim.fn.fnameescape(first)))
  end

  for i = 2, #lines do
    local path = lines[i]
    if path and path ~= "" then
      vim.cmd(("tabedit %s"):format(vim.fn.fnameescape(path)))
    end
  end
end

local function maybe_update_cwd(cwd_file)
  normalize_config()
  if not M.config.chdir then
    return
  end
  local cwd = read_first_line(cwd_file)
  if cwd and cwd ~= "" then
    pcall(vim.fn.chdir, cwd)
  end
end

local function current_entry()
  local path = vim.fn.expand("%:p")
  if path == nil or path == "" then
    return vim.loop.cwd()
  end
  return path
end

local function apply_term_ui(term)
  local win = term and term.window
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  pcall(vim.api.nvim_win_set_option, win, "number", false)
  pcall(vim.api.nvim_win_set_option, win, "relativenumber", false)
  pcall(vim.api.nvim_win_set_option, win, "signcolumn", "no")
  pcall(vim.api.nvim_win_set_option, win, "cursorline", false)
  pcall(vim.api.nvim_win_set_option, win, "statusline", " ")
end

local function build_cmd(start_entry, chooser_file, cwd_file)
  normalize_config()

  local parts = {
    "yazi",
    "--chooser-file",
    shellescape(chooser_file),
    "--cwd-file",
    shellescape(cwd_file),
  }

  local extra = M.config.extra_args
  if type(extra) == "table" then
    for _, arg in ipairs(extra) do
      if type(arg) == "string" and arg ~= "" then
        table.insert(parts, arg)
      end
    end
  end

  table.insert(parts, shellescape(start_entry))
  return table.concat(parts, " ")
end

local function choose_direction()
  normalize_config()
  local direction = tostring(M.config.direction or "")
  if direction == "horizontal" or direction == "float" or direction == "vertical" then
    return direction
  end
  return "vertical"
end

local function choose_size()
  normalize_config()
  local size = tonumber(M.config.win_size)
  if not size or size <= 0 then
    return defaults.win_size
  end
  return size
end

function M.open(entry)
  if vim.fn.executable("yazi") ~= 1 then
    vim.notify("yazi not found in PATH", vim.log.levels.ERROR)
    return
  end

  local chooser_file = vim.fn.tempname()
  local cwd_file = vim.fn.tempname()
  local start_entry = entry and entry ~= "" and entry or current_entry()

  local cmd = build_cmd(start_entry, chooser_file, cwd_file)

  local direction = choose_direction()
  local size = choose_size()

  local term_opts = {
    cmd = cmd,
    hidden = true,
    direction = direction,
    close_on_exit = true,
    size = size,
    on_open = function(term)
      apply_term_ui(term)
    end,
    on_exit = function()
      open_selected_files(chooser_file)
      maybe_update_cwd(cwd_file)
      safe_remove(chooser_file)
      safe_remove(cwd_file)
    end,
  }

  if direction == "float" then
    term_opts.direction = "float"
  end

  local term = Terminal:new({
    cmd = term_opts.cmd,
    hidden = term_opts.hidden,
    direction = term_opts.direction,
    close_on_exit = term_opts.close_on_exit,
    size = term_opts.size,
    on_open = term_opts.on_open,
    on_exit = term_opts.on_exit,
  })

  M._last_term = term

  local restore_splitright
  if direction == "vertical" then
    normalize_config()
    local pos = tostring(M.config.win_pos or "left")
    local old = vim.o.splitright
    vim.o.splitright = (pos == "right")
    restore_splitright = function()
      vim.o.splitright = old
    end
  end

  local ok = pcall(function()
    term:toggle()
  end)

  if restore_splitright then
    restore_splitright()
  end

  if not ok then
    safe_remove(chooser_file)
    safe_remove(cwd_file)
  end
end

function M.open_current()
  M.open(current_entry())
end

function M.toggle(entry)
  local term = M._last_term
  if term and term.is_open and term:is_open() then
    return M.close()
  end
  return M.open(entry)
end

function M.focus()
  local term = M._last_term
  if not term or not (term.is_open and term:is_open()) then
    return
  end

  local win = term.window
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
end

function M.close()
  local term = M._last_term
  if not term then
    return
  end

  if term.is_open and term:is_open() then
    term:close()
    return
  end

  -- Fallback: toggle will close if open.
  pcall(function()
    term:toggle()
  end)
end

local function is_directory(path)
  if not path or path == "" then
    return false
  end
  local stat = vim.loop.fs_stat(path)
  return stat and stat.type == "directory"
end

local function maybe_hijack_netrw()
  normalize_config()
  if not M.config.hijack_netrw then
    return
  end

  vim.g.loaded_netrw = 1
  vim.g.loaded_netrwPlugin = 1

  local group = vim.api.nvim_create_augroup("UserYaziHijackNetrw", { clear = true })
  vim.api.nvim_create_autocmd({ "VimEnter", "BufEnter" }, {
    group = group,
    callback = function(args)
      local buf = args.buf
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      local name = vim.api.nvim_buf_get_name(buf)
      if name == "" then
        return
      end
      if not is_directory(name) then
        return
      end

      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
        M.open(name)
      end)
    end,
  })
end

local function define_nerdtree_compat()
  local function cmd(name, rhs, desc)
    pcall(vim.api.nvim_create_user_command, name, rhs, { desc = desc })
  end

  cmd("NERDTreeToggle", function()
    M.toggle(current_entry())
  end, "Yazi (NERDTreeToggle compat)")

  cmd("NERDTreeFind", function()
    M.open_current()
  end, "Yazi (NERDTreeFind compat)")

  cmd("NERDTreeFocus", function()
    M.focus()
  end, "Yazi (NERDTreeFocus compat)")

  cmd("NERDTreeClose", function()
    M.close()
  end, "Yazi (NERDTreeClose compat)")
end

normalize_config()
maybe_hijack_netrw()
define_nerdtree_compat()

return M
