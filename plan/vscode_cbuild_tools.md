# 自研轻量 VS Code 插件

## 操作留痕

- 确认项目当前对 Task Buttons 的依赖只体现在 `.vscode/settings.json` 的 `VsCodeTaskButtons.*` 配置和 README 描述中。
- 确认项目核心构建入口是 `cb.py` / `cb.sh`，VS Code task 只是现有编辑器入口之一。
- 确认替换方向为自研轻量 VS Code 插件。
- 确认自研插件应直接调用 `cb.py` / `cb.sh`，不依赖 `.vscode/tasks.json`。
- 确认 `PLAN.md` 只作为总说明和规划索引，具体规划放入 `plan/` 目录。
- 确认不保留固定 `deploy` 按钮，改为通过 `cbuild.targets` 支持多个自定义 target。
- 确认 Python 命令应优先使用 `python3`，没有 `python3` 时回退到 `python`。
- 确认 `cbuild.showButtons` 不配置时默认显示全部基础按钮。
- 确认终端名称只是 VS Code 终端面板里显示的名称，不作为核心配置项暴露。
- 已新增插件工程目录 `tools/cbuild-plugin-vscode/`。
- 已实现基础状态栏按钮、自定义 target、执行器选择、Python 命令探测、terminal 复用和错误提示。
- 已通过 `npm run compile`、`npm audit --audit-level=moderate` 和 `npm run package` 验证。
- 已补充插件 `.vsix` 打包和安装说明。
- 已将插件打包说明迁移到 `tools/cbuild-plugin-vscode/docs/package.md`。
- 已调整 `install.sh`，安装时不再下载 task 模板，也不再生成或覆盖 `.vscode/tasks.json`。
- 确认 `cbuild.targets` 专用于 CMake target；新增 `cbuild.commands` 支持自定义 shell 命令按钮。
- 确认插件检测到当前 workspace 缺少 `cb.py` / `cb.sh` 时，可以弹窗询问是否运行 `install.sh`，但不能静默执行。

## 结论

项目不再依赖 Task Buttons 插件，改为自研一个轻量 VS Code 插件提供状态栏按钮。

插件应直接调用 `cb.py` 或 `cb.sh`，不依赖 `.vscode/tasks.json`。这样可以避免同时维护 VS Code task 和插件按钮两套入口配置，插件只需要维护按钮到 cbuild CLI 参数的映射。

## 目标

- 去掉对第三方 Task Buttons 插件的依赖。
- 保留状态栏按钮体验。
- 保留 `conan`、`generate`、`build`、`run`、`switch`、`clean` 这些基础操作入口。
- 支持用户配置多个自定义 CMake target 操作入口，用于替代固定 `deploy` 按钮。
- 支持用户配置多个自定义 shell 命令入口。
- 支持缺少 `cb.py` / `cb.sh` 时提示用户确认并运行 bootstrap 命令。
- 插件直接调用 `cb.py` / `cb.sh`，不通过 VS Code task 间接执行。
- 不改变 `cb.py` / `cb.sh` 的命令语义。
- Python 与 Bash 两套使用方式都能支持。

## 当前状态

- `.vscode/tasks.json` 已经定义了现有 VS Code tasks。
- 仓库中仍保留 `.vscode/tasks.json`、`.vscode/tasks_python.json` 和 `.vscode/tasks_bash.json`，但 `install.sh` 不再下载 task 模板，也不再生成或覆盖目标项目的 `.vscode/tasks.json`。
- `.vscode/settings.json` 中的 `VsCodeTaskButtons.*` 配置只服务于 Task Buttons 插件。
- README 中把 Task Buttons 标为可选依赖，并描述了通过插件按钮快速执行任务。

## 插件方案

开发一个项目配套插件，例如 `cbuild-tools`。

插件激活后在 VS Code 状态栏创建按钮：

- `conan`
- `generate`
- `build`
- `run`
- `switch`
- `clean`

点击按钮时，插件在当前 workspace 根目录直接执行对应命令。

除基础按钮外，插件支持按配置生成多个自定义 target 入口。每个自定义 target 对应一次 `cb.py -b --target <name>` 或 `cb.sh -b --target <name>` 调用。

