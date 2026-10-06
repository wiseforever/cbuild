# 构建目标参数

## 目标

- 让 `-b` / `--build` 的位置参数与 `--target <target>` 语义一致，都表示构建目标。
- 修正 `-b all` 被当作 `EXEC_NAME` 导致构建后无法解析可执行文件的问题。
- 保持 Bash 与 Python 两个入口行为一致。

## 背景

- 上一次提交为 `-b` / `-r` 增加了位置参数用作可执行文件名，但 `-b` 的位置参数被赋给 `EXEC_NAME`。
- 由于 `BUILD_TARGET` 默认为 `all`，`-b all` 的编译命令与 `-b --target all` 相同，但随后 `get_exec_path("all")` 找不到可执行文件而报错退出。
- `cb.py` 帮助文本写 `[target]`、`cb.sh` 写 `[exe_name]`，两者不一致且前者与实现不符。

## 实施步骤

1. `cb.py` 与 `cb.sh` 的 `-b` 解析中，把未显式以 `--target` 给出的位置参数赋给 `BUILD_TARGET`。
2. 统一 `cb.sh` 帮助文本为 `[target]`。

## 验收标准

- `-b all` 与 `-b --target all` 解析结果一致（`BUILD_TARGET=all`，`EXEC_NAME` 为空）。
- `-b Debug all` 能同时设置构建类型与目标。
- `-r` 的位置参数仍作为可执行文件名。

## 风险

- `-b` 不再通过位置参数指定可执行文件名；指定可执行文件名仍可用 `-r` 或依赖默认的首个可执行文件解析。

## 操作留痕

- 已修改 `cb.py:484`、`cb.sh:822` 的 `-b` 解析：位置参数改赋给 `BUILD_TARGET`，`--target` 分支保持不变。
- 已将 `cb.sh` 帮助项从 `[exe_name]` 更正为 `[target]`。
- 已通过 `bash -n cb.sh`、`python3 -m py_compile cb.py` 及参数解析模拟验证：`-b all` 与 `-b --target all` 结果一致。
