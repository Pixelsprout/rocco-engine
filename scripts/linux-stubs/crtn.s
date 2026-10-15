# The epilogues of _init and _fini, which crti.s opens.
.section .init,"ax",@progbits
	add $8, %rsp
	ret

.section .fini,"ax",@progbits
	add $8, %rsp
	ret

.section .note.GNU-stack,"",@progbits
