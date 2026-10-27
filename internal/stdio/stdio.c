/* Native CLI I/O boundary. Serialization and generation are implemented in MoonBit. */
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#else
#include <unistd.h>
#endif

int capnp_mbt_stdin_read(unsigned char *data, int size) {
  if (size < 0) return -1;
#ifdef _WIN32
  if (_setmode(_fileno(stdin), _O_BINARY) == -1) return -1;
  int count;
  do {
    count = _read(_fileno(stdin), data, (unsigned int)size);
  } while (count < 0 && errno == EINTR);
#else
  ssize_t count;
  do {
    count = read(STDIN_FILENO, data, (size_t)size);
  } while (count < 0 && errno == EINTR);
#endif
  /* A short read is useful data, not EOF: do not wait to fill a caller's chunk. */
  return count < 0 ? -1 : (int)count;
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
