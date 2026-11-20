local M = {}

local function git(root, args)
  local command = { 'git', '-C', root, '--literal-pathspecs' }
  vim.list_extend(command, args)
  return vim.system(command, { text = true }):wait()
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO)
end

-- Only an explicit Y can authorize a destructive Git operation.
local function confirm_at_top(title, lines)
  local width = math.min(88, math.max(1, vim.o.columns - 4))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = 1,
    col = math.floor((vim.o.columns - width - 2) / 2),
    width = width,
    height = 1,
    border = 'rounded',
    title = ' ' .. title .. ' ',
    title_pos = 'center',
    footer = ' [Y] Yes   [N] No ',
    footer_pos = 'center',
    style = 'minimal',
    focusable = false,
    zindex = 200,
    noautocmd = true,
  })
  vim.wo[win].wrap = true
  vim.api.nvim_win_set_height(win, math.min(
    vim.api.nvim_win_text_height(win, {}).all,
    math.max(1, vim.o.lines - 5)
  ))
  vim.cmd.redraw()
  while vim.api.nvim_win_is_valid(win) do
    local ok, key = pcall(vim.fn.getcharstr)
    if not ok or key == 'y' or key == 'Y' or key == 'n' or key == 'N' or key == '\27' then
      if not vim.api.nvim_win_is_valid(win) then return false end
      vim.api.nvim_win_close(win, true)
      return ok and (key == 'y' or key == 'Y')
    end
  end
  return false
end

local function session_at(tab)
  local lifecycle = package.loaded['codediff.ui.lifecycle']
  return lifecycle and lifecycle.get_session(tab)
end

local function target()
  local tab = vim.api.nvim_get_current_tabpage()
  local session = session_at(tab)
  if session then
    local panel = session.panel
    local data = panel and panel.data
    if not panel or panel.name ~= "explorer" or data and data.target_revision and data.target_revision ~= "WORKING" then
      notify("File changes can only be reverted in a working tree diff", vim.log.levels.WARN); return nil
    end
    local selected = data and data.current_selection
    if panel and panel.bufnr == vim.api.nvim_get_current_buf() and panel.tree then
      local node = panel.tree:get_node(vim.api.nvim_win_get_cursor(0)[1])
      selected = node and node.data
      if not selected or selected.type == 'group' or selected.type == 'directory' or not selected.path then return nil end
    end
    local relative = selected and selected.path or data and data.current_file_path
    if not session.git_root or type(relative) ~= 'string' then return nil end
    return session.git_root, relative, tab, session, data and data.base_revision or 'HEAD'
  end
  local path = vim.api.nvim_buf_get_name(0)
  if path == '' or vim.bo.buftype ~= '' then return nil end
  local result = git(vim.fs.dirname(path), { 'rev-parse', '--show-toplevel' })
  if result.code ~= 0 then return nil end
  local root = vim.trim(result.stdout)
  return root, vim.fs.relpath(root, path), tab, nil, 'HEAD'
end

