# CMake 自定义宏与插件终端行为

状态：已完成。

## 关键决策

- Bash/Python 接受 `-DNAME=value` 和 `-D NAME=value`，保留每个定义的独立参数边界，并附加到 CMake 配置命令。
- `-D` 仅能与 `-g` / `--generate` 使用，不会触发隐式重新配置；其他动作使用时明确报错。
- 插件 Bootstrap 可选择 Python 或 Bash；GitHub/Gitee 内置源提供对应安装命令，自定义源通过 `bashCommand` 提供 Bash 安装方式，不自动推导。
- 插件仅将 `-r` / `--run` 发送到独立的 `run` 终端，其他操作复用 `cbuild` 终端，避免运行中的程序吞掉后续命令。
- 全局及项目级安装在 Unix 平台均为所选脚本设置可执行权限。
