# StackMap parity test

`run_parity.sh` decodes the `.cjmetadata.stackmap` section referenced by every
28-byte function descriptor in ten selfhost difftest objects. The C++ oracle
uses the read-only runtime headers (`CompressedStackMap`, `SlotRoot`,
`DerivedPtr`, and `StacksizeVarInt`); the second dump invokes the Cangjie
decoder. The resulting canonical event streams are compared byte for byte.
Additional hand-encoded objects exercise the register/derived-register paths
and both pure/compressed WAH slot words. The available difftest objects do not
emit those forms at their current optimization level. Synthetic coverage is
reported separately and is not counted among the ten acceptance objects.

Each event is `E kind pc value0 value1`:

| kind | decoded structure | values |
|---:|---|---|
| 1 | function header | stack size, compression format |
| 2 | prologue save | callee-save ordinal, stack offset |
| 3 | stack-map row | PC offset, source line |
| 4 / 5 | GC register / slot root | register and subslot / frame bias |
| 6 / 7 | derived register / slot root | base-root ordinal, derived location |
| 8 / 9 | stack-grow register / slot root | register and subslot / frame bias |

The Cangjie API accepts a caller-owned `StackMapEvent` buffer. Passing a null
buffer performs a count-only decode. It does not allocate, grow an array,
construct strings, capture closures, or throw; malformed/truncated input and
insufficient output capacity are returned as integer status codes.
