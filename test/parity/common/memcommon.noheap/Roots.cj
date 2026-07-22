package memcommon.noheap

import rt.common.*

@C
public func MemCommonRoundRoot(bytes: UIntNative): UIntNative { return SizeManagerRoundUp(bytes) }

@C
public func MemCommonIndexRoot(bytes: UIntNative): UIntNative { return SizeManagerIndex(bytes) }
