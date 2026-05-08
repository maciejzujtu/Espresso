// =================================================== //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //

.include "include/defs.inc"

.section __DATA, __data
    usage_message: .ascii "Usage: ./main < input.pla\n"
.equ usage_len, . - usage_message

.section __DATA, __bss
.globl buffer
.align 3
    buffer: .space BUF_SIZE


// --- _main ---
.global _main
.section __TEXT, __text

_main:
    SUB     sp,  sp,    #32
    STP     fp,  lr,    [sp, #16]
    ADD     fp,  sp,    #16

    CMP     w0,         #1
    B.GT    _usage_err

    // Read from stdin into buffer
    MOV     x0,         #STDIN
    ADRP    x1,         buffer@PAGE
    ADD     x1,  x1,    buffer@PAGEOFF
    MOV     x2,         #BUF_SIZE
    LDR     x16,        =SYS_READ
    SVC     #0x80
    B.CS    _usage_err
    CBZ     x0,         _usage_err

    // _parse(buf=x1, len=x0)
    MOV     x1,         x0
    ADRP    x0,         buffer@PAGE
    ADD     x0,  x0,    buffer@PAGEOFF
    BL      _parse

    MOV     w0,         #0
    B       _exit

_usage_err:
    MOV     x0,         #STDOUT
    ADRP    x1,         usage_message@PAGE
    ADD     x1,  x1,    usage_message@PAGEOFF
    MOV     x2,         #usage_len
    LDR     x16,        =SYS_WRITE
    SVC     #0x80
    MOV     w0,         #1

_exit:
    LDP     fp,  lr,    [sp, #16]
    ADD     sp,  sp,    #32
    LDR     x16,        =SYS_EXIT
    SVC     #0x80
