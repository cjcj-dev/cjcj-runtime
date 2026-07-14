#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>
#include <unistd.h>

#ifdef PAGEPOOL_ORIGINAL
#define protected public
#define private public
#include "/root/cj_build/cangjie_runtime/runtime/src/Common/PagePool.h"
#include "/root/cj_build/cangjie_runtime/runtime/src/Base/ImmortalWrapper.h"
#undef private
#undef protected

namespace MapleRuntime {
const size_t MRT_PAGE_SIZE = static_cast<size_t>(getpagesize());

PagePool& PagePool::Instance() noexcept
{
    static ImmortalWrapper<PagePool> instance("PagePool");
    return *instance;
}
} // namespace MapleRuntime
#else
struct PagePool;
extern "C" PagePool* CjInstance() asm("_ZN12MapleRuntime8PagePool8InstanceEv");
extern "C" uint8_t* CjGetPage(PagePool*, size_t) asm("_ZN12MapleRuntime8PagePool7GetPageEm");
extern "C" void CjReturnPage(PagePool*, uint8_t*, size_t)
    asm("_ZN12MapleRuntime8PagePool10ReturnPageEPhm");
extern "C" void CjFini(PagePool*) asm("_ZN12MapleRuntime8PagePool4FiniEv");
extern "C" void CJRT_PagePoolProbeInit(uint32_t);
extern "C" void CJRT_PagePoolProbeTrim();
extern "C" uint8_t* CJRT_PagePoolProbeBase();
extern "C" size_t CJRT_PagePoolProbeTotalSize();
extern "C" size_t CJRT_PagePoolProbePageSize();
extern "C" const char* CJRT_PagePoolProbeTag();
#endif

extern "C" void CJRT_PagePoolMutexLock(void*);
extern "C" void CJRT_PagePoolMutexUnlock(void*);

