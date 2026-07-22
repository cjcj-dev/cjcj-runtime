#include <cstdint>
#include <cstdio>

#define private public
#include "Common/MarkWorkStack.h"
#undef private

using namespace MapleRuntime;

extern "C" void MarkWorkStackAllocReset();
extern "C" size_t MarkWorkStackNewCalls();
extern "C" size_t MarkWorkStackNewBytes();
extern "C" size_t MarkWorkStackDeleteCalls();

static void* Value(uintptr_t value) { return reinterpret_cast<void*>(value); }
static uintptr_t Token(void* value) { return reinterpret_cast<uintptr_t>(value); }

int main()
{
    std::printf("MARKWORKSTACK_LAYOUT buf=%zu/%zu next=%zu pre=%zu count=%zu stack=%zu "
                "owner=%zu/%zu head=%zu tail=%zu size=%zu max=%zu\n",
        sizeof(MarkStackBuf<void*>), alignof(MarkStackBuf<void*>),
        offsetof(MarkStackBuf<void*>, next), offsetof(MarkStackBuf<void*>, pre),
        offsetof(MarkStackBuf<void*>, count), offsetof(MarkStackBuf<void*>, stack),
        sizeof(MarkStack<void*>), alignof(MarkStack<void*>), offsetof(MarkStack<void*>, h),
        offsetof(MarkStack<void*>, t), offsetof(MarkStack<void*>, s),
        sizeof(((MarkStackBuf<void*>*)nullptr)->stack) / sizeof(void*));

    MarkWorkStackAllocReset();
    MarkStack<void*> stack;
    std::printf("EMPTY empty=%u back=%zu buffers=%zu\n", unsigned(stack.empty()),
        Token(stack.back()), stack.size());
    for (uintptr_t value = 1; value <= 130; ++value) {
        stack.push_back(Value(value));
    }
    std::printf("PUSH count=130 back=%zu buffers=%zu head_pre=%u tail_next=%u\n",
        Token(stack.back()), stack.size(), unsigned(stack.head()->pre == nullptr),
        unsigned(stack.tail()->next == nullptr));
    stack.pop_back();
    stack.pop_back();
    std::printf("POP count=128 back=%zu buffers=%zu\n", Token(stack.back()), stack.size());

    MarkStack<void*> other;
    for (uintptr_t value = 201; value <= 266; ++value) {
        other.push_back(Value(value));
    }
    stack.insert(other);
    std::printf("INSERT buffers=%zu other_empty=%u back=%zu\n", stack.size(),
        unsigned(other.empty()), Token(stack.back()));

    MarkStackBuf<void*>* split = stack.split(2);
    MarkStack<void*> detached(split);
    std::printf("SPLIT left=%zu left_back=%zu right=%zu right_back=%zu link=%u\n",
        detached.size(), Token(detached.back()), stack.size(), Token(stack.back()),
        unsigned(detached.tail()->next == nullptr && stack.head()->pre == nullptr));

    MarkStack<void*> moved(static_cast<MarkStack<void*>&&>(detached));
    std::printf("MOVE moved=%zu source_empty=%u back=%zu\n", moved.size(),
        unsigned(detached.empty()), Token(moved.back()));
    while (!moved.empty()) {
        moved.pop_back();
    }
    while (!stack.empty()) {
        stack.pop_back();
    }
    moved.clear();
    stack.clear();

    MarkStack<void*> shortStack;
    shortStack.push_back(Value(777));
    MarkStack<void*> all(shortStack.split(3));
    std::printf("SPLIT_ALL source_empty=%u taken=%zu back=%zu\n", unsigned(shortStack.empty()),
        all.size(), Token(all.back()));
    while (!all.empty()) {
        all.pop_back();
    }
    all.clear();
    std::printf("ALLOC new_calls=%zu bytes=%zu delete_calls=%zu\n",
        MarkWorkStackNewCalls(), MarkWorkStackNewBytes(), MarkWorkStackDeleteCalls());
    std::puts("MARKWORKSTACK_PARITY PASS");
    return 0;
}
