# 当前 Vim / Neovim 全量盘点

核对日期：2026年11月17日。依据本轮重新读取的配置、隔离Neovim注册结果、磁盘目录和PATH。只把当前注册的组件算作正式插件，不把缓存、依赖包、已卸载副本或历史会话混入数量。

## 最终数量

| 项目 | 当前结果 |
|---|---|
| 正式注册插件 | **30项，逐项见下表** |
| 插件安装位置 | lazy目录29项 + 独立Lathe客户端1项；与30个注册项一一对应 |
| 最小启动观察 | 未打开业务文件；VeryLazy后10项已加载，其余按触发条件加载；没有启动语言服务 |
| Neovim自有配置/脚本/文档 | **46个文件**，全部列出 |
| 语言服务配置 | Java Lathe 1个 + 非Java 7个；不代表8个服务常驻 |
| 非Java安装资源 | 5个独立npm前缀；直接依赖版本逐项列出 |
| 用户安装Treesitter解析器 | 当前runtime可发现19份 |
| Neovim内置解析器 | 7份；与用户解析器有重名，不直接相加成26种 |
| 已执行清理 | 44份旧Packer插件副本 + 4个Snacks已替代包 + 3个失效映射 + 旧服务/工具残留 |

本轮不卸载系统共享命令，不删除用户会话文件，不结束用户当前Neovim或改动其未保存buffer。旧进程不会因为删除磁盘包自动变成新配置；保存需要的修改后退出并重新打开。

## 30个正式保留插件

加载列记录配置触发条件；未触发/尚未加载不等于无用。所有30项在本机目录均存在，当前不再安装第二套同职责前端。

| 类别 | 插件 | 用途 | 保留依据 | 加载条件 |
|---|---|---|---|---|
| 管理与依赖 | `lazy.nvim` | 插件注册、按需加载、锁版本 | 基础设施 | 启动 |
| 管理与依赖 | `plenary.nvim` | todo-comments搜索实际使用的Job等Lua工具 | 配套依赖 | 被使用时 |
| 语言服务 | `lathe.nvim` | 唯一Java客户端：模型准备、语义索引、跳转和诊断 | Java核心 | Java文件/Lathe命令 |
| Git | `codediff.nvim` | 分支完整Diff、历史、三方合并 | 审查核心 | Git快捷键/CodeDiff命令 |
| Git | `gitsigns.nvim` | 普通源码行标记、块恢复/暂存、blame | 源码行级Git，与CodeDiff分工不同 | BufReadPre/BufNewFile |
| 搜索与导航 | `snacks.nvim` | Picker、项目树、终端、保布局buffer关闭 | 统一工具界面 | 启动；功能模块按需 |
| 搜索与导航 | `aerial.nvim` | 当前文件常驻结构大纲 | 持久大纲 | `,s`/Aerial命令 |
| 搜索与导航 | `lspsaga.nvim` | 递归调用树及Enter后保留窗口 | 唯一调用链UI | LspAttach |
| 搜索与导航 | `flash.nvim` | f/F标签定位与Treesitter定位 | 保留既有快速导航 | VeryLazy/定位键 |
| 窗口与提示 | `bufferline.nvim` | 可点击buffer标签、排序和关闭 | 多文件审查导航 | VeryLazy |
| 窗口与提示 | `lualine.nvim` | Git、诊断、Lathe准备/就绪与位置状态 | 状态反馈 | VeryLazy |
| 窗口与提示 | `which-key.nvim` | 精简主菜单与合并m上下文提示 | 快捷键提示 | VeryLazy |
| 补全与片段 | `nvim-cmp` | 统一补全菜单和选择/确认 | 补全核心 | InsertEnter |
| 补全与片段 | `cmp-nvim-lsp` | LSP补全数据源和capabilities | 配套依赖 | 公共LSP配置加载时已require |
| 补全与片段 | `cmp-buffer` | 当前buffer词汇补全 | 配套数据源 | nvim-cmp依赖 |
| 补全与片段 | `cmp-path` | 路径补全 | 配套数据源 | nvim-cmp依赖 |
| 补全与片段 | `cmp_luasnip` | 片段进入补全列表的桥接 | 配套依赖 | nvim-cmp依赖 |
| 补全与片段 | `LuaSnip` | 展开和跳转代码片段；处理LSP snippet | 片段引擎 | nvim-cmp依赖 |
| 补全与片段 | `friendly-snippets` | 多语言片段数据 | 片段库 | nvim-cmp依赖，片段按需加载 |
| 语法与编辑 | `nvim-treesitter` | 解析器管理；原生高亮/语法结构接入 | 语法基础 | BufReadPost/BufNewFile |
| 语法与编辑 | `nvim-treesitter-textobjects` | J/K方法导航；函数、类、参数文本对象 | 保留原编辑/导航 | BufReadPost/BufNewFile |
| 语法与编辑 | `Comment.nvim` | gc行注释、gb块注释及额外动作 | 保留行/块注释 | gc/gb按键 |
| 语法与编辑 | `nvim-ts-context-commentstring` | JSX/TSX等混合语境选择注释格式 | Comment pre_hook配套 | 注释hook require时 |
| 语法与编辑 | `nvim-ts-autotag` | HTML/JSX/Vue标签自动闭合和同步改名 | 标签编辑增强 | BufReadPost/BufNewFile |
| 语法与编辑 | `nvim-autopairs` | 括号/引号配对，与补全联动 | 编辑增强 | InsertEnter |
| 语法与编辑 | `conform.nvim` | 唯一手动格式化入口，按文件类型调用工具 | 格式化编排 | VeryLazy |
| 语法与编辑 | `todo-comments.nvim` | TODO/FIXME/BUG等醒目标记 | 审查增强 | BufReadPost/BufNewFile |
| 主题与图标 | `catppuccin` | 唯一Mocha主题、语义颜色与未使用符号灰色 | 统一外观 | 启动 |
| 主题与图标 | `transparent.nvim` | 透明背景插件及现有手动开关 | 保留当前透明外观能力 | VeryLazy |
| 主题与图标 | `nvim-web-devicons` | Picker、结构树、标签等共享图标 | 配套依赖 | 消费者require/依赖触发 |

