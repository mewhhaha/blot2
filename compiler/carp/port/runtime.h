#ifndef BLOT_CARP_PORT_RUNTIME_H
#define BLOT_CARP_PORT_RUNTIME_H
/* Generic value/ownership primitives and byte transport for generated Carp.
 * No Blot parsing, type checking, evaluation, or Wasm lowering lives here. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
typedef long Long;
_Static_assert(sizeof(Long)==8, "The Carp semantic port requires 64-bit Long");
#include "tables.h"
typedef struct BPObj BPObj;
typedef struct {Long (*code)(Long*); uint32_t slots, arity, captures; const char *name;} BPFunction;
typedef struct {const uint16_t *text; size_t length; BPObj *cached;} BPLiteral;
typedef struct {uint32_t tag, count; const uint32_t *keys; BPObj *cached;} BPShape;
extern const BPFunction bp_functions[BP_FUNCTIONS];
extern BPLiteral bp_literals[BP_LITERALS];
extern BPShape bp_shapes[BP_SHAPES];
Long bp_get(Long*,int); void bp_put(Long*,int,Long); Long bp_assign(Long*,int,Long);
Long bp_local_field(Long*,int,int); Long bp_local_tag(Long*,int,int);
Long bp_retain(Long); void bp_release(Long);
/* Scalars never own storage. Keep the no-op path in the calling unit rather
 * than making an out-of-line ownership call for every number/Bool/empty slot. */
static inline bool bp_is_pointer(Long value) {
  return ((uint64_t)value & UINT64_C(0xffff000000000000)) == UINT64_C(0x7ff9000000000000);
}
static inline Long bp_keep(Long value) {
  return bp_is_pointer(value) ? bp_retain(value) : value;
}
static inline void bp_drop(Long value) {
  if (bp_is_pointer(value)) bp_release(value);
}
bool bp_truthy(Long);
Long bp_literal(int); Long bp_function(int); Long bp_field(Long,int);
Long bp_binary(int,Long,Long); Long bp_not(Long); Long bp_neg(Long); Long bp_bitnot(Long);
Long bp_codepoint(Long,Long); Long bp_index(Long,Long); Long bp_set_index(Long,Long,Long);
Long bp_slice0(Long); Long bp_slice1(Long,Long); Long bp_slice2(Long,Long,Long); Long bp_spread(Long);
Long bp_nat_chk(Long); Long bp_u32_to_word(Long); Long bp_word_to_u32(Long);
Long bp_char_new(Long); Long bp_cmp_new(Long,Long); Long bp_nat_divmod(Long,Long);
Long bp_array_new(Long,Long); Long bp_f32_bits(Long); Long bp_f32_from_bits(Long); Long bp_f32_read(Long);
Long bp_run_clo(Long); Long bp_run_loop(Long); Long bp_run_tail(Long,Long);
Long bp_math_imul(Long,Long); Long bp_math_fround(Long); Long bp_math_floor(Long); Long bp_math_abs(Long);
Long bp_math_sqrt(Long); Long bp_math_ceil(Long); Long bp_math_trunc(Long);
Long bp_unreachable(void); void bp_unreachable_unit(void);
void bp_handshake(Long); Long bp_receive(void); Long bp_request_length(void); void bp_send(Long); bool bp_has_frame(Long);
Long bp_future2(int,Long,Long); Long bp_await(Long);
Long bp_callthen(int,int,Long,int,Long*);
Long bp_tailcall(int,int,Long*); Long bp_tailapply(Long,int,Long*);
Long bp_call(int,int,Long*); Long bp_apply(Long,int,Long*); Long bp_closure(int,int,Long*); Long bp_record(int,int,Long*);
void bp_destroy(void);
#include "calls.h"
#endif
