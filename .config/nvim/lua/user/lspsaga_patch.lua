-- lspsaga callhierarchy 扩展：新增"跳转不关闭"方法
-- 不修改 lspsaga 源码，通过 monkey-patch 注入新方法 + 扩展 keymap
-- 更新 lspsaga 不影响此 patch（require 时重新应用）

local M = {}

function M.apply()
  local ok, ch_module = pcall(require, "lspsaga.callhierarchy")
  if not ok then return end

  local mt = getmetatable(ch_module)
  if not mt or not mt.__index then return end
  local ch = mt.__index

  -- 防止重复 patch
  if ch._user_patched then return end
  ch._user_patched = true

  local api      = vim.api
  local lsp      = vim.lsp
  local util     = require("lspsaga.util")
  local slist    = require("lspsaga.slist")
  local win      = require("lspsaga.window")
  local beacon   = require("lspsaga.beacon").jump_beacon
  local config   = require("lspsaga.config")

  -- 通用跳转方法：action = 'edit'/'vsplit'/'split'/'tabe'
  -- keep_open=true 保留 callhierarchy 窗口；false 走原 clean 行为
  function ch:jump_to(action, keep_open)
    local curlnum = api.nvim_win_get_cursor(0)[1]
    local curnode = slist.find_node(self.list, curlnum)
    if not curnode then return end
    local client = lsp.get_client_by_id(curnode.value.client_id)
    if not client then return end
    local data = (self.method == "callHierarchy/incomingCalls")
                 and curnode.value.from or curnode.value.to
    local start = data.selectionRange.start
    if not keep_open then
      self:clean()
    end
    local restore = win:minimal_restore()
    vim.cmd(action)
    local uri = data.uri
    if not string.match(uri, "^[^:]+://") then
      uri = vim.uri_from_fname(uri)
    end
    vim.lsp.util.jump_to_location({
      uri = uri,
      range = { start = start, ["end"] = start },
    }, client.offset_encoding)
    restore()
    beacon({ start.line, 0 }, #api.nvim_get_current_line())
  end

  -- 便捷方法：跳转 + 保留窗口
  function ch:edit_keep_open()   self:jump_to("edit",   true) end
  function ch:vsplit_keep_open() self:jump_to("vsplit", true) end
  function ch:split_keep_open()  self:jump_to("split",  true) end
  function ch:tabe_keep_open()   self:jump_to("tabe",   true) end

  -- patch keymap：原 keymap 之后，额外绑定 keep_open 键
  local original_keymap = ch.keymap
  ch.keymap = function(self)
    original_keymap(self)
    local keys = config.callhierarchy.keys
    local function bind(key, fn)
      if key then util.map_keys(self.left_bufnr, key, fn) end
    end
    bind(keys.edit_keep_open,   function() self:edit_keep_open() end)
    bind(keys.vsplit_keep_open, function() self:vsplit_keep_open() end)
    bind(keys.split_keep_open,  function() self:split_keep_open() end)
    bind(keys.tabe_keep_open,   function() self:tabe_keep_open() end)
  end
end

return M
