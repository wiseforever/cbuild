#!/bin/bash
# cbuild 全局卸载脚本
# 通过 install.sh --global 安装时，此脚本会被一同安装到目标目录。
# 也可以直接从仓库运行：bash uninstall.sh

set -euo pipefail

# 检测脚本所在目录（即安装目录）
INSTALL_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)"

# 默认路径（供直接运行仓库中脚本时使用）
DEFAULT_INSTALL_DIR="${HOME}/.cbuild"
DEFAULT_BIN_DIR="${HOME}/.cbuild/bin"
DEFAULT_CMD_NAME="cb"

# 读取安装配置
CONFIG_FILE="${INSTALL_DIR}/.install.cfg"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    # 从配置文件读取，若未定义则使用默认值
    LAUNCHER_PATH="${LAUNCHER_PATH:-${DEFAULT_BIN_DIR}/${DEFAULT_CMD_NAME}}"
elif [[ "$INSTALL_DIR" == "$(cd "$(dirname "$(readlink -f "$0")")" && pwd)" && -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    LAUNCHER_PATH="${LAUNCHER_PATH:-${DEFAULT_BIN_DIR}/${DEFAULT_CMD_NAME}}"
else
    # 判断是否是通过 install.sh --global 安装的（兼容新旧默认路径）
    for candidate_dir in "$DEFAULT_INSTALL_DIR" "${HOME}/.local/share/cbuild"; do
        if [[ -f "${candidate_dir}/.install.cfg" ]]; then
            INSTALL_DIR="$candidate_dir"
            source "${candidate_dir}/.install.cfg"
            LAUNCHER_PATH="${LAUNCHER_PATH:-${DEFAULT_BIN_DIR}/${DEFAULT_CMD_NAME}}"
            found=1
            break
        fi
    done
    if [[ -z "${found:-}" ]]; then
        echo "错误：找不到 cbuild 全局安装。"
        echo ""
        echo "如需手动卸载，请删除以下内容："
        echo "  安装目录: ${DEFAULT_INSTALL_DIR}"
        echo "  命令入口: ${DEFAULT_BIN_DIR}/${DEFAULT_CMD_NAME}"
        echo ""
        echo "如果自定义了安装路径，请直接删除对应目录和命令文件。"
        exit 1
    fi
fi

uninstall_global() {
    echo "========================================"
    echo "   cbuild 全局卸载"
    echo "========================================"
    echo "  安装目录: ${INSTALL_DIR}"
    echo "  命令入口: ${LAUNCHER_PATH}"
    echo ""

    read -r -p "确认卸载以上内容? [y/N] " confirm
    echo ""

    case "$confirm" in
        [yY]|[yY]es)
            # 移除命令入口
            if [[ -f "$LAUNCHER_PATH" ]]; then
                rm -f "$LAUNCHER_PATH"
                echo "  ✓ 已移除命令: ${LAUNCHER_PATH}"
            else
                echo "  - 命令文件不存在: ${LAUNCHER_PATH}"
            fi

            # 移除安装目录（包括自身、cb脚本、配置文件等）
            if [[ -d "$INSTALL_DIR" ]]; then
                rm -rf "$INSTALL_DIR"
                echo "  ✓ 已移除安装目录: ${INSTALL_DIR}"
            else
                echo "  - 安装目录不存在: ${INSTALL_DIR}"
            fi

            echo ""
            echo "cbuild 已成功卸载。"

            # 提示 PATH
            case ":${PATH}:" in
                *":${BIN_DIR:-${DEFAULT_BIN_DIR}}:"*) ;;
                *)
                    echo "提示: 如需彻底清理，可手动从 PATH 中移除 ${BIN_DIR:-${DEFAULT_BIN_DIR}}。"
                    ;;
            esac
            ;;
        *)
            echo "已取消卸载。"
            exit 0
            ;;
    esac
}

# --- 处理参数 ---
case "${1:-}" in
    -h|--help)
        cat <<EOF
用法: $(basename "$0") [选项]

卸载 cbuild 全局安装。
默认读取安装配置 ~/.cbuild/.install.cfg。

选项:
  -h, --help      显示帮助
EOF
        exit 0
        ;;
esac

uninstall_global
