    .text
    .globl cjrt_stackmap_wah_synthetic
    .type cjrt_stackmap_wah_synthetic,@function
cjrt_stackmap_wah_synthetic:
    ret
    .size cjrt_stackmap_wah_synthetic, .-cjrt_stackmap_wah_synthetic

    .section .cjmetadata.stackmap,"aw",@progbits
.Lstackmap:
    # A WAH slot row: 31 compressed references, then a pure word with bits 0 and 2.
    .byte 0x8c, 0x11, 0x10, 0x10, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x10, 0x20, 0x90, 0x4d, 0xe0, 0x8d
    .byte 0x05, 0x00, 0x00, 0x00, 0x00, 0x00

    .section .cjmetadata.methodinfo,"aw",@progbits
    .long .Lstackmap - .
    .long 1
    .zero 20

    .section .cjmetadata.gcflags,"aw",@progbits
    .byte 1, 1, 1

    .section .note.GNU-stack,"",@progbits
