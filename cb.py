#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import platform
import subprocess
import shutil
import re
import configparser
import importlib.util
import logging

logging.basicConfig(
    level=logging.DEBUG,
    # format='%(asctime)s [%(levelname)s] [%(filename)s:%(lineno)d]: %(message)s'
    format='[%(levelname)s] [%(filename)s:%(lineno)d]: %(message)s'
)
log = logging.getLogger()

# -------------------- 配置文件 --------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(SCRIPT_DIR, "cb_conf.ini")

# -------------------- 读取配置 --------------------
CONFIG = configparser.ConfigParser()
CONFIG.read(CONFIG_FILE, encoding="utf-8")

BUILD_TYPE = CONFIG.get("build", "build_type", fallback="Release")
VALID_BUILD_TYPES = ["Debug", "Release"]
SOURCE_DIR = CONFIG.get("build", "source_dir", fallback=".")
BUILD_DIR = None
GENERATOR = CONFIG.get("build", "generator", fallback="Ninja")
PARALLEL_JOBS_RAW = CONFIG.get("build", "parallel_jobs", fallback="auto")
if str(PARALLEL_JOBS_RAW).lower() == "auto":
    PARALLEL_JOBS = os.cpu_count() or 1
else:
    PARALLEL_JOBS = int(PARALLEL_JOBS_RAW)

c_compiler = CONFIG.get("compiler", "c_compiler", fallback=None)
cpp_compiler = CONFIG.get("compiler", "cpp_compiler", fallback=None)
CONAN_ENABLER = CONFIG.getboolean("compiler", "conan_enable", fallback=False)
CONAN_BUILD = CONFIG.get("compiler", "conan_build", fallback=None)
CONAN_HOST = CONFIG.get("compiler", "conan_host", fallback=None)

MSVC_ENABLE = False
MSVC_ENV_SCRIPT = None
HOST_ARCH = None

COMPILER_TYPE = None
COMPILER_EXEC_P = []
CMAKE_TOOLCHAIN_FILE = None

# -------------------- 系统识别 --------------------
OS_TYPE = platform.system().lower()
if OS_TYPE == "windows":
    MSVC_ENABLE = CONFIG.getboolean("msvc", "enable", fallback=False)
    MSVC_ENV_SCRIPT = CONFIG.get("msvc", "msvc_env_script", fallback=None)
    HOST_ARCH = CONFIG.get("msvc", "host_arch", fallback="x64")
    c_compiler = c_compiler or "gcc.exe"
    cpp_compiler = cpp_compiler or "g++.exe"
elif OS_TYPE == "linux":
    c_compiler = c_compiler or "gcc"
    cpp_compiler = cpp_compiler or "g++"
elif OS_TYPE == "darwin":
    c_compiler = c_compiler or "clang"
    cpp_compiler = cpp_compiler or "clang++"
else:
    log.error(f"Unknown system: {OS_TYPE}")
    sys.exit(1)

C_COMPILER_EXEC = c_compiler
CXX_COMPILER_EXEC = cpp_compiler

# -------------------- 工具函数 --------------------
def get_compiler_type(compiler):
    if MSVC_ENABLE and MSVC_ENV_SCRIPT:
        return "msvc"
    if compiler is None:
        return "unknown"
    base = os.path.basename(compiler).lower()
    if base in ["gcc", "gcc.exe"]:
        return "gcc"
    elif base in ["g++", "g++.exe"]:
        return "g++"
    elif base in ["clang", "clang.exe"]:
        return "clang"
    elif base in ["clang++", "clang++.exe"]:
        return "clang++"
    elif base in ["cl", "cl.exe", "vcvarsall.bat"]:
        return "msvc"
    return "unknown"

COMPILER_TYPE = get_compiler_type(CXX_COMPILER_EXEC or C_COMPILER_EXEC)

def rm_rf(path):
    """跨平台删除文件或目录，等价 rm -rf"""
    import os
    import shutil

    if not os.path.exists(path):
        return  # 路径不存在，直接返回

    try:
        if os.path.isdir(path):
            shutil.rmtree(path)
        else:
            os.remove(path)
    except Exception as e:
        log.warning(f"Failed to remove {path}: {e}")

