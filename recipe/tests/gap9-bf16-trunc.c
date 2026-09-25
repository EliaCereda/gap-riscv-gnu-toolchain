/* bf16 <-> integer conversions (patch 0007). fcvt.w.ah and vfcvt.x.ah have no
 * rounding-mode field (rm = 101 is what selects .ah), so they can't be asked
 * to truncate, and on GAP9 silicon an FP instruction right after a write to frm
 * still rounds by the old frm. C conversions to integer widen to float (exact)
 * and use fcvt.w.s rtz, scalar and vectorised alike; nothing writes fcsr. The
 * builtins stay plain instructions.
 * Built with -O3 -march=rv32imcxgap9 -mint64 -S; gap9-asm-checks.sh greps it. */
typedef float16alt bf16;
typedef float16alt v2bf __attribute__((vector_size(4)));
typedef short v2s __attribute__((vector_size(4)));

int to_int(bf16 x) { return (int)x; }
unsigned to_uint(bf16 x) { return (unsigned)x; }

/* Not vectorised any more: scalar widen + fcvt.w.s rtz per element. */
void to_short_array(const bf16 *a, short *b)
{
  for (int i = 0; i < 64; i++)
    b[i] = (short)a[i];
}

/* int -> bf16 rounds by frm: vfcvt.ah.x on pairs, without fcsr writes. */
void from_short_array(const short *a, bf16 *b)
{
  for (int i = 0; i < 64; i++)
    b[i] = (bf16)a[i];
}

v2s builtin_round(v2bf x) { return __builtin_pulp_v2ohftov2hi(x); }
