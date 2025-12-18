local function set_transparent_background()
  local groups = {
    "Normal",
    "NormalNC",
    "SignColumn",
    "EndOfBuffer",
    "LineNr",
    "FoldColumn",
    "CursorLineNr",
    "NormalFloat",
    "FloatBorder",
    "Pmenu",
    -- Common plugin windows
    "NvimTreeNormal",
    "NvimTreeNormalNC",
    "NvimTreeEndOfBuffer",
    "TelescopeNormal",
    "TelescopeBorder",
    "WhichKeyFloat",
  }

  for _, group in ipairs(groups) do
    vim.api.nvim_set_hl(0, group, { bg = "none" })
  end
end

vim.opt.winblend = 15
vim.opt.pumblend = 15

if vim.g.neovide then
  vim.g.neovide_transparency = 0.85
end

vim.api.nvim_create_autocmd({ "ColorScheme", "VimEnter" }, {
  desc = "Transparent background",
  callback = set_transparent_background,
})
