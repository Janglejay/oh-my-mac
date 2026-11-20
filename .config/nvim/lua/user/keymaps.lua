local opts = { noremap = true, silent = true }
local term_opts = { silent = true }
local keymap = vim.api.nvim_set_keymap

-- ====================
-- Leader Key
-- ====================
vim.g.mapleader = ","
vim.g.maplocalleader = ","

-- ====================
-- 基础按键映射 (来自 .vimrc)
-- ====================

-- ESC delay 设置 (timoutlen=500, ttimeoutlen=0 在 options.lua 中)
vim.opt.ttimeoutlen = 0

-- Normal 模式
keymap("n", "q", "<NOP>", opts)          -- 禁用 q
keymap("n", "\\", "q", opts)              -- \ 代替 q
keymap("n", "U", ":redo<CR>", opts)       -- U 重做
keymap("n", "<C-e>", "<C-d>", opts)       -- Ctrl+e 向下半页
keymap("n", "<C-r>", "<C-u>", opts)       -- Ctrl+r 向上半页
keymap("n", "<CR>", ";", opts)            -- 回车变为 ;
keymap("n", "vv", "<S-v>", opts)          -- vv 选中整行
keymap("n", "go", "gi", opts)             -- go 跳到上次插入位置并进入插入模式

-- 翻页 (以空行为段落)
-- keymap("n", "J", "}", opts)  -- 已替换为 treesitter method jump (editing.lua)
-- keymap("n", "K", "{", opts)  -- 已替换为 treesitter method jump (editing.lua)

-- Leader 快捷键
keymap("n", "<Leader>j", "*", opts)        -- 搜索当前词
keymap("n", "<Leader>k", "#", opts)        -- 反向搜索
keymap("n", "W", "b", opts)                -- W 跳词
keymap("n", "zc", "zz", opts)
keymap("n", "zz", "zc", opts)
keymap("n", "zZ", "zM", opts)
keymap("n", "zO", "zR", opts)

-- 移动
keymap("n", "L", "g$", opts)               -- L 跳到当前视觉行尾
keymap("n", "H", "g^", opts)               -- H 跳到当前视觉行首
keymap("x", "L", "g$", opts)               -- Visual 选择延伸至当前视觉行尾
keymap("x", "H", "g^", opts)               -- Visual 选择延伸至当前视觉行首
keymap("n", "gn", "%", opts)               -- gn 跳到匹配括号
keymap("x", "gn", "%", opts)               -- Visual 移到匹配括号并保留选区起点

