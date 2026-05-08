// =================================================== //
// Description:      .pla format parser               //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //

.include "include/defs.inc"

// ---- Read-only data -----------------------------------
.section __TEXT, __cstring
.Lp_err_syntax:     .ascii "error: invalid .pla syntax\n"
.equ Lp_err_syntax_len, . - .Lp_err_syntax

.Lp_err_io:         .ascii "error: missing .i / .o declaration\n"
.equ Lp_err_io_len, . - .Lp_err_io


// ---- BSS globals (parser state) ----------------------
.section __DATA, __bss
.align  3
_p_buf:     .space 8        // pointer to input buffer
_p_len:     .space 8        // buffer length (bytes read)
_p_off:     .space 8        // current parse offset

// PLA state struct
.global _pla_state
_pla_state: .space PLA_STRUCT_SIZE


// ---- Text ---------------------------------------------
.section __TEXT, __text

// ------------------------------------------------------------------
// _parse(x0=buf_ptr, x1=len)
//   Entry point called from main.s.  Parses .pla format, builds F
//   and D covers stored in _pla_state, then calls _minimize.
//
// Callee-saved layout (80-byte frame):
//   x19 = p_part   (positive input literals for current term)
//   x20 = n_part   (negative input literals for current term)
//   x21 = bit_idx  (loop index, reused for input and output loops)
//   x22 = out_mask (output '1' bits for current term)
//   x23 = dc_mask  (output '-' bits for current term)
//   x24 = ninputs  (loaded from _pla_state; stable across BL)
//   x25 = noutputs
// ------------------------------------------------------------------
.global _parse
_parse:
    STP     fp, lr,   [sp, #-80]!
    STP     x19, x20, [sp, #16]
    STP     x21, x22, [sp, #32]
    STP     x23, x24, [sp, #48]
    STP     x25, x26, [sp, #64]
    MOV     fp, sp

    // Store parser globals
    ADRP    x2, _p_buf@PAGE
    ADD     x2, x2, _p_buf@PAGEOFF
    STR     x0, [x2]

    ADRP    x2, _p_len@PAGE
    ADD     x2, x2, _p_len@PAGEOFF
    STR     x1, [x2]

    ADRP    x2, _p_off@PAGE
    ADD     x2, x2, _p_off@PAGEOFF
    STR     xzr, [x2]

    // Initialise allocator
    BL      _alloc_init

    // Initialise pla_state
    ADRP    x0, _pla_state@PAGE
    ADD     x0, x0, _pla_state@PAGEOFF
    STR     xzr, [x0, #PLA_NI]
    STR     xzr, [x0, #PLA_NO]
    STR     xzr, [x0, #PLA_F]
    STR     xzr, [x0, #PLA_D]
    STR     xzr, [x0, #PLA_R]

    // Allocate F cover
    BL      _cover_new
    CBZ     x0, .Lp_oom
    ADRP    x1, _pla_state@PAGE
    ADD     x1, x1, _pla_state@PAGEOFF
    STR     x0, [x1, #PLA_F]

    // Allocate D cover
    BL      _cover_new
    CBZ     x0, .Lp_oom
    ADRP    x1, _pla_state@PAGE
    ADD     x1, x1, _pla_state@PAGEOFF
    STR     x0, [x1, #PLA_D]

    // Allocate R cover (starts empty)
    BL      _cover_new
    CBZ     x0, .Lp_oom
    ADRP    x1, _pla_state@PAGE
    ADD     x1, x1, _pla_state@PAGEOFF
    STR     x0, [x1, #PLA_R]

// ---- Main parse loop ----------------------------------
.Lp_loop:
    BL      _p_skip_ws
    BL      _p_eof
    B.EQ    .Lp_done

    BL      _p_peek             // char in w0
    CMP     w0, #'.'
    B.EQ    .Lp_directive
    CMP     w0, #'#'
    B.EQ    .Lp_comment
    CMP     w0, #'0'
    B.EQ    .Lp_term
    CMP     w0, #'1'
    B.EQ    .Lp_term
    CMP     w0, #'-'
    B.EQ    .Lp_term
    BL      _p_skip_line
    B       .Lp_loop

.Lp_comment:
    BL      _p_skip_line
    B       .Lp_loop

// ---- Directive ----------------------------------------
.Lp_directive:
    BL      _p_advance          // consume '.'
    BL      _p_eof
    B.EQ    .Lp_syntax_err

    BL      _p_advance          // consume directive letter → w0
    CMP     w0, #'i'
    B.EQ    .Lp_dir_i
    CMP     w0, #'o'
    B.EQ    .Lp_dir_o
    CMP     w0, #'p'
    B.EQ    .Lp_dir_p
    CMP     w0, #'e'
    B.EQ    .Lp_done
    BL      _p_skip_line
    B       .Lp_loop

.Lp_dir_i:
    BL      _p_skip_ws_inline
    BL      _p_parse_num        // → x0 = value
    ADRP    x1, _pla_state@PAGE
    ADD     x1, x1, _pla_state@PAGEOFF
    STR     x0, [x1, #PLA_NI]
    BL      _p_skip_line
    B       .Lp_loop

.Lp_dir_o:
    BL      _p_skip_ws_inline
    BL      _p_parse_num
    ADRP    x1, _pla_state@PAGE
    ADD     x1, x1, _pla_state@PAGEOFF
    STR     x0, [x1, #PLA_NO]
    BL      _p_skip_line
    B       .Lp_loop

.Lp_dir_p:
    BL      _p_skip_ws_inline
    BL      _p_parse_num        // consume and discard
    BL      _p_skip_line
    B       .Lp_loop

// ---- Product term -------------------------------------
.Lp_term:// =================================================== //
// Description:      .pla format parser               //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //

.include "include/defs.inc"

// ---- Read-only data -----------------------------------
.section __TEXT, __cstring
.Lp_err_syntax:     .ascii "error: invalid .pla syntax\n"
.equ Lp_err_syntax_len, . - .Lp_err_syntax

.Lp_err_io:         .ascii "error: missing .i / .o declaration\n"
.equ Lp_err_io_len, . - .Lp_err_io


// ---- BSS globals (parser state) ----------------------
.section __DATA, __bss
.align  3
_p_buf:     .space 8        // pointer to input buffer
_p_len:     .space 8        // buffer length (bytes read)
_p_off:     .space 8        // current parse offset

// PLA state struct
.global _pla_state
_pla_state: .space PLA_STRUCT_SIZE


// ---- Text ---------------------------------------------
.section __TEXT, __text

// ------------------------------------------------------------------
// _parse(x0=buf_ptr, x1=len)
//   Entry point called from main.s.  Parses .pla format, builds F
//   and D covers stored in _pla_state, then calls _minimize.
//
// Callee-saved layout (80-byte frame):
//   x19 = p_part   (positive input literals for current term)
//   x20 = n_part   (negative input literals for current term)
//   x21 = bit_idx  (loop index, reused for input and output loops)
//   x22 = out_mask (output '1' bits for current term)
//   x23 = dc_mask  (output '-' bits for current term)
//   x24 = ninputs  (loaded from _pla_state; stable across BL)
//   x25 = noutputs
// ------------------------------------------------------------------
.global _parse
_parse:
    STP     fp, lr,   [sp, #-80]!
    STP     x19, x20, [sp, #16]
    STP     x21, x22, [sp, #32]
    STP     x23, x24, [sp, #48]
    STP     x25, x26, [sp, #64]
    MOV     fp, sp

    // Store parser globals
    ADRP    x2, _p_buf@PAGE
    ADD     x2, x2, _p_buf@PAGEOFF
    STR     x0, [x2]

    ADRP    x2, _p_len@PAGE
    ADD     x2, x2, _p_len@PAGEOFF
    STR     x1, [x2]

    ADRP    x2, _p_off@PAGE
    ADD     x2, x2, _p_off@PAGEOFF
    STR     xzr, [x2]

    // Initialise allocator
    BL      _alloc_init

    // Initialise pla_state
    ADRP    x0, _pla_state@PAGE
    ADD     x0, x0, _pla_state@PAGEOFF
    STR     xzr, [x0, #PLA_NI]
    STR     xzr, [x0, #PLA_NO]
    STR     xzr, [x0, #PLA_F]
    STR     xzr, [x0, #PLA_D]
    STR     xzr, [x0, #PLA_R]

    // Allocate F cover
    BL      _cover_new
    CBZ     x0, .Lp_oom
    ADRP    x1, _pla_state@PAGE
    ADD     x1, x1, _pla_state@PAGEOFF
    STR     x0, [x1, #PLA_F]

    // Allocate D cover
    BL      _cover_new
    CBZ     x0, .Lp_oom
    ADRP    x1, _pla_state@PAGE
    ADD     x1, x1, _pla_state@PAGEOFF
    STR     x0, [x1, #PLA_D]

    // Allocate R cover (starts empty)
    BL      _cover_new
    CBZ     x0, .Lp_oom
    ADRP    x1, _pla_state@PAGE
    ADD     x1, x1, _pla_state@PAGEOFF
    STR     x0, [x1, #PLA_R]

// ---- Main parse loop ----------------------------------
.Lp_loop:
    BL      _p_skip_ws
    BL      _p_eof
    B.EQ    .Lp_done

    BL      _p_peek             // char in w0
    CMP     w0, #'.'
    B.EQ    .Lp_directive
    CMP     w0, #'#'
    B.EQ    .Lp_comment
    CMP     w0, #'0'
    B.EQ    .Lp_term
    CMP     w0, #'1'
    B.EQ    .Lp_term
    CMP     w0, #'-'
    B.EQ    .Lp_term
    BL      _p_skip_line
    B       .Lp_loop

.Lp_comment:
    BL      _p_skip_line
    B       .Lp_loop

// ---- Directive ----------------------------------------
.Lp_directive:
    BL      _p_advance          // consume '.'
    BL      _p_eof
    B.EQ    .Lp_syntax_err

    BL      _p_advance          // consume directive letter → w0
    CMP     w0, #'i'
    B.EQ    .Lp_dir_i
    CMP     w0, #'o'
    B.EQ    .Lp_dir_o
    CMP     w0, #'p'
    B.EQ    .Lp_dir_p
    CMP     w0, #'e'
    B.EQ    .Lp_done
    BL      _p_skip_line
    B       .Lp_loop

.Lp_dir_i:
    BL      _p_skip_ws_inline
    BL      _p_parse_num        // → x0 = value
    ADRP    x1, _pla_state@PAGE
    ADD     x1, x1, _pla_state@PAGEOFF
    STR     x0, [x1, #PLA_NI]
    BL      _p_skip_line
    B       .Lp_loop

.Lp_dir_o:
    BL      _p_skip_ws_inline
    BL      _p_parse_num
    ADRP    x1, _pla_state@PAGE
    ADD     x1, x1, _pla_state@PAGEOFF
    STR     x0, [x1, #PLA_NO]
    BL      _p_skip_line
    B       .Lp_loop

.Lp_dir_p:
    BL      _p_skip_ws_inline
    BL      _p_parse_num        // consume and discard
    BL      _p_skip_line
    B       .Lp_loop

// ---- Product term -------------------------------------
.Lp_term:
    // Reload ninputs and noutputs from pla_state into callee-saved regs
    ADRP    x0, _pla_state@PAGE
    ADD     x0, x0, _pla_state@PAGEOFF
    LDR     x24, [x0, #PLA_NI]     // x24 = ninputs (callee-saved)
    LDR     x25, [x0, #PLA_NO]     // x25 = noutputs (callee-saved)
    CBZ     x24, .Lp_io_err
    CBZ     x25, .Lp_io_err

    // Initialise term state in callee-saved registers
    MOV     x19, #0             // x19 = p_part
    MOV     x20, #0             // x20 = n_part
    MOV     x21, #0             // x21 = bit index

// ---- Parse input literals ----------------------------
.Lp_input_loop:
    CMP     x21, x24            // x24 = ninputs (callee-saved, safe)
    B.GE    .Lp_inputs_done
    BL      _p_eof
    B.EQ    .Lp_syntax_err
    BL      _p_advance          // char → w0
    CMP     w0, #'1'
    B.EQ    .Lp_in_one
    CMP     w0, #'0'
    B.EQ    .Lp_in_zero
    // '-' = don't-care
    ADD     x21, x21, #1
    B       .Lp_input_loop

.Lp_in_one:
    MOV     x0, #1
    LSL     x0, x0, x21
    ORR     x19, x19, x0        // x19 = p_part
    ADD     x21, x21, #1
    B       .Lp_input_loop

.Lp_in_zero:
    MOV     x0, #1
    LSL     x0, x0, x21
    ORR     x20, x20, x0        // x20 = n_part
    ADD     x21, x21, #1
    B       .Lp_input_loop

// ---- Parse output mask -------------------------------
.Lp_inputs_done:
    BL      _p_skip_ws_inline
    MOV     x22, #0             // x22 = out_mask
    MOV     x23, #0             // x23 = dc_mask
    MOV     x21, #0             // reuse x21 as output bit index

.Lp_output_loop:
    CMP     x21, x25            // x25 = noutputs (callee-saved)
    B.GE    .Lp_outputs_done
    BL      _p_eof
    B.EQ    .Lp_outputs_done
    BL      _p_peek
    CMP     w0, #'\n'
    B.EQ    .Lp_outputs_done
    CMP     w0, #'\r'
    B.EQ    .Lp_outputs_done
    BL      _p_advance          // consume char → w0
    CMP     w0, #'1'
    B.EQ    .Lp_out_one
    CMP     w0, #'-'
    B.EQ    .Lp_out_dc
    ADD     x21, x21, #1
    B       .Lp_output_loop

.Lp_out_one:
    MOV     x0, #1
    LSL     x0, x0, x21
    ORR     x22, x22, x0        // x22 = out_mask
    ADD     x21, x21, #1
    B       .Lp_output_loop

.Lp_out_dc:
    MOV     x0, #1
    LSL     x0, x0, x21
    ORR     x23, x23, x0        // x23 = dc_mask
    ADD     x21, x21, #1
    B       .Lp_output_loop

// ---- Route cube to F or D ----------------------------
.Lp_outputs_done:
    ADRP    x0, _pla_state@PAGE
    ADD     x0, x0, _pla_state@PAGEOFF
    CBNZ    x22, .Lp_add_F

    // out_mask == 0 → check dc_mask
    CBZ     x23, .Lp_term_skip  // pure OFF-set term: skip (goes to R implicitly)

    LDR     x0, [x0, #PLA_D]
    MOV     x1, x19             // p_part
    MOV     x2, x20             // n_part
    MOV     x3, x23             // dc_mask
    BL      _cover_add
    BL      _p_skip_line
    B       .Lp_loop

.Lp_add_F:
    LDR     x0, [x0, #PLA_F]
    MOV     x1, x19
    MOV     x2, x20
    MOV     x3, x22
    BL      _cover_add

.Lp_term_skip:
    BL      _p_skip_line
    B       .Lp_loop

// ---- Done: call minimizer ----------------------------
.Lp_done:
    ADRP    x0, _pla_state@PAGE
    ADD     x0, x0, _pla_state@PAGEOFF
    BL      _minimize

    LDP     x25, x26, [sp, #64]
    LDP     x23, x24, [sp, #48]
    LDP     x21, x22, [sp, #32]
    LDP     x19, x20, [sp, #16]
    LDP     fp,  lr,  [sp], #80
    RET

// ---- Errors -------------------------------------------
.Lp_syntax_err:
    MOV     x0, #STDERR
    ADRP    x1, .Lp_err_syntax@PAGE
    ADD     x1, x1, .Lp_err_syntax@PAGEOFF
    MOV     x2, #Lp_err_syntax_len
    LDR     x16, =SYS_WRITE
    SVC     #0x80
    MOV     w0, #1
    LDR     x16, =SYS_EXIT
    SVC     #0x80

.Lp_io_err:
    MOV     x0, #STDERR
    ADRP    x1, .Lp_err_io@PAGE
    ADD     x1, x1, .Lp_err_io@PAGEOFF
    MOV     x2, #Lp_err_io_len
    LDR     x16, =SYS_WRITE
    SVC     #0x80
    MOV     w0, #1
    LDR     x16, =SYS_EXIT
    SVC     #0x80

.Lp_oom:
    MOV     w0, #3
    LDR     x16, =SYS_EXIT
    SVC     #0x80


// ---- Parser helpers (leaf functions using BSS globals) ----

// _p_eof(): sets Z flag if offset >= len
_p_eof:
    ADRP    x0, _p_off@PAGE
    ADD     x0, x0, _p_off@PAGEOFF
    LDR     x0, [x0]
    ADRP    x1, _p_len@PAGE
    ADD     x1, x1, _p_len@PAGEOFF
    LDR     x1, [x1]
    CMP     x0, x1
    RET

// _p_peek(): returns current char in w0 (does not advance)
_p_peek:
    ADRP    x0, _p_off@PAGE
    ADD     x0, x0, _p_off@PAGEOFF
    LDR     x1, [x0]
    ADRP    x0, _p_buf@PAGE
    ADD     x0, x0, _p_buf@PAGEOFF
    LDR     x0, [x0]
    LDRB    w0, [x0, x1]
    RET

// _p_advance(): consumes current char, returns it in w0
_p_advance:
    ADRP    x1, _p_off@PAGE
    ADD     x1, x1, _p_off@PAGEOFF
    LDR     x2, [x1]
    ADRP    x0, _p_buf@PAGE
    ADD     x0, x0, _p_buf@PAGEOFF
    LDR     x0, [x0]
    LDRB    w0, [x0, x2]
    ADD     x2, x2, #1
    STR     x2, [x1]
    RET

// _p_skip_ws(): skip spaces, tabs, CR, LF
_p_skip_ws:
    ADRP    x0, _p_off@PAGE
    ADD     x0, x0, _p_off@PAGEOFF
    LDR     x1, [x0]
    ADRP    x2, _p_len@PAGE
    ADD     x2, x2, _p_len@PAGEOFF
    LDR     x2, [x2]
    ADRP    x3, _p_buf@PAGE
    ADD     x3, x3, _p_buf@PAGEOFF
    LDR     x3, [x3]
.Lp_ws_loop:
    CMP     x1, x2
    B.GE    .Lp_ws_ret
    LDRB    w4, [x3, x1]
    CMP     w4, #' '
    B.EQ    .Lp_ws_next
    CMP     w4, #'\t'
    B.EQ    .Lp_ws_next
    CMP     w4, #'\n'
    B.EQ    .Lp_ws_next
    CMP     w4, #'\r'
    B.EQ    .Lp_ws_next
    B       .Lp_ws_ret
.Lp_ws_next:
    ADD     x1, x1, #1
    B       .Lp_ws_loop
.Lp_ws_ret:
    STR     x1, [x0]
    RET

// _p_skip_ws_inline(): skip only spaces and tabs (not newlines)
_p_skip_ws_inline:
    ADRP    x0, _p_off@PAGE
    ADD     x0, x0, _p_off@PAGEOFF
    LDR     x1, [x0]
    ADRP    x2, _p_len@PAGE
    ADD     x2, x2, _p_len@PAGEOFF
    LDR     x2, [x2]
    ADRP    x3, _p_buf@PAGE
    ADD     x3, x3, _p_buf@PAGEOFF
    LDR     x3, [x3]
.Lp_wsi_loop:
    CMP     x1, x2
    B.GE    .Lp_wsi_ret
    LDRB    w4, [x3, x1]
    CMP     w4, #' '
    B.EQ    .Lp_wsi_next
    CMP     w4, #'\t'
    B.EQ    .Lp_wsi_next
    B       .Lp_wsi_ret
.Lp_wsi_next:
    ADD     x1, x1, #1
    B       .Lp_wsi_loop
.Lp_wsi_ret:
    STR     x1, [x0]
    RET

// _p_skip_line(): advance past next '\n'
_p_skip_line:
    ADRP    x0, _p_off@PAGE
    ADD     x0, x0, _p_off@PAGEOFF
    LDR     x1, [x0]
    ADRP    x2, _p_len@PAGE
    ADD     x2, x2, _p_len@PAGEOFF
    LDR     x2, [x2]
    ADRP    x3, _p_buf@PAGE
    ADD     x3, x3, _p_buf@PAGEOFF
    LDR     x3, [x3]
.Lp_sl_loop:
    CMP     x1, x2
    B.GE    .Lp_sl_ret
    LDRB    w4, [x3, x1]
    ADD     x1, x1, #1
    CMP     w4, #'\n'
    B.NE    .Lp_sl_loop
.Lp_sl_ret:
    STR     x1, [x0]
    RET

// _p_parse_num(): parse decimal integer at current offset → x0
_p_parse_num:
    ADRP    x1, _p_off@PAGE
    ADD     x1, x1, _p_off@PAGEOFF
    LDR     x2, [x1]
    ADRP    x3, _p_len@PAGE
    ADD     x3, x3, _p_len@PAGEOFF
    LDR     x3, [x3]
    ADRP    x4, _p_buf@PAGE
    ADD     x4, x4, _p_buf@PAGEOFF
    LDR     x4, [x4]
    MOV     x0, #0
    MOV     x5, #10
.Lp_num_loop:
    CMP     x2, x3
    B.GE    .Lp_num_ret
    LDRB    w6, [x4, x2]
    SUB     w7, w6, #'0'
    CMP     w7, #9
    B.HI    .Lp_num_ret
    MUL     x0, x0, x5
    ADD     x0, x0, x7
    ADD     x2, x2, #1
    B       .Lp_num_loop
.Lp_num_ret:
    STR     x2, [x1]
    RET

    // Reload ninputs and noutputs from pla_state into callee-saved regs
    ADRP    x0, _pla_state@PAGE
    ADD     x0, x0, _pla_state@PAGEOFF
    LDR     x24, [x0, #PLA_NI]     // x24 = ninputs (callee-saved)
    LDR     x25, [x0, #PLA_NO]     // x25 = noutputs (callee-saved)
    CBZ     x24, .Lp_io_err
    CBZ     x25, .Lp_io_err

    // Initialise term state in callee-saved registers
    MOV     x19, #0             // x19 = p_part
    MOV     x20, #0             // x20 = n_part
    MOV     x21, #0             // x21 = bit index

// ---- Parse input literals ----------------------------
.Lp_input_loop:
    CMP     x21, x24            // x24 = ninputs (callee-saved, safe)
    B.GE    .Lp_inputs_done
    BL      _p_eof
    B.EQ    .Lp_syntax_err
    BL      _p_advance          // char → w0
    CMP     w0, #'1'
    B.EQ    .Lp_in_one
    CMP     w0, #'0'
    B.EQ    .Lp_in_zero
    // '-' = don't-care
    ADD     x21, x21, #1
    B       .Lp_input_loop

.Lp_in_one:
    MOV     x0, #1
    LSL     x0, x0, x21
    ORR     x19, x19, x0        // x19 = p_part
    ADD     x21, x21, #1
    B       .Lp_input_loop

.Lp_in_zero:
    MOV     x0, #1
    LSL     x0, x0, x21
    ORR     x20, x20, x0        // x20 = n_part
    ADD     x21, x21, #1
    B       .Lp_input_loop

// ---- Parse output mask -------------------------------
.Lp_inputs_done:
    BL      _p_skip_ws_inline
    MOV     x22, #0             // x22 = out_mask
    MOV     x23, #0             // x23 = dc_mask
    MOV     x21, #0             // reuse x21 as output bit index

.Lp_output_loop:
    CMP     x21, x25            // x25 = noutputs (callee-saved)
    B.GE    .Lp_outputs_done
    BL      _p_eof
    B.EQ    .Lp_outputs_done
    BL      _p_peek
    CMP     w0, #'\n'
    B.EQ    .Lp_outputs_done
    CMP     w0, #'\r'
    B.EQ    .Lp_outputs_done
    BL      _p_advance          // consume char → w0
    CMP     w0, #'1'
    B.EQ    .Lp_out_one
    CMP     w0, #'-'
    B.EQ    .Lp_out_dc
    ADD     x21, x21, #1
    B       .Lp_output_loop

.Lp_out_one:
    MOV     x0, #1
    LSL     x0, x0, x21
    ORR     x22, x22, x0        // x22 = out_mask
    ADD     x21, x21, #1
    B       .Lp_output_loop

.Lp_out_dc:
    MOV     x0, #1
    LSL     x0, x0, x21
    ORR     x23, x23, x0        // x23 = dc_mask
    ADD     x21, x21, #1
    B       .Lp_output_loop

// ---- Route cube to F or D ----------------------------
.Lp_outputs_done:
    ADRP    x0, _pla_state@PAGE
    ADD     x0, x0, _pla_state@PAGEOFF
    CBNZ    x22, .Lp_add_F

    // out_mask == 0 → check dc_mask
    CBZ     x23, .Lp_term_skip  // pure OFF-set term: skip (goes to R implicitly)

    LDR     x0, [x0, #PLA_D]
    MOV     x1, x19             // p_part
    MOV     x2, x20             // n_part
    MOV     x3, x23             // dc_mask
    BL      _cover_add
    BL      _p_skip_line
    B       .Lp_loop

.Lp_add_F:
    LDR     x0, [x0, #PLA_F]
    MOV     x1, x19
    MOV     x2, x20
    MOV     x3, x22
    BL      _cover_add

.Lp_term_skip:
    BL      _p_skip_line
    B       .Lp_loop

// ---- Done: call minimizer ----------------------------
.Lp_done:
    ADRP    x0, _pla_state@PAGE
    ADD     x0, x0, _pla_state@PAGEOFF
    BL      _minimize

    LDP     x25, x26, [sp, #64]
    LDP     x23, x24, [sp, #48]
    LDP     x21, x22, [sp, #32]
    LDP     x19, x20, [sp, #16]
    LDP     fp,  lr,  [sp], #80
    RET

// ---- Errors -------------------------------------------
.Lp_syntax_err:
    MOV     x0, #STDERR
    ADRP    x1, .Lp_err_syntax@PAGE
    ADD     x1, x1, .Lp_err_syntax@PAGEOFF
    MOV     x2, #Lp_err_syntax_len
    LDR     x16, =SYS_WRITE
    SVC     #0x80
    MOV     w0, #1
    LDR     x16, =SYS_EXIT
    SVC     #0x80

.Lp_io_err:
    MOV     x0, #STDERR
    ADRP    x1, .Lp_err_io@PAGE
    ADD     x1, x1, .Lp_err_io@PAGEOFF
    MOV     x2, #Lp_err_io_len
    LDR     x16, =SYS_WRITE
    SVC     #0x80
    MOV     w0, #1
    LDR     x16, =SYS_EXIT
    SVC     #0x80

.Lp_oom:
    MOV     w0, #3
    LDR     x16, =SYS_EXIT
    SVC     #0x80


// ---- Parser helpers (leaf functions using BSS globals) ----

// _p_eof(): sets Z flag if offset >= len
_p_eof:
    ADRP    x0, _p_off@PAGE
    ADD     x0, x0, _p_off@PAGEOFF
    LDR     x0, [x0]
    ADRP    x1, _p_len@PAGE
    ADD     x1, x1, _p_len@PAGEOFF
    LDR     x1, [x1]
    CMP     x0, x1
    RET

// _p_peek(): returns current char in w0 (does not advance)
_p_peek:
    ADRP    x0, _p_off@PAGE
    ADD     x0, x0, _p_off@PAGEOFF
    LDR     x1, [x0]
    ADRP    x0, _p_buf@PAGE
    ADD     x0, x0, _p_buf@PAGEOFF
    LDR     x0, [x0]
    LDRB    w0, [x0, x1]
    RET

// _p_advance(): consumes current char, returns it in w0
_p_advance:
    ADRP    x1, _p_off@PAGE
    ADD     x1, x1, _p_off@PAGEOFF
    LDR     x2, [x1]
    ADRP    x0, _p_buf@PAGE
    ADD     x0, x0, _p_buf@PAGEOFF
    LDR     x0, [x0]
    LDRB    w0, [x0, x2]
    ADD     x2, x2, #1
    STR     x2, [x1]
    RET

// _p_skip_ws(): skip spaces, tabs, CR, LF
_p_skip_ws:
    ADRP    x0, _p_off@PAGE
    ADD     x0, x0, _p_off@PAGEOFF
    LDR     x1, [x0]
    ADRP    x2, _p_len@PAGE
    ADD     x2, x2, _p_len@PAGEOFF
    LDR     x2, [x2]
    ADRP    x3, _p_buf@PAGE
    ADD     x3, x3, _p_buf@PAGEOFF
    LDR     x3, [x3]
.Lp_ws_loop:
    CMP     x1, x2
    B.GE    .Lp_ws_ret
    LDRB    w4, [x3, x1]
    CMP     w4, #' '
    B.EQ    .Lp_ws_next
    CMP     w4, #'\t'
    B.EQ    .Lp_ws_next
    CMP     w4, #'\n'
    B.EQ    .Lp_ws_next
    CMP     w4, #'\r'
    B.EQ    .Lp_ws_next
    B       .Lp_ws_ret
.Lp_ws_next:
    ADD     x1, x1, #1
    B       .Lp_ws_loop
.Lp_ws_ret:
    STR     x1, [x0]
    RET

// _p_skip_ws_inline(): skip only spaces and tabs (not newlines)
_p_skip_ws_inline:
    ADRP    x0, _p_off@PAGE
    ADD     x0, x0, _p_off@PAGEOFF
    LDR     x1, [x0]
    ADRP    x2, _p_len@PAGE
    ADD     x2, x2, _p_len@PAGEOFF
    LDR     x2, [x2]
    ADRP    x3, _p_buf@PAGE
    ADD     x3, x3, _p_buf@PAGEOFF
    LDR     x3, [x3]
.Lp_wsi_loop:
    CMP     x1, x2
    B.GE    .Lp_wsi_ret
    LDRB    w4, [x3, x1]
    CMP     w4, #' '
    B.EQ    .Lp_wsi_next
    CMP     w4, #'\t'
    B.EQ    .Lp_wsi_next
    B       .Lp_wsi_ret
.Lp_wsi_next:
    ADD     x1, x1, #1
    B       .Lp_wsi_loop
.Lp_wsi_ret:
    STR     x1, [x0]
    RET

// _p_skip_line(): advance past next '\n'
_p_skip_line:
    ADRP    x0, _p_off@PAGE
    ADD     x0, x0, _p_off@PAGEOFF
    LDR     x1, [x0]
    ADRP    x2, _p_len@PAGE
    ADD     x2, x2, _p_len@PAGEOFF
    LDR     x2, [x2]
    ADRP    x3, _p_buf@PAGE
    ADD     x3, x3, _p_buf@PAGEOFF
    LDR     x3, [x3]
.Lp_sl_loop:
    CMP     x1, x2
    B.GE    .Lp_sl_ret
    LDRB    w4, [x3, x1]
    ADD     x1, x1, #1
    CMP     w4, #'\n'
    B.NE    .Lp_sl_loop
.Lp_sl_ret:
    STR     x1, [x0]
    RET

// _p_parse_num(): parse decimal integer at current offset → x0
_p_parse_num:
    ADRP    x1, _p_off@PAGE
    ADD     x1, x1, _p_off@PAGEOFF
    LDR     x2, [x1]
    ADRP    x3, _p_len@PAGE
    ADD     x3, x3, _p_len@PAGEOFF
    LDR     x3, [x3]
    ADRP    x4, _p_buf@PAGE
    ADD     x4, x4, _p_buf@PAGEOFF
    LDR     x4, [x4]
    MOV     x0, #0
    MOV     x5, #10
.Lp_num_loop:
    CMP     x2, x3
    B.GE    .Lp_num_ret
    LDRB    w6, [x4, x2]
    SUB     w7, w6, #'0'
    CMP     w7, #9
    B.HI    .Lp_num_ret
    MUL     x0, x0, x5
    ADD     x0, x0, x7
    ADD     x2, x2, #1
    B       .Lp_num_loop
.Lp_num_ret:
    STR     x2, [x1]
    RET
