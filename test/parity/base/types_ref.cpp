// Base/Types.h:21-55 executable ABI oracle.
#include "Base/Types.h"

#include <iostream>

using namespace MapleRuntime;

template<typename T>
static void PrintLayout()
{
    std::cout << sizeof(T) << '/' << alignof(T);
}

int main()
{
    std::cout << "TYPES_INT ";
    PrintLayout<U1>(); std::cout << ' '; PrintLayout<I1>(); std::cout << ' ';
    PrintLayout<U8>(); std::cout << ' '; PrintLayout<I8>(); std::cout << ' ';
    PrintLayout<U16>(); std::cout << ' '; PrintLayout<I16>(); std::cout << ' ';
    PrintLayout<U32>(); std::cout << ' '; PrintLayout<I32>(); std::cout << ' ';
    PrintLayout<U64>(); std::cout << ' '; PrintLayout<I64>(); std::cout << '\n';

    std::cout << "TYPES_FLOAT ";
    PrintLayout<F16>(); std::cout << ' '; PrintLayout<F32>(); std::cout << ' ';
    PrintLayout<F64>(); std::cout << '\n';

    std::cout << "TYPES_PTR ";
    PrintLayout<Uptr>(); std::cout << ' '; PrintLayout<Sptr>(); std::cout << ' ';
    PrintLayout<Size>(); std::cout << ' '; PrintLayout<USize>(); std::cout << ' ';
    PrintLayout<Index>(); std::cout << ' '; PrintLayout<Offset>(); std::cout << ' ';
    PrintLayout<ArchUInt>(); std::cout << '\n';
    return 0;
}
