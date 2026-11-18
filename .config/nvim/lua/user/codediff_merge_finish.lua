local M = {}

local busy = {}
local uv = vim.uv or vim.loop

local function session_for(tabpage)
  return require("codediff.ui.lifecycle").get_session(tabpage)
end

local function notify(message, level)
  vim.notify("Apply Changes: " .. message, level or vim.log.levels.WARN)
end

--- Inspect conflict tracking; marker scanning is reserved for the explicit Apply action.
--- @param session table CodeDiff merge session
--- @param scan_markers boolean|nil Whether to scan the complete Result for conflict markers
--- @return table status Remaining block count, first block line, and marker count
function M.status(session, scan_markers)
  local status = { remaining = 0, total = 0, markers = 0 }
  local buf = session and session.result_bufnr
  if not buf or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf)
      or type(session.conflict_blocks) ~= "table" then
    status.invalid = true
    return status
  end
  local tracking = require("codediff.ui.conflict.tracking")
  for _, block in ipairs(session.conflict_blocks) do
    status.total = status.total + 1
    local ok, active = pcall(tracking.is_block_active, session, block)
    if not ok or active then
      status.remaining = status.remaining + 1
      status.first = status.first or tracking.get_block_start_line(session, block, buf) or 1
    end
  end
  if scan_markers then
    for line, text in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      if text:match("^%s*<<<<<<<") or text:match("^%s*>>>>>>>")
          or text:match("^%s*|||||||") or text:match("^%s*=======%s*$") then
        status.markers = status.markers + 1
        status.first_marker = status.first_marker or line
      end
    end
  end
  return status
end

local function same_session(ctx)
  return vim.api.nvim_tabpage_is_valid(ctx.tab) and session_for(ctx.tab) == ctx.session
    and ctx.session.git_root == ctx.root
end

local function selected_conflict(session, relative)
  local panel = session.panel
  local selected = panel and panel.data and panel.data.current_selection
  return panel and panel.name == "explorer" and selected and selected.group == "conflicts"
    and type(selected.path) == "string" and vim.fs.normalize(selected.path) == relative
end

local function same_result(ctx)
  local session = ctx.session
  local stat = uv.fs_lstat(ctx.filename)
  return same_session(ctx) and vim.api.nvim_get_current_tabpage() == ctx.tab and session.merge
    and not session.suspended and session.result_bufnr == ctx.buf
    and session.result_win and vim.api.nvim_win_is_valid(session.result_win)
    and vim.api.nvim_win_get_buf(session.result_win) == ctx.buf
    and vim.api.nvim_buf_is_valid(ctx.buf) and vim.api.nvim_buf_is_loaded(ctx.buf)
    and vim.bo[ctx.buf].buftype == "" and vim.api.nvim_buf_get_name(ctx.buf) == ctx.filename
    and selected_conflict(session, ctx.relative)
    and stat and stat.type == "file" and uv.fs_realpath(ctx.filename) == ctx.canonical
end

local function unchanged(ctx)
  return same_result(ctx) and vim.api.nvim_buf_get_changedtick(ctx.buf) == ctx.tick
    and not vim.bo[ctx.buf].modified
end

local function stop(ctx, message, level)
  if busy[ctx.tab] == ctx then busy[ctx.tab] = nil end
  notify(message, level)
end

local function run_git(ctx, arguments, done)
  local command = { "git", "-C", ctx.root }
  vim.list_extend(command, arguments)
  local ok, err = pcall(vim.system, command, { text = false, env = { GIT_OPTIONAL_LOCKS = "0" } },
    vim.schedule_wrap(function(result)
      local success, failure = xpcall(function()
        if busy[ctx.tab] ~= ctx then return end
        if result.code ~= 0 then
          stop(ctx, vim.trim(result.stderr or "Git command failed"), vim.log.levels.ERROR)
          return
        end
        done(result.stdout or "")
      end, debug.traceback)
      if not success then stop(ctx, tostring(failure), vim.log.levels.ERROR) end
    end))
  if not ok then stop(ctx, tostring(err), vim.log.levels.ERROR) end
end

local function index_entries(ctx, done)
  run_git(ctx, { "ls-files", "--stage", "-z", "--", ctx.pathspec }, done)
end

local function unmerged(entries)
  for record in entries:gmatch("([^%z]+)%z") do
    local stage = record:match("^%d+ %x+ (%d)\t")
    if stage and stage ~= "0" then return true end
  end
  return false
end

local function disk_identity(filename)
  local stat = uv.fs_stat(filename)
  if not stat then return end
  return { dev = stat.dev, ino = stat.ino, size = stat.size, mtime = stat.mtime, ctime = stat.ctime }
