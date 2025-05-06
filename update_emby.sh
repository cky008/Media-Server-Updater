#!/bin/bash

# ==============================================================================
# Emby Server 自动更新脚本 (专为 arm64 Debian/Ubuntu 设计) - v9
#
# 功能:
# 1. 自动从 GitHub API (Emby Releases) 获取最新版本链接和版本号。
#    - 可配置是否包含预发布版本。
# 2. 如果自动获取失败，允许用户手动输入版本号。
# 3. 下载最新的 .deb 安装包。
# 4. 可选：对下载的 .deb 包进行 MD5 校验和验证。
# 5. 使用 dpkg 安装 Emby Server。
# 6. 重启 emby-server 服务 (带有更长的超时和更耐心的状态检查循环)。
# 7. 清理下载的安装包和 MD5 文件。
# 8. 在脚本末尾输出最终的服务状态。
#
# 使用方法:
# 1. 根据需要修改下面的 `INCLUDE_PRERELEASES` 和 `RESTART_TIMEOUT` 配置。
# 2. 确保 'jq' 和 'timeout' (通常在 coreutils 包中) 已安装:
#    `sudo apt-get update && sudo apt-get install jq coreutils`
# 3. 保存此脚本为例如 `update_emby.sh`。
# 4. 赋予执行权限: `chmod +x update_emby.sh`。
# 5. 运行脚本: `sudo ./update_emby.sh` (需要 sudo 权限来安装和重启服务)。
#
# 变更日志:
# v9: 在脚本执行完毕前，增加一次最终的服务状态检查和输出。
# v8: 增加 RESTART_COMMAND_TIMEOUT 默认值至 180s。
#     改进服务重启后的状态检查，使用循环多次检查服务是否激活。
# v7: 增加 INCLUDE_PRERELEASES 选项以支持获取预发布版本。
# ==============================================================================

# --- 配置 ---
ARCHITECTURE="arm64" # 目标架构，例如 arm64, amd64
SERVICE_NAME="emby-server.service" # Emby 服务名称

# 是否包含预发布版本 ("true" 或 "false")
INCLUDE_PRERELEASES="true" # <--- 修改此项以包含预发布版本

# GitHub API 端点，获取所有版本列表
GITHUB_API_RELEASES_URL="https://api.github.com/repos/MediaBrowser/Emby.Releases/releases"
GITHUB_RELEASES_DOWNLOAD_BASE="https://github.com/MediaBrowser/Emby.Releases/releases/download" # 用于手动输入

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

