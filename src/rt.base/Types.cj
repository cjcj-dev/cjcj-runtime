// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.
//
// See https://cangjie-lang.cn/pages/LICENSE for license information.

package rt.base

// Base/Types.h:21-34. General unmanaged scalar types.
public type U1 = UInt8
public type I1 = Int8
public type U8 = UInt8
public type I8 = Int8
public type U16 = UInt16
public type I16 = Int16
public type U32 = UInt32
public type I32 = Int32
public type U64 = UInt64
public type I64 = Int64

public type F16 = UInt16
public type F32 = Float32
public type F64 = Float64

// Base/Types.h:38-42. Apple defines Uptr as uint64_t; other targets use uintptr_t.
@When[os == "macOS" || os == "iOS"]
public type Uptr = UInt64

@When[os != "macOS" && os != "iOS"]
public type Uptr = UIntNative

// Base/Types.h:43-49. Pointer-sized signed/unsigned vocabulary.
public type Sptr = IntNative
public type Size = IntNative
public type USize = UIntNative
public type Index = UIntNative
public type Offset = UIntNative

// Base/Types.h:51-55. Only 32-bit ARM uses a 32-bit architecture word.
@When[arch == "arm"]
public type ArchUInt = UInt32

@When[arch != "arm"]
public type ArchUInt = UInt64
