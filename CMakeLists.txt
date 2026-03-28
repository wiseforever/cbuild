cmake_minimum_required(VERSION 3.16)

# include ez_custom_func.cmake
if(EXISTS "cmake/ez_custom_func.cmake")
    include("cmake/ez_custom_func.cmake")
endif()

if(USER_COMPILER_TYPE)
    message(STATUS "USER_COMPILER_TYPE: " ${USER_COMPILER_TYPE})
endif()


# Setup compiler settings
set(CMAKE_C_STANDARD 11)                # 设置C语言标准
set(CMAKE_C_STANDARD_REQUIRED ON)       # 是否强制遵循C语言标准
set(CMAKE_C_EXTENSIONS OFF)             # 是否使用C语言扩展

set(CMAKE_CXX_STANDARD 11)              # 设置C++语言标准
set(CMAKE_CXX_STANDARD_REQUIRED ON)     # 是否强制遵循C++语言标准
set(CMAKE_CXX_EXTENSIONS OFF)           # 是否C++语言扩展

# Enable compile command to ease indexing with e.g. clangd (compile_commands.json)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)   # 是否生成编译命令文件 compile_commands.json

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin) # 可执行文件输出目录
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin) # 动态库输出目录
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/static_lib) # 静态库输出目录
# 如果需要，可以单独为 Debug/Release 设置 (MSVC需要这里设置)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_DEBUG ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON) # 导出所有符号
add_compile_options("$<$<C_COMPILER_ID:MSVC>:/utf-8>")
add_compile_options("$<$<CXX_COMPILER_ID:MSVC>:/utf-8>")


# Core project settings
set(APP_NAME "application")
project(${APP_NAME} VERSION 0.1 LANGUAGES C CXX ASM)

# set(CMAKE_PREFIX_PATH ${XXX})


# Define the build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Debug")
endif()

# 将项目根目录转换为 CMake 标准路径格式（跨平台兼容）
# 定义一个宏 SOURCE_DIR，值为项目根目录（注意：末尾显式添加分隔符）
file(TO_CMAKE_PATH "${CMAKE_SOURCE_DIR}" PROJECT_ROOT_DIR)
add_definitions(-DSOURCE_DIR="${PROJECT_ROOT_DIR}")

if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /EHsc")  # 启用异常处理
    # CMAKE_BUILD_TYPE 匹配不区分大小写 cmake内部做了特殊处理
    if(CMAKE_BUILD_TYPE MATCHES "^[Dd][Ee][Bb][Uu][Gg]$") # Debug
        message(STATUS "Debug build")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /Od")  # 禁用优化
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /Zi")  # 启用调试信息

    elseif(CMAKE_BUILD_TYPE MATCHES "^[Rr][Ee][Ll][Ee][Aa][Ss][Ee]$") # Release
        message(STATUS "Release build")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /O2")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /DNDEBUG")

    endif()

elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    # add_compile_options(-fmacro-prefix-map=${CMAKE_SOURCE_DIR}=.)
    # add_definitions(-DUSE_MACRO_PREFIX_MAP)

    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wl,-Map=${PROJECT_NAME}.map")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wl,-Map=${PROJECT_NAME}.map")

    # CMAKE_BUILD_TYPE 匹配不区分大小写 cmake内部做了特殊处理
    if(CMAKE_BUILD_TYPE MATCHES "^[Dd][Ee][Bb][Uu][Gg]$") # Debug
        message(STATUS "Debug build")
        set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O0 -g3")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O0 -g3")
    elseif(CMAKE_BUILD_TYPE MATCHES "^[Rr][Ee][Ll][Ee][Aa][Ss][Ee]$") # Release
        message(STATUS "Release build")
        set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O2 -g0")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O2 -g0")
        # set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O2 -g")
        # set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O2 -g")
    endif()
endif()

message(STATUS " ")
message(STATUS "Start configuration project.")
message(STATUS " ")

# # vcpkg 配置
# set(CMAKE_TOOLCHAIN_FILE "D:/cppsoft/vcpkg/scripts/buildsystems/vcpkg.cmake")
# set(VCPKG_HOST_TRIPLET x64-mingw-static)
# set(VCPKG_TARGET_TRIPLET x64-mingw-static)
# find_package(httplib CONFIG REQUIRED)

set(TOML_FILE "config.toml")
if(EXISTS "${CMAKE_SOURCE_DIR}/${TOML_FILE}")
    file(COPY ${CMAKE_SOURCE_DIR}/${TOML_FILE} DESTINATION ${CMAKE_BINARY_DIR}/bin)
else()
    if(EXISTS "${CMAKE_BINARY_DIR}/bin/${TOML_FILE}")
        file(REMOVE ${CMAKE_BINARY_DIR}/bin/${TOML_FILE})
    endif()
endif()

