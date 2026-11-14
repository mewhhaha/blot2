# Delete the scoped backend

Owner decision (14 November 2026): the direct backend (tasks/FAST_COMPILE.md)
becomes the only backend. The scoped backend and everything built only to
serve it are deleted, and then tasks/LANGUAGE_COHERENCE.md follows.

## Scope

| Tree | Lines | Fate |
| --- | ---: | --- |
| `compiler/src/backend/` | 81,406 | Deleted. The checker needs eight of its modules (`collection_ops`, `scalar_ops`, `simd_intrinsics`, `opaque_storage`, `loop_targets`, `function_facts`, `runtime_identity`, `wasm`); move them to a neutral place or cut the dependency. |
| `compiler/src/eval/` | 33,064 | Deleted. Only `backend/` imports it. |
| `compiler/src/runtime/` | 5,897 | Deleted. It is the scoped runtime, built on `backend/wasm.zig`. |
| `compiler/src/reuse/` | 67,630 | Keep the project server and the checker's interface reuse. Delete the archives, checkpoints, optimized bodies and retained candidates. |

## Measuring the gap

```
cd compiler && zig build install -Doptimize=fast -Dllvm=false \
  -Ddirect-default=true --prefix zig-out-direct
cd .. && deno test -A --parallel --junit-path=J.xml tests/guest tests/host -- \
  compiler/zig-out-direct/bin/blotc
python3 scripts/integration/direct_guest_gap.py J.xml inventory.json
```

`-Ddirect-default` and the classifier are temporary; delete them with the
scoped backend. Some guest files hardcode `compiler/zig-out-dev/bin/blotc` and
so still test that binary.

Baseline at 51536924: 771 of 1,990 guest cases pass on the direct default.

## Decisions by category

Case counts are from the baseline run.

| Category | Cases | Files | Action |
| --- | ---: | ---: | --- |
| Scoped internal (work counters, checkpoints, optimizer stats, restart artifacts) | 218 | 87 | Delete those assertions or tests with the code. |
| Type inference gaps (open variables at closures, arrays, blocks, calls) | 174 | 82 | Implement in the direct backend. |
| Providers and effect operations (`handle`, `effect_provider`, `state_provider`, `operation_value`) | 115 | 44 | Implement: B1 keeps them. |
| Run-time mismatches (traps, signature mismatches, wrong values) | 114 | 56 | Investigate each. Some are the retired snapshot semantics (LANGUAGE_COHERENCE A7). |
| Other | 94 | 50 | Review per file. |
| Constant exports (`entry const`, modules exporting no functions) | 89 | 42 | Implement the ABI 8 constant exports. |
| Diagnostics the scoped backend produced (`entry_type`, `const_panic`, `missing_associated`, `invalid_annotation`, `ownership_unproved`, ...) | 73 | 41 | Move each to the checker, or to the direct backend where it is about code generation. |
| Request handlers (B3) | 66 | 20 | Delete tests. |
| Effect identities and reflection (B3) | 54 | 21 | Delete tests. |
| Typed staging (C8) | 46 | 13 | Delete tests. The `#run` redesign replaces it. |
| Usage contracts and resources (C8) | 33 | 17 | Delete tests. (*) |
| Traits redesign (`contract_method`) | 31 | 8 | Keep as requirements; rewrite for the trait design. |
| Polymorphic packages (C8) | 28 | 15 | Delete tests. |
| Monads and resolvers (B3) | 26 | 6 | Delete tests. |
| Other unsupported forms | 21 | 14 | Implement or reclassify. |
| Recursive data types | 9 | 2 | Implement (box the recursive positions). |
| Language tasks (retired) | 8 | 5 | Delete tests. |
| Entry ABI forms (`never` / tuple results, function parameters) | 7 | 3 | Implement or reject in the checker. |
| Erased proofs (C8) | 6 | 2 | Delete tests. |
| Type values and witnesses (C3/C4) | 5 | 3 | Delete tests. |

