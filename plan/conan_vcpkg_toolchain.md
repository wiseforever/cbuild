# Conan 与 vcpkg 组合工具链

## 目标

- 保持 Conan 现有 `conan_toolchain.cmake` 生成与兼容处理流程。
- 支持通过 `cb_conf.ini` 指定 vcpkg 根目录或 `vcpkg.cmake` 的直接路径。
- 在构建目录生成唯一的 `cbuild_toolchain.cmake`，作为 CMake 的 `CMAKE_TOOLCHAIN_FILE`。
- 支持用户维护的 `cbuild_custom.cmake`，在 vcpkg 初始化前由生成的包装工具链加载。
- 增加 Boost（Conan）与 JsonCpp（vcpkg）的混合依赖示例。

## 实施步骤

1. 为 Python 与 Bash 脚本加入 vcpkg / 自定义工具链配置解析和 wrapper 生成逻辑。
2. 添加 vcpkg manifest、CMake 链接配置、C++ 示例与用户自定义工具链模板。
3. 更新中英文文档及配置模板。
4. 用两套脚本分别执行依赖安装、配置、构建和运行验证。

## 验收标准

- `cb.py -g` 与 `cb.sh -g` 都仅向 CMake 传入生成的 `cbuild_toolchain.cmake`。
- wrapper 能设置可选 triplet，加载用户 `cbuild_custom.cmake`，并由 vcpkg chainload Conan toolchain。
- 示例程序能输出 Boost 版本和由 JsonCpp 序列化的 JSON。

## 风险

- Conan profile、vcpkg triplet 与用户自定义工具链必须指向兼容的编译器、架构与运行时。
- 更换 triplet 或工具链后需要清理旧构建目录，避免 CMake cache 复用旧配置。

## 操作记录

- 已确认仓库位于 `master` 分支，工作区无未提交改动。
- 已为 `cb.py` 与 `cb.sh` 增加 `[vcpkg]`、`[toolchain]` 配置解析，以及 `cbuild_toolchain.cmake` 生成逻辑。
- wrapper 会先加载用户维护的 `cbuild_custom.cmake`，再由 vcpkg 通过 `VCPKG_CHAINLOAD_TOOLCHAIN_FILE` 加载 Conan toolchain。
- 已添加 `vcpkg.json`（`jsoncpp`）、Boost + JsonCpp 示例、配置模板和中英文说明；`conanfile.py` 未改动。
- 已增加 CMake cache 中 toolchain 不匹配的保护，提示先执行 `-c` 清理旧构建目录。
- 已验证：`python3 cb.py --conan && python3 cb.py -g && python3 cb.py -b && python3 cb.py -r`。
- 已验证：`bash cb.sh -g && bash cb.sh -b && bash cb.sh -r`。
- 两套流程均解析 Conan Boost 1.84.0、安装/复用 vcpkg JsonCpp 1.9.6，并成功运行示例。
