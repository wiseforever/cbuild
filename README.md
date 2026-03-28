# cbuild-py

English documentation: [README_EN.md](README_EN.md)

```
    该仓库用于更方便的编译c、c++程序。

    对vscode做了适配，依赖 VSCode 的 .vscode 目录下的 tasks.json、settings.json、c_cpp_properties.json + C/C++ 插件 + Task Buttons 插件；实现 在 VSCode 的左下角快速编译运行程序，以及代码的语法高亮与跳转。

    camke目录下提供了一些简易的cmake函数。

    支持conan，但需要根据此脚本的说明使用 conanfile.py(推荐) 或者 conanfile.txt。

    conan的知识需要自己学习，这里不做过多介绍。
```

## 如何使用

### 1. 安装依赖

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

### 2. 搭建项目

首先进入自己项目的根目录，运行此仓库的install.sh脚本，脚本会自动搭建好。

默认安装 Bash 版本（会覆盖 `.vscode/tasks.json` 为 Bash 任务）：

```bash
curl -fsSL https://gitee.com/wiseforever/cbuild-py/raw/master/install.sh | bash
```

安装 Python 版本（会覆盖 `.vscode/tasks.json` 为 Python 任务）：

```bash
curl -fsSL https://gitee.com/wiseforever/cbuild-py/raw/master/install.sh | bash -s py
```

仅拉取 `.clang-format`：

```bash
curl -fsSL https://gitee.com/wiseforever/cbuild-py/raw/master/install.sh | bash -s format
```

前提：

- 项目根目录下应该不要存在.vscode目录，因为脚本会检查、备份以及看情况创建这个目录，为了避免冲突请在运行 install.sh 脚本的时候，请先清理好项目目录。

- 若不需要使用 vscode 可以不依赖 .vscode 目录，仅仅需要 cb.py 或 cb.sh 与 cb_conf.ini 文件即可。

- `.vscode/tasks.json` 已按模板拆分为 `.vscode/tasks_python.json` 与 `.vscode/tasks_bash.json`，安装时会按版本自动覆盖为对应的 `tasks.json`。


### cb.py / cb.sh 的使用
cb.py 与 cb.sh 都依赖 cb_conf.ini 文件，在使用前请将 cb_conf.ini 放在其同级目录下。

### 关于 `CMAKE_C_COMPILER` / `CMAKE_CXX_COMPILER`

`cb.py` 与 `cb.sh` 默认不传入 `-DCMAKE_C_COMPILER` 和 `-DCMAKE_CXX_COMPILER`。  
如果你需要固定编译器，请自行在 `CMakeLists.txt` 中添加（建议放在第一次 `project()` 之前）：

```CMakeLists.txt
cmake_minimum_required(VERSION 3.20)

# 按需固定编译器（示例）
set(CMAKE_C_COMPILER "gcc" CACHE STRING "" FORCE)
set(CMAKE_CXX_COMPILER "g++" CACHE STRING "" FORCE)

project(my_project LANGUAGES C CXX)
```

MSVC 不需要指定该参数

#### cb_conf.ini 参数说明

cb_conf.ini 中的参数都可以自行进行合理的修改 ，以下是参数的说明：

```ini
[build]
build_type = Debug      # 编译类型为 Debug。目前可选 [Debug、Release]
source_dir = .          # 源码目录，.表示当前目录
generator = Ninja       # 构建工具，可选 [Ninja、Unix Makefiles ...]
parallel_jobs = auto    # 并行编译的线程数，auto为自动选择cpu核心数

[compiler]              # 编译器相关配置（不含MSVC），若msvc的enable生效则此项无效（linux下msvc项无效）
c_compiler = gcc        # c语言编译器
cpp_compiler = g++      # c++语言编译器
conan_enable = 1        # 是否使用conan，1、True、true表示使用，0、False、false表示不使用
conan_build = gcc       # conan 的 profile build 对应的 profile
conan_host = gcc        # conan 的 profile host 对应的 profile

[msvc]                  # msvc 编译器比较特殊，需要指定环境变量脚本vcvarsall.bat的路径
enable = 1              # 是否使用MSVC编译器，1、True、true表示使用，0、False、false表示不使用
msvc_env_script = D:/Develop/Visual Studio/2019/BuildTools/VC/Auxiliary/Build/vcvarsall.bat # MSVC环境变量脚本路径
host_arch = x64         # 编译可执行程序的位数，可选 [x86、x64]
conan_enable = 1        # 是否使用conan，1、True、true表示使用，0、False、false表示不使用
conan_build = default   # conan 的 profile build 对应的 profile ，没有 conanfile.txt 或 conanfile.py 时，不生效
conan_host = default    # conan 的 profile host 对应的 profile ，没有 conanfile.txt 或 conanfile.py 时，不生效

```

