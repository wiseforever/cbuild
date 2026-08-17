#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_FILE_CWD="$PWD/cb_conf.ini"
CONFIG_FILE="$CONFIG_FILE_CWD"
if [[ ! -f "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$SCRIPT_DIR/cb_conf.ini"
fi

VALID_BUILD_TYPES=("Debug" "Release")

BUILD_TYPE="Release"
SOURCE_DIR="."
GENERATOR="Ninja"
PARALLEL_JOBS_RAW="auto"

C_COMPILER=""
CXX_COMPILER=""
CONFIG_C_COMPILER=""
CONFIG_CXX_COMPILER=""
CONAN_ENABLE="false"
CONAN_BUILD=""
CONAN_HOST=""
ENV_VCPKG_ROOT="${VCPKG_ROOT:-}"
VCPKG_ENABLE="false"
VCPKG_ROOT=""
VCPKG_TOOLCHAIN_FILE=""
VCPKG_TRIPLET=""
CBUILD_CUSTOM_TOOLCHAIN_FILE=""

MSVC_ENABLE="false"
MSVC_ENV_SCRIPT=""
HOST_ARCH="x64"
MSVC_CONAN_ENABLE="false"
MSVC_CONAN_BUILD=""
MSVC_CONAN_HOST=""

BUILD_DIR=""
COMPILER_TYPE="unknown"
CMAKE_TOOLCHAIN_FILE=""
CMAKE_RUN_PATH_PREFIX=""
declare -a CMAKE_COMPILER_ARGS=()
declare -a CMAKE_DEFINE_ARGS=()
BUILD_TARGET="all"

SHOULD_CONAN_BUILD="false"
SHOULD_CONFIGURE="false"
SHOULD_BUILD="false"
SHOULD_RUN="false"
SHOULD_CLEAN="false"
EXIT_AFTER_TYPE_CHANGE="false"

OS_TYPE="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS_TYPE" in
linux*) OS_TYPE="linux" ;;
darwin*) OS_TYPE="darwin" ;;
msys*|mingw*|cygwin*) OS_TYPE="windows" ;;
*) OS_TYPE="unknown" ;;
esac

log_info() { printf '[INFO] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }
log_err() { printf '[ERROR] %s\n' "$*" >&2; }

cmd_array_to_cmdline() {
  local out="" token
  for token in "$@"; do
    if [[ "$token" == *" "* || "$token" == *"("* || "$token" == *")"* || "$token" == *"&"* ]]; then
      out+=" \"${token}\""
    else
      out+=" ${token}"
    fi
  done
  printf '%s' "${out# }"
}

run_with_msvc_env() {
  local user_cmd="$1"
  local msvc_env
  local tmp_cmd tmp_cmd_win
  local exit_code=0
  msvc_env="${MSVC_ENV_SCRIPT//\//\\}"
  log_info "call \"${msvc_env}\" ${HOST_ARCH} && ${user_cmd}"

  if command -v mktemp >/dev/null 2>&1; then
    tmp_cmd="$(mktemp "${TMPDIR:-/tmp}/cb_msvc_XXXXXX.cmd")"
  else
    tmp_cmd="${TMPDIR:-/tmp}/cb_msvc_$$.cmd"
  fi

  cat > "$tmp_cmd" <<EOF
@echo off
call "${msvc_env}" ${HOST_ARCH}
if errorlevel 1 exit /b %errorlevel%
${user_cmd}
exit /b %errorlevel%
EOF

  tmp_cmd_win="$tmp_cmd"
  if command -v cygpath >/dev/null 2>&1; then
    tmp_cmd_win="$(cygpath -w "$tmp_cmd")"
  fi

  # In Git Bash/MSYS, disable argument path conversion for cmd switches.
  MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 \
    cmd.exe /d /c "$tmp_cmd_win" || exit_code=$?

  rm -f "$tmp_cmd"
  return $exit_code
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

to_bool() {
  local v
  v="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$v" in
  1|true|yes|on) printf 'true' ;;
  *) printf 'false' ;;
  esac
}

