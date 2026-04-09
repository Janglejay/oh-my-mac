# Oh-My-Zsh 迁移到 Starship + Zap 完整指南

## 概述

本文档记录从 Oh-My-Zsh 迁移到 Starship + Zap 的完整方案，包括工具选择理由、迁移步骤、配置说明和常见问题解决。

**迁移时间**: 2026-04-09

---

## 为什么迁移

| 对比项 | Oh-My-Zsh | Starship + Zap |
|-------|-----------|----------------|
| 启动速度 | 100-500ms | 20-50ms |
| 内存占用 | 较高 | 较低 |
| 定制灵活性 | 中等 | 极高 |
| Git 信息显示 | 基础 | 详细（分支、stash、ahead/behind等） |
| 跨 Shell 支持 | 仅 Zsh | Zsh/Bash/Fish/PowerShell |

---

## 工具介绍

### Starship
- **定位**: 跨 shell 的极速提示符（Prompt）
- **语言**: Rust 编写，性能极佳
- **特点**:
  - 启动速度快 10-100 倍
  - 内置丰富的模块（git、nodejs、python、java 等）
  - 跨平台，支持多种 shell
  - 可自定义每个元素的显示

### Zap
- **定位**: 极速 Zsh 插件管理器
- **特点**:
  - 延迟加载插件，提升启动速度
  - 兼容所有 oh-my-zsh 插件
  - 支持并行安装插件
  - 配置简单，单行命令安装

---

## 迁移前准备

### 1. 备份当前配置

```bash
# 备份 .zshrc
cp ~/.zshrc ~/.zshrc.omz-backup-$(date +%Y%m%d)

# 如果使用了自定义插件，也备份一下
cp -r ~/.oh-my-zsh/custom/plugins ~/oh-my-zsh-plugins-backup
```

### 2. 记录当前插件列表

查看当前 `.zshrc` 中的 `plugins` 配置：

```bash
grep -A 10 "^plugins=" ~/.zshrc
```

常见的 oh-my-zsh 插件对应关系：

| Oh-My-Zsh 插件 | Zap/Starship 替代方案 |
|---------------|----------------------|
| `git` | Starship 内置 git 模块 |
| `zsh-autosuggestions` | `plug "zsh-users/zsh-autosuggestions"` |
| `zsh-syntax-highlighting` | `plug "zsh-users/zsh-syntax-highlighting"` |
| `z` | 保留现有 `z.sh` 或使用 `agkozak/zsh-z` |

---

## 迁移步骤

### 步骤 1: 安装 Starship

```bash
# macOS (使用 Homebrew)
brew install starship

# 或使用官方脚本
curl -sS https://starship.rs/install.sh | sh
```

### 步骤 2: 安装 Zap

```bash
# 安装 Zap
zsh <(curl -s https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh) --branch release-v1
```

安装完成后，Zap 会自动创建一个新的 `.zshrc` 文件，原配置会被备份为 `.zshrc_YYYY-MM-DD_时间戳`。

### 步骤 3: 配置新的 .zshrc

将原有的环境变量、别名等配置合并到新的 `.zshrc` 中：

```zsh
# ============================================================================
# Zap 插件管理器配置
# ============================================================================

# 初始化 Zap
[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh" ] && source "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh"

# 插件配置
plug "zsh-users/zsh-autosuggestions"
plug "zsh-users/zsh-syntax-highlighting"
plug "zap-zsh/supercharge"

# 加载补全系统
autoload -Uz compinit
compinit

# ============================================================================
# Starship 提示符配置
# ============================================================================

eval "$(starship init zsh)"

# ============================================================================
# 原有配置迁移到这里
# ============================================================================

# 环境变量、别名、函数等...
```

### 步骤 4: 创建 Starship 配置

```bash
mkdir -p ~/.config
touch ~/.config/starship.toml
```

**推荐配置**:

```toml
# Starship 配置文件
format = """
$username$hostname$directory$git_branch$git_status$java$nodejs$python$cmd_duration$line_break$character"""

# 提示符字符
[character]
success_symbol = "[➜](bold green)"
error_symbol = "[✗](bold red)"
vimcmd_symbol = "[❮](bold green)"

# 用户名
[username]
style_user = "white bold"
style_root = "red bold"
format = "[$user]($style)"
show_always = false

# 主机名
[hostname]
ssh_only = true
format = "[@$hostname](bold yellow) "

# 目录显示
[directory]
truncation_length = 3
truncate_to_repo = true
format = "[$path]($style)[$read_only]($read_only_style) "
style = "cyan bold"

# Git 分支
[git_branch]
symbol = " "
format = "on [$symbol$branch(:$remote_branch)]($style) "
truncation_length = 20
truncation_symbol = "…"
style = "purple bold"

# Git 状态
[git_status]
format = '([$all_status$ahead_behind]($style)) '
conflicted = "=${count} "
ahead = "⇡${count} "
behind = "⇣${count} "
diverged = "⇕⇡${ahead_count}⇣${behind_count} "
untracked = "?${count} "
stashed = "\\${count} "
modified = "!${count} "
staged = "+${count} "
renamed = "»${count} "
deleted = "✘${count} "
style = "red bold"

# Java 版本
[java]
symbol = " "
style = "red dimmed"
format = "via [$symbol($version )]($style)"

# Node.js 版本
[nodejs]
symbol = " "
style = "green bold"
format = "via [$symbol($version )]($style)"

# Python 版本
[python]
symbol = " "
style = "yellow bold"
format = 'via [$symbol$pyenv_prefix($version )(\($virtualenv\) )]($style)'

# 命令执行时间
[cmd_duration]
min_time = 500
format = "took [$duration](bold yellow) "
style = "bold yellow"

# 禁用不需要的模块
[package]
disabled = true

[docker_context]
disabled = true
```

