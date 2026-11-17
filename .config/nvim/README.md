# Neovim 配置

面向 Java 代码审查和日常编辑的 Neovim 配置，也保留 Python、TypeScript/Vue、Rust 等语言支持。

当前 Java 默认后端为 **Lathe 0.3.1**，打开 Maven 工程自动准备 Java 8 分析模型；JDT LS 保留为一行配置可切换的后端。重启 Neovim 后加载修改，不向各项目写入编辑器配置。

---

## 目录

1. [特性概览](#特性概览)
2. [安装](#安装)
3. [配置结构](#配置结构)
4. [核心功能](#核心功能)
5. [快捷键](#快捷键)
6. [语言支持](#语言支持)
7. [Java 开发专题](#java-开发专题)
8. [故障排除](#故障排除)

---

## 特性概览

| 功能 | 实现方案 | IDEA 对应 |
|------|----------|-----------|
| **代码导航** | fzf-lua + Lathe / JDT LS | Search Everywhere / Goto |
| **代码补全** | nvim-cmp + LSP | 智能补全 |
| **代码格式化** | conform.nvim | `Cmd+Alt+L` |
| **调试** | nvim-dap + dap-ui | Debug 工具窗口 |
| **测试运行** | neotest + neotest-java | JUnit 运行器 |
| **版本控制** | gitsigns + CodeDiff（主审查）/ Diffview（历史与回退） | Git 工具窗口 |
| **调用链分析** | lspsaga | Call Hierarchy |
| **文件结构** | aerial.nvim | Structure |
| **方法跳转** | treesitter | `Ctrl+Up/Down` |

---

## 安装

### 前提条件

| 依赖 | 版本 | 安装 |
|------|------|------|
| Neovim | 0.11+（本机验证 0.12.3） | `brew install neovim` |
| Java 运行时 | 21，供 Lathe / JDT LS 运行 | `brew install --cask zulu@21` |
| Java 项目编译器 | 8，供独立构建副本编译 | 安装 JDK 8，保留项目原有版本 |
| Maven | 本机验证 3.9.11 | `brew install maven`；项目依赖须已缓存 |
| Python | 3.10+ | `java_backend.lua` 中配置可执行文件 |
| ripgrep | - | `brew install ripgrep` |
| fd | - | `brew install fd` |
| fzf | - | `brew install fzf` |
| Node.js | 18+ | `brew install node` |
| Git | - | `brew install git` |

### 快速开始

```bash
# 本机 ~/.config/nvim 已软链到 ~/.vim/.config/nvim
# 重启后直接打开工程目录，也可直接打开工程内的 Java 文件
nvim /path/to/maven-project
```

Lathe 使用已安装的公开客户端、Maven 扩展和独立依赖缓存，不由 Mason 安装。新机器须先准备这些资源，并核对 `lua/user/java_backend.lua` 的资源、Python 和 JDK 路径；只有配置仓库本身不足以完成 Lathe 安装。详见下方 [Java 开发专题](#java-开发专题)。

---

## 配置结构

```
~/.config/nvim/
├── init.vim                      # 入口：设置 runtimepath
├── lazy-lock.json               # 插件版本锁定
├── lua/
│   ├── init.lua                 # lazy.nvim 初始化
│   └── user/
│       ├── options.lua          # Neovim 基础选项
│       ├── keymaps.lua          # 全局快捷键
│       ├── autocommands.lua     # 自动命令
│       ├── codediff_review.lua    # 分支审查、基准选择与会话键位
│       ├── codediff_merge_controls.lua # 块旁箭头、菜单与撤销边界
│       ├── codediff_merge_finish.lua # 保存、精确暂存与回到审查
│       ├── codediff_merge_presentation.lua # 来源标记、配色与有限记录
│       ├── java_backend.lua     # Java 后端选择与本机资源路径
│       ├── lathe_live.lua       # 多工程准备、实时源码和生命周期
│       ├── cmp.lua              # 自动补全配置
│       ├── plugins/
│       │   ├── init.lua         # 插件汇总入口
│       │   ├── java.lua         # Java 后端分发入口
│       │   ├── java_lathe.lua   # Lathe LSP 接入
│       │   ├── java_jdtls.lua   # JDT LS 独立配置
│       │   ├── lsp.lua          # LSP 服务器 + Mason
│       │   ├── search.lua       # fzf-lua + aerial + 书签
│       │   ├── spring.lua       # Spring HTTP 接口搜索
│       │   ├── dap.lua          # 调试器
│       │   ├── test.lua         # 测试运行器
│       │   ├── editing.lua      # Treesitter + 文本对象
│       │   ├── git.lua          # Git 集成
│       │   └── ui.lua           # UI 组件
│       └── lsp/
│           ├── handlers.lua     # LSP 通用配置
│           └── conform.lua      # 格式化器配置
├── scripts/
│   ├── lathe-model.py           # 自动识别 Maven、独立构建和发布模型
│   └── prewarm-jdtls.sh         # JDT 预热；Lathe 模式自动跳过
└── docs/
    └── java-dev-guide.md        # Java 开发详细指南
```

---

## 核心功能

### 1. 代码导航

#### 1.1 定义与引用

| 快捷键 | 功能 | 说明 |
|--------|------|------|
| `gd` | 智能跳转 | 定义处→显示引用，引用处→跳转定义 |
| `gD` | 跳到声明 | - |
| `gr` | 查找引用 | 过滤 Maven `.m2` 依赖 |
| `gi` | 跳到实现 | 接口→实现类 |
| `gu` | 跳到父类/接口 | Java 专属 |
| `gR` | 调用链 | 来调者树 (lspsaga GUI) |

#### 1.2 搜索体系

| 快捷键 | 用途 | 实现方式 |
|--------|------|----------|
| `<Leader>f` | 搜类/接口/方法名 | ripgrep 即时扫描 |
| `<Leader>F` | 全文内容搜索 | live grep |
| `<Leader>ha` | Spring HTTP 接口 | 扫描 `@Mapping` 注解 |
| `<Leader>e` | 最近文件 | - |
| `<Leader>s` | 文件结构大纲 | aerial |

#### 1.3 方法级跳转（Treesitter）

| 快捷键 | 功能 | IDEA 对应 |
|--------|------|-----------|
| `J` | 跳到下一个方法 | `Ctrl+Down` |
| `K` | 跳到上一个方法 | `Ctrl+Up` |
| `f` | AceJump 字符跳转 | AceJump |
| `F` | AceJump Treesitter 选择 | - |

**文本对象**（Visual/Operator 模式）：
- `af` / `if`：方法外部/内部
- `ac` / `ic`：类外部/内部
- `aa` / `ia`：参数外部/内部

### 2. 代码补全

使用 `nvim-cmp` 提供上下文感知的自动补全：

| 按键 | 功能 |
|------|------|
| `<C-e>` | 上一个候选 |
| `<C-u>` | 下一个候选 |
| `<CR>` | 确认选择 |
| `<Tab>` | 选择下一个 / 展开片段 |
| `<S-Tab>` | 选择上一个 |

**补全来源**：LSP、Snippets、Buffer、Path

### 3. 代码格式化

**手动触发**：`=`（选中或全文件）

| 文件类型 | 格式化器 |
|----------|----------|
| Java | google-java-format |
| Python | black + isort + ruff |
| Lua | stylua |
| JSON/JSONC | jq (2空格) |
| YAML | yamlfmt |
| JS/TS/Vue/CSS/HTML | prettier |

> 注意：不自动格式化保存，完全手动控制

### 4. 调试（nvim-dap）

| 快捷键 | 功能 | IDEA |
|--------|------|------|
| `bb` | 切换断点 | `F9` |
| `bc` | 条件断点 | `Ctrl+Shift+F8` |
| `br` | 继续运行 | `F9` |
| `bi` | 单步进入 | `F7` |
| `bn` | 单步跳过 | `F8` |
| `bp` | 单步返回 | `Shift+F8` |
| `bf` | 运行到光标 | `Alt+F9` |
| `be` | 表达式求值 | `Alt+F8` |
| `bv` | 查看断点面板 | - |
| `sd` | 切换调试 UI | - |

**远程调试**：`br` → 选择 "Remote Debug (Attach)" → 输入 `host:port`

### 5. 测试运行（neotest）

| 快捷键 | 功能 |
|--------|------|
| `zr` | 运行当前文件测试 |
| `zR` | 运行整个项目测试 |
| `zd` | 调试最近测试方法 |
| `zD` | 调试整个项目测试 |
| `sr` | 切换测试结果面板 |

### 6. Git 集成

**gitsigns（行内）**：
| 快捷键 | 功能 |
|--------|------|
| `<C-d>` | 下一个 hunk |
| `<C-f>` | 上一个 hunk |
| `gp` | 预览 hunk |
| `<C-u>` | 重置 hunk |

**CodeDiff（主审查）**：按目录展示整个分支相对比较基准的变更，包含已提交、未提交和未跟踪文件；Enter 选择文件后，仅显示该文件的完整 Diff。默认基准为 `origin/master`，`,gB` 只选择比较基准，不 checkout 或 fetch。

| 快捷键 | 功能 |
|--------|------|
| `,gd` | 打开审查；存在未合并文件时进入冲突列表 |
| `,gB` | Compare with Branch |
| `,gc` / `q` | 关闭审查，保留未完成/未保存提示 |
| `Ctrl+d` / `Ctrl+f` | 普通 Diff 下一/上一变更；合并视图下一/上一未解决冲突 |
| `,w` | 最大化当前拆分窗口，再按恢复 |
| `,gh` / `,gH` | Diffview 文件/项目历史 |
| `:DiffviewBranchReview` | 按同一比较基准使用 Diffview 回退 |

合并视图直接按 `m` 打开英文菜单，无需 `,g` 前缀。`ml/mr/ma/mu` 分别接受左侧、右侧、双方和还原祖先；`mz/mZ` 撤销/重做，`mf` 保存当前文件并暂存为已解决，再回该文件普通 Diff。未解决块或残留冲突标记会阻止完成。

安装固定版本、完整键位、来源标记及安全边界见 [Git 审查与合并指南](docs/git-review-guide.md)。

### 7. LSP 功能

| 快捷键 | 功能 | IDEA |
|--------|------|------|
| `<Leader>R` | 重命名 | `Shift+F6` |
| `ga` | Code Action | `Alt+Enter` |
| `<c-p>` | Hover 文档 | `F1` |
| `qt` | 类型定义 | - |
| `qd` | Quick JavaDoc | - |
| `<Leader>oi` | 整理导入 (Java) | `Ctrl+Alt+O` |
| `<Leader>T` | 重构菜单 (Java) | `Ctrl+Alt+Shift+T` |
| `<Leader>ih` | 切换 Inlay Hints | 参数名提示 |
| `se` | 显示诊断 | - |
| `<F2>` | 下一个错误 | `F2` |

### 8. 窗口与工具

| 快捷键 | 功能 |
|--------|------|
| `gh/gj/gk/gl` | 窗口导航 |
| `sV` / `sv` | 水平/垂直分割 |
| `sl` / `sh` | 下一个/上一个窗口 |
| `sw` | 在新窗口打开定义 |
| `sq` | 关闭窗口 |
| `<Leader>w` | 最大化当前拆分/恢复原布局 |
| `<Leader><Arrow>` | 调整窗口大小 |
| `gw` | 切换文件树 |
| `<Leader>P` | 定位当前文件 |
| `st` | 打开终端 |

### 9. 书签

| 快捷键 | 功能 | IDEA |
|--------|------|------|
| `mm` | 打标/取消书签 | `F11` |
| `ma` | 查看所有书签 | `Shift+F11` |
| `gm` | 下一个书签 | `F4` |
| `gM` | 上一个书签 | `Shift+F4` |

### 10. 折叠

| 快捷键 | 功能 |
|--------|------|
| `zz` | 折叠/展开当前块 |
| `zZ` | 折叠/展开所有 |
| `zc` | 居中当前行 |
| `zO` | 全部展开 |

---

## 快捷键

> `<Leader>` = `,`（逗号键）

### 快速参考卡

```
【导航】
  gd   智能跳转定义/引用
  gr   查找所有引用
  gi   跳到实现
  gR   调用链分析
  J/K  下一个/上一个方法
  f/F  AceJump

【搜索】
  <Leader>f   搜类/方法名
  <Leader>F   全文搜索
  <Leader>ha  Spring 接口
  <Leader>e   最近文件
  <Leader>s   文件结构

【编辑】
  =    格式化
  ga   快速修复
  <Leader>R   重命名
  <Leader>oi  整理导入

【调试】
  bb   切换断点
  br   继续运行
  bi   单步进入
  bn   单步跳过
  sd   调试面板

【测试】
  zr   运行当前文件
  zR   运行全部
  zd   调试测试
  sr   测试结果面板

【Git】
  <Leader>gd  Git diff
  gp   预览 hunk
  <C-d>/<C-f>  hunk 跳转

【窗口】
  gh/j/k/l  窗口导航
  <Leader>w  最大化当前拆分/恢复布局
  gw   文件树
```

---

## 语言支持

### Java

- **LSP**: 默认 Lathe，可切换为 JDT LS；同一配置只加载选中的 Java 后端
- **调试**: nvim-dap (内置 Java 适配器)
- **测试**: neotest-java (JUnit 4/5)
- **格式化**: google-java-format
- **特色功能**: Java 8 分析、Lombok 支持、多模块 Maven；Spring Boot LS 仅在 JDT LS 模式启用

Lathe 下的调试、JUnit 运行器与 Spring 专属功能没有在本轮做兼容性验收，不将插件已安装等同于这些能力均已通过验证。

[详细 Java 开发指南 →](./docs/java-dev-guide.md)

### Python

- **LSP**: pyright
- **格式化**: black + isort + ruff
- **调试**: nvim-dap (需手动配置 debugpy)

### TypeScript / JavaScript / Vue

- **LSP**: ts_ls (TypeScript), vue_ls (Vue 3), eslint
- **格式化**: prettier
- **特色**: Vue 单文件组件完整支持、ESLint 集成

### 其他语言

| 语言 | LSP | 格式化 |
|------|-----|--------|
| Lua | builtin | stylua |
| Rust | rust_analyzer | builtin |
| Go | gopls | builtin |
| JSON | builtin | jq |
| YAML | builtin | yamlfmt |
| CSS/SCSS | cssls | prettier |
| HTML | html | prettier |

---

## Java 开发专题

### 一行切换后端

编辑 [lua/user/java_backend.lua](lua/user/java_backend.lua)，只改下面一行，然后重启 Neovim：

```lua
server = "lathe", -- 改成 "jdtls" 即切回 JDT LS
```

`java.lua` 分发到两个独立实现。Mason 不自动启动第二个 JDT LS；选择 Lathe 时，JDT 预热脚本直接跳过。切换不改项目 POM、全局 `JAVA_HOME` 或 Zed 配置。

### Maven 自动准备与实时审查

| 时机 | 行为 |
|------|------|
| 首次打开目录或 Java 文件 | 从最近的 POM 向上确认真实聚合关系，识别多模块工程并后台准备模型 |
| 再次打开同一工程 | 复用已有模型和缓存，不因重新打开而重跑 Maven |
| 外部工具修改源码 | LSP 的源码根指向原工程；可见且未编辑的缓冲区自动重载，未保存编辑保持不动 |
| 编辑器内修改 Java | 通过 LSP 发送未保存内容，不要求先保存到构建副本 |
| POM、构建配置或已解析依赖变化 | 自动在后台更新独立模型；失败保留上一份可用模型 |
| 同时打开多个工程 | 按规范化工程根路径区分客户端、构建目录和缓存，避免同名类跨工程串跳 |

首次准备会离线运行 Maven 并编译主源码，耗时取决于项目规模；这不是业务测试通过的证明。当前准备命令跳过测试编译和执行，测试源码的完整语义能力未纳入本轮验收。缺少本地依赖或原工程编译失败时会显示失败状态，不修改原工程来绕过错误。

### Java 8 与 Lombok 边界

| 部分 | 使用方式 |
|------|----------|
| Lathe 运行时 | JDK 21，默认 JVM 参数 `-Xms256m -Xmx3g` |
| 独立构建副本 | JDK 8 编译器，保留项目原 Lombok 依赖；显式 `release=8` 只在副本转为等价的 source/target 8 参数 |
| 编辑器分析模型 | `--release 8`；兼容性处理仅替换分析模型中的旧 Lombok，原项目依赖版本保持不变 |
| 原工程 | 不写入 `.lathe`、构建输出或 POM；不自动 `git add` |

### 安装资源与缓存

本机安装资源由 `java_backend.lua` 的 `lathe.resources` 指定，目前位于 `~/.codex/experiments/lathe-java8-20261116-side`，需保留其中的 `lathe.nvim-0.3.1`、`extension-classpath.txt` 和 `vim-trial/m2`。这些资源不包含在配置提交中；分析脚本使用的 Maven/JDK 8 路径见 `scripts/lathe-model.py`。该模式当前面向 Maven Java 8，其他构建系统可切换 JDT LS。

| 数据 | 默认位置 |
|------|----------|
| 每工程状态、日志、模型和索引缓存 | `~/.local/state/nvim/lathe/projects/<工程路径哈希>/` |
| Git 工程的独立构建 worktree | `~/.codex/worktrees/lathe-<工程路径哈希>/<仓库名>/` |
| 非 Git 工程的构建副本 | 对应状态目录下的 `build/` |
| 独立 Maven 制品缓存 | `lathe.resources` 下的 `vim-trial/m2/`，多个工程复用；原 `~/.m2` 只读取 |
| JDT LS 缓存（macOS） | `~/Library/Caches/jdtls/nvim-<工程路径哈希>/`，可复用身份匹配的历史缓存 |

后台准备退出时只收尾本次任务的子进程；已完成的模型和缓存保留供下次复用。

### 状态与维护入口

| 入口 | Lathe | JDT LS |
|------|-------|--------|
| 状态栏 | 区分等待、准备模型、失败、模型已准备和客户端连接状态 | 区分服务就绪与真实构建任务；ServiceReady 不代表所有语义查询已完成 |
| `,jr` | 刷新当前工程模型；打开 Java 文件后可重试首次准备失败 | 更新当前项目配置 |
| `,jR` | 在独立构建副本执行 clean 后重新准备 | 重建当前工程的专用 workspace |
| `:LatheLog` | 查看当前或最近失败工程的准备日志 | 不适用 |
| `:LatheSync` | 手动提交模型刷新请求 | 不适用 |

### 本轮验证（2026-11-16）

已验证目录自动准备、多模块和嵌套工程识别、两个工程同名符号的跳转隔离、缓存复用、POM 自动刷新、缺依赖后的重试、Java 8 API 限制、退出时进程收尾，以及真实工程的 `gd` 和 `,f` 源码预览。JDT LS 切换后完成了服务就绪和文件符号查询检查。核对过原工程 POM、Git 状态及暂存区，保持不变；没有运行业务回归测试。

### Spring Boot 支持

可选安装 Spring Boot Language Server：

```bash
bash ~/.config/nvim/scripts/install-spring-boot-ls.sh
```

提供：
- Bean 定义导航
- `@RequestMapping` 补全
- `application.yml/properties` 智能提示

---

## 故障排除

### 通用检查清单

```vim
:checkhealth          " 环境健康检查
:LspInfo             " LSP 客户端状态
:LspLog              " LSP 日志
:Mason               " 管理 LSP 工具
:Lazy                " 插件管理
```

### 常见问题

**Q: Lathe 提示准备失败**
- 执行 `:LatheLog`，核对 Maven 缺依赖、编译错误及本机资源路径。
- 在原工程按正常研发流程准备缺失依赖；分析任务保持离线，不自动修改原 POM。
- 保存 POM 或补齐已监测的本地依赖后自动重试，也可打开 Java 文件后按 `,jr`。
- 第一次准备尚未完成时，符号搜索可以使用，语义跳转需等待模型和服务就绪。

**Q: 切到 jdtls 后显示 `✗` 未连接**
- 确认当前文件是 `.java`
- 确认项目根有 `pom.xml` 或 `build.gradle`
- 检查 Java 21: `/usr/libexec/java_home -v 21`
- 检查 jdtls 安装: `:Mason`

**Q: `gd` 跳转没反应**
- 先在 `:LspInfo` 确认当前缓冲区连接的是所选后端。
- Lathe 先检查模型准备状态和 `:LatheLog`；JDT LS 检查服务和构建状态。

**Q: 格式化不生效**
- 确认格式化器已安装: `:Mason`
- 手动触发: `=`
- 检查 conform 配置: `:ConformInfo`

**Q: 补全不工作**
- 确认 LSP 已连接: `:LspInfo`
- 检查 cmp 状态: `:CmpStatus`

### 更新维护

```vim
:Lazy update          " 更新插件
:MasonUpdate          " 更新 Mason 工具
:TSUpdate             " 更新 Treesitter 解析器
```

---

## 自定义

### 添加新 LSP 服务器

编辑 `lua/user/plugins/lsp.lua`：

```lua
vim.lsp.config("myserver", {
  cmd = { mason_bin .. "/myserver", "--stdio" },
  filetypes = { "myfiletype" },
  root_markers = { ".git", "config.json" },
  on_attach = handlers.on_attach,
  capabilities = handlers.capabilities,
})
vim.lsp.enable("myserver")
```

### 添加格式化器

编辑 `lua/user/lsp/conform.lua`：

```lua
formatters_by_ft = {
  myfiletype = { "myformatter" },
}
```

### 添加快捷键

编辑 `lua/user/keymaps.lua`：

```lua
vim.keymap.set("n", "<Leader>x", ":MyCommand<CR>", { noremap = true, silent = true })
```

---

## 参考

- [Java 开发详细指南](./docs/java-dev-guide.md)
- [lazy.nvim 文档](https://github.com/folke/lazy.nvim)
- [nvim-jdtls 文档](https://github.com/mfussenegger/nvim-jdtls)
- [fzf-lua 文档](https://github.com/ibhagwan/fzf-lua)
