package callee.noheap

import rt.exception.*

public CFunc func CalleeSavedSetValueRoot(context: CPointer<CalleeSavedRegisterContext>,
    idx: UInt32, value: UInt64): Unit {
    unsafe {
        var current = context.read()
        current.SetValueByIdx(idx, value)
        context.write(current)
    }
}
