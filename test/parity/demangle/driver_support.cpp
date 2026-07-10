#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <vector>

namespace {
std::vector<std::string> LoadSymbols()
{
    const char* path = std::getenv("CJRT_DEMANGLE_SYMBOLS");
    if (path == nullptr) {
        std::fputs("CJRT_DEMANGLE_SYMBOLS is not set\n", stderr);
        std::exit(2);
    }
    std::ifstream input(path);
    if (!input) {
        std::fprintf(stderr, "cannot open symbol corpus: %s\n", path);
        std::exit(2);
    }
    std::vector<std::string> symbols;
    std::string symbol;
    while (std::getline(input, symbol)) {
        if (!symbol.empty()) {
            symbols.push_back(symbol);
        }
    }
    return symbols;
}

std::vector<std::string> symbols = LoadSymbols();
std::size_t cursor = 0;

void WriteBytes(const void* data, std::size_t size)
{
    if (std::fwrite(data, 1, size, stdout) != size) {
        std::fputs("cannot write demangle parity output\n", stderr);
        std::exit(2);
    }
}
} // namespace

extern "C" const unsigned char* CJRT_DemangleParityNext()
{
    if (cursor == symbols.size()) {
        return nullptr;
    }
    return reinterpret_cast<const unsigned char*>(symbols[cursor++].c_str());
}

extern "C" void CJRT_DemangleParityEmit(const char* input, const char* output)
{
    const auto inputSize = static_cast<std::uint64_t>(std::char_traits<char>::length(input));
    const auto outputSize = static_cast<std::uint64_t>(std::char_traits<char>::length(output));
    WriteBytes(&inputSize, sizeof(inputSize));
    WriteBytes(input, inputSize);
    WriteBytes(&outputSize, sizeof(outputSize));
    WriteBytes(output, outputSize);
}
