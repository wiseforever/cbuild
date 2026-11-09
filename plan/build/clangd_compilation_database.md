# clangd 编译数据库

状态：已完成。

## 关键决策

- Bash/Python 直接按 YAML 层级维护项目根目录 `.clangd` 的 `CompileFlags.CompilationDatabase`，不依赖自定义标记，也不再修改 `.vscode/settings.json`。
- 常规单文档块式配置中，字段存在时原位更新，缺字段时补到已有 `CompileFlags`，缺少该块时在文件开头补充。保留其他配置、注释和原有缩进；只在输出成功后替换文件。
- 不新增 YAML 解析器依赖。多文档、顶层 `If`、重复目标及无法安全识别的复杂格式会警告并保留原文件，由开发者手动维护。
- 编译数据库在项目内时使用相对 `.clangd` 的目录，项目外使用绝对目录，不使用 `${workspaceFolder}`。
- 脚本内置默认配置，缺少 `.clangd` 时生成的文件使用 2 空格缩进；新增块或无法推断已有块缩进时也使用 2 空格，不统一修改已有文件的缩进；`CompileFlags` 位于最前面；随后设置 `Completion.AllScopes: false` 和 `Completion.HeaderInsertion: Never`，并注明可选值。已有文件（包括空文件）不补写这些默认值，用户可自由修改或删除。
- 项目 `.clangd` 缺失时由构建脚本创建，已存在配置由用户自行维护；安装器所有模式均不下载、替换或备份该文件。仓库不再携带根 `.clangd` 模板。
- VS Code 保留已迁移参数的注释，不再启用这些参数；不兼容旧 `--compile-commands-dir` 写法，由用户自行删除生效参数，不提供自动迁移。
