import Base
import ./LAWS.bend as Laws
import ./compiler/model.bend as M
import ./compiler/lower.bend as Lower
import ./compiler/types.bend as Substitutions
import ./compiler/const_eval.bend as Const
import ./compiler/native_session.bend as Session
import ./compiler/wasm.bend as Wasm
import ./compiler/patterns.bend as Patterns
import ./compiler/monomorph.bend as Mono
import ./compiler/dependency.bend as Dependency
import ./compiler/infer.bend as Infer

def Laws.declaration_tag_preserves_origin_and_operands(offset, function, value):
  {==}

def Laws.declaration_tag_reachability_includes_both_operands(offset, function, value):
  {==}

def Laws.empty_declaration_tags_preserve_initializer(value, fuel, scope):
  {==}

def Laws.checked_public_wrapper_calls_stored_constant(name, input, output, variables, row):
  {==}

def Laws.dependency_membership_hit_finishes(remaining):
  {==}

def Laws.empty_dependency_graph_has_no_components():
  {==}

def Laws.singleton_dependency_graph_is_one_component(name, references, lambdas):
  {==}

def Laws.seen_dependency_enter_does_not_expand_neighbors(name, edges, pending):
  {==}

def Laws.seen_dependency_reach_does_not_expand_neighbors(edges, name, pending):
  {==}

def Laws.mono_rename_keeps_first_found(tail, wanted, specialized):
  match tail:
    case Nil{}:
      {==}
    case Mono.Rename{original, renamed} <> rest:
      {==}

def Laws.mono_function_keeps_first_found(tail, wanted, function):
  match tail:
    case Nil{}:
      {==}
    case M.Function{name, exported, parameter, p, r, body} <> rest:
      {==}

def Laws.mono_constant_keeps_first_found(tail, wanted, constant):
  match tail:
    case Nil{}:
      {==}
    case M.Constant{name, exported, annotation, expression} <> rest:
      {==}

def Laws.mono_local_template_keeps_first_found(tail, wanted, value):
  match tail:
    case Nil{}:
      {==}
    case Mono.LocalTemplate{name, expression} <> rest:
      {==}

def Laws.mono_effect_family_keeps_first_found(tail, wanted, declaration):
  match tail:
    case Nil{}:
      {==}
    case M.Operation{identity, parameter, result} <> rest:
      {==}
    case M.OperationTemplate{identity, parameters, parameter, result} <> rest:
      {==}
    case M.OperationInstance{template, arguments} <> rest:
      {==}

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

def Laws.native_emit_compiles_like_compile():
  {==}

def Laws.native_emit_replies_wasm_only():
  {==}

def Laws.native_wasm_only_reply_omits_analysis(analysis):
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

def Laws.runtime_initializers_preserve_const_budget(expression, steps, context):
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
    case Lower.Context{globals, headers, fixities, locals, return_label, annotation_variables}:
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
    case M.FreeTy{scope, name} 1n+rest:
      {==}
    case M.ParameterTy{index} 1n+rest:
      {==}
    case M.VariableTy{index} 1n+rest:
      {==}
    case M.ProviderTy{identity, effects} 1n+rest:
      {==}
    case M.StateProviderTy{read, write, state} 1n+rest:
      {==}
    case M.EffectDescriptorTy{} 1n+rest:
      {==}
    case M.EffectSetTy{} 1n+rest:
      {==}

def Laws.final_substitution_does_not_rewrite_its_replacement(replacement, fuel):
  Laws.empty_substitutions_preserve_type(replacement, 1n+fuel)

def Laws.substitutions_preserve_u32(substitutions, fuel):
  match substitutions:
    case Substitutions.Substitutions{history, values, rows, 0n}:
      {==}
    case Substitutions.Substitutions{history, values, rows, 1n+count}:
      {==}

def Laws.flat_resolver_step_exhaustion_restarts_reference(substitutions, fuel, work):
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

def Laws.value_pattern_preserves_local_reference(name, node):
  {==}

def Laws.value_pattern_is_refutable(head, reference, tail):
  match head:
    case Patterns.UnitHead{}:
      {==}
    case Patterns.BoolHead{value}:
      {==}
    case Patterns.ConstructorHead{name, payload}:
      match payload:
        case True{}:
          {==}
        case False{}:
          {==}
    case Patterns.ProductHead{arity}:
      {==}
    case Patterns.DefaultHead{}:
      {==}

def Laws.empty_array_fill_preserves_budget(value, steps):
  {==}

def Laws.array_fill_rejects_oversized_count(count, value, steps):
  {==}

def Laws.empty_array_generation_skips_callback(steps, generator, context):
  match steps:
    case Const.Budget{0n, cells}:
      {==}
    case Const.Budget{1n+rest, cells}:
      {==}

