# 自研轻量 VS Code 插件

状态：核心功能已完成，剩余项目 README 推荐入口说明、本地调试说明及发布方式决策。

## 脚本与执行器

- 自动模式顺序：PATH `cb.sh` → PATH `cb.py` → 备用目录 `cb.sh` → 备用目录 `cb.py`。
- 备用目录默认 `~/.cbuild`；机器级设置 `cbuild.installDirectory` 同时控制备用目录及内置安装的 `--prefix`。
- 显式 Bash/Python 模式只查指定变体，仍按 PATH、备用目录的顺序查找。
- POSIX 使用 `command -v` 并检查文件及执行权限；Windows 使用 `where $PATH:<文件名>` 限定 PATH 搜索。
- Python 执行器优先 `python3`，其次 `python`；可通过 `cbuild.pythonCommand` / `cbuild.bashCommand` 覆盖。
- 第一个 workspace folder 作为项目；项目配置由核心脚本读取。`run` 使用独立终端，其余操作复用 `cbuild` 终端。
- 项目模板和配置安装使用显式目标目录；构建操作受专用终端当前目录影响。

## 安装命令

| 命令 ID | 行为 |
| --- | --- |
| `cbuild.bootstrapProject` | 安装或更新全局 cbuild，选择源后先展示 Bash，再展示 Python。 |
| `cbuild.installVscode` | 调用 `cb_install.sh --vscode <project-root>` 安装 VS Code 模板。 |
| `cbuild.installConfig` | 调用 `cb_install.sh --config <project-root>` 安装项目配置。 |

- 命令面板和资源管理器右键菜单提供上述入口，安装前要求确认。
- `cbuild.installRelease` 默认 `latest`，内置源通过 `master/LATEST` 或固定 tag 选择版本，项目配置入口同样传递 `--release`。
- GitHub/Gitee 内置安装命令显式指定 `--global --bash` / `--global --python` 和安装目录。
- 自定义源通过 `command` / `bashCommand` 提供安装命令，负责指定版本及全局安装目标。
- 安装器同样按 PATH、备用目录顺序查找。替换项目 `.vscode` / `cb.conf` 前备份到 `cbuild_bak`。
- 同目录安装应串行执行，详见[并发安装限制](../workflow/safety_and_workflow_fixes.md#并发安装限制)。

## 按钮与设置

- 插件直接调用 cbuild CLI，构建逻辑由 `cb.sh` / `cb.py` 负责。
- 基础按钮包括 Conan、generate、build、run、构建类型切换和 clean。
- `cbuild.targets` 配置自定义 CMake target；`cbuild.commands` 配置自定义 shell 命令。
- `cbuild.showButtons` 未配置或为空时展示全部基础按钮。
- 安装器提供项目配置和 VS Code 模板；仓库 task 文件可供原生 Tasks 手动参考。

## 剩余工作

- [ ] 在中英文项目 README 中完善自研插件推荐入口。
- [ ] 补充本地调试和 Extension Development Host 加载说明。
- [ ] 确定 Marketplace 发布方式，或提供明确的源码/VSIX 安装路径。
