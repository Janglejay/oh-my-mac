-- Mason + Mason-LSPConfig for Neovim 0.12+
-- LSP servers installed by mason, configured via vim.lsp.config
local mason_ok, mason = pcall(require, "mason")
if not mason_ok then
  vim.notify("mason.nvim not found, please run :PackerSync", vim.log.levels.ERROR)
  return
end

local mason_lspconfig_ok, mason_lspconfig = pcall(require, "mason-lspconfig")
if not mason_lspconfig_ok then
  vim.notify("mason-lspconfig.nvim not found, please run :PackerSync", vim.log.levels.ERROR)
  return
end

-- Mason: install LSP servers, linters, formatters
mason.setup({
  ui = {
    border = "rounded",
    icons = {
      package_installed = "✓",
      package_pending = "➜",
      package_uninstalled = "✗",
    },
  },
  log_level = vim.log.levels.INFO,
  max_concurrent_installers = 4,
})

-- Mason-LSPConfig: auto-register servers with vim.lsp.config
local lsp_servers = { "pyright", "jdtls" }
mason_lspconfig.setup({
  ensure_installed = lsp_servers,
  automatic_installation = true,
})

-- vim.lsp.config (Neovim 0.11+/0.12 native LSP config)
vim.lsp.config('pyright', {
  settings = {
    python = {
      analysis = {
        autoSearchPaths = true,
        diagnosticMode = "openFilesOnly",
        typeCheckingMode = "basic",
      },
    },
  },
})

vim.lsp.config('jdtls', {
  cmd = { "jdtls" },
  root_dir = function()
    return vim.fs.root(0, { "pom.xml", "build.gradle", ".git", "mvnw", "gradlew" }) or vim.fn.getcwd()
  end,
})

-- vim.lsp.enable starts registered servers
vim.lsp.enable('pyright')
vim.lsp.enable('jdtls')
