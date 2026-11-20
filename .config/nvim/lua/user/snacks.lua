local M = {}
local terminal_height = 20

function M.terminal(cmd)
  local term = Snacks.terminal.get(cmd, { create = false })
  if term then
    if term:win_valid() then
      terminal_height = vim.api.nvim_win_get_height(term.win)
      term.opts.height = terminal_height
    end
    return term:toggle()
  end
  return Snacks.terminal(cmd, { win = { position = "bottom", height = terminal_height } })
end

function M.explorer_toggle()
  local explorer = Snacks.picker.get({ source = "explorer" })[1]
  if explorer then explorer:close() else Snacks.explorer({ cwd = vim.fn.getcwd() }) end
end

local function compact_explorer_finder(opts, ctx)
  local find = require("snacks.picker.source.explorer").explorer(opts, ctx)
  if not opts.tree or not ctx.filter:is_empty() then return find end

  return function(emit)
    local items, only_child, merged = {}, {}, {}
    find(function(item)
      items[#items + 1] = item
      if item.parent then
        if only_child[item.parent] == nil then
          only_child[item.parent] = item
        else
          only_child[item.parent] = false
        end
      end
    end)

    for _, item in ipairs(items) do
      if not merged[item] then
        local leaf = item
        local names = {}
        local child = only_child[leaf]
        -- Keep the project root and stop at branches, files, and symlinks.
        while item.parent and leaf.type == "directory" and child and child.type == "directory" do
          names[#names + 1] = vim.fs.basename(leaf.file)
          child.hidden = child.hidden or leaf.hidden
          child.ignored = child.ignored or leaf.ignored
          merged[child] = true
          leaf = child
          child = only_child[leaf]
        end
        if leaf ~= item then
          names[#names + 1] = vim.fs.basename(leaf.file)
          leaf.compact_name = table.concat(names, ".")
          leaf.parent, leaf.last = item.parent, item.last
        end
        emit(leaf)
      end
    end
  end
end

local function format_explorer_item(item, picker)
  local chunks = require("snacks.picker.format").file(item, picker)
  for _, chunk in ipairs(chunks) do
    if chunk[2] == "SnacksPickerTree" then
      local guides = { item.last and "└" or "├" }
      local parent = item.parent
      while parent and parent.parent do
        guides[#guides + 1] = parent.last and " " or "│"
        parent = parent.parent
      end
      local indent = {}
      for i = #guides, 1, -1 do
        indent[#indent + 1] = guides[i]
      end
      chunk[1] = table.concat(indent)
    elseif item.compact_name and chunk.field == "file" then
      chunk[1] = item.compact_name
      break
    end
  end
  return chunks
end

local function jump_explorer_directory(picker, direction)
  local list = picker.list
  local last = direction > 0 and list:count() or 1
  for index = list.cursor + direction, last, direction do
    local item = list:get(index)
    if item and item.dir then
      list:view(index)
      return
    end
  end
end

local function expand_explorer_branch(tree, root, visible)
  local changed = not root.open
  root.open = true
  if not root.expanded then tree:expand(root) end
  -- Expansion state only depends on directories. The picker sorts display rows separately.
  for _, child in pairs(root.children) do
    -- Directory symlinks can leave the project or point back to an ancestor.
    if child.type == "directory" and visible(child) then
      if expand_explorer_branch(tree, child, visible) then changed = true end
    end
  end
  return changed
end

local function close_explorer_branch(root)
  root.open = false
  for _, child in pairs(root.children) do
    if child.dir then close_explorer_branch(child) end
  end
end

local function toggle_explorer_tree(picker)
  local tree = require("snacks.explorer.tree")
  local actions = require("snacks.explorer.actions")
  local cwd = picker:cwd()
  local root = tree:find(cwd)
  local visible = tree:filter(picker.opts)
  tree:expand(root)

  for _, child in pairs(root.children) do
    if child.dir and child.open and visible(child) then
      close_explorer_branch(root)
      actions.update(picker, { target = cwd, refresh = true })
      return
    end
  end

  expand_explorer_branch(tree, root, visible)
  actions.update(picker, { target = cwd, refresh = true })
end

local function toggle_explorer_directory(picker, item)
  if not item then return end
  local path = Snacks.picker.util.path(item)
  if not path then return end
  local dir = item.dir and path or vim.fs.dirname(path)
  local tree = require("snacks.explorer.tree")
  local cwd = picker:cwd()
  -- The root row and files directly under it must never invoke a project-wide toggle.
  if dir == cwd or not vim.fs.relpath(cwd, dir) then return end
  local branch = tree:find(dir)
  local visible = tree:filter(picker.opts)
  if branch.type == "link" then
    tree:toggle(dir)
  elseif not expand_explorer_branch(tree, branch, visible) then
    close_explorer_branch(branch)
  end

  -- After expansion, the selected path may become part of a compact row.
  -- Follow its visible directory chain so a second z acts on that row.
  local target = branch
  while target.open and target.type == "directory" do
    local only_child
    for _, child in pairs(target.children) do
      if visible(child) then
        if only_child then
          only_child = nil
          break
        end
        only_child = child
      end
    end
    if not only_child or only_child.type ~= "directory" then break end
    target = only_child
  end
  require("snacks.explorer.actions").update(picker, { target = target.path, refresh = true })
end

function M.setup()
  require("snacks").setup({
    picker = {
      enabled = true, ui_select = true,
      layout = { preset = "default", layout = { width = 0.92, height = 0.85 } },
      jump = { reuse_win = false },
      sources = {
        files = { hidden = true, exclude = { ".git", "target", "node_modules" } },
        explorer = {
          finder = compact_explorer_finder,
          format = format_explorer_item,
          hidden = true, ignored = true, exclude = { ".git", "node_modules", ".cache" },
          follow_file = true, git_status = true, git_untracked = true, diagnostics = true,
          layout = { preset = "sidebar", preview = false, layout = { width = 48 } },
          actions = {
            toggle_current_directory = { action = toggle_explorer_directory, desc = "Toggle Directory Recursively" },
            toggle_all_directories = { action = toggle_explorer_tree, desc = "Toggle All Directories" },
            next_directory = { action = function(p) jump_explorer_directory(p, 1) end, desc = "Next Directory" },
            prev_directory = { action = function(p) jump_explorer_directory(p, -1) end, desc = "Previous Directory" },
          },
          win = { list = { keys = {
            ["z"] = "toggle_current_directory",
            ["Z"] = "toggle_all_directories",
            ["J"] = "next_directory", ["K"] = "prev_directory",
            ["h"] = false, ["l"] = false, ["<CR>"] = "confirm",
            ["<Left>"] = false, ["<Right>"] = false,
          } } },
        },
      },
    },
    explorer = { enabled = true },
    terminal = { enabled = true, win = { keys = { term_normal = false } } },
    -- Optional dashboards, animations, GitHub integration, notifications, etc. stay disabled.
  })
  require("user.navigation").setup()
  vim.keymap.set({ "n", "t", "i" }, "<C-\\>", function() M.terminal() end,
    { silent = true, desc = "Terminal" })
  vim.api.nvim_create_autocmd("TermOpen", {
    group = vim.api.nvim_create_augroup("UserTerminalKeys", { clear = true }),
    callback = function(ev)
      local opts = { buffer = ev.buf, silent = true }
      vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], opts)
      vim.keymap.set("t", "jk", [[<C-\><C-n>]], opts)
      for _, key in ipairs({ "h", "j", "k", "l" }) do
        vim.keymap.set("t", "<C-" .. key .. ">", [[<C-\><C-n><C-w>]] .. key, opts)
      end
    end,
  })
  _G._LAZYGIT_TOGGLE = function()
    Snacks.terminal("lazygit", { win = { position = "float", width = 0.95, height = 0.92,
      keys = { { "q", "hide", mode = "t" } } } })
  end
end

return M
