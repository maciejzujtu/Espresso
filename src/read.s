// =================================================== //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //

.equ        SYSCALL_CLASS, 0x2000000
.equ        SYS_EXIT,      0x2000001
.equ        SYS_READ,      0x2000003
.equ        SYS_WRITE,     0x2000004
.equ        SYS_OPEN,      0x2000005
.equ        SYS_CLOSE,     0x2000006

.equ        STDOUT,         1
.equ        O_RDONLY,       0
.equ        BUF_SIZE,       1024



.section __DATA, __data
    file_path:      .asciz  "/Users/maciej/Desktop/XORcist/input.bin"
    err_msg:        .ascii "Failed to open file\n"
    .equ            err_len, . - err_msg



.section __DATA, __bss
    .p2align        2
    buffer:         .space BUF_SIZE



.global    _read



.section __TEXT, __text
.p2align            2



_read:
    
    STP     FP, LR, [SP, #-16]!
    MOV     FP, SP,

    ADRP    x0,     file_path@PAGE
    ADD     x0, x0, file_path@PAGEOFF
    MOV     x1,     #O_RDONLY
    MOV     x16,    #SYS_OPEN
    SVC     #0x80

    B.CS    open_error
    MOV     x19, x0

    


    LDP     FP, LR, [SP], #16

    MOV     x0, #0
    MOV     x16, #1
    SVC     #0x80

