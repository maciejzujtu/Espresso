// =================================================== //
// Description:      Bump allocator + cover helpers   //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //

.include "include/defs.inc"

// ---- BSS ----------------------------------------------
.section __DATA, __bss
.align  4
_heap:      .space HEAP_SIZE        // 512 KB pool

.align  3
_heap_ptr:  .space 8                // bump pointer


// ---- Text ---------------------------------------------
.section __TEXT, __text

// _alloc_init — reset bump pointer to start of _heap
.global _alloc_init
_alloc_init:
    ADRP    x0, _heap@PAGE
    ADD     x0, x0, _heap@PAGEOFF
    ADRP    x1, _heap_ptr@PAGE
    ADD     x1, x1, _heap_ptr@PAGEOFF
    STR     x0, [x1]
    RET


// _alloc(x0=size) → ptr in x0  (0 on OOM)
// Allocates size bytes, rounded up to 8-byte alignment.
.global _alloc
_alloc:
    // Round up to next multiple of 8
    ADD     x0, x0, #7
    BIC     x0, x0, #7

    ADRP    x1, _heap_ptr@PAGE
    ADD     x1, x1, _heap_ptr@PAGEOFF
    LDR     x2, [x1]               // current bump ptr

    // Compute remaining space: heap_end - bump_ptr
    ADRP    x3, _heap@PAGE
    ADD     x3, x3, _heap@PAGEOFF
    MOV     x4, #HEAP_SIZE
    ADD     x3, x3, x4             // x3 = heap end
    SUB     x3, x3, x2             // x3 = remaining bytes
    CMP     x3, x0
    B.LT    .La_oom

    ADD     x3, x2, x0             // new bump ptr
    STR     x3, [x1]
    MOV     x0, x2                 // return old ptr
    RET

.La_oom:
    MOV     x0, #0
    RET


// _cover_new() → cover ptr in x0  (0 on OOM)
// Allocates a cover struct + MAX_TERMS cube slots.
.global _cover_new
_cover_new:
    STP     fp, lr,   [sp, #-32]!
    STP     x19, x20, [sp, #16]
    MOV     fp, sp

    // Allocate cover header
    MOV     x0, #COV_STRUCT_SIZE
    BL      _alloc
    CBZ     x0, .La_cov_oom
    MOV     x19, x0                // x19 = cover ptr (callee-saved → safe across BL)

    // Allocate cube array
    MOV     x0, #(MAX_TERMS * CUBE_SIZE)
    BL      _alloc
    CBZ     x0, .La_cov_oom

    // Initialise header
    STR     xzr, [x19, #COV_COUNT]
    MOV     x1,  #MAX_TERMS
    STR     x1,  [x19, #COV_CAP]
    STR     x0,  [x19, #COV_DATA]
    MOV     x0,  x19

    LDP     x19, x20, [sp, #16]
    LDP     fp,  lr,  [sp], #32
    RET

.La_cov_oom:
    MOV     x0, #0
    LDP     x19, x20, [sp, #16]
    LDP     fp,  lr,  [sp], #32
    RET


// _cover_add(x0=cover_ptr, x1=p_part, x2=n_part, x3=out_mask)
// Appends one cube.  Returns 0 on success, -1 if cover is full.
// Leaf function — no frame needed.
.global _cover_add
_cover_add:
    LDR     x4, [x0, #COV_COUNT]
    LDR     x5, [x0, #COV_CAP]
    CMP     x4, x5
    B.GE    .La_full

    LDR     x6, [x0, #COV_DATA]
    MOV     x7, #CUBE_SIZE
    MUL     x7, x4, x7
    ADD     x6, x6, x7             // slot = data + count * CUBE_SIZE

    STR     x1, [x6, #CUBE_P]
    STR     x2, [x6, #CUBE_N]
    STR     x3, [x6, #CUBE_OUT]
    STR     xzr,[x6, #CUBE_FLAGS]  // clear flags (not deleted)

    ADD     x4, x4, #1
    STR     x4, [x0, #COV_COUNT]
    MOV     x0, #0
    RET

.La_full:
    MOV     x0, #-1
    RET


// _cover_get(x0=cover_ptr, x1=index) → cube ptr in x0
// Returns pointer to cube at given index (no bounds check).
.global _cover_get
_cover_get:
    LDR     x2, [x0, #COV_DATA]
    MOV     x3, #CUBE_SIZE
    MUL     x3, x1, x3
    ADD     x0, x2, x3
    RET
