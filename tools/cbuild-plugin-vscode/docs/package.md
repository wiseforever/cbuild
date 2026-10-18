# 打包说明

## 前置条件

- 已安装 Node.js。
- 已安装 npm。
- 已安装 VS Code 命令行工具 `code`，仅命令行安装 `.vsix` 时需要。
- 本仓库尚未发布 Marketplace 版本，当前通过本地 VSIX 安装。

## 生成 VSIX

从仓库根目录进入插件目录：

```sh
cd tools/cbuild-plugin-vscode
```

首次打包前安装依赖：

```sh
npm ci --ignore-scripts
```

编译、测试并生成 VSIX：

```sh
npm test
npm run package
```

打包产物版本由 `package.json` 的 `version` 决定，应与 `cb.sh` / `cb.py` 的 `CBUILD_VERSION` 一致：

```text
tools/cbuild-plugin-vscode/cbuild-plugin-vscode-0.1.0.vsix
```

可在仓库根目录执行 `tools/check_version.sh` 检查所有版本来源。

## 安装 VSIX

从仓库根目录执行：

```sh
code --install-extension tools/cbuild-plugin-vscode/cbuild-plugin-vscode-0.1.0.vsix
```

也可以在 VS Code 扩展面板中选择 `Install from VSIX...`，然后选择生成的 `.vsix` 文件。

## 与 master 分支的关系

插件内置的默认安装命令从所选源的 `master/install.sh` 启动，再由 `master/LATEST` 解析 tag；不使用 GitHub API 或 Release 附件。显式版本则直接读取对应 tag 的 `install.sh`。

正式 tag、`master` 和 VSIX 的发布步骤见仓库根目录的 [RELEASING.md](../../../RELEASING.md)。Release 附件是可选的发布说明材料，不是默认安装入口。

在对应 `vX.Y.Z` tag 推送前，默认全局安装无法完成下载；此时应使用本地 VSIX、显式 tag，或配置 `cbuild.bootstrapCommands` 指向内部安装源。

## 验证

安装后打开包含 `cb.conf` 的 cbuild workspace，确认 VS Code 状态栏出现 cbuild 操作按钮。真实 VS Code 交互和 Windows/macOS shell 仍需人工验证。
