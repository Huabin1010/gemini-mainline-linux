// Minimal aarch64 initramfs /init for gemini (UFS userdata).
// Pattern from Kernel-Build/initramfs/init.c; paths from the 2026-08-27 dump.
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>

/* Kept open so TIOCCONS keeps sending printk to the USB ACM gadget. */
static int gs0_fd = -1;

static const char *userdata_paths[] = {
	"/dev/disk/by-partlabel/userdata",
	"/dev/disk/by-label/rootfs",
	"/dev/block/bootdevice/by-name/userdata",
	"/dev/block/by-name/userdata",
	"/dev/sda15",
	NULL,
};

static void mkpath(const char *path)
{
	if (mkdir(path, 0755) && errno != EEXIST) {
		dprintf(STDERR_FILENO, "initramfs: mkdir %s failed\n", path);
		for (;;)
			sleep(3600);
	}
}

/* umeko 6.1 uses built-in g_serial for 0525:a4a7. Do not bind configfs
 * ACM — that steals the UDC and ttyGS0 never carries data. */
static void setup_usb_acm(void)
{
}

static void gs_write(const char *s)
{
	if (gs0_fd < 0 || !s)
		return;
	write(gs0_fd, s, strlen(s));
}

static void attach_usb_console(void)
{
	pid_t pid = fork();

	if (pid != 0)
		return;

	/* Child: blocking open/write so logs wait until the host opens ACM. */
	for (;;) {
		gs0_fd = open("/dev/ttyGS0", O_RDWR | O_NOCTTY);
		if (gs0_fd >= 0)
			break;
		usleep(100000);
	}
	gs_write("\r\ninitramfs: USB console on ttyGS0\r\n");

	{
		int kfd = open("/dev/kmsg", O_RDONLY);
		char buf[512];
		int n, tick = 0;

		for (;;) {
			if (kfd >= 0) {
				n = read(kfd, buf, sizeof(buf));
				if (n > 0)
					write(gs0_fd, buf, n);
			}
			if (tick++ % 20 == 0) {
				int fb = !access("/dev/fb0", F_OK);
				int dri = !access("/dev/dri/card0", F_OK);
				dprintf(gs0_fd,
					"initramfs: alive fb0=%d dri=%d\r\n",
					fb, dri);
			}
			usleep(250000);
		}
	}
}

static void release_stdio_for_systemd(void)
{
	/* Do not steal ttyGS0 from serial-getty; kmsg child keeps the fd. */
}

static void die(const char *msg)
{
	dprintf(STDERR_FILENO, "initramfs: %s\n", msg);
	setup_usb_acm();
	attach_usb_console();
	dprintf(STDERR_FILENO, "initramfs: %s (halted, USB console up)\n", msg);
	for (;;)
		sleep(3600);
}

static int is_block_name(const char *name)
{
	return !strncmp(name, "mmcblk", 6) ||
	       !strncmp(name, "sd", 2) ||
	       !strncmp(name, "ufshcd", 6);
}

static void trigger_block_uevents(void)
{
	DIR *dir = opendir("/sys/class/block");
	struct dirent *ent;

	if (!dir)
		return;

	while ((ent = readdir(dir))) {
		char path[256];
		int fd;

		if (!is_block_name(ent->d_name))
			continue;

		snprintf(path, sizeof(path), "/sys/class/block/%s/uevent",
			 ent->d_name);
		fd = open(path, O_WRONLY);
		if (fd < 0)
			continue;
		write(fd, "add\n", 4);
		close(fd);
	}
	closedir(dir);
	usleep(200000);
}

static const char *find_by_partname(void)
{
	static char dev[128];
	DIR *dir;
	struct dirent *ent;
	char path[256], buf[512];
	int fd, n;

	dir = opendir("/sys/class/block");
	if (!dir)
		return NULL;
	while ((ent = readdir(dir))) {
		if (!is_block_name(ent->d_name))
			continue;
		snprintf(path, sizeof(path), "/sys/class/block/%s/uevent",
			 ent->d_name);
		fd = open(path, O_RDONLY);
		if (fd < 0)
			continue;
		n = read(fd, buf, sizeof(buf) - 1);
		close(fd);
		if (n <= 0)
			continue;
		buf[n] = '\0';
		if (!strstr(buf, "PARTNAME=userdata") &&
		    !strstr(buf, "PARTNAME=rootfs"))
			continue;
		snprintf(dev, sizeof(dev), "/dev/%s", ent->d_name);
		closedir(dir);
		return dev;
	}
	closedir(dir);
	return NULL;
}

static const char *find_userdata(void)
{
	const char *p;

	for (int i = 0; i < 240; i++) {
		if (i == 0 || i % 20 == 0)
			dprintf(STDERR_FILENO, "initramfs: waiting for disk (%ds)\n",
				i / 4);
		trigger_block_uevents();
		for (int j = 0; userdata_paths[j]; j++) {
			if (!access(userdata_paths[j], F_OK)) {
				dprintf(STDERR_FILENO, "initramfs: root %s\n",
					userdata_paths[j]);
				return userdata_paths[j];
			}
		}
		p = find_by_partname();
		if (p) {
			dprintf(STDERR_FILENO, "initramfs: root %s (partname)\n",
				p);
			return p;
		}
		usleep(250000);
	}
	return NULL;
}

