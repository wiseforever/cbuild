# Release 与 tag 版本化安装

状态：核心 0.3.0 准备发布，尚未发布；本地 `LATEST` 已指向 `v0.3.0`。

## 安装与版本规则

- 所有安装模式默认 `--release latest`，从所选源 `master/LATEST` 读取 tag；显式 `--release vX.Y.Z` 直接使用对应 tag。
- 构建脚本、更新器、配置及 VS Code 模板从同一个 tag 下载。
- `--source github|gitee` 同时决定版本指针和文件来源；文件缺失直接报错，不跨源补取。
- `--base-url` 必须包含 `{tag}`，并配合显式版本使用。
- 下载到暂存目录，校验脚本版本和必需文件后再备份、替换目标。
- 安装目录记录版本、变体和来源；`cb_install.sh` 默认沿用自身目录及变体，版本默认 latest，显式参数优先。
- `cb.sh` / `cb.py` 的核心版本保持一致；`LATEST` 记录核心发布 tag。插件 package.json/package-lock.json 由 npm 独立维护，不要求与核心同版。当前核心版本为 0.3.0，尚未发布。

## 插件与卸载

- 插件 `cbuild.installRelease` 选择核心版本而非插件版本，默认 latest，作用于内置全局安装及 `--config` / `--vscode` 命令。
- 自定义初始化命令由用户维护，PATH 查找顺序独立于安装版本设置。
- `install.sh` / `cb_install.sh --uninstall [--prefix] [--yes]` 统一执行卸载。
- 非交互卸载要求 `--yes`，拒绝根目录、主目录和源码仓库。
- 同一安装目录的安装、更新需串行执行。

## 发布流程

- 先向 GitHub 和 Gitee 推送不可变 tag，再推送更新 `LATEST` 的 master；两个源的代码与版本指针保持一致。
- 安装使用 tag 文件，不依赖 GitHub API 或 Release 附件。
- 具体流程见 [RELEASING.md](../../RELEASING.md)。

## 剩余事项

- 本次 Conan profile 与 `-g`/`-b` 职责调整纳入 `v0.3.0`；发布时先推送 tag，再推送更新 `LATEST` 的 master。
