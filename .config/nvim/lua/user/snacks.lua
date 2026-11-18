local M = {}
local terminal_height = 20

function M.terminal(cmd)
  local term = Snacks.terminal.get(cmd, { create = false })
  if term then
    if term:win_valid() then
      terminal_height = vim.api.nvim_win_get_height(term.win)
      term.opts.height = terminal_height
    end
    return term:toggle()
  end
  return Snacks.terminal(cmd, { win = { position = "bottom", height = terminal_height } })
end

function M.explorer_toggle()
  local explorer = Snacks.picker.get({ source = "explorer" })[1]
  if explorer then explorer:close() else Snacks.explorer({ cwd = vim.fn.getcwd() }) end
end

function M.setup()
  require("snacks").setup({
    picker = {
      enabled = true, ui_select = true,
      layout = { preset = "default", layout = { width = 0.92, height = 0.85 } },
      jump = { reuse_win = false },
      sources = {
        files = { hidden = true, exclude = { ".git", "target", "node_modules" } },
        explorer = {
          hidden = true, ignored = true, exclude = { ".git", "node_modules", ".cache" },
          follow_file = true, git_status = true, git_untracked = true, diagnostics = true,
          layout = { preset = "sidebar", preview = false, layout = { width = 35 } },
          win = { list = { keys = {
            ["h"] = false, ["l"] = false, ["<CR>"] = "confirm",
            ["<Left>"] = false, ["<Right>"] = false,
          } } },
        },
      },
    },
    explorer = { enabled = true },
    terminal = { enabled = true, win = { keys = { term_normal = false } } },
    -- Optional dashboards, animations, GitHub integration, notifications, etc. stay disabled.
  })
  require("user.navigation").setup()
  vim.keymap.set({ "n", "t", "i" }, "<C-\\>", function() M.terminal() end,
    { silent = true, desc = "Terminal" })
  vim.api.nvim_create_autocmd("TermOpen", {
    group = vim.api.nvim_create_augroup("UserTerminalKeys", { clear = true }),
    callback = function(ev)
      local opts = { buffer = ev.buf, silent = true }
      vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], opts)
      vim.keymap.set("t", "jk", [[<C-\><C-n>]], opts)
      for _, key in ipairs({ "h", "j", "k", "l" }) do
        vim.keymap.set("t", "<C-" .. key .. ">", [[<C-\><C-n><C-w>]] .. key, opts)
      end
    end,
  })
  _G._LAZYGIT_TOGGLE = function()
    Snacks.terminal("lazygit", { win = { position = "float", width = 0.95, height = 0.92,
      keys = { { "q", "hide", mode = "t" } } } })
  end
end

return M
