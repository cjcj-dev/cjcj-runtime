// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.
//
// See https://cangjie-lang.cn/pages/LICENSE for license information.

#include "Cangjie.h"

#include <vector>

// The official x86_64 runtime emitted this weak template instantiation. Newer
// libstdc++ headers inline it at the SignalStack call site, but the old spelling
// remains part of the observed dynamic ABI and must still be materialized.
template void std::vector<SignalAction>::_M_realloc_insert<const SignalAction&>(
    std::vector<SignalAction>::iterator, const SignalAction&);
