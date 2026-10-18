/* Native CLI I/O boundary. Serialization and generation are implemented in MoonBit. */
#include <stdio.h>
#include <stdlib.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

int capnp_mbt_stdin_read(unsigned char *data, int size) {
#ifdef _WIN32
  if (_setmode(_fileno(stdin), _O_BINARY) == -1) return -1;
#endif
  size_t n = fread(data, 1, (size_t)size, stdin);
  return ferror(stdin) ? -1 : (int)n;
}

int capnp_mbt_stdout_write(const unsigned char *data, int size) {
#ifdef _WIN32
  if (_setmode(_fileno(stdout), _O_BINARY) == -1) return -1;
#endif
  size_t n = fwrite(data, 1, (size_t)size, stdout);
  if (fflush(stdout) != 0) return -1;
  return (int)n;
}

void capnp_mbt_exit(int code) { exit(code); }
