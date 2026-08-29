#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <linux/reboot.h>

/*
 * LINUX_REBOOT_CMD_RESTART2 "bootloader" so qcom-pon writes mode-bootloader
 * (pm8994 spare 0x2). glibc reboot(3) cannot pass that string.
 * Skip systemd: 7.0 GNOME/DRM teardown can blank the panel and never restart.
 */
int main(void)
{
	sync();
	errno = 0;
	if (syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
		    LINUX_REBOOT_CMD_RESTART2, "bootloader") < 0)
		perror("reboot bootloader");
	return 1;
}
