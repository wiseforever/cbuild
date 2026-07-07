# cbuild

[English Documentation](README.md)

一个轻量级的 C/C++ 项目构建工作流工具，提供 Python 和 Bash 两种脚本实现，可选 VSCode 集成与 Conan 包管理支持。

## 目录

- [快速开始](#快速开始)
- [安装依赖](#1-安装依赖)
- [搭建项目](#2-搭建项目)
- [全局安装](#全局安装)
- [卸载](#卸载)
- [cb.py / cb.sh 使用说明](#cbpy--cbsh-的使用)
  - [参数说明](#cb_confini-参数说明)
  - [命令参考](#cbpy--cbsh-使用命令说明)
- [VSCode 配置](#vscode-配置)
- [Conan 使用](#若使用-conan)

## 快速开始

```bash
# Python 版本 — 安装到你的项目
curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash

# 然后配置、编译并运行：
python cb.py -g    # CMake 生成
python cb.py -b    # 编译
python cb.py -r    # 运行
```

## 1. 安装依赖

- python3 (required for `cb.py`)
- CMake + make / Ninja
- MSVC / gcc / clang
- conan (可选)
- VSCode (可选)
- C/C++ (VSCode插件、可选)
- clangd + CodeLLDB (VSCode插件、可选)
- Task Buttons (VSCode插件、可选)

环境建议：

- Windows 下使用 Bash 版本（`install.sh` / `cb.sh`）时，建议在 Git Bash 终端执行。
- 使用 Python 版本（`cb.py`）前，请先安装 Python（建议 Python 3.8+）。
- Conan 建议通过 `pip` 安装：

```bash
python -m pip install conan
```

## 2. 搭建项目

首先进入自己项目的根目录，运行此仓库的 `install.sh` 脚本，脚本会自动搭建好。

默认安装 Python 版本（会覆盖 `.vscode/tasks.json` 为 Python 任务）：

```bash
# github
curl -fsSL https://github.com/wiseforever/cbuild/raw/master/install.sh | bash

# gitee
curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash
```

安装 Bash 版本（会覆盖 `.vscode/tasks.json` 为 Bash 任务）：

```bash
# github
curl -fsSL https://github.com/wiseforever/cbuild/raw/master/install.sh | bash -s sh

# gitee
curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash -s sh
```

仅拉取 `.clang-format`：

```bash
# github
curl -fsSL https://github.com/wiseforever/cbuild/raw/master/install.sh | bash -s format

# gitee
curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash -s format
```

前提：

- 项目根目录下应该不要存在 `.vscode` 目录，因为脚本会检查、备份以及看情况创建这个目录，为避免冲突请在运行 `install.sh` 脚本的时候，请先清理好项目目录。
- 若不需要使用 VSCode 可以不依赖 `.vscode` 目录，仅仅需要 `cb.py` 或 `cb.sh` 与 `cb_conf.ini` 文件即可。
- `.vscode/tasks.json` 已按模板拆分为 `.vscode/tasks_python.json` 与 `.vscode/tasks_bash.json`，安装时会按版本自动覆盖为对应的 `tasks.json`。

## 全局安装

安装到共享目录，可在任意项目目录下使用。`-g` 与 `--global` 均可。

```bash
# 默认安装 Python 版本
curl -fsSL https://github.com/wiseforever/cbuild/raw/master/install.sh | bash -s -- -g

# 安装 Bash 版本
curl -fsSL https://github.com/wiseforever/cbuild/raw/master/install.sh | bash -s -- -g --bash

# 自定义安装目录
curl -fsSL https://github.com/wiseforever/cbuild/raw/master/install.sh | \
  bash -s -- -g --prefix ~/.cbuild
```

全局安装后，在项目目录中通过完整路径使用：

```bash
cd my-project
python3 ~/.cbuild/cb.py -g    # CMake 生成
python3 ~/.cbuild/cb.py -b    # 编译
python3 ~/.cbuild/cb.py -r    # 运行
```

也可将 `~/.cbuild` 加入 `PATH` 后直接用 `python3 cb.py` 执行。

全局安装时，`cb.py` / `cb.sh` 查找 `cb_conf.ini` 的顺序：

1. 当前工作目录 `./cb_conf.ini`
2. 脚本安装目录（作为回退）

## 卸载

### 卸载全局安装

全局安装附带了卸载脚本，运行以下任一方式即可：

```bash
# 方式一：直接运行卸载脚本（在安装目录中）
~/.cbuild/uninstall.sh

# 方式二：使用 install.sh --uninstall
curl -fsSL https://github.com/wiseforever/cbuild/raw/master/install.sh | bash -s -- --uninstall
```

卸载脚本会移除以下内容：

- 全局安装目录（`~/.cbuild/`）
- 所有已安装的脚本和配置文件

### 卸载项目级安装

对于通过普通（simple）模式安装到项目的文件，直接删除即可：

```bash
rm cb.py cb.sh cb_conf.ini
rm -rf .vscode/ cmake/cbuild_bak/
```

## cb.py / cb.sh 的使用

`cb.py` 与 `cb.sh` 都依赖 `cb_conf.ini`，查找顺序如下：

1. 当前工作目录 `./cb_conf.ini`
2. 脚本同级目录 `cb_conf.ini`（回退）

### 关于 `CMAKE_C_COMPILER` / `CMAKE_CXX_COMPILER`

`cb.py` 与 `cb.sh` 的行为如下：

- `cb_conf.ini` 中 `c_compiler` / `cpp_compiler` **留空**：不注入 `-DCMAKE_C_COMPILER` / `-DCMAKE_CXX_COMPILER`，按系统环境正常调用 CMake。
- `c_compiler` / `cpp_compiler` **已配置**：
  - 自动注入 `-DCMAKE_C_COMPILER=...` / `-DCMAKE_CXX_COMPILER=...`。
  - 若写的是绝对路径（或带目录的路径），会把其目录仅在本次 `cmake` 子进程临时补到 `PATH`。
  - 若写的是 `gcc`/`g++`/`clang`/`clang++` 这类命令名，会先解析其实际路径，再把对应目录临时补到 `PATH`。
- `MSVC` 模式（`[msvc] enable=1` 且 `msvc_env_script` 有效）保持原行为：通过 `vcvarsall.bat` 建环境，不走上述注入流程。

说明：这里的 `PATH` 处理仅对当前 `cb.py`/`cb.sh` 启动的子进程生效，不会修改系统级或用户级环境变量。

### cb_conf.ini 参数说明

`cb_conf.ini` 中的参数都可以自行进行合理的修改，以下是参数的说明：

> **全局安装路径说明：**
> `cb.py` / `cb.sh` 按以下顺序查找 `cb_conf.ini`：
> 1. **当前工作目录** `./cb_conf.ini`（项目级配置）
> 2. **脚本所在目录**（回退，即 `~/.cbuild/cb_conf.ini`）
>
> 修改配置时（`-t` / `--config`），始终修改**实际加载的那个文件**——
> 项目目录有就改项目目录的，没有则改全局的，互不干扰。
>

```ini
[build]
build_type = Debug      # 编译类型为 Debug。目前可选 [Debug、Release]
source_dir = .          # 源码目录，.表示当前目录
output_dir = output     # 输出目录，不写则默认为 build；会追加编译器后缀如 output/GCC-11.4.0-Release
generator = Ninja       # 构建工具，可选 [Ninja、Unix Makefiles, ...]
parallel_jobs = auto    # 并行编译的线程数，auto为自动选择cpu核心数

[compiler]              # 编译器相关配置（不含MSVC），若msvc的enable生效则此项无效（linux下msvc项无效）
c_compiler = gcc        # C 编译器（可写命令名或路径）；非空时会注入 CMAKE_C_COMPILER
cpp_compiler = g++      # C++ 编译器（可写命令名或路径）；非空时会注入 CMAKE_CXX_COMPILER

[conan]                 # Conan 包管理器配置
conan_enable = 1        # 是否使用conan，1、True、true表示使用，0、False、false表示不使用
conan_build = gcc       # 对应 conan 的 profile build
conan_host = gcc        # 对应 conan 的 profile host

[msvc]                  # msvc 编译器比较特殊，需要指定环境变量脚本vcvarsall.bat的路径
enable = 1              # 是否使用MSVC编译器，1、True、true表示使用，0、False、false表示不使用
msvc_env_script = D:/Develop/Visual Studio/2019/BuildTools/VC/Auxiliary/Build/vcvarsall.bat # MSVC环境变量脚本路径
host_arch = x64         # 编译可执行程序的位数，可选 [x86、x64]
```

### cb.py / cb.sh 使用命令说明

`cb.py` 脚本依赖 `cb_conf.ini` 文件中的参数具有一些记忆功能，但也可以通过命令行让其不过分依赖。

Python 版本命令参考：

```bash
# -t|--type 切换默认的编译类型
python cb.py -t
python cb.py -t Debug
python cb.py -t Release
python cb.py --type

# --conan 使用 conan 构建依赖库
python cb.py --conan
python cb.py --conan Debug
python cb.py --conan Release

# -g|--generate 生成CMake缓存
python cb.py -g
python cb.py -g Debug
python cb.py -g Release
python cb.py --generate

# -b|--build 编译
python cb.py -b
python cb.py -b Debug
python cb.py -b Release
python cb.py -b --target all
python cb.py -b Debug --target all
python cb.py -b Release --target all
python cb.py --build

# -c|--clean 清理
python cb.py -c
python cb.py --clean

# -r|--run 运行
python cb.py -r
python cb.py -r Debug
python cb.py -r Release
python cb.py --run

# -h|--help 帮助
python cb.py -h
python cb.py --help
```

Bash 版本参数与 Python 版本保持一致：

```bash
bash cb.sh -t
bash cb.sh --conan
bash cb.sh -g
bash cb.sh -b --target all
bash cb.sh -c
bash cb.sh -r
bash cb.sh -h
```

## VSCode 配置

`.vscode` 目录按照作者的习惯，做了一些配置，可以自行修改。

![alt text](image.png)

如上图的 1-6 按钮，分别对应了：

1. CMake generate；
2. 编译；
3. 运行；
4. Deploy（需要在 `CMakeLists.txt` 中自己定义一个 `deploy` 的 target，若不需要请忽略）；
5. 切换 Debug/Release 编译类型；
6. 清理。

也可以在终端中使用 [cb.py/cb.sh 命令](#cbpy--cbsh-使用命令说明)，或者在 VSCode 中使用 Task Buttons 插件，配置好快捷键，即可快速编译运行。

## 若使用 Conan

- 首先安装 conan
- 然后在项目根目录下创建 `conanfile.py` 文件，并在其中定义依赖库
- 在 `conanfile.py` 中，指定依赖库的名称、版本、路径等信息
- 在 `cb_conf.ini` 中，将 `conan_enable` 设置为 1
- 在 `cb_conf.ini` 中，指定 `conan_build` 和 `conan_host` 对应的 profile
- Conan 的 profile 可以根据自己项目的需求进行修改，但需要注意，profile 的名称必须与 `cb_conf.ini` 中定义的名称一致（需要开发者自行了解相关知识）
- 在 `CMakeLists.txt` 中，使用 `find_package()` 函数查找依赖库，并使用 `target_link_libraries()` 函数链接依赖库
- `cb.py` 脚本会自动设置 `CMAKE_TOOLCHAIN_FILE` 变量，并使用 conan 的 profile 编译依赖库，请不要在 `CMakeLists.txt` 中覆盖 `CMAKE_TOOLCHAIN_FILE` 变量
- 运行 `cb.py` 脚本，会自动使用 conan 编译依赖库

### conanfile.py 示例

```python
from conan import ConanFile
from conan.tools.files import copy
import os

class MyProjectConan(ConanFile):
    settings = "os", "compiler", "build_type", "arch"

    # 生成器
    generators = "CMakeToolchain", "CMakeDeps"

    def requirements(self):
        self.requires("boost/1.84.0", options={"header_only": True})  # 仅头文件库
        self.requires("jsoncpp/1.9.5", options={"shared": False})     # 静态库

    def layout(self):
        self.folders.build = ""
        self.folders.generators = os.path.join(self.folders.build, "generators")
        self.cpp.build.bindirs = ["bin"]
        self.cpp.build.libdirs = ["lib"]

    def generate(self):
        # 将动态库拷贝到 bin 目录，便于运行时直接加载
        build_bin = os.path.join(self.build_folder, "bin")
        os.makedirs(build_bin, exist_ok=True)
        for dep in self.dependencies.values():
            for shared_lib in dep.cpp_info.bindirs:
                copy(self, "*.dll", shared_lib, build_bin)
                copy(self, "*.so", shared_lib, build_bin)
                copy(self, "*.dylib", shared_lib, build_bin)
```
