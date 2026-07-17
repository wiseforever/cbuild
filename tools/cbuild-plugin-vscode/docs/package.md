# 打包说明

## 前置条件

- 已安装 Node.js。
- 已安装 npm。
- 已安装 VS Code 命令行工具 `code`，仅命令行安装 `.vsix` 时需要。

## 生成 VSIX

从仓库根目录进入插件目录：

```sh
cd tools/cbuild-plugin-vscode
```

首次打包前安装依赖：

```sh
npm install
```

编译并检查依赖审计：

```sh
npm run compile
npm audit --audit-level=moderate
```

生成本地 `.vsix` 安装包：

```sh
npm run package
```

打包完成后会在插件目录生成：

```text
tools/cbuild-plugin-vscode/cbuild-plugin-vscode-0.1.0.vsix
```

## 安装 VSIX

从仓库根目录执行：

```sh
code --install-extension tools/cbuild-plugin-vscode/cbuild-plugin-vscode-0.1.0.vsix
```

也可以在 VS Code 扩展面板中选择 `Install from VSIX...`，然后选择生成的 `.vsix` 文件。

## 验证

安装后打开包含 `cb.py` 或 `cb.sh` 的 cbuild workspace，确认 VS Code 状态栏出现 cbuild 操作按钮。
