/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Unblank + Volume-Up reboot-fastboot. Do not paint the panel: fbcon owns
 * scanout (kernel log / Tux). Short Volume Up (no power) = reboot-fastboot.
 * Hardware VolDown+Power is LK, not this path.
 */
#include <dirent.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <linux/reboot.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

static void logmsg(const char *msg)
{
	FILE *f = fopen("/var/log/gemini-display.log", "a");
	int k = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
	time_t t = time(NULL);
	char ts[32];
	char line[256];

	strftime(ts, sizeof(ts), "%Y-%m-%dT%H:%M:%S", localtime(&t));
	snprintf(line, sizeof(line), "gemini-fb-ui: %s\n", msg);
	if (f) {
		fprintf(f, "%s %s", ts, line);
		fclose(f);
	}
	if (k >= 0) {
		write(k, line, strlen(line));
		close(k);
	}
}

static void msleep(int ms)
{
	struct timespec ts = { .tv_sec = ms / 1000, .tv_nsec = (ms % 1000) * 1000000L };

	nanosleep(&ts, NULL);
}

static int wait_paths(void)
{
	int i;

	for (i = 0; i < 150; i++) {
		if (!access("/dev/dri/card0", F_OK) && !access("/dev/fb0", F_OK))
			return 0;
		msleep(200);
	}
	return -1;
}

static void unblank_fb(void)
{
	int fd = open("/dev/fb0", O_RDWR);

	if (fd < 0)
		return;
	ioctl(fd, FBIOBLANK, FB_BLANK_UNBLANK);
	close(fd);
}

static unsigned opened_ev;

static void do_reboot_fastboot(const char *why)
{
	logmsg(why);
	sync();
	if (syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
		    LINUX_REBOOT_CMD_RESTART2, "bootloader") < 0)
		logmsg("SYS_reboot bootloader failed");
	execl("/usr/local/sbin/reboot-fastboot", "reboot-fastboot", (char *)NULL);
	_exit(1);
}

static int open_event(const char *path)
{
	int fd = open(path, O_RDONLY | O_NONBLOCK);
	int one = 1;

	if (fd < 0)
		return -1;
	ioctl(fd, EVIOCGRAB, &one);
	return fd;
}

static int add_input(struct pollfd *pfds, int *n, int cap)
{
	DIR *d = opendir("/dev/input");
	struct dirent *ent;

	if (!d)
		return *n;
	while ((ent = readdir(d)) && *n < cap) {
		char path[64];
		int fd, num;

		if (strncmp(ent->d_name, "event", 5))
			continue;
		num = atoi(ent->d_name + 5);
		if (num >= 0 && num < 32 && (opened_ev & (1u << num)))
			continue;
		snprintf(path, sizeof(path), "/dev/input/%s", ent->d_name);
		fd = open_event(path);
		if (fd < 0)
			continue;
		if (num >= 0 && num < 32)
			opened_ev |= 1u << num;
		pfds[*n].fd = fd;
		pfds[*n].events = POLLIN;
		(*n)++;
		logmsg(path);
	}
	closedir(d);
	return *n;
}

static void handle_key(uint16_t type, uint16_t code, int32_t value)
{
	char msg[80];

	if (type == EV_KEY && value == 1) {
		snprintf(msg, sizeof(msg), "EV_KEY code=%u", (unsigned)code);
		logmsg(msg);
		if (code == KEY_VOLUMEUP)
			do_reboot_fastboot(msg);
	}
}

static void listen_keys(void)
{
	struct pollfd pfds[32];
	int n = 0;
	int i;

	add_input(pfds, &n, 32);
	logmsg("listening for Volume Up");
	for (;;) {
		if (poll(pfds, n, 2000) <= 0) {
			add_input(pfds, &n, 32);
			unblank_fb();
			continue;
		}
		for (i = 0; i < n; i++) {
			unsigned char buf[256];
			ssize_t got;

			if (!(pfds[i].revents & POLLIN))
				continue;
			got = read(pfds[i].fd, buf, sizeof(buf));
			if (got < 24)
				continue;
			/* 24-byte kernel events; also try 32-byte. */
			if (got % 24 == 0) {
				ssize_t off;
				for (off = 0; off + 24 <= got; off += 24) {
					uint16_t type, code;
					int32_t value;
					memcpy(&type, buf + off + 16, 2);
					memcpy(&code, buf + off + 18, 2);
					memcpy(&value, buf + off + 20, 4);
					handle_key(type, code, value);
				}
			} else if (got % 32 == 0) {
				ssize_t off;
				for (off = 0; off + 32 <= got; off += 32) {
					uint16_t type, code;
					int32_t value;
					memcpy(&type, buf + off + 16, 2);
					memcpy(&code, buf + off + 18, 2);
					memcpy(&value, buf + off + 24, 4);
					handle_key(type, code, value);
				}
			}
		}
	}
}

int main(void)
{
	if (wait_paths())
		logmsg("timeout waiting for card0/fb0");
	unblank_fb();
	listen_keys();
	return 0;
}