local function modified_buffer(path)
  local canonical = vim.fs.normalize(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified
        and vim.fs.normalize(vim.api.nvim_buf_get_name(buf)) == canonical then return true end
  end
  return false
end

local function snapshot(root, path, full)
  local status = git(root, { 'status', '--porcelain=v1', '-z', '--untracked-files=all', '--', path })
  local index = git(root, { 'ls-files', '--stage', '-z', '--', path })
  if status.code ~= 0 or index.code ~= 0 then return nil end
  local stat = vim.uv.fs_lstat(full)
  local stamp = stat and table.concat({ stat.type, stat.dev, stat.ino, stat.size, stat.mtime.sec, stat.mtime.nsec }, ':') or 'missing'
  return status.stdout .. '\1' .. index.stdout .. '\1' .. stamp, index.stdout ~= '', status.stdout:sub(1, 3) == '?? '
end

local function has_unsaved_result(session)
  local buf = session and session.result_bufnr
  return buf and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified
end

function M.reset()
  local root, relative, tab, session, revision = target()
  if not root or not relative or relative == '' or relative:sub(1, 1) == '/' or relative:match('^%.%./') then
    notify('Select a file in a Git repository', vim.log.levels.WARN); return
  end
  local full = vim.fs.normalize(root .. '/' .. relative)
  if not vim.startswith(full, vim.fs.normalize(root) .. '/') then notify('Invalid file path', vim.log.levels.ERROR); return end
  if modified_buffer(full) or has_unsaved_result(session) then
    notify('The file or merge result has unsaved changes. Save or discard them first', vim.log.levels.WARN); return
  end
  local commit = git(root, { 'rev-parse', '--verify', revision .. '^{commit}' })
  if commit.code ~= 0 then notify('Could not resolve the base revision', vim.log.levels.ERROR); return end
  local sha = vim.trim(commit.stdout)
  local tree = git(root, { 'ls-tree', '-z', sha, '--', relative })
  local before, tracked, untracked = snapshot(root, relative, full)
  if tree.code ~= 0 or not before then notify('Could not read the file status', vim.log.levels.ERROR); return end
  local exists = tree.stdout ~= ''
  if exists and not tree.stdout:match('^%d+ blob ') then notify('Reverting directories or submodules is not supported', vim.log.levels.WARN); return end
  local stat = vim.uv.fs_lstat(full)
  if stat and stat.type ~= 'file' and stat.type ~= 'link' then notify('Only regular files and symbolic links can be reverted', vim.log.levels.WARN); return end
  if not tracked and not untracked and (stat or not exists) then
    notify('No tracked or untracked file changes to revert', vim.log.levels.WARN); return
  end
  local base = revision
  if session then
    local comparison = require('user.codediff_review').get_base(root)
    if comparison.sha == sha then base = comparison.name end
  end
  local detail = exists and 'Restore the file in the working tree and index to this revision.'
    or 'The file is absent from this revision. Delete it from the working tree and remove it from the index.'
  if not confirm_at_top('Revert File Changes', {
    'File: ' .. vim.fn.strtrans(relative),
    'Base: ' .. base .. ' (' .. sha:sub(1, 12) .. ')',
    '',
    detail,
    'Discard these changes?',
  }) then
    notify('File revert canceled')
    return
  end
  if snapshot(root, relative, full) ~= before or modified_buffer(full) or has_unsaved_result(session) then
    notify('The file or Git status changed. Try again', vim.log.levels.WARN); return
  end
  local result
  if exists or tracked then
    result = git(root, { 'restore', '--source=' .. sha, '--staged', '--worktree', '--', relative })
  else
    local ok, err = vim.uv.fs_unlink(full)
    if not ok then notify('Could not delete the untracked file: ' .. tostring(err), vim.log.levels.ERROR); return end
  end
  if result and result.code ~= 0 then notify('Could not revert file: ' .. vim.trim(result.stderr or ''), vim.log.levels.ERROR); return end
  local buf = vim.fn.bufnr(full)
  if buf > 0 and vim.api.nvim_buf_is_loaded(buf) and not vim.bo[buf].modified then
    if exists then vim.api.nvim_buf_call(buf, function() vim.cmd('silent! checktime') end)
    else pcall(vim.api.nvim_buf_delete, buf, {}) end
  end
  local active = session_at(tab)
  if active and active.panel and active.panel.update_files then active.panel:update_files() end
  notify('Reverted: ' .. relative .. ' (base: ' .. base .. ')')
end

function M.abort_merge()
  local session = session_at(vim.api.nvim_get_current_tabpage())
  local name = vim.api.nvim_buf_get_name(0)
  local seed = session and session.git_root or (vim.bo.buftype == '' and name ~= '' and vim.fs.dirname(name)) or vim.fn.getcwd()
  local repo = git(seed, { 'rev-parse', '--show-toplevel' })
  if repo.code ~= 0 then notify('The current location is not in a Git repository', vim.log.levels.WARN); return end
  local root = vim.trim(repo.stdout)
  local head = git(root, { 'rev-parse', '--verify', 'MERGE_HEAD' })
  if head.code ~= 0 then notify('No Git merge is in progress', vim.log.levels.WARN); return end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified
        and (vim.startswith(name, root .. '/') or session and buf == session.result_bufnr) then
      notify('Save or discard unsaved changes in this repository before aborting the merge', vim.log.levels.WARN); return
    end
  end
  local status = git(root, { 'status', '--porcelain=v1', '-z', '--untracked-files=all' })
  if status.code ~= 0 then notify('Could not read Git status', vim.log.levels.ERROR); return end
  if not confirm_at_top('Abort Merge', {
    'Abort the current merge?',
    '',
    'Git will try to restore the pre-merge state. Changes made during the merge may be lost.',
  }) then
    notify('Merge left in progress'); return
  end
  local current = git(root, { 'status', '--porcelain=v1', '-z', '--untracked-files=all' })
  local current_head = git(root, { 'rev-parse', '--verify', 'MERGE_HEAD' })
  if current.code ~= 0 or current.stdout ~= status.stdout or current_head.stdout ~= head.stdout then
    notify('The merge state changed. Try again', vim.log.levels.WARN); return
  end
  local result = git(root, { 'merge', '--abort' })
  if result.code ~= 0 then notify('Could not abort merge: ' .. vim.trim(result.stderr or ''), vim.log.levels.ERROR); return end
  vim.cmd('silent! checktime')
  if session and session.panel and session.panel.update_files then session.panel:update_files() end
  notify('Merge aborted')
end

return M
