-- Shared navigation UI for every language; LSP backends do not own the keymaps.
local M = {}

local test_exclusion = "scope:!test"
local default_scope = test_exclusion .. " "
local search_title_hint = " · Remove scope:!test to include test paths"
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
  opts.search = default_scope
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
  if vim.g.neovide then
    local root = require("user.project").root(0)
    if root then return root end
  end
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
  return M.items(title .. " · Test paths last", items, usage_order)
end

function M.references(skip_spring)
  if vim.bo.filetype == "java" then
    if require("user.java_dependency_usages").at_field() then return end
    local dependency = package.loaded["user.java_dependency_navigation"]
    if dependency and dependency.references_at_field() then return end
    local function java_references(extra)
      local function picker()
        local opts = vim.tbl_deep_extend("force", usage_order, {
          title = "Find Java Usages · Test paths last", include_declaration = false,
          auto_confirm = false, jump = { reuse_win = false },
        })
        if not extra or #extra == 0 then return Snacks.picker.lsp_references(opts) end
        opts.multi = { "lsp_references", {
          finder = function() return extra end,
          format = function(item) return { { item.text } } end,
        } }
        return Snacks.picker(opts)
      end
      if not require("user.mybatis_navigation").java_references(picker, extra) then return picker() end
    end
    local function references()
      if not require("user.java_constructor_usages").at_field(java_references) then return java_references() end
    end
    if not skip_spring and require("user.spring_navigation").run(false, references) then return end
    return references()
  end
  return Snacks.picker.lsp_references(vim.tbl_deep_extend("force", usage_order, {
    title = "Find Usages · Test paths last · Remove !.m2 to include dependencies", pattern = "!.m2",
    auto_confirm = false, jump = { reuse_win = false },
  }))
end

function M.at_definition(row, column)
  local cursor = vim.api.nvim_win_get_cursor(0)
  if cursor[1] ~= row then return false end
  if cursor[2] == column then return true end
  local line = vim.api.nvim_get_current_line()
  local offset = 0
  while offset <= math.min(cursor[2], column) do
    local _, first, last = unpack(vim.fn.matchstrpos(line, [[\k\+]], offset))
    if first < 0 or first > math.min(cursor[2], column) then return false end
    if cursor[2] < last then return column < last end
    offset = last
  end
  return false
end

function M.definitions(locations, encodings)
  local lsp = require("snacks.picker.source.lsp")
  local origin = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
  local buffers = lsp.bufmap()
  local items, by_encoding, seen = {}, {}, {}
  for i, location in ipairs(locations) do
    local encoding = encodings[i]
    by_encoding[encoding] = by_encoding[encoding] or {}
    table.insert(by_encoding[encoding], location)
  end
  for encoding, group in pairs(by_encoding) do
    local entries = vim.lsp.util.locations_to_items(group, encoding)
    lsp.fix_locs(entries)
    for _, entry in ipairs(entries) do
      local at_cursor = vim.fs.normalize(entry.filename) == origin
        and M.at_definition(entry.lnum, entry.col - 1)
      local key = ("%s:%d:%d"):format(entry.filename, entry.lnum, entry.col)
      if not at_cursor and not seen[key] then
        seen[key] = true
        items[#items + 1] = {
          file = entry.filename, buf = buffers[entry.filename],
          text = entry.filename .. " " .. entry.text, line = entry.text,
          pos = { entry.lnum, entry.col - 1 },
          end_pos = entry.end_lnum and entry.end_col and { entry.end_lnum, entry.end_col - 1 } or nil,
        }
      end
    end
  end
  return Snacks.picker.lsp_definitions(vim.tbl_deep_extend("force", usage_order, {
    -- The original query already waited for every attached definition provider.
    finder = function() return items end,
    title = "Go to Definition · Test paths last", jump = { reuse_win = false },
  }))
end

function M.implementations()
  local function picker() return Snacks.picker.lsp_implementations({ jump = { reuse_win = false } }) end
  if not require("user.mybatis_navigation").implementation(picker) then return picker() end
end

local java_declarations = [[
  (class_declaration name: (identifier) @Class)
  (interface_declaration name: (identifier) @Interface)
  (annotation_type_declaration name: (identifier) @Interface)
  (enum_declaration name: (identifier) @Enum)
  (record_declaration name: (identifier) @Record)
  (method_declaration name: (identifier) @Method)
  (annotation_type_element_declaration name: (identifier) @Method)
]]

local function java_symbols(query, ctx)
  local cwd = ctx:cwd()
  local files = require("snacks.picker.source.proc").proc(ctx:opts({
    cmd = "rg", cwd = cwd, notify = false, sep = "\0",
    args = { "--files", "--null", "-tjava", "--glob", "!**/target/**", "--glob", "!**/.git/**" },
  }), ctx)

  return function(add)
    local yield = require("snacks.picker.util.async").yielder()
    local parsed = 0
    files(function(item)
      local file = item.text
      local path = vim.fs.joinpath(cwd, file)
      local handle = io.open(path, "rb")
      if not handle then return end
      local source = handle:read("*a")
      handle:close()
      if not source then return end

      local parser = vim.treesitter.get_string_parser(source, "java")
      local tree = parser:parse()[1]
      if tree then
        local qualified = (("/" .. file):match("/src/[^/]+/java/(.+)%.java$")
          or file:match("([^/]+)%.java$") or file):gsub("/", ".")
        for capture, node in query:iter_captures(tree:root(), source) do
          local kind = query.captures[capture]
          local name = vim.treesitter.get_node_text(node, source)
          local row, col = node:start()
          local symbol = qualified
          if kind == "Method" then
            symbol = qualified .. "." .. name .. "()"
          elseif qualified:match("[^.]+$") ~= name then
            symbol = qualified .. "." .. name
          end
          add({
            file = path,
            pos = { row + 1, col },
            text = symbol,
            display = string.format("%-36s %-9s ./%s:%d", name, kind, file, row + 1),
          })
        end
      end
      -- Snacks pauses automatic GC during finding. Release temporary parse
      -- trees in small batches so a large project cannot retain them all.
      parsed = parsed + 1
      if parsed % 32 == 0 then collectgarbage("step", 256) end
      yield()
    end)
  end
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
  local ok, query = pcall(vim.treesitter.query.parse, "java", java_declarations)
  if not ok then
    vim.notify("Java symbol search requires the Java Tree-sitter parser. Run :TSInstall java.", vim.log.levels.WARN)
    return project_files()
  end
  return Snacks.picker({
    title = "Search Everywhere — Classes / Methods" .. search_title_hint,
    pattern = default_scope, transform = mark_path_scope,
    cwd = M.root(), preview = "file",
    finder = function(_, ctx) return java_symbols(query, ctx) end,
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
