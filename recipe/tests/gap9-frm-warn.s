# gas's GAP9 rounding-mode warnings (riscv-binutils-gdb patch 0005): every line
# tagged WARN must warn, and no other line may. gap9-asm-checks.sh assembles it
# with -march=rv32imcxgap9 and compares the warnings' line numbers with the tags.
	.text
# (1) An FP instruction that rounds by frm, right after a write to frm/fcsr.
	fsrm	a0
	fadd.s	a1, a2, a3		# WARN: rm defaults to dyn
	fsrm	a0
	nop
	fadd.s	a1, a2, a3		# one instruction in between: fine
	fsrm	a0
	fadd.s	a1, a2, a3, rne		# a static mode doesn't read frm
	csrrwi	a0, 2, 1
	fcvt.w.ah	a1, a2		# WARN: .ah rounds by frm
	fscsr	a0
	vfadd.ah	a1, a2, a3	# WARN: packed ops round by frm
	fssr	a0
	vfcvt.x.h	a1, a2		# WARN
	csrw	3, a0
	fmadd.s	a1, a2, a3, a4		# WARN
	csrs	2, a0
	fmul.ah	a1, a2, a3		# WARN: csrrs with a register writes
	csrr	a0, 3
	fadd.s	a1, a2, a3		# a read only
	csrsi	2, 0
	fadd.s	a1, a2, a3		# csrrsi with 0 only reads
	csrci	2, 1
	fsub.s	a1, a2, a3		# WARN: csrrci with an immediate writes
	fsrm	a0
	fcvt.s.ah	a1, a2		# exact widening
	fsrm	a0
	fcvt.s.h	a1, a2		# exact widening
	fsrm	a0
	fsgnj.s	a1, a2, a3		# no rounding
	fsrm	a0
1:
	fcvt.w.s	a1, a2		# WARN: labels don't reset it
	fsflags	a0
	fadd.s	a1, a2, a3		# fflags isn't frm
	fsrm	a0
	.section .text.other, "ax"
	fadd.s	a1, a2, a3		# another section
	.text
	fdiv.s	a1, a2, a3		# WARN: back in .text, right after the fsrm
# (3) fdiv/fsqrt with a static directed mode.
	fdiv.s	a1, a2, a3, rdn		# WARN
	fdiv.s	a1, a2, a3, rup		# WARN
	fsqrt.s	a1, a2, rmm		# WARN
	fdiv.h	a1, a2, a3, rdn		# WARN
	fdiv.s	a1, a2, a3, rtz		# RTZ is right
	fsqrt.s	a1, a2			# dyn: not static
	fadd.s	a1, a2, a3, rdn		# only the divide/sqrt unit
