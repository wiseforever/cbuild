#!/usr/bin/env bash

set -euo pipefail

CBUILD_VERSION="0.3.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_FILE_CWD="$PWD/cb.conf"
CONFIG_FILE="$CONFIG_FILE_CWD"
if [[ ! -f "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$SCRIPT_DIR/cb.conf"
fi

VALID_BUILD_TYPES=("Debug" "Release")

BUILD_TYPE="Release"
SOURCE_DIR="."
GENERATOR="Ninja"
PARALLEL_JOBS_RAW="auto"

C_COMPILER=""
CXX_COMPILER=""
CONFIG_COMPILER=""
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
BUILD_DIR_TYPE=""
OUTPUT_DIR_USE_SUBDIR="true"
SUBDIR_USE_COMPILER="false"
COMPILER_TYPE="unknown"
CMAKE_TOOLCHAIN_FILE=""
CMAKE_RUN_PATH_PREFIX=""
declare -a CMAKE_COMPILER_ARGS=()
declare -a CMAKE_DEFINE_ARGS=()
BUILD_TARGET="all"
EXEC_NAME=""

SHOULD_CONAN_BUILD="false"
SHOULD_CONAN_PROFILE="false"
COMPILER_FAMILY=""
COMPILER_MAJOR=""
COMPILER_EXECUTABLES=""
COMPILER_SYSROOT=""
declare -a COMPILER_BUILDENV=()
declare -a CONAN_PROFILE_ARGS=()
SHOULD_CONFIGURE="false"
SHOULD_BUILD="false"
SHOULD_RUN="false"
SHOULD_CLEAN="false"
SHOULD_LIST_EXECS="false"
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

is_windows_abs_path() {
  local path="$1"
  [[ "$path" =~ ^[A-Za-z]:[\\/].* ]]
}

normalize_path() {
  # Normalize absolute paths lexically: do not resolve symlinks and do not
  # require the path to exist. Standalone relative prefixes such as ./ and ../
  # are returned unchanged.
  local path="$1" prefix="" rest component joined
  local -a parts=() components=()

  if [[ "$path" =~ ^[A-Za-z]:[\\/] ]]; then
    path="${path//\\//}"
    prefix="${path:0:3}"
    rest="${path:3}"
  elif [[ "$path" == /* ]]; then
    prefix="/"
    rest="${path#/}"
  else
    printf '%s' "$path"
    return
  fi

  IFS='/' read -r -a components <<< "$rest"
  for component in "${components[@]}"; do
    case "$component" in
      ''|.)
        ;;
      ..)
        if (( ${#parts[@]} > 0 )); then
          unset "parts[$(( ${#parts[@]} - 1 ))]"
        fi
        ;;
      *)
        parts+=("$component")
        ;;
    esac
  done

  joined="$(IFS=/; printf '%s' "${parts[*]}")"
  if [[ -n "$joined" ]]; then
    printf '%s%s' "$prefix" "$joined"
  else
    printf '%s' "$prefix"
  fi
}

resolve_config_path() {
  local value
  value="$(trim "$1")"
  [[ -n "$value" ]] || return 0

  if [[ "$value" == /* ]] || is_windows_abs_path "$value"; then
    normalize_path "$value"
  else
    normalize_path "$(cd "$(dirname "$CONFIG_FILE")" && pwd -P)/$value"
  fi
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
  SOURCE_DIR="$(resolve_config_path "$(ini_get build source_dir .)")"
  GENERATOR="$(ini_get build generator Ninja)"
  PARALLEL_JOBS_RAW="$(ini_get build parallel_jobs auto)"
  OUTPUT_DIR="$(ini_get build output_dir "")"
  OUTPUT_DIR_USE_SUBDIR="$(to_bool "$(ini_get build output_dir_use_subdir true)")"
  SUBDIR_USE_COMPILER="$(to_bool "$(ini_get build subdir_use_compiler false)")"

  local unsupported_key
  for unsupported_key in c_compiler cpp_compiler; do
    if [[ "$(ini_get compiler "$unsupported_key" __cbuild_absent_key__)" != __cbuild_absent_key__ ]]; then
      log_err "Unsupported [compiler] options: c_compiler/cpp_compiler; configure compiler = gcc, gcc-9, clang or a toolchain driver path"
      exit 1
    fi
  done
  CONFIG_COMPILER="$(trim "$(ini_get compiler compiler "")")"
  CONFIG_C_COMPILER=""
  CONFIG_CXX_COMPILER=""
  C_COMPILER=""
  CXX_COMPILER=""
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
  configure_compiler_pair
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

configure_compiler_pair() {
  [[ -n "$CONFIG_COMPILER" ]] || return 0
  [[ "$OS_TYPE" != "windows" || "$MSVC_ENABLE" != "true" || -z "$MSVC_ENV_SCRIPT" ]] || return 0
  local resolved directory base prefix family version extension driver name nearby path
  local -a families=() drivers=()
  resolve_compiler_and_bin_dir "$CONFIG_COMPILER"
  resolved="$RESOLVED_COMPILER"
  directory="$RESOLVED_BIN_DIR"
  base="$(basename "$resolved")"
  if [[ ! "$base" =~ ^(.*-)?(gcc|g\+\+|clang|clang\+\+)(-[0-9]+(\.[0-9]+)*)?(\.exe)?$ ]]; then
    log_err "Unsupported [compiler] compiler: $CONFIG_COMPILER; use a GCC or Clang driver"
    exit 1
  fi
  prefix="${BASH_REMATCH[1]}"
  family="${BASH_REMATCH[2]}"
  version="${BASH_REMATCH[3]}"
  extension="${BASH_REMATCH[5]}"
  case "$family" in
  gcc|g++) families=(gcc 'g++') ;;
  *) families=(clang 'clang++') ;;
  esac
  for driver in "${families[@]}"; do
    name="${prefix}${driver}${version}${extension}"
    nearby="$name"
    [[ -z "$directory" ]] || nearby="$directory/$name"
    if [[ "$driver" == "$family" ]]; then
      path="$resolved"
    elif [[ -x "$nearby" && ! -d "$nearby" ]]; then
      path="$nearby"
    else
      path="$(type -P "$name" || true)"
      [[ -n "$path" ]] || path="$nearby"
    fi
    drivers+=("$path")
  done
  CONFIG_C_COMPILER="${drivers[0]}"
  CONFIG_CXX_COMPILER="${drivers[1]}"
  C_COMPILER="$CONFIG_C_COMPILER"
  CXX_COMPILER="$CONFIG_CXX_COMPILER"
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
    {
      # Normalize CRLF and use explicit spaces/tabs for mawk 1.3.3.
      sub(/\r$/, "")
      if ($0 ~ /^[ \t]*\[.*\][ \t]*$/) {
        if (in_build && !done) {
          print "build_type = " new_type
          done=1
        }
        section=$0
        sub(/^[ \t]*\[/, "", section)
        sub(/\][ \t]*$/, "", section)
        sub(/^[ \t]*/, "", section)
        sub(/[ \t]*$/, "", section)
        in_build = (tolower(section) == "build")
      }
      if (in_build && tolower($0) ~ /^[ \t]*build_type[ \t]*=/ && !done) {
        print "build_type = " new_type
        done=1
        next
      }
      print
    }
    END {
      if (!done) {
        if (!in_build) {
          print ""
          print "[build]"
        }
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
  if [[ "$base" =~ ^(.*-)?(gcc|g\+\+|clang|clang\+\+)(-[0-9]+(\.[0-9]+)*)?(\.exe)?$ ]]; then
    printf '%s' "${BASH_REMATCH[2]}"
  else
    case "$base" in
    cl|cl.exe|vcvarsall.bat) printf 'msvc' ;;
    *) printf 'unknown' ;;
    esac
  fi
}

detect_compiler_version() {
  local -x PATH="${CMAKE_RUN_PATH_PREFIX}${CMAKE_RUN_PATH_PREFIX:+:}$PATH"
  local ctype="$1" output first_line ver compiler_exec
  case "$ctype" in
  gcc|g++)
    if [[ "$ctype" == "gcc" ]]; then
      compiler_exec="$C_COMPILER"
    else
      compiler_exec="$CXX_COMPILER"
    fi
    if ! output="$("$compiler_exec" --version 2>/dev/null)" || [[ -z "$output" ]]; then
      log_warn "Cannot query compiler: $compiler_exec"
      return 0
    fi
    first_line="${output%%$'\n'*}"
    # GCC provides a machine-readable version, unlike distribution banners.
    ver="$("$compiler_exec" -dumpfullversion -dumpversion 2>/dev/null || true)"
    if [[ ! "$ver" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
      ver="$(printf '%s' "$first_line" | grep -Eo '[0-9]+(\.[0-9]+){1,2}' | head -n1 || true)"
    fi
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
    if ! output="$("$compiler_exec" --version 2>/dev/null)" || [[ -z "$output" ]]; then
      log_warn "Cannot query compiler: $compiler_exec"
      return 0
    fi
    first_line="${output%%$'\n'*}"
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
  if [[ -z "$BUILD_DIR" || "$BUILD_DIR_TYPE" != "$BUILD_TYPE" ]]; then
    local compiler_id suffix="$BUILD_TYPE"
    if [[ "$OUTPUT_DIR_USE_SUBDIR" == "true" && "$SUBDIR_USE_COMPILER" == "true" ]]; then
      compiler_id="$(detect_compiler_version "$COMPILER_TYPE")"
      if [[ -n "$compiler_id" ]]; then
        suffix="${compiler_id}-${BUILD_TYPE}"
      fi
    fi

    local base_dir
    if [[ -n "$OUTPUT_DIR" ]]; then
      if [[ "$OUTPUT_DIR" == /* ]] || is_windows_abs_path "$OUTPUT_DIR"; then
        base_dir="$OUTPUT_DIR"
      else
        base_dir="${SOURCE_DIR}/${OUTPUT_DIR}"
      fi
    else
      base_dir="${SOURCE_DIR}/build"
    fi

    if [[ "$OUTPUT_DIR_USE_SUBDIR" == "true" ]]; then
      BUILD_DIR="${base_dir}/${suffix}"
    else
      BUILD_DIR="${base_dir}"
    fi
    BUILD_DIR="$(normalize_path "$BUILD_DIR")"
    BUILD_DIR_TYPE="$BUILD_TYPE"
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

update_clangd_config() {
  local path="$SOURCE_DIR/.clangd" directory tmp='' input missing=false last_newline=true
  prepare_build_dir false
  if [[ "$BUILD_DIR" == "$SOURCE_DIR" ]]; then
    directory='.'
  elif [[ "$SOURCE_DIR" == / && "$BUILD_DIR" == /* ]]; then
    directory="${BUILD_DIR#/}"
  elif [[ "$BUILD_DIR" == "$SOURCE_DIR/"* ]]; then
    directory="${BUILD_DIR#"$SOURCE_DIR"/}"
  else
    directory="$BUILD_DIR"
    if [[ "$OS_TYPE" == windows ]] && command -v cygpath >/dev/null 2>&1; then
      directory="$(cygpath -m "$directory")" || { log_warn "Failed to convert .clangd path"; return 0; }
    fi
  fi
  if [[ "$directory" == *$'\n'* || "$directory" == *$'\r'* || -L "$path" ]]; then
    log_warn "Failed to update .clangd: invalid path or symbolic link"
    return 0
  fi
  if [[ -e "$path" ]]; then
    if [[ ! -f "$path" || ! -r "$path" ]]; then
      log_warn "Failed to update .clangd: not a readable regular file"
      return 0
    fi
    if [[ -s "$path" && -n "$(tail -c 1 "$path")" ]]; then last_newline=false; fi
  else
    missing=true
  fi
  tmp="$(mktemp "$SOURCE_DIR/.clangd.XXXXXXXX")" || { log_warn "Failed to create .clangd temporary file"; return 0; }
  if [[ -e "$path" ]] && ! cp -p "$path" "$tmp"; then
    log_warn "Failed to preserve .clangd permissions"; rm -f "$tmp"; return 0
  fi
  input="$path"
  [[ "$missing" == false ]] || input=/dev/null
  # Recognize plain block mappings only; never guess at conditional or complex YAML.
  if ! CBUILD_CLANGD_DIR="$directory" CBUILD_CLANGD_MISSING="$missing" CBUILD_CLANGD_NEWLINE="$last_newline" awk '
    function fail(reason) {
      print "Cannot update .clangd: " reason > "/dev/stderr"
      exit 2
    }
    function indent(s) { match(s, /^ */); return RLENGTH }
    function suffix(s, q, c, j, tail) {
      q = substr(s, 1, 1)
      if (q == sq || q == "\"") {
        for (j = 2; j <= length(s); j++) {
          c = substr(s, j, 1)
          if (q == "\"" && c == "\\") { j++; continue }
          if (c != q) continue
          if (q == sq && substr(s, j + 1, 1) == sq) { j++; continue }
          tail = substr(s, j + 1)
          if (tail !~ /^ *(#.*)?$/) fail("unsupported CompilationDatabase scalar")
          return tail
        }
        fail("unsupported CompilationDatabase scalar")
      }
      if (q == "#") return " " s
      if (length(q) && index("[{&*!|>", q)) fail("CompilationDatabase must be a single-line scalar")
      if (match(s, / +#/)) return substr(s, RSTART)
      match(s, / *$/)
      return substr(s, RSTART)
    }
    { lines[NR] = $0 }
    END {
      sq = sprintf("%c", 39)
      directory = ENVIRON["CBUILD_CLANGD_DIR"]
      gsub(sq, sq sq, directory)
      value = sq directory sq
      n = NR
      if (ENVIRON["CBUILD_CLANGD_MISSING"] == "true") {
        print "CompileFlags:"
        print "  CompilationDatabase: " value
        print ""
        print "Completion:"
        print "  # 可选值：true（包含不可见作用域的补全）、false（仅当前可见作用域）。"
        print "  AllScopes: false"
        print "  # 可选值：IWYU（补全时按需插入头文件）、Never（不自动插入）。"
        print "  HeaderInsertion: Never"
      } else {
        block_end = n + 1
        insert_at = 1
        for (i = 1; i <= n; i++) {
          raw = lines[i]
          if (index(raw, "\r")) fail("expected LF-delimited text")
          if (raw ~ /^ *\t/) fail("tab indentation is not supported")
          if (raw ~ /^ *(#.*)?$/) continue
          if (raw ~ /^ /) {
            seen = 1
            if (block_start && block_end == n + 1) {
              width = indent(raw)
              if (!child_indent || width < child_indent) child_indent = width
            }
            continue
          }
          if (raw ~ /^--- *(#.*)?$/) {
            if (seen) fail("multiple YAML documents are not supported")
            seen = 1
            insert_at = i + 1
            continue
          }
          seen = 1
          if (!match(raw, /^[A-Za-z_][A-Za-z_0-9.-]* *:( |$)/)) fail("expected plain top-level YAML keys")
          key = substr(raw, 1, RLENGTH)
          rest = substr(raw, RLENGTH + 1)
          sub(/ *: *$/, "", key)
          if (key == "If") fail("conditional YAML configuration is not supported")
          if (block_start && block_end == n + 1) block_end = i
          if (key == "CompileFlags") {
            if (block_start) fail("duplicate CompileFlags blocks")
            if (rest !~ /^ *(#.*)?$/) fail("CompileFlags must be a block mapping")
            block_start = i
          }
        }
        if (block_start) {
          if (!child_indent) child_indent = 2
          for (i = block_start + 1; i < block_end; i++) {
            raw = lines[i]
            if (raw ~ /^ *(#.*)?$/) continue
            width = indent(raw)
            if (after_target) {
              if (width > child_indent) fail("multiline CompilationDatabase is not supported")
              after_target = 0
            }
            if (width != child_indent) continue
            if (raw !~ /^ +[A-Za-z_][A-Za-z_0-9.-]* *:( |$)/) fail("CompileFlags must contain plain mapping keys")
            if (raw ~ /^ +CompilationDatabase *:( |$)/) {
              if (target) fail("duplicate CompilationDatabase keys")
              target = i
              after_target = 1
            }
          }
          if (target) {
            match(lines[target], /^ +CompilationDatabase *:( |$) */)
            prefix = substr(lines[target], 1, RLENGTH)
            scalar = substr(lines[target], RLENGTH + 1)
            if (substr(prefix, length(prefix), 1) != " ") prefix = prefix " "
            lines[target] = prefix value suffix(scalar)
          }
        }
        for (i = 1; i <= n + 1; i++) {
          if (!block_start && i == insert_at) {
            print "CompileFlags:"
            print "  CompilationDatabase: " value
            if (i <= n) print ""
          }
          if (block_start && !target && i == block_start + 1)
            print sprintf("%*s", child_indent, "") "CompilationDatabase: " value
          if (i <= n) {
            printf "%s", lines[i]
            if (i < n || ENVIRON["CBUILD_CLANGD_NEWLINE"] == "true" ||
                (block_start && !target && i == block_start) ||
                (!block_start && i == insert_at - 1)) printf "\n"
          }
        }
      }
    }
  ' "$input" > "$tmp"; then
    log_warn "Failed to update .clangd; original file preserved"; rm -f "$tmp"; return 0
  fi
  if [[ -e "$path" ]] && cmp -s "$path" "$tmp"; then
    rm -f "$tmp"
  elif ! mv -f "$tmp" "$path"; then
    log_warn "Failed to replace .clangd"; rm -f "$tmp"
  else
    log_info "Updated .clangd CompilationDatabase"
  fi
}

get_exec_path() {
  local target_name="${1:-}"
  local rule bin_dir exe_path

  # 1) Ninja: 解析 build.ninja
  if [[ -f "$BUILD_DIR/build.ninja" ]]; then
    if [[ -n "$target_name" ]]; then
      # 指定了 target_name，优先匹配
      rule="$(grep -Em1 "^build.*:[[:space:]]+(C|CXX)_EXECUTABLE_LINKER__${target_name}[^a-zA-Z]" "$BUILD_DIR/build.ninja" 2>/dev/null || true)"
    else
      # 未指定，查找第一个可执行文件
      rule="$(grep -Em1 "^build.*:[[:space:]]+(C|CXX)_EXECUTABLE_LINKER__" "$BUILD_DIR/build.ninja" 2>/dev/null || true)"
    fi
    if [[ -n "$rule" ]]; then
      rule="${rule#build }"
      exe_path="${rule%%: *}"
      if [[ "$exe_path" == /* ]] || is_windows_abs_path "$exe_path"; then
        normalize_path "$exe_path"
      else
        normalize_path "${BUILD_DIR}/${exe_path}"
      fi
      return
    fi
  fi

  # 2) Unix Makefiles: 解析 link.txt
  local link_file
  for link_file in "$BUILD_DIR"/CMakeFiles/*/link.txt; do
    if [[ -f "$link_file" ]]; then
      # 使用 sed 替代 grep -P，更兼容
      exe_path="$(sed -n 's/.*-o \([^ ]*\).*/\1/p' "$link_file" 2>/dev/null | head -n1 || true)"
      if [[ -n "$exe_path" ]]; then
        # 如果指定了 target_name，检查是否匹配
        if [[ -n "$target_name" ]]; then
          local exe_name
          exe_name="$(basename "$exe_path")"
          if [[ "$exe_name" == "$target_name" ]]; then
            if [[ "$exe_path" == /* ]] || is_windows_abs_path "$exe_path"; then
              normalize_path "$exe_path"
            else
              normalize_path "${BUILD_DIR}/${exe_path}"
            fi
            return
          fi
        else
          # 未指定，返回第一个
          if [[ "$exe_path" == /* ]] || is_windows_abs_path "$exe_path"; then
            normalize_path "$exe_path"
          else
            normalize_path "${BUILD_DIR}/${exe_path}"
          fi
          return
        fi
      fi
    fi
  done

  # 找不到可执行文件，返回空字符串
  printf ''
}

list_execs() {
  local exe_path exe_name
  local -a execs=()

  # 1) Ninja: 解析 build.ninja
  if [[ -f "$BUILD_DIR/build.ninja" ]]; then
    while IFS= read -r rule; do
      if [[ "$rule" =~ ^build.*:[[:space:]]+(C|CXX)_EXECUTABLE_LINKER__ ]]; then
        rule="${rule#build }"
        exe_path="${rule%%: *}"
        exe_name="$(basename "$exe_path")"
        execs+=("$exe_name")
      fi
    done < <(grep -E "^build.*:[[:space:]]+(C|CXX)_EXECUTABLE_LINKER__" "$BUILD_DIR/build.ninja" 2>/dev/null || true)
  fi

  # 2) Unix Makefiles: 解析 link.txt
  for link_file in "$BUILD_DIR"/CMakeFiles/*/link.txt; do
    if [[ -f "$link_file" ]]; then
      exe_path="$(sed -n 's/.*-o \([^ ]*\).*/\1/p' "$link_file" 2>/dev/null | head -n1 || true)"
      if [[ -n "$exe_path" ]]; then
        exe_name="$(basename "$exe_path")"
        # 去重
        local exists="false"
        for e in "${execs[@]}"; do
          if [[ "$e" == "$exe_name" ]]; then
            exists="true"
            break
          fi
        done
        if [[ "$exists" == "false" ]]; then
          execs+=("$exe_name")
        fi
      fi
    fi
  done

  if (( ${#execs[@]} == 0 )); then
    log_warn "No executables found in build directory"
    return 1
  fi

  log_info "Available executables:"
  for exe in "${execs[@]}"; do
    printf '  - %s\n' "$exe"
  done
}

update_vscode_launch() {
  local launch_json rel_path program_path escaped
  launch_json="$SOURCE_DIR/.vscode/launch.json"
  [[ -f "$launch_json" ]] || return 0

  prepare_build_dir false

  local exe_path
  exe_path="$(get_exec_path "$EXEC_NAME")"

  if [[ -z "$exe_path" ]]; then
    log_warn "Cannot find executable path, skipping launch.json update"
    return 0
  fi

  if [[ "$exe_path" == "$SOURCE_DIR/"* ]]; then
    rel_path="${exe_path#"$SOURCE_DIR"/}"
    program_path="\${workspaceFolder}/${rel_path}"
  else
    program_path="${exe_path}"
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
  -t | --type [Debug|Release]    切换编译类型 (Debug/Release)，保存到 cb.conf
                                 / Toggle or set build type, saves to cb.conf
  --conan-profile | --conan-profle  按配置的编译器生成/覆盖 profile / Generate the compiler's profile
  --conan [<type>]               使用 Conan 构建依赖库 / Build Conan dependencies
  -g | --generate [<type>]       运行 CMake 配置 / Run CMake configure only
  -D<name>=<value>               传递 CMake 定义（仅与 -g/--generate 一起使用）
  -D <name>=<value>              Pass a CMake definition (only with -g/--generate)
  -b | --build [<type>] [--target <target>] [target]  构建项目 / Build the project
  -r | --run [<type>] [exe_name] 运行程序 / Run the application
  -c | --clean [<type>]          清理构建目录 / Clean build directory
  --list-execs                   列出所有可执行文件 / List all executables
  -V | --version                 显示版本 / Show version
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
          update_clangd_config
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
        update_clangd_config
        log_info "The build type has been switched to: $BUILD_TYPE"
        type_changed="true"
      fi
      ;;
    --conan-profile|--conan-profle)
      SHOULD_CONAN_PROFILE="true"
      had_action="true"
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
      if (( i + 1 < ${#args[@]} )) && [[ "${args[i+1]}" != -* ]]; then
        type="${args[i+1]^}"
        if is_build_type "$type"; then
          BUILD_TYPE="$type"
          i=$((i + 1))
        fi
      fi
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
      elif (( i + 1 < ${#args[@]} )) && [[ "${args[i+1]}" != -* ]]; then
        BUILD_TARGET="${args[i+1]}"
        i=$((i + 1))
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
      if (( i + 1 < ${#args[@]} )) && [[ "${args[i+1]}" != -* ]]; then
        EXEC_NAME="${args[i+1]}"
        i=$((i + 1))
      fi
      ;;
    --list-execs)
      SHOULD_LIST_EXECS="true"
      had_action="true"
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

gcc_json_path() {
  local value="${1//\\//}"
  value="${value//\"/\\\"}"
  value="${value//$'\t'/\\t}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  printf '%s' "$value"
}

configured_compiler_info() {
  local -x PATH="${CMAKE_RUN_PATH_PREFIX}${CMAKE_RUN_PATH_PREFIX:+:}$PATH"
  local driver base family="" driver_family="" version major=""
  if [[ -z "$CONFIG_COMPILER" ]]; then
    log_err "Set [compiler] compiler before generating a Conan profile"
    return 1
  fi
  for driver in "$C_COMPILER" "$CXX_COMPILER"; do
    base="$(basename "$driver")"
    if [[ ! "$base" =~ ^(.*-)?(gcc|g\+\+|clang|clang\+\+)(-[0-9]+(\.[0-9]+)*)?(\.exe)?$ ]]; then
      log_err "Unsupported compiler for automatic Conan profiles: $CONFIG_COMPILER; set [conan] build/host explicitly"
      return 1
    fi
    case "${BASH_REMATCH[2]}" in
    gcc|g++) driver_family="gcc" ;;
    *) driver_family="clang" ;;
    esac
    if [[ -z "$family" ]]; then
      family="$driver_family"
    elif [[ "$family" != "$driver_family" ]]; then
      log_err "Configured C/C++ drivers mix compiler families: $C_COMPILER vs $CXX_COMPILER"
      return 1
    fi
  done
  for driver in "$C_COMPILER" "$CXX_COMPILER"; do
    if [[ ! -x "$driver" ]] && ! type -P "$driver" >/dev/null 2>&1; then
      log_err "Configured compiler not found: $driver"
      return 1
    fi
    if ! version="$("$driver" -dumpfullversion -dumpversion 2>/dev/null)" || [[ ! "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
      log_err "Cannot detect compiler version: $driver"
      return 1
    fi
    if [[ -n "$major" && "$major" != "${version%%.*}" ]]; then
      log_err "Configured C/C++ compiler versions differ: $major vs ${version%%.*}"
      return 1
    fi
    major="${version%%.*}"
  done
  COMPILER_FAMILY="$family"
  COMPILER_MAJOR="$major"
  COMPILER_EXECUTABLES="{\"c\":\"$(gcc_json_path "$C_COMPILER")\",\"cpp\":\"$(gcc_json_path "$CXX_COMPILER")\"}"
}

compiler_profile_buildenv() {
  local -x PATH="${CMAKE_RUN_PATH_PREFIX}${CMAKE_RUN_PATH_PREFIX:+:}$PATH"
  local directory base prefix="" tool query candidate nearby found
  local -a candidates=()
  directory="$(dirname "$C_COMPILER")"
  base="$(basename "$C_COMPILER")"
  if [[ "$base" =~ ^(.*-)?(gcc|g\+\+|clang|clang\+\+)(-[0-9]+(\.[0-9]+)*)?(\.exe)?$ ]]; then
    prefix="${BASH_REMATCH[1]}"
  fi
  COMPILER_BUILDENV=("CC=${C_COMPILER//\\//}" "CXX=${CXX_COMPILER//\\//}")
  for tool in ar as ld nm ranlib strip objcopy objdump; do
    query="$("$C_COMPILER" "-print-prog-name=$tool" 2>/dev/null || true)"
    candidates=()
    if [[ -n "$query" && ( "$query" != "$tool" || -z "$prefix" ) ]]; then
      candidates+=("$query")
    fi
    candidates+=("${prefix}${tool}")
    found=""
    for candidate in "${candidates[@]}"; do
      nearby="$candidate"
      if [[ "$candidate" != /* ]] && ! is_windows_abs_path "$candidate"; then
        nearby="$directory/$candidate"
      fi
      if [[ -x "$nearby" && ! -d "$nearby" ]]; then
        found="$(normalize_path "$nearby")"
        break
      fi
      if [[ "$candidate" != *'/'* && "$candidate" != *'\\'* ]]; then
        found="$(type -P "$candidate" || true)"
        [[ -z "$found" ]] || break
      fi
    done
    if [[ -n "$found" ]]; then
      COMPILER_BUILDENV+=("${tool^^}=${found//\\//}")
    else
      log_warn "Toolchain tool not found, omitted from profile: ${tool^^}"
    fi
  done
  COMPILER_SYSROOT="$("$C_COMPILER" -print-sysroot 2>/dev/null || true)"
  if [[ -n "$COMPILER_SYSROOT" ]]; then
    if [[ "$COMPILER_SYSROOT" != /* ]] && ! is_windows_abs_path "$COMPILER_SYSROOT"; then
      COMPILER_SYSROOT="$directory/$COMPILER_SYSROOT"
    fi
    COMPILER_SYSROOT="$(normalize_path "$COMPILER_SYSROOT")"
    if [[ ! -d "$COMPILER_SYSROOT" ]]; then
      log_err "Compiler sysroot directory not found: $COMPILER_SYSROOT"
      return 1
    fi
    COMPILER_BUILDENV+=("SYSROOT=${COMPILER_SYSROOT//\\//}")
  fi
}

compiler_profile_name() {
  local value name
  value="$(trim "$CONFIG_COMPILER")"
  [[ -n "$value" ]] || return 0
  name="$(basename "${value//\\//}")"
  name="${name%.[eE][xX][eE]}"
  if [[ ! "$name" =~ ^[A-Za-z0-9_.+-]+$ ]]; then
    log_err "Cannot derive a Conan profile name from [compiler] compiler = $value; set [conan] build/host explicitly"
    return 1
  fi
  printf '%s' "$name"
}

profile_matches_compiler() {
  local name="$1" family="$2" major="$3" output line in_settings="false" seen="false" compiler="" version=""
  output="$(conan profile show -pr:b "$name" -pr:h "$name" 2>/dev/null)" || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "${line%$'\r'}")"
    if [[ "$line" == '[settings]' ]]; then
      [[ "$seen" == "false" ]] || break
      seen="true"
      in_settings="true"
    elif [[ "$line" == '['* ]]; then
      in_settings="false"
    elif [[ "$in_settings" == "true" ]]; then
      case "$line" in
      compiler=*) compiler="$(trim "${line#*=}")" ;;
      compiler.version=*) version="$(trim "${line#*=}")" ;;
      esac
    fi
  done <<< "$output"
  [[ "$compiler" == "$family" && "${version%%.*}" == "$major" ]]
}

generate_conan_profile() {
  configured_compiler_info || return 1
  local name="" build host path line entry directory cpp_directory separator=":"
  build="$(trim "$CONAN_BUILD")"
  host="$(trim "$CONAN_HOST")"
  name="$host"
  [[ -n "$name" ]] || name="$build"
  [[ -n "$name" ]] || name="$(compiler_profile_name)" || return 1
  if [[ ! "$name" =~ ^[A-Za-z0-9_.+-]+$ ]]; then
    log_err "Profile name may only contain letters, digits, '.', '_', '+' or '-'"
    return 1
  fi
  compiler_profile_buildenv || return 1
  CC="$C_COMPILER" CXX="$CXX_COMPILER" PATH="${CMAKE_RUN_PATH_PREFIX}${CMAKE_RUN_PATH_PREFIX:+:}$PATH" \
    conan profile detect --name "$name" --force
  path="$(conan profile path "$name")"
  if ! profile_matches_compiler "$name" "$COMPILER_FAMILY" "$COMPILER_MAJOR"; then
    log_err "Detected profile $name does not match $COMPILER_FAMILY $COMPILER_MAJOR; inspect $path"
    return 1
  fi
  directory="$(dirname "$C_COMPILER")"
  cpp_directory="$(dirname "$CXX_COMPILER")"
  [[ "$OS_TYPE" != "windows" ]] || separator=";"
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      printf '%s\n' "$line"
    done < "$path"
    printf '\n[buildenv]\n'
    for entry in "${COMPILER_BUILDENV[@]}"; do
      printf '%s\n' "$entry"
    done
    printf 'PATH=+(path)%s' "${directory//\\//}"
    [[ "$cpp_directory" == "$directory" ]] || printf '%s%s' "$separator" "${cpp_directory//\\//}"
    printf '\n'
    if [[ -n "$COMPILER_SYSROOT" ]]; then
      printf '\n[conf]\ntools.build:sysroot=%s\n' "${COMPILER_SYSROOT//\\//}"
    fi
  } > "$path.tmp"
  mv "$path.tmp" "$path"
  log_info "Generated Conan profile: $name ($path)"
  log_info "Profile settings retain Conan's detected defaults; review os/arch/ABI and build/host profiles for cross compilation"
  if [[ -n "$build" && "$build" != "$name" ]]; then
    log_info "Build profile left unchanged: $build"
  fi
}

prepare_conan_profiles() {
  [[ "$CONAN_ENABLE" == "true" ]] || return 0
  [[ -f "$SOURCE_DIR/conanfile.txt" || -f "$SOURCE_DIR/conanfile.py" ]] || return 0
  local build host auto_build="false" auto_host="false" executables="" selected=""
  build="$(trim "$CONAN_BUILD")"
  host="$(trim "$CONAN_HOST")"
  [[ -n "$build" ]] || auto_build="true"
  [[ -n "$host" ]] || auto_host="true"
  if [[ -n "$CONFIG_COMPILER" ]]; then
    configured_compiler_info || return 1
    executables="$COMPILER_EXECUTABLES"
    if [[ "$auto_build" == "true" || "$auto_host" == "true" ]]; then
      selected="$host"
      [[ -n "$selected" ]] || selected="$build"
      [[ -n "$selected" ]] || selected="$(compiler_profile_name)" || return 1
      log_info "Conan profile selection: $selected ([compiler] compiler = $CONFIG_COMPILER, $COMPILER_FAMILY $COMPILER_MAJOR)"
      [[ -n "$build" ]] || build="$selected"
      [[ -n "$host" ]] || host="$selected"
    fi
    # Explicit names are checked the same way: existence plus compiler family and major version.
    local context profile name_list
    name_list="$(conan profile list | tr -d '\r')"
    for context in build host; do
      profile="${!context}"
      [[ -n "$profile" ]] || continue
      if ! grep -Fxq -- "$profile" <<< "$name_list"; then
        log_err "No Conan profile named $profile for $context; run --conan-profile first or set [conan] build/host"
        return 1
      fi
      if ! profile_matches_compiler "$profile" "$COMPILER_FAMILY" "$COMPILER_MAJOR"; then
        log_err "Conan profile $profile does not match $COMPILER_FAMILY $COMPILER_MAJOR or cannot be loaded; run --conan-profile to regenerate it"
        return 1
      fi
    done
  fi
  CONAN_PROFILE_ARGS=()
  [[ -z "$build" ]] || CONAN_PROFILE_ARGS+=(--profile:build "$build")
  [[ -z "$host" ]] || CONAN_PROFILE_ARGS+=(--profile:host "$host")
  log_info "Conan config: $CONFIG_FILE (script: $SCRIPT_DIR/cb.sh)"
  local profile_output build_source="configured" host_source="configured"
  if ! profile_output="$(conan profile show "${CONAN_PROFILE_ARGS[@]}" 2>&1)"; then
    log_err "$profile_output"
    return 1
  fi
  if [[ "$auto_build" == "true" ]]; then
    build_source="default"
    [[ -z "$build" ]] || build_source="auto"
  fi
  if [[ "$auto_host" == "true" ]]; then
    host_source="default"
    [[ -z "$host" ]] || host_source="auto"
  fi
  log_info "Conan profiles: build=${build:-default}, host=${host:-default}"
  log_info "Conan profile sources: build=$build_source, host=$host_source"
}

run_conan_install() {
  local conan_enabled="$CONAN_ENABLE"
  local conan_file_txt conan_file_py
  local cmd=() line key value

  [[ "$conan_enabled" == "true" ]] || return 0

  conan_file_txt="$SOURCE_DIR/conanfile.txt"
  conan_file_py="$SOURCE_DIR/conanfile.py"
  if [[ ! -f "$conan_file_txt" && ! -f "$conan_file_py" ]]; then
    return 0
  fi

  cmd=(conan install "$SOURCE_DIR" -s "build_type=$BUILD_TYPE" --output-folder "$BUILD_DIR" --build=missing)

  cmd+=("${CONAN_PROFILE_ARGS[@]}")

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
    PATH="${CMAKE_RUN_PATH_PREFIX}${CMAKE_RUN_PATH_PREFIX:+:}$PATH" "${cmd[@]}"
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

reset_cmake_cache_for_toolchain_change() {
  local cache_file="${BUILD_DIR}/CMakeCache.txt"
  local cache_line=""
  local cached_toolchain=""
  local desired_toolchain="${CMAKE_TOOLCHAIN_FILE:-}"
  local reset_required="false"

  [[ -f "$cache_file" ]] || return 0
  cache_line="$(grep -m1 '^CMAKE_TOOLCHAIN_FILE:[^=]*=' "$cache_file" || true)"

  if [[ -z "$cache_line" ]]; then
    [[ -n "$desired_toolchain" ]] && reset_required="true"
  elif [[ "$cache_line" == CMAKE_TOOLCHAIN_FILE:UNINITIALIZED=* ]]; then
    # CMake records a newly supplied toolchain this way when a previous cache
    # prevented it from being loaded during the initial configuration.
    reset_required="true"
  else
    cached_toolchain="${cache_line#*=}"
    cached_toolchain="$(cmake_path "$cached_toolchain")"
    [[ "$cached_toolchain" != "$desired_toolchain" ]] && reset_required="true"
  fi

  [[ "$reset_required" == "true" ]] || return 0

  log_info "Resetting stale CMake cache so the current toolchain can be loaded"
  rm -f "$cache_file"
  rm -rf "${BUILD_DIR}/CMakeFiles"
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
  reset_cmake_cache_for_toolchain_change
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
  local exe_path
  exe_path="$(get_exec_path "$EXEC_NAME")"

  if [[ -z "$exe_path" ]]; then
    log_err "Cannot find executable path from build files. Please run 'cb.sh -g' to configure and 'cb.sh -b' to build first."
    exit 1
  fi

  if [[ "$OS_TYPE" == "windows" && "$exe_path" != *.exe ]]; then
    exe_path="${exe_path}.exe"
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
    local source_real build_real
    source_real="$(cd "$SOURCE_DIR" && pwd -P)"
    build_real="$(cd "$BUILD_DIR" && pwd -P)"
    if [[ "$source_real" == "$build_real" || "$source_real" == "${build_real%/}/"* ]]; then
      log_err "Refusing to clean source directory or its ancestor: $BUILD_DIR"
      return 1
    fi
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
  if (($# == 0)); then
    printf 'Use -h for help.\n'
    exit 0
  fi

  local arg
  for arg in "$@"; do
    case "$arg" in
    -V|--version) printf 'cbuild %s\n' "$CBUILD_VERSION"; exit 0 ;;
    -h|--help) print_help; exit 0 ;;
    esac
  done

  load_config
  GENERATOR="$(resolve_generator "$GENERATOR")"
  set_parallel_jobs
  prepare_cmake_compiler_env
  COMPILER_TYPE="$(get_compiler_type)"

  parse_args "$@"

  if [[ "$EXIT_AFTER_TYPE_CHANGE" == "true" ]]; then
    exit 0
  fi

  if [[ "$SHOULD_CONAN_PROFILE" == "true" ]]; then
    if [[ "$SHOULD_CONAN_BUILD" == "true" || "$SHOULD_CONFIGURE" == "true" || "$SHOULD_BUILD" == "true" || "$SHOULD_RUN" == "true" || "$SHOULD_CLEAN" == "true" || "$SHOULD_LIST_EXECS" == "true" ]]; then
      log_err "--conan-profile must be used without other actions"
      exit 1
    fi
    generate_conan_profile
    exit 0
  fi
  if [[ "$SHOULD_CONAN_BUILD" == "true" ]]; then
    prepare_conan_profiles
  fi
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
    update_clangd_config
    exit 0
  fi

  if [[ "$SHOULD_BUILD" == "true" ]]; then
    if [[ ! -f "$BUILD_DIR/CMakeCache.txt" ]]; then
      log_err "Build directory is not configured: $BUILD_DIR; run -g/--generate first"
      exit 1
    fi
    run_cmake_build

    local exe_path
    exe_path="$(get_exec_path "$EXEC_NAME")"

    # Library/custom targets need not produce an executable. Only -r
    # requires one; optional editor updates must not invalidate a build.
    if [[ -n "$exe_path" ]]; then
      if [[ "$OS_TYPE" == "windows" && "$exe_path" != *.exe ]]; then
        exe_path="${exe_path}.exe"
      fi
      if [[ -f "$exe_path" ]]; then
        if has_vscode_launch; then
          update_vscode_launch
        fi
        log_info "exec: $exe_path"
      fi
    fi
    update_cpp_properties
    update_clangd_config
    exit 0
  fi

  if [[ "$SHOULD_RUN" == "true" ]]; then
    run_application
    exit 0
  fi

  if [[ "$SHOULD_LIST_EXECS" == "true" ]]; then
    list_execs
    exit 0
  fi

  printf 'Use -h for help.\n'
}

main "$@"
