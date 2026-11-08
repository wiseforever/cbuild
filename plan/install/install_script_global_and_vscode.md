# 安装脚本的全局与 VS Code 模板模式

状态：已完成。

## 关键决策

- 默认全局安装 Bash，保留 `--simple` 项目级安装及 `--python` 变体切换；中英文安装说明按 GitHub/Gitee 下载源分组。
- 当前 PATH 或 shell rc 已包含安装目录时，不重复添加 PATH 条目。
- 全局更新先暂存必需下载，准备成功后才替换并删除另一变体；可选卸载包装下载失败时保留当前副本，手动回退配置不覆盖。
- 全局更新器名为 `cb_install.sh`；`.install.cfg` 作为全局安装标记，并保留版本、变体及来源。
- `--vscode [目录]` 仅安装四个 VS Code 模板；`--config [目录]`（别名 `--conf`）仅安装 `cb.conf`，默认目标为当前目录。
- 项目级 `--simple` 和独立模板/配置安装在替换前备份对应目标到 `cbuild_bak`。
- 所有模式默认从所选源 `master/LATEST` 解析版本，也可用 `--release vX.Y.Z` 固定 tag，详见[版本化安装](release_versioned_install.md)。

## 已知限制

- 同一安装目录不支持并发安装/更新，尤其 Bash/Python 变体可能互相删除；应等待前一次操作结束再启动下一次。
- 详见[并发安装限制](../workflow/safety_and_workflow_fixes.md#并发安装限制)。
