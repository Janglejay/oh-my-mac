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
  --   • 在定义处 → 显示 Lathe 索引中的引用
  local function smart_goto()
    if vim.bo.filetype == "java" and require("user.java_dependency_usages").at_field() then return end
    local dependency = package.loaded["user.java_dependency_navigation"]
    if dependency and dependency.references_at_field() then return end
    local bufnr = vim.api.nvim_get_current_buf()
    local method = "textDocument/definition"
    if #vim.lsp.get_clients({ bufnr = bufnr, method = method }) == 0 then
      vim.notify("LSP is not connected. Wait for Lathe to be ready", vim.log.levels.WARN)
      return
    end

    local request = {
      winid = vim.api.nvim_get_current_win(),
      cursor = vim.api.nvim_win_get_cursor(0),
      changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    }
    local pending = goto_requests[bufnr]
    if pending and pending.winid == request.winid and pending.changedtick == request.changedtick
        and vim.deep_equal(pending.cursor, request.cursor) then
      return
    end
    local navigation = require("user.navigation")
    cancel_goto(bufnr)
    goto_requests[bufnr] = request
    vim.api.nvim_echo({ { "  gd: Looking up definition...", "Comment" } }, false, {})
    request.timer = vim.defer_fn(function()
      if goto_requests[bufnr] ~= request then return end
      cancel_goto(bufnr)
      vim.api.nvim_echo({ { "" } }, false, {})
      vim.notify("gd: The definition request timed out after 30 seconds. Try again later", vim.log.levels.WARN)
    end, 30000)

    local function still_here()
      return goto_requests[bufnr] == request
        and vim.api.nvim_buf_is_valid(bufnr)
        and vim.api.nvim_get_current_win() == request.winid
        and vim.api.nvim_get_current_buf() == bufnr
        and vim.api.nvim_buf_get_changedtick(bufnr) == request.changedtick
        and vim.deep_equal(vim.api.nvim_win_get_cursor(0), request.cursor)
    end
    local function show_definition(location, encoding)
      -- Keep the jump in the review window so Ctrl-O returns to the original diff column.
      local review = package.loaded["user.codediff_review"]
      local in_review = vim.wo.diff or (review and review.is_open())
      if vim.lsp.util.show_document(location, encoding, { focus = true, reuse_win = not in_review }) then
        vim.cmd("normal! zz")
      end
    end
    local function missing_definition()
      vim.notify("gd: No definition found for the symbol under the cursor", vim.log.levels.WARN)
    end
    request.cancel = vim.lsp.buf_request_all(bufnr, method, function(client)
      -- 按各客户端的位置编码生成参数，避免中文前缀导致列号偏移。
      return vim.lsp.util.make_position_params(request.winid, client.offset_encoding)
    end, function(results)
      vim.schedule(function()
        if goto_requests[bufnr] ~= request then return end
        if not still_here() then cancel_goto(bufnr); return end
        vim.api.nvim_echo({ { "" } }, false, {})

        local defs, encodings, seen = {}, {}, {}
        local successful, error_message = false, nil
        for client_id, response in pairs(results) do
          local err = response.err or response.error
          if err then
            error_message = err.message or "Language server request failed"
          else
            successful = true
            local result = response.result
            local locations = type(result) == "table" and result or {}
            if locations.uri or locations.targetUri then locations = { locations } end
            local client = vim.lsp.get_client_by_id(client_id)
            local encoding = client and client.offset_encoding or "utf-16"
            for _, location in ipairs(locations) do
              local uri = location.uri or location.targetUri
              local range = location.targetSelectionRange or location.range or location.targetRange
              if uri and range then
                  local key = encoding .. ":" .. uri .. ":" .. range.start.line .. ":" .. range.start.character
                if not seen[key] then
                  seen[key] = true
                  defs[#defs + 1] = location
                    encodings[#defs] = encoding
                end
              end
            end
          end
        end
        if not successful then
          cancel_goto(bufnr)
          vim.notify("gd: " .. (error_message or "Language server disconnected"), vim.log.levels.WARN)
          return
        end

        -- Press gd on the declaration name to find usages.
        if #defs == 0 then
          local lathe = vim.lsp.get_clients({ bufnr = bufnr, name = "lathe" })[1]
          local pending = lathe and require("user.java_dependency_navigation").resolve(lathe, bufnr, request.winid,
            function(location, open_bytecode)
              if goto_requests[bufnr] ~= request then return end
              local valid = still_here()
              cancel_goto(bufnr)
              if not valid then return end
              if location then show_definition(location, "utf-8")
              elseif open_bytecode then open_bytecode()
              else missing_definition() end
            end)
          if pending then request.cancel = pending; return end
          cancel_goto(bufnr)
          missing_definition()
          return
        end
        cancel_goto(bufnr)
        local at_def = false
        local cur_uri = vim.uri_from_bufnr(bufnr)
        for i, location in ipairs(defs) do
          local range = location.targetSelectionRange or location.range or location.targetRange
          if (location.uri or location.targetUri) == cur_uri
              and range.start.line == request.cursor[1] - 1 then
            local column = vim.str_byteindex(vim.api.nvim_get_current_line(), encodings[i], range.start.character, false)
            if navigation.at_definition(range.start.line + 1, column) then
              at_def = true
              break
            end
          end
        end
        if at_def then
          navigation.references(true)
        elseif #defs == 1 then
          show_definition(defs[1], encodings[1])
        else
          navigation.definitions(defs, encodings)
        end
      end)
    end)
  end
  vim.keymap.set("n", "gd", function()
    if require("user.mybatis_navigation").jump_from_java(smart_goto) then return end
    if require("user.spring_navigation").run(true, smart_goto) then return end
    smart_goto()
  end, vim.tbl_extend("force", o, { desc = "gd: smart goto" }))

  -- 其他 LSP 快捷键
  vim.keymap.set("n", "gu", vim.lsp.buf.declaration, vim.tbl_extend("force", o, { desc = "GotoDeclaration" }))
  vim.keymap.set("n", "<Leader>T", function()
    vim.lsp.buf.code_action({ context = { only = { "refactor" } } })
  end, vim.tbl_extend("force", o, { desc = "Refactor" }))
  vim.keymap.set("n", "<Leader>oi", function()
    vim.lsp.buf.code_action({ context = { only = { "source.organizeImports" } } })
  end, vim.tbl_extend("force", o, { desc = "OrganizeImports" }))
  vim.keymap.set("n", "<c-p>",    vim.lsp.buf.hover,        vim.tbl_extend("force", o, { desc = "Hover" }))
  vim.keymap.set("n", "gi",      function() require("user.navigation").implementations() end, o)
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
      vim.notify("Inlay hints " .. (enabled and "disabled" or "enabled"), vim.log.levels.INFO)
    end, { noremap = true, silent = true, buffer = bufnr, desc = "Toggle inlay hints" })
  end
end

-- ── capabilities（修复：cmp 失败时不再 return nil）──────────────
local ok, cmp_lsp = pcall(require, "cmp_nvim_lsp")
M.capabilities = ok
  and cmp_lsp.default_capabilities()
  or  vim.lsp.protocol.make_client_capabilities()

-- 禁用 willSaveWaitUntil：阻止 LSP 在保存前注入格式化 edits
local sync = M.capabilities.textDocument and M.capabilities.textDocument.synchronization
if sync then
  sync.willSaveWaitUntil = false
end

-- ── 全局 LSP 超时优化（大型项目索引慢，需要更长的默认超时）────────
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
