/* GCC1 exec test, functions under test: pv.unpack builtins (compiled by the
 * GCC under test at -O2). Silicon: unpack1.lo = {lane0: ext(b0), lane1: ext(b1)},
 * unpack1.hi = {ext(b2), ext(b3)}; unpack2 writes rd = lo pair, rd+1 = hi pair. */
typedef signed char v4s __attribute__((vector_size(4)));
typedef unsigned char v4u __attribute__((vector_size(4)));
typedef short v2s __attribute__((vector_size(4)));
#define NI __attribute__((noinline))

NI v2s f_lo_s(v4s x) { return __builtin_pulp_unpacklo_h_b_s(x); }
NI v2s f_hi_s(v4s x) { return __builtin_pulp_unpackhi_h_b_s(x); }
NI v2s f_lo_u(v4u x) { return __builtin_pulp_unpacklo_h_b_u(x); }
NI v2s f_hi_u(v4u x) { return __builtin_pulp_unpackhi_h_b_u(x); }
NI v2s f_pair_s(v4s x, v2s y) { return __builtin_pulp_unpack_h_b_s(x, y); }
NI v2s f_pair_u(v4u x, v2s y) { return __builtin_pulp_unpack_h_b_u(x, y); }

/* Lanes read back through GCC's RTL simplifications. */
NI int f_lo_lane0(v4s x) { v2s r = __builtin_pulp_unpacklo_h_b_s(x); return r[0]; }
NI int f_lo_lane1(v4s x) { v2s r = __builtin_pulp_unpacklo_h_b_s(x); return r[1]; }
NI int f_hi_lane0(v4s x) { v2s r = __builtin_pulp_unpackhi_h_b_s(x); return r[0]; }
NI int f_hi_lane1(v4s x) { v2s r = __builtin_pulp_unpackhi_h_b_s(x); return r[1]; }
NI int f_const_lane0(void) { v2s r = __builtin_pulp_unpacklo_h_b_s((v4s){ 1, 2, 3, 4 }); return r[0]; }

/* unpack2 with a value live in rd+1: silicon writes rd+1, which GWT GCC 7
 * didn't know (it printed pv.unpack2 a0,a0,a5 and then read k0 from a1). */
NI int f_pair_keep1(v4s x, int k0)
{
  union { v2s v; int i; } u;
  u.v = __builtin_pulp_unpack_h_b_s(x, (v2s){ 0, 0 });
  return u.i ^ k0;
}
NI int f_pair_keep3(v4s x, int k0, int k1)
{
  union { v2s v; int i; } u;
  u.v = __builtin_pulp_unpack_h_b_s(x, (v2s){ 0, 0 });
  return (u.i ^ k0) + k1 * 3;
}
