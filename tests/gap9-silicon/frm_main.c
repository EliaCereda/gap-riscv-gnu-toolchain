/* GCC1 probe: how many instructions after a write to frm does an FP instruction
 * that rounds by frm see the new mode? Not self-checking: prints what each
 * sequence gave, "new" or "OLD" (the mode before the write).
 * Each case: frm = RNE, settle, write frm = <mode> by <how>, then d-1 nops,
 * then one FP instruction; frm is set back to RNE and allowed to settle. */
#include <pmsis.h>

#define NOP1 "nop\n\t"
#define NOPS(n) NOPS_##n
#define NOPS_0 ""
#define NOPS_1 NOP1
#define NOPS_2 NOP1 NOP1
#define NOPS_3 NOP1 NOP1 NOP1
#define SETTLE "fsrm zero\n\t" NOP1 NOP1 NOP1 NOP1 NOP1 NOP1 NOP1 NOP1

/* fadd.s 1 + 2^-24 (a tie): RNE gives 0x3f800000, RUP 0x3f800001. */
#define FADD_FSRM(n)                                                                          \
  static unsigned fadd_fsrm_##n(void)                                                        \
  {                                                                                          \
    unsigned r, one = 0x3f800000u, tiny = 0x33800000u, rup = 3;                              \
    asm volatile(SETTLE "fsrm %[m]\n\t" NOPS(n) "fadd.s %[r], %[a], %[b]\n\t" SETTLE        \
                 : [r] "=&r"(r) : [a] "r"(one), [b] "r"(tiny), [m] "r"(rup));                 \
    return r;                                                                                \
  }
#define FADD_FSCSR(n)                                                                         \
  static unsigned fadd_fscsr_##n(void)                                                       \
  {                                                                                          \
    unsigned r, one = 0x3f800000u, tiny = 0x33800000u, rup = 3 << 5;                         \
    asm volatile(SETTLE "fscsr %[m]\n\t" NOPS(n) "fadd.s %[r], %[a], %[b]\n\t" SETTLE       \
                 : [r] "=&r"(r) : [a] "r"(one), [b] "r"(tiny), [m] "r"(rup));                 \
    return r;                                                                                \
  }
#define FADD_CSRRWI(n)                                                                        \
  static unsigned fadd_csrrwi_##n(void)                                                      \
  {                                                                                          \
    unsigned r, t, one = 0x3f800000u, tiny = 0x33800000u;                                     \
    asm volatile(SETTLE "csrrwi %[t], 2, 3\n\t" NOPS(n) "fadd.s %[r], %[a], %[b]\n\t" SETTLE \
                 : [r] "=&r"(r), [t] "=&r"(t) : [a] "r"(one), [b] "r"(tiny));                 \
    return r;                                                                                \
  }
/* fcvt.w.ah / vfcvt.x.ah of 1.5 under RTZ: 1 (new) or 2 (RNE, old). */
#define CVT_CSRRWI(n)                                                                         \
  static unsigned cvt_csrrwi_##n(void)                                                       \
  {                                                                                          \
    unsigned r, t, x = 0x3fc0u;                                                              \
    asm volatile(SETTLE "csrrwi %[t], 2, 1\n\t" NOPS(n) "fcvt.w.ah %[r], %[x]\n\t" SETTLE    \
                 : [r] "=&r"(r), [t] "=&r"(t) : [x] "r"(x));                                  \
    return r;                                                                                \
  }
#define VCVT_CSRRWI(n)                                                                        \
  static unsigned vcvt_csrrwi_##n(void)                                                      \
  {                                                                                          \
    unsigned r, t, x = 0x3fc03fc0u;                                                          \
    asm volatile(SETTLE "csrrwi %[t], 2, 1\n\t" NOPS(n) "vfcvt.x.ah %[r], %[x]\n\t" SETTLE   \
                 : [r] "=&r"(r), [t] "=&r"(t) : [x] "r"(x));                                  \
    return r;                                                                                \
  }
/* Restore direction: frm = RTZ settled, write RNE, then vfcvt.x.ah 1.5: 2 (new) or 1 (old). */
#define VCVT_RESTORE(n)                                                                       \
  static unsigned vcvt_restore_##n(void)                                                     \
  {                                                                                          \
    unsigned r, rtz = 1, x = 0x3fc03fc0u;                                                    \
    asm volatile("fsrm %[z]\n\t" NOP1 NOP1 NOP1 NOP1 NOP1 NOP1 NOP1 NOP1                     \
                 "fsrm zero\n\t" NOPS(n) "vfcvt.x.ah %[r], %[x]\n\t" SETTLE                  \
                 : [r] "=&r"(r) : [x] "r"(x), [z] "r"(rtz));                                  \
    return r;                                                                                \
  }

#define ALL(M) M(0) M(1) M(2) M(3)
ALL(FADD_FSRM)
ALL(FADD_FSCSR)
ALL(FADD_CSRRWI)
ALL(CVT_CSRRWI)
ALL(VCVT_CSRRWI)
ALL(VCVT_RESTORE)

static void row(const char *name, unsigned newval, unsigned r0, unsigned r1, unsigned r2, unsigned r3)
{
  unsigned r[4] = { r0, r1, r2, r3 };
  printf("GCC1 FRM %-26s", name);
  for (int d = 0; d < 4; d++)
    printf(" d=%d:%s(%08lx)", d + 1, r[d] == newval ? "new" : "OLD", (unsigned long)r[d]);
  printf("\n");
}

int main(void)
{
  row("fsrm RUP -> fadd.s", 0x3f800001u, fadd_fsrm_0(), fadd_fsrm_1(), fadd_fsrm_2(), fadd_fsrm_3());
  row("fscsr RUP -> fadd.s", 0x3f800001u, fadd_fscsr_0(), fadd_fscsr_1(), fadd_fscsr_2(), fadd_fscsr_3());
  row("csrrwi RUP -> fadd.s", 0x3f800001u, fadd_csrrwi_0(), fadd_csrrwi_1(), fadd_csrrwi_2(), fadd_csrrwi_3());
  row("csrrwi RTZ -> fcvt.w.ah", 1, cvt_csrrwi_0(), cvt_csrrwi_1(), cvt_csrrwi_2(), cvt_csrrwi_3());
  row("csrrwi RTZ -> vfcvt.x.ah", 0x00010001u, vcvt_csrrwi_0(), vcvt_csrrwi_1(), vcvt_csrrwi_2(),
      vcvt_csrrwi_3());
  row("fsrm RNE (from RTZ) -> vfcvt", 0x00020002u, vcvt_restore_0(), vcvt_restore_1(), vcvt_restore_2(),
      vcvt_restore_3());
  printf("GCC1 DONE\n");
  return 0;
}