def Laws.associated_left_precedence(left, right, name, other, subject, description):
  {==}

def Laws.associated_call_preserves_operands(name, member, left, right, signature):
  {==}

def Laws.rebinding_self_uses_previous_local(core, context, node):
  {==}

def Laws.state_scope_returns_successor(current, result, steps, outer):
  {==}

def Laws.state_scope_preserves_nonlocal_return(current, result, label, steps, outer):
  {==}

def Laws.shared_array_is_not_consumed(last, end):
  {==}

def Laws.unknown_array_storage_is_not_owned(name, usages, end):
  {==}

def Laws.array_reuse_preserves_operand_order(array, index, value):
  {==}

def Laws.retained_core_comparison_stops_on_mismatch(fuel, pending):
  match fuel pending:
    case 0n Nil{}:
      {==}
    case 0n head <> tail:
      {==}
    case 1n+rest Nil{}:
      {==}
    case 1n+rest head <> tail:
      {==}

def Laws.retained_core_comparison_exhaustion_is_a_miss(head, tail):
  {==}

def Laws.retained_group_skips_reinference(position, checked):
  {==}

def Laws.ordinary_catalog_does_not_collect_certificates(module):
  match module:
    case M.Module{constants, functions, types, operations}:
      {==}

def Laws.evidenced_group_keeps_exact_source_and_imports(position, module, imports, cost):
  {==}

def Laws.residual_renaming_preserves_operation_labels(operations, tail, mapping):
  {==}

def Laws.parameter_mapping_keeps_first_binder(previous, head, index, mapping):
  {==}

def Laws.empty_generic_scheme_needs_no_traversal(ty, next):
  {==}

def Laws.retained_group_cannot_discard_all_functions(function, rest):
  {==}

def Laws.frontier_comparison_stops_on_mismatch(fuel, pending, delta):
  match fuel pending:
    case 0n Nil{}:
      {==}
    case 0n head <> tail:
      {==}
    case 1n+rest Nil{}:
      {==}
    case 1n+rest head <> tail:
      {==}

def Laws.frontier_comparison_exhaustion_is_a_miss(head, tail, delta):
  {==}

def Laws.frontier_failure_checks_the_current_task(diagnostic, task):
  {==}

def Laws.frontier_reuse_excludes_retained_tasks(position, checked):
  {==}

def Laws.pending_cache_preserves_requirements(count, needs):
  {==}

def Laws.empty_pending_change_has_no_requirements(change):
  {==}

def Laws.different_qualified_site_stays_pending(predicate, selected):
  {==}

def Laws.unknown_choice_change_uses_full_refresh(selected, cache):
  {==}

def Laws.empty_coverage_preserves_pending_tail(choices, rest):
  {==}

def Laws.empty_fresh_prefix_preserves_pending_tail(definitions, choices, rest):
  {==}

def Laws.invalid_pending_prefix_uses_full_scan(selected, count, prior_count, definitions, prior_needs, choices):
  {==}

def Laws.global_binding_repeat_reference_keeps_selection(name, index, selection):
  {==}

def Laws.empty_global_references_select_no_bindings(index):
  {==}

def Laws.global_declaration_lookup_keeps_first_match(rest, name, declaration):
  match rest:
    case Nil{}:
      {==}
    case head <> tail:
      {==}

def Laws.dependency_membership_work_stops_after_hit(rest, name):
  match rest:
    case Nil{}:
      {==}
    case head <> tail:
      {==}

def Laws.state_membership_work_stops_after_hit(rest, identity):
  match rest:
    case Nil{}:
      {==}
    case M.Operation{known, parameter, result} <> tail:
      {==}
    case M.OperationTemplate{known, parameters, parameter, result} <> tail:
      {==}
    case M.OperationInstance{template, arguments} <> tail:
      {==}

def Laws.dependency_lookup_stops_after_match(rest, name, found):
  match rest:
    case Nil{}:
      {==}
    case Dependency.Node{node_name, references, lambdas} <> tail:
      {==}

def Laws.definition_predicates_stop_after_match(rest, name, found):
  match rest:
    case Nil{}:
      {==}
    case Infer.Definition{definition_name, inference} <> tail:
      {==}

def Laws.empty_operation_merge_preserves_catalog(operations):
  match operations:
    case Nil{}:
      {==}
    case head <> tail:
      {==}

def Laws.zero_distance_index_advance_preserves_suffix(suffix):
  {==}

def Laws.variable_membership_work_stops_after_hit(rest, variable):
  match rest:
    case Nil{}:
      {==}
    case head <> tail:
      {==}

def Laws.failed_parallel_commit_replays_serial_inference(declarations, environment, operations, types, functions, catalog):
  {==}

