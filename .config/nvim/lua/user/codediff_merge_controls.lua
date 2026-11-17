local M = {}

-- Fixed CodeDiff 4.0.8 adapter: keep its statuscolumn expression and renderer.
-- One fixed mouse column precedes the native brackets, fillers and numbers.
local native_name = "codediff.ui.conflict.gutter.statuscolumn"
local native_expression = "%!v:lua.require'codediff.ui.conflict.gutter.statuscolumn'.render()"
local click_name, hook_name = "UserCodeDiffMergeArrowClick", "UserCodeDiffMergeRenderHook"
local apply_click_name, apply_click_handler = "UserCodeDiffApplyChangesClick", nil
local windows, tabs, enabled, click_handler = {}, {}, false, nil

local function valid(win)
  return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

local function session_for(tab)
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  if type(lifecycle) == "table" and type(lifecycle.get_session) == "function" then
    return lifecycle.get_session(tab)
  end
end

local function ready(session)
  return session and session.merge and not session.suspended and session.conflict_blocks
    and valid(session.original_win) and valid(session.modified_win) and valid(session.result_win)
    and session.original_bufnr and vim.api.nvim_buf_is_valid(session.original_bufnr)
    and session.modified_bufnr and vim.api.nvim_buf_is_valid(session.modified_bufnr)
    and session.result_bufnr and vim.api.nvim_buf_is_valid(session.result_bufnr)
    and vim.api.nvim_win_get_buf(session.original_win) == session.original_bufnr
    and vim.api.nvim_win_get_buf(session.modified_win) == session.modified_bufnr
    and vim.api.nvim_win_get_buf(session.result_win) == session.result_bufnr
end

local function ticks(session)
  return {
    vim.api.nvim_buf_get_changedtick(session.original_bufnr),
    vim.api.nvim_buf_get_changedtick(session.modified_bufnr),
    vim.api.nvim_buf_get_changedtick(session.result_bufnr),
  }
end

local function index_of(session, block)
  for index, candidate in ipairs(session.conflict_blocks) do
    if candidate == block then return index end
  end
end

local function active(session, block)
  return block and require("codediff.ui.conflict.tracking").is_block_active(session, block)
end

local function snapshot(session, block, index)
  return {
    session = session, tab = session.tabpage or vim.api.nvim_get_current_tabpage(), block = block, index = index,
    original = session.original_bufnr, modified = session.modified_bufnr, result = session.result_bufnr,
    mark = block.extmark_id, ticks = ticks(session),
  }
end

local function unchanged(target)
  local session = session_for(target.tab)
  return session == target.session and ready(session)
    and session.original_bufnr == target.original and session.modified_bufnr == target.modified
    and session.result_bufnr == target.result and index_of(session, target.block)
    and target.block.extmark_id == target.mark and vim.deep_equal(ticks(session), target.ticks)
end

local function block_at_cursor(session, allow_resolved)
  local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  if win ~= session.original_win and win ~= session.modified_win and win ~= session.result_win then return end
  local tracking, line = require("codediff.ui.conflict.tracking"), vim.api.nvim_win_get_cursor(win)[1]
  if buf == session.result_bufnr then
    for _, block in ipairs(session.conflict_blocks) do
      local mark = vim.api.nvim_buf_get_extmark_by_id(buf, tracking.tracking_ns, block.extmark_id, { details = true })
      if #mark >= 3 and mark[3].end_row then
        local first, last = mark[1] + 1, mark[3].end_row
        if line >= first and line <= math.max(first, last) and (allow_resolved or active(session, block)) then return block end
      end
    end
  else
    return tracking.find_conflict_at_cursor(session, line, buf == session.original_bufnr and "left" or "right", allow_resolved)
  end
end

local function input_position(session, block)
  local ours_first = session.original_revision == ":2"
  for _, side in ipairs(ours_first and { "original", "modified" } or { "modified", "original" }) do
    local range = block[side == "original" and "output1_range" or "output2_range"]
    local win = session[side .. "_win"]
    if range and range.start_line < range.end_line and valid(win)
      and range.start_line <= vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win)) then
      return win, range.start_line
    end
  end
end

