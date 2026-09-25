/* GCC1 exec test, functions under test: bf16 -> integer (compiled by the GCC
 * under test at -O3, so the loop is vectorised). C conversions truncate; the
 * builtin is the instruction, which rounds by frm. */
typedef float16alt bf16;
typedef float16alt v2bf __attribute__((vector_size(4)));
typedef short v2s __attribute__((vector_size(4)));
#define NI __attribute__((noinline))

NI int f_to_int(bf16 x) { return (int)x; }
NI unsigned f_to_uint(bf16 x) { return (unsigned)x; }
NI void f_to_short_array(const bf16 *a, short *b)
{
  for (int i = 0; i < 16; i++)
    b[i] = (short)a[i];
}
NI v2s f_builtin(v2bf x) { return __builtin_pulp_v2ohftov2hi(x); }