插件还支持按配置生成多个自定义命令入口。每个自定义命令会直接发送到名为 `cbuild` 的 VS Code terminal，在 workspace 根目录执行。

## 命令映射

Python 执行器，其中 `<python-command>` 来自 `cbuild.pythonCommand` 或自动探测结果：

- `conan` -> `<python-command> cb.py --conan`
- `generate` -> `<python-command> cb.py -g`
- `build` -> `<python-command> cb.py -b`
- `run` -> `<python-command> cb.py -r`
- `switch` -> `<python-command> cb.py -t`
- `clean` -> `<python-command> cb.py -c`
- 自定义 target -> `<python-command> cb.py -b --target <target>`
- 自定义命令 -> `<command>`

Bash 执行器：

- `conan` -> `bash cb.sh --conan`
- `generate` -> `bash cb.sh -g`
- `build` -> `bash cb.sh -b`
- `run` -> `bash cb.sh -r`
- `switch` -> `bash cb.sh -t`
- `clean` -> `bash cb.sh -c`
- 自定义 target -> `bash cb.sh -b --target <target>`
- 自定义命令 -> `<command>`

## 执行器选择

插件应支持配置项：

- `cbuild.executor`: `auto` / `python` / `bash`
- `cbuild.pythonCommand`: 可选；未配置时自动选择 `python3` 或 `python`
- `cbuild.bashCommand`: 默认 `bash`
- `cbuild.showButtons`: 可配置显示哪些基础按钮；不配置时默认显示全部基础按钮
- `cbuild.targets`: 自定义 target 列表
- `cbuild.commands`: 自定义 shell 命令列表
- `cbuild.bootstrapCommand`: bootstrap 命令；默认 `curl -fsSL https://github.com/wiseforever/cbuild/raw/master/install.sh | bash`

基础按钮包括：

- `conan`
- `generate`
- `build`
- `run`
- `switch`
- `clean`

`cbuild.showButtons` 不影响 `cbuild.targets` 或 `cbuild.commands`。自定义 target 是否显示由 `cbuild.targets` 决定，自定义命令是否显示由 `cbuild.commands` 决定。

插件复用一个 VS Code terminal 执行命令。该 terminal 在 VS Code 终端面板中的显示名称固定为 `cbuild`，用户通常不需要配置。

当 workspace 根目录不存在 `cb.py` 和 `cb.sh` 时，插件显示确认弹窗：`当前项目未安装 cbuild，是否运行 install.sh？`。用户选择确认后，插件才会在 `cbuild` terminal 中执行 `cbuild.bootstrapCommand`。

`cbuild.targets` 示例：

```jsonc
[
    {
        "label": "$(package)",
        "target": "deploy",
        "tooltip": "build deploy target"
    },
    {
        "label": "$(beaker)",
        "target": "test",
        "tooltip": "build test target"
    }
]
```

`cbuild.commands` 示例：

```jsonc
[
    {
        "label": "$(terminal)",
        "command": "echo hello",
        "tooltip": "run custom command"
    }
]
```

`auto` 模式规则：

1. 若用户显式配置 `cbuild.executor`，优先使用用户配置。
2. 若存在安装流程生成的版本标记，按版本标记选择。
3. 若没有版本标记但存在 `cb.py`，使用 Python。
4. 若没有 `cb.py` 但存在 `cb.sh`，使用 Bash。
5. 若两者都不存在，给出明确错误提示。

Python 命令选择规则：

1. 若用户显式配置 `cbuild.pythonCommand`，使用用户配置。
2. 否则优先探测 `python3`。
3. 若 `python3` 不可用，再探测 `python`。
4. 若两者都不可用，给出明确错误提示。

## 技术实现

使用 VS Code Extension API：

- `vscode.window.createStatusBarItem`
- `vscode.commands.registerCommand`
- `vscode.window.createTerminal`
- `vscode.workspace.getConfiguration`
- `vscode.workspace.workspaceFolders`

插件行为：

