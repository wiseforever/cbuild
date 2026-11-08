# 按编译器匹配 Conan GCC profile

状态：已完成。

## 生成 profile

- `[compiler] compiler` 统一指定 GCC/Clang 工具链，按同目录、PATH 顺序配对 C/C++ 驱动；GCC profile 生成检查两个驱动的主版本。
- `--conan-profile`（别名 `--conan-profle`）优先按 `conan.host` 命名，其次 `conan.build`，均未指定时用 `gcc-<主版本>`。
- 名称仅允许 gcc 开头的字母、数字及 `._+-`。名称是标签，实际版本取自配置的编译器。
- 每次生成一个 profile，直接覆盖、不备份；不同名的 build profile 保持不变。生成操作独立于依赖安装和 CMake 配置。
- `[buildenv]` 记录 CC/CXX、可定位的 binutils 和工具链 PATH；缺失工具警告并省略，前缀工具缺失时不猜填无前缀 binutils。
- 编译器版本、binutils 和 sysroot 查询复用构建子进程的临时环境。
- 有效的 GCC sysroot 同时写入 SYSROOT 和 Conan sysroot 配置。
- `os/arch/cppstd` 由 Conan 探测，目标平台设置通过 profile 维护。
- 交叉编译需显式维护本机 build 与目标 host profile，并确认目标架构、ABI、SDK、三元组及额外选项。

## 使用 profile

- `--conan`、`-g` 共用选择规则：显式 build/host 各自优先；缺省项匹配名称以 gcc 开头、实际编译器为 GCC 且主版本一致的 profile，优先 `gcc-<主版本>`。
- Conan 未启用或项目没有依赖清单时不自动匹配。未配置编译器时使用 Conan 默认 profile 行为。
- 自动匹配和生成仅支持 GCC；其他编译器使用显式 build/host profile。
- 最终 profile 必须可加载；显式配置无效时报错。日志显示配置、脚本路径及选择来源。
- 依赖构建使用 profile 的 `[buildenv]`；本项目 CMake 显式接收配置的编译器路径。
- 修改 profile 后先执行 `--conan`，再执行 `-g`。缺少依赖安装记录或选择记录不一致时提示安装依赖。
- 环境调整仅作用于当前子进程。

## 配置解析

- `conanfile.txt` 支持无值条目，仅用等号分隔选项，包名中的冒号保留原义。
