#!/bin/bash

set -euo pipefail

arg_path="$(pwd -P)"
if [[ "$arg_path" == /cygdrive/* ]]; then
    arg_path="$(cygpath -w "$arg_path")"
    arg_path="${arg_path//\\//}"
fi

mode="global"
install_variant="bash"
global_install_dir="${HOME}/.cbuild"
prefix_set="false"
assume_yes="false"
vscode_target_dir="$arg_path"
config_target_dir="$arg_path"
release="latest"
source_name="github"
custom_base_url=""
raw_base_url=""
staging_dir=""

# A globally installed updater retains its own prefix, variant, and source.
# Read only known data fields; never source a manifest. Detection is based on
# the adjacent installation manifest, not on the script's filename.
script_parent="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -f "$script_parent/.install.cfg" ]]; then
    global_install_dir="$script_parent"
    while IFS= read -r line; do
        case "$line" in
            'INSTALL_VARIANT="python"') install_variant="python" ;;
            'INSTALL_VARIANT="bash"') install_variant="bash" ;;
            'INSTALL_SOURCE="gitee"'|*'gitee.com'*) source_name="gitee" ;;
            'INSTALL_SOURCE="github"'|*'github'*) source_name="github" ;;
        esac
    done < "$global_install_dir/.install.cfg"
fi

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
cleanup() { [[ -z "$staging_dir" ]] || rm -rf -- "$staging_dir"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

print_help() {
    cat <<'EOF'
Usage:
  install.sh [--python|--bash] [--global] [--prefix <dir>] [--release <tag|latest>]
  install.sh [--python|--bash] --simple [--release <tag|latest>]
  install.sh --vscode [<directory>] [--release <tag|latest>]
  install.sh --config [<directory>] [--release <tag|latest>]
  install.sh --format [--release <tag|latest>]
  install.sh --uninstall [--prefix <dir>] [--yes]

Options:
  --bash            Install Bash variant (default for a fresh installation)
  --python          Install Python variant
  -s, --simple      Install to current project
  -g, --global      Install globally (default)
  --prefix <dir>    Global install directory (default: ~/.cbuild)
  --release <tag>   Version tag such as v0.1.0; default: tag in source master/LATEST
  --source <name>   Preferred tag file source: github (default) or gitee
  --base-url <url>  Custom raw URL template containing {tag}; no public fallback
  --vscode [dir]    Install only .vscode templates (default: current directory)
  --config [dir]    Install only cb.conf (default: current directory)
  --format          Install only .clang-format in current directory
  --uninstall       Uninstall global installation (local only, no network)
  --yes             Skip the uninstall confirmation (required when non-interactive)
  -h, --help        Show this help

All download modes default to the tag in the selected source's master/LATEST.
An explicit version downloads that tag directly without this lookup.
cb_install.sh keeps its installation directory and variant unless overridden.
Do not run concurrent installations/updates into the same directory.
EOF
}

require_value() {
    [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || fail "$1 requires a value"
}

while (($# > 0)); do
    case "$1" in
        format|--format) mode="format"; shift ;;
        -s|--simple|simple) mode="simple"; shift ;;
        -g|--global|global) mode="global"; shift ;;
        --uninstall|uninstall) mode="uninstall"; shift ;;
        --vscode|vscode)
            mode="vscode"
            if (($# > 1)) && [[ "$2" != -* ]]; then vscode_target_dir="$2"; shift; fi
            shift ;;
        --config|config|--conf|conf)
            mode="config"
            if (($# > 1)) && [[ "$2" != -* ]]; then config_target_dir="$2"; shift; fi
            shift ;;
        python|--python|py|--py) install_variant="python"; shift ;;
        bash|--bash|sh|--sh) install_variant="bash"; shift ;;
        --prefix) require_value "$@"; global_install_dir="$2"; prefix_set="true"; shift 2 ;;
        --yes|-y) assume_yes="true"; shift ;;
        --release) require_value "$@"; release="$2"; shift 2 ;;
        --source) require_value "$@"; source_name="$2"; shift 2 ;;
        --base-url) require_value "$@"; custom_base_url="$2"; shift 2 ;;
        --version) fail "install.sh --version was removed; run cb.sh --version after installation" ;;
        -h|--help) print_help; exit 0 ;;
        *) fail "Unknown option: $1" ;;
    esac
done

if [[ "$mode" == "uninstall" ]]; then
    # Uninstall is local-only and intentionally handled before release/network
    # resolution. An installed cb_install.sh targets its own directory.
    uninstall_dir="$global_install_dir"
    if [[ "$prefix_set" != "true" && -f "$script_parent/.install.cfg" ]]; then
        uninstall_dir="$script_parent"
    fi
    [[ -d "$uninstall_dir" ]] || fail "Installation directory not found: $uninstall_dir"
    uninstall_dir="$(cd "$uninstall_dir" && pwd -P)"
    home_dir="$(cd "${HOME}" && pwd -P)"
    [[ "$uninstall_dir" != "/" && "$uninstall_dir" != "$home_dir" ]] ||
        fail "Refusing to uninstall unsafe directory: $uninstall_dir"
    [[ -f "$uninstall_dir/.install.cfg" ]] ||
        fail "Not a cbuild installation (missing .install.cfg): $uninstall_dir"

    printf 'Install directory: %s\n' "$uninstall_dir"
    installed_release="$(sed -n 's/^INSTALL_RELEASE="\(.*\)"$/\1/p' "$uninstall_dir/.install.cfg" | head -n1)"
    if [[ -n "$installed_release" ]]; then
        printf 'Installed release: %s\n' "$installed_release"
    fi

    if [[ "$assume_yes" != "true" ]]; then
        [[ -t 0 ]] || fail "Non-interactive uninstall requires --yes"
        read -r -p 'Confirm uninstall? [y/N] ' confirm
        case "$confirm" in
            [yY]|[yY][eE][sS]) ;;
            *) echo 'Uninstall cancelled.'; exit 0 ;;
        esac
    fi

    rc_file=""
    case "${SHELL:-}" in
        */bash) rc_file="$HOME/.bashrc" ;;
        */zsh) rc_file="$HOME/.zshrc" ;;
    esac
    if [[ -n "$rc_file" && -f "$rc_file" ]] && grep -qF "$uninstall_dir" "$rc_file"; then
        tmp_rc="$(mktemp)"
        awk -v dir="$uninstall_dir" '
            $0 == "# Added by cbuild install" { next }
            $0 ~ /^export PATH=/ && index($0, dir) { next }
            { print }
        ' "$rc_file" > "$tmp_rc"
        cat "$tmp_rc" > "$rc_file"
        rm -f "$tmp_rc"
        printf 'Cleaned PATH from %s\n' "$rc_file"
    fi
    rm -rf -- "$uninstall_dir"
    printf 'cbuild has been uninstalled: %s\n' "$uninstall_dir"
    exit 0