static void copy_file(const char *src, const char *dst, mode_t mode)
{
	char buf[4096];
	ssize_t n;
	int in, out;

	in = open(src, O_RDONLY);
	if (in < 0)
		return;
	out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, mode);
	if (out < 0) {
		close(in);
		return;
	}
	while ((n = read(in, buf, sizeof(buf))) > 0)
		write(out, buf, n);
	fchown(out, 0, 0);
	close(in);
	close(out);
}

static void mkdir_p(const char *path)
{
	char tmp[512];
	char *p;

	snprintf(tmp, sizeof(tmp), "%s", path);
	for (p = tmp + 1; *p; p++) {
		if (*p != '/')
			continue;
		*p = '\0';
		mkdir(tmp, 0755);
		*p = '/';
	}
	mkdir(tmp, 0755);
}

static void deploy_entry(const char *src, const char *dst);

static void deploy_dir(const char *src, const char *dst)
{
	DIR *dir = opendir(src);
	struct dirent *ent;
	char srcpath[512], dstpath[512];

	if (!dir)
		return;
	while ((ent = readdir(dir))) {
		if (!strcmp(ent->d_name, ".") || !strcmp(ent->d_name, ".."))
			continue;
		snprintf(srcpath, sizeof(srcpath), "%s/%s", src, ent->d_name);
		snprintf(dstpath, sizeof(dstpath), "%s/%s", dst, ent->d_name);
		deploy_entry(srcpath, dstpath);
	}
	closedir(dir);
}

static void deploy_entry(const char *src, const char *dst)
{
	struct stat st;
	char link[512];
	ssize_t len;
	const char *slash;

	if (lstat(src, &st))
		return;

	if (S_ISDIR(st.st_mode)) {
		mkdir(dst, st.st_mode & 07777);
		chown(dst, 0, 0);
		deploy_dir(src, dst);
		return;
	}

	slash = strrchr(dst, '/');
	if (slash) {
		char parent[512];

		snprintf(parent, sizeof(parent), "%.*s", (int)(slash - dst), dst);
		mkdir_p(parent);
	}

	/* Overlay updates must replace whatever is already on userdata.
	 * symlink() fails with EEXIST, so the autottyGS0 → /dev/null mask
	 * never landed and two gettys kept eating ACM input. */
	unlink(dst);

	if (S_ISLNK(st.st_mode)) {
		len = readlink(src, link, sizeof(link) - 1);
		if (len < 0)
			return;
		link[len] = '\0';
		symlink(link, dst);
		return;
	}

	if (S_ISREG(st.st_mode))
		copy_file(src, dst, st.st_mode & 07777);
}

static void force_symlink(const char *target, const char *dst)
{
	unlink(dst);
	symlink(target, dst);
}

static void prune_duplicate_gs0_getty(void)
{
	/* Stale wants/ from older ram-boots are not deleted by deploy_dir. */
	unlink("/newroot/etc/systemd/system/multi-user.target.wants/autottyGS0.service");
	unlink("/newroot/etc/systemd/system/multi-user.target.wants/gemini-fb-ui.service");
	mkdir_p("/newroot/etc/systemd/system/getty.target.wants");
	force_symlink("/dev/null",
		      "/newroot/etc/systemd/system/autottyGS0.service");
	force_symlink("/lib/systemd/system/serial-getty@.service",
		      "/newroot/etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service");
}

static void deploy_overlay(void)
{
	if (access("/overlay", F_OK))
		return;
	deploy_dir("/overlay", "/newroot");
	prune_duplicate_gs0_getty();
	gs_write("initramfs: overlay installed on userdata\r\n");
}

int main(void)
{
	const char *rootdev;

	mkpath("/proc");
	mkpath("/sys");
	mkpath("/dev");
	if (mount("proc", "/proc", "proc", 0, NULL))
		die("mount proc failed");
	if (mount("sysfs", "/sys", "sysfs", 0, NULL))
		die("mount sysfs failed");
	if (mount("devtmpfs", "/dev", "devtmpfs", 0, NULL))
		die("mount devtmpfs failed");

	setup_usb_acm();
	attach_usb_console();
	dprintf(STDERR_FILENO, "initramfs: looking for userdata\n");

	rootdev = find_userdata();
	if (!rootdev)
		die("userdata partition not found");

	mkpath("/newroot");
	if (mount(rootdev, "/newroot", "ext4", 0, NULL))
		die("mount userdata failed");

	deploy_overlay();

	mkpath("/newroot/proc");
	mkpath("/newroot/sys");
	mkpath("/newroot/dev");

	if (mount("/proc", "/newroot/proc", NULL, MS_MOVE, NULL))
		die("move proc failed");
	if (mount("/sys", "/newroot/sys", NULL, MS_MOVE, NULL))
		die("move sys failed");
	if (mount("/dev", "/newroot/dev", NULL, MS_MOVE, NULL))
		die("move dev failed");

	if (chdir("/newroot"))
		die("chdir /newroot failed");
	if (mount(".", "/", NULL, MS_MOVE, NULL))
		die("move root failed");
	if (chroot("."))
		die("chroot failed");

	dprintf(STDERR_FILENO, "initramfs: exec /sbin/init\n");
	release_stdio_for_systemd();
	execl("/sbin/init", "init", NULL);
	die("exec /sbin/init failed");
}
