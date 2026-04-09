-- LSP configuration using Neovim 0.11+ native vim.lsp.config
-- No longer requires lspconfig module

-- Setup handlers (diagnostic signs, keymaps, etc.)
require("user.lsp.handlers").setup()

-- Mason + vim.lsp.config for LSP server management
require("user.lsp.lsp-installer")

-- Conform.nvim for formatting (replaces null-ls.nvim)
require("user.lsp.conform")