fi

[[ "$source_name" == "github" || "$source_name" == "gitee" ]] || fail "--source must be github or gitee"
if [[ -n "$custom_base_url" && "$custom_base_url" != *'{tag}'* ]]; then
    fail '--base-url must contain {tag}; unversioned URLs are no longer supported'
fi

_download_one() {
    local url="$1" destination="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 --max-time 120 "$url" -o "$destination" && return 0
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=120 -O "$destination" "$url" && return 0
    else
        printf 'Neither curl nor wget found.\n' >&2
    fi
    rm -f -- "$destination"
    return 1
}

# Only safe, version-shaped tags are supported, not arbitrary refs or URLs.
valid_tag() {
    [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]]
}

staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/cbuild-install.XXXXXX")"
if [[ "$release" == "latest" ]]; then
    [[ -z "$custom_base_url" ]] || fail "--base-url requires an explicit --release; latest is read from the selected source's master/LATEST"
    case "$source_name" in
        gitee) latest_url="https://gitee.com/wiseforever/cbuild/raw/master/LATEST" ;;
        *) latest_url="https://raw.githubusercontent.com/wiseforever/cbuild/master/LATEST" ;;
    esac
    latest_file="$staging_dir/latest-tag"
    _download_one "$latest_url" "$latest_file" ||
        fail "Cannot read $latest_url. Use --release vX.Y.Z or push LATEST to that source."
    release="$(tr -d ' \r\n' < "$latest_file")"
    valid_tag "$release" || fail "Invalid LATEST at $latest_url; expected one tag such as v0.1.0"
