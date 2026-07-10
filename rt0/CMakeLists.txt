cmake_minimum_required(VERSION 3.20)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    project(cjcj_rt0 LANGUAGES CXX ASM)
endif()

if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux" OR NOT CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64)$")
    message(FATAL_ERROR "cjcj_rt0 currently supports only x86_64 Linux")
endif()

set(CANGJIE_RUNTIME_SOURCE "/root/cj_build/cangjie_runtime/runtime" CACHE PATH
    "Read-only Cangjie runtime source used for frozen Layer0 headers")
if(NOT EXISTS "${CANGJIE_RUNTIME_SOURCE}/src/Cangjie.h")
    message(FATAL_ERROR "invalid CANGJIE_RUNTIME_SOURCE: ${CANGJIE_RUNTIME_SOURCE}")
endif()

set(RT0_ARCH_SOURCES
    arch/x86_64_linux/C2NStub.S
    arch/x86_64_linux/CalleeSavedStub.S
    arch/x86_64_linux/CjNativeRuntimeStartAndEnd.S
    arch/x86_64_linux/Cjpgo.S
    arch/x86_64_linux/Cjstart.S
    arch/x86_64_linux/ExclusiveScope.S
    arch/x86_64_linux/HandleSafepointStub.S
    arch/x86_64_linux/N2CStub.S
    arch/x86_64_linux/RestoreContextForEH.S
    arch/x86_64_linux/StackGrowStub.S)

set(RT0_PLATFORM_SOURCES
    os/Linux/Loader.cpp
    os/Linux/Path.cpp
    signal/SignalStack.cpp
    signal/SignalUtils.cpp
    signal/SignalVectorCompat.cpp
    signal/SignalHandler.h
    signal/SignalStack.h
    signal/SignalUtils.h
    mutator/SafepointPageManager.h)

add_library(cjcj_rt0 STATIC ${RT0_ARCH_SOURCES} ${RT0_PLATFORM_SOURCES})
set_target_properties(cjcj_rt0 PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
    OUTPUT_NAME cjcj_rt0
    POSITION_INDEPENDENT_CODE ON)
target_compile_features(cjcj_rt0 PRIVATE cxx_std_14)
target_include_directories(cjcj_rt0 PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/signal"
    "${CANGJIE_RUNTIME_SOURCE}/src"
    "${CANGJIE_RUNTIME_SOURCE}/third_party/third_party_bounds_checking_function/include")
target_compile_options(cjcj_rt0 PRIVATE
    $<$<CONFIG:Release>:-O2>
    $<$<CONFIG:Release>:-D_FORTIFY_SOURCE=2>
    $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions;-fno-rtti;-fno-omit-frame-pointer;-fno-strict-aliasing;-fno-common;-ffunction-sections;-fstack-protector-strong>)

install(TARGETS cjcj_rt0 ARCHIVE DESTINATION lib)
