# Neovim 配置

面向 Java 代码审查和日常编辑的 Neovim 配置，也保留 Python、TypeScript/Vue 语义服务，以及 Rust 等语言的语法高亮。

Java 语义导航使用 **Lathe 0.3.1**，打开 Maven 工程时自动准备分析模型。其他语言由独立安装的语言服务提供支持，快捷键和补全共用 Neovim 的统一配置。编辑器配置保存在 Neovim 的配置目录。

---

## 目录

完整文件、插件、工具的保留／删除结果与替代方案见 [全量配置盘点](docs/config-inventory.md)。

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
|---|---|---|
| 代码导航 | Snacks Picker + Lathe/各语言LSP | Search Everywhere / Goto |
| 代码补全 | nvim-cmp + LSP | 智能补全 |
| 代码格式化 | conform.nvim | Reformat |
| 版本控制 | CodeDiff + Gitsigns | Git审查、历史、合并与源码行级操作 |
| 调用链 | lspsaga | 多级 Call Hierarchy |
| 文件大纲 | aerial.nvim | Structure |
| 方法跳转 | Treesitter + textobjects | Method Up/Down |

配置专注审查、导航与编辑，已移除 Neovim 测试运行器和调试器。完整最小集判断与最新工具比较见 [导航与界面分析](docs/navigation-ui-minimum.md)。

---

## 安装

### 前提条件

| 依赖 | 版本 | 安装 |
|------|------|------|
| Neovim | 0.12+（本机验证 0.12.3） | `brew install neovim` |
| Java 运行时 | 21，供 Lathe 运行 | `brew install --cask zulu@21` |
| Java 项目编译器 | 8，供独立构建副本编译 | 安装 JDK 8，保留项目原有版本 |
| Maven | 本机验证 3.9.11 | `brew install maven`；项目依赖须已缓存 |
| Python | 3.10+ | `lathe_config.lua` 中配置可执行文件 |
| ripgrep | - | `brew install ripgrep` |
| fd | - | `brew install fd` |
| Node.js | 18+ | `brew install node` |
| Git | - | `brew install git` |

### 快速开始

```bash
# 本机 ~/.config/nvim 已软链到 ~/.vim/.config/nvim
# 重启后直接打开工程目录，也可直接打开工程内的 Java 文件
nvim /path/to/maven-project
```

