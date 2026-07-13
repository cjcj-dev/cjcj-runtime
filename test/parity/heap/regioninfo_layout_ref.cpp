#include <cstddef>
#include <cstdint>
#include <cstdio>

template<typename T>
struct BitField {
    T fieldVal;
};

enum RouteState : uint8_t {
    NORMAL = 0,
    FORWARDABLE,
    ROUTING,
    ROUTED,
    COMPACTED,
    FORWARDED,
};

struct RouteInfo {
    static constexpr uint32_t INVALID_VALUE = UINT32_MAX;
    uintptr_t toRegion1StartAddress = 0;
    uint32_t toRegion1UsedBytes = 0;
    uint32_t toRegion2Idx = 0;
};

struct RwLock {
    int32_t lockCount;
};

struct UnitMetadata {
    struct {
        uintptr_t allocPtr;
        uintptr_t regionEnd;
        uint32_t nextRegionIdx;
        uint32_t prevRegionIdx;
        uint32_t liveByteCount;
        int32_t rawPointerObjectCount;
    };

    union {
        void* liveInfo = nullptr;
        void* ownerRegion;
    };

    union {
        void* liveInfo0 = nullptr;
        void* ownerRegion0;
    };

    uintptr_t regionEnd0;
    RouteInfo routeInfo;
    uint32_t nextRegionIdx0;

    union {
        struct {
            uint8_t unitRole : 4;
            uint8_t unitRole0 : 4;
        };
        BitField<uint8_t> unitRoleBitField;
    };

    union {
        struct {
            uint8_t regionType : 4;
            uint8_t isTraceRegion : 1;
            uint8_t inGhostFromRegion : 1;
            uint8_t isMarked : 1;
            uint8_t isEnqueued : 1;
            uint8_t isResurrected : 1;
        };
        BitField<uint16_t> regionStateBitField;
    };
    RouteState routeState;
    RwLock rwLock;
};

int main()
{
    std::printf(
        "REGIONINFO_LAYOUT sizeof=%zu allocPtr=%zu regionEnd=%zu nextRegionIdx=%zu prevRegionIdx=%zu "
        "liveByteCount=%zu rawPointerObjectCount=%zu liveInfo=%zu liveInfo0=%zu regionEnd0=%zu "
        "routeInfo=%zu nextRegionIdx0=%zu unitRoleBitField=%zu regionStateBitField=%zu routeState=%zu "
        "rwLock=%zu\n",
        sizeof(UnitMetadata), offsetof(UnitMetadata, allocPtr), offsetof(UnitMetadata, regionEnd),
        offsetof(UnitMetadata, nextRegionIdx), offsetof(UnitMetadata, prevRegionIdx),
        offsetof(UnitMetadata, liveByteCount), offsetof(UnitMetadata, rawPointerObjectCount),
        offsetof(UnitMetadata, liveInfo), offsetof(UnitMetadata, liveInfo0),
        offsetof(UnitMetadata, regionEnd0), offsetof(UnitMetadata, routeInfo),
        offsetof(UnitMetadata, nextRegionIdx0), offsetof(UnitMetadata, unitRoleBitField),
        offsetof(UnitMetadata, regionStateBitField), offsetof(UnitMetadata, routeState),
        offsetof(UnitMetadata, rwLock));
    return 0;
}
