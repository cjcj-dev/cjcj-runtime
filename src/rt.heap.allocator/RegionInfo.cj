package rt.heap.allocator

import rt.base.*
import std.overflow.*

foreign {
    func cj_atomic_u8_cas(p: CPointer<UInt8>, expected: CPointer<UInt8>, desired: UInt8): Int32
    func cj_atomic_u8_load(p: CPointer<UInt8>): UInt8
    func cj_atomic_u8_store(p: CPointer<UInt8>, value: UInt8): Unit
    func cj_atomic_u16_cas(p: CPointer<UInt16>, expected: CPointer<UInt16>, desired: UInt16): Int32
    func cj_atomic_u16_load(p: CPointer<UInt16>): UInt16
    func cj_atomic_u16_store(p: CPointer<UInt16>, value: UInt16): Unit
    func cj_atomic_i32_store(p: CPointer<Int32>, value: Int32): Unit
    func cj_atomic_u32_store_release(p: CPointer<UInt32>, value: UInt32): Unit
    func memset(destination: CPointer<Unit>, value: Int32, count: UIntNative): CPointer<Unit>
    func write(fd: Int32, data: CPointer<UInt8>, size: UIntNative): IntNative
    func abort(): Unit
    func RtFatal(message: CString): Unit

    @When[os == "Windows"]
    func VirtualFree(address: CPointer<Unit>, size: UIntNative, freeType: UInt32): Int32
}

// Heap/Allocator/RegionInfo.h:95-443,516-532,607-738. Static NUL-terminated
// messages keep every Collector-deferred abort path independent of the GC allocator.
private var collectorDeferredMessages: VArray<UInt8, $2506> = [
    82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 67u8, 111u8, 109u8, 112u8,
    97u8, 114u8, 101u8, 69u8, 120u8, 99u8, 104u8, 97u8, 110u8, 103u8, 101u8, 82u8, 111u8, 117u8, 116u8, 101u8,
    83u8, 116u8, 97u8, 116u8, 101u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8,
    114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8,
    100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8,
    73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 71u8, 101u8, 116u8, 82u8, 111u8, 117u8, 116u8, 101u8, 83u8, 116u8,
    97u8, 116u8, 101u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8,
    101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8,
    102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8,
    102u8, 111u8, 58u8, 58u8, 83u8, 101u8, 116u8, 82u8, 111u8, 117u8, 116u8, 101u8, 83u8, 116u8, 97u8, 116u8,
    101u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8,
    32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8,
    114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8,
    58u8, 58u8, 73u8, 115u8, 67u8, 111u8, 109u8, 112u8, 97u8, 99u8, 116u8, 101u8, 100u8, 32u8, 110u8, 111u8,
    116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8,
    108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8,
    41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 73u8, 115u8,
    82u8, 111u8, 117u8, 116u8, 105u8, 110u8, 103u8, 83u8, 116u8, 97u8, 116u8, 101u8, 32u8, 110u8, 111u8, 116u8,
    32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8,
    108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8,
    0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 84u8, 114u8, 121u8,
    76u8, 111u8, 99u8, 107u8, 82u8, 111u8, 117u8, 116u8, 105u8, 110u8, 103u8, 32u8, 110u8, 111u8, 116u8, 32u8,
    121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8,
    101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8,
    82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 71u8, 101u8, 116u8, 80u8,
    114u8, 101u8, 76u8, 105u8, 118u8, 101u8, 66u8, 121u8, 116u8, 101u8, 115u8, 73u8, 110u8, 71u8, 104u8, 111u8,
    115u8, 116u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8,
    32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8,
    111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8,
    105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 71u8, 101u8, 116u8, 76u8, 105u8, 118u8, 101u8,
    73u8, 110u8, 102u8, 111u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8,
    116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8,
    101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8,
    110u8, 102u8, 111u8, 58u8, 58u8, 71u8, 101u8, 116u8, 79u8, 114u8, 65u8, 108u8, 108u8, 111u8, 99u8, 76u8,
    105u8, 118u8, 101u8, 73u8, 110u8, 102u8, 111u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8, 32u8,
    112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8, 111u8,
    114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8, 105u8,
    111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 71u8, 101u8, 116u8, 77u8, 97u8, 114u8, 107u8, 66u8,
    105u8, 116u8, 109u8, 97u8, 112u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8,
    114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8,
    100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8,
    73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 71u8, 101u8, 116u8, 79u8, 114u8, 65u8, 108u8, 108u8, 111u8, 99u8,
    77u8, 97u8, 114u8, 107u8, 66u8, 105u8, 116u8, 109u8, 97u8, 112u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8,
    101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8,
    99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8,
    101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 71u8, 101u8, 116u8, 82u8, 101u8,
    115u8, 117u8, 114u8, 114u8, 101u8, 99u8, 116u8, 66u8, 105u8, 116u8, 109u8, 97u8, 112u8, 32u8, 110u8, 111u8,
    116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8,
    108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8,
    41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 71u8, 101u8,
    116u8, 79u8, 114u8, 65u8, 108u8, 108u8, 111u8, 99u8, 82u8, 101u8, 115u8, 117u8, 114u8, 114u8, 101u8, 99u8,
    116u8, 66u8, 105u8, 116u8, 109u8, 97u8, 112u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8, 32u8,
    112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8, 111u8,
    114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8, 105u8,
    111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 71u8, 101u8, 116u8, 69u8, 110u8, 113u8, 117u8, 101u8,
    117u8, 101u8, 66u8, 105u8, 116u8, 109u8, 97u8, 112u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8,
    32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8,
    111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8,
    105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 71u8, 101u8, 116u8, 79u8, 114u8, 65u8, 108u8,
    108u8, 111u8, 99u8, 69u8, 110u8, 113u8, 117u8, 101u8, 117u8, 101u8, 66u8, 105u8, 116u8, 109u8, 97u8, 112u8,
    32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8,
    40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8,
    114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8,
    58u8, 82u8, 101u8, 115u8, 101u8, 116u8, 77u8, 97u8, 114u8, 107u8, 66u8, 105u8, 116u8, 32u8, 110u8, 111u8,
    116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8,
    108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8,
    41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 77u8, 97u8,
    114u8, 107u8, 79u8, 98u8, 106u8, 101u8, 99u8, 116u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8,
    32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8,
    111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8,
    105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 82u8, 101u8, 115u8, 117u8, 114u8, 114u8, 101u8,
    99u8, 116u8, 79u8, 98u8, 106u8, 101u8, 99u8, 116u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8,
    32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8,
    111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8,
    105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 69u8, 110u8, 113u8, 117u8, 101u8, 117u8, 101u8,
    79u8, 98u8, 106u8, 101u8, 99u8, 116u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8,
    111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8,
    45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8,
    110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 73u8, 115u8, 82u8, 101u8, 115u8, 117u8, 114u8, 114u8, 101u8,
    99u8, 116u8, 101u8, 100u8, 79u8, 98u8, 106u8, 101u8, 99u8, 116u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8,
    101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8,
    99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8,
    101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 73u8, 115u8, 77u8, 97u8, 114u8,
    107u8, 101u8, 100u8, 79u8, 98u8, 106u8, 101u8, 99u8, 116u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8,
    116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8,
    116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8,
    103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 73u8, 115u8, 83u8, 117u8, 114u8, 118u8,
    105u8, 118u8, 101u8, 100u8, 79u8, 98u8, 106u8, 101u8, 99u8, 116u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8,
    101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8,
    99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8,
    101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 73u8, 115u8, 69u8, 110u8, 113u8,
    117u8, 101u8, 117u8, 101u8, 100u8, 79u8, 98u8, 106u8, 101u8, 99u8, 116u8, 32u8, 110u8, 111u8, 116u8, 32u8,
    121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8,
    101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8,
    82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 73u8, 110u8, 71u8, 104u8,
    111u8, 115u8, 116u8, 70u8, 114u8, 111u8, 109u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 32u8, 110u8, 111u8,
    116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8,
    108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8,
    41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 71u8, 101u8,
    116u8, 71u8, 104u8, 111u8, 115u8, 116u8, 70u8, 114u8, 111u8, 109u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8,
    65u8, 116u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8,
    100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8,
    101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8,
    111u8, 58u8, 58u8, 71u8, 101u8, 116u8, 71u8, 104u8, 111u8, 115u8, 116u8, 82u8, 101u8, 103u8, 105u8, 111u8,
    110u8, 83u8, 105u8, 122u8, 101u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8,
    114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8,
    100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8,
    73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 71u8, 101u8, 116u8, 71u8, 104u8, 111u8, 115u8, 116u8, 82u8, 101u8,
    103u8, 105u8, 111u8, 110u8, 85u8, 110u8, 105u8, 116u8, 67u8, 111u8, 117u8, 110u8, 116u8, 32u8, 110u8, 111u8,
    116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8,
    108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8,
    41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 68u8, 117u8,
    109u8, 112u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 32u8, 110u8, 111u8, 116u8,
    32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8,
    108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8,
    0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 71u8, 101u8, 116u8,
    84u8, 121u8, 112u8, 101u8, 78u8, 97u8, 109u8, 101u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8,
    32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8,
    111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8,
    105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 86u8, 105u8, 115u8, 105u8, 116u8, 65u8, 108u8,
    108u8, 79u8, 98u8, 106u8, 101u8, 99u8, 116u8, 115u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8,
    32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8,
    111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8,
    105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 86u8, 105u8, 115u8, 105u8, 116u8, 76u8, 105u8,
    118u8, 101u8, 79u8, 98u8, 106u8, 101u8, 99u8, 116u8, 115u8, 85u8, 110u8, 116u8, 105u8, 108u8, 70u8, 97u8,
    108u8, 115u8, 101u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8,
    101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8,
    102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8,
    102u8, 111u8, 58u8, 58u8, 71u8, 101u8, 116u8, 82u8, 111u8, 117u8, 116u8, 101u8, 32u8, 110u8, 111u8, 116u8,
    32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8,
    108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8,
    0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 80u8, 114u8, 101u8,
    112u8, 97u8, 114u8, 101u8, 70u8, 111u8, 114u8, 119u8, 97u8, 114u8, 100u8, 97u8, 98u8, 108u8, 101u8, 82u8,
    101u8, 103u8, 105u8, 111u8, 110u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8,
    114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8,
    100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8,
    73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 67u8, 108u8, 101u8, 97u8, 114u8, 71u8, 104u8, 111u8, 115u8, 116u8,
    82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 66u8, 105u8, 116u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8,
    116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8,
    116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8,
    103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 68u8, 105u8, 115u8, 112u8, 101u8, 108u8,
    71u8, 104u8, 111u8, 115u8, 116u8, 70u8, 114u8, 111u8, 109u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 32u8,
    110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8,
    67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8,
    101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8,
    73u8, 115u8, 71u8, 104u8, 111u8, 115u8, 116u8, 70u8, 114u8, 111u8, 109u8, 82u8, 101u8, 103u8, 105u8, 111u8,
    110u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8,
    32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8, 100u8, 101u8, 102u8, 101u8,
    114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8,
    58u8, 58u8, 67u8, 104u8, 101u8, 99u8, 107u8, 65u8, 110u8, 100u8, 67u8, 108u8, 101u8, 97u8, 114u8, 76u8,
    105u8, 118u8, 101u8, 73u8, 110u8, 102u8, 111u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8, 32u8,
    112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8, 111u8,
    114u8, 45u8, 100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8, 82u8, 101u8, 103u8, 105u8,
    111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 67u8, 108u8, 101u8, 97u8, 114u8, 76u8, 105u8, 118u8,
    101u8, 73u8, 110u8, 102u8, 111u8, 32u8, 110u8, 111u8, 116u8, 32u8, 121u8, 101u8, 116u8, 32u8, 112u8, 111u8,
    114u8, 116u8, 101u8, 100u8, 32u8, 40u8, 67u8, 111u8, 108u8, 108u8, 101u8, 99u8, 116u8, 111u8, 114u8, 45u8,
    100u8, 101u8, 102u8, 101u8, 114u8, 114u8, 101u8, 100u8, 41u8, 0u8
]

