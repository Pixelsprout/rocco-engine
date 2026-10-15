# The prologues of _init and _fini. crtn.s closes both. The sub keeps the
# stack 16-byte aligned for code that the linker places between them.
.section .init,"ax",@progbits
.globl _init
.type _init, @function
_init:
	sub $8, %rsp

.section .fini,"ax",@progbits
.globl _fini
.type _fini, @function
_fini:
	sub $8, %rsp

.section .note.GNU-stack,"",@progbits
