# Neovide

Neovide 0.17.2 作为现有 Neovim 的可选图形界面，使用 `/opt/homebrew/bin/nvim` 和同一份用户配置；复用现有插件和 Vim 快捷键，额外提供仅 GUI 生效的 macOS 常用快捷键。安装的是官方 Apple Silicon 发布包，已核对官方 SHA256。Neovim 保持 0.12.3，没有通过 Homebrew 升级依赖。

## 启动

运行 `neovide --reuse-instance /absolute/path/to/project`，或从 Applications 打开 Neovide。命令链接为 `/opt/homebrew/bin/neovide`，应用位于 `/Applications/Neovide.app`。如果希望省略复用参数，可在 `~/.zshrc` 添加 `alias neovide='neovide --reuse-instance'`，然后在现有终端运行 `source ~/.zshrc`。启用 `fork = true` 后，终端会在启动后返回。

### 打开文件和项目

Neovide 没有另一套项目模型；“打开项目”就是切换 Neovim 的当前目录，再从该目录选择文件。因此 Java 模型会在打开该项目的 Java 文件时按现有 Lathe 生命周期准备。

| 操作 | 快捷键 | 行为 |
| --- | --- | --- |
| 新建文件 | `Cmd+N` | 新建未命名 Neovim buffer；`Cmd+S` 时按现有 Save As 流程命名。 |
| 打开当前项目文件 | `Cmd+O` 或 `Cmd+P` | 在当前项目根目录打开模糊文件选择。 |
| 切换到已知项目 | `gw` | 从当前和最近打开文件识别项目根；确认后在同一个 Neovide 应用中新建项目窗口。 |
| 打开任意项目目录 | `Cmd+Shift+O` | 输入或粘贴项目目录；目录存在后在当前窗口切换 cwd，并立即显示该项目的文件选择。 |
| 当前项目目录树 | `,p` | 在当前窗口显示/定位 Snacks Explorer。 |
| 命令面板 | `Cmd+Shift+P` | 搜索并执行 Neovim 命令。 |
| 新 Neovide 窗口 | `Cmd+Shift+N` | Neovide 原生新窗口；也可用 `Window > New Window`。 |
| 从终端新开项目窗口 | `neovide --reuse-instance --new-window --chdir /absolute/path/to/project` | 在已有应用中新建窗口。 |

上述 `Cmd` 映射只在 Neovide 生效。Neovide 只转发按键、不自带编辑器快捷键；映射由 `lua/user/neovide.lua` 定义。修改 `config.toml` 后请退出并重新打开 Neovide。

## 界面设置

- `~/.config/neovide/config.toml`：固定现有 Neovim，窗口最大化，保留 multigrid 与空闲停绘。
- `lua/user/neovide.lua`：JetBrainsMono Nerd Font Mono（字号由 `neovide.lua` 第一行的 `h16` 控制），Symbols Nerd Font Mono 作为图标回退；复用本机字体。
- Neovide 窗口和正文不透明度均为 1，浮窗/补全透明度为 0，无背景模糊。
- 光标动画和短距离动画均为 0；插入模式不做光标动画，无粒子效果。
- `lua/user/options.lua` 避免启动时应用 macOS 无法解析的通用 monospace 字体。`lua/user/transparency.lua` 仅对终端保留原透明背景逻辑。

这些设置和 Command 快捷键仅在 `vim.g.neovide` 为真时生效。终端中的 `monospace:h17`、winblend/pumblend=15 保持原样。GUI 不改变 Lathe 索引策略，也不承诺降低语言服务内存或索引时间。

## macOS Command 快捷键

仅在 Neovide 生效，终端 Neovim 不注册这些映射。