set(INI_FILE "config.ini")
if(EXISTS "${CMAKE_SOURCE_DIR}/${INI_FILE}")
    file(COPY ${CMAKE_SOURCE_DIR}/${INI_FILE} DESTINATION ${CMAKE_BINARY_DIR}/bin)
else()
    if(EXISTS "${CMAKE_BINARY_DIR}/bin/${INI_FILE}")
        file(REMOVE ${CMAKE_BINARY_DIR}/bin/${INI_FILE})
    endif()
endif()

file(GLOB src_files 
    "./*.c" "./*.cpp"
    "./src/*.c" ".//src/*.cpp"
    "utils/*.c" "utils/*.cpp"
    "modbus/*.c"
)
include_directories(
    ${CMAKE_SOURCE_DIR}/src
    ${CMAKE_SOURCE_DIR}/utils
    ${CMAKE_SOURCE_DIR}/modbus
)




# Create an executable object type
add_executable(${PROJECT_NAME}
    ${src_files}
)

if(WIN32)
    add_definitions(-D_WIN32_WINNT=0x0601 -DWIN32_LEAN_AND_MEAN)

    if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")

    elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        # set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,--verbose")
        # add_link_options(-static-libgcc -static-libstdc++)
        set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -static-libgcc -static-libstdc++")

    endif()

elseif(APPLE)

elseif(UNIX)
    # set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,--verbose")
    # add_link_options(-static-libgcc -static-libstdc++)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -static-libgcc -static-libstdc++")

endif()


# # Add subdirectories
# add_subdirectory(app)
# add_subdirectory(third-party)

# # Add linked libraries
# target_link_libraries(${PROJECT_NAME}
#     PRIVATE
#     app
#     third-party
# )


# # ======== Boost 库配置 ========
# add_definitions("-DBOOST_ALLOW_DEPRECATED_HEADERS")
# add_definitions("-DBOOST_BIND_GLOBAL_PLACEHOLDERS")

# if(POLICY CMP0144)
#     cmake_policy(SET CMP0144 NEW)
# endif()
# if(POLICY CMP0167)
#     cmake_policy(SET CMP0167 NEW)
# endif()

# # 强制使用静态库
# set(Boost_USE_STATIC_LIBS ON)
# # 禁用静态运行时（避免与编译器冲突）
# set(Boost_USE_STATIC_RUNTIME OFF)

find_package(Boost REQUIRED COMPONENTS)
if(Boost_FOUND)
    message(STATUS "Boost version: ${Boost_VERSION}")
    # message(STATUS "Boost include dir: ${Boost_INCLUDE_DIRS}")
    # message(STATUS "Boost libraries: ${Boost_LIBRARIES}")

    include_directories(
        ${Boost_INCLUDE_DIRS}
    )
else()
    message(FATAL_ERROR "Boost not found")
endif()

# # Add linked libraries
# target_link_libraries(${PROJECT_NAME}
#     PRIVATE
#     Boost::thread       # 对应 boost_thread
#     Boost::context      # 对应 boost_context
#     # Boost::filesystem   # 对应 boost_filesystem
#     # Boost::coroutine    # 对应 boost_coroutine
#     # Boost::date_time    # 对应 boost_date_time
#     # Boost::locale       # 对应 boost_locale
#     # Boost::log_setup    # 对应 libboost_log_setup.a
#     # Boost::log          # 对应 libboost_log.a
# )


include_directories(
    ${CMAKE_SOURCE_DIR}/third-party/toml11/include
)



# set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-rpath='$ORIGIN:$ORIGIN/depend'")

set(CMAKE_SKIP_BUILD_RPATH FALSE)
set_target_properties(${PROJECT_NAME} PROPERTIES
    BUILD_RPATH ""
    INSTALL_RPATH "$ORIGIN;$ORIGIN/depend"
    BUILD_WITH_INSTALL_RPATH TRUE
)

# 检查 readelf -d ./application | grep -i RUNPATH

if(WIN32)
    target_link_libraries(${PROJECT_NAME}
        PRIVATE
        ws2_32
    )
elseif(UNIX)
    target_link_libraries(${PROJECT_NAME}
        PRIVATE
        pthread
        dl
        icuuc
    )

endif()

# set(CMAKE_SKIP_BUILD_RPATH FALSE)
# set_target_properties(${PROJECT_NAME} PROPERTIES
#     BUILD_RPATH ""
#     INSTALL_RPATH "$ORIGIN;$ORIGIN/depend"
#     BUILD_WITH_INSTALL_RPATH TRUE
# )

# Linux 下，系统的动态库搜索还会受 /etc/ld.so.conf 和 /etc/ld.so.conf.d/ 影响
# cat /etc/ld.so.conf 如果内容为 include /etc/ld.so.conf.d/*.conf
# 则 ls/etc/ld.so.conf.d  cat /etc/ld.so.conf.d/*.conf 显示动态库搜索路径
