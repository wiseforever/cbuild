# 回归测试

## 构建与安装脚本

在仓库根目录运行：

```bash
python3 -m unittest discover -s tests -v
```

依赖 Python 3、Bash、CMake、Ninja、gcc/g++；本轮在 Linux 上验证。缺少构建工具时，构建相关测试会跳过；安装器测试只要求 Bash。

覆盖范围：

- Python/Bash 两个入口在 Ninja、Unix Makefiles 下构建、列出并运行 C/C++ 程序。
- 无可执行程序、程序尚未构建时，库和自定义 target 仍能成功；真实构建失败和无程序可运行仍返回失败。
- VS Code 配置更新触发目录初始化后，后续构建类型变化仍使用正确目录。
- 清理拒绝删除源码目录、祖先目录及其符号链接别名，允许删除正常构建目录。
- 全局更新下载失败保留旧安装；成功切换变体不丢失用户配置；可选卸载脚本下载失败保留旧副本。
- 项目级安装显式选择 Python/Bash 版本；全局安装器的 `--vscode` / `--config` 显式指定项目目标，只替换并备份请求的文件，不向项目复制构建脚本。

所有清理和安装都在一次性临时目录中执行。下载器使用本地模拟，不访问网络，也不修改真实 HOME 或全局安装；自更新测试只执行临时安装目录中的更新器。

## VS Code 插件

```bash
cd tools/cbuild-plugin-vscode
npm ci --ignore-scripts
npm test
```

插件测试使用 Node.js 内置测试运行器，先编译 TypeScript，再模拟 VS Code API。覆盖 PATH 优先与备用目录兜底、GitHub/Gitee 的全局安装命令、每级 Bash 优先、显式执行器、自定义备用目录、Windows 风格路径、项目模板/配置命令、缺失依赖与取消流程；安装器同样优先从 PATH 查找。Windows 模拟包含裸 `where` 的当前目录优先行为，确认实际查询限定为 `$PATH:<文件名>`，不误用当前目录脚本；用户显式把项目目录放入 PATH 的行为仍保留。另用隔离的真实临时 POSIX PATH 验证可执行脚本发现及不可执行文件回退，只运行查找命令，不执行脚本。不会打开真实终端或执行安装命令；Windows 路径测试为模拟，不代表真实 Windows shell 已验证。

问题表、解决方案与验证结论见 [修复记录](../plan/safety_and_workflow_fixes.md)。