// RegionInfo.h:555-588,592-605,1056-1174. Non-allocating invariant failures.
private var regionInfoInvariantMessages: VArray<UInt8, $486> = [
    85u8, 110u8, 105u8, 116u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 71u8, 101u8, 116u8, 85u8, 110u8, 105u8,
    116u8, 65u8, 100u8, 100u8, 114u8, 101u8, 115u8, 115u8, 32u8, 105u8, 110u8, 100u8, 101u8, 120u8, 32u8, 111u8,
    117u8, 116u8, 32u8, 111u8, 102u8, 32u8, 114u8, 97u8, 110u8, 103u8, 101u8, 0u8, 85u8, 110u8, 105u8, 116u8,
    73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 71u8, 101u8, 116u8, 85u8, 110u8, 105u8, 116u8, 73u8, 110u8, 102u8,
    111u8, 32u8, 105u8, 110u8, 100u8, 101u8, 120u8, 32u8, 111u8, 117u8, 116u8, 32u8, 111u8, 102u8, 32u8, 114u8,
    97u8, 110u8, 103u8, 101u8, 0u8, 85u8, 110u8, 105u8, 116u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 71u8,
    101u8, 116u8, 85u8, 110u8, 105u8, 116u8, 73u8, 100u8, 120u8, 32u8, 115u8, 104u8, 111u8, 117u8, 108u8, 100u8,
    32u8, 110u8, 111u8, 116u8, 32u8, 101u8, 120u8, 101u8, 99u8, 117u8, 116u8, 101u8, 32u8, 104u8, 101u8, 114u8,
    101u8, 0u8, 85u8, 110u8, 105u8, 116u8, 73u8, 110u8, 102u8, 111u8, 65u8, 114u8, 114u8, 97u8, 121u8, 32u8,
    105u8, 110u8, 100u8, 101u8, 120u8, 32u8, 111u8, 117u8, 116u8, 32u8, 111u8, 102u8, 32u8, 114u8, 97u8, 110u8,
    103u8, 101u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 71u8,
    101u8, 116u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 83u8, 116u8, 97u8, 114u8, 116u8, 32u8, 109u8, 101u8,
    116u8, 97u8, 100u8, 97u8, 116u8, 97u8, 32u8, 97u8, 100u8, 100u8, 114u8, 101u8, 115u8, 115u8, 32u8, 105u8,
    110u8, 118u8, 97u8, 108u8, 105u8, 100u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8,
    111u8, 58u8, 58u8, 71u8, 101u8, 116u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 83u8, 116u8, 97u8, 114u8,
    116u8, 32u8, 117u8, 110u8, 105u8, 116u8, 32u8, 105u8, 110u8, 100u8, 101u8, 120u8, 32u8, 105u8, 110u8, 118u8,
    97u8, 108u8, 105u8, 100u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8,
    58u8, 71u8, 101u8, 116u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 83u8, 105u8, 122u8, 101u8, 32u8, 114u8,
    101u8, 103u8, 105u8, 111u8, 110u8, 32u8, 101u8, 110u8, 100u8, 32u8, 105u8, 110u8, 118u8, 97u8, 108u8, 105u8,
    100u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 73u8, 115u8,
    69u8, 109u8, 112u8, 116u8, 121u8, 32u8, 114u8, 101u8, 113u8, 117u8, 105u8, 114u8, 101u8, 115u8, 32u8, 115u8,
    109u8, 97u8, 108u8, 108u8, 32u8, 114u8, 101u8, 103u8, 105u8, 111u8, 110u8, 0u8, 82u8, 101u8, 103u8, 105u8,
    111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 82u8, 101u8, 108u8, 101u8, 97u8, 115u8, 101u8, 85u8,
    110u8, 105u8, 116u8, 115u8, 32u8, 86u8, 105u8, 114u8, 116u8, 117u8, 97u8, 108u8, 70u8, 114u8, 101u8, 101u8,
    32u8, 102u8, 97u8, 105u8, 108u8, 101u8, 100u8, 0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8,
    102u8, 111u8, 58u8, 58u8, 82u8, 101u8, 108u8, 101u8, 97u8, 115u8, 101u8, 85u8, 110u8, 105u8, 116u8, 115u8,
    32u8, 109u8, 109u8, 97u8, 112u8, 32u8, 77u8, 65u8, 80u8, 95u8, 70u8, 65u8, 73u8, 76u8, 69u8, 68u8,
    0u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 73u8, 110u8, 102u8, 111u8, 58u8, 58u8, 82u8, 101u8, 108u8,
    101u8, 97u8, 115u8, 101u8, 85u8, 110u8, 105u8, 116u8, 115u8, 32u8, 109u8, 109u8, 97u8, 112u8, 32u8, 114u8,
    101u8, 116u8, 117u8, 114u8, 110u8, 101u8, 100u8, 32u8, 119u8, 114u8, 111u8, 110u8, 103u8, 32u8, 97u8, 100u8,
    100u8, 114u8, 101u8, 115u8, 115u8, 0u8
]
private var regionInfoNewline: VArray<UInt8, $1> = [10u8]

