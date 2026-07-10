#ifndef MRT_BASE_LOG_H
#define MRT_BASE_LOG_H

#include <cstdlib>

#define LOG(...) ((void)0)
#define FLOG(...) ((void)0)
#define DLOG(...) ((void)0)
#define CHECK(condition) do { if (!(condition)) { std::abort(); } } while (false)
#define CHECK_DETAIL(condition, ...) do { if (!(condition)) { std::abort(); } } while (false)

#endif
