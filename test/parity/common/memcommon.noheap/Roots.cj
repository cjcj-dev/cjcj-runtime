package memcommon.noheap

import rt.common.*

@C
public func MemCommonRoundRoot(bytes: UIntNative): UIntNative { return SizeManagerRoundUp(bytes) }

@C
public func MemCommonIndexRoot(bytes: UIntNative): UIntNative { return SizeManagerIndex(bytes) }

@C
public func MemCommonLimitRoot(bytes: UIntNative): UIntNative { return SizeManagerLimitSize(bytes) }

@C
public func MemCommonPagesRoot(bytes: UIntNative): UIntNative { return SizeManagerCalculatePageNum(bytes) }
