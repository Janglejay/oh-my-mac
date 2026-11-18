return {
  { "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-buffer", "hrsh7th/cmp-path",
      "hrsh7th/cmp-nvim-lsp", "saadparwaiz1/cmp_luasnip",
      "L3MON4D3/LuaSnip", "rafamadriz/friendly-snippets",
    },
    config = function() require "user.cmp" end,
  },
  { "stevearc/conform.nvim", event = { "VeryLazy" }, config = function() require "user.lsp.conform" end },
}