-- Edit 快捷键
keymap("n", "{", "$a {<CR>}<Esc>O", opts) -- { 补 {}

-- Buffer 操作
keymap("n", "R", ":bnext<CR>", opts)      -- R 下一个 buffer
keymap("n", "E", ":bprevious<CR>", opts)   -- E 上一个 buffer

-- Window 导航
keymap("n", "gh", "<C-w>h", opts)
keymap("n", "gj", "<C-w>j", opts)
keymap("n", "gk", "<C-w>k", opts)
keymap("n", "gl", "<C-w>l", opts)

-- 分割窗口
keymap("n", "sV", ":sp<CR>", opts)
keymap("n", "sv", ":vs<CR>", opts)

-- 窗口缩放：<Leader> + 方向键，每次 4 格
-- 比 <C-arrow> 更不易与终端快捷键冲突
vim.keymap.set("n", "<Leader><Up>",    ":resize +4<CR>",          { noremap=true, silent=true, desc="Increase Window Height" })
vim.keymap.set("n", "<Leader><Down>",  ":resize -4<CR>",          { noremap=true, silent=true, desc="Decrease Window Height" })
vim.keymap.set("n", "<Leader><Right>", ":vertical resize +4<CR>", { noremap=true, silent=true, desc="Increase Window Width" })
vim.keymap.set("n", "<Leader><Left>",  ":vertical resize -4<CR>", { noremap=true, silent=true, desc="Decrease Window Width" })

-- Tab 操作
keymap("n", "<Tab>", ">>", opts)          -- Tab 右缩进
keymap("n", "<BS>", "<<", opts)           -- Backspace 左缩进
keymap("v", "<Tab>", ">", opts)
keymap("v", "<BS>", "<", opts)

-- ====================
-- 搜索
-- ====================
keymap("n", "<Leader>n", ":nohlsearch<CR>", opts)  -- 取消高亮

-- ====================
-- 复制粘贴 (来自 .vimrc)
-- ====================
keymap("n", "Y", "gg^yG<End>", opts)      -- Y 复制整行
keymap("n", "<Leader>v", "gg^vG<End>", opts) -- 全选
keymap("n", "<Leader>x", "^f=2hciw", opts) -- 改赋值左边变量名（来自 ideavimrc）
keymap("n", "<Leader>d", "\"_d", opts)     -- 删除到黑洞寄存器
keymap("n", "x", "\"_x", opts)             -- x 删除字符
keymap("n", "c", "\"_c", opts)             -- c 修改
keymap("n", "cc", "\"_cc", opts)           -- cc 删除当前行进入插入
keymap("n", "s", "\"_s", opts)             -- s 删除字符进入插入
keymap("v", "p", "\"_dP", opts)            -- v 模式 p 粘贴到前面
keymap("n", "<Leader>y", "\"_y", opts)     -- y 复制到黑洞
keymap("n", "<Leader>r", 'viw"_dP', opts)  -- 替换当前词

-- ====================
-- Git / Hunk 操作
-- ====================
-- gitsigns：行内 hunk 跳转（保持不变）
keymap("n", "<C-u>", "<cmd>lua require 'gitsigns'.reset_hunk()<cr>", opts)
keymap("n", "gp", "<cmd>lua require 'gitsigns'.preview_hunk()<cr>", opts)
keymap("n", "<C-f>", "<cmd>lua require 'gitsigns'.prev_hunk()<cr>", opts)
keymap("n", "<C-d>", "<cmd>lua require 'gitsigns'.next_hunk()<cr>", opts)

-- Fork：在 Fork GUI 中打开当前项目
vim.keymap.set("n", "<Leader>gf", function()
  local path = vim.fn.expand("%:p:h")
  vim.fn.jobstart({ "open", "-a", "Fork", path })
end, { noremap = true, silent = true, desc = "Open in Fork" })

-- ====================
-- 跳转历史
-- ====================
keymap("n", "<C-n>", "<C-i>", opts)  -- Forward（对应 IdeaVim <C-n> Forward）

-- ====================
-- Terminal
-- ====================
vim.keymap.set("n", "st", function() require("user.snacks").terminal() end, { silent = true, desc = "Terminal" })

-- ====================
-- LSP Format
-- ====================
-- = 用 conform.nvim 格式化：支持有/无 LSP 的文件类型（JSON/YAML/Java/JS/Vue 等）
-- JSON → jq，Java → google-java-format，JS/Vue → prettier，Java → LSP fallback
vim.keymap.set({ "n", "v" }, "=", function()
  require("conform").format({ async = true, lsp_fallback = true })
end, vim.tbl_extend("force", opts, { desc = "Format (conform)" }))

-- ====================
-- Insert 模式
-- ====================
keymap("i", "jk", "<ESC>", opts)          -- jk 退出插入模式

-- ====================
-- Visual 模式
-- ====================
keymap("v", "U", "~", opts)                -- U 大写
keymap("v", "~", "<Nop>", opts)
keymap("v", "u", "<ESC>", opts)            -- u 小写

-- ====================
-- LSP 快速查看（对照 IdeaVim）
-- ====================
keymap("n", "qt", "<cmd>lua vim.lsp.buf.type_definition()<CR>", opts)   -- QuickTypeDefinition
keymap("n", "qd", "<cmd>lua vim.lsp.buf.hover()<CR>", opts)              -- QuickJavaDoc

-- ====================
-- 窗口操作（对照 IdeaVim）
-- ====================
keymap("n", "sl", "<C-w>w", opts)                          -- NextWindow（循环切换分割）
keymap("n", "sh", "<C-w>W", opts)                          -- PreviousWindow（反向循环）
keymap("n", "sw", "<cmd>vsplit<CR><cmd>lua vim.lsp.buf.definition()<CR>", opts)  -- EditSourceInNewWindow
keymap("n", "sq", "<cmd>close<CR>", opts)                  -- Unsplit
-- <Leader>w: 最大化当前拆分窗口，再按恢复原布局；不关闭窗口或切换 Buffer。
local zoom_states = {}

-- 临时解除尺寸限制，操作结束立即还原，避免影响其他 Tab 或后续拆分。
local function resize_for_zoom(wins, action)
  local min_width, min_height = vim.o.winminwidth, vim.o.winminheight
  local fixed = {}
  for _, win in ipairs(wins) do
    fixed[win] = { width = vim.wo[win].winfixwidth, height = vim.wo[win].winfixheight }
    vim.wo[win].winfixwidth, vim.wo[win].winfixheight = false, false
  end
  local ok, err = pcall(function()
    vim.o.winminwidth, vim.o.winminheight = 0, 0
    action()
  end)
  vim.o.winminwidth, vim.o.winminheight = min_width, min_height
  for win, flags in pairs(fixed) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].winfixwidth, vim.wo[win].winfixheight = flags.width, flags.height
    end
  end
  return ok, err
