/* GAP9 pv.unpack (patch 0006). Silicon: unpack1.lo = {lane0: ext(b0), lane1:
 * ext(b1)}, unpack1.hi the same for b2/b3; unpack2 writes the register pair
 * rd:rd+1 = (unpack1.lo, unpack1.hi) and ignores the register in its rs2 field.
 * Built with -O2 -march=rv32imcxgap9 -mint64 -S; gap9-asm-checks.sh greps it. */
typedef signed char v4s __attribute__((vector_size(4)));
typedef unsigned char v4u __attribute__((vector_size(4)));
typedef short v2s __attribute__((vector_size(4)));

/* GCC simplifies a lane of the result through the pattern's RTL, so these show
 * the lane order: pv.extract.b of byte 0, 1 and 2, and the constant 1. */
short lo_lane0(v4s x) { v2s r = __builtin_pulp_unpacklo_h_b_s(x); return r[0]; }
short lo_lane1(v4s x) { v2s r = __builtin_pulp_unpacklo_h_b_s(x); return r[1]; }
short hi_lane0(v4s x) { v2s r = __builtin_pulp_unpackhi_h_b_s(x); return r[0]; }
short lo_const_lane0(void) { v2s r = __builtin_pulp_unpacklo_h_b_s((v4s){ 1, 2, 3, 4 }); return r[0]; }

v2s lo_s(v4s x) { return __builtin_pulp_unpacklo_h_b_s(x); }
v2s hi_u(v4u x) { return __builtin_pulp_unpackhi_h_b_u(x); }

/* unpack2: a pair destination, rs2 printed as zero; the builtin returns the low pair. */
v2s pair_s(v4s x, v2s y) { return __builtin_pulp_unpack_h_b_s(x, y); }
v2s pair_u(v4u x, v2s y) { return __builtin_pulp_unpack_h_b_u(x, y); }
