// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.
//
// See https://cangjie-lang.cn/pages/LICENSE for license information.

#include <cstdlib>
#include <cstring>
#include <execinfo.h>
#include <unistd.h>

// TRANSITIONAL: Base/Log.cpp:417-419 terminates RTLOG_FATAL with std::abort().
// This Layer0 bridge additionally carries the requested native backtrace until
// Logger::FormatLog itself is ported.
extern "C" [[noreturn]] void RtFatal(const char* message)
{
    if (message != nullptr) {
        ssize_t messageWrite = write(STDERR_FILENO, message, std::strlen(message));
        ssize_t newlineWrite = write(STDERR_FILENO, "\n", 1);
        (void)messageWrite;
        (void)newlineWrite;
    }
    void* frames[64];
    int count = backtrace(frames, 64);
    backtrace_symbols_fd(frames, count, STDERR_FILENO);
    std::abort();
}