end

local function toggle_window_zoom()
  local tab, current = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win()
  -- 弹出的搜索/预览窗口不属于拆分布局。
  if vim.api.nvim_win_get_config(current).relative ~= "" then return end
  local wins = vim.tbl_filter(function(win)
    return vim.api.nvim_win_get_config(win).relative == ""
  end, vim.api.nvim_tabpage_list_wins(tab))
  local active_view = vim.fn.winsaveview()
  local state = zoom_states[tab]
  if state then
    zoom_states[tab] = nil
    local unchanged = vim.deep_equal(state.layout, vim.fn.winlayout())
      and state.columns == vim.o.columns and state.lines == vim.o.lines
    local ok, err = resize_for_zoom(wins, function()
      if unchanged then
        vim.api.nvim_set_current_win(state.win)
        vim.cmd(state.restore)
        for win, saved in pairs(state.views) do
          if win ~= current and vim.api.nvim_win_get_buf(win) == saved.buf then
            vim.api.nvim_win_call(win, function() vim.fn.winrestview(saved.view) end)
          end
        end
      else
        -- 用户已增删窗口或改变终端尺寸：只展开现有布局，不执行旧窗口编号。
        vim.cmd("wincmd =")
      end
    end)
    -- 保留最大化期间的滚动/gd 结果，不退回旧文件或旧光标位置。
    if vim.api.nvim_win_is_valid(current) then
      vim.api.nvim_set_current_win(current)
      vim.fn.winrestview(active_view)
    end
    if not ok then vim.notify("Could not restore window layout: " .. tostring(err), vim.log.levels.ERROR) end
    return
  end
  if #wins < 2 then return end
  state = {
    win = current, layout = vim.fn.winlayout(), restore = vim.fn.winrestcmd(), views = {},
    columns = vim.o.columns, lines = vim.o.lines,
  }
  for _, win in ipairs(wins) do
    state.views[win] = {
      buf = vim.api.nvim_win_get_buf(win),
      view = vim.api.nvim_win_call(win, vim.fn.winsaveview),
    }
  end
  local ok, err = resize_for_zoom(wins, function()
    vim.cmd("wincmd _")
    vim.cmd("wincmd |")
  end)
  if ok then
    zoom_states[tab] = state
  else
    resize_for_zoom(wins, function() vim.cmd(state.restore) end)
    vim.notify("Could not maximize window: " .. tostring(err), vim.log.levels.ERROR)
  end
  vim.fn.winrestview(active_view)
end

vim.api.nvim_create_autocmd("TabClosed", {
  group = vim.api.nvim_create_augroup("UserWindowZoom", { clear = true }),
  callback = function()
    for tab in pairs(zoom_states) do
      if not vim.api.nvim_tabpage_is_valid(tab) then zoom_states[tab] = nil end
    end
  end,
})
vim.keymap.set("n", "<Leader>w", toggle_window_zoom,
  { noremap = true, silent = true, desc = "Maximize or Restore Window" })
