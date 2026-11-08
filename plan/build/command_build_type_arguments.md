# 命令行构建类型参数

状态：已完成。

## 关键决策

- Bash/Python 的 `-g` / `--generate` 与 `-b` 一样支持临时指定 `Debug` / `Release`，参数不区分大小写。
- 动作参数仅对当前命令有效，不写入 `cb.conf`；`-t` 保持持久修改配置的语义。
- 构建目录缓存记录对应构建类型，类型变化后重新计算，避免 VS Code 更新提前初始化目录后缓存失效。
- `-t Debug -g Release` 持久配置为 Debug，实际配置类型及目录为 Release；`-t Debug -g` 仍按 Debug 进入配置流程。
- 帮助及中英文示例同步该语义；相关缓存调整见[构建工作流](../workflow/safety_and_workflow_fixes.md)。
