# 项目规划

本目录仅记录方案、实施进展、关键决策和剩余事项；维护规则见 [AGENTS.md](../AGENTS.md#规划记录)。

## 未完成事项

- **版本化安装：核心 0.2.1 准备发布，尚未发布。** 本地 `LATEST` 已指向 `v0.2.1`；待提交准备改动并创建 `v0.2.1` tag 后，先推送 tag，最后推进两个远端的 `master`。见[版本化安装](install/release_versioned_install.md)。
- **VS Code 插件：文档与发布收尾。** 核心功能已完成；剩余中英文 README 推荐入口说明、本地调试说明及发布方式决策。见[插件规划](vscode/vscode_cbuild_tools.md)。

## 主题索引

| 分类 | 主题 | 状态 |
| --- | --- | --- |
| 安装发布 | [master/LATEST 与 tag 版本化安装](install/release_versioned_install.md) | 待发布 |
| VS Code | [自研轻量 VS Code 插件](vscode/vscode_cbuild_tools.md) | 进行中 |
| 构建 | [clangd 编译数据库](build/clangd_compilation_database.md) | 已完成 |
| 构建 | [编译器与构建类型配置](build/build_type_config_write.md) | 已完成 |
| 构建 | [命令行构建类型](build/command_build_type_arguments.md) | 已完成 |
| 构建 | [构建目标参数](build/build_target_arguments.md) | 已完成 |
| 构建 | [CMake 输出路径解析](build/cmake_output_path_resolution.md) | 已完成 |
| 构建 | [CMake 自定义宏与插件终端](build/cmake_defines_and_plugin_terminals.md) | 已完成 |
| 依赖 | [按编译器匹配 Conan GCC profile](dependencies/conan_gcc_profiles.md) | 已完成 |
| 依赖 | [Conan 与 vcpkg 组合工具链](dependencies/conan_vcpkg_toolchain.md) | 已完成 |
| 安装发布 | [全局安装与配置路径](install/global_install_config_paths.md) | 已完成 |
| 安装发布 | [安装脚本全局与模板模式](install/install_script_global_and_vscode.md) | 已完成 |
| 工作流 | [清理安全与构建工作流](workflow/safety_and_workflow_fixes.md) | 已完成 |
