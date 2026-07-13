// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.
//
// See https://cangjie-lang.cn/pages/LICENSE for license information.

#include <cstdio>
#include <cstdlib>
#include <cstring>

// TRANSITIONAL: Base/Log.cpp:417-419 terminates RTLOG_FATAL with std::abort().
// This Windows Layer0 bridge mirrors the Linux bridge's role but, because Windows
// has no execinfo backtrace, it writes the message to stderr and aborts without a
// native backtrace (the Linux bridge's backtrace is a POSIX-only debugging aid).
extern "C" [[noreturn]] void RtFatal(const char* message)
{
    if (message != nullptr) {
        (void)std::fwrite(message, 1, std::strlen(message), stderr);
        (void)std::fputc('\n', stderr);
        (void)std::fflush(stderr);
    }
    std::abort();
}
