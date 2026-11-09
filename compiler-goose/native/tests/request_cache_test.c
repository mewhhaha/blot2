#define _GNU_SOURCE
#include "../request_cache.h"
#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static int active = 1;
int32_t blot_request_input_fd(void) { if (active) return 9; return -1; }
static int forbidden;
void *__real_malloc(size_t);
void *__real_calloc(size_t,size_t);
void *__real_realloc(void *,size_t);
void *__wrap_malloc(size_t n) { assert(!forbidden); return __real_malloc(n); }
void *__wrap_calloc(size_t n,size_t s) { assert(!forbidden); return __real_calloc(n,s); }
void *__wrap_realloc(void *p,size_t n) { assert(!forbidden); return __real_realloc(p,n); }
static void publish(void) { active=0; forbidden=1; blot_request_cache_publish(); forbidden=0; active=1; assert(!blot_request_cache_pending()); }
static int fds(void) {
    DIR *d=opendir("/proc/self/fd"); assert(d); int count=0;
    while (readdir(d)) count++;
    closedir(d); return count;
}
static void put(const char *path,const char *bytes) {
    int fd=open(path,O_WRONLY|O_CREAT|O_TRUNC,0600); assert(fd>=0);
    size_t n=strlen(bytes); assert(write(fd,bytes,n)==(ssize_t)n); assert(!close(fd));
}
static void expect(const char *path,const char *expected) {
    char bytes[64]={0}; int fd=open(path,O_RDONLY); assert(fd>=0);
    ssize_t n=read(fd,bytes,sizeof bytes); assert(n==(ssize_t)strlen(expected));
    assert(!memcmp(bytes,expected,(size_t)n)); close(fd);
}
struct paths { char directory[PATH_MAX],lock[PATH_MAX],target[3][PATH_MAX],temporary[3][PATH_MAX]; };
static void paths(struct paths *p,const char *directory) {
    assert(snprintf(p->directory,sizeof p->directory,"%s",directory)>0);
    assert(snprintf(p->lock,sizeof p->lock,"%s/key.lock",directory)>0);
    for (int i=0;i<3;i++) {
        assert(snprintf(p->target[i],PATH_MAX,"%s/key.%d",directory,i)>0);
        assert(snprintf(p->temporary[i],PATH_MAX,"%s/key.%d.partial",directory,i)>0);
    }
}
static int stage(struct paths *p,unsigned part,const char *bytes) {
    return blot_request_cache_stage_write(part,(uint8_t *)p->directory,strlen(p->directory),
        (uint8_t *)p->lock,strlen(p->lock),(uint8_t *)p->target[part],strlen(p->target[part]),
        (uint8_t *)p->temporary[part],strlen(p->temporary[part]),(uint8_t *)bytes,strlen(bytes));
}
static int remove_part(struct paths *p,unsigned part) {
    return blot_request_cache_stage_remove(part,(uint8_t *)p->directory,strlen(p->directory),
        (uint8_t *)p->lock,strlen(p->lock),(uint8_t *)p->target[part],strlen(p->target[part]));
}
static void cleanup(struct paths *p) {
    unlink(p->lock);
    for (int i=0;i<3;i++) {unlink(p->target[i]);unlink(p->temporary[i]);}
}
int main(void) {
    char directory[]="/tmp/blot-request-cache-XXXXXX"; assert(mkdtemp(directory));
    struct paths p;paths(&p,directory);
    int baseline=fds();
    put(p.target[0],"old");put(p.target[1],"old-output");
    pid_t child=fork();assert(child>=0);
    if (!child) {assert(!stage(&p,0,"discarded"));assert(!remove_part(&p,1));_exit(0);}
    int status;assert(waitpid(child,&status,0)==child && WIFEXITED(status) && !WEXITSTATUS(status));
    assert(!blot_request_cache_pending());expect(p.target[0],"old");expect(p.target[1],"old-output");
    assert(access(p.lock,F_OK)<0 && access(p.temporary[0],F_OK)<0 && fds()==baseline);
    char bytes[]="checkpoint";assert(!stage(&p,0,bytes));bytes[0]='X';
    assert(!stage(&p,1,"output"));assert(!stage(&p,2,"seed"));
    assert(blot_request_cache_pending()==3 && fds()==baseline+3);
    expect(p.target[0],"old");expect(p.target[1],"old-output");
    assert(access(p.lock,F_OK)<0 && access(p.target[2],F_OK)<0);
    /* Paths are owned too; changing the caller's storage cannot redirect a write. */
    struct paths staged=p;p.target[0][0]='X';
    publish();p=staged;
    expect(p.target[0],"checkpoint");expect(p.target[1],"output");expect(p.target[2],"seed");
    assert(fds()==baseline);
    assert(!stage(&p,0,"new"));assert(!remove_part(&p,1));
    blot_request_cache_discard();expect(p.target[0],"checkpoint");expect(p.target[1],"output");
    assert(!blot_request_cache_pending() && fds()==baseline);
    /* Replacement closes the old memfd; adopted close drains writes and removals. */
    assert(!stage(&p,0,"intermediate"));assert(!stage(&p,0,"close"));assert(!remove_part(&p,1));
    assert(blot_request_cache_pending()==2 && fds()==baseline+1);
    int pipefd[2];assert(!pipe(pipefd));
    child=fork();assert(child>=0);
    if (!child) {
        close(pipefd[0]);int lock=open(p.lock,O_RDWR);assert(lock>=0 && !flock(lock,LOCK_EX));
        assert(write(pipefd[1],"x",1)==1);close(pipefd[1]);
        struct timespec pause={.tv_nsec=30000000};nanosleep(&pause,NULL);close(lock);_exit(0);
    }
    close(pipefd[1]);char ready;assert(read(pipefd[0],&ready,1)==1);close(pipefd[0]);
    publish();assert(waitpid(child,&status,0)==child && WIFEXITED(status) && !WEXITSTATUS(status));
    expect(p.target[0],"close");assert(access(p.target[1],F_OK)<0 && fds()==baseline);
    /* No directory/lock mutation until adopted. */
    char nested[PATH_MAX];assert(snprintf(nested,sizeof nested,"%s/nested/deeper",directory)>0);
    struct paths n;paths(&n,nested);assert(!stage(&n,0,"nested"));assert(access(nested,F_OK)<0);
    publish();expect(n.target[0],"nested");cleanup(&n);assert(!rmdir(nested));
    assert(snprintf(nested,sizeof nested,"%s/nested",directory)>0);assert(!rmdir(nested));
    /* Optional publication failure drains every memfd and permits a later retry. */
    char blocked[PATH_MAX];assert(snprintf(blocked,sizeof blocked,"%s/blocked",directory)>0);put(blocked,"file");
    struct paths b;paths(&b,blocked);assert(!stage(&b,0,"optional"));publish();assert(fds()==baseline);
    assert(!unlink(blocked));assert(!stage(&b,0,"retry"));publish();expect(b.target[0],"retry");cleanup(&b);assert(!rmdir(blocked));
    /* Reject OS-long components/paths and embedded NUL; never truncate a path. */
    char long_path[PATH_MAX+1];memset(long_path,'a',sizeof long_path);long_path[0]='/';
    assert(blot_request_cache_stage_remove(0,(uint8_t *)long_path,PATH_MAX,(uint8_t *)p.lock,strlen(p.lock),(uint8_t *)p.target[0],strlen(p.target[0]))<0);
    long_path[NAME_MAX+2]=0;
    assert(blot_request_cache_stage_remove(0,(uint8_t *)long_path,NAME_MAX+2,(uint8_t *)p.lock,strlen(p.lock),(uint8_t *)p.target[0],strlen(p.target[0]))<0);
    assert(blot_request_cache_stage_remove(0,(uint8_t *)p.directory,strlen(p.directory)+1,(uint8_t *)p.lock,strlen(p.lock),(uint8_t *)p.target[0],strlen(p.target[0]))<0);
    active=0;assert(stage(&p,0,"inactive")<0);active=1;
    assert(!blot_request_cache_pending() && fds()==baseline);
    cleanup(&p);assert(!rmdir(directory));
    puts("request cache staging/discard/publish/retry/close: passed");
    return 0;
}
