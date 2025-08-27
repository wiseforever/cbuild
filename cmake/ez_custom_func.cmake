

# 不递归添加源文件
function(ez_set_src SOURCES_VAR)
    # 检查参数数量是否足够
    if(NOT SOURCES_VAR)
        message(FATAL_ERROR "ez_set_src requires at least 1 arguments: SOURCES_VAR.")
    endif()

    # 使用传入的 COMPILE_DIRS 变量，如果没有指定则使用当前目录
    if(ARGN STREQUAL "")
        set(COMPILE_DIRS "")
    else()
        set(COMPILE_DIRS ${ARGN})
    endif()

    # 临时变量（仅限此函数作用域）
    set(SOURCES_LOCAL "")

    foreach(dir IN LISTS COMPILE_DIRS)
        file(GLOB temp_sources
            ${dir}/*.c
            ${dir}/*.cc
            ${dir}/*.cpp
            ${dir}/*.s
            ${dir}/*.S
        )
        list(APPEND SOURCES_LOCAL ${temp_sources})
    endforeach()

    # 去重
    list(REMOVE_DUPLICATES SOURCES_LOCAL)

    # 设置输出变量到调用者作用域
    set(${SOURCES_VAR} ${SOURCES_LOCAL} PARENT_SCOPE)

endfunction()

# 递归添加源文件
function(ez_set_src_recurse SOURCES_VAR)
    # 检查参数数量是否足够
    if(NOT SOURCES_VAR)
        message(FATAL_ERROR "ez_set_src_recurse requires at least 1 arguments: SOURCES_VAR.")
    endif()

    # 使用传入的 COMPILE_DIRS 变量，如果没有指定则使用当前目录
    if(ARGN STREQUAL "")
        set(COMPILE_DIRS "")
    else()
        set(COMPILE_DIRS ${ARGN})
    endif()

    # 临时变量（仅限此函数作用域）
    set(SOURCES_LOCAL "")

    foreach(dir IN LISTS COMPILE_DIRS)
        file(GLOB_RECURSE temp_sources
            ${dir}/*.c
            ${dir}/*.cc
            ${dir}/*.cpp
            ${dir}/*.s
            ${dir}/*.S
        )
        list(APPEND SOURCES_LOCAL ${temp_sources})
    endforeach()

    # 去重
    list(REMOVE_DUPLICATES SOURCES_LOCAL)

    # 设置输出变量到调用者作用域
    set(${SOURCES_VAR} ${SOURCES_LOCAL} PARENT_SCOPE)

endfunction()











# 不递归添加头文件
function(ez_set_head_file HEADER_FILES_VAR)
    # 检查参数数量是否足够
    if(NOT HEADER_FILES_VAR)
        message(FATAL_ERROR "ez_set_head_file requires at least 1 arguments: HEADER_FILES_VAR.")
    endif()

    # 使用传入的 COMPILE_DIRS 变量，如果没有指定则使用当前目录
    if(ARGN STREQUAL "")
        set(COMPILE_DIRS "")
    else()
        set(COMPILE_DIRS ${ARGN})
    endif()

    # 临时变量（仅限此函数作用域）
    set(HEADER_FILES_LOCAL "")

    foreach(dir IN LISTS COMPILE_DIRS)
        file(GLOB temp_headers
            ${dir}/*.h
            ${dir}/*.hpp
            ${dir}/*.hxx
        )
        list(APPEND HEADER_FILES_LOCAL ${temp_headers})
    endforeach()

    # 去重
    list(REMOVE_DUPLICATES HEADER_FILES_LOCAL)

    # 设置输出变量到调用者作用域
    set(${HEADER_FILES_VAR} ${HEADER_FILES_LOCAL} PARENT_SCOPE)

endfunction()

# 递归添加头文件
function(ez_set_head_file_recurse HEADER_FILES_VAR)
    # 检查参数数量是否足够
    if(NOT HEADER_FILES_VAR)
        message(FATAL_ERROR "ez_set_head_file_recurse requires at least 1 arguments: HEADER_FILES_VAR.")
    endif()

    # 使用传入的 COMPILE_DIRS 变量，如果没有指定则使用当前目录
    if(ARGN STREQUAL "")
        set(COMPILE_DIRS "")
    else()
        set(COMPILE_DIRS ${ARGN})
    endif()

    # 临时变量（仅限此函数作用域）
    set(HEADER_FILES_LOCAL "")

    foreach(dir IN LISTS COMPILE_DIRS)
        file(GLOB_RECURSE temp_headers
            ${dir}/*.h
            ${dir}/*.hpp
            ${dir}/*.hxx
        )
        list(APPEND HEADER_FILES_LOCAL ${temp_headers})
    endforeach()

    # 去重
    list(REMOVE_DUPLICATES HEADER_FILES_LOCAL)

    # 设置输出变量到调用者作用域
    set(${HEADER_FILES_VAR} ${HEADER_FILES_LOCAL} PARENT_SCOPE)

endfunction()







# 不递归添加头文件目录
function(ez_set_head_dir HEADER_DIRS_VAR)
    # 检查参数数量是否足够
    if(NOT HEADER_DIRS_VAR)
        message(FATAL_ERROR "ez_set_head_dir requires at least 1 arguments: HEADER_DIRS_VAR.")
    endif()

    # 使用传入的 COMPILE_DIRS 变量，如果没有指定则使用当前目录
    if(ARGN STREQUAL "")
        set(COMPILE_DIRS "")
    else()
        set(COMPILE_DIRS ${ARGN})
    endif()

    # 临时变量（仅限此函数作用域）
    set(HEADER_DIRS_LOCAL "")

    foreach(dir IN LISTS COMPILE_DIRS)
        file(GLOB temp_headers
            ${dir}/*.h
            ${dir}/*.hpp
            ${dir}/*.hxx
        )
        foreach(header_file IN LISTS temp_headers)
            get_filename_component(header_dir ${header_file} DIRECTORY)
            list(APPEND HEADER_DIRS_LOCAL ${header_dir})
        endforeach()
    endforeach()

    # 去重
    list(REMOVE_DUPLICATES HEADER_DIRS_LOCAL)

    # 设置输出变量到调用者作用域
    set(${HEADER_DIRS_VAR} ${HEADER_DIRS_LOCAL} PARENT_SCOPE)

endfunction()

# 递归添加头文件目录
function(ez_set_head_dir_recurse HEADER_DIRS_VAR)
    # 检查参数数量是否足够
    if(NOT HEADER_DIRS_VAR)
        message(FATAL_ERROR "ez_set_head_dir_recurse requires at least 1 arguments: HEADER_DIRS_VAR.")
    endif()

    # 使用传入的 COMPILE_DIRS 变量，如果没有指定则使用当前目录
    if(ARGN STREQUAL "")
        set(COMPILE_DIRS "")
    else()
        set(COMPILE_DIRS ${ARGN})
    endif()

    # 临时变量（仅限此函数作用域）
    set(HEADER_DIRS_LOCAL "")

    foreach(dir IN LISTS COMPILE_DIRS)
        file(GLOB_RECURSE temp_headers
            ${dir}/*.h
            ${dir}/*.hpp
            ${dir}/*.hxx
        )
        foreach(header_file IN LISTS temp_headers)
            get_filename_component(header_dir ${header_file} DIRECTORY)
            list(APPEND HEADER_DIRS_LOCAL ${header_dir})
        endforeach()
    endforeach()

    # 去重
    list(REMOVE_DUPLICATES HEADER_DIRS_LOCAL)

    # 设置输出变量到调用者作用域
    set(${HEADER_DIRS_VAR} ${HEADER_DIRS_LOCAL} PARENT_SCOPE)

endfunction()











# 不递归添加源文件与头文件
function(ez_set_src_and_head_file SOURCES_VAR HEADER_FILES_VAR)
    # 检查参数数量是否足够
    if(NOT SOURCES_VAR OR NOT HEADER_FILES_VAR)
        message(FATAL_ERROR "ez_set_src_and_head_file requires at least 2 arguments: SOURCES_VAR, and HEADER_FILES_VAR.")
    endif()

    # 使用传入的 COMPILE_DIRS 变量，如果没有指定则使用当前目录
    if(ARGN STREQUAL "")
        set(COMPILE_DIRS "")
    else()
        set(COMPILE_DIRS ${ARGN})
    endif()

    # 临时变量（仅限此函数作用域）
    set(SOURCES_LOCAL "")
    set(HEADER_FILES_LOCAL "")

    foreach(dir IN LISTS COMPILE_DIRS)
        file(GLOB temp_sources
            ${dir}/*.c
            ${dir}/*.cc
            ${dir}/*.cpp
            ${dir}/*.s
            ${dir}/*.S
        )
        list(APPEND SOURCES_LOCAL ${temp_sources})

        file(GLOB temp_headers
            ${dir}/*.h
            ${dir}/*.hpp
            ${dir}/*.hxx
        )
        list(APPEND HEADER_FILES_LOCAL ${temp_headers})
    endforeach()

    # 去重
    list(REMOVE_DUPLICATES SOURCES_LOCAL)
    list(REMOVE_DUPLICATES HEADER_FILES_LOCAL)

    # 设置输出变量到调用者作用域
    set(${SOURCES_VAR} ${SOURCES_LOCAL} PARENT_SCOPE)
    set(${HEADER_FILES_VAR} ${HEADER_FILES_LOCAL} PARENT_SCOPE)

endfunction()

# 递归添加源文件与头文件
function(ez_set_src_and_head_file_recurse SOURCES_VAR HEADER_FILES_VAR)
    # 检查参数数量是否足够
    if(NOT SOURCES_VAR OR NOT HEADER_FILES_VAR)
        message(FATAL_ERROR "ez_set_src_and_head_file_recurse requires at least 2 arguments: SOURCES_VAR, and HEADER_FILES_VAR.")
    endif()

    # 使用传入的 COMPILE_DIRS 变量，如果没有指定则使用当前目录
    if(ARGN STREQUAL "")
        set(COMPILE_DIRS "")
    else()
        set(COMPILE_DIRS ${ARGN})
    endif()

    # 临时变量（仅限此函数作用域）
    set(SOURCES_LOCAL "")
    set(HEADER_FILES_LOCAL "")

    foreach(dir IN LISTS COMPILE_DIRS)
        file(GLOB_RECURSE temp_sources
            ${dir}/*.c
            ${dir}/*.cc
            ${dir}/*.cpp
            ${dir}/*.s
            ${dir}/*.S
        )
        list(APPEND SOURCES_LOCAL ${temp_sources})

        file(GLOB_RECURSE temp_headers
            ${dir}/*.h
            ${dir}/*.hpp
            ${dir}/*.hxx
        )
        list(APPEND HEADER_FILES_LOCAL ${temp_headers})
    endforeach()

    # 去重
    list(REMOVE_DUPLICATES SOURCES_LOCAL)
    list(REMOVE_DUPLICATES HEADER_FILES_LOCAL)

    # 设置输出变量到调用者作用域
    set(${SOURCES_VAR} ${SOURCES_LOCAL} PARENT_SCOPE)
    set(${HEADER_FILES_VAR} ${HEADER_FILES_LOCAL} PARENT_SCOPE)

endfunction()









# 不递归添加源文件与头文件目录
function(ez_set_src_and_head_dir SOURCES_VAR HEADER_DIRS_VAR)
    # 检查参数数量是否足够
    if(NOT SOURCES_VAR OR NOT HEADER_DIRS_VAR)
        message(FATAL_ERROR "ez_set_src_and_head_dir requires at least 2 arguments: SOURCES_VAR, and HEADER_DIRS_VAR.")
    endif()

    # 使用传入的 COMPILE_DIRS 变量，如果没有指定则使用当前目录
    if(ARGN STREQUAL "")
        set(COMPILE_DIRS "")
    else()
        set(COMPILE_DIRS ${ARGN})
    endif()

    # 临时变量（仅限此函数作用域）
    set(SOURCES_LOCAL "")
    set(HEADER_DIRS_LOCAL "")

    foreach(dir IN LISTS COMPILE_DIRS)
        file(GLOB temp_sources
            ${dir}/*.c 
            ${dir}/*.cc 
            ${dir}/*.cpp 
            ${dir}/*.s 
            ${dir}/*.S
        )
        list(APPEND SOURCES_LOCAL ${temp_sources})

        file(GLOB temp_headers
            ${dir}/*.h 
            ${dir}/*.hpp 
            ${dir}/*.hxx
        )
        foreach(header_file IN LISTS temp_headers)
            get_filename_component(header_dir ${header_file} DIRECTORY)
            list(APPEND HEADER_DIRS_LOCAL ${header_dir})
        endforeach()
    endforeach()

    # 去重
    list(REMOVE_DUPLICATES SOURCES_LOCAL)
    list(REMOVE_DUPLICATES HEADER_DIRS_LOCAL)

    # 设置输出变量到调用者作用域
    set(${SOURCES_VAR} ${SOURCES_LOCAL} PARENT_SCOPE)
    set(${HEADER_DIRS_VAR} ${HEADER_DIRS_LOCAL} PARENT_SCOPE)

endfunction()

# 递归添加源文件与头文件目录
function(ez_set_src_and_head_dir_recurse SOURCES_VAR HEADER_DIRS_VAR)
    # 检查参数数量是否足够
    if(NOT SOURCES_VAR OR NOT HEADER_DIRS_VAR)
        message(FATAL_ERROR "ez_set_src_and_head_dir_recurse requires at least 2 arguments: SOURCES_VAR, and HEADER_DIRS_VAR.")
    endif()

    # 使用传入的 COMPILE_DIRS 变量，如果没有指定则使用当前目录
    if(ARGN STREQUAL "")
        set(COMPILE_DIRS "")
    else()
        set(COMPILE_DIRS ${ARGN})
    endif()

    # 临时变量（仅限此函数作用域）
    set(SOURCES_LOCAL "")
    set(HEADER_DIRS_LOCAL "")

    foreach(dir IN LISTS COMPILE_DIRS)
        file(GLOB_RECURSE temp_sources
            ${dir}/*.c 
            ${dir}/*.cc 
            ${dir}/*.cpp 
            ${dir}/*.s 
            ${dir}/*.S
        )
        list(APPEND SOURCES_LOCAL ${temp_sources})

        file(GLOB_RECURSE temp_headers
            ${dir}/*.h 
            ${dir}/*.hpp 
            ${dir}/*.hxx
        )
        foreach(header_file IN LISTS temp_headers)
            get_filename_component(header_dir ${header_file} DIRECTORY)
            list(APPEND HEADER_DIRS_LOCAL ${header_dir})
        endforeach()
    endforeach()

    # 去重
    list(REMOVE_DUPLICATES SOURCES_LOCAL)
    list(REMOVE_DUPLICATES HEADER_DIRS_LOCAL)

    # 设置输出变量到调用者作用域
    set(${SOURCES_VAR} ${SOURCES_LOCAL} PARENT_SCOPE)
    set(${HEADER_DIRS_VAR} ${HEADER_DIRS_LOCAL} PARENT_SCOPE)

endfunction()