(*) `@resource.acquire` / `release` are documented with the usage contracts
(docs/compiler/USAGE_CONTRACTS.md, check/usage_core.zig). Retiring them with
`@usage.*` is this task's reading of C8; the owner has not ruled on it
separately.

For dropped features, only the tests go in this task; the language phase
removes the parser and checker support. Until then the direct backend reports
those forms as unsupported. A test that mixes a dropped feature with kept
behaviour keeps the kept part.

## Changes that land with the default flip

- `array_snapshot` expects 40, not 22, in tests/guest/entry_execution.test.ts
  and tests/guest/development_tier.test.ts. Writes through an alias are
  visible (LANGUAGE_COHERENCE A7); the scoped backend still returns 22.
- `const_panic`: constants are computed at instantiation, so a panicking
  constant traps there. Tests expecting the compile-time diagnostic change to
  expect an instantiation trap.
- Exports without complete signatures (numeric-literal defaulting, as in
  `entry const increment = func value => return value + 1`) are `entry_type`
  errors on the direct backend (FAST_COMPILE decision 2). The examples are
  annotated; tests that rely on the defaulting are rewritten with signatures.
- Mixed-operand dispatch (`@type.call` falling back to the right operand's
  owner) goes with the traits redesign: a trait dispatches on one type.

## Order

1. Implement the kept gaps in the direct backend: constant exports, entry ABI
   forms, inference gaps, providers and effect operations, recursive data, and
   the remaining forms. Investigate the run-time mismatches.
