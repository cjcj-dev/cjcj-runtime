import rt.base.*

// Base/Types.h:21-55. Host-selected scalar and pointer vocabulary ABI record.
main(): Int64 {
    println("TYPES_INT ${sizeOf<U1>()}/${alignOf<U1>()} ${sizeOf<I1>()}/${alignOf<I1>()} " +
        "${sizeOf<U8>()}/${alignOf<U8>()} ${sizeOf<I8>()}/${alignOf<I8>()} " +
        "${sizeOf<U16>()}/${alignOf<U16>()} ${sizeOf<I16>()}/${alignOf<I16>()} " +
        "${sizeOf<U32>()}/${alignOf<U32>()} ${sizeOf<I32>()}/${alignOf<I32>()} " +
        "${sizeOf<U64>()}/${alignOf<U64>()} ${sizeOf<I64>()}/${alignOf<I64>()}")
    println("TYPES_FLOAT ${sizeOf<F16>()}/${alignOf<F16>()} ${sizeOf<F32>()}/${alignOf<F32>()} " +
        "${sizeOf<F64>()}/${alignOf<F64>()}")
    println("TYPES_PTR ${sizeOf<Uptr>()}/${alignOf<Uptr>()} ${sizeOf<Sptr>()}/${alignOf<Sptr>()} " +
        "${sizeOf<Size>()}/${alignOf<Size>()} ${sizeOf<USize>()}/${alignOf<USize>()} " +
        "${sizeOf<Index>()}/${alignOf<Index>()} ${sizeOf<Offset>()}/${alignOf<Offset>()} " +
        "${sizeOf<ArchUInt>()}/${alignOf<ArchUInt>()}")
    return 0
}
