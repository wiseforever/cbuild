#!/bin/bash

arg_path=$(pwd)
if [[ $arg_path == /cygdrive/* ]]; then
    arg_path=$(cygpath -w "$arg_path")
    arg_path=${arg_path//\\//}
fi

repo_url="https://gitee.com/wiseforever/cbuild-py.git"
temp_dir="${arg_path}/cbuild-py_tmp"
bak_dir="${arg_path}/cbuild-py_bak"
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

for arg in "$@"; do
    case "$arg" in
        format|--format)
            mode="format"
            ;;
        -s|--simple|simple)
            mode="simple"
            ;;
        python|--python)
            install_variant="python"
            ;;
        bash|--bash)
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

mkdir -p "$temp_dir" || {
    echo "创建临时目录失败，请检查目录权限或路径是否正确！"
    exit 1
}

git clone --depth=1 "$repo_url" "$temp_dir" || {
    rm -rf "$temp_dir"
    echo "克隆仓库失败，请检查网络、git环境或仓库地址是否正确！"
    exit 1
}

if [[ ! -d "$temp_dir" ]]; then
    echo "克隆仓库失败，请检查网络、git环境或仓库地址是否正确！"
    exit 1
fi

if [[ "$mode" == "format" ]]; then
    if [[ ! -f "$temp_dir/$clang_format_file" ]]; then
        rm -rf "$temp_dir"
        echo "远程仓库未找到 $clang_format_file 文件，请检查仓库是否正确克隆！"
        exit 1
    fi

    if [[ -f "${arg_path}/$clang_format_file" ]]; then
        mkdir -p "${bak_dir}/bak_${date_str}"
        mv "${arg_path}/$clang_format_file" "${bak_dir}/bak_${date_str}/"
    fi

    cp -a "$temp_dir/$clang_format_file" "$arg_path" 2>/dev/null
    rm -rf "$temp_dir"
    echo "已更新 $clang_format_file 到当前目录。"
    exit 0
fi

if [[ ! -d "$temp_dir/.vscode" ]]; then
    rm -rf "$temp_dir"
    echo "未找到远程仓库的 .vscode 目录，请检查仓库是否正确克隆！"
    exit 1
fi

if [[ ! -d "$temp_dir/cmake" ]]; then
    rm -rf "$temp_dir"
    echo "未找到远程仓库的 cmake 目录，请检查仓库是否正确克隆！"
    exit 1
fi

if [[ ! -f "$temp_dir/$selected_tool" ]]; then
    rm -rf "$temp_dir"
    echo "未找到 ${selected_tool}，请检查仓库是否正确克隆！"
    exit 1
fi

if [[ ! -f "$temp_dir/$tool_conf" ]]; then
    rm -rf "$temp_dir"
    echo "未找到 ${tool_conf}，请检查仓库是否正确克隆！"
    exit 1
fi

if [[ ! -f "$temp_dir/$selected_tasks_template" ]]; then
    rm -rf "$temp_dir"
    echo "未找到 ${selected_tasks_template}，请检查仓库是否正确克隆！"
    exit 1
fi

if [[ ! -f "$temp_dir/$cmake_file" ]]; then
    rm -rf "$temp_dir"
    echo "未找到 ${cmake_file}，请检查仓库是否正确克隆！"
    exit 1
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
    cp -a "$temp_dir/.vscode" "$arg_path" 2>/dev/null
    cp -a "$temp_dir/$selected_tool" "$arg_path" 2>/dev/null
    cp -a "$temp_dir/$tool_conf" "$arg_path" 2>/dev/null
    cp -a "$temp_dir/$selected_tasks_template" "${arg_path}/.vscode/tasks.json" 2>/dev/null
    mkdir -p "${arg_path}/cmake"
    cp -a "$temp_dir/$cmake_file" "${arg_path}/cmake/" 2>/dev/null
fi

rm -rf "$temp_dir"
echo "已安装 ${install_variant} 版本：.vscode(含 tasks.json)、${selected_tool}、${tool_conf}、${cmake_file}"
