# 安装脚本的全局与 VS Code 模板模式

## 目标

- 默认全局安装 Bash 版本，并避免重复写入 PATH 配置。
- 提供仅安装 `.vscode` 模板到当前或指定目录的命令。
- 按 GitHub 与 Gitee 下载源分组说明安装命令。

## 实施步骤

1. 将安装默认模式改为全局 Bash，并保留 `--simple` 与 `--python` 显式切换。
2. 新增 `--vscode [目录]`，仅下载 VS Code 模板，并备份同名目录。
3. 保留 PATH 检测，在当前 PATH 或 shell rc 已有安装目录时跳过写入。
4. 更新中英文 README。

## 验收标准

- 全局默认安装下载 `cb.sh`、`install.sh` 与卸载脚本，不下载 `cb_conf.ini`。
- 重复执行全局安装不重复增加 shell rc 的 PATH 条目。
- `--vscode` 只安装四个模板文件，并备份原 `.vscode`。

## 风险

- 独立 VS Code 模板安装会移动目标目录中已有的 `.vscode` 到备份目录。
- 全局更新会覆盖受管理脚本，并删除旧的 Bash/Python 脚本变体；手动维护的回退 `cb_conf.ini` 会保留。

## 操作留痕

- 已实现默认 Bash 安装、`--vscode [目录]` 模式及按下载源分组的文档调整。
- 已通过本地 HTTP 下载源模拟：`--vscode` 安装四个模板并备份旧目录；全局默认安装仅下载 `cb.sh` 与卸载脚本、不下载 `cb_conf.ini`；重复全局安装的 shell rc PATH 条目数量保持为 1。
- 已调整为默认全局安装，并增加全局 `install.sh` 自更新与旧脚本变体清理。
- 已通过本地 HTTP 下载源模拟首次安装、从已安装的 `install.sh` 重复更新以及 Python 变体切换：默认安装为 Bash，`install.sh` 可自更新，旧变体被清理，手动回退配置保留，shell rc PATH 条目数量保持为 1。
- 已将 README 的全局安装章节前置，并明确项目级 `--simple` 安装会备份既有项目文件。
- 已通过隔离临时项目验证 `--simple`：原有 `.vscode`、`cb.py`、`cb.sh`、`cb_conf.ini` 与 `cmake/ez_custom_func.cmake` 均进入时间戳备份目录，替换文件安装成功。