def Laws.rejected_staging_scheme_does_not_replay(scheme, clone, parsed, stride, environment):
  {==}

def Laws.shared_nominal_catalog_reuses_sorted_list(shared, common):
  match shared:
    case MTip{}:
      {==}
    case MLeaf{key, value}:
      {==}
    case MNode{position, left, right}:
      {==}

def Laws.sorted_nominal_merge_keeps_common_without_new_types(common):
  match common:
    case Nil{}:
      {==}
    case head <> tail:
      {==}


def Laws.exhausted_schema_reduction_is_a_miss(work):
  {==}

def Laws.rejected_schema_source_is_a_miss(left, witness, proof):
  {==}

def Laws.schema_hit_still_validates_tail(fuel, tail, wanted, proof, answer):
  {==}

def Laws.missing_schema_choice_uses_ordinary_selection(need, left, right, specialization, configuration, shapes, schemes):
  {==}

def Laws.dispatch_inference_variable_is_open(fuel, index, tail):
  {==}

def Laws.dispatch_generalized_variable_is_open(fuel, index, tail):
  {==}

def Laws.dispatch_open_effect_row_is_open(fuel, parameter, result, operations, index, tail):
  {==}

def Laws.dispatch_type_identity_is_not_plain():
  {==}

def Laws.dispatch_unknown_receiver_waits(index):
  {==}

def Laws.dispatch_dropped_requirement_changes_nothing(need, solving):
  {==}

def Laws.dispatch_unplanned_site_stays_deferred(identity, dispatch, member, templates, left, right):
  {==}

def Laws.dispatch_conflicting_requirements_rewrite_neither(choice):
  {==}

def Laws.dispatch_binary_site_calls_selected_implementation(identity, member, templates, left, right, name, signature):
  {==}

def Laws.dispatch_receiver_site_applies_selected_member(identity, member, templates, receiver, unit, name, signature):
  {==}

def Laws.dispatch_resolved_site_is_not_a_seed(left, right, name):
  {==}

def Laws.dispatch_field_accessor_is_shared(owner, member):
  {==}

def Laws.dispatch_field_update_accessor_is_shared(owner, member):
  {==}

def Laws.dispatch_duplicate_accessor_keeps_first(function, reversed):
  {==}

def Laws.dispatch_failed_round_abandons_resolution(fuel, module, diagnostic, next, proofs, cache, budget, entry, source, partial, inferred, retained):
  {==}

def Laws.dispatch_unchanged_round_keeps_its_check(fuel, initial, module, certificates, next, cache, stable, proofs, budget, entry, source):
  {==}

def Laws.dispatch_stable_rewrite_skips_verification(fuel, initial, module, certificates, next, cache, proofs, budget, entry, source):
  {==}

def Laws.dispatch_group_without_resolutions_is_stable(state, waiting, progress, members, generalized, next):
  {==}

def Laws.dispatch_changed_local_scheme_is_checked_again(unchanged):
  {==}

def Laws.dispatch_let_generalized_binding_changes_its_scheme(group, replacement):
  {==}

def Laws.dispatch_group_variable_must_not_name_let_generalized(replacement):
  {==}

def Laws.dispatch_fresh_instance_may_name_let_generalized(replacement):
  {==}

def Laws.dispatch_group_without_let_generalization_keeps_schemes(substitutions, next):
  {==}

def Laws.dispatch_unchanged_schemes_defer_to_interfaces(unchanged):
  {==}

def Laws.let_generalization_evidence_is_not_a_pattern_constraint(witness, tail, substitutions, types):
  {==}

def Laws.let_generalization_evidence_is_not_a_requirement(witness, tail):
  {==}

def Laws.let_without_generalization_records_no_evidence(coverage, substitutions):
  {==}

def Laws.dispatch_unresolved_module_specializes_original(module, entry, family_templates):
  {==}

def Laws.evidence_check_certifies_retained_groups(position, subset, imports, checked):
  {==}


def Laws.entry_modifier_rejects_other_identifiers(entry_module, node):
  match entry_module:
    case True{}:
      {==}
    case False{}:
      {==}

def Laws.entry_outside_entry_module_is_rejected(node):
  {==}

def Laws.entry_in_entry_module_is_exported(node):
  {==}

def Laws.declaration_without_modifier_is_not_exported(entry_module):
  {==}

def Laws.exported_function_is_an_entry(name, parameter, p, r, body):
  {==}

def Laws.runtime_constant_is_an_entry_let(name, annotation, value):
  {==}

def Laws.non_entry_constant_is_not_an_entry(name, annotation, value):
  {==}

def Laws.unreached_function_is_pruned(name, exported, parameter, p, r, body):
  {==}

def Laws.unreached_constant_is_pruned(name, exported, annotation, value):
  {==}

