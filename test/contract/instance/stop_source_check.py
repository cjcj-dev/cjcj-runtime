#!/usr/bin/env python3

import pathlib
import re
import sys


def fail(message: str) -> None:
    print(f"INSTANCE_STOP_SOURCE FAIL {message}", file=sys.stderr)
    raise SystemExit(1)


if len(sys.argv) != 3:
    fail("usage=stop_source_check.py bridge.cpp CjScheduler.cpp")

bridge_path = pathlib.Path(sys.argv[1])
oracle_path = pathlib.Path(sys.argv[2])
bridge = bridge_path.read_text(encoding="utf-8")
oracle = oracle_path.read_text(encoding="utf-8")

oracle_match = re.search(
    r"int8_t\s+MRT_StopSubScheduler\(void\* schedule\)\s*\{(?P<body>.*?)\n\}",
    oracle,
    re.DOTALL,
)
if oracle_match is None:
    fail("official_definition=missing")

oracle_body = oracle_match.group("body")
oracle_checks = (
    "Runtime::Current()",
    "runtime->FiniSubScheduler(schedule)",
    'LOG(RTLOG_ERROR, "Fail to stop sub-scheduler")',
    "return 1;",
    "return 0;",
)
for token in oracle_checks:
    if oracle_body.count(token) != 1:
        fail(f"official_token={token!r} count={oracle_body.count(token)}")

declaration = 'extern "C" int8_t MRT_StopSubScheduler(void* schedule);'
if bridge.count(declaration) != 1:
    fail(f"bridge_declaration_count={bridge.count(declaration)}")

wrapper_match = re.search(
    r'extern "C" MRT_EXPORT int CJCJ_MRT_InstanceStop\(CjcjRtInstanceHandle instance\)\s*'
    r"\{(?P<body>.*?)\n\}",
    bridge,
    re.DOTALL,
)
if wrapper_match is None:
    fail("wrapper_definition=missing")

wrapper_body = wrapper_match.group("body")
if wrapper_body.count("return MRT_StopSubScheduler(instance);") != 1:
    fail("wrapper_official_call_count")
if "Runtime::CurrentRef() == nullptr || instance == nullptr" not in wrapper_body:
    fail("wrapper_boundary_guard=missing")

forbidden = (
    "ScheduleAnyCJThreadRunning",
    "ScheduleNonDefaultThreadExit",
    "ScheduleProcessorSkipFFI",
    "ScheduleNonDefaultFree",
    "SchmonPreemptRunning",
    "allScheduleListLock",
    "SCHEDULE_WAITING",
    "SCHEDULE_EXITING",
)
present = [token for token in forbidden if token in bridge]
if present:
    fail("extracted_stop_tokens=" + ",".join(present))

print(
    "INSTANCE_STOP_SOURCE "
    f"official_checks={len(oracle_checks)} bridge_declarations=1 wrapper_calls=1 "
    f"forbidden_extractions={len(present)} status=PASS"
)