-- A queued click must not overwrite a newer edit or switch to another block.
local function apply(action, target)
  if not unchanged(target) then
    vim.notify("Merge content has changed. Review the conflict block again.", vim.log.levels.INFO)
    M.refresh(true)
    return false
  end
  local session, block = target.session, target.block
  if action ~= "base" and not active(session, block) then
    vim.notify("This conflict is already resolved or edited. Use Reset to Base to choose again.", vim.log.levels.INFO)
    return false
  end
  local win, line = input_position(session, block)
  if not win then return false end
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_cursor(win, { line, 0 })
  local resolution, fn = require("codediff.ui.conflict.resolution")
  local before_seq = vim.api.nvim_buf_call(session.result_bufnr, function() return vim.fn.undotree().seq_cur end)
  local ours_left = session.original_revision == ":2"
  if action == "ours" then fn = ours_left and resolution.accept_incoming or resolution.accept_current
  elseif action == "theirs" then fn = ours_left and resolution.accept_current or resolution.accept_incoming
  elseif action == "both" then fn = resolution.accept_both
  elseif action == "base" then fn = resolution.discard end
  local ok = fn and fn(target.tab) or false
  if ok then
    require("user.codediff_merge_presentation").record(session, block, action, before_seq)
    vim.api.nvim_set_current_win(session.result_win)
    local first = require("codediff.ui.conflict.tracking").get_block_start_line(session, block, session.result_bufnr)
    if first then
      vim.api.nvim_win_set_cursor(session.result_win, { math.min(first, vim.api.nvim_buf_line_count(session.result_bufnr)), 0 })
    end
  end
  M.refresh(true)
  return ok
end

--- Apply to the actual cursor block, including Result; context never reuses an old selection.
--- @param action string ours|theirs|both|base|next|prev
--- @return boolean
function M.action(action)
  if not enabled then return false end
  local tab = vim.api.nvim_get_current_tabpage()
  local session = session_for(tab)
  if not ready(session) then return false end
  if action == "next" or action == "prev" then
    local buf = vim.api.nvim_get_current_buf()
    if buf ~= session.original_bufnr and buf ~= session.modified_bufnr and buf ~= session.result_bufnr then return false end
    local navigation = require("codediff.ui.conflict.navigation")
    if action == "next" then navigation.navigate_next_conflict(tab) else navigation.navigate_prev_conflict(tab) end
    M.refresh()
    return true
  end
  if action ~= "ours" and action ~= "theirs" and action ~= "both" and action ~= "base" then return false end
  local block = block_at_cursor(session, true)
  if not block then
    vim.notify("Place the cursor on the conflict you want to resolve.", vim.log.levels.INFO)
    return false
  end
  return apply(action, snapshot(session, block, index_of(session, block)))
end

--- Count unresolved blocks from their current Result text, including after undo.
function M.remaining(session)
  local count = 0
  for _, block in ipairs(session and session.conflict_blocks or {}) do
    if active(session, block) then count = count + 1 end
  end
  return count
end

--- Undo/redo Result edits from any merge pane; Git's index is deliberately unchanged.
function M.history(direction)
  local tab = vim.api.nvim_get_current_tabpage()
  local session = session_for(tab)
  if not ready(session) or (direction ~= "undo" and direction ~= "redo") then return false end
  local buf = vim.api.nvim_get_current_buf()
  if buf ~= session.original_bufnr and buf ~= session.modified_bufnr and buf ~= session.result_bufnr then return false end
  M.refresh()
  local state = tabs[tab]
  if not state or state.result ~= session.result_bufnr or not state.undo_base then return false end
  vim.api.nvim_set_current_win(session.result_win)
  local changed = false
  for _ = 1, vim.v.count1 do
    local before = vim.fn.undotree().seq_cur
    if before < state.undo_base or direction == "undo" and before == state.undo_base then
      if not changed then vim.notify("Already at the start of this merge resolution.", vim.log.levels.INFO) end
      break
    end
    local ok, err = pcall(vim.cmd, direction)
    if not ok then vim.notify("Merge " .. direction .. ": " .. tostring(err), vim.log.levels.WARN); break end
    local after = vim.fn.undotree().seq_cur
    if after < state.undo_base then
      vim.cmd("silent undo " .. before)
      vim.notify("Undo stopped at the start of this merge resolution.", vim.log.levels.WARN)
      break
    end
    if after == before then break end
    changed = true
  end
  require("codediff.ui.refresh").refresh_result_now(session.result_bufnr)
  M.refresh(true)
  return changed
