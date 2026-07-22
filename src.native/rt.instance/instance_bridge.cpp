// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <mutex>
#include <new>
#include <string>
#include <unordered_map>

#include <pthread.h>
#if defined(__linux__) || defined(hongmeng)
#include <sys/prctl.h>
#endif

// Stage A must insert the parameterized Concurrency in CangjieRuntime's
// existing subModelMap. This changes access only; ownership and layout remain
// CangjieRuntime.cpp:209-224 and CangjieRuntime.cpp:294-303.
#define private public
#include "CangjieRuntime.h"
#undef private

#include "Base/Log.h"
#include "Concurrency/Concurrency.h"
#include "Mutator/ThreadLocal.h"
#include "cjcj_rt_instance.h"

// CjScheduler.cpp:831-840 owns the complete official stop primitive. Keep the
// instance boundary on that symbol instead of extracting scheduler internals.
extern "C" int8_t MRT_StopSubScheduler(void* schedule);

namespace MapleRuntime {
namespace {

static_assert(sizeof(CjcjRtInstanceParam) == sizeof(ConcurrencyParam), "instance parameter size");
static_assert(alignof(CjcjRtInstanceParam) == alignof(ConcurrencyParam), "instance parameter alignment");
static_assert(offsetof(CjcjRtInstanceParam, thStackSize) == offsetof(ConcurrencyParam, thStackSize),
    "thread stack field offset");
static_assert(offsetof(CjcjRtInstanceParam, coStackSize) == offsetof(ConcurrencyParam, coStackSize),
    "cjthread stack field offset");
static_assert(offsetof(CjcjRtInstanceParam, processorNum) == offsetof(ConcurrencyParam, processorNum),
    "processor count field offset");

// Parameterized form of CangjieRuntime::CreateSubSchedulerAndInit at
// CangjieRuntime.cpp:209-224. Only the hard-coded ConcurrencyParam construction
// is replaced by the caller-supplied value authorized by RT_ISOLATE_API_SPEC.
void* CreateSubSchedulerAndInit(
    CangjieRuntime* runtime, const ConcurrencyParam& coParam, ScheduleType type)
{
    std::lock_guard<std::mutex> guard(runtime->mtx);
    auto concurrency = new (std::nothrow) Concurrency();
    CHECK_DETAIL(concurrency != nullptr, "NewAndInit failed");
    concurrency->Init(coParam, type);
    void* scheduler = concurrency->GetThreadScheduler();
    runtime->subModelMap.insert({scheduler, concurrency});
    return scheduler;
}

// CjScheduler.cpp:804-809 SubSchedulerContextData, extended only by the
// authorized ConcurrencyParam that replaces the fixed creation parameters.
struct SubSchedulerContextData {
    ScheduleHandle schedule;
    std::condition_variable* conditionVar;
    std::atomic_bool* inited;
    std::string threadName;
    ConcurrencyParam coParam;
};

// Parameterized form of CjScheduler.cpp:811-827 MRT_StartSubScheduler.
void* MRT_StartSubScheduler(void* args)
{
    auto runtime = reinterpret_cast<CangjieRuntime*>(&Runtime::Current());
    auto* data = static_cast<SubSchedulerContextData*>(args);
    void* schedule = CreateSubSchedulerAndInit(runtime, data->coParam, SCHEDULE_UI_THREAD);
#ifdef __APPLE__
    // TODO(apple-verify): compile and run this branch on an SDK-backed Apple builder.
    CHECK_PTHREAD_CALL(pthread_setname_np, (data->threadName.c_str()), "set sub-scheduler thread name");
#elif defined(__linux__) || defined(hongmeng)
    CHECK_PTHREAD_CALL(prctl, (PR_SET_NAME, data->threadName.c_str()), "set sub-scheduler thread name");
#endif
    data->schedule = schedule;
    data->inited->store(true);
    data->conditionVar->notify_all();
    ThreadLocal::SetCJProcessorFlag(true);
    ScheduleStart();
    // CjScheduler.cpp:503-514 uses the named helper for the EXITED transition.
    // This remains on the sub-scheduler driver thread, whose ScheduleGet() is
    // the instance being stopped; calling it from InstanceStop would target
    // the caller's default scheduler instead (schedule.cpp:86-90).
    SetSchedulerState(5); // 5: state is SCHEDULE_EXITED.
    return nullptr;
}

} // namespace
} // namespace MapleRuntime

extern "C" MRT_EXPORT CjcjRtInstanceHandle CJCJ_MRT_InstanceNew(const CjcjRtInstanceParam* param)
{
    using namespace MapleRuntime;
    if (Runtime::CurrentRef() == nullptr) {
        LOG(RTLOG_ERROR, "Cangjie runtime should be initialized when initialize a sub scheduler.");
        return nullptr;
    }

    auto defaultParam = CangjieRuntime::GetConcurrencyParam();
    ConcurrencyParam coParam = {
        param == nullptr || param->thStackSize == 0 ? defaultParam.thStackSize : param->thStackSize,
        param == nullptr || param->coStackSize == 0 ? defaultParam.coStackSize : param->coStackSize,
        param == nullptr || param->processorNum == 0 ? 1 : param->processorNum,
    };

    static int id = 0;
    std::condition_variable conditionVariable;
    std::atomic_bool subScheduleInited = ATOMIC_VAR_INIT(false);
    std::mutex mtx;
    SubSchedulerContextData context = {
        nullptr,
        &conditionVariable,
        &subScheduleInited,
        "sub-schedule" + std::to_string(id++),
        coParam,
    };

    pthread_t thread;
    pthread_attr_t attr;
    size_t stackSize = coParam.thStackSize * KB;
    CHECK_PTHREAD_CALL(pthread_attr_init, (&attr), "init pthread attr");
    CHECK_PTHREAD_CALL(pthread_attr_setdetachstate, (&attr, PTHREAD_CREATE_JOINABLE), "set pthread joinable");
    CHECK_PTHREAD_CALL(pthread_attr_setstacksize, (&attr, stackSize), "set pthread stacksize");
    CHECK_PTHREAD_CALL(pthread_create, (&thread, &attr, MRT_StartSubScheduler, &context),
        "create sub-scheduler thread");
#ifdef __WIN64
    // TODO(win64-verify): run the full lifecycle contract on a Win64 target runner.
    CHECK_PTHREAD_CALL(pthread_setname_np, (thread, context.threadName.c_str()), "set sub-scheduler thread name");
#endif
    CHECK_PTHREAD_CALL(pthread_attr_destroy, (&attr), "destroy pthread attr");

    std::unique_lock<std::mutex> lock(mtx);
    conditionVariable.wait(lock, [&subScheduleInited]() { return subScheduleInited.load(); });
    return context.schedule;
}

extern "C" MRT_EXPORT CJThreadHandle CJCJ_MRT_InstanceRunTask(
    CjcjRtInstanceHandle instance, const CJTaskFunc func, void* args)
{
    using namespace MapleRuntime;
    if (Runtime::CurrentRef() == nullptr || instance == nullptr) {
        return nullptr;
    }
    auto runtime = reinterpret_cast<CangjieRuntime*>(&Runtime::Current());
    if (!runtime->CheckSubSchedulerValid(instance)) {
        return nullptr;
    }
    return RunCJTaskToSchedule(func, args, instance);
}

extern "C" MRT_EXPORT int CJCJ_MRT_InstanceStop(CjcjRtInstanceHandle instance)
{
    using namespace MapleRuntime;
    if (Runtime::CurrentRef() == nullptr || instance == nullptr) {
        return 1;
    }
    return MRT_StopSubScheduler(instance);
}
