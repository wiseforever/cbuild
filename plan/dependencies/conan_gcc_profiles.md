# 按配置的编译器命名并使用 Conan profile

状态：已完成。

## 生成 profile

- `[compiler] compiler` 统一指定 GCC/Clang 工具链，按同目录、PATH 顺序配对 C/C++ 驱动；profile 生成检查两个驱动的主版本是否一致。
- `--conan-profile`（别名 `--conan-profle`）优先按 `conan.host` 命名，其次 `conan.build`，均未指定时原样使用 `[compiler] compiler` 的文件名（`gcc` → `gcc`、`gcc-9` → `gcc-9`、`clang-14` → `clang-14`；路径只取末段）。不因编译器类型或主版本改写名称。
- 名称仅允许字母、数字及 `._+-`，不符时报错并提示显式配置 build/host。名称是标签，实际版本取自配置的编译器。
- 每次生成一个 profile，直接覆盖、不备份；不同名的 build profile 保持不变。生成操作独立于依赖安装和 CMake 配置。
- `[buildenv]` 记录 CC/CXX、可定位的 binutils 和工具链 PATH；缺失工具警告并省略，前缀工具缺失时不猜填无前缀 binutils。
- 编译器版本、binutils 和 sysroot 查询复用构建子进程的临时环境。
- 编译器报告有效 sysroot 时（GCC 的 `-print-sysroot`）同时写入 SYSROOT 和 Conan sysroot 配置；不支持该查询的编译器跳过。
- `os/arch/cppstd` 由 Conan 探测，目标平台设置通过 profile 维护。
- 交叉编译需显式维护本机 build 与目标 host profile，并确认目标架构、ABI、SDK、三元组及额外选项。

## 使用 profile

- `--conan` 负责选择与校验 profile：显式 build/host 各自优先；缺省项严格使用与 `[compiler] compiler` 同名的 profile，不篡改名称、不扫描其他 profile；只配了一项时缺省项沿用该项（与生成一致）。缺省项和显式配置的 build/host 都校验“存在性 + compiler 家族/主版本”，不一致即报错并提示 `--conan-profile`。日志显示最终选择与编译器来源。
- Conan 未启用或项目没有依赖清单时不自动匹配。未配置编译器时使用 Conan 默认 profile 行为。
- 自动匹配和生成支持 GCC 与 Clang 驱动；MSVC 等其他编译器使用显式 build/host profile。
- 最终 profile 必须可加载；显式配置无效时报错。日志显示配置、脚本路径及选择来源。
- 依赖构建使用 profile 的 `[buildenv]`；本项目 CMake 显式接收配置的编译器路径。
- `-g` 只接工具链并执行 CMake 配置，不查询/记录 profile，直接使用构建目录中已有的 Conan 生成文件；`-b` 不涉及 Conan 与工具链，构建目录未配置时提示先 `-g`。改 `compiler` 或 profile 后由用户自行先执行 `--conan`。
- 环境调整仅作用于当前子进程。

## 配置解析

- `conanfile.txt` 支持无值条目，仅用等号分隔选项，包名中的冒号保留原义。
