#!/bin/bash

set -euo pipefail

arg_path=$(pwd)
if [[ $arg_path == /cygdrive/* ]]; then
    arg_path=$(cygpath -w "$arg_path")
    arg_path=${arg_path//\\//}
fi

# 默认下载源，可通过 --base-url 指定其他镜像
raw_base_url="https://gitee.com/wiseforever/cbuild/raw/master"
fallback_base_url="https://raw.githubusercontent.com/wiseforever/cbuild/master"
bak_dir="${arg_path}/cbuild_bak"
date_str=$(date "+%Y%m%d_%H%M%S")

tool_python="cb.py"
tool_bash="cb.sh"
tool_conf="cb_conf.ini"
tool_install="install.sh"
tool_uninstall="cb_uninstall.sh"
clang_format_file=".clang-format"
cmake_file="cmake/ez_custom_func.cmake"

mode="global"
install_variant="bash"
global_install_dir="${HOME}/.cbuild"
vscode_target_dir="${arg_path}"

print_help() {
    cat <<'EOF'
Usage:
  ./install.sh [--python|--bash] [--global] [--prefix <dir>]
  ./install.sh [--python|--bash] --simple
  ./install.sh --vscode [<directory>]
  ./install.sh --uninstall
  ./install.sh --format

Options:
  --bash            Install Bash variant (default)
  --python          Install Python variant
  -s, --simple      Install to current project
  --global          Install globally (default; shared directory)
  --prefix <dir>    Install directory (default: ~/.cbuild)
  --uninstall       Uninstall global installation
  --vscode [dir]    Install only .vscode templates to dir (default: current directory)
  --base-url <url>  Custom download base URL
  format, --format  Fetch only .clang-format
  -h, --help        Show this help
EOF
}

download_file() {
    local rel_path="$1"
    local dest_path="$2"
    local tmp_path="${dest_path}.cbtmp.$$"

    mkdir -p "$(dirname "$dest_path")"

    # Try primary URL, fall back to mirror on failure
    local url="${raw_base_url}/${rel_path}"
    if ! _download_one "$url" "$tmp_path"; then
        if [[ -n "$fallback_base_url" && "$raw_base_url" != "$fallback_base_url" ]]; then
            url="${fallback_base_url}/${rel_path}"
            _download_one "$url" "$tmp_path" || return 1
        else
            return 1
        fi
    fi

    mv -f "$tmp_path" "$dest_path"
}

make_executable_on_unix() {
    local file_path="$1"
    case "$(uname -s)" in
        Linux|Darwin)
            chmod +x "$file_path"
            ;;
    esac
}

_download_one() {
    local url="$1" tmp_path="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$tmp_path" && return 0
        rm -f "$tmp_path"
        return 1
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp_path" "$url" && return 0
        rm -f "$tmp_path"
        return 1
    else
        echo "Error: neither curl nor wget found. Cannot download files."
        return 1
    fi
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
        --vscode|vscode)
            mode="vscode"
            if (($# > 1)) && [[ "$2" != -* ]]; then
                vscode_target_dir="$2"
                shift 2
            else
                shift
            fi
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
                echo "Error: --prefix requires a directory"
                exit 1
            fi
            global_install_dir="$2"
            shift 2
            ;;
        --base-url)
            if (($# < 2)); then
                echo "Error: --base-url requires a URL"
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
            echo "Unknown option: $arg"
            print_help
            exit 1
            ;;
    esac
done

selected_tool="$tool_bash"
if [[ "$install_variant" == "python" ]]; then
    selected_tool="$tool_python"
fi

# --- 卸载模式 ---
if [[ "$mode" == "uninstall" ]]; then
    # 尝试多个常见路径寻找已安装的卸载脚本
    for candidate_dir in "$global_install_dir"; do
        candidate_uninstall="${candidate_dir}/${tool_uninstall}"
        if [[ -f "$candidate_uninstall" ]]; then
            echo "Found cbuild installation at: ${candidate_dir}"
            exec bash "$candidate_uninstall"
        fi
    done

    echo "No cbuild global installation found."
    echo "To uninstall manually, remove the following:"
    echo "  Install directory: ${global_install_dir}"
    exit 1
fi

if [[ "$mode" == "format" ]]; then
    if [[ -f "${arg_path}/$clang_format_file" ]]; then
        mkdir -p "${bak_dir}/bak_${date_str}"
        mv "${arg_path}/$clang_format_file" "${bak_dir}/bak_${date_str}/"
    fi

    if ! download_file "$clang_format_file" "${arg_path}/$clang_format_file"; then
        echo "Failed to download $clang_format_file. Please check network or repository URL."
        exit 1
    fi

    echo "$clang_format_file has been updated in the current directory."
    exit 0
fi

# Auto-add install dir to PATH via shell rc file (Linux / macOS)
update_shell_rc() {
  local dir_to_add="$1"

  # Already in PATH? skip
  case ":${PATH}:" in
    *":${dir_to_add}:"*)
      echo "PATH already contains ${dir_to_add}; no shell configuration changes needed."
      return 0
      ;;
  esac

  local rc_file=""
  case "${SHELL##*/}" in
    bash) rc_file="${HOME}/.bashrc" ;;
    zsh)  rc_file="${HOME}/.zshrc" ;;
    fish) rc_file="${HOME}/.config/fish/config.fish" ;;
    *)    return 1 ;;  # Unknown shell, skip
  esac

  # Check if line already exists in rc file
  if [[ -f "$rc_file" ]] && grep -qF "${dir_to_add}" "$rc_file" 2>/dev/null; then
    echo "PATH entry for ${dir_to_add} already exists in ${rc_file}; no changes needed."
    return 0
  fi

  # Append
  { echo ""; echo "# Added by cbuild install"; echo "export PATH=\"${dir_to_add}:\$PATH\""; } >> "$rc_file"
  echo "Added ${dir_to_add} to ${rc_file}"
  echo "Run 'source ${rc_file}' or restart your terminal to use it."
}

