# 软链接配置方案

本文档说明本仓库的软链接配置方案，以及如何在多台设备上同步配置。

## 目录结构

```
~/.vim/                          (Git 仓库)
├── .config/
│   ├── nvim/                    # Neovim 配置
│   ├── ghostty/                 # Ghostty 终端配置
│   ├── karabiner/               # Karabiner 键盘配置
│   ├── raycast/                 # Raycast 配置
│   └── starship.toml            # Starship 提示符配置
├── .zshrc                       # Zsh 配置
├── deploy.sh                    # 一键部署脚本
└── README.md                    # 使用说明

~/.config/                       (用户配置目录)
├── nvim -> ~/.vim/.config/nvim
├── ghostty -> ~/.vim/.config/ghostty
├── karabiner -> ~/.vim/.config/karabiner
├── raycast -> ~/.vim/.config/raycast
└── starship.toml -> ~/.vim/.config/starship.toml

~/.zshrc -> ~/.vim/.zshrc
```

## 快速开始

### 新设备部署

```bash
# 1. 克隆仓库
git clone git@github.com:Janglejay/vim-config.git ~/.vim

# 2. 运行部署脚本
cd ~/.vim && ./deploy.sh

# 3. 安装依赖
brew install starship

# 4. 重新加载配置
source ~/.zshrc
```

### 手动创建软链接

```bash
# 创建必要的目录
mkdir -p ~/.config

# 创建软链接
ln -sf ~/.vim/.config/nvim ~/.config/nvim
ln -sf ~/.vim/.config/ghostty ~/.config/ghostty
ln -sf ~/.vim/.config/karabiner ~/.config/karabiner
ln -sf ~/.vim/.config/raycast ~/.config/raycast
ln -sf ~/.vim/.config/starship.toml ~/.config/starship.toml
ln -sf ~/.vim/.zshrc ~/.zshrc
```

## 配置管理

### 修改配置

直接编辑 `~/.vim/` 下的文件：

```bash
# 编辑 zsh 配置
vim ~/.vim/.zshrc

# 编辑 starship 配置
vim ~/.vim/.config/starship.toml

# 编辑 nvim 配置
vim ~/.vim/.config/nvim/lua/user/
```

### 提交变更

```bash
cd ~/.vim
git add .
git commit -m "更新配置"
git push
```

### 同步到其他设备

```bash
# 在其他设备上执行
cd ~/.vim
git pull
```

## 文件说明

| 文件/目录 | 用途 |
|----------|------|
| `.zshrc` | Zsh shell 配置，包含别名、环境变量、插件等 |
| `.config/starship.toml` | Starship 提示符主题配置 |
| `.config/nvim/` | Neovim 完整配置（Lua） |
| `.config/ghostty/` | Ghostty 终端模拟器配置 |
| `.config/karabiner/` | Karabiner-Elements 键盘映射 |
| `.config/raycast/` | Raycast 启动器配置 |
| `deploy.sh` | 一键部署脚本 |
| `SYMLINK_SETUP.md` | 本文档 |

## 备份机制

运行 `deploy.sh` 时会自动备份现有配置：

```
~/.config/backups-YYYYMMDD-HHMMSS/
├── starship.toml
├── raycast/
├── karabiner/
├── ghostty/
└── .zshrc
```

## 注意事项

### 1. 不要直接编辑软链接目标

错误：
```bash
vim ~/.config/starship.toml  # 这会编辑 ~/.vim/.config/starship.toml
```

正确：
```bash
vim ~/.vim/.config/starship.toml
```

### 2. 敏感配置排除

以下配置不放入 Git 仓库：
- `.config/clash/` - 代理配置
- `.config/cmux/` - 本地多路复用配置

### 3. 恢复原始配置

如需撤销软链接：

```bash
# 1. 删除软链接
rm ~/.config/starship.toml
rm ~/.config/raycast
rm ~/.config/karabiner
rm ~/.config/ghostty
rm ~/.zshrc

# 2. 从备份恢复
cp -r ~/.config/backups-2026*/starship.toml ~/.config/
cp -r ~/.config/backups-2026*/raycast ~/.config/
# ... 其他配置
```

## 故障排除

### 软链接失效

```bash
# 检查软链接指向
ls -la ~/.config/starship.toml

# 如果指向不存在，重新运行 deploy.sh
./deploy.sh
```

### 权限问题

```bash
# 确保脚本可执行
chmod +x deploy.sh
```

## 参考文档

- [ohmyzsh-to-starship-zap-migration.md](./references/ohmyzsh-to-starship-zap-migration.md) - Zsh 迁移指南
- [symlink-config-guide.md](./references/symlink-config-guide.md) - 软链接配置参考