// RegionInfo.h:570-583; Windows <winnt.h> and Linux/OHOS <sys/mman.h> values.
@When[os == "Windows"]
private const MEM_DECOMMIT: UInt32 = 0x4000u32
@When[os == "Linux" || env == "ohos"]
private const MADV_DONTNEED: Int32 = 4

// PLATFORM-DEBT(CANGJIE_ASAN_SUPPORT): RegionInfo ReleaseUnits OnHeapMadvise bridge missing
// RegionInfo.h:585-587. This is the explicit post-release boundary for non-ASAN builds.
private func OnHeapMadvise(unitAddress: CPointer<Unit>, size: UIntNative): Unit {}

// RegionInfo.h:49-52. C++ integer promotion performs the bit math above the
// uint8_t/uint16_t width; the width mask truncates the complement back to T.
// This split also avoids the selfhost backend's loop-carried bitwise-value gap.
private func SetAtomicValuePart2(oldValue: UInt64, pos: UIntNative, bitLen: UIntNative,
    newValue: UInt64, widthMask: UInt64): UInt64 {
    let bitMask = (1u64.wrappingShl(UInt64(bitLen)) - 1u64).wrappingShl(UInt64(pos))
    let unchangedBitMask = widthMask ^ bitMask
    let changedBits = newValue.wrappingShl(UInt64(pos)) & bitMask
    let unchangedBits = oldValue & unchangedBitMask
    return changedBits | unchangedBits
}

// Heap/Allocator/RegionInfo.h:35-58; concrete UInt8 instantiation of BitField.
@C
public struct BitFieldU8 {
    public var fieldVal: UInt8

    public init(value: UInt8) {
        fieldVal = value
    }

    // RegionInfo.h:40-45.
    public static func GetAtomicValue(bitField: CPointer<BitFieldU8>,
        pos: UIntNative, bitLen: UIntNative): UInt8 {
        unsafe {
            let field = CPointer<UInt8>(bitField)
            let value = cj_atomic_u8_load(field)
            let bitMask = UInt8(
                (1u64.wrappingShl(UInt64(bitLen)) - 1u64).wrappingShl(UInt64(pos)))
            return value & bitMask
        }
    }

    // RegionInfo.h:46-58.
    public static func SetAtomicValue(bitField: CPointer<BitFieldU8>,
        pos: UIntNative, bitLen: UIntNative, newValue: UInt8): Unit {
        unsafe {
            let field = CPointer<UInt8>(bitField)
            var oldValue = cj_atomic_u8_load(field)
            let expected = CPointer<UInt8>(inout oldValue)
            while (true) {
                let newFieldValue = UInt8(SetAtomicValuePart2(
                    UInt64(oldValue), pos, bitLen, UInt64(newValue), 0xffu64))
                if (cj_atomic_u8_cas(field, expected, newFieldValue) != 0) {
                    return
                }
            }
        }
    }
}

// Heap/Allocator/RegionInfo.h:35-58; concrete UInt16 instantiation of BitField.
@C
public struct BitFieldU16 {
    public var fieldVal: UInt16

    public init(value: UInt16) {
        fieldVal = value
    }

    // RegionInfo.h:40-45.
    public static func GetAtomicValue(bitField: CPointer<BitFieldU16>,
        pos: UIntNative, bitLen: UIntNative): UInt16 {
        unsafe {
            let field = CPointer<UInt16>(bitField)
            let value = cj_atomic_u16_load(field)
            let bitMask = UInt16(
                (1u64.wrappingShl(UInt64(bitLen)) - 1u64).wrappingShl(UInt64(pos)))
            return value & bitMask
        }
    }

    // RegionInfo.h:46-58.
    public static func SetAtomicValue(bitField: CPointer<BitFieldU16>,
        pos: UIntNative, bitLen: UIntNative, newValue: UInt16): Unit {
        unsafe {
            let field = CPointer<UInt16>(bitField)
            var oldValue = cj_atomic_u16_load(field)
            let expected = CPointer<UInt16>(inout oldValue)
            while (true) {
                let newFieldValue = UInt16(SetAtomicValuePart2(
                    UInt64(oldValue), pos, bitLen, UInt64(newValue), 0xffffu64))
                if (cj_atomic_u16_cas(field, expected, newFieldValue) != 0) {
                    return
                }
            }
        }
    }
}

// RegionInfo.h:451-458. C enums map to integer aliases in Cangjie's C ABI.
public type UnitRole = UInt8
public const FREE_UNITS: UnitRole = 0u8
public const SMALL_SIZED_UNITS: UnitRole = 1u8
public const LARGE_SIZED_UNITS: UnitRole = 2u8
public const SUBORDINATE_UNIT: UnitRole = 3u8

// RegionInfo.h:463-490.
public type RegionType = UInt8
public const FREE_REGION: RegionType = 0u8
public const THREAD_LOCAL_REGION: RegionType = 1u8
public const RECENT_FULL_REGION: RegionType = 2u8
public const FROM_REGION: RegionType = 3u8
public const LONE_FROM_REGION: RegionType = 4u8
public const UNMOVABLE_FROM_REGION: RegionType = 5u8
public const TO_REGION: RegionType = 6u8
public const FULL_PINNED_REGION: RegionType = 7u8
public const RECENT_PINNED_REGION: RegionType = 8u8
public const RAW_POINTER_PINNED_REGION: RegionType = 9u8
public const TL_RAW_POINTER_REGION: RegionType = 10u8
public const TL_LARGE_RAW_POINTER_REGION: RegionType = 11u8
public const LARGE_REGION: RegionType = 12u8
public const RECENT_LARGE_REGION: RegionType = 13u8
public const GARBAGE_REGION: RegionType = 14u8

