# oh-my-mac

A comprehensive macOS development environment configuration featuring modern terminal, editor, and productivity tools. Built for efficiency with a focus on keyboard-centric workflows, seamless multi-device synchronization via Git, and automated deployment through symlinks.

## Overview

This dotfiles repository manages configurations across multiple software dimensions:

| Dimension | Primary Tool | Philosophy |
|-----------|-------------|------------|
| **Shell** | Zsh + Zap + Starship | Fast, minimal, informative prompt |
| **Terminal** | Ghostty | GPU-accelerated, modern terminal emulator |
| **Editor** | Neovim (primary) / Vim (legacy) | Modal editing, LSP-powered IDE experience |
| **Multiplexer** | Tmux | Persistent terminal sessions |
| **File Manager** | Yazi (terminal) / Nvim-tree (sidebar) | Keyboard-driven navigation |
| **Keyboard** | Karabiner-Elements | Vim-style navigation everywhere |
| **Launcher** | Raycast | Keyboard-first app launching |

## Repository Structure

```
~/.vim/                                    # Git repository root
├── .config/                               # XDG-compliant configurations
│   ├── nvim/                              # Neovim (Lua-based, 25+ modules)
│   ├── ghostty/                           # Terminal emulator config
│   ├── karabiner/                         # Keyboard remapping rules
│   ├── raycast/                           # Launcher extensions
│   ├── starship.toml                      # Shell prompt theme
│   └── cmux/                              # Local-only configs (excluded)
├── .zshrc                                 # Shell configuration (manual sync)
├── .tmux.conf                             # Terminal multiplexer
├── .ideavimrc                             # JetBrains IDE Vim emulation
├── lua/                                   # Neovim Lua modules
├── one-step-install.sh                    # **推荐: 一键安装脚本**
├── deploy.sh                              # 仅部署配置（符号链接）
├── mac-setup.sh                           # 仅安装软件
├── references/                            # Migration guides & docs
├── SYMLINK_SETUP.md                       # Sync management guide
└── CHANGELOG.md                           # Version history
```

## Configuration Architecture

### 1. Shell & Terminal Stack

#### Zsh Configuration (`.zshrc`)
Modern Zsh setup migrated from Oh-My-Zsh to lightweight alternatives:

```bash
# Plugin Manager: Zap (faster than Oh-My-Zsh)
# Plugins:
#   - zsh-autosuggestions      # Fish-like suggestions
#   - zsh-syntax-highlighting  # Command highlighting
#   - zap-zsh/supercharge      # Enhanced defaults

# Prompt: Starship (cross-shell, async rendering)
# Features:
#   - Directory navigation aliases: cc, cm, cdd, cn, cs, ct, cg, cr, cj, cll
#   - IDE shortcuts: idea, fleet, py
#   - Yazi integration: cd on quit
#   - Z command: smart directory jumping
```

#### Starship Prompt (`.config/starship.toml`)
Cross-shell prompt with rich context:
- **User/Host**: Shows when in SSH or different user
- **Directory**: Truncated with git repo awareness
- **Git**: Branch, status, ahead/behind indicators
- **Languages**: Java, Node.js, Python versions
- **Timing**: Commands >500ms show execution time
- **Style**: Nerd Font icons with custom colors

#### Ghostty Terminal (`.config/ghostty/config`)
Native macOS terminal with modern features:
```
Theme:        Catppuccin Mocha
Font:         Hack + Noto Sans SC (16pt)
Opacity:      0.85 (transparency)
Cursor:       Block with blinking
Navigation:   Alt+hjkl for pane switching
GPU:          Metal acceleration
Scrollback:   10000 lines
```

#### Tmux (`.tmux.conf`)
Terminal session management:
- **Prefix**: `Ctrl+t` (instead of default Ctrl+b)
- **Navigation**: Vim-style `hjkl` for panes
- **Mouse**: Full mouse support enabled
- **Windows**: Numbered from 1 (not 0)
- **Resizing**: `Ctrl+t` + `H/J/K/L`

完整编辑器盘点见 [Neovim 全量配置清单](.config/nvim/docs/config-inventory.md)。

### 2. Editor Stack

#### Neovim (Primary Editor)

