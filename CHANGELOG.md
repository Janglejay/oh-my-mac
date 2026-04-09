# Neovim 配置更新日志

## 2026-04-09 Neovim 配置重构

### 主要变更

#### 1. LSP 配置升级 (Neovim 0.12 兼容)

**问题：** 旧版 `nvim-lsp-installer` + `null-ls.nvim` 与 Neovim 0.12 不兼容

**解决方案：**
- 移除 `williamboman/nvim-lsp-installer`
- 添加 `williamboman/mason.nvim` + `mason-lspconfig.nvim`
- 用 `conform.nvim` 替换 `null-ls.nvim`（已无人维护）
- 重写 `lsp/lsp-installer.lua`，使用 `vim.lsp.config` API

**变更文件：**
- `lua/user/plugins.lua` — 更新插件列表
- `lua/user/lsp/init.lua` — 清理，移除不必要的 lspconfig require
- `lua/user/lsp/lsp-installer.lua` — 重写为 mason 配置
- `lua/user/lsp/conform.lua` — 新建，格式化配置
- `lua/user/lsp/null-ls.lua` → `null-ls.lua.bak`（已禁用）

#### 2. .vimrc 迁移到 Lua

**问题：** 双配置源混乱，维护困难

**解决方案：** 统一使用 Lua 配置，废弃 `.vimrc`

**操作：**
- `~/.vimrc` → `~/.vimrc.bak`（备份）
- `init.vim` — 移除 `source ~/.vimrc`
- 新建 `lua/user/vim-compat.lua` — 迁移 .vimrc 的 buffer-local 配置

#### 3. Keymaps 补全

**问题：** 大量 .vimrc 中的 keymap 未迁移

**补全的映射：**

| 映射 | 功能 |
|------|------|
| `jk` (Insert) | 退出插入模式 |
| `U` (Visual) | 大写选中 |
| `vv` | 全选整行 |
| `J/K` | 翻页（以空行为段落）|
| `L` | 跳到行尾 |
| `H` | 跳到行首 |
| `W` | 跳词 |
| `R/E` | 切换 buffer |
| `gh/gj/gk/gl` | 窗口导航 |
| `sV/sv` | 分割窗口 |
| `<Leader>n` | 取消搜索高亮 |
| `<Leader>j/k` | 搜索当前词/反向搜索 |
| `<Leader>d/y/r` | 删除/复制/替换 |
| `gp/C-f/C-d/C-u` | Git hunk 操作 |
| `ma` | Telescope bookmarks |

**文件类型特定映射（vim-compat.lua）：**
- Java/Rust/Lua/Go: `;` → 自动加分号，`{` → 自动加 `{}`
- Rust: `zr/zb/zc/zR` → cargo 命令
- Lua: `zr` → 运行当前文件
- Markdown: `<Leader>x/C/c/b/s/o/O/m` → 常用格式快捷键

#### 4. Options 修复

| 选项 | 原值 | 新值 | 说明 |
|------|------|------|------|
| `shiftwidth` | 2 | 4 | 匹配 .vimrc |
| `tabstop` | 2 | 4 | 匹配 .vimrc |
| `softtabstop` | - | 4 | 匹配 .vimrc |
| `mouse` | `"a"` | `""` | 禁用鼠标（匹配 .vimrc）|
| `autowriteall` | - | true | 自动保存（新增）|

---

### 变更文件清单

**核心更新：**
- `lua/user/keymaps.lua` — 补全所有缺失的 keymap
- `lua/user/options.lua` — 修复缩进和鼠标设置
- `lua/user/vim-compat.lua` — 新建，文件类型特定映射
- `lua/init.lua` — 添加 vim-compat require
- `init.vim` — 移除 source .vimrc

**LSP 相关：**
- `lua/user/plugins.lua` — 更新插件
- `lua/user/lsp/init.lua` — 简化
- `lua/user/lsp/lsp-installer.lua` — 重写为 mason
- `lua/user/lsp/conform.lua` — 新建
- `lua/user/lsp/null-ls.lua` — 禁用

**未变更：**
- 其他插件配置（cmp, telescope, gitsigns, etc.）

---

### 下一步操作

1. **安装新插件：**
   ```vim
   :PackerSync
   ```

2. **测试配置：**
   重启 Neovim，检查以下功能是否正常：
   - `jk` 退出插入模式
   - LSP（Python/Java）是否正常工作
   - 格式化（black, isort）是否生效

3. **如遇问题：**
   ```vim
   :checkhealth
   ```
