/*
 * chardev_test.c - user-space self-test for /dev/mychardev (Phase 1).
 * Exit status = number of failed checks.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>

#include "../include/mychardev_ioctl.h"

#define DEV "/dev/mychardev"

static int failures;

#define CHECK(cond, name) do {                                   \
	if (cond) printf("[ PASS ] %s\n", name);                 \
	else { printf("[ FAIL ] %s (errno=%d)\n", name, errno);  \
	       failures++; }                                     \
} while (0)

int main(void)
{
	char buf[128], big[8192];
	int fd, cap = 0, len = -1;
	ssize_t n;

	fd = open(DEV, O_RDWR);
	CHECK(fd >= 0, "open " DEV);
	if (fd < 0)
		return 1;

	CHECK(ioctl(fd, MYCHAR_IOC_GET_CAP, &cap) == 0 && cap > 0, "ioctl GET_CAP");
	printf("       capacity = %d bytes\n", cap);

	n = write(fd, "hello", 5);
	CHECK(n == 5, "write 5 bytes");
	lseek(fd, 0, SEEK_SET);
	memset(buf, 0, sizeof(buf));
	n = read(fd, buf, sizeof(buf));
	CHECK(n == 5 && memcmp(buf, "hello", 5) == 0, "read back \"hello\"");

	ioctl(fd, MYCHAR_IOC_GET_LEN, &len);
	CHECK(len == 5, "ioctl GET_LEN == 5");

	/* read at EOF returns 0 */
	CHECK(read(fd, buf, sizeof(buf)) == 0, "read at EOF returns 0");

	lseek(fd, 0, SEEK_SET);
	write(fd, "hi", 2);
	ioctl(fd, MYCHAR_IOC_GET_LEN, &len);
	CHECK(len == 2, "rewrite at offset 0 shrinks length to 2");

	ioctl(fd, MYCHAR_IOC_RESET);
	memset(big, 'A', sizeof(big));
	lseek(fd, 0, SEEK_SET);
	n = write(fd, big, cap + 100);
	CHECK(n == cap, "oversized write is truncated to capacity");
	errno = 0;
	n = write(fd, "x", 1);
	CHECK(n < 0 && errno == ENOSPC, "write at end of buffer -> ENOSPC");

	/* bad user pointer must fail cleanly, not crash the kernel */
	lseek(fd, 0, SEEK_SET);
	errno = 0;
	n = write(fd, (void *)1, 16);
	CHECK(n < 0 && errno == EFAULT, "bad user pointer -> EFAULT (no oops)");

	ioctl(fd, MYCHAR_IOC_RESET);
	ioctl(fd, MYCHAR_IOC_GET_LEN, &len);
	CHECK(len == 0, "ioctl RESET empties buffer");

	errno = 0;
	CHECK(ioctl(fd, _IO(MYCHAR_IOC_MAGIC, 99)) < 0 && errno == ENOTTY,
	      "unknown ioctl -> ENOTTY");

	close(fd);
	printf("== %s (%d failure%s) ==\n", failures ? "FAILED" : "ALL PASSED",
	       failures, failures == 1 ? "" : "s");
	return failures;
}
