#!/bin/bash

# ==============================================================================
# Plex Media Server 自动更新脚本 (专为 Debian/Ubuntu 设计) - v1.2
#
# 功能:
# 1. 优先让用户提供直接的 .deb 下载链接 (推荐用于 Beta/Plex Pass 版本)。
# 2. 如果没有直接链接，允许用户手动输入版本号，脚本尝试构建标准下载链接。
# 3. 下载指定的 .deb 安装包。
# 4. 可选：对下载的 .deb 包进行 SHA1 校验和验证。
# 5. 使用 dpkg 安装 Plex Media Server。
# 6. 重启 plexmediaserver 服务 (带有超时和状态检查)。
# 7. 清理下载的安装包和 SHA1 文件 (包括下载失败的SHA1文件)。
# 8. 在脚本末尾输出最终的服务状态 (使用更清晰的颜色高亮)。
#
# 使用方法:
# 1. 根据需要修改下面的 `ARCHITECTURE` 和重启超时相关配置。
#    (此版本默认 ARCHITECTURE 已修改为 "arm64")
# 2. 确保 'wget', 'dpkg', 'systemctl', 'sha1sum', 'awk', 'grep', 'sed', 'timeout', 'basename' 已安装:
#    `sudo apt-get update && sudo apt-get install wget dpkg systemctl coreutils findutils procps`
# 3. 保存此脚本为例如 `update_plex.sh`。
# 4. 赋予执行权限: `chmod +x update_plex.sh`。
# 5. 运行脚本: `sudo ./update_plex.sh` (需要 sudo 权限来安装和重启服务)。
#
# 变更日志:
# v1.2: 无论SHA1文件下载是否成功，都尝试删除本地SHA1文件。
#       调整最终服务状态输出，使用更直接和鲜明的颜色高亮。
# v1.1: 将默认 ARCHITECTURE 修改为 "arm64"。
# ==============================================================================

# --- 配置 ---
ARCHITECTURE="arm64" # 目标架构，例如 amd64, arm64
SERVICE_NAME="plexmediaserver.service" # Plex 服务名称

# Plex 下载相关 (主要用于无直接链接时构建URL)
PLEX_DOWNLOAD_BASE_URL="https://downloads.plex.tv/plex-media-server-new"

# systemctl restart 的超时时间
RESTART_COMMAND_TIMEOUT="180s" # 例如: 60s, 120s, 180s
# 服务激活状态检查的总等待时间 (在 restart 命令后)
POST_RESTART_CHECK_TOTAL_WAIT_SECONDS=60
# 服务激活状态检查的间隔时间
POST_RESTART_CHECK_INTERVAL_SECONDS=10


# --- 助手函数 ---
# 打印信息 (输出到 stderr)
info() {
    echo -e "\033[0;32m[信息]\033[0m $1" >&2
}

# 打印错误 (输出到 stderr)
error() {
    echo -e "\033[0;31m[错误]\033[0m $1" >&2
}

# 打印警告 (输出到 stderr)
warning() {
    echo -e "\033[0;33m[警告]\033[0m $1" >&2
}

# --- 主要功能函数 ---

