# ============================================================================
# Zap 插件管理器配置
# ============================================================================

# 初始化 Zap
[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh" ] && source "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh"

# 插件配置
# zsh-autosuggestions: 根据历史命令自动建议补全
# zsh-syntax-highlighting: 命令语法高亮显示
# supercharge: 提供额外的 zsh 功能增强
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
# 开发环境配置 - Java
# ============================================================================

# Java 主目录：使用 Zulu OpenJDK 8
export JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
# 其他 JDK 版本备选：
# export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk1.8.0_311.jdk/Contents/Home
# export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk1.8.0_201.jdk/Contents/Home
# export JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-16.jdk/Contents/Home
# export JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-18.jdk/Contents/Home
# export JAVA_HOME=/opt/homebrew/opt/openjdk@21

# Maven 主目录：Java 项目构建工具
export MAVEN_HOME=/opt/homebrew/Cellar/maven/3.9.11
export PATH=$PATH:$MAVEN_HOME/bin
# 旧版 Maven 路径：
# export MAVEN_HOME=/opt/maven/apache-maven-3.9.1


# ============================================================================
# 开发环境配置 - 数据库
# ============================================================================

# MySQL 主目录配置
export MYSQL_HOME=/usr/local/mysql

# MySQL 5.7 版本路径（通过 Homebrew 安装）
export PATH="/opt/homebrew/opt/mysql@5.7/bin:$PATH"

# MySQL 5.7 快捷命令别名
alias mysql5=$MYSQL_HOME/bin/mysql


# ============================================================================
# 开发环境配置 - Python
# ============================================================================

# Anaconda Python 发行版路径
export PATH="/opt/homebrew/anaconda3/bin:$PATH"


# ============================================================================
# 开发环境配置 - Node.js
# ============================================================================

# 禁用 Node.js 警告信息输出
export NODE_NO_WARNINGS=1


# ============================================================================
# 开发工具配置 - JetBrains IDEs
# ============================================================================

# JetBrains IDE 命令行工具路径
export JET_SHELL="/Users/fufangjie/Documents/Shell/jetbrains_shell"

# IntelliJ IDEA 命令行启动别名
alias idea=$JET_SHELL/idea

# Fleet 编辑器命令行启动别名
alias fleet=$JET_SHELL/fleet

# PyCharm 命令行启动别名
alias py=$JET_SHELL/pycharm


# ============================================================================
# 自定义环境变量
# ============================================================================

# Shell 脚本目录
export S="/Users/fufangjie/Documents/Shell"

# 临时文件目录
export T="/Users/fufangjie/Documents/tmp"

# Neovim 配置目录
export NEO_VIM="/Users/fufangjie/.config/nvim/"

# 职业技能学习资料目录
export V_S=/Users/fufangjie/Documents/Learn/vocational_skills


# ============================================================================
# 目录导航别名
# ============================================================================

# 快速切换到公司 Java 项目目录
alias cc='cd /Users/fufangjie/Company/JavaProjects'

# 快速切换到个人项目目录
alias cm='cd /Users/fufangjie/MyProjects'

# 快速切换到 Documents 目录
alias cdd='cd /Users/fufangjie/Documents'

# 快速切换到 Neovim 配置目录
alias cn='cd $NEO_VIM'

# 快速切换到 Shell 脚本目录
alias cs='cd $S'

# 快速切换到临时文件目录
alias ct='cd $T'

# 快速切换到 Go 项目目录
alias cg='cd /Users/fufangjie/MyProjects/go_project'

# 快速切换到 Rust 项目目录
alias cr='cd /Users/fufangjie/MyProjects/rust_project'

# 快速切换到 Java 项目目录
alias cj='cd /Users/fufangjie/MyProjects/java_project'

# 快速切换到学习资料目录
alias cll='cd /Users/fufangjie/Documents/Learn'

# 执行学习目录跳转脚本
alias cl='source $S/goto_learn.sh'


# ============================================================================
# 编辑器别名
# ============================================================================

# 使用 Neovim 替代 vim
alias vim='nvim'

# 使用 Neovim 替代 vi
alias vi='nvim'

# 编辑 JSON 文件快捷命令
alias ej='source $S/edit_file.sh json'

# 编辑文本文件快捷命令
alias et='source $S/edit_file.sh txt'

# 编辑 Markdown 文件快捷命令
alias em='source $S/edit_file.sh md'

# 编辑 Lua 文件快捷命令
alias el='source $S/edit_file.sh lua'

# 编辑 Shell 脚本快捷命令
alias es='source $S/edit_file.sh sh'


# ============================================================================
# Git 版本控制别名
# ============================================================================

# Git 提交脚本快捷命令（交互式提交）
alias gcm='source $S/commit.sh'

# Git 提交脚本快捷命令（直接提交）
alias gcmf='source $S/commit.sh real_commit'

# Git 切换分支快捷命令
alias gc='git checkout'

# Git 查看状态快捷命令
alias gs="git status"


# ============================================================================
# 终端工具别名
# ============================================================================

# Tmux 终端复用器快捷启动
alias t='tmux'

# Tree 命令指定层级显示
alias tl='tree -L'

# macOS 系统剪贴板复制命令
alias pc='pbcopy'

# macOS 系统剪贴板粘贴命令
alias pp='pbpaste'


# ============================================================================
# 自定义脚本别名
# ============================================================================

# 格式化日期脚本
alias sd='source $S/format_date.sh'

# 翻译为中文脚本
alias tt='source $S/tran.sh zh'

# 翻译为英文脚本
alias te='source $S/tran.sh en'


# ============================================================================
# 文件管理工具 - Yazi
# ============================================================================

# Yazi 文件管理器快捷启动
alias y='yazi'

# Yazi 增强函数：退出时自动切换到浏览的目录
function yy() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}


