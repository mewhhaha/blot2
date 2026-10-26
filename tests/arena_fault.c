/* Linux test adapter for Goose arena reservation and commit failures.
   Optional BLOT_FAULT_COMMIT replaces Linux overcommit with explicit protected
   chunks, mirroring a commit-on-touch platform. Compiler sources are unchanged.
   This is fault infrastructure, never part of the compiler or guest runtime. */
#define _GNU_SOURCE
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/resource.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdatomic.h>
#include <errno.h>
#include <signal.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

static _Atomic unsigned long count;
static unsigned long fail_at;
static int armed, commit_mode;
#define MAX_ARENAS 4096
#define COMMIT_BYTES (64ul << 10)
struct arena { uintptr_t base, end, committed; };
static struct arena arenas[MAX_ARENAS];
static unsigned arena_count;
static struct sigaction forward_segv, forward_bus;
static int (*real_sigaction)(int,const struct sigaction *,struct sigaction *);
static size_t (*real_fread)(void *,size_t,size_t,FILE *);

static int fail_now(const char *record,size_t length) {
    if (!armed) return 0;
    unsigned long index=atomic_fetch_add_explicit(&count,1,memory_order_relaxed)+1;
    syscall(SYS_write,STDERR_FILENO,record,length);
    if (fail_at && index>=fail_at) { errno=ENOMEM;return 1; }
    return 0;
}
static int event(void) {const char record[]="BLOT_ALLOC_EVENT\n";return fail_now(record,sizeof(record)-1);}
static void fatal_commit(void) {
    const char message[]="k1_allocation_failure: test arena commit failed\n";
    syscall(SYS_write,STDERR_FILENO,message,sizeof(message)-1);
    syscall(SYS_exit_group,86);
    __builtin_unreachable();
}
static int commit_to(struct arena *a,uintptr_t end) {
    if(end<=a->committed)return 1;
    if(end>a->end)return 0;
    /* Chunk offsets belong to the reservation. Absolute-address rounding makes
       the first chunk vary with ASLR and moves fault ordinals between runs. */
    uintptr_t offset=end-a->base;
    uintptr_t limit=a->base+((offset+COMMIT_BYTES-1)&~(uintptr_t)(COMMIT_BYTES-1));
    if(limit>a->end)limit=a->end;
    if(event() || syscall(SYS_mprotect,(void *)a->committed,limit-a->committed,PROT_READ|PROT_WRITE))fatal_commit();
    a->committed=limit;return 1;
}
static int commit_range(void *ptr,size_t length) {
    if(!commit_mode || !length)return 1;
    uintptr_t start=(uintptr_t)ptr;
    if(length>UINTPTR_MAX-start)return 0;
    for(unsigned i=0;i<arena_count;i++)if(start>=arenas[i].base && start<arenas[i].end)return commit_to(&arenas[i],start+length);
    return 1;
}
static void fault_handler(int signal,siginfo_t *info,void *context) {
    uintptr_t address=(uintptr_t)info->si_addr;
    for(unsigned i=0;i<arena_count;i++) {
        struct arena *a=&arenas[i];
        if(address>=a->base && address<a->end && address>=a->committed) {if(commit_to(a,address+1))return;}
    }
    struct sigaction *next=signal==SIGBUS?&forward_bus:&forward_segv;
    if(next->sa_flags&SA_SIGINFO) {next->sa_sigaction(signal,info,context);return;}
    if(next->sa_handler!=SIG_DFL && next->sa_handler!=SIG_IGN && next->sa_handler!=NULL) {next->sa_handler(signal);return;}
    syscall(SYS_exit_group,128+signal);
}
__attribute__((constructor)) static void initialize_faults(void) {
    const char *value=getenv("BLOT_FAULT_AT");if(!value)return;
    fail_at=strtoul(value,NULL,10);
    struct rlimit limit={0,0};setrlimit(RLIMIT_CORE,&limit);
    commit_mode=getenv("BLOT_FAULT_COMMIT")!=NULL;
    if(commit_mode) {
        real_sigaction=dlsym(RTLD_NEXT,"sigaction");real_fread=dlsym(RTLD_NEXT,"fread");
        if(!real_sigaction || !real_fread)_exit(87);
        struct sigaction handler={0};handler.sa_sigaction=fault_handler;handler.sa_flags=SA_SIGINFO|SA_ONSTACK;
        sigemptyset(&handler.sa_mask);
        real_sigaction(SIGSEGV,&handler,&forward_segv);real_sigaction(SIGBUS,&handler,&forward_bus);
    }
    armed=1;
}
int sigaction(int signal,const struct sigaction *action,struct sigaction *old) {
    if(!real_sigaction)real_sigaction=dlsym(RTLD_NEXT,"sigaction");
    if(commit_mode && (signal==SIGSEGV || signal==SIGBUS)) {
        struct sigaction *saved=signal==SIGBUS?&forward_bus:&forward_segv;
        if(old)*old=*saved;if(action)*saved=*action;return 0;
    }
    return real_sigaction(signal,action,old);
}
void *mmap(void *address,size_t length,int protection,int flags,int fd,off_t offset) {
    if(event())return MAP_FAILED;
    int tracked=commit_mode && (flags&MAP_ANONYMOUS) && (protection&PROT_WRITE) && length>=65536 && arena_count<MAX_ARENAS;
    void *p=(void *)syscall(SYS_mmap,address,length,tracked?PROT_NONE:protection,flags,fd,offset);
    if(tracked && p!=MAP_FAILED)arenas[arena_count++]=(struct arena){(uintptr_t)p,(uintptr_t)p+length,(uintptr_t)p};
    return p;
}
int mprotect(void *address,size_t length,int protection) {
    if(commit_mode && protection==PROT_NONE) {
        uintptr_t start=(uintptr_t)address;
        for(unsigned i=0;i<arena_count;i++)if(start>arenas[i].base && start<=arenas[i].end) {arenas[i].end=start;break;}
    }
    if((protection&PROT_WRITE) && event())return -1;
    return (int)syscall(SYS_mprotect,address,length,protection);
}
ssize_t read(int fd,void *buffer,size_t length) {
    if(!commit_range(buffer,length)){errno=EFAULT;return -1;}
    return syscall(SYS_read,fd,buffer,length);
}
size_t fread(void *buffer,size_t size,size_t count,FILE *file) {
    if(!real_fread)real_fread=dlsym(RTLD_NEXT,"fread");
    if(size && count>SIZE_MAX/size){errno=EOVERFLOW;return 0;}
    if(!commit_range(buffer,size*count)){errno=EFAULT;return 0;}
    return real_fread(buffer,size,count,file);
}
