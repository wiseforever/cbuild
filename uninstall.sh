#!/bin/bash
# cbuild global uninstall script
# Installed by install.sh --global, also runnable from repo: bash uninstall.sh

set -euo pipefail

# Detect script directory (= install directory)
INSTALL_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)"

DEFAULT_INSTALL_DIR="${HOME}/.cbuild"

# Read install manifest
CONFIG_FILE="${INSTALL_DIR}/.install.cfg"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
elif [[ -f "${DEFAULT_INSTALL_DIR}/.install.cfg" ]]; then
    INSTALL_DIR="$DEFAULT_INSTALL_DIR"
    source "${INSTALL_DIR}/.install.cfg"
else
    echo "Error: no cbuild global installation found."
    echo ""
    echo "To uninstall manually, remove the following:"
    echo "  Install directory: ${DEFAULT_INSTALL_DIR}"
    echo ""
    echo "If you used a custom path, delete that directory directly."
    exit 1
fi

uninstall_global() {
    echo "========================================"
    echo "   cbuild Global Uninstall"
    echo "========================================"
    echo "  Install directory: ${INSTALL_DIR}"
    echo ""

    read -r -p "Confirm uninstall? [y/N] " confirm
    echo ""

    case "$confirm" in
        [yY]|[yY]es)
            if [[ -d "$INSTALL_DIR" ]]; then
                rm -rf "$INSTALL_DIR"
                echo "  ✓ Removed install directory: ${INSTALL_DIR}"
            else
                echo "  - Install directory not found: ${INSTALL_DIR}"
            fi

            echo ""
            echo "cbuild has been uninstalled."
            ;;
        *)
            echo "Uninstall cancelled."
            exit 0
            ;;
    esac
}

# --- Argument handling ---
case "${1:-}" in
    -h|--help)
        cat <<EOF
Usage: $(basename "$0") [options]

Uninstall cbuild global installation.
Reads config from ~/.cbuild/.install.cfg by default.

Options:
  -h, --help      Show this help
EOF
        exit 0
        ;;
esac

uninstall_global