可选图形界面：[Neovide 启动、外观与验收说明](.config/nvim/docs/neovide.md)，沿用现有 Neovim 和快捷键。
**Architecture**: Modular Lua configuration

Java 审查默认使用 Lathe 0.3.1：打开 Maven 工程自动准备 Java 8 分析模型，直接读取原工程最新源码，每工程缓存和构建副本独立；原 POM 和 Lombok 版本保持不变。Java 只使用 Lathe，已移除 JDT LS、后端切换及预热脚本。

安装前置、缓存位置、失败重试与已验证范围见 [Neovim 配置说明](.config/nvim/README.md#java-开发专题)。配置提交不包含本机 Lathe 安装资源或 Maven 制品缓存。

```lua
-- Entry Point Chain:
~/.config/nvim/init.vim      →  Loads lua/init.lua
~/.config/nvim/lua/init.lua  →  Loads the modular lazy.nvim configuration
```

**Module Organization** (`lua/user/`):

| Category | Modules | Purpose |
|----------|---------|---------|
| **Core** | `options.lua`, `keymaps.lua`, `autocommands.lua` | Editor fundamentals |
| **Plugin Management** | `plugins/init.lua` | lazy.nvim plugin declarations |
| **Java** | `lathe_config.lua`, `lathe_live.lua`, `plugins/java.lua` | Lathe integration and isolated Maven models |
| **LSP** | `plugins/lsp.lua`, `lsp/handlers.lua` | Language servers |
| **Completion** | `cmp.lua` | nvim-cmp with multiple sources |
| **UI** | `lualine.lua`, `bufferline.lua`, `whichkey.lua` | Visual interface |
| **Navigation** | `navigation.lua`, `snacks.lua`, `project.lua` | Snacks pickers, source previews, and project navigation |
| **Terminal** | `snacks.lua` | Integrated terminal |
| **Git** | `gitsigns.lua` | Inline git status/diff |
| **Editing** | `plugins/editing.lua` | Editing plugins and text motions |
| **Appearance** | `colorschemes/catppuccin.lua`, `transparency.lua` | Theme and transparency |

**Key Bindings** (Leader = `,`):

| Mode | Key | Action |
|------|-----|--------|
| Normal | `<leader>e` | Recent files in the current project |
| Normal | `<leader>p` | Find current file in tree |
| Normal | `<leader>f` | Project symbols or files with source preview. Remove `scope:!test` to include test paths |
| Normal | `<leader>F` | Project content search |
| Normal | `<leader>b` | Buffer list |
| Normal | `<leader>g` | Git operations (which-key submenu) |
| Normal | `<leader>l` | LSP operations (which-key submenu) |
| Normal | `gd` | Go to definition, including supported MyBatis XML links |
| Normal | `gr` | Find references with test paths listed last |
| Normal | `<C-\>` | Toggle terminal |

**LSP Configuration**:
- Configured servers: Lathe, pyright, ts_ls, vue_ls, eslint, cssls, html, emmet_ls. Installed packages and availability are listed in the inventory. Rust/JSON/Lua parser support does not imply an enabled language server.
- Diagnostics: Virtual text disabled, signs enabled
- Installation: independent language-tool directories; native vim.lsp.config/enable; no Mason
- Formatting: Conform.nvim (replaces null-ls)
- Completion: nvim-cmp with LSP, buffer, path, luasnip sources

Git 审查主入口使用 CodeDiff 4.0.8：目录树、单文件完整 Diff、比较基准选择，以及带来源反馈、撤销边界和显式 Apply Changes 的三方合并。历史查看同样由 CodeDiff 提供，Gitsigns 保留源码行级操作。详见 [Git 审查与合并指南](.config/nvim/docs/git-review-guide.md)。

Traditional Vim backups, vim-plug and copied plugin trees were removed. Neovim has its own runtime and lazy.nvim plugin set.

#### JetBrains IDEs (`.ideavimrc`)
Extensive Vim emulation for IntelliJ IDEA, PyCharm, Fleet:
- 800+ lines of IDE-specific keybindings
- Custom leader commands for refactoring
- Integration with IDE actions (rename, extract, etc.)

### 3. File Management

Yazi remains a standalone shell tool; the unused Neovim integration was removed.

#### Snacks Explorer

Open the project tree and reveal the current file with `<leader>p`. The tree shows file icons and Git status.

### 4. macOS System Integration

#### Karabiner-Elements (`.config/karabiner/karabiner.json`)
System-wide keyboard modifications:
```
Caps Lock → Left Control
Ctrl+hjkl → Arrow Keys (Vim navigation everywhere)
Backslash ↔ Delete (swap)
```

#### Raycast (`.config/raycast/`)
Application launcher and workflow automation:
- Extension bundles and manifests in `.config/raycast/extensions/`
- Includes Easydict, JSON Editor, and Date Format Converter

### 5. Deployment & Synchronization

#### Symlink-Based Management
Configurations are symlinked from `~/.vim/.config/` to `~/.config/`:

```bash
~/.config/nvim        → ~/.vim/.config/nvim
~/.config/ghostty     → ~/.vim/.config/ghostty
~/.config/karabiner   → ~/.vim/.config/karabiner
~/.config/raycast     → ~/.vim/.config/raycast
~/.config/starship.toml → ~/.vim/.config/starship.toml
```

**Notable Exception**: `.zshrc` is NOT symlinked (manual sync) due to machine-specific customizations.

#### Quick Deployment

```bash
# New machine setup
git clone git@github.com:Janglejay/vim-config.git ~/.vim
cd ~/.vim && ./deploy.sh

# The deploy script:
# 1. Creates timestamped backups of existing configs
# 2. Creates symlinks for all managed configs
# 3. Preserves local-only configurations
```

## Installation Scripts

This repository provides three installation scripts for different use cases:

| Script | Purpose | Use When |
|--------|---------|----------|
| `one-step-install.sh` | **完整安装** (软件 + 配置) | 新机器首次设置 |
| `mac-setup.sh` | 仅安装软件 | 只需安装应用，不部署配置 |
| `deploy.sh` | 仅部署配置 | 软件已安装，只需同步配置 |

### Script Details

#### `one-step-install.sh` (Recommended)
The all-in-one installer for new machines:
```bash
./one-step-install.sh
```
**Does:**
- Installs Homebrew
- Installs all CLI tools (Git, Neovim, Tmux, Starship, Zap, Yazi, etc.)
- Installs GUI apps (Ghostty, Karabiner, Raycast)
- Clones the repository
- Creates symbolic links
- Configures Zsh
- Installs Neovim/Tmux plugins

#### `mac-setup.sh`
Software-only installer:
```bash
./mac-setup.sh
```
**Does:** Installs applications and tools
**Does NOT:** Clone repo, create symlinks, or configure shell

#### `deploy.sh`
Configuration-only deployer:
```bash
./deploy.sh
```
**Does:** Creates symbolic links from `~/.vim/.config/` to `~/.config/`
**Does NOT:** Install any software (assumes they're already installed)

## Software Dimension Details

### Shell Dimension
| Component | Tool | Config Location | Purpose |
|-----------|------|-----------------|---------|
| Shell | Zsh | `.zshrc` | Command interpreter |
| Plugin Manager | Zap | `.zshrc` | Zsh plugin management |
| Prompt | Starship | `.config/starship.toml` | Rich context prompt |
| Directory Jump | Z | `.zshrc` | Frecency-based cd |
| File Manager | Yazi | Shell integration | TUI file operations |

### Terminal Dimension
| Component | Tool | Config Location | Purpose |
|-----------|------|-----------------|---------|
| Emulator | Ghostty | `.config/ghostty/config` | Modern GPU terminal |
| Multiplexer | Tmux | `.tmux.conf` | Session management |
| Font | Hack + Noto Sans SC | System | Monospace + CJK support |

### Editor Dimension
| Component | Tool | Config Location | Purpose |
|-----------|------|-----------------|---------|
| Primary | Neovim | `.config/nvim/` | Modern modal editor |
| IDE | JetBrains + IdeaVim | `.ideavimrc` | GUI IDE with Vim |
| Notes | Obsidian | `.obsidian.vimrc` | Knowledge base |

### macOS Dimension
| Component | Tool | Config Location | Purpose |
|-----------|------|-----------------|---------|
| Keyboard | Karabiner-Elements | `.config/karabiner/` | Key remapping |
| Launcher | Raycast | `.config/raycast/` | App launching |

## Getting Started

### Prerequisites
- macOS (primary target)
- Git
- Internet connection

### One-Step Installation (Recommended)

The fastest way to set up the entire environment:

```bash
# Option 1: Clone and run installer
git clone git@github.com:Janglejay/vim-config.git ~/.vim
cd ~/.vim && ./one-step-install.sh

# Option 2: Direct install via curl (if repo is public)
curl -fsSL https://raw.githubusercontent.com/Janglejay/vim-config/main/one-step-install.sh | bash
```

This script will:
1. Install Homebrew (if not present)
2. Install all CLI tools: Git, Neovim, Tmux, Starship, Zap, Yazi, Zoxide, etc.
3. Install GUI apps: Ghostty, Karabiner-Elements, Raycast
4. Clone the dotfiles repository
5. Create symbolic links for all configurations
6. Install Neovim and Tmux plugins
7. Configure Zsh with required settings

### Manual Installation (Alternative)

If you prefer step-by-step control:

```bash
# 1. Clone repository
git clone git@github.com:Janglejay/vim-config.git ~/.vim

# 2. Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 3. Install CLI tools
brew install git nvim tmux starship ripgrep fd fzf lazygit yazi zoxide

# 4. Install GUI apps
brew install --cask ghostty karabiner-elements raycast

# 5. Deploy symlinks
cd ~/.vim && ./deploy.sh

# 6. Install Neovim plugins
nvim +Lazy
```

### Post-Installation

1. **Restart terminal** or run `source ~/.zshrc` to apply changes
2. **Karabiner-Elements**: Open and grant system permissions
3. **Raycast**: Set shortcut to `Cmd+Space` to replace Spotlight
4. **Ghostty**: Configuration auto-loaded from `.config/ghostty/`
5. **Tmux plugins**: Start tmux, press `Ctrl+t` then `I` (capital i) to install plugins

## Key Workflows

### Daily Development
```bash
# Open project
cd ~/projects/my-project
nvim .

# Inside Neovim:
# <leader>e  - Open file tree
# <leader>f  - Find file
# <leader>F  - Search in files
# gd         - Go to definition
# <C-\>      - Open terminal
```

### Terminal Session Management
```bash
# Start new session
tmux new -s project

# Detach: Ctrl+t d
# Reattach: tmux attach -t project

# Window navigation: Ctrl+t 1/2/3...
# Pane navigation: Ctrl+t hjkl
```

### File Operations
```bash
# Quick file manager in terminal
yazi

# Or in Neovim:
# <leader>e  - Toggle sidebar tree
# <leader>p  - Find current file
```

## Configuration Philosophy

1. **Keyboard-First**: Minimize mouse usage with Vim-style bindings everywhere
2. **Git-Tracked**: All configs version controlled for rollback and sync
3. **Modular**: Each tool has isolated, focused configuration
4. **Progressive Enhancement**: Works without plugins, enhanced with them
5. **Cross-Tool Consistency**: Similar keybindings across editors, terminal, system

## Troubleshooting

### Neovim
- **Plugins not loading**: Run `:PackerSync`
- **LSP not working**: Check independent tool paths in `.config/nvim/docs/language-tools.md`
- **Config errors**: Check `:messages` and `:checkhealth`

### Symlinks
- **Broken links**: Re-run `./deploy.sh`
- **Conflicts**: Check `~/.config/backups-*/` for originals

### Terminal
- **Fonts not showing**: Install Nerd Font (Hack Nerd Font)
- **Colors wrong**: Ensure `$TERM` supports truecolor

## References

- [SYMLINK_SETUP.md](./SYMLINK_SETUP.md) - Detailed sync management
- [references/ohmyzsh-to-starship-zap-migration.md](./references/ohmyzsh-to-starship-zap-migration.md) - Shell migration guide
- [references/symlink-config-guide.md](./references/symlink-config-guide.md) - Symlink configuration patterns
- [CHANGELOG.md](./CHANGELOG.md) - Version history

## License

Personal configuration - feel free to reference and adapt for your own use.
