/* Checklist item 1: proves the ARM cross-toolchain output runs under QEMU. */
#include <stdio.h>
#include <sys/utsname.h>

int main(void)
{
	struct utsname u;

	uname(&u);
	printf("Hello from ARM! machine=%s kernel=%s\n", u.machine, u.release);
	return 0;
}