// RegionInfo.h:78-85.
public type RouteState = UInt8
public const NORMAL: RouteState = 0u8
public const FORWARDABLE: RouteState = 1u8
public const ROUTING: RouteState = 2u8
public const ROUTED: RouteState = 3u8
public const COMPACTED: RouteState = 4u8
public const FORWARDED: RouteState = 5u8

// RegionInfo.h:980-989.
public const BIT_LENGTH: UIntNative = 4
public const REGION_TYPE_FLAG: UIntNative = 0
public const TRACE_REGION_FLAG: UIntNative = BIT_LENGTH
public const IN_GHOST_FROM_REGION_FLAG: UIntNative = 5
public const MARKED_REGION_FLAG: UIntNative = 6
public const ENQUEUED_REGION_FLAG: UIntNative = 7
public const RESURRECTED_REGION_FLAG: UIntNative = 8

// Heap/Collector/LiveInfo.h:200-213.
@C
public struct RouteInfo {
    public static const INVALID_VALUE: UInt32 = 0xffffffffu32

    public var toRegion1StartAddress: UIntNative
    public var toRegion1UsedBytes: UInt32
    public var toRegion2Idx: UInt32

    public init() {
        toRegion1StartAddress = 0
        toRegion1UsedBytes = 0
        toRegion2Idx = 0
    }

    public mut func SetRouteInfo(to1: UIntNative, to1used!: UInt32 = 0u32,
        to2!: UInt32 = INVALID_VALUE): Unit {
        toRegion1StartAddress = to1
        toRegion1UsedBytes = to1used
        toRegion2Idx = to2
    }
}

// RegionInfo.h:991-1054. The two C++ pointer unions each occupy one opaque pointer;
// the two bit-field unions each occupy their concrete BitField instantiation.
@C
public struct UnitMetadata {
    public var allocPtr: UIntNative
    public var regionEnd: UIntNative
    public var nextRegionIdx: UInt32
    public var prevRegionIdx: UInt32
    public var liveByteCount: UInt32
    public var rawPointerObjectCount: Int32
    public var liveInfo: CPointer<Unit>
    public var liveInfo0: CPointer<Unit>
    public var regionEnd0: UIntNative
    public var routeInfo: RouteInfo
    public var nextRegionIdx0: UInt32
    public var unitRoleBitField: BitFieldU8
    public var regionStateBitField: BitFieldU16
    public var routeState: RouteState
    public var rwLock: RwLock

    public init() {
        allocPtr = 0
        regionEnd = 0
        nextRegionIdx = 0u32
        prevRegionIdx = 0u32
        liveByteCount = 0u32
        rawPointerObjectCount = 0
        liveInfo = CPointer<Unit>()
        liveInfo0 = CPointer<Unit>()
        regionEnd0 = 0
        routeInfo = RouteInfo()
        nextRegionIdx0 = 0u32
        unitRoleBitField = BitFieldU8(0u8)
        regionStateBitField = BitFieldU16(0u16)
        routeState = NORMAL
        rwLock = RwLock()
    }
}

// RegionInfo.h:1056-1120. UnitInfo and RegionInfo are distinct C++ types with the
// same sole field and therefore the same address-calculation size.
@C
public struct UnitInfo {
    public static var heapStartAddress: UIntNative = 0
    public static var totalUnitCount: UIntNative = 0
    public static const INVALID_IDX: UInt32 = 0xffffffffu32

    public var metadata: UnitMetadata

    public init() {
        metadata = UnitMetadata()
    }

    public static func GetUnitIdxAt(allocAddr: UIntNative): UIntNative {
        if (heapStartAddress <= allocAddr &&
            allocAddr < heapStartAddress + totalUnitCount * RegionInfo.UNIT_SIZE) {
            // RegionManager.cpp:54 and AllocUtil.cj:4; live UNIT_SIZE=4096 is
            // guarded by the original-vs-port execution/layout probe.
            return (allocAddr - heapStartAddress) / 4096
        }
        unsafe { abort() }
        return 0
    }

    public static func GetUnitInfoAt(allocAddr: UIntNative): CPointer<UnitInfo> {
        let idx: UIntNative = GetUnitIdxAt(allocAddr)
        let unit: CPointer<UnitInfo> = GetUnitInfo(idx)
        return unit
    }

    public static func GetUnitAddress(idx: UIntNative): UIntNative {
        if (idx >= totalUnitCount) {
            unsafe { RtFatal(CString(CPointer<UInt8>(inout regionInfoInvariantMessages))) }
        }
        return heapStartAddress + idx * RegionInfo.UNIT_SIZE
    }

    public static func GetUnitInfo(idx: UIntNative): CPointer<UnitInfo> {
        if (idx >= totalUnitCount) {
            unsafe { RtFatal(CString(CPointer<UInt8>(inout regionInfoInvariantMessages) + 44)) }
        }
        let unitSize: UIntNative = sizeOf<UnitInfo>()
        let address = heapStartAddress - (idx + 1) * unitSize
        let unit: CPointer<UnitInfo> = unsafe {
            CPointer<UnitInfo>(CPointer<UInt8>() + Int64(address))
        }
        return unit
    }

    public static func GetUnitIdx(unit: CPointer<UnitInfo>): UIntNative {
        let ptr: UIntNative = unit.toUIntNative()
        if (ptr < heapStartAddress) {
            let unitSize: UIntNative = sizeOf<UnitInfo>()
            return (heapStartAddress - ptr).wrappingDiv(unitSize) - 1
        }
        unsafe { RtFatal(CString(CPointer<UInt8>(inout regionInfoInvariantMessages) + 85)) }
        return 0
    }
}

// RegionInfo.h:1157-1174.
public struct UnitInfoArray {
    private let unitArray: CPointer<UnitInfo>
    private let size: UIntNative

    public init(unit: CPointer<UnitInfo>, size: UIntNative) {
        let lastUnitAddress: UIntNative = unit.toUIntNative() - (size - 1) * sizeOf<UnitInfo>()
        unitArray = unsafe { CPointer<UnitInfo>(CPointer<UInt8>() + Int64(lastUnitAddress)) }
        this.size = size
    }

    public operator func [](index: UIntNative): CPointer<UnitInfo> {
        if (index >= size) {
            unsafe { RtFatal(CString(CPointer<UInt8>(inout regionInfoInvariantMessages) + 130)) }
        }
        let offset: Int64 = Int64(size - index - 1)
        let unit: CPointer<UnitInfo> = unsafe { unitArray + offset }
        return unit
    }
}

// RegionInfo.h:63-76,991-1054,1211. Its only field is the same UnitMetadata as UnitInfo.
@C
public struct RegionInfo {
    // RegionInfo.h:87 and RegionManager.cpp:31-54. Linux/OHOS runtime pages are 4 KiB;
    // the allocator foundation's page constant is the same value.
    public static let UNIT_SIZE: UIntNative = UIntNative(ALLOC_UTIL_PAGE_SIZE)

    public var metadata: UnitMetadata

    // RegionInfo.h:124-128.
    public init() {
        metadata = UnitMetadata()
        metadata.allocPtr = 0
        metadata.regionEnd = 0
    }

    // RegionInfo.h:492-496.
    public static func Initialize(nUnit: UIntNative, heapAddress: UIntNative): Unit {
        UnitInfo.totalUnitCount = nUnit
        UnitInfo.heapStartAddress = heapAddress
    }