end

local function restore_review(ctx)
  if not same_session(ctx) or vim.api.nvim_get_current_tabpage() ~= ctx.tab then
    notify("File saved and marked as resolved. The review view has changed.", vim.log.levels.INFO)
    return
  end
  local refresh = require("codediff.ui.refresh")
  -- A native refresh may reselect the next conflict and cancel its own generation's callbacks.
  -- Read status independently so the explicit Apply action can return to this file reliably.
  refresh.request(ctx.tab, { full = true })
  require("codediff.core.git").get_status(ctx.root, vim.schedule_wrap(function(err, status)
    if not same_session(ctx) or vim.api.nvim_get_current_tabpage() ~= ctx.tab then return end
    if err or not status then
      notify("File saved and marked as resolved, but could not return to the review: " .. tostring(err or "Git status unavailable"),
        vim.log.levels.WARN)
      return
    end
    for _, file in ipairs(status.conflicts or {}) do
      if file.path == ctx.relative then
        notify("The Git state changed after staging. This file is conflicted again; refresh the review.")
        return
      end
    end
    local remaining = #(status.conflicts or {})
    for _, file in ipairs(status.staged or {}) do
      if file.path == ctx.relative then
        refresh.select(ctx.tab, vim.tbl_extend("force", file, { group = "staged", git_root = ctx.root }),
          { force = true, no_jump = true })
        notify(string.format("File saved and marked as resolved. %d conflicted file(s) remaining.", remaining), vim.log.levels.INFO)
        return
      end
    end
    -- A valid resolution can be identical to HEAD, so no staged Diff entry is required.
    notify(string.format("File saved and marked as resolved; no staged differences. %d conflicted file(s) remaining.", remaining),
      vim.log.levels.INFO)
  end))
end

local function verify_staged(ctx)
  index_entries(ctx, function(entries)
    local mode, oid, stage = entries:match("^(%d+) (%x+) (%d)\t[^%z]+%z$")
    if not mode or stage ~= "0" or oid ~= ctx.oid or unmerged(entries) then
      stop(ctx, "The index does not match the saved Result. Keep the Result open and review the file before retrying.",
        vim.log.levels.ERROR)
      return
    end
    if not vim.api.nvim_buf_is_valid(ctx.buf) or not vim.api.nvim_buf_is_loaded(ctx.buf)
        or vim.api.nvim_buf_get_changedtick(ctx.buf) ~= ctx.tick or vim.bo[ctx.buf].modified then
      stop(ctx, "The saved file was marked as resolved, but Result changed while staging. New edits remain unsaved.",
        vim.log.levels.WARN)
      return
    end
    busy[ctx.tab] = nil
    restore_review(ctx)
  end)
end

local function stage_saved(ctx)
  index_entries(ctx, function(entries)
    if not unchanged(ctx) or not vim.deep_equal(ctx.disk, disk_identity(ctx.filename)) then
      stop(ctx, "Result changed after saving. Review the file and apply again; it has not been staged.")
      return
    end
    if entries ~= ctx.index then
      stop(ctx, "The conflict index changed while saving. Review the current Git state before applying again.")
      return
    end
    require("codediff.core.git").stage_file(ctx.root, ctx.pathspec, vim.schedule_wrap(function(err)
      if busy[ctx.tab] ~= ctx then return end
      if err then
        stop(ctx, "Result was saved, but could not be marked as resolved: " .. tostring(err), vim.log.levels.ERROR)
        return
      end
      verify_staged(ctx)
    end))
  end)
end

local function save_result(ctx)
  if not same_result(ctx) or vim.api.nvim_buf_get_changedtick(ctx.buf) ~= ctx.before_tick then
    stop(ctx, "The selected conflict or Result changed. Review the file and apply again.")
    return
  end
  local ok, err = pcall(vim.api.nvim_buf_call, ctx.buf, function() vim.cmd("silent write") end)
  if not ok or vim.bo[ctx.buf].modified then
    stop(ctx, "Could not save Result. The merge remains open: " .. tostring(err or "buffer is still modified"), vim.log.levels.ERROR)
    return
  end
  if not same_result(ctx) then
    stop(ctx, "Result was saved, but the merge view changed. The file has not been staged.")
    return
  end
  local status = M.status(ctx.session, true)
  if status.invalid or status.remaining > 0 or status.markers > 0 then
    stop(ctx, "Saving changed the conflict state. Resolve all conflicts and remove conflict markers before applying again.")
    return
  end
  ctx.tick = vim.api.nvim_buf_get_changedtick(ctx.buf)
  ctx.disk = disk_identity(ctx.filename)
  if not ctx.disk then stop(ctx, "The saved file could not be read. It has not been staged."); return end
  run_git(ctx, { "hash-object", "--path=" .. ctx.relative, "--", ctx.relative }, function(oid)
    ctx.oid = vim.trim(oid)
    if not ctx.oid:match("^%x+$") then stop(ctx, "Could not verify the saved Result."); return end
    stage_saved(ctx)
  end)
