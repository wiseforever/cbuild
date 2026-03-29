#!/bin/bash

set -euo pipefail

arg_path=$(pwd)
if [[ $arg_path == /cygdrive/* ]]; then
    arg_path=$(cygpath -w "$arg_path")
    arg_path=${arg_path//\\//}
fi

raw_base_url="https://gitee.com/wiseforever/cbuild/raw/master"
bak_dir="${arg_path}/cbuild_bak"
date_str=$(date "+%Y%m%d_%H%M%S")

tool_python="cb.py"
tool_bash="cb.sh"
tool_conf="cb_conf.ini"
tasks_python=".vscode/tasks_python.json"
tasks_bash=".vscode/tasks_bash.json"
clang_format_file=".clang-format"
cmake_file="cmake/ez_custom_func.cmake"

mode="simple"
install_variant="bash"

print_help() {
    cat <<'EOF'
Usage:
  ./install.sh [--python|--bash] [--simple]
  ./install.sh --format

Options:
  --bash            安装 Bash 版本（默认）
  --python          安装 Python 版本
  -s, --simple      普通安装模式（默认）
  format, --format  仅拉取 .clang-format
  -h, --help        显示帮助
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

for arg in "$@"; do
    case "$arg" in
        format|--format)
            mode="format"
            ;;
        -s|--simple|simple)
            mode="simple"
            ;;
        python|--python|py|--py)
            install_variant="python"
            ;;
        bash|--bash|sh|--sh)
            install_variant="bash"
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
