package rt.common

import rt.base.*

// Port of Common/RunType.h / RunType.cpp: the native allocator's run (size-class) configuration
// table and the size->config-index map. Pure allocation-size data, consumed by the (not-yet-ported)
// PageAllocator/ThreadCache. Depends only on Base.

// Common/RunType.h:14-19. Slots up to SMALL are thread-local cache runs; up to LARGE come from the
// global buffer; larger are large slots.
public const RUN_ALLOC_SMALL_SIZE: UIntNative = 104
public const RUN_ALLOC_LARGE_SIZE: UIntNative = 2016

// Common/RunType.h:57. C++ declares this `int`; it is only ever used as numPagesPerRun (uint8_t).
public const DEFAULT_PAGE_PER_RUN: UInt8 = 1

// Common/RunType.h:22. Fast index shortcut valid under the current TYPES layout.
public func RUNTYPE_FAST_RUN_IDX(size: UIntNative): UIntNative {
    return (size >> 3) - 2
}

public struct RunType {
    // Common/RunType.h:26-28. Supports up to a 256*8 == 2048 byte run.
    public static const MAX_NUM_OF_RUN_TYPES: UInt32 = 256
    // Common/RunType.h:30-31. REMEMBER TO CHANGE THIS WHEN YOU ADD/REMOVE CONFIGS.
    public static const NUM_OF_RUN_TYPES: UInt32 = 53
    // Common/RunType.h:33. RUNTYPE_FAST_RUN_IDX(RUN_ALLOC_SMALL_SIZE) + 1 = (104>>3)-2+1 = 12.
    public static const NUM_OF_LOCAL_TYPES: UInt32 = 12

    // Common/RunType.h:43-47.
    public let isSmall: Bool         // this kind of run is composed of small-sized slots
    public let numPagesPerRun: UInt8 // pages per run
    public let size: UInt32          // slot size of this kind of run

    public init(isSmall: Bool, numPagesPerRun: UInt8, size: UInt32) {
        this.isSmall = isSmall
        this.numPagesPerRun = numPagesPerRun
        this.size = size
    }

    // RunType.cpp:13-75. One config per kind of run, indexed by run index. Ascending by size.
    public static let TYPES: Array<RunType> = [
        RunType(true, DEFAULT_PAGE_PER_RUN, 16),
        RunType(true, DEFAULT_PAGE_PER_RUN, 24),
        RunType(true, DEFAULT_PAGE_PER_RUN, 32),
        RunType(true, DEFAULT_PAGE_PER_RUN, 40),
        RunType(true, DEFAULT_PAGE_PER_RUN, 48),
        RunType(true, DEFAULT_PAGE_PER_RUN, 56),
        RunType(true, DEFAULT_PAGE_PER_RUN, 64),
        RunType(true, DEFAULT_PAGE_PER_RUN, 72),
        RunType(true, DEFAULT_PAGE_PER_RUN, 80),
        RunType(true, DEFAULT_PAGE_PER_RUN, 88),
        RunType(true, DEFAULT_PAGE_PER_RUN, 96),
        RunType(true, DEFAULT_PAGE_PER_RUN, UInt32(RUN_ALLOC_SMALL_SIZE)),
        RunType(false, DEFAULT_PAGE_PER_RUN, 112),
        RunType(false, DEFAULT_PAGE_PER_RUN, 120),
        RunType(false, DEFAULT_PAGE_PER_RUN, 128),
        RunType(false, DEFAULT_PAGE_PER_RUN, 136),
        RunType(false, DEFAULT_PAGE_PER_RUN, 144),
        RunType(false, DEFAULT_PAGE_PER_RUN, 152),
        RunType(false, DEFAULT_PAGE_PER_RUN, 160),
        RunType(false, DEFAULT_PAGE_PER_RUN, 168),
        RunType(false, DEFAULT_PAGE_PER_RUN, 176),
        RunType(false, DEFAULT_PAGE_PER_RUN, 184),
        RunType(false, DEFAULT_PAGE_PER_RUN, 192),
        RunType(false, DEFAULT_PAGE_PER_RUN, 200),
        RunType(false, DEFAULT_PAGE_PER_RUN, 208),
        RunType(false, DEFAULT_PAGE_PER_RUN, 216),
        RunType(false, DEFAULT_PAGE_PER_RUN, 224),
        RunType(false, DEFAULT_PAGE_PER_RUN, 232),
        RunType(false, DEFAULT_PAGE_PER_RUN, 240),
        RunType(false, DEFAULT_PAGE_PER_RUN, 248),
        RunType(false, DEFAULT_PAGE_PER_RUN, 256),
        RunType(false, DEFAULT_PAGE_PER_RUN, 264),
        RunType(false, DEFAULT_PAGE_PER_RUN, 272),
        RunType(false, DEFAULT_PAGE_PER_RUN, 280),
        RunType(false, DEFAULT_PAGE_PER_RUN, 288),
        RunType(false, DEFAULT_PAGE_PER_RUN, 296),
        RunType(false, DEFAULT_PAGE_PER_RUN, 304),
        RunType(false, DEFAULT_PAGE_PER_RUN, 312),
        RunType(false, DEFAULT_PAGE_PER_RUN, 320),
        RunType(false, DEFAULT_PAGE_PER_RUN, 328),
        RunType(false, DEFAULT_PAGE_PER_RUN, 336),
        RunType(false, DEFAULT_PAGE_PER_RUN, 344),
        RunType(false, DEFAULT_PAGE_PER_RUN, 352),
        RunType(false, DEFAULT_PAGE_PER_RUN, 360),
        RunType(false, DEFAULT_PAGE_PER_RUN, 400),
        RunType(false, DEFAULT_PAGE_PER_RUN, 448),
        RunType(false, DEFAULT_PAGE_PER_RUN, 504),
        RunType(false, DEFAULT_PAGE_PER_RUN, 576),
        RunType(false, DEFAULT_PAGE_PER_RUN, 672),
        RunType(false, DEFAULT_PAGE_PER_RUN, 800),
        RunType(false, DEFAULT_PAGE_PER_RUN, 1008),
        RunType(false, DEFAULT_PAGE_PER_RUN, 1344),
        RunType(false, DEFAULT_PAGE_PER_RUN, UInt32(RUN_ALLOC_LARGE_SIZE))
    ]