vim.keymap.set("n", "<Leader>c", function() Snacks.bufdelete() end, { silent = true, desc = "Close Editor" })         -- CloseContent
vim.keymap.set("n", "<Leader>C", function() Snacks.bufdelete.other() end, { silent = true, desc = "Close Other Editors" })     -- CloseAllEditorsButActive
vim.keymap.set("n", "gw", function() require("user.project").switch() end, { silent = true, desc = "Switch Project" })         -- SwitchProject
vim.keymap.set("n", "<Leader>P", function() Snacks.explorer.reveal() end, { silent = true, desc = "Select In Project" }) -- SelectIn（定位当前文件）

-- ====================
-- 构建（对照 IdeaVim zb = Java.BuildMenu）
-- ====================
vim.keymap.set("n", "zb", function() require("user.snacks").terminal("mvn compile") end, { silent = true, desc = "Build Project" })  -- Java.BuildMenu

-- ====================
-- 来自 .vimrc 的全局 buffer-local 映射
-- ====================
-- 这些通过 autocmd 在特定文件类型上设置
--[[ vim.api.nvim_create_autocmd("FileType", { ]]
--[[   pattern = { "java", "rust", "lua", "go" }, ]]
--[[   callback = function() ]]
--[[     vim.api.nvim_buf_set_keymap(0, "n", ";", "$a;<Esc>", { noremap = true, silent = true }) ]]
--[[     vim.api.nvim_buf_set_keymap(0, "n", "{", "$a {<CR>}<Esc>O", { noremap = true, silent = true }) ]]
--[[   end, ]]
--[[ }) ]]
--[[]]
--[[ -- Rust 特有 ]]
--[[ vim.api.nvim_create_autocmd("FileType", { ]]
--[[   pattern = { "rust" }, ]]
--[[   callback = function() ]]
--[[     vim.api.nvim_buf_set_keymap(0, "n", "zr", "<cmd>w<CR><cmd>TermExec cmd=\"cargo run\" dir=\".\"<CR>", { noremap = true, silent = true }) ]]
--[[     vim.api.nvim_buf_set_keymap(0, "n", "zb", "<cmd>w<CR><cmd>TermExec cmd=\"cargo build\" dir=\".\"<CR>", { noremap = true, silent = true }) ]]
--[[     vim.api.nvim_buf_set_keymap(0, "n", "zc", "<cmd>w<CR><cmd>TermExec cmd=\"cargo check\" dir=\".\"<CR>", { noremap = true, silent = true }) ]]
--[[     vim.api.nvim_buf_set_keymap(0, "n", "zR", "<cmd>w<CR><cmd>RustRun<CR>", { noremap = true, silent = true }) ]]
--[[   end, ]]
--[[ }) ]]
--[[]]
--[[ -- Lua 特有 ]]
--[[ vim.api.nvim_create_autocmd("FileType", { ]]
--[[   pattern = { "lua" }, ]]
--[[   callback = function() ]]
--[[     vim.api.nvim_buf_set_keymap(0, "n", "zr", "<cmd>w<CR><cmd>!lua %<CR>", { noremap = true, silent = true }) ]]
--[[   end, ]]
--[[ }) ]]
--[[]]
--[[ -- Markdown 特有 ]]
--[[ vim.api.nvim_create_autocmd("FileType", { ]]
--[[   pattern = { "markdown" }, ]]
--[[   callback = function() ]]
--[[     local mopts = { noremap = true, silent = true, buffer = 0 } ]]
--[[     vim.keymap.set("n", "<Leader>x", "/<++><CR>:nohl<CR>4\"-cl", mopts) ]]
--[[     vim.keymap.set("n", "<Leader>C", "i```<CR><++><CR>```<Esc>", mopts) ]]
--[[     vim.keymap.set("n", "<Leader>c", "i`<++>`<Esc>", mopts) ]]
--[[     vim.keymap.set("n", "<Leader>b", "i**<++>**<Esc>", mopts) ]]
--[[     vim.keymap.set("n", "<Leader>s", "i~~<++>~~<Esc>", mopts) ]]
--[[     vim.keymap.set("n", "<Leader>o", "i[<++>](<++>)<Esc>", mopts) ]]
--[[     vim.keymap.set("n", "<Leader>O", "i![<++>](<++>)<Esc>", mopts) ]]
--[[     vim.keymap.set("n", "<Leader>m", "i- [<Space>]<Esc>", mopts) ]]
--[[   end, ]]
--[[ }) ]]
