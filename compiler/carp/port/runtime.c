#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#include "runtime.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <signal.h>
#include <ctype.h>
#include <stdatomic.h>
#include <pthread.h>
#include <sys/resource.h>
#ifdef __linux__
#include <sched.h>
#include <sys/syscall.h>
#include <unistd.h>
#endif
#define BP_PTR UINT64_C(0x7ff9000000000000)
#define BP_NULL UINT64_C(0x7ffa000000000000)
#define BP_BOOL UINT64_C(0x7ffb000000000000)
#define BP_UNDEF UINT64_C(0x7ffc000000000000)
#define BP_MASK UINT64_C(0xffff000000000000)
#define BP_PAYLOAD UINT64_C(0x0000ffffffffffff)
#define BP_IMMORTAL UINT32_MAX
#define BP_MAX_WORDS UINT32_C(16777216)
enum {BP_RECORD, BP_STRING, BP_ARRAY, BP_CLOSURE, BP_LOOP, BP_JUMP, BP_FUTURE, BP_BOXED_NUMBER, BP_TAIL_TOKEN, BP_CALL_THEN};
struct BPObj {_Atomic uint32_t refs; uint32_t kind,tag; _Atomic uint32_t flags; size_t n; BPObj *pending; const uint16_t *text; BPObj *base; BPObj *queue_next; Long values[];};
/* Each worker accounts locally. Joining transfers its counts to the owner;
 * object ownership itself remains atomic whenever workers are enabled. Tracking
 * allocations/releases separately also handles objects freed by other workers. */
typedef struct { uint64_t objects_created, objects_destroyed, frames_created, frames_destroyed; } BPStatistics;
static _Thread_local BPStatistics bp_statistics;
static bool bp_parallel;
static uint32_t bp_received_words;
static uint64_t bp_requests;
static _Thread_local int bp_trace[16384],bp_depth;
static BPObj *bp_static_functions[BP_FUNCTIONS];
static _Noreturn void bp_fail(const char *message) {
  fprintf(stderr,"blotc-carp: %s\n",message);
  for(int i=bp_depth-1;i>=0&&i>=bp_depth-12;i--)fprintf(stderr,"  at %s\n",bp_functions[bp_trace[i]].name);
  exit(1);
}
static bool bp_isptr(Long v){return ((uint64_t)v&BP_MASK)==BP_PTR;}
static BPObj *bp_obj(Long v){if(!bp_isptr(v))bp_fail("invalid value representation");return (BPObj*)(uintptr_t)((uint64_t)v&BP_PAYLOAD);}
static Long bp_value(BPObj *p){if((uintptr_t)p>BP_PAYLOAD)bp_fail("pointer outside the 48-bit host range");return (Long)(BP_PTR|(uintptr_t)p);}
static BPObj *bp_alloc(uint32_t kind,size_t count);
static Long bp_num(double d){uint64_t bits;memcpy(&bits,&d,8);uint64_t tag=bits&BP_MASK;
 if(tag>=BP_PTR&&tag<=BP_UNDEF){BPObj *p=bp_alloc(BP_BOXED_NUMBER,1);p->values[0]=(Long)bits;return bp_value(p);}return (Long)bits;}