    // RunType.cpp:79 / RunType.h:41. Maps (size>>3 - 1) to a run config index; all zero-initialised.
    public static let g_size2Idx: Array<UInt32> = Array<UInt32>(Int64(MAX_NUM_OF_RUN_TYPES), repeat: 0)

    // RunType.cpp:86-120. Fill g_size2Idx so every size has a config: an inexact size picks the
    // closest config with a greater-or-equal size.
    public static func InitRunTypeMap(): Unit {
        let runSizeShift: UInt32 = 3
        MRT_ASSERT(NUM_OF_RUN_TYPES <= MAX_NUM_OF_RUN_TYPES, "too many configs")
        var idx: UInt32 = NUM_OF_RUN_TYPES
        var nextSize: UInt32 = TYPES[Int64(NUM_OF_RUN_TYPES) - 1].size
        MRT_ASSERT(nextSize <= (MAX_NUM_OF_RUN_TYPES << runSizeShift), "size too big in config")
        var i: UInt32 = MAX_NUM_OF_RUN_TYPES - 1
        while (true) {
            if (((i + 1) << runSizeShift) > nextSize) {
                if (idx < NUM_OF_RUN_TYPES) {
                    g_size2Idx[Int64(i)] = idx
                }
            } else {
                MRT_ASSERT(((i + 1) << runSizeShift) == nextSize, "init run config error")
                MRT_ASSERT(idx > 0, "init run config error")
                idx -= 1
                g_size2Idx[Int64(i)] = idx
                if (idx > 0 && idx < NUM_OF_RUN_TYPES) {
                    MRT_ASSERT(TYPES[Int64(idx) - 1].size < nextSize, "not in ascending order")
                    nextSize = TYPES[Int64(idx) - 1].size
                } else {
                    nextSize = 0
                }
            }

            if (i == 0) {
                break
            } else {
                i -= 1
            }
        }

        MRT_ASSERT(RUNTYPE_SIZE_TO_RUN_IDX(RUN_ALLOC_LARGE_SIZE) + 1 == NUM_OF_RUN_TYPES,
            "run config inconsistent: large size")
    }
}

// RunType.h:53. assume(size <= (TYPES[NUM_OF_RUN_TYPES - 1].size << 3)).
public func RUNTYPE_SIZE_TO_RUN_IDX(size: UIntNative): UInt32 {
    return RunType.g_size2Idx[Int64((size >> 3) - 1)]
}

// RunType.h:55.
public func RUNTYPE_RUN_IDX_TO_SIZE(idx: UInt32): UInt32 {
    return RunType.TYPES[Int64(idx)].size
}