def get_project_name_simple():
    cmakelists = os.path.join(SOURCE_DIR, "CMakeLists.txt")
    if not os.path.isfile(cmakelists):
        return "application"
    with open(cmakelists, "r", encoding="utf-8") as f:
        content = f.read()
    m = re.search(r'project\s*\(\s*([^\s\)]+)', content, re.IGNORECASE)
    if m:
        name = m.group(1)
        if name.startswith("${") and name.endswith("}"):
            var_name = name[2:-1]
            m2 = re.search(rf'set\s*\(\s*{var_name}\s+"([^"]+)"\)', content)
            if m2:
                return m2.group(1)
        return name
    return "application"

def save_config():
    if "build" not in CONFIG:
        CONFIG.add_section("build")
    CONFIG.set("build", "build_type", BUILD_TYPE)
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        CONFIG.write(f)

def update_vscode_launch():
    """更新 .vscode/launch.json 中的 program 路径，保留注释"""
    launch_json_path = os.path.join(SOURCE_DIR, ".vscode", "launch.json")
    if not os.path.isfile(launch_json_path):
        return  # 没有 launch.json 就跳过

    try:
        with open(launch_json_path, "r", encoding="utf-8") as f:
            content = f.read()

        app_name = get_project_name_simple()
        prepare_build_dir()
        program_path = f"${{workspaceFolder}}/{os.path.relpath(BUILD_DIR, SOURCE_DIR).replace(os.sep, '/')}/bin/{app_name}"

        # 用正则匹配 "program": "xxx"
        # 保留前后的引号和 key，只替换路径
        new_content, n = re.subn(
            r'("program"\s*:\s*")[^"]*(")',
            rf'\1{program_path}\2',
            content
        )

        if n > 0:
            # 先备份原文件
            bak_file = launch_json_path + ".bak"
            with open(bak_file, "w", encoding="utf-8") as f:
                f.write(content)

            # 写回修改后的内容
            with open(launch_json_path, "w", encoding="utf-8") as f:
                f.write(new_content)

            log.info(f"Updated .vscode/launch.json program -> {program_path}")
        else:
            log.warning("No program field found in launch.json")
    except Exception as e:
        log.warning(f"Failed to update launch.json: {e}")

def is_option_token(tok: str) -> bool:
    return tok.startswith("-")

# -------------------- 命令行参数 --------------------
SHOULD_CONFIGURE = False
SHOULD_BUILD = False
SHOULD_RUN = False
SHOULD_CLEAN = False
BUILD_TARGET = "all"
EXIT_AFTER_TYPE_CHANGE = False  # 仅切换类型时立即退出

