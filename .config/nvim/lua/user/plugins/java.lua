local options = require("user.lathe_config")
return {
  {
    dir = options.resources .. "/lathe.nvim-0.3.1",
    name = "lathe.nvim",
    ft = "java",
    cmd = { "LatheStart", "LatheSync", "LatheLog" },
    config = function()
      local live = require("user.lathe_live")
      local lathe = require("lathe")
      local workspace = require("lathe.workspace")
      lathe.get_root, workspace.get_root = live.root, live.root
      workspace.cache_root = function() return options.state_root .. "/projects" end
      lathe.warn_if_not_ready = function(buf) live.ensure(buf, function() live.attach(buf) end) end
      local handlers = require("user.lsp.handlers")
      lathe.setup({ capabilities = handlers.capabilities, pom = { validate = false, format = false }, format_on_save = false })
      require("lathe.sync").run = function() live.refresh(0, false) end
      vim.api.nvim_create_user_command("LatheStart", function()
        local buf = vim.api.nvim_get_current_buf()
        live.ensure(buf, function() live.attach(buf) end)
      end, { force = true })
      vim.api.nvim_create_user_command("LatheSync", function() live.refresh(0, false) end, { force = true })
      vim.api.nvim_create_user_command("LatheLog", live.log, { force = true })
      -- Also available before LSP attachment, so a failed first preparation can be retried.
      vim.keymap.set("n", "<Leader>lr", function() live.refresh(0, false) end,
        { silent = true, desc = "Lathe: refresh current Maven project" })
      vim.keymap.set("n", "<Leader>lR", function() live.refresh(0, true) end,
        { silent = true, desc = "Lathe: rebuild current Maven project" })
      vim.lsp.handlers["lathe/sync"] = function(_, _, ctx) live.model_changed(ctx.client_id) end
      vim.lsp.config("lathe", {
        handlers = {
          ["window/showMessageRequest"] = function(err, params, ctx, config)
            if params and params.message and params.message:find("Build files changed", 1, true) then
              live.model_changed(ctx.client_id)
              return { title = "Later" } -- The configured background preparation owns this refresh.
            end
            return vim.lsp.handlers["window/showMessageRequest"](err, params, ctx, config)
          end,
        },
        root_dir = function(buf, on_dir)
          live.ensure(buf, function(project) on_dir(project.analysis) end)
        end,
        cmd = function(dispatchers, config)
          local project
          for _, p in pairs(live.contexts) do if p.analysis == config.root_dir then project = p; break end end
          assert(project, "Unknown Lathe project")
          return vim.lsp.rpc.start({ workspace.launcher_path(project.analysis) }, dispatchers, {
            cwd = project.analysis,
            env = { LATHE_CACHE = project.cache, LATHE_JAVA_HOME = options.runtime_jdk, LATHE_JVM_OPTS = options.jvm_opts },
          })
        end,
        on_attach = function(client, buf)
          handlers.on_attach(client, buf)
          local opts = { buffer = buf, silent = true, noremap = true }
          vim.keymap.set("n", "<Leader>lr", function() live.refresh(buf, false) end,
            vim.tbl_extend("force", opts, { desc = "Lathe: refresh current project model" }))
          vim.keymap.set("n", "<Leader>lR", function() live.refresh(buf, true) end,
            vim.tbl_extend("force", opts, { desc = "Lathe: rebuild current project model" }))
        end,
      })
      local function attach(buf)
        if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "java" and vim.bo[buf].buftype == "" then
          live.ensure(buf, function() live.attach(buf) end)
        end
      end
      local group = vim.api.nvim_create_augroup("LatheMavenAttach", { clear = true })
      vim.api.nvim_create_autocmd("BufEnter", { group = group, pattern = "*.java", callback = function(ev) attach(ev.buf) end })
      attach(vim.api.nvim_get_current_buf())
    end,
  },
}