fi
valid_tag "$release" || fail "Invalid release tag: $release (expected vX.Y.Z or vX.Y.Z-rc.1)"

if [[ -n "$custom_base_url" ]]; then
    raw_base_url="${custom_base_url//\{tag\}/$release}"
elif [[ "$source_name" == "gitee" ]]; then
    raw_base_url="https://gitee.com/wiseforever/cbuild/raw/$release"
else
    raw_base_url="https://raw.githubusercontent.com/wiseforever/cbuild/$release"
fi
raw_base_url="${raw_base_url%/}"
printf 'Selected cbuild release: %s\nTag file source: %s\n' "$release" "$raw_base_url"

download_file() {
    local relative="$1" destination="$2"
    mkdir -p "$(dirname "$destination")"
    _download_one "$raw_base_url/$relative" "$destination" || return 1
    [[ -s "$destination" ]]
}

selected_tool="cb.sh"
[[ "$install_variant" != "python" ]] || selected_tool="cb.py"
vscode_files=(.vscode/c_cpp_header.code-snippets .vscode/c_cpp_properties.json .vscode/launch.json .vscode/settings.json)
case "$mode" in
    global) files=("$selected_tool" install.sh) ;;
    simple) files=("${vscode_files[@]}" "$selected_tool" cb.conf cmake/ez_custom_func.cmake) ;;
    vscode) files=("${vscode_files[@]}") ;;
    config) files=(cb.conf) ;;
    format) files=(.clang-format) ;;
esac
for relative in "${files[@]}"; do
    download_file "$relative" "$staging_dir/$relative" ||
        fail "Failed to download $relative from $release. Existing installation/project preserved."
done

# The selected tool carries CBUILD_VERSION. Verify it against the tag before
# touching an installation or project; config/template-only modes download no
# script, so they rely on the tag itself being immutable.
if [[ "$mode" == "global" || "$mode" == "simple" ]]; then
    staged_tool="$staging_dir/$selected_tool"
    case "$selected_tool" in
        cb.sh) tool_version="$(sed -nE 's/^CBUILD_VERSION="([^"]+)"$/\1/p' "$staged_tool" | head -n1)" ;;
        cb.py) tool_version="$(sed -nE 's/^CBUILD_VERSION = "([^"]+)"$/\1/p' "$staged_tool" | head -n1)" ;;
    esac
    [[ -n "$tool_version" ]] || fail "Cannot read CBUILD_VERSION from downloaded $selected_tool; existing files preserved"
    [[ "v$tool_version" == "$release" || "$release" == "v$tool_version"-* ]] ||
        fail "Downloaded $selected_tool ($tool_version) does not match $release; existing files preserved"
fi

# The uninstaller is now implemented by this installer. Keep installing the
# compatibility wrapper when available, but never let it block a valid install.
if [[ "$mode" == "global" ]] && ! download_file cb_uninstall.sh "$staging_dir/cb_uninstall.sh"; then
    rm -f "$staging_dir/cb_uninstall.sh"
    printf 'Warning: compatibility cb_uninstall.sh unavailable; the installer supports --uninstall directly.\n'
fi

update_shell_rc() {
    local dir_to_add="$1" rc_file=""
    case ":${PATH}:" in *":${dir_to_add}:"*) return 0 ;; esac
    case "${SHELL:-}" in
        */bash) rc_file="$HOME/.bashrc" ;;
        */zsh) rc_file="$HOME/.zshrc" ;;
        *) return 0 ;;
    esac
    if [[ -f "$rc_file" ]] && grep -qF "$dir_to_add" "$rc_file"; then return 0; fi
    { printf '\n# Added by cbuild install\n'; printf 'export PATH=%q:"$PATH"\n' "$dir_to_add"; } >> "$rc_file"
    printf 'Added %s to %s; restart your terminal to use it.\n' "$dir_to_add" "$rc_file"
}

