cmake_minimum_required(VERSION 3.20)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    set(OHOS_FLAG "0" CACHE STRING "OHOS target: 0=off, 1=aarch64, 2=x86_64, 3=arm")
    set(IOS_FLAG "0" CACHE STRING "Build for an iOS device")
    set(IOS_SIMULATOR_FLAG "0" CACHE STRING "iOS simulator: 0=off, 1=aarch64, 2=x86_64")
    if(OHOS_FLAG MATCHES "^[123]$")
        set(CMAKE_SYSTEM_NAME Linux)
        if(OHOS_FLAG MATCHES 1)
            set(CMAKE_SYSTEM_PROCESSOR aarch64)
        elseif(OHOS_FLAG MATCHES 2)
            set(CMAKE_SYSTEM_PROCESSOR x86_64)
        elseif(OHOS_FLAG MATCHES 3)
            set(CMAKE_SYSTEM_PROCESSOR arm)
        endif()
    endif()
    option(CJCJ_RT0_CONFIGURE_ONLY
        "Validate rt0 platform source selection without requiring a cross toolchain" OFF)
    if(CJCJ_RT0_CONFIGURE_ONLY)
        project(cjcj_rt0 LANGUAGES NONE)
    else()
        project(cjcj_rt0 LANGUAGES CXX ASM)
    endif()
endif()

if(OHOS_FLAG MATCHES 1)
    set(RT0_ARCH aarch64_linux)
elseif(OHOS_FLAG MATCHES 2)
    set(RT0_ARCH x86_64_linux)
elseif(OHOS_FLAG MATCHES 3)
    set(RT0_ARCH arm_linux)
elseif(MINGW OR CMAKE_SYSTEM_NAME STREQUAL "Windows")
    set(RT0_ARCH x86_64_windows)
elseif(IOS_FLAG MATCHES 1 OR IOS_SIMULATOR_FLAG MATCHES "^[12]$")
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$" OR IOS_SIMULATOR_FLAG MATCHES 2)
        set(RT0_ARCH x86_64_ios)
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$" OR IOS_SIMULATOR_FLAG MATCHES 1)
        set(RT0_ARCH aarch64_ios)
    endif()
elseif(APPLE)
    if(IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
        if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$")
            set(RT0_ARCH x86_64_ios)
        elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
            set(RT0_ARCH aarch64_ios)
        endif()
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$")
        set(RT0_ARCH x86_64_macos)
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
        set(RT0_ARCH aarch64_macos)
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$")
        set(RT0_ARCH x86_64_linux)
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
        set(RT0_ARCH aarch64_linux)
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(arm|armv7.*)$")
        set(RT0_ARCH arm_linux)
    endif()
endif()

if(NOT RT0_ARCH)
    message(FATAL_ERROR
        "unsupported rt0 target: system=${CMAKE_SYSTEM_NAME} processor=${CMAKE_SYSTEM_PROCESSOR} "
        "OHOS_FLAG=${OHOS_FLAG} MINGW=${MINGW} APPLE=${APPLE} IOS=${IOS}")
endif()

set(CANGJIE_RUNTIME_SOURCE "/root/cj_build/cangjie_runtime/runtime" CACHE PATH
    "Read-only Cangjie runtime source used for frozen Layer0 headers")
if(NOT EXISTS "${CANGJIE_RUNTIME_SOURCE}/src/Cangjie.h")
    message(FATAL_ERROR "invalid CANGJIE_RUNTIME_SOURCE: ${CANGJIE_RUNTIME_SOURCE}")
endif()

file(GLOB RT0_ARCH_SOURCES CONFIGURE_DEPENDS "arch/${RT0_ARCH}/*.S")

if(MINGW OR CMAKE_SYSTEM_NAME STREQUAL "Windows")
    set(RT0_PLATFORM_SOURCES
        os/Windows/Loader.cpp
        os/Windows/Path.cpp
        os/Windows/UnwindWin.cpp
        os/Windows/WinModuleManager.cpp
        signal/SignalUtils.cpp)
else()
    set(RT0_PLATFORM_SOURCES
        os/Linux/Loader.cpp
        os/Linux/Path.cpp
        signal/SignalStack.cpp
        signal/SignalUtils.cpp
        signal/SignalVectorCompat.cpp)
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    list(APPEND RT0_PLATFORM_SOURCES
        os/Linux/Atomic.cpp
        os/Linux/Futex.cpp
        os/Linux/PagePoolMutex.cpp
        os/Linux/Panic.cpp
        os/Linux/SpinLock.cpp)
endif()

list(APPEND RT0_PLATFORM_SOURCES
    os/Loader.h
    os/Path.h
    signal/SignalHandler.h
    signal/SignalStack.h
    signal/SignalUtils.h
    mutator/SafepointPageManager.h)

foreach(source IN LISTS RT0_ARCH_SOURCES RT0_PLATFORM_SOURCES)
    if(NOT IS_ABSOLUTE "${source}")
        set(source "${CMAKE_CURRENT_SOURCE_DIR}/${source}")
    endif()
    if(NOT EXISTS "${source}")
        message(FATAL_ERROR "selected rt0 source does not exist: ${source}")
    endif()
endforeach()

list(LENGTH RT0_ARCH_SOURCES RT0_ARCH_SOURCE_COUNT)
message(STATUS
    "cjcj_rt0 target=${RT0_ARCH} system=${CMAKE_SYSTEM_NAME} "
    "processor=${CMAKE_SYSTEM_PROCESSOR} arch_sources=${RT0_ARCH_SOURCE_COUNT}")

if(CJCJ_RT0_CONFIGURE_ONLY)
    return()
endif()

add_library(cjcj_rt0 STATIC ${RT0_ARCH_SOURCES} ${RT0_PLATFORM_SOURCES})
set_target_properties(cjcj_rt0 PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
    OUTPUT_NAME cjcj_rt0
    POSITION_INDEPENDENT_CODE ON)
target_compile_features(cjcj_rt0 PRIVATE cxx_std_14)
target_include_directories(cjcj_rt0 PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/signal"
    "${CMAKE_CURRENT_SOURCE_DIR}/os"
    "${CMAKE_CURRENT_SOURCE_DIR}/os/Windows"
    "${CANGJIE_RUNTIME_SOURCE}/src"
    "${CANGJIE_RUNTIME_SOURCE}/third_party/third_party_bounds_checking_function/include")
target_compile_options(cjcj_rt0 PRIVATE
    $<$<CONFIG:Release>:-O2>
    $<$<CONFIG:Release>:-D_FORTIFY_SOURCE=2>
    $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions;-fno-rtti;-fno-omit-frame-pointer;-fno-strict-aliasing;-fno-common;-ffunction-sections;-fstack-protector-strong>)

install(TARGETS cjcj_rt0 ARCHIVE DESTINATION lib)