def parse_args():
    global BUILD_TYPE, SHOULD_BUILD, SHOULD_CONFIGURE, SHOULD_RUN, SHOULD_CLEAN, BUILD_TARGET, EXIT_AFTER_TYPE_CHANGE
    args = sys.argv[1:]
    i = 0
    BUILD_TARGET = "all"

    type_changed = False
    had_action = False

    while i < len(args):
        arg = args[i]
        if arg in ("-h", "--help"):
            print("Usage: cb.py [options]")
            print("Options:")
            print("  -t, --type [Debug|Release]   不带参数时在 Debug/Release 间切换，并保存到 config.ini")
            print("  -g, --generate               仅运行 CMake 配置")
            print("  -b, --build [<type>] [--target <target>]   构建项目")
            print("  -r, --run [<type>]           运行程序")
            print("  -c, --clean [<type>]         清理构建目录")
            sys.exit(0)

        elif arg in ("-t", "--type"):
            next_is_value = (i + 1 < len(args)) and (not is_option_token(args[i + 1]))
            if next_is_value:
                new_type = args[i + 1].capitalize()
                i += 1
                if new_type not in VALID_BUILD_TYPES:
                    log.error(f"Invalid build type: {new_type}, valid types are: {VALID_BUILD_TYPES}")
                    sys.exit(1)
                if new_type != BUILD_TYPE:
                    BUILD_TYPE = new_type
                    save_config()
                    update_vscode_launch()
                    log.info(f"The build type has been switched to: {BUILD_TYPE}")
                    type_changed = True
                else:
                    log.info(f"The build type is already: {BUILD_TYPE}")
            else:
                BUILD_TYPE = "Debug" if BUILD_TYPE == "Release" else "Release"
                save_config()
                update_vscode_launch()
                log.info(f"The build type has been switched to: {BUILD_TYPE}")
                type_changed = True

        elif arg in ("-g", "--generate"):
            SHOULD_CONFIGURE = True
            had_action = True

        elif arg in ("-b", "--build"):
            SHOULD_BUILD = True
            had_action = True
            if i + 1 < len(args) and not is_option_token(args[i + 1]) and args[i + 1].capitalize() in VALID_BUILD_TYPES:
                BUILD_TYPE = args[i + 1].capitalize()
                i += 1
            if i + 2 < len(args) and args[i + 1] == "--target":
                BUILD_TARGET = args[i + 2]
                i += 2

        elif arg in ("-r", "--run"):
            SHOULD_RUN = True
            had_action = True
            if i + 1 < len(args) and not is_option_token(args[i + 1]) and args[i + 1].capitalize() in VALID_BUILD_TYPES:
                BUILD_TYPE = args[i + 1].capitalize()
                i += 1

        elif arg in ("-c", "--clean"):
            SHOULD_CLEAN = True
            had_action = True
            if i + 1 < len(args) and not is_option_token(args[i + 1]) and args[i + 1].capitalize() in VALID_BUILD_TYPES:
                BUILD_TYPE = args[i + 1].capitalize()
                i += 1

        else:
            log.error(f"Unknown option: {arg}")
            sys.exit(1)

        i += 1

    EXIT_AFTER_TYPE_CHANGE = (type_changed and not had_action)

# -------------------- 构建目录 --------------------
def detect_compiler_version(compiler_type, c_compiler_exec, cxx_compiler_exec,
                            msvc_env_script=None, host_arch="x64"):
    try:
        if compiler_type in ("gcc", "g++"):
            compiler_exec = c_compiler_exec if compiler_type == "gcc" else cxx_compiler_exec
            result = subprocess.run([compiler_exec, "--version"], capture_output=True, text=True, check=True)
            first_line = result.stdout.splitlines()[0]
            m = re.search(r"(\d+(\.\d+){1,2})", first_line)
            ver = m.group(1) if m else "unknown"
            if "mingw" in first_line.lower():
                return f"MinGW-{ver}"
            else:
                return f"GCC-{ver}"
        elif compiler_type in ("clang", "clang++"):
            compiler_exec = c_compiler_exec if compiler_type == "clang" else cxx_compiler_exec
            result = subprocess.run([compiler_exec, "--version"], capture_output=True, text=True, check=True)
            first_line = result.stdout.splitlines()[0]
            m = re.search(r"(\d+(\.\d+){1,2})", first_line)
            ver = m.group(1) if m else "unknown"
            return f"Clang-{ver}"
        elif compiler_type == "msvc":
            # result = subprocess.run(["cl"], capture_output=True, text=True)
            # out = result.stdout or result.stderr
            # m = re.search(r"Version\s+([0-9]+\.[0-9]+)", out, re.IGNORECASE)
            # if m:
            #     return f"MSVC-{m.group(1)}"
            # else:
            #     return "MSVC-unknown"
            return f"MSVC-{host_arch}"
        else:
            return "Default"
    except FileNotFoundError:
        log.error(f"Compiler not found: {compiler_type}")
        return "unknown"

def prepare_build_dir():
    global BUILD_DIR
    if BUILD_DIR is None:
        compiler_id = detect_compiler_version(
            COMPILER_TYPE,
            C_COMPILER_EXEC,
            CXX_COMPILER_EXEC,
            MSVC_ENV_SCRIPT,
            HOST_ARCH or "x64"
        )
        BUILD_DIR = os.path.join(SOURCE_DIR, "build", f"{compiler_id}-{BUILD_TYPE}").replace("\\", "/")
    os.makedirs(BUILD_DIR, exist_ok=True)

