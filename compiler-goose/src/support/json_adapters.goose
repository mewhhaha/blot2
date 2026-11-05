// Generated source by tools/write_json_adapters.py; unverified.
// Exact overloads keep custom wire projections and enum tags explicit.
namespace blot_json;
import support.json;
import backend.activation_graph;
import backend.allocation_emission;
import backend.array_cost_explanation;
import backend.backend_emission;
import backend.backend_timing;
import backend.callable_origins;
import backend.collection_edit_call;
import backend.collection_ops;
import backend.collector_contract;
import backend.core_backend;
import backend.empty_root_scopes;
import backend.exact_builder;
import backend.function_facts;
import backend.host_cleanup_shapes;
import backend.host_entry;
import backend.identity_array;
import backend.known_call;
import backend.layout;
import backend.memory_profile;
import backend.native_asset_numbers;
import backend.native_asset_readers;
import backend.native_assets;
import backend.numeric_rows;
import backend.opaque_storage;
import backend.optimized_bodies;
import backend.owned_arrays;
import backend.packed_layout;
import backend.pipeline_builder;
import backend.private_append_region;
import backend.private_cursor;
import backend.provider_modes;
import backend.ragged_builder;
import backend.resolved_call;
import backend.resolved_flow;
import backend.runtime_body_relocation;
import backend.runtime_flags;
import backend.runtime_ir;
import backend.runtime_job;
import backend.runtime_parallel;
import backend.runtime_pipeline;
import backend.scoped_backend;
import backend.simd_call;
import backend.simd_intrinsics;
import backend.source_origins;
import backend.startup_emission_facts;
import backend.startup_occurrence_flow;
import backend.startup_runtime_reach;
import backend.storage_calls;
import backend.storage_plan;
import backend.storage_recursive_admission;
import backend.storage_transport;
import backend.storage_type_key;
import backend.wasm;
import backend.wasm_bit_recurrence;
import backend.wasm_bulk_loop;
import backend.wasm_control_flow;
import backend.wasm_lifetimes;
import backend.wasm_scope_outline;
import backend.wasm_sroa;
import backend.wasm_transport_cleanup;
import check.capability_contract_core;
import check.capability_contract_source;
import check.capability_contracts;
import check.capability_flow;
import check.capability_lifetimes;
import check.check;
import check.closed_nominal_storage;
import check.core;
import check.diagnostic_code;
import check.diagnostic_location;
import check.dictionary_owner;
import check.effects;
import check.frozen_core_graph;
import check.frozen_types;
import check.generative_relocation;
import check.lifetime_report_pool;
import check.numeric_proof_bodies;
import check.numeric_proof_core;
import check.numeric_proof_terms;
import check.package_contracts;
import check.package_row_facts;
import check.parameter_patterns;
import check.primitive_operator;
import check.scheme_equations;
import check.solver_worklist;
import check.source_sort;
import check.staging_origins;
import check.storage_core;
import check.storage_ops;
import check.task_core;
import check.task_regions;
import check.task_types;
import check.type_store_snapshot;
import check.typed_staging;
import check.types;
import check.usage_check;
import check.usage_core;
import compilation_tier;
import driver.cli;
import eval.canonical_specialization;
import eval.closed_evidence_import;
import eval.closed_local_value;
import eval.completed_specialization_query;
import eval.core_eval;
import eval.eval_indexed_builder;
import eval.eval_values;
import eval.implementation_evidence;
import eval.pool_leases;
import eval.purity_type_key;
import eval.region_arena;
import eval.semantic_parallel;
import eval.specialization;
import eval.type_evidence;
import parse.parse_error;
import phase_profile;
import reuse.artifact_emitter;
import reuse.artifact_import;
import reuse.body_auxiliary;
import reuse.body_check_cache;
import reuse.body_check_digests;
import reuse.code_artifacts;
import reuse.completion_fit;
import reuse.completion_probe;
import reuse.composite_resolution_cache;
import reuse.constant_receipt;
import reuse.declaration_dependencies;
import reuse.declaration_projection;
import reuse.dependency_cli;
import reuse.dependency_consumer;
import reuse.dependency_format_owners;
import reuse.dependency_payload;
import reuse.dependency_project_consumer;
import reuse.dispatch_explanation;
import reuse.editor_completion;
import reuse.entry_frontend_cutoff;
import reuse.frontend_binding_relocation;
import reuse.frontend_graph_correspondence;
import reuse.frozen_dependency;
import reuse.global_references;
import reuse.hole_diagnostics;
import reuse.independent_call_proof;
import reuse.partial_dependency;
import reuse.portable_query;
import reuse.principal_evidence_reuse;
import reuse.principal_inputs;
import reuse.principal_interface;
import reuse.principal_reuse_gate;
import reuse.project;
import reuse.project_check;
import reuse.project_check_engine;
import reuse.refinement_receipt;
import reuse.restart_cache;
import reuse.retained_revision;
import reuse.revision_inputs;
import reuse.row_projection_uses;
import reuse.semantic_query_table;
import reuse.source_value_template;
import reuse.specialization_receipt;
import reuse.zig_project_server;
import reuse.zig_project_server_build;
import reuse.zig_project_server_inputs;
import reuse.zig_project_server_lifecycle;
import reuse.zig_project_server_loop;
import runtime.cycles_runtime;
import runtime.data_stacks;
import runtime.memory;
import runtime.runtime_cleanup;
import support.blake3;
import support.core_packet;
import support.error;
import support.process_pool;
import support.project_packet_owners;
import support.wyhash;
import work_counters;
fn write(writer:Writer&,value:blot_backend_activation_graph::Blocker)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_activation_graph::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_allocation_emission::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_backend_emission::CursorPrevious)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_backend_emission::DispatchPlan)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_backend_emission::FactoryCallee)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_backend_emission::InlinePreparation)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_backend_emission::JoinKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_backend_emission::Plan)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_backend_emission::ProjectionPlan)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_backend_emission::ResolverPlan)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_backend_emission::SmallKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_backend_timing::Phase)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_callable_origins::Environment)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_collection_ops::Op)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_collector_contract::Reason)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_core_backend::EmissionResult)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_empty_root_scopes::Action)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_function_facts::Length)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_host_cleanup_shapes::Tag)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_host_entry::Value)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_layout::Tag)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_memory_profile::Category)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_memory_profile::Metric)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_memory_profile::Value)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_native_asset_readers::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_native_asset_readers::Result)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_native_asset_readers::ShapeTag)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_native_asset_readers::Tag)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_native_assets::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_opaque_storage::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_owned_arrays::Callee)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_owned_arrays::Decision)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_owned_arrays::Use)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_provider_modes::Access)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_resolved_call::Callee)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_resolved_flow::ExitKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_runtime_body_relocation::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_runtime_pipeline::Pass)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_scoped_backend::AccessContract)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_scoped_backend::CallableKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_scoped_backend::FunctionAbi)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_scoped_backend::PreparedKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_scoped_backend::ValueTag)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_scoped_backend::WriterKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_simd_intrinsics::Lane)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_simd_intrinsics::Shape)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_startup_emission_facts::EventKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_startup_emission_facts::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_startup_occurrence_flow::EdgeKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_startup_occurrence_flow::FactKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_startup_occurrence_flow::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_startup_occurrence_flow::Match)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_startup_occurrence_flow::Provenance)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_startup_runtime_reach::Work)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_storage_calls::TargetKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_storage_plan::ExitKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_storage_plan::LayoutKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_storage_plan::RegionRole)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_storage_transport::State)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_storage_type_key::Memo)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_wasm::MemoryModel)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_wasm::OwnershipFallback)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_wasm::SemanticKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_wasm_bit_recurrence::Flow)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_wasm_bit_recurrence::Term)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_wasm_bulk_loop::Replacement)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_wasm_bulk_loop::SourceReplacement)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_wasm_lifetimes::AccessKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_wasm_lifetimes::AnalysisMode)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_wasm_lifetimes::Edge)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_wasm_lifetimes::RcWriteKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_wasm_lifetimes::SummaryPhase)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_wasm_scope_outline::Contract)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_wasm_scope_outline::GlobalMap)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_wasm_sroa::ReferenceProof)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_wasm_transport_cleanup::Pair)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_capability_contract_core::FunctionUse)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_capability_contracts::Projection)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_capability_contracts::Tag)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_capability_flow::ConstructionKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_capability_flow::Contract)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_capability_flow::ParameterResult)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_capability_lifetimes::EdgeKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_capability_lifetimes::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_capability_lifetimes::Parameters)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::AssociatedChoice)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::Callees)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::Code)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::ComponentProgress)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::DiagnosticContextKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::DictionaryProof)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::EditorName_kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::EffectRunnerKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::Engine_contract_states_state)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::Engine_implementation_member_states_state)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::Engine_member_states_state)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::GlobalTrace_kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::ImportedCatalog_kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::OperationUse_call)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::ReflectionKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::RequestControl_kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::ResolverKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::State)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_check::TypeApplication)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_core::Code)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_core::DictionaryProof)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_check_core::LoopKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_core::Op)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_core::PatternTag)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_core::PrimitiveKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_core::RequestDecisionKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_core::ResolverOperation)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_core::Tag)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_core::UpdateKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_diagnostic_code::Code)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_dictionary_owner::Owner)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_check_effects::Tail)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_check_frozen_core_validation::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_frozen_types::Patterns)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_check_frozen_types::Source)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_check_numeric_proof_core::Fact)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_check_numeric_proof_core::SummaryInputs)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_check_numeric_proof_terms::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_numeric_proof_terms::Relation)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_numeric_proof_terms::Tag)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_parameter_patterns::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_source_sort::Hint)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_staging_origins::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_storage_ops::Op)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_task_core::SpawnApplication)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_check_task_types::CaptureIssue)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_task_types::Op)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_typed_staging::Op)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_types::ObligationKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_types::Operator)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_types::Tag)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_usage_check::Mode)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_usage_check::Outcome)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_check_usage_core::Outcome)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_cli::Command)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_compilation_tier::Tier)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_core_packet::Run)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_error::Error)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_canonical_specialization::Mode)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_completed_specialization_query::Reason)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_core_eval::CodeProjection)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_core_eval::ConstraintKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_core_eval::DispatchContextKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_core_eval::Expected)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_core_eval::Flow)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_core_eval::PrincipalAction)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_core_eval::PrincipalClaim)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_core_eval::RequirementPart)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_core_eval::SchemeImport)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_core_eval::State)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_core_eval::SummaryJobState)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_core_eval::SummaryProgress)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_core_eval::Work)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_eval_values::ClosureOrigin)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_eval_values::ValueKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_implementation_evidence::Code)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_implementation_evidence::FieldCheck)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_implementation_evidence::ProofKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_pool_leases::Field)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_purity_type_key::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_specialization::FailureCode)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_specialization::MappingSink)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_specialization::RowSink)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_eval_type_evidence::Tag)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_json::FrameKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_parse_error::ParseError)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_phase_profile::OptimizationPass)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_phase_profile::Phase)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_phase_profile::Space)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_process_pool::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_project_packet::Run)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_artifact_emitter::Event)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_artifact_emitter::FunctionRole)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_artifact_emitter::ResourceKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_artifact_emitter::Role)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_artifact_import::Domain)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_artifact_import::OperationScope)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_body_auxiliary::Route)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_body_check_cache::NominalKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_body_check_cache::PrivateVersionKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_code_artifacts::Event)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_code_artifacts::OperationLocation)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_code_artifacts::Request)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_code_artifacts::StampAlgorithm)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_code_artifacts::State)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_completion_fit::Match)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_completion_probe::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_constant_receipt::Event)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_constant_receipt::JudgmentKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_constant_receipt::QueryKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_constant_receipt::Reason)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_constant_receipt::Source)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_declaration_dependencies::Work)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_declaration_projection::Work)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_dependency_cli::Creation)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_dependency_format::Run)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_dependency_payload::Run)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_dependency_project_consumer::Lowered)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_dispatch_explanation::ContextKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_dispatch_explanation::Outcome)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_dispatch_explanation::Side)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_editor_completion::ItemKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_entry_frontend_cutoff::Color)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_frontend_binding_relocation::Stage)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_frontend_graph_correspondence::Reason)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_frozen_dependency::ExportKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_global_references::Event)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_global_references::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_hole_diagnostics::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_independent_call_proof::DeclineReason)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_partial_dependency::Preparation)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_portable_query::Claim)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_principal_evidence_reuse::PrimitiveResult)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_principal_evidence_reuse::SourceReason)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_principal_inputs::Reason)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_principal_interface::ContractMemberKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_principal_interface::ImplementationMemberKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_principal_interface::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_principal_interface::SelectedProofKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_principal_reuse_gate::IdentityFailure)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_project::Code)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_project::InputMode)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_project::Visit)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_project_check::CatalogOwner)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_project_check::Code)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_project_check::Editor)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_refinement_receipt::Reason)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_refinement_receipt::RecordDecline)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_refinement_receipt::Root)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_restart_cache::Part)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_restart_cache::Persisted)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_retained_revision::CandidateKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_retained_revision::CandidateStatus)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_retained_revision::LibraryUpdate)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_retained_revision::Preparation)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_revision_inputs::Outcome)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_row_projection_uses::OriginKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_row_projection_uses::PositionKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_semantic_query_table::Kind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_semantic_query_table::Order)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_source_value_template::Reason)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_source_value_template::RowPolicy)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_specialization_receipt::PrincipalOutcome)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_zig_project_server::ByteOwner)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_zig_project_server::JsonRun)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_reuse_zig_project_server::RequestKind)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_runtime_cycles_runtime::Phase)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_runtime_data_stacks::Mode)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_runtime_memory::Sharing)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_runtime_runtime_cleanup::Action)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_runtime_runtime_cleanup::Backing)->blot_error::Error {return unionValue(writer,value);}
fn write(writer:Writer&,value:blot_work_counters::InferenceStage)->blot_error::Error {return enumValue(writer,value);}
fn write(writer:Writer&,value:blot_backend_allocation_emission::Site)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}var bytes:u8[>..]=[];blot_backend_allocation_emission::jsonStringify(value,bytes);return write(writer,Raw{bytes[:]});}
fn write(writer:Writer&,value:blot_backend_array_cost_explanation::Site)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_array_cost_explanation::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_backend_timing::RefinementCensus)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}var bytes:u8[>..]=[];blot_backend_backend_timing::jsonStringify(value,bytes);return write(writer,Raw{bytes[:]});}
fn write(writer:Writer&,value:blot_backend_backend_timing::RefinementCost)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}var bytes:u8[>..]=[];blot_backend_backend_timing::jsonStringify(value,bytes);return write(writer,Raw{bytes[:]});}
fn write(writer:Writer&,value:blot_backend_backend_timing::RefinementRequest)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}var bytes:u8[>..]=[];blot_backend_backend_timing::jsonStringify(value,bytes);return write(writer,Raw{bytes[:]});}
fn write(writer:Writer&,value:blot_backend_backend_timing::Region)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}var bytes:u8[>..]=[];blot_backend_backend_timing::jsonStringify(value,bytes);return write(writer,Raw{bytes[:]});}
fn write(writer:Writer&,value:blot_backend_backend_timing::RegionCensus)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}var bytes:u8[>..]=[];blot_backend_backend_timing::jsonStringify(value,bytes);return write(writer,Raw{bytes[:]});}
fn write(writer:Writer&,value:blot_backend_backend_timing::RegionCost)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}var bytes:u8[>..]=[];blot_backend_backend_timing::jsonStringify(value,bytes);return write(writer,Raw{bytes[:]});}
fn write(writer:Writer&,value:blot_backend_backend_timing::Stats)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}var bytes:u8[>..]=[];blot_backend_backend_timing::jsonStringify(value,bytes);return write(writer,Raw{bytes[:]});}
fn write(writer:Writer&,value:blot_backend_backend_timing::ThreadCpu)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}var bytes:u8[>..]=[];blot_backend_backend_timing::jsonStringify(value,bytes);return write(writer,Raw{bytes[:]});}
fn write(writer:Writer&,value:blot_backend_backend_timing::WorkStats)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}var bytes:u8[>..]=[];blot_backend_backend_timing::jsonStringify(value,bytes);return write(writer,Raw{bytes[:]});}
fn write(writer:Writer&,value:blot_backend_core_backend::WireBridge)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireCallback)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireClosures)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireDemandEvent)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireDemandEvents)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireEffects)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireEmission)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireEmissionEvent)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireEmissionRecords)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write<T>(writer:Writer&,value:blot_backend_core_backend::WireEnum<T>)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireEvaluatorSnapshot)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireEvidence)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireEvidenceGoals)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireEvidenceNodes)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireFunctionArtifacts)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireFunctions)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireImplementationFact)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireImplementationMembers)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireImplementationProofs)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireImplementationSnapshot)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireJob)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireJobs)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireLayoutNodes)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireLayouts)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireModulePin)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireOp)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireOperand)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireOperationLocation)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireOperationRelocations)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireOptionalScalar)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireOwnedPools)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireOwnerBoundary)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireRequest)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireRole)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireScalar)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireSemanticSite)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireSymbolicInstructions)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireValueType)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireValueTypes)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_core_backend::WireValues)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_core_backend::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_memory_profile::Digest)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_memory_profile::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_memory_profile::Sites)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_memory_profile::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_memory_profile::Source)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_memory_profile::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_native_assets::Definition)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}blot_backend_native_assets::jsonStringify(value,writer);return writer.failure;}
fn write(writer:Writer&,value:blot_backend_wasm::BoundaryJson)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_wasm::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_wasm::CallbackJson)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_wasm::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_wasm::CertificateJson)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_wasm::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_wasm::CollectorJson)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_wasm::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_wasm::DigestJson)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_wasm::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_wasm::ExportJson)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_wasm::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_backend_wasm::ScalarJson)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_backend_wasm::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write<P>(writer:Writer&,value:blot_check_diagnostic_location::WithOrigins<P>)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_check_diagnostic_location::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_phase_profile::PhaseRecord)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_phase_profile::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_phase_profile::Record)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_phase_profile::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_dependency_cli::Metrics)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_dependency_cli::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_dependency_consumer::Details)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_dependency_consumer::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_dispatch_explanation::Candidate)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_dispatch_explanation::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_dispatch_explanation::Explanation)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_dispatch_explanation::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_editor_completion::Diagnostic)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_editor_completion::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_editor_completion::DiagnosticDetails)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_editor_completion::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_editor_completion::Item)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_editor_completion::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_editor_completion::Result)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_editor_completion::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_hole_diagnostics::Binding)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_hole_diagnostics::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_hole_diagnostics::Edge)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_hole_diagnostics::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_hole_diagnostics::Node)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_hole_diagnostics::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_hole_diagnostics::Requirement)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_hole_diagnostics::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_hole_diagnostics::Snapshot)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_hole_diagnostics::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_hole_diagnostics::Span)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_hole_diagnostics::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_principal_evidence_reuse::SourceDecline)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_principal_evidence_reuse::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_restart_cache::Report)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_restart_cache::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_retained_revision::FallbackStats)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_retained_revision::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_retained_revision::Stats)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_retained_revision::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_zig_project_server::BuildReply)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_zig_project_server::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_zig_project_server::BuildStats)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_zig_project_server::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_zig_project_server::CheckpointReply)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_zig_project_server::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_zig_project_server::Diagnostic)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_zig_project_server::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_reuse_zig_project_server::IssueDetails)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_reuse_zig_project_server::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,value:blot_runtime_memory::Counts)->blot_error::Error {if writer.failure!=blot_error::Error.none {return writer.failure;}let error=blot_runtime_memory::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;}
fn write(writer:Writer&,values:blot_backend_backend_emission::FactRange[4])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_backend_emission::LayoutEntry[32])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_backend_timing::RefinementCost[32])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_backend_timing::RefinementRequest[8])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_backend_timing::Region[8])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_backend_timing::RegionCost[32])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_host_entry::Value[256])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_numeric_rows::Guard[32])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_numeric_rows::Leaf[64])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_numeric_rows::Storage[32])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_opaque_storage::Frame[256])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_optimized_bodies::WorkerTiming[16])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_packed_layout::Leaf[32])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_private_append_region::Frame[16])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_runtime_ir::Instruction[18])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_runtime_ir::ValueType[3])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_runtime_parallel::WorkerTiming[16])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_source_origins::Frame[4])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_storage_calls::InlineScope[256])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_storage_calls::Ref[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_backend_storage_recursive_admission::Ref[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_capability_contract_core::Alias[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_capability_contract_source::Entry[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_capability_flow::AstId[3])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_capability_flow::AstId[16])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_capability_flow::CoreInvocationBinding[16])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_capability_flow::SourceBinding[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_capability_lifetimes::Entry[256])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_capability_lifetimes::Id[16])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_capability_lifetimes::Mapping[64])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_closed_nominal_storage::Id[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_core::BindingRef[8])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_core::BindingRef[12])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_core::BindingRef[16])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_core::Id[3])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_core::Id[16])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_core::Id[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_effects::Id[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_generative_relocation::Instance[32])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_generative_relocation::Pair[16])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_generative_relocation::Pair[4096])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_generative_relocation::RowInstance[32])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_lifetime_report_pool::Range[13])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_package_contracts::FormalPair[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_package_contracts::Id[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_package_contracts::Id[256])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_package_contracts::Id[4096])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_package_contracts::Opening[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_package_contracts::Scheme[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_package_row_facts::Page[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_scheme_equations::Id[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_staging_origins::Origin[8])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_storage_core::Pair[4])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_task_regions::Range[16])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_types::ClosedRow[4])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_types::OperationRow[64])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_types::Scheme[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_usage_check::Id[4096])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_usage_core::State[4096])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_check_usage_core::State[65536])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_eval_closed_evidence_import::Frame[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_eval_closed_local_value::BindingRef[16])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_eval_core_eval::DispatchCandidate[3])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_eval_core_eval::DispatchContext[2])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_eval_core_eval::RaggedOperation[256])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_eval_eval_indexed_builder::Edit[16])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_eval_pool_leases::LeaseRef[48])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_json::Frame[256])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_reuse_body_check_cache::ClosedRole[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_reuse_body_check_cache::Digest[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_reuse_body_check_cache::RecipeEntry[64])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_reuse_composite_resolution_cache::Dependency[8])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_reuse_dispatch_explanation::Candidate[4])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_reuse_dispatch_explanation::Step[8])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_reuse_principal_evidence_reuse::SourceDecline[8])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_reuse_source_value_template::RootObservation[32])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_reuse_specialization_receipt::PrincipalRead[64])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:blot_reuse_specialization_receipt::ReadyRead[64])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:bool[16])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:bool[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:bool[4096])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:i64[3])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:i64[5])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:i64[7])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:i64[8])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:i64[9])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:i64[11])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:i64[15])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:i64[19])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:i64[22])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:i64[64])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:i64[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u16[8192])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u32[2])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u32[3])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u32[4])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u32[8])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u32[16])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u32[18])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u32[32])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u32[64])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u32[128])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u32[256])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u32[4096])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u64[3])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u64[4])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u64[21])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u64[64])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u64[69])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u8[32])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u8[48])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u8[64])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u8[96])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u8[160])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u8[256])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
fn write(writer:Writer&,values:u8[4096])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}
