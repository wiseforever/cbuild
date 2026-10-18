# Release 与 tag 版本化安装

状态：实现与本地验证完成，待首次实际发布验证。

## 实现结果

- `install.sh` 增加 `--release <latest|vX.Y.Z[-pre]>`、`--source github|gitee`、`--base-url`（必须含 `{tag}`）；卸载逻辑并入安装器，支持 `--uninstall [--prefix] [--yes]`，不再提供安装器 `--version`。
- 全局/项目安装先下载脚本并校验其 `CBUILD_VERSION` 与 tag 一致，再备份/替换目标文件；全局安装额外记录版本、变体和来源。
- 已安装 `cb_install.sh` 默认保留自身目录和变体；`cb.sh` / `cb.py` / 兼容包装 `cb_uninstall.sh` 支持 `--version`，不依赖项目配置。
- 插件新增 `cbuild.installRelease`（默认 `latest`），内置安装命令从所选源的 `master/install.sh` 或固定 tag 获取安装器，并为项目模板/配置传入 `--release`。
- 新增 `LATEST`、`tools/check_version.sh` 和 `RELEASING.md`；latest 直接使用所选源 `master/LATEST`，不引入额外指针分支。
- 卸载逻辑并入安装器，`cb_uninstall.sh` 变为兼容包装；非交互卸载要求 `--yes`，并拒绝根目录、主目录和源码仓库。
- 未加入并发安装锁；该限制继续保留在 README 和复审记录中。

## 确定的规则

- 所有安装模式默认 `--release latest`，直接使用所选源 `master/LATEST` 中的 tag；显式 `--release vX.Y.Z` 跳过该文件。
- 不调用 GitHub API，不使用 GitHub Release 附件，也不回退到 `master`。latest 入口和版本解析都不依赖 GitHub。
- 构建脚本、更新器、兼容卸载包装、配置和 VS Code 模板从同一个 tag 下载，不自动降级到其它版本。
- `--source github|gitee` 同时决定 `LATEST` 与 tag 文件来源；所选源是唯一来源，文件缺失直接报错，不跨源补取。
- `--base-url` 是包含 `{tag}` 的 URL 模板，必须配合显式 `--release`，避免自定义源解析 latest。
- 下载到暂存目录并校验脚本版本、必需文件后，才备份/替换项目文件。兼容卸载包装可选下载，缺失时安装器仍可直接卸载。
- 安装目录记录版本、变体和来源。已安装 `cb_install.sh` 默认沿用自身目录和安装变体，但版本仍默认 latest；显式参数优先。
- 插件安装版本设置（默认 latest）作用于内置全局初始化、`--config` 和 `--vscode`；不改变 PATH 查找顺序，不改写自定义初始化命令。
- `cb.sh` / `cb.py` 的 `CBUILD_VERSION`、插件 package.json/package-lock.json 与 `LATEST` 指向的 tag 保持一致；当前以已有插件 0.1.0 建立版本基线，不创建 tag 或公开 Release。

## 发布流程

- 发布前在本地运行版本一致性检查、脚本/插件测试，并按需构建 VSIX。
- 推送 `v*` tag 到 GitHub 和 Gitee 后，再推送包含新 `LATEST` 和 `install.sh` 的 `master` 到两个远端；两个镜像内容必须一致。
- tag 不覆盖；必须先推送 tag，再推进远端 `master/LATEST`。对应 tag 不存在时默认安装会失败，必须显式指定 tag。
- 保留已知的同目录并发安装限制，不加入锁，不宣称完整文件系统事务或签名验证。

## 验收

- [x] latest 只读取一次 `LATEST`；指定 tag 不读取；`LATEST` 缺失、非法、tag 不匹配、脚本版本不符、缺文件均失败且不破坏旧文件。
- [x] 默认及指定版本覆盖全局、simple、config、vscode、format；master/LATEST 单次读取、Gitee 独立、LATEST 失败不借源、自定义源需显式版本、已有更新器目录/变体保持、版本查询不依赖项目配置。
- [x] 插件默认/指定版本命令及原 PATH 回归均通过；插件 56 项、脚本 34 个测试方法通过。
- [x] 卸载由安装器执行，兼容包装可用；非交互 `--yes`、危险目录拒绝、缺少包装仍可卸载均有回归。
- [x] Bash/Python 语法、版本检查、TypeScript 编译、VSIX 打包和 diff 检查。
- [ ] 首次推送 tag 与 `master` 后验证两个源的 `master/LATEST`、`master/install.sh` 入口及安装结果；尚未实际发布。
- [x] 未创建提交，未推送 tag，未实际发布 Release。
