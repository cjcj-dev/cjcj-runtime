#include "Exception/CalleeSavedRegisterContext.h"

#include <cstddef>
#include <cstdio>

using MapleRuntime::CalleeSavedRegisterContext;

int main()
{
    CalleeSavedRegisterContext context{};
    std::printf("CALLEE_LAYOUT %zu %zu %zu %zu %zu %zu\n",
        sizeof(context), alignof(CalleeSavedRegisterContext),
        offsetof(CalleeSavedRegisterContext, rbx), offsetof(CalleeSavedRegisterContext, r12),
        offsetof(CalleeSavedRegisterContext, rbp), offsetof(CalleeSavedRegisterContext, rsp));
    context.SetValueByIdx(0, 101);
    context.SetValueByIdx(1, 202);
    context.SetValueByIdx(5, 606);
    context.SetValueByIdx(6, 707);
    std::printf("CALLEE_VALUES %llu %llu %llu %llu %llu %llu %llu\n",
        static_cast<unsigned long long>(context.rbx),
        static_cast<unsigned long long>(context.r12),
        static_cast<unsigned long long>(context.r13),
        static_cast<unsigned long long>(context.r14),
        static_cast<unsigned long long>(context.r15),
        static_cast<unsigned long long>(context.rbp),
        static_cast<unsigned long long>(context.rsp));
    return 0;
}
