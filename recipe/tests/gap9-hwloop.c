/* GAP9 hardware loops of one store or load (patch 0008). Silicon runs a
 * hardware loop whose body is one instruction once, so GCC pads such a body
 * with a nop. OffsetedWritePtr (GAP_WRITE_PTR, as in the SDK's eu_sem_inc) and
 * event_unit_read_fenced expand to a code-less barrier and the access, which
 * counted as two instructions. Built with -O2, -O3 and -Os
 * -march=rv32imcxgap9 -S; gap9-asm-checks.sh counts each loop's body. */
void inc100(unsigned int sem)
{
    for (int i = 0; i < 100; i++)
        __builtin_pulp_OffsetedWritePtr((int *)1, (int *)sem, 0x404);
}

void incn(unsigned int sem, int n)
{
    for (int i = 0; i < n; i++)
        __builtin_pulp_OffsetedWritePtr((int *)1, (int *)sem, 0x404);
}

void poll100(int *base)
{
    for (int i = 0; i < 100; i++)
        (void)__builtin_pulp_event_unit_read_fenced(base, 0x3c);
}

/* Two instructions of their own: no pad. */
int sum(const int *a, int n)
{
    int s = 0;
    for (int i = 0; i < n; i++)
        s += a[i];
    return s;
}
