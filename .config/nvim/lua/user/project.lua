-- 保留当前实际使用的自动项目根定位，不依赖项目管理插件或 LSP 后端。
local M = {}
local markers = { ".git", "_darcs", ".hg", ".bzr", ".svn", "Makefile", "package.json" }
local project_markers = { ".git", "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "package.json", "Makefile" }

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
  return vim.fs.root(path, { ".git" }) or vim.fs.root(path, project_markers)
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
  add(vim.fn.getcwd())
  add(vim.api.nvim_buf_get_name(0))
  for _, file in ipairs(vim.v.oldfiles) do add(file) end
  table.sort(roots, function(a, b)
    if a == vim.fn.getcwd() then return true end
    if b == vim.fn.getcwd() then return false end
    return a:lower() < b:lower()
  end)
  return roots
end

---Build a command separately so it can be inspected without opening a GUI.
---@param root string
---@return string[]
function M.neovide_command(root)
  return { "neovide", "--reuse-instance", "--new-window", "--fork", "--chdir", root }
end

function M.open_in_neovide(root)
  local ok, err = pcall(vim.system, M.neovide_command(root), { detach = true }, function(result)
    if result.code ~= 0 then
      vim.schedule(function()
        vim.notify("Switch Project: Neovide could not open " .. root, vim.log.levels.ERROR)
      end)
    end
  end)
  if not ok then vim.notify("Switch Project: " .. tostring(err), vim.log.levels.ERROR) end
end

function M.switch()
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
    title = "Switch Project — Enter opens a new Neovide window",
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
        if item then M.open_in_neovide(item.root) end
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
  local directory = vim.fs.dirname(filename)
  if not directory or not vim.uv.fs_stat(directory) then return nil end
  -- 同组标记按目录距离匹配，保持旧配置“最近项目根”的语义。
  return vim.fs.root(directory, { markers })
end

function M.update(bufnr)
  local root = M.root(bufnr)
  if root and vim.fn.getcwd() ~= root then vim.api.nvim_set_current_dir(root) end
  return root
end

function M.setup()
  vim.opt.autochdir = false
  local group = vim.api.nvim_create_augroup("UserProjectRoot", { clear = true })
  vim.api.nvim_create_autocmd({ "VimEnter", "BufEnter" }, {
    group = group,
    callback = function(ev)
      if vim.v.vim_did_enter == 1 then M.update(ev.buf) end
    end,
  })
  vim.api.nvim_create_user_command("ProjectRoot", function() M.update(0) end,
    { desc = "Set current project root", force = true })
  vim.api.nvim_create_user_command("SwitchProject", M.switch,
    { desc = "Open a known project in a Neovide window", force = true })
end

return M
