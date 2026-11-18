-- Lathe 本机资源与运行参数；项目由 Lathe 自动识别。
local M = {
  resources = vim.fn.expand("~/.codex/experiments/lathe-java8-20261116-side"),
  state_root = vim.fn.expand("~/.local/state/nvim/lathe"),
  worktree_root = vim.fn.expand("~/.codex/worktrees"),
  python = "/opt/homebrew/anaconda3/bin/python3",
  runtime_jdk = "/Library/Java/JavaVirtualMachines/zulu-21.jdk/Contents/Home",
  jvm_opts = "-Xms256m -Xmx3g",
}
function M.setup()
  assert(vim.fn.isdirectory(M.resources .. "/lathe.nvim-0.3.1") == 1, "Lathe client installation is missing")
  -- Shared parent only for identifying read-only cache buffers. Each server gets its own cache.
  vim.env.LATHE_CACHE = M.state_root .. "/projects"
end
return M
