-- Neovide keeps the theme background and opaque floating windows.
if vim.g.neovide then
  return
end

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
    "SnacksPicker",
    "SnacksPickerBorder",
    "SnacksPickerList",
    "SnacksPickerPreview",
    "WhichKeyFloat",
  }

  for _, group in ipairs(groups) do
    vim.api.nvim_set_hl(0, group, { bg = "none" })
  end
end

vim.opt.winblend = 15
vim.opt.pumblend = 15


vim.api.nvim_create_autocmd({ "ColorScheme", "VimEnter" }, {
  desc = "Transparent background",
  callback = set_transparent_background,
})
