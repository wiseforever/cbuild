# CMake 自定义宏与插件终端行为

## 目标

- 让 `cb.py` 与 `cb.sh` 接受标准 CMake 定义参数，并在配置阶段透传。
- 让项目级安装在 Linux/macOS 上为下载的 `cb.py` 或 `cb.sh` 设置可执行权限。
- Bootstrap 在选择安装源后，可明确选择安装 Python 版或 Bash 版脚本。
- 保持原有 `cbuild` 终端用于 Conan、生成、构建、切换、清理和自定义命令；仅将 `-r` / `--run` 发送到独立的 `run` 终端，避免运行中的程序吞掉后续命令。

## 实施步骤

1. 为两个构建脚本实现 `-DNAME=value` 和 `-D NAME=value` 参数解析，并仅在 `-g` / `--generate` 时附加到 CMake 配置命令。
2. 扩展插件 Bootstrap 配置，默认源提供 Python 与 Bash 两个安装命令；自定义源可通过 `bashCommand` 提供 Bash 安装命令。
3. 将插件终端管理拆分为 `cbuild` 与 `run` 两个复用终端。
4. 在项目级安装下载构建脚本后，为 Unix 平台设置可执行权限。
5. 更新中英文说明和插件说明，执行脚本语法、TypeScript 编译及 VSIX 打包验证。

## 验收标准

- `python3 cb.py -g -DFOO=bar` 与 `bash cb.sh -g -DFOO=bar` 都会向 CMake 传递 `-DFOO=bar`。
- 未指定 `-g` / `--generate` 时传递 `-D` 会清晰报错，不会静默忽略。
- 插件 Bootstrap 可选择 `Python (cb.py)` 或 `Bash (cb.sh)`；默认 Bash 命令使用 `install.sh ... --bash`。
- 插件点击 run 按钮后命令发送到名为 `run` 的终端，其他行为维持在 `cbuild` 终端。
- 在 Linux/macOS 的项目级安装后，所选 `cb.py` 或 `cb.sh` 具有可执行权限。

## 风险

- `-D` 是 CMake 配置参数，不会触发隐式重新配置；用户仍需显式执行 `-g`。
- 自定义 Bootstrap 源若未配置 `bashCommand`，插件不能安全推导 Bash 安装方式，应提示用户补充该字段。

## 操作留痕

- 已实现 `-DNAME=value` 与 `-D NAME=value` 两种参数形式；两个脚本会在 CMake 配置命令末尾保留每个定义的独立参数边界。
- 已限制 `-D` 只能与 `-g` / `--generate` 使用，避免构建或运行时被静默忽略。
- 已为 GitHub、Gitee 默认 Bootstrap 源添加 Bash 安装命令；自定义源可配置 `bashCommand`。
- 已将插件终端拆分为 `cbuild` 与 `run`，仅基础 `run` 操作使用后者。
- 已完成 `python3 -m py_compile cb.py`、`bash -n cb.sh`、Python/Bash 宏透传模拟、`npm run compile`、`npm run package` 与 `git diff --check` 验证。
- 已在 `install.sh` 的项目级安装分支添加 Unix 平台权限设置；全局安装原本已有该行为。
