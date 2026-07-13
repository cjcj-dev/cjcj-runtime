package rt.sync

main(): Int64 {
    return if (Futex(CPointer<Int32>(), 1, 1) == -1) { 0 } else { 1 }
}
