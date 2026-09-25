/* GCC1 exec test harness for unpack_fns.c: expected values from plain C bit
 * operations (silicon semantics, ROADMAP §5.7 of gap-llvm-toolchain). */
#include <pmsis.h>
typedef signed char v4s __attribute__((vector_size(4)));
typedef unsigned char v4u __attribute__((vector_size(4)));
typedef short v2s __attribute__((vector_size(4)));

v2s f_lo_s(v4s x);
v2s f_hi_s(v4s x);
v2s f_lo_u(v4u x);
v2s f_hi_u(v4u x);
v2s f_pair_s(v4s x, v2s y);
v2s f_pair_u(v4u x, v2s y);
int f_lo_lane0(v4s x);
int f_lo_lane1(v4s x);
int f_hi_lane0(v4s x);
int f_hi_lane1(v4s x);
int f_const_lane0(void);
int f_pair_keep1(v4s x, int k0);
int f_pair_keep3(v4s x, int k0, int k1);

static int errors, checks;
static void check(const char *name, unsigned u, unsigned got, unsigned want)
{
  checks++;
  if (got != want) {
    errors++;
    printf("GCC1 FAIL %s x=%08lx got=%08lx want=%08lx\n", name, (unsigned long)u, (unsigned long)got,
           (unsigned long)want);
  }
}
static unsigned bits(v2s v) { union { v2s v; unsigned u; } x; x.v = v; return x.u; }
static v4s mks(unsigned u) { union { unsigned u; v4s v; } x; x.u = u; return x.v; }
static v4u mku(unsigned u) { union { unsigned u; v4u v; } x; x.u = u; return x.v; }
static unsigned h2(int lo, int hi) { return ((unsigned)lo & 0xffffu) | ((unsigned)hi << 16); }
static int sb(unsigned u, int i) { return (signed char)(u >> (8 * i)); }
static int zb(unsigned u, int i) { return (u >> (8 * i)) & 0xff; }

int main(void)
{
  static const unsigned xs[] = { 0x04030201u, 0x80ff7f01u, 0xfe01c33cu, 0u, 0xffffffffu, 0x7f80017eu };
  v2s zero = { 0, 0 };
  for (unsigned i = 0; i < sizeof(xs) / sizeof(xs[0]); i++) {
    unsigned u = xs[i];
    unsigned lo_s = h2(sb(u, 0), sb(u, 1)), hi_s = h2(sb(u, 2), sb(u, 3));
    unsigned lo_u = h2(zb(u, 0), zb(u, 1)), hi_u = h2(zb(u, 2), zb(u, 3));
    check("lo_s", u, bits(f_lo_s(mks(u))), lo_s);
    check("hi_s", u, bits(f_hi_s(mks(u))), hi_s);
    check("lo_u", u, bits(f_lo_u(mku(u))), lo_u);
    check("hi_u", u, bits(f_hi_u(mku(u))), hi_u);
    check("pair_s", u, bits(f_pair_s(mks(u), zero)), lo_s);
    check("pair_u", u, bits(f_pair_u(mku(u), zero)), lo_u);
    check("lo_lane0", u, f_lo_lane0(mks(u)), sb(u, 0));
    check("lo_lane1", u, f_lo_lane1(mks(u)), sb(u, 1));
    check("hi_lane0", u, f_hi_lane0(mks(u)), sb(u, 2));
    check("hi_lane1", u, f_hi_lane1(mks(u)), sb(u, 3));
    check("pair_keep1", u, f_pair_keep1(mks(u), 0x12345678), lo_s ^ 0x12345678u);
    check("pair_keep3", u, f_pair_keep3(mks(u), 0x12345678, 7), (lo_s ^ 0x12345678u) + 21);
  }
  check("const_lane0", 0x04030201u, f_const_lane0(), 1);
  printf("GCC1 unpack: %d checks, %d errors\n", checks, errors);
  printf("GCC1 DONE\n");
  return errors != 0;
}
