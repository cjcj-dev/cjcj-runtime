set pagination off
set confirm off
set breakpoint pending on
set print thread-events off
python
import gdb

active = 0
counts = {"roots": 0, "malloc": 0, "mcc_new": 0, "tls": 0}

class RootFinish(gdb.FinishBreakpoint):
    def __init__(self, frame):
        super().__init__(frame, internal=True)
        self.silent = True
    def stop(self):
        global active
        active -= 1
        return False

class RootBreakpoint(gdb.Breakpoint):
    def stop(self):
        global active
        active += 1
        counts["roots"] += 1
        RootFinish(gdb.newest_frame())
        return False

class EventBreakpoint(gdb.Breakpoint):
    def __init__(self, spec, kind):
        super().__init__(spec, internal=True)
        self.silent = True
        self.kind = kind
    def stop(self):
        if active > 0:
            counts[self.kind] += 1
        return False

for symbol in ("CJRT_G1StackOnlyProbe", "CJRT_G5ThreadLocalProbe"):
    breakpoint = RootBreakpoint(symbol)
    breakpoint.silent = True
EventBreakpoint("malloc", "malloc")
for symbol in (
    "MCC_NewAndInitEnumTupleObject", "MCC_NewArray", "MCC_NewArray16", "MCC_NewArray32",
    "MCC_NewArray64", "MCC_NewArray8", "MCC_NewArrayGeneric", "MCC_NewCJThread",
    "MCC_NewCJThreadNoReturn", "MCC_NewExclusiveCJThread", "MCC_NewFinalizer",
    "MCC_NewGenericObject", "MCC_NewObjArray", "MCC_NewObject", "MCC_NewPinnedObject",
    "MCC_NewWeakRefObject", "CJ_MCC_NewAndInitEnumTupleObject", "CJ_MCC_NewArray",
    "CJ_MCC_NewArray16", "CJ_MCC_NewArray32", "CJ_MCC_NewArray64", "CJ_MCC_NewArray8",
    "CJ_MCC_NewArrayGeneric", "CJ_MCC_NewCJThread", "CJ_MCC_NewCJThreadNoReturn",
    "CJ_MCC_NewFinalizer", "CJ_MCC_NewObjArray", "CJ_MCC_NewObject",
    "CJ_MCC_NewPinnedObject", "CJ_MCC_NewWeakRefObject",
):
    EventBreakpoint(symbol, "mcc_new")
EventBreakpoint("MRT_GetThreadLocalData", "tls")
end
run
python
print("DYNAMIC_SUMMARY roots={roots} malloc_hits={malloc} mcc_new_hits={mcc_new} tls_hits={tls}".format(**counts))
if counts["roots"] != 2 or counts["malloc"] != 0 or counts["mcc_new"] != 0 or counts["tls"] < 1:
    gdb.execute("quit 1")
end
quit