2. Move the diagnostics the scoped backend produced.
3. Delete the tests of dropped features and of scoped internals.
4. Make the direct backend the default, then delete `backend/` (after moving
   the checker's shared modules), `eval/`, `runtime/`, the scoped parts of
   `reuse/`, the outlining and plan machinery, and their native tests. Update
   `check:dev` areas and `test:compiler`.
5. Release tier: the direct output, optionally run through `wasm-opt`. First
   measure Gdev's run-time frame cost against the scoped build.

Each step runs Ink (`pen test-blot`, all 64 modules matching) and Gdev Main's
Pen frame (frame.png 19a03f0a…, frames.trace 86d50101…) before pushing.

## Inventory at the baseline

Each failing file is listed under its most frequent category, with its number
of failing cases.

### scoped internal (76 files)

`addressed_input_execution` 16, `source_proof_dag_execution` 12, `projected_parameter_execution` 8, `completed_plain_execution` 6, `numeric_curried_execution` 6, `owner_graph_execution` 6, `parameter_copy_execution` 6, `completed_context_execution` 4, `concrete_fields_execution` 4, `general_cache_execution` 4, `opaque_implementation_cutoff_execution` 4, `opaque_public_contract_cutoff_execution` 4, `opaque_storage_cutoff_execution` 4, `static_constructor_fields_execution` 4, `storage_created_span_execution` 4, `storage_inline_registers_execution` 4, `storage_machine_regions_execution` 4, `storage_result_alias_execution` 4, `cli_profile` 3, `opaque_associated_cutoff_execution` 3, `safe_local_sinking_execution` 3, `scoped_assembly_options_execution` 3, `specialization_origin` 3, `aggregate_transport_execution` 2, `associated_pure_clause_execution` 2, `body_general_receipts` 2, `deferred_join_execution` 2, `deferred_named_capture_execution` 2, `direct_input_execution` 2, `fixed_scalar_spans_execution` 2, `fresh_owner_return_execution` 2, `function_plan_execution` 2, `global_call_execution` 2, `identity_join_execution` 2, `immutable_survivor_execution` 2, `input_alias_execution` 2, `list_leaf_execution` 2, `module_abstraction_import_execution` 2, `module_cutoff_all_dirty_execution` 2, `mutating_owner_return_execution` 2, `numeric_bit_identity_execution` 2, `numeric_finite_composition_execution` 2, `owned_word_execution` 2, `packed_input_execution` 2, `prepared_reader_arguments_execution` 2, `scoped_aggregate_reader_execution` 2, `scoped_literal_data_execution` 2, `scoped_selected_fields_execution` 2, `semantic_jobs_execution` 2, `storage_bulk_loops_execution` 2, `storage_call_graph_execution` 2, `storage_emission_work_execution` 2, `storage_inline_witnesses_execution` 2, `storage_lane_loop_execution` 2, `storage_literal_projection_execution` 2, `storage_local_compaction_execution` 2, `storage_merge_loop_execution` 2, `storage_nominal_fields_execution` 2, `storage_nominal_parameter_fields_execution` 2, `storage_planner_context_execution` 2, `storage_refinement_index_execution` 2, `storage_scalar_replacements_execution` 2, `storage_stride_reduce_execution` 2, `backend_checkpoint` 1, `bit_recurrence_execution` 1, `canonical_specialization_execution` 1, `collection_successor_execution` 1, `compilation_tiers` 1, `cursor_directory_execution` 1, `dependency_owner_memo` 1, `eager_row_reduction_execution` 1, `optimized_body_worklist_execution` 1, `rank_inferred_predicates_portable_execution` 1, `reductions_revision` 1, `refinement_queries_execution` 1, `static_capture_keys` 1

### implement: type inference gaps (54 files)

`generalized_local_instance_execution` 19, `inferred_dictionary_execution` 9, `typed_path_execution` 9, `local_storage_execution` 7, `package_static_execution` 7, `array_execution` 6, `rank_carrier_execution` 6, `universal_dictionary_execution` 6, `member_dictionary_alias_execution` 5, `canonical_constructor_execution` 4, `iterator_execution` 4, `memory_profile_execution` 4, `packed_rows_execution` 4, `suspended_ownership_execution` 4, `unconstrained_collection_execution` 4, `bottom_flow_execution` 3, `entry_execution` 3, `evaluated_calls_execution` 3, `general_optimization_execution` 3, `recursive_component_execution` 3, `array_member_receipts` 2, `bottom_binding_execution` 2, `constant_query_barriers` 2, `contracts_execution` 2, `generic_word_ownership` 2, `inferred_dictionary_portable_execution` 2, `member_storage_execution` 2, `partial_array_execution` 2, `ragged_builders_revision` 2, `rank_constant_field_execution` 2, `record_payload_execution` 2, `small_collections_execution` 2, `storage_generic_readers_execution` 2, `storage_simd_execution` 2, `wide_ownership_execution` 2, `allocation_cost_matrix` 1, `array_cost_explanation` 1, `body_qualified_roots` 1, `conditional_roots_execution` 1, `cursor_forks_execution` 1, `development_tier` 1, `immutable_constructor_execution` 1, `iterator_control_exits_execution` 1, `list_snapshot_execution` 1, `list_traversal_execution` 1, `packed_rows_revision` 1, `rank_nested_opening_execution` 1, `rank_portable_execution` 1, `rank_row_execution` 1, `rank_structural_execution` 1, `reductions_ownership_execution` 1, `stage_chain_budget` 1, `universal_dictionary_portable_execution` 1, `windows_completed_producer_execution` 1

### runtime mismatch (38 files)

`constant_receipts` 10, `persistent_roots_execution` 9, `body_check_cache` 8, `opaque_wrapper_operations` 8, `collection_execution` 6, `ragged_builders_execution` 6, `restart_cache` 6, `stdlib_execution` 6, `tracing_replacement_execution` 6, `zig_project_protocol` 5, `collection_step_sink_execution` 4, `collection_iteration_execution` 3, `list_row_boundaries_execution` 3, `numeric_scopes_execution` 3, `retained_record_execution` 3, `row_fusion_execution` 3, `acyclic_updates_execution` 2, `body_path_update_cache` 2, `checked_store_execution` 2, `compile_budget` 2, `completed_function_execution` 2, `cyclic_ownership_execution` 2, `exact_builders_execution` 2, `indexed_numeric_projection_execution` 2, `multi_parameter_syntax_execution` 2, `row_products_execution` 2, `storage_globals_execution` 2, `table_projection_execution` 2, `activation_ownership_execution` 1, `aggregate_constant_reuse` 1, `array_publication_execution` 1, `boolean_words_execution` 1, `getter_ownership_execution` 1, `list_span_execution` 1, `numeric_aggregates_execution` 1, `scalar_cursor_execution` 1, `scalar_record_reader_execution` 1, `shared_rc_execution` 1

### implement: providers and effect operations (B1) (31 files)

`retained_state_execution` 22, `call_summary_execution` 12, `staging_execution` 9, `guest` 7, `effect_execution` 6, `where_execution` 5, `builtin_state_execution` 4, `callback_row_execution` 4, `effect_runner_execution` 4, `effectful_dictionary_closure_execution` 4, `opaque_binding_relocation_execution` 4, `qualified_row_execution` 4, `rank_staging_effects` 4, `symbolic_effect_rows` 3, `typed_staging_effects` 3, `arena_gc_execution` 2, `body_static_operation_cache` 2, `body_user_rows_cache` 2, `canonical_constructor_import_execution` 2, `effectful_dictionary_closure_portable` 2, `handler_cleanup_execution` 2, `request_factory_import_execution` 2, `scoped_older_cell_execution` 2, `shaped_parameter_execution` 2, `state_frame_execution` 2, `aliases_execution` 1, `foreign_execution` 1, `lexical_summary_execution` 1, `open_row_execution` 1, `state_provider_ownership_execution` 1, `static_capture_row_execution` 1

### implement: constant exports (25 files)

`captured_callable_execution` 21, `unit_coverage_execution` 11, `native_asset_protocol` 10, `loop_execution` 6, `principal_replay_execution` 5, `project_execution` 5, `result_execution` 5, `source_buffers` 5, `update_execution` 5, `execution` 4, `tags_execution` 4, `initialization_execution` 3, `module_abstraction_execution` 3, `associated_execution` 2, `callable_constant_receipts` 2, `let_fallback_execution` 2, `named_functions_execution` 2, `value_pattern_scope_execution` 2, `adjacent_call_execution` 1, `annotation_arity_execution` 1, `lexical_capture_scan` 1, `package_execution` 1, `principal_query_reuse` 1, `product_projection_execution` 1, `summary_job_principal_reuse` 1

### other (29 files)

`recursive_storage_execution` 24, `simd_execution` 9, `immutable_acyclic_execution` 7, `runtime_pathology_execution` 7, `owned_array_execution` 5, `numeric_variants_execution` 4, `storage_capacity_execution` 3, `public_api` 3, `body_cutoff_reuse` 2, `collector_contract_execution` 2, `identity_array_execution` 2, `literal_edit_reuse` 2, `numeric_call_boundaries_execution` 2, `pipeline_builder_execution` 2, `scalar_constant_reuse` 2, `editor_completion` 2, `guest_associated_types` 2, `aggregate_execution` 1, `allocation_project_execution` 1, `collection_optimization_revision` 1, `constant_temporary_execution` 1, `empty_cursor_execution` 1, `evaluation_depth` 1, `portable_query_restart` 1, `prelude_execution` 1, `storage_host_execution` 1, `storage_project_execution` 1, `trivia_edit_reuse` 1, `format` 1

### diagnostic owned by scoped backend (17 files)

`unused_aggregate_execution` 12, `storage_records_execution` 9, `scoped_storage_execution` 7, `dispatch_explanation` 5, `storage_calls_execution` 5, `entry_interface_order_execution` 4, `qualified_evidence_execution` 4, `reflection_execution` 4, `array_limit_execution` 2, `associated_catalog_execution` 2, `entry_diagnostic_execution` 2, `scoped_empty_rows_execution` 2, `scoped_loop_cleanup_execution` 2, `scoped_loop_refinement_execution` 2, `scoped_simd_wrappers_execution` 2, `storage_flat_data_execution` 1, `storage_record_merge_execution` 1

### drop: request handlers (B3) (12 files)

`request_execution` 48, `scoped_request_execution` 4, `body_general_receipts_expanded` 2, `list_traversal_effect_execution` 2, `ownership_roles` 2, `resource_request_execution` 2, `bottom_ownership_execution` 1, `function_exit_execution` 1, `package_control_execution` 1, `region_activation_execution` 1, `resolved_flow` 1, `scalar_closure_environment_execution` 1

### drop: typed staging (C8) (12 files)

`typed_staging_execution` 21, `typed_staging_statement_if` 8, `task_execution` 7, `typed_staging_composition` 5, `closed_stage_task_boundaries` 2, `run_surface_execution` 2, `storage_comprehensions_execution` 2, `typed_staging_ambient_rows` 2, `typed_staging_sealed` 2, `typed_staging_origins` 1, `typed_staging_packages` 1, `typed_staging_resources` 1

### drop: effect identities and reflection (B3) (21 files)

`scoped_effect_execution` 7, `scoped_aggregate_flow_execution` 4, `scoped_curried_execution` 4, `scoped_invocation_flow_execution` 4, `scoped_pair_execution` 4, `scoped_selection_execution` 4, `scoped_callback_execution` 2, `scoped_closure_footprint_execution` 2, `scoped_forwarding_callback_execution` 2, `scoped_generation_execution` 2, `scoped_generic_state_execution` 2, `scoped_lifetime_execution` 2, `scoped_multi_input_callback_execution` 2, `scoped_parameter_execution` 2, `scoped_projected_callback_execution` 2, `scoped_public_flow_execution` 2, `scoped_resource_footprint_execution` 2, `scoped_value_flow_execution` 2, `scoped_capability_diagnostics` 1, `scoped_generic_execution` 1, `scoped_grouped_product_execution` 1

### drop: polymorphic packages (C8) (15 files)

`package_sequence_execution` 8, `package_runtime_execution` 6, `associated_dictionary_execution` 4, `package_dictionary_execution` 3, `package_dictionary_resealing` 2, `package_owned_execution` 2, `associated_dictionary_portable_execution` 1, `package_associated_payload_execution` 1, `package_associated_payload_portable` 1, `package_dictionary_capture_execution` 1, `package_dictionary_portable_execution` 1, `package_dictionary_resealing_portable` 1, `package_owner_execution` 1, `package_portable_execution` 1, `rank_inferred_execution` 1

### pending: traits redesign (C) (5 files)

`body_implementation_cache` 12, `guest_implementations` 10, `derive_execution` 5, `runtime_text_execution` 2, `scoped_contract_methods_execution` 2

### drop: usage contracts and resources (C8) (13 files)

`resource_execution` 3, `resource_host_cleanup_execution` 3, `resource_transfer_execution` 3, `rank_region_execution` 2, `resource_aggregate_execution` 2, `resource_nominal_execution` 2, `resource_pure_cleanup_execution` 2, `resource_reference_execution` 2, `usage_backend_execution` 2, `usage_forall_execution` 2, `usage_nominal_execution` 2, `usage_execution` 1, `usage_sharing_execution` 1

### drop: monads and resolvers (B3) (4 files)

`monad_execution` 15, `monad_loop_execution` 8, `semantic_artifacts` 2, `resolved_calls` 1

### implement: recursive data types (2 files)

`rolling_execution` 7, `summary_execution` 6

### implement: other forms (6 files)

`primitive_alias_execution` 2, `runtime_boundaries_retained_execution` 2, `scoped_opaque_layout_execution` 2, `selected_callback_execution` 2, `inference_budget_config` 1, `guest_arrays` 1

### implement: entry ABI forms (3 files)

`public_owner_execution` 4, `structural_host_cleanup_execution` 3, `usage_once_entry_execution` 2

### drop: erased proofs (C8) (2 files)

`numeric_proof_execution` 3, `quantified_execution` 3

### drop: language tasks (retired) (2 files)

`task_surface_execution` 4, `task_abi_execution` 1

### drop: type values and witnesses (C3/C4) (2 files)

`type_identity_execution` 3, `higher_order_summary_execution` 1
