return {
  {
    -- 固定公开版本由本机包目录加载，不建立或使用 GitHub Git remote。
    name = "codediff.nvim",
    dir = vim.fn.expand("~/.local/share/nvim/lazy/codediff.nvim"),
    cmd = { "CodeDiff", "CodeDiffBase" },
    keys = {
      { "<Leader>gh", function() require("user.codediff_review").open_history(true) end,
        noremap = true, silent = true, desc = "Show File History" },
      { "<Leader>gH", function() require("user.codediff_review").open_history(false) end,
        noremap = true, silent = true, desc = "Show Project History" },
      { "<Leader>gd", function() require("user.codediff_review").open_branch_review() end,
        noremap = true, silent = true, desc = "Show Diff / Resolve Conflicts" },
      { "<Leader>gc", function() require("user.codediff_review").close_review() end,
        noremap = true, silent = true, desc = "Close Diff" },
      { "<Leader>gB", function() require("user.codediff_review").pick_base() end,
        noremap = true, silent = true, desc = "Compare with Branch (without checkout)" },
    },
    config = function()
      require("user.codediff_review").setup()
    end,
  },
}
