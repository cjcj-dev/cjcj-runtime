// CJThread schedule/include/schedule.h:439-474,
// trace/include/inner/trace.h:20-73, and
// schedule/include/inner/trace_impl.h:27-103.
// Test-only native oracle and bidirectional ABI observer.
#include <cstdarg>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>

#include "trace.h"
#include "trace_impl.h"

namespace {
unsigned char cppMarker[6] {};
unsigned char cppDumpBytes[3] {1, 2, 3};
unsigned char candidateDumpBytes[4] {9, 8, 7, 6};
uint64_t cppCallbackBits = 0;
#ifdef TRACE_VOCAB_ORACLE
constexpr std::size_t VALUE_COUNT = 45;
uint64_t oracleArg0 = 0;
uint64_t oracleArg1 = 0;

struct TraceHooksAlignProbe {
    unsigned char pad;
    TraceHooks value;
};

struct TraceBufHeaderAlignProbe {
    unsigned char pad;
    TraceBufHeader value;
};

struct TraceBufAlignProbe {
    unsigned char pad;
    TraceBuf value;
};
#endif

void PrintRange(const char* label, const uint64_t* values, std::size_t begin, std::size_t count)
{
    std::printf("%s", label);
    for (std::size_t i = 0; i < count; ++i) {
        std::printf(" %llu", static_cast<unsigned long long>(values[begin + i]));
    }
    std::puts("");
}

void PrintVocabulary(const uint64_t* values)
{
    PrintRange("TRACE_TYPES", values, 0, 3);
    PrintRange("TRACE_EVENTS", values, 3, 21);
    PrintRange("TRACE_ERRORS", values, 24, 11);
    PrintRange("TRACE_CONSTANTS", values, 35, 10);
}

void PrintBytes(const char* name, const unsigned char* bytes, std::size_t size)
{
    std::printf("TRACE_STRING %s length=%zu bytes=", name, size);
    for (std::size_t i = 0; i < size; ++i) {
        std::printf("%02x", static_cast<unsigned>(bytes[i]));
    }
    std::puts("");
}

void PrintStrings(const unsigned char* header, const unsigned char* exitString,
                  const unsigned char* resched, const unsigned char* netBlock,
                  const unsigned char* netUnblock, const unsigned char* unblock,
                  const unsigned char* unknown, const unsigned char* runtime)
{
    PrintBytes("TRACE_HEADER", header, sizeof(TRACE_HEADER));
    PrintBytes("TRACE_EXIT_STRING", exitString, sizeof(TRACE_EXIT_STRING));
    PrintBytes("TRACE_RESCHED_STRING", resched, sizeof(TRACE_RESCHED_STRING));
    PrintBytes("TRACE_NET_BLOCK_STRING", netBlock, sizeof(TRACE_NET_BLOCK_STRING));
    PrintBytes("TRACE_NET_UNBLOCK_STRING", netUnblock, sizeof(TRACE_NET_UNBLOCK_STRING));
    PrintBytes("TRACE_UNBLOCK_STRING", unblock, sizeof(TRACE_UNBLOCK_STRING));
    PrintBytes("TRACE_UNKNOWN_STRING", unknown, sizeof(TRACE_UNKNOWN_STRING));
    PrintBytes("TRACE_RUNTIME_STRING", runtime, sizeof(TRACE_RUNTIME_STRING));
}

void PrintLayouts(const uint64_t* layout)
{
    std::printf("TRACE_HOOKS_LAYOUT size=%llu align=%llu deregister=%llu start=%llu stop=%llu "
                "event=%llu dump=%llu reader=%llu\n",
        static_cast<unsigned long long>(layout[0]), static_cast<unsigned long long>(layout[1]),
        static_cast<unsigned long long>(layout[2]), static_cast<unsigned long long>(layout[3]),
        static_cast<unsigned long long>(layout[4]), static_cast<unsigned long long>(layout[5]),
        static_cast<unsigned long long>(layout[6]), static_cast<unsigned long long>(layout[7]));
    std::printf("TRACE_HEADER_LAYOUT size=%llu align=%llu dulink=%llu ticks=%llu pos=%llu\n",
        static_cast<unsigned long long>(layout[8]), static_cast<unsigned long long>(layout[9]),
        static_cast<unsigned long long>(layout[10]), static_cast<unsigned long long>(layout[11]),
        static_cast<unsigned long long>(layout[12]));
    std::printf("TRACE_BUF_LAYOUT size=%llu align=%llu header=%llu arr=%llu arr_length=%llu "
                "derived_length=%llu\n",
        static_cast<unsigned long long>(layout[13]), static_cast<unsigned long long>(layout[14]),
        static_cast<unsigned long long>(layout[15]), static_cast<unsigned long long>(layout[16]),
        static_cast<unsigned long long>(layout[17]), static_cast<unsigned long long>(layout[18]));
}

void CppDeregister()
{
    cppCallbackBits |= UINT64_C(1) << 0;
}

bool CppStart(unsigned short traceType)
{
    if (traceType == TRACE_TYPE_RUNTIME) {
        cppCallbackBits |= UINT64_C(1) << 1;
    }
    return true;
}

bool CppStop()
{
    cppCallbackBits |= UINT64_C(1) << 2;
    return true;
}

void CppEvent(TraceEvent event, int skip, void* mutator, int argNum, va_list)
{
    if (event == TRACE_EV_CJTHREAD_RESCHED && skip == 7 && mutator == &cppMarker[5] && argNum == 2) {
        cppCallbackBits |= UINT64_C(1) << 3;
    }
}

unsigned char* CppDump(int* len)
{
    cppCallbackBits |= UINT64_C(1) << 4;
    *len = 3;
    return cppDumpBytes;
}

CJThread* CppReader()
{
    cppCallbackBits |= UINT64_C(1) << 5;
    return reinterpret_cast<CJThread*>(&cppMarker[4]);
}

#ifdef TRACE_VOCAB_ORACLE
void OracleDeregister() {}
bool OracleStart(unsigned short traceType) { return traceType == TRACE_TYPE_ALL; }
bool OracleStop() { return true; }

void OracleEvent(TraceEvent event, int skip, void* mutator, int argNum, va_list args)
{
    if (event == TRACE_EV_CJTHREAD_UNBLOCK && skip == 5 && mutator == &cppMarker[5] && argNum == 2) {
        oracleArg0 = va_arg(args, unsigned long long);
        oracleArg1 = va_arg(args, unsigned long long);
    }
}

unsigned char* OracleDump(int* len)
{
    *len = 4;
    return candidateDumpBytes;
}

CJThread* OracleReader()
{
    return reinterpret_cast<CJThread*>(&cppMarker[4]);
}
#endif

void WriteCppRecords(TraceBufHeader* header, TraceBuf* buffer, TraceHooks* hooks)
{
    std::memset(header, 0, sizeof(*header));
    std::memset(buffer, 0, sizeof(*buffer));
    std::memset(hooks, 0, sizeof(*hooks));
    header->dulink.prev = reinterpret_cast<Dulink*>(&cppMarker[0]);
    header->dulink.next = reinterpret_cast<Dulink*>(&cppMarker[1]);
    header->lastTicks = UINT64_C(0x0123456789abcdef);
    header->pos = 0x10203040;
    buffer->header.dulink.prev = reinterpret_cast<Dulink*>(&cppMarker[1]);
    buffer->header.dulink.next = reinterpret_cast<Dulink*>(&cppMarker[0]);
    buffer->header.lastTicks = UINT64_C(0xfedcba9876543210);
    buffer->header.pos = 0x50607080;
    buffer->arr[0] = 0x11;
    buffer->arr[TRACE_BUF_LENGTH / 2] = 0x22;
    buffer->arr[TRACE_BUF_LENGTH - 1] = 0x33;
    hooks->traceDeregister = CppDeregister;
    hooks->traceStart = CppStart;
    hooks->traceStop = CppStop;
    hooks->traceRecordEvent = CppEvent;
    hooks->traceDump = CppDump;
    hooks->traceReaderGet = CppReader;
}

#ifdef TRACE_VOCAB_ORACLE
uint64_t CheckCppRecords(const TraceBufHeader& header, const TraceBuf& buffer)
{
    uint64_t failures = 0;
    failures |= header.dulink.prev == reinterpret_cast<const Dulink*>(&cppMarker[0]) ? 0 : UINT64_C(1) << 0;
    failures |= header.dulink.next == reinterpret_cast<const Dulink*>(&cppMarker[1]) ? 0 : UINT64_C(1) << 1;
    failures |= header.lastTicks == UINT64_C(0x0123456789abcdef) ? 0 : UINT64_C(1) << 2;
    failures |= header.pos == 0x10203040 ? 0 : UINT64_C(1) << 3;
    failures |= buffer.header.dulink.prev == reinterpret_cast<const Dulink*>(&cppMarker[1]) ? 0 : UINT64_C(1) << 4;
    failures |= buffer.header.dulink.next == reinterpret_cast<const Dulink*>(&cppMarker[0]) ? 0 : UINT64_C(1) << 5;
    failures |= buffer.header.lastTicks == UINT64_C(0xfedcba9876543210) ? 0 : UINT64_C(1) << 6;
    failures |= buffer.header.pos == 0x50607080 ? 0 : UINT64_C(1) << 7;
    failures |= buffer.arr[0] == 0x11 ? 0 : UINT64_C(1) << 8;
    failures |= buffer.arr[TRACE_BUF_LENGTH / 2] == 0x22 ? 0 : UINT64_C(1) << 9;
    failures |= buffer.arr[TRACE_BUF_LENGTH - 1] == 0x33 ? 0 : UINT64_C(1) << 10;
    return failures;
}
#endif

void InvokeEvent(TraceEventFunc function, ...)
{
    va_list args;
    va_start(args, function);
    function(TRACE_EV_CJTHREAD_UNBLOCK, 5, &cppMarker[5], 2, args);
    va_end(args);
}

uint64_t CheckCandidateRecords(const TraceBufHeader& header, const TraceBuf& buffer,
                               const TraceHooks& hooks)
{
    uint64_t failures = 0;
    failures |= header.dulink.prev == reinterpret_cast<const Dulink*>(&cppMarker[2]) ? 0 : UINT64_C(1) << 0;
    failures |= header.dulink.next == reinterpret_cast<const Dulink*>(&cppMarker[3]) ? 0 : UINT64_C(1) << 1;
    failures |= header.lastTicks == UINT64_C(0x8899aabbccddeeff) ? 0 : UINT64_C(1) << 2;
    failures |= header.pos == 0x11223344 ? 0 : UINT64_C(1) << 3;
    failures |= buffer.header.dulink.prev == reinterpret_cast<const Dulink*>(&cppMarker[3]) ? 0 : UINT64_C(1) << 4;
    failures |= buffer.header.dulink.next == reinterpret_cast<const Dulink*>(&cppMarker[2]) ? 0 : UINT64_C(1) << 5;
    failures |= buffer.header.lastTicks == UINT64_C(0x7766554433221100) ? 0 : UINT64_C(1) << 6;
    failures |= buffer.header.pos == 0x55667788 ? 0 : UINT64_C(1) << 7;
    failures |= buffer.arr[0] == 0xaa ? 0 : UINT64_C(1) << 8;
    failures |= buffer.arr[TRACE_BUF_LENGTH / 2] == 0xbb ? 0 : UINT64_C(1) << 9;
    failures |= buffer.arr[TRACE_BUF_LENGTH - 1] == 0xcc ? 0 : UINT64_C(1) << 10;

    hooks.traceDeregister();
    failures |= hooks.traceStart(TRACE_TYPE_ALL) ? 0 : UINT64_C(1) << 11;
    failures |= hooks.traceStop() ? 0 : UINT64_C(1) << 12;
    InvokeEvent(hooks.traceRecordEvent, UINT64_C(0x1122334455667788), UINT64_C(0x8877665544332211));
    int len = 0;
    const unsigned char* dump = hooks.traceDump(&len);
    failures |= len == 4 && std::memcmp(dump, candidateDumpBytes, 4) == 0 ? 0 : UINT64_C(1) << 13;
    failures |= hooks.traceReaderGet() == reinterpret_cast<CJThread*>(&cppMarker[4]) ? 0 : UINT64_C(1) << 14;
    return failures;
}

#ifdef TRACE_VOCAB_ORACLE
void FillValues(uint64_t* values)
{
    const uint64_t expected[VALUE_COUNT] = {
        TRACE_TYPE_SCHEDULE, TRACE_TYPE_RUNTIME, TRACE_TYPE_ALL,
        TRACE_EV_NONE, TRACE_EV_BATCH, TRACE_EV_FREQUENCY, TRACE_EV_STACK, TRACE_EV_STRING,
        TRACE_EV_PROC_WAKE, TRACE_EV_PROC_STOP, TRACE_EV_CJTHREAD_CREATE, TRACE_EV_CJTHREAD_START,
        TRACE_EV_CJTHREAD_END, TRACE_EV_CJTHREAD_RESCHED, TRACE_EV_CJTHREAD_SLEEP,
        TRACE_EV_CJTHREAD_BLOCK, TRACE_EV_CJTHREAD_UNBLOCK, TRACE_EV_CJTHREAD_BLOCK_SYNC,
        TRACE_EV_CJTHREAD_BLOCK_NET, TRACE_EV_CJTHREAD_SYSCALL, TRACE_EV_CJTHREAD_SYSEXIT,
        TRACE_EV_GC_START, TRACE_EV_GC_DONE, TRACE_EV_COUNT,
        ERRNO_TRACE_ALREADY_START, ERRNO_TRACE_SHUTDOWN_WRONG, ERRNO_TRACE_BUF_FLUSH_WRONG,
        ERRNO_TRACE_EVENT_WHEN_STOP, ERRNO_TRACE_MALLOC_FAILED, ERRNO_TRACE_READER_SPURIOUS_WAKEUP,
        ERRNO_TRACE_MULTIPLE_READER, ERRNO_TRACE_STOP_EXCEPTION, ERRNO_TRACE_ALREADY_STOP,
        ERRNO_TRACE_STRING_EVENT, ERRNO_TRACE_STACK_EVENT,
        TRACE_EVENT_MAXSIZE, TRACE_STACK_EVENT_MAXSIZE, TRACE_HEADER_LENGTH, TRACE_PATH_LENGTH,
        TRACE_EFFECTIVE_EVENT, TRACE_EFFECTIVE_ARG_NUM, TRACE_BUF_LENGTH, TRACE_UINT64_SHIFTS,
        TRACE_UINT64_SHIFT_THRESHOLD, TRACE_STACK_ARG_NUM
    };
    std::memcpy(values, expected, sizeof(expected));
}

void FillLayouts(uint64_t* layout)
{
    const uint64_t expected[19] = {
        sizeof(TraceHooks), offsetof(TraceHooksAlignProbe, value),
        offsetof(TraceHooks, traceDeregister), offsetof(TraceHooks, traceStart),
        offsetof(TraceHooks, traceStop), offsetof(TraceHooks, traceRecordEvent),
        offsetof(TraceHooks, traceDump), offsetof(TraceHooks, traceReaderGet),
        sizeof(TraceBufHeader), offsetof(TraceBufHeaderAlignProbe, value),
        offsetof(TraceBufHeader, dulink), offsetof(TraceBufHeader, lastTicks),
        offsetof(TraceBufHeader, pos), sizeof(TraceBuf), offsetof(TraceBufAlignProbe, value),
        offsetof(TraceBuf, header), offsetof(TraceBuf, arr), sizeof(TraceBuf::arr),
        (UINT64_C(64) << 10) - sizeof(TraceBufHeader)
    };
    std::memcpy(layout, expected, sizeof(expected));
}
#endif
} // namespace