    // RegionInfo.h:498-505.
    public static func GetRegionInfo(idx: UInt32): CPointer<RegionInfo> {
        let unit: CPointer<UnitInfo> = UnitInfo.GetUnitInfo(UIntNative(idx))
        let metadata: UnitMetadata = unsafe { unit.read().metadata }
        if ((metadata.unitRoleBitField.fieldVal & 0x0fu8) == SUBORDINATE_UNIT) {
            let owner: CPointer<RegionInfo> = CPointer<RegionInfo>(metadata.liveInfo)
            return owner
        }
        let region: CPointer<RegionInfo> = CPointer<RegionInfo>(unit)
        return region
    }

    // RegionInfo.h:507-514.
    public static func GetRegionInfoAt(allocAddr: UIntNative): CPointer<RegionInfo> {
        let unit: CPointer<UnitInfo> = UnitInfo.GetUnitInfoAt(allocAddr)
        let metadata: UnitMetadata = unsafe { unit.read().metadata }
        if ((metadata.unitRoleBitField.fieldVal & 0x0fu8) == SUBORDINATE_UNIT) {
            let owner: CPointer<RegionInfo> = CPointer<RegionInfo>(metadata.liveInfo)
            return owner
        }
        let region: CPointer<RegionInfo> = CPointer<RegionInfo>(unit)
        return region
    }

    // Heap/Allocator/RegionInfo.h:516-520
    // GC-DEFERRED: needs Collector
    public static func InGhostFromRegion(obj: CPointer<Unit>): Bool {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1504)) }
        return false
    }

    // Heap/Allocator/RegionInfo.h:522-532
    // GC-DEFERRED: needs Collector
    public static func GetGhostFromRegionAt(allocAddr: UIntNative): CPointer<RegionInfo> {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1570)) }
        return CPointer<RegionInfo>()
    }

    // RegionInfo.h:534-538.
    public static func InitFreeRegion(unitIdx: UIntNative, nUnit: UIntNative): Unit {
        let region: CPointer<RegionInfo> = CPointer<RegionInfo>(UnitInfo.GetUnitInfo(unitIdx))
        region.InitRegionInfo(nUnit, FREE_UNITS)
    }

    // RegionInfo.h:540-545.
    public static func InitRegion(unitIdx: UIntNative, nUnit: UIntNative,
        uclass: UnitRole): CPointer<RegionInfo> {
        let region: CPointer<RegionInfo> = CPointer<RegionInfo>(UnitInfo.GetUnitInfo(unitIdx))
        region.InitRegion(nUnit, uclass)
        return region
    }

    // RegionInfo.h:547-551.
    public static func InitRegionAt(addr: UIntNative, nUnit: UIntNative,
        uclass: UnitRole): CPointer<RegionInfo> {
        let idx: UIntNative = UnitInfo.GetUnitIdxAt(addr)
        let region: CPointer<RegionInfo> = InitRegion(idx, nUnit, uclass)
        return region
    }

    // RegionInfo.h:553.
    public static func GetUnitAddress(unitIdx: UIntNative): UIntNative {
        let address: UIntNative = UnitInfo.GetUnitAddress(unitIdx)
        return address
    }

    // RegionInfo.h:555-562.
    public static func ClearUnits(idx: UIntNative, cnt: UIntNative): Unit {
        let unitAddress: UIntNative = GetUnitAddress(idx)
        let size: UIntNative = cnt * UNIT_SIZE
        let unitPointer = unsafe { CPointer<Unit>(CPointer<UInt8>() + Int64(unitAddress)) }
        unsafe { let _ = memset(unitPointer, 0, size) }
    }

    // RegionInfo.h:564-588, `_WIN64` branch.
    @When[os == "Windows"]
    public static func ReleaseUnits(idx: UIntNative, cnt: UIntNative): Unit {
        let address: UIntNative = GetUnitAddress(idx)
        let unitAddress: CPointer<Unit> = unsafe {
            CPointer<Unit>(CPointer<UInt8>() + Int64(address))
        }
        let size: UIntNative = cnt * UNIT_SIZE
        if (unsafe { VirtualFree(unitAddress, size, MEM_DECOMMIT) == 0 }) {
            unsafe { RtFatal(CString(CPointer<UInt8>(inout regionInfoInvariantMessages) + 348)) }
        }
        OnHeapMadvise(unitAddress, size)
    }

    // RegionInfo.h:564-588, `__APPLE__` branch.
    @When[os == "macOS" || os == "iOS"]
    public static func ReleaseUnits(idx: UIntNative, cnt: UIntNative): Unit {
        let address: UIntNative = GetUnitAddress(idx)
        let unitAddress: CPointer<Unit> = unsafe {
            CPointer<Unit>(CPointer<UInt8>() + Int64(address))
        }
        let size: UIntNative = cnt * UNIT_SIZE
        unsafe { let _ = memset(unitAddress, 0, size) }
        let ret = unsafe {
            mmap(unitAddress, size, MemMap.PROT_READ | MemMap.PROT_WRITE,
                Int32(MemMap.MAP_PRIVATE | MemMap.MAP_ANONYMOUS | MemMap.MAP_FIXED), -1, 0)
        }
        if (ret.toUIntNative() == UIntNative.Max) {
            unsafe {
                let _ = write(2, CPointer<UInt8>(inout regionInfoInvariantMessages) + 392, 40)
                let _ = write(2, CPointer<UInt8>(inout regionInfoNewline), 1)
            }
        } else if (ret != unitAddress) {
            unsafe {
                let _ = write(2, CPointer<UInt8>(inout regionInfoInvariantMessages) + 433, 52)
                let _ = write(2, CPointer<UInt8>(inout regionInfoNewline), 1)
            }
        }
        OnHeapMadvise(unitAddress, size)
    }

    // RegionInfo.h:564-588, Linux/OHOS branch.
    @When[os == "Linux" || env == "ohos"]
    public static func ReleaseUnits(idx: UIntNative, cnt: UIntNative): Unit {
        let address: UIntNative = GetUnitAddress(idx)
        let unitAddress: CPointer<Unit> = unsafe {
            CPointer<Unit>(CPointer<UInt8>() + Int64(address))
        }
        let size: UIntNative = cnt * UNIT_SIZE
        unsafe { let _ = madvise(unitAddress, size, MADV_DONTNEED) }
        OnHeapMadvise(unitAddress, size)
    }

    // RegionInfo.h:760-814,868-873,948. The explicit pointer is the C++
    // methods' implicit receiver and keeps the mapped descriptor in place.
    public static func SetUnitRole0(region: CPointer<RegionInfo>, role: UnitRole): Unit {
        region.SetUnitRole0(role)
    }

    public static func SetRegionType(region: CPointer<RegionInfo>, regionType: RegionType): Unit {
        region.SetRegionType(regionType)
    }

    public static func SetTraceRegionFlag(region: CPointer<RegionInfo>, flag: UInt8): Unit {
        region.SetTraceRegionFlag(flag)
    }

    // Heap/Allocator/RegionInfo.h:777-780.
    public static func SetInGhostRegion(region: CPointer<RegionInfo>, flag: UInt8): Unit {
        region.SetInGhostRegion(flag)
    }

    public static func SetMarkedRegionFlag(region: CPointer<RegionInfo>, flag: UInt8): Unit {
        region.SetMarkedRegionFlag(flag)
    }

    public static func SetEnqueuedRegionFlag(region: CPointer<RegionInfo>, flag: UInt8): Unit {
        region.SetEnqueuedRegionFlag(flag)
    }

    public static func SetResurrectedRegionFlag(region: CPointer<RegionInfo>, flag: UInt8): Unit {
        region.SetResurrectedRegionFlag(flag)
    }

    public static func GetRegionType(region: CPointer<RegionInfo>): RegionType {
        let regionType: RegionType = region.GetRegionType()
        return regionType
    }

    public static func GetUnitRole(region: CPointer<RegionInfo>): UnitRole {
        let role: UnitRole = region.GetUnitRole()
        return role
    }

    public static func GetUnitIdx(region: CPointer<RegionInfo>): UIntNative {
        let idx: UIntNative = region.GetUnitIdx()
        return idx
    }

    public static func GetRegionStart(region: CPointer<RegionInfo>): UIntNative {
        let address: UIntNative = region.GetRegionStart()
        return address
    }

    public static func GetRegionSize(region: CPointer<RegionInfo>): UIntNative {
        let size: UIntNative = region.GetRegionSize()
        return size
    }

    public static func GetUnitCount(region: CPointer<RegionInfo>): UIntNative {
        let count: UIntNative = region.GetUnitCount()
        return count
    }

    public static func GetRegionAllocPtr(region: CPointer<RegionInfo>): UIntNative {
        let address: UIntNative = region.GetRegionAllocPtr()
        return address
    }

    // RegionInfo.h:863-872.
    public static func Alloc(region: CPointer<RegionInfo>, size: UIntNative): UIntNative {
        return region.Alloc(size)
    }

    public static func IsEmpty(region: CPointer<RegionInfo>): Bool {
        let empty: Bool = region.IsEmpty()
        return empty
    }

    public static func IsTraceRegion(region: CPointer<RegionInfo>): Bool {
        let trace: Bool = region.IsTraceRegion()
        return trace
    }

    public static func IsSmallRegion(region: CPointer<RegionInfo>): Bool {
        let small: Bool = region.IsSmallRegion()
        return small
    }

    public static func IsLargeRegion(region: CPointer<RegionInfo>): Bool {
        let large: Bool = region.IsLargeRegion()
        return large
    }

    public static func IsFreeRegion(region: CPointer<RegionInfo>): Bool {
        let free: Bool = region.IsFreeRegion()
        return free
    }

    // RegionInfo.h:739-752. Explicit receiver package boundary for the
    // ForwardDataManager owner; CPointer extensions are not exported by 0619 cjc.
    public static func CheckAndClearLiveInfo(region: CPointer<RegionInfo>,
        liveInfo: CPointer<Unit>): Unit {
        region.CheckAndClearLiveInfo(liveInfo)
    }
}

