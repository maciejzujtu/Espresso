// =================================================== //
// Description:      .PLA file format parser           //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //

.include "include/defs.inc"



.section __DATA,    __data
    error_syntax:           .ascii  "Error: Invalid .PLA syntax\n"
    .equ syntax_size,        . -    error_syntax
    error_io:               .ascii  "Error: Missing '.i' or '.o' declarations\n"
    .equ io_size,            . -    error_io



// ===================================================== //
// Parser globals — exported so build.s helpers can      //
// access the active buffer without extra arguments.     //
// ===================================================== //

.section __DATA,    __bss
    .globl _p_buf                                       // Pointer to input buffer (set by _parse)
    .align 3
        _p_buf:             .space  8                   // Stores address of the stdin-read buffer

    .globl _p_len                                       // Total bytes available in the buffer
    .align 3
        _p_len:             .space  8                   // Set once on entry, never changes

    .globl _p_off                                       // Current read position inside the buffer
    .align 3
        _p_off:             .space  8                   // Incremented by build.s helpers as chars are consumed

    .globl PLA_STRUCT                                   // Output of the parse stage — passed to minimize.s
    .align 3
        PLA_STRUCT:         .space  PLA_STRUCT_SIZE     // Holds NI, NO, F-cover ptr, D-cover ptr, R-cover ptr



// ===================================================== //
// _parse(x0=buf_ptr, x1=len)                           //
//   Entry point called from main.s.  Initialises the   //
//   allocator and PLA_STRUCT, allocates three covers   //
//   (F, D, R), then drives the main token loop that    //
//   fills F (ON-set) and D (DC-set) from the .pla      //
//   file.  On '.e' or EOF hands control to _minimize.  //
//                                                       //
// Callee-saved argument layout (80-byte frame):         //
//  * x19   64-bit bitmask for '1' input  literals      //
//  * x20   64-bit bitmask for '0' input  literals      //
//  * x21   Bit-index cursor (reused for input/output)  //
//  * x22   64-bit bitmask for '1' output literals      //
//  * x23   64-bit bitmask for '-' output literals      //
//  * x24   num_inputs  (loaded from PLA_STRUCT)        //
//  * x25   num_outputs (loaded from PLA_STRUCT)        //
// ===================================================== //

.section __text,    __text
    .globl _parse