def copy_compile_commands():
    src = os.path.join(BUILD_DIR, "compile_commands.json").replace("\\", "/")
    dst = os.path.join(SOURCE_DIR, "build", "compile_commands.json").replace("\\", "/")
    if os.path.isfile(src):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        log.info(f"Copy compile_commands.json to {dst}")

def read_conanfile_py_options(conanfile_path):
    try:
        from conan import ConanFile
    except ModuleNotFoundError:
        log.warning("The Conan module is not installed. Skip.")
        return []

    spec = importlib.util.spec_from_file_location("conanfile_module", conanfile_path)
    conanfile_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(conanfile_module)

    # 遍历模块内的类，找到继承自 ConanFile 的类
    for attr in dir(conanfile_module):
        obj = getattr(conanfile_module, attr)
        if isinstance(obj, type) and issubclass(obj, ConanFile) and obj is not ConanFile:
            requires_options = getattr(obj, "requires_options", {})
            # 转换成 Conan CLI 参数
            options_list = []
            for key, value in requires_options.items():
                # val_str = str(value).lower() if isinstance(value, bool) else str(value)
                val_str = str(value) if not isinstance(value, bool) else str(value)
                options_list.append(f"-o {key}={val_str}")
            return options_list
    return []

def read_conanfile_txt_options(conanfile_txt_path):
    import configparser
    config = configparser.ConfigParser()
    config.read(conanfile_txt_path)
    options_list = []
    if config.has_section("options"):
        for key, value in config.items("options"):
            options_list.append(f"-o {key}={value}")
    return options_list

def get_generators_folder(conanfile_path):
    try:
        from conan import ConanFile
    except ModuleNotFoundError:
        log.warning("The Conan module is not installed. Skip.")
        return []
    
    spec = importlib.util.spec_from_file_location("conanfile_module", conanfile_path)
    conanfile_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(conanfile_module)

    # 找到继承自 ConanFile 的类
    for attr in dir(conanfile_module):
        cls = getattr(conanfile_module, attr)
        if isinstance(cls, type) and issubclass(cls, ConanFile) and cls is not ConanFile:
            instance = cls()
            # 调用 layout 方法确保 folders.generators 被正确设置
            if hasattr(instance, "layout"):
                instance.layout()
            return instance.folders.generators
    return None

# -------------------- Conan 处理 --------------------
def run_conan_install():
    try:
        from conan import ConanFile
    except ModuleNotFoundError:
        log.warning("The Conan module is not installed. Skip.")
        return
    global CONAN_HOST, CONAN_BUILD, CONAN_ENABLER

    if MSVC_ENABLE and MSVC_ENV_SCRIPT:
        CONAN_ENABLER = CONFIG.getboolean("msvc", "conan_enable", fallback=False)

    if not CONAN_ENABLER:
        return

    conan_file_txt = os.path.join(SOURCE_DIR, "conanfile.txt")
    conan_file_py = os.path.join(SOURCE_DIR, "conanfile.py")

    if os.path.isfile(conan_file_txt) or os.path.isfile(conan_file_py):
        if MSVC_ENABLE and MSVC_ENV_SCRIPT:
            CONAN_HOST = CONFIG.get("msvc", "conan_host", fallback=None)
            CONAN_BUILD = CONFIG.get("msvc", "conan_build", fallback=None)

        cmd = ["conan", "install", SOURCE_DIR, "-s", f"build_type={BUILD_TYPE}", "--output-folder", BUILD_DIR, "--build=missing"]
        if CONAN_HOST != None:
            cmd += ["--profile:host", CONAN_HOST]
        if CONAN_BUILD != None:
            cmd += ["--profile:build", CONAN_BUILD]

        options_list = []
        if os.path.isfile(conan_file_py):
            options_list += read_conanfile_py_options(conan_file_py)
        if os.path.isfile(conan_file_txt):
            options_list += read_conanfile_txt_options(conan_file_txt)
        if options_list:
            cmd += options_list

        log.info(" ".join(f'"{c}"' if " " in c else c for c in cmd))
        subprocess.run(cmd, check=True)

        # toolchain_file = os.path.join(BUILD_DIR, "generators/conan_toolchain.cmake")
        generators_folder = get_generators_folder(conan_file_py)
        if generators_folder is None:
            toolchain_file = os.path.join(BUILD_DIR, "conan_toolchain.cmake")
        else:
            toolchain_file = os.path.join(BUILD_DIR, generators_folder, "conan_toolchain.cmake")
        
        if os.path.isfile(toolchain_file):
            bak_file = toolchain_file + ".bak"
            shutil.copy2(toolchain_file, bak_file)
            with open(toolchain_file, "r", encoding="utf-8") as f:
                content = f.read()
            content = re.sub(
                r'^(set\(CMAKE_GENERATOR_(PLATFORM|TOOLSET).*FORCE\)|message\(STATUS "Conan toolchain: CMAKE_GENERATOR_TOOLSET=.*"\)|string\(APPEND CONAN_(CXX_FLAGS|C_FLAGS) " /MP[0-9]+"\))',
                r'# \1',
                content,
                flags=re.MULTILINE
            )
            with open(toolchain_file, "w", encoding="utf-8") as f:
                f.write(content)
            global CMAKE_TOOLCHAIN_FILE
            CMAKE_TOOLCHAIN_FILE = toolchain_file.replace("\\", "/")

