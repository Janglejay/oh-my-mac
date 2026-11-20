local which_key = require("which-key")
local primary = { b=true, e=true, p=true, w=true, c=true, C=true, n=true, f=true, F=true, s=true,
  g=true, h=true, j=true, l=true, R=true, T=true }
local secondary = { la=true, lf=true, lj=true, lk=true, ll=true, lq=true, ls=true, lS=true }
which_key.setup({
  delay = 250,
  plugins = {
    marks = false, registers = false, spelling = { enabled = false },
    presets = { operators=false, motions=false, text_objects=false, windows=false, nav=false, z=false, g=false },
  },
  triggers = { { "<leader>", mode = "n" } },
  filter = function(mapping)
    if mapping.group then return true end
    local lhs = mapping.lhs or ""
    -- Only curate leader hints; merge-only m mappings are managed by CodeDiff.
    if lhs:sub(1, 1) ~= vim.g.mapleader then return mapping.desc ~= nil end
    local key = lhs:sub(2)
    if secondary[key] or key:sub(1,1) == "S" or key == "P" then return false end
    return primary[key] or key:match("^g") ~= nil or key:match("^h") ~= nil or key:match("^j") ~= nil
      or key == "ld" or key == "lw" or key == "lr" or key == "lR"
  end,
  icons = { breadcrumb = "»", separator = "➜", group = "+" },
  win = { border = "rounded", height = { max = 16 } },
  layout = { width = { min = 20, max = 48 }, spacing = 2 },
  show_help = false,
})
-- Descriptions only: never replace module-owned commands or context-local merge mappings.
which_key.add({
  { "<leader>g", group = "Git" },
  { "<leader>gm", group = "Merge" },
  { "<leader>h", group = "HTTP" },
  { "<leader>j", desc = "Find Word" },
  { "<leader>l", group = "Language Services" },
  { "<leader>n", desc = "Clear Search Highlight" },
  { "<leader>w", desc = "Maximize / Restore Window" },
  { "<leader>gl", desc = "Annotate Line" },
  { "<leader>gL", desc = "Annotate File" },
  { "<leader>gs", desc = "Stage Hunk" },
  { "<leader>gu", desc = "Undo Stage Hunk" },
  { "<leader>gf", desc = "Open in Fork" },
  { "<leader>lr", desc = "Reload Project" },
  { "<leader>lR", desc = "Rebuild Index" },
})
-- These were functional commands in the old menu, retained as secondary aliases.
vim.keymap.set("n", "<leader>q", "<cmd>q!<CR>", { silent = true })
vim.keymap.set("n", "<leader>gl", function() require("gitsigns").blame_line() end,
  { silent = true, desc = "Annotate Line" })
vim.keymap.set("n", "<leader>gL", function() require("gitsigns").blame() end,
  { silent = true, desc = "Annotate File" })
for key, action in pairs({ gs="stage_hunk", gu="undo_stage_hunk" }) do
  vim.keymap.set("n", "<leader>" .. key, function() require("gitsigns")[action]() end,
    { silent = true, desc = ({ gs="Stage Hunk", gu="Undo Stage Hunk", gR="Reset File Changes" })[key] })
end
vim.keymap.set("n", "mR", function() require("user.git_reset").reset() end,
  { silent = true, desc = "Revert File Changes" })
vim.keymap.set("n", "mB", function() require("user.git_reset").abort_merge() end,
  { silent = true, desc = "Abort Merge" })
