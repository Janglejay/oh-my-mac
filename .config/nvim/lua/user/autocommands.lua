vim.cmd [[
  augroup _general_settings
    autocmd!
    autocmd FileType qf,help,man,lspinfo nnoremap <silent> <buffer> q :close<CR> 
    autocmd TextYankPost * silent! lua require('vim.highlight').on_yank({higroup = 'Visual', timeout = 200}) 
    autocmd BufWinEnter * :set formatoptions-=cro
    autocmd FileType qf set nobuflisted
  augroup end

  augroup _git
    autocmd!
    autocmd FileType gitcommit setlocal wrap
    autocmd FileType gitcommit setlocal spell
  augroup end

  augroup _markdown
    autocmd!
    autocmd FileType markdown setlocal wrap
    autocmd FileType markdown setlocal spell
  augroup end

  augroup _auto_resize
    autocmd!
    autocmd VimResized * tabdo wincmd = 
  augroup end

]]

-- Autoformat
-- augroup _lsp
--   autocmd!
--   autocmd BufWritePre * lua vim.lsp.buf.formatting()
-- augroup end

-- K=MethodUp 保护：lspsaga/Neovim 在 LspAttach 里（含 vim.schedule）设 buffer-local K→hover
-- vim.defer_fn(100ms) 明确晚于所有同步+异步 LspAttach 处理，buffer-local 最后设置的赢
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local buf = args.buf
    vim.defer_fn(function()
      if not _G._nvim_method_jump then return end
      vim.keymap.set("n", "K", function() _G._nvim_method_jump("prev") end,
        { noremap = true, silent = true, buffer = buf, desc = "MethodUp" })
    end, 100)
  end,
})

-- mtcc / Claude Code 集成：外部修改文件后，切回 Neovim 时自动重载 buffer
-- autoread 只声明意图，checktime 才真正触发检查
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  command = "silent! checktime",
})

-- 禁止 LSP 通过 willSaveWaitUntil 在保存时注入格式化 edits
-- 保留保存前格式化保护；后端精简不改变此规则。
vim.lsp.handlers["textDocument/willSaveWaitUntil"] = function() end

require("user.saved_buffer_state").setup()
require("user.auto_save").setup()

-- Directory buffers are handled by Snacks Explorer.