Lathe 使用已安装的公开客户端、Maven 扩展和独立依赖缓存，不由 Mason 安装。新机器须先准备这些资源，并核对 `lua/user/lathe_config.lua` 的资源、Python 和 JDK 路径；只有配置仓库本身不足以完成 Lathe 安装。详见下方 [Java 开发专题](#java-开发专题)。

---

## 配置结构

```
~/.config/nvim/
├── init.vim                      # 入口：加载 lua/init.lua
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
│       ├── lathe_config.lua     # Lathe 本机资源路径
│       ├── project.lua          # 原生自动项目根定位
│       ├── lathe_live.lua       # 多工程准备、实时源码和生命周期
│       ├── cmp.lua              # 自动补全配置
│       ├── plugins/
│       │   ├── init.lua         # 插件汇总入口
│       │   ├── java.lua         # Lathe 唯一接入入口
│       │   ├── lsp.lua          # 补全与格式化插件
│       │   ├── search.lua       # aerial + lspsaga（Picker由Snacks提供）
│       │   ├── spring.lua       # Spring HTTP 接口搜索
│       │   ├── editing.lua      # Treesitter + 文本对象
│       │   ├── git.lua          # Git 集成
│       │   └── ui.lua           # UI 组件
│       └── lsp/
│           ├── servers.lua      # 原生语言服务配置（独立工具目录）
│           ├── handlers.lua     # LSP 通用配置
│           └── conform.lua      # 格式化器配置
├── scripts/
│   ├── lathe-model.py           # 自动识别 Maven、独立构建和发布模型
└── docs/
    └── java-dev-guide.md        # Java 开发详细指南
```

---

## Snacks 整合与迁移

当前注册30个插件。Snacks **v2.31.0**（`e6fd58c82f2f3fcddd3fe81703d47d6d48fc7b9f`）取代 fzf-lua、nvim-tree、toggleterm 和 vim-bbye；保留 Aerial、Saga、Flash、Bufferline、Lualine、Which-key。详见 [整合说明](docs/navigation-ui-minimum.md)。仅启用 picker、explorer、terminal，buffer删除按需调用；未启用dashboard、GitHub集成、滚动动画等功能。

公开发行包解压到 `~/.local/share/nvim/lazy/snacks.nvim`，由本地dir加载，无Git remote；该版本由本节固定，不由lazy-lock锁定。新机器应先从[固定commit发行包](https://codeload.github.com/folke/snacks.nvim/tar.gz/e6fd58c82f2f3fcddd3fe81703d47d6d48fc7b9f)安装到此目录。

- `,f` 项目符号、`,F` 全文、`,e` 项目最近文件、`,b` buffer、`gr/gi` 引用与实现均有源码预览。Java `,f`保留已保存类型/方法扫描；字段和未保存覆盖不是本轮新增能力。
- Neovide 无参数启动时恢复最近项目的根目录和文件。`gw` 在同一应用里进入所选项目的新窗口，优先打开该项目最近访问的文件。`,p` / `,P` 打开目录树并定位当前文件。项目树 Git 颜色显示工作区状态，分支对比使用 `,gd` 的 CodeDiff 树。
- `st` / Ctrl+反斜杠显隐底部终端，保留会话、尺寸和Esc/jk；`,c/,C`关闭buffer保留窗口布局。关闭未保存buffer会询问，不强制丢弃。
- Which-key主菜单聚焦搜索、文件、Git、Java、HTTP与Problems；重复的`,S*`和次要LSP别名仍可使用，不在主菜单展示；Merge专用m菜单只在合并上下文出现。

## 核心功能

### 1. 代码导航

#### 1.1 定义与引用

| 快捷键 | 功能 | 说明 |
|--------|------|------|
| `gd` | 智能跳转 | 定义处显示引用，使用处跳转定义。能确认依赖版本及符号的类和实例方法可回退到只读字节码 |
| `gD` | 跳到声明 | - |
| `gr` | 查找引用 | 保留语言服务返回的测试引用，并排到其他结果之后。由 `gd` 打开的引用列表也使用此顺序 |
| `gi` | 跳到实现 | Java Mapper 调用可直接跳到 XML 语句，其余调用查询实现 |
| `gu` | 跳到父类/接口 | Java 专属 |
| `gR` | 调用链 | 来调者树 (lspsaga GUI) |

MyBatis 根据完整 `namespace` 和语句 `id` 匹配。Java Mapper 方法声明与 XML 中的 `select`、`insert`、`update`、`delete` 可用 `gd` 互跳，`Ctrl+o` 回到原位置。可直接打开 Lathe 缓存的依赖源码，在字段名上用 `gr` 或 `gd` 搜索模型中能验证归属的字段引用和 getter/setter 调用。

Mapper XML 中，`gd` 可跳到 `resultMap`、`extends` 和 `include refid` 对应定义。对能解析出 Java 类型的映射属性、`@Param` 参数、`foreach` 元素和 OGNL 属性也可跳到 Java 声明。复用片段根据调用它的语句解析参数类型。光标处的 `gr` 可反查对应 XML，Java 属性声明上的 `gr` 同时查询语言服务。依赖动态键或无法确认类型的表达式会提示无法静态定位。

在普通 Java DTO 的字段声明上按 `gd` 或 `gr`，可查看普通引用及能静态确认的 Lombok 构造器实参。选中结果会定位到对应参数。Spring 导航先核对 Bean 注册，再处理普通类上的构造器注入候选。

Java Spring 导航按需启动 Spring Boot Language Server，直接复用 Lathe 捕获的 Maven 模块、源码根、编译 classpath 和项目 JDK。Lathe 继续提供 Java 定义与引用，Spring Tools 提供 Bean 符号。macOS 上 Spring 服务在本地网络隔离中运行。

- 在构造器、`@Autowired`、`@Resource` 或 `@Bean` 参数的注入点按 `gd` 跳到 Bean。Lombok 隐式构造器的注入点显示在对应字段上。构造器选取遵循可静态确认的签名和 `onConstructor`，只在 `lombok.config` 声明复制 `@Qualifier` 时把字段限定符用于生成的参数。
- 在 Spring XML 的 `ref`、`depends-on`、`parent`、`factory-bean` 或别名上按 `gd` 跳到 Bean，从 `class` 跳到工程里的 Java 声明。XML 范围由 Lathe 捕获的 Maven 资源根决定。
- 在 Bean 类名、工厂方法名、XML `id` 或注册名称上按 `gr` 反查能唯一确认的注入点和配置引用。有多个静态候选时，`gd` 会打开候选列表。测试路径排在最后。
- `:SpringProfiles dev` 或 `:SpringProfiles dev,local` 为当前工程选择导航用的 Profile。`:SpringProfiles` 查看当前选择，`:SpringProfiles!` 恢复 `SPRING_PROFILES_ACTIVE` 或 Spring 的 `default`。支持字符串 `@Profile` 及 `!`、`&`、`|` 组合。Profile 在当前 Neovim 会话生效。
- 程序化配置支持类字面量 `@Import`、Spring 回调里的固定名称 `registerSingleton` 和 `registerBeanDefinition`，以及同一方法内可追踪的独立 Spring 容器的 `registerBean`、`registerAlias` 和 `getBean`。动态 Bean 名、外部配置值及需执行分支或自定义工厂才能确定的目标仍需运行时信息。

本机依赖 [Spring Boot Tools](https://marketplace.visualstudio.com/items?itemName=vmware.vscode-spring-boot) 2.4.1。下载对应 VSIX 后，将包内 `extension/language-server/` 的内容（含 `lib/`）放到 `stdpath('data') .. '/spring-tools/2.4.1'`，默认路径为 `~/.local/share/nvim/spring-tools/2.4.1/`。首次 Bean 查询需等待各模块完成索引。

#### 1.2 搜索体系

| 快捷键 | 用途 | 实现方式 |
|--------|------|----------|
| `<Leader>f` | 搜项目符号或文件 | `scope:!test` 后已预留空格，可直接输入。删除该筛选词可在本次搜索中包含测试路径 |
| `<Leader>F` | 全文内容搜索 | live grep |
| `<Leader>ha` | Spring HTTP 接口 | 扫描 `@Mapping` 注解 |
| `<Leader>e` | 最近文件 | - |
| `<Leader>s` | 可搜索的文件结构 | Aerial 数据 + Snacks Picker |

#### 1.3 方法级跳转（Treesitter）

| 快捷键 | 功能 | IDEA 对应 |
|--------|------|-----------|
| `J` | 跳到下一个方法 | `Ctrl+Down` |
| `K` | 方法内先跳到当前方法名；在声明行或方法外跳到上一处声明 | `Ctrl+Up` |
| `f` | AceJump 字符跳转 | AceJump |
| `F` | AceJump Treesitter 选择 | - |

`gn` 跳到配对括号。Visual 模式下保留选区起点，将选区扩展到配对位置，支持字符、行和块选择。

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

### 4. Git 集成

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
| `Ctrl+d` / `Ctrl+f` | Diff/合并视图统一下一/上一变更（包括已处理块），不自动切文件 |
| `,w` | 最大化当前拆分窗口，再按恢复 |
| `,gh` / `,gH` | CodeDiff 文件/项目历史 |

合并视图直接按 `m` 打开英文菜单，无需 `,g` 前缀。`ml/mr/ma/mu` 分别接受左侧、右侧、双方和还原祖先；`mz/mZ` 撤销/重做，`mf` 保存当前文件并暂存为已解决，再回该文件普通 Diff。未解决块或残留冲突标记会阻止完成。

安装固定版本、完整键位、来源标记及安全边界见 [Git 审查与合并指南](docs/git-review-guide.md)。

### 5. LSP 功能

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

### 6. 窗口与工具

| 快捷键 | 功能 |
|--------|------|
| `gh/gj/gk/gl` | 窗口导航 |
| `sV` / `sv` | 水平/垂直分割 |
| `sl` / `sh` | 下一个/上一个窗口 |
| `sw` | 在新窗口打开定义 |
| `sq` | 关闭窗口 |
| `<Leader>w` | 最大化当前拆分/恢复原布局 |
| `<Leader><Arrow>` | 调整窗口大小 |
| `gw` | 在同一 Neovide 应用中新建项目窗口并打开所选项目的最近文件 |
| `<Leader>p` | 打开项目目录树并定位当前文件 |
| `<Leader>P` | 定位当前文件 |
| `st` | 打开终端 |

### 7. 书签与跳转记录

使用 Vim 原生 marks：`mA` 设置文件标记，`'A` 返回标记行；`Ctrl+o` / `Ctrl+i` 访问跳转记录。已移除失效的 vim-bookmarks/Harpoon 配置，不再声明 `mm`、`gm`、`gM` 为插件书签键。三方合并中的 `ma` 保持 Accept Both。

### 8. 折叠

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

【Git】
  <Leader>gd  Git diff
  gp   预览 hunk
  <C-d>/<C-f>  hunk 跳转

【窗口】
  gh/j/k/l  窗口导航
  <Leader>w  最大化当前拆分/恢复布局
  gw   切换项目（同一应用中的新窗口）
  <Leader>p  项目文件树
```

Neovide 的启动、Command 快捷键、字体和窗口设置见 [Neovide 使用指南](docs/neovide.md)。`H` / `L` 在普通和可视模式下分别移动到当前视觉行的首个非空字符和行尾。

---

## 语言支持

### Java

- **LSP**: Lathe 提供 Java 语言服务，Spring Tools 复用其工程模型提供 Bean 索引
- **格式化**: google-java-format
- **特色功能**: Maven 分析模型、Lombok 支持、多模块导航。`,ha` 静态搜索 Spring HTTP 注解


[详细 Java 开发指南 →](./docs/java-dev-guide.md)

### Python

- **LSP**: pyright
- **格式化**: black + isort + ruff

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

### Lathe 参数

资源与 JVM 参数位于 [lua/user/lathe_config.lua](lua/user/lathe_config.lua)，唯一 Java 接入位于 `lua/user/plugins/java.lua`。不再保留后端切换入口。

### Maven 自动准备与实时审查

| 时机 | 行为 |
|------|------|
| 首次打开目录或 Java 文件 | 从最近的 POM 向上确认真实聚合关系，识别多模块工程并后台准备模型 |
| 再次打开同一工程 | 复用已有模型和缓存，不因重新打开而重跑 Maven |
| 外部工具修改源码 | LSP 的源码根指向原工程；可见且未编辑的缓冲区自动重载，未保存编辑保持不动 |
| 编辑器内修改 Java | 通过 LSP 发送未保存内容，不要求先保存到构建副本 |
| POM、构建配置或已解析依赖变化 | 自动在后台更新独立模型；失败保留上一份可用模型 |
| 同时打开多个工程 | 按规范化工程根路径区分客户端、构建目录和缓存，避免同名类跨工程串跳 |

首次准备会离线运行 Maven 并编译主源码，耗时取决于项目规模。准备命令跳过测试编译和执行。缺少本地依赖时请查看 `:LatheLog`。遇到源码符号解析错误时，Lathe 会尝试继续捕获导航所需的编译参数。若有模块仍被 Maven 阻断，只发布本次成功捕获的模块，状态栏显示「部分索引，Maven 有错误」。

### JDK 与 Lombok

| 部分 | 使用方式 |
|------|----------|
| Lathe 运行时 | JDK 21，默认 JVM 参数 `-Xms256m -Xmx3g` |
| 独立构建副本 | Java 8 工程用 JDK 8；缺少 JavaFX 时选用本机带 JavaFX 的 JDK 8。遇到更高版本的字节码时改用 JDK 21，沿用 Maven 的编译版本 |
| Maven 兼容 | 按捕获日志在独立副本中修正过旧的编译插件、Java 8 启动类路径和 Git 元数据插件配置 |
| 编辑器分析模型 | 使用捕获的 Java 版本。分析用 Lombok 最低为 1.18.38，保留生成方法关联所需的注解标记。原项目继续使用自己的版本 |
| 原工程 | 不写入 `.lathe`、构建输出或 POM；不自动 `git add` |

### 安装资源与缓存

本机安装资源由 `lathe_config.lua` 的 `resources` 指定，目前位于 `~/.codex/experiments/lathe-java8-20261116-side`，需保留其中的 `lathe.nvim-0.3.1`、`extension-classpath.txt` 和 `vim-trial/m2`。这些资源不包含在配置提交中。准备脚本使用的 Maven 和 JDK 路径见 `scripts/lathe-model.py`，自动模型准备适用于 Maven 工程。

| 数据 | 默认位置 |
|------|----------|
| 每工程状态、日志、模型和索引缓存 | `~/.local/state/nvim/lathe/projects/<工程路径哈希>/` |
| Git 工程的独立构建 worktree | `~/.codex/worktrees/lathe-<工程路径哈希>/<仓库名>/` |
| 非 Git 工程的构建副本 | 对应状态目录下的 `build/` |
| 独立 Maven 制品缓存 | `resources` 下的 `vim-trial/m2/`，多个工程复用；原 `~/.m2` 只读取 |

后台准备退出时只收尾本次任务的子进程；已完成的模型和缓存保留供下次复用。

### 本机依赖覆盖

在对应工程的 Lathe 状态目录创建 `dependency-overrides.json`。以下是虚构示例，`pom` 是相对于 Git 工作区根目录的路径。

```json
[
  {
    "pom": "example-client/pom.xml",
    "groupId": "org.example",
    "artifactId": "example-sdk",
    "from": "1.0.0",
    "to": "1.1.0"
  }
]
```

Lathe 只替换独立构建副本里版本恰好匹配 `from` 的直接依赖。`to` 需要已在本机 Maven 缓存中，覆盖模块仍执行 Maven 校验并要求编译成功。修改后可以用 `,lr` 刷新。状态栏提示「分析依赖覆盖」，`:LatheLog` 记录实际应用的替换。

### 状态与维护入口

| 入口 | Lathe |
|---|---|
| 状态栏 | 准备和连接状态、Java 版本、部分索引提示和本机依赖覆盖提示 |
| `,lr` | 刷新当前工程模型，首次准备失败后可重试 |
| `,lR` | 在独立构建副本 clean 后重新准备 |
| `:LatheLog` | 准备日志 |
| `:LatheSync` | 手动刷新 |

索引没有跨语言统一的 LSP 重建协议；上述模型维护动作针对 Lathe。通用导航、引用、重构和补全映射统一定义在 `lsp/handlers.lua`、`plugins/search.lua` 与 `cmp.lua`，不在语言服务配置中重复绑定。

### 本轮验证（2026-11-16）

已验证目录自动准备、多模块和嵌套工程识别、两个工程同名符号的跳转隔离、缓存复用、POM 自动刷新、缺依赖后的重试、Java 8 API 限制、退出时进程收尾，以及真实工程的 `gd` 和 `,f` 源码预览。核对过原工程 POM、Git 状态及暂存区，保持不变；没有运行业务回归测试。

### 独立安装与语言服务管理

本配置已移除 Mason 和后端切换逻辑。其他语言服务放在 `~/.local/share/nvim/language-tools/`，由 `lua/user/lsp/servers.lua` 通过原生 `vim.lsp.config` / `vim.lsp.enable` 按文件类型启动。安装、更新、版本固定和添加服务见 [语言工具安装](docs/language-tools.md)。

`,ha` 静态搜索 Spring HTTP 路径。Bean 定义和注入关系通过 `gd`、`gr` 查询，支持范围见[代码导航](#11-定义与引用)。

---

## 故障排除

### 通用检查清单

```vim
:checkhealth          " 环境健康检查
:LspInfo             " LSP 客户端状态
:LspLog              " LSP 日志
:Lazy                " 插件管理
```

### 常见问题

**Q: Lathe 提示准备失败**
- 执行 `:LatheLog`，核对 Maven 缺依赖、编译错误及本机资源路径。
- 在原工程按正常研发流程准备缺失依赖；分析任务保持离线，不自动修改原 POM。
- 保存 POM 或补齐已监测的本地依赖后自动重试，也可打开 Java 文件后按 `,lr`。
- 第一次准备尚未完成时，符号搜索可以使用，语义跳转需等待模型和服务就绪。

**Q: `gd` 跳转没反应**
- 先在 `:LspInfo` 确认当前 Java 缓冲区连接的是 Lathe。
- 检查模型准备状态和 `:LatheLog`。

**Q: 格式化不生效**
- 确认工具在 PATH 中可执行，或按独立工具安装说明安装
- 手动触发: `=`
- 检查 conform 配置: `:ConformInfo`

**Q: 补全不工作**
- 确认 LSP 已连接: `:LspInfo`
- 检查 cmp 状态: `:CmpStatus`

### 更新维护

```vim
:Lazy update          " 更新插件
:TSUpdate             " 更新 Treesitter 解析器
```

---

## 自定义

### 添加新 LSP 服务器

编辑 `lua/user/lsp/servers.lua`，安装工具后填写其独立目录的绝对启动路径；沿用 `handlers.on_attach` 与 `handlers.capabilities`：

```lua
vim.lsp.config("myserver", {
  cmd = { "/path/to/myserver", "--stdio" },
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
- [Lathe Neovim 文档](https://github.com/ag-libs/lathe/blob/main/docs/guide/editors/neovim.md)
- [Snacks 文档](https://github.com/folke/snacks.nvim/tree/v2.31.0/docs)
