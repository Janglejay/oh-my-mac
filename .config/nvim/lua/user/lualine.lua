local status_ok, lualine = pcall(require, "lualine")
if not status_ok then
	return
end

local hide_in_width = function()
	return vim.fn.winwidth(0) > 80
end

local diagnostics = {
	"diagnostics",
	sources = { "nvim_diagnostic" },
	sections = { "error", "warn" },
	symbols = { error = " ", warn = " " },
	colored = false,
	update_in_insert = false,
	always_visible = true,
}

local diff = {
	"diff",
	colored = false,
	symbols = { added = " ", modified = " ", removed = " " }, -- changes diff symbols
  cond = hide_in_width
}

local mode = {
	"mode",
	fmt = function(str)
		return "-- " .. str .. " --"
	end,
}

local filetype = {
	"filetype",
	icons_enabled = false,
	icon = nil,
}

local branch = {
	"branch",
	icons_enabled = true,
	icon = "",
}

local location = {
	"location",
	padding = 0,
}

-- cool function for progress
local progress = function()
	local current_line = vim.fn.line(".")
	local total_lines = vim.fn.line("$")
	local chars = { "__", "▁▁", "▂▂", "▃▃", "▄▄", "▅▅", "▆▆", "▇▇", "██" }
	local line_ratio = current_line / total_lines
	local index = math.ceil(line_ratio * #chars)
	return chars[index]
end

local spaces = function()
	return "spaces: " .. vim.api.nvim_buf_get_option(0, "shiftwidth")
end

-- Lathe 由准备任务直接触发 redrawstatus；LSP 连入/退出时补充刷新。
vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach" }, {
  group = vim.api.nvim_create_augroup("UserLatheStatusline", { clear = true }),
  callback = function() vim.schedule(function() pcall(vim.cmd, "redrawstatus") end) end,
})
local function current_java_status()
  return require("user.lathe_live").status()
end

local lathe_colors = {
  ready = "#a6e3a1",
  warning = "#f9e2af",
  error = "#f38ba8",
  busy = "#89b4fa",
  none = "#a6adc8",
}

local lsp_progress = {
  function()
    local _, text = current_java_status()
    -- 状态栏把百分号作为格式符，语言服务的原文必须在输出边界转义。
    return (text:gsub("%%", "%%%%"))
  end,
  color = function()
    local state = current_java_status()
    return { fg = lathe_colors[state] or lathe_colors.none }
  end,
}

lualine.setup({
	options = {
		icons_enabled = true,
		theme = "auto",
		component_separators = { left = "", right = "" },
		section_separators = { left = "", right = "" },
		disabled_filetypes = { "alpha", "dashboard", "snacks_picker_list", "snacks_layout_box", "aerial" },
		always_divide_middle = true,
	},
	sections = {
		lualine_a = { branch, diagnostics },
		lualine_b = { mode },
		lualine_c = { lsp_progress },
		-- lualine_x = { "encoding", "fileformat", "filetype" },
		lualine_x = { diff, spaces, "encoding", filetype },
		lualine_y = { location },
		lualine_z = { progress },
	},
	inactive_sections = {
		lualine_a = {},
		lualine_b = {},
		lualine_c = { "filename" },
		lualine_x = { "location" },
		lualine_y = {},
		lualine_z = {},
	},
	tabline = {},
	extensions = {},
})
