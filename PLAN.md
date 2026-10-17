# PLAN

## 说明

本文件作为项目规划索引和关键进展入口，优先展示未完成事项。

需要持续跟踪的具体方案放在 `plan/` 目录下；新建门槛及记录规则见 [AGENTS.md](AGENTS.md#规划记录)。小改动不单独建规划，主题文件不强制套用完整模板。

## 未完成事项

- **进行中：VS Code 插件迁移。** 插件核心已实现；仍需将中英文 README 的 Task Buttons 说明迁移到自研插件、补充本地开发说明，并确定是否发布 Marketplace。详见[插件规划](plan/vscode_cbuild_tools.md)。

## 规划索引

| 主题 | 状态 |
| --- | --- |
| [自研轻量 VS Code 插件](plan/vscode_cbuild_tools.md) | 进行中 |
| [构建类型配置写入兼容性](plan/build_type_config_write.md) | 待验证 |
| [Conan 与 vcpkg 组合工具链](plan/conan_vcpkg_toolchain.md) | 已完成 |
| [CMake 自定义宏与插件终端行为](plan/cmake_defines_and_plugin_terminals.md) | 已完成 |
| [CMake 可执行文件输出路径解析](plan/cmake_output_path_resolution.md) | 已完成 |
| [全局安装与配置路径解析](plan/global_install_config_paths.md) | 已完成 |
| [命令行构建类型参数](plan/command_build_type_arguments.md) | 已完成 |
| [构建目标参数](plan/build_target_arguments.md) | 已完成 |
| [安装脚本的全局与 VS Code 模板模式](plan/install_script_global_and_vscode.md) | 已完成 |

状态按各主题已有的实施及验证记录维护：“待开始”表示尚未实施；“进行中”表示仍有实施工作；“待验证”表示实现已完成但仍有验证未闭环；“已完成”表示该主题范围内的实施及验证已完成，不代表所有平台均已验证。提交审批不作为实施状态。

主题收尾后从“未完成事项”移除，保留索引和主题文件中的关键结论。