install_vscode_templates() {
    local target_dir="$1"
    local target_vscode_dir="${target_dir}/.vscode"
    local target_bak_dir="${target_dir}/cbuild_bak/bak_${date_str}"

    if [[ -d "$target_vscode_dir" ]]; then
        mkdir -p "$target_bak_dir"
        mv "$target_vscode_dir" "$target_bak_dir/"
    fi

    download_file ".vscode/c_cpp_header.code-snippets" "${target_vscode_dir}/c_cpp_header.code-snippets" || return 1
    download_file ".vscode/c_cpp_properties.json" "${target_vscode_dir}/c_cpp_properties.json" || return 1
    download_file ".vscode/launch.json" "${target_vscode_dir}/launch.json" || return 1
    download_file ".vscode/settings.json" "${target_vscode_dir}/settings.json" || return 1

    echo "Installed .vscode templates to: ${target_vscode_dir}"
}

if [[ "$mode" == "global" ]]; then
    mkdir -p "$global_install_dir"

    if [[ -e "$global_install_dir/$tool_bash" || -e "$global_install_dir/$tool_python" || -e "$global_install_dir/$tool_install" ]]; then
        echo "Updating global installation: ${global_install_dir}"
    fi
    rm -f "$global_install_dir/$tool_bash" "$global_install_dir/$tool_python"

    if [[ "$install_variant" == "python" ]]; then
        download_file "$tool_python" "$global_install_dir/$tool_python" || {
            echo "Failed to download ${tool_python}!"
            exit 1
        }
        chmod +x "$global_install_dir/$tool_python"
    else
        download_file "$tool_bash" "$global_install_dir/$tool_bash" || {
            echo "Failed to download ${tool_bash}!"
            exit 1
        }
        chmod +x "$global_install_dir/$tool_bash"
    fi

    download_file "$tool_install" "$global_install_dir/$tool_install" || {
        echo "Failed to download ${tool_install}!"
        exit 1
    }
    chmod +x "$global_install_dir/$tool_install"

    # Install uninstall script alongside (optional, warn on failure)
    if download_file "$tool_uninstall" "$global_install_dir/$tool_uninstall"; then
        chmod +x "$global_install_dir/$tool_uninstall"
    else
        echo "Warning: Failed to download ${tool_uninstall}, skipping."
    fi

    # Write install manifest for uninstall.sh
    cat > "${global_install_dir}/.install.cfg" <<EOF
# cbuild install config - used by uninstall.sh
INSTALL_DIR="${global_install_dir}"
INSTALL_VARIANT="${install_variant}"
EOF

    echo "Globally installed ${install_variant} variant to: ${global_install_dir}"
    echo "Create cb_conf.ini in each project, or add one manually in ${global_install_dir} as a fallback."
    echo "Uninstall: ${global_install_dir}/${tool_uninstall}"
    update_shell_rc "$global_install_dir"
    exit 0
fi

if [[ "$mode" == "vscode" ]]; then
    install_vscode_templates "$vscode_target_dir" || {
        echo "Failed to install .vscode templates. Please check network or repository URL."
        exit 1
    }
    exit 0
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
    install_vscode_templates "$arg_path" || {
        echo "Failed to install .vscode templates. Please check network or repository URL."
        exit 1
    }
    download_file "$selected_tool" "${arg_path}/$selected_tool" || {
        echo "Failed to download ${selected_tool}!"
        exit 1
    }
    make_executable_on_unix "${arg_path}/$selected_tool"
    download_file "$tool_conf" "${arg_path}/$tool_conf" || {
        echo "Failed to download ${tool_conf}!"
        exit 1
    }
    download_file "$cmake_file" "${arg_path}/$cmake_file" || {
        echo "Failed to download ${cmake_file}!"
        exit 1
    }

fi

echo "Installed ${install_variant} variant: .vscode, ${selected_tool}, ${tool_conf}, ${cmake_file}"
