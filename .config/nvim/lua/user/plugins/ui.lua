-- UI 相关插件

return {
  -- Icons（被多个插件依赖）
  {
    "nvim-tree/nvim-web-devicons",
    lazy = true,
  },

  -- Fixed public release v2.31.0, installed from a tarball; no Git remote.
  {
    name = "snacks.nvim",
    dir = vim.fn.stdpath("data") .. "/lazy/snacks.nvim",
    lazy = false,
    priority = 900,
    config = function() require("user.snacks").setup() end,
  },

  -- Bufferline（tab 栏）
  {
    "akinsho/bufferline.nvim",
    event = "VeryLazy",
    config = function()
      require "user.bufferline"
    end,
  },

  -- 状态栏
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    config = function()
      require "user.lualine"
    end,
  },

  -- 快捷键提示
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    config = function()
      require "user.whichkey"
    end,
  },

  -- ==================== 配色方案 ====================
  -- Catppuccin - 柔和奶油风
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    config = function()
      require("user.colorschemes.catppuccin").setup()
      vim.cmd.colorscheme("catppuccin")
    end,
  },

  -- Git 状态标记
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require "user.gitsigns"
    end,
  },

  -- 自动括号配对
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      require "user.autopairs"
    end,
  },

  -- 注释
  {
    "numToStr/Comment.nvim",
    keys = { { "gc", mode = { "n", "v" } }, { "gb", mode = { "n", "v" } } },
    config = function()
      require "user.comment"
    end,
  },

  -- TODO 注释高亮
  {
    "folke/todo-comments.nvim",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require "user.todo-comments"
    end,
  },

  -- 透明背景
  {
    "xiyaowong/transparent.nvim",
    event = "VeryLazy",
    config = function()
      require "user.transparency"
    end,
  },

  -- 工具库（被多个插件依赖）
  {
    "nvim-lua/plenary.nvim",
    lazy = true,
  },
}