# --- 脚本主逻辑 ---
main() {
    info "Plex Media Server 更新脚本 for ${ARCHITECTURE} (v1.2)"
    info "-----------------------------------------------------------------"

    if [ "$(id -u)" -ne 0 ]; then
        error "此脚本需要以 root 或 sudo 权限运行。"
        error "请尝试: sudo $0"
        exit 1
    fi

    # 检查必需的命令
    local missing_cmds=0
    for cmd in wget dpkg systemctl grep sed awk timeout sha1sum basename; do
        if ! command -v $cmd &> /dev/null; then
            error "必需命令 '$cmd' 未找到。请先安装它。"
            missing_cmds=$((missing_cmds + 1))
        fi
    done
    if [ $missing_cmds -gt 0 ]; then
        error "请安装缺失的依赖后再运行脚本。"
        error "您可以尝试: sudo apt-get update && sudo apt-get install wget dpkg systemctl coreutils procps findutils"
        exit 1
    fi

    local PLEX_VERSION_FULL # 例如 1.32.8.7639-fb6452ebf
    local DOWNLOAD_URL
    local DEB_FILENAME
    local ARCH_TO_USE="$ARCHITECTURE" # 默认为配置的架构

    info "由于 Plex Beta/Plex Pass 版本的下载链接通常需要登录，"
    info "此脚本建议您直接提供 .deb 包的下载链接。"
    echo >&2

    read -p "您有 Plex Media Server .deb 包的直接下载链接吗? (y/N): " has_direct_url

    if [[ "$has_direct_url" == "y" || "$has_direct_url" == "Y" ]]; then
        while true; do
            read -p "请输入 .deb 包的直接下载链接: " direct_url_input
            if [[ -z "$direct_url_input" ]]; then
                error "下载链接不能为空。请重试。"
                continue
            fi
            DOWNLOAD_URL="$direct_url_input"
            DEB_FILENAME=$(basename "$DOWNLOAD_URL") # 从URL中提取文件名

            # 尝试从文件名解析版本和架构，例如: plexmediaserver_1.23.4.5678-abcdef_amd64.deb
            if [[ "$DEB_FILENAME" =~ ^plexmediaserver_([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9a-fA-F]+)_([^_]+)\.deb$ ]]; then
                PLEX_VERSION_FULL="${BASH_REMATCH[1]}"
                local ARCH_FROM_FILENAME="${BASH_REMATCH[2]}"
                info "从文件名 '$DEB_FILENAME' 中解析得到:"
                info "  版本: $PLEX_VERSION_FULL"
                info "  架构: $ARCH_FROM_FILENAME"

                if [ "$ARCH_FROM_FILENAME" != "$ARCHITECTURE" ]; then
                    warning "从文件名解析的架构 '$ARCH_FROM_FILENAME' 与脚本配置的默认架构 '$ARCHITECTURE' 不同。"
                    read -p "要使用文件名中的架构 '$ARCH_FROM_FILENAME' 吗? (y/N, N 将使用配置的 '$ARCHITECTURE'): " use_parsed_arch
                    if [[ "$use_parsed_arch" == "y" || "$use_parsed_arch" == "Y" ]]; then
                        ARCH_TO_USE="$ARCH_FROM_FILENAME"
                        info "将使用架构: $ARCH_TO_USE"
                    else
                        ARCH_TO_USE="$ARCHITECTURE" # 坚持使用配置的架构
                        info "将继续使用配置的架构: $ARCH_TO_USE. 请确保下载链接确实对应此架构。"
                    fi
                else # 解析出的架构与配置的架构相同
                    ARCH_TO_USE="$ARCH_FROM_FILENAME" # 一致，使用解析出的架构
                    info "文件名中的架构 '$ARCH_FROM_FILENAME' 与配置的默认架构 '$ARCHITECTURE' 一致。"
                fi
                break
            else
                warning "无法从文件名 '$DEB_FILENAME' 自动解析版本和架构。"
                warning "预期的文件名格式为 'plexmediaserver_VERSION-HASH_ARCH.deb'。"
                warning "例如: 'plexmediaserver_1.32.8.7639-fb6452ebf_arm64.deb'。"
                read -p "文件名格式似乎不标准。是否仍要使用此链接和文件名? (y/N): " continue_with_url
                if [[ "$continue_with_url" == "y" || "$continue_with_url" == "Y" ]]; then
                    PLEX_VERSION_FULL="unknown" # 标记版本为未知
                    ARCH_TO_USE="$ARCHITECTURE" # 依赖配置的架构
                    warning "将继续使用提供的链接。版本号标记为未知，架构将使用配置的 '$ARCH_TO_USE'。"
                    warning "某些版本比较（如降级检查）可能无法准确执行。"
                    break
                fi
                # 如果用户选择 'N'，则循环提示重新输入URL
            fi
        done
    else
        info "将尝试根据您输入的版本号和配置的架构 (${ARCHITECTURE}) 构建下载链接。"
        info "这主要适用于 Plex 的公开正式版本。"
        while true; do
            read -p "请输入您想要安装的 Plex 版本号 (例如 1.32.8.7639-fb6452ebf): " manual_version
            # 验证版本号格式 (数字.数字.数字.数字-十六进制串)
            if [[ "$manual_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9a-fA-F]+$ ]]; then
                PLEX_VERSION_FULL="$manual_version"
                ARCH_TO_USE="$ARCHITECTURE"
                DEB_FILENAME="plexmediaserver_${PLEX_VERSION_FULL}_${ARCH_TO_USE}.deb"
                DOWNLOAD_URL="${PLEX_DOWNLOAD_BASE_URL}/${PLEX_VERSION_FULL}/debian/${DEB_FILENAME}"
                info "您已手动指定版本: $PLEX_VERSION_FULL"
                info "构建的下载链接为: $DOWNLOAD_URL"
                warning "请注意: 此链接是基于标准 Plex 发布模式构建的。"
                warning "对于 Beta 或 Plex Pass 特定版本，此链接可能无效。"
                warning "如果下载失败，请尝试获取直接下载链接并重新运行脚本。"
                break
            else
                error "版本号格式不正确。应为 X.Y.Z.A-HASH (例如 1.32.8.7639-fb6452ebf)。"
                error "它应该包含四段数字，后跟一个连字符和一串十六进制字符。"
            fi
        done
    fi

    if [ -z "$DOWNLOAD_URL" ] || [ -z "$DEB_FILENAME" ]; then
        error "未能确定下载链接或文件名。脚本无法继续。"
        exit 1
    fi

    info "将要处理的版本 (如果已知): $PLEX_VERSION_FULL"
    info "目标架构: $ARCH_TO_USE"
    info "最终下载链接: $DOWNLOAD_URL"
    info "目标文件名: $DEB_FILENAME"
    echo >&2

    if [ -f "$DEB_FILENAME" ]; then
        read -p "文件 $DEB_FILENAME 已存在。是否重新下载? (y/N): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            info "删除已存在的文件 $DEB_FILENAME"
            if ! rm -f "$DEB_FILENAME"; then
                error "删除旧文件 $DEB_FILENAME 失败。请检查权限。"
                exit 1;
            fi
        else
            info "将使用已存在的本地文件 $DEB_FILENAME."
        fi
    fi

    if [ ! -f "$DEB_FILENAME" ]; then
        info "正在下载 $DEB_FILENAME..."
        wget -O "$DEB_FILENAME" "$DOWNLOAD_URL"
        if [ $? -ne 0 ]; then
            error "下载 $DEB_FILENAME 失败。请检查链接或网络。"
            rm -f "$DEB_FILENAME" 2>/dev/null # 尝试删除下载失败的文件
            exit 1
        fi
        info "下载完成: $DEB_FILENAME"
    fi
    echo >&2

    local sha1_url="${DOWNLOAD_URL}.sha1"
    local sha1_filename_local="${DEB_FILENAME}.sha1"
    info "正在尝试下载 SHA1 校验文件: ${sha1_filename_local}"
    if wget -qO "$sha1_filename_local" "$sha1_url"; then
        info "SHA1 文件下载完成: $sha1_filename_local"
        local expected_sha1=$(awk '{print $1}' "$sha1_filename_local")
        if [ -z "$expected_sha1" ]; then
            warning "无法从 $sha1_filename_local 中提取预期的 SHA1 校验和。将跳过校验。"
        else
            info "预期的 SHA1 校验和: $expected_sha1"
            info "正在计算下载文件 $DEB_FILENAME 的 SHA1 校验和..."
            local calculated_sha1=$(sha1sum "$DEB_FILENAME" | awk '{print $1}')
            if [ -z "$calculated_sha1" ]; then
                error "计算 $DEB_FILENAME 的 SHA1 校验和失败。"
                warning "建议删除文件并重试。将跳过校验。"
            else
                info "计算得到的 SHA1 校验和: $calculated_sha1"
                if [ "$expected_sha1" == "$calculated_sha1" ]; then
                    info "\033[1;32mSHA1 校验和匹配！文件完整性已验证。\033[0m"
                else
                    error "SHA1 校验和不匹配！文件可能已损坏或被篡改。"
                    error "预期: $expected_sha1"; error "得到: $calculated_sha1"
                    read -p "警告：校验和不匹配！是否仍然继续安装此文件? (y/N): " continue_anyway
                    if ! [[ "$continue_anyway" == "y" || "$continue_anyway" == "Y" ]]; then
                        info "安装已取消。请删除 $DEB_FILENAME 并重试下载。"
                        rm -f "$DEB_FILENAME" # 删除 .deb 文件
                        rm -f "$sha1_filename_local" 2>/dev/null # 删除 .sha1 文件
                        exit 1
                    fi
                    warning "用户选择继续安装可能已损坏的文件。"
                fi
            fi
        fi
        rm -f "$sha1_filename_local" 2>/dev/null # 成功下载并处理后，删除SHA1文件
    else
        warning "下载 SHA1 文件 $sha1_filename_local 失败 (链接: $sha1_url)。可能是此版本没有提供 SHA1 文件。将跳过校验。"
        rm -f "$sha1_filename_local" 2>/dev/null # 即使下载失败，也尝试删除可能创建的空/不完整SHA1文件
    fi
    echo >&2

    info "正在安装 $DEB_FILENAME..."
    current_installed_version=$(dpkg-query -W -f='${Version}' plexmediaserver 2>/dev/null || echo "not-installed")

    if [ "$PLEX_VERSION_FULL" != "unknown" ] && [ "$current_installed_version" != "not-installed" ]; then
        if dpkg --compare-versions "$PLEX_VERSION_FULL" "lt" "$current_installed_version"; then
            warning "注意：您将要安装的版本 ($PLEX_VERSION_FULL) 低于当前已安装的版本 ($current_installed_version)。"
            read -p "您确定要降级吗? (y/N): " confirm_downgrade
            if ! [[ "$confirm_downgrade" == "y" || "$confirm_downgrade" == "Y" ]]; then
                info "降级操作已取消。脚本退出。"
                # 在此不删除 .deb 文件，因为用户可能想手动操作
                exit 0
            fi
            info "用户确认降级。"
        fi
    elif [ "$PLEX_VERSION_FULL" == "unknown" ] && [ "$current_installed_version" != "not-installed" ]; then
        warning "无法自动确定要安装的软件包版本。无法执行自动降级检查。"
        warning "当前安装版本: $current_installed_version. 请自行确认是否要继续。"
        read -p "是否继续安装? (y/N): " continue_unknown_version
        if ! [[ "$continue_unknown_version" == "y" || "$continue_unknown_version" == "Y" ]]; then
            info "安装已取消。"
            exit 0
        fi
    fi

    if sudo dpkg -i "$DEB_FILENAME"; then
        info "Plex Media Server 安装/更新成功。"
        info "如果 dpkg 报告了依赖问题，它通常会给出解决建议。"
        info "您可以尝试运行 'sudo apt-get -f install' 来修复任何悬挂的依赖项。"
    else
        error "使用 dpkg 安装 $DEB_FILENAME 失败。"
        warning "这可能是由于缺少依赖。您可以尝试运行 'sudo apt-get update && sudo apt-get -f install' 来修复依赖问题，"
        warning "然后可以尝试重新运行此脚本 (选择不重新下载文件)，或手动安装 '$DEB_FILENAME'。"
    fi
    echo >&2

    info "正在尝试重启 $SERVICE_NAME 服务 (命令超时时间: ${RESTART_COMMAND_TIMEOUT})..."
    sudo timeout "$RESTART_COMMAND_TIMEOUT" systemctl restart "$SERVICE_NAME"
    restart_command_exit_code=$?

    if [ $restart_command_exit_code -eq 124 ]; then
        warning "systemctl restart $SERVICE_NAME 命令超时 (超过 ${RESTART_COMMAND_TIMEOUT})。"
        warning "这可能意味着服务停止或启动过程非常缓慢。将继续检查服务状态..."
    elif [ $restart_command_exit_code -ne 0 ]; then
        error "执行 systemctl restart $SERVICE_NAME 时遇到错误 (退出码: $restart_command_exit_code)。"
        warning "请尝试手动执行 'sudo systemctl restart $SERVICE_NAME' 并查看日志 'sudo journalctl -u $SERVICE_NAME'。"
    else
        info "$SERVICE_NAME 重启命令已成功发送。"
    fi

    info "开始检查服务激活状态 (总等待时间: ${POST_RESTART_CHECK_TOTAL_WAIT_SECONDS}s, 间隔: ${POST_RESTART_CHECK_INTERVAL_SECONDS}s)..."
    local checks_done=0
    local max_checks=$((POST_RESTART_CHECK_TOTAL_WAIT_SECONDS / POST_RESTART_CHECK_INTERVAL_SECONDS))
    local service_activated=false

    while [ $checks_done -lt $max_checks ]; do
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            info "$SERVICE_NAME 服务已成功启动并正在运行。"
            service_activated=true
            break
        else
            info "服务尚未激活，等待 ${POST_RESTART_CHECK_INTERVAL_SECONDS}秒 后重试... ($((checks_done + 1))/$max_checks)"
            sleep "$POST_RESTART_CHECK_INTERVAL_SECONDS"
        fi
        checks_done=$((checks_done + 1))
    done

    if [ "$service_activated" != true ]; then
        error "$SERVICE_NAME 服务在等待 ${POST_RESTART_CHECK_TOTAL_WAIT_SECONDS} 秒后仍未激活。"
        warning "请手动检查服务状态和日志:"
        warning "  sudo systemctl status $SERVICE_NAME --no-pager -l"
        warning "  sudo journalctl -u $SERVICE_NAME -e --no-pager"
    fi
    echo >&2

    if [ -f "$DEB_FILENAME" ]; then
        info "正在删除安装包 $DEB_FILENAME..."
        if rm -f "$DEB_FILENAME"; then
            info "安装包已成功删除。"
        else
            warning "删除 $DEB_FILENAME 失败。您可以手动删除它。"
        fi
    fi

    # --- 最终状态检查 ---
    info "-----------------------------------------------------------------"
    info "最终 Plex Media Server 服务状态确认:"
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "  \033[1;32m$SERVICE_NAME 服务当前状态: active (正在运行)\033[0m" >&2
    elif systemctl is-failed --quiet "$SERVICE_NAME"; then
        echo -e "  \033[1;31m$SERVICE_NAME 服务当前状态: failed (启动失败)\033[0m" >&2
        warning "  请使用 'sudo systemctl status $SERVICE_NAME --no-pager -l' 和 'sudo journalctl -u $SERVICE_NAME -e --no-pager' 查看详情。"
    else
        local current_substate
        current_substate=$(systemctl show -p SubState --value "$SERVICE_NAME" 2>/dev/null || echo "unknown")
        local current_activestate
        current_activestate=$(systemctl show -p ActiveState --value "$SERVICE_NAME" 2>/dev/null || echo "unknown")
        echo -e "  \033[1;33m$SERVICE_NAME 服务当前状态: $current_activestate (substate: $current_substate)\033[0m" >&2
        warning "  如果不是 'active' 或 'running', 请手动检查。"
    fi
    info "-----------------------------------------------------------------"
    info "Plex Media Server 更新流程处理完毕！"
    info "您可以尝试在浏览器中打开 Plex: http://<您的服务器IP>:32400/web"
}

main
exit 0
