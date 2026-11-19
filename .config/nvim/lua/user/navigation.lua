-- Shared navigation UI for every language; LSP backends do not own the keymaps.
local M = {}

local test_exclusion = "scope:!test"
local search_title_hint = " · 删除 scope:!test 可包含测试路径"
local test_dirs = {
  test = true, tests = true, __tests__ = true, testfixtures = true,
  ["test-fixtures"] = true, ["test-classes"] = true,
  ["generated-test-sources"] = true, ["generated-test-resources"] = true,
  integrationtest = true, integrationtests = true, ["integration-test"] = true, ["integration-tests"] = true,
}

local function mark_path_scope(item, ctx)
  local path = Snacks.picker.util.path(item)
  item.scope = "source"
  if not path then return end
  local prefix = ctx:cwd() .. "/"
  if vim.startswith(path, prefix) then path = path:sub(#prefix + 1) end
  for dir in path:gmatch("([^/]+)/") do
    if test_dirs[dir:lower()] then
      item.scope = "test"
      return
    end
  end
end

local usage_order = {
  transform = mark_path_scope,
  matcher = { sort_empty = true },
  sort = { fields = { "scope", "score:desc", "#text", "idx" } },
}

local function live_search(opts)
  opts.title = opts.title .. search_title_hint
  opts.search = test_exclusion
  opts.filter = {
    transform = function(picker, filter)
      -- Keep the token in the visible input, but pass only the query to the finder.
      local query, count = (" " .. filter.search .. " "):gsub("%s" .. vim.pesc(test_exclusion) .. "%f[%s]", "")
      filter.search, filter.exclude_test_paths = vim.trim(query), count > 0
      local previous = picker.finder.filter
      return previous and previous.exclude_test_paths ~= filter.exclude_test_paths
    end,
  }
  opts.transform = function(item, ctx)
    mark_path_scope(item, ctx)
    return not ctx.filter.exclude_test_paths or item.scope ~= "test"
  end
  return opts
end

-- Search Everywhere should behave like an IDE file search: match a contiguous
-- filename fragment (AwardsController -> awardscontr), or CamelCase initials
-- (MerchantActivityResponseMapper -> MARM).  Do not accept arbitrary
-- characters scattered through a long path.
local function filename_words(path)
  local name = vim.fn.fnamemodify(path, ":t"):gsub("%.[^.]+$", "")
  name = name:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2")
  local words = {}
  for word in name:gmatch("[%a%d]+") do
    words[#words + 1] = word:lower()
  end
  return words
end

local function compact(value)
  return value:lower():gsub("[^%a%d]", "")
end

local function camel_prefix_match(query, words, query_at, word_at)
  if query_at > #query then return true end
  for index = word_at, #words do
    local word = words[index]
    for length = 1, math.min(#word, #query - query_at + 1) do
      if word:sub(1, length) ~= query:sub(query_at, query_at + length - 1) then break end
      if camel_prefix_match(query, words, query_at + length, index + 1) then return true end
    end
  end
  return false
end

local function strict_file_match(path, query)
  query = compact(query)
  if query == "" then return true, 0 end

  local filename = vim.fn.fnamemodify(path, ":t")
  if compact(filename):find(query, 1, true) then return true, 100 end

  local words = filename_words(filename)
  if camel_prefix_match(query, words, 1, 1) then return true, 40 end
  return false, 0
end

local function strict_files(opts, ctx)
  local cwd = ctx:cwd()
  return require("snacks.picker.source.proc").proc(ctx:opts({
    cmd = "rg",
    args = { "--files", "--no-messages", "--color=never", "-g", "!.git", "-g", "!*/target/*" },
    cwd = cwd,
    notify = false,
    transform = function(item)
      local matched, score = strict_file_match(item.text, ctx.filter.search)
      if not matched then return false end
      item.cwd, item.file, item.score_add = cwd, item.text, score
    end,
  }), ctx)
end

local function project_files()
  return Snacks.picker(live_search({
    title = "Search Everywhere — Files",
    cwd = M.root(),
    live = true,
    finder = strict_files,
    format = "file",
    preview = "file",
    matcher = { fuzzy = false, sort_empty = true },
    jump = { reuse_win = false, jumplist = true },
  }))
end

function M.root()
  local path = vim.fs.root(0, { { "pom.xml", "build.gradle", "mvnw", "gradlew" } }) or vim.fn.getcwd()
  local parent = vim.fs.dirname(path)
  while parent and parent ~= path and vim.fn.filereadable(parent .. "/pom.xml") == 1 do
    path, parent = parent, vim.fs.dirname(parent)
  end
  return path
end

function M.items(title, items, opts)
  return Snacks.picker(vim.tbl_deep_extend("force", {
    title = title, items = items, preview = "file",
    format = function(item) return { { item.text } } end,
    jump = { reuse_win = false, jumplist = true },
  }, opts or {}))
end

function M.usage_items(title, items)
  return M.items(title .. " · 测试路径排最后", items, usage_order)
end

function M.references()
  if vim.bo.filetype == "java" then
    if require("user.java_dependency_usages").at_field() then return end
    local dependency = package.loaded["user.java_dependency_navigation"]
    if dependency and dependency.references_at_field() then return end
    local function picker()
      return Snacks.picker.lsp_references(vim.tbl_deep_extend("force", usage_order, {
        title = "Find Java Usages · 测试路径排最后", include_declaration = false,
        auto_confirm = false, jump = { reuse_win = false },
      }))
    end
    local function java_references()
      if not require("user.mybatis_navigation").java_references(picker) then return picker() end
    end
    if require("user.spring_navigation").run(false, java_references) then return end
    return java_references()
  end
  return Snacks.picker.lsp_references(vim.tbl_deep_extend("force", usage_order, {
    title = "Find Usages · 测试路径排最后 · 删除 !.m2 可包含依赖", pattern = "!.m2",
    auto_confirm = false, jump = { reuse_win = false },
  }))
end

function M.definitions()
  return Snacks.picker.lsp_definitions(vim.tbl_deep_extend("force", usage_order, {
    title = "Go to Definition · 测试路径排最后", jump = { reuse_win = false },
  }))
end

function M.implementations()
  local function picker() return Snacks.picker.lsp_implementations({ jump = { reuse_win = false } }) end
  if not require("user.mybatis_navigation").implementation(picker) then return picker() end
end

function M.project_symbols()
  if vim.bo.filetype ~= "java" then
    if #vim.lsp.get_clients({ bufnr = 0, method = "workspace/symbol" }) > 0 then
      return Snacks.picker.lsp_workspace_symbols(live_search({
        title = "Project Symbols", jump = { reuse_win = false },
      }))
    end
    return project_files()
  end
  return Snacks.picker({
    title = "Search Everywhere — Classes / Methods" .. search_title_hint,
    pattern = test_exclusion, transform = mark_path_scope,
    cwd = M.root(), preview = "file",
    finder = function(_, ctx)
      return require("snacks.picker.source.proc").proc(ctx:opts({
        cmd = "rg", cwd = ctx:cwd(), notify = false,
        args = { "-tjava", "-n", "--no-heading", "--color=never",
          "-e", "(class|interface|enum|@interface)\\s+\\w+",
          "-e", "\\s+(public|protected|private)\\s+\\S+\\s+\\w+\\s*\\(",
          "--glob", "!*/target/*", "--glob", "!*/.git/*", "." },
        transform = function(item)
          local file, lnum, content = item.text:match("^(.+):(%d+):(.*)")
          if not file then return false end
          local sym = content:match("[Cc]lass%s+(%w+)") or content:match("[Ii]nterface%s+(%w+)")
            or content:match("[Ee]num%s+(%w+)") or content:match("%s(%w+)%s*%(") or "?"
          local kind = content:match("class") and "Class" or content:match("interface") and "Interface"
            or content:match("enum") and "Enum" or "Method"
          item.file = vim.fs.normalize(ctx:cwd() .. "/" .. file)
          item.pos = { tonumber(lnum), 0 }
          local qualified = file:match("/src/[^/]+/java/(.+)%.java$")
            or file:match("^src/[^/]+/java/(.+)%.java$")
            or vim.fn.fnamemodify(file, ":t:r")
          qualified = qualified:gsub("/", ".")
          item.text = kind == "Method" and (qualified .. "." .. sym .. "()") or qualified
          item.display = string.format("%-36s %-9s %s:%s", sym, kind, file, lnum)
        end,
      }), ctx)
    end,
    format = function(item) return { { item.display } } end,
    jump = { reuse_win = false, jumplist = true },
  })
end

function M.setup()
  local function map(key, fn, desc) vim.keymap.set("n", key, fn, { silent = true, desc = desc }) end
  map("<Leader>f", M.project_symbols, "Search Everywhere")
  map("<Leader>F", function() Snacks.picker.grep({ cwd = M.root() }) end, "Find in Files")
  map("<Leader>e", function() Snacks.picker.recent({ filter = { cwd = true } }) end, "Recent Files")
  map("<Leader>b", function() Snacks.picker.buffers() end, "Switch Editor")
  map("<Leader>p", function() Snacks.explorer.reveal() end, "Select In Project")
  map("gr", M.references, "Find Usages")
  map("gi", M.implementations, "Go to Implementation")
  map("qi", M.implementations, "Quick Implementations")
  map("gR", "<cmd>Lspsaga incoming_calls<CR>", "Call Hierarchy")
  map("<Leader>go", function() Snacks.picker.git_status() end, "Local Changes")
  map("<Leader>gb", function() Snacks.picker.git_branches() end, "Branches (Checkout)")
  map("<Leader>ld", function() Snacks.picker.diagnostics_buffer() end, "File Problems")
  map("<Leader>lw", function() Snacks.picker.diagnostics() end, "Project Problems")
  map("<Leader>ls", function() Snacks.picker.lsp_symbols() end, "File Structure")
  map("<Leader>lS", function() Snacks.picker.lsp_workspace_symbols() end, "Project Symbols")
  -- Existing secondary aliases remain available, hidden from the main Which-key menu.
  local aliases = { Sb = "git_branches", Sc = "colorschemes", Sh = "help", SM = "man", Sr = "recent",
    SR = "registers", Sk = "keymaps", SC = "commands" }
  for key, source in pairs(aliases) do
    map("<Leader>" .. key, function() Snacks.picker[source]() end, source)
  end
  map("<Leader>la", vim.lsp.buf.code_action, "Context Actions")
  map("<Leader>lf", function() vim.lsp.buf.format({ async = true }) end, "Format")
  map("<Leader>lj", function() vim.diagnostic.jump({ count = 1, float = true }) end, "Next Problem")
  map("<Leader>lk", function() vim.diagnostic.jump({ count = -1, float = true }) end, "Previous Problem")
  map("<Leader>ll", vim.lsp.codelens.run, "CodeLens Action")
  map("<Leader>lq", vim.diagnostic.setloclist, "Problems List")
  map("<Leader>lr", function() require("user.lathe_live").refresh(0, false) end, "Reload Project")
  map("<Leader>lR", function() require("user.lathe_live").refresh(0, true) end, "Rebuild Index")
end

return M
