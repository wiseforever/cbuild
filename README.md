# cbuild-py

```
    该仓库用于更方便的编译c、c++程序，python + CMake + make / Ninja 等。对vscode做了适配，依赖 VSCode 的 .vscode 目录下的 tasks.json、settings.json、c_cpp_properties.json + C/C++ 插件 + Task Buttons 插件；实现 在 VSCode 的左下角快速编译运行程序，以及代码的语法高亮与跳转。

    camke目录下提供了一些简易的cmake函数。

    支持conan，但需要根据此脚本的说明使用 conanfile.txt 或者 conanfile.py。推荐使用conanfile.py

    conan的知识需要自己学习，这里不做过多介绍。
```

## 如何使用

### 1. 安装依赖

- python
- CMake
- make / Ninja
- MSVC / gcc / clang
- conan (可选)
- VSCode(可选)
- C/C++ (VSCode插件、可选)
- Task Buttons (VSCode插件、可选)

### 2. 搭建项目

首先进入自己项目的根目录，运行此仓库的install.sh脚本，脚本会自动搭建好。

```bash
# 默认是
./install.sh

# 若install.sh不是最新版本
# 可以手动下载最新版本的install.sh，也可以用install.sh进行更新
./install.sh update
# or
./install.sh --update
```

前提：

- 项目根目录下应该不要存在.vscode目录，因为脚本会检查、备份以及看情况创建这个目录，为了避免冲突请在运行 install.sh 脚本的时候，请先清理好项目目录。

- 若不需要使用 vscode 可以不依赖 .vscode 目录，仅仅需要 cb.py 与 cb_conf.ini 文件即可。


### cb.py 的使用
cb.py 依赖 cb_conf.ini 文件，在使用 cb.py 之前请将 cb_conf.ini 放在其同级目录下。没有

#### cb_conf.ini 参数说明

cb_conf.ini 中的参数都可以自行进行合理的修改 ，以下是参数的说明：

```ini
[build]
build_type = Debug      # 编译类型为 Debug。目前可选 [Debug、Release]
source_dir = .          # 源码目录，.表示当前目录
generator = Ninja       # 构建工具，可选 [Ninja、Unix Makefiles ...]
parallel_jobs = auto    # 并行编译的线程数，auto为自动选择cpu核心数

[compiler]              # 编译器相关配置（不包括MSVC）
c_compiler = gcc        # c语言编译器
cpp_compiler = g++      # c++语言编译器
conan_enable = 1        # 是否使用conan，1、True、true表示使用，0、False、false表示不使用
conan_build = gcc       # conan 的 profile build 对应的 profile
conan_host = gcc        # conan 的 profile host 对应的 profile

[msvc]                  # msvc 编译器的参数不受 compiler 和 conan 影响。单独配置。
enable = 1              # 是否使用MSVC编译器，1、True、true表示使用，0、False、false表示不使用
msvc_env_script = D:/Develop/VisualStudio/2019/Community/VC/Auxiliary/Build/vcvarsall.bat # MSVC环境变量脚本路径
host_arch = x64         # 编译可执行程序的位数，可选 [x86、x64]
conan_enable = 1        # 是否使用conan，1、True、true表示使用，0、False、false表示不使用
conan_host = default_debug  # conan 的 profile host 对应的 profile ，没有 conanfile.txt 或 conanfile.py 时，不生效
conan_build = default_debug # conan 的 profile build 对应的 profile ，没有 conanfile.txt 或 conanfile.py 时，不生效

```

#### conanfile.py 示例

```python
from conan import ConanFile
# from conan.tools.cmake import cmake_layout
from conan.tools.files import copy
import os

class MyProjectConan(ConanFile):
    name = "myproject"
    version = "0.1"

    settings = "os", "compiler", "build_type", "arch"

    # 生成器
    generators = "CMakeToolchain", "CMakeDeps"

    def requirements(self):
        requires = []
        if self.settings.os == "Windows":
            requires = [
                "jsoncpp/1.9.5",
                "boost/1.81.0"
            ]
        else:
            requires = [
                
            ]
        for dep in requires:
            self.requires(dep)
    # 若要控制 库的链接方式，可以设置 requires_options。默认情况下，静态链接。
    requires_options = {
        "jsoncpp*:shared": True
    }

    def layout(self):
        # cmake_layout(self)
        # self.folders.build = os.path.join("build", str(self.settings.build_type))
        self.folders.build = ""
        self.folders.generators = os.path.join(self.folders.build, "generators")
        self.cpp.build.bindirs = ["bin"]
        self.cpp.build.libdirs = ["lib"]

    def generate(self):
        # if not self.options.shared:
        #     return
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

#### cb.py 使用命令说明

cb.py  脚本依赖 cb_conf.ini 文件中的参数具有一些记忆功能，但也可以通过命令行让其不过分依赖。

cb 脚本的使用方法如下：

```bash
# -t|--type 切换默认的编译类型
python cb.py -t
python cb.py -t Debug
python cb.py -t Release
python cb.py --type


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

也可以在终端中使用 cb 使用命令说明中的命令，也可以在 vscode 中使用 Task Buttons 插件，配置好快捷键，即可快速编译运行。
