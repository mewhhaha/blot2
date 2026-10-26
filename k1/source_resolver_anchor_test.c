#include "goose.h"
#include <stdint.h>
#include <stdio.h>
#include <assert.h>
#include <string.h>
#include <stdlib.h>
typedef struct { const uint8_t *data; int64_t len; } bytes;
int64_t k1_source_root_open(bytes path);
int64_t k1_source_root_close(int64_t fd);
int64_t k1_source_read_under(int64_t fd, bytes path, gs_rref out);
static bytes s(const char *p) { return (bytes){(const uint8_t*)p,(int64_t)strlen(p)}; }
int main(int argc,char** argv) {
 assert(argc==4); int64_t fd=k1_source_root_open(s(argv[1])); assert(fd>=0);
 assert(rename(argv[1],argv[2])==0); assert(rename(argv[3],argv[1])==0);
 uint8_t buffer[128]={0}; gs_rhdr hdr={buffer,0}; gs_stack stack={buffer}; gs_rref out={&hdr,&stack};
 assert(k1_source_read_under(fd,s("main.blot"),out)==0);
 assert(hdr.len==9 && memcmp(buffer,"original\n",9)==0);
 assert(k1_source_root_close(fd)==0); puts("renamed root anchor passed");
}
