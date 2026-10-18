# 自研轻量 VS Code 插件

状态：核心功能已完成，主题仍进行中，仅剩文档与发布收尾。本轮全局脚本模式与项目配置入口已实现并通过自动化验证；剩余项是中英文项目 README 的推荐入口迁移、本地调试/开发宿主加载说明，以及发布方式决策。

## 本轮方案：全局脚本与项目配置分离

用户明确要求：调用全局 `cb.sh` / `cb.py`，优先 `cb.sh`；插件初始化安装全局版本；提供 `--vscode` / `--config` 入口方便配置项目。

### 脚本与执行器

- 先查扩展宿主环境的 PATH；未找到可用脚本时才查备用目录，默认 `~/.cbuild`，机器级配置 `cbuild.installDirectory` 可修改备用目录及内置安装的 `--prefix` 目标。
- 自动模式顺序：PATH `cb.sh` → PATH `cb.py` → 备用目录 `cb.sh` → 备用目录 `cb.py`。因此 PATH 的 Python 优先于备用目录的 Bash。
- 显式 `bash` / `python` 只查指定变体，仍先 PATH 后备用目录；配置备用目录不能覆盖 PATH 中的可用脚本。
- POSIX 通过 `command -v` 并检查文件及可执行权限，Windows 通过 `where $PATH:<文件名>` 只查 PATH，避免当前目录隐式遮蔽；将解析到的路径传给解释器。没有额外的项目根目录查找，但用户显式放入 PATH 的项目目录会参与环境查找。
- 保留 Python 命令优先 `python3`、其次 `python`，以及 `cbuild.pythonCommand` / `cbuild.bashCommand` 覆盖。
- 第一个 workspace folder 仍作为项目；新终端在那里启动，项目里的 `cb.conf` 仍由核心脚本加载。
- `run` 使用独立终端；其余操作复用 `cbuild` 终端。手动改变专用终端目录后，构建操作会受当前目录影响；项目模板/配置安装使用显式目标目录，不依赖终端 cwd。

### 命令入口

| 命令 ID | 界面标题 / 行为 |
| --- | --- |
| `cbuild.bootstrapProject` | Install / Update Global cbuild；保留原 ID 兼容已有快捷键，选择源后先展示 Bash，再展示 Python。 |
| `cbuild.installVscode` | Install VS Code Templates (--vscode)；调用全局 `cb_install.sh --vscode <project-root>`。 |
| `cbuild.installConfig` | Install Project Config (--config)；调用全局 `cb_install.sh --config <project-root>`。 |

- 三个入口均提供命令面板与资源管理器右键菜单项。
- 新增 `cbuild.installRelease`（默认 `latest`）：内置全局初始化从所选源的 `master/install.sh` 或固定 tag 的安装器启动，并把 `--release` 传给安装器；`--config` / `--vscode` 同样显式传递版本。非法值在任何命令执行前拒绝。
- 自定义安装源的 `command` / `bashCommand` 保持原样，用户需确保命令是版本化全局安装。
- 内置 GitHub/Gitee 安装命令显式传入 `--global --bash` / `--global --python`，并附带匹配 `cbuild.installDirectory` 的 `--prefix`。
- 自定义安装源的 `command` / `bashCommand` 保持原样，用户需确保命令全局安装到配置目录。
- 项目配置入口先查 PATH 中的 `cb_install.sh`，没有才查备用目录；复用安装器的下载及备份行为，执行前说明 `.vscode` / `cb.conf` 会先备份到 `cbuild_bak`。
- 所有安装操作都要求用户确认，不在启动时静默执行。
- 缺少脚本或安装器时，给出期望位置与全局安装/目录配置提示，不隐式复制项目脚本。

### 实施与验证