ini_get() {
  local section="$1" key="$2" default="${3:-}" in_section="false"
  local line sec lhs rhs
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*[#\;] ]] && continue
    if [[ "$line" =~ ^[[:space:]]*\[(.*)\][[:space:]]*$ ]]; then
      sec="$(trim "${BASH_REMATCH[1]}")"
      if [[ "${sec,,}" == "${section,,}" ]]; then
        in_section="true"
      else
        in_section="false"
      fi
      continue
    fi
    [[ "$in_section" != "true" ]] && continue
    [[ "$line" != *"="* ]] && continue
    lhs="$(trim "${line%%=*}")"
    rhs="$(trim "${line#*=}")"
    rhs="${rhs%%#*}"
    rhs="${rhs%%;*}"
    rhs="$(trim "$rhs")"
    if [[ "${lhs,,}" == "${key,,}" ]]; then
      printf '%s' "$rhs"
      return 0
    fi
  done < "$CONFIG_FILE"
  printf '%s' "$default"
}

load_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_err "Config file not found: $CONFIG_FILE"
    exit 1
  fi

  BUILD_TYPE="$(ini_get build build_type Release)"
  SOURCE_DIR="$(ini_get build source_dir .)"
  GENERATOR="$(ini_get build generator Ninja)"
  PARALLEL_JOBS_RAW="$(ini_get build parallel_jobs auto)"
  OUTPUT_DIR="$(ini_get build output_dir "")"

  CONFIG_C_COMPILER="$(trim "$(ini_get compiler c_compiler "")")"
  CONFIG_CXX_COMPILER="$(trim "$(ini_get compiler cpp_compiler "")")"
  C_COMPILER="$CONFIG_C_COMPILER"
  CXX_COMPILER="$CONFIG_CXX_COMPILER"
  CONAN_ENABLE="$(to_bool "$(ini_get conan enable false)")"
  CONAN_BUILD="$(ini_get conan build "")"
  CONAN_HOST="$(ini_get conan host "")"
  VCPKG_ENABLE="$(to_bool "$(ini_get vcpkg enable false)")"
  VCPKG_ROOT="$(trim "$(ini_get vcpkg root "")")"
  VCPKG_TOOLCHAIN_FILE="$(trim "$(ini_get vcpkg toolchain_file "")")"
  VCPKG_TRIPLET="$(trim "$(ini_get vcpkg triplet "")")"
  CBUILD_CUSTOM_TOOLCHAIN_FILE="$(trim "$(ini_get toolchain custom_file "")")"

  MSVC_ENABLE="$(to_bool "$(ini_get msvc enable false)")"
  MSVC_ENV_SCRIPT="$(ini_get msvc msvc_env_script "")"
  HOST_ARCH="$(ini_get msvc host_arch x64)"

  case "$OS_TYPE" in
  windows)
    [[ -n "$C_COMPILER" ]] || C_COMPILER="gcc.exe"
    [[ -n "$CXX_COMPILER" ]] || CXX_COMPILER="g++.exe"
    ;;
  linux)
    [[ -n "$C_COMPILER" ]] || C_COMPILER="gcc"
    [[ -n "$CXX_COMPILER" ]] || CXX_COMPILER="g++"
    ;;
  darwin)
    [[ -n "$C_COMPILER" ]] || C_COMPILER="clang"
    [[ -n "$CXX_COMPILER" ]] || CXX_COMPILER="clang++"
    ;;
  *)
    log_err "Unknown system: $OS_TYPE"
    exit 1
    ;;
  esac
}

is_windows_abs_path() {
  local path="$1"
  [[ "$path" =~ ^[A-Za-z]:[\\/].* ]]
}

