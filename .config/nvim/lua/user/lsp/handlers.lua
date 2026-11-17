local M = {}

-- 每个来源 Buffer 只保留一次 gd 请求；切文件/重新查询后丢弃旧结果。
local goto_requests = {}
local function cancel_goto(bufnr)
  local request = goto_requests[bufnr]
  if not request then return end
  goto_requests[bufnr] = nil
  if request.cancel then request.cancel() end
  if request.timer and not request.timer:is_closing() then
    request.timer:stop()
    request.timer:close()
  end
end

vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout" }, {
  group = vim.api.nvim_create_augroup("UserSmartGotoRequests", { clear = true }),
  callback = function(ev) cancel_goto(ev.buf) end,
})

-- ── 诊断配置 ────────────────────────────────────────────────────
M.setup = function()
  local signs = {
    { name = "DiagnosticSignError", text = "" },
    { name = "DiagnosticSignWarn",  text = "" },
    { name = "DiagnosticSignHint",  text = "" },
    { name = "DiagnosticSignInfo",  text = "" },
  }
  for _, sign in ipairs(signs) do
    vim.fn.sign_define(sign.name, { texthl = sign.name, text = sign.text, numhl = "" })
  end

  vim.diagnostic.config({
    virtual_text    = false,
    signs           = { active = signs },
    update_in_insert = true,
    underline       = true,
    severity_sort   = true,
    float = {
      focusable = false, style = "minimal", border = "rounded",
      source = "always", header = "", prefix = "",
    },
  })

  -- Hover / signature_help 圆角边框
  local function wrap_with_border(handler)
    return function(err, result, ctx, cfg)
      cfg = vim.tbl_extend("force", cfg or {}, { border = "rounded" })
      handler(err, result, ctx, cfg)
    end
  end
  vim.lsp.handlers.hover         = wrap_with_border(vim.lsp.handlers.hover)
  vim.lsp.handlers.signature_help = wrap_with_border(vim.lsp.handlers.signature_help)
end

-- ── 文档高亮（光标停留高亮同名符号）──────────────────────────────
local function lsp_highlight_document(client)
  if not (client.server_capabilities or {}).documentHighlightProvider then return end
  local grp = vim.api.nvim_create_augroup("lsp_doc_highlight", { clear = true })
  vim.api.nvim_create_autocmd("CursorHold",  { group = grp, buffer = 0,
    callback = vim.lsp.buf.document_highlight })
  vim.api.nvim_create_autocmd("CursorMoved", { group = grp, buffer = 0,
    callback = vim.lsp.buf.clear_references })
end

