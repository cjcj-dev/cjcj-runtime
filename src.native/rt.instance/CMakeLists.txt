cmake_minimum_required(VERSION 3.20)

file(GLOB_RECURSE CJCJ_RUNTIME_HEADERS CONFIGURE_DEPENDS
    "${CANGJIE_RUNTIME_SOURCE}/src/*.h")
set(CJCJ_RUNTIME_INCLUDE_DIRS
    "${CANGJIE_RUNTIME_SOURCE}/output/temp/include"
    "${CANGJIE_RUNTIME_SOURCE}/include"
    "${CANGJIE_RUNTIME_SOURCE}/src"
    "${CANGJIE_RUNTIME_SOURCE}/third_party/third_party_bounds_checking_function/include")
foreach(header IN LISTS CJCJ_RUNTIME_HEADERS)
    get_filename_component(header_dir "${header}" DIRECTORY)
    list(APPEND CJCJ_RUNTIME_INCLUDE_DIRS "${header_dir}")
endforeach()
list(REMOVE_DUPLICATES CJCJ_RUNTIME_INCLUDE_DIRS)

set(CJCJ_CJTHREAD_SOURCE "${CANGJIE_RUNTIME_SOURCE}/src/CJThread/src")
if(WIN32)
    list(PREPEND CJCJ_RUNTIME_INCLUDE_DIRS
        "${CJCJ_CJTHREAD_SOURCE}/runtime/netpoll/include/windows"
        "${CJCJ_CJTHREAD_SOURCE}/runtime/netpoll/include/windows/inner"
        "${CJCJ_CJTHREAD_SOURCE}/syscall/include/windows")
    set(CJCJ_RT_INSTANCE_PLATFORM MRT_WINDOWS)
elseif(APPLE OR IOS_FLAG MATCHES 1 OR IOS_SIMULATOR_FLAG MATCHES "^[12]$")
    list(PREPEND CJCJ_RUNTIME_INCLUDE_DIRS
        "${CJCJ_CJTHREAD_SOURCE}/runtime/netpoll/include/macos"
        "${CJCJ_CJTHREAD_SOURCE}/runtime/netpoll/include/macos/inner"
        "${CJCJ_CJTHREAD_SOURCE}/syscall/include/macos")
    set(CJCJ_RT_INSTANCE_PLATFORM MRT_MACOS)
else()
    list(PREPEND CJCJ_RUNTIME_INCLUDE_DIRS
        "${CJCJ_CJTHREAD_SOURCE}/runtime/netpoll/include/linux"
        "${CJCJ_CJTHREAD_SOURCE}/runtime/netpoll/include/linux/inner"
        "${CJCJ_CJTHREAD_SOURCE}/syscall/include/linux")
    set(CJCJ_RT_INSTANCE_PLATFORM MRT_LINUX)
endif()

add_library(cjcj_rt_instance OBJECT instance_bridge.cpp)
set_target_properties(cjcj_rt_instance PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_compile_features(cjcj_rt_instance PRIVATE cxx_std_14)
target_compile_definitions(cjcj_rt_instance PRIVATE
    MRT_USE_CJTHREAD_RENAME
    ${CJCJ_RT_INSTANCE_PLATFORM})
target_include_directories(cjcj_rt_instance PRIVATE
    "${CMAKE_SOURCE_DIR}/contract"
    ${CJCJ_RUNTIME_INCLUDE_DIRS})
target_compile_options(cjcj_rt_instance PRIVATE
    $<$<CONFIG:Release>:-O2>
    $<$<CONFIG:Release>:-D_FORTIFY_SOURCE=2>
    -fno-exceptions
    -fno-rtti
    -fno-omit-frame-pointer
    -fno-strict-aliasing
    -fno-common
    -ffunction-sections
    -fstack-protector-strong)

set(CJCJ_RT_INSTANCE_OBJECT "${CMAKE_BINARY_DIR}/lib/instance_bridge.o")
add_custom_target(cjcj_rt_instance_object ALL
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${CMAKE_BINARY_DIR}/lib"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        $<TARGET_OBJECTS:cjcj_rt_instance> "${CJCJ_RT_INSTANCE_OBJECT}"
    DEPENDS cjcj_rt_instance
    COMMAND_EXPAND_LISTS
    VERBATIM)
