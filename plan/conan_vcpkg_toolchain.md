# Conan 与 vcpkg 组合工具链

## 目标

- 保持 Conan 现有 `conan_toolchain.cmake` 生成与兼容处理流程。
- 支持通过 `cb.conf` 指定 vcpkg 根目录或 `vcpkg.cmake` 的直接路径。
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
- 更换 triplet 或工具链时，脚本会仅重置过期的 CMake 缓存，保留 Conan 生成文件，并继续执行 `-g`。

## 操作记录

- 已确认仓库位于 `master` 分支，工作区无未提交改动。
- 已为 `cb.py` 与 `cb.sh` 增加 `[vcpkg]`、`[toolchain]` 配置解析，以及 `cbuild_toolchain.cmake` 生成逻辑。
- wrapper 会先加载用户维护的 `cbuild_custom.cmake`，再由 vcpkg 通过 `VCPKG_CHAINLOAD_TOOLCHAIN_FILE` 加载 Conan toolchain。
- 已添加 `vcpkg.json`（`jsoncpp`）、Boost + JsonCpp 示例、配置模板和中英文说明；`conanfile.py` 未改动。
- 已将 CMake cache 与工具链不匹配时的脚本级阻断改为自动重置 `CMakeCache.txt` 与 `CMakeFiles/`；`-g` 会继续将当前工具链参数传给 CMake，且无需再次执行 Conan。
- 已在 `/home/a/share/git/pcieAutoCalibration` 验证：首次缺少 Ceres 的缓存存在时，`--conan` 后直接 `-g` 会加载 Conan toolchain、发现 `Ceres::ceres` 并完成配置。
- 已在 `ubuntu18.04-amd64-dev` 验证：`-g` 会加载 Conan toolchain，不再出现工具链缓存阻断或 Ceres 查找错误；该容器当前配置随后因缺少 Qt5 开发包配置而停止，属于独立环境依赖问题。
- 已验证：`python3 cb.py --conan && python3 cb.py -g && python3 cb.py -b && python3 cb.py -r`。
- 已验证：`bash cb.sh -g && bash cb.sh -b && bash cb.sh -r`。
- 两套流程均解析 Conan Boost 1.84.0、安装/复用 vcpkg JsonCpp 1.9.6，并成功运行示例。
