# PLAN

## 说明

本文件作为项目操作留痕与规划索引使用。

具体规划、执行步骤、验收标准和风险记录统一放在 `plan/` 目录下，避免 `PLAN.md` 变成单个方案的详细设计文档。

## 留痕规则

- 新的规划放在 `plan/` 目录下，每个主题一个 Markdown 文件。
- `PLAN.md` 只记录总体说明、规划索引和关键状态。
- 不在规划文件中强制加入日期。
- 已实施的关键操作应回写到对应主题文件中，保留操作痕迹。
- 具体实现完成并经用户 review / approval 后，再按仓库要求创建 git commit。

## 规划索引

- [自研轻量 VS Code 插件](plan/vscode_cbuild_tools.md)
- [Conan 与 vcpkg 组合工具链](plan/conan_vcpkg_toolchain.md)

## 当前关键状态

- Task Buttons 替换方向已确定为自研轻量 VS Code 插件。
- 插件规划放在 `plan/vscode_cbuild_tools.md`。
- 插件应直接调用 `cb.py` / `cb.sh`，不依赖 `.vscode/tasks.json`。