resolve_compiler_and_bin_dir() {
  local compiler_value="$1"
  RESOLVED_COMPILER=""
  RESOLVED_BIN_DIR=""

  compiler_value="$(trim "$compiler_value")"
  [[ -n "$compiler_value" ]] || return 0

  if [[ "$compiler_value" == *"/"* || "$compiler_value" == *"\\"* ]]; then
    if [[ "$compiler_value" == /* ]] || is_windows_abs_path "$compiler_value"; then
      RESOLVED_COMPILER="$compiler_value"
    else
      RESOLVED_COMPILER="$PWD/$compiler_value"
    fi
    RESOLVED_BIN_DIR="$(dirname "$RESOLVED_COMPILER")"
    return 0
  fi

  local resolved
  resolved="$(type -P "$compiler_value" || true)"
  if [[ -n "$resolved" ]]; then
    RESOLVED_COMPILER="$resolved"
    RESOLVED_BIN_DIR="$(dirname "$resolved")"
  else
    RESOLVED_COMPILER="$compiler_value"
  fi
}

prepare_cmake_compiler_env() {
  CMAKE_COMPILER_ARGS=()
  CMAKE_RUN_PATH_PREFIX=""

  if [[ "$OS_TYPE" == "windows" && "$MSVC_ENABLE" == "true" && -n "$MSVC_ENV_SCRIPT" ]]; then
    return 0
  fi

  local resolved_c="" resolved_cxx="" c_bin_dir="" cxx_bin_dir=""
  local -a bin_dirs=()

  if [[ -n "$CONFIG_C_COMPILER" ]]; then
    resolve_compiler_and_bin_dir "$CONFIG_C_COMPILER"
    resolved_c="$RESOLVED_COMPILER"
    c_bin_dir="$RESOLVED_BIN_DIR"
    if [[ -n "$resolved_c" ]]; then
      C_COMPILER="$resolved_c"
      CMAKE_COMPILER_ARGS+=("-DCMAKE_C_COMPILER=$resolved_c")
    fi
    if [[ -n "$c_bin_dir" ]]; then
      bin_dirs+=("$c_bin_dir")
    fi
  fi

  if [[ -n "$CONFIG_CXX_COMPILER" ]]; then
    resolve_compiler_and_bin_dir "$CONFIG_CXX_COMPILER"
    resolved_cxx="$RESOLVED_COMPILER"
    cxx_bin_dir="$RESOLVED_BIN_DIR"
    if [[ -n "$resolved_cxx" ]]; then
      CXX_COMPILER="$resolved_cxx"
      CMAKE_COMPILER_ARGS+=("-DCMAKE_CXX_COMPILER=$resolved_cxx")
    fi
    if [[ -n "$cxx_bin_dir" ]]; then
      bin_dirs+=("$cxx_bin_dir")
    fi
  fi

  if [[ ${#bin_dirs[@]} -eq 0 ]]; then
    return 0
  fi

  local -a unique_dirs=()
  local dir
  for dir in "${bin_dirs[@]}"; do
    local exists="false"
    local seen
    for seen in "${unique_dirs[@]}"; do
      if [[ "$seen" == "$dir" ]]; then
        exists="true"
        break
      fi
    done
    if [[ "$exists" == "false" ]]; then
      unique_dirs+=("$dir")
    fi
  done

  CMAKE_RUN_PATH_PREFIX="$(IFS=:; printf '%s' "${unique_dirs[*]}")"

  # 只注入不在当前 PATH 中的目录，避免无意义的提示
  local -a new_dirs=()
  local dir
  for dir in "${unique_dirs[@]}"; do
    case ":${PATH}:" in
      *":${dir}:"*) ;;
      *) new_dirs+=("$dir") ;;
    esac
  done

  if [[ ${#new_dirs[@]} -eq 0 ]]; then
    CMAKE_RUN_PATH_PREFIX=""
    return 0
  fi

  CMAKE_RUN_PATH_PREFIX="$(IFS=:; printf '%s' "${new_dirs[*]}")"
  log_info "Temporary PATH injection for CMake subprocess: $CMAKE_RUN_PATH_PREFIX"
}

save_build_type() {
  local new_type="$1"
  awk -v new_type="$new_type" '
    BEGIN { in_build=0; done=0 }
    /^\[/{ in_build = (tolower($0) == "[build]") }
    {
      if (in_build && tolower($0) ~ /^[[:space:]]*build_type[[:space:]]*=/ && !done) {
        print "build_type = " new_type
        done=1
        next
      }
      print
    }
    END {
      if (!done) {
        if (!in_build) print ""
        print "[build]"
        print "build_type = " new_type
      }
    }
  ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
  mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}

is_build_type() {
  local t="${1:-}"
  [[ "$t" == "Debug" || "$t" == "Release" ]]
}

resolve_generator() {
  local gen="${1:-Ninja}"
  case "$gen" in
  Ninja)
    if ! command -v ninja >/dev/null 2>&1; then
      log_warn "Ninja not found, falling back to Unix Makefiles"
      printf 'Unix Makefiles'
    else
      printf '%s' "$gen"
    fi
    ;;
  *)
    printf '%s' "$gen"
    ;;
  esac
}

get_compiler_type() {
  if [[ "$OS_TYPE" == "windows" && "$MSVC_ENABLE" == "true" && -n "$MSVC_ENV_SCRIPT" ]]; then
    printf 'msvc'
    return 0
  fi
  local base
  base="$(basename "${CXX_COMPILER:-$C_COMPILER}" | tr '[:upper:]' '[:lower:]')"
  case "$base" in
  gcc|gcc.exe) printf 'gcc' ;;
  g++|g++.exe) printf 'g++' ;;
  clang|clang.exe) printf 'clang' ;;
  clang++|clang++.exe) printf 'clang++' ;;
  cl|cl.exe|vcvarsall.bat) printf 'msvc' ;;
  *) printf 'unknown' ;;
  esac
}

detect_compiler_version() {
  local ctype="$1" first_line ver compiler_exec
  case "$ctype" in
  gcc|g++)
    if [[ "$ctype" == "gcc" ]]; then
      compiler_exec="$C_COMPILER"
    else
      compiler_exec="$CXX_COMPILER"
    fi
    if ! first_line="$("$compiler_exec" --version 2>/dev/null | head -n1)"; then
      log_warn "Compiler not found: $compiler_exec"
      printf ''
      return 0
    fi
    ver="$(printf '%s' "$first_line" | grep -Eo '[0-9]+(\.[0-9]+){1,2}' | head -n1 || true)"
    [[ -n "$ver" ]] || ver="unknown"
    if [[ "${first_line,,}" == *"mingw"* ]]; then
      printf 'MinGW-%s' "$ver"
    else
      printf 'GCC-%s' "$ver"
    fi
    ;;
  clang|clang++)
    if [[ "$ctype" == "clang" ]]; then
      compiler_exec="$C_COMPILER"
    else
      compiler_exec="$CXX_COMPILER"
    fi
    if ! first_line="$("$compiler_exec" --version 2>/dev/null | head -n1)"; then
      log_warn "Compiler not found: $compiler_exec"
      printf ''
      return 0
    fi
    ver="$(printf '%s' "$first_line" | grep -Eo '[0-9]+(\.[0-9]+){1,2}' | head -n1 || true)"
    [[ -n "$ver" ]] || ver="unknown"
    printf 'Clang-%s' "$ver"
    ;;
  msvc)
    printf 'MSVC-%s' "${HOST_ARCH:-x64}"
    ;;
  *)
    printf ''
    ;;
  esac
}

prepare_build_dir() {
  local create="${1:-true}"
  if [[ -z "$BUILD_DIR" ]]; then
    local compiler_id
    compiler_id="$(detect_compiler_version "$COMPILER_TYPE")"
    if [[ -n "$compiler_id" ]]; then
      local suffix="${compiler_id}-${BUILD_TYPE}"
    else
      local suffix="${BUILD_TYPE}"
    fi

    if [[ -n "$OUTPUT_DIR" ]]; then
      if [[ "$OUTPUT_DIR" == /* ]] || is_windows_abs_path "$OUTPUT_DIR"; then
        BUILD_DIR="${OUTPUT_DIR}/${suffix}"
      else
        BUILD_DIR="${SOURCE_DIR}/${OUTPUT_DIR}/${suffix}"
      fi
    else
      BUILD_DIR="${SOURCE_DIR}/build/${suffix}"
    fi
  fi
  if [[ "$create" == "true" ]]; then
    mkdir -p "$BUILD_DIR"
  fi
}

copy_compile_commands() {
  local src dst
  src="$BUILD_DIR/compile_commands.json"
  dst="$SOURCE_DIR/build/compile_commands.json"
  if [[ -f "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"
    log_info "Copy compile_commands.json to $dst"
  fi
}

update_cpp_properties() {
  local cpp_json rel_path compile_commands_path escaped
  cpp_json="$SOURCE_DIR/.vscode/c_cpp_properties.json"
  [[ -f "$cpp_json" ]] || return 0

  prepare_build_dir false

  if [[ "$BUILD_DIR" == "$SOURCE_DIR/"* ]]; then
    rel_path="${BUILD_DIR#"$SOURCE_DIR"/}"
    compile_commands_path="\${workspaceFolder}/${rel_path}/compile_commands.json"
  else
    compile_commands_path="${BUILD_DIR}/compile_commands.json"
  fi

#   cp -f "$cpp_json" "${cpp_json}.bak"
  escaped="${compile_commands_path//\//\\/}"
  sed -E "s/(\"compileCommands\"[[:space:]]*:[[:space:]]*\")[^\"]*(\")/\1${escaped}\2/g" \
    "$cpp_json" > "${cpp_json}.tmp"
  mv "${cpp_json}.tmp" "$cpp_json"
  log_info "Updated .vscode/c_cpp_properties.json compileCommands -> ${compile_commands_path}"
}

update_settings_json() {
  local settings_json rel_path compile_commands_dir escaped
  settings_json="$SOURCE_DIR/.vscode/settings.json"
  [[ -f "$settings_json" ]] || return 0

  prepare_build_dir false

  if [[ "$BUILD_DIR" == "$SOURCE_DIR/"* ]]; then
    rel_path="${BUILD_DIR#"$SOURCE_DIR"/}"
    compile_commands_dir="\${workspaceFolder}/${rel_path}"
  else
    compile_commands_dir="${BUILD_DIR}"
  fi

#   cp -f "$settings_json" "${settings_json}.bak"
  escaped="${compile_commands_dir//\//\\/}"
  sed -E "s/(\"--compile-commands-dir=)[^\"]*(\")/\1${escaped}\2/g" \
    "$settings_json" > "${settings_json}.tmp"
  mv "${settings_json}.tmp" "$settings_json"
  log_info "Updated .vscode/settings.json compile-commands-dir -> ${compile_commands_dir}"
}

get_bin_dir() {
  local app_name="${1:-}"
  local rule bin_dir

  # 1) Ninja: 解析 build.ninja
  if [[ -f "$BUILD_DIR/build.ninja" && -n "$app_name" ]]; then
    rule="$(grep -m1 "^build.*: CXX_EXECUTABLE_LINKER__${app_name}[^a-zA-Z]" "$BUILD_DIR/build.ninja" 2>/dev/null || true)"
    if [[ -n "$rule" ]]; then
      rule="${rule#build }"
      rule="${rule%%: *}"
      bin_dir="$(dirname "$rule")"
      printf '%s' "${BUILD_DIR}/${bin_dir}"
      return
    fi
  fi

  # 2) Unix Makefiles: 解析 link.txt
  if [[ -n "$app_name" ]]; then
    local link_file="${BUILD_DIR}/CMakeFiles/${app_name}.dir/link.txt"
    if [[ -f "$link_file" ]]; then
      bin_dir="$(grep -oP '(?<=-o )\S+' "$link_file" 2>/dev/null || true)"
      if [[ -n "$bin_dir" ]]; then
        bin_dir="$(dirname "$bin_dir")"
        printf '%s' "${BUILD_DIR}/${bin_dir}"
        return
      fi
    fi
  fi

  # 3) 默认 fallback
  printf '%s' "${BUILD_DIR}/bin"
}

get_project_name_simple() {
  local cmakelists line name var_name
  cmakelists="$SOURCE_DIR/CMakeLists.txt"
  [[ -f "$cmakelists" ]] || { printf 'application'; return 0; }

  line="$(grep -Eim1 '^[[:space:]]*project[[:space:]]*\(' "$cmakelists" || true)"
  [[ -n "$line" ]] || { printf 'application'; return 0; }
  name="$(printf '%s' "$line" | sed -E 's/.*[Pp][Rr][Oo][Jj][Ee][Cc][Tt][[:space:]]*\([[:space:]]*([^[:space:])]+).*/\1/')"
  [[ -n "$name" ]] || { printf 'application'; return 0; }

  if [[ "$name" =~ ^\$\{[^}]+\}$ ]]; then
    var_name="${name:2:${#name}-3}"
    line="$(grep -Eim1 "^[[:space:]]*set[[:space:]]*\\([[:space:]]*${var_name}[[:space:]]+\"[^\"]+\"" "$cmakelists" || true)"
    if [[ -n "$line" ]]; then
      name="$(printf '%s' "$line" | sed -E 's/.*"([^"]+)".*/\1/')"
    fi
  fi
  printf '%s' "$name"
}

update_vscode_launch() {
  local launch_json rel_path app_name program_path escaped
  launch_json="$SOURCE_DIR/.vscode/launch.json"
  [[ -f "$launch_json" ]] || return 0

  prepare_build_dir false
  app_name="$(get_project_name_simple)"

  local bin_dir
  bin_dir="$(get_bin_dir "$app_name")"
  if [[ "$bin_dir" == "$SOURCE_DIR/"* ]]; then
    rel_path="${bin_dir#"$SOURCE_DIR"/}"
    program_path="\${workspaceFolder}/${rel_path}/${app_name}"
  else
    program_path="${bin_dir}/${app_name}"
  fi

#   cp -f "$launch_json" "${launch_json}.bak"
  escaped="${program_path//\//\\/}"
  sed -E "s/(\"program\"[[:space:]]*:[[:space:]]*\")[^\"]*(\")/\1${escaped}\2/g" \
    "$launch_json" > "${launch_json}.tmp"
  mv "${launch_json}.tmp" "$launch_json"
  log_info "Updated .vscode/launch.json program -> ${program_path}"
}

has_vscode_launch() {
  [[ -f "$SOURCE_DIR/.vscode/launch.json" ]]
}

print_help() {
  cat <<'EOF'
Usage: cb.sh [options]
Options:
  -h, --help                     显示帮助 / Show this help
  -t | --type [Debug|Release]    切换编译类型 (Debug/Release)，保存到 cb_conf.ini
                                 / Toggle or set build type, saves to cb_conf.ini
  --conan [<type>]               使用 Conan 构建依赖库 / Build Conan dependencies
  -g | --generate                运行 CMake 配置 / Run CMake configure only
  -D<name>=<value>               传递 CMake 定义（仅与 -g/--generate 一起使用）
  -D <name>=<value>              Pass a CMake definition (only with -g/--generate)
  -b | --build [<type>] [--target <target>]  构建项目 / Build the project
  -r | --run [<type>]            运行程序 / Run the application
  -c | --clean [<type>]          清理构建目录 / Clean build directory
EOF
}

parse_args() {
  local args=("$@")
  local i=0 arg next type_changed="false" had_action="false"

  while (( i < ${#args[@]} )); do
    arg="${args[i]}"
    case "$arg" in
    -h|--help)
      print_help
      exit 0
      ;;
    -t|--type)
      if (( i + 1 < ${#args[@]} )) && [[ "${args[i+1]}" != -* ]]; then
        next="${args[i+1]}"
        next="${next^}"
        if ! is_build_type "$next"; then
          log_err "Invalid build type: $next, valid types are: Debug Release"
          exit 1
        fi
        i=$((i + 1))
        if [[ "$next" != "$BUILD_TYPE" ]]; then
          BUILD_TYPE="$next"
          save_build_type "$BUILD_TYPE"
          if has_vscode_launch; then
            update_vscode_launch
          fi
          update_cpp_properties
          update_settings_json
          log_info "The build type has been switched to: $BUILD_TYPE"
          type_changed="true"
        else
          log_info "The build type is already: $BUILD_TYPE"
        fi
      else
        if [[ "$BUILD_TYPE" == "Release" ]]; then
          BUILD_TYPE="Debug"
        else
          BUILD_TYPE="Release"
        fi
        save_build_type "$BUILD_TYPE"
        if has_vscode_launch; then
          update_vscode_launch
        fi
        update_cpp_properties
        update_settings_json
        log_info "The build type has been switched to: $BUILD_TYPE"
        type_changed="true"
      fi
      ;;
    --conan)
      SHOULD_CONAN_BUILD="true"
      had_action="true"
      if (( i + 1 < ${#args[@]} )) && [[ "${args[i+1]}" != -* ]]; then
        type="${args[i+1]^}"
        if is_build_type "$type"; then
          BUILD_TYPE="$type"
          i=$((i + 1))
        fi
      fi
      ;;
    -g|--generate)
      SHOULD_CONFIGURE="true"
      had_action="true"
      ;;
    -D)
      if (( i + 1 >= ${#args[@]} )) || [[ -z "${args[i+1]}" ]]; then
        log_err "-D requires a definition, for example: -DMY_OPTION=ON"
        exit 1
      fi
      CMAKE_DEFINE_ARGS+=("-D${args[i+1]}")
      i=$((i + 1))
      ;;
    -D?*)
      CMAKE_DEFINE_ARGS+=("$arg")
      ;;
    -b|--build)
      SHOULD_BUILD="true"
      had_action="true"
      if (( i + 1 < ${#args[@]} )) && [[ "${args[i+1]}" != -* ]]; then
        type="${args[i+1]^}"
        if is_build_type "$type"; then
          BUILD_TYPE="$type"
          i=$((i + 1))
        fi
      fi
      if (( i + 2 < ${#args[@]} )) && [[ "${args[i+1]}" == "--target" ]]; then
        BUILD_TARGET="${args[i+2]}"
        i=$((i + 2))
      fi
      ;;
    -r|--run)
      SHOULD_RUN="true"
      had_action="true"
      if (( i + 1 < ${#args[@]} )) && [[ "${args[i+1]}" != -* ]]; then
        type="${args[i+1]^}"
        if is_build_type "$type"; then
          BUILD_TYPE="$type"
          i=$((i + 1))
        fi
      fi
      ;;
    -c|--clean)
      SHOULD_CLEAN="true"
      had_action="true"
      if (( i + 1 < ${#args[@]} )) && [[ "${args[i+1]}" != -* ]]; then
        type="${args[i+1]^}"
        if is_build_type "$type"; then
          BUILD_TYPE="$type"
          i=$((i + 1))
        fi
      fi
      ;;
    *)
      log_err "Unknown option: $arg"
      exit 1
      ;;
    esac
    i=$((i + 1))
  done

  if (( ${#CMAKE_DEFINE_ARGS[@]} > 0 )) && [[ "$SHOULD_CONFIGURE" != "true" ]]; then
    log_err "CMake definitions (-D...) are only valid together with -g or --generate"
    exit 1
  fi

  if [[ "$type_changed" == "true" && "$had_action" == "false" ]]; then
    EXIT_AFTER_TYPE_CHANGE="true"
  fi
}

run_conan_install() {
  local conan_enabled="$CONAN_ENABLE"
  local conan_build="$CONAN_BUILD"
  local conan_host="$CONAN_HOST"
  local conan_file_txt conan_file_py
  local cmd=() line key value

  [[ "$conan_enabled" == "true" ]] || return 0

  conan_file_txt="$SOURCE_DIR/conanfile.txt"
  conan_file_py="$SOURCE_DIR/conanfile.py"
  if [[ ! -f "$conan_file_txt" && ! -f "$conan_file_py" ]]; then
    return 0
  fi

  cmd=(conan install "$SOURCE_DIR" -s "build_type=$BUILD_TYPE" --output-folder "$BUILD_DIR" --build=missing)

  if [[ -n "$(trim "$conan_build")" && -z "$(trim "$conan_host")" ]]; then
    cmd+=(--profile:build "$(trim "$conan_build")")
  elif [[ -n "$(trim "$conan_build")" && -n "$(trim "$conan_host")" ]]; then
    cmd+=(--profile:build "$(trim "$conan_build")" --profile:host "$(trim "$conan_host")")
  fi

  if [[ -f "$conan_file_txt" ]]; then
    local in_options="false"
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      line="$(trim "$line")"
      [[ -z "$line" ]] && continue
      [[ "$line" =~ ^[[:space:]]*[#\;] ]] && continue
      if [[ "$line" =~ ^\[(.*)\]$ ]]; then
        if [[ "${BASH_REMATCH[1],,}" == "options" ]]; then
          in_options="true"
        else
          in_options="false"
        fi
        continue
      fi
      [[ "$in_options" == "true" ]] || continue
      if [[ "$line" == *"="* ]]; then
        key="$(trim "${line%%=*}")"
        value="$(trim "${line#*=}")"
        cmd+=(-o "${key}=${value}")
      fi
    done < "$conan_file_txt"
  fi

  log_info "$(cmd_array_to_cmdline "${cmd[@]}")"
  if [[ "$OS_TYPE" == "windows" && "$MSVC_ENABLE" == "true" && -n "$MSVC_ENV_SCRIPT" ]]; then
    run_with_msvc_env "$(cmd_array_to_cmdline "${cmd[@]}")"
  else
    "${cmd[@]}"
  fi

  local toolchain_file
  toolchain_file="$(detect_toolchain_file)"
  if [[ -n "$toolchain_file" && -f "$toolchain_file" ]]; then
    patch_conan_toolchain "$toolchain_file"
    CMAKE_TOOLCHAIN_FILE="${toolchain_file//\\//}"
  fi
}

patch_conan_toolchain() {
  local toolchain_file="$1"
  [[ -n "$toolchain_file" && -f "$toolchain_file" ]] || return 0

  # cp -f "$toolchain_file" "${toolchain_file}.bak"
  sed -E \
    -e 's/^(set\(CMAKE_GENERATOR_(PLATFORM|TOOLSET).*FORCE\))/#\1/' \
    -e 's/^(message\(STATUS "Conan toolchain: CMAKE_GENERATOR_TOOLSET=.*"\))/#\1/' \
    -e 's/^(string\(APPEND CONAN_(CXX_FLAGS|C_FLAGS) " \/MP[0-9]+"\))/#\1/' \
    -e '/message\(FATAL_ERROR "The .CMakeToolchain./s/^/#/' \
    -e 's/(list\(PREPEND ([^ )]*))/list(INSERT \2 0/' \
    -e '/CMAKE_FIND_PACKAGE_PREFER_CONFIG/s/^/#/' \
    "$toolchain_file" > "${toolchain_file}.tmp"
  mv "${toolchain_file}.tmp" "$toolchain_file"

  # 同样 patch 同目录下 *Config.cmake 中的 CMake 版本检查
  local gen_dir
  gen_dir="$(dirname "$toolchain_file")"
  while IFS= read -r -d '' cfg; do
    if grep -q 'message(FATAL_ERROR.*CMakeDeps.*generator.*only works with CMake' "$cfg" 2>/dev/null; then
      sed -i '/message(FATAL_ERROR.*CMakeDeps.*generator.*only works with CMake/s/^/#/' "$cfg"
      log_info "Patched CMake version check in $(basename "$cfg")"
    fi
  done < <(find "$gen_dir" -maxdepth 1 -name '*Config.cmake' -print0 2>/dev/null)
}

resolve_config_path() {
  local value
  value="$(trim "$1")"
  [[ -n "$value" ]] || return 0

  if [[ "$value" == /* ]] || is_windows_abs_path "$value"; then
    printf '%s' "$value"
  else
    printf '%s/%s' "$(cd "$(dirname "$CONFIG_FILE")" && pwd -P)" "$value"
  fi
}

cmake_path() {
  local path="$1"
  if [[ "$path" != /* ]] && ! is_windows_abs_path "$path"; then
    path="$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")"
  fi
  printf '%s' "${path//\\//}"
}

get_vcpkg_toolchain_file() {
  local toolchain_file vcpkg_root
  if [[ -n "$VCPKG_TOOLCHAIN_FILE" ]]; then
    toolchain_file="$(resolve_config_path "$VCPKG_TOOLCHAIN_FILE")"
  else
    vcpkg_root="$VCPKG_ROOT"
    if [[ -z "$vcpkg_root" ]]; then
      vcpkg_root="$ENV_VCPKG_ROOT"
    fi
    if [[ -z "$vcpkg_root" ]]; then
      log_err "vcpkg is enabled but neither [vcpkg] toolchain_file/root nor VCPKG_ROOT is set"
      return 1
    fi
    vcpkg_root="$(resolve_config_path "$vcpkg_root")"
    toolchain_file="${vcpkg_root}/scripts/buildsystems/vcpkg.cmake"
  fi

  if [[ ! -f "$toolchain_file" ]]; then
    log_err "vcpkg toolchain file not found: $toolchain_file"
    return 1
  fi
  cmake_path "$toolchain_file"
}

get_custom_toolchain_file() {
  local custom_file
  [[ -n "$CBUILD_CUSTOM_TOOLCHAIN_FILE" ]] || return 0
  custom_file="$(resolve_config_path "$CBUILD_CUSTOM_TOOLCHAIN_FILE")"
  if [[ ! -f "$custom_file" ]]; then
    log_err "Custom toolchain file not found: $custom_file"
    return 1
  fi
  cmake_path "$custom_file"
}

write_cbuild_toolchain() {
  local vcpkg_toolchain_file="$1"
  local conan_toolchain_file="$2"
  local custom_toolchain_file="$3"
  local toolchain_file="${BUILD_DIR}/cbuild_toolchain.cmake"

  {
    printf '%s\n' '# Generated by cbuild. Do not edit.'
    printf '%s\n' '# Edit the configured [toolchain] custom_file instead.'
    printf '\n'
    if [[ -n "$custom_toolchain_file" ]]; then
      printf '%s\n' '# User settings must be visible before vcpkg is initialized.'
      printf 'include("%s")\n\n' "$custom_toolchain_file"
    fi
    if [[ -n "$vcpkg_toolchain_file" ]]; then
      if [[ -n "$conan_toolchain_file" ]]; then
        printf 'set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "%s")\n\n' "$conan_toolchain_file"
      fi
      if [[ -n "$VCPKG_TRIPLET" ]]; then
        printf 'set(VCPKG_TARGET_TRIPLET "%s")\n\n' "$VCPKG_TRIPLET"
      fi
      printf 'include("%s")\n' "$vcpkg_toolchain_file"
    elif [[ -n "$conan_toolchain_file" ]]; then
      printf 'include("%s")\n' "$conan_toolchain_file"
    fi
  } > "${toolchain_file}.tmp"
  mv "${toolchain_file}.tmp" "$toolchain_file"
  CMAKE_TOOLCHAIN_FILE="$(cmake_path "$toolchain_file")"
  log_info "Generated cbuild toolchain: $CMAKE_TOOLCHAIN_FILE"
}

ensure_cached_toolchain_matches() {
  local cache_file="${BUILD_DIR}/CMakeCache.txt"
  local cache_line=""
  local cached_toolchain=""
  local desired_toolchain="${CMAKE_TOOLCHAIN_FILE:-}"

  [[ -f "$cache_file" ]] || return 0
  cache_line="$(grep -m1 '^CMAKE_TOOLCHAIN_FILE:[^=]*=' "$cache_file" || true)"
  if [[ -n "$cache_line" ]]; then
    cached_toolchain="${cache_line#*=}"
    cached_toolchain="$(cmake_path "$cached_toolchain")"
  fi

  if [[ "$cached_toolchain" == "$desired_toolchain" ]]; then
    return 0
  fi
  if [[ -z "$cache_line" && -z "$desired_toolchain" ]]; then
    return 0
  fi

  log_err "CMake toolchain changed after this build directory was configured. Run cb.py -c (or cb.sh -c), then install Conan dependencies again if needed."
  exit 1
}

prepare_cmake_toolchain() {
  local conan_toolchain_file=""
  local vcpkg_toolchain_file=""
  local custom_toolchain_file=""

  CMAKE_TOOLCHAIN_FILE=""
  if [[ "$CONAN_ENABLE" == "true" && ( -f "$SOURCE_DIR/conanfile.txt" || -f "$SOURCE_DIR/conanfile.py" ) ]]; then
    conan_toolchain_file="$(detect_toolchain_file)"
    if [[ -n "$conan_toolchain_file" && -f "$conan_toolchain_file" ]]; then
      patch_conan_toolchain "$conan_toolchain_file"
      conan_toolchain_file="$(cmake_path "$conan_toolchain_file")"
    else
      conan_toolchain_file=""
    fi
  fi

  if [[ "$VCPKG_ENABLE" == "true" ]]; then
    vcpkg_toolchain_file="$(get_vcpkg_toolchain_file)" || exit 1
  fi
  custom_toolchain_file="$(get_custom_toolchain_file)" || exit 1

  if [[ -n "$vcpkg_toolchain_file" || -n "$custom_toolchain_file" ]]; then
    write_cbuild_toolchain "$vcpkg_toolchain_file" "$conan_toolchain_file" "$custom_toolchain_file"
  else
    CMAKE_TOOLCHAIN_FILE="$conan_toolchain_file"
  fi
  ensure_cached_toolchain_matches
}

detect_toolchain_file() {
  local toolchain_file=""
  if [[ -f "$BUILD_DIR/conan_toolchain.cmake" ]]; then
    toolchain_file="$BUILD_DIR/conan_toolchain.cmake"
  else
    toolchain_file="$(find "$BUILD_DIR" -type f -name conan_toolchain.cmake 2>/dev/null | head -n1 || true)"
  fi
  printf '%s' "$toolchain_file"
}

run_cmake_configure() {
  if [[ "$OS_TYPE" == "windows" && "$MSVC_ENABLE" == "true" && -n "$MSVC_ENV_SCRIPT" ]]; then
    local cmake_cmd
    cmake_cmd="cmake -H\"${SOURCE_DIR}\" -B\"${BUILD_DIR}\" -G \"${GENERATOR}\" -DCMAKE_BUILD_TYPE=${BUILD_TYPE}"
    if [[ -n "$CMAKE_TOOLCHAIN_FILE" ]]; then
      cmake_cmd+=" -DCMAKE_TOOLCHAIN_FILE=\"${CMAKE_TOOLCHAIN_FILE}\""
    fi
    if (( ${#CMAKE_DEFINE_ARGS[@]} > 0 )); then
      cmake_cmd+=" $(cmd_array_to_cmdline "${CMAKE_DEFINE_ARGS[@]}")"
    fi
    run_with_msvc_env "$cmake_cmd"
    return 0
  fi

  local cmd=()
  cmd=(cmake -H"$SOURCE_DIR" -B"$BUILD_DIR" -G "$GENERATOR" "-DCMAKE_BUILD_TYPE=$BUILD_TYPE")
  if [[ ${#CMAKE_COMPILER_ARGS[@]} -gt 0 ]]; then
    cmd+=("${CMAKE_COMPILER_ARGS[@]}")
  fi
  if [[ -n "$CMAKE_TOOLCHAIN_FILE" ]]; then
    cmd+=("-DCMAKE_TOOLCHAIN_FILE=$CMAKE_TOOLCHAIN_FILE")
  fi
  cmd+=("${CMAKE_DEFINE_ARGS[@]}")
  log_info "$(cmd_array_to_cmdline "${cmd[@]}")"
  if [[ -n "$CMAKE_RUN_PATH_PREFIX" ]]; then
    PATH="$CMAKE_RUN_PATH_PREFIX${PATH:+:$PATH}" "${cmd[@]}"
  else
    "${cmd[@]}"
  fi
}

run_cmake_build() {
  # CMake --build -j flag requires CMake >= 3.12, use -- separator for older versions
  local cmake_ver cmake_major cmake_minor
  cmake_ver="$(cmake --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
  cmake_major="${cmake_ver%.*}"
  cmake_minor="${cmake_ver#*.}"

  if [[ "$OS_TYPE" == "windows" && "$MSVC_ENABLE" == "true" && -n "$MSVC_ENV_SCRIPT" ]]; then
    local build_cmd
    build_cmd="cmake --build \"${BUILD_DIR}\" --target ${BUILD_TARGET}"
    if (( cmake_major > 3 || (cmake_major == 3 && cmake_minor >= 12) )); then
      build_cmd+=" -j${PARALLEL_JOBS}"
    else
      build_cmd+=" -- -j${PARALLEL_JOBS}"
    fi
    run_with_msvc_env "$build_cmd"
    return 0
  fi

  local cmd=(cmake --build "$BUILD_DIR" --target "$BUILD_TARGET")
  if (( cmake_major > 3 || (cmake_major == 3 && cmake_minor >= 12) )); then
    cmd+=("-j$PARALLEL_JOBS")
  else
    cmd+=("--" "-j$PARALLEL_JOBS")
  fi
  log_info "$(cmd_array_to_cmdline "${cmd[@]}")"
  if [[ -n "$CMAKE_RUN_PATH_PREFIX" ]]; then
    PATH="$CMAKE_RUN_PATH_PREFIX${PATH:+:$PATH}" "${cmd[@]}"
  else
    "${cmd[@]}"
  fi
}

run_application() {
  local app_name exe_path
  app_name="$(get_project_name_simple)"
  local bin_dir
  bin_dir="$(get_bin_dir "$app_name")"
  if [[ "$OS_TYPE" == "windows" ]]; then
    exe_path="${bin_dir}/${app_name}.exe"
  else
    exe_path="${bin_dir}/${app_name}"
  fi
  if [[ ! -f "$exe_path" ]]; then
    log_err "The executable file: $exe_path cannot be found."
    exit 1
  fi
  log_info "Running $exe_path"
  "$exe_path"
}

clean_build() {
  prepare_build_dir false
  if [[ -d "$BUILD_DIR" ]]; then
    log_info "Cleaning $BUILD_DIR"
    rm -rf "$BUILD_DIR"
  fi
  rm -f "$SOURCE_DIR/build/compile_commands.json"
}

set_parallel_jobs() {
  if [[ "${PARALLEL_JOBS_RAW,,}" == "auto" || -z "$PARALLEL_JOBS_RAW" ]]; then
    if command -v nproc >/dev/null 2>&1; then
      PARALLEL_JOBS="$(nproc)"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
      PARALLEL_JOBS="$(sysctl -n hw.ncpu)"
    else
      PARALLEL_JOBS="1"
    fi
  else
    PARALLEL_JOBS="$PARALLEL_JOBS_RAW"
  fi
}

detect_existing_toolchain() {
  local toolchain_file
  toolchain_file="$(detect_toolchain_file)"
  if [[ -n "$toolchain_file" && -f "$toolchain_file" ]]; then
    patch_conan_toolchain "$toolchain_file"
    CMAKE_TOOLCHAIN_FILE="${toolchain_file//\\//}"
  fi
}

main() {
  load_config
  GENERATOR="$(resolve_generator "$GENERATOR")"
  set_parallel_jobs
  COMPILER_TYPE="$(get_compiler_type)"

  parse_args "$@"

  if [[ "$EXIT_AFTER_TYPE_CHANGE" == "true" ]]; then
    exit 0
  fi

  prepare_cmake_compiler_env
  COMPILER_TYPE="$(get_compiler_type)"
  prepare_build_dir true

  if [[ "$SHOULD_CLEAN" == "true" ]]; then
    clean_build
    exit 0
  fi

  if [[ "$SHOULD_CONAN_BUILD" == "true" ]]; then
    run_conan_install
    rm -rf "$SOURCE_DIR/CMakeUserPresets.json"
    exit 0
  fi

  if [[ "$SHOULD_CONFIGURE" == "true" ]]; then
    prepare_cmake_toolchain
    run_cmake_configure
    if has_vscode_launch; then
      update_vscode_launch
    fi
    update_cpp_properties
    update_settings_json
    exit 0
  fi

  if [[ "$SHOULD_BUILD" == "true" ]]; then
    run_cmake_build

    local app_name exe_path bin_dir
    app_name="$(get_project_name_simple)"
    bin_dir="$(get_bin_dir "$app_name")"
    if [[ "$OS_TYPE" == "windows" ]]; then
      exe_path="${bin_dir}/${app_name}.exe"
    else
      exe_path="${bin_dir}/${app_name}"
    fi
    if [[ ! -f "$exe_path" ]]; then
      log_err "The executable file: $exe_path cannot be found."
      exit 1
    fi
    if has_vscode_launch; then
      update_vscode_launch
    fi
    update_cpp_properties
    update_settings_json
    log_info "exec: $exe_path"
    exit 0
  fi

  if [[ "$SHOULD_RUN" == "true" ]]; then
    run_application
    exit 0
  fi

  printf 'Use -h for help.\n'
}

main "$@"
