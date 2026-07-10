#ifndef CJRT_STACKMAP_API_H
#define CJRT_STACKMAP_API_H

#include <cstdint>

extern "C" {

struct StackMapEvent {
    uint32_t kind;
    uint32_t row;
    int64_t value0;
    int64_t value1;
};

}

#endif
