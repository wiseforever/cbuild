# 构建目标参数

状态：已完成。

## 关键决策

- `-b` / `--build` 的位置参数与 `--target <target>` 语义一致，均表示 `BUILD_TARGET`。
- `-b Debug all` 可同时指定临时构建类型和构建目标；Bash/Python 帮助文本统一使用 `[target]`。
- 构建成功以 CMake 退出状态为准；库和自定义 target 不要求生成可执行文件，日志及 VS Code 启动路径更新为可选步骤。
- `-r` 的位置参数仍表示可执行文件名，并严格要求程序存在。

## 运行程序

- 使用 `-r` 指定运行程序；默认运行解析首个可执行文件。
- 相关规则见[清理安全与构建工作流](../workflow/safety_and_workflow_fixes.md)。
