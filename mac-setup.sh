#!/bin/bash

# =============================================================================
# Mac 开发环境一键安装脚本
# =============================================================================
# 安装内容:
#   - Homebrew (包管理器)
#   - Raycast (快捷启动)
#   - Google Chrome (浏览器)
#   - Microsoft Edge (浏览器)
#   - Karabiner-Elements (键盘映射)
#   - Git (版本控制)
#   - Ghostty (终端)
#   - Neovim + 配置 (编辑器)
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查命令是否存在
check_command() {
    command -v "$1" &> /dev/null
}

# =============================================================================
# 1. 安装 Homebrew
# =============================================================================
install_homebrew() {
    log_info "检查 Homebrew..."
    if check_command brew; then
        log_success "Homebrew 已安装: $(brew --version | head -n1)"
        return 0
    fi

    log_info "正在安装 Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # 配置环境变量
    if [[ $(uname -m) == "arm64" ]]; then
        # Apple Silicon Mac
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        # Intel Mac
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    log_success "Homebrew 安装完成"
}

# =============================================================================
# 2. 安装 Raycast
# =============================================================================
install_raycast() {
    log_info "检查 Raycast..."
    if [[ -d "/Applications/Raycast.app" ]]; then
        log_success "Raycast 已安装"
        return 0
    fi

    log_info "正在安装 Raycast..."
    brew install --cask raycast
    log_success "Raycast 安装完成"
}

# =============================================================================
# 3. 安装 Chrome
# =============================================================================
install_chrome() {
    log_info "检查 Google Chrome..."
    if [[ -d "/Applications/Google Chrome.app" ]]; then
        log_success "Google Chrome 已安装"
        return 0
    fi

    log_info "正在安装 Google Chrome..."
    brew install --cask google-chrome
    log_success "Google Chrome 安装完成"
}

# =============================================================================
# 4. 安装 Edge
# =============================================================================
install_edge() {
    log_info "检查 Microsoft Edge..."
    if [[ -d "/Applications/Microsoft Edge.app" ]]; then
        log_success "Microsoft Edge 已安装"
        return 0
    fi

    log_info "正在安装 Microsoft Edge..."
    brew install --cask microsoft-edge
    log_success "Microsoft Edge 安装完成"
}

# =============================================================================
# 5. 安装 Karabiner-Elements
# =============================================================================
install_karabiner() {
    log_info "检查 Karabiner-Elements..."
    if [[ -d "/Applications/Karabiner-Elements.app" ]]; then
        log_success "Karabiner-Elements 已安装"
        return 0
    fi

    log_info "正在安装 Karabiner-Elements..."
    brew install --cask karabiner-elements
    log_success "Karabiner-Elements 安装完成"
    log_warn "请手动打开 Karabiner-Elements 并授予必要的权限"
}

# =============================================================================
# 6. 安装 Git
# =============================================================================
install_git() {
    log_info "检查 Git..."
    if check_command git; then
        log_success "Git 已安装: $(git --version)"
        return 0
    fi

    log_info "正在安装 Git..."
    brew install git

    # 配置 Git 默认设置
    git config --global init.defaultBranch main
    git config --global core.editor nvim

    log_success "Git 安装完成"
}

# =============================================================================
# 7. 安装 Ghostty
# =============================================================================
install_ghostty() {
    log_info "检查 Ghostty..."
    if check_command ghostty; then
        log_success "Ghostty 已安装"
        return 0
    fi

    log_info "正在安装 Ghostty..."
    brew install --cask ghostty
    log_success "Ghostty 安装完成"
}

