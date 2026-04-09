# 软链接配置方案

## 概述

通过软链接将分散在 `~/.config/` 各处的配置文件统一管理，实现**单一数据源，多处生效**。

## 方案设计

### 目录结构

```
~/MyProjects/oh-my-mac/          (Git 仓库，版本控制)
└── .config/
    ├── nvim/                    (Neovim 配置)
    ├── ghostty/                 (Ghostty 终端配置)
    ├── karabiner/               (Karabiner 键盘配置)
    ├── raycast/                 (Raycast 配置)
    └── starship.toml            (Starship 提示符配置)

~/.config/                        (用户配置目录，软链接指向仓库)
├── nvim     -> ~/MyProjects/oh-my-mac/.config/nvim
├── ghostty  -> ~/MyProjects/oh-my-mac/.config/ghostty
├── karabiner -> ~/MyProjects/oh-my-mac/.config/karabiner
├── raycast  -> ~/MyProjects/oh-my-mac/.config/raycast
└── starship.toml -> ~/MyProjects/oh-my-mac/.config/starship.toml

~/.zshrc -> ~/MyProjects/oh-my-mac/.zshrc
```

### 优点

1. **单一数据源** - 所有配置在 Git 仓库中统一管理
2. **版本控制** - 配置变更可追溯、可回滚
3. **多设备同步** - clone 仓库后创建软链接即可恢复环境
4. **隔离性好** - 修改不影响系统其他配置

## 新设备部署流程

### 1. 克隆仓库

```bash
git clone git@github.com:Janglejay/oh-my-mac.git ~/MyProjects/oh-my-mac
```

### 2. 创建软链接

```bash
# Neovim
ln -s ~/MyProjects/oh-my-mac/.config/nvim ~/.config/nvim

# Ghostty
ln -s ~/MyProjects/oh-my-mac/.config/ghostty ~/.config/ghostty

# Karabiner
ln -s ~/MyProjects/oh-my-mac/.config/karabiner ~/.config/karabiner

# Raycast
ln -s ~/MyProjects/oh-my-mac/.config/raycast ~/.config/raycast

# Starship
mkdir -p ~/.config
ln -s ~/MyProjects/oh-my-mac/.config/starship.toml ~/.config/starship.toml

# Zsh
ln -s ~/MyProjects/oh-my-mac/.zshrc ~/.zshrc
```

### 3. 一键部署脚本

```bash
#!/bin/zsh
# deploy.sh

REPO_DIR="$HOME/MyProjects/oh-my-mac"
CONFIG_DIR="$HOME/.config"

# 创建必要的目录
mkdir -p "$CONFIG_DIR"

# 软链接配置
ln -sf "$REPO_DIR/.config/nvim" "$CONFIG_DIR/nvim"
ln -sf "$REPO_DIR/.config/ghostty" "$CONFIG_DIR/ghostty"
ln -sf "$REPO_DIR/.config/karabiner" "$CONFIG_DIR/karabiner"
ln -sf "$REPO_DIR/.config/raycast" "$CONFIG_DIR/raycast"
ln -sf "$REPO_DIR/.config/starship.toml" "$CONFIG_DIR/starship.toml"
ln -sf "$REPO_DIR/.zshrc" "$HOME/.zshrc"

# 安装必要工具
brew install starship

echo "部署完成！请重新打开终端或 source ~/.zshrc"
```

## 注意事项

### 1. 敏感配置排除

以下配置不应放入 Git 仓库：

```gitignore
# .gitignore 示例
.config/clash/          # 代理配置（可能包含凭证）
.config/cmux/           # 本地多路复用配置
*.local                # 本地特定配置
.DS_Store
```

### 2. 软链接验证

```bash
# 检查软链接是否正确
ls -la ~/.config/

# 验证目标存在
ls -la ~/.config/nvim
```

### 3. 冲突处理

如果目标已存在：

```bash
# 先备份
mv ~/.config/nvim ~/.config/nvim.bak

# 再创建软链接
ln -s ~/MyProjects/oh-my-mac/.config/nvim ~/.config/nvim
```

## 相关文档

- [ohmyzsh-to-starship-zap-migration.md](./ohmyzsh-to-starship-zap-migration.md) - Zsh 环境迁移指南