- 只在存在 workspace folder 时启用。
- 默认使用第一个 workspace folder 作为执行目录。
- 复用同一个名为 `cbuild` 的 VS Code terminal，避免每次点击都创建新终端。
- 点击按钮后显示 terminal，并发送对应命令。
- 基础按钮由插件内置命令映射生成。
- 自定义 target 按钮由 `cbuild.targets` 配置生成。
- 自定义 target 的 `target` 为空时跳过该项并给出配置提示。
- 自定义命令按钮由 `cbuild.commands` 配置生成。
- 自定义命令的 `command` 为空时跳过该项并给出配置提示。
- 缺少 `cb.py` / `cb.sh` 时弹窗询问是否运行 `install.sh`。
- 用户确认后通过 `cbuild.bootstrapCommand` 在 `cbuild` terminal 中执行 bootstrap。
- 找不到 `cb.py` / `cb.sh` 时，通过 `showErrorMessage` 给出提示。
- 插件不解析 `cb_conf.ini`，构建逻辑继续由 `cb.py` / `cb.sh` 负责。
- 插件不读取或执行 `.vscode/tasks.json`。

## 目录建议

插件源码放在独立目录：

```text
tools/cbuild-plugin-vscode/
```

当前结构：

```text
tools/cbuild-plugin-vscode/
  .gitignore
  .vscodeignore
  LICENSE
  docs/
    package.md
  package.json
  package-lock.json
  tsconfig.json
  src/
    extension.ts
  README.md
```

## 计划改动

第一阶段：准备插件源码

- [x] 新增 `tools/cbuild-plugin-vscode/`。
- [x] 创建 VS Code 插件基础工程。
- [x] 实现状态栏按钮。
- [x] 实现 `python` / `bash` / `auto` 执行器选择。
- [x] 实现按钮到 `cb.py` / `cb.sh` 参数的映射。
- [x] 实现 `cbuild.targets`，支持多个自定义 target 按钮。
- [x] 实现 `cbuild.commands`，支持多个自定义命令按钮。
- [x] 实现缺少 `cb.py` / `cb.sh` 时的 bootstrap 确认提示。
- [x] 实现 terminal 复用和错误提示。
- [x] 通过编译、审计和打包验证。

第二阶段：移除 Task Buttons 默认依赖

- 从 `.vscode/settings.json` 删除 `VsCodeTaskButtons.*` 配置。
- 从 README / README_zhCN 移除 Task Buttons 依赖项。
- README 改为说明自研插件是推荐按钮入口。
- 保留 `.vscode/tasks.json` 作为 VS Code 原生 task 兼容入口，但插件不依赖它。

第三阶段：安装与发布

- 补充插件本地开发说明。
- [x] 补充 `.vsix` 打包说明。
- 决定是否将插件发布到 VS Code Marketplace。
- 若不发布 Marketplace，则在 README 中说明如何从源码或 `.vsix` 安装。

## 打包说明位置

插件打包与安装说明放在插件源码目录下：

```text
tools/cbuild-plugin-vscode/docs/package.md
```

## 验收标准

- 未安装 Task Buttons 时，VS Code 不依赖任何 `VsCodeTaskButtons.*` 配置。
- 安装自研插件后，状态栏显示 cbuild 操作按钮。
- 点击按钮会在 workspace 根目录执行对应 `cb.py` 或 `cb.sh` 命令。
- 固定 `deploy` 按钮不再作为默认按钮出现。
- 用户可以通过 `cbuild.targets` 配置多个自定义 target 入口。
- 用户可以通过 `cbuild.commands` 配置多个自定义 shell 命令入口。
- 缺少 `cb.py` / `cb.sh` 时，插件会提示用户确认是否运行 `install.sh`，不会静默执行。
- `python`、`bash`、`auto` 三种执行器模式可用。
- 找不到 `cb.py` / `cb.sh` 时有明确错误提示。
- 插件不依赖 `.vscode/tasks.json`。
- README 不再把 Task Buttons 表述为依赖。

## 风险

- 自研插件需要维护 VS Code API 兼容性。
- 插件需要处理 Python / Bash 版本选择和跨平台 shell 差异。
- 如果未来 `cb.py` / `cb.sh` 参数发生变化，插件命令映射也要同步更新。
- 若插件不发布 Marketplace，用户安装步骤会比普通 VS Code 插件更繁琐。
