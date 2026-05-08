// =================================================== //
// Description:      Variable definitions             //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //

// SYSCALL
.equ SYS_EXIT,          0x2000001
.equ SYS_READ,          0x2000003
.equ SYS_WRITE,         0x2000004
.equ SYS_OPEN,          0x2000005
.equ SYS_CLOSE,         0x2000006
.equ SYS_IOCTL,         0x2000036

// STD
.equ STDIN,             0x0000
.equ STDOUT,            0x0001
.equ STDERR,            0x0002
.equ BUF_SIZE,          65536       // 64 KB stdin buffer

// FILE FLAGS
.equ O_RDONLY,          0x0000
.equ O_WRONLY,          0x0001
.equ O_RDWR,            0x0002

// ---- Allocator ----------------------------------------
.equ HEAP_SIZE,         524288      // 512 KB heap
.equ OUT_BUF_SIZE,      65536       // 64 KB output buffer

// ---- Cube struct (32 bytes, power-of-2 for fast idx) --
// p_part: bit i = 1 → input i must be 1 (positive literal)
// n_part: bit i = 1 → input i must be 0 (negative literal)
// both = 0 → don't-care;  both = 1 → impossible (empty)
.equ CUBE_P,            0           // positive input literals (u64)
.equ CUBE_N,            8           // negative input literals (u64)
.equ CUBE_OUT,          16          // output bitmask (u64)
.equ CUBE_FLAGS,        24          // internal flags; bit 63 = deleted
.equ CUBE_SIZE,         32

// ---- Cover struct (24 bytes) --------------------------
.equ COV_COUNT,         0           // live cube count (u64)
.equ COV_CAP,           8           // allocated capacity in cubes (u64)
.equ COV_DATA,          16          // pointer to cube array (u64)
.equ COV_STRUCT_SIZE,   24

// ---- PLA state struct (40 bytes) ----------------------
.equ PLA_NI,            0           // num_inputs  (u64)
.equ PLA_NO,            8           // num_outputs (u64)
.equ PLA_F,             16          // ON-set  cover ptr (u64)
.equ PLA_D,             24          // DC-set  cover ptr (u64)
.equ PLA_R,             32          // OFF-set cover ptr (u64)
.equ PLA_STRUCT_SIZE,   40

// ---- Cover capacity limits ----------------------------
.equ MAX_TERMS,         512         // max cubes per cover
.equ MAX_INPUTS,        64
.equ MAX_OUTPUTS,       64
