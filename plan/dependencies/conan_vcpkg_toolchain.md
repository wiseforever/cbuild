# Conan 与 vcpkg 组合工具链

状态：已完成。

## 关键决策

- Bash/Python 读取 `[vcpkg]`、`[toolchain]` 配置，处理 Conan 生成的 `conan_toolchain.cmake`。
- 在构建目录生成唯一的 `cbuild_toolchain.cmake`，作为传给 CMake 的 `CMAKE_TOOLCHAIN_FILE`。
- wrapper 先加载用户维护的 `cbuild_custom.cmake`，再由 vcpkg 通过 `VCPKG_CHAINLOAD_TOOLCHAIN_FILE` 加载 Conan toolchain，并支持可选 triplet。
- vcpkg 可配置根目录或 `vcpkg.cmake` 的直接路径，默认也支持环境变量 `VCPKG_ROOT`。
- 工具链变化时仅重置过期的 `CMakeCache.txt` 与 `CMakeFiles/`，保留 Conan 生成文件，继续执行 `-g`，无需重新执行 Conan。
- 示例通过 `vcpkg.json` 使用 JsonCpp，通过 Conan 使用 Boost，并提供用户自定义工具链模板。

## 风险

- Conan profile、vcpkg triplet 与自定义工具链必须指向兼容的编译器、架构和运行时。
- 工具链包装不负责补齐 Qt 等项目自身的开发依赖。
