-- 语言服务由独立工具目录安装，Neovim 原生 LSP 按文件类型启动。
local tools_root = vim.fn.stdpath("data") .. "/language-tools"
local function binary(group, name)
  return tools_root .. "/" .. group .. "/node_modules/.bin/" .. name
end
local handlers = require("user.lsp.handlers")

-- ── Python ──────────────────────────────────────────────────────────
vim.lsp.config("pyright", {
  cmd = { binary("pyright", "pyright-langserver"), "--stdio" },
  filetypes = { "python" },
  root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
  settings = {
    python = { analysis = { autoSearchPaths = true, diagnosticMode = "openFilesOnly", typeCheckingMode = "basic" } },
  },
  on_attach = handlers.on_attach,
  capabilities = handlers.capabilities,
})
vim.lsp.enable("pyright")

-- ── TypeScript / React ───────────────────────────────────────────────
vim.lsp.config("ts_ls", {
  cmd = { binary("typescript", "typescript-language-server"), "--stdio" },
  filetypes = {
    "javascript", "javascriptreact", "javascript.jsx",
    "typescript", "typescriptreact", "typescript.tsx",
  },
  root_markers = { "tsconfig.json", "jsconfig.json", "package.json", ".git" },
  init_options = { hostInfo = "neovim" },
  on_attach = function(client, bufnr)
    -- 格式化交给 prettier（conform.nvim），禁用 ts_ls 自带格式化
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
    handlers.on_attach(client, bufnr)
  end,
  capabilities = handlers.capabilities,
})
vim.lsp.enable("ts_ls")

-- ── Vue 3（vue_ls / Vue Language Tools 2.x）─────────────────────────
vim.lsp.config("vue_ls", {
  cmd = { binary("vue", "vue-language-server"), "--stdio" },
  filetypes = { "vue" },
  root_markers = { "vue.config.js", "vue.config.ts", "vite.config.js", "vite.config.ts", "nuxt.config.ts", "package.json", ".git" },
  init_options = {
    vue = { hybridMode = false },
    typescript = {
      tsdk = (function()
        local local_ts = vim.fn.getcwd() .. "/node_modules/typescript/lib"
        if vim.fn.isdirectory(local_ts) == 1 then
          return local_ts
        end
        return tools_root .. "/vue/node_modules/typescript/lib"
      end)(),
    },
  },
  on_attach = function(client, bufnr)
    client.server_capabilities.documentFormattingProvider = false
    handlers.on_attach(client, bufnr)
  end,
  capabilities = handlers.capabilities,
})
vim.lsp.enable("vue_ls")

-- ── ESLint ───────────────────────────────────────────────────────────
vim.lsp.config("eslint", {
  cmd = { binary("web", "vscode-eslint-language-server"), "--stdio" },
  filetypes = {
    "javascript", "javascriptreact", "javascript.jsx",
    "typescript", "typescriptreact", "typescript.tsx",
    "vue",
  },
  root_markers = { ".eslintrc", ".eslintrc.js", ".eslintrc.cjs", ".eslintrc.json", "eslint.config.js", "eslint.config.ts", "package.json", ".git" },
  settings = { workingDirectory = { mode = "auto" } },
  on_attach = function(client, bufnr)
    -- 无文件路径的 buffer（unnamed/scratch）跳过，避免 -32603 path undefined 错误
    if vim.api.nvim_buf_get_name(bufnr) == "" then
      vim.lsp.buf_detach_client(bufnr, client.id)
      return
    end
    client.server_capabilities.documentFormattingProvider = false
    handlers.on_attach(client, bufnr)
  end,
  capabilities = handlers.capabilities,
})
vim.lsp.enable("eslint")

-- ── CSS / SCSS / Less ────────────────────────────────────────────────
vim.lsp.config("cssls", {
  cmd = { binary("web", "vscode-css-language-server"), "--stdio" },
  filetypes = { "css", "scss", "less" },
  root_markers = { "package.json", ".git" },
  settings = {
    css  = { validate = true },
    scss = { validate = true },
    less = { validate = true },
  },
  on_attach = function(client, bufnr)
    client.server_capabilities.documentFormattingProvider = false
    handlers.on_attach(client, bufnr)
  end,
  capabilities = handlers.capabilities,
})
vim.lsp.enable("cssls")

-- ── HTML ─────────────────────────────────────────────────────────────
vim.lsp.config("html", {
  cmd = { binary("web", "vscode-html-language-server"), "--stdio" },
  filetypes = { "html" },
  root_markers = { "package.json", ".git" },
  init_options = { configurationSection = { "html", "css", "javascript" }, embeddedLanguages = { css = true, javascript = true } },
  on_attach = function(client, bufnr)
    client.server_capabilities.documentFormattingProvider = false
    handlers.on_attach(client, bufnr)
  end,
  capabilities = handlers.capabilities,
})
vim.lsp.enable("html")

-- ── Emmet ────────────────────────────────────────────────────────────
vim.lsp.config("emmet_ls", {
  cmd = { binary("emmet", "emmet-ls"), "--stdio" },
  filetypes = {
    "html", "css", "scss", "javascriptreact", "typescriptreact", "vue",
  },
  root_markers = { "package.json", ".git" },
  on_attach = handlers.on_attach,
  capabilities = handlers.capabilities,
})
vim.lsp.enable("emmet_ls")