end

--- Save and mark only the selected merge file as resolved, then show its normal staged Diff.
--- @param tabpage number|nil CodeDiff tab page, defaulting to the current tab
--- @return boolean started Whether the guarded asynchronous Apply operation was started
function M.finish(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  if busy[tabpage] then notify("Already applying this file."); return false end
  local session = session_for(tabpage)
  if not session or not session.merge or session.suspended or not session.result_bufnr
      or not session.result_win or not vim.api.nvim_win_is_valid(session.result_win)
      or not vim.api.nvim_buf_is_valid(session.result_bufnr) or not vim.api.nvim_buf_is_loaded(session.result_bufnr)
      or vim.bo[session.result_bufnr].buftype ~= ""
      or vim.api.nvim_get_current_tabpage() ~= tabpage then
    notify("Open a merge conflict before applying changes.")
    return false
  end
  -- Navigation can replace a merge pane's displayed buffer without replacing
  -- the tracked Result. Restore that exact buffer before allowing any Apply;
  -- keep the displaced buffer and its edits for the user to review separately.
  if vim.api.nvim_win_get_buf(session.result_win) ~= session.result_bufnr then
    local displaced = vim.api.nvim_win_get_buf(session.result_win)
    if vim.bo[displaced].modified and vim.bo[displaced].bufhidden ~= "" and vim.bo[displaced].bufhidden ~= "hide" then
      notify("The Result pane shows another modified buffer. Save or keep that buffer, then return to the merge Result.")
      return false
    end
    local ok = pcall(vim.api.nvim_win_set_buf, session.result_win, session.result_bufnr)
    if not ok then
      notify("Could not restore the merge Result. Keep your current edits and reopen this conflict file.")
      return false
    end
    vim.api.nvim_set_current_win(session.result_win)
    notify("Restored the merge Result. Review it, then press mf again to Apply Changes.", vim.log.levels.INFO)
    return false
  end
  local status = M.status(session, true)
  if status.invalid or status.remaining > 0 or status.markers > 0 then
    local first = status.first or status.first_marker or 1
    vim.api.nvim_set_current_win(session.result_win)
    vim.api.nvim_win_set_cursor(session.result_win, { math.min(first, vim.api.nvim_buf_line_count(session.result_bufnr)), 0 })
    notify(string.format("%d unresolved conflict(s), %d conflict marker(s). Resolve them before applying changes.",
      status.remaining, status.markers))
    return false
  end
  local root = session.git_root and vim.fs.normalize(session.git_root)
  local filename = vim.fs.normalize(vim.api.nvim_buf_get_name(session.result_bufnr))
  local real_root, real_file = root and uv.fs_realpath(root), uv.fs_realpath(filename)
  if not root or not real_root or not real_file or filename:sub(1, #root + 1) ~= root .. "/"
      or real_file:sub(1, #real_root + 1) ~= real_root .. "/" then
    notify("The Result file must belong to the current Git repository.")
    return false
  end
  local relative = filename:sub(#root + 2)
  local stat = uv.fs_lstat(filename)
  if not stat or stat.type ~= "file" or real_file ~= real_root .. "/" .. relative then
    notify("Apply Changes requires a regular Result file, without symbolic links in its repository path.")
    return false
  end
  if not selected_conflict(session, relative) then
    notify("The selected conflict does not match the Result file. Refresh the merge view before applying changes.")
    return false
  end
  local ctx = { tab = tabpage, session = session, root = session.git_root, buf = session.result_bufnr,
    filename = filename, relative = relative, pathspec = ":(literal)" .. relative,
    canonical = real_root .. "/" .. relative,
    before_tick = vim.api.nvim_buf_get_changedtick(session.result_bufnr) }
  if not same_result(ctx) then notify("The Result window changed. Apply again from the merge view."); return false end
  busy[tabpage] = ctx
  index_entries(ctx, function(entries)
    if not same_result(ctx) or vim.api.nvim_buf_get_changedtick(ctx.buf) ~= ctx.before_tick then
      stop(ctx, "The selected conflict or Result changed. Review the file and apply again.")
      return
    end
    if not unmerged(entries) then
      stop(ctx, "This file is no longer marked as conflicted in Git. Refresh the review before applying again.")
      return
    end
    ctx.index = entries
    save_result(ctx)
  end)
  return true
end

return M
