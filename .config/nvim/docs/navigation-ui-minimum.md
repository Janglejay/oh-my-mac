# 导航与界面最小集

更新日期：2026年11月17日。配置面向审查、导航、编辑与合并；注册插件从初始54项依次降到44、39、33，本次整合后为 **30项**。数量减少不代表相同幅度的CPU、内存或Java索引提速，本轮没有做性能排名。

## 当前架构

导航/窗口层保留七个组件：**Snacks + Aerial + Saga + Flash + Bufferline + Lualine + Which-key**。图标、主题、Git、补全和语言服务不计入这七项。

| 组件 | 必要职责 | 本轮决定 |
|---|---|---|
| Snacks v2.31.0 | 统一搜索Picker、项目树、终端和保布局buffer关闭 | 替换fzf-lua、nvim-tree、toggleterm、vim-bbye |
| Aerial | 当前文件常驻结构大纲 | 保留，避免把持久大纲降为临时Picker |
| Saga | 可递归展开的调用链及Enter跳转后保留窗口 | 保留唯一树形调用UI；Snacks单层调用列表不等价 |
| Flash | f/F标签定位与Treesitter定位 | 保留 |
| Bufferline | 可点击标签、现有排序/分组和关闭 | 保留，不用简化原生tabline取代 |
| Lualine | 分支、问题、Lathe状态、文件位置 | 保留 |
| Which-key | 主菜单和合并上下文菜单 | 精简提示，实际操作由各模块持有 |

Snacks使用固定公开发行包commit `e6fd58c82f2f3fcddd3fe81703d47d6d48fc7b9f`，安装说明见[README](../README.md#snacks-整合与迁移)。由本地dir加载，没有新增Git remote。只启用picker、explorer、terminal；buffer删除按需调用。Dashboard、GitHub集成、滚动动画、通知接管等可选模块没有启用。

四个旧插件已从新配置、lazy-lock和安装目录删除；两份旧tree/terminal配置也已删除。本轮又清除44份旧Packer副本、旧Python服务和旧工具缓存；清单见[全量盘点](config-inventory.md)。当前用户旧进程保留，需保存后重开。

## 快捷键和模块

| 功能 | 现有入口 | 当前实现 |
|---|---|---|
| 项目类/方法、全文、最近文件、buffer | `,f / ,F / ,e / ,b` | `user/navigation.lua`统一Snacks Picker，真实源码预览 |
| 定义、引用、实现 | `gd / gr / gi / qi` | 公共LSP绑定，后端更换不需重配键位；Ctrl+o返回Diff原列 |
| 当前文件大纲、调用树 | `,s / gR` | Aerial / Saga，保留原行为 |
| 项目树切换/定位 | `gw / ,p / ,P` | Snacks Explorer，跟随文件、Git/诊断、文件监控；目录Enter折叠，h/l不折叠 |
| 底部终端 | `st / Ctrl+反斜杠` | 保留会话和尺寸；Esc/jk退出终端输入，Ctrl+h/j/k/l切窗口 |
| 关闭buffer | `,c / ,C`、标签关闭 | Snacks.bufdelete保留拆分；未保存会询问，标签关闭也不强制丢弃 |
| 当前窗口最大化/原布局恢复 | `,w` | 保留原实现，包括三列Diff |
| 分支审查、切换对比基准、历史 | `,gd / ,gB / ,gh / ,gH` | 保留CodeDiff；`,gb`仍是Checkout分支，不能与`,gB`混淆 |
| 合并与冲突 | `ml / mr / ma / mu`、`Ctrl+d / Ctrl+f`、`mf` | CodeDiff现有安全流程，块旁箭头可点击、支持撤销/重做 |
| HTTP接口 | `,ha` | 保留Spring静态注解扫描，统一Picker和源码预览 |

`user/snacks.lua`集中维护工具界面；`plugins/search.lua`只保留Aerial/Saga。公共LSP的请求取消、30秒gd超时、窗口/光标/changedtick过期检查、位置编码和保存前格式化保护均保留。

## Which-key精简

主菜单保留搜索、文件操作、Git、Java、HTTP、Problems及主要重构入口。主提示不再列出原生g/z/窗口/动作词表。重复的`,P`、`,S*`和次要`,l*`快捷键仍存在，只隐藏重复提示；失效的LSP Info说明不再显示。

Which-key不再重新绑定`,F`等模块拥有的命令，避免覆盖正确的项目根与搜索实现。合并m菜单仍仅在CodeDiff合并buffer接管，不在普通源码抢占Vim mark操作。所有合并/目录说明继续使用当前IDEA风格英文。

## 明确保留的边界

- Java `,f`仍扫描已保存源码中的类型/方法。没有在本轮增加字段索引或未保存声明覆盖；原来没有的能力不算迁移完成。非Java仍走当前语言服务的workspace symbols，无服务时退回文件搜索。
- Java声明和HTTP注解扫描仍同步收集，Snacks品牌本身不会消除大仓扫描成本。要优化需另做可取消/增量数据源，不凭仓库数量断言更快。
- 项目树Git标记是本地工作区状态。整个分支相对所选基准、含已提交/暂存/未暂存/新增/删除，仍用CodeDiff审查树。
- 置灰只显示语言服务确认的Unnecessary范围。真实Lathe验证private方法收到诊断、public方法不收到，不等价于IDEA全项目public未使用声明检查。详见[Java指南](java-dev-guide.md#未使用代码置灰)。

## 其他精简决定

测试/调试插件与入口已全部移除，不恢复。project.nvim由`user/project.lua`的原生项目根定位替代，保留最近标记、worktree和虚拟buffer排除策略。

Comment.nvim和nvim-ts-context-commentstring继续保留：按需加载不等于无用。此前Java行/块注释和TSX文本上下文的四项对照验证有效；Neovim 0.12原生gc已有Treesitter上下文感知，但不等价于现有gc/gb及额外动作。mini.comment/mini.statusline/mini.tabline没有在本机相同任务下证明更快，不再叠装另一套候选。

## 增量验收

本轮证据在 `~/.codex/experiments/nvim-snacks-20261117/`，全部使用本地合成工程与任务专属Neovim：

- 17项启动/模块检查：30个注册插件、共享语言键位、保留模块，以及测试/调试后端不再加载。
- 8项Picker/窗口/终端/诊断交互：真实源码与Enter定位、带空格路径全文搜索、项目树配置、保布局删除/取消未保存关闭、窗口恢复、同一终端进程与尺寸、Which-key、Unnecessary到灰色extmark。
- CodeDiff完整分支回归：新增/修改/删除目录状态、单文件完整上下文、Ctrl+d/Ctrl+f、窗口恢复及watch刷新。旧Diffview回退已按前轮决定移除，不执行旧回退断言。
- 合并回归：真实鼠标箭头、空白处不操作、ml/mr/ma/mu、撤销/重做、未完成时不暂存、完成后保存并精确标记已解决。修复了原状态列按行改变点击处理器的问题；固定处理器，保留所有位置、版本、目标块与内容校验。
- 真实Lathe 0.3.1对未保存private/public方法的未使用诊断对照；退出后恢复buffer，未写入业务工程。

已有7个独立语言服务初始化、项目根与注释检查的输入未改变，复用前轮结果，不称为本轮重跑。未热重载用户会话、未运行公司工程构建或测试、未重测索引和内存。退出并重开Neovim后生效。
