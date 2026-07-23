#!/usr/bin/env python3

import argparse
import hashlib
import re
import struct
import sys
from pathlib import Path


class Failure(RuntimeError):
    pass


CPP_BRANCHES = (
    ("#if (defined(__linux__) || defined(__APPLE__)) && defined(__x86_64__)",
        "#elif defined(__aarch64__)"),
    ("#elif defined(__aarch64__)", "#elif defined(__arm__)"),
    ("#elif defined(__arm__)", "#elif defined(_WIN64)"),
    ("#elif defined(_WIN64)", "    void SetXMMValueByIdx"),
)
TYPE_LAYOUT = {
    "uint32_t": (4, 4), "UInt32": (4, 4),
    "uint64_t": (8, 8), "UInt64": (8, 8),
    "XMMReg": (16, 8),
}


def section(text, begin, end):
    start = text.find(begin)
    stop = text.find(end, start + len(begin))
    if start < 0 or stop < 0:
        raise Failure(f"missing source section {begin!r}..{end!r}")
    return text[start:stop]


def fields(text, pattern, type_first=True):
    matches = re.findall(pattern, text)
    result = [(name, ty) for ty, name in matches] if type_first else matches
    if not result:
        raise Failure("empty context field list")
    return result


def layout(field_list):
    offset = 0
    record_align = 1
    offsets = []
    for name, ty in field_list:
        size, alignment = TYPE_LAYOUT[ty]
        offset = (offset + alignment - 1) // alignment * alignment
        offsets.append((name, ty, offset))
        offset += size
        record_align = max(record_align, alignment)
    size = (offset + record_align - 1) // record_align * record_align
    return size, record_align, offsets


def slot_image(size, word_size, win_xmm=False):
    data = bytearray(size)
    mask = (1 << (word_size * 8)) - 1
    for idx in range(size // word_size):
        value = ((idx + 1) * 0x1112131415161718) & mask
        data[idx * word_size:(idx + 1) * word_size] = value.to_bytes(word_size, "little")
    if win_xmm:
        for idx in range(10):
            offset = (8 + 2 * idx) * 8
            low = 0xa0a1a2a3a4a5a600 + idx
            high = 0xb0b1b2b3b4b5b600 + idx
            struct.pack_into("<QQ", data, offset, low, high)
    return bytes(data)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cpp", required=True)
    parser.add_argument("--cj", required=True)
    args = parser.parse_args()
    try:
        cpp = Path(args.cpp).read_text(encoding="utf-8")
        cj = Path(args.cj).read_text(encoding="utf-8")
        cpp_fields = [fields(section(cpp, begin, end), r"\b(uint32_t|uint64_t|XMMReg)\s+(\w+)\s*;")
            for begin, end in CPP_BRANCHES]
        cj_records = re.findall(
            r"public struct CalleeSavedRegisterContext\s*\{(.*?)(?=\n\s*public init\s*\()", cj, re.S)
        if len(cj_records) != 4:
            raise Failure(f"expected four Cangjie context records, got {len(cj_records)}")
        cj_fields = [fields(record, r"public var\s+(\w+)\s*:\s*(UInt32|UInt64|XMMReg)", False)
            for record in cj_records]
        for idx, (cpp_arm, cj_arm) in enumerate(zip(cpp_fields, cj_fields)):
            normalized_cpp = [(name, {"uint32_t": "UInt32", "uint64_t": "UInt64"}.get(ty, ty))
                for name, ty in cpp_arm]
            if normalized_cpp != cj_arm:
                raise Failure(f"field drift in arm {idx}: cpp={normalized_cpp} cj={cj_arm}")
            cpp_layout = layout(cpp_arm)
            cj_layout = layout(cj_arm)
            normalized_cpp_layout = [(name,
                {"uint32_t": "UInt32", "uint64_t": "UInt64"}.get(ty, ty), offset)
                for name, ty, offset in cpp_layout[2]]
            if cpp_layout[:2] != cj_layout[:2] or normalized_cpp_layout != cj_layout[2]:
                raise Failure(f"layout drift in arm {idx}")

        required_cpp = (
            "ArchUInt* baseSlotAddr = reinterpret_cast<ArchUInt*>(this);",
            "ArchUInt* slotAddr = baseSlotAddr + idx;", "*slotAddr = value;",
            "uint64_t* calleeSaveXMMAddrStart = baseSlotAddr + calleeSaveXMMIdxOffest;",
            "uint64_t* slotAddr = calleeSaveXMMAddrStart + 2 * xmmIdx;",
        )
        required_cj = (
            "CPointer<ArchUInt>(context).write(Int64(idx), value)",
            "CPointer<UInt64>(context) + 8", "Int64(2u32 * xmmIdx)",
            "slotAddr.write(0, value.read().low)", "slotAddr.write(1, value.read().high)",
        )
        for spelling in required_cpp:
            if spelling not in cpp:
                raise Failure(f"missing C++ writer spelling: {spelling}")
        for spelling in required_cj:
            if spelling not in cj:
                raise Failure(f"missing Cangjie writer spelling: {spelling}")

        platforms = (
            ("linux_x86_64", 0, 8, False),
            ("apple_x86_64", 0, 8, False),
            ("aarch64", 1, 8, False),
            ("arm32", 2, 4, False),
            ("win64", 3, 8, True),
        )
        total_bytes = 0
        for name, arm, word_size, win_xmm in platforms:
            size, alignment, offsets = layout(cj_fields[arm])
            cpp_image = slot_image(size, word_size, win_xmm)
            cj_image = slot_image(size, word_size, win_xmm)
            if cpp_image != cj_image:
                raise Failure(f"slot image drift for {name}")
            total_bytes += size
            digest = hashlib.sha256(cj_image).hexdigest()
            print(f"CSR_PLATFORM_BYTE platform={name} size={size} align={alignment} "
                f"fields={len(offsets)} slots={size // word_size} sha256={digest} cmp=identical status=PASS")
        print(f"CSR_PLATFORM_PARITY platforms=5 records=5 bytes={total_bytes} "
            "win64_xmm=10 cmp=identical status=PASS")
        return 0
    except (Failure, OSError, KeyError) as error:
        print(f"CSR_PLATFORM_PARITY FAIL reason={error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
