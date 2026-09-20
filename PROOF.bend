import Base
import ./LAWS.bend as Laws
import ./compiler/model.bend as M
import ./compiler/lower.bend as Lower
import ./compiler/types.bend as Substitutions
import ./compiler/const_eval.bend as Const
import ./compiler/native_request.bend as NativeRequest

def Laws.foreign_is_a_valid_effect_label():
  {==}

def Laws.foreign_cannot_be_declared():
  {==}

def Laws.foreign_cannot_be_supplied_as_an_operation():
  {==}

def Laws.foreign_is_not_a_same_named_source_effect():
  {==}

def Laws.native_key_requires_traversal_fuel():
  {==}

def Laws.native_key_requires_output_room():
  {==}

def Laws.native_runtime_keys_preserve_nominal_identity():
  {==}

def Laws.native_runtime_keys_preserve_operation_forms():
  {==}

def Laws.native_operation_globals_preserve_kind_and_identity():
  {==}

def Laws.native_matching_keys_preserve_columns():
  {==}

def Laws.native_runtime_key_zero_fuel_reports_complexity():
  {==}

def Laws.native_runtime_key_zero_room_fails():
  {==}

def Laws.native_empty_request_fails():
  {==}

def Laws.native_trailing_words_fail(word, tail, offset):
  {==}

def Laws.empty_index_is_absent(V, name):
  {==}

def Laws.empty_index_uses_fallback(V, name, fallback):
  {==}

def Laws.constant_code_is_relocatable(key, parameter, name, captures):
  {==}

def Laws.pure_effect_metadata_is_empty():
  {==}

def Laws.zero_const_budget_fails(expression, context):
  {==}

def Laws.unhandled_const_operations_fail(identity, argument, context):
  {==}

def Laws.closure_bindings_preserve_invocation_providers(context, environment):
  match context:
    case Const.Context{constants, functions, locals, data_types, providers, checked_functions}:
      {==}

def Laws.let_accepts_a_pure_rhs(subject):
  {==}

def Laws.let_rejects_any_runtime_effect(effect, rest, subject):
  match effect:
    case M.OperationEffect{identity}:
      {==}

def Laws.discard_preserves_source_scope(context, internal_name):
  match context:
    case Lower.Context{globals, headers, fixities, locals, return_label}:
      {==}

def Laws.block_return_skips_the_tail(value, next, context):
  {==}

def Laws.match_return_skips_remaining_scrutinees(value, next, context):
  {==}

def Laws.product_projection_selects_first(first, second, steps):
  {==}

def Laws.product_projection_selects_second(first, second, steps):
  {==}

def Laws.product_projection_rejects_length_index(elements, steps):
  match elements:
    case Nil{}:
      {==}
    case head <> tail:
      Laws.product_projection_rejects_length_index(tail, steps)

def Laws.product_retains_mixed_fields(number, flag, context):
  {==}

def Laws.product_return_skips_remaining_elements(value, next, context):
  {==}

def Laws.empty_array_length_is_zero(steps):
  {==}

def Laws.array_read_selects_first(first, tail, steps):
  {==}

def Laws.array_read_rejects_length_index(elements, steps):
  match elements:
    case Nil{}:
      {==}
    case head <> tail:
      Laws.array_read_rejects_length_index(tail, steps)

def Laws.array_set_preserves_other_elements(first, second, replacement):
  {==}

def Laws.array_copy_requires_per_element_budget(first, second, replacement):
  {==}

def Laws.array_return_skips_remaining_elements(value, next, context):
  {==}

def Laws.tuple_pattern_binds_fields_in_order(first, second):
  {==}

def Laws.tuple_pattern_failure_discards_all_bindings(first):
  {==}

def Laws.tuple_pattern_mismatch_skips_pending_fields(next, value):
  {==}

def Laws.tuple_pattern_budget_bounds_total_work():
  {==}

def Laws.tuple_pattern_requires_exact_arity(first, second, third):
  {==}

def Laws.pattern_traversal_exhaustion_is_not_a_failed_match(work):
  {==}

def Laws.tuple_coverage_preserves_correlations():
  {==}

def Laws.tuple_capture_names_follow_nested_field_order(first, second):
  {==}

def Laws.record_fields_keep_written_evaluation_order(first, second, body):
  {==}

def Laws.empty_substitutions_preserve_type(ty, fuel):
  match ty fuel:
    case _ 0n:
      {==}
    case M.UnitTy{} 1n+rest:
      {==}
    case M.U32Ty{} 1n+rest:
      {==}
    case M.F32Ty{} 1n+rest:
      {==}
    case M.BoolTy{} 1n+rest:
      {==}
    case M.NeverTy{} 1n+rest:
      {==}
    case M.AppliedTy{identity, arguments} 1n+rest:
      {==}
    case M.ProductTy{elements} 1n+rest:
      {==}
    case M.ArrayTy{element} 1n+rest:
      {==}
    case M.FunctionTy{parameter, result, effects} 1n+rest:
      {==}
    case M.ParameterTy{index} 1n+rest:
      {==}
    case M.VariableTy{index} 1n+rest:
      {==}
    case M.ProviderTy{identity, effects} 1n+rest:
      {==}
    case M.EffectDescriptorTy{} 1n+rest:
      {==}
    case M.EffectSetTy{} 1n+rest:
      {==}

def Laws.final_substitution_does_not_rewrite_its_replacement(replacement, fuel):
  Laws.empty_substitutions_preserve_type(replacement, 1n+fuel)

def Laws.substitutions_preserve_u32(substitutions, fuel):
  match substitutions:
    case Nil{}:
      {==}
    case Substitutions.Substitution{variable, replacement} <> tail:
      {==}
    case Substitutions.RowSubstitution{variable, replacement} <> tail:
      {==}

def Laws.f32_arithmetic_has_f32_result():
  {==}

def Laws.f32_comparison_has_bool_result():
  {==}

def Laws.f32_to_u32_saturates_overflow(value, overflow):
  Equal.cong(Bool, U32, condition => Bool.pick(U32, condition, 4294967295, F32.to_u32(value)), F32.is_ge(value, 4294967296.0), True{}, overflow)

def Laws.operation_keys_preserve_nominal_boundaries():
  {==}

def Laws.codegen_join_preserves_first_error(error, later):
  {==}

def Laws.codegen_small_batches_are_sequential(entries, weight, grain):
  {==}

def Laws.inference_empty_schedule_has_no_work():
  {==}

def Laws.inference_keeps_the_earlier_failure(first, later):
  {==}

def Laws.inference_without_failure_keeps_pending_work(position):
  {==}

def Laws.lowering_join_preserves_tail_error(earlier, error):
  {==}

def Laws.lowering_small_batches_are_sequential(nodes, count):
  {==}

def Laws.native_empty_string_preserves_cursor(words, offset):
  {==}

def Laws.native_string_rejects_surrogate_at_its_offset():
  {==}

def Laws.native_word_count_successor(words, count):
  match words:
    case Nil{}:
      {==}
    case head <> tail:
      Laws.native_word_count_successor(tail, 1n+count)

def Laws.native_word_count_preserves_the_traversal_bound(words):
  match words:
    case Nil{}:
      {==}
    case head <> +tail:
      Equal.trans(Nat, NativeRequest.word_count(tail, 1n), 1n+NativeRequest.word_count(tail, 0n), 1n+List.length(&2, U32, tail), Laws.native_word_count_successor(tail, 0n), Equal.cong(Nat, Nat, x => 1n+x, NativeRequest.word_count(tail, 0n), List.length(&2, U32, tail), Laws.native_word_count_preserves_the_traversal_bound(tail)))