# 函数：获取最新版本信息
fetch_latest_version_info() {
    info "正在尝试从 GitHub API ($GITHUB_API_RELEASES_URL) 获取最新的 Emby Server ($ARCHITECTURE) 版本信息..."
    if [ "$INCLUDE_PRERELEASES" == "true" ]; then
        info "配置为包含预发布版本。"
    else
        info "配置为仅获取稳定版本。"
    fi

    local api_response_json
    local latest_version
    local deb_filename
    local download_url
    local release_data_json

    api_response_json=$(curl -sL \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$GITHUB_API_RELEASES_URL")

    if [ -z "$api_response_json" ]; then
        error "无法从 GitHub API 获取数据或响应为空。"
        error "请检查网络连接或URL: $GITHUB_API_RELEASES_URL"
        return 1
    fi

    local jq_filter_prerelease_condition=""
    if [ "$INCLUDE_PRERELEASES" != "true" ]; then
        jq_filter_prerelease_condition='select(.prerelease == false) |'
    fi

    release_data_json=$(echo "$api_response_json" | jq -er --arg ARCH_ARG "$ARCHITECTURE" "
        first(
            .[] |
            ${jq_filter_prerelease_condition}
            . as \$release |
            \$release.tag_name as \$tag |
            (\"emby-server-deb_\" + \$tag + \"_\" + \$ARCH_ARG + \".deb\") as \$deb_file_to_find |
            (\$release.assets[] | select(.name == \$deb_file_to_find)) as \$asset |
            if \$asset != null then {tag: \$tag, url: \$asset.browser_download_url, debfile: \$deb_file_to_find} else empty end
        )
    ")

    if [ $? -ne 0 ] || [ "$release_data_json" == "null" ] || [ -z "$release_data_json" ]; then
        error "无法从 GitHub API 响应中找到符合条件的版本或其 '$ARCHITECTURE' 资源。"
        if [ "$INCLUDE_PRERELEASES" != "true" ]; then
            error "尝试设置为 INCLUDE_PRERELEASES=\"true\" 看看是否能找到预发布版本。"
        fi
        return 1
    fi

    latest_version=$(echo "$release_data_json" | jq -er '.tag')
    download_url=$(echo "$release_data_json" | jq -er '.url')
    deb_filename=$(echo "$release_data_json" | jq -er '.debfile')

    if [ -z "$latest_version" ] || [ -z "$download_url" ] || [ -z "$deb_filename" ]; then
        error "从解析后的 JSON 中提取版本信息失败。"
        error "解析得到的数据: $release_data_json"
        return 1
    fi

    info "从 API 获取到的版本 (tag_name): $latest_version"
    info "预期的 DEB 文件名: $deb_filename"
    info "通过 API 成功找到下载链接: $download_url"

    echo "$latest_version"
    echo "$download_url"
    echo "$deb_filename"
    return 0
}

# --- 脚本主逻辑 ---
main() {
    info "Emby Server 更新脚本 for ${ARCHITECTURE} (v9 - 增加最终状态输出)"
    info "-----------------------------------------------------------------"

    if [ "$(id -u)" -ne 0 ]; then
        error "此脚本需要以 root 或 sudo 权限运行。"
        error "请尝试: sudo $0"
        exit 1
    fi

    for cmd in curl wget dpkg systemctl grep sed md5sum awk jq timeout; do
        if ! command -v $cmd &> /dev/null; then
            error "必需命令 '$cmd' 未找到。请先安装它。"
            if [ "$cmd" == "jq" ]; then
                error "您可以使用 'sudo apt-get update && sudo apt-get install jq' 来安装 jq。"
            elif [ "$cmd" == "timeout" ]; then
                error "您可以使用 'sudo apt-get update && sudo apt-get install coreutils' 来安装 timeout。"
            fi
            exit 1
        fi
    done

    local latest_version
    local download_url
    local deb_filename

    read_output=$(fetch_latest_version_info)
    if [ $? -ne 0 ]; then
        error "获取最新版本信息失败。请检查上面的错误日志。"
    else
        mapfile -t version_info_array <<< "$read_output"
        latest_version="${version_info_array[0]}"
        download_url="${version_info_array[1]}"
        deb_filename="${version_info_array[2]}"
    fi

    if [ -z "$latest_version" ] || [ -z "$download_url" ] || [ -z "$deb_filename" ]; then
        warning "无法自动确定最新版本，或自动获取过程中出错。"
        while true; do
            read -p "请输入您想要安装的 Emby 版本号 (例如 4.9.0.52): " manual_version
            if [[ "$manual_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                latest_version="$manual_version"
                deb_filename="emby-server-deb_${latest_version}_${ARCHITECTURE}.deb"
                download_url="${GITHUB_RELEASES_DOWNLOAD_BASE}/${latest_version}/${deb_filename}"
                info "您已手动指定版本: $latest_version"
                break
            else
                error "版本号格式不正确，应为 X.Y.Z.B (例如 4.9.0.52)。请重试。"
            fi
        done
    fi

    info "将要处理的版本: $latest_version"
    info "最终下载链接: $download_url"
    info "目标文件名: $deb_filename"
    echo >&2

    if [ -f "$deb_filename" ]; then
        read -p "文件 $deb_filename 已存在。是否重新下载? (y/N): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            info "删除已存在的文件 $deb_filename"
            if ! rm -f "$deb_filename"; then
                error "删除旧文件 $deb_filename 失败。请检查权限。"
                exit 1;
            fi
        else
            info "将使用已存在的本地文件 $deb_filename."
        fi
    fi

    if [ ! -f "$deb_filename" ]; then
        info "正在下载 $deb_filename..."
        wget --progress=bar:force:noscroll -O "$deb_filename" "$download_url"
        if [ $? -ne 0 ]; then
            error "下载 $deb_filename 失败。请检查链接或网络。"
            rm -f "$deb_filename" 2>/dev/null
            exit 1
        fi
        info "下载完成: $deb_filename"
    fi
    echo >&2

    local md5_url="${download_url}.md5"
    local md5_filename_local="${deb_filename}.md5"
    info "正在尝试下载 MD5 校验文件: ${md5_filename_local}"
    if wget -qO "$md5_filename_local" "$md5_url"; then
        info "MD5 文件下载完成: $md5_filename_local"
        local expected_md5=$(awk '{print $1}' "$md5_filename_local")
        if [ -z "$expected_md5" ]; then
            warning "无法从 $md5_filename_local 中提取预期的 MD5 校验和。将跳过校验。"
        else
            info "预期的 MD5 校验和: $expected_md5"
            info "正在计算下载文件 $deb_filename 的 MD5 校验和..."
            local calculated_md5=$(md5sum "$deb_filename" | awk '{print $1}')
            if [ -z "$calculated_md5" ]; then
                error "计算 $deb_filename 的 MD5 校验和失败。"
                warning "建议删除文件并重试。将跳过校验。"
            else
                info "计算得到的 MD5 校验和: $calculated_md5"
                if [ "$expected_md5" == "$calculated_md5" ]; then
                    info "\033[1;32mMD5 校验和匹配！文件完整性已验证。\033[0m"
                else
                    error "MD5 校验和不匹配！文件可能已损坏或被篡改。"
                    error "预期: $expected_md5"; error "得到: $calculated_md5"
                    read -p "警告：校验和不匹配！是否仍然继续安装此文件? (y/N): " continue_anyway
                    if ! [[ "$continue_anyway" == "y" || "$continue_anyway" == "Y" ]]; then
                        info "安装已取消。请删除 $deb_filename 并重试下载。"
                        rm -f "$deb_filename" "$md5_filename_local" 2>/dev/null
                        exit 1
                    fi
                    warning "用户选择继续安装可能已损坏的文件。"
                fi
            fi
        fi
        rm -f "$md5_filename_local" 2>/dev/null
    else
        warning "下载 MD5 文件 $md5_filename_local 失败 (链接: $md5_url)。可能是此版本没有提供 MD5 文件。将跳过校验。"
    fi
    echo >&2

    info "正在安装 $deb_filename..."
    current_installed_version=$(dpkg-query -W -f='${Version}' emby-server 2>/dev/null || echo "not-installed")
    if dpkg --compare-versions "$latest_version" "lt" "$current_installed_version" && [ "$current_installed_version" != "not-installed" ]; then
        warning "注意：您将要安装的版本 ($latest_version) 低于当前已安装的版本 ($current_installed_version)。"
        read -p "您确定要降级吗? (y/N): " confirm_downgrade
        if ! [[ "$confirm_downgrade" == "y" || "$confirm_downgrade" == "Y" ]]; then
            info "降级操作已取消。脚本退出。"
            exit 0
        fi
        info "用户确认降级。"
    fi

    if dpkg -i "$deb_filename"; then
        info "Emby Server 安装/更新成功。"
    else
        error "使用 dpkg 安装 $deb_filename 失败。"
        warning "这可能是由于缺少依赖。您可以尝试运行 'sudo apt-get update && sudo apt-get -f install' 来修复依赖问题，"
        warning "然后可以尝试重新运行此脚本 (选择不重新下载文件)，或手动安装 '$deb_filename'。"
    fi
    echo >&2

    info "正在尝试重启 $SERVICE_NAME 服务 (命令超时时间: ${RESTART_COMMAND_TIMEOUT})..."
    timeout "$RESTART_COMMAND_TIMEOUT" systemctl restart "$SERVICE_NAME"
    restart_command_exit_code=$?

    if [ $restart_command_exit_code -eq 124 ]; then
        warning "systemctl restart $SERVICE_NAME 命令超时 (超过 ${RESTART_COMMAND_TIMEOUT})。"
        warning "这可能意味着服务停止或启动过程非常缓慢。将继续检查服务状态..."
    elif [ $restart_command_exit_code -ne 0 ]; then
        error "执行 systemctl restart $SERVICE_NAME 时遇到错误 (退出码: $restart_command_exit_code)。"
        warning "请尝试手动执行 'sudo systemctl restart $SERVICE_NAME' 并查看日志 'journalctl -u $SERVICE_NAME'。"
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

    if [ -f "$deb_filename" ]; then
        info "正在删除安装包 $deb_filename..."
        if rm -f "$deb_filename"; then
            info "安装包已成功删除。"
        else
            warning "删除 $deb_filename 失败。您可以手动删除它。"
        fi
    fi

    # --- 最终状态检查 ---
    info "-----------------------------------------------------------------"
    info "最终 Emby Server 服务状态确认:"
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        info "  \033[1;32m$SERVICE_NAME 服务当前状态: active (正在运行)\033[0m"
    elif systemctl is-failed --quiet "$SERVICE_NAME"; then
        error "  $SERVICE_NAME 服务当前状态: failed (启动失败)"
        warning "  请使用 'sudo systemctl status $SERVICE_NAME --no-pager -l' 和 'sudo journalctl -u $SERVICE_NAME -e --no-pager' 查看详情。"
    else
        local current_substate
        current_substate=$(systemctl show -p SubState --value "$SERVICE_NAME" 2>/dev/null || echo "unknown")
        local current_activestate
        current_activestate=$(systemctl show -p ActiveState --value "$SERVICE_NAME" 2>/dev/null || echo "unknown")
        warning "  $SERVICE_NAME 服务当前状态: $current_activestate (substate: $current_substate)"
        warning "  如果不是 'active' 或 'running', 请手动检查。"
    fi
    info "-----------------------------------------------------------------"
    info "Emby Server 更新流程处理完毕！"
    info "您可以尝试在浏览器中打开 Emby: http://<您的服务器IP>:8096"
}

main
exit 0
