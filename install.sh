#!/bin/bash

arg_path=$(pwd)

if [[ $arg_path == /cygdrive/* ]]; then
    arg_path=$(cygpath -w $arg_path)
    arg_path=${arg_path//\\//}  # 将路径中的反斜杠替换为正斜杠
fi


tool_name="cb.py"
tool_conf_name="cb_conf.ini"
temp_dir=${arg_path}/cbuild-py_tmp
install_script_name="install.sh"
bak_dir="cbuild-py_bak"


# 参数解析
if [[ "$1" == "-format" || "$1" == "--format" ]]; then
    mode="format"
fi

mode="simple"
if [[ "$1" == "-s" || "$1" == "--simple" ]]; then
    mode="simple"
fi

if [[ "$1" == "-update" || "$1" == "--update" ]]; then
    mode="update"
fi


# 创建临时目录
mkdir -p "$temp_dir" || {
    echo "❌ 创建临时目录失败，请检查目录权限或路径是否正确！"
    exit 1
}
# echo "🔧 临时目录：$temp_dir"


# 克隆远程仓库（浅克隆）
git clone --depth=1 https://gitee.com/wiseforever/cbuild-py.git "$temp_dir" || {
    rm -rf "$temp_dir" # 删除临时目录
    echo "❌ 克隆仓库失败，请检查网络，git环境或仓库地址是否正确！"
    exit 1
}

if [ ! -d "$temp_dir" ]; then
    echo "❌ 克隆仓库失败，请检查网络，git环境或仓库地址是否正确！"
    exit 1
fi

if [[ $mode == "format" ]]; then
    if [[ -f "$temp_dir/.clang-format" ]]; then
        mkdir -p ${bak_dir}/bak_$date_str/
        mv ${arg_path}/.clang-format ${bak_dir}/bak_$date_str/
        cp -a "$temp_dir/.clang-format" ${arg_path} 2>/dev/null
        rm -rf "$temp_dir"
        exit 0
    else
        echo "远程仓库未找到 .clang-format 文件，请检查仓库是否正确克隆！"
        exit 1
    fi
fi

# 判断 $temp_dir/.vscode 与 $temp_dir/cmake 是否存在
if [ ! -d "$temp_dir/.vscode" ]; then
    rm -rf "$temp_dir" # 删除临时目录
    echo "❌ 未找到远程仓库的 .vscode 目录，请检查仓库是否正确克隆！"
    exit 1
fi

if [ ! -d "$temp_dir/cmake" ]; then
    rm -rf "$temp_dir" # 删除临时目录
    echo "❌ 未找到远程仓库的 cmake 目录，请检查仓库是否正确克隆！"
    exit 1
fi


date_str=$(date "+%Y%m%d_%H%M%S")

if [[ $mode == "update" ]]; then
    # 更新你需要的内容到当前目录
    if [[ -f "$temp_dir/${install_script_name}" ]]; then
        mkdir -p ${bak_dir}/bak_$date_str/
        mv ${arg_path}/${install_script_name} ${bak_dir}/bak_$date_str/
        cp -a "$temp_dir/${install_script_name}"  ${arg_path} 2>/dev/null
        rm -rf "$temp_dir"
        exit 0
    else
        echo "远程仓库未找到 ${install_script_name} 脚本，请检查仓库是否正确克隆！"
        exit 1
    fi
fi




# 检查当前了目录是否存在.vscode 和 tools 目录，若有则直接mv到当前目录tool_backup目录中备份
# 备份文件加上后缀时间戳，防止覆盖 确保同一时间备份的.vscode 和 tools 目录后缀时间戳相同

if [ -d ".vscode" ]; then
    mkdir -p ${bak_dir}
    mv ${arg_path}/.vscode ${bak_dir}/bak_$date_str/
fi

if [ -d "cmake" ]; then
    if [ -f "cmake/ez_custom_func.cmake" ]; then
        mkdir -p ${bak_dir}/bak_$date_str/cmake
        mv ${arg_path}/cmake/ez_custom_func.cmake ${bak_dir}/bak_$date_str/cmake/
    fi
fi

# 判断当前目录是否存在 cb.py 和 cb_conf.ini 文件
if [ -f "${tool_name}" ]; then
    mv ${tool_name} ${bak_dir}/bak_$date_str/
fi

if [ -f "${tool_conf_name}" ]; then
    mv ${tool_conf_name} ${bak_dir}/bak_$date_str/
fi




if [ ! -f "$temp_dir/${tool_name}" ]; then
    rm -rf "$temp_dir" # 删除临时目录
    echo "❌ 未找到 ${tool_name}，请检查仓库是否正确克隆！"
    exit 1
fi

if [[ $mode == "simple" ]]; then
    # 拷贝你需要的内容到当前目录
    cp -a "$temp_dir/.vscode" ${arg_path} 2>/dev/null
    cp -a "$temp_dir/${tool_name}"  ${arg_path} 2>/dev/null
    cp -a "$temp_dir/${tool_conf_name}"  ${arg_path} 2>/dev/null
    mkdir -p ${arg_path}/cmake
    cp -a "$temp_dir/cmake/ez_custom_func.cmake"  ${arg_path}/cmake/ 2>/dev/null
fi

# 清理临时目录
rm -rf "$temp_dir"

echo "✅ 已提取 .vscode、${tool_name}、${tool_conf_name}、cmake/ez_custom_func.cmake 到当前目录！"
