# Media Server Updater
# 媒体服务器更新脚本

[View English Version README](#english-version-anchor)

本仓库包含两个独立的 Bash 脚本，旨在自动化 Debian/Ubuntu 系统上 Emby Server 和 Plex Media Server 的更新过程，特别针对 `arm64` 架构（Plex 脚本的架构可配置）。

**包含脚本:**

1.  `update_emby.sh`: 自动更新 Emby Server。
2.  `update_plex.sh`: 自动(手动)更新 Plex Media Server。

---

## 1. Emby Server 自动更新脚本 ([`update_emby.sh`](./update_emby.sh))

**版本:** 9

此脚本用于在 `arm64` 架构的 Debian/Ubuntu 系统上自动下载并安装最新（或指定）版本的 Emby Server。它可以直接从 Emby GitHub releases API 获取最新的发布信息。

**功能特性:**

* **自动获取最新版本:** 从 [Emby GitHub Releases](https://github.com/MediaBrowser/Emby.Releases/releases) API 检索最新版本链接和版本号。
* **预发布版本支持:** 可配置选项以包含或排除预发布版本。
* **手动版本输入:** 如果自动获取失败或被跳过，允许用户输入特定的 Emby 版本号。
* **固定架构:** 主要为 `arm64` 设计。
* **MD5 校验和验证:** 可选下载并验证 `.deb` 包的 MD5 校验和。
* **自动安装:** 使用 `dpkg` 安装下载的 Emby Server 软件包。
* **带超时和检查的服务重启:** 使用可配置的超时和更耐心的状态检查循环重启 `emby-server` 服务。
* **降级警告:** 如果所选版本低于当前已安装版本，则会警告用户并请求确认。
* **清理:** 安装后删除下载的 `.deb` 软件包和 MD5 文件。
* **详细日志记录:** 提供带有颜色高亮的信息性消息、警告和错误。
* **依赖检查:** 执行前验证所需命令行工具 (`curl`, `jq` 等) 是否存在。

**先决条件:**

* 基于 Debian/Ubuntu 的系统 (专注于 `arm64`)。
* `sudo` 权限 (脚本必须以 root 或 sudo 身份运行)。
* 所需软件包: `curl`, `wget`, `dpkg`, `systemctl`, `grep`, `sed`, `md5sum`, `awk`, `jq`, `coreutils` (用于 `timeout`)。
    * 使用以下命令安装它们: `sudo apt-get update && sudo apt-get install curl wget dpkg systemctl grep sed coreutils procps findutils jq`

**配置 (在 `update_emby.sh` 脚本内):**

打开 `update_emby.sh` 文件，您可以修改以下变量：

| 变量名                                  | 描述                                                         | 默认值                                                                                                                                   | 备注                       |
| :-------------------------------------- | :----------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------- | :------------------------- |
| `ARCHITECTURE`                          | 目标架构                                                     | `"arm64"`                                                                                                                                | 例如 `arm64`, `amd64`      |
| `SERVICE_NAME`                          | Emby 服务名称                                                | `"emby-server.service"`                                                                                                                  |                            |
| `INCLUDE_PRERELEASES`                   | 是否包含预发布版本。设置为 `"true"` 包含，`"false"` 仅稳定版 | `"true"`                                                                                                                                 |                            |
| `GITHUB_API_RELEASES_URL`               | 获取所有版本列表的 GitHub API 端点                           | [`"https://api.github.com/repos/MediaBrowser/Emby.Releases/releases"`](https://api.github.com/repos/MediaBrowser/Emby.Releases/releases) |                            |
| `RESTART_COMMAND_TIMEOUT`               | 服务重启命令的超时时间                                       | `"180s"`                                                                                                                                 | 例如 `60s`, `120s`, `180s` |
| `POST_RESTART_CHECK_TOTAL_WAIT_SECONDS` | 重启后等待服务激活的总时间 (秒)                              | `60`                                                                                                                                     |                            |
| `POST_RESTART_CHECK_INTERVAL_SECONDS`   | 服务状态检查之间的时间间隔 (秒)                              | `10`                                                                                                                                     |                            |

**使用方法:**

1.  将脚本另存为 `update_emby.sh`。
2.  赋予执行权限: `chmod +x update_emby.sh`。
3.  使用 sudo 运行: `sudo ./update_emby.sh`。
4.  脚本将尝试自动查找最新版本。如果失败，它会提示您手动输入版本号。
    * **示例运行:**
        ```bash
        ubuntu@instance-20231107-1658:~$ sudo ./update_emby.sh
        [信息] Emby Server 更新脚本 for arm64 (v9 - 增加最终状态输出)
        [信息] -----------------------------------------------------------------
        [信息] 正在尝试从 GitHub API ([https://api.github.com/repos/MediaBrowser/Emby.Releases/releases](https://api.github.com/repos/MediaBrowser/Emby.Releases/releases)) 获取最新的 Emby Server (arm64) 版本信息...
        [信息] 配置为包含预发布版本。
        [信息] 从 API 获取到的版本 (tag_name): 4.9.0.52
        [信息] 预期的 DEB 文件名: emby-server-deb_4.9.0.52_arm64.deb
        [信息] 通过 API 成功找到下载链接: [https://github.com/MediaBrowser/Emby.Releases/releases/download/4.9.0.52/emby-server-deb_4.9.0.52_arm64.deb](https://github.com/MediaBrowser/Emby.Releases/releases/download/4.9.0.52/emby-server-deb_4.9.0.52_arm64.deb)
        [信息] 将要处理的版本: 4.9.0.52
        [信息] 最终下载链接: [https://github.com/MediaBrowser/Emby.Releases/releases/download/4.9.0.52/emby-server-deb_4.9.0.52_arm64.deb](https://github.com/MediaBrowser/Emby.Releases/releases/download/4.9.0.52/emby-server-deb_4.9.0.52_arm64.deb)
        [信息] 目标文件名: emby-server-deb_4.9.0.52_arm64.deb

        [信息] 正在下载 emby-server-deb_4.9.0.52_arm64.deb...
        # ... 下载过程 ...
        [信息] 下载完成: emby-server-deb_4.9.0.52_arm64.deb

        [信息] 正在尝试下载 MD5 校验文件: emby-server-deb_4.9.0.52_arm64.deb.md5
        # ... MD5 校验过程 ...
        [信息] MD5 校验和匹配！文件完整性已验证。

        [信息] 正在安装 emby-server-deb_4.9.0.52_arm64.deb...
        # ... 安装过程 ...
        [信息] Emby Server 安装/更新成功。

        [信息] 正在尝试重启 emby-server.service 服务 (命令超时时间: 180s)...
        # ... 服务重启和状态检查 ...
        [信息] emby-server.service 服务已成功启动并正在运行。

        [信息] 正在删除安装包 emby-server-deb_4.9.0.52_arm64.deb...
        [信息] 安装包已成功删除。
        [信息] -----------------------------------------------------------------
        [信息] 最终 Emby Server 服务状态确认:
        [信息]   emby-server.service 服务当前状态: active (正在运行)
        [信息] -----------------------------------------------------------------
        [信息] Emby Server 更新流程处理完毕！
        [信息] 您可以尝试在浏览器中打开 Emby: http://<您的服务器IP>:8096
        ```

---

## 2. Plex Media Server 自动更新脚本 ([`update_plex.sh`](./update_plex.sh))

**版本:** 1.2

此脚本用于在 Debian/Ubuntu 系统上更新 Plex Media Server。它提供了灵活性，允许用户提供直接下载链接（推荐用于 Beta/Plex Pass 版本），或者通过用户提供的版本号尝试构建下载 URL。

**功能特性:**

* **直接下载链接优先:** 推荐并使用用户提供的直接 `.deb` 下载链接，非常适合 Plex Pass 测试版。
* **手动版本输入:** 如果未提供直接链接，允许用户输入 Plex 版本号，脚本会尝试构建标准的下载 URL。
* **架构配置:** 默认为 `arm64`，但可以在脚本内更改。
* **SHA1 校验和验证:** 可选下载并验证 `.deb` 包的 SHA1 校验和以确保完整性。
* **自动安装:** 使用 `dpkg` 安装下载的 Plex Media Server 软件包。
* **带超时的服务重启:** 使用可配置的超时和状态检查重启 `plexmediaserver` 服务。
* **降级警告:** 如果所选版本低于当前已安装版本，则会警告用户并请求确认。
* **清理:** 安装后删除下载的 `.deb` 软件包和 SHA1 文件。
* **详细日志记录:** 提供带有颜色高亮的信息性消息、警告和错误。
* **依赖检查:** 执行前验证所需命令行工具是否存在。

**先决条件:**

* 基于 Debian/Ubuntu 的系统。
* `sudo` 权限 (脚本必须以 root 或 sudo 身份运行)。
* 所需软件包: `wget`, `dpkg`, `systemctl`, `coreutils` (用于 `sha1sum`, `timeout`, `basename`), `findutils`, `procps`, `grep`, `sed`, `awk`。
    * 使用以下命令安装它们: `sudo apt-get update && sudo apt-get install wget dpkg systemctl coreutils findutils procps grep sed awk`

**配置 (在 `update_plex.sh` 脚本内):**

打开 `update_plex.sh` 文件，您可以修改以下变量：

| 变量名                                  | 描述                                           | 默认值                                                                                                 | 备注                       |
| :-------------------------------------- | :--------------------------------------------- | :----------------------------------------------------------------------------------------------------- | :------------------------- |
| `ARCHITECTURE`                          | 目标架构                                       | `"arm64"`                                                                                              | 例如 `amd64`, `arm64`      |
| `SERVICE_NAME`                          | Plex 服务名称                                  | `"plexmediaserver.service"`                                                                            |                            |
| `PLEX_DOWNLOAD_BASE_URL`                | 如果未提供直接链接，用于构建下载链接的基础 URL | [`"https://downloads.plex.tv/plex-media-server-new"`](https://downloads.plex.tv/plex-media-server-new) |                            |
| `RESTART_COMMAND_TIMEOUT`               | 服务重启命令的超时时间                         | `"180s"`                                                                                               | 例如 `60s`, `120s`, `180s` |
| `POST_RESTART_CHECK_TOTAL_WAIT_SECONDS` | 重启后等待服务激活的总时间 (秒)                | `60`                                                                                                   |                            |
| `POST_RESTART_CHECK_INTERVAL_SECONDS`   | 服务状态检查之间的时间间隔 (秒)                | `10`                                                                                                   |                            |

**使用方法:**

1.  将脚本另存为 `update_plex.sh`。
2.  赋予执行权限: `chmod +x update_plex.sh`。
3.  使用 sudo 运行: `sudo ./update_plex.sh`。
4.  脚本会首先询问您是否有[直接的 `.deb` 下载链接](https://www.plex.tv/media-server-downloads/?cat=computer&plat=linux&signUp=0)。
    * **示例运行 (使用直接链接):**
        ```bash
        ubuntu@instance-20231107-1658:~$ sudo ./update_plex.sh
        [信息] Plex Media Server 更新脚本 for arm64 (v1.2)
        [信息] -----------------------------------------------------------------
        [信息] 由于 Plex Beta/Plex Pass 版本的下载链接通常需要登录，
        [信息] 此脚本建议您直接提供 .deb 包的下载链接。

        您有 Plex Media Server .deb 包的直接下载链接吗? (y/N): y
        请输入 .deb 包的直接下载链接: [https://downloads.plex.tv/plex-media-server-new/1.41.7.9749-ce0b45d6e/debian/plexmediaserver_1.41.7.9749-ce0b45d6e_arm64.deb](https://downloads.plex.tv/plex-media-server-new/1.41.7.9749-ce0b45d6e/debian/plexmediaserver_1.41.7.9749-ce0b45d6e_arm64.deb)
        [信息] 从文件名 'plexmediaserver_1.41.7.9749-ce0b45d6e_arm64.deb' 中解析得到:
        [信息]   版本: 1.41.7.9749-ce0b45d6e
        [信息]   架构: arm64
        [信息] 文件名中的架构 'arm64' 与配置的默认架构 'arm64' 一致。
        [信息] 将要处理的版本 (如果已知): 1.41.7.9749-ce0b45d6e
        [信息] 目标架构: arm64
        [信息] 最终下载链接: [https://downloads.plex.tv/plex-media-server-new/1.41.7.9749-ce0b45d6e/debian/plexmediaserver_1.41.7.9749-ce0b45d6e_arm64.deb](https://downloads.plex.tv/plex-media-server-new/1.41.7.9749-ce0b45d6e/debian/plexmediaserver_1.41.7.9749-ce0b45d6e_arm64.deb)
        [信息] 目标文件名: plexmediaserver_1.41.7.9749-ce0b45d6e_arm64.deb

        [信息] 正在下载 plexmediaserver_1.41.7.9749-ce0b45d6e_arm64.deb...
        # ... 下载过程 ...
        [信息] 下载完成: plexmediaserver_1.41.7.9749-ce0b45d6e_arm64.deb

        [信息] 正在尝试下载 SHA1 校验文件: plexmediaserver_1.41.7.9749-ce0b45d6e_arm64.deb.sha1
        [警告] 下载 SHA1 文件 ... 失败 ... 将跳过校验。

        [信息] 正在安装 plexmediaserver_1.41.7.9749-ce0b45d6e_arm64.deb...
        # ... 安装过程 ...
        [信息] Plex Media Server 安装/更新成功。

        [信息] 正在尝试重启 plexmediaserver.service 服务 (命令超时时间: 180s)...
        # ... 服务重启和状态检查 ...
        [信息] plexmediaserver.service 服务已成功启动并正在运行。

        [信息] 正在删除安装包 plexmediaserver_1.41.7.9749-ce0b45d6e_arm64.deb...
        [信息] 安装包已成功删除。
        [信息] -----------------------------------------------------------------
        [信息] 最终 Plex Media Server 服务状态确认:
        [信息]   plexmediaserver.service 服务当前状态: active (正在运行)
        [信息] -----------------------------------------------------------------
        [信息] Plex Media Server 更新流程处理完毕！
        [信息] 您可以尝试在浏览器中打开 Plex: http://<您的服务器IP>:32400/web
        ```
    * **如果选择不提供直接链接 (输入 'N')**，脚本会提示您输入版本号，然后尝试构建下载链接。

---
<a name="english-version-anchor"></a>
# Media Server Updater Scripts

This repository contains two separate Bash scripts designed to automate the update process for Emby Server and Plex Media Server on Debian/Ubuntu-based systems, with a specific focus on `arm64` architecture (though configurable for Plex).

**Included Scripts:**

1.  `update_emby.sh`: Automates Emby Server updates.
2.  `update_plex.sh`: Automates Plex Media Server updates.

---

## 1. Emby Server Auto Update Script (`update_emby.sh`)

**Version:** 9

This script automates the process of downloading and installing the latest (or a specified) version of Emby Server on `arm64` Debian/Ubuntu systems. It can fetch the latest release information directly from the Emby GitHub releases API.

**Features:**

* **Automatic Latest Version Fetching:** Retrieves the latest version link and number from the Emby GitHub Releases API.
* **Prerelease Support:** Configurable option to include or exclude pre-release versions.
* **Manual Version Input:** If automatic fetching fails or is bypassed, allows users to input a specific Emby version number.
* **Fixed Architecture:** Designed primarily for `arm64`.
* **MD5 Checksum Verification:** Optionally downloads and verifies the MD5 checksum of the `.deb` package.
* **Automated Installation:** Uses `dpkg` to install the downloaded Emby Server package.
* **Service Restart with Timeout & Checks:** Restarts the `emby-server` service with a configurable timeout and a more patient status check loop.
* **Downgrade Warning:** Warns the user if the selected version is older than the currently installed version and asks for confirmation.
* **Cleanup:** Removes the downloaded `.deb` package and MD5 file after installation.
* **Detailed Logging:** Provides informative messages, warnings, and errors with color highlighting.
* **Dependency Check:** Verifies the presence of required command-line tools (`curl`, `jq`, etc.) before execution.

**Prerequisites:**

* Debian/Ubuntu-based system (focused on `arm64`).
* `sudo` access (script must be run as root or with sudo).
* Required packages: `curl`, `wget`, `dpkg`, `systemctl`, `grep`, `sed`, `md5sum`, `awk`, `jq`, `coreutils` (for `timeout`).
    * Install them using: `sudo apt-get update && sudo apt-get install curl wget dpkg systemctl grep sed coreutils procps findutils jq`

**Configuration (within `update_emby.sh`):**

Open the `update_emby.sh` file to modify the following variables:

| Variable Name                           | Description                                                            | Default Value                                                                                                                            | Notes                       |
| :-------------------------------------- | :--------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------- | :-------------------------- |
| `ARCHITECTURE`                          | Target architecture                                                    | `"arm64"`                                                                                                                                | e.g., `arm64`, `amd64`      |
| `SERVICE_NAME`                          | Name of the Emby service                                               | `"emby-server.service"`                                                                                                                  |                             |
| `INCLUDE_PRERELEASES`                   | Whether to include pre-release versions. Set to `"true"` or `"false"`. | `"true"`                                                                                                                                 |                             |
| `GITHUB_API_RELEASES_URL`               | API endpoint for Emby releases                                         | [`"https://api.github.com/repos/MediaBrowser/Emby.Releases/releases"`](https://api.github.com/repos/MediaBrowser/Emby.Releases/releases) |                             |
| `RESTART_COMMAND_TIMEOUT`               | Timeout for the service restart command                                | `"180s"`                                                                                                                                 | e.g., `60s`, `120s`, `180s` |
| `POST_RESTART_CHECK_TOTAL_WAIT_SECONDS` | Total time to wait for service activation after restart (seconds)      | `60`                                                                                                                                     |                             |
| `POST_RESTART_CHECK_INTERVAL_SECONDS`   | Interval between service status checks after restart (seconds)         | `10`                                                                                                                                     |                             |

**Usage:**

1.  Save the script as `update_emby.sh`.
2.  Make it executable: `chmod +x update_emby.sh`.
3.  Run with sudo: `sudo ./update_emby.sh`.
4.  The script will attempt to find the latest version automatically. If it fails, it will prompt you to enter a version number manually.

---

## 2. Plex Media Server Auto Update Script (`update_plex.sh`)

**Version:** 1.2

This script facilitates updating Plex Media Server on Debian/Ubuntu systems. It offers flexibility by allowing users to provide a direct download link (recommended for Beta/Plex Pass versions) or by attempting to construct a download URL based on a user-provided version number.

**Features:**

* **Direct Download Link Priority:** Recommends and uses direct `.deb` download links provided by the user, ideal for Plex Pass beta versions.
* **Manual Version Input:** If no direct link is provided, allows users to input a Plex version number, and the script attempts to construct a standard download URL.
* **Architecture Configuration:** Defaults to `arm64` but can be changed within the script.
* **SHA1 Checksum Verification:** Optionally downloads and verifies the SHA1 checksum of the `.deb` package to ensure integrity.
* **Automated Installation:** Uses `dpkg` to install the downloaded Plex Media Server package.
* **Service Restart with Timeout:** Restarts the `plexmediaserver` service with a configurable timeout and status check.
* **Downgrade Warning:** Warns the user if the selected version is older than the currently installed version and asks for confirmation.
* **Cleanup:** Removes the downloaded `.deb` package and SHA1 file after installation.
* **Detailed Logging:** Provides informative messages, warnings, and errors with color highlighting.
* **Dependency Check:** Verifies the presence of required command-line tools before execution.

**Prerequisites:**

* Debian/Ubuntu-based system.
* `sudo` access (script must be run as root or with sudo).
* Required packages: `wget`, `dpkg`, `systemctl`, `coreutils` (for `sha1sum`, `timeout`, `basename`), `findutils`, `procps`, `grep`, `sed`, `awk`.
    * Install them using: `sudo apt-get update && sudo apt-get install wget dpkg systemctl coreutils findutils procps grep sed awk`

**Configuration (within `update_plex.sh`):**

Open the `update_plex.sh` file to modify the following variables:

| Variable Name                           | Description                                                              | Default Value                                                                                          | Notes                       |
| :-------------------------------------- | :----------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------- | :-------------------------- |
| `ARCHITECTURE`                          | Target architecture                                                      | `"arm64"`                                                                                              | e.g., `amd64`, `arm64`      |
| `SERVICE_NAME`                          | Name of the Plex service                                                 | `"plexmediaserver.service"`                                                                            |                             |
| `PLEX_DOWNLOAD_BASE_URL`                | Base URL for constructing download links if a direct link isn't provided | [`"https://downloads.plex.tv/plex-media-server-new"`](https://downloads.plex.tv/plex-media-server-new) |                             |
| `RESTART_COMMAND_TIMEOUT`               | Timeout for the service restart command                                  | `"180s"`                                                                                               | e.g., `60s`, `120s`, `180s` |
| `POST_RESTART_CHECK_TOTAL_WAIT_SECONDS` | Total time to wait for service activation after restart (seconds)        | `60`                                                                                                   |                             |
| `POST_RESTART_CHECK_INTERVAL_SECONDS`   | Interval between service status checks after restart (seconds)           | `10`                                                                                                   |                             |

**Usage:**

1.  Save the script as `update_plex.sh`.
2.  Make it executable: `chmod +x update_plex.sh`.
3.  Run with sudo: `sudo ./update_plex.sh`.
4.  The script will first ask if you have a direct `.deb` download link.
    * **If you choose not to provide a direct link (enter 'N')**, the script will prompt you for a version number and attempt to construct the download link.
