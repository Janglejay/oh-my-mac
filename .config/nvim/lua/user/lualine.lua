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

-- JDT 服务就绪与构建任务分开统计；没有进度不等于已经完成。
local jdt_tasks = {}
local redraw_pending = false
local function redraw_jdt_status()
  if redraw_pending then return end
  redraw_pending = true
  vim.schedule(function()
    redraw_pending = false
    pcall(vim.cmd, "redrawstatus")
  end)
end

local jdt_group = vim.api.nvim_create_augroup("UserJdtlsStatusline", { clear = true })
vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach" }, {
  group = jdt_group,
  callback = redraw_jdt_status,
})
vim.api.nvim_create_autocmd("User", {
  group = jdt_group,
  pattern = "JdtlsStatus",
  callback = redraw_jdt_status,
})
vim.api.nvim_create_autocmd("LspProgress", {
  group = jdt_group,
  callback = function(ev)
    local data = ev.data or {}
    local client = vim.lsp.get_client_by_id(data.client_id)
    if not client or (client.name ~= "jdtls" and client.name ~= "lathe") then return end
    local params = data.params or {}
    local value = params.value or {}
    if params.token == nil or type(value) ~= "table" then return end
    local tasks = jdt_tasks[client.id] or {}
    jdt_tasks[client.id] = tasks
    if value.kind == "end" then
      tasks[params.token] = nil
    elseif value.kind == "begin" or value.kind == "report" then
      local task = tasks[params.token] or {}
      task.title = value.title or task.title or "项目构建中"
      task.percentage = value.percentage
      task.updated_at = vim.uv.now()
      tasks[params.token] = task
    end
    redraw_jdt_status()
  end,
})

local function current_jdt_status()
  if require("user.java_backend").server == "lathe" then
    return require("user.lathe_live").status()
  end
  -- 回收已经退出客户端的任务，避免反复重开工程后残留状态。
  for client_id in pairs(jdt_tasks) do
    local client = vim.lsp.get_client_by_id(client_id)
    if not client or client:is_stopped() then jdt_tasks[client_id] = nil end
  end
  local clients = vim.lsp.get_clients({ name = "jdtls", bufnr = 0 })
  if #clients == 0 then clients = vim.lsp.get_clients({ name = "jdtls" }) end
  if #clients == 0 then return "none", "✗ jdtls" end

  local latest_task, all_ready = nil, true
  local states = _G.nvim_java_status or {}
  for _, client in ipairs(clients) do
    local state = states[client.config.root_dir]
    if state and state.type == "Error" then
      local message = state.message or "服务错误"
      if vim.fn.strdisplaywidth(message) > 32 then message = vim.fn.strcharpart(message, 0, 28) .. "…" end
      return "error", "✗ jdtls " .. message
    end
    if not state or state.type ~= "ServiceReady" then all_ready = false end
    for _, task in pairs(jdt_tasks[client.id] or {}) do
      if not latest_task or task.updated_at > latest_task.updated_at then latest_task = task end
    end
  end
  if latest_task then
    local title = latest_task.title
    if vim.fn.strdisplaywidth(title) > 32 then title = vim.fn.strcharpart(title, 0, 28) .. "…" end
    local percentage = tonumber(latest_task.percentage)
    if percentage then title = title .. " " .. math.max(0, math.min(100, math.floor(percentage))) .. "%" end
    return "busy", "󰔟 " .. title
  end
  if not all_ready then return "preparing", "󰔟 jdtls 项目准备中" end
  local suffix = #clients > 1 and (" ×" .. #clients) or ""
  -- ServiceReady 只证明服务已连，首次语义解析仍可能继续准备。
  return "ready", "✓ jdtls 服务" .. suffix
end

local lsp_progress = {
  function()
    local _, text = current_jdt_status()
    -- 状态栏把百分号作为格式符，语言服务的原文必须在输出边界转义。
    return (text:gsub("%%", "%%%%"))
  end,
  color = function()
    local state = current_jdt_status()
    if state == "none" or state == "error" then return { fg = "#f38ba8" } end
    if state == "ready" then return { fg = "#a6e3a1" } end
    return { fg = "#fab387" }
  end,
}

lualine.setup({
	options = {
		icons_enabled = true,
		theme = "auto",
		component_separators = { left = "", right = "" },
		section_separators = { left = "", right = "" },
		disabled_filetypes = { "alpha", "dashboard", "NvimTree", "Outline" },
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