# -------------------- 配置 & 构建 --------------------
def run_cmake_configure():
    if MSVC_ENABLE and MSVC_ENV_SCRIPT:
        # 确保路径为反斜杠
        msvc_env = MSVC_ENV_SCRIPT.replace("/", "\\")

        # 先生成 Conan toolchain
        run_conan_install()

        cmake_configure_cmd = f'cmake -S "{SOURCE_DIR}" -B "{BUILD_DIR}" -G "{GENERATOR}" -DCMAKE_BUILD_TYPE={BUILD_TYPE}'
        if COMPILER_EXEC_P:
            cmake_configure_cmd += " " + " ".join(COMPILER_EXEC_P)
        if CMAKE_TOOLCHAIN_FILE:
            cmake_configure_cmd += f' -DCMAKE_TOOLCHAIN_FILE="{CMAKE_TOOLCHAIN_FILE}"'

        # 在 cmd 中调用 vcvarsall.bat，然后执行 cmake 配置
        log.info(cmake_configure_cmd)
        return subprocess.run(f'call "{msvc_env}" {HOST_ARCH} && {cmake_configure_cmd}', shell=True, check=True)
    else:
        run_conan_install()
        cmd = ["cmake", "-S", SOURCE_DIR, "-B", BUILD_DIR, "-G", GENERATOR, f"-DCMAKE_BUILD_TYPE={BUILD_TYPE}"]
        if COMPILER_EXEC_P:
            cmd += COMPILER_EXEC_P
        if CMAKE_TOOLCHAIN_FILE:
            cmd.append(f"-DCMAKE_TOOLCHAIN_FILE={CMAKE_TOOLCHAIN_FILE}")
        log.info(" ".join(f'"{c}"' if " " in c else c for c in cmd))
        return subprocess.run(cmd, check=True)

def run_cmake_build():
    cmd = ["cmake", "--build", BUILD_DIR, "--target", BUILD_TARGET, f"-j{PARALLEL_JOBS}"]
    # print(cmd)
    log.info(" ".join(f'"{c}"' if " " in c else c for c in cmd))
    return subprocess.run(cmd, check=True)

def run_msvc_build():
    # 确保路径为反斜杠
    msvc_env = MSVC_ENV_SCRIPT.replace("/", "\\")

    # 先生成 Conan toolchain
    run_conan_install()

    # 1. 配置 CMake
    cmake_configure_cmd = f'cmake -S "{SOURCE_DIR}" -B "{BUILD_DIR}" -G "{GENERATOR}" -DCMAKE_BUILD_TYPE={BUILD_TYPE}'
    if COMPILER_EXEC_P:
        cmake_configure_cmd += " " + " ".join(COMPILER_EXEC_P)
    if CMAKE_TOOLCHAIN_FILE:
        cmake_configure_cmd += f' -DCMAKE_TOOLCHAIN_FILE="{CMAKE_TOOLCHAIN_FILE}"'

    # 在 cmd 中调用 vcvarsall.bat，然后执行 cmake 配置
    log.info(cmake_configure_cmd)
    subprocess.run(f'call "{msvc_env}" {HOST_ARCH} && {cmake_configure_cmd}', shell=True, check=True)

    rm_rf(os.path.join(SOURCE_DIR, "CMakeUserPresets.json"))

    # 2. 拷贝 compile_commands.json（用 Python 内部操作）
    copy_compile_commands()

    # 3. 构建
    cmake_build_cmd = f'cmake --build "{BUILD_DIR}" --target {BUILD_TARGET} -j{PARALLEL_JOBS}'
    log.info(cmake_build_cmd)
    subprocess.run(f'call "{msvc_env}" {HOST_ARCH} && {cmake_build_cmd}', shell=True, check=True)



