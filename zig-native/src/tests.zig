comptime {
    _ = @import("solver_worklist.zig");
    _ = @import("region_arena.zig");
    _ = @import("restart_cache.zig");
    _ = @import("structural.zig");
    _ = @import("diagnostic_code.zig");
    _ = @import("wasm_inline.zig");
    _ = @import("wasm_sroa.zig");
    _ = @import("wasm_row_reduce.zig");
    _ = @import("optimized_archive_tests.zig");
    _ = @import("runtime_parallel_tests.zig");
    _ = @import("machine_code_sharing_tests.zig");
    _ = @import("packed_layout.zig");
    _ = @import("collection_optimization_tests.zig");
    _ = @import("structural_record_tests.zig");
    _ = @import("check_contract_tests.zig");
    _ = @import("collection_tests.zig");
    _ = @import("module_frontend_tests.zig");
    _ = @import("zig_project_frames.zig");
    _ = @import("partial_dependency_tests.zig");
    _ = @import("partial_runtime_tests.zig");
    _ = @import("runtime_operation_tests.zig");
    _ = @import("runtime_operation_backend_tests.zig");
    _ = @import("module_relink_tests.zig");
    _ = @import("unit_coverage_tests.zig");
    _ = @import("layout_bridge.zig");
    _ = @import("dependency_project_consumer_tests.zig");
    _ = @import("dependency_import_resolution_tests.zig");
    _ = @import("frozen_core_validation_tests.zig");
    _ = @import("dependency_closure_tests.zig");
    _ = @import("dependency_interface_tests.zig");
    _ = @import("dependency_format_tests.zig");
    _ = @import("syntax_diagnostics.zig");
    _ = @import("shaped_parameter_tests.zig");
    _ = @import("symbols.zig");
    _ = @import("lexer.zig");
    _ = @import("parser.zig");
    _ = @import("parser_tests.zig");
    _ = @import("types.zig");
    _ = @import("principal_type_graph.zig");
    _ = @import("nominal_argument_borrow_tests.zig");
    _ = @import("solver_scratch_tests.zig");
    _ = @import("check.zig");
    _ = @import("check_hole_tests.zig");
    _ = @import("check_alias_tests.zig");
    _ = @import("check_tests.zig");
    _ = @import("tag_tests.zig");
    _ = @import("check_loop_tests.zig");
    _ = @import("check_result_tests.zig");
    _ = @import("check_demand_tests.zig");
    _ = @import("check_monad_tests.zig");
    _ = @import("effects_tests.zig");
    _ = @import("provider_chain.zig");
    _ = @import("check_effect_tests.zig");
    _ = @import("check_open_row_tests.zig");
    _ = @import("check_where_tests.zig");
    _ = @import("check_pattern_tests.zig");
    _ = @import("qualified_evidence_tests.zig");
    _ = @import("owned_arrays_tests.zig");
    _ = @import("wasm.zig");
    _ = @import("memory.zig");
    _ = @import("project.zig");
    _ = @import("project_check_tests.zig");
    _ = @import("core.zig");
    _ = @import("core_tests.zig");
    _ = @import("core_aggregate_tests.zig");
    _ = @import("core_closure_tests.zig");
    _ = @import("core_array_tests.zig");
    _ = @import("core_callable_tests.zig");
    _ = @import("core_loop_tests.zig");
    _ = @import("core_update_tests.zig");
    _ = @import("core_demand_tests.zig");
    _ = @import("core_monad_tests.zig");
    _ = @import("loop_targets_tests.zig");
    _ = @import("core_eval.zig");
    _ = @import("core_eval_tests.zig");
    _ = @import("core_operation_evidence_tests.zig");
    _ = @import("builtin_state_tests.zig");
    _ = @import("reflection_tests.zig");
    _ = @import("scalar_ops.zig");
    _ = @import("pipeline_tests.zig");
    _ = @import("project_pipeline_tests.zig");
    _ = @import("project_prelude_tests.zig");
    _ = @import("check_request_tests.zig");
    _ = @import("core_request_tests.zig");
    _ = @import("request_backend_tests.zig");
    _ = @import("parser_binder_tests.zig");
    _ = @import("parser_identifier_tests.zig");
}

comptime {
    _ = @import("proof_reuse_tests.zig");
}

comptime {
    _ = @import("entry_diagnostic_tests.zig");
}

comptime {
    _ = @import("value_pattern_scope_tests.zig");
}

