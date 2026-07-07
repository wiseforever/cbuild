#!/bin/bash

set -euo pipefail

arg_path=$(pwd)
if [[ $arg_path == /cygdrive/* ]]; then
    arg_path=$(cygpath -w "$arg_path")
    arg_path=${arg_path//\\//}
fi

# 默认下载源，可通过 --base-url 指定其他镜像
raw_base_url="https://gitee.com/wiseforever/cbuild/raw/master"
bak_dir="${arg_path}/cbuild_bak"
date_str=$(date "+%Y%m%d_%H%M%S")

tool_python="cb.py"
tool_bash="cb.sh"
tool_conf="cb_conf.ini"
tool_uninstall="uninstall.sh"
tasks_python=".vscode/tasks_python.json"
tasks_bash=".vscode/tasks_bash.json"
clang_format_file=".clang-format"
cmake_file="cmake/ez_custom_func.cmake"

mode="simple"
install_variant="python"
global_install_dir="${HOME}/.cbuild"
global_bin_dir="${HOME}/.cbuild/bin"
global_cmd_name="cb"

print_help() {
    cat <<'EOF'
用法 / Usage:
  ./install.sh [--python|--bash] [--simple]
  ./install.sh [--python|--bash] --global [--prefix <dir>] [--bin-dir <dir>] [--cmd <name>]
  ./install.sh --uninstall
  ./install.sh --format

选项 / Options:
  --bash            安装 Bash 版本 / Install Bash variant
  --python          安装 Python 版本（默认）/ Install Python variant (default)
  -s, --simple      普通安装模式（默认）/ Install to current project (default)
  --global          全局安装模式（安装工具到共享目录并生成可执行命令）
                    / Install globally (shared dir + executable launcher)
  --prefix <dir>    全局安装目录（默认: ~/.cbuild）
                    / Global install directory (default: ~/.cbuild)
  --bin-dir <dir>   全局命令目录（默认: ~/.cbuild/bin）
                    / Binary/launcher directory (default: ~/.cbuild/bin)
  --cmd <name>      全局命令名（默认: cb）
                    / Command name (default: cb)
  --uninstall       卸载全局安装 / Uninstall global installation
  --base-url <url>  自定义下载镜像地址 / Custom download base URL
  format, --format  仅拉取 .clang-format / Fetch only .clang-format
  -h, --help        显示帮助 / Show this help
EOF
}

download_file() {
    local rel_path="$1"
    local dest_path="$2"
    local url="${raw_base_url}/${rel_path}"
    local tmp_path="${dest_path}.cbtmp.$$"

    mkdir -p "$(dirname "$dest_path")"

    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "$url" -o "$tmp_path"; then
            rm -f "$tmp_path"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -qO "$tmp_path" "$url"; then
            rm -f "$tmp_path"
            return 1
        fi
    else
        echo "未找到 curl 或 wget，无法下载文件。"
        return 1
    fi

    mv -f "$tmp_path" "$dest_path"
}

while (($# > 0)); do
    arg="$1"
    case "$arg" in
        format|--format)
            mode="format"
            shift
            ;;
        -s|--simple|simple)
            mode="simple"
            shift
            ;;
        -g|--global|global)
            mode="global"
            shift
            ;;
        --uninstall|uninstall)
            mode="uninstall"
            shift
            ;;
        python|--python|py|--py)
            install_variant="python"
            shift
            ;;
        bash|--bash|sh|--sh)
            install_variant="bash"
            shift
            ;;
        --prefix)
            if (($# < 2)); then
                echo "参数 --prefix 需要一个目录"
                exit 1
            fi
            global_install_dir="$2"
            shift 2
            ;;
        --bin-dir)
            if (($# < 2)); then
                echo "参数 --bin-dir 需要一个目录"
                exit 1
            fi
            global_bin_dir="$2"
            shift 2
            ;;
        --cmd)
            if (($# < 2)); then
                echo "参数 --cmd 需要一个命令名"
                exit 1
            fi
            global_cmd_name="$2"
            shift 2
            ;;
        --base-url)
            if (($# < 2)); then
                echo "参数 --base-url 需要一个 URL"
                exit 1
            fi
            raw_base_url="$2"
            shift 2
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "未知参数: $arg"
            print_help
            exit 1
            ;;
    esac
done

selected_tool="$tool_bash"
selected_tasks_template="$tasks_bash"
if [[ "$install_variant" == "python" ]]; then
    selected_tool="$tool_python"
    selected_tasks_template="$tasks_python"
fi

# --- 卸载模式 ---
if [[ "$mode" == "uninstall" ]]; then
    # 尝试多个常见路径寻找已安装的卸载脚本
    for candidate_dir in "$global_install_dir"; do
        candidate_uninstall="${candidate_dir}/uninstall.sh"
        if [[ -f "$candidate_uninstall" ]]; then
            echo "找到已安装的 cbuild: ${candidate_dir}"
            exec bash "$candidate_uninstall"
        fi
    done

    echo "未找到已安装的 cbuild 全局安装。"
    echo "如需手动卸载，请删除以下内容："
    echo "  安装目录: ${global_install_dir}"
    echo "  命令入口: ${global_bin_dir}/${global_cmd_name}"
    exit 1
fi

if [[ "$mode" == "format" ]]; then
    if [[ -f "${arg_path}/$clang_format_file" ]]; then
        mkdir -p "${bak_dir}/bak_${date_str}"
        mv "${arg_path}/$clang_format_file" "${bak_dir}/bak_${date_str}/"
    fi

    if ! download_file "$clang_format_file" "${arg_path}/$clang_format_file"; then
        echo "下载 $clang_format_file 失败，请检查网络或仓库地址是否正确！"
        exit 1
    fi

    echo "已更新 $clang_format_file 到当前目录。"
    exit 0
fi

if [[ "$mode" == "global" ]]; then
    mkdir -p "$global_install_dir" "$global_bin_dir"

    if [[ "$install_variant" == "python" ]]; then
        download_file "$tool_python" "$global_install_dir/$tool_python" || {
            echo "下载 ${tool_python} 失败！"
            exit 1
        }
        chmod +x "$global_install_dir/$tool_python"
    else
        download_file "$tool_bash" "$global_install_dir/$tool_bash" || {
            echo "下载 ${tool_bash} 失败！"
            exit 1
        }
        chmod +x "$global_install_dir/$tool_bash"
    fi

    download_file "$tool_conf" "$global_install_dir/$tool_conf" || {
        echo "下载 ${tool_conf} 失败！"
        exit 1
    }

    # 安装卸载脚本
    download_file "$tool_uninstall" "$global_install_dir/$tool_uninstall" || {
        echo "下载 ${tool_uninstall} 失败！"
        exit 1
    }
    chmod +x "$global_install_dir/$tool_uninstall"

    launcher_path="${global_bin_dir}/${global_cmd_name}"
    if [[ "$install_variant" == "python" ]]; then
        cat > "$launcher_path" <<EOF
#!/usr/bin/env bash
set -e
exec python3 "${global_install_dir}/${tool_python}" "\$@"
EOF
    else
        cat > "$launcher_path" <<EOF
#!/usr/bin/env bash
set -e
exec bash "${global_install_dir}/${tool_bash}" "\$@"
EOF
    fi
    chmod +x "$launcher_path"

    # 写入安装清单，供卸载脚本使用
    cat > "${global_install_dir}/.install.cfg" <<EOF
# cbuild 安装配置 - 供卸载脚本使用
LAUNCHER_PATH="${launcher_path}"
INSTALL_DIR="${global_install_dir}"
CMD_NAME="${global_cmd_name}"
INSTALL_VARIANT="${install_variant}"
EOF

    echo "已全局安装 ${install_variant} 版本到: ${global_install_dir}"
    echo "命令入口: ${launcher_path}"
    echo "卸载方式: ${global_install_dir}/${tool_uninstall}"
    case ":${PATH}:" in
        *":${global_bin_dir}:"*) ;;
        *)
            echo "提示: 当前 PATH 不含 ${global_bin_dir}，请将其加入 PATH 后再直接使用 ${global_cmd_name}。"
            ;;
    esac
    exit 0
fi

if [[ -d "${arg_path}/.vscode" ]]; then
    mkdir -p "${bak_dir}/bak_${date_str}"
    mv "${arg_path}/.vscode" "${bak_dir}/bak_${date_str}/"
fi

if [[ -f "${arg_path}/$cmake_file" ]]; then
    mkdir -p "${bak_dir}/bak_${date_str}/cmake"
    mv "${arg_path}/$cmake_file" "${bak_dir}/bak_${date_str}/cmake/"
fi

if [[ -f "${arg_path}/$tool_python" ]]; then
    mkdir -p "${bak_dir}/bak_${date_str}"
    mv "${arg_path}/$tool_python" "${bak_dir}/bak_${date_str}/"
fi

if [[ -f "${arg_path}/$tool_bash" ]]; then
    mkdir -p "${bak_dir}/bak_${date_str}"
    mv "${arg_path}/$tool_bash" "${bak_dir}/bak_${date_str}/"
fi

if [[ -f "${arg_path}/$tool_conf" ]]; then
    mkdir -p "${bak_dir}/bak_${date_str}"
    mv "${arg_path}/$tool_conf" "${bak_dir}/bak_${date_str}/"
fi

if [[ "$mode" == "simple" ]]; then
    download_file ".vscode/c_cpp_header.code-snippets" "${arg_path}/.vscode/c_cpp_header.code-snippets" || {
        echo "下载 .vscode/c_cpp_header.code-snippets 失败！"
        exit 1
    }
    download_file ".vscode/c_cpp_properties.json" "${arg_path}/.vscode/c_cpp_properties.json" || {
        echo "下载 .vscode/c_cpp_properties.json 失败！"
        exit 1
    }
    download_file ".vscode/launch.json" "${arg_path}/.vscode/launch.json" || {
        echo "下载 .vscode/launch.json 失败！"
        exit 1
    }
    download_file ".vscode/settings.json" "${arg_path}/.vscode/settings.json" || {
        echo "下载 .vscode/settings.json 失败！"
        exit 1
    }
    download_file "$tasks_bash" "${arg_path}/$tasks_bash" || {
        echo "下载 ${tasks_bash} 失败！"
        exit 1
    }
    download_file "$tasks_python" "${arg_path}/$tasks_python" || {
        echo "下载 ${tasks_python} 失败！"
        exit 1
    }
    download_file "$selected_tool" "${arg_path}/$selected_tool" || {
        echo "下载 ${selected_tool} 失败！"
        exit 1
    }
    download_file "$tool_conf" "${arg_path}/$tool_conf" || {
        echo "下载 ${tool_conf} 失败！"
        exit 1
    }
    download_file "$cmake_file" "${arg_path}/$cmake_file" || {
        echo "下载 ${cmake_file} 失败！"
        exit 1
    }

    cp -a "${arg_path}/$selected_tasks_template" "${arg_path}/.vscode/tasks.json"
fi

echo "已安装 ${install_variant} 版本：.vscode(含 tasks.json)、${selected_tool}、${tool_conf}、${cmake_file}"
