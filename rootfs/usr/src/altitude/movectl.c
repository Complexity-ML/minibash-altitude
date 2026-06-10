#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static void die(const char *msg) {
  fprintf(stderr, "movectl: %s: %s\n", msg, strerror(errno));
  exit(1);
}

static int emit_event(int fd, unsigned short type, unsigned short code, int value) {
  struct input_event ev;
  memset(&ev, 0, sizeof(ev));
  ev.type = type;
  ev.code = code;
  ev.value = value;
  return write(fd, &ev, sizeof(ev)) == (ssize_t)sizeof(ev) ? 0 : -1;
}

static void syn(int fd) {
  if (emit_event(fd, EV_SYN, SYN_REPORT, 0) < 0)
    die("emit SYN_REPORT");
}

static int setup_uinput(void) {
  int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
  if (fd < 0)
    die("open /dev/uinput");

  if (ioctl(fd, UI_SET_EVBIT, EV_KEY) < 0)
    die("UI_SET_EVBIT EV_KEY");
  if (ioctl(fd, UI_SET_KEYBIT, BTN_LEFT) < 0)
    die("UI_SET_KEYBIT BTN_LEFT");
  if (ioctl(fd, UI_SET_EVBIT, EV_REL) < 0)
    die("UI_SET_EVBIT EV_REL");
  if (ioctl(fd, UI_SET_RELBIT, REL_X) < 0)
    die("UI_SET_RELBIT REL_X");
  if (ioctl(fd, UI_SET_RELBIT, REL_Y) < 0)
    die("UI_SET_RELBIT REL_Y");

  struct uinput_setup usetup;
  memset(&usetup, 0, sizeof(usetup));
  usetup.id.bustype = BUS_USB;
  usetup.id.vendor = 0x1d6b;
  usetup.id.product = 0x0104;
  usetup.id.version = 1;
  snprintf(usetup.name, UINPUT_MAX_NAME_SIZE, "Altitude movectl pointer");

  if (ioctl(fd, UI_DEV_SETUP, &usetup) < 0)
    die("UI_DEV_SETUP");
  if (ioctl(fd, UI_DEV_CREATE) < 0)
    die("UI_DEV_CREATE");

  usleep(250000);
  return fd;
}

static void destroy_uinput(int fd) {
  ioctl(fd, UI_DEV_DESTROY);
  close(fd);
}

static void usage(void) {
  fprintf(stderr,
          "usage:\n"
          "  movectl move DX DY [STEPS]\n"
          "  movectl click [left]\n"
          "  movectl nudge\n");
  exit(64);
}

static int to_int(const char *s) {
  char *end = NULL;
  long v = strtol(s, &end, 10);
  if (!s[0] || (end && *end) || v < -100000 || v > 100000)
    usage();
  return (int)v;
}

int main(int argc, char **argv) {
  if (argc < 2)
    usage();

  int fd = setup_uinput();

  if (strcmp(argv[1], "move") == 0) {
    if (argc < 4 || argc > 5)
      usage();
    int dx = to_int(argv[2]);
    int dy = to_int(argv[3]);
    int steps = argc == 5 ? to_int(argv[4]) : 1;
    if (steps < 1)
      steps = 1;
    for (int i = 0; i < steps; i++) {
      if (emit_event(fd, EV_REL, REL_X, dx / steps) < 0)
        die("emit REL_X");
      if (emit_event(fd, EV_REL, REL_Y, dy / steps) < 0)
        die("emit REL_Y");
      syn(fd);
      usleep(25000);
    }
  } else if (strcmp(argv[1], "click") == 0) {
    if (argc > 3)
      usage();
    if (argc == 3 && strcmp(argv[2], "left") != 0)
      usage();
    if (emit_event(fd, EV_KEY, BTN_LEFT, 1) < 0)
      die("emit BTN_LEFT down");
    syn(fd);
    usleep(60000);
    if (emit_event(fd, EV_KEY, BTN_LEFT, 0) < 0)
      die("emit BTN_LEFT up");
    syn(fd);
  } else if (strcmp(argv[1], "nudge") == 0) {
    for (int i = 0; i < 8; i++) {
      if (emit_event(fd, EV_REL, REL_X, 35) < 0)
        die("emit REL_X");
      syn(fd);
      usleep(30000);
    }
  } else {
    usage();
  }

  destroy_uinput(fd);
  return 0;
}
