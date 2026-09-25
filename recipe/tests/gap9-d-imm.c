/* GAP9 .d immediates (patch 0005): silicon zero-extends the 5-bit immediate of
 * xori.d/ori.d/andi.d/sltiu.d (0..31) and sign-extends it for addi.d/slti.d
 * (-16..15). GCC must never print a negative immediate for the first four.
 * Built with -O2 -march=rv32imcxgap9 -mint64 -S; gap9-asm-checks.sh greps it. */
typedef unsigned long long u64;
typedef long long s64;
extern void g(void);

/* The miscompile: this used to be sltiu.d a0,a0,-16, i.e. x < 16 on silicon. */
int ltu_m16(u64 x) { return x < 0xfffffffffffffff0ULL; }
int leu_m17(u64 x) { return x <= 0xffffffffffffffefULL; }
int geu_m16(u64 x) { return x >= 0xfffffffffffffff0ULL; }
int gtu_m16(u64 x) { return x > 0xfffffffffffffff0ULL; }
void br_geu_m16(u64 x) { if (x >= 0xfffffffffffffff0ULL) g(); }
void br_ltu_m1(u64 x) { if (x < 0xffffffffffffffffULL) g(); }

/* 16..31 now fit the unsigned immediate. */
int ltu_16(u64 x) { return x < 16; }
int ltu_31(u64 x) { return x < 31; }
int leu_30(u64 x) { return x <= 30; }
void br_geu_20(u64 x) { if (x >= 20) g(); }

/* GCC splits 64-bit AND/IOR/XOR into word ops (there is no anddi3), so these
 * only guard against a negative immediate if a .d form is ever chosen. */
u64 and_m16(u64 x) { return x & 0xfffffffffffffff0ULL; }
u64 or_m16(u64 x) { return x | 0xfffffffffffffff0ULL; }
u64 xor_m1(u64 x) { return x ^ 0xffffffffffffffffULL; }
u64 xor_m16(u64 x) { return x ^ 0xfffffffffffffff0ULL; }
u64 and_31(u64 x) { return x & 31; }
u64 xor_17(u64 x) { return x ^ 17; }

/* Signed forms keep simm5. */
int lt_m16(s64 x) { return x < -16; }
int le_m17(s64 x) { return x <= -17; }
s64 add_m16(s64 x) { return x - 16; }
