local M = {}

local review_request = 0
local review_tabs = {}
local selected_bases = {}
local pending_reviews = {}
local explorer_bars = {}
local merge_key_states = {}
local click_name = "UserCodeDiffBaseClick"

local function lifecycle()
  return package.loaded["codediff.ui.lifecycle"]
end

local function session_for(tabpage)
  local lib = lifecycle()
  return lib and lib.get_session(tabpage)
end

local function default_base()
  return { ref = "refs/remotes/origin/master", name = "origin/master" }
end

function M.get_base(root)
  return vim.deepcopy(selected_bases[root] or default_base())
end

function M.selected_base(root)
  return M.get_base(root).ref
end

local function current_root_seed()
  local session = session_for(vim.api.nvim_get_current_tabpage())
  if session and session.git_root then return session.git_root end
  local filename = vim.api.nvim_buf_get_name(0)
  if vim.bo.buftype == "" and filename ~= "" and not filename:match("^%a[%w+.-]*://") then
    return vim.fs.dirname(filename)
  end
  return vim.fn.getcwd()
end

function M.repository_seed()
  return current_root_seed()
end

local function valid_request(request, tabpage)
  return request == review_request and vim.api.nvim_tabpage_is_valid(tabpage)
    and vim.api.nvim_get_current_tabpage() == tabpage
end

local function resolve_root(seed, callback)
  vim.system({ "git", "-C", seed, "rev-parse", "--show-toplevel" }, { text = true }, vim.schedule_wrap(function(repo)
    if repo.code ~= 0 then
      vim.notify("Git Diff: the current file is not in a Git repository", vim.log.levels.WARN)
      return
    end
    callback(vim.trim(repo.stdout or ""))
  end))
end

local function replaceable_review(tabpage)
  local session = session_for(tabpage)
  local data = session and session.panel and session.panel.data
  -- 合并标签页即使当前选中了普通文件，也可能保存着别的未保存冲突结果。
  if not session or session.merge or next(session.conflict_files or {}) then return nil end
  if not (review_tabs[tabpage] and data and data.base_revision) then return nil end
  return session
end

local function open_at_base(root, selection, request, tabpage)
  vim.system({ "git", "-C", root, "rev-parse", "--verify", selection.ref .. "^{commit}" },
    { text = true }, vim.schedule_wrap(function(base)
      if not valid_request(request, tabpage) then return end
      if base.code ~= 0 then
        vim.notify("Git Diff: comparison base is not available locally: " .. selection.name .. ". Fetch it first.", vim.log.levels.WARN)
        return
      end
      local sha = vim.trim(base.stdout or "")
      selected_bases[root] = { ref = selection.ref, name = selection.name, sha = sha }
      pending_reviews[1] = {
        root = root, sha = sha, base = vim.deepcopy(selected_bases[root]),
        old_tab = tabpage, old_session = replaceable_review(tabpage),
      }
      vim.api.nvim_cmd({ cmd = "CodeDiff", args = { "--repo", root, sha } }, {})
    end))
end

-- 未合并时进入原生状态/三方视图；其余情况按所选 ref tip 比较到工作区。
-- 默认基准 origin/master，只读解析仓库和引用，不 fetch、不修改工作区。
function M.open_branch_review()
  review_request = review_request + 1
  local request = review_request
  local tabpage = vim.api.nvim_get_current_tabpage()
  resolve_root(current_root_seed(), function(root)
    if not valid_request(request, tabpage) then return end
    vim.system({ "git", "-C", root, "ls-files", "--unmerged", "-z" }, { text = true }, vim.schedule_wrap(function(index)
      if not valid_request(request, tabpage) then return end
      if index.code ~= 0 then
        vim.notify("Git Diff: unable to read unmerged files", vim.log.levels.WARN)
        return
      end
      if index.stdout and index.stdout ~= "" then
        -- 保留原生 Git 状态分组，冲突文件可进入三方合并，其他文件仍可审查。
        pending_reviews[1] = nil
        vim.api.nvim_cmd({ cmd = "CodeDiff", args = { "--repo", root } }, {})
      else
        open_at_base(root, M.get_base(root), request, tabpage)
      end
    end))
  end)