_parse:
    // -- prologue --
    SUB     sp, sp,         #80                         // Allocate 80 bytes for fp, lr and x19-x26
    STP     fp, lr,         [sp, #64]                   // Store Frame Pointer & Link Register
    STP     x19, x20,       [sp, #48]                   // Store callee-saved registers
    STP     x21, x22,       [sp, #32]
    STP     x23, x24,       [sp, #16]
    STP     x25, x26,       [sp, #0]
    ADD     fp, sp,         #64                         // Frame pointer -> saved fp/lr slot

    // -- store parser globals --
    ADRP    x2,             _p_buf@PAGE                 // Load page address of _p_buf
    ADD     x2, x2,         _p_buf@PAGEOFF              // Resolve full address
    STR     x0,             [x2]                        // Store buffer pointer

    ADRP    x2,             _p_len@PAGE
    ADD     x2, x2,         _p_len@PAGEOFF
    STR     x1,             [x2]                        // Store buffer length

    ADRP    x2,             _p_off@PAGE
    ADD     x2, x2,         _p_off@PAGEOFF
    STR     xzr,            [x2]                        // Reset parse offset to 0

    // -- initialise allocator --
    BL                      _alloc_init                 // Reset bump pointer to start of heap

    // -- initialise PLA struct --
    ADRP    x0,             PLA_STRUCT@PAGE
    ADD     x0, x0,         PLA_STRUCT@PAGEOFF
    STR     xzr,            [x0, #PLA_NI]               // num_inputs  = 0
    STR     xzr,            [x0, #PLA_NO]               // num_outputs = 0
    STR     xzr,            [x0, #PLA_F]                // ON-set  cover = null
    STR     xzr,            [x0, #PLA_D]                // DC-set  cover = null
    STR     xzr,            [x0, #PLA_R]                // OFF-set cover = null

    // -- allocate F cover (ON-set) --
    BL                      _cover_new
    CBZ     x0,             _p_oom
    ADRP    x1,             PLA_STRUCT@PAGE
    ADD     x1, x1,         PLA_STRUCT@PAGEOFF
    STR     x0,             [x1, #PLA_F]                // Save F-cover pointer

    // -- allocate D cover (DC-set) --
    BL                      _cover_new
    CBZ     x0,             _p_oom
    ADRP    x1,             PLA_STRUCT@PAGE
    ADD     x1, x1,         PLA_STRUCT@PAGEOFF
    STR     x0,             [x1, #PLA_D]                // Save D-cover pointer

    // -- allocate R cover (OFF-set, starts empty) --
    BL                      _cover_new
    CBZ     x0,             _p_oom
    ADRP    x1,             PLA_STRUCT@PAGE
    ADD     x1, x1,         PLA_STRUCT@PAGEOFF
    STR     x0,             [x1, #PLA_R]                // Save R-cover pointer



// ===================================================== //
// Main parse loop — advances one token at a time until  //
// EOF or the '.e' end-of-file directive is reached.     //
// ===================================================== //

_p_loop:
    BL                      _p_skip_ws                  // Skip blank lines and leading whitespace
    BL                      _p_eof                      // Sets Z flag if offset >= len
    B.EQ                    _p_done

    BL                      _p_peek                     // Current char -> w0 (does not advance)
    CMP     w0,             #'.'
    B.EQ                    _p_directive
    CMP     w0,             #'#'
    B.EQ                    _p_comment
    CMP     w0,             #'0'
    B.EQ                    _p_term
    CMP     w0,             #'1'
    B.EQ                    _p_term
    CMP     w0,             #'-'
    B.EQ                    _p_term
    BL                      _p_skip_line                // Unrecognised line: skip it entirely
    B                       _p_loop

_p_comment:
    BL                      _p_skip_line                // '#' comment: discard until newline
    B                       _p_loop



// ===================================================== //
// Directive handler — '.i', '.o', '.p', '.e'           //
// ===================================================== //

_p_directive:
    BL                      _p_advance                  // Consume '.'
    BL                      _p_eof
    B.EQ                    _p_syntax_err

    BL                      _p_advance                  // Consume directive letter -> w0
    CMP     w0,             #'i'
    B.EQ                    _p_dir_i
    CMP     w0,             #'o'
    B.EQ                    _p_dir_o
    CMP     w0,             #'p'
    B.EQ                    _p_dir_p
    CMP     w0,             #'e'
    B.EQ                    _p_done                     // '.e' marks end of PLA file
    BL                      _p_skip_line                // Unknown directive: skip
    B                       _p_loop

_p_dir_i:
    BL                      _p_skip_ws_inline           // Skip spaces after '.i'
    BL                      _p_parse_num                // Parse decimal num_inputs -> x0
    ADRP    x1,             PLA_STRUCT@PAGE
    ADD     x1, x1,         PLA_STRUCT@PAGEOFF
    STR     x0,             [x1, #PLA_NI]               // Store num_inputs
    BL                      _p_skip_line
    B                       _p_loop

_p_dir_o:
    BL                      _p_skip_ws_inline           // Skip spaces after '.o'
    BL                      _p_parse_num                // Parse decimal num_outputs -> x0
    ADRP    x1,             PLA_STRUCT@PAGE
    ADD     x1, x1,         PLA_STRUCT@PAGEOFF
    STR     x0,             [x1, #PLA_NO]               // Store num_outputs
    BL                      _p_skip_line
    B                       _p_loop

_p_dir_p:
    BL                      _p_skip_ws_inline
    BL                      _p_parse_num                // Parse and discard product-term count
    BL                      _p_skip_line
    B                       _p_loop



// ===================================================== //
// Product term — parse one row of input and output bits //
// and route the resulting cube to the correct cover.    //
// ===================================================== //

_p_term:
    // -- load and validate header counts --
    ADRP    x0,             PLA_STRUCT@PAGE
    ADD     x0, x0,         PLA_STRUCT@PAGEOFF
    LDR     x24,            [x0, #PLA_NI]               // x24 = num_inputs  (callee-saved across BL)
    LDR     x25,            [x0, #PLA_NO]               // x25 = num_outputs (callee-saved across BL)
    CBZ     x24,            _p_io_err                   // Error if '.i' was never declared
    CBZ     x25,            _p_io_err                   // Error if '.o' was never declared

    // -- initialise per-term bitmasks --
    MOV     x19,            #0                          // x19 = p_part  (positive literals, '1' inputs)
    MOV     x20,            #0                          // x20 = n_part  (negative literals, '0' inputs)
    MOV     x21,            #0                          // x21 = bit-index cursor



// ---- Parse input literals ----------------------------

_p_input_loop:
    CMP     x21,            x24                         // Stop when bit_idx >= num_inputs
    B.GE                    _p_inputs_done
    BL                      _p_eof
    B.EQ                    _p_syntax_err
    BL                      _p_advance                  // Consume next input char -> w0
    CMP     w0,             #'1'
    B.EQ                    _p_in_one
    CMP     w0,             #'0'
    B.EQ                    _p_in_zero
    ADD     x21, x21,       #1                          // '-' = don't-care, advance index only
    B                       _p_input_loop

_p_in_one:
    MOV     x0,             #1
    LSL     x0, x0,         x21                         // Bitmask for position x21
    ORR     x19, x19,       x0                          // Set bit in p_part
    ADD     x21, x21,       #1
    B                       _p_input_loop

_p_in_zero:
    MOV     x0,             #1
    LSL     x0, x0,         x21                         // Bitmask for position x21
    ORR     x20, x20,       x0                          // Set bit in n_part
    ADD     x21, x21,       #1
    B                       _p_input_loop



// ---- Parse output mask -------------------------------

_p_inputs_done:
    BL                      _p_skip_ws_inline           // Skip the space between input and output fields
    MOV     x22,            #0                          // x22 = out_mask ('1' output bits)
    MOV     x23,            #0                          // x23 = dc_mask  ('-' output bits)
    MOV     x21,            #0                          // Reuse x21 as output bit-index cursor

_p_output_loop:
    CMP     x21,            x25                         // Stop when bit_idx >= num_outputs
    B.GE                    _p_outputs_done
    BL                      _p_eof
    B.EQ                    _p_outputs_done
    BL                      _p_peek                     // Look ahead without consuming
    CMP     w0,             #'\n'
    B.EQ                    _p_outputs_done             // Newline terminates the output field
    CMP     w0,             #'\r'
    B.EQ                    _p_outputs_done
    BL                      _p_advance                  // Consume output char -> w0
    CMP     w0,             #'1'
    B.EQ                    _p_out_one
    CMP     w0,             #'-'
    B.EQ                    _p_out_dc
    ADD     x21, x21,       #1                          // '0' output: advance index only
    B                       _p_output_loop

_p_out_one:
    MOV     x0,             #1
    LSL     x0, x0,         x21
    ORR     x22, x22,       x0                          // Set bit in out_mask
    ADD     x21, x21,       #1
    B                       _p_output_loop

_p_out_dc:
    MOV     x0,             #1
    LSL     x0, x0,         x21
    ORR     x23, x23,       x0                          // Set bit in dc_mask
    ADD     x21, x21,       #1
    B                       _p_output_loop



// ---- Route cube to F or D ----------------------------

_p_outputs_done:
    ADRP    x0,             PLA_STRUCT@PAGE
    ADD     x0, x0,         PLA_STRUCT@PAGEOFF
    CBNZ    x22,            _p_add_F                    // out_mask != 0 -> ON-set term, goes to F

    CBZ     x23,            _p_term_skip                // out_mask=0, dc_mask=0 -> OFF-set term, skip

    // -- dc_mask != 0: this is a DC-set term, add to D --
    LDR     x0,             [x0, #PLA_D]
    MOV     x1,             x19                         // p_part
    MOV     x2,             x20                         // n_part
    MOV     x3,             x23                         // dc_mask as output field
    BL                      _cover_add
    BL                      _p_skip_line
    B                       _p_loop

_p_add_F:
    // -- out_mask != 0: add to F (ON-set) --
    LDR     x0,             [x0, #PLA_F]
    MOV     x1,             x19                         // p_part
    MOV     x2,             x20                         // n_part
    MOV     x3,             x22                         // out_mask
    BL                      _cover_add

_p_term_skip:
    BL                      _p_skip_line                // Advance past any remainder of this term's line
    B                       _p_loop



// ===================================================== //
// Done — hand the completed covers to _minimize         //
// ===================================================== //

_p_done:
    ADRP    x0,             PLA_STRUCT@PAGE
    ADD     x0, x0,         PLA_STRUCT@PAGEOFF
    BL                      _minimize                   // Run Espresso: expand -> irredundant loop

    // -- epilogue --
    LDP     x25, x26,       [sp, #0]                    // Restore callee-saved registers
    LDP     x23, x24,       [sp, #16]
    LDP     x21, x22,       [sp, #32]
    LDP     x19, x20,       [sp, #48]
    LDP     fp, lr,         [sp, #64]                   // Restore Frame Pointer & Link Register
    ADD     sp, sp,         #80                         // Normalise stack pointer
    RET



// ===================================================== //
// Error exits                                           //
// ===================================================== //

_p_syntax_err:
    // -- syntax error --
    MOV     x0,             #STDERR                     // 1st argument: write to stderr
    ADRP    x1,             error_syntax@PAGE           // 2nd argument: error message address
    ADD     x1, x1,         error_syntax@PAGEOFF
    MOV     x2,             #syntax_size                // 3rd argument: pre-calc'd message length
    LDR     x16,            =SYS_WRITE                  // write(STDERR, error_syntax, syntax_size)
    SVC     #0x80
    MOV     w0,             #1                          // Exit code 1: syntax error
    LDR     x16,            =SYS_EXIT
    SVC     #0x80

_p_io_err:
    // -- missing .i / .o error --
    MOV     x0,             #STDERR
    ADRP    x1,             error_io@PAGE
    ADD     x1, x1,         error_io@PAGEOFF
    MOV     x2,             #io_size
    LDR     x16,            =SYS_WRITE                  // write(STDERR, error_io, io_size)
    SVC     #0x80
    MOV     w0,             #1                          // Exit code 1: missing declaration
    LDR     x16,            =SYS_EXIT
    SVC     #0x80

_p_oom:
    // -- out of heap memory --
    MOV     w0,             #3                          // Exit code 3: allocator exhausted
    LDR     x16,            =SYS_EXIT
    SVC     #0x80