# =============================================================================
# 8. 配置 Neovim 环境
# =============================================================================
setup_nvim() {
    log_info "检查 Neovim..."

    # 安装 Neovim
    if ! check_command nvim; then
        log_info "正在安装 Neovim..."
        brew install neovim
        log_success "Neovim 安装完成"
    else
        log_success "Neovim 已安装: $(nvim --version | head -n1)"
    fi

    # 安装依赖工具
    log_info "安装 Neovim 依赖..."
    brew install ripgrep fd lazygit node python

    # 安装 pynvim
    pip3 install --user pynvim

    # 备份旧配置
    if [[ -d "$HOME/.config/nvim" ]]; then
        log_warn "发现旧版 nvim 配置，备份到 ~/.config/nvim.backup.$(date +%Y%m%d%H%M%S)"
        mv "$HOME/.config/nvim" "$HOME/.config/nvim.backup.$(date +%Y%m%d%H%M%S)"
    fi

    # 克隆配置仓库
    log_info "克隆 nvim 配置文件..."
    git clone https://github.com/Janglejay/vim-config.git "$HOME/.config/nvim"

    log_success "Neovim 配置完成"
    log_info "首次启动 nvim 时会自动下载插件，请耐心等待..."
}

# =============================================================================
# 9. 配置 Ghostty (从 vim-config 仓库)
# =============================================================================
setup_ghostty_config() {
    log_info "配置 Ghostty..."

    # 确保配置目录存在
    mkdir -p "$HOME/.config/ghostty"

    # 如果仓库中有 ghostty 配置，创建软链接或复制
    if [[ -f "$HOME/.config/nvim/ghostty/config" ]]; then
        cp "$HOME/.config/nvim/ghostty/config" "$HOME/.config/ghostty/config"
        log_success "Ghostty 配置已复制"
    elif [[ -f "$HOME/.config/nvim/ghostty/ghostty.conf" ]]; then
        cp "$HOME/.config/nvim/ghostty/ghostty.conf" "$HOME/.config/ghostty/config"
        log_success "Ghostty 配置已复制"
    else
        log_warn "未在 vim-config 仓库中找到 ghostty 配置，使用默认配置"
    fi
}

# =============================================================================
# 10. 配置 Zsh (可选)
# =============================================================================
setup_zsh() {
    log_info "配置 Zsh..."

    # 安装 oh-my-zsh (如果未安装)
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        log_info "安装 Oh My Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi

    # 添加常用别名到 .zshrc
    cat >> ~/.zshrc << 'EOF'

# ============================================
# 自定义配置
# ============================================

# 编辑器设置
export EDITOR='nvim'
alias vi='nvim'
alias vim='nvim'

# 常用别名
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'

# Git 别名
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'

# 快速编辑配置
alias zshrc='${EDITOR} ~/.zshrc'
alias vimrc='${EDITOR} ~/.config/nvim/init.lua'

# Homebrew 路径 (Apple Silicon)
if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi
EOF

    log_success "Zsh 配置完成"
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    echo "=========================================="
    echo "   Mac 开发环境一键安装脚本"
    echo "=========================================="
    echo ""

    # 检查系统
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_error "此脚本仅适用于 macOS"
        exit 1
    fi

    log_info "开始安装，这可能需要一些时间..."
    echo ""

    # 执行安装步骤
    install_homebrew
    echo ""

    install_raycast
    echo ""

    install_chrome
    echo ""

    install_edge
    echo ""

    install_karabiner
    echo ""

    install_git
    echo ""

    install_ghostty
    echo ""

    setup_nvim
    echo ""

    setup_ghostty_config
    echo ""

    setup_zsh
    echo ""

    # 完成提示
    echo "=========================================="
    log_success "所有安装完成！"
    echo "=========================================="
    echo ""
    echo "请执行以下操作:"
    echo ""
    echo "1. 重启终端或执行: source ~/.zshrc"
    echo "2. 启动 nvim，等待插件自动安装完成"
    echo "3. 打开 Karabiner-Elements 并授予权限"
    echo "4. 配置 Raycast 替换 Spotlight (Cmd+Space)"
    echo ""
    echo "常用命令:"
    echo "  nvim    - 启动编辑器"
    echo "  ghostty - 启动终端"
    echo ""
}

# 运行主函数
main
