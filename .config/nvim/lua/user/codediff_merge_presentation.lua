local M = {}

-- This namespace owns presentation only. It never changes Result, native tracking or filler rows.
local namespace = vim.api.nvim_create_namespace("user-codediff-merge-presentation")
local states, configured = {}, false
local history_limit = 64
local palette_generation = 0
local paint_generation = 0

local groups = {
  pending = "UserCodeDiffMergePending", accepted = "UserCodeDiffMergeAccepted",
  ignored = "UserCodeDiffMergeIgnored", matched = "UserCodeDiffMergeMatched",
  edited = "UserCodeDiffMergeEdited", ambiguous = "UserCodeDiffMergeAmbiguous",
  pending_line = "UserCodeDiffMergePendingLine", accepted_line = "UserCodeDiffMergeAcceptedLine",
  ignored_line = "UserCodeDiffMergeIgnoredLine", matched_line = "UserCodeDiffMergeMatchedLine",
  edited_line = "UserCodeDiffMergeEditedLine", ambiguous_line = "UserCodeDiffMergeAmbiguousLine",
}

local function highlights()
  local dark = vim.o.background ~= "light"
  local colors = dark and {
    pending = "#ff9299", accepted = "#97d9ad", ignored = "#8a8f9b", matched = "#8bcbd9",
    edited = "#9ebeff", ambiguous = "#e8c17c", pending_line = "#493039", accepted_line = "#263d35",
    ignored_line = "#292b34", matched_line = "#293b40", edited_line = "#2a364b", ambiguous_line = "#443c2b",
  } or {
    pending = "#bd303b", accepted = "#28783e", ignored = "#6e7480", matched = "#236b7d",
    edited = "#275faf", ambiguous = "#906215", pending_line = "#ffe7e9", accepted_line = "#e1f0e4",
    ignored_line = "#eef0f3", matched_line = "#e0f1f3", edited_line = "#e4edfc", ambiguous_line = "#fff1d1",
  }
  for name, group in pairs(groups) do
    if name:match("_line$") then
      vim.api.nvim_set_hl(0, group, { bg = colors[name] })
    else
      vim.api.nvim_set_hl(0, group, { fg = colors[name], bold = name ~= "ignored" })
    end
  end
  palette_generation = palette_generation + 1
end

local function valid_buffer(buf)
  return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf)
end

local function ready(session)
  return session and session.merge and not session.suspended and type(session.conflict_blocks) == "table"
    and valid_buffer(session.original_bufnr) and valid_buffer(session.modified_bufnr) and valid_buffer(session.result_bufnr)
    and session.original_win and vim.api.nvim_win_is_valid(session.original_win)
    and session.modified_win and vim.api.nvim_win_is_valid(session.modified_win)
    and session.result_win and vim.api.nvim_win_is_valid(session.result_win)
    and vim.api.nvim_win_get_buf(session.original_win) == session.original_bufnr
    and vim.api.nvim_win_get_buf(session.modified_win) == session.modified_bufnr
    and vim.api.nvim_win_get_buf(session.result_win) == session.result_bufnr
end

local function clear_buffer(buf)
  if valid_buffer(buf) then vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1) end
end

local function dispose(state)
  for _, buf in ipairs(state.buffers) do clear_buffer(buf) end
  states[state.result] = nil
  paint_generation = paint_generation + 1
end

