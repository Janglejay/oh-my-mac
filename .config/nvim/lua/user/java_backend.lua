-- 修改 server 后重启 Neovim；项目由 Lathe 自动识别，无需逐项目登记。
local M = {
  server = "lathe", -- "lathe" 或 "jdtls"
  lathe = {
    resources = vim.fn.expand("~/.codex/experiments/lathe-java8-20261116-side"),
    state_root = vim.fn.expand("~/.local/state/nvim/lathe"),
    worktree_root = vim.fn.expand("~/.codex/worktrees"),
    python = "/opt/homebrew/anaconda3/bin/python3",
    runtime_jdk = "/Library/Java/JavaVirtualMachines/zulu-21.jdk/Contents/Home",
    jvm_opts = "-Xms256m -Xmx3g",
  },
}
assert(M.server == "lathe" or M.server == "jdtls", "Java server must be lathe or jdtls")
function M.setup()
  if M.server ~= "lathe" then return end
  assert(vim.fn.isdirectory(M.lathe.resources .. "/lathe.nvim-0.3.1") == 1, "Lathe client installation is missing")
  -- Shared parent only for identifying read-only cache buffers. Each server gets its own cache.
  vim.env.LATHE_CACHE = M.lathe.state_root .. "/projects"
end
return M
