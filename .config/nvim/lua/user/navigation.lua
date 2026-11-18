-- Shared navigation UI for every language; LSP backends do not own the keymaps.
local M = {}

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
  return Snacks.picker({
    title = "Search Everywhere — Files",
    cwd = M.root(),
    live = true,
    finder = strict_files,
    format = "file",
    preview = "file",
    matcher = { fuzzy = false, sort_empty = true },
    jump = { reuse_win = false, jumplist = true },
  })
end

function M.root()
  local path = vim.fs.root(0, { { "pom.xml", "build.gradle", "mvnw", "gradlew" } }) or vim.fn.getcwd()
  local parent = vim.fs.dirname(path)
  while parent and parent ~= path and vim.fn.filereadable(parent .. "/pom.xml") == 1 do
    path, parent = parent, vim.fs.dirname(parent)
  end
  return path
end

function M.items(title, items)
  return Snacks.picker({
    title = title, items = items, preview = "file",
    format = function(item) return { { item.text } } end,
    jump = { reuse_win = false, jumplist = true },
  })
end

function M.references()
  if vim.bo.filetype == "java" then
    if require("user.java_dependency_usages").at_field() then return end
    local dependency = package.loaded["user.java_dependency_navigation"]
    if dependency and dependency.references_at_field() then return end
    return Snacks.picker.lsp_references({
      title = "Find Java Usages", include_declaration = false,
      auto_confirm = false, jump = { reuse_win = false },
    })
  end
  return Snacks.picker.lsp_references({
    title = "Find Usages (remove !.m2 to include dependencies)", pattern = "!.m2",
    auto_confirm = false, jump = { reuse_win = false },
  })
end

function M.definitions()
  return Snacks.picker.lsp_definitions({ jump = { reuse_win = false } })
end

function M.implementations()
  local function picker() return Snacks.picker.lsp_implementations({ jump = { reuse_win = false } }) end
  if not require("user.mybatis_navigation").implementation(picker) then return picker() end
end

function M.project_symbols()
  if vim.bo.filetype ~= "java" then
    if #vim.lsp.get_clients({ bufnr = 0, method = "workspace/symbol" }) > 0 then
      return Snacks.picker.lsp_workspace_symbols({ jump = { reuse_win = false } })
    end
    return project_files()
  end
  return Snacks.picker({
    title = "Search Everywhere — Classes / Methods",
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
