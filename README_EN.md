# cbuild

中文文档: [README.md](README.md)

This repository provides a lightweight build workflow for C/C++ projects, with optional VSCode integration and Conan support.

## How To Use

### 1. Prerequisites

- python3 (required for `cb.py`)
- CMake + make/Ninja
- MSVC / gcc / clang
- Conan (optional)
- VSCode (optional)
- C/C++ extension (VSCode, optional)
- clangd + CodeLLDB (VSCode, optional)
- Task Buttons (VSCode, optional)

Environment notes:

- On Windows, it is recommended to run Bash scripts (`install.sh`, `cb.sh`) in Git Bash.
- For the Python workflow, install Python first.
- Conan is recommended to be installed via pip:

```bash
python -m pip install conan
```

### 2. Project Bootstrap

Run the install script in your project root.

Default install (Bash version, replaces `.vscode/tasks.json` with Bash tasks):

```bash
curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash
```

Install Python version (replaces `.vscode/tasks.json` with Python tasks):

```bash
curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash -s py
```

Only pull `.clang-format`:

```bash
curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash -s format
```

Notes:

- It is recommended to clean existing `.vscode` content before running `install.sh`.
- If you do not use VSCode, only `cb.py` or `cb.sh` plus `cb_conf.ini` is required.
- Task templates are split into `.vscode/tasks_python.json` and `.vscode/tasks_bash.json`; install will copy one of them to `tasks.json`.

### 3. `cb.py` / `cb.sh`

Both scripts depend on `cb_conf.ini` in the same directory.

Python examples:

```bash
python cb.py -t
python cb.py --conan
python cb.py -g
python cb.py -b --target all
python cb.py -c
python cb.py -r
python cb.py -h
```

Bash examples:

```bash
bash cb.sh -t
bash cb.sh --conan
bash cb.sh -g
bash cb.sh -b --target all
bash cb.sh -c
bash cb.sh -r
bash cb.sh -h
```

### 4. About `CMAKE_C_COMPILER` / `CMAKE_CXX_COMPILER`

`cb.py` and `cb.sh` do not pass `-DCMAKE_C_COMPILER` or `-DCMAKE_CXX_COMPILER` by default.

If you need fixed compilers, configure them in `CMakeLists.txt` (before the first `project()`), for example:

```cmake
cmake_minimum_required(VERSION 3.20)
set(CMAKE_C_COMPILER "gcc" CACHE STRING "" FORCE)
set(CMAKE_CXX_COMPILER "g++" CACHE STRING "" FORCE)
project(my_project LANGUAGES C CXX)
```

MSVC does not need to specify this parameter.

### 5. Conan Usage

- Create `conanfile.py` or `conanfile.txt` in the project root.
- Enable Conan in `cb_conf.ini` (`conan_enable = 1`).
- Set `conan_build` / `conan_host` profiles in `cb_conf.ini`.
- Use `find_package()` and `target_link_libraries()` in `CMakeLists.txt`.
- Do not override `CMAKE_TOOLCHAIN_FILE` manually when using this workflow.

#### `conanfile.py` example

```python
from conan import ConanFile
from conan.tools.files import copy
import os

class MyProjectConan(ConanFile):
    settings = "os", "compiler", "build_type", "arch"
    generators = "CMakeToolchain", "CMakeDeps"

    def requirements(self):
        self.requires("boost/1.84.0", options={"header_only": True})
        self.requires("jsoncpp/1.9.5", options={"shared": False})

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
