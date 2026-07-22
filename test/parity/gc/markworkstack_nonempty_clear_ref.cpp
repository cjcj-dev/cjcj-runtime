#include <cstdint>
#include "Common/MarkWorkStack.h"

int main()
{
    MapleRuntime::MarkStack<void*> stack;
    stack.push_back(reinterpret_cast<void*>(uintptr_t(1)));
    stack.clear();
    return 0;
}
