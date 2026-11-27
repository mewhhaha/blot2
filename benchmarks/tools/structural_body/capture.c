// Use the compiler's queue layout to capture each checked module before
// teardown. Only this symbol is exported by the diagnostic preload library.
#include "check_queue.c"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

__attribute__((visibility("default"))) int munmap(void *address,
                                                  size_t length) {
  const char *directory = getenv("SQUID_CORE_PACKETS");
  if (directory && length > PERSIST_ARENA_CAPACITY &&
      length < PERSIST_ARENA_CAPACITY + 1024 * 1024) {
    struct persist_queue *queue = address;
    if (queue->map_length == length && queue->count == 293 &&
        queue->finished == queue->count && !queue->failure) {
      for (uint32_t i = 0; i < queue->count; i++) {
        struct persist_packet packet = queue->nodes[i].packets[1];
        if (!packet.ready || packet.length <= 24 ||
            packet.offset > queue->arena_used ||
            packet.length > queue->arena_used - packet.offset)
          abort();
        char path[4096];
        if (snprintf(path, sizeof path, "%s/%u-2.bin", directory, i + 1) >=
            (int)sizeof path)
          abort();
        FILE *file = fopen(path, "wb");
        if (!file ||
            fwrite(persist_arena(queue) + packet.offset, 1, packet.length,
                   file) != packet.length ||
            fclose(file))
          abort();
      }
    }
  }
  int (*unmap)(void *, size_t) = dlsym(RTLD_NEXT, "munmap");
  if (!unmap)
    abort();
  return unmap(address, length);
}
