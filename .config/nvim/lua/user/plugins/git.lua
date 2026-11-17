local review_request = 0

-- 用当前源码所在仓库定位基准；异步查询不阻塞切换窗口和输入。
local function open_branch_review()
  review_request = review_request + 1
  local request = review_request
  local tabpage = vim.api.nvim_get_current_tabpage()
  local filename = vim.api.nvim_buf_get_name(0)
  local cwd = vim.fn.getcwd()
  local review = package.loaded["user.codediff_review"]
  if type(review) == "table" and type(review.repository_seed) == "function" then
    cwd = review.repository_seed()
  elseif vim.bo.buftype == "" and filename ~= "" and not filename:match("^%a[%w+.-]*://") then
    cwd = vim.fs.dirname(filename)
  end

  vim.system({ "git", "-C", cwd, "rev-parse", "--show-toplevel" }, { text = true }, vim.schedule_wrap(function(repo)
    if request ~= review_request then return end
    if repo.code ~= 0 then
      vim.notify("Git Diff: the current file is not in a Git repository", vim.log.levels.WARN)
      return
    end

    local root = vim.trim(repo.stdout or "")
    local base_ref = type(review) == "table" and type(review.selected_base) == "function"
      and review.selected_base(root) or "origin/master"
    vim.system({ "git", "-C", root, "rev-parse", "--verify", base_ref .. "^{commit}" },
      { text = true }, vim.schedule_wrap(function(base)
        if request ~= review_request or not vim.api.nvim_tabpage_is_valid(tabpage)
          or vim.api.nvim_get_current_tabpage() ~= tabpage then
          return
        end
        if base.code ~= 0 then
          vim.notify("Git Diff: comparison base is not available locally: " .. base_ref .. ". Fetch it first.", vim.log.levels.WARN)
          return
        end

        -- 固定本地 tip，比较到最终工作区；不是仅比较未提交内容，也不是共同祖先。
        -- 只扩展本视图的 adapter：复用原生未跟踪文件读取与空白左侧 Diff。
        -- 不改插件源码、索引、暂存区或其他 Diff/历史视图。
        local view = require("diffview.lib").diffview_open({ vim.trim(base.stdout or ""), "-C=" .. root })
        if view then
          view.adapter.show_untracked = function() return true end
          view:open()
        end
      end))
  end))
end

return {
  -- 保留 Diffview 历史及同口径回退；主审查由下方 CodeDiff 提供。
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles", "DiffviewBranchReview" },
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<Leader>gh", "<cmd>DiffviewFileHistory %<CR>",   noremap = true, silent = true, desc = "Show File History" },
      { "<Leader>gH", "<cmd>DiffviewFileHistory<CR>",     noremap = true, silent = true, desc = "Show Project History" },
    },
    config = function()
      require("diffview").setup({
        enhanced_diff_hl = true,
        view = {
          default      = { layout = "diff2_horizontal" },
          file_history = { layout = "diff2_horizontal" },
        },
        file_panel = {
          listing_style = "tree",
          tree_options  = { flatten_dirs = true, folder_statuses = "only_folded" },
          win_config    = { position = "left", width = 50 },
        },
        keymaps = {
          file_panel = {
            -- 目录仅用 Enter 展开/折叠；h/l 恢复普通左右移动。
            ["h"] = false,
            ["l"] = false,
            ["o"] = "<Nop>",
            ["zo"] = "<Nop>",
            ["zc"] = "<Nop>",
            ["za"] = "<Nop>",
            ["zR"] = "<Nop>",
            ["zM"] = "<Nop>",
            ["<2-LeftMouse>"] = "<Nop>",
          },
          view = {
            -- 跳当前基准的 Diff 块，而不是 Gitsigns 的 index→工作区块。
            { "n", "<C-d>", "]c", { desc = "Next Change" } },
            { "n", "<C-f>", "[c", { desc = "Previous Change" } },
          },
        },
        hooks = {
          -- 此事件晚于 Diffview 默认窗口设置，切换文件后也保持完整上下文。
          -- 仅作用于 Diff 窗口，不改变普通文件的折叠或换行选项。
          diff_buf_win_enter = function(_, winid)
            if winid and vim.api.nvim_win_is_valid(winid) then
              vim.wo[winid].foldenable = false
            end
          end,
        },
      })

      -- 在 diffview 内按 q 关闭
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "DiffviewFiles", "DiffviewFileHistory" },
        callback = function(args)
          vim.keymap.set("n", "q", "<cmd>DiffviewClose<CR>",
            { buffer = args.buf, noremap = true, silent = true })
        end,
      })

      vim.api.nvim_create_user_command("DiffviewBranchReview", open_branch_review,
        { desc = "Show Diff in Diffview (current base, including untracked files)", force = true })
    end,
  },
  {
    -- 固定公开版本由本机包目录加载，不建立或使用 GitHub Git remote。
    name = "codediff.nvim",
    dir = vim.fn.expand("~/.local/share/nvim/lazy/codediff.nvim"),
    cmd = { "CodeDiff", "CodeDiffBase" },
    keys = {
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
