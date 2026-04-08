#!/bin/bash

# =============================================================================
# Mac 开发环境一键安装脚本
# =============================================================================
# 安装内容:
#   - Homebrew (包管理器)
#   - Raycast (快捷启动)
#   - Google Chrome (浏览器)
#   - Microsoft Edge (浏览器)
#   - Snipaste (截图/贴图工具)
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

# 检查文件中是否已包含某行
file_contains() {
    local file="$1"
    local pattern="$2"
    [[ -f "$file" ]] && grep -q "$pattern" "$file" 2>/dev/null
}

# 安全追加配置（避免重复）
safe_append_config() {
    local file="$1"
    local content="$2"
    local pattern="${3:-$content}"

    if [[ ! -f "$file" ]]; then
        touch "$file"
    fi

    if ! file_contains "$file" "$pattern"; then
        # 确保文件以换行符结尾
        [[ -s "$file" && "$(tail -c1 "$file" | wc -l)" -eq 0 ]] && echo "" >> "$file"
        echo "$content" >> "$file"
        return 0
    fi
    return 1
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
        safe_append_config ~/.zprofile 'eval "$(/opt/homebrew/bin/brew shellenv)"' "brew shellenv"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        # Intel Mac
        safe_append_config ~/.zprofile 'eval "$(/usr/local/bin/brew shellenv)"' "brew shellenv"
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    log_success "Homebrew 安装完成"
}

