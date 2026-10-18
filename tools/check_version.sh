#!/usr/bin/env bash
# Verify that every version source agrees. Usage: tools/check_version.sh [tag]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
latest="$(tr -d '\r\n' < "$root/LATEST")"

read_constant() {
    sed -nE "s/^$2[[:space:]]*=[[:space:]]*[\"']([^\"']+)[\"']/\\1/p" "$1" | head -n1
}

bash_script="$(read_constant "$root/cb.sh" CBUILD_VERSION)"
python_script="$(read_constant "$root/cb.py" CBUILD_VERSION)"
version="$bash_script"
plugin="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$root/tools/cbuild-plugin-vscode/package.json")"
lock="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$root/tools/cbuild-plugin-vscode/package-lock.json")"
lock_root="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["packages"][""]["version"])' "$root/tools/cbuild-plugin-vscode/package-lock.json")"

status=0
check() {
    if [[ "$2" != "$version" ]]; then
        printf 'Mismatch: %-45s %s (expected %s)\n' "$1" "$2" "$version" >&2
        status=1
    fi
}

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)*$ ]] ||
    { echo "Invalid CBUILD_VERSION: $version" >&2; exit 1; }
[[ "$latest" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]] ||
    { echo "Invalid LATEST (expected a tag such as v0.1.0): $latest" >&2; exit 1; }
check cb.sh "$bash_script"
check cb.py "$python_script"
check tools/cbuild-plugin-vscode/package.json "$plugin"
check tools/cbuild-plugin-vscode/package-lock.json "$lock"
check 'package-lock.json packages[""]' "$lock_root"

# install.sh intentionally has no self-version constant: tags identify releases,
# and LATEST records the last published tag.

if (($# > 0)); then
    tag="$1"
    [[ "$tag" == "v$version" || "$tag" == "v$version"-* ]] ||
        { echo "Tag $tag does not match script version $version" >&2; status=1; }
    [[ "$tag" == "$latest" ]] ||
        { echo "Tag $tag does not match LATEST $latest" >&2; status=1; }
fi

if ((status == 0)); then
    echo "Version checks passed: $version"
fi
exit "$status"
