return {
  -- Aerial aggregates LSP/Tree-sitter symbols; Snacks renders the compact picker.
  {
    "stevearc/aerial.nvim",
    cmd  = { "AerialToggle", "AerialOpen", "AerialNext", "AerialPrev" },
    keys = {
      {
        "<Leader>s",
        function()
          require("aerial").snacks_picker({
            title = "File Structure — Enter jump · Esc close",
            preview = "none",
            matcher = { fuzzy = true, keep_parents = true, sort_empty = false },
            layout = {
              hidden = { "preview" },
              layout = {
                backdrop = false,
                width = 0.52,
                min_width = 72,
                max_width = 112,
                height = 0.58,
                min_height = 12,
                border = true,
                box = "vertical",
                title = "{title}",
                title_pos = "center",
                { win = "input", height = 1, border = "bottom" },
                { win = "list", border = "none" },
              },
            },
          })
        end,
        desc = "File Structure",
      },
    },
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    config = function()
      require("aerial").setup({
        backends = { "lsp", "treesitter", "markdown", "man" },
        filter_kind = false,
      })
    end,
  },

  -- lspsaga: GUI 风格 LSP UI（主要用于 gR Call Hierarchy）
  {
    "nvimdev/lspsaga.nvim",
    event = "LspAttach",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      require("lspsaga").setup({
        -- 只配置 call hierarchy，其他功能不干扰已有快捷键
        callhierarchy = {
          layout = "normal",      -- 底部分割，测试稳定性（原 float 有关不掉问题）
          left_width = 0.3,       -- 调用链树占 30%，预览占 70%
          keys = {
            edit           = "e",    -- 原跳转键（保留，跳转后关闭）
            vsplit         = "v",
            split          = "s",
            tabe           = "t",
            quit           = "q",
            close          = "q",
            toggle_or_req  = "u",   -- u 展开/折叠节点
            -- 扩展键（由 user.lspsaga_patch 注入）：跳转后保留窗口
            edit_keep_open   = "<CR>",  -- <CR> 跳转 + 保留 callhierarchy 窗口（主要使用）
            vsplit_keep_open = "V",
            split_keep_open  = "S",
            tabe_keep_open   = "T",
          },
        },
        -- 禁用会覆盖已有快捷键的功能
        ui = {
          border        = "rounded",
          devicon       = true,
          title         = true,
          expand        = "⊞",
          collapse      = "⊟",
          code_action   = "💡",
          diagnostic    = "🐛",
          incoming      = "󰏷 ",   -- 调用者图标
          outgoing      = "󰏻 ",   -- 被调用者图标
          hover         = "▣",
        },
        -- 关闭所有非 call hierarchy 的后台功能
        -- symbol_in_winbar 会后台轮询 buffer 符号，buffer 删除后崩溃
        symbol_in_winbar = { enable = false },
        lightbulb        = { enable = false },
        diagnostic       = { show_code_action = false },
        rename           = { in_select = false },
        outline          = { auto_preview = false },
        finder           = { default = "ref" },
        -- beacon 是导航高亮动画，关掉节省资源
        beacon           = { enable = false },
      })
      -- 注入扩展方法：edit_keep_open 等（跳转不关闭窗口）
      require("user.lspsaga_patch").apply()
    end,
  },

}