extern "C" void TracePrintCandidateVocabulary(const uint64_t* values) { PrintVocabulary(values); }

extern "C" void TracePrintCandidateStrings(const unsigned char* header, const unsigned char* exitString,
    const unsigned char* resched, const unsigned char* netBlock, const unsigned char* netUnblock,
    const unsigned char* unblock, const unsigned char* unknown, const unsigned char* runtime)
{
    PrintStrings(header, exitString, resched, netBlock, netUnblock, unblock, unknown, runtime);
}

extern "C" void TracePrintCandidateLayouts(const uint64_t* layout) { PrintLayouts(layout); }

extern "C" void* TraceExpected(int index)
{
    return index >= 0 && index < 6 ? &cppMarker[index] : nullptr;
}

extern "C" void TraceCppWriteRecords(TraceBufHeader* header, TraceBuf* buffer, TraceHooks* hooks)
{
    WriteCppRecords(header, buffer, hooks);
}

extern "C" uint64_t TraceCppCallbackStatus()
{
    const uint64_t failures = cppCallbackBits == UINT64_C(0x3f) ? 0 : cppCallbackBits ^ UINT64_C(0x3f);
    cppCallbackBits = 0;
    return failures;
}

extern "C" void TraceReadVaList(void* rawArgs, uint64_t* first, uint64_t* second)
{
    va_list* args = static_cast<va_list*>(rawArgs);
    *first = va_arg(*args, unsigned long long);
    *second = va_arg(*args, unsigned long long);
}