27个普通插件由lazy-lock.json锁定commit。三个本地dir组件：**Snacks v2.31.0、CodeDiff 4.0.8、Lathe客户端0.3.1**；它们不在lazy-lock中，不能假装运行Lazy就能从空机器自动恢复完整环境。

## 46个配置、脚本与文档

以下路径相对 `~/.config/nvim`（软链接到 `~/.vim/.config/nvim`）。不是46个额外插件；其中包含模块拆分和使用文档。

| 文件 | 职责 |
|---|---|
| `.gitignore` | 排除日志、缓存等生成内容 |
| `README.md` | 安装、使用与键位总说明 |
| `docs/config-inventory.md` | 本报告：当前全量清单和实际删除记录 |
| `docs/git-review-guide.md` | 审查、冲突、撤销与完成合并操作 |
| `docs/java-dev-guide.md` | Java能力、使用及未使用诊断范围 |
| `docs/language-tools.md` | 语言服务独立安装与统一键位 |
| `docs/navigation-ui-minimum.md` | 整合架构、能力边界与迁移验收 |
| `init.vim` | 唯一Neovim入口，加载lua/init.lua |
| `lazy-lock.json` | 27个普通插件的固定commit；三个本地dir组件另锁版本 |
| `lua/init.lua` | 加载基础配置、lazy、原生项目根、其他语言LSP和Lathe生命周期 |
| `lua/user/autocommands.lua` | 外部改动checktime、K方法导航保护及willSaveWaitUntil保护 |
| `lua/user/autopairs.lua` | 括号与补全联动 |
| `lua/user/bufferline.lua` | 标签、排序与保布局关闭 |
| `lua/user/cmp.lua` | 统一补全数据源、菜单与片段键位 |
| `lua/user/codediff_merge_controls.lua` | 块旁箭头、合并键位和撤销/重做边界 |
| `lua/user/codediff_merge_finish.lua` | 检查剩余冲突、保存、精确暂存和返回审查 |
| `lua/user/codediff_merge_presentation.lua` | 来源标记、配色和有界记录 |
| `lua/user/codediff_review.lua` | 分支基准、目录状态、单文件审查与会话键位 |
| `lua/user/colorschemes/catppuccin.lua` | 唯一主题与DiagnosticUnnecessary灰色 |
| `lua/user/comment.lua` | 行/块注释与混合语境pre_hook |
| `lua/user/gitsigns.lua` | 普通源码行级Git样式与行为 |
| `lua/user/keymaps.lua` | 跨功能全局键位和窗口最大化/恢复；本轮移除3个失效书签映射 |
| `lua/user/lathe_config.lua` | Lathe资源、状态、Python、JDK路径和JVM内存参数 |
| `lua/user/lathe_live.lua` | 项目识别、准备、实时源码和Java服务生命周期 |
| `lua/user/lsp/conform.lua` | 格式化工具与文件类型对应规则 |
| `lua/user/lsp/handlers.lua` | 共享LSP键位、异步gd、位置编码和过期结果保护 |
| `lua/user/lsp/servers.lua` | 7个非Java服务的命令、文件类型和公共attach |
| `lua/user/lspsaga_patch.lua` | 调用树Enter跳转后保留窗口的定制适配 |
| `lua/user/lualine.lua` | 文件、Git、问题和Lathe状态 |
| `lua/user/navigation.lua` | 跨语言统一Picker；Java磁盘声明、引用/实现和二级搜索别名 |
| `lua/user/options.lua` | 编辑、缩进、撤销、自动读盘和显示选项 |
| `lua/user/plugins/editing.lua` | Treesitter、文本对象、Flash和标签编辑 |
| `lua/user/plugins/git.lua` | CodeDiff本地包与Git入口声明 |
| `lua/user/plugins/init.lua` | 插件声明汇总 |
| `lua/user/plugins/java.lua` | 唯一Lathe客户端接入，不再切换后端 |
| `lua/user/plugins/lsp.lua` | 补全、片段依赖和格式化声明 |
| `lua/user/plugins/search.lua` | Aerial/Saga声明 |
| `lua/user/plugins/spring.lua` | 静态HTTP注解扫描及源码预览 |
| `lua/user/plugins/ui.lua` | 工具、窗口、主题和共享依赖声明 |
| `lua/user/project.lua` | 原生项目根/cwd定位与虚拟buffer排除 |
| `lua/user/snacks.lua` | Picker、项目树、终端会话和工具界面 |
| `lua/user/todo-comments.lua` | TODO/FIXME等高亮规则 |
| `lua/user/transparency.lua` | 透明组与Neovide显示配置；由transparent插件配置加载 |
| `lua/user/vim-compat.lua` | Java/Rust/Lua、Markdown等buffer-local编辑映射 |
| `lua/user/whichkey.lua` | 最新工作流提示、隐藏重复别名 |
| `scripts/lathe-model.py` | 独立Maven Java 8模型、源码同步、路径与自有进程保护 |