### 步骤 5: 加载新配置

```bash
source ~/.zshrc
```

或打开新的终端窗口。

---

## 配置详解

### Starship 提示符格式

新的提示符会显示：

```
fufangjie@hostname ~/Projects/myapp on main via v18.12.1 took 2s
➜
```

各部分的含义：
- `fufangjie` - 用户名
- `@hostname` - 主机名（仅 SSH 时显示）
- `~/Projects/myapp` - 当前目录
- `on main` - Git 分支
- `?2 !1` - Git 状态（2 个未跟踪文件，1 个修改）
- `via v18.12.1` - Node.js 版本（根据项目自动检测）
- `took 2s` - 上一条命令执行时间
- `➜` - 提示符

### 支持的编程语言

Starship 会自动检测以下语言的版本：
- Java (☕)
- Node.js (⬢)
- Python (🐍)
- Go
- Rust
- Ruby
- 等等

---

## 常见问题

### 1. TOML 语法错误

**错误信息**:
```
Error in 'GitStatus' at 'stashed': missing escaped value
```

**原因**: `$` 符号在 TOML 中需要转义

**解决**:
```toml
# 错误
stashed = "\${count} "

# 正确
stashed = "\\${count} "
```

### 2. Git 分支截断配置错误

**错误信息**:
```
Unknown key (Did you mean 'truncation_symbol'?)
```

**解决**:
```toml
# 错误
truncate_symbol = "…"

# 正确
truncation_symbol = "…"
```

### 3. 插件未生效

**解决**: 确保在 `compinit` 之前加载 Zap：

```zsh
source "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh"
plug "zsh-users/zsh-autosuggestions"
plug "zsh-users/zsh-syntax-highlighting"
autoload -Uz compinit
compinit
```

### 4. Starship 提示符不显示

**检查**:
```bash
which starship
starship --version
```

确保 `eval "$(starship init zsh)"` 在 `.zshrc` 中。

---

## Zap 插件管理

### 安装插件

```zsh
plug "作者/仓库名"
```

### 常用插件推荐

```zsh
# 自动建议
plug "zsh-users/zsh-autosuggestions"

# 语法高亮
plug "zsh-users/zsh-syntax-highlighting"

# 快速目录跳转（替代 z）
plug "agkozak/zsh-z"

# 历史搜索
plug "zsh-users/zsh-history-substring-search"

# 自动补全
plug "zsh-users/zsh-completions"

# fzf 集成
plug "Aloxaf/fzf-tab"
```

### 更新插件

```bash
# 更新所有插件
zap update

# 更新特定插件
zap update zsh-autosuggestions
```

### 删除插件

直接从 `.zshrc` 中删除对应的 `plug` 行，然后重新加载配置。

---

## 回退方案

如果迁移后不满意，可以恢复到 Oh-My-Zsh：

```bash
# 恢复备份
cp ~/.zshrc.omz-backup-20260409 ~/.zshrc

# 重新加载
source ~/.zshrc
```

---

## 参考链接

- [Starship 官方文档](https://starship.rs/config/)
- [Zap GitHub 仓库](https://github.com/zap-zsh/zap)
- [Zsh 自动建议插件](https://github.com/zsh-users/zsh-autosuggestions)
- [Zsh 语法高亮插件](https://github.com/zsh-users/zsh-syntax-highlighting)

---

## 迁移检查清单

- [ ] 备份原 `.zshrc`
- [ ] 安装 Starship
- [ ] 安装 Zap
- [ ] 创建新的 `.zshrc`
- [ ] 创建 `starship.toml`
- [ ] 迁移环境变量
- [ ] 迁移别名
- [ ] 迁移自定义函数
- [ ] 测试 Git 显示
- [ ] 测试语言版本检测
- [ ] 提交到 dotfiles 仓库

---

*文档生成时间: 2026-04-09*
*适用于: macOS + Homebrew + Zsh 环境*
