#!/bin/bash
# Compatibility wrapper. Uninstall is implemented by install.sh / cb_install.sh.
# Installed copies target their own directory; the repository copy targets ~/.cbuild.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
installer=""
for candidate in "$script_dir/cb_install.sh" "$script_dir/install.sh"; do
    if [[ -f "$candidate" ]]; then
        installer="$candidate"
        break
    fi
done

case "${1:-}" in
    -h|--help)
        cat <<EOF
Usage: $(basename "$0") [--prefix <dir>] [--yes]

Compatibility wrapper for cbuild uninstall.
Uninstall is implemented by install.sh / cb_install.sh.
An installed wrapper removes its own directory; a repository copy defaults to ~/.cbuild.

Options:
  --prefix <dir>  Installation directory to remove
  --yes           Skip confirmation (required when non-interactive)
  -V, --version   Show the installed cbuild version
  -h, --help      Show this help
EOF
        exit 0
        ;;
    -V|--version)
        for dir in "$script_dir" "${HOME}/.cbuild"; do
            release=""
            if [[ -f "$dir/.install.cfg" ]]; then
                release="$(sed -n 's/^INSTALL_RELEASE="\(.*\)"$/\1/p' "$dir/.install.cfg" | head -n1)"
            elif [[ -f "$dir/LATEST" ]]; then
                release="$(tr -d ' \r\n' < "$dir/LATEST")"
            fi
            if [[ -n "$release" ]]; then
                printf 'cbuild %s\n' "${release#v}"
                exit 0
            fi
        done
        echo "Installed cbuild version is unknown (no installation manifest)."
        exit 0
        ;;
esac

[[ -n "$installer" ]] || {
    echo "Error: cb_install.sh or install.sh not found next to $script_dir" >&2
    exit 1
}

if [[ -f "$script_dir/.install.cfg" ]]; then
    exec bash "$installer" --uninstall --prefix "$script_dir" "$@"
else
    exec bash "$installer" --uninstall "$@"
fi