if [[ "$mode" == "global" ]]; then
    mkdir -p "$global_install_dir"
    global_install_dir="$(cd "$global_install_dir" && pwd -P)"
    # Copy to a same-filesystem staging directory before individual atomic moves.
    publish_dir="$(mktemp -d "$global_install_dir/.cbuild-update.XXXXXX")"
    cp -R "$staging_dir/." "$publish_dir/"
    rm -rf -- "$staging_dir"
    staging_dir="$publish_dir"
    chmod +x "$staging_dir/$selected_tool" "$staging_dir/install.sh"
    if [[ -f "$staging_dir/cb_uninstall.sh" ]]; then
        chmod +x "$staging_dir/cb_uninstall.sh"
    fi
    {
        printf '# cbuild installation manifest\n'
        printf 'INSTALL_DIR=%q\n' "$global_install_dir"
        printf 'INSTALL_RELEASE="%s"\n' "$release"
        printf 'INSTALL_VARIANT="%s"\n' "$install_variant"
        printf 'INSTALL_SOURCE="%s"\n' "$source_name"
    } > "$staging_dir/.install.cfg"
    mv -f "$staging_dir/$selected_tool" "$global_install_dir/$selected_tool"
    mv -f "$staging_dir/install.sh" "$global_install_dir/cb_install.sh"
    if [[ -f "$staging_dir/cb_uninstall.sh" ]]; then
        mv -f "$staging_dir/cb_uninstall.sh" "$global_install_dir/cb_uninstall.sh"
    fi
    mv -f "$staging_dir/.install.cfg" "$global_install_dir/.install.cfg"
    if [[ "$install_variant" == "python" ]]; then
        rm -f "$global_install_dir/cb.sh"
    else
        rm -f "$global_install_dir/cb.py"
    fi
    printf 'Globally installed %s (%s) to: %s\n' "$install_variant" "$release" "$global_install_dir"
    update_shell_rc "$global_install_dir"
    exit 0
fi

case "$mode" in
    vscode) target_dir="$vscode_target_dir" ;;
    config) target_dir="$config_target_dir" ;;
    *) target_dir="$arg_path" ;;
esac
mkdir -p "$target_dir"
target_dir="$(cd "$target_dir" && pwd -P)"
backup_dir=""
backup_file() {
    local relative="$1"
    [[ -e "$target_dir/$relative" || -L "$target_dir/$relative" ]] || return 0
    if [[ -z "$backup_dir" ]]; then
        mkdir -p "$target_dir/cbuild_bak"
        backup_dir="$(mktemp -d "$target_dir/cbuild_bak/bak_$(date +%Y%m%d_%H%M%S)_XXXXXX")"
    fi
    mkdir -p "$(dirname "$backup_dir/$relative")"
    mv "$target_dir/$relative" "$backup_dir/$relative"
}
case "$mode" in
    simple)
        for relative in .vscode cb.sh cb.py cb.conf cmake/ez_custom_func.cmake; do backup_file "$relative"; done
        ;;
    vscode) backup_file .vscode ;;
    config) backup_file cb.conf ;;
    format) backup_file .clang-format ;;
esac
for relative in "${files[@]}"; do
    mkdir -p "$(dirname "$target_dir/$relative")"
    cp "$staging_dir/$relative" "$target_dir/$relative"
done
if [[ "$mode" == "simple" ]]; then chmod +x "$target_dir/$selected_tool"; fi
printf 'Installed %s files from %s to: %s\n' "$mode" "$release" "$target_dir"