| 快捷键 | 行为 |
| --- | --- |
| `⌘C` | 复制选区；普通/插入模式无选区时复制当前行；命令行模式复制当前命令文本 |
| `⌘V` | 普通、插入、可视选择、命令行、内置终端模式粘贴；可视模式替换选区 |
| `⌘X` | 剪切选区；普通/插入模式无选区时剪切当前行 |
| `⌘A` | 普通、插入、可视模式全选当前文件 |
| `⌘S` | 保存当前文件；未命名文件显示 Save As，可取消 |
| `⌘Z` / `⇧⌘Z` | 撤销/重做；三方合并使用已有合并历史和边界保护 |
| `⌘N` | 新建未命名文件；Neovide 的新窗口移至 `⇧⌘N` |
| `⌘O` / `⌘P` | 使用现有 Snacks 文件选择器打开当前项目文件 |
| `⇧⌘O` | 输入或粘贴目录，切换到另一个项目后选择文件 |
| `⇧⌘P` | 命令面板 |
| `⌘F` | 当前文件查找，Enter 确认，Esc 取消 |
| `⌘W` | 关闭当前文件/审查，沿用未保存、未完成合并的确认保护 |

内置终端可用鼠标或 Visual 模式选中输出后复制；没有选区时 `⌘C` 复制光标所在行，不向进程发送 Ctrl+C。剪切和粘贴不会修改只读 Diff 来源；在中间 Result 或工作文件中编辑。`⌘S` 只保存，冲突完成仍使用 `mf` / Apply Changes。

`⌘H` 隐藏、`⌘M` 最小化、`⌘Q` 退出、`⇧⌘N` 新建窗口、`⌃⌘F` 全屏由 Neovide 原生菜单处理，未自动执行退出操作。文件编辑与 Command 快捷键不会把 Neovim 变成 Cocoa 原生文本框；命令行没有额外模拟选区或剪切。

`<D-v>` 是 Neovim 对 Command+V 的写法；`n/i/x/c/t` 分别表示普通/插入/可视选择/命令行/内置终端模式。配置在新启动的 Neovide 中生效，已有会话不自动重载。需要手动应用时，可在目标 Neovide 执行 `:lua package.loaded["user.neovide"]=nil; require("user.neovide").setup()`，不需要关闭文件或清除索引。

## Git 和导航

沿用现有 `,g` 菜单、`,gd` 审查、`,gB` 比较基准选择。`gw` 用于切换项目，`,p` 打开当前项目目录树。三方合并中，冲突块旁的左右箭头可点击；`ml`/`mr` 采用左/右，`ma` 保留双方，`mu` 恢复 Base，`mz`/`mZ` 撤销/重做，`mf` 执行 Apply Changes。`Ctrl+d`/`Ctrl+f` 跳转下一/上一处变更。Java 中 `gd` 查询定义/引用，`Ctrl+o` 返回原位置。

## 本次验证（2026-11-17）

全部使用无远端的本地示例与独立 Neovide 实例，没有接入、重载、关闭原有 Neovim 会话，也没有读取或写入其未保存缓冲区。

- 在实际 Neovide GUI 中点击左侧第一个、右侧第二个冲突块箭头，并核对仅对应结果改变。
- 验证三方分组、ml/mr/ma/mu、撤销/重做、实际 GUI Ctrl+d/Ctrl+f，以及未完成合并保护和最终保存/暂存。
- 使用 Lathe 0.3.1 的独立 Maven 示例模型和真实服务，实际 GUI gd 从 Diff 右侧跳至另一模块的方法/字段定义，Ctrl+o 恢复同一 Diff 窗口、缓冲区和光标。隔离测试跳过自动模型准备，直接启动现有模型；未运行公司工程的首次模型导入性能测试。
- 正常配置重新启动后无消息错误，字体/背景/动画参数符合预期；终端模式回归检查通过。
- Command 快捷键在独立 GUI 中验证了原生 C/V/X/A/S/Z/Shift+Z/O/F 按键；补验插入/选择/命令行/内置终端粘贴、选区替换的剪贴板保留、未命名 Save As 取消、关闭未保存文件取消和合并撤销/关闭保护。终端的五种模式全量映射前后相同，没有注册这些 Command 映射。
- 临时验收 GUI 与它启动的 Java 服务已退出；保留一个使用正常用户配置的简洁合并示例窗口供体验。

官方说明：[安装](https://neovide.dev/installation.html)、[运行设置](https://neovide.dev/configuration.html)、[配置文件](https://neovide.dev/config-file.html)。