def Laws.pruning_keeps_operations(constants, functions, types, operations, seen):
  {==}

def Laws.entry_owner_prefix_matches_specialization(identity, entry):
  match identity:
    case M.TypeId{module_name, declaration}:
      {==}

def Laws.dispatch_failed_pruning_abandons_resolution(diagnostic, next, entry, source):
  {==}

def Laws.build_without_entries_fails(types, operations):
  {==}

def Laws.no_entries_verify(checked):
  match checked:
    case M.CheckedModule{constants, functions, types, operations}:
      {==}

def Laws.unused_operation_has_no_wasm_job(identity, parameter, result):
  {==}

def Laws.dispatch_original_failure_is_authoritative(diagnostic, certificates, inferred, retained, module, entry):
  {==}

def Laws.inlined_operator_retains_source_and_creation_site(offset, site, value):
  {==}

def Laws.dispatch_transformed_failure_preserves_certificates(diagnostic, certificates, inferred, retained, module, next, entry, source):
  {==}

def Laws.failed_initial_assembly_preserves_completed_groups(diagnostic, certificates, needs, inferred, retained):
  {==}

def Laws.qualified_rename_shares_type_and_row_mapping(mapping, type_index, row_index, labels):
  {==}

def Laws.qualified_parameterize_preserves_row_multiplicity(mapping, index, labels):
  {==}

def Laws.qualified_relocate_free_row_scope_only(scope, name, suffix, labels):
  {==}

def Laws.qualified_occurrence_site_is_not_a_predicate(site, subject, ty, predicate):
  {==}

def Laws.qualified_root_uses_reserved_creation_lane(offset, value):
  {==}

def Laws.unexported_qualified_declaration_has_no_root_demand(offset, value):
  {==}

def Laws.scc_creation_site_keeps_peer_obligation(site, subject, ty, predicate):
  {==}

def Laws.scc_effect_reflection_creates_no_callable_site(name):
  {==}

def Laws.scc_raw_core_reference_keeps_dependency_without_inventing_site(name):
  {==}

def Laws.scc_qualified_reference_keeps_nearest_boundary(offset, site, name):
  {==}

def Laws.scc_other_boundary_cannot_satisfy_local_clause(site, name, predicate):
  {==}

def Laws.raw_core_rejects_nonempty_qualification(offset):
  {==}

def Laws.raw_core_accepts_empty_qualification(value):
  {==}

def Laws.imported_scheme_rejects_mixed_parameter_kinds(subject):
  {==}

def Laws.const_instantiation_metadata_is_free(site, value, depth, steps, context):
  {==}

def Laws.const_qualified_metadata_is_free(offset, annotation, predicates, value, depth, steps, context):
  {==}

def Laws.loop_memory_pure_closed_row_is_isolated():
  {==}

def Laws.loop_memory_foreign_closed_row_is_isolated():
  {==}

def Laws.loop_memory_open_row_is_not_isolated(operations, index):
  {==}

def Laws.loop_memory_source_state_is_not_isolated():
  {==}

def Laws.dispatch_fallback_reuses_checked_source(transformed, module, initial, source):
  {==}

def Laws.dispatch_without_sites_reuses_checked_source(seen, unique, module, inlined, initial, original, entry, source):
  match unique:
    case True{}:
      {==}
    case False{}:
      {==}

def Laws.certificate_type_index_keeps_first_identity():
  {==}

def Laws.certificate_operation_index_keeps_first_identity():
  {==}

def Laws.retained_resolving_task_keeps_requirements(position, module, imports, checked, needs):
  {==}

def Laws.conflicting_resolving_association_cannot_certify(certificate):
  {==}


def Laws.seen_compact_dependency_enter_does_not_expand_neighbors(identity, edges, pending):
  {==}


def Laws.unknown_compact_dependency_reference_is_omitted(tail):
  {==}

def Laws.specialization_without_inference_ignores_shape_failure(expanded, configuration, shapes, isolated, schemes, diagnostic):
  {==}

def Laws.protected_selected_row_preserves_state(index, state):
  {==}

def Laws.selected_signature_collects_only_flexible_effect_tail(value, row, parameter, labels, scope, name):
  {==}

def Laws.closing_selected_tail_preserves_duplicate_operations(operation):
  {==}


def Laws.runtime_array_byte_count_does_not_wrap():
  {==}

def Laws.runtime_memory_uses_wasm32_page_range():
  {==}

def Laws.saturated_partial_application_is_not_expanded(key, left, right, body, argument):
  {==}

def Laws.saturated_known_head_uses_direct_call(name, argument):
  {==}

def Laws.saturated_compaction_loop_is_not_inlineable(state, initial, body):
  {==}

def Laws.saturated_counted_loop_is_not_inlineable(index, start, end, state, initial, body):
  {==}