自有实现中维护成本最高的两块是：Java模型/实时源码桥接，以及CodeDiff分支/合并体验适配。它们是本机自定义代码，不能把其全部效果说成上游插件开箱即用。Snacks/Aerial/Saga/Flash等则提供通用UI和数据展示基础。

## 语言服务与安装资源

| 服务 | 语言/功能 | 安装与状态 |
|---|---|---|
| Lathe 0.3.1 | Java/Maven语义、Lombok相关跳转和诊断 | 唯一Java后端；Java文件按需准备模型 |
| pyright | Python索引/诊断/补全 | 已配置；独立可执行入口存在 |
| ts_ls | JS/TS/React | 已配置；独立可执行入口存在 |
| vue_ls | Vue | 已配置；独立可执行入口存在 |
| eslint | JS/TS/Vue问题检查 | 已配置；是否产生有效结果取决于项目ESLint配置 |
| cssls | CSS/SCSS/Less | 已配置；独立可执行入口存在 |
| html | HTML | 已配置；独立可执行入口存在 |
| emmet_ls | 标签/样式缩写能力 | 已配置；独立可执行入口存在 |

所有服务复用公共LSP键位与补全。Rust/Go/Lua/JSON等保留语法高亮、搜索及相应格式化定义，不因此声称已经启用对应语义LSP。

