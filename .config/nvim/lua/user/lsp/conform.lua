-- Conform.nvim — formatting for Neovim 0.12+
-- Replaces null-ls.nvim (unmaintained / incompatible with Neovim 0.12)
local conform_ok, conform = pcall(require, "conform")
if not conform_ok then
  return
end

conform.setup({
  formatters_by_ft = {
    python = { "black", "isort", "ruff_format" },
    java = { "google-java-format" },
    lua = { "stylua" },
    json = { "jq" },
    yaml = { "yamlfmt" },
  },
  format_on_save = {
    timeout_ms = 5000,
    lsp_fallback = true,
  },
})

-- Keymap for manual formatting
vim.keymap.set({ "n", "v" }, "<leader>f", function()
  conform.format({ async = true, timeout_ms = 5000 })
end, { desc = "Format buffer with conform" })
