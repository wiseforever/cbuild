# CMake 可执行文件输出路径解析

## 目标

- 修复 Ubuntu 18 等旧版 CMake 生成绝对链接输出路径时，`cb.sh -b`、`cb.sh -r` 和 `cb.sh -t` 写出错误可执行文件路径的问题。
- 保持 Bash 与 Python 两个入口的输出路径解析行为一致。

## 实施步骤

1. 解析 `build.ninja` 或 Makefile `link.txt` 时，识别绝对 POSIX 和 Windows 路径。
2. 仅对相对输出路径加上 `BUILD_DIR` 前缀。
3. 用构造的 Ninja/Makefile 构建元数据验证绝对与相对路径两种情况，并检查 Bash/Python 语法。

## 验收标准

- `build.ninja` 内的 `/path/to/output/App` 被解析为 `/path/to/output/App`，不会重复添加构建目录。
- 相对输出路径仍解析到 `<BUILD_DIR>/<relative-output-dir>`。
- `-b`、`-r` 和更新 VS Code 启动配置所共用的路径解析均正确。

## 风险

- 该修复只改变构建元数据中已经是绝对路径的处理方式；CMake 的实际输出目录配置不变。

## 操作留痕

- 已定位：`get_bin_dir` 对绝对 Ninja/Makefile 输出路径无条件拼接 `BUILD_DIR`，导致 Ubuntu 18 的错误路径。
- 已在 `cb.sh` 与 `cb.py` 中实现绝对路径保留、相对路径拼接的统一处理；`-b`、`-r` 和 `-t` 更新 VS Code 启动路径会复用该逻辑。
- 已通过 `bash -n cb.sh`、`python3 -m py_compile cb.py`、`git diff --check` 以及绝对/相对路径解析模拟验证。
- 已补充路径词法规范化：构建元数据拼接为完整路径后会清理冗余的 `/./` 与可折叠的 `..`，使日志、运行命令和 VS Code 启动配置不再包含冗余目录段；独立的 `./`、`../`、`../../` 等相对路径前缀不作为此规范化目标。
- 已验证 Bash 与 Python 的根目录、`/./`、内部 `..`、Windows 风格绝对路径及独立相对前缀样例；同时通过 `bash -n cb.sh`、`python3 -m py_compile cb.py` 和 `git diff --check`。
