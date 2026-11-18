# 语言工具独立安装与统一快捷键

Java 使用 Lathe；其他语言使用各自的语言服务。Mason 与 mason-lspconfig 已移除。工具安装放在编辑器之外，Neovim 原生 LSP 负责启动和通信，公共配置统一键位与补全。

## 安装位置与版本

本轮复用本机已安装的公开 npm 包，将其迁出 Mason 目录，没有联网重装或升级；保留各前缀的 package.json、lockfile 和 node_modules。下表是实际读取的直接依赖版本。

| 前缀（位于 `~/.local/share/nvim/language-tools/`） | 包与版本 | 服务 |
|---|---|---|
| `pyright/` | pyright 1.1.408 | Python |
| `typescript/` | typescript 6.0.3、typescript-language-server 5.3.0 | JS/TS |
| `vue/` | @vue/language-server 3.3.5、typescript 6.0.3 | Vue |
| `web/` | vscode-langservers-extracted 4.10.0 | CSS、HTML、ESLint |
| `emmet/` | emmet-ls 0.4.2 | Emmet |

这些文件均为本机工具，不随配置仓库提交。Lathe 的客户端、服务器和构建模型路径由 `lua/user/lathe_config.lua` 维护。

## 手动安装或更新

已存在且有 lockfile 的前缀，可进入对应目录执行 `npm ci` 按现有依赖树重装。新机器可使用以下明确版本的命令；它们只固定直接依赖，新生成的传递依赖树应保留 lockfile。命令需用户主动运行，编辑器启动不安装或更新工具。

```bash
tools_dir="$HOME/.local/share/nvim/language-tools"
npm install --prefix "$tools_dir/pyright" --save-exact pyright@1.1.408
npm install --prefix "$tools_dir/typescript" --save-exact typescript@6.0.3 typescript-language-server@5.3.0
npm install --prefix "$tools_dir/vue" --save-exact @vue/language-server@3.3.5 typescript@6.0.3
npm install --prefix "$tools_dir/web" --save-exact vscode-langservers-extracted@4.10.0
npm install --prefix "$tools_dir/emmet" --save-exact emmet-ls@0.4.2
```

保持可用 Node 运行时。不要把其他工程的 package.json 或私有依赖送入以上公共工具安装步骤。

## 增加或更换语言服务

只在 `lua/user/lsp/servers.lua` 配置启动命令、filetypes、root_markers、服务设置，以及公共 `handlers.on_attach` / `handlers.capabilities`，再 `vim.lsp.enable(name)`。不复制另一套快捷键。Vue/TS 等服务如果必须定制 attach，只追加服务行为并调用公共 on_attach。

| 操作 | 共用入口 | 实现 |
|---|---|---|
| 定义／声明处查引用 | `gd` | 公共异步查询；保留过期请求、超时及跳回 Diff 的保护 |
| 查引用／实现／调用树 | `gr` / `gi` / `gR` | 当前服务提供数据，统一 Snacks/Saga 界面 |
| 声明 | `gD` / `gu` | 原生 declaration |
| 项目符号 | `,f` | 非 Java 用 workspace/symbol；Java 保留原有磁盘声明搜索；无服务能力时退回文件搜索 |
| 全文搜索 | `,F` | 文本搜索，不依赖语言服务 |
| 当前文件大纲 | `,s` | Aerial，语言服务或 Treesitter 提供结构 |
| 查看说明 | `Ctrl+p` | hover |
| 重命名／重构／整理导入 | `,R` / `,T` / `,oi` | 统一 LSP 请求，具体服务必须支持该动作 |
| 补全选择／确认／片段 | 原有 Ctrl+e/u、Enter、Tab/Shift-Tab | 共用 nvim-cmp/LuaSnip |
| 参数提示 | 插入模式 `Ctrl+s` | Neovim 原生 signature_help；不再用 lsp_signature 自动弹窗 |

索引就绪由各服务维护，LSP 没有通用的强制重建索引请求。`,lr` / `,lR` 是 Lathe 项目模型维护入口，不能假装它们对所有语言都执行同一种重建。统一快捷键不等于各服务支持完全相同的语义能力。Java `,f` 的字段、未保存修改及更完整声明解析仍属已知缺口。

## 审查配置边界

Neovim的测试运行器、DAP、测试适配器及快捷键已删除；没有注册 `:LatheDebug`。独立语言工具和公共跳转、补全、重构继续保留。Lathe上游包本身包含可选运行模块，本配置不修改其源码。

## 替代工具判断

- 当前采用独立 npm 前缀与原生 LSP，安装管理层最少，无额外常驻管理器。
- [mise](https://mise.jdx.dev/) 可统一管理 Node、Python 及其他开发工具的版本，并在 shell、编辑器和 CI 间复用环境；适合进一步统一多机器工具链。它不是语言分析引擎，换用它不会直接提高跳转准确性或索引速度。本轮未安装。
- [nvim-lsp-installer](https://github.com/williamboman/nvim-lsp-installer) 已归档并迁移到 Mason，不采用。

## 验证范围

7 个独立路径的语言服务已在空的本地目录完成 initialize 握手，包括原先命令错误的 Emmet；未打开业务文件，未验证各语言真实工程的索引准确性。CodeDiff 的文件历史（含空格路径）、项目历史、历史后返回分支审查及从审查进入文件历史，已在本地合成仓库验证。没有重启用户当前 Neovim 会话，下一次打开使用新配置。
