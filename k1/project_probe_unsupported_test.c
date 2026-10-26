#include <assert.h>
#include <stdint.h>
typedef struct { const uint8_t *data; int64_t len; } project_bytes;
int64_t k1_project_probe(int64_t root, project_bytes path);
int main(void) {
    project_bytes p={(const uint8_t*)"x",1};assert(k1_project_probe(0,p)==4);
}