end

-- Text-height includes wrapping and virtual lines even with off-screen anchors.
local function before_text(win, line)
  return vim.api.nvim_win_text_height(win, { start_row = 0, end_row = line - 1, end_vcol = 0 }).all
end

local function visual_index(win, point, counts)
  if point.offset == 0 then return before_text(win, point.line) end
  local following = point.line + 1
  local count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
  local after = following <= count and before_text(win, following) or vim.api.nvim_win_text_height(win, {}).all
  return after - (counts[point.line] or 0) + point.offset - 1
end

local function viewport(win)
  local info = vim.fn.getwininfo(win)[1]
  local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  local first = before_text(win, view.topline) - view.topfill
  if view.skipcol > 0 then
    first = first + vim.api.nvim_win_text_height(win, {
      start_row = view.topline - 1, start_vcol = 0, end_row = view.topline - 1, end_vcol = view.skipcol,
    }).all
  end
  return first, info.winrow + info.winbar, info
end

local function unhook()
  for _, state in pairs(windows) do if state.input then return end end
  local hook = rawget(_G, hook_name)
  if hook and hook.owner == M then
    if hook.native.render == hook.wrapper then hook.native.render = hook.original end
    _G[hook_name] = nil
  end
end

local function restore(win)
  local state = windows[win]
  if state and valid(win) then
    if vim.wo[win].winbar == state.owned_bar then vim.wo[win].winbar = state.previous_bar end
    if (state.column_owned or state.forced_column) and vim.wo[win].statuscolumn == native_expression then
      local native = package.loaded[native_name]
      if native then native.detach(win) end
      vim.wo[win].statuscolumn = state.forced_column or state.previous_column or ""
    end
  end
  windows[win] = nil
end

local function clear_tab(tab)
  for win, state in pairs(windows) do if state.tab == tab then restore(win) end end
  tabs[tab] = nil
  local presentation = package.loaded["user.codediff_merge_presentation"]
  if presentation then presentation.clear(tab) end
  unhook()
end

local function render_valid(state, win)
  local session = state.session
  return ready(session) and vim.api.nvim_win_get_buf(win) == state.buf
    and state.blocks == session.conflict_blocks and state.original == session.original_bufnr
    and state.modified == session.modified_bufnr and state.result == session.result_bufnr
    and vim.deep_equal(state.ticks, ticks(session))
end

local function install_hook()
  local native = require(native_name)
  local previous = rawget(_G, hook_name)
  if previous and previous.native == native and native.render == previous.wrapper then
    if previous.owner == M then return native end
    native.render = previous.original
  end
  local original = native.render
  local wrapper = function()
    local base = original()
    local win = tonumber(vim.g.statusline_winid)
    local state = windows[win]
    if not state then return base end
    local arrow = (state.by_line or {})[vim.v.lnum .. ":" .. vim.v.virtnum]
    local badge = (state.badges_by_line or {})[vim.v.lnum .. ":" .. vim.v.virtnum]
    if vim.v.virtnum < 0 and vim.v.relnum < 0 then arrow, badge = nil, nil end
    local text = badge and render_valid(state, win) and badge.text or "  "
    local highlight = badge and badge.hl or "UserCodeDiffMergeArrow"
    local prefix = "%#" .. highlight .. "#" .. text .. "%* "
    if arrow then prefix = "%#" .. highlight .. "#%@v:lua." .. click_name .. "@" .. text .. "%T%* " end
    return prefix .. base
  end
  native.render = wrapper
  _G[hook_name] = { native = native, original = original, wrapper = wrapper, owner = M }
  return native
end