| `language-tools/`前缀 | 实际直接依赖版本 |
|---|---|
| `web` | `vscode-langservers-extracted@4.10.0` |
| `typescript` | `typescript@6.0.3`、`typescript-language-server@5.3.0` |
| `vue` | `@vue/language-server@3.3.5`、`@vue/typescript-plugin@3.3.5`、`typescript@6.0.3` |
| `emmet` | `emmet-ls@0.4.2` |
| `pyright` | `pyright@1.1.408` |

Lathe另依赖：指定Python、JDK21运行时、JDK8项目编译器、Maven和本地资源/依赖缓存；JVM配置为`-Xms256m -Xmx3g`，不是声称进程始终只占256MiB。资源仍在本机Lathe实验目录中，跨机器迁移需要准备完整资源。此轮没有重建公司项目索引或重新进行冷启动/内存基准。

## 外部命令与格式化

| 命令/资源 | 核对结果 | 用途与结论 |
|---|---|---|
| `nvim` | PATH可见 | 编辑器 |
| `git` | PATH可见 | 分支、Diff和合并数据 |
| `rg` | PATH可见 | Java/HTTP声明扫描与全文搜索 |
| `fd` | PATH可见 | 文件搜索 |
| `fzf` | PATH可见 | 本机共享工具；当前Neovim已不依赖fzf-lua，不能再当作Snacks依赖 |
| `node` | PATH可见 | 非Java语言服务 |
| `npm` | PATH可见 | 手工维护独立工具，不由编辑器自动升级 |
| `python3` | PATH可见 | Java模型辅助脚本及独立工具 |
| `mvn` | PATH可见 | Lathe模型准备及显式构建入口 |
| `java` | PATH可见 | 当前shell为Java 8；Lathe使用单独指定的Java 21 |
| `black` | PATH可见 | Python格式化链 |
| `isort` | PATH可见 | Python导入排序链 |
| `ruff` | PATH可见 | Python格式化链中的ruff_format |
| `google-java-format` | **当前PATH未找到** | Java格式化定义 |
| `stylua` | **当前PATH未找到** | Lua格式化定义 |
| `jq` | PATH可见 | JSON格式化；不能直接处理带注释JSONC |
| `yamlfmt` | **当前PATH未找到** | YAML格式化定义 |
| `prettier` | **当前PATH未找到** | 前端格式化定义 |
| `lazygit` | PATH可见 | 保留独立终端GUI入口 |
| `yazi` | PATH可见 | 独立终端工具；当前Neovim没有接入Yazi插件 |

存在格式化定义不等于命令已安装。google-java-format/stylua/yamlfmt/prettier四项当前PATH缺失，本轮没有逐项目检查node_modules等本地工具；不据此断言所有项目绝对不可用。Python当前black→isort→ruff_format存在重叠，JSONC→jq有能力缺口；此次清理没有擅自改变格式化输出。

## Treesitter全量清单

正式用户解析器（19份）：`bash`、`css`、`dtd`、`go`、`html`、`java`、`javascript`、`json`、`lua`、`markdown`、`markdown_inline`、`python`、`rust`、`toml`、`tsx`、`typescript`、`vue`、`xml`、`yaml`。

Neovim自带（7份）：`c`、`lua`、`markdown`、`markdown_inline`、`query`、`vim`、`vimdoc`。重名时按runtime顺序解析，不解释为7种额外配置。

旧Packer内的11份解析器（含仅旧副本存在的regex）已随旧Packer目录删除。此前“磁盘20种”包含旧副本，不能称为当前20种生效解析器。

## 本轮已直接删除的所有残留

### 44份旧Packer副本

`~/.local/share/nvim/site/pack/packer/opt/start/`中的下列44项全部删除，空的Packer/pack父目录一并清理。它们原本未加入新配置或旧用户会话的runtime。

