// =================================================== //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //

.include "include/defs.inc"



.section __DATA,    __data
    usage_message:          .asciz  "Usage: ./main < <FILE_PATH>"
    .equ usage_size,         . -    usage_message

 

.section __DATA,    __bss
    .globl buffer                                       // Buffer for storing argument's text data
    .align 3                                            // Shifts MEM pointer to be at beginning if not
        buffer:             .space  BUF_SIZE            // Allocate 65536 bytes in MEM for buffer



.section __text,    __text
    .globl _main

_main:
    // -- prologue --
    SUB     sp, sp,         #32                         // Allocate 32 bytes for 4 variables in SP
    STP     fp, lr,         [sp, #16]                   // Store Link Register & Frame Pointer's states
    ADD     fp, sp,         #16                         // Move pointer and leave space in stack for 2 variables

    CMP     x0,             #1                          // Check if any arguments were given
    B.GT                    _usage_error                // If argc > 1 throw error and exit
    
    // -- buffer --
    MOV     x0,             #STDIN                      // Set 1st argument to file descriptor
    ADRP    x1,             buffer@PAGE                 // Set 2nd argument to buffer's MEM addr
    ADD     x1, x1,         buffer@PAGEOFF              // Set 3rd argument to buffer's byte size
    MOV     x2,             #BUF_SIZE
    LDR     x16,            =SYS_READ                   // read(fd, *buf, size)
    SVC     #0x80

    B.CS                    _usage_error                // If file doesn't exist (-1) throw error and exit
    CBZ     x0,             _usage_error                // If file is empty (0 bytes)

    // -- parser --
    MOV     x1,             x0                          // Set 2nd argument to buffer's byte size
    ADRP    x0,             buffer@PAGE                 // Set 1st argument to buffer's MEM addr
    ADD     x0, x0,         buffer@PAGEOFF  
    BL                      _parse                      // Go to parse.s with our buffer's saved

    MOV     x0,             #0                          // Set exit code to 0
    B                       _exit





_usage_error:
    // -- error --
    MOV     x0,             #STDOUT                     // Set 1st argument to file descriptor
    ADRP    x1,             usage_message@PAGE          // Set 2nd argument to pre-defined error message
    ADD     x1,  x1,        usage_message@PAGEOFF
    MOV     x2,             #usage_size                 // Set 3rd argument to pre-calc'd error's length
    LDR     x16,            =SYS_WRITE                  // write(fd, *usage_message, usage_size)
    SVC     #0x80
    MOV     w0,         #1                              // Set exit code to 1





_exit:
    // -- epilogue --
    LDP     fp, lr,         [sp, #16]                   // Replace Frame Pointer & Link register with their initial states
    ADD     sp, sp,         #32                         // Shift Stack Pointer at the end (e.g. normalize)
    LDR     x16,            =SYS_EXIT                   // exit(0)
    SVC     #0x80