// =================================================== //
// Description:      Espresso minimizer + PLA output   //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //
//
// Expand (conservative without explicit R):
//   For each cube c_i in F and each literal b in c_i:
//     Compute c_new = the "new territory" half that expansion would add.
//       (removing positive literal b: c_new has n[b] set + rest of c_i)
//       (removing negative literal b: c_new has p[b] set + rest of c_i)
//     Accept the expansion if some cube in F ∪ D covers c_new.
//   This ensures we never expand into minterms not already in F ∪ D.
//
// Irredundant:
//   Remove cube c_i if some other c_j in F is strictly more general
//   (c_j.p ⊆ c_i.p, c_j.n ⊆ c_i.n, c_j.out ⊇ c_i.out).
//
// Reduce: identity stub (SCCC algorithm — add later).
//
// =================================================== //

.include "include/defs.inc"

// ---- BSS: output buffer ------------------------------
.section __DATA, __bss
.align  3
_out_buf:   .space OUT_BUF_SIZE
_out_pos:   .space 8


// ---- Text --------------------------------------------
.section __TEXT, __text

// ------------------------------------------------------------------
// _minimize(x0=pla_ptr)
// ------------------------------------------------------------------
.global _minimize
_minimize:
    STP     fp, lr,   [sp, #-32]!
    STP     x19, x20, [sp, #16]
    MOV     fp, sp
    MOV     x19, x0

    ADRP    x0, _out_pos@PAGE
    ADD     x0, x0, _out_pos@PAGEOFF
    STR     xzr, [x0]

    MOV     x20, #8             // iteration budget

.Lm_iter:
    CBZ     x20, .Lm_write
    SUB     x20, x20, #1

    LDR     x0, [x19, #PLA_F]
    LDR     x9, [x0, #COV_COUNT]    // cost before

    LDR     x0, [x19, #PLA_F]
    LDR     x1, [x19, #PLA_D]
    BL      _expand

    LDR     x0, [x19, #PLA_F]
    BL      _irredundant

    LDR     x0, [x19, #PLA_F]
    LDR     x10, [x0, #COV_COUNT]   // cost after
    CMP     x10, x9
    B.EQ    .Lm_write

    B       .Lm_iter

.Lm_write:
    MOV     x0, x19
    BL      _write_pla

    LDP     x19, x20, [sp, #16]
    LDP     fp,  lr,  [sp], #32
    RET


// ------------------------------------------------------------------
// _expand(x0=F_cover, x1=D_cover)
//
// For each cube c_i in F and each literal bit b:
//   Compute c_new (new-territory half of the proposed expansion).
//   Accept if _cover_covers_val(F, c_new) || _cover_covers_val(D, c_new).
//
// Callee-saved layout (96-byte frame):
//   x19 = F  x20 = D  x21 = count  x22 = cube-index
//   x23 = cube-ptr  x24 = bit index  x25 = p snapshot
//   x26 = n snapshot  x27 = out (needed across BL calls)
// ------------------------------------------------------------------
_expand:
    STP     fp, lr,   [sp, #-112]!
    STP     x19, x20, [sp, #16]
    STP     x21, x22, [sp, #32]
    STP     x23, x24, [sp, #48]
    STP     x25, x26, [sp, #64]
    STP     x27, xzr, [sp, #80]
    MOV     fp, sp

    MOV     x19, x0
    MOV     x20, x1
    LDR     x21, [x19, #COV_COUNT]
    MOV     x22, #0

.Lexp_cube:
    CMP     x22, x21
    B.GE    .Lexp_done

    MOV     x0, x19
    MOV     x1, x22
    BL      _cover_get
    MOV     x23, x0

    LDR     x0, [x23, #CUBE_FLAGS]
    TBNZ    x0, #63, .Lexp_next

    LDR     x25, [x23, #CUBE_P]    // p snapshot (callee-saved)
    LDR     x26, [x23, #CUBE_N]    // n snapshot
    LDR     x27, [x23, #CUBE_OUT]  // out (needed for c_new)
    MOV     x24, #0                 // bit index

// ---- Try removing each positive literal --------------
.Lexp_p:
    CMP     x24, #MAX_INPUTS
    B.GE    .Lexp_p_done

    MOV     x0, #1
    LSL     x0, x0, x24
    TST     x25, x0
    B.EQ    .Lexp_p_next

    // c_new for removing p[b]: c_i with n[b] set, p[b] cleared
    BIC     x1, x25, x0            // c_new.p = c_i.p & ~(1<<b)
    ORR     x2, x26, x0            // c_new.n = c_i.n |  (1<<b)
    MOV     x3, x27                // c_new.out = c_i.out

    // Check: does F cover c_new?
    MOV     x0, x19
    BL      _cover_covers_val       // x24,x25,x26,x27 intact (callee-saved)
    CBNZ    x0, .Lexp_p_accept

    // Check: does D cover c_new?
    BIC     x1, x25, x0            // recompute (x0 was clobbered by BL ret)
    // We need the bit mask again — it's (1 << x24)
    MOV     x0, #1
    LSL     x0, x0, x24
    BIC     x1, x25, x0
    ORR     x2, x26, x0
    MOV     x3, x27
    MOV     x0, x20
    BL      _cover_covers_val
    CBZ     x0, .Lexp_p_next       // neither F nor D covers c_new → reject

.Lexp_p_accept:
    // Remove p[b] from cube and update snapshot
    MOV     x0, #1
    LSL     x0, x0, x24
    BIC     x25, x25, x0
    STR     x25, [x23, #CUBE_P]

.Lexp_p_next:
    ADD     x24, x24, #1
    B       .Lexp_p

// ---- Try removing each negative literal --------------
.Lexp_p_done:
    MOV     x24, #0

.Lexp_n:
    CMP     x24, #MAX_INPUTS
    B.GE    .Lexp_next

    MOV     x0, #1
    LSL     x0, x0, x24
    TST     x26, x0
    B.EQ    .Lexp_n_next

    // c_new for removing n[b]: c_i with p[b] set, n[b] cleared
    ORR     x1, x25, x0            // c_new.p = c_i.p |  (1<<b)
    BIC     x2, x26, x0            // c_new.n = c_i.n & ~(1<<b)
    MOV     x3, x27

    MOV     x0, x19
    BL      _cover_covers_val
    CBNZ    x0, .Lexp_n_accept

    MOV     x0, #1
    LSL     x0, x0, x24
    ORR     x1, x25, x0
    BIC     x2, x26, x0
    MOV     x3, x27
    MOV     x0, x20
    BL      _cover_covers_val
    CBZ     x0, .Lexp_n_next

.Lexp_n_accept:
    MOV     x0, #1
    LSL     x0, x0, x24
    BIC     x26, x26, x0
    STR     x26, [x23, #CUBE_N]

.Lexp_n_next:
    ADD     x24, x24, #1
    B       .Lexp_n

.Lexp_next:
    ADD     x22, x22, #1
    B       .Lexp_cube

.Lexp_done:
    LDP     x27, xzr, [sp, #80]
    LDP     x25, x26, [sp, #64]
    LDP     x23, x24, [sp, #48]
    LDP     x21, x22, [sp, #32]
    LDP     x19, x20, [sp, #16]
    LDP     fp,  lr,  [sp], #112
    RET


// ------------------------------------------------------------------
// _cover_covers_val(x0=cover_ptr, x1=p_val, x2=n_val, x3=out_val)
//   Returns 1 if any live cube in cover covers the given cube.
//   c_j covers (p,n,out) iff:
//     (c_j.p & ~p) == 0  AND  (c_j.n & ~n) == 0
//     AND  (c_j.out & out) == out
//
// Callee-saved layout (64-byte frame):
//   x19=cover x20=p x21=n x22=out x23=count x24=index
// ------------------------------------------------------------------
_cover_covers_val:
    STP     fp, lr,   [sp, #-80]!
    STP     x19, x20, [sp, #16]
    STP     x21, x22, [sp, #32]
    STP     x23, x24, [sp, #48]
    MOV     fp, sp

    MOV     x19, x0
    MOV     x20, x1
    MOV     x21, x2
    MOV     x22, x3
    LDR     x23, [x19, #COV_COUNT]
    MOV     x24, #0

.Lccv_loop:
    CMP     x24, x23
    B.GE    .Lccv_no

    MOV     x0, x19
    MOV     x1, x24
    BL      _cover_get              // x19-x24 intact

    // Skip deleted
    LDR     x1, [x0, #CUBE_FLAGS]
    TBNZ    x1, #63, .Lccv_next

    // Check cj covers (p, n, out)
    LDR     x1, [x0, #CUBE_P]
    BIC     x1, x1, x20             // cj.p & ~p
    CBNZ    x1, .Lccv_next

    LDR     x1, [x0, #CUBE_N]
    BIC     x1, x1, x21             // cj.n & ~n
    CBNZ    x1, .Lccv_next

    LDR     x1, [x0, #CUBE_OUT]
    AND     x1, x1, x22             // cj.out & out
    CMP     x1, x22
    B.NE    .Lccv_next

    MOV     x0, #1
    LDP     x23, x24, [sp, #48]
    LDP     x21, x22, [sp, #32]
    LDP     x19, x20, [sp, #16]
    LDP     fp,  lr,  [sp], #80
    RET

.Lccv_next:
    ADD     x24, x24, #1
    B       .Lccv_loop

.Lccv_no:
    MOV     x0, #0
    LDP     x23, x24, [sp, #48]
    LDP     x21, x22, [sp, #32]
    LDP     x19, x20, [sp, #16]
    LDP     fp,  lr,  [sp], #80
    RET


// ------------------------------------------------------------------
// _irredundant(x0=F_cover)
//   Mark cube c_i deleted if c_j (j≠i) covers c_i, then compact.
//
// Callee-saved layout (80-byte frame):
//   x19=F x20=count x21=outer-i x22=ci-ptr
//   x23=inner-j x24=cj-ptr x25=ci.p x26=ci.n
// ------------------------------------------------------------------
_irredundant:
    STP     fp, lr,   [sp, #-80]!
    STP     x19, x20, [sp, #16]
    STP     x21, x22, [sp, #32]
    STP     x23, x24, [sp, #48]
    STP     x25, x26, [sp, #64]
    MOV     fp, sp

    MOV     x19, x0
    LDR     x20, [x19, #COV_COUNT]
    MOV     x21, #0

.Lir_outer:
    CMP     x21, x20
    B.GE    .Lir_compact

    MOV     x0, x19
    MOV     x1, x21
    BL      _cover_get
    MOV     x22, x0

    LDR     x0, [x22, #CUBE_FLAGS]
    TBNZ    x0, #63, .Lir_next_i

    LDR     x25, [x22, #CUBE_P]
    LDR     x26, [x22, #CUBE_N]

    MOV     x23, #0

.Lir_inner:
    CMP     x23, x20
    B.GE    .Lir_next_i
    CMP     x23, x21
    B.EQ    .Lir_next_j

    MOV     x0, x19
    MOV     x1, x23
    BL      _cover_get
    MOV     x24, x0

    LDR     x0, [x24, #CUBE_FLAGS]
    TBNZ    x0, #63, .Lir_next_j

    // cj covers ci?
    LDR     x0, [x24, #CUBE_P]
    BIC     x0, x0, x25             // cj.p & ~ci.p
    CBNZ    x0, .Lir_next_j

    LDR     x0, [x24, #CUBE_N]
    BIC     x0, x0, x26             // cj.n & ~ci.n
    CBNZ    x0, .Lir_next_j

    LDR     x0, [x22, #CUBE_OUT]    // ci.out
    LDR     x1, [x24, #CUBE_OUT]    // cj.out
    AND     x1, x1, x0
    CMP     x1, x0
    B.NE    .Lir_next_j

    // Mark ci deleted
    MOV     x0, #1
    LSL     x0, x0, #63
    STR     x0, [x22, #CUBE_FLAGS]
    B       .Lir_next_i

.Lir_next_j:
    ADD     x23, x23, #1
    B       .Lir_inner

.Lir_next_i:
    ADD     x21, x21, #1
    B       .Lir_outer

.Lir_compact:
    MOV     x0, x19
    BL      _compact_cover

    LDP     x25, x26, [sp, #64]
    LDP     x23, x24, [sp, #48]
    LDP     x21, x22, [sp, #32]
    LDP     x19, x20, [sp, #16]
    LDP     fp,  lr,  [sp], #80
    RET


// ------------------------------------------------------------------
// _compact_cover(x0=cover_ptr)
// ------------------------------------------------------------------
_compact_cover:
    STP     fp, lr,   [sp, #-16]!
    MOV     fp, sp

    LDR     x1, [x0, #COV_COUNT]
    LDR     x2, [x0, #COV_DATA]
    MOV     x3, #0              // write index
    MOV     x4, #0              // read index
    MOV     x5, #CUBE_SIZE

.Lcc_loop:
    CMP     x4, x1
    B.GE    .Lcc_done

    MUL     x6, x4, x5
    ADD     x6, x2, x6

    LDR     x7, [x6, #CUBE_FLAGS]
    TBNZ    x7, #63, .Lcc_skip

    CMP     x3, x4
    B.EQ    .Lcc_no_copy
    MUL     x8, x3, x5
    ADD     x8, x2, x8
    LDP     x9,  x10, [x6]
    STP     x9,  x10, [x8]
    LDP     x9,  x10, [x6, #16]
    STP     x9,  x10, [x8, #16]
    STR     xzr, [x8, #CUBE_FLAGS]

.Lcc_no_copy:
    ADD     x3, x3, #1

.Lcc_skip:
    ADD     x4, x4, #1
    B       .Lcc_loop

.Lcc_done:
    STR     x3, [x0, #COV_COUNT]
    LDP     fp, lr, [sp], #16
    RET


// ------------------------------------------------------------------
// _cube_intersects_cover(x0=cube_ptr, x1=cover_ptr) → x0=0/1
// (Used by the old D-intersection check; kept for future use.)
// ------------------------------------------------------------------
_cube_intersects_cover:
    STP     fp, lr,   [sp, #-64]!
    STP     x19, x20, [sp, #16]
    STP     x21, x22, [sp, #32]
    STP     x23, xzr, [sp, #48]
    MOV     fp, sp

    MOV     x19, x0
    MOV     x20, x1
    LDR     x21, [x20, #COV_COUNT]
    MOV     x22, #0

.Lcic_loop:
    CMP     x22, x21
    B.GE    .Lcic_no

    MOV     x0, x20
    MOV     x1, x22
    BL      _cover_get
    MOV     x23, x0

    LDR     x0, [x23, #CUBE_FLAGS]
    TBNZ    x0, #63, .Lcic_next

    MOV     x0, x19
    MOV     x1, x23
    BL      _cubes_intersect
    CBNZ    x0, .Lcic_yes

.Lcic_next:
    ADD     x22, x22, #1
    B       .Lcic_loop

.Lcic_yes:
    MOV     x0, #1
    LDP     x23, xzr, [sp, #48]
    LDP     x21, x22, [sp, #32]
    LDP     x19, x20, [sp, #16]
    LDP     fp,  lr,  [sp], #64
    RET

.Lcic_no:
    MOV     x0, #0
    LDP     x23, xzr, [sp, #48]
    LDP     x21, x22, [sp, #32]
    LDP     x19, x20, [sp, #16]
    LDP     fp,  lr,  [sp], #64
    RET


// ------------------------------------------------------------------
// _cubes_intersect(x0=c1_ptr, x1=c2_ptr) → x0=0/1
// ------------------------------------------------------------------
_cubes_intersect:
    LDR     x2, [x0, #CUBE_P]
    LDR     x3, [x0, #CUBE_N]
    LDR     x4, [x1, #CUBE_P]
    LDR     x5, [x1, #CUBE_N]
    AND     x6, x2, x5
    CBNZ    x6, .Lci_no
    AND     x6, x3, x4
    CBNZ    x6, .Lci_no
    LDR     x6, [x0, #CUBE_OUT]
    LDR     x7, [x1, #CUBE_OUT]
    AND     x6, x6, x7
    CBZ     x6, .Lci_no
    MOV     x0, #1
    RET
.Lci_no:
    MOV     x0, #0
    RET


// ------------------------------------------------------------------
// _write_pla(x0=pla_ptr)
//
// Callee-saved layout (112-byte frame):
//   x19=pla x20=ninputs x21=noutputs x22=F-cover
//   x23=cube-index x24=cube-ptr x25=p x26=n x27=out_mask
// ------------------------------------------------------------------
_write_pla:
    STP     fp, lr,   [sp, #-112]!
    STP     x19, x20, [sp, #16]
    STP     x21, x22, [sp, #32]
    STP     x23, x24, [sp, #48]
    STP     x25, x26, [sp, #64]
    STP     x27, xzr, [sp, #80]
    MOV     fp, sp

    MOV     x19, x0
    LDR     x20, [x19, #PLA_NI]
    LDR     x21, [x19, #PLA_NO]
    LDR     x22, [x19, #PLA_F]

    // .i <ninputs>
    MOV     x0, #'.'
    BL      _out_byte
    MOV     x0, #'i'
    BL      _out_byte
    MOV     x0, #' '
    BL      _out_byte
    MOV     x0, x20
    BL      _out_u64
    MOV     x0, #'\n'
    BL      _out_byte

    // .o <noutputs>
    MOV     x0, #'.'
    BL      _out_byte
    MOV     x0, #'o'
    BL      _out_byte
    MOV     x0, #' '
    BL      _out_byte
    MOV     x0, x21
    BL      _out_u64
    MOV     x0, #'\n'
    BL      _out_byte

    // .p <count>
    MOV     x0, #'.'
    BL      _out_byte
    MOV     x0, #'p'
    BL      _out_byte
    MOV     x0, #' '
    BL      _out_byte
    LDR     x0, [x22, #COV_COUNT]
    BL      _out_u64
    MOV     x0, #'\n'
    BL      _out_byte

    // Term rows
    MOV     x23, #0             // cube index (callee-saved)

.Lwp_term:
    LDR     x0, [x22, #COV_COUNT]
    CMP     x23, x0
    B.GE    .Lwp_end

    MOV     x0, x22
    MOV     x1, x23
    BL      _cover_get
    MOV     x24, x0

    LDR     x25, [x24, #CUBE_P]
    LDR     x26, [x24, #CUBE_N]
    LDR     x27, [x24, #CUBE_OUT]

    // Input field (x9=bit index; _out_byte uses only x0-x3)
    MOV     x9, #0
.Lwp_in:
    CMP     x9, x20
    B.GE    .Lwp_in_done
    MOV     x0, #1
    LSL     x0, x0, x9
    TST     x25, x0
    B.NE    .Lwp_in_one
    TST     x26, x0
    B.NE    .Lwp_in_zero
    MOV     x0, #'-'
    BL      _out_byte
    ADD     x9, x9, #1
    B       .Lwp_in
.Lwp_in_one:
    MOV     x0, #'1'
    BL      _out_byte
    ADD     x9, x9, #1
    B       .Lwp_in
.Lwp_in_zero:
    MOV     x0, #'0'
    BL      _out_byte
    ADD     x9, x9, #1
    B       .Lwp_in

.Lwp_in_done:
    MOV     x0, #' '
    BL      _out_byte

    // Output field
    MOV     x9, #0
.Lwp_out:
    CMP     x9, x21
    B.GE    .Lwp_out_done
    MOV     x0, #1
    LSL     x0, x0, x9
    TST     x27, x0
    B.NE    .Lwp_out_one
    MOV     x0, #'0'
    BL      _out_byte
    ADD     x9, x9, #1
    B       .Lwp_out
.Lwp_out_one:
    MOV     x0, #'1'
    BL      _out_byte
    ADD     x9, x9, #1
    B       .Lwp_out

.Lwp_out_done:
    MOV     x0, #'\n'
    BL      _out_byte
    ADD     x23, x23, #1
    B       .Lwp_term

.Lwp_end:
    MOV     x0, #'.'
    BL      _out_byte
    MOV     x0, #'e'
    BL      _out_byte
    MOV     x0, #'\n'
    BL      _out_byte
    BL      _out_flush

    LDP     x27, xzr, [sp, #80]
    LDP     x25, x26, [sp, #64]
    LDP     x23, x24, [sp, #48]
    LDP     x21, x22, [sp, #32]
    LDP     x19, x20, [sp, #16]
    LDP     fp,  lr,  [sp], #112
    RET


// ---- Output helpers -----------------------------------

_out_byte:
    ADRP    x1, _out_pos@PAGE
    ADD     x1, x1, _out_pos@PAGEOFF
    LDR     x2, [x1]
    ADRP    x3, _out_buf@PAGE
    ADD     x3, x3, _out_buf@PAGEOFF
    STRB    w0, [x3, x2]
    ADD     x2, x2, #1
    STR     x2, [x1]
    RET

_out_u64:
    CBNZ    x0, .Lou64_nz
    ADRP    x2, _out_pos@PAGE
    ADD     x2, x2, _out_pos@PAGEOFF
    LDR     x3, [x2]
    ADRP    x4, _out_buf@PAGE
    ADD     x4, x4, _out_buf@PAGEOFF
    MOV     w5, #'0'
    STRB    w5, [x4, x3]
    ADD     x3, x3, #1
    STR     x3, [x2]
    RET
.Lou64_nz:
    ADRP    x2, _out_pos@PAGE
    ADD     x2, x2, _out_pos@PAGEOFF
    LDR     x3, [x2]
    ADRP    x4, _out_buf@PAGE
    ADD     x4, x4, _out_buf@PAGEOFF
    MOV     x5, #10
    MOV     x6, x3
.Lou64_loop:
    CBZ     x0, .Lou64_rev
    UDIV    x7, x0, x5
    MSUB    x8, x7, x5, x0
    ADD     x8, x8, #'0'
    STRB    w8, [x4, x6]
    ADD     x6, x6, #1
    MOV     x0, x7
    B       .Lou64_loop
.Lou64_rev:
    MOV     x9,  x3
    SUB     x10, x6, #1
.Lou64_rev_loop:
    CMP     x9, x10
    B.GE    .Lou64_done
    LDRB    w11, [x4, x9]
    LDRB    w12, [x4, x10]
    STRB    w11, [x4, x10]
    STRB    w12, [x4, x9]
    ADD     x9,  x9,  #1
    SUB     x10, x10, #1
    B       .Lou64_rev_loop
.Lou64_done:
    STR     x6, [x2]
    RET

_out_flush:
    ADRP    x1, _out_pos@PAGE
    ADD     x1, x1, _out_pos@PAGEOFF
    LDR     x2, [x1]
    CBZ     x2, .Lof_ret
    MOV     x0, #STDOUT
    ADRP    x1, _out_buf@PAGE
    ADD     x1, x1, _out_buf@PAGEOFF
    LDR     x16, =SYS_WRITE
    SVC     #0x80
    ADRP    x0, _out_pos@PAGE
    ADD     x0, x0, _out_pos@PAGEOFF
    STR     xzr, [x0]
.Lof_ret:
    RET
