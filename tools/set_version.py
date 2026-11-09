#!/usr/bin/env python3
"""Update core script versions; optionally prepare the local release pointer."""

import argparse
import os
from pathlib import Path
import re
import stat
import sys
import tempfile

VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?\Z")
ASSIGNMENT = re.compile(rb"^CBUILD_VERSION[ \t]*=.*$", re.MULTILINE)
CONSTANT = re.compile(rb"^(CBUILD_VERSION[ \t]*=[ \t]*)([\"'])([^\"'\r\n]+)(\2)([^\r\n]*)$")
ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(
        description="Update core versions, without creating commits, tags or pushing. "
        "Updating local LATEST is not publishing: push the tag before master."
    )
    parser.add_argument("version", help="core version, e.g. 0.2.1 or 0.2.1-rc.1 (no v)")
    parser.add_argument("--latest", action="store_true", help="also prepare local LATEST for release")
    args = parser.parse_args()
    if not VERSION.fullmatch(args.version):
        parser.error("VERSION must be X.Y.Z or X.Y.Z-prerelease, without a v prefix")

    updates = []
    for name in ("cb.sh", "cb.py"):
        path = ROOT / name
        data = path.read_bytes()
        matches = list(ASSIGNMENT.finditer(data))
        if len(matches) != 1:
            raise ValueError(f"{name}: expected exactly one CBUILD_VERSION assignment")
        match = CONSTANT.fullmatch(matches[0].group())
        if not match or not VERSION.fullmatch(match.group(3).decode("ascii")):
            raise ValueError(f"{name}: invalid CBUILD_VERSION assignment")
        start, end = matches[0].span(0)
        replacement = match.group(1) + match.group(2) + args.version.encode("ascii") + match.group(4) + match.group(5)
        updates.append((path, data, data[:start] + replacement + data[end:], path.stat().st_mode))

    if args.latest:
        path = ROOT / "LATEST"
        data = path.read_bytes()
        if not re.fullmatch(rb"v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?\n?", data):
            raise ValueError("LATEST: invalid release tag")
        new_data = b"v" + args.version.encode("ascii") + (b"\n" if data.endswith(b"\n") else b"")
        updates.append((path, data, new_data, path.stat().st_mode))

    for path, old, new, mode in updates:
        if old == new:
            continue
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.", delete=False) as output:
                temporary = output.name
                output.write(new)
            os.chmod(temporary, stat.S_IMODE(mode))
            os.replace(temporary, path)
        finally:
            if temporary and os.path.exists(temporary):
                os.unlink(temporary)
    print(f"Core version set to {args.version}" + ("; local LATEST prepared" if args.latest else ""))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, UnicodeError) as error:
        print(f"set_version: {error}", file=sys.stderr)
        sys.exit(1)