local function state_for(session)
  if not ready(session) then return end
  local buf, state = session.result_bufnr, states[session.result_bufnr]
  local tab = session.tabpage or vim.api.nvim_get_current_tabpage()
  local previous = {}
  for _, candidate in pairs(states) do
    if candidate.tab == tab and candidate.result ~= buf then previous[#previous + 1] = candidate end
  end
  for _, candidate in ipairs(previous) do dispose(candidate) end
  local input_ticks = { vim.api.nvim_buf_get_changedtick(session.original_bufnr), vim.api.nvim_buf_get_changedtick(session.modified_bufnr) }
  if state and (state.session ~= session or state.blocks ~= session.conflict_blocks
      or state.original ~= session.original_bufnr or state.modified ~= session.modified_bufnr
      or not vim.deep_equal(state.input_ticks, input_ticks)) then
    dispose(state)
    state = nil
  end
  if not state then
    state = {
      session = session, result = buf, original = session.original_bufnr, modified = session.modified_bufnr,
      tab = tab, blocks = session.conflict_blocks,
      input_ticks = input_ticks, buffers = { session.original_bufnr, session.modified_bufnr, buf }, history = {}, order = {},
    }
    states[buf] = state
  end
  return state
end

local function seq(buf)
  return vim.api.nvim_buf_call(buf, function() return vim.fn.undotree().seq_cur end)
end

local function equal(left, right)
  if #left ~= #right then return false end
  for index, line in ipairs(left) do if line ~= right[index] then return false end end
  return true
end

local function fingerprint(lines)
  return vim.fn.sha256(tostring(#lines) .. ":" .. table.concat(lines, "\n"))
end

local function input_range(buf, range)
  local count = vim.api.nvim_buf_line_count(buf)
  local first = math.max(0, math.min(range and range.start_line and range.start_line - 1 or 0, count))
  local last = math.max(first, math.min(range and range.end_line and range.end_line - 1 or first, count))
  return { row = first, end_row = last, anchor_row = math.min(first, count - 1), empty = first == last }
end

local function result_range(session, block)
  local tracking = require("codediff.ui.conflict.tracking")
  local mark = block.extmark_id and vim.api.nvim_buf_get_extmark_by_id(session.result_bufnr, tracking.tracking_ns,
    block.extmark_id, { details = true }) or {}
  local count = vim.api.nvim_buf_line_count(session.result_bufnr)
  if #mark < 3 or not mark[3].end_row then
    return { row = 0, end_row = 0, anchor_row = 0, empty = true, invalid = true }
  end
  local first = math.max(0, math.min(mark[1], count))
  local last = math.max(first, math.min(mark[3].end_row, count))
  return { row = first, end_row = last, anchor_row = math.min(first, count - 1), empty = first == last }
end

local function lines(buf, range)
  return vim.api.nvim_buf_get_lines(buf, range.row, range.end_row, false)
end

local function block_data(session, block)
  local result = result_range(session, block)
  local original = input_range(session.original_bufnr, block.output1_range)
  local modified = input_range(session.modified_bufnr, block.output2_range)
  return {
    result = result, original = original, modified = modified,
    result_lines = lines(session.result_bufnr, result),
    original_lines = lines(session.original_bufnr, original), modified_lines = lines(session.modified_bufnr, modified),
  }
end

local function combined(session, block, data)
  local combine = require("codediff.ui.conflict.resolution.combine")
  for _, first in ipairs({ 1, 2 }) do
    local ok, candidate = pcall(combine.smart_combine_inputs, session, block, first)
    if ok and candidate and equal(data.result_lines, candidate) then return true end
    local concatenated = combine.dumb_combine_inputs(data.original_lines, data.modified_lines, first)
    if equal(data.result_lines, concatenated) then return true end
  end
  return false
end

local function role_side(session, action)
  local original_role = session.original_revision == ":2" and "ours" or "theirs"
  if action == "ours" or action == "theirs" then return action == original_role and "original" or "modified" end
end

local function action_matches(session, block, data, action)
  local side = role_side(session, action)
  if side then return equal(data.result_lines, data[side .. "_lines"]) end
  return action == "both" and combined(session, block, data)
end

local function physical_side(session, input)
  local original_col = vim.api.nvim_win_get_position(session.original_win)[2]
  local modified_col = vim.api.nvim_win_get_position(session.modified_win)[2]
  if original_col == modified_col then return nil end
  local original_left = original_col < modified_col
  return (input == "original") == original_left and "left" or "right"
end

local function input_style(range, status, proven)
  local styles = {
    pending = { groups.pending, groups.pending_line }, accepted = { groups.accepted, groups.accepted_line },
    ignored = { groups.ignored, groups.ignored_line }, matched = { groups.matched, groups.matched_line },
    different = { groups.ignored, groups.ignored_line }, edited = { groups.edited, groups.edited_line },
    ambiguous = { groups.ambiguous, groups.ambiguous_line },
  }
  range.status, range.proven = status, proven
  if status == "accepted" or status == "matched" then range.selected = true
  elseif status == "ignored" or status == "different" then range.selected = false
  else range.selected = nil end
  range.hl, range.line_hl = unpack(styles[status])
  return range
end

local function classify(session, block, index, data, evidence)
  local tracking = require("codediff.ui.conflict.tracking")
  local active_ok, active = pcall(tracking.is_block_active, session, block)
  local item = { index = index, block = block, result = data.result, hash = fingerprint(data.result_lines), proven = false }
  local source
  if not active_ok or active or data.result.invalid then
    item.kind, item.code, item.label = "unresolved", "!", "Unresolved"
    item.provenance = "unresolved"
    item.hl, item.line_hl = groups.pending, groups.pending_line
  elseif evidence and evidence.hash == item.hash and action_matches(session, block, data, evidence.action) then
    item.proven, item.provenance, item.action = true, "accepted", evidence.action
    source = role_side(session, evidence.action)
    item.kind = source and physical_side(session, source) or evidence.action == "both" and "both" or "edited"
    item.kind = item.kind or "edited"
    item.code = ({ left = "L", right = "R", both = "B", edited = "E" })[item.kind]
    item.label = ({ left = "Accepted Left", right = "Accepted Right", both = "Accepted Both", edited = "Edited" })[item.kind]
    item.hl, item.line_hl = groups.accepted, groups.accepted_line
  else
    local original = equal(data.result_lines, data.original_lines)
    local modified = equal(data.result_lines, data.modified_lines)
    if original and modified then
      item.kind, item.code, item.label = "ambiguous", "?", "Matches Both Inputs"
      item.hl, item.line_hl = groups.ambiguous, groups.ambiguous_line
    elseif original or modified then
      source = original and "original" or "modified"
      item.kind = physical_side(session, source) or "edited"
      item.code = item.kind == "left" and "L" or item.kind == "right" and "R" or "E"
      item.label = item.kind == "left" and "Matches Left" or item.kind == "right" and "Matches Right" or "Edited"
      item.hl, item.line_hl = groups.matched, groups.matched_line
    elseif combined(session, block, data) then
      item.kind, item.code, item.label = "both", "B", "Matches Both (Combined)"
      item.hl, item.line_hl = groups.matched, groups.matched_line
    else
      item.kind, item.code, item.label = "edited", "E", "Edited"
      item.hl, item.line_hl = groups.edited, groups.edited_line
    end
    item.provenance = item.kind == "edited" and "edited" or "matches"
  end
  for _, side in ipairs({ "original", "modified" }) do
    local status
    if item.kind == "unresolved" then status = "pending"
    elseif item.kind == "edited" then status = "edited"
    elseif item.kind == "ambiguous" then status = "ambiguous"
    elseif item.kind == "both" or side == source then status = item.proven and "accepted" or "matched"
    else status = item.proven and "ignored" or "different" end
    item[side] = input_style(data[side], status, item.proven)
    item[side].physical_side = physical_side(session, side)
  end
  item.result.hl, item.result.line_hl = item.hl, item.line_hl
  return item
end

local function paint(buf, range, group)
  if range.empty or range.invalid then return end
  vim.api.nvim_buf_set_extmark(buf, namespace, range.row, 0, {
    end_row = range.end_row, end_col = 0, hl_group = group, hl_eol = true, priority = 110,
  })
end

local function decorate(state, session, items)
  for _, buf in ipairs(state.buffers) do clear_buffer(buf) end
  for _, item in ipairs(items) do
    paint(session.original_bufnr, item.original, item.original.line_hl)
    paint(session.modified_bufnr, item.modified, item.modified.line_hl)
    paint(session.result_bufnr, item.result, item.line_hl)
    local suffix = item.result.empty and " (Deleted)" or ""
    vim.api.nvim_buf_set_extmark(session.result_bufnr, namespace, item.result.anchor_row, 0, {
      virt_text = { { "  [" .. item.label .. suffix .. "]", item.hl } },
      virt_text_pos = "eol", hl_mode = "combine", priority = 210,
    })
  end
  paint_generation = paint_generation + 1
  state.painted = paint_generation
end

--- Refresh only when the inputs, Result text, layout or palette change; never writes source text.
--- @param session table Current CodeDiff merge session
--- @return table|nil presentation Cached block labels and decoration metadata
function M.refresh(session)
  if not configured then highlights(); configured = true end
  local state = state_for(session)
  if not state then return nil end
  local key = {
    vim.api.nvim_buf_get_changedtick(session.original_bufnr), vim.api.nvim_buf_get_changedtick(session.modified_bufnr),
    vim.api.nvim_buf_get_changedtick(session.result_bufnr), vim.api.nvim_win_get_position(session.original_win)[2],
    vim.api.nvim_win_get_position(session.modified_win)[2], palette_generation,
  }
  if state.cached and state.painted == paint_generation and vim.deep_equal(state.key, key) then return state.cached end
  local current = seq(session.result_bufnr)
  local evidence, items = state.history[current] or {}, {}
  for index, block in ipairs(session.conflict_blocks) do
    local data = block_data(session, block)
    items[index] = classify(session, block, index, data, evidence[index])
  end
  decorate(state, session, items)
  state.key, state.cached = key, { blocks = items, seq = current, tab = state.tab, result = state.result }
  return state.cached
end

--- Get one current block; accepted labels require recorded action evidence, not text equality alone.
--- @param session table Current CodeDiff merge session
--- @param block_or_index table|number Conflict block object or its one-based index
--- @return table|nil item Source label, code, ranges and input decisions
function M.get(session, block_or_index)
  local presentation = M.refresh(session)
  if not presentation then return nil end
  if type(block_or_index) == "number" then return presentation.blocks[block_or_index] end
  for _, item in ipairs(presentation.blocks) do if item.block == block_or_index then return item end end
end

--- Record a successfully applied action using hashes and semantic roles, bounded to 64 undo states.
--- @param session table Current CodeDiff merge session
--- @param targets table|nil One block, an explicit block array, or nil for every block
--- @param action string ours|theirs|both|base as passed to the native resolution layer
--- @param before_seq number|nil Undo sequence immediately before the action
function M.record(session, targets, action, before_seq)
  local state = state_for(session)
  if not state then return end
  local selected = {}
  if targets and targets.base_range then selected[targets] = true
  elseif targets then for _, block in ipairs(targets) do selected[block] = true end
  else for _, block in ipairs(session.conflict_blocks) do selected[block] = true end end
  local snapshot = {}
  local previous = state.history[before_seq] or {}
  for index, block in ipairs(session.conflict_blocks) do
    local data = block_data(session, block)
    local hash = fingerprint(data.result_lines)
    if selected[block] then
      if action ~= "base" and action_matches(session, block, data, action) then snapshot[index] = { hash = hash, action = action } end
    elseif previous[index] and previous[index].hash == hash then
      snapshot[index] = { hash = hash, action = previous[index].action }
    end
  end
  local current = seq(session.result_bufnr)
  if not state.history[current] then state.order[#state.order + 1] = current end
  state.history[current] = snapshot
  while #state.order > history_limit do state.history[table.remove(state.order, 1)] = nil end
  state.key = nil
  M.refresh(session)
end

--- Remove this adapter's decorations and bounded provenance for one tab or all active states.
--- @param tabpage number|nil Tab page to clear; nil clears all presentation state
function M.clear(tabpage)
  local remove = {}
  for _, state in pairs(states) do if not tabpage or state.tab == tabpage then remove[#remove + 1] = state end end
  for _, state in ipairs(remove) do dispose(state) end
end

--- Install only the presentation palette lifecycle; root controls own refresh and file selection.
function M.setup()
  highlights()
  configured = true
  local group = vim.api.nvim_create_augroup("UserCodeDiffMergePresentation", { clear = true })
  local function update_palette()
    highlights()
    for _, state in pairs(states) do state.key = nil end
    vim.schedule(function()
      local controls = package.loaded["user.codediff_merge_controls"]
      if controls and controls.refresh then controls.refresh(true) end
    end)
  end
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = update_palette })
  vim.api.nvim_create_autocmd("OptionSet", { group = group, pattern = "background", callback = update_palette })
end

--- Release only this module's namespace, metadata and palette autocmd ownership.
function M.teardown()
  M.clear()
  pcall(vim.api.nvim_del_augroup_by_name, "UserCodeDiffMergePresentation")
  configured = false
end

return M