end

function M.pick_base()
  review_request = review_request + 1
  local request = review_request
  local tabpage = vim.api.nvim_get_current_tabpage()
  resolve_root(current_root_seed(), function(root)
    if not valid_request(request, tabpage) then return end
    vim.system({ "git", "-C", root, "for-each-ref", "--format=%(refname)%09%(symref)", "refs/heads", "refs/remotes" },
      { text = true }, vim.schedule_wrap(function(result)
        if not valid_request(request, tabpage) then return end
        if result.code ~= 0 then
          vim.notify("Git Diff: unable to read local branch references", vim.log.levels.WARN)
          return
        end
        local choices, current = {}, M.get_base(root)
        for line in (result.stdout or ""):gmatch("[^\r\n]+") do
          local ref, symbolic = line:match("^([^\t]+)\t(.*)$")
          if ref and symbolic == "" then
            local name = ref:gsub("^refs/heads/", ""):gsub("^refs/remotes/", "")
            choices[#choices + 1] = { ref = ref, name = name, text = name }
          end
        end
        table.sort(choices, function(a, b)
          if a.ref == current.ref then return b.ref ~= current.ref end
          if b.ref == current.ref then return false end
          return a.name < b.name
        end)
        if #choices == 0 then
          vim.notify("Git Diff: no local or remote-tracking branches available", vim.log.levels.WARN)
          return
        end
        -- Do not use vim.ui.select here: its active UI provider can render a
        -- table-backed choice list as an empty panel.  A direct Snacks picker
        -- shows the repository refs deterministically and remains searchable.
        Snacks.picker({
          title = "Compare with Branch — Enter confirm · Esc cancel (no checkout)",
          items = choices,
          preview = "none",
          layout = { preset = "select", preview = false },
          matcher = { fuzzy = true, sort_empty = true, filename_bonus = false },
          format = function(item)
            local label = item.name
            if item.ref == current.ref then label = label .. "  [current base]" end
            local scope = item.ref:match("^refs/heads/") and "local" or "remote"
            return { { label }, { "  " .. scope, "Comment" } }
          end,
          actions = {
            confirm = function(picker, item)
              picker:close()
              if item and valid_request(request, tabpage) then open_at_base(root, item, request, tabpage) end
            end,
          },
        })
      end))
  end)
end

function M.is_open(tabpage)
  return review_tabs[tabpage or vim.api.nvim_get_current_tabpage()] ~= nil
end

-- 沿用 gh/gH 的历史入口，原生 CodeDiff history 不依赖 Diffview。
function M.open_history(current_file)
  local tabpage = vim.api.nvim_get_current_tabpage()
  local session = session_for(tabpage)
  local filename = vim.api.nvim_buf_get_name(0)
  if current_file and session then
    local path = session.modified
    if not path or path.absolute == "" then path = session.original end
    if path then filename = path.absolute end
  end
  if current_file and (filename == "" or filename:match("^%a[%w+.-]*://")) then
    vim.notify("File History: select a source file first", vim.log.levels.WARN)
    return
  end
  review_request = review_request + 1
  local request = review_request
  resolve_root(current_root_seed(), function(root)
    if not valid_request(request, tabpage) then return end
    local args = { "--repo", root, "history" }
    if current_file then
      -- 删除文件仍可查历史；显式 range 避免命令把不存在的路径当成 revision。
      if vim.fn.filereadable(filename) ~= 1 then args[#args + 1] = "HEAD" end
      args[#args + 1] = filename
    end
    vim.api.nvim_cmd({ cmd = "CodeDiff", args = args }, {})
  end)
end

-- 使用 v4.0.8 原生关闭动作，保留未保存合并结果的确认和清理逻辑。
-- 版本相关调用集中在此，不直接关闭合并标签页绕过原生守卫。
function M.close_review()
  if M.is_open() then
    local tabpage = vim.api.nvim_get_current_tabpage()
    local session = session_for(tabpage)
    local data = session and session.panel and session.panel.data
    local conflicted_files = data and data.status_result and #(data.status_result.conflicts or {}) or 0
    if session and (session.merge or conflicted_files > 0) then
      local message = string.format("Merge is not finished: %d conflicted file(s) remain. Use Apply Changes (mf) on resolved files.",
        math.max(conflicted_files, session.merge and 1 or 0))
      local unsaved = require("codediff.ui.lifecycle.accessors").get_unsaved_conflict_files(tabpage)
      if #unsaved == 0 then
        if vim.fn.confirm(message .. "\nClose the merge view?", "&Cancel\nC&lose", 1) ~= 2 then return end
      else
        vim.notify(message, vim.log.levels.WARN)
      end
    end
    require("codediff.ui.lifecycle").close(tabpage)
  end
end

local function restore_bar(win)
  local state = explorer_bars[win]
  if state and vim.api.nvim_win_is_valid(win) and vim.wo[win].winbar == state.owned then
    vim.wo[win].winbar = state.previous
  end
  explorer_bars[win] = nil
end

local function merged_buffer(session, buf)
  return session and session.merge and session.result_bufnr
    and (buf == session.original_bufnr or buf == session.modified_bufnr or buf == session.result_bufnr)
end

-- 键盘左右操作按实际屏幕列定位；角色可能随配置交换，不能假设 original 就是 ours。
local function resolve_merge_action(session, action)
  if action ~= "left" and action ~= "right" then return action end
  local original, modified = session and session.original_win, session and session.modified_win
  if not original or not modified or not vim.api.nvim_win_is_valid(original) or not vim.api.nvim_win_is_valid(modified) then
    vim.notify("Resolve using Left/Right requires valid merge input panes", vim.log.levels.WARN)
    return nil
  end
  local original_col = vim.api.nvim_win_get_position(original)[2]
  local modified_col = vim.api.nvim_win_get_position(modified)[2]
  if original_col == modified_col then
    vim.notify("Resolve using Left/Right requires side-by-side merge input panes", vim.log.levels.WARN)
    return nil
  end
  local use_original = (action == "left") == (original_col < modified_col)
  local revision = use_original and session.original_revision or session.modified_revision
  if revision == ":2" then return "ours" end
  if revision == ":3" then return "theirs" end
  vim.notify("Resolve using Left/Right requires Git merge-stage inputs", vim.log.levels.WARN)
end

local function apply_all(tabpage, action)
  local session = session_for(tabpage)
  if vim.api.nvim_get_current_tabpage() ~= tabpage or not merged_buffer(session, vim.api.nvim_get_current_buf()) then return end
  local requested_action = action
  action = resolve_merge_action(session, action)
  if not action then return end
  local labels = {
    left = "Accept All from Left", right = "Accept All from Right", both = "Accept Both for All Conflicts", base = "Reset All to Base",
  }
  local scope = action == "base" and "all conflicts, including resolved blocks" or "all unresolved conflicts"
  if vim.fn.confirm(labels[requested_action] .. " for " .. scope
      .. " in this file?\nThis edits Result only. It does not save or stage the file.", "&Apply\n&Cancel", 2) ~= 1 then return end
  local before_seq = vim.api.nvim_buf_call(session.result_bufnr, function() return vim.fn.undotree().seq_cur end)
  local before_tick = vim.api.nvim_buf_get_changedtick(session.result_bufnr)
  local affected = {}
  local tracking = require("codediff.ui.conflict.tracking")
  for _, block in ipairs(session.conflict_blocks or {}) do
    if action == "base" or tracking.is_block_active(session, block) then affected[#affected + 1] = block end
  end
  local resolution = require("codediff.ui.conflict.resolution")
  if action == "both" then
    resolution.accept_all_both(tabpage)
  elseif action == "base" then
    resolution.discard_all(tabpage)
  else
    local prefer_ours = action == "ours"
    local original_is_ours = session.original_revision == ":2"
    local fn = prefer_ours == original_is_ours and resolution.accept_all_incoming or resolution.accept_all_current
    fn(tabpage)
  end
  if vim.api.nvim_buf_get_changedtick(session.result_bufnr) ~= before_tick then
    require("user.codediff_merge_presentation").record(session, affected, action, before_seq)
  end
  require("user.codediff_merge_controls").refresh()
end

-- 使用 CodeDiff 的会话映射管理器，离开合并视图或切换普通文件时恢复旧映射。
function M.bind_merge_keys(tabpage)
  local lib, session = lifecycle(), session_for(tabpage)
  if not lib or not session then merge_key_states[tabpage] = nil; return end
  local ready = session.merge and session.result_bufnr and session.conflict_blocks
  local previous = merge_key_states[tabpage]
  if ready and previous and previous.session == session and previous.original == session.original_bufnr
      and previous.modified == session.modified_bufnr and previous.result == session.result_bufnr then return end
  if not ready and not previous then return end

  lib.begin_keymap_scope(tabpage, "user-merge")
  if ready then
    local actions = {
      { "ml", "left", "Resolve using Left" },
      { "mr", "right", "Resolve using Right" },
      { "ma", "both", "Accept Both (Current Conflict)" },
      { "mu", "base", "Reset to Base (Current Conflict)" },
      { "<C-d>", "next", "Next Change" },
      { "<C-f>", "prev", "Previous Change" },
    }
    local all_actions = {
      { "mL", "left", "Accept All from Left (Confirm)" },
      { "mT", "right", "Accept All from Right (Confirm)" },
      { "mA", "both", "Accept Both for All Conflicts (Confirm)" },
      { "mU", "base", "Reset All to Base, Including Resolved (Confirm)" },
    }
    for _, buf in ipairs({ session.original_bufnr, session.modified_bufnr, session.result_bufnr }) do
      if vim.api.nvim_buf_is_valid(buf) then
        -- bare m* 仅在当前合并会话接管，释放 scope 后恢复 Vim mark 操作。
        lib.set_buf_keymap(tabpage, buf, "n", "m", function()
          local which_key = package.loaded["which-key"]
          if which_key and which_key.show then which_key.show({ keys = "m", mode = "n", loop = false }) end
        end, { noremap = true, silent = true, nowait = false, desc = "which-key-trigger Merge" }, { priority = 10 })
        for _, entry in ipairs(actions) do
          local action = entry[2]
          lib.set_buf_keymap(tabpage, buf, "n", entry[1], function()
            if vim.api.nvim_get_current_tabpage() ~= tabpage then return end
            local resolved = resolve_merge_action(session_for(tabpage), action)
            if resolved then require("user.codediff_merge_controls").action(resolved) end
          end, { noremap = true, silent = true, desc = entry[3] }, { priority = 10 })
        end
        for _, entry in ipairs(all_actions) do
          local action = entry[2]
          lib.set_buf_keymap(tabpage, buf, "n", entry[1], function() apply_all(tabpage, action) end,
            { noremap = true, silent = true, desc = entry[3] }, { priority = 10 })
        end
        for _, entry in ipairs({ { "mz", "undo", "Undo Merge Resolution" }, { "mZ", "redo", "Redo Merge Resolution" },
            { "u", "undo", "Undo Merge Resolution" }, { "<C-r>", "redo", "Redo Merge Resolution" } }) do
          local direction = entry[2]
          lib.set_buf_keymap(tabpage, buf, "n", entry[1], function()
            if vim.api.nvim_get_current_tabpage() == tabpage then require("user.codediff_merge_controls").history(direction) end
          end, { noremap = true, silent = true, desc = entry[3] }, { priority = 10 })
        end
        for _, key in ipairs({ "mf", "<leader>gmf" }) do
          lib.set_buf_keymap(tabpage, buf, "n", key, function()
            require("user.codediff_merge_finish").finish(tabpage)
          end, { noremap = true, silent = true, desc = "Apply Changes (Save and Mark Resolved)" }, { priority = 10 })
        end
        local which_key = package.loaded["which-key"]
        if which_key and which_key.add then
          which_key.add({ { "m", group = function()
            return vim.api.nvim_get_current_tabpage() == tabpage and merged_buffer(session_for(tabpage), buf) and "Merge" or "Marks"
          end, buffer = buf } })
        end
      end
    end
    merge_key_states[tabpage] = {
      session = session, original = session.original_bufnr, modified = session.modified_bufnr, result = session.result_bufnr,
    }
  else
    merge_key_states[tabpage] = nil
  end
  lib.end_keymap_scope(tabpage, "user-merge")
end

function M.refresh(tabpage, redraw_tree)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  if not vim.api.nvim_tabpage_is_valid(tabpage) then return end
  local lib, session = lifecycle(), session_for(tabpage)
  if not lib or not session then return end
  lib.begin_keymap_scope(tabpage, "user-close")
  local close_buffers = {}
  for _, key in ipairs({ "original_bufnr", "modified_bufnr", "result_bufnr" }) do
    local buf = session[key]
    if buf and vim.api.nvim_buf_is_valid(buf) then close_buffers[buf] = true end
  end
  local panel = lib.get_panel_view(tabpage)
  if panel and panel.bufnr and vim.api.nvim_buf_is_valid(panel.bufnr) then close_buffers[panel.bufnr] = true end
  for buf in pairs(close_buffers) do
    for key, action in pairs({ mR = "reset", mB = "abort_merge" }) do
      lib.set_buf_keymap(tabpage, buf, "n", key, function() require("user.git_reset")[action]() end,
        { noremap = true, silent = true, desc = key == "mR" and "Revert File Changes" or "Abort Merge" }, { priority = 20 })
    end
    for _, key in ipairs({ "q", "<leader>gc" }) do
      lib.set_buf_keymap(tabpage, buf, "n", key, M.close_review,
        { noremap = true, silent = true, desc = "Close Diff" }, { priority = 10 })
    end
  end
  lib.end_keymap_scope(tabpage, "user-close")
  M.bind_merge_keys(tabpage)
  local explorer = session.panel and session.panel.name == "explorer" and lib.get_panel_view(tabpage)
  if not explorer or not explorer.winid or not vim.api.nvim_win_is_valid(explorer.winid) then return end
  for win in pairs(explorer_bars) do
    if not vim.api.nvim_win_is_valid(win) then explorer_bars[win] = nil end
  end
  local data = session.panel.data
  local info = review_tabs[tabpage]
  local label
  if data.base_revision then
    label = info and info.base and info.base.name or tostring(data.base_revision):sub(1, 12)
  else
    label = session.merge and "Merge / Compare with Branch" or "Local Changes / Compare with Branch"
  end
  local bar = "%#TabLineSel#%1@v:lua." .. click_name .. "@ Base: " .. label:gsub("%%", "%%%%") .. " ▾ %T%*"
  local state = explorer_bars[explorer.winid] or { previous = vim.wo[explorer.winid].winbar }
  state.owned, state.tabpage = bar, tabpage
  explorer_bars[explorer.winid] = state
  vim.wo[explorer.winid].winbar = bar
  if redraw_tree and explorer.tree then
    vim.api.nvim_win_call(explorer.winid, function() explorer.tree:render() end)
  end
end

local function schedule_refresh(tabpage, redraw_tree, attempt)
  vim.schedule(function()
    if not vim.api.nvim_tabpage_is_valid(tabpage) then return end
    M.refresh(tabpage, redraw_tree)
    local session = session_for(tabpage)
    if session and session.merge and not session.conflict_blocks and (attempt or 0) < 20 then
      vim.defer_fn(function() schedule_refresh(tabpage, false, (attempt or 0) + 1) end, 50)
    end
  end)
end

local function group_formatter(ctx)
  local session = session_for(vim.api.nvim_get_current_tabpage())
  local data = session and session.panel and session.panel.data
  local labels = {
    conflicts = "Merge Conflicts",
    staged = "Staged Changes",
    unstaged = data and data.base_revision and "Changes" or "Local Changes",
  }
  local translated = vim.tbl_extend("force", ctx, { label = labels[ctx.name] or ctx.label })
  return require("codediff.ui.explorer.formatters").group(translated)
end

function M.options()
  return {
    diff = {
      layout = "side-by-side",
      compact = false,
      cycle_next_hunk = false,
      cycle_next_file = false,
      cycle_hunks_across_files = false,
      conflict_ours_position = "left",
      conflict_result_position = "center",
      conflict_result_width_ratio = { 1, 1.25, 1 },
    },
    explorer = {
      position = "left",
      width = 50,
      view_mode = "tree",
      flatten_dirs = true,
      untracked = "all",
      auto_refresh = true,
      initial_focus = "explorer",
      focus_on_select = true,
      auto_open_on_cursor = false,
      visible_groups = { conflicts = true, unstaged = true, staged = true },
      formatters = { group = group_formatter },
    },
    keymaps = {
      view = {
        quit = { "q", "<leader>gc" },
        next_hunk = { "]c", "<C-d>" },
        prev_hunk = { "[c", "<C-f>" },
      },
      explorer = {
        select = "<CR>",
        fold_open = false,
        fold_open_recursive = false,
        fold_close = false,
        fold_close_recursive = false,
        fold_toggle = false,
        fold_toggle_recursive = false,
        fold_open_all = false,
        fold_close_all = false,
      },
      -- 合并动作由 bind_merge_keys 统一转到鼠标控件同一语义入口。
      -- 禁用按输入窗口命名的原生绑定，避免左右调换后 co/ct 意义反转。
      conflict = {
        accept_incoming = false,
        accept_current = false,
        accept_both = false,
        discard = false,
        next_conflict = false,
        prev_conflict = false,
        accept_all_incoming = false,
        accept_all_current = false,
        accept_all_both = false,
        discard_all = false,
      },
    },
  }
end

function M.setup()
  local group = vim.api.nvim_create_augroup("UserCodeDiffReview", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffOpen",
    callback = function(event)
      local tabpage = event.data and event.data.tabpage
      if not tabpage then return end
      local session = session_for(tabpage)
      local pending = pending_reviews[1]
      review_tabs[tabpage] = { root = session and session.git_root }
      if pending and session and pending.root == session.git_root and pending.sha == session.original_revision then
        review_tabs[tabpage].base = pending.base
        pending_reviews[1] = nil
        -- 新视图已成功创建才关闭旧普通审查；合并及其未保存结果一律保留。
        if pending.old_session and vim.api.nvim_tabpage_is_valid(pending.old_tab) then
          vim.schedule(function()
            if session_for(pending.old_tab) == pending.old_session and replaceable_review(pending.old_tab) then
              lifecycle().close(pending.old_tab)
            end
          end)
        end
      end
      schedule_refresh(tabpage, true)
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffClose",
    callback = function(event)
      local tabpage = event.data and event.data.tabpage
      if tabpage then
        review_tabs[tabpage], merge_key_states[tabpage] = nil, nil
        if pending_reviews[1] and pending_reviews[1].old_tab == tabpage then pending_reviews[1] = nil end
        for win, state in pairs(explorer_bars) do
          if state.tabpage == tabpage then restore_bar(win) end
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffFileSelect",
    callback = function(event)
      local tabpage = event.data and event.data.tabpage
      if tabpage then schedule_refresh(tabpage, true) end
    end,
  })
  vim.api.nvim_create_autocmd({ "TabEnter", "BufWinEnter", "WinEnter", "CursorMoved" }, {
    group = group,
    callback = function(event)
      local tabpage = vim.api.nvim_get_current_tabpage()
      if session_for(tabpage) then schedule_refresh(tabpage, event.event == "TabEnter") end
    end,
  })
  vim.api.nvim_create_user_command("CodeDiffBase", M.pick_base,
    { desc = "Compare with Branch (without checkout)", force = true })
  _G[click_name] = function(_, clicks, button)
    if clicks ~= 1 or button ~= "l" then return end
    local mouse = vim.fn.getmousepos()
    local state = explorer_bars[mouse.winid]
    if not state or not vim.api.nvim_win_is_valid(mouse.winid) or vim.wo[mouse.winid].winbar ~= state.owned then return end
    vim.api.nvim_set_current_win(mouse.winid)
    M.pick_base()
  end
  require("codediff").setup(M.options())
  require("user.codediff_merge_controls").setup()
  -- 支持当前 Neovim 会话刷新配置，不依赖将来的 CodeDiffOpen 事件。
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    local session = session_for(tabpage)
    if session then
      review_tabs[tabpage] = review_tabs[tabpage] or { root = session.git_root }
      schedule_refresh(tabpage, true)
    end
  end
end

return M
