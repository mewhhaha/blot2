/* The runtime is included here so tests can check ownership and the scheduler
 * directly. The generated language functions are linked, never substituted. */
#define BP_NO_MAIN
#include "runtime.c"
#include <assert.h>

static unsigned checks;
#define CHECK(test) do { checks++; if (!(test)) { fprintf(stderr,"runtime test failed at line %d: %s\n",__LINE__,#test); abort(); } } while(0)
static void number_is(Long value,double expected) {
  double actual=bp_number(value);
  CHECK((isnan(actual)&&isnan(expected)) ||
    (actual==expected && (expected!=0 || signbit(actual)==signbit(expected))));
  bp_drop(value);
}
static Long ascii(const char *text) {
  size_t n=strlen(text);
  BPObj *s=bp_string(n);
  for(size_t i=0;i<n;i++)((uint16_t*)s->text)[i]=(unsigned char)text[i];
  return bp_value(s);
}
static void parsed_bits(const char *text,uint32_t expected) {
  Long result=bp_f32_read(ascii(text));
  CHECK(bp_obj(result)->tag==BP_SHAPE_SOME);
  number_is(bp_f32_bits(bp_field(result,BP_KEY_VALUE)),expected);
}

int main(void) {
  bp_pool_start(4);
  number_is(bp_binary(0,bp_num(40),bp_num(2)),42);
  number_is(bp_binary(18,bp_num(-1),bp_num(0)),4294967295.0);
  number_is(bp_binary(17,bp_num(0x80000000u),bp_num(31)),-1);
  number_is(bp_binary(16,bp_num(1),bp_num(63)),-2147483648.0);
  number_is(bp_binary(4,bp_num(-4),bp_num(2)),-0.0);
  number_is(bp_math_imul(bp_num(0xffffffffu),bp_num(0xffffffffu)),1);
  number_is(bp_math_fround(bp_num(1.000000059604644775390625)),1);
  number_is(bp_math_trunc(bp_num(-0.9)),-0.0);
  CHECK(!bp_truthy(bp_binary(5,bp_num(NAN),bp_num(NAN))));
  CHECK(bp_truthy(bp_binary(5,bp_num(-0.0),bp_num(0.0))));
  for(uint32_t payload=1;payload<0x800000;payload+=131071) {
    uint32_t bits=0x7f800000u|payload;
    number_is(bp_f32_bits(bp_f32_from_bits(bp_num(bits))),bits|0x00400000u);
    number_is(bp_f32_bits(bp_f32_from_bits(bp_num(bits|0x80000000u))),bits|0x80400000u);
  }
  parsed_bits("1.000000059604644775390625",0x3f800000);
  parsed_bits("1.000000059604644775390626",0x3f800001);
  parsed_bits("-0",0x80000000u);
  parsed_bits("1e999",0x7f800000u);
  parsed_bits("-Infinity",0xff800000u);
  for(size_t i=0;i<7;i++) {
    const char *invalid[]={"","+","1.0x","1e","nanx","1 ","1\n"};
    Long result=bp_f32_read(ascii(invalid[i]));
    CHECK(bp_obj(result)->tag==BP_SHAPE_NONE);bp_drop(result);
  }
  Long nul=ascii("nanxjunk");((uint16_t*)bp_obj(nul)->text)[3]=0;
  Long rejected=bp_f32_read(nul);CHECK(bp_obj(rejected)->tag==BP_SHAPE_NONE);bp_drop(rejected);
  Long astral=bp_char_new(bp_num(0x1f600));
  number_is(bp_field(bp_keep(astral),BP_KEY_LENGTH),2);
  number_is(bp_codepoint(bp_keep(astral),bp_num(0)),0x1f600);
  number_is(bp_field(bp_spread(bp_keep(astral)),BP_KEY_LENGTH),1);
  Long twice=bp_binary(0,bp_keep(astral),bp_keep(astral));
  number_is(bp_field(bp_spread(twice),BP_KEY_LENGTH),2);
  bp_drop(astral);
  Long text=ascii("abcdefghij");
  for(int i=0;i<9;i++)text=bp_slice1(text,bp_num(1));
  CHECK(bp_truthy(bp_binary(5,bp_keep(text),ascii("j"))));
  bp_drop(text);
  Long original=bp_array_new(bp_num(2),bp_num(42));
  Long copy=bp_slice0(bp_keep(original));
  number_is(bp_set_index(bp_keep(copy),bp_num(1),bp_num(99)),99);
  number_is(bp_index(bp_keep(original),bp_num(1)),42);
  number_is(bp_index(bp_keep(copy),bp_num(1)),99);
  bp_drop(original);bp_drop(copy);
  /* Borrowing a local must not borrow the escaping child: reusing the
   * parent's slot must leave that child alive and release it exactly once. */
  Long local_storage[] = {1, (Long)BP_UNDEF};
  Long *local = local_storage + 1;
  Long child = ascii("retained across slot reuse");
  Long fields[] = {child};
  local[0] = bp_record(BP_SHAPE_SOME, 1, fields);
  BPObj *parent = bp_obj(local[0]);
  uint32_t parent_refs = atomic_load(&parent->refs);
  Long escaped = bp_local_field(local, 0, BP_KEY_VALUE);
  CHECK(atomic_load(&parent->refs) == parent_refs);
  CHECK(atomic_load(&bp_obj(escaped)->refs) == 2);
  CHECK(bp_truthy(bp_local_tag(local, 0, (int)bp_shapes[BP_SHAPE_SOME].tag)));
  CHECK(!bp_truthy(bp_local_tag(local, 0, (int)bp_shapes[BP_SHAPE_NONE].tag)));
  CHECK(atomic_load(&parent->refs) == parent_refs);
  CHECK((uint64_t)bp_local_field(local, 0, BP_KEY_HEAD) == BP_UNDEF);
  bp_put(local, 0, bp_num(42));
  CHECK(atomic_load(&bp_obj(escaped)->refs) == 1);
  CHECK(bp_truthy(bp_binary(5, escaped, ascii("retained across slot reuse"))));
  bp_drop(local[0]);
  /* Exercise the generated name-equality rewrite with arbitrary UTF-16 data,
   * including NUL, surrogate code units and shared substring storage. */
  int name_equal = -1;
  for (int i = 0; i < BP_FUNCTIONS; i++)
    if (!strcmp(bp_functions[i].name, "$$$$047model$name_equal$")) name_equal = i;
  CHECK(name_equal >= 0);
  uint32_t seed = UINT32_C(0x63707274);
  for (size_t trial = 0; trial < 256; trial++) {
    size_t count = trial % 65;
    BPObj *a = bp_string(count), *b = bp_string(count);
    for (size_t j = 0; j < count; j++) {
      seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5;
      ((uint16_t *)a->text)[j] = ((uint16_t *)b->text)[j] = (uint16_t)seed;
    }
    Long av = bp_value(a), bv = bp_value(b);
    CHECK(bp_truthy(bp_call2(name_equal, bp_keep(av), bp_keep(bv))));
    Long suffix_a = bp_slice1(bp_keep(av), bp_num((double)(count / 2)));
    Long suffix_b = bp_slice1(bp_keep(bv), bp_num((double)(count / 2)));
    CHECK(bp_truthy(bp_call2(name_equal, suffix_a, suffix_b)));
    if (count) {
      ((uint16_t *)b->text)[count - 1] ^= 1;
      CHECK(!bp_truthy(bp_call2(name_equal, bp_keep(av), bp_keep(bv))));
    }
    bp_drop(av); bp_drop(bv);
  }

  /* Long protocol headers must not consume the native call stack. */
  int length=-1, append=-1, take=-1, replicate=-1, runs=-1, concat=-1;
  for(int i=0;i<BP_FUNCTIONS;i++) {
    const char *name=bp_functions[i].name;
    if(!strcmp(name,"$List$length$"))length=i;
    if(!strcmp(name,"$List$append$"))append=i;
    if(!strcmp(name,"$List$take$"))take=i;
    if(!strcmp(name,"$List$replicate$"))replicate=i;
    if(!strcmp(name,"$List$sort$runs$"))runs=i;
    if(!strcmp(name,"$List$concat$"))concat=i;
  }
  CHECK(length>=0&&append>=0&&take>=0&&replicate>=0&&runs>=0&&concat>=0);
  Long big=bp_call2(replicate,bp_num(100000),bp_num(7));
  number_is(bp_call1(length,bp_keep(big)),100000);
  Long first=bp_call2(take,bp_keep(big),bp_num(75000));
  number_is(bp_call1(length,bp_keep(first)),75000);
  Long both=bp_call2(append,bp_keep(big),first);
  number_is(bp_call1(length,both),175000);
  Long small=bp_call2(take,bp_keep(big),bp_num(10));
  Long singleton_runs=bp_call1(runs,bp_keep(small));
  Long joined=bp_call1(concat,singleton_runs);
  number_is(bp_call1(length,bp_keep(joined)),10);
  while(!bp_is_nil(joined)) {
    number_is(bp_field(bp_keep(joined),BP_KEY_HEAD),7);
    joined=bp_field(joined,BP_KEY_TAIL);
  }
  bp_drop(joined);bp_drop(small);bp_drop(big);
  int conjunction=-1;
  for(int i=0;i<BP_FUNCTIONS;i++)if(strcmp(bp_functions[i].name,"$Bool$and$")==0)conjunction=i;
  CHECK(conjunction>=0);
  Long work[256];
  for(size_t i=0;i<256;i++)work[i]=bp_future2(conjunction,bp_bool((i&1)!=0),bp_bool(true));
  /* Waiting without helping once proves a worker actually executes a task. */
  pthread_mutex_lock(&bp_pool_mutex);
  while(!atomic_load_explicit(&bp_obj(work[0])->flags,memory_order_acquire))
    pthread_cond_wait(&bp_pool_ready,&bp_pool_mutex);
  pthread_mutex_unlock(&bp_pool_mutex);
  for(size_t i=0;i<256;i++)CHECK(bp_truthy(bp_await(work[i]))==((i&1)!=0));
  CHECK(atomic_load(&bp_tasks_by_workers)>0);
  bp_pool_stop();
  bp_destroy();
  printf("runtime: %u checks passed; worker tasks=%" PRIu64 "\n",checks,(uint64_t)bp_tasks_by_workers);
  return 0;
}
