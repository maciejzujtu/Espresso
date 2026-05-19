// =================================================== //
// Description:      parser helper utilities           //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //

.include "include/defs.inc"

.section __TEXT, __text

// Note: these helpers read parser globals _p_buf, _p_len, _p_off
//       which are defined with .globl in parser.s.

// ------------------------------------------------------------------
// _p_eof(): sets Z flag if offset >= len
// ------------------------------------------------------------------
.globl _p_eof
_p_eof:
    ADRP    x0, _p_off@PAGE
    ADD     x0, x0, _p_off@PAGEOFF
    LDR     x0, [x0]
    ADRP    x1, _p_len@PAGE
    ADD     x1, x1, _p_len@PAGEOFF
    LDR     x1, [x1]
    CMP     x0, x1
    RET

// ------------------------------------------------------------------
// _p_peek(): returns current char in w0 (does not advance)
// ------------------------------------------------------------------
.globl _p_peek
_p_peek:
    ADRP    x0, _p_off@PAGE
    ADD     x0, x0, _p_off@PAGEOFF
    LDR     x1, [x0]
    ADRP    x0, _p_buf@PAGE
    ADD     x0, x0, _p_buf@PAGEOFF
    LDR     x0, [x0]
    LDRB    w0, [x0, x1]
    RET

// ------------------------------------------------------------------
// _p_advance(): consumes current char, returns it in w0
// ------------------------------------------------------------------
.globl _p_advance
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

// ------------------------------------------------------------------
// _p_skip_ws(): skip spaces, tabs, CR, LF
// ------------------------------------------------------------------
.globl _p_skip_ws
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

// ------------------------------------------------------------------
// _p_skip_ws_inline(): skip only spaces and tabs (not newlines)
// ------------------------------------------------------------------
.globl _p_skip_ws_inline
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

// ------------------------------------------------------------------
// _p_skip_line(): advance past next '\n'
// ------------------------------------------------------------------
.globl _p_skip_line
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

// ------------------------------------------------------------------
// _p_parse_num(): parse decimal integer at current offset -> x0
// ------------------------------------------------------------------
.globl _p_parse_num
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
