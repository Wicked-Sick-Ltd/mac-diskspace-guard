/*
 * Stand-in for the macOS stat(1) calls cloudspace_evict.sh actually makes.
 *
 * Behavior copied from Apple file_cmds stat.c (main):
 * - options string on Apple is "f:FlLnqrst:x" (no -c); any other flag
 *   falls through to usage() and exit(1)
 * - "-f %z" lstats the path and prints st_size (SHOW_st_size)
 * - lstat failure sets errs and returns non-zero, with no size printed
 *
 * This is not a general stat(1). It exists so a Linux test can enter the
 * BSD "stat -f '%z'" branch of cloudspace_evict.sh.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static void usage(void) {
  fprintf(stderr,
          "usage: stat [-FLnq] [-f format | -l | -r | -s | -x] "
          "[-t timefmt] [file ...]\n");
  exit(1);
}

int main(int argc, char **argv) {
  int i = 1;
  const char *fmt = NULL;

  if (argc < 2) {
    usage();
  }

  while (i < argc && argv[i][0] == '-' && argv[i][1] != '\0') {
    if (strcmp(argv[i], "-f") == 0) {
      if (i + 1 >= argc) {
        usage();
      }
      fmt = argv[++i];
      i++;
      continue;
    }
    usage();
  }

  if (fmt == NULL || strcmp(fmt, "%z") != 0 || i >= argc) {
    usage();
  }

  int errs = 0;
  for (; i < argc; i++) {
    struct stat st;
    if (lstat(argv[i], &st) == -1) {
      fprintf(stderr, "stat: %s: stat: %s\n", argv[i], strerror(errno));
      errs = 1;
      continue;
    }
    printf("%llu\n", (unsigned long long)st.st_size);
  }
  return errs;
}
