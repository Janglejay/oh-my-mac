#!/bin/zsh
# =============================================================================
# Dotfiles 部署脚本
# =============================================================================
# 用途: 在新设备上快速部署配置文件
# 用法: ./deploy.sh
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 路径配置
REPO_DIR="${HOME}/.vim"
CONFIG_DIR="${HOME}/.config"
BACKUP_DIR="${CONFIG_DIR}/backups-$(date +%Y%m%d-%H%M%S)"

# 打印函数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查仓库是否存在
check_repo() {
    if [ ! -d "$REPO_DIR" ]; then
        print_error "仓库目录不存在: $REPO_DIR"
        echo "请先克隆仓库:"
        echo "  git clone git@github.com:Janglejay/vim-config.git ~/.vim"
        exit 1
    fi
    print_success "仓库目录存在: $REPO_DIR"
}

# 创建备份
create_backup() {
    print_info "创建配置备份..."
    mkdir -p "$BACKUP_DIR"

    local items=("starship.toml" "raycast" "karabiner" "ghostty")
    for item in "${items[@]}"; do
        if [ -e "$CONFIG_DIR/$item" ] && [ ! -L "$CONFIG_DIR/$item" ]; then
            cp -r "$CONFIG_DIR/$item" "$BACKUP_DIR/" 2>/dev/null || true
            print_warning "已备份: $item"
        fi
    done

    print_success "备份完成: $BACKUP_DIR"
}

# 创建软链接
create_symlink() {
    local src="$1"
    local dst="$2"
    local name="$3"

    if [ -L "$dst" ]; then
        # 如果已经是软链接，检查是否指向正确位置
        local current_target=$(readlink "$dst")
        if [ "$current_target" = "$src" ]; then
            print_success "$name 已正确链接"
            return 0
        else
            print_warning "$name 指向其他位置，重新链接"
            rm "$dst"
        fi
    elif [ -e "$dst" ]; then
        # 如果是普通文件/目录，备份后删除
        print_warning "$name 是普通文件，已备份并移除"
        rm -rf "$dst"
    fi

    # 创建软链接
    ln -sf "$src" "$dst"
    print_success "$name -> $src"
}

# 主部署流程
main() {
    echo "========================================"
    echo "  Dotfiles 部署脚本"
    echo "========================================"
    echo ""

    # 检查仓库
    check_repo

    # 创建备份
    create_backup

    # 确保 .config 目录存在
    mkdir -p "$CONFIG_DIR"

    echo ""
    print_info "开始创建软链接..."
    echo ""

    # 创建各配置的软链接
    create_symlink "$REPO_DIR/.config/starship.toml" "$CONFIG_DIR/starship.toml" "starship.toml"
    create_symlink "$REPO_DIR/.config/raycast" "$CONFIG_DIR/raycast" "raycast"
    create_symlink "$REPO_DIR/.config/karabiner" "$CONFIG_DIR/karabiner" "karabiner"
    create_symlink "$REPO_DIR/.config/ghostty" "$CONFIG_DIR/ghostty" "ghostty"
    create_symlink "$REPO_DIR/.config/nvim" "$CONFIG_DIR/nvim" "nvim"

    echo ""
    echo "========================================"
    print_success "部署完成！"
    echo "========================================"
    echo ""
    echo "注意: .zshrc 不通过软链接管理，请手动同步"
    echo ""
    echo "请执行以下操作："
    echo "  1. 安装必要工具: brew install starship"
    echo "  2. 验证配置: starship --version"
    echo ""
    echo "备份位置: $BACKUP_DIR"
}

# 执行主函数
main "$@"
