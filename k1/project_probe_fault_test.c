#define _GNU_SOURCE
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/openat2.h>
#include <stdarg.h>
#include <stdint.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>
typedef struct { const uint8_t *data; int64_t len; } project_bytes;
int64_t k1_project_probe(int64_t root, project_bytes path);
static int failure;
long __wrap_syscall(long number, ...) {
    assert(number == SYS_openat2); errno=failure; return -1;
}
int main(int argc,char **argv) {
    assert(argc==2);int root=open(argv[1],O_RDONLY|O_DIRECTORY|O_CLOEXEC);assert(root>=0);
    project_bytes path={(const uint8_t*)"missing.blot",12};
    failure=ENOENT;assert(k1_project_probe(root,path)==0);
    failure=EACCES;assert(k1_project_probe(root,path)==2);
    failure=EXDEV;assert(k1_project_probe(root,path)==2);
    failure=EAGAIN;assert(k1_project_probe(root,path)==2);
    failure=ELOOP;assert(k1_project_probe(root,path)==2);
    failure=ENOSYS;assert(k1_project_probe(root,path)==4);
    failure=EINVAL;assert(k1_project_probe(root,path)==4);
    assert(close(root)==0);
}