#### cb.py / cb.sh 使用命令说明

cb.py  脚本依赖 cb_conf.ini 文件中的参数具有一些记忆功能，但也可以通过命令行让其不过分依赖。

cb 脚本的使用方法如下：

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
python cb.py -b --target all # 指定编译目标 all
python cb.py -b Debug --target all # 指定编译Debug编译类型，编译目标 all
python cb.py -b Release --target all # 指定编译Release编译类型，编译目标 all
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

`cb.sh` 参数与 `cb.py` 保持一致，用法示例：

```bash
bash cb.sh -t
bash cb.sh --conan
bash cb.sh -g
bash cb.sh -b --target all
bash cb.sh -c
bash cb.sh -r
bash cb.sh -h
```

### vscode 配置
.vscode 目录按照作者的习惯，做了一些配置，可以自行修改。

![alt text](image.png)

如上图的1-5按钮，分别对应了生成

- 1.CMake缓存；
- 2.编译；
- 3.运行；
- 4.deploy部署（此处需要自己在CMakeLists.txt中根据自己项目定义一个deploy的target。若不需要请忽略）
- 5.切换Debug/Release编译类型；
- 6.清理。

也可以在终端中使用 cb.py/cb.sh 使用命令说明中的命令，也可以在 vscode 中使用 Task Buttons 插件，配置好快捷键，即可快速编译运行。



### 若使用 conan

- 首先安装 conan
- 然后在项目根目录下创建 conanfile.py 文件，并在其中定义依赖库
- 在 conanfile.py 中，指定依赖库的名称、版本、路径等信息
- 在 cb_conf.ini 中，将 conan_enable 设置为 1
- 在 cb_conf.ini 中，指定 conan_build 和 conan_host 对应的 profile
- conan的profile可以根据自己项目的需求进行修改，但需要注意，profile的名称必须与 cb_conf.ini中定义的名称一致（需要开发者自行了解相关知识）
- 在CMakeLists.txt中，使用find_package()函数查找依赖库，并使用target_link_libraries()函数链接依赖库
- cb.py 脚本会自动设置CMAKE_TOOLCHAIN_FILE变量，并使用conan的profile编译依赖库，请不要在CMakeLists.txt中覆盖CMAKE_TOOLCHAIN_FILE变量
- 运行 cb.py 脚本，会自动使用 conan 编译依赖库

#### conanfile.py 示例

```python
from conan import ConanFile
# from conan.tools.cmake import cmake_layout
from conan.tools.files import copy
import os

class MyProjectConan(ConanFile):
    settings = "os", "compiler", "build_type", "arch"

    # 生成器
    generators = "CMakeToolchain", "CMakeDeps"

    def requirements(self):
        self.requires("boost/1.84.0", options={"header_only": True}) # 仅头文件库
        self.requires("jsoncpp/1.9.5", options={"shared": False}) # 静态库

    def layout(self):
        # cmake_layout(self)
        # self.folders.build = os.path.join("build", str(self.settings.build_type))
        self.folders.build = ""
        self.folders.generators = os.path.join(self.folders.build, "generators")
        self.cpp.build.bindirs = ["bin"]
        self.cpp.build.libdirs = ["lib"]

    def generate(self):
        # 这个位置可以自定义，self.build_folder是 构建目录，表示在构建目录下的bin目录
        # 目的是将动态库直接拷贝到bin目录下，便于运行时直接加载
        build_bin = os.path.join(self.build_folder, "bin")
        os.makedirs(build_bin, exist_ok=True)
        for dep in self.dependencies.values():
            for shared_lib in dep.cpp_info.bindirs:
                print(">>>")
                print(">>>", shared_lib)
                print(">>>")
                copy(self, "*.dll", shared_lib, build_bin)
                copy(self, "*.so", shared_lib, build_bin)
                copy(self, "*.dylib", shared_lib, build_bin)

```