# =============================================================================
# 2. 安装 Raycast
# =============================================================================
install_raycast() {
    log_info "检查 Raycast..."
    local was_installed=false

    if [[ -d "/Applications/Raycast.app" ]]; then
        log_success "Raycast 已安装"
        was_installed=true
    else
        log_info "正在安装 Raycast..."
        brew install --cask raycast
        log_success "Raycast 安装完成"
    fi

    # 导入配置文件
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_file="${script_dir}/raycast_config.rayconfig"

    if [[ -f "$config_file" ]]; then
        log_info "导入 Raycast 配置..."
        # Raycast 配置导入命令（使用密码 fufangjie）
        if open -a Raycast "$config_file" 2>/dev/null; then
            log_success "Raycast 配置导入已启动"
            log_info "请在弹出的窗口中输入密码: fufangjie"
        else
            log_warn "无法自动导入配置，请手动导入: $config_file"
            log_info "配置文件密码: fufangjie"
        fi
    else
        log_warn "未找到配置文件: $config_file"
    fi
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
# 5. 安装 Snipaste
# =============================================================================
install_snipaste() {
    log_info "检查 Snipaste..."
    if [[ -d "/Applications/Snipaste.app" ]]; then
        log_success "Snipaste 已安装"
        return 0
    fi

    log_info "正在安装 Snipaste..."
    brew install --cask snipaste
    log_success "Snipaste 安装完成"
    log_info "Snipaste 是一个强大的截图/贴图工具"
    log_info "启动后可配置快捷键: F1 截图, F3 贴图"
}

# =============================================================================
# 6. 安装 Karabiner-Elements
# =============================================================================
install_karabiner() {
    log_info "检查 Karabiner-Elements..."
    local need_restart=false

    if [[ -d "/Applications/Karabiner-Elements.app" ]]; then
        log_success "Karabiner-Elements 已安装"
    else
        log_info "正在安装 Karabiner-Elements..."
        brew install --cask karabiner-elements
        log_success "Karabiner-Elements 安装完成"
        need_restart=true
    fi

    # 导入配置文件
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_file="${script_dir}/karabiner_config.json"

    if [[ -f "$config_file" ]]; then
        log_info "导入 Karabiner-Elements 配置..."
        mkdir -p "$HOME/.config/karabiner"
        cp "$config_file" "$HOME/.config/karabiner/karabiner.json"
        log_success "Karabiner-Elements 配置已导入"
        need_restart=true
    else
        log_warn "未找到配置文件: $config_file"
    fi

    if $need_restart; then
        log_warn "请手动打开 Karabiner-Elements 并授予必要的权限"
        log_warn "配置导入后可能需要重启 Karabiner-Elements 生效"
    fi
}

# =============================================================================
# 7. 安装 Git
# =============================================================================
install_git() {
    log_info "检查 Git..."
    if check_command git; then
        log_success "Git 已安装: $(git --version)"
        return 0
    fi

    log_info "正在安装 Git..."
    brew install git
    log_success "Git 安装完成"

    # 配置 Git 默认设置（无论是否新安装都执行）
    log_info "配置 Git 默认设置..."
    git config --global init.defaultBranch main
    git config --global core.editor nvim
    log_success "Git 配置完成"
}

# =============================================================================
# 8. 安装 Ghostty
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
# 9. 配置 Neovim 环境
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

    # 安装 pynvim（检查 pip3 是否存在）
    if ! check_command pip3; then
        log_warn "pip3 未找到，尝试安装..."
        python3 -m ensurepip --user 2>/dev/null || {
            log_error "无法安装 pip3，请手动安装"
            exit 1
        }
    fi
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
# 10. 配置 Ghostty (从 vim-config 仓库)
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
# 11. 配置 Zsh (可选)
# =============================================================================
setup_zsh() {
    log_info "配置 Zsh..."

    # 安装 oh-my-zsh (如果未安装)
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        log_info "安装 Oh My Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi

    # 添加常用别名到 .zshrc
    log_info "添加别名和配置到 .zshrc..."

    # 使用安全追加函数添加配置块
    local config_block=''
    config_block+=$'\n# ============================================\n'
    config_block+=$'# 自定义配置（由 mac-setup.sh 添加）\n'
    config_block+=$'# ============================================\n'
    config_block+=$'\n'
    config_block+=$'# 编辑器设置\n'
    config_block+=$'export EDITOR=\'nvim\'\n'
    config_block+=$'alias vi=\'nvim\'\n'
    config_block+=$'alias vim=\'nvim\'\n'
    config_block+=$'\n'
    config_block+=$'# 常用别名\n'
    config_block+=$'alias ll=\'ls -alF\'\n'
    config_block+=$'alias la=\'ls -A\'\n'
    config_block+=$'alias l=\'ls -CF\'\n'
    config_block+=$'alias ..=\'cd ..\'\n'
    config_block+=$'alias ...=\'cd ../..\'\n'
    config_block+=$'\n'
    config_block+=$'# Git 别名\n'
    config_block+=$'alias gs=\'git status\'\n'
    config_block+=$'alias ga=\'git add\'\n'
    config_block+=$'alias gc=\'git commit\'\n'
    config_block+=$'alias gp=\'git push\'\n'
    config_block+=$'alias gl=\'git pull\'\n'
    config_block+=$'alias gd=\'git diff\'\n'
    config_block+=$'\n'
    config_block+=$'# 快速编辑配置\n'
    config_block+=$'alias zshrc=\'${EDITOR} ~/.zshrc\'\n'
    config_block+=$'alias vimrc=\'${EDITOR} ~/.config/nvim/init.lua\'\n'
    config_block+=$'\n'
    config_block+=$'# Homebrew 路径 (Apple Silicon)\n'
    config_block+=$'if [[ -f "/opt/homebrew/bin/brew" ]]; then\n'
    config_block+=$'    eval "$(/opt/homebrew/bin/brew shellenv)"\n'
    config_block+=$'fi\n'

    # 检查是否已添加过配置
    if ! file_contains ~/.zshrc "由 mac-setup.sh 添加"; then
        [[ -f ~/.zshrc ]] || touch ~/.zshrc
        [[ -s ~/.zshrc && "$(tail -c1 ~/.zshrc | wc -l)" -eq 0 ]] && echo "" >> ~/.zshrc
        echo "$config_block" >> ~/.zshrc
        log_success "Zsh 配置已添加"
    else
        log_warn "Zsh 配置已存在，跳过添加"
    fi

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

    # 管理员权限检查
    log_info "检查管理员权限..."
    if ! sudo -n true 2>/dev/null; then
        log_warn "某些安装步骤需要管理员权限，可能会提示输入密码"
        log_warn "如需提前授权，请执行: sudo -v"
        echo ""
    fi

    # 安全警告
    log_warn "安全提示: 本脚本会从网络下载并执行 Homebrew 和 Oh My Zsh 安装脚本"
    log_warn "请确保您信任这些来源:"
    log_warn "  - https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
    log_warn "  - https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
    echo ""
    read -p "是否继续? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "已取消安装"
        exit 0
    fi
    echo ""

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

    install_snipaste
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
    echo "配置文件导入提示:"
    echo "  - Raycast 配置密码: fufangjie"
    echo "  - 如未自动导入，可手动导入脚本目录中的:"
    echo "    - raycast_config.rayconfig"
    echo "    - karabiner_config.json"
    echo ""
    echo "常用命令:"
    echo "  nvim    - 启动编辑器"
    echo "  ghostty - 启动终端"
    echo ""
}

# 运行主函数
main
