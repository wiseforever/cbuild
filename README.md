# cbuild

[中文文档](README_zhCN.md)

This repository provides a lightweight build workflow for C/C++ projects, with optional VSCode integration and Conan support.

## Table of Contents

- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Global Install](#global-install)
- [Project Bootstrap](#project-bootstrap)
- [Uninstall](#uninstall)
- [cb.py / cb.sh Usage](#cbpy--cbsh-usage)
  - [cb.conf Parameters](#cbconf-parameters)
  - [Command Reference](#command-reference)
- [VSCode Configuration](#vscode-configuration)
- [Conan Usage](#conan-usage)

## Quick Start

```bash
# Bash variant (default) — install globally
curl -fsSL https://raw.githubusercontent.com/wiseforever/cbuild/master/install.sh | bash

cd my-project
# cb.conf is required; install it first (existing files are backed up)
curl -fsSL https://raw.githubusercontent.com/wiseforever/cbuild/master/install.sh | \
  bash -s -- --config

# Generate, build, and run
~/.cbuild/cb.sh -g
~/.cbuild/cb.sh -b
~/.cbuild/cb.sh -r
```

`-g`, `-b`, `-t`, and `-r` require an available `cb.conf` (project root first, then the optional script-directory fallback). If neither exists, they stop with an error instead of guessing a source directory. You can install the template above or write `cb.conf` manually.

## Prerequisites

- python3 (required for `cb.py`)
- CMake + make/Ninja
- MSVC / gcc / clang
- Conan (optional)
- VSCode (optional)
- C/C++ extension (VSCode, optional)
- clangd + CodeLLDB (VSCode, optional)

Environment notes:

- On Windows, it is recommended to run Bash scripts (`install.sh`, `cb.sh`) in Git Bash.
- For the Python workflow, install Python first.
- Conan is recommended to be installed via pip:

```bash
python -m pip install conan
```

## Global Install

The default installation is global: it installs `cb.py` or `cb.sh`, `cb_install.sh`, and, when available, the `cb_uninstall.sh` uninstall wrapper to a shared directory. `-g` and `--global` are also accepted. Global installation does not install `cb.conf`.

### GitHub

```bash
# Install Bash variant (default)
curl -fsSL https://raw.githubusercontent.com/wiseforever/cbuild/master/install.sh | bash

# Install Python variant
curl -fsSL https://raw.githubusercontent.com/wiseforever/cbuild/master/install.sh | bash -s -- --python

# Customize install directory
curl -fsSL https://raw.githubusercontent.com/wiseforever/cbuild/master/install.sh | \
  bash -s -- --prefix ~/.cbuild
```

### Gitee

```bash
# Install Bash variant (default)
curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash -s -- --source gitee

# Install Python variant
curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash -s -- --source gitee --python
```

### Version Selection

All download modes install the tag recorded in the selected source's `master/LATEST` by default. The installer reads it once and downloads every file from that immutable tag. No GitHub API, GitHub Release asset, or extra pointer branch is required. GitHub and Gitee each use their own `master/LATEST`.

```bash
# Pin a specific version (works for --global, --simple, --config, --vscode, and --format)
curl -fsSL https://raw.githubusercontent.com/wiseforever/cbuild/master/install.sh | \
  bash -s -- --release v0.1.0 --python

# Gitee-only path: both LATEST and tag files come from the Gitee mirror
curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | \
  bash -s -- --source gitee

# Install cb.conf or VS Code templates from a pinned version
~/.cbuild/cb_install.sh --config /path/to/project --release v0.1.0
~/.cbuild/cb_install.sh --vscode /path/to/project --release v0.1.0
```

- `--release latest` (default) reads `<source>/master/LATEST`; an explicit tag such as `v0.1.0` skips that lookup.
- `--source github|gitee` selects both the `LATEST` lookup and the tag files. The selected source is authoritative; a missing file is an error and is not fetched from the other source.
- `--base-url` is a custom raw URL template that must contain `{tag}` and requires an explicit `--release`; `latest` is not resolved for custom URLs.
- `cb_install.sh` keeps its own installation directory, variant, and source (unless overridden), but updates to `master/LATEST` unless `--release` is given.
- Query installed versions without loading a project `cb.conf`: `cb.sh --version`, `cb.py --version`, or `cb_uninstall.sh --version`.
- Tags and tag files are immutable. Push the tag before advancing `master/LATEST`; each remote determines `latest` only from its own branch state.
- Release process: [RELEASING.md](RELEASING.md)

After global install, use the full path to run it from any project directory:

```bash
cd my-project
~/.cbuild/cb.sh -g    # CMake generate
~/.cbuild/cb.sh -b    # build
~/.cbuild/cb.sh -r    # run
```

The installer changes your shell rc file only when the install directory is absent from both the current `PATH` and its configured PATH entries. Then add `~/.cbuild` to your `PATH` and run `cb.sh` from any project directory.

The globally installed updater is named `cb_install.sh`; for example, run `~/.cbuild/cb_install.sh --python` to update the global installation and switch to the Python variant.

**Known limitation:** concurrent installations or updates to the same directory are not protected by a lock. In particular, simultaneous Bash/Python installations can remove each other's scripts even when both report success. Wait for each installation to finish before starting another. If this happens, wait for all installers to exit, then reinstall the desired variant into that directory once.

When using the global install, `cb.py` / `cb.sh` looks for `cb.conf` in this order:

1. Current working directory: `./cb.conf`
2. Script installation directory (fallback, only if you manually create `~/.cbuild/cb.conf`)

## Project Bootstrap

Run the install script in your project root. The default is a global Bash installation; use `--simple` to install files into the current project.

### GitHub

```bash
# Install Bash variant into the current project
curl -fsSL https://raw.githubusercontent.com/wiseforever/cbuild/master/install.sh | bash -s -- --simple

# Install Python variant into the current project
curl -fsSL https://raw.githubusercontent.com/wiseforever/cbuild/master/install.sh | bash -s -- --simple --python

# Install only .vscode templates to the current directory
curl -fsSL https://raw.githubusercontent.com/wiseforever/cbuild/master/install.sh | bash -s -- --vscode

# Install only .vscode templates to another project root
curl -fsSL https://raw.githubusercontent.com/wiseforever/cbuild/master/install.sh | bash -s -- --vscode /path/to/project

# Install only cb.conf to the current directory (or append a project path)
curl -fsSL https://raw.githubusercontent.com/wiseforever/cbuild/master/install.sh | bash -s -- --config

# Only pull .clang-format
curl -fsSL https://raw.githubusercontent.com/wiseforever/cbuild/master/install.sh | bash -s format
```

### Gitee

```bash
# Install Bash variant into the current project
curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash -s -- --source gitee --simple

# Install Python variant into the current project
curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash -s -- --source gitee --simple --python

# Install only .vscode templates to the current directory
curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash -s -- --source gitee --vscode

# Install only cb.conf to the current directory (or append a project path)
curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash -s -- --source gitee --config

# Only pull .clang-format
curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash -s -- --source gitee format
```

Notes:

- A simple install moves existing `.vscode`, `cb.py`, `cb.sh`, `cb.conf`, and `cmake/ez_custom_func.cmake` to `cbuild_bak/` before installing replacements.
- `--vscode [directory]` installs only the four VS Code templates. When `.vscode` already exists, it is moved to `<directory>/cbuild_bak/` first.
- `--config [directory]` installs only `cb.conf`. An existing configuration is moved to `<directory>/cbuild_bak/` first.
- If you do not use VSCode, only `cb.py` or `cb.sh` plus `cb.conf` is required.
- `install.sh` does not generate or overwrite `.vscode/tasks.json`. The repository keeps the task files for users who still want to use VS Code's built-in Tasks manually.

## Uninstall

### Uninstall Global Installation
Uninstall is implemented by `install.sh` / `cb_install.sh`; `cb_uninstall.sh` is an optional uninstall wrapper. If the wrapper was not installed, use the updater or a downloaded installer instead.

```bash
# Installed wrapper (removes its own directory):
~/.cbuild/cb_uninstall.sh --yes

# Globally installed updater:
~/.cbuild/cb_install.sh --uninstall

# Re-download the installer (use --yes because stdin is not interactive):
curl -fsSL https://raw.githubusercontent.com/wiseforever/cbuild/master/install.sh | \
  bash -s -- --uninstall --yes

# Uninstall a custom installation directory via the default updater:
~/.cbuild/cb_install.sh --uninstall --prefix /path/to/cbuild
```

Uninstall is local-only and does not query GitHub. It refuses `/`, your home directory, and directories that do not look like a cbuild installation. `--yes` is required when stdin is not a terminal.

### Uninstall Project-local Installation

For a project-local (simple) install, simply delete the installed files from your project directory:

```bash
rm cb.py cb.sh cb.conf
rm -rf .vscode/ cmake/cbuild_bak/
```

## cb.py / cb.sh Usage

Both scripts need `cb.conf` for build operations, with this lookup order (`-h/--help`, `--version`, and no-argument runs do not require it):

1. current working directory: `./cb.conf`
2. script directory fallback: `cb.conf`

### Regarding `CMAKE_C_COMPILER` / `CMAKE_CXX_COMPILER`

`cb.py` and `cb.sh` behave as follows:

- If `[compiler] compiler` is **empty or unset**: no `-DCMAKE_C_COMPILER` / `-DCMAKE_CXX_COMPILER` is injected; CMake uses the normal environment.
- If `compiler` is **configured**: one GCC or Clang driver selects the C/C++ pair, and both CMake compiler arguments are injected automatically.
  - `gcc` → `gcc/g++`; `gcc-9` → `gcc-9/g++-9`.
  - `clang` → `clang/clang++`; `clang-14` → `clang-14/clang++-14`. Clang is never paired with G++.
  - Cross prefixes, `.exe` suffixes and paths are supported; the corresponding C++ driver can also be the entry point. Companion drivers are located in the same directory first, then by matching name on PATH.
  - Compiler directories are temporarily prepended to subprocess PATH, without changing persistent environment settings.
- In `MSVC` mode (`[msvc] enable=1` with valid `msvc_env_script`), the CMake build environment is initialized via `vcvarsall.bat`.

Note: this temporary `PATH` change is process-local and does not modify user/system persistent environment variables.

### cb.conf Parameters

All the parameters in `cb.conf` can be modified according to your needs.

> **Global install path note:**
> `cb.py` / `cb.sh` looks for `cb.conf` in the following order:
> 1. **Current working directory** `./cb.conf` (project-local config)
> 2. **Script directory** (fallback, i.e. `~/.cbuild/cb.conf`)
>
> When changing the build type (`-t` / `--type`), the script always writes to whichever file was actually loaded — project-local first, global fallback otherwise. They do not interfere with each other.
>
> Relative `source_dir` is resolved from the directory of the active `cb.conf`; a relative `output_dir` is resolved from `source_dir`.

```ini
[build]
build_type = Debug      # The compilation type is Debug. Currently, [Debug, Release]
source_dir = .          # The source code directory, "."indicates the current directory
output_dir = output     # Base output directory; defaults to "build"
# output_dir_use_subdir = true # Default true: append the build type, e.g. output/Debug
# subdir_use_compiler = false # Default false: include the compiler only when enabled; requires output_dir_use_subdir = true
generator = Ninja       # Build tools available: [Ninja, Unix Makefiles, ...]
parallel_jobs = auto    # The number of threads for parallel compilation, where auto means the number of cpu cores is automatically selected

[compiler]              # Compact-related configuration (excluding MSVC), is invalid if the enable of msvc takes effect (the msvc item is invalid under linux).
compiler = gcc         # Pairs gcc/g++; also accepts gcc-9, clang, clang-14, cross prefixes and driver paths

[conan]                 # Conan package manager settings
enable = 1              # Whether to use Conan
# build = gcc           # Explicit build profile; otherwise match a gcc* profile to the configured compiler
# host = gcc            # Explicit host profile; otherwise match a gcc* profile to the configured compiler

[vcpkg]                 # vcpkg package manager settings
enable = 1              # Enable the vcpkg toolchain
root = /path/to/vcpkg   # Optional; falls back to the VCPKG_ROOT environment variable
toolchain_file =        # Direct vcpkg.cmake path; takes precedence over root
triplet =               # Empty lets vcpkg infer it from the active compiler

[toolchain]
custom_file = cbuild_custom.cmake  # User-maintained CMake toolchain extension

[msvc]                  # The msvc compiler is rather special and requires specifying the path of the environment variable script vcvarsall.bat
enable = 1              # Whether to use the MSVC compiler or not, 1, True, true indicates usage, and 0, False, false indicates non-usage
msvc_env_script = D:/Develop/Visual Studio/2019/BuildTools/VC/Auxiliary/Build/vcvarsall.bat # MSVC environment variable script path
host_arch = x64         # The number of bits for compiling the executable program can be selected as [x86, x64]
```

`output_dir_use_subdir` defaults to `true`, creating a build-type subdirectory. When set to `false`, the build directory is exactly `output_dir`, regardless of `subdir_use_compiler`. `subdir_use_compiler` defaults to `false`; enabling it includes the compiler name and version in the subdirectory. When switching compilers without isolated directories, clear the CMake cache first or use a separate `output_dir`.

### Conan GCC profiles

Set `[compiler] compiler` to the toolchain driver, e.g. `gcc-9`. Conan profiles and CMake share the GCC/G++ pair located in the same directory or on PATH. GCC profile generation checks both drivers' major versions.

```bash
bash cb.sh --conan-profile       # Prefer conan.host as the name; otherwise apply the fallback rules
python3 cb.py --conan-profile    # Same behavior; --conan-profle is also accepted
bash cb.sh --conan
bash cb.sh -g
```

- Generation uses `conan.host` as the name first, then `conan.build` if host is unset, then `gcc-<major>` if both are unset. With both build and host set to `gcc`, the generated/overwritten profile is `gcc`. Generated names must start with `gcc` and contain only letters, digits or `._+-`. The name is only a label: `compiler.version` still comes from the actual `[compiler]` toolchain, not from parsing the profile name.
- Generation handles one profile for the configured toolchain and overwrites it without a backup, even if Conan is disabled; it does not install dependencies or run CMake. When both build and host are configured with different names, only the host profile is generated; build is left untouched.
- `[buildenv]` explicitly records `CC` and `CXX`. GCC tool queries, matching prefixes and the toolchain directory locate `AR`, `AS`, `LD`, `NM`, `RANLIB`, `STRIP`, `OBJCOPY` and `OBJDUMP`; compiler directories are prepended to `PATH`. Missing tools produce a warning and are omitted; prefixed driver names do not fall back to unprefixed binutils when companion tools are missing.
- Compiler paths are supplied by `[buildenv]`. A valid GCC-reported sysroot is recorded as `[buildenv] SYSROOT` and `[conf] tools.build:sysroot`.
- With Conan enabled and a dependency manifest present, `--conan` and `-g` use the same selection policy. Each explicit build/host profile wins; unset entries match existing names beginning with `gcc`, with `compiler=gcc` and the selected major version. `gcc-<major>` is preferred; cb does not infer or filter target architectures. Without a match, run `--conan-profile` first; neither action silently generates one.
- If an explicit profile is missing or cannot be loaded, both `--conan` and `-g` fail instead of falling back to automatic matching. Logs identify the active config file, script path and each profile's source (configured / auto / default).
- Existing matched profiles are not modified during selection. Conan dependency builds rely on the selected profile's `[buildenv]`, so existing profiles must specify the intended toolchain there. The project's CMake configure still receives explicit compiler arguments from cbuild.
- `-g` configures the project only. After editing a profile, run `--conan` to install dependencies before `-g`. A missing dependency-installation record or a different profile selection prompts the user to run `--conan`.
- Conan detects `os`, `arch` and `compiler.cppstd`; profiles define the required target-platform settings.
- For cross compilation, explicitly maintain native build and target host profiles, and correct target OS/architecture, ABI, SDK, triplets and extra flags after generation. `conan profile detect` primarily detects the running machine; its default settings are not target-platform settings. Do not rely on GCC-major-only matching to distinguish targets.
- With `compiler` empty or unset, Conan's default profile behavior is preserved. Automatic selection/generation supports GCC only; for Clang or MSVC, explicitly maintain and select suitable build/host profiles.

### Command Reference

Python examples:

```bash
# -t|--type     Toggle or set build type
python cb.py -t
python cb.py -t Debug
python cb.py -t Release

# --conan       Build Conan dependencies
python cb.py --conan
python cb.py --conan Debug

# -g|--generate [Debug|Release] CMake generate; build type is case-insensitive
python cb.py -g
python cb.py -g Debug
python cb.py -g release

# Pass custom definitions to CMake during generate
python cb.py -g -DMY_OPTION=ON -DMY_VALUE=example
python cb.py -g -D MY_OPTION=ON

# -b|--build    Compile
python cb.py -b
python cb.py -b --target all
python cb.py -b Debug --target all

# -r|--run      Run the built executable
python cb.py -r
python cb.py -r Debug

# -c|--clean    Clean build directory
python cb.py -c

# -h|--help     Show help
python cb.py -h

# -V|--version  Show version without reading a project cb.conf
python cb.py --version

# --list-execs  List executables in the configured build directory (requires cb.conf)
python cb.py --list-execs
```

Bash examples:

```bash
# -t|--type     Toggle or set build type
bash cb.sh -t
bash cb.sh -t Debug

# --conan       Build Conan dependencies
bash cb.sh --conan

# -g|--generate CMake generate
bash cb.sh -g
bash cb.sh -g Debug
bash cb.sh -g release
bash cb.sh -g -DMY_OPTION=ON -DMY_VALUE=example

# -b|--build    Compile
bash cb.sh -b --target all

# -r|--run      Run the built executable
bash cb.sh -r

# -c|--clean    Clean build directory
bash cb.sh -c

# -h|--help     Show help
bash cb.sh -h
bash cb.sh --version

# --list-execs  List executables in the configured build directory (requires cb.conf)
bash cb.sh --list-execs
```

`-D` definitions are configuration-time options. They must be used with `-g` / `--generate`; cbuild does not silently reconfigure when building or running.

## VSCode Configuration

The `.vscode` directory contains debug launch configurations, C/C++ and clangd settings, and snippets. Adjust them as needed.

You can run the commands listed in [Command Reference](#command-reference) in a terminal.

## Conan Usage

- Create `conanfile.py` or `conanfile.txt` in the project root.
- Enable Conan in the `[conan]` section of `cb.conf` (`enable = 1`).
- Set `[conan] build` / `host` profiles in `cb.conf`.
- Use `find_package()` and `target_link_libraries()` in `CMakeLists.txt`.
- Do not override `CMAKE_TOOLCHAIN_FILE` manually when using this workflow.

### conanfile.py example

```python
from conan import ConanFile
from conan.tools.files import copy
import os

class MyProjectConan(ConanFile):
    settings = "os", "compiler", "build_type", "arch"
    generators = "CMakeToolchain", "CMakeDeps"

    def requirements(self):
        self.requires("boost/1.84.0", options={"header_only": True})

    def layout(self):
        self.folders.build = ""
        self.folders.generators = os.path.join(self.folders.build, "generators")
        self.cpp.build.bindirs = ["bin"]
        self.cpp.build.libdirs = ["lib"]

    def generate(self):
        build_bin = os.path.join(self.build_folder, "bin")
        os.makedirs(build_bin, exist_ok=True)
        for dep in self.dependencies.values():
            for shared_lib in dep.cpp_info.bindirs:
                copy(self, "*.dll", shared_lib, build_bin)
                copy(self, "*.so", shared_lib, build_bin)
                copy(self, "*.dylib", shared_lib, build_bin)
```

## Combined Conan and vcpkg Usage

`CMAKE_TOOLCHAIN_FILE` accepts only one file. When `[vcpkg]` is enabled, cbuild generates `cbuild_toolchain.cmake` in the current build directory and passes it as the single entry point. The wrapper loads `[toolchain] custom_file` first, then vcpkg chainloads Conan's generated `conan_toolchain.cmake`.

Use a project-root `vcpkg.json` to declare manifest dependencies. This repository's demo keeps Boost in `conanfile.py` and declares JsonCpp in `vcpkg.json`. For a first build, run:

```bash
python cb.py --conan
python cb.py -g
python cb.py -b
```

The vcpkg path resolution order is `toolchain_file` > `root` > `VCPKG_ROOT`. If `triplet` is empty, vcpkg infers it from the active compiler. Set it explicitly for cross builds, static linkage, or custom runtimes.

When first enabling, disabling, or changing a toolchain for an existing build directory, run `cb.py -c` (or `cb.sh -c`) first to clear its CMake cache.

Do not edit the generated `cbuild_toolchain.cmake`. Put project-specific additions in `cbuild_custom.cmake`, for example:

```cmake
set(VCPKG_OVERLAY_TRIPLETS "${CMAKE_CURRENT_LIST_DIR}/triplets")
```
