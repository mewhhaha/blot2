/* Built with __linux__ undefined to exercise the compile-time unsupported path. */
#include "goose.h"
#include <assert.h>
#include <stdint.h>
#include <string.h>
typedef struct { const uint8_t *data; int64_t len; } k1_resolver_bytes;
int64_t k1_source_root_open(k1_resolver_bytes path);
int64_t k1_source_root_close(int64_t root);
int64_t k1_source_read_under(int64_t root, k1_resolver_bytes path, gs_rref out);
int main(void) {
    uint8_t storage[16] = "sentinel";
    gs_rhdr header = { storage, 8 }; gs_stack stack = { storage + 8 }; gs_rref out = { &header, &stack };
    const k1_resolver_bytes path = { (const uint8_t *)"source.blot", 11 };
    assert(k1_source_root_open(path) == -2);
    assert(k1_source_read_under(0, path, out) == 4);
    assert(k1_source_root_close(0) != 0);
    assert(header.len == 8 && stack.top == storage + 8 && memcmp(storage, "sentinel", 8) == 0);
}