| 旧副本 | 结论 |
|---|---|
| `Comment.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `FixCursorHold.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `LuaSnip` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `alpha-nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `bufferline.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `cmp-buffer` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `cmp-cmdline` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `cmp-nvim-lsp` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `cmp-path` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `cmp_luasnip` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `conform.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `darkplus.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `friendly-snippets` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `gitsigns.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `gruvbox` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `impatient.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `indent-blankline.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `lsp_signature.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `lualine.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `mason-lspconfig.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `mason.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `monokai.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `nlsp-settings.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `nvim-autopairs` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `nvim-cmp` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `nvim-lspconfig` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `nvim-tree.lua` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `nvim-treesitter` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `nvim-ts-context-commentstring` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `nvim-web-devicons` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `packer.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `plenary.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `popup.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `project.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `rust.vim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `telescope-live-grep-raw.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `telescope-ui-select.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `telescope-vim-bookmarks.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `telescope.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `todo-comments.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `toggleterm.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `vim-bbye` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `vim-bookmarks` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |
| `which-key.nvim` | 已删除旧副本；同名正式插件如保留，仅来自上表安装位置 |

### 其他已删除项

| 路径/入口 | 原因 |
|---|---|
| `lazy/fzf-lua` | 已被Snacks Picker替代 |
| `lazy/nvim-tree.lua` | 已被Snacks Explorer替代 |
| `lazy/toggleterm.nvim` | 已被Snacks Terminal替代 |
| `lazy/vim-bbye` | 已被Snacks.bufdelete替代 |
| `lsp_servers/` | 旧Python服务安装；当前使用独立pyright前缀 |
| `neotest-java/` | 测试插件已移除，目录为空 |
| `project_nvim/` | 旧project.nvim历史；当前使用原生根定位 |
| `telescope_history` | Telescope已移除的历史缓存 |
| `rplugin.vim` | 只有空插件分类注释，无注册项 |
| `tree-sitter-markdown.tar.gz` | 旧下载包，现行解析器已独立安装 |
| 数据根`.DS_Store` | Finder元数据 |
| `mm` / `gm` / `gM` | 原BookmarkToggle/Next/Prev命令不存在，删除全局失效映射 |

这些路径均相对`~/.local/share/nvim`，键位除外。未卸载系统fzf、Yazi、Python/Node/Java等其他应用也会使用的工具。保留Neovim sessions与当前Snacks历史数据，不把用户会话或当前工具状态当作无用插件。

## 编辑器外的7个保留入口

| 文件 | 职责 |
|---|---|
| `~/.vim/.ideavimrc` | IDEA独立Vim键位及插件标志；当前软链接有效 |
| `~/.vim/.obsidian.vimrc` | Obsidian独立jk退出映射；软链接有效 |
| `~/.vim/.luarc.json` | Lua工作区诊断设置，不等于安装Lua LS |
| `~/.vim/deploy.sh` | 多应用软链接部署 |
| `~/.vim/one-step-install.sh` | 多工具安装入口；本轮未执行 |
| `~/.vim/mac-setup.sh` | 系统/多应用环境配置；本轮未执行 |
| `~/.vim/SYMLINK_SETUP.md` | 软链接说明 |

IdeaVim里的NERDTree/argtextobj/commentary/highlightedyank/surround和Ace动作属于IDEA入口；不随旧Neovim磁盘副本一起删除。系统安装脚本与其他应用目录不冒充Neovim的46个文件。

## 当前功能边界与验证

- Java`,f`仍是磁盘类型/方法扫描，未增加字段和未保存声明索引。HTTP搜索仍是静态注解扫描。
- 原生Unnecessary置灰仅覆盖Lathe确认的符号范围，public方法不因此获得IDEA全项目未使用分析。
- CodeDiff提供基础Diff/合并；来源配色、块旁箭头、部分目录/菜单/完成流程来自自有适配。
- 当前30项维持已有功能；未触发插件和必要依赖不以“看起来没加载”为由删掉。此轮没有证明其为理论最小数量或全网最快方案。

本轮重新启动隔离Neovim确认30项全部存在、启动无错误；删除后重跑17项模块/键位检查与受影响的Picker/窗口/终端/Git回归。真实语言服务的索引准确性、业务工程测试与内存性能不在本轮重跑范围。

本次清理的回退归档保留在本地，不属于配置仓库。

机器可读注册、磁盘和清理证据：`~/.codex/experiments/nvim-current-inventory-20261117/`。配置未热重载到现有用户进程；请保存编辑内容后退出重开。