static double bp_number(Long v){if(bp_isptr(v)&&bp_obj(v)->kind==BP_BOXED_NUMBER){double out;memcpy(&out,bp_obj(v)->values,8);return out;}uint64_t bits=(uint64_t)v;if((bits&BP_MASK)>=BP_PTR&&(bits&BP_MASK)<=BP_UNDEF)bp_fail("expected a numeric value");double d;memcpy(&d,&bits,8);return d;}
static Long bp_bool(bool b){return (Long)(BP_BOOL|(uint64_t)b);}
static uint32_t bp_u32(double d){if(d>=0&&d<4294967296.0)return (uint32_t)d;if(!isfinite(d)||d==0)return 0;double m=fmod(trunc(d),4294967296.0);if(m<0)m+=4294967296.0;return (uint32_t)m;}
static double bp_signed(uint32_t x){return x<UINT32_C(2147483648)?(double)x:(double)((int64_t)x-INT64_C(4294967296));}
static BPObj *bp_alloc(uint32_t kind,size_t count){size_t children=kind==BP_STRING?0:count;if(children>(SIZE_MAX-sizeof(BPObj))/sizeof(Long))bp_fail("allocation overflow");BPObj *p=calloc(1,sizeof(BPObj)+children*sizeof(Long));if(!p)bp_fail("out of memory");atomic_init(&p->refs,1);atomic_init(&p->flags,0);p->kind=kind;p->n=count;bp_statistics.objects_created++;return p;}
Long bp_retain(Long v){if(bp_isptr(v)){BPObj *p=bp_obj(v);if(atomic_load_explicit(&p->refs,memory_order_relaxed)!=BP_IMMORTAL){uint32_t old;if(bp_parallel)old=atomic_fetch_add_explicit(&p->refs,1,memory_order_relaxed);else{old=atomic_load_explicit(&p->refs,memory_order_relaxed);atomic_store_explicit(&p->refs,old+1,memory_order_relaxed);}if(old==0||old>=BP_IMMORTAL-1)bp_fail("reference count overflow or use after release");}}return v;}
static void bp_enqueue(Long v,BPObj **pending){if(!bp_isptr(v))return;BPObj *p=bp_obj(v);if(atomic_load_explicit(&p->refs,memory_order_relaxed)==BP_IMMORTAL)return;uint32_t old;if(bp_parallel)old=atomic_fetch_sub_explicit(&p->refs,1,memory_order_acq_rel);else{old=atomic_load_explicit(&p->refs,memory_order_relaxed);atomic_store_explicit(&p->refs,old-1,memory_order_relaxed);}if(!old)bp_fail("double release");if(old==1){p->pending=*pending;*pending=p;}}
void bp_release(Long v){BPObj *pending=NULL;bp_enqueue(v,&pending);while(pending){BPObj *p=pending;pending=p->pending;if(p->kind==BP_STRING){if(p->base)bp_enqueue(bp_value(p->base),&pending);if(p->flags)free((void*)p->text);}else if(p->kind!=BP_BOXED_NUMBER){for(size_t i=0;i<p->n;i++)bp_enqueue(p->values[i],&pending);}bp_statistics.objects_destroyed++;free(p);}}
Long bp_get(Long *f,int index){if(index<0||index>=f[-1])bp_fail("invalid local read");return bp_keep(f[index]);}
void bp_put(Long *f,int index,Long v){if(index<0||index>=f[-1])bp_fail("invalid local write");bp_drop(f[index]);f[index]=v;}
Long bp_assign(Long *f,int index,Long v){Long result=bp_keep(v);bp_put(f,index,v);return result;}
static bool bp_truth(Long v){if(bp_isptr(v)){BPObj *p=bp_obj(v);if(p->kind==BP_BOXED_NUMBER)return false;return p->kind!=BP_STRING||p->n!=0;}if(((uint64_t)v&BP_MASK)==BP_BOOL)return (v&1)!=0;if((uint64_t)v==BP_NULL||(uint64_t)v==BP_UNDEF)return false;double d=bp_number(v);return d!=0&&!isnan(d);}
bool bp_truthy(Long v){bool result=bp_truth(v);bp_drop(v);return result;}
Long bp_not(Long v){return bp_bool(!bp_truthy(v));}
Long bp_neg(Long v){double d=bp_number(v);bp_drop(v);return bp_num(-d);}
Long bp_bitnot(Long v){uint32_t d=bp_u32(bp_number(v));bp_drop(v);return bp_num(bp_signed(~d));}
Long bp_literal(int id){if(id<0||id>=BP_LITERALS)bp_fail("invalid literal id");BPLiteral *s=&bp_literals[id];if(!s->cached){s->cached=bp_alloc(BP_STRING,s->length);s->cached->refs=BP_IMMORTAL;s->cached->text=s->text;}return bp_value(s->cached);}
static BPObj *bp_string(size_t n){BPObj *s=bp_alloc(BP_STRING,n);if(n>SIZE_MAX/sizeof(uint16_t))bp_fail("string size overflow");uint16_t *text=malloc((n?n:1)*sizeof(uint16_t));if(!text)bp_fail("out of memory");s->text=text;s->flags=1;return s;}
static Long bp_substring(Long v,size_t start,size_t end){BPObj *p=bp_obj(v);if(p->kind!=BP_STRING||start>end||end>p->n)bp_fail("invalid string slice");if(start==0&&end==p->n)return v;BPObj *s=bp_alloc(BP_STRING,end-start);s->text=p->text+start;BPObj *root=p->base?p->base:p;s->base=bp_obj(bp_keep(bp_value(root)));bp_drop(v);return bp_value(s);}
static bool bp_same(Long a,Long b){if((bp_isptr(a)&&bp_obj(a)->kind==BP_BOXED_NUMBER)||(bp_isptr(b)&&bp_obj(b)->kind==BP_BOXED_NUMBER))return false;if(bp_isptr(a)||bp_isptr(b)){if(!bp_isptr(a)||!bp_isptr(b))return false;BPObj *x=bp_obj(a),*y=bp_obj(b);if(x->kind==BP_STRING&&y->kind==BP_STRING)return x->n==y->n&&(x->n==0||memcmp(x->text,y->text,x->n*sizeof(uint16_t))==0);return a==b;}uint64_t ta=(uint64_t)a&BP_MASK,tb=(uint64_t)b&BP_MASK;if((ta>=BP_NULL&&ta<=BP_UNDEF)||(tb>=BP_NULL&&tb<=BP_UNDEF))return a==b;return bp_number(a)==bp_number(b);}
Long bp_binary(int op,Long a,Long b){Long out;
 if(op==5||op==6||op==7||op==8){bool eq=bp_same(a,b);out=bp_bool(op==6||op==8?!eq:eq);}
 else if(op==0&&bp_isptr(a)&&bp_isptr(b)&&bp_obj(a)->kind==BP_STRING&&bp_obj(b)->kind==BP_STRING){BPObj *x=bp_obj(a),*y=bp_obj(b);if(x->n>SIZE_MAX-y->n)bp_fail("string concatenation overflow");if(x->n==0)out=bp_keep(b);else if(y->n==0)out=bp_keep(a);else{BPObj *s=bp_string(x->n+y->n);memcpy((void*)s->text,x->text,x->n*2);memcpy((void*)(s->text+x->n),y->text,y->n*2);out=bp_value(s);}}
 else {double x=bp_number(a),y=bp_number(b);uint32_t u=0,w=0,s=0;if(op>=13&&op<=18){u=bp_u32(x);w=bp_u32(y);s=w&31;}switch(op){
 case 0:out=bp_num(x+y);break;case 1:out=bp_num(x-y);break;case 2:out=bp_num(x*y);break;case 3:out=bp_num(x/y);break;case 4:out=bp_num(fmod(x,y));break;
 case 9:out=bp_bool(x<y);break;case 10:out=bp_bool(x<=y);break;case 11:out=bp_bool(x>y);break;case 12:out=bp_bool(x>=y);break;
 case 13:out=bp_num(bp_signed(u&w));break;case 14:out=bp_num(bp_signed(u|w));break;case 15:out=bp_num(bp_signed(u^w));break;case 16:out=bp_num(bp_signed(u<<s));break;
 case 17:out=bp_num(bp_signed((u>>s)|((u&UINT32_C(0x80000000))&&s?(~UINT32_C(0)<<(32-s)):0)));break;
 case 18:out=bp_num(u>>s);break;case 19:out=bp_num(pow(x,y));break;default:bp_fail("unknown numeric operation");}}
 bp_drop(a);bp_drop(b);return out;
}
Long bp_record(int shape,int n,Long *values){if(shape<0||shape>=BP_SHAPES||n!=(int)bp_shapes[shape].count)bp_fail("invalid record layout");if(!n){if(!bp_shapes[shape].cached){BPObj *p=bp_alloc(BP_RECORD,0);p->tag=shape;p->refs=BP_IMMORTAL;bp_shapes[shape].cached=p;}return bp_value(bp_shapes[shape].cached);}BPObj *p=bp_alloc(BP_RECORD,n);p->tag=shape;memcpy(p->values,values,(size_t)n*sizeof(Long));return bp_value(p);}
static Long bp_borrow_field(Long v,int key){BPObj *p=bp_obj(v);if((p->kind==BP_STRING||p->kind==BP_ARRAY)&&key==BP_KEY_LENGTH)return bp_num((double)p->n);if(p->kind!=BP_RECORD)bp_fail("field access on a non-record");const BPShape *s=&bp_shapes[p->tag];if(key==BP_KEY_DOLLAR)return bp_literal(s->tag);for(uint32_t i=0;i<s->count;i++)if(s->keys[i]==(uint32_t)key)return p->values[i];return (Long)BP_UNDEF;}
Long bp_field(Long v,int key){Long out=bp_keep(bp_borrow_field(v,key));bp_drop(v);return out;}
/* A frame is private to one dispatched call. These operations borrow its local
 * while the frame keeps ownership; only an escaping field receives a new ref.
 * Tag IDs index interned UTF-16 strings, so tag equality needs no string scan. */
