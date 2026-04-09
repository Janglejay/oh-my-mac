-- vim-compat.lua
-- 迁移自 .vimrc 的 buffer-local 配置
-- 统一使用 Lua + Neovim 原生 API

local opts = { noremap = true, silent = true }

-- ====================
-- 通用 Edit 快捷键
-- ====================
vim.api.nvim_set_keymap("n", "{", "$a {<CR>}<Esc>O", opts)

-- ====================
-- Java / Rust / Lua 文件专用快捷键
-- ====================
vim.api.nvim_create_autocmd({ "FileType" }, {
  pattern = { "java", "rust", "lua" },
  callback = function()
    vim.api.nvim_buf_set_keymap(0, "n", ";", "$a;<Esc>", opts)
    vim.api.nvim_buf_set_keymap(0, "n", "{", "$a {<CR>}<Esc>O", opts)
  end,
})

-- ====================
-- Markdown 文件专用快捷键
-- ====================
vim.api.nvim_create_autocmd({ "FileType" }, {
  pattern = { "markdown" },
  callback = function()
    local mopts = { noremap = true, silent = true, buffer = 0 }
    vim.keymap.set("n", "<Leader>x", "/<++><CR>:nohl<CR>4\"-cl", mopts)
    vim.keymap.set("n", "<Leader>C", "i```<CR><++><CR>```<Esc>", mopts)
    vim.keymap.set("n", "<Leader>c", "i`<++>`<Esc>", mopts)
    vim.keymap.set("n", "<Leader>b", "i**<++>**<Esc>", mopts)
    vim.keymap.set("n", "<Leader>s", "i~~<++>~~<Esc>", mopts)
    vim.keymap.set("n", "<Leader>o", "i[<++>](<++>)<Esc>", mopts)
    vim.keymap.set("n", "<Leader>O", "i![<++>](<++>)<Esc>", mopts)
    vim.keymap.set("n", "<Leader>m", "i- [<Space>]<Esc>", mopts)
  end,
})

-- ====================
-- Go 文件专用快捷键 (if needed)
-- ====================
vim.api.nvim_create_autocmd({ "FileType" }, {
  pattern = { "go" },
  callback = function()
    vim.api.nvim_buf_set_keymap(0, "n", ";", "$a;<Esc>", opts)
    vim.api.nvim_buf_set_keymap(0, "n", "{", "$a {<CR>}<Esc>O", opts)
  end,
})