// runtime/src/Heap/Allocator/RegionInfo.h:759-763.
// LANG-BOUNDARY: concrete CPointer extension member collision
public func SetUnitRole(self: CPointer<RegionInfo>, role: UnitRole): Unit {
    let field = unsafe { CPointer<BitFieldU8>(CPointer<UInt8>(self) + 76) }
    BitFieldU8.SetAtomicValue(field, 0, BIT_LENGTH, role)
}

// runtime/src/Heap/Allocator/RegionInfo.h:1103-1107.
// LANG-BOUNDARY: concrete CPointer extension member collision
func SetUnitRole(self: CPointer<UnitInfo>, role: UnitRole): Unit {
    let field = unsafe { CPointer<BitFieldU8>(CPointer<UInt8>(self) + 76) }
    BitFieldU8.SetAtomicValue(field, 0, BIT_LENGTH, role)
}

// C++ RegionInfo methods use an implicit RegionInfo* receiver. Extending the mapped
// descriptor pointer preserves that identity while keeping RegionInfo byte-faithful.
extend CPointer<RegionInfo> {
    // Heap/Allocator/RegionInfo.h:95-106
    // GC-DEFERRED: needs Collector
    public func CompareExchangeRouteState(expected: RouteState, newWord: RouteState): Bool {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 0)) }
        return false
    }

    // Heap/Allocator/RegionInfo.h:108-112
    // GC-DEFERRED: needs Collector
    public func GetRouteState(): RouteState {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 74)) }
        return NORMAL
    }

    // Heap/Allocator/RegionInfo.h:114
    // GC-DEFERRED: needs Collector
    public func SetRouteState(state: RouteState): Unit {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 136)) }
    }

    // Heap/Allocator/RegionInfo.h:116
    // GC-DEFERRED: needs Collector
    public func IsCompacted(): Bool {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 198)) }
        return false
    }

    // Heap/Allocator/RegionInfo.h:118
    // GC-DEFERRED: needs Collector
    public func IsRoutingState(): Bool {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 258)) }
        return false
    }

    // Heap/Allocator/RegionInfo.h:120-126
    // GC-DEFERRED: needs Collector
    public func TryLockRouting(curState: RouteState): Bool {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 321)) }
        return false
    }

    // Heap/Allocator/RegionInfo.h:128-133
    // GC-DEFERRED: needs Collector
    public func GetPreLiveBytesInGhostRegion(address: UIntNative): UIntNative {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 384)) }
        return 0
    }

    // Heap/Allocator/RegionInfo.h:146-153
    // GC-DEFERRED: needs Collector
    public func GetLiveInfo(): CPointer<Unit> {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 461)) }
        return CPointer<Unit>()
    }

    // Heap/Allocator/RegionInfo.h:155-177
    // GC-DEFERRED: needs Collector
    public func GetOrAllocLiveInfo(): CPointer<Unit> {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 521)) }
        return CPointer<Unit>()
    }

    // Heap/Allocator/RegionInfo.h:179-190
    // GC-DEFERRED: needs Collector
    public func GetMarkBitmap(): CPointer<Unit> {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 588)) }
        return CPointer<Unit>()
    }

    // Heap/Allocator/RegionInfo.h:192-215
    // GC-DEFERRED: needs Collector
    public func GetOrAllocMarkBitmap(): CPointer<Unit> {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 650)) }
        return CPointer<Unit>()
    }

    // Heap/Allocator/RegionInfo.h:217-228
    // GC-DEFERRED: needs Collector
    public func GetResurrectBitmap(): CPointer<Unit> {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 719)) }
        return CPointer<Unit>()
    }

    // Heap/Allocator/RegionInfo.h:230-254
    // GC-DEFERRED: needs Collector
    public func GetOrAllocResurrectBitmap(): CPointer<Unit> {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 786)) }
        return CPointer<Unit>()
    }

    // Heap/Allocator/RegionInfo.h:256-267
    // GC-DEFERRED: needs Collector
    public func GetEnqueueBitmap(): CPointer<Unit> {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 860)) }
        return CPointer<Unit>()
    }

    // Heap/Allocator/RegionInfo.h:269-293
    // GC-DEFERRED: needs Collector
    public func GetOrAllocEnqueueBitmap(): CPointer<Unit> {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 925)) }
        return CPointer<Unit>()
    }

    // Heap/Allocator/RegionInfo.h:295-300
    // GC-DEFERRED: needs Collector
    public func ResetMarkBit(): Unit {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 997)) }
    }

    // Heap/Allocator/RegionInfo.h:302-317
    // GC-DEFERRED: needs Collector
    public func MarkObject(obj: CPointer<Unit>): Bool {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1058)) }
        return false
    }

    // Heap/Allocator/RegionInfo.h:319-333
    // GC-DEFERRED: needs Collector
    public func MarkObject(obj: CPointer<Unit>, objSize: UIntNative): Bool {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1058)) }
        return false
    }

    // Heap/Allocator/RegionInfo.h:335-349
    // GC-DEFERRED: needs Collector
    public func ResurrectObject(obj: CPointer<Unit>, offset: UIntNative): Bool {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1117)) }
        return false
    }

    // Heap/Allocator/RegionInfo.h:351-366
    // GC-DEFERRED: needs Collector
    public func EnqueueObject(obj: CPointer<Unit>, offset: UIntNative): Bool {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1181)) }
        return false
    }

    // Heap/Allocator/RegionInfo.h:368-379
    // GC-DEFERRED: needs Collector
    public func IsResurrectedObject(obj: CPointer<Unit>): Bool {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1243)) }
        return false
    }

    // Heap/Allocator/RegionInfo.h:381-391
    // GC-DEFERRED: needs Collector
    public func IsResurrectedObject(offset: UIntNative): Bool {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1243)) }
        return false
    }

    // Heap/Allocator/RegionInfo.h:393-404
    // GC-DEFERRED: needs Collector
    public func IsMarkedObject(obj: CPointer<Unit>): Bool {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1311)) }
        return false
    }

    // Heap/Allocator/RegionInfo.h:406-416
    // GC-DEFERRED: needs Collector
    public func IsMarkedObject(offset: UIntNative): Bool {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1311)) }
        return false
    }

    // Heap/Allocator/RegionInfo.h:418-434
    // GC-DEFERRED: needs Collector
    public func IsSurvivedObject(offset: UIntNative): Bool {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1374)) }
        return false
    }

    // Heap/Allocator/RegionInfo.h:436-443
    // GC-DEFERRED: needs Collector
    public func IsEnqueuedObject(offset: UIntNative): Bool {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1439)) }
        return false
    }

    // Heap/Allocator/RegionInfo.h:607-612
    // GC-DEFERRED: needs Collector
    public func GetGhostRegionSize(): UIntNative {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1639)) }
        return 0
    }

    // Heap/Allocator/RegionInfo.h:614
    // GC-DEFERRED: needs Collector
    public func GetGhostRegionUnitCount(): UIntNative {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1706)) }
        return 0
    }

    // Heap/Allocator/RegionInfo.h:624-625
    // GC-DEFERRED: needs Collector
    public func DumpRegionInfo(logType: LogType): Unit {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1778)) }
    }

    // Heap/Allocator/RegionInfo.h:624-626
    // GC-DEFERRED: needs Collector
    public func GetTypeName(): CString {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1841)) }
        return unsafe { CString(CPointer<UInt8>()) }
    }

    // Heap/Allocator/RegionInfo.h:629
    // GC-DEFERRED: needs Collector
    public func VisitAllObjects(callbackPayload: CPointer<Unit>): Unit {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1901)) }
    }

    // Heap/Allocator/RegionInfo.h:630
    // GC-DEFERRED: needs Collector
    public func VisitLiveObjectsUntilFalse(callbackPayload: CPointer<Unit>): Bool {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 1965)) }
        return false
    }

    // Heap/Allocator/RegionInfo.h:648-654
    // GC-DEFERRED: needs Collector
    public func GetRoute(fromObj: CPointer<Unit>): CPointer<Unit> {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 2040)) }
        return CPointer<Unit>()
    }

    // Heap/Allocator/RegionInfo.h:656-688
    // GC-DEFERRED: needs Collector
    public func PrepareForwardableRegion(): Unit {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 2097)) }
    }

    // Heap/Allocator/RegionInfo.h:690-700
    // GC-DEFERRED: needs Collector
    public func ClearGhostRegionBit(): Unit {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 2170)) }
    }

    // Heap/Allocator/RegionInfo.h:705-714
    // GC-DEFERRED: needs Collector
    public func DispelGhostFromRegion(): Unit {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 2238)) }
    }

    // Heap/Allocator/RegionInfo.h:716
    // GC-DEFERRED: needs Collector
    public func IsGhostFromRegion(): Bool {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 2308)) }
        return false
    }

    // Heap/Allocator/RegionInfo.h:739-752. This leaf is consumed by
    // ForwardDataManager::ForwardDataSpace::UnbindPreviousLiveInfo after GC.
    public func CheckAndClearLiveInfo(liveInfo: CPointer<Unit>): Unit {
        if (GetRegionType() == GARBAGE_REGION) {
            return
        }
        let field = unsafe { CPointer<CPointer<Unit>>(CPointer<UInt8>(this) + 32) }
        if (unsafe { field.read(0) }.toUIntNative() == liveInfo.toUIntNative()) {
            unsafe {
                field.write(0, CPointer<Unit>())
                cj_atomic_u32_store_release(CPointer<UInt32>(CPointer<UInt8>(this) + 24), 0u32)
            }
        }
    }

    // Heap/Allocator/RegionInfo.h:732-738
    // GC-DEFERRED: needs Collector
    public func ClearLiveInfo(): Unit {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout collectorDeferredMessages) + 2444)) }
    }

    // Heap/Allocator/RegionInfo.h:643-646
    public func SetRouteInfo(to1: UIntNative, to1used!: UInt32 = 0u32,
        to2!: UInt32 = RouteInfo.INVALID_VALUE): Unit {
        var layout = UnitMetadata()
        let offset = unsafe {
            CPointer<UInt8>(inout layout.routeInfo).toUIntNative() -
                CPointer<UInt8>(inout layout).toUIntNative()
        }
        let routeInfo = unsafe { CPointer<RouteInfo>(CPointer<UInt8>(this) + Int64(offset)) }
        var value = unsafe { routeInfo.read() }
        value.SetRouteInfo(to1, to1used: to1used, to2: to2)
        unsafe { routeInfo.write(value) }
    }

    // RegionInfo.h:764-767.
    public func SetUnitRole0(role: UnitRole): Unit {
        var layout = UnitMetadata()
        let offset = unsafe {
            CPointer<UInt8>(inout layout.unitRoleBitField).toUIntNative() -
                CPointer<UInt8>(inout layout).toUIntNative()
        }
        let field = unsafe { CPointer<BitFieldU8>(CPointer<UInt8>(this) + Int64(offset)) }
        BitFieldU8.SetAtomicValue(field,
            BIT_LENGTH, BIT_LENGTH, role)
    }

    // RegionInfo.h:768-772.
    public func SetRegionType(regionType: RegionType): Unit {
        // RegionInfo.h:1030-1051; guarded by the live C++-vs-Cangjie layout probe.
        let field = unsafe { CPointer<BitFieldU16>(CPointer<UInt8>(this) + 78) }
        BitFieldU16.SetAtomicValue(field,
            REGION_TYPE_FLAG, BIT_LENGTH, UInt16(regionType))
    }

    // RegionInfo.h:773-776.
    public func SetTraceRegionFlag(flag: UInt8): Unit {
        let field = unsafe { CPointer<BitFieldU16>(CPointer<UInt8>(this) + 78) }
        BitFieldU16.SetAtomicValue(field,
            TRACE_REGION_FLAG, 1, UInt16(flag))
    }

    // Heap/Allocator/RegionInfo.h:777-780.
    public func SetInGhostRegion(flag: UInt8): Unit {
        var layout = UnitMetadata()
        let offset = unsafe {
            CPointer<UInt8>(inout layout.regionStateBitField).toUIntNative() -
                CPointer<UInt8>(inout layout).toUIntNative()
        }
        let field = unsafe { CPointer<BitFieldU16>(CPointer<UInt8>(this) + Int64(offset)) }
        BitFieldU16.SetAtomicValue(field,
            IN_GHOST_FROM_REGION_FLAG, 1, UInt16(flag))
    }

    // RegionInfo.h:782-785.
    public func SetMarkedRegionFlag(flag: UInt8): Unit {
        let field = unsafe { CPointer<BitFieldU16>(CPointer<UInt8>(this) + 78) }
        BitFieldU16.SetAtomicValue(field,
            MARKED_REGION_FLAG, 1, UInt16(flag))
    }

    // RegionInfo.h:787-790.
    public func SetEnqueuedRegionFlag(flag: UInt8): Unit {
        let field = unsafe { CPointer<BitFieldU16>(CPointer<UInt8>(this) + 78) }
        BitFieldU16.SetAtomicValue(field,
            ENQUEUED_REGION_FLAG, 1, UInt16(flag))
    }

    // RegionInfo.h:791-794.
    public func SetResurrectedRegionFlag(flag: UInt8): Unit {
        let field = unsafe { CPointer<BitFieldU16>(CPointer<UInt8>(this) + 78) }
        BitFieldU16.SetAtomicValue(field,
            RESURRECTED_REGION_FLAG, 1, UInt16(flag))
    }

    // RegionInfo.h:796.
    public func GetRegionType(): RegionType {
        let field = unsafe { CPointer<BitFieldU16>(CPointer<UInt8>(this) + 78) }
        let value = BitFieldU16.GetAtomicValue(field, REGION_TYPE_FLAG, BIT_LENGTH)
        let regionType = UInt8(value)
        return regionType
    }

    // RegionInfo.h:797.
    public func GetUnitRole(): UnitRole {
        let field = unsafe { CPointer<BitFieldU8>(CPointer<UInt8>(this) + 76) }
        let value = BitFieldU8.GetAtomicValue(field, 0, BIT_LENGTH)
        return value
    }

    // RegionInfo.h:799.
    public func GetUnitIdx(): UIntNative {
        let idx = UnitInfo.GetUnitIdx(CPointer<UnitInfo>(this))
        return idx
    }

    // RegionInfo.h:801-808.
    public func GetRegionStart(): UIntNative {
        let ptr = this.toUIntNative()
        if (ptr >= UnitInfo.heapStartAddress) {
            unsafe { RtFatal(CString(CPointer<UInt8>(inout regionInfoInvariantMessages) + 163)) }
        }
        // RegionInfo.h:65 and 1087-1092; live sizeof(UnitInfo)=88 is guarded by
        // the original-vs-port layout oracle, and avoids a runtime generic sizeof.
        let idx = (UnitInfo.heapStartAddress - ptr).wrappingDiv(88) - 1
        if (idx >= UnitInfo.totalUnitCount) {
            unsafe { RtFatal(CString(CPointer<UInt8>(inout regionInfoInvariantMessages) + 215)) }
        }
        return idx * RegionInfo.UNIT_SIZE + UnitInfo.heapStartAddress
    }

    // RegionInfo.h:598-603.
    public func GetRegionSize(): UIntNative {
        let regionStart = GetRegionStart()
        let regionEnd = unsafe { this.read().metadata.regionEnd }
        if (regionEnd <= regionStart) {
            unsafe { RtFatal(CString(CPointer<UInt8>(inout regionInfoInvariantMessages) + 261)) }
        }
        return regionEnd - regionStart
    }

    // RegionInfo.h:605.
    public func GetUnitCount(): UIntNative {
        let size = GetRegionSize()
        return size.wrappingDiv(RegionInfo.UNIT_SIZE)
    }

    // RegionInfo.h:814.
    public func GetRegionAllocPtr(): UIntNative {
        let allocPtr = unsafe { this.read().metadata.allocPtr }
        return allocPtr
    }

    // RegionInfo.h:863-872. UIntNative wrapping addition is the exact C++
    // size_t behavior, including its overflow comparison semantics.
    @NoHeapAlloc
    public func Alloc(size: UIntNative): UIntNative {
        let limit = unsafe { this.read().metadata.regionEnd }
        let allocPtr = unsafe { this.read().metadata.allocPtr }
        let next = allocPtr.wrappingAdd(size)
        if (next <= limit) {
            unsafe { CPointer<UIntNative>(CPointer<UInt8>(this)).write(0, next) }
            return allocPtr
        }
        return 0
    }

    // RegionInfo.h:592-596.
    public func IsEmpty(): Bool {
        if (!IsSmallRegion()) {
            unsafe { RtFatal(CString(CPointer<UInt8>(inout regionInfoInvariantMessages) + 306)) }
        }
        let allocPtr = GetRegionAllocPtr()
        let regionStart = GetRegionStart()
        return allocPtr == regionStart
    }

    // RegionInfo.h:868.
    public func IsTraceRegion(): Bool {
        let bits = unsafe { this.read().metadata.regionStateBitField.fieldVal }
        let shift = UInt16(TRACE_REGION_FLAG)
        return (bits & (1u16 << shift)) != 0u16
    }

    // RegionInfo.h:871.
    public func IsSmallRegion(): Bool {
        let role = GetUnitRole()
        return role == SMALL_SIZED_UNITS
    }

    // RegionInfo.h:873.
    public func IsLargeRegion(): Bool {
        let role = GetUnitRole()
        return role == LARGE_SIZED_UNITS
    }

    // RegionInfo.h:948.
    public func IsFreeRegion(): Bool {
        let role = GetUnitRole()
        return role == FREE_UNITS
    }

    // RegionInfo.h:1180-1195.
    func InitRegionInfo(nUnit: UIntNative, uClass: UnitRole): Unit {
        // RegionInfo.h:991-1054 gives the exact live offsets below; the parity
        // probe derives and checks every one from both production layouts.
        let allocPtr = GetRegionStart()
        unsafe {
            CPointer<UIntNative>(CPointer<UInt8>(this)).write(0, allocPtr)
            CPointer<UIntNative>(CPointer<UInt8>(this) + 8).write(0,
                allocPtr + nUnit * RegionInfo.UNIT_SIZE)
            CPointer<UInt32>(CPointer<UInt8>(this) + 20).write(0, UnitInfo.INVALID_IDX)
            CPointer<UInt32>(CPointer<UInt8>(this) + 16).write(0, UnitInfo.INVALID_IDX)
            CPointer<UInt32>(CPointer<UInt8>(this) + 24).write(0, 0u32)
            CPointer<CPointer<Unit>>(CPointer<UInt8>(this) + 32).write(0, CPointer<Unit>())
        }
        SetRegionType(FREE_REGION)
        SetUnitRole(this, uClass)
        SetTraceRegionFlag(0u8)
        SetMarkedRegionFlag(0u8)
        SetEnqueuedRegionFlag(0u8)
        SetResurrectedRegionFlag(0u8)
        unsafe {
            let field = CPointer<Int32>(CPointer<UInt8>(this) + 28)
            cj_atomic_i32_store(field, 0)
        }
    }

    // RegionInfo.h:1197-1208.
    func InitRegion(nUnit: UIntNative, uClass: UnitRole): Unit {
        InitRegionInfo(nUnit, uClass)
        let unit = CPointer<UnitInfo>(this)
        let array = UnitInfoArray(unit, nUnit)
        for (i in 1..nUnit) {
            let subordinate = array[i]
            subordinate.InitSubordinateUnit(this)
        }
    }
}

// RegionInfo.h:1098-1101 deletes UnitInfo lifecycle; these methods operate only
// on already-existing native records.
extend CPointer<UnitInfo> {
    // RegionInfo.h:1141-1145.
    func InitSubordinateUnit(owner: CPointer<RegionInfo>): Unit {
        SetUnitRole(this, SUBORDINATE_UNIT)
        unsafe {
            CPointer<CPointer<Unit>>(CPointer<UInt8>(this) + 32).write(0, CPointer<Unit>(owner))
        }
    }
}
