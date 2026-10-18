# PLAN

## 说明

本文件作为项目规划索引和关键进展入口，优先展示未完成事项。

需要持续跟踪的具体方案放在 `plan/` 目录下；新建门槛及记录规则见 [AGENTS.md](AGENTS.md#规划记录)。小改动不单独建规划，主题文件不强制套用完整模板。

## 未完成事项

- **进行中：VS Code 插件文档与发布收尾（核心功能已完成）。** PATH 优先、备用目录兜底、全局初始化及项目配置入口均已实现并通过自动化验证；剩余工作是迁移中英文 README 的 Task Buttons 说明、补充本地调试/开发宿主加载流程，以及确定发布方式。详见[插件规划](plan/vscode_cbuild_tools.md)。

## 规划索引

| 主题 | 状态 |
| --- | --- |
| [自研轻量 VS Code 插件（核心已完成，文档/发布收尾）](plan/vscode_cbuild_tools.md) | 进行中 |
| [构建类型配置写入兼容性](plan/build_type_config_write.md) | 待验证 |
| [清理安全与构建工作流缺陷修复（问题表、方案及复审）](plan/safety_and_workflow_fixes.md) | 已完成 |
| [Conan 与 vcpkg 组合工具链](plan/conan_vcpkg_toolchain.md) | 已完成 |
| [CMake 自定义宏与插件终端行为](plan/cmake_defines_and_plugin_terminals.md) | 已完成 |
| [CMake 可执行文件输出路径解析](plan/cmake_output_path_resolution.md) | 已完成 |
| [全局安装与配置路径解析](plan/global_install_config_paths.md) | 已完成 |
| [命令行构建类型参数](plan/command_build_type_arguments.md) | 已完成 |
| [构建目标参数](plan/build_target_arguments.md) | 已完成 |
| [安装脚本的全局与 VS Code 模板模式](plan/install_script_global_and_vscode.md) | 已完成 |

状态按各主题已有的实施及验证记录维护：“待开始”表示尚未实施；“进行中”表示仍有实施工作；“待验证”表示实现已完成但仍有验证未闭环；“已完成”表示该主题范围内的实施及验证已完成，不代表所有平台均已验证。提交审批不作为实施状态。

主题收尾后从“未完成事项”移除，保留索引和主题文件中的关键结论。