Long bp_local_field(Long *frame,int index,int key) {
  if(index<0||index>=frame[-1])bp_fail("invalid local field read");
  return bp_keep(bp_borrow_field(frame[index],key));
}
Long bp_local_tag(Long *frame,int index,int literal) {
  if(index<0||index>=frame[-1]||literal<0||literal>=BP_LITERALS)
    bp_fail("invalid local tag test");
  BPObj *p=bp_obj(frame[index]);
  if(p->kind!=BP_RECORD)bp_fail("field access on a non-record");
  return bp_bool(bp_shapes[p->tag].tag==(uint32_t)literal);
}

Long bp_index(Long v,Long at){BPObj *p=bp_obj(v);double d=bp_number(at);Long out=(Long)BP_UNDEF;if(isfinite(d)&&d>=0&&d<(double)p->n&&trunc(d)==d){size_t i=(size_t)d;if(p->kind==BP_ARRAY)out=bp_keep(p->values[i]);else if(p->kind==BP_STRING)out=bp_substring(bp_keep(v),i,i+1);else bp_fail("indexing a non-array");}bp_drop(v);bp_drop(at);return out;}
Long bp_set_index(Long v,Long at,Long value){BPObj *p=bp_obj(v);double d=bp_number(at);if(p->kind!=BP_ARRAY||!isfinite(d)||d<0||d>=(double)p->n||trunc(d)!=d)bp_fail("invalid array update");size_t i=(size_t)d;bp_drop(p->values[i]);p->values[i]=value;Long out=bp_keep(value);bp_drop(v);bp_drop(at);return out;}
static size_t bp_slice_at(double x,size_t n){if(isnan(x))return 0;if(x<0){double y=(double)n+trunc(x);return y<=0?0:(size_t)y;}return x>=(double)n?n:(size_t)trunc(x);}
Long bp_slice2(Long v,Long a,Long b){BPObj *p=bp_obj(v);size_t start=bp_slice_at(bp_number(a),p->n),end=bp_slice_at(bp_number(b),p->n);if(end<start)end=start;bp_drop(a);bp_drop(b);if(p->kind==BP_STRING)return bp_substring(v,start,end);if(p->kind!=BP_ARRAY)bp_fail("slice of a non-array");BPObj *out=bp_alloc(BP_ARRAY,end-start);for(size_t i=start;i<end;i++)out->values[i-start]=bp_keep(p->values[i]);bp_drop(v);return bp_value(out);}
Long bp_slice1(Long v,Long a){return bp_slice2(v,a,bp_num((double)bp_obj(v)->n));}
Long bp_slice0(Long v){return bp_slice1(v,bp_num(0));}
static uint32_t bp_cp(BPObj *p,size_t i){uint32_t a=p->text[i];if(a>=0xd800&&a<=0xdbff&&i+1<p->n){uint32_t b=p->text[i+1];if(b>=0xdc00&&b<=0xdfff)return 0x10000+((a-0xd800)<<10)+(b-0xdc00);}return a;}
Long bp_codepoint(Long v,Long at){BPObj *p=bp_obj(v);if(p->kind!=BP_STRING)bp_fail("codePointAt on non-string");double d=bp_number(at);Long out=(Long)BP_UNDEF;if(isfinite(d)&&d>=0&&d<(double)p->n)out=bp_num(bp_cp(p,(size_t)d));bp_drop(v);bp_drop(at);return out;}
Long bp_spread(Long v){BPObj *p=bp_obj(v);if(p->kind==BP_ARRAY)return bp_slice0(v);if(p->kind!=BP_STRING)bp_fail("spread of non-iterable");size_t n=0;for(size_t i=0;i<p->n;i++){if(bp_cp(p,i)>0xffff)i++;n++;}BPObj *a=bp_alloc(BP_ARRAY,n);size_t j=0;for(size_t i=0;i<p->n;){size_t end=i+(bp_cp(p,i)>0xffff?2:1);a->values[j++]=bp_substring(bp_keep(v),i,end);i=end;}bp_drop(v);return bp_value(a);}
Long bp_char_new(Long v){double d=bp_number(v);if(!isfinite(d)||d<0||d>0x10ffff||trunc(d)!=d||(d>=0xd800&&d<=0xdfff))bp_fail("invalid Unicode scalar value");uint32_t c=(uint32_t)d;BPObj *s=bp_string(c>0xffff?2:1);uint16_t *p=(uint16_t*)s->text;if(c>0xffff){c-=0x10000;p[0]=0xd800+(c>>10);p[1]=0xdc00+(c&1023);}else p[0]=(uint16_t)c;bp_drop(v);return bp_value(s);}
Long bp_nat_chk(Long v){double d=bp_number(v);if(!isfinite(d)||d<0||d>281474976710655.0||trunc(d)!=d)bp_fail("Nat outside 0..2^48-1");return v;}
Long bp_cmp_new(Long a,Long b){double x=bp_number(a),y=bp_number(b);bp_drop(a);bp_drop(b);return bp_record(x<y?BP_SHAPE_LT:x==y?BP_SHAPE_EQ:BP_SHAPE_GT,0,NULL);}
Long bp_nat_divmod(Long a,Long b){double x=bp_number(a),y=bp_number(b);Long vals[]={bp_num(y==0?0:trunc(x/y)),bp_num(y==0?x:fmod(x,y))};bp_drop(a);bp_drop(b);return bp_record(BP_SHAPE_TUPLE,2,vals);}
Long bp_array_new(Long d,Long v){double depth=bp_number(d);if(!isfinite(depth)||depth<0||depth>31||trunc(depth)!=depth)bp_fail("invalid array depth");size_t count=(size_t)1<<(unsigned)depth;BPObj *a=bp_alloc(BP_ARRAY,count);for(size_t i=0;i<count;i++)a->values[i]=bp_keep(v);bp_drop(d);bp_drop(v);return bp_value(a);}
Long bp_u32_to_word(Long v){uint32_t x=bp_u32(bp_number(v));Long word=bp_record(BP_SHAPE_WNIL,0,NULL);for(int i=31;i>=0;i--){Long a[]={bp_bool(((x>>i)&1)!=0),word};word=bp_record(BP_SHAPE_WCON,2,a);}bp_drop(v);return word;}
Long bp_word_to_u32(Long v){uint32_t x=0;Long w=v;for(unsigned i=0;i<32&&bp_obj(w)->tag==BP_SHAPE_WCON;i++){if(bp_truth(bp_borrow_field(w,BP_KEY_HEAD)))x|=UINT32_C(1)<<i;w=bp_borrow_field(w,BP_KEY_TAIL);}bp_drop(v);return bp_num(x);}
Long bp_f32_bits(Long v){float f=(float)bp_number(v);uint32_t bits;memcpy(&bits,&f,4);bp_drop(v);return bp_num(bits);}
Long bp_f32_from_bits(Long v){uint32_t bits=bp_u32(bp_number(v));float f;memcpy(&f,&bits,4);bp_drop(v);return bp_num(f);}
#define BP_MATH(name,expression) Long bp_math_##name(Long v){double d=bp_number(v);bp_drop(v);return bp_num(expression);}
BP_MATH(fround,(double)(float)d) BP_MATH(floor,floor(d)) BP_MATH(ceil,ceil(d)) BP_MATH(trunc,trunc(d)) BP_MATH(abs,fabs(d)) BP_MATH(sqrt,sqrt(d))
Long bp_math_imul(Long a,Long b){uint32_t x=bp_u32(bp_number(a)),y=bp_u32(bp_number(b));bp_drop(a);bp_drop(b);return bp_num(bp_signed(x*y));}
static bool bp_space(uint16_t c){return (c>=9&&c<=13)||c==32||c==0xa0||c==0x1680||(c>=0x2000&&c<=0x200a)||c==0x2028||c==0x2029||c==0x202f||c==0x205f||c==0x3000||c==0xfeff;}
Long bp_f32_read(Long v){BPObj *s=bp_obj(v);if(s->kind!=BP_STRING)bp_fail("float read requires text");size_t start=0;while(start<s->n&&bp_space(s->text[start]))start++;size_t n=s->n-start;char *text=malloc(n+1);if(!text)bp_fail("out of memory");bool ascii=true;for(size_t i=0;i<n;i++){if(s->text[start+i]>127||s->text[start+i]==0)ascii=false;text[i]=(char)s->text[start+i];}text[n]=0;size_t p=0;if(text[p]=='+'||text[p]=='-')p++;bool valid=false;
 if(ascii){char *rest=text+p;for(char *q=rest;*q;q++)*q=(char)tolower((unsigned char)*q);if(!strcmp(rest,"inf")||!strcmp(rest,"infinity")||!strcmp(rest,"nan"))valid=true;else{size_t digits=0;while(p<n&&isdigit((unsigned char)text[p])){p++;digits++;}if(p<n&&text[p]=='.'){p++;while(p<n&&isdigit((unsigned char)text[p])){p++;digits++;}}valid=digits!=0;if(p<n&&text[p]=='e'){p++;if(p<n&&(text[p]=='+'||text[p]=='-'))p++;size_t begin=p;while(p<n&&isdigit((unsigned char)text[p]))p++;valid=valid&&p!=begin;}valid=valid&&p==n;}}
 Long result;if(valid){float f=strtof(text,NULL);Long a[]={bp_num(f)};result=bp_record(BP_SHAPE_SOME,1,a);}else result=bp_record(BP_SHAPE_NONE,0,NULL);free(text);bp_drop(v);return result;
}
Long bp_closure(int id,int n,Long *values){if(id<0||id>=BP_FUNCTIONS||n!=(int)bp_functions[id].captures)bp_fail("invalid closure environment");if(!n)return bp_function(id);BPObj *p=bp_alloc(BP_CLOSURE,n);p->tag=id;memcpy(p->values,values,(size_t)n*sizeof(Long));return bp_value(p);}
Long bp_function(int id){if(id<0||id>=BP_FUNCTIONS||bp_functions[id].captures!=0)bp_fail("invalid static function");if(!bp_static_functions[id]){BPObj *p=bp_alloc(BP_CLOSURE,0);p->tag=id;p->refs=BP_IMMORTAL;bp_static_functions[id]=p;}return bp_value(bp_static_functions[id]);}
/* A tail transfer carries already evaluated, owned arguments in thread-local
 * storage. It is consumed immediately after the current native function returns.
 * This is a calling convention for AOT code, not a bytecode interpreter. */
