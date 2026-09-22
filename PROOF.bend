import Base
import ./LAWS.bend as Laws
import ./compiler/model.bend as M
import ./compiler/lower.bend as Lower
import ./compiler/types.bend as Substitutions
import ./compiler/const_eval.bend as Const
import ./compiler/native_session.bend as Session
import ./compiler/wasm.bend as Wasm

def Laws.pipelined_codegen_keeps_first_failure(error, tail, next, reversed, counts):
  {==}

def Laws.completed_dependency_does_not_join_pending_regions(owner, fuel, head, name, forest):
  {==}

def Laws.cached_scan_preserves_first_failure(error, following):
  {==}

def Laws.blocked_single_group_preserves_progress(scheduled, known, previous, progress):
  match progress:
    case Session.GroupProgress{state, failure}:
      {==}

def Laws.cached_group_cost_skips_body_traversal(cost, known, job):
  {==}

def Laws.small_frontier_skips_pipeline_cost_traversal(ready, known):
  {==}

def Laws.inference_union_same_root_preserves_forest(left, left_rank, right, right_rank, forest, order):
  {==}

def Laws.session_key_failure_preserves_earlier_misses(jobs, previous, selections, missing, error):
  match jobs:
    case Nil{}:
      {==}
    case Session.KeyedEntry{job, encoded} <> tail:
      {==}

def Laws.session_small_frontier_skips_cost_traversal(job, known):
  {==}

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

def Laws.native_trailing_words_fail(words, remaining, offset):
  {==}

def Laws.native_response_failure_keeps_protocol_version():
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

def Laws.preparation_join_preserves_first_error(error, later):
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

def Laws.inference_single_frontier_keeps_its_parallel_batch(chains, ready):
  match ready:
    case Nil{}:
      {==}
    case root <> Nil{}:
      {==}
    case first <> second <> rest:
      {==}

def Laws.inference_single_root_needs_no_partition(chains, root, pending):
  match pending:
    case Nil{}:
      {==}
    case head <> tail:
      {==}

def Laws.inference_chain_never_contracts_a_join(position, consumers):
  {==}

def Laws.inference_chain_never_contracts_a_fanout(position):
  {==}

def Laws.lowering_cost_stops_at_its_bound(nodes, cost):
  {==}

def Laws.lowering_heavy_first_declaration_never_makes_an_empty_half(node):
  {==}

def Laws.session_lowering_join_preserves_first_error(error, later):
  {==}

def Laws.native_empty_string_preserves_cursor(words, offset, remaining):
  {==}

def Laws.native_zero_nat_consumes_exactly_two_words():
  {==}

def Laws.native_string_rejects_surrogate_at_its_offset():
  {==}

def Laws.native_exhausted_buffer_never_wraps(words, offset):
  {==}

def Laws.native_empty_dictionary_rejects_zero_id():
  {==}

def Laws.dependency_siblings_keep_their_depth_budget():
  {==}

def Laws.reachability_counts_the_empty_children_step(catalog, state):
  {==}

def Laws.reachability_leaf_spends_two_steps(catalog, state):
  {==}

def Laws.parallel_linking_keeps_first_failure(error, following):
  {==}

def Laws.nominal_summaries_keep_function_failure_first(error, constants):
  {==}

def Laws.packed_output_keeps_first_failure(error, following):
  match following:
    case Fail{later}:
      {==}
    case Done{packed}:
      {==}

def Laws.parallel_modules_keep_first_failure(error, following, previous):
  {==}

def Laws.wasm_local_lookup_hit_finishes(locals, name, location):
  match locals:
    case Nil{}:
      {==}
    case Wasm.Local{declared, stored} <> tail:
      {==}

def Laws.const_local_lookup_hit_finishes(locals, name, value):
  match locals:
    case Nil{}:
      {==}
    case Const.Binding{declared, stored} <> tail:
      {==}

def Laws.const_declaration_lookup_hit_finishes(constants, name, value):
  match constants:
    case Nil{}:
      {==}
    case M.Constant{declared, exported, annotation, stored} <> tail:
      {==}

def Laws.const_function_lookup_hit_finishes(functions, name, value):
  match functions:
    case Nil{}:
      {==}
    case M.Function{declared, exported, parameter, parameter_type, result_type, body} <> tail:
      {==}