namespace {
constexpr size_t PAGE_SIZE = 4096;
constexpr uint32_t POOL_PAGES = 96;

[[noreturn]] void Fail(const char* message)
{
    std::fprintf(stderr, "PAGEPOOL_PROBE FAIL %s\n", message);
    std::abort();
}

void Require(bool condition, const char* message)
{
    if (!condition) {
        Fail(message);
    }
}

#ifdef PAGEPOOL_ORIGINAL
using Pool = MapleRuntime::PagePool;
Pool* Instance() { return &Pool::Instance(); }
void Init(Pool*, uint32_t count) { Pool::Instance().Init(count); }
uint8_t* Get(Pool* pool, size_t bytes) { return pool->GetPage(bytes); }
void Put(Pool* pool, uint8_t* page, size_t bytes) { pool->ReturnPage(page, bytes); }
void Fini(Pool* pool) { pool->Fini(); }
void Trim(Pool* pool) { pool->Trim(); }
uint8_t* Base(Pool* pool) { return pool->base; }
size_t TotalSize(Pool* pool) { return pool->totalSize; }
size_t PageSize() { return MapleRuntime::MRT_PAGE_SIZE; }
const char* Tag(Pool* pool) { return pool->tag; }
#else
using Pool = PagePool;
Pool* Instance() { return CjInstance(); }
void Init(Pool*, uint32_t count) { CJRT_PagePoolProbeInit(count); }
uint8_t* Get(Pool* pool, size_t bytes) { return CjGetPage(pool, bytes); }
void Put(Pool* pool, uint8_t* page, size_t bytes) { CjReturnPage(pool, page, bytes); }
void Fini(Pool* pool) { CjFini(pool); }
void Trim(Pool*) { CJRT_PagePoolProbeTrim(); }
uint8_t* Base(Pool*) { return CJRT_PagePoolProbeBase(); }
size_t TotalSize(Pool*) { return CJRT_PagePoolProbeTotalSize(); }
size_t PageSize() { return CJRT_PagePoolProbePageSize(); }
const char* Tag(Pool*) { return CJRT_PagePoolProbeTag(); }
#endif

void PrintLayouts()
{
#ifdef PAGEPOOL_ORIGINAL
    using namespace MapleRuntime;
    using SUD = SingleUseDeque<void*>;
    using Allocator = RTAllocatorT<sizeof(CartesianTree::Node), alignof(CartesianTree::Node)>;
    using LD = LocalDeque<void*>;
    std::printf("SINGLE_USE_DEQUE_LAYOUT sizeof=%zu align=%zu memMap=%zu begin=%zu front=%zu top=%zu end=%zu\n",
        sizeof(SUD), alignof(SUD), offsetof(SUD, memMap), offsetof(SUD, beginAddr),
        offsetof(SUD, frontAddr), offsetof(SUD, topAddr), offsetof(SUD, endAddr));
    std::printf("RTALLOCATOR_LAYOUT sizeof=%zu align=%zu head=%zu curr=%zu end=%zu memMap=%zu\n",
        sizeof(Allocator), alignof(Allocator), offsetof(Allocator, head), offsetof(Allocator, currAddr),
        offsetof(Allocator, endAddr), offsetof(Allocator, memMap));
    std::printf("CARTESIAN_TREE_LAYOUT sizeof=%zu align=%zu totalCount=%zu root=%zu sud=%zu traversalSud=%zu nodeAllocator=%zu\n",
        sizeof(CartesianTree), alignof(CartesianTree), offsetof(CartesianTree, totalCount),
        offsetof(CartesianTree, root), offsetof(CartesianTree, sud),
        offsetof(CartesianTree, traversalSud), offsetof(CartesianTree, nodeAllocator));
    std::printf("LOCALDEQUE_LAYOUT sizeof=%zu align=%zu front=%zu top=%zu sud=%zu array=%zu local_length=%d\n",
        sizeof(LD), alignof(LD), offsetof(LD, front), offsetof(LD, top), offsetof(LD, sud),
        offsetof(LD, array), LD::LOCAL_LENGTH);
    std::printf("CARTESIAN_NODE_LAYOUT sizeof=%zu align=%zu l=%zu r=%zu index=%zu count=%zu\n",
        sizeof(CartesianTree::Node), alignof(CartesianTree::Node), offsetof(CartesianTree::Node, l),
        offsetof(CartesianTree::Node, r), offsetof(CartesianTree::Node, index),
        offsetof(CartesianTree::Node, count));
    std::printf("PAGEPOOL_LAYOUT sizeof=%zu align=%zu mutex=%zu tree=%zu base=%zu totalSize=%zu usedZone=%zu tag=%zu smallPageUsed=%zu totalPageCount=%zu\n",
        sizeof(PagePool), alignof(PagePool), offsetof(PagePool, freePagesMutex),
        offsetof(PagePool, freePagesTree), offsetof(PagePool, base), offsetof(PagePool, totalSize),
        offsetof(PagePool, usedZone), offsetof(PagePool, tag), offsetof(PagePool, smallPageUsed),
        offsetof(PagePool, totalPageCount));
    std::printf("PAGEPOOL_FIELDS mutex_size=%zu mutex_align=%zu tree_size=%zu tree_align=%zu atomic_size=%zu atomic_align=%zu\n",
        sizeof(std::mutex), alignof(std::mutex), sizeof(CartesianTree), alignof(CartesianTree),
        sizeof(std::atomic<uint32_t>), alignof(std::atomic<uint32_t>));
#else
    std::printf("SINGLE_USE_DEQUE_LAYOUT sizeof=%zu align=%zu memMap=%zu begin=%zu front=%zu top=%zu end=%zu\n",
        size_t(CJ_SUD_SIZE), size_t(CJ_SUD_ALIGN), size_t(CJ_SUD_MEMMAP), size_t(CJ_SUD_BEGIN),
        size_t(CJ_SUD_FRONT), size_t(CJ_SUD_TOP), size_t(CJ_SUD_END));
    std::printf("RTALLOCATOR_LAYOUT sizeof=%zu align=%zu head=%zu curr=%zu end=%zu memMap=%zu\n",
        size_t(CJ_RT_SIZE), size_t(CJ_RT_ALIGN), size_t(CJ_RT_HEAD), size_t(CJ_RT_CURR),
        size_t(CJ_RT_END), size_t(CJ_RT_MEMMAP));
    std::printf("CARTESIAN_TREE_LAYOUT sizeof=%zu align=%zu totalCount=%zu root=%zu sud=%zu traversalSud=%zu nodeAllocator=%zu\n",
        size_t(CJ_TREE_SIZE), size_t(CJ_TREE_ALIGN), size_t(CJ_TREE_TOTAL), size_t(CJ_TREE_ROOT),
        size_t(CJ_TREE_SUD), size_t(CJ_TREE_TRAVERSAL), size_t(CJ_TREE_ALLOCATOR));
    std::printf("LOCALDEQUE_LAYOUT sizeof=%zu align=%zu front=%zu top=%zu sud=%zu array=%zu local_length=%zu\n",
        size_t(CJ_LD_SIZE), size_t(CJ_LD_ALIGN), size_t(CJ_LD_FRONT), size_t(CJ_LD_TOP),
        size_t(CJ_LD_SUD), size_t(CJ_LD_ARRAY), size_t(512));
    std::printf("CARTESIAN_NODE_LAYOUT sizeof=%zu align=%zu l=%zu r=%zu index=%zu count=%zu\n",
        size_t(CJ_NODE_SIZE), size_t(CJ_NODE_ALIGN), size_t(CJ_NODE_L), size_t(CJ_NODE_R),
        size_t(CJ_NODE_INDEX), size_t(CJ_NODE_COUNT));
    std::printf("PAGEPOOL_LAYOUT sizeof=%zu align=%zu mutex=%zu tree=%zu base=%zu totalSize=%zu usedZone=%zu tag=%zu smallPageUsed=%zu totalPageCount=%zu\n",
        size_t(CJ_POOL_SIZE), size_t(CJ_POOL_ALIGN), size_t(CJ_POOL_MUTEX), size_t(CJ_POOL_TREE),
        size_t(CJ_POOL_BASE), size_t(CJ_POOL_TOTALSIZE), size_t(CJ_POOL_USEDZONE), size_t(CJ_POOL_TAG),
        size_t(CJ_POOL_ATOMIC), size_t(CJ_POOL_PAGECOUNT));
    std::printf("PAGEPOOL_FIELDS mutex_size=%zu mutex_align=%zu tree_size=%zu tree_align=%zu atomic_size=%zu atomic_align=%zu\n",
        size_t(CJ_MUTEX_SIZE), size_t(CJ_MUTEX_ALIGN), size_t(CJ_TREE_SIZE), size_t(CJ_TREE_ALIGN),
        size_t(CJ_ATOMIC_SIZE), size_t(CJ_ATOMIC_ALIGN));
#endif
}

struct Live {
    uint8_t* pointer;
    size_t bytes;
    bool inside;
    size_t index;
    size_t pages;
};

void Stress(Pool* pool)
{
    constexpr size_t THREADS = 8;
    constexpr size_t PER_THREAD = 2500;
    std::mutex modelMutex;
    std::unordered_map<uint8_t*, size_t> live;
    std::atomic<size_t> duplicates{0};
    std::atomic<size_t> overlaps{0};
    std::vector<std::thread> threads;
    for (size_t tid = 0; tid < THREADS; ++tid) {
        threads.emplace_back([&, tid] {
            for (size_t step = 0; step < PER_THREAD; ++step) {
                size_t pages = ((step + tid) % 3) + 1;
                size_t bytes = pages * PAGE_SIZE - ((step & 1) ? 17 : 0);
                uint8_t* page = Get(pool, bytes);
                {
                    std::lock_guard<std::mutex> guard(modelMutex);
                    if (!live.emplace(page, pages).second) {
                        ++duplicates;
                    }
                    for (const auto& other : live) {
                        if (other.first != page && !(page + pages * PAGE_SIZE <= other.first ||
                                other.first + other.second * PAGE_SIZE <= page)) {
                            ++overlaps;
                            break;
                        }
                    }
                }
                page[0] = static_cast<uint8_t>(tid + 1);
                {
                    std::lock_guard<std::mutex> guard(modelMutex);
                    live.erase(page);
                }
                Put(pool, page, bytes);
            }
        });
    }
    for (auto& thread : threads) {
        thread.join();
    }
    Require(live.empty(), "stress live set");
    Require(duplicates.load() == 0 && overlaps.load() == 0, "stress ownership");
    std::printf("PAGEPOOL_MUTEX threads=%zu operations=%zu duplicates=%zu overlaps=%zu status=PASS\n",
        THREADS, THREADS * PER_THREAD, duplicates.load(), overlaps.load());
}

void MutexInterop(Pool* pool)
{
    auto* native = reinterpret_cast<std::mutex*>(pool);
    std::atomic<bool> started{false};
    std::atomic<bool> acquired{false};
    native->lock();
    std::thread bridgeThread([&] {
        started.store(true, std::memory_order_release);
        CJRT_PagePoolMutexLock(pool);
        acquired.store(true, std::memory_order_release);
        CJRT_PagePoolMutexUnlock(pool);
    });
    while (!started.load(std::memory_order_acquire)) {
        std::this_thread::yield();
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
    Require(!acquired.load(std::memory_order_acquire), "std::mutex blocks bridge");
    native->unlock();
    bridgeThread.join();
    Require(acquired.load(std::memory_order_acquire), "bridge acquired after std::mutex");

    started.store(false, std::memory_order_release);
    acquired.store(false, std::memory_order_release);
    CJRT_PagePoolMutexLock(pool);
    std::thread nativeThread([&] {
        started.store(true, std::memory_order_release);
        native->lock();
        acquired.store(true, std::memory_order_release);
        native->unlock();
    });
    while (!started.load(std::memory_order_acquire)) {
        std::this_thread::yield();
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
    Require(!acquired.load(std::memory_order_acquire), "bridge blocks std::mutex");
    CJRT_PagePoolMutexUnlock(pool);
    nativeThread.join();
    Require(acquired.load(std::memory_order_acquire), "std::mutex acquired after bridge");
    std::printf("PAGEPOOL_MUTEX_ABI cpp_to_bridge=PASS bridge_to_cpp=PASS bytes=40 status=PASS\n");
}

void RunTrace(Pool* pool, size_t& operations, size_t& records)
{
    uint8_t* base = Base(pool);
    size_t total = TotalSize(pool);
    std::vector<uint8_t> owned(total / PAGE_SIZE, 0);
    std::vector<Live> live;
    uint64_t seed = 0x50414745504f4f4cULL;
    constexpr size_t STEPS = 2200;
    for (size_t step = 0; step < STEPS; ++step) {
        seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;
        bool allocate = live.empty() || ((seed >> 61) != 0 && live.size() < 80);
        if (allocate) {
            size_t pages = static_cast<size_t>((seed >> 17) % 4) + 1;
            size_t bytes = pages * PAGE_SIZE - static_cast<size_t>((seed >> 29) % 127);
            if (bytes == 0) {
                bytes = 1;
            }
            uint8_t* pointer = Get(pool, bytes);
            bool inside = pointer >= base && pointer < base + total;
            size_t index = inside ? static_cast<size_t>(pointer - base) / PAGE_SIZE : 0;
            if (inside) {
                Require(index + pages <= owned.size(), "trace inside range");
                for (size_t i = 0; i < pages; ++i) {
                    Require(owned[index + i] == 0, "trace overlap");
                    owned[index + i] = 1;
                }
            }
            live.push_back({pointer, bytes, inside, index, pages});
            std::printf("TRACE step=%zu op=GET where=%s index=%zu pages=%zu bytes=%zu live=%zu\n",
                step, inside ? "inside" : "outside", index, pages, bytes, live.size());
        } else {
            size_t selected = static_cast<size_t>((seed >> 11) % live.size());
            Live item = live[selected];
            if (item.inside) {
                for (size_t i = 0; i < item.pages; ++i) {
                    Require(owned[item.index + i] == 1, "trace lost return");
                    owned[item.index + i] = 0;
                }
            }
            Put(pool, item.pointer, item.bytes);
            live[selected] = live.back();
            live.pop_back();
            std::printf("TRACE step=%zu op=RETURN where=%s index=%zu pages=%zu bytes=%zu live=%zu\n",
                step, item.inside ? "inside" : "outside", item.index, item.pages, item.bytes, live.size());
        }
        ++operations;
        ++records;
    }
    for (const auto& item : live) {
        Put(pool, item.pointer, item.bytes);
        if (item.inside) {
            for (size_t i = 0; i < item.pages; ++i) {
                Require(owned[item.index + i] == 1, "trace final ownership");
                owned[item.index + i] = 0;
            }
        }
        ++operations;
    }
    Require(std::none_of(owned.begin(), owned.end(), [](uint8_t value) { return value != 0; }),
        "trace final model");
}
} // namespace

#ifdef PAGEPOOL_ORIGINAL
int main()
#else
extern "C" int PagePoolProbeMain()
#endif
{
    PrintLayouts();
    Pool* pool = Instance();
    Require(pool == Instance(), "singleton address");
    MutexInterop(pool);
    Require(PageSize() == PAGE_SIZE && std::strcmp(Tag(pool), "PagePool") == 0, "tag/page size");
    std::printf("PAGEPOOL_CONFIG tag=PagePool page_size=%zu singleton=stable\n", PageSize());
    size_t operations = 0;
    size_t records = 7;
    constexpr size_t LIFETIMES = 3;
    for (size_t lifetime = 0; lifetime < LIFETIMES; ++lifetime) {
        Init(pool, POOL_PAGES);
        uint8_t* base = Base(pool);
        Require(TotalSize(pool) == POOL_PAGES * PAGE_SIZE, "pool size");
        if (lifetime != 0) {
            uint8_t* repeated = Get(pool, PAGE_SIZE + lifetime);
            bool inside = repeated >= base && repeated < base + TotalSize(pool);
            size_t index = inside ? static_cast<size_t>(repeated - base) / PAGE_SIZE : 0;
            std::printf("LIFETIME id=%zu repeated=%s:%zu pages=1\n",
                lifetime, inside ? "inside" : "outside", index);
            Put(pool, repeated, PAGE_SIZE + lifetime);
            Trim(pool);
            Fini(pool);
            operations += 2;
            records += 1;
            continue;
        }
        uint8_t* zero = Get(pool, 0);
        Require(zero == base, "zero request");
        uint8_t* first = Get(pool, PAGE_SIZE);
        uint8_t* unaligned = Get(pool, PAGE_SIZE + 17);
        uint8_t* multi = Get(pool, PAGE_SIZE * 3);
        std::printf("LIFETIME id=%zu zero=inside:0 first=inside:%zu unaligned=inside:%zu multi=inside:%zu\n",
            lifetime, static_cast<size_t>(first - base) / PAGE_SIZE,
            static_cast<size_t>(unaligned - base) / PAGE_SIZE,
            static_cast<size_t>(multi - base) / PAGE_SIZE);
        Put(pool, unaligned, PAGE_SIZE + 17);
        uint8_t* reused = Get(pool, PAGE_SIZE + 1);
        Require(reused == unaligned, "returned-tree reuse");
        Put(pool, first, PAGE_SIZE);
        Put(pool, reused, PAGE_SIZE + 1);
        uint8_t* coalesced = Get(pool, PAGE_SIZE * 3);
        Require(coalesced == first, "adjacent coalescing");
        uint8_t* zeroFill = Get(pool, PAGE_SIZE);
        zeroFill[0] = 0x5a;
        Put(pool, zeroFill, PAGE_SIZE);
        uint8_t* zeroFillAgain = Get(pool, PAGE_SIZE);
        Require(zeroFillAgain == zeroFill && zeroFillAgain[0] == 0, "MADV_DONTNEED zero fill");
        Put(pool, zeroFillAgain, PAGE_SIZE);
        Put(pool, coalesced, PAGE_SIZE * 3);
        Put(pool, multi, PAGE_SIZE * 3);
        if (lifetime == 0) {
            RunTrace(pool, operations, records);
        }
        std::vector<std::pair<uint8_t*, size_t>> bump;
        for (;;) {
            uint8_t* page = Get(pool, PAGE_SIZE);
            if (page < base || page >= base + TotalSize(pool)) {
                std::printf("OVERFLOW lifetime=%zu where=outside pages=1\n", lifetime);
                Put(pool, page, PAGE_SIZE);
                break;
            }
            bump.push_back({page, PAGE_SIZE});
        }
        for (const auto& item : bump) {
            Put(pool, item.first, item.second);
        }
        if (lifetime == 0) {
            Stress(pool);
        }
        Trim(pool);
        Fini(pool);
        operations += 18 + bump.size();
        records += 2;
    }
    std::printf("PAGEPOOL_PARITY PASS operations=%zu lifetimes=%zu records=%zu\n",
        operations, LIFETIMES, records);
    std::printf("PAGEPOOL_PLATFORM os=Linux bump=executed reuse=executed overflow=executed dontneed=executed status=PASS\n");
    return 0;
}
