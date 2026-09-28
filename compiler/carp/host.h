#ifndef BLOT_CARP_HOST_H
#define BLOT_CARP_HOST_H
/* OS and representation boundary only. Language semantics live in Carp. */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#include <float.h>
_Static_assert(sizeof(long) == 8, "Carp compiler requires a 64-bit Long");
_Static_assert(sizeof(float) == 4 && FLT_RADIX == 2, "Blot F32 requires binary32");

static inline void blot_error(String *message, int offset) {
  fprintf(stderr, "blot-carp:offset:%d: %s\n", offset, *message);
}
static inline int blot_byte_at(String *s, int index) {
  return (unsigned char)(*s)[index];
}
static inline int blot_byte_length(String *s) { return (int)strlen(*s); }
static inline String blot_slice(String *s, int start, int end) {
  size_t n = (size_t)(end - start);
  char *r = CARP_MALLOC(n + 1);
  if (!r) { fputs("blot-carp: out of memory\n", stderr); exit(1); }
  memcpy(r, *s + start, n); r[n] = 0; return r;
}
static inline String blot_read(String *path) {
  FILE *f = fopen(*path, "rb");
  if (!f) { fprintf(stderr, "blot-carp: %s: %s\n", *path, strerror(errno)); exit(1); }
  const size_t limit = 16 * 1024 * 1024;
  size_t size = 0, cap = 4096;
  char *s = CARP_MALLOC(cap + 1);
  if (!s) { fclose(f); exit(1); }
  for (;;) {
    size_t n = fread(s + size, 1, cap - size, f); size += n;
    if (n == 0) {
      if (ferror(f)) { fputs("blot-carp: read failed\n", stderr); exit(1); }
      break;
    }
    if (size == cap) {
      if (cap == limit) {
        if (fgetc(f) == EOF && !ferror(f)) break;
        fputs("blot-carp: source limit (16 MiB)\n", stderr);
        CARP_FREE(s); fclose(f); exit(1);
      }
      cap *= 2;
      char *next = CARP_REALLOC(s, cap + 1);
      if (!next) { CARP_FREE(s); fclose(f); exit(1); }
      s = next;
    }
  }
  fclose(f);
  if (memchr(s, 0, size)) { fputs("blot-carp: NUL in source\n", stderr); CARP_FREE(s); exit(1); }
  s[size] = 0; return s;
}
static inline void blot_write(String *path, Array *bytes) {
  /* Publish with a same-directory rename only after the entire write succeeds. */
  size_t n = strlen(*path);
  char *temporary = CARP_MALLOC(n + 12);
  if (!temporary) exit(1);
  memcpy(temporary, *path, n); memcpy(temporary + n, ".tmp.XXXXXX", 12);
  int fd = mkstemp(temporary);
  if (fd < 0) { fprintf(stderr, "blot-carp: %s: %s\n", *path, strerror(errno)); CARP_FREE(temporary); exit(1); }
  FILE *f = fdopen(fd, "wb");
  if (!f) { close(fd); remove(temporary); CARP_FREE(temporary); exit(1); }
  int *data = (int *)bytes->data;
  int failed = 0;
  for (int i = 0; i < bytes->len; i++) {
    if (fputc(data[i], f) == EOF) { failed = 1; break; }
  }
  if (fclose(f)) failed = 1;
  if (!failed && rename(temporary, *path)) failed = 1;
  if (failed) { remove(temporary); fputs("blot-carp: output write failed\n", stderr); }
  CARP_FREE(temporary);
  if (failed) exit(1);
}

static inline float blot_float(String *s) {
  char *end; errno = 0;
  float f = strtof(*s, &end);
  if (end == *s || *end) { fputs("blot-carp: invalid F32 literal\n", stderr); exit(1); }
  return f; /* ERANGE deliberately permits IEEE-754 underflow/overflow. */
}
static inline long blot_float_bits(float f) { uint32_t u; memcpy(&u, &f, 4); return (long)u; }
static inline float blot_bits_float(long u) { uint32_t bits = (uint32_t)u; float f; memcpy(&f, &bits, 4); return f; }
static inline long blot_u32(long n) { return (long)(uint32_t)n; }
static inline float blot_long_float(long n) { return (float)n; }
static inline long blot_float_long(float n) { return (long)n; }
#endif
