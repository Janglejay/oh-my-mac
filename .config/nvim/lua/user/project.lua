-- 保留当前实际使用的自动项目根定位，不依赖项目管理插件或 LSP 后端。
local M = {}
local markers = { ".git", "_darcs", ".hg", ".bzr", ".svn", "Makefile", "package.json" }
local project_markers = { ".git", "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "package.json", "Makefile" }
local entry_files = { "README.md", "README.rst", "README", "pom.xml", "build.gradle.kts", "build.gradle", "package.json", "Cargo.toml", "go.mod", "Makefile" }
local recent = {}
local home = vim.uv.fs_realpath(vim.fn.expand("~"))

local function path_for(value)
  if not value or value == "" then return nil end
  local path = vim.fn.fnamemodify(vim.fn.expand(value), ":p")
  local stat = vim.uv.fs_stat(path)
  if not stat then return nil end
  if stat.type ~= "directory" then path = vim.fs.dirname(path) end
  return path and vim.uv.fs_realpath(path) or path
end

---Return the Git root when available, otherwise the nearest build/project root.
---This is intentionally separate from root(): changing the automatic cwd
---semantics would be surprising in an existing Neovim session.
---@param value string|nil a file or directory
---@return string|nil
function M.find_project_root(value)
  local path = path_for(value)
  if not path then return nil end
  local git = vim.fs.root(path, { ".git" })
  if git and git ~= home then return git end
  local root = vim.fs.root(path, project_markers)
  if root ~= home then return root end
end

local function existing_file(path)
  if path == "" or path:match("^%a[%w+.-]*://") then return end
  local real = vim.uv.fs_realpath(path)
  local stat = real and vim.uv.fs_stat(real)
  if stat and stat.type == "file" and not real:find("/.git/", 1, true) and vim.fn.filereadable(real) == 1 then
    return real
  end
end

local function remember(bufnr)
  if vim.bo[bufnr].buftype ~= "" or not vim.bo[bufnr].buflisted then return end
  local file = existing_file(vim.api.nvim_buf_get_name(bufnr))
  if not file or recent[1] == file then return end
  for i, previous in ipairs(recent) do
    if previous == file then table.remove(recent, i); break end
  end
  table.insert(recent, 1, file)
  recent[101] = nil
end

local function history()
  local files = vim.list_extend({}, recent)
  -- ShaDa's numbered file marks record the last file of each editing session.
  local numbered = {}
  for _, mark in ipairs(vim.fn.getmarklist()) do
    local digit = mark.mark:match("^'(%d)$")
    if digit then numbered[tonumber(digit)] = mark.file end
  end
  for i = 0, 9 do if numbered[i] then files[#files + 1] = numbered[i] end end
  return vim.list_extend(files, vim.v.oldfiles)
end

local function recent_file(root)
  for _, name in ipairs(history()) do
    local file = existing_file(name)
    if file and (not root or vim.startswith(file, root .. "/")) then
      local actual = M.find_project_root(file)
      if actual and (not root or actual == root) then return file end
    end
  end
end

local function project_file(root)
  local file = recent_file(root)
  if file then return file end
  for _, name in ipairs(entry_files) do
    file = existing_file(root .. "/" .. name)
    if file and vim.startswith(file, root .. "/") and M.find_project_root(file) == root then return file end
  end
  if vim.fn.executable("rg") ~= 1 then return end
  local ok, job = pcall(vim.system, { "rg", "--no-config", "--files", "--null", "--sort", "path",
    "-g", "!**/target/**", "-g", "!**/node_modules/**", "-g", "!**/build/**" }, { cwd = root, timeout = 1000 })
  if not ok then return end
  local result = job:wait()
  if result.code ~= 0 then return end
  for name in (result.stdout or ""):gmatch("[^%z]+") do
    file = existing_file(root .. "/" .. name)
    if file and vim.startswith(file, root .. "/") and M.find_project_root(file) == root then
      local fd = vim.uv.fs_open(file, "r", 0)
      if fd then
        local sample = vim.uv.fs_read(fd, 1024, 0)
        vim.uv.fs_close(fd)
        if sample and not sample:find("\0", 1, true) then return file end
      end
    end
  end
end

local function open_recent()
  if not vim.g.neovide or vim.fn.argc() > 0 or vim.v.this_session ~= "" or vim.tbl_contains(vim.v.argv, "-") then return end
  if vim.api.nvim_buf_get_name(0) ~= "" or vim.bo.buftype ~= "" or vim.bo.modified
      or vim.api.nvim_buf_line_count(0) ~= 1 or vim.api.nvim_get_current_line() ~= "" then return end
  local file = recent_file()
  local root = M.find_project_root(file or vim.fn.getcwd())
  if not file and root then file = project_file(root) end
  if file and root then
    vim.api.nvim_set_current_dir(root)
    vim.cmd.edit({ args = { file }, magic = { file = false, bar = false } })
  end
end

local function candidate_roots()
  local roots, seen = {}, {}
  local function add(value)
    local root = M.find_project_root(value)
    if root then
      root = vim.uv.fs_realpath(root) or root
      if not seen[root] then
        seen[root] = true
        roots[#roots + 1] = root
      end
    end
  end

  -- Do not crawl the disk: only offer this instance's current and previously
  -- visited projects, which keeps gw immediate even in a large source tree.
  local cwd = vim.fn.getcwd()
  add(cwd)
  add(vim.api.nvim_buf_get_name(0))
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    add(vim.t[tab].switch_project_root)
  end
  for _, file in ipairs(history()) do add(file) end
  table.sort(roots, function(a, b)
    if (a == cwd) ~= (b == cwd) then return a == cwd end
    return a:lower() < b:lower()
  end)
  return roots
end

local function set_tab_root(root)
  if vim.fn.getcwd(-1, 0) ~= root or vim.fn.haslocaldir(-1, 0) ~= 2 then
    -- Snacks listens for DirChanged in every open Explorer, including other tabs.
    vim.cmd.tcd({ args = { root }, magic = { file = false, bar = false }, mods = { noautocmd = true } })
    if package.loaded["snacks.picker"] then
      for _, explorer in ipairs(Snacks.picker.get({ source = "explorer" })) do
        if explorer:cwd() ~= root then
          explorer:set_cwd(root)
          explorer:find()
        end
      end
    end
    local lathe = package.loaded["user.lathe_live"]
    if lathe then lathe.ensure_directory(root) end
  end
end

local function focus_project_tab(tab)
  if vim.api.nvim_get_current_tabpage() == tab then return end
  -- Switching tab-local directories emits DirChanged even without a :tcd call.
  local ignored = vim.o.eventignore
  vim.opt.eventignore:append("DirChanged")
  local ok, err = pcall(vim.api.nvim_set_current_tabpage, tab)
  vim.o.eventignore = ignored
  if not ok then error(err) end
end

local function open_project(root)
  local tabs = vim.api.nvim_list_tabpages()
  local current = vim.api.nvim_get_current_tabpage()
  -- Match canonical paths, so separate worktrees of the same repo stay separate.
  for _, tab in ipairs(tabs) do
    if vim.t[tab].switch_project_root == root then
      focus_project_tab(tab)
      set_tab_root(root)
      return
    end
  end
  table.insert(tabs, 1, current)
  local diff = package.loaded["codediff.ui.lifecycle"]
  for _, tab in ipairs(tabs) do
    if not vim.t[tab].switch_project_root and not (diff and diff.get_session(tab)) then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].buftype == "" and M.find_project_root(vim.api.nvim_buf_get_name(buf)) == root then
          focus_project_tab(tab)
          vim.t.switch_project_root = root
          set_tab_root(root)
          vim.api.nvim_set_current_win(win)
          return
        end
      end
    end
  end
  local file = project_file(root)
  vim.cmd.tabnew()
  vim.t.switch_project_root = root
  set_tab_root(root)
  if file then vim.cmd.edit({ args = { file }, magic = { file = false, bar = false } }) end
end

function M.switch()
  remember(vim.api.nvim_get_current_buf())
  local roots = candidate_roots()
  if #roots == 0 then
    vim.notify("Switch Project: no known project roots", vim.log.levels.WARN)
    return
  end
  local items = {}
  for _, root in ipairs(roots) do
    items[#items + 1] = {
      root = root,
      text = vim.fn.fnamemodify(root, ":t"),
      file = root,
    }
  end
  Snacks.picker({
    title = "Switch Project",
    items = items,
    preview = "none",
    layout = { preset = "select", preview = false },
    matcher = { fuzzy = true, sort_empty = true, filename_bonus = false },
    format = function(item)
      return {
        { item.text, "Title" },
        { "  " .. vim.fn.fnamemodify(item.root, ":~"), "Comment" },
      }
    end,
    actions = {
      confirm = function(picker, item)
        picker:close()
        if item then open_project(item.root) end
      end,
    },
  })
end

function M.root(bufnr)
  bufnr = bufnr or 0
  if not vim.api.nvim_buf_is_valid(bufnr) then return nil end
  local buftype = vim.bo[bufnr].buftype
  if buftype ~= "" and buftype ~= "acwrite" then return nil end
  local filename = vim.api.nvim_buf_get_name(bufnr)
  if filename == "" or filename:match("^%a[%w+.-]*://") then return nil end
  if vim.g.neovide then
    local root = M.find_project_root(filename)
    if root then return root end
  end
  local directory = vim.fs.dirname(filename)
  if not directory or not vim.uv.fs_stat(directory) then return nil end
  -- 同组标记按目录距离匹配，保持旧配置“最近项目根”的语义。
  local root = vim.fs.root(directory, { markers })
  if not vim.g.neovide or root ~= home then return root end
end

function M.update(bufnr)
  local project = vim.t.switch_project_root
  if project then
    set_tab_root(project)
    return project
  end
  local root = M.root(bufnr)
  if root then
    if vim.g.neovide then
      set_tab_root(root)
    elseif vim.fn.getcwd() ~= root then
      vim.api.nvim_set_current_dir(root)
    end
  end
  return root
end

function M.setup()
  vim.opt.autochdir = false
  local group = vim.api.nvim_create_augroup("UserProjectRoot", { clear = true })
  vim.api.nvim_create_autocmd({ "VimEnter", "BufEnter" }, {
    group = group,
    nested = not not vim.g.neovide,
    callback = function(ev)
      if vim.v.vim_did_enter == 1 then
        remember(ev.buf)
        M.update(ev.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimEnter", { group = group, once = true, nested = true, callback = open_recent })
  vim.api.nvim_create_user_command("ProjectRoot", function() M.update(0) end,
    { desc = "Set current project root", force = true })
  vim.api.nvim_create_user_command("SwitchProject", M.switch,
    { desc = "Switch to a known project in the current window", force = true })
end

return M
