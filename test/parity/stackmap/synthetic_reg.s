    .text
    .globl cjrt_stackmap_synthetic
    .type cjrt_stackmap_synthetic,@function
cjrt_stackmap_synthetic:
    ret
    .size cjrt_stackmap_synthetic, .-cjrt_stackmap_synthetic

    .section .cjmetadata.stackmap,"aw",@progbits
.Lstackmap:
    # One GC register root (rax), whose derived pointer is in rdx.
    .byte 0x8c, 0x01, 0x10, 0x02, 0x10, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x50, 0x91, 0x04, 0x04, 0x80, 0x10

    .section .cjmetadata.methodinfo,"aw",@progbits
    .long .Lstackmap - .
    .long 1
    .zero 20

    .section .cjmetadata.gcflags,"aw",@progbits
    .byte 1, 1, 1

    .section .note.GNU-stack,"",@progbits