# ============================================================================
# 目录跳转工具 - Z
# ============================================================================

# Z 命令：智能目录跳转工具，根据访问频率快速切换目录
source /opt/homebrew/Cellar/z/1.9/etc/profile.d/z.sh

# Z 列表命令：显示所有记录的目录及权重
alias zl='z -l'


# ============================================================================
# AI 工具配置 - CatPaw
# ============================================================================

# CatPaw CLI 工具路径
export PATH="/Users/fufangjie/.catpaw/bin:$PATH"

# CatPaw 代码模式基础命令
alias mtc="mc --code"

# CatPaw 代码模式（跳过权限检查）
alias mtcc="/usr/local/bin/mc --code --dangerously-skip-permissions --model Claude-Opus-4.5"
# alias mtcc="/usr/local/bin/mc --code --dangerously-skip-permissions"

# CatPaw CLI 不同 AI 模型别名
# 参考文档: https://km.sankuai.com/collabpage/2723617394

# LongCat Flash Chat 模型
alias mcl="mc --code --dangerously-skip-permissions --model LongCat-Flash-Chat"

# Qwen3 Coder FP8 模型（美团版）
alias mcq="mc --code --dangerously-skip-permissions --model qwen3-coder-fp8-meituan"

# DeepSeek V3.1 模型（美团版）
alias mcd="mc --code --dangerously-skip-permissions --model deepseek-v31-meituan"

# Kimi K2 预览版模型
alias mck="mc --code --dangerously-skip-permissions --model kimi-k2-0905-preview"

# GLM-4.7 模型
alias mcg="mc --code --dangerously-skip-permissions --model glm-4.7"

# DeepSeek Chat 模型
alias mcdc="mc --code --dangerously-skip-permissions --model deepseek-chat"

# MiniMax M2 模型
alias mcm="mc --code --dangerously-skip-permissions --model MiniMax-M2.7"

# kimi-k2.5
alias mck="mc --code --dangerously-skip-permissions --model kimi-k2.5"

# gpt
alias mcgp="mc --code --dangerously-skip-permissions --model gpt-5.4"



# ============================================================================
# 键盘绑定配置
# ============================================================================

# 禁用 Ctrl+D 快捷键（防止误触退出终端）
bindkey -r "^D"

# Vim 模式编辑配置（已注释，需要时可取消注释启用）
# 参考文档: http://bolyai.cs.elte.hu/zsh-manual/zsh_14.html
# bindkey -v
# bindkey -M vicmd "H" vi-beginning-of-line
# bindkey -M vicmd "L" vi-end-of-line
# bindkey -M vicmd "k" history-beginning-search-backward
# bindkey -M vicmd "j" history-beginning-search-forward
# bindkey -M viins "jk" vi-cmd-mode

# Vim 模式下光标形状切换函数（已注释）
# function zle-keymap-select {
#   if [[ ${KEYMAP} == vicmd ]] ||
#      [[ $1 = 'block' ]]; then
#     echo -ne '\e[1 q'
#
#   elif [[ ${KEYMAP} == main ]] ||
#        [[ ${KEYMAP} == viins ]] ||
#        [[ ${KEYMAP} = '' ]] ||
#        [[ $1 = 'beam' ]]; then
#     echo -ne '\e[5 q'
#   fi
# }
# zle -N zle-keymap-select
# echo -ne '\e[5 q'
# preexec() {
#    echo -ne '\e[5 q'
# }


# ============================================================================
# 外部工具和包管理器
# ============================================================================

# 本地 bin 目录环境配置
. "$HOME/.local/bin/env"
export PATH="$HOME/.local/bin:$PATH"

# GG 应用程序命令行工具路径
export PATH="/Applications/gg.app/Contents/MacOS:$PATH"
# alias gg='/Applications/gg.app/Contents/MacOS/gg &'

# SDKMAN 软件开发工具包管理器（必须放在文件末尾）
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# MOA 扩展配置加载
source ~/.moaextrc


alias la='ls -alh'
