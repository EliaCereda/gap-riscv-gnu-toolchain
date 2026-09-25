/* GCC1 exec test harness for trunc_fns.c: C's bf16 -> integer conversions
 * truncate whatever frm holds and leave frm as it was; the builtin rounds by frm. */
#include <pmsis.h>
typedef float16alt bf16;
typedef float16alt v2bf __attribute__((vector_size(4)));
typedef short v2s __attribute__((vector_size(4)));

int f_to_int(bf16 x);
unsigned f_to_uint(bf16 x);
void f_to_short_array(const bf16 *a, short *b);
v2s f_builtin(v2bf x);

static int errors, checks;
static void check(const char *name, unsigned in, unsigned got, unsigned want)
{
  checks++;
  if (got != want) {
    errors++;
    printf("GCC1 FAIL %s in=%08lx got=%08lx want=%08lx\n", name, (unsigned long)in, (unsigned long)got,
           (unsigned long)want);
  }
}
static bf16 bf(unsigned short u) { union { unsigned short u; bf16 f; } x; x.u = u; return x.f; }
static v2bf v2(unsigned u) { union { unsigned u; v2bf v; } x; x.u = u; return x.v; }
static unsigned bits(v2s v) { union { v2s v; unsigned u; } x; x.v = v; return x.u; }
static void set_frm(unsigned rm) { asm volatile("fsrm %0" : : "r"(rm)); }
static unsigned get_frm(void) { unsigned rm; asm volatile("frrm %0" : "=r"(rm)); return rm; }

/* bf16 bits and the truncated value. */
static const struct { unsigned short in; int trunc; } cases[] = {
  { 0x3fc0, 1 },   /* 1.5 */
  { 0x4020, 2 },   /* 2.5 */
  { 0xbfc0, -1 },  /* -1.5 */
  { 0x3fe0, 1 },   /* 1.75 */
  { 0xc030, -2 },  /* -2.75 */
  { 0x42c9, 100 }, /* 100.5 */
  { 0x3f00, 0 },   /* 0.5 */
  { 0xbf40, 0 },   /* -0.75 */
  { 0x4040, 3 },   /* 3.0 */
};
#define N (sizeof(cases) / sizeof(cases[0]))

int main(void)
{
  static const unsigned modes[] = { 0 /* RNE */, 2 /* RDN */, 3 /* RUP */, 4 /* RMM */ };
  for (unsigned m = 0; m < sizeof(modes) / sizeof(modes[0]); m++) {
    unsigned rm = modes[m];
    for (unsigned i = 0; i < N; i++) {
      set_frm(rm);
      int r = f_to_int(bf(cases[i].in));
      check(rm == 0 ? "to_int RNE" : rm == 2 ? "to_int RDN" : rm == 3 ? "to_int RUP" : "to_int RMM", cases[i].in,
            r, cases[i].trunc);
      check("frm kept (to_int)", rm, get_frm(), rm);
      if (cases[i].trunc >= 0 && !(cases[i].in & 0x8000)) {
        set_frm(rm);
        check("to_uint", cases[i].in, f_to_uint(bf(cases[i].in)), cases[i].trunc);
      }
    }
    bf16 a[16];
    short b[16];
    for (unsigned i = 0; i < 16; i++)
      a[i] = bf(cases[i % N].in);
    set_frm(rm);
    f_to_short_array(a, b);
    check("frm kept (array)", rm, get_frm(), rm);
    for (unsigned i = 0; i < 16; i++)
      check("to_short_array", cases[i % N].in, (unsigned)(int)b[i], (unsigned)cases[i % N].trunc);
  }
  /* The builtin is vfcvt.x.ah: it rounds by frm (1.5, 2.5 -> 2, 2 under RNE; 1, 2 under RDN). */
  set_frm(0);
  check("builtin RNE", 0x40203fc0u, bits(f_builtin(v2(0x40203fc0u))), 0x00020002u);
  set_frm(2);
  check("builtin RDN", 0x40203fc0u, bits(f_builtin(v2(0x40203fc0u))), 0x00020001u);
  /* Not checks: what the raw instructions do under each frm (1.5, 2.5, -1.5). */
  for (unsigned m = 0; m < 5; m++) {
    unsigned r0, r1, r2, v;
    set_frm(m);
    asm volatile("fcvt.w.ah %0, %1" : "=r"(r0) : "r"(0x3fc0u));
    asm volatile("fcvt.w.ah %0, %1" : "=r"(r1) : "r"(0x4020u));
    asm volatile("fcvt.w.ah %0, %1" : "=r"(r2) : "r"(0xbfc0u));
    v = 0xdeadbeef; /* GVSOC aborts on vfcvt.x.ah with frm = RMM ("Unimplemented rounding mode") */
    if (m != 4)
      asm volatile("vfcvt.x.ah %0, %1" : "=r"(v) : "r"(0x40203fc0u));
    set_frm(0);
    printf("GCC1 INFO frm=%u fcvt.w.ah(1.5,2.5,-1.5)=%ld,%ld,%ld vfcvt.x.ah(1.5,2.5)=%08lx\n", m, (long)(int)r0,
           (long)(int)r1, (long)(int)r2, (unsigned long)v);
  }
  set_frm(0);
  printf("GCC1 trunc: %d checks, %d errors\n", checks, errors);
  printf("GCC1 DONE\n");
  return errors != 0;
}
