return {
  {
    "mfussenegger/nvim-jdtls",
    ft = "java",
    config = function()
      local uv = vim.uv or vim.loop
      local mason_path = vim.fn.stdpath("data") .. "/mason"
      local lombok_path = mason_path .. "/packages/jdtls/lombok.jar"
      local jdtls_bin = mason_path .. "/bin/jdtls"
      local cache_base = (vim.fn.has("mac") == 1 and vim.fn.expand("~/Library/Caches")
        or (vim.env.XDG_CACHE_HOME or vim.fn.expand("~/.cache"))) .. "/jdtls"
      local workspaces, rebuilding = {}, {}
      local java21

      local function canonical(path)
        local normalized = vim.fs.normalize(uv.fs_realpath(path) or vim.fn.fnamemodify(path, ":p"))
        return normalized == "/" and normalized or normalized:gsub("/+$", "")
      end
      cache_base = canonical(cache_base)

      local function publish(root, status_type, message)
        local status = { type = status_type, message = message or "", updated_at = uv.now() }
        _G.nvim_java_status = _G.nvim_java_status or {}
        _G.nvim_java_status[root] = status
        vim.api.nvim_exec_autocmds("User", {
          pattern = "JdtlsStatus", modeline = false,
          data = { root = root, type = status_type, message = status.message },
        })
      end

      local function find_java21()
        if java21 then return java21 end
        local found = vim.fn.trim(vim.fn.system("/usr/libexec/java_home -v 21 2>/dev/null"))
        if found ~= "" and vim.fn.executable(found .. "/bin/java") == 1 then
          java21 = found
          return java21
        end
        for _, home in ipairs({ "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home",
          "/opt/homebrew/opt/openjdk@21" }) do
          if vim.fn.executable(home .. "/bin/java") == 1 then java21 = home; return java21 end
        end
        return nil
      end

      -- 项目身份使用真实文件与聚合根，不受启动 cwd 或符号链接路径影响。
      local function find_root(bufnr)
        local name = canonical(vim.api.nvim_buf_get_name(bufnr))
        local git_root = vim.fs.root(name, { ".git" })
        local root
        local path = vim.fs.dirname(name)
        while path and path ~= "/" do
          if vim.fn.filereadable(path .. "/pom.xml") == 1
            or vim.fn.filereadable(path .. "/build.gradle") == 1
            or vim.fn.filereadable(path .. "/mvnw") == 1
            or vim.fn.filereadable(path .. "/gradlew") == 1 then
            root = path
          end
          if git_root and canonical(path) == canonical(git_root) then break end
          local parent = vim.fs.dirname(path)
          if parent == path then break end
          path = parent
        end
        root = root or git_root or vim.fs.dirname(name)
        return canonical(root)
      end

      local function dedicated_workspace(root)
        return cache_base .. "/nvim-" .. vim.fn.sha256(root)
      end

      -- 只复用项目位置均属于该根的旧缓存，不根据 basename 猜测，不迁移/删除旧目录。
      local function matching_legacy_workspace(root)
        if vim.fn.isdirectory(cache_base) == 0 then return nil end
        local best, best_time
        for name, kind in vim.fs.dir(cache_base) do
          if kind == "directory" and name:match("^jdtls%-%x+$") then
            local candidate = cache_base .. "/" .. name
            local locations = vim.fn.glob(candidate ..
              "/.metadata/.plugins/org.eclipse.core.resources/.projects/*/.location", false, true)
            local matches, valid = 0, true
            for _, location in ipairs(locations) do
              local f = io.open(location, "rb")
              local blob = f and f:read("*a") or ""
              if f then f:close() end
              local uri = blob:match("URI//(file:[^%z]+)")
              if uri then
                local ok, decoded = pcall(vim.uri_to_fname, uri)
                local path = ok and canonical(decoded) or ""
                if path == root or path:sub(1, #root + 1) == root .. "/" then
                  matches = matches + 1
                else
                  valid = false
                  break
                end
              else
                valid = false
                break
              end
            end
            local stat = uv.fs_stat(candidate .. "/.metadata")
            local modified = stat and stat.mtime.sec or 0
            if valid and matches > 0 and (not best_time or modified > best_time) then
              best, best_time = candidate, modified
            end
          end
        end
        return best
      end

      local function workspace_for(root)
        if workspaces[root] then return workspaces[root] end
        local dedicated = dedicated_workspace(root)
        workspaces[root] = uv.fs_stat(dedicated) and dedicated or matching_legacy_workspace(root) or dedicated
        return workspaces[root]
      end

      local function is_real_java(bufnr)
        if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "" then return false end
        local name = vim.api.nvim_buf_get_name(bufnr)
        return name ~= "" and not name:match("^%a[%w+.-]*://")
          and vim.bo[bufnr].filetype == "java" and vim.fn.filereadable(name) == 1
      end

      local function clients_for(root)
        return vim.tbl_filter(function(client)
          return client.config.root_dir and canonical(client.config.root_dir) == root
        end, vim.lsp.get_clients({ name = "jdtls" }))
      end

      local handlers_ok, handlers = pcall(require, "user.lsp.handlers")
      local caps = handlers_ok and handlers.capabilities or vim.lsp.protocol.make_client_capabilities()
      local make_config, start_buffer

      -- 退出后只清理由完整根路径 hash 确定的专用目录；旧缓存始终保留。
      local function rebuild_buffer(bufnr)
        if not is_real_java(bufnr) then return end
        local root = find_root(bufnr)
        if rebuilding[root] then return end
        local target = dedicated_workspace(root)
        local stat = uv.fs_lstat(target)
        if canonical(vim.fs.dirname(target)) ~= cache_base or target ~= dedicated_workspace(root)
          or (stat and stat.type ~= "directory") then
          vim.notify("jdtls: 缓存路径校验失败，拒绝重建", vim.log.levels.ERROR)
          return
        end
        local clients = clients_for(root)
        rebuilding[root] = true
        publish(root, "Preparing", "正在停止当前工程服务以重建索引")
        for _, client in ipairs(clients) do client:stop() end
        local started = uv.now()
        local function restart_when_stopped()
          for _, client in ipairs(clients) do
            if not client:is_stopped() then
              if uv.now() - started > 15000 then
                rebuilding[root] = nil
                publish(root, "Error", "当前工程服务未正常退出，未删除缓存")
                vim.notify("jdtls: 服务未正常退出，已取消重建", vim.log.levels.ERROR)
                return
              end
              vim.defer_fn(restart_when_stopped, 100)
              return
            end
          end
          -- Eclipse 的锁若仍被进程持有，不碰目录，稍后可重新执行重建。
          if vim.fn.filereadable(target .. "/.metadata/.lock") == 1 then
            local free = false
            if vim.fn.executable("lsof") == 1 then
              local lock = vim.system({ "lsof", "-t", "--", target .. "/.metadata/.lock" },
                { text = true }):wait(1000)
              -- lsof 的 1 表示没有占用者；超时、报错或缺少工具均不能证明安全。
              free = lock.code == 1 and vim.trim(lock.stdout or "") == ""
                and vim.trim(lock.stderr or "") == ""
            end
            if not free then
              rebuilding[root] = nil
              publish(root, "Error", "无法确认专用缓存已释放，未删除缓存")
              vim.notify("jdtls: 缓存占用检查未通过，已取消重建", vim.log.levels.ERROR)
              return
            end
          end
          if vim.fn.isdirectory(target) == 1 and vim.fn.delete(target, "rf") ~= 0 then
            rebuilding[root] = nil
            publish(root, "Error", "无法清理当前工程的专用缓存")
            return
          end
          workspaces[root] = target
          rebuilding[root] = nil
          if vim.api.nvim_buf_is_valid(bufnr) then start_buffer(bufnr) end
        end
        restart_when_stopped()
      end

      make_config = function(root)
        local home = find_java21()
        if not home then
          vim.notify("[jdtls] 未找到 Java 21 运行环境", vim.log.levels.ERROR)
          return nil
        end
        local workspace = workspace_for(root)
        local stat = uv.fs_lstat(workspace)
        if stat and stat.type ~= "directory" then
          vim.notify("[jdtls] 缓存不是普通目录，拒绝启动", vim.log.levels.ERROR)
          return nil
        end
        local cmd = { jdtls_bin, "--java-executable", home .. "/bin/java",
          "--jvm-arg=-Xms2g", "--jvm-arg=-Xmx6g", "-data", workspace }
        if vim.fn.filereadable(lombok_path) == 1 then
          table.insert(cmd, "--jvm-arg=-javaagent:" .. lombok_path)
        end
        local config = {
          cmd = cmd, cmd_env = { JAVA_HOME = home }, cmd_cwd = root, root_dir = root,
          flags = { debounce_text_changes = 150, allow_incremental_sync = true },
          settings = {
            java = {
              -- 审查会话保留完整索引，编译由 Maven 工作流执行，避免启动时自动构建。
              autobuild     = { enabled = false },
              home          = home,
              maven         = { downloadSources = true },
              configuration = { updateBuildConfiguration = "interactive" },
              references    = { includeDecompiledSources = true },
              format        = { enabled = true },
              signatureHelp = { enabled = true },
              implementationsCodeLens = { enabled = false },
              referencesCodeLens      = { enabled = false },
              completion = {
                favoriteStaticMembers = {
                  "org.junit.Assert.*",
                  "org.junit.jupiter.api.Assertions.*",
                  "org.mockito.Mockito.*",
                },
                importOrder = { "java", "javax", "com", "org" },
              },
              sources      = { organizeImports = { starThreshold = 9999, staticStarThreshold = 9999 } },
              codeGeneration = { useBlocks = true },
              import = {
                exclusions = {
                  "**/node_modules/**",
                  "**/.git/**",
                  "**/build/**",
                  "**/target/**",
                  "**/.gradle/**",
                  "**/.idea/**",
                },
              },
            },
          },

          init_options = { bundles = {} },
          capabilities = vim.deepcopy(caps),
          handlers = {
            ["language/status"] = function(err, result)
              if err or type(result) ~= "table" then return end
              publish(root, result.type or "Unknown", result.message)
            end,
          },
          on_exit = function()
            vim.schedule(function()
              if #clients_for(root) == 0 and not rebuilding[root] then publish(root, "Stopped", "") end
            end)
          end,
          on_attach = function(client, bufnr)
            if handlers_ok then handlers.on_attach(client, bufnr) end
            -- Java 专属快捷键（统一用 o，不重复定义）
            local o = { noremap = true, silent = true, buffer = bufnr }

            vim.keymap.set("n", "gu", function()
              require("jdtls").super_implementation()
            end, vim.tbl_extend("force", o, { desc = "GotoSuperMethod" }))

            vim.keymap.set("n", "<Leader>T", function()
              vim.lsp.buf.code_action({ context = { only = { "refactor" } } })
            end, vim.tbl_extend("force", o, { desc = "RefactoringGroup" }))

            vim.keymap.set("n", "<Leader>oi", function()
              require("jdtls").organize_imports()
            end, vim.tbl_extend("force", o, { desc = "Organize Imports" }))

            -- DAP 集成
            if pcall(require, "dap") then
              require("jdtls").setup_dap({ hotcodereplace = "auto" })
            end

            vim.keymap.set("n", "<Leader>jr", function()
              require("jdtls").update_project_config()
              vim.notify("jdtls: 正在同步当前工程配置...", vim.log.levels.INFO)
            end, vim.tbl_extend("force", o, { desc = "jdtls: Reload project config" }))
            vim.keymap.set("n", "<Leader>jR", function() rebuild_buffer(bufnr) end,
              vim.tbl_extend("force", o, { desc = "jdtls: Full reindex" }))
          end,
        }
        -- 初始导入与后续配置使用同一设置，避免先按默认值自动构建。
        config.init_options.settings = vim.deepcopy(config.settings)
        return config
      end

      start_buffer = function(bufnr)
        if not is_real_java(bufnr) then return end
        local root = find_root(bufnr)
        if rebuilding[root] then return end
        for _, client in ipairs(clients_for(root)) do
          if vim.lsp.buf_is_attached(bufnr, client.id) then return end
        end
        local config = make_config(root)
        if not config then return end
        if #clients_for(root) == 0 then publish(root, "Preparing", "正在启动或恢复项目索引") end
        vim.api.nvim_buf_call(bufnr, function() require("jdtls").start_or_attach(config) end)
      end

      local group = vim.api.nvim_create_augroup("UserJavaProjectAttach", { clear = true })
      vim.api.nvim_create_autocmd("FileType", {
        group = group, pattern = "java", callback = function(event) start_buffer(event.buf) end,
      })
      -- gd 也可能打开已加载过的真实文件，不会再次触发 FileType。
      vim.api.nvim_create_autocmd("BufEnter", {
        group = group, pattern = "*.java", callback = function(event) start_buffer(event.buf) end,
      })
      -- Diffview 会复用已有 Buffer；该 Buffer 可能错过了首次 FileType 附着。
      -- 仅补真实工作区文件，历史快照仍由 is_real_java 拒绝。
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "DiffviewDiffBufWinEnter",
        callback = function() start_buffer(vim.api.nvim_get_current_buf()) end,
      })
      -- lazy.nvim 首次触发 FileType 后才执行本配置，当前文件也需要附着。
      start_buffer(vim.api.nvim_get_current_buf())
    end,
  },
}
