/* A stand-in release executable: reports "server <VERSION>" for --version. */
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
  if (argc == 2 && strcmp(argv[1], "--version") == 0) {
    printf("server %s\n", VERSION);
    return 0;
  }
  return 64;
}