local function rebuild(state, session, side, visuals)
  state.ticks, state.blocks = ticks(session), session.conflict_blocks
  state.original, state.modified, state.result = session.original_bufnr, session.modified_bufnr, session.result_bufnr
  state.layout = { vim.api.nvim_win_get_position(session.original_win)[2], vim.api.nvim_win_get_position(session.modified_win)[2] }
  state.arrows, state.by_line, state.badges_by_line = {}, {}, {}
  state.counts = require("codediff.ui.filler").get_virt_line_counts(state.buf)
  local compute = require("codediff.ui.conflict.gutter.compute")
  state.role, state.side = session[side .. "_revision"] == ":2" and "ours" or "theirs", side
  local left = vim.api.nvim_win_get_position(state.win)[2] < vim.api.nvim_win_get_position(session.result_win)[2]
  local glyph = left and "→" or "←"
  if vim.fn.strdisplaywidth(glyph) ~= 1 then glyph = left and ">" or "<" end
  for index, block in ipairs(session.conflict_blocks) do
    local visual = visuals.blocks[index]
    if visual then
      local range = block[side == "original" and "output1_range" or "output2_range"]
      local point = compute.visual_positions(range, state.counts)[1]
      if not point and range and range.start_line == range.end_line then
        point = { line = math.max(1, math.min(range.start_line, vim.api.nvim_buf_line_count(state.buf))), offset = 0 }
      end
      if point then
        local lnum = math.max(1, point.line)
        -- Nvim counts virtual rows backwards toward the following real line:
        -- three fillers are -3, -2, -1, rather than -1, -2, -3.
        local virtnum = point.offset == 0 and 0 or -((state.counts[point.line] or 0) - point.offset + 1)
        local key, badge = lnum .. ":" .. virtnum, nil
        if visual.kind == "unresolved" then
          local arrow = { index = index, lnum = lnum, virtnum = virtnum, point = point,
            glyph = glyph, action = state.role, target = snapshot(session, block, index) }
          state.arrows[#state.arrows + 1] = arrow
          state.by_line[key] = arrow
          badge = { text = glyph .. " ", hl = visual.hl }
        else
          local input = visual[side]
          local mark = input.selected and (visual.proven and "✓" or "=") or (visual.proven and "×" or "~")
          if vim.fn.strdisplaywidth(mark) ~= 1 then mark = input.selected and "+" or "x" end
          badge = { text = mark .. " ", hl = input.hl or visual.hl }
        end
        state.badges_by_line[key] = badge
      end
    end
  end
end

local function rebuild_result(state, session, visuals)
  state.ticks, state.blocks = ticks(session), session.conflict_blocks
  state.original, state.modified, state.result = session.original_bufnr, session.modified_bufnr, session.result_bufnr
  state.layout = { vim.api.nvim_win_get_position(session.original_win)[2], vim.api.nvim_win_get_position(session.modified_win)[2] }
  state.arrows, state.by_line, state.badges_by_line = {}, {}, {}
  for _, visual in ipairs(visuals.blocks) do
    local row = visual.result.row
    if visual.result.empty then row = visual.result.anchor_row end
    local line = math.max(1, math.min(row + 1, vim.api.nvim_buf_line_count(state.buf)))
    local suffix = visual.kind == "unresolved" and " " or (visual.proven and "✓" or "=")
    if visual.kind == "edited" then suffix = "~" end
    if vim.fn.strdisplaywidth(suffix) ~= 1 then suffix = visual.proven and "+" or "=" end
    state.badges_by_line[line .. ":0"] = { text = visual.code .. suffix, hl = visual.hl }
  end
end

--- Refresh labels and precomputed row caches, without per-render block scans.
--- @param force boolean|nil
function M.refresh(force)
  if not enabled then return end
  local tab = vim.api.nvim_get_current_tabpage()
  local session = session_for(tab)
  if not ready(session) then clear_tab(tab); return end
  local visuals = require("user.codediff_merge_presentation").refresh(session)
  local native = install_hook()
  local selection = tabs[tab]
  if not selection or selection.session ~= session or selection.result ~= session.result_bufnr
      or selection.blocks ~= session.conflict_blocks then
    selection = { session = session, result = session.result_bufnr, blocks = session.conflict_blocks,
      undo_base = vim.api.nvim_buf_call(session.result_bufnr, function() return vim.fn.undotree().seq_cur end) }
    tabs[tab] = selection
  end
  local block = block_at_cursor(session, true)
  if block then selection.block = block end
  if not index_of(session, selection.block) then selection.block = nil end
  local index = index_of(session, selection.block)
  local label = index and string.format(" #%d/%d", index, #session.conflict_blocks) or ""
  local remaining = M.remaining(session)
  local current = index and visuals.blocks[index]
  local pane_sides = { [session.original_win] = "original", [session.modified_win] = "modified", [session.result_win] = "result" }
  local repaint = false
  for win, side in pairs(pane_sides) do
    local state = windows[win]
    if not state then
      local previous = vim.wo[win].winbar
      if previous:find("UserCodeDiffMergeClick", 1, true) then previous = "" end
      state = { previous_bar = previous, previous_column = vim.wo[win].statuscolumn, win = win }; windows[win] = state
    end
    state.tab, state.session, state.input, state.buf = tab, session, side ~= "result", vim.api.nvim_win_get_buf(win)
    if state.input then
      if vim.wo[win].statuscolumn ~= "" and vim.wo[win].statuscolumn ~= native_expression then
        state.forced_column = state.forced_column or vim.wo[win].statuscolumn
        vim.wo[win].statuscolumn = ""
      end
      if vim.wo[win].statuscolumn ~= native_expression then state.column_owned = true end
      native.attach(win)
      if force or state.blocks ~= session.conflict_blocks or not vim.deep_equal(state.ticks, ticks(session))
        or state.original ~= session.original_bufnr or state.modified ~= session.modified_bufnr or state.result ~= session.result_bufnr
        or not vim.deep_equal(state.layout, { vim.api.nvim_win_get_position(session.original_win)[2],
          vim.api.nvim_win_get_position(session.modified_win)[2] }) then
        rebuild(state, session, side, visuals)
        repaint = true
      end
      local first = vim.api.nvim_win_get_position(session.original_win)[2] < vim.api.nvim_win_get_position(session.modified_win)[2]
      local is_left = (side == "original") == first
      state.owned_bar = (is_left and " Left: " or " Right: ") .. (state.role == "ours" and "Yours" or "Theirs") .. label
    else
      if vim.wo[win].statuscolumn ~= "" and vim.wo[win].statuscolumn ~= native_expression then
        state.forced_column = state.forced_column or vim.wo[win].statuscolumn
        vim.wo[win].statuscolumn = ""
      end
      if vim.wo[win].statuscolumn ~= native_expression then state.column_owned = true end
      native.attach(win)
      if force or state.blocks ~= session.conflict_blocks or not vim.deep_equal(state.ticks, ticks(session))
          or not vim.deep_equal(state.layout, { vim.api.nvim_win_get_position(session.original_win)[2],
            vim.api.nvim_win_get_position(session.modified_win)[2] }) then
        rebuild_result(state, session, visuals)
        repaint = true
      end
      local status = current and current.label or (remaining > 0 and string.format("%d unresolved", remaining) or "Ready to Apply")
      local width = vim.api.nvim_win_get_width(win)
      local title = width >= 65 and (" Result" .. label .. " | " .. status .. " | " .. remaining .. " unresolved")
        or (width >= 40 and (" Result | " .. status) or (" " .. status))
      state.owned_bar = "%<" .. title .. "%=%@v:lua." .. apply_click_name .. "@ Apply Changes %T"
    end
    vim.wo[win].winbar = state.owned_bar
  end
  local progress = remaining > 0 and (" | " .. remaining .. " unresolved") or " | Ready"
  for _, input_win in ipairs({ session.original_win, session.modified_win }) do
    local input_state = windows[input_win]
    if input_state and vim.api.nvim_win_get_width(input_win) >= 32 then
      input_state.owned_bar = input_state.owned_bar .. progress
      vim.wo[input_win].winbar = input_state.owned_bar
    end
  end
  for win, state in pairs(windows) do
    if not valid(win) or (state.tab == tab and not pane_sides[win]) then restore(win) end
  end
  -- Virtual filler rows can retain a cached statuscolumn after their source side becomes resolved.
  -- Invalidate the screen only when badge data changes, never on ordinary cursor movement.
  if repaint then vim.cmd("redraw!") end
end

--- Read-only row metadata; never applies a merge operation.
function M.inspect()
  local tab, result = vim.api.nvim_get_current_tabpage(), { panes = {} }
  for win, state in pairs(windows) do
    if state.tab == tab and state.input and valid(win) then
      local first, top, info = viewport(win)
      local pane = { win = win, buf = state.buf, role = state.role, side = state.side, arrows = {} }
      for _, arrow in ipairs(state.arrows or {}) do
        local row = top + visual_index(win, arrow.point, state.counts) - first
        pane.arrows[#pane.arrows + 1] = { index = arrow.index, lnum = arrow.lnum, virtnum = arrow.virtnum,
          anchor_line = arrow.point.line, offset = arrow.point.offset, glyph = arrow.glyph,
          screenrow = row, screencol = info.wincol }
      end
      result.panes[#result.panes + 1] = pane
    end
  end
  return result
end

--- Release only this adapter's UI ownership, allowing a safe live reload.
function M.teardown()
  enabled = false
  for win in pairs(windows) do restore(win) end
  for tab in pairs(tabs) do tabs[tab] = nil end
  unhook()
  pcall(vim.api.nvim_del_augroup_by_name, "UserCodeDiffMergeControls")
  if rawget(_G, click_name) == click_handler then _G[click_name] = nil end
  if rawget(_G, apply_click_name) == apply_click_handler then _G[apply_click_name] = nil end
  local presentation = package.loaded["user.codediff_merge_presentation"]
  if presentation then presentation.teardown() end
end

function M.setup()
  enabled = true
  require("user.codediff_merge_presentation").setup()
  _G.UserCodeDiffMergeClick = nil
  click_handler = function(_, clicks, button)
    if clicks ~= 1 or button ~= "l" then return end
    local mouse = vim.fn.getmousepos()
    local state = windows[mouse.winid]
    if not state or not state.input or not valid(mouse.winid) or not render_valid(state, mouse.winid) then return end
    local first, top, info = viewport(mouse.winid)
    if mouse.screencol ~= info.wincol then return end
    local position = first + mouse.screenrow - top
    for _, arrow in ipairs(state.arrows or {}) do
      if visual_index(mouse.winid, arrow.point, state.counts) == position then
        if vim.fn.screenstring(mouse.screenrow, mouse.screencol) ~= arrow.glyph then return end
        local action, target = arrow.action, arrow.target
        vim.schedule(function()
          if not enabled then return end
          local ok, err = pcall(apply, action, target)
          if not ok then vim.notify("Failed to accept merge change: " .. tostring(err), vim.log.levels.ERROR) end
        end)
        return
      end
    end
  end
  _G[click_name] = click_handler
  apply_click_handler = function(_, clicks, button)
    if clicks ~= 1 or button ~= "l" then return end
    local mouse = vim.fn.getmousepos()
    local state = windows[mouse.winid]
    if not state or state.input or not valid(mouse.winid) or vim.wo[mouse.winid].winbar ~= state.owned_bar then return end
    local session = session_for(state.tab)
    if not ready(session) or session ~= state.session or mouse.winid ~= session.result_win
        or state.buf ~= session.result_bufnr or vim.api.nvim_win_get_buf(mouse.winid) ~= state.buf then return end
    vim.api.nvim_set_current_win(mouse.winid)
    require("user.codediff_merge_finish").finish(state.tab)
  end
  _G[apply_click_name] = apply_click_handler
  vim.api.nvim_set_hl(0, "UserCodeDiffMergeArrow", { default = true, link = "DiagnosticOk" })
  local group = vim.api.nvim_create_augroup("UserCodeDiffMergeControls", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group, pattern = { "CodeDiffOpen", "CodeDiffFileSelect" },
    callback = function() vim.schedule(function() M.refresh(true) end) end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group, pattern = "CodeDiffClose",
    callback = function(event) clear_tab(event.data and event.data.tabpage or vim.api.nvim_get_current_tabpage()) end,
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "WinEnter", "BufEnter" }, {
    group = group, callback = function() vim.schedule(M.refresh) end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "WinResized", "VimResized" }, {
    group = group, callback = function() vim.schedule(function() M.refresh(true) end) end,
  })
  vim.api.nvim_create_autocmd("OptionSet", {
    group = group, pattern = { "wrap", "number", "relativenumber", "signcolumn", "foldcolumn" },
    callback = function() vim.schedule(function() M.refresh(true) end) end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group, callback = function(event) restore(tonumber(event.match)); unhook() end,
  })
  M.refresh(true)
end

return M