def run_application():
    app_name = get_project_name_simple()
    exe_path = os.path.join(BUILD_DIR, "bin", app_name + (".exe" if OS_TYPE == "windows" else "")).replace("\\", "/")
    if not os.path.isfile(exe_path):
        log.error(f"The executable file: {exe_path} cannot be found. ")
        sys.exit(1)
    log.info(f"Running {exe_path} ...")
    try:
        # 直接使用run，Python会自动处理Ctrl+C信号传递
        subprocess.run(exe_path, check=True)
    except KeyboardInterrupt:
        log.info("\nProcess interrupted by user (Ctrl+C)")
        sys.exit(130)  # 130是通常用于Ctrl+C退出的代码
    except subprocess.CalledProcessError as e:
        log.error(f"Application exited with error code: {e.returncode}")
        sys.exit(e.returncode)

def clean_build():
    global BUILD_DIR
    if BUILD_DIR is None:
        # 尝试初始化 BUILD_DIR
        compiler_id = detect_compiler_version(
            COMPILER_TYPE,
            C_COMPILER_EXEC,
            CXX_COMPILER_EXEC,
            MSVC_ENV_SCRIPT,
            HOST_ARCH or "x64"
        )
        BUILD_DIR = os.path.join(SOURCE_DIR, "build", f"{compiler_id}-{BUILD_TYPE}").replace("\\", "/")

    if os.path.isdir(BUILD_DIR):
        log.info(f"Cleaning {BUILD_DIR} ...")
        shutil.rmtree(BUILD_DIR)

    compile_json = os.path.join(SOURCE_DIR, "build", "compile_commands.json")
    if os.path.isfile(compile_json):
        os.remove(compile_json)

# -------------------- 执行 --------------------
def run():
    parse_args()

    if EXIT_AFTER_TYPE_CHANGE:
        return

    prepare_build_dir()

    if SHOULD_CLEAN:
        clean_build()
        return

    if SHOULD_CONFIGURE:
        if run_cmake_configure():
            rm_rf(os.path.join(SOURCE_DIR, "CMakeUserPresets.json"))
            copy_compile_commands()
        else:
            log.error("CMake configure failed.")
        return

    if SHOULD_BUILD:
        if MSVC_ENABLE and MSVC_ENV_SCRIPT:
            run_msvc_build()
        else:
            if run_cmake_configure():
                rm_rf(os.path.join(SOURCE_DIR, "CMakeUserPresets.json"))
                copy_compile_commands()
                if not run_cmake_build():
                    log.error("CMake build failed.")
            else:
                log.error("CMake configure failed.")
        
        app_name = get_project_name_simple()
        exe_path = os.path.join(BUILD_DIR, "bin", app_name + (".exe" if OS_TYPE == "windows" else "")).replace("\\", "/")
        if not os.path.isfile(exe_path):
            log.error(f"The executable file: {exe_path} cannot be found.")
            sys.exit(1)
        update_vscode_launch()
        log.info(f"exec: {exe_path}")
        return

    if SHOULD_RUN:
        run_application()
        return

    print("请使用 -h 查看使用帮助")

if __name__ == "__main__":
    try:
        run()
    except KeyboardInterrupt:
        log.info("\nProcess interrupted by user (Ctrl+C)")
        sys.exit(130)  # 130是通常用于Ctrl+C退出的代码
    except Exception as e:
        log.error(f"{e}")
        sys.exit(1)