static BPObj bp_tail_token = {.refs = BP_IMMORTAL, .kind = BP_TAIL_TOKEN};
static _Thread_local struct {
  bool pending, apply;
  int id, count;
  Long function, arguments[BP_MAX_ARGUMENTS];
} bp_transfer;
Long bp_tailcall(int id,int n,Long *values) {
  if(bp_transfer.pending||n<0||n>BP_MAX_ARGUMENTS)bp_fail("invalid tail transfer");
  bp_transfer.pending=true;bp_transfer.apply=false;bp_transfer.id=id;bp_transfer.count=n;
  memcpy(bp_transfer.arguments,values,(size_t)n*sizeof(Long));
  return bp_value(&bp_tail_token);
}
Long bp_tailapply(Long function,int n,Long *values) {
  (void)bp_tailcall(0,n,values);
  bp_transfer.apply=true;bp_transfer.function=function;
  return bp_value(&bp_tail_token);
}
/* Schedule a call followed by a compiled two-argument continuation. */
Long bp_callthen(int id,int after,Long continuation,int n,Long *values) {
  if(n<0||n>BP_MAX_ARGUMENTS||id<0||id>=BP_FUNCTIONS||after<0||after>=BP_FUNCTIONS)
    bp_fail("invalid deferred call");
  BPObj *call=bp_alloc(BP_CALL_THEN,(size_t)n+1);
  call->tag=(uint32_t)id;call->flags=(uint32_t)after;call->values[0]=continuation;
  memcpy(call->values+1,values,(size_t)n*sizeof(Long));
  return bp_value(call);
}
typedef struct {int function;Long environment;bool run_jumps;} BPContinuation;
static Long bp_dispatch(bool apply,int id,Long function,int n,Long *values) {
  if(n<0||n>BP_MAX_ARGUMENTS)bp_fail("invalid call arity");
  Long arguments[BP_MAX_ARGUMENTS];
  memcpy(arguments,values,(size_t)n*sizeof(Long));
  bool run_jumps=false;
  BPContinuation *continuations=NULL;size_t continuation_count=0,continuation_capacity=0;
  if(bp_depth==(int)(sizeof(bp_trace)/sizeof(bp_trace[0])))bp_fail("native call-depth limit exceeded");
  int trace=bp_depth++;
  bp_trace[trace]=0;
  Long *storage=NULL;
  size_t storage_capacity=0;
  for(;;) {
    BPObj *environment=NULL;
    if(apply) {
      environment=bp_obj(function);
      while(environment->kind==BP_LOOP) {
        run_jumps=true;
        Long inner=bp_keep(environment->values[0]);
        bp_drop(function);function=inner;environment=bp_obj(function);
      }
      if(environment->kind!=BP_CLOSURE)bp_fail("application of non-function");
      id=(int)environment->tag;
    }
    if(id<0||id>=BP_FUNCTIONS)bp_fail("invalid function id");
    const BPFunction *fn=&bp_functions[id];
    if(n>(int)fn->arity||fn->slots<fn->arity+fn->captures||(!apply&&fn->captures))
      bp_fail("invalid call arity or environment");
    size_t required=(size_t)fn->slots+1;
    if(required>storage_capacity) {
      if(required>SIZE_MAX/sizeof(Long))bp_fail("frame allocation overflow");
      Long *grown=realloc(storage,required*sizeof(Long));
      if(!grown)bp_fail("out of memory");
      storage=grown;storage_capacity=required;
    }
    Long *frame=storage+1;storage[0]=fn->slots;
    for(uint32_t i=0;i<fn->slots;i++)frame[i]=(Long)BP_UNDEF;
    for(uint32_t i=0;i<fn->captures;i++)frame[i]=bp_keep(environment->values[i]);
    for(int i=0;i<n;i++)frame[fn->captures+(unsigned)i]=arguments[i];
    if(apply)bp_drop(function);
    bp_trace[trace]=id;bp_statistics.frames_created++;
    Long result=fn->code(frame);
    for(uint32_t i=0;i<fn->slots;i++)bp_drop(frame[i]);
    bp_statistics.frames_destroyed++;
    if(result==bp_value(&bp_tail_token)) {
      if(!bp_transfer.pending)bp_fail("missing tail transfer");
      apply=bp_transfer.apply;id=bp_transfer.id;function=bp_transfer.function;n=bp_transfer.count;
      memcpy(arguments,bp_transfer.arguments,(size_t)n*sizeof(Long));
      bp_transfer.pending=false;
      continue;
    }
    if(bp_isptr(result)&&bp_obj(result)->kind==BP_CALL_THEN) {
      BPObj *call=bp_obj(result);
      if(continuation_count==continuation_capacity) {
        continuation_capacity=continuation_capacity?continuation_capacity*2:32;
        if(continuation_capacity>SIZE_MAX/sizeof(BPContinuation))bp_fail("continuation stack overflow");
        BPContinuation *grown=realloc(continuations,continuation_capacity*sizeof(BPContinuation));
        if(!grown)bp_fail("out of memory");continuations=grown;
      }
      continuations[continuation_count++]=(BPContinuation){(int)call->flags,bp_keep(call->values[0]),run_jumps};
      id=(int)call->tag;n=(int)call->n-1;apply=false;run_jumps=true;
      for(int i=0;i<n;i++)arguments[i]=bp_keep(call->values[i+1]);
      bp_drop(result);continue;
    }
    if(run_jumps&&bp_isptr(result)&&bp_obj(result)->kind==BP_JUMP) {
      BPObj *jump=bp_obj(result);
      function=bp_keep(jump->values[0]);arguments[0]=bp_keep(jump->values[1]);
      n=1;apply=true;bp_drop(result);continue;
    }
    if(continuation_count) {
      BPContinuation next=continuations[--continuation_count];
      id=next.function;arguments[0]=result;arguments[1]=next.environment;
      n=2;apply=false;run_jumps=next.run_jumps;continue;
    }
    free(storage);free(continuations);bp_depth--;return result;
  }
}
Long bp_call(int id,int n,Long *values){return bp_dispatch(false,id,(Long)BP_UNDEF,n,values);}
Long bp_apply(Long v,int n,Long *values){return bp_dispatch(true,0,v,n,values);}
Long bp_run_clo(Long v){BPObj *p=bp_alloc(BP_LOOP,1);p->values[0]=v;return bp_value(p);}
Long bp_run_tail(Long v,Long x){BPObj *p=bp_obj(v);if(p->kind==BP_LOOP){Long f=bp_keep(p->values[0]);bp_drop(v);v=f;}BPObj *j=bp_alloc(BP_JUMP,2);j->values[0]=v;j->values[1]=x;return bp_value(j);}
Long bp_run_loop(Long v){while(bp_isptr(v)&&bp_obj(v)->kind==BP_JUMP){BPObj *j=bp_obj(v);Long f=bp_keep(j->values[0]),args[]={bp_keep(j->values[1])};bp_drop(v);v=bp_apply(f,1,args);}return v;}
Long bp_unreachable(void){bp_fail("unreachable generated control path");}
void bp_unreachable_unit(void){bp_fail("unreachable generated control path");}
#include "calls.inc"
#include "scheduler.inc"
static void bp_write(const void *bytes,size_t n){if(n&&fwrite(bytes,1,n,stdout)!=n)bp_fail("failed to write native response");}
static void bp_write_word(uint32_t w){unsigned char b[4]={(unsigned char)w,(unsigned char)(w>>8),(unsigned char)(w>>16),(unsigned char)(w>>24)};bp_write(b,4);}
void bp_handshake(Long version){bp_write_word(2);bp_write_word(UINT32_C(1112297300));bp_write_word(bp_u32(bp_number(version)));bp_drop(version);if(fflush(stdout))bp_fail("failed to flush native response");}
Long bp_receive(void){unsigned char b[4];size_t n=fread(b,1,4,stdin);if(n==0&&!ferror(stdin))return (Long)BP_NULL;if(n!=4)bp_fail("native protocol: truncated frame");uint32_t length=(uint32_t)b[0]|((uint32_t)b[1]<<8)|((uint32_t)b[2]<<16)|((uint32_t)b[3]<<24);if(length>BP_MAX_WORDS)bp_fail("native protocol: frame exceeds 16777216 words");if(bp_requests++>=UINT64_C(281474976710655))bp_fail("native compiler request limit exhausted");size_t capacity=1;while(capacity<length)capacity*=2;BPObj *a=bp_alloc(BP_ARRAY,capacity);for(uint32_t i=0;i<length;i++){if(fread(b,1,4,stdin)!=4)bp_fail("native protocol: truncated frame");uint32_t w=(uint32_t)b[0]|((uint32_t)b[1]<<8)|((uint32_t)b[2]<<16)|((uint32_t)b[3]<<24);a->values[i]=bp_num(w);}for(size_t i=length;i<capacity;i++)a->values[i]=bp_num(0);bp_received_words=length;return bp_value(a);}
Long bp_request_length(void){return bp_num(bp_received_words);}
bool bp_has_frame(Long v){return (uint64_t)v!=BP_NULL;}
static bool bp_is_nil(Long v){BPObj *p=bp_obj(v);return p->kind==BP_RECORD&&p->tag==BP_SHAPE_NIL;}
void bp_send(Long packet){uint32_t count=bp_u32(bp_number(bp_borrow_field(packet,BP_KEY_WORD_COUNT)));if(count>BP_MAX_WORDS)bp_fail("native response exceeds 16M words");bp_write_word(count);size_t bytes=0;Long header=bp_borrow_field(packet,BP_KEY_HEADER);while(!bp_is_nil(header)){bp_write_word(bp_u32(bp_number(bp_borrow_field(header,BP_KEY_HEAD))));bytes+=4;header=bp_borrow_field(header,BP_KEY_TAIL);}Long blocks=bp_borrow_field(packet,BP_KEY_BLOCKS);while(!bp_is_nil(blocks)){Long block=bp_borrow_field(blocks,BP_KEY_HEAD);size_t remaining=(size_t)bp_number(bp_borrow_field(block,BP_KEY_LENGTH));Long words=bp_borrow_field(block,BP_KEY_WORDS);while(remaining){if(bp_is_nil(words))bp_fail("truncated output block");uint32_t w=bp_u32(bp_number(bp_borrow_field(words,BP_KEY_HEAD)));unsigned char b[4]={(unsigned char)w,(unsigned char)(w>>8),(unsigned char)(w>>16),(unsigned char)(w>>24)};size_t take=remaining<4?remaining:4;bp_write(b,take);remaining-=take;bytes+=take;words=bp_borrow_field(words,BP_KEY_TAIL);}blocks=bp_borrow_field(blocks,BP_KEY_TAIL);}while(bytes%4){const unsigned char zero=0;bp_write(&zero,1);bytes++;}if(bytes!=(size_t)count*4)bp_fail("native response length mismatch");bp_drop(packet);if(fflush(stdout))bp_fail("failed to flush native response");}
void bp_destroy(void){for(int i=0;i<BP_FUNCTIONS;i++)if(bp_static_functions[i]){bp_static_functions[i]->refs=1;bp_drop(bp_value(bp_static_functions[i]));bp_static_functions[i]=NULL;}for(int i=0;i<BP_SHAPES;i++)if(bp_shapes[i].cached){bp_shapes[i].cached->refs=1;bp_drop(bp_value(bp_shapes[i].cached));bp_shapes[i].cached=NULL;}for(int i=0;i<BP_LITERALS;i++)if(bp_literals[i].cached){bp_literals[i].cached->refs=1;bp_drop(bp_value(bp_literals[i].cached));bp_literals[i].cached=NULL;}if(bp_statistics.objects_created!=bp_statistics.objects_destroyed||bp_statistics.frames_created!=bp_statistics.frames_destroyed){fprintf(stderr,"blotc-carp: ownership mismatch: objects=%" PRIu64 "/%" PRIu64 " frames=%" PRIu64 "/%" PRIu64 "\n",bp_statistics.objects_created,bp_statistics.objects_destroyed,bp_statistics.frames_created,bp_statistics.frames_destroyed);exit(1);}}
#ifndef BP_NO_MAIN
extern void port_MINUS_serve(void);
int main(int argc,char **argv){bool inherit=false,stats=false;unsigned threads=1;for(int i=1;i<argc;i++){if(!strcmp(argv[i],"--threads")&&i+1<argc){char *end=NULL;long n=strtol(argv[++i],&end,10);if(!end||*end||n<1||n>64)bp_fail("threads must be between 1 and 64");threads=(unsigned)n;}else if(!strcmp(argv[i],"--inherit-priority"))inherit=true;else if(!strcmp(argv[i],"--runtime-stats"))stats=true;else if(!strcmp(argv[i],"--version")){puts("blotc-carp native semantic port 0.2");return 0;}else bp_fail("usage: blotc-carp-native [--threads 1..64] [--inherit-priority]");}
#ifdef __linux__
 if(!inherit){
  int policy=sched_getscheduler(0); errno=0; int nice=getpriority(PRIO_PROCESS,0);
  bool cpu=policy>=0&&((policy&~SCHED_RESET_ON_FORK)==SCHED_IDLE||
    ((((policy&~SCHED_RESET_ON_FORK)==SCHED_OTHER)||((policy&~SCHED_RESET_ON_FORK)==SCHED_BATCH))&&errno==0&&nice>0));
  long io=syscall(SYS_ioprio_get,1,0); bool idle_io=io>=0&&(io>>13)==3;
  if(cpu){struct sched_param p={0};(void)sched_setscheduler(0,SCHED_OTHER,&p);(void)setpriority(PRIO_PROCESS,0,0);}
  if(cpu||idle_io)(void)syscall(SYS_ioprio_set,1,0,(2<<13)|4);
 }
#else
 (void)inherit;
#endif
 signal(SIGPIPE,SIG_IGN);bp_pool_start(threads);bp_handshake(bp_call0(BP_VERSION));port_MINUS_serve();bp_pool_stop();bp_destroy();
 if(stats)fprintf(stderr,"runtime_stats: {\"threads\":%u,\"tasks_submitted\":%" PRIu64 ",\"worker_tasks\":%" PRIu64 ",\"objects_allocated\":%" PRIu64 "}\n",threads,(uint64_t)bp_tasks_submitted,(uint64_t)bp_tasks_by_workers,bp_statistics.objects_created);return 0;}
#endif
