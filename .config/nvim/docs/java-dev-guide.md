# Neovim Java 开发配置指南

> Java 只使用 Lathe 0.3.1，打开 Maven 工程自动准备 Java 8 模型。安装资源、独立缓存、重试和验证范围统一见 [配置说明的 Java 开发专题](../README.md#java-开发专题)。
> 本页只保留源码审查、导航和编辑。Neovim 中的测试运行器、DAP及其快捷键已移除。

---

## 目录

1. [环境依赖](#1-环境依赖)
2. [插件架构总览](#2-插件架构总览)
3. [快捷键速查表](#3-快捷键速查表)
4. [配置文件导航](#4-配置文件导航)
5. [核心功能详解](#5-核心功能详解)
6. [常见操作流程](#6-常见操作流程)
7. [故障排除](#7-故障排除)
8. [维护与更新](#8-维护与更新)

---

## 1. 环境依赖

### 必须安装

| 依赖 | 版本要求 | 安装方式 |
|------|----------|----------|
| Neovim | 0.12+（本机验证 0.12.3） | `brew install neovim` |
| Java | 21（LSP 运行环境）及 8（Lathe 独立构建） | 保留项目 Java 8，另装 JDK 21 |
| Maven / Python | 本机 Maven 3.9.11、Python 3.10+ | Lathe 资源和路径见主说明 |
| ripgrep | 任意 | `brew install ripgrep` |
| fd | 任意 | `brew install fd` |
| Node.js | 18+ | `brew install node`（prettier/ts-ls 依赖） |

### 安装工具与 Lombok

Lathe 客户端、运行资源和独立 Maven 模型按 [主配置说明](../README.md#java-开发专题) 准备，不使用 Mason。项目原 Lombok 依赖保持不变；模型侧兼容处理见 `scripts/lathe-model.py`。非 Java 工具按 [独立语言工具安装](language-tools.md) 维护。

`,ha` 保留静态 Spring HTTP 注解搜索。本配置不再包含独立 Spring Boot LS 安装脚本，不宣称 Bean 专用语义已接入。

---

## 2. 插件架构总览

```
lua/
├── init.lua                    # 启动入口（lazy.nvim 初始化）
└── user/
    ├── options.lua             # Neovim 基础选项
    ├── keymaps.lua             # 全局快捷键
    ├── autocommands.lua        # 自动命令
    ├── plugins/
    │   ├── init.lua            # 插件汇总入口
    │   ├── java.lua            # Lathe 唯一 Java 接入
    │   ├── lsp.lua             # 补全与格式化插件
    │   ├── search.lua          # aerial + lspsaga（Snacks统一Picker）
    │   ├── spring.lua          # Spring HTTP 接口搜索
    │   ├── editing.lua         # Treesitter + flash.nvim + 文本对象
    │   ├── git.lua             # Git 集成
    │   └── ui.lua              # 主题、状态栏、文件树等 UI
    └── lsp/
        ├── handlers.lua        # LSP 通用配置（诊断、快捷键、capabilities）
        └── conform.lua         # 格式化器配置
```

### Java 相关插件一览

| 插件 | 功能 | 对应 IDEA 功能 |
|------|------|----------------|
| `ag-libs/lathe.nvim` | 唯一 Java 语义服务 | Java 分析与运行接口 |
| `snacks.nvim` | 统一搜索与导航Picker | Search Everywhere / Find Usages |
| `stevearc/aerial.nvim` | 文件结构大纲 | Structure 窗口 |
| `nvimdev/lspsaga.nvim` | 调用链（Call Hierarchy） | Call Hierarchy |
| `stevearc/conform.nvim` | 代码格式化 | google-java-format |
| `nvim-treesitter/nvim-treesitter` | 语法高亮/折叠/文本对象 | 内置 |
| Spring Boot LS | Bean 导航 / yml 补全 | Spring 插件 |

---

## 3. 快捷键速查表

> `<Leader>` = 空格键

### 导航与跳转

| 快捷键 | 功能 | IDEA 对应 |
|--------|------|-----------|
| `gd` | 智能跳转：在定义处→显示引用，在引用处→跳到定义 | `Cmd+B` |
| `gD` | 跳到声明 | `Cmd+Alt+B` |
| `gr` | 查找所有引用（过滤 Maven .m2） | `Alt+F7` |
| `gi` | 跳到实现 | `Cmd+Alt+B`（接口→实现） |
| `gu` | 跳到父类/接口方法 | `Cmd+U` |
| `gR` | 调用链（来调者树，lspsaga GUI） | `Ctrl+Alt+H` |
| `qi` | 快速查看实现列表 | `Cmd+Alt+B` |
| `<c-p>` | 查看文档 Hover | `F1` |
| `J` | 跳到下一个方法 | `Ctrl+Down` |
| `K` | 跳到上一个方法 | `Ctrl+Up` |
| `f` | AceJump 字符跳转 | `Cmd+Shift+F` AceJump |
| `H` | 行首 | `Home` |
| `L` | 行尾 | `End` |

### 搜索

| 快捷键 | 功能 | 说明 |
|--------|------|------|
| `<Leader>f` | 搜索项目类/接口/枚举/方法声明 | ripgrep 即时，无 LSP 依赖 |
| `<Leader>F` | 全文内容搜索（live grep） | 适合搜字符串、注解值 |
| `<Leader>e` | 最近打开文件 | RecentFiles |
| `<Leader>s` | 当前文件结构大纲（aerial） | FileStructurePopup |
| `<Leader>ha` | 搜索项目所有 Spring HTTP 接口 | Cool Request 等价 |

### LSP 操作

| 快捷键 | 功能 | IDEA 对应 |
|--------|------|-----------|
| `<Leader>R` | 重命名 | `Shift+F6` |
| `ga` | 快速修复 / Code Action | `Alt+Enter` |
| `se` | 显示当前行诊断错误 | 鼠标悬停 |
| `<F2>` | 跳到下一个错误 | `F2` |
| `<Leader>oi` | 整理导入（Java） | `Ctrl+Alt+O` |
| `<Leader>T` | 重构菜单（Java） | `Ctrl+Alt+Shift+T` |
| `<Leader>ih` | 切换 Inlay Hints 显示 | 参数名内联提示 |
| `=` | 格式化当前文件/选区 | `Cmd+Alt+L` |

### 书签与跳转记录

使用 Vim 原生 marks：`mA` 设置文件标记，`'A` 返回标记行；`Ctrl+o` / `Ctrl+i` 访问跳转记录。已移除失效的 vim-bookmarks/Harpoon 配置，不再声明 `mm`、`gm`、`gM` 为插件书签键。三方合并中的 `ma` 保持 Accept Both。

### Java 模型与索引管理

| 快捷键 | 功能 | 说明 |
|--------|------|------|
| `<Leader>lr` | 刷新 Lathe 项目模型 | Lathe 首次失败时先打开 Java 文件再重试 |
| `<Leader>lR` | 重建 Lathe 项目模型 | 只清理 Lathe 独立构建输出 |

### 窗口管理

| 快捷键 | 功能 |
|--------|------|
| `gh/gj/gk/gl` | 窗口导航（左/下/上/右） |
| `<Leader>w` | 隐藏/恢复所有工具窗口（IDEA Shift+F12） |
| `<Leader><Arrow>` | 调整窗口大小 |
| `gn` | 跳转匹配括号 |

### 折叠

| 快捷键 | 功能 |
|--------|------|
| `zz` | 折叠/展开当前块 |
| `zZ` | 折叠/展开所有 |

---

## 4. 配置文件导航

修改某个功能时，应该改哪个文件：

| 需求 | 文件 |
|------|------|
| Lathe 安装和 JVM 参数 | `lua/user/lathe_config.lua` |
| Lathe 多工程生命周期 | `lua/user/lathe_live.lua` |
| Lathe Maven 模型准备 | `scripts/lathe-model.py` |
| 添加新 LSP 服务器 | `lua/user/plugins/lsp.lua` |
| 修改格式化器 | `lua/user/lsp/conform.lua` |
| 修改搜索快捷键 | `lua/user/plugins/search.lua` |
| Spring 接口搜索逻辑 | `lua/user/plugins/spring.lua` |
| LSP 诊断样式、通用快捷键 | `lua/user/lsp/handlers.lua` |
| 全局编辑器选项 | `lua/user/options.lua` |
| 全局快捷键 | `lua/user/keymaps.lua` |

---

## 5. 核心功能详解

### 5.1 Lathe Java 服务

`lathe_config.lua` 只保存 Lathe 资源、JDK/Python、堆参数与状态目录。`plugins/java.lua` 注册服务，`lathe_live.lua` 维护原源码、独立构建和工程生命周期。没有 JDT 后端开关。

状态栏直接读取 Lathe：等待/准备模型、准备失败、模型已准备，以及客户端连接状态。`,lr` 刷新，`,lR` 重建，`:LatheLog` 看日志；所有跳转与补全共用公共 LSP 键位。

### 5.2 搜索体系

三种搜索各司其职：

| 快捷键 | 适合场景 | 底层实现 |
|--------|----------|----------|
| `<Leader>f` | 搜类名、方法名、接口名 | ripgrep 扫声明行，即时 |
| `<Leader>F` | 搜字符串内容、注解值、配置项 | ripgrep live grep |
| `<Leader>ha` | 搜 HTTP 接口路径（Spring） | ripgrep 扫 @Mapping 注解 |

`<Leader>f` 识别的 Java 声明模式：
- `class Foo` / `interface Bar` / `enum Baz` / `@interface Qux`
- `public/protected/private void/String methodName(`

`<Leader>ha` 特性：
- 自动拼接类级别 `@RequestMapping` 前缀 + 方法级别路径
- 支持多行注解（`value` 在下一行的格式）
- 识别 HTTP 方法：GET/POST/PUT/DELETE/PATCH/ANY

### 5.3 格式化

格式化**只在手动按 `=` 时触发**，不自动格式化：

| 文件类型 | 格式化器 |
|----------|----------|
| Java | google-java-format |
| JSON / JSONC | jq（2 空格缩进） |
| YAML | yamlfmt |
| Lua | stylua |
| Python | black + isort + ruff_format |
| JS/TS/Vue/CSS/HTML | prettier |

禁用自动格式化的机制：
- conform 无 `format_on_save` 配置
- `willSaveWaitUntil` LSP 协议已禁用（防止语言服务在保存前注入格式化）

### 5.4 Call Hierarchy（调用链）

`gR` 使用 lspsaga 的 GUI 浮窗：

| 按键 | 功能 |
|------|------|
| `u` | 展开/折叠节点 |
| `<CR>` | 跳转到调用处 |
| `v` | 垂直分割打开 |
| `s` | 水平分割打开 |
| `q` | 关闭 |

### 5.5 Inlay Hints

在方法调用处显示参数名（灰色内联提示）：
```java
orderService.create(userId: id, quantity: 3)
//                  ^^^^^^^^   ^^^^^^^^  ← 灰色提示
```

- 默认**开启**（服务支持并就绪后自动生效）
- `<Leader>ih` 切换显示/隐藏

---

## 6. 常见操作流程

### 打开新 Java 项目

```bash
# 从项目根目录（含 pom.xml）启动 nvim
cd /path/to/maven-project
nvim src/main/java/com/example/SomeClass.java

# 默认 Lathe 自动识别 Maven 并准备模型；打开 Java 文件后附着 LSP
# 已有模型会复用，首次准备耗时依项目规模与本地依赖而定
```

### 重建损坏的索引

```
# 重建独立构建模型
<Leader>lR

# 软刷新（pom.xml 依赖变更后同步）
<Leader>lr
```

### 查找 Spring 接口

```
<Leader>ha   # 打开 Spring 接口列表
# 输入路径关键词过滤，如 "/order" 或 "createOrder"
# <Enter> 跳转到对应 Controller 方法
```

---

## 7. 故障排除

### Lathe 准备失败或未连接

打开 `.java` 文件，先执行 `:LatheLog` 检查资源、编译器和离线依赖。补齐原工程依赖或编译错误后 `,lr` 重试；只有必要时才 `,lR` 重建。项目原 POM、依赖版本和暂存区不由准备过程修改。

### `gd` 跳转没反应

- 先确认当前 Java 缓冲区连接 Lathe，并检查 `:LatheLog`
- 若状态是 `󰔟`，等待索引完成
- 若 LSP 未就绪，`gd` 会弹出 "LSP 未连接" 提示

### `<Leader>f` 搜不到符号

- 确认从项目根目录（最顶层 pom.xml）打开 nvim
- 确认 ripgrep 已安装：`rg --version`
- `<Leader>f` 只搜 `*.java` 文件的声明行，不搜 JAR 包内的类（那是 `gd` + LSP 的职责）

### `<Leader>ha` 显示 "no path"

- 注解路径在下一行的多行格式已支持（向后读 4 行）
- 若仍显示 no path，说明路径用了常量（如 `@GetMapping(Const.PATH)`），ripgrep 无法静态解析

### 格式化后代码被意外修改

- 确认 conform.lua 没有 `format_on_save`（当前已移除）
- 确认 `autocommands.lua` 有 `willSaveWaitUntil` handler 覆盖
- 若仍有问题，在 Neovim 中运行 `:verbose autocmd BufWritePre` 查看注册的处理器

### google-java-format 未安装

```
# 手动安装工具后用 :ConformInfo 检查实际命令
```

---

## 8. 维护与更新

### 更新所有插件

```
:Lazy update
```

### 更新独立语言工具

按 [语言工具安装](language-tools.md) 在编辑器之外更新对应前缀目录，不在启动时自动升级。

### 修改 Lathe 内存限制

编辑 `lua/user/lathe_config.lua` 的 `jvm_opts`，下次重开 Neovim 生效。

### 添加新 LSP 服务器

在 `lua/user/lsp/servers.lua` 参照现有配置添加服务。统一填写 `handlers.on_attach` 和 `handlers.capabilities`，不再另配快捷键：
```lua
vim.lsp.config("新服务器名", {
  cmd = { "/absolute/path/to/server", "--stdio" },
  filetypes = { "对应文件类型" },
  root_markers = { "项目标记文件" },
  on_attach = handlers.on_attach,
  capabilities = handlers.capabilities,
})
vim.lsp.enable("新服务器名")
```

### 添加新格式化器

在 `lua/user/lsp/conform.lua` 的 `formatters_by_ft` 中添加：
```lua
新文件类型 = { "格式化器名称" },
```
然后独立安装对应工具，并用 `:ConformInfo` 检查实际可执行路径。

### 禁用某个 LSP 的自动格式化

在对应 LSP 的 `on_attach` 中添加：
```lua
client.server_capabilities.documentFormattingProvider = false
```

---

## 附录：目录结构速查

- `~/.local/share/nvim/language-tools/`：独立非 Java npm 工具前缀。
- `~/.local/state/nvim/lathe/projects/`：Lathe 每工程模型、日志和索引。
- `~/.config/nvim/lua/user/lathe_config.lua`：Lathe 本机资源参数。
- `~/.config/nvim/lua/user/lsp/servers.lua`：所有非 Java 服务配置。
- `~/.config/nvim/lua/user/lsp/handlers.lua`：共享导航、重构、提示与安全规则。

## 未使用代码置灰

当前 Lathe 0.3.1 对未使用的private方法、私有字段、局部变量等发送 `lathe.unused`、Hint和 `DiagnosticTag.Unnecessary`。Neovim原生将其渲染为 `DiagnosticUnnecessary`，Catppuccin配置明确设为灰色；只变灰服务端标出的标识符范围，不会把整段方法体变灰。

本地真实服务验证：同一文件内新增未调用的private/public方法（仅未保存buffer，退出还原），仅private方法收到上述诊断。public方法、跨项目API和框架/反射入口不因此被判为未使用；没有后台逐方法请求references的轮询，也没有按文本搜索数量伪造诊断。它不等价于IDEA全项目Unused declaration检查。普通真实源码可显示；历史Diff虚拟buffer没有附着语言服务时不会产生新的语义诊断。
