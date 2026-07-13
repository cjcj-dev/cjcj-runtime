import rt.common.*

main(): Int64 {
    RunType.InitRunTypeMap()

    // Every exact config size must map back to its own run index.
    var k = 0
    while (k < Int64(RunType.NUM_OF_RUN_TYPES)) {
        let s = UIntNative(RunType.TYPES[k].size)
        let got = RUNTYPE_SIZE_TO_RUN_IDX(s)
        if (Int64(got) != k) {
            println("FAIL exact size=${s} idx=${got} expected=${k}")
            return 1
        }
        if (RUNTYPE_RUN_IDX_TO_SIZE(UInt32(k)) != RunType.TYPES[k].size) {
            println("FAIL idx2size ${k}")
            return 2
        }
        k += 1
    }

    // Inexact but 8-aligned sizes (callers align to 8 first) round up to the closest config
    // with a greater-or-equal size.
    if (RUNTYPE_SIZE_TO_RUN_IDX(456) != 46) { println("FAIL round 456"); return 3 } // -> 504 (idx 46)
    if (RUNTYPE_SIZE_TO_RUN_IDX(368) != 44) { println("FAIL round 368"); return 4 } // -> 400 (idx 44)

    // Boundary configs and derived constants.
    if (RUNTYPE_RUN_IDX_TO_SIZE(0) != 16) { println("FAIL idx0"); return 5 }
    if (RUNTYPE_RUN_IDX_TO_SIZE(52) != 2016) { println("FAIL idx52"); return 6 }
    if (RUNTYPE_SIZE_TO_RUN_IDX(RUN_ALLOC_LARGE_SIZE) + 1 != RunType.NUM_OF_RUN_TYPES) {
        println("FAIL large invariant"); return 7
    }
    if (RunType.NUM_OF_LOCAL_TYPES != 12) { println("FAIL local types"); return 8 }
    if (RUNTYPE_FAST_RUN_IDX(RUN_ALLOC_SMALL_SIZE) != 11) { println("FAIL fast idx"); return 9 }

    println("RUNTYPE_PROBE PASS types=${RunType.NUM_OF_RUN_TYPES} local=${RunType.NUM_OF_LOCAL_TYPES}")
    return 0
}