extern "C" uint64_t TraceCppCheckCandidate(const TraceBufHeader* header, const TraceBuf* buffer,
                                             const TraceHooks* hooks)
{
    return CheckCandidateRecords(*header, *buffer, *hooks);
}

extern "C" void TracePrintSentinel(uint64_t cppWriteCjRead, uint64_t cjWriteCppRead,
                                    uint64_t callbacks, uint64_t arg0, uint64_t arg1)
{
    std::printf("TRACE_SENTINEL cpp_write_cj_read=%llu cj_write_cpp_read=%llu callbacks=%llu "
                "va0=%016llx va1=%016llx status=%s\n",
        static_cast<unsigned long long>(cppWriteCjRead),
        static_cast<unsigned long long>(cjWriteCppRead),
        static_cast<unsigned long long>(callbacks),
        static_cast<unsigned long long>(arg0), static_cast<unsigned long long>(arg1),
        cppWriteCjRead == 0 && cjWriteCppRead == 0 && callbacks == 0 &&
        arg0 == UINT64_C(0x1122334455667788) && arg1 == UINT64_C(0x8877665544332211) ? "PASS" : "FAIL");
}

#ifdef TRACE_VOCAB_ORACLE
int main()
{
    uint64_t values[VALUE_COUNT] {};
    uint64_t layout[19] {};
    FillValues(values);
    FillLayouts(layout);
    PrintVocabulary(values);
    PrintStrings(reinterpret_cast<const unsigned char*>(TRACE_HEADER),
        reinterpret_cast<const unsigned char*>(TRACE_EXIT_STRING),
        reinterpret_cast<const unsigned char*>(TRACE_RESCHED_STRING),
        reinterpret_cast<const unsigned char*>(TRACE_NET_BLOCK_STRING),
        reinterpret_cast<const unsigned char*>(TRACE_NET_UNBLOCK_STRING),
        reinterpret_cast<const unsigned char*>(TRACE_UNBLOCK_STRING),
        reinterpret_cast<const unsigned char*>(TRACE_UNKNOWN_STRING),
        reinterpret_cast<const unsigned char*>(TRACE_RUNTIME_STRING));
    PrintLayouts(layout);

    TraceBufHeader cppHeader {};
    TraceBuf cppBuffer {};
    TraceHooks cppHooks {};
    WriteCppRecords(&cppHeader, &cppBuffer, &cppHooks);
    const uint64_t cppWrite = CheckCppRecords(cppHeader, cppBuffer);

    TraceBufHeader candidateHeader {};
    TraceBuf candidateBuffer {};
    candidateHeader.dulink.prev = reinterpret_cast<Dulink*>(&cppMarker[2]);
    candidateHeader.dulink.next = reinterpret_cast<Dulink*>(&cppMarker[3]);
    candidateHeader.lastTicks = UINT64_C(0x8899aabbccddeeff);
    candidateHeader.pos = 0x11223344;
    candidateBuffer.header.dulink.prev = reinterpret_cast<Dulink*>(&cppMarker[3]);
    candidateBuffer.header.dulink.next = reinterpret_cast<Dulink*>(&cppMarker[2]);
    candidateBuffer.header.lastTicks = UINT64_C(0x7766554433221100);
    candidateBuffer.header.pos = 0x55667788;
    candidateBuffer.arr[0] = 0xaa;
    candidateBuffer.arr[TRACE_BUF_LENGTH / 2] = 0xbb;
    candidateBuffer.arr[TRACE_BUF_LENGTH - 1] = 0xcc;
    TraceHooks candidateHooks {OracleDeregister, OracleStart, OracleStop, OracleEvent, OracleDump, OracleReader};
    const uint64_t candidateRead = CheckCandidateRecords(candidateHeader, candidateBuffer, candidateHooks);
    TracePrintSentinel(cppWrite, candidateRead, 0, oracleArg0, oracleArg1);
    return cppWrite == 0 && candidateRead == 0 &&
        oracleArg0 == UINT64_C(0x1122334455667788) &&
        oracleArg1 == UINT64_C(0x8877665544332211) ? 0 : 1;
}
#endif