comptime {
    _ = @import("parser_adjacent_call_tests.zig");
}

comptime {
    _ = @import("discarded_bindings_tests.zig");
}

comptime {
    _ = @import("callback_row_tests.zig");
    _ = @import("qualified_row_tests.zig");
}

comptime {
    _ = @import("record_payload_tests.zig");
}

test {
    _ = @import("canonical_constructor_tests.zig");
}

comptime {
    _ = @import("associated_catalog_tests.zig");
    _ = @import("product_projection_tests.zig");
}

comptime {
    _ = @import("retained_capture_tests.zig");
}

comptime {
    _ = @import("captured_callable_tests.zig");
}

test {
    _ = @import("annotation_arity_tests.zig");
}

test {
    _ = @import("source_operators_tests.zig");
    _ = @import("contextual_pattern_tests.zig");
}

test {
    _ = @import("fixity_core_tests.zig");
}

test {
    _ = @import("resolution_cache_tests.zig");
    _ = @import("closed_graph_tests.zig");
}

test {
    _ = @import("array_limit_tests.zig");
}

test {
    _ = @import("let_fallback_tests.zig");
}

test {
    _ = @import("bottom_binding_tests.zig");
}

test {
    _ = @import("bottom_flow_tests.zig");
}

test {
    _ = @import("effect_span_tests.zig");
    _ = @import("effect_unification_tests.zig");
    _ = @import("parser_use_tests.zig");
}

test {
    _ = @import("source_order_tests.zig");
}

comptime {
    _ = @import("source_input_tests.zig");
    _ = @import("entry_interface_order_tests.zig");
    _ = @import("numeric_phase_tests.zig");
    _ = @import("startup_dependency_tests.zig");
}

comptime {
    _ = @import("initializer_purity_tests.zig");
    _ = @import("purity_type_key_tests.zig");
}

comptime {
    _ = @import("dependency_cli_tests.zig");
}

comptime {
    _ = @import("dependency_publication_tests.zig");
}

test {
    _ = @import("prepared_revision_tests.zig");
}
comptime {
    _ = @import("artifact_emitter_tests.zig");
    _ = @import("artifact_backend_tests.zig");
    _ = @import("code_artifacts_tests.zig");
}

test {
    _ = @import("principal_reuse_gate_tests.zig");
    _ = @import("principal_import_tests.zig");
    _ = @import("principal_evidence_reuse_tests.zig");
}

comptime {
    _ = @import("startup_graph_tests.zig");
}

comptime {
    _ = @import("selected_startup_tests.zig");
    _ = @import("named_closure_parameter_tests.zig");
}

comptime {
    _ = @import("deferred_method_parity_tests.zig");
    _ = @import("selected_entry_parity_tests.zig");
}

comptime {
    _ = @import("revision_input_tests.zig");
    _ = @import("startup_occurrence_plan_tests.zig");
    _ = @import("startup_occurrence_flow_tests.zig");
    _ = @import("startup_query_composition_tests.zig");
}

comptime {
    _ = @import("entry_phase_parity_tests.zig");
    _ = @import("demanded_mismatch_tests.zig");
}

comptime {
    _ = @import("member_origin_index_tests.zig");
    _ = @import("retained_candidate_tests.zig");
}

comptime {
    _ = @import("fallback_check_sharing_tests.zig");
}

comptime {
    _ = @import("fallback_core_reuse_tests.zig");
}
comptime {
    _ = @import("checked_core_freeze_tests.zig");
}

comptime {
    _ = @import("alias_project_tests.zig");
}

comptime {}

test {
    _ = @import("plain_catalog_tests.zig");
    _ = @import("source_value_template_tests.zig");
    _ = @import("projection_cache_tests.zig");
    _ = @import("principal_input_tests.zig");
}

comptime {
    _ = @import("entry_frontend_cutoff_tests.zig");
    _ = @import("source_overlay_tests.zig");
    _ = @import("zig_project_server.zig");
}

test {
    _ = @import("artifact_import_tests.zig");
    _ = @import("optimized_bodies_tests.zig");
    _ = @import("principal_archive_tests.zig");
    _ = @import("artifact_operation_admission_tests.zig");
    _ = @import("buffered_stamp_tests.zig");
    _ = @import("check_nominal_tests.zig");
    _ = @import("check_shared_scheme_tests.zig");
    _ = @import("core_dispatch_tests.zig");
    _ = @import("retained_catalog_tests.zig");
    _ = @import("startup_emission_facts_tests.zig");
}
