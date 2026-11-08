# CMake 可执行文件输出路径解析

状态：已完成。

## 路径规则

- Bash/Python 对 POSIX 和 Windows 绝对路径保留原值，仅对相对路径补充 `BUILD_DIR`；`-b`、`-r` 和 VS Code 启动路径更新复用该逻辑。
- Ninja 解析同时支持 `C_EXECUTABLE_LINKER__` 和 `CXX_EXECUTABLE_LINKER__`，可执行文件列表支持冒号后的空白。
- 完整路径采用词法规范化，清理 `/./` 和可折叠的 `..`，不解析符号链接，不要求目标已经存在。
- 同一规范化规则用于配置阶段的 `SOURCE_DIR`、`BUILD_DIR`，覆盖 CMake 参数及清理日志。

## 边界

- 不改变 CMake 的实际输出目录配置。
- 独立的 `./`、`../`、`../../` 等相对路径前缀保持原样，不作为绝对路径规范化目标。
- 相关规则见[清理安全与构建工作流](../workflow/safety_and_workflow_fixes.md)。