-- ── Buffer 快捷键 ────────────────────────────────────────────────
local function lsp_keymaps(bufnr)
  local o = { noremap = true, silent = true, buffer = bufnr }

  -- gD: 跳到声明
  vim.keymap.set("n", "gD", vim.lsp.buf.declaration, vim.tbl_extend("force", o, { desc = "Declaration" }))

  -- gd: 上下文感知（IDEA Cmd+B 风格）
  --   • 在引用处 → 跳到定义
  --   • 在定义处 → 显示所有引用（支持字段/属性/Lombok 生成的 getter/setter）
  vim.keymap.set("n", "gd", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local method = "textDocument/definition"
    if #vim.lsp.get_clients({ bufnr = bufnr, method = method }) == 0 then
      vim.notify("LSP 未连接，请等待 jdtls 就绪", vim.log.levels.WARN)
      return
    end

    local fzf = require("fzf-lua")
    cancel_goto(bufnr)
    local request = {
      winid = vim.api.nvim_get_current_win(),
      cursor = vim.api.nvim_win_get_cursor(0),
      changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    }
    goto_requests[bufnr] = request
    vim.api.nvim_echo({ { "  gd 查询中...", "Comment" } }, false, {})
    request.timer = vim.defer_fn(function()
      if goto_requests[bufnr] ~= request then return end
      cancel_goto(bufnr)
      vim.api.nvim_echo({ { "" } }, false, {})
      vim.notify("gd: 查询超时（30s），可继续操作并稍后重试", vim.log.levels.WARN)
    end, 30000)

    request.cancel = vim.lsp.buf_request_all(bufnr, method, function(client)
      -- 按各客户端的位置编码生成参数，避免中文前缀导致列号偏移。
      return vim.lsp.util.make_position_params(request.winid, client.offset_encoding)
    end, function(results)
      vim.schedule(function()
        if goto_requests[bufnr] ~= request then return end
        cancel_goto(bufnr)
        if not vim.api.nvim_buf_is_valid(bufnr)
            or vim.api.nvim_get_current_win() ~= request.winid
            or vim.api.nvim_get_current_buf() ~= bufnr
            or vim.api.nvim_buf_get_changedtick(bufnr) ~= request.changedtick
            or not vim.deep_equal(vim.api.nvim_win_get_cursor(0), request.cursor) then
          return
        end
        vim.api.nvim_echo({ { "" } }, false, {})

        local defs, encodings, seen = {}, {}, {}
        local successful, error_message = false, nil
        for client_id, response in pairs(results) do
          local err = response.err or response.error
          if err then
            error_message = err.message or "语言服务查询失败"
          else
            successful = true
            local result = response.result
            local locations = type(result) == "table" and result or {}
            if locations.uri or locations.targetUri then locations = { locations } end
            local client = vim.lsp.get_client_by_id(client_id)
            for _, location in ipairs(locations) do
              local uri = location.uri or location.targetUri
              local range = location.targetSelectionRange or location.range or location.targetRange
              if uri and range then
                local key = uri .. ":" .. range.start.line .. ":" .. range.start.character
                if not seen[key] then
                  seen[key] = true
                  defs[#defs + 1] = location
                  encodings[#defs] = client and client.offset_encoding or "utf-16"
                end
              end
            end
          end
        end
        if not successful then
          vim.notify("gd: " .. (error_message or "语言服务已断开"), vim.log.levels.WARN)
          return
        end

        -- 保留原操作：声明所在行查引用，使用处跳定义。
        local at_def = #defs == 0
        local cur_uri = vim.uri_from_bufnr(bufnr)
        for _, location in ipairs(defs) do
          local range = location.targetSelectionRange or location.range or location.targetRange
          if (location.uri or location.targetUri) == cur_uri
              and range.start.line == request.cursor[1] - 1 then
            at_def = true
            break
          end
        end
        if at_def then
          fzf.lsp_references({ fzf_opts = { ["--query"] = "!.m2" } })
        elseif #defs == 1 then
          -- 审查窗口内就地跳转，避免复用另一 Tab 的同一文件，确保 Ctrl-O 回到原 Diff 列。
          local review = package.loaded["user.codediff_review"]
          local in_review = vim.wo.diff or (review and review.is_open())
          if vim.lsp.util.show_document(defs[1], encodings[1], { focus = true, reuse_win = not in_review }) then
            vim.cmd("normal! zz")
          end
        else
          fzf.lsp_definitions()
        end
      end)
    end)
  end, vim.tbl_extend("force", o, { desc = "gd: smart goto" }))

  -- 其他 LSP 快捷键
  vim.keymap.set("n", "<c-p>",    vim.lsp.buf.hover,        vim.tbl_extend("force", o, { desc = "Hover" }))
  vim.keymap.set("n", "gi",      "<cmd>lua require('fzf-lua').lsp_implementations()<CR>", o)
  vim.keymap.set("n", "<Leader>R", vim.lsp.buf.rename,      vim.tbl_extend("force", o, { desc = "Rename" }))
  vim.keymap.set("n", "ga",      vim.diagnostic.open_float, vim.tbl_extend("force", o, { desc = "Show Diagnostic" }))
  vim.keymap.set("n", "<F2>",    function()
    vim.diagnostic.goto_next({ float = { border = "rounded" } })
  end, vim.tbl_extend("force", o, { desc = "Next Diagnostic" }))
end

-- ── on_attach ────────────────────────────────────────────────────
M.on_attach = function(client, bufnr)
  lsp_keymaps(bufnr)
  lsp_highlight_document(client)
  -- Neovim 0.10+ 在 LSP attach 时自动设置 buffer-local K→hover，会覆盖全局 K=MethodUp
  -- 删除该 buffer-local 映射，让 editing.lua 里的全局 K 生效（hover 已绑定到 <c-p>）
  pcall(vim.keymap.del, "n", "K", { buffer = bufnr })

  -- Inlay hints（内联类型/参数名提示，Neovim 0.10+ 原生支持）
  -- 效果：orderService.create(userId: id, quantity: 3) ← 灰色的是提示
  if client.server_capabilities.inlayHintProvider then
    vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
    -- <Leader>ih 切换显示/隐藏（提示太多时可临时关掉）
    vim.keymap.set("n", "<Leader>ih", function()
      local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr })
      vim.lsp.inlay_hint.enable(not enabled, { bufnr = bufnr })
      vim.notify("Inlay hints " .. (enabled and "关闭" or "开启"), vim.log.levels.INFO)
    end, { noremap = true, silent = true, buffer = bufnr, desc = "Toggle inlay hints" })
  end
end

-- ── capabilities（修复：cmp 失败时不再 return nil）──────────────
local ok, cmp_lsp = pcall(require, "cmp_nvim_lsp")
M.capabilities = ok
  and cmp_lsp.default_capabilities()
  or  vim.lsp.protocol.make_client_capabilities()

-- 禁用 willSaveWaitUntil：阻止 jdtls 等 LSP 在保存前注入格式化 edits
local sync = M.capabilities.textDocument and M.capabilities.textDocument.synchronization
if sync then
  sync.willSaveWaitUntil = false
end

-- ── 全局 LSP 超时优化（jdtls 索引慢，需要更长的默认超时）────────
-- 默认 10s 对于大型 Java 项目不够，增加到 60s
vim.lsp.buf_request_sync_default_timeout = 60000

-- 包装常用请求，使用更长的超时
local orig_references = vim.lsp.buf.references
vim.lsp.buf.references = function()
  return orig_references({ timeout = 60000 })
end

local orig_document_symbol = vim.lsp.buf.document_symbol
vim.lsp.buf.document_symbol = function()
  return orig_document_symbol({ timeout = 30000 })
end

return M