- [x] 切换全局脚本发现与 Bash 优先策略。
- [x] 内置初始化改为全局安装，并支持与运行相同的自定义安装目录。
- [x] 新增 `--vscode` / `--config` 命令、菜单与确认提示。
- [x] 增加 `cbuild.installRelease`，内置安装命令改为 master/LATEST 与 tag 版本化，项目配置入口传递 `--release`。
- [x] 更新插件 README、配置描述、激活条件和模拟 API 测试。
- [x] 完成 TypeScript 编译、56 项插件回归、34 个脚本测试方法及 VSIX 打包验证；Bash/Python 语法与 `git diff --check` 通过。

复审已修复 Windows 裸 `where` 额外搜索当前目录的问题；新增 10 项模拟回归，覆盖脚本/安装器遮蔽、兜底与显式加入 PATH 的项目目录。用户决定本轮不增加并发安装锁，仅将同目录并发更新风险记为已知限制，不作为待实施任务，见[复审记录](safety_and_workflow_fixes.md#复审追加问题)。

插件回归覆盖 PATH 与备用目录的分级顺序、四组内置安装选择、master/LATEST 与 tag 版本命令、非法版本拒绝、Bash/Python 策略、项目安装入口、确认/取消和缺失依赖；额外使用真实临时 POSIX PATH 验证可执行文件查找及不可执行文件触发回退（不执行脚本）；脚本集成验证全局安装器只备份及替换所选项目配置，目标路径含空格时也正常。

验证重点：全局两种脚本同时存在时的优先级、Python 回退、显式执行器、拒绝项目脚本回退、自定义目录、目录/文件区分、安装前确认、项目目标参数、Windows 风格路径及缺失依赖提示。真实 VS Code 交互与 Windows/macOS 环境需要后续手动测试。

## 已有功能与关键决策

- 自研插件直接调用 cbuild CLI，不读取或执行 `.vscode/tasks.json`，不依赖 Task Buttons。
- 基础按钮：Conan、generate、build、run、Debug/Release switch、clean。
- `cbuild.targets` 专用于自定义 CMake target；`cbuild.commands` 用于自定义 shell 命令。
- `cbuild.showButtons` 不配置或为空时展示全部基础按钮。
- 插件不解析 `cb.conf`，构建逻辑由 `cb.sh` / `cb.py` 负责。
- 已实现 terminal 复用、错误提示、GitHub/Gitee 安装源选择、自定义源和安装确认。
- 已有 VSIX 打包与安装说明：`tools/cbuild-plugin-vscode/docs/package.md`。
- `install.sh` 不再安装 task 模板；仓库保留现有 task 文件作为 VS Code 原生 Tasks 的手动参考。

## 方案演进记录

- 初版只调用项目根目录脚本，自动模式优先 Python。
- [七项缺陷修复](safety_and_workflow_fixes.md)首先通过显式项目级安装解决初始化与查找方式不一致；该问题表继续保留。
- 本轮按用户新要求改为全局脚本、Bash 优先、全局初始化，项目只单独安装配置和可选 VS Code 模板，替代上一步的项目级初始化方案。
- 随后按用户澄清，将“固定目录优先”修正为“环境 PATH 优先、`~/.cbuild` 或配置目录兜底”；安装器 `cb_install.sh` 采用同样策略。

## 尚未完成的迁移与发布工作

- [ ] 中英文项目 README 移除 Task Buttons 推荐，改为自研插件入口。
- [ ] 补充插件本地调试及 Extension Development Host 加载流程；插件 README 已有依赖安装、编译和测试命令，`docs/package.md` 已有 VSIX 打包/安装说明。
- [ ] 确定是否发布 VS Code Marketplace；若不发布，在项目 README 中补充源码/VSIX 安装路径。

`.vscode/settings.json` 已移除 `VsCodeTaskButtons.*`，以上剩余工作不阻塞插件核心功能。

## 验证入口

- 插件：`cd tools/cbuild-plugin-vscode && npm test && npm run package`。
- 脚本：`python3 -m unittest discover -s tests -v`。
- 完整测试说明：[tests/README.md](../tests/README.md)。
