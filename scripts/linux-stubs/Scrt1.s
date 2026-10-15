# The PIE entry point. The kernel enters _start with argc at (%rsp), argv
# after it, and the dynamic linker's fini function in %rdx. glibc's
# __libc_start_main runs the constructors from the dynamic section when init
# is null, as glibc 2.34 and later do.
.text
.globl _start
.type _start, @function
_start:
	xor %ebp, %ebp
	mov %rdx, %r9
	pop %rsi
	mov %rsp, %rdx
	and $-16, %rsp
	push %rax
	push %rsp
	xor %r8d, %r8d
	xor %ecx, %ecx
	mov main@GOTPCREL(%rip), %rdi
	call *__libc_start_main@GOTPCREL(%rip)
	hlt
.size _start, . - _start

.section .note.GNU-stack,"",@progbits
