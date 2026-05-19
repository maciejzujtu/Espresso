// =================================================== //
// Description:      Bump allocator + cover helpers    //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //

.include "include/defs.inc"



// ===================================================== //
// Heap storage — a single flat 512 KB BSS pool.         //
// _heap_ptr holds the current bump pointer; it starts   //
// at _heap on _alloc_init and advances with each call.  //
// ===================================================== //

.section __DATA,    __bss
    .align 4
        _heap:              .space  HEAP_SIZE            // 512 KB allocation pool

    .align 3
        _heap_ptr:          .space  8                    // Bump pointer into _heap



// ===================================================== //
// _alloc_init()                                         //
//   Resets the bump pointer to the start of _heap.      //
//   Call once before any _alloc / _cover_new calls.     //
//   Leaf function — no frame needed.                    //
// ===================================================== //

.section __text,    __text
    .globl _alloc_init

_alloc_init:
    ADRP    x0,             _heap@PAGE                  // Load page address of _heap
    ADD     x0, x0,         _heap@PAGEOFF               // Resolve full address
    ADRP    x1,             _heap_ptr@PAGE
    ADD     x1, x1,         _heap_ptr@PAGEOFF
    STR     x0,             [x1]                        // heap_ptr = &_heap
    RET



// ===================================================== //
// _alloc(x0=size) -> ptr in x0  (0 on OOM)             //
//   Allocates size bytes rounded up to 8-byte           //
//   alignment from the bump pool.                       //
//   Leaf function — no frame needed.                    //
// ===================================================== //

    .globl _alloc

_alloc:
    // -- round size up to next multiple of 8 --
    ADD     x0, x0,         #7                          // size = size + 7
    BIC     x0, x0,         #7                          // size = size & ~7 (clears low 3 bits)

    ADRP    x1,             _heap_ptr@PAGE
    ADD     x1, x1,         _heap_ptr@PAGEOFF
    LDR     x2,             [x1]                        // x2 = current bump pointer

    // -- check remaining space: heap_end - bump_ptr >= size --
    ADRP    x3,             _heap@PAGE
    ADD     x3, x3,         _heap@PAGEOFF
    MOV     x4,             #HEAP_SIZE
    ADD     x3, x3,         x4                          // x3 = heap end address
    SUB     x3, x3,         x2                          // x3 = remaining bytes
    CMP     x3,             x0
    B.LT                    _alloc_oom                  // Not enough space

    // -- advance bump pointer and return old position --
    ADD     x3, x2,         x0                          // new bump ptr = old ptr + size
    STR     x3,             [x1]                        // store new bump pointer
    MOV     x0,             x2                          // return old (allocated) pointer
    RET

_alloc_oom:
    MOV     x0,             #0                          // Return null on out-of-memory
    RET



// ===================================================== //
// _cover_new() -> cover ptr in x0  (0 on OOM)           //
//   Allocates a cover header (COV_STRUCT_SIZE bytes)    //
//   plus MAX_TERMS cube slots, then initialises the     //
//   count/cap/data fields before returning.             //
// ===================================================== //

    .globl _cover_new

_cover_new:
    // -- prologue --
    SUB     sp, sp,         #32                         // Allocate 32 bytes for fp, lr and x19, x20
    STP     fp, lr,         [sp, #16]                   // Store Frame Pointer & Link Register
    STP     x19, x20,       [sp, #0]                    // x19 = cover ptr  x20 = (unused, pair slot)
    ADD     fp, sp,         #16                         // Frame pointer -> saved fp/lr slot

    // -- allocate cover header --
    MOV     x0,             #COV_STRUCT_SIZE
    BL                      _alloc
    CBZ     x0,             _cover_new_oom              // Bail on OOM
    MOV     x19,            x0                          // x19 = cover ptr (callee-saved across BL)

    // -- allocate cube array --
    MOV     x0,             #(MAX_TERMS * CUBE_SIZE)
    BL                      _alloc
    CBZ     x0,             _cover_new_oom              // Bail on OOM

    // -- initialise cover header fields --
    STR     xzr,            [x19, #COV_COUNT]           // count = 0
    MOV     x1,             #MAX_TERMS
    STR     x1,             [x19, #COV_CAP]             // cap   = MAX_TERMS
    STR     x0,             [x19, #COV_DATA]            // data  = cube array pointer
    MOV     x0,             x19                         // Return cover pointer

    // -- epilogue --
    LDP     x19, x20,       [sp, #0]
    LDP     fp, lr,         [sp, #16]
    ADD     sp, sp,         #32
    RET

_cover_new_oom:
    MOV     x0,             #0                          // Return null on OOM
    LDP     x19, x20,       [sp, #0]
    LDP     fp, lr,         [sp, #16]
    ADD     sp, sp,         #32
    RET



// ===================================================== //
// _cover_add(x0=cover_ptr, x1=p_part,                  //
//            x2=n_part,    x3=out_mask)                 //
//   Appends one cube to the cover.                      //
//   Returns 0 on success, -1 if the cover is full.      //
//   Leaf function — no frame needed.                    //
// ===================================================== //

    .globl _cover_add

_cover_add:
    LDR     x4,             [x0, #COV_COUNT]            // x4 = current count
    LDR     x5,             [x0, #COV_CAP]              // x5 = capacity
    CMP     x4,             x5
    B.GE                    _cover_add_full             // Cover is full

    // -- compute slot address: data + count * CUBE_SIZE --
    LDR     x6,             [x0, #COV_DATA]
    MOV     x7,             #CUBE_SIZE
    MUL     x7, x4,         x7                          // offset = count * CUBE_SIZE
    ADD     x6, x6,         x7                          // slot   = data  + offset

    // -- write cube fields --
    STR     x1,             [x6, #CUBE_P]               // positive input literals
    STR     x2,             [x6, #CUBE_N]               // negative input literals
    STR     x3,             [x6, #CUBE_OUT]             // output bitmask
    STR     xzr,            [x6, #CUBE_FLAGS]           // flags = 0 (not deleted)

    // -- increment count --
    ADD     x4, x4,         #1
    STR     x4,             [x0, #COV_COUNT]
    MOV     x0,             #0                          // Return 0: success
    RET

_cover_add_full:
    MOV     x0,             #-1                         // Return -1: cover full
    RET



// ===================================================== //
// _cover_get(x0=cover_ptr, x1=index) -> cube ptr in x0 //
//   Returns a pointer to the cube at the given index.   //
//   No bounds check — caller is responsible.            //
//   Leaf function — no frame needed.                    //
// ===================================================== //

    .globl _cover_get

_cover_get:
    LDR     x2,             [x0, #COV_DATA]             // x2 = base of cube array
    MOV     x3,             #CUBE_SIZE
    MUL     x3, x1,         x3                          // offset = index * CUBE_SIZE
    ADD     x0, x2,         x3                          // return data + offset
    RET
