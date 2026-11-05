// Named code instances and constants share the checked immutable Core graph.
namespace blot_backend_core_backend;
import .result_publication;
import .result_owner;
import reuse.dependency_payload;
import .substitution_buffers;
import std;
import .call_limits;
import dictionary;
import check.core;
import check.types;
import check.diagnostic_code;
import check.dictionary_owner;
import check.staging_origins;
import check.numeric_proof_core;
import check.effect_evidence;
import .runtime_ir;
import .wasm;
import .scalar_ops;
import .simd_intrinsics;
import .layout;
import .backend_timing;
import .allocation_emission;
import .backend_plan;
import .backend_representations;
import .backend_static_data;
import .backend_emission;
import .numeric_rows;
import .packed_layout;
import .acyclic_layout;
import .bottom_result;
import .unit_index;
import .owned_arrays;
import .discarded_bindings;
import .dictionary_layout;
import .runtime_identity;
import .runtime_operations;
import .host_cleanup_shapes;
import .host_entry;
import .source_origins;
import .storage_plan;
import .backend_checkpoint;
import .region_candidate;
import .cohort_candidate;
import .activation_model;
import .collector_contract;
import .simd_abi;
import .scoped_backend;
import .ragged_builder;
import .optimized_bodies;
import .function_facts;
import .startup_emission_facts;
import eval.core_eval;
import eval.eval_values;
import eval.implementation_evidence;
import eval.type_evidence;
import eval.specialization;
import eval.completed_specialization_query;
import eval.implementation_trace;
import eval.selected_query;
import reuse.code_artifacts;
import reuse.artifact_emitter;
import reuse.artifact_capture;
import reuse.artifact_fragment;
import reuse.principal_evidence_reuse;
import reuse.principal_archive;
import reuse.principal_inputs;
import reuse.constant_receipt_reuse;
import reuse.refinement_receipt;
import reuse.dispatch_explanation;
import reuse.code_expectation;
import reuse.substitution_keys;
import reuse.semantic_query_table;
import reuse.constant_receipt;
import reuse.specialization_receipt;
import reuse.dependency_certificate;
import reuse.completed_core_validation;
import reuse.source_completion;
import reuse.shared_query_gate;
import reuse.principal_reuse_gate;
import runtime.runtime_layout;
import runtime.request_runtime;
import runtime.public_owners;
import runtime.task_context;
import runtime.task_abi;
import work_counters;
import execution_policy;
import compilation_tier;
import compiler_defaults;
import support.native;
import phase_profile;
import support.option;
import support.error;
import support.path;
import support.host_layout;
import support.json;

type Code = blot_check_diagnostic_code::Code;
type Scalar = blot_backend_runtime_ir::Scalar;
type Value = blot_backend_scalar_ops::Value;
type Key = blot_reuse_code_artifacts::Key;
type Mapping = blot_backend_layout::Mapping;
type RowMapping = blot_backend_layout::RowMapping;
type CapturedTemplate = blot_reuse_code_artifacts::CapturedTemplate;
type StaticCodeProjection = blot_eval_specialization::PhysicalProjection;
struct Diagnostic {
    unit: u32 = 0, span: blot_check_core::Span, code: Code, detail: const u8[:] = "",
    ownership: blot_support::Option<blot_backend_wasm::OwnershipFailure>, dispatch: blot_support::Option<blot_eval_core_eval::DispatchRecord>,
    implementation_trace: blot_support::Option<blot_eval_implementation_trace::Record>, related: blot_support::Option<blot_eval_core_eval::SourceLocation>, origins: blot_check_staging_origins::Trace,
}
fn message(diagnostic: Diagnostic) -> const u8[:] { diagnostic.code.message(diagnostic.detail) }
struct ArtifactSummary { demands: i64 = 0, jobs: i64 = 0, functions: i64 = 0, helpers: i64 = 0, emission_events: i64 = 0, metadata_events: i64 = 0, operation_symbols: i64 = 0, templates: i64 = 0, pinned_modules: i64 = 0 }
struct ModuleStamps { computed: i64 = 0, reused: i64 = 0, comparisons: i64 = 0, copied: i64 = 0, hashed: i64 = 0 }
struct QueryTables {
    selected: blot_reuse_semantic_query_table::Storage, principal: blot_reuse_semantic_query_table::Storage, portable_principal: blot_reuse_semantic_query_table::Storage,
    canonical: blot_reuse_semantic_query_table::Storage, source_description: blot_reuse_semantic_query_table::Storage, open_residual: blot_reuse_semantic_query_table::Storage,
    executable_fragment: blot_reuse_semantic_query_table::Storage, executable_optimizer: blot_reuse_semantic_query_table::Storage,
}
var inactive_result_bytes = blot_backend_result_owner::ByteBuffer {..};
var inactive_result_message = blot_backend_result_owner::ByteBuffer {..};
struct Result {
    active: bool = false,output_owner: blot_backend_result_owner::Owner,detached: bool = false,message_source: const u8[:] = default<const u8[:]>(),publication_owner: blot_backend_result_publication::Owner,publication_epoch: u64 = 0,publication_pinned: bool = false,publication_units: const blot_check_core::Module[:] = default<const blot_check_core::Module[:]>(),
    allocation_emission: blot_backend_allocation_emission::Snapshot&? = null, timing: blot_backend_backend_timing::Stats,
    counters: blot_work_counters::Counters, optimization: blot_backend_function_facts::Stats, runtime_optimization: blot_backend_optimized_bodies::Stats,
    module_stamps: ModuleStamps, refinements: blot_reuse_refinement_receipt::Stats, completed_queries: blot_eval_completed_specialization_query::Stats, query_tables: QueryTables,
    artifacts: blot_support::Option<ArtifactSummary>, capture: blot_reuse_artifact_capture::Capture&? = null, whole_module_only: bool = false,
    reuse: blot_reuse_artifact_fragment::Stats, principal: blot_reuse_principal_evidence_reuse::Stats, source_validation: blot_reuse_dependency_certificate::Stats,
    bytes: blot_backend_result_owner::ByteBuffer& = inactive_result_bytes, diagnostic: blot_support::Option<Diagnostic>, code_instances: i64 = 0, callable_wrappers: i64 = 0, emitted_functions: i64 = 0, constant_steps: i64 = 0,
    constant_receipts: blot_reuse_constant_receipt::Stats, owned_message: blot_backend_result_owner::ByteBuffer& = inactive_result_message, explanation: blot_reuse_dispatch_explanation::Explanation&? = null,
    startup_observation: blot_backend_startup_emission_facts::Snapshot&? = null,
}
struct Generator {
    owner_id: u64 = blot_native::fresh_owner_id(),
    allocation_owner: u64 = 0,
    inline_named: bool = true, speculative_locals: bool = true, speculated: bool = false, ragged_probe_limit: u32 = blot_backend_ragged_builder::probe_limit,
    work_timing: blot_backend_backend_timing::Work, units: const blot_check_core::Module[:], spawn_units: const blot_check_core::Module[:] = default<const blot_check_core::Module[:]>(),
    artifacts: blot_reuse_code_artifacts::Context&? = null, retained: blot_reuse_artifact_fragment::State&? = null,
    principal_state: blot_reuse_principal_evidence_reuse::State&? = null, persisted_principals: blot_reuse_principal_archive::Reader&? = null,
    principal_stats: blot_reuse_principal_evidence_reuse::Stats, query_state: blot_eval_completed_specialization_query::State&? = null,
    constant_state: blot_reuse_constant_receipt_reuse::State&? = null, refinement_owner: blot_reuse_code_artifacts::Context&? = null,
    refinement_stats: blot_reuse_refinement_receipt::Stats, work: blot_reuse_artifact_fragment::Stats,
    module: blot_backend_wasm::Module&, planning: blot_backend_backend_plan::State&, evaluator: blot_eval_core_eval::Session&,
    representations: blot_backend_backend_representations::State&, static_data: blot_backend_backend_static_data::State&, numeric_rows: blot_backend_numeric_rows::Cache&,
    persistent_outputs: bool = false, memory_profile: bool = false, diagnostic_contexts: blot_backend_source_origins::ContextPool&,
    public_owners: blot_support::Option<blot_runtime_public_owners::Runtime>, task_context: blot_support::Option<blot_runtime_task_context::Functions>,
    request_owner: blot_support::Option<u32>, scoped_effects: bool = false, diagnostic: blot_support::Option<Diagnostic>, staging_trace: blot_check_staging_origins::Trace, instance_depth: i64 = 0,
}
fn init(generator: Generator&, journal: blot_reuse_artifact_emitter::Recorder&?) -> blot_error::Error {
    generator.evaluator.options.trace_runtime_dependencies = true; generator.module.defer_cycles = true; generator.module.artifacts .= journal;
    var requests = false;
    for source in generator.units { if source.request_loops.len != 0 { requests = true; } }
    if requests { let owner, error = generator.module.addGlobal(blot_backend_runtime_ir::SC_u32, 0, true); if error != blot_error::Error.none { return error; } generator.request_owner = blot_support::some(owner); }
    for source in generator.units {
        for closure in source.closures { if source.types.node(closure.parameter.ty).tag == blot_check_types::Tag.scoped { generator.scoped_effects = true; } }
        for binding in source.bindings { if binding.capability_flow == blot_check_core::CapabilityFlow.spawn_task { generator.spawn_units = generator.units; } }
    }
    return blot_error::Error.none;
}
fn unit(generator: Generator&, id: u32) -> const blot_check_core::Module& { generator.units[id - 1] }
fn decline(generator: Generator&, unit_id: u32, span: blot_check_core::Span, code: Code) -> blot_error::Error {
    if !generator.diagnostic.present { generator.diagnostic = blot_support::some(Diagnostic { unit: unit_id, span: span, code: code, origins: generator.staging_trace , ..}); }
    return blot_error::Error.declined;
}
fn fail(generator: Generator&, unit_id: u32, node: blot_check_core::Id, code: Code) -> blot_error::Error { decline(generator, unit_id, generator.unit(unit_id).span(node), code) }
fn failSpecialization(generator: Generator&, unit_id: u32, node: blot_check_core::Id, code: Code) -> blot_error::Error {
    let fresh = !generator.diagnostic.present; let failure = fail(generator, unit_id, node, code);
    if fresh && blot_eval_core_eval::callerDependentUse(generator.unit(unit_id), node) && generator.evaluator.specialization_origin.present {
        let origin = generator.evaluator.specialization_origin.value; let diagnostic = generator.diagnostic.value;
        if unit_id != origin.unit || diagnostic.span != origin.span { generator.diagnostic.value.related = blot_support::some(blot_eval_core_eval::SourceLocation { unit: unit_id, span: diagnostic.span , ..}); generator.diagnostic.value.unit = origin.unit; generator.diagnostic.value.span = origin.span; }
    }
    return failure;
}
fn functionRoot(generator: Generator&, unit_id: u32, ty: blot_check_types::Id, span: blot_check_core::Span) -> blot_check_types::Id, blot_error::Error {
    let root, error = generator.unit(unit_id).types.withoutForall(ty); if error != blot_error::Error.none { return 0, decline(generator, unit_id, span, blot_check_diagnostic_code::Code.complexity); } return root, blot_error::Error.none;
}
fn nestedRow(generator: Generator&, id: blot_backend_layout::Id) -> blot_support::Option<blot_backend_numeric_rows::Plan>, blot_error::Error {
    if blot_backend_packed_layout::rowWords(generator.representations.store, id) != 0 { return blot_support::none<blot_backend_numeric_rows::Plan>(), blot_error::Error.none; }
    let tag = generator.representations.store.node(id).tag;
    if tag != blot_backend_layout::Tag.record && tag != blot_backend_layout::Tag.product && tag != blot_backend_layout::Tag.nominal { return blot_support::none<blot_backend_numeric_rows::Plan>(), blot_error::Error.none; }
    return generator.numeric_rows.get(generator, id);
}
fn rowWords(generator: Generator&, id: blot_backend_layout::Id) -> u32, blot_error::Error {
    let flat = blot_backend_packed_layout::rowWords(generator.representations.store, id); if flat != 0 { return flat, blot_error::Error.none; }
    let plan, error = nestedRow(generator, id); if error != blot_error::Error.none { return 0, error; } if !plan.present { return 0, blot_error::Error.none; } return plan.value.word_count, blot_error::Error.none;
}
fn collectionRowWords(generator: Generator&, id: blot_backend_layout::Id) -> u32, blot_error::Error { let node = generator.representations.store.node(id); if node.tag == blot_backend_layout::Tag.array || node.tag == blot_backend_layout::Tag.list { return rowWords(generator, node.a); } return 0, blot_error::Error.none; }
fn layoutRole(generator: Generator&, id: blot_backend_layout::Id) -> blot_backend_runtime_ir::Role {
    let node = generator.representations.store.node(id);
    if node.tag == blot_backend_layout::Tag.nominal && generator.representations.store.scalar(id).present { return blot_backend_runtime_ir::ROLE_scalar; }
    if node.tag == blot_backend_layout::Tag.scoped || node.tag == blot_backend_layout::Tag.unit || node.tag == blot_backend_layout::Tag.boolean || node.tag == blot_backend_layout::Tag.unsigned32 || node.tag == blot_backend_layout::Tag.floating32 || node.tag == blot_backend_layout::Tag.never || node.tag == blot_backend_layout::Tag.type_constructor || node.tag == blot_backend_layout::Tag.resolver || node.tag == blot_backend_layout::Tag.erased_proof { return blot_backend_runtime_ir::ROLE_scalar; }
    if node.tag == blot_backend_layout::Tag.invalid || node.tag == blot_backend_layout::Tag.erased { return blot_backend_runtime_ir::ROLE_value; }
    if node.tag == blot_backend_layout::Tag.nominal { if node.a == 4294967295 && node.b != 5 && node.b != 6 && node.b != blot_backend_layout::capability_layout_decl { return blot_backend_runtime_ir::ROLE_value; } }
    return blot_backend_runtime_ir::ROLE_reference;
}
fn bodyResultRole(generator: Generator&, selected: blot_backend_layout::Id, owner: u32, root: blot_check_core::Id) -> blot_backend_runtime_ir::Role {
    let role = layoutRole(generator, selected); if selected == blot_backend_layout::erased && blot_backend_bottom_result::proves(generator.units, owner, root) { return blot_backend_runtime_ir::ROLE_scalar; } return role;
}
fn setParameterRoles(generator: Generator&, function_id: u32, roles: u64, provider: blot_support::Option<u16>) -> blot_error::Error {
    let error = generator.module.setParameterRoles(function_id, roles); if error != blot_error::Error.none { return error; } generator.evaluator.counters.parameter_role_functions++;
    var index: u16 = blot_backend_runtime_ir::no_provider; if provider.present { if provider.value >= 32 { return blot_error::Error.none; } index = provider.value; } return generator.module.setProviderParameter(function_id, index);
}
fn closureRoles(generator: Generator&, argument: blot_backend_layout::Id) -> u64 {
    if generator.representations.store.node(argument).tag == blot_backend_layout::Tag.erased_proof { return blot_backend_runtime_ir::packParameterRoles([blot_backend_runtime_ir::ROLE_reference, blot_backend_runtime_ir::ROLE_reference]); }
    return blot_backend_runtime_ir::packParameterRoles([blot_backend_runtime_ir::ROLE_reference, layoutRole(generator, argument), blot_backend_runtime_ir::ROLE_reference]);
}
fn dictionaryClosureRoles(generator: Generator&, argument: blot_backend_layout::Id) -> u64 {
    if generator.representations.store.node(argument).tag == blot_backend_layout::Tag.erased_proof { return blot_backend_runtime_ir::packParameterRoles([blot_backend_runtime_ir::ROLE_reference; 3]); }
    return blot_backend_runtime_ir::packParameterRoles([blot_backend_runtime_ir::ROLE_reference, layoutRole(generator, argument), blot_backend_runtime_ir::ROLE_reference, blot_backend_runtime_ir::ROLE_reference]);
}
fn resultMachine(generator: Generator&, result: blot_backend_layout::Id) -> blot_backend_runtime_ir::ValueType { if generator.representations.store.node(result).tag == blot_backend_layout::Tag.erased_proof { return blot_backend_runtime_ir::VT_none; } return generator.representations.store.machine(result); }
fn closureSignature(generator: Generator&, argument: blot_backend_layout::Id, result: blot_backend_layout::Id) -> u32, blot_error::Error {
    if generator.representations.store.node(argument).tag == blot_backend_layout::Tag.erased_proof { return generator.module.internType([blot_backend_runtime_ir::VT_i32; 2], resultMachine(generator, result)); }
    return generator.module.internType([blot_backend_runtime_ir::VT_i32, generator.representations.store.machine(argument), blot_backend_runtime_ir::VT_i32], resultMachine(generator, result));
}
fn dictionaryClosureSignature(generator: Generator&, argument: blot_backend_layout::Id, result: blot_backend_layout::Id) -> u32, blot_error::Error {
    if generator.representations.store.node(argument).tag == blot_backend_layout::Tag.erased_proof { return generator.module.internType([blot_backend_runtime_ir::VT_i32; 3], resultMachine(generator, result)); }
    return generator.module.internType([blot_backend_runtime_ir::VT_i32, generator.representations.store.machine(argument), blot_backend_runtime_ir::VT_i32, blot_backend_runtime_ir::VT_i32], resultMachine(generator, result));
}
fn emitValue(generator: Generator&, function_id: u32, value: Value) -> blot_error::Error {
    if value.scalar == blot_backend_runtime_ir::SC_pointer || value.scalar == blot_backend_runtime_ir::SC_array_u32 || value.scalar == blot_backend_runtime_ir::SC_array_f32 {
        let error = generator.module.emit(function_id, blot_backend_runtime_ir::immortalReference()); if error != blot_error::Error.none { return error; }
        return generator.module.emitReference(function_id, blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const, value.bits), blot_reuse_artifact_emitter::Role.static_address);
    }
    var op = blot_backend_runtime_ir::OP_i32_const; if value.scalar == blot_backend_runtime_ir::SC_f32 { op = blot_backend_runtime_ir::OP_f32_const; } return generator.module.emit(function_id, blot_backend_runtime_ir::instruction(op, value.bits));
}
fn callableLayout(generator: Generator&, function_id: u32, ty: blot_backend_layout::Id) -> blot_error::Error {
    let arrow = generator.representations.store.node(ty); if arrow.tag != blot_backend_layout::Tag.function || ty >= 67108864 { return blot_error::Error.none; }
    let body = generator.module.functions[function_id]; let signature, error = closureSignature(generator, arrow.a, arrow.b); if error != blot_error::Error.none { return error; }
    if body.entry || body.signature != signature || body.parameter_roles != closureRoles(generator, arrow.a) || body.result_role != layoutRole(generator, arrow.b) { return blot_error::Error.none; }
    return generator.module.setCallableLayout(function_id, ty);
}
recursive fn completeRetainedRows(generator: Generator&, requested: blot_backend_layout::Id, actual: blot_backend_layout::Id, depth: i64) -> blot_backend_layout::Id, blot_error::Error {
    if depth >= 128 { return 0, decline(generator, 1, blot_check_core::Span {..}, blot_check_diagnostic_code::Code.unresolved_type); } if requested == blot_backend_layout::erased { return actual, blot_error::Error.none; }
    let wanted = generator.representations.store.node(requested); let proven = generator.representations.store.node(actual);
    if wanted.tag != proven.tag { return 0, decline(generator, 1, blot_check_core::Span {..}, blot_check_diagnostic_code::Code.unresolved_type); }
    if wanted.tag != blot_backend_layout::Tag.function { return requested, blot_error::Error.none; }
    let input, input_error = completeRetainedRows(generator, wanted.a, proven.a, depth + 1); if input_error != blot_error::Error.none { return 0, input_error; }
    let output, output_error = completeRetainedRows(generator, wanted.b, proven.b, depth + 1); if output_error != blot_error::Error.none { return 0, output_error; }
    var row = wanted.c; if row == blot_backend_layout::unknown_row { row = proven.c; } return internLayoutWithEffects(generator, blot_backend_layout::Tag.function, input, output, row, []);
}
fn acyclicLayout(generator: Generator&, ty: blot_backend_layout::Id) -> bool, blot_error::Error { return blot_backend_acyclic_layout::proven(generator.representations.store, generator.units, ty); }
fn scalar(generator: Generator&, unit_id: u32, ty: blot_check_types::Id, mappings: const Mapping[:], span: blot_check_core::Span) -> Scalar, blot_error::Error {
    let selected, error = codeLayout(generator, unit_id, ty, mappings, span); if error != blot_error::Error.none { return 0, error; }
    let scalar = generator.representations.store.scalar(selected); if scalar.present { return scalar.value, blot_error::Error.none; } return blot_backend_runtime_ir::SC_pointer, blot_error::Error.none;
}
fn typeLayout(generator: Generator&, unit_id: u32, ty: blot_check_types::Id, mappings: const Mapping[:], span: blot_check_core::Span) -> blot_backend_layout::Id, blot_error::Error {
    let selected, error = generator.representations.store.fromType(generator.unit(unit_id), ty, mappings);
    if error == blot_error::Error.out_of_memory { return 0, error; } if error != blot_error::Error.none { return 0, decline(generator, unit_id, span, blot_check_diagnostic_code::Code.unresolved_type); } return selected, blot_error::Error.none;
}
fn codeLayout(generator: Generator&, unit_id: u32, ty: blot_check_types::Id, mappings: const Mapping[:], span: blot_check_core::Span) -> blot_backend_layout::Id, blot_error::Error {
    let selected, error = generator.representations.store.fromTypePartial(generator.unit(unit_id), ty, mappings);
    if error == blot_error::Error.out_of_memory { return 0, error; } if error != blot_error::Error.none { return 0, decline(generator, unit_id, span, blot_check_diagnostic_code::Code.unresolved_type); } return selected, blot_error::Error.none;
}
fn internLayout(generator: Generator&, tag: blot_backend_layout::Tag, a: u32, b: u32, values: const u32[:]) -> blot_backend_layout::Id, blot_error::Error {
    var selected: u32; var error: blot_error::Error; if tag == blot_backend_layout::Tag.record { selected,error = generator.representations.store.internRecord(values); } else { selected,error = generator.representations.store.intern(tag,a,b,values); }
    if error == blot_error::Error.out_of_memory { return 0,error; } if error != blot_error::Error.none { return 0,decline(generator,1,blot_check_core::Span {..},blot_check_diagnostic_code::Code.complexity); } return selected,blot_error::Error.none;
}
fn internLayoutWithEffects(generator: Generator&, tag: blot_backend_layout::Tag, a: u32, b: u32, row: u32, values: const u32[:]) -> blot_backend_layout::Id, blot_error::Error {
    let selected, error = generator.representations.store.internWithEffects(tag, a, b, row, values); if error == blot_error::Error.out_of_memory { return 0, error; } if error != blot_error::Error.none { return 0, decline(generator, 1, blot_check_core::Span {..}, blot_check_diagnostic_code::Code.complexity); } return selected, blot_error::Error.none;
}
fn codeLayoutWithRows(generator: Generator&, unit_id: u32, ty: blot_check_types::Id, mappings: const Mapping[:], rows: const RowMapping[:], span: blot_check_core::Span) -> blot_backend_layout::Id, blot_error::Error {
    let timing = generator.work_timing.enter(blot_backend_backend_timing::Phase.layouts); let selected, error = generator.representations.store.fromTypeWithRows(generator.unit(unit_id), ty, mappings, rows, true); timing.deinit();
    if error == blot_error::Error.out_of_memory { return 0, error; } if error != blot_error::Error.none { return 0, decline(generator, unit_id, span, blot_check_diagnostic_code::Code.unresolved_type); } return selected, blot_error::Error.none;
}
fn scalarWithRows(generator: Generator&, unit_id: u32, ty: blot_check_types::Id, mappings: const Mapping[:], rows: const RowMapping[:], span: blot_check_core::Span) -> Scalar, blot_error::Error {
    let selected, error = codeLayoutWithRows(generator, unit_id, ty, mappings, rows, span); if error != blot_error::Error.none { return 0, error; }
    let scalar = generator.representations.store.scalar(selected); if scalar.present { return scalar.value, blot_error::Error.none; } return blot_backend_runtime_ir::SC_pointer, blot_error::Error.none;
}
fn evaluationFailure(generator: Generator&) -> blot_error::Error {
    if generator.evaluator.diagnostic.present {
        let item = generator.evaluator.diagnostic.value; var code = item.code;
        if code == blot_check_diagnostic_code::Code.unsupported || code == blot_check_diagnostic_code::Code.cycle { code = blot_check_diagnostic_code::Code.constant_expression; }
        var span = item.span;
        if code == blot_check_diagnostic_code::Code.const_panic && !item.tag_origin && item.origins.len == 0 && generator.staging_trace.len == 0 { span = blot_check_core::Span {..}; }
        let fresh = !generator.diagnostic.present; let result = decline(generator, item.unit, span, code); generator.diagnostic.value.detail = item.detail;
        if fresh { generator.diagnostic.value.dispatch = item.dispatch; generator.diagnostic.value.implementation_trace = item.implementation_trace; generator.diagnostic.value.related = item.related; if item.origins.len != 0 { generator.diagnostic.value.origins = item.origins; } }
        return result;
    }
    return decline(generator, 1, blot_check_core::Span {..}, blot_check_diagnostic_code::Code.constant_expression);
}
fn constant(generator: Generator&, target: blot_check_core::BindingRef, ty: blot_backend_layout::Id) -> Value, blot_error::Error {
    let timing = generator.work_timing.enter(blot_backend_backend_timing::Phase.constants);
    var scope = blot_support::none<blot_reuse_code_artifacts::Scope>();
    if generator.artifacts {
        let opened, error = generator.artifacts.enter(blot_reuse_code_artifacts::Request.constant { key: blot_reuse_code_artifacts::ConstantKey { target: target, ty: ty , ..} , ..});
        if error != blot_error::Error.none { timing.deinit(); return Value {..}, error; } scope = blot_support::some(opened);
    }
    let value, error = constantScoped(generator, target, ty, scope);
    if scope.present { scope.value.deinit(); } timing.deinit(); return value, error;
}
fn constantScoped(generator: Generator&, target: blot_check_core::BindingRef, ty: blot_backend_layout::Id, scope: blot_support::Option<blot_reuse_code_artifacts::Scope>&) -> Value, blot_error::Error {
    let id, evaluated = generator.evaluator.richValue(target);
    if evaluated != blot_error::Error.none { if evaluated == blot_error::Error.out_of_memory { return Value {..}, evaluated; } return Value {..}, evaluationFailure(generator); }
    if generator.representations.store.node(ty).tag != blot_backend_layout::Tag.owning {
        let scalar = generator.evaluator.valueScalar(id);
        if scalar.present { if scope.present { let error = scope.value.completeValue(id, ty); if error != blot_error::Error.none { return Value {..}, error; } } return scalar.value, blot_error::Error.none; }
    }
    let bits, serialized = generator.static_data.serialize(generator, id, ty, 0); if serialized != blot_error::Error.none { return Value {..}, serialized; }
    if scope.present { let error = scope.value.completeValue(id, ty); if error != blot_error::Error.none { return Value {..}, error; } }
    let scalar = generator.representations.store.scalar(ty); var kind = blot_backend_runtime_ir::SC_pointer; if scalar.present { kind = scalar.value; } return Value { scalar: kind, bits: bits , ..}, blot_error::Error.none;
}
fn discardableClosure(generator: Generator&, owner: u32, catalog: u32) -> bool {
    let source .= generator.unit(owner); let metadata = source.closures[catalog];
    if metadata.qualifier != 0 && source.binding(metadata.qualifier).scheme.obligations.len != 0 { return false; }
    let body = source.node(metadata.body); if body.tag == blot_check_core::Tag.constant || body.tag == blot_check_core::Tag.panic { return true; }
    if body.tag != blot_check_core::Tag.reference { return false; } let reference = source.reference(metadata.body);
    return (reference.unit == 0 || reference.unit == owner) && reference.binding == metadata.parameter.binding;
}
recursive fn discardableValue(generator: Generator&, id: blot_eval_core_eval::ValueId, depth: i64) -> bool {
    if depth >= 256 { return false; } let info = generator.evaluator.valueInfo(id);
    if info.kind == blot_eval_eval_values::ValueKind.closure {
        let metadata = generator.evaluator.closureInfo(id); let source .= generator.unit(metadata.unit);
        if metadata.origin == blot_eval_eval_values::ClosureOrigin.named { let body .= source.body(metadata.identity); if body == null || body.scheme.obligations.len != 0 { return false; } }
        else if metadata.origin == blot_eval_eval_values::ClosureOrigin.anonymous { if !discardableClosure(generator, metadata.unit, metadata.identity) { return false; } }
        else if metadata.origin == blot_eval_eval_values::ClosureOrigin.operation { return false; }
    } else if info.kind != blot_eval_eval_values::ValueKind.scalar && info.kind != blot_eval_eval_values::ValueKind.array && info.kind != blot_eval_eval_values::ValueKind.list && info.kind != blot_eval_eval_values::ValueKind.cursor && info.kind != blot_eval_eval_values::ValueKind.product && info.kind != blot_eval_eval_values::ValueKind.record && info.kind != blot_eval_eval_values::ValueKind.nominal { return false; }
    for child in generator.evaluator.valueChildren(id) { if !discardableValue(generator, child, depth + 1) { return false; } } return true;
}
recursive fn retainedLayoutConcrete(generator: Generator&, ty: blot_backend_layout::Id, callable_rows: bool, depth: i64, budget: i64&) -> bool {
    if depth >= 128 || budget == 0 || ty == 0 || ty >= generator.representations.store.nodes.len { return false; } budget--;
    let node = generator.representations.store.node(ty);
    if node.tag == blot_backend_layout::Tag.associated || node.tag == blot_backend_layout::Tag.universal || node.tag == blot_backend_layout::Tag.existential || node.tag == blot_backend_layout::Tag.opened || node.tag == blot_backend_layout::Tag.invalid || node.tag == blot_backend_layout::Tag.erased { return false; }
    if node.tag == blot_backend_layout::Tag.unit || node.tag == blot_backend_layout::Tag.boolean || node.tag == blot_backend_layout::Tag.unsigned32 || node.tag == blot_backend_layout::Tag.floating32 || node.tag == blot_backend_layout::Tag.never || node.tag == blot_backend_layout::Tag.type_constructor || node.tag == blot_backend_layout::Tag.erased_proof { return true; }
    if node.tag == blot_backend_layout::Tag.function { return (callable_rows || node.c != blot_backend_layout::unknown_row) && retainedLayoutConcrete(generator, node.a, callable_rows, depth + 1, budget) && retainedLayoutConcrete(generator, node.b, callable_rows, depth + 1, budget); }
    if node.tag == blot_backend_layout::Tag.owning || node.tag == blot_backend_layout::Tag.array || node.tag == blot_backend_layout::Tag.list || node.tag == blot_backend_layout::Tag.cursor || node.tag == blot_backend_layout::Tag.resolver { return retainedLayoutConcrete(generator, node.a, false, depth + 1, budget); }
    if node.tag == blot_backend_layout::Tag.scoped { return node.b != 0 && node.c != 0 && retainedLayoutConcrete(generator, node.a, false, depth + 1, budget); }
    if node.tag == blot_backend_layout::Tag.provider { return node.c != blot_backend_layout::unknown_row && retainedLayoutConcrete(generator, node.a, false, depth + 1, budget); }
    if node.tag == blot_backend_layout::Tag.state_provider { return retainedLayoutConcrete(generator, node.a, false, depth + 1, budget) && retainedLayoutConcrete(generator, node.b, false, depth + 1, budget) && retainedLayoutConcrete(generator, node.c, false, depth + 1, budget); }
    let count = generator.representations.store.children(ty).len; var first = 0; var step = 1; if node.tag == blot_backend_layout::Tag.record { first = 1; step = 2; }
    var index = first; while index < count { if !retainedLayoutConcrete(generator, generator.representations.store.children(ty)[index], false, depth + 1, budget) { return false; } index += step; } return true;
}
fn nominalPayload(generator: Generator&, family: u64, tag: u32, ty: blot_backend_layout::Id) -> blot_backend_layout::Id, blot_error::Error {
    let owner = (family >> 32) as u32; let declaration = family as! u32; let source .= generator.unit(owner);
    for constructor in source.constructors {
        let nominal = source.nominal(constructor.nominal); if nominal.identity.unit != owner || nominal.identity.decl != declaration || constructor.tag != tag { continue; }
        let parameters = source.types.list(nominal.parameters); let arguments = generator.representations.store.children(ty);
        if parameters.len != arguments.len { return 0, decline(generator, owner, blot_check_core::Span {..}, blot_check_diagnostic_code::Code.unresolved_type); }
        if constructor.payload == 0 { return 1, blot_error::Error.none; } var mappings: Mapping[>..<] = [];
        for parameter, index in parameters { let error = mapType(generator, owner, mappings, parameter, arguments[index], blot_check_core::Span {..}); if error != blot_error::Error.none { return 0, error; } }
        return codeLayout(generator, owner, constructor.payload, mappings, blot_check_core::Span {..});
    }
    return 0, decline(generator, owner, blot_check_core::Span {..}, blot_check_diagnostic_code::Code.unresolved_type);
}
fn captureLayout<M,R>(generator: Generator&, owner: u32, binding: blot_check_core::BindingId, value: blot_eval_core_eval::ValueId, mappings: M&, rows: R&) -> blot_backend_layout::Id, blot_error::Error { let declaration = generator.unit(owner).binding(binding); return captureTypeLayout(generator, owner, declaration.ty, declaration.span, value, mappings, rows); }
fn captureTypeLayout<M,R>(generator: Generator&, owner: u32, ty: blot_check_types::Id, span: blot_check_core::Span, value: blot_eval_core_eval::ValueId, mappings: M&, rows: R&) -> blot_backend_layout::Id, blot_error::Error {
    let source .= generator.unit(owner); let concrete, initial = generator.representations.store.fromTypeWithRows(source, ty, mappingItems(mappings), rowItems(rows), false);
    if initial == blot_error::Error.none { return concrete, initial; } if initial == blot_error::Error.out_of_memory { return 0, initial; }
    let actual = generator.evaluator.valueEvidence(value);
    if actual != 0 {
        let selected, converted = generator.representations.fromEvidence(generator.evaluator.evidenceStore(), actual);
        if converted == blot_error::Error.out_of_memory { return 0, converted; } if converted != blot_error::Error.none { return 0, decline(generator, owner, span, blot_check_diagnostic_code::Code.unresolved_type); }
        let error = mapTypeDepth(generator, owner, mappings, rows, ty, selected, span, 0); if error != blot_error::Error.none { return 0, error; }
    }
    return codeLayoutWithRows(generator, owner, ty, mappingItems(mappings), rowItems(rows), span);
}
fn normalize(generator: Generator&, owner: u32, reference: blot_check_core::BindingRef) -> blot_check_core::BindingRef, blot_error::Error {
    var target = reference; if target.unit == 0 { target.unit = owner; }
    for step in 0..256 {
        if target.unit == 0 || target.unit > generator.units.len || target.binding == 0 || target.binding >= generator.unit(target.unit).bindings.len { return blot_check_core::BindingRef {..}, decline(generator, owner, blot_check_core::Span {..}, blot_check_diagnostic_code::Code.unsupported); }
        let source .= generator.unit(target.unit); let binding = source.binding(target.binding);
        if binding.kind == blot_reuse_principal_interface::Kind.external { let previous = target.unit; target = binding.target; if target.unit == 0 { target.unit = previous; } continue; }
        let body .= source.body(target.binding);
        if body != null { let tag = source.types.node(binding.ty).tag; if (tag == blot_check_types::Tag.function || tag == blot_check_types::Tag.forall) && body.parameters.len == 0 && source.node(body.root).tag == blot_check_core::Tag.reference { let previous = target.unit; target = source.reference(body.root); if target.unit == 0 { target.unit = previous; } continue; } }
        return target, blot_error::Error.none;
    }
    return blot_check_core::BindingRef {..}, decline(generator, owner, blot_check_core::Span {..}, blot_check_diagnostic_code::Code.complexity);
}
fn mappingEvidence(generator: Generator&, mappings: const Mapping[:]) -> u32, blot_error::Error {
    var words: u32[>..<] = [];
    for mapping in mappings {
        if mapping.instance.decl != 0 { continue; }
        let actual, error = generator.representations.toEvidence(generator.evaluator.evidenceStore(), mapping.layout);
        if error == blot_error::Error.unresolved_type { continue; } if error == blot_error::Error.out_of_memory { return 0, error; } if error != blot_error::Error.none { return 0, decline(generator, 1, blot_check_core::Span {..}, blot_check_diagnostic_code::Code.unresolved_type); }
        words.append([mapping.variable, actual]);
    }
    let result, error = generator.evaluator.storage.evidence.intern(blot_eval_type_evidence::Tag.record, 0, 0, words);
    if error == blot_error::Error.out_of_memory { return 0, error; } if error != blot_error::Error.none { return 0, decline(generator, 1, blot_check_core::Span {..}, blot_check_diagnostic_code::Code.unresolved_type); } return result, blot_error::Error.none;
}
fn rowMappingEvidence(generator: Generator&, rows: const RowMapping[:]) -> u32, blot_error::Error {
    var entries: blot_reuse_substitution_keys::Entry[>..<] = [];
    for mapping in rows {
        if mapping.row == blot_backend_layout::unknown_row { continue; }
        let actual, error = generator.representations.rowToEvidence(generator.evaluator.evidenceStore(), mapping.row);
        if error == blot_error::Error.unresolved_type { continue; } if error == blot_error::Error.out_of_memory { return 0, error; } if error != blot_error::Error.none { return 0, decline(generator, 1, blot_check_core::Span {..}, blot_check_diagnostic_code::Code.unresolved_type); }
        entries.push(blot_reuse_substitution_keys::Entry { variable: mapping.variable, value: actual , ..});
    }
    let result, error = generator.representations.row_keys.intern(entries);
    if error == blot_error::Error.out_of_memory { return 0, error; } if error != blot_error::Error.none { return 0, decline(generator, 1, blot_check_core::Span {..}, blot_check_diagnostic_code::Code.unresolved_type); } return result, blot_error::Error.none;
}
fn mappingItems(values: Mapping[>..<]&) -> Mapping[:] { return values[..]; }
fn mappingItems(values: blot_backend_substitution_buffers::Mappings&) -> Mapping[:] { return values.items; }
fn appendMappings(values: Mapping[>..<]&,value: Mapping) -> blot_error::Error { values.push(value); return blot_error::Error.none; }
fn appendMappings(values: blot_backend_substitution_buffers::Mappings&,value: Mapping) -> blot_error::Error { return values.push(value); }
fn rowItems(values: RowMapping[>..<]&) -> RowMapping[:] { return values[..]; }
fn rowItems(values: blot_backend_substitution_buffers::Rows&) -> RowMapping[:] { return values.items; }
fn appendRows(rows: RowMapping[>..<]&,value: RowMapping) -> blot_error::Error { rows.push(value); return blot_error::Error.none; }
fn appendRows(rows: blot_backend_substitution_buffers::Rows&,value: RowMapping) -> blot_error::Error { return rows.push(value); }
fn loadSemanticRows<R>(generator: Generator&, mappings: const blot_eval_type_evidence::RowMapping[:], rows: R&) -> blot_error::Error {
    for mapping in mappings {
        let concrete, error = generator.representations.rowFromEvidence(generator.evaluator.evidenceStore(), mapping.evidence);
        if error == blot_error::Error.out_of_memory { return error; } if error != blot_error::Error.none { return decline(generator, 1, blot_check_core::Span {..}, blot_check_diagnostic_code::Code.unresolved_type); }
        let appended = appendRows(rows,RowMapping { variable: mapping.variable,row: concrete , ..}); if appended != blot_error::Error.none { return appended; }
    }
    return blot_error::Error.none;
}
fn capturedTemplate(generator: Generator&, key: u32, binding: blot_check_core::BindingId) -> blot_support::Option<CapturedTemplate> {
    for entry in generator.representations.template_keys.get(key) { if entry.variable == binding { return blot_support::some(generator.planning.template_catalog.items[entry.value - 1]); } } return blot_support::none<CapturedTemplate>();
}
fn capturedStatic(generator: Generator&, key: u32, binding: blot_check_core::BindingId) -> blot_support::Option<blot_eval_core_eval::ValueId> {
    for entry in generator.representations.static_keys.get(key) { if entry.variable == binding { return blot_support::some(entry.value); } } return blot_support::none<blot_eval_core_eval::ValueId>();
}
fn directCallableEnvironment(generator: Generator&, ty: blot_backend_layout::Id, applied: i64) -> bool {
    var current = ty; var retained = blot_support::none<blot_backend_layout::Id>();
    for index in 0..applied { let arrow = generator.representations.store.node(current); if arrow.tag != blot_backend_layout::Tag.function { return false; } current = arrow.b; if generator.representations.store.node(arrow.a).tag == blot_backend_layout::Tag.erased_proof { continue; } if retained.present { return false; } retained = blot_support::some(arrow.a); }
    return retained.present && layoutRole(generator, retained.value) == blot_backend_runtime_ir::ROLE_reference;
}
const max_parameters: i64 = blot_backend_call_limits::max_parameters;
fn signature(generator: Generator&, target: blot_check_core::BindingRef, ty: blot_check_types::Id, source_id: u32, mappings: const Mapping[:], rows: const RowMapping[:], span: blot_check_core::Span, complete: bool) -> Key, blot_error::Error {
    let normalized, normalized_error = normalize(generator, source_id, target); if normalized_error != blot_error::Error.none { return Key {..}, normalized_error; }
    var key = Key { target: normalized , ..}; let root, root_error = functionRoot(generator, source_id, ty, span); if root_error != blot_error::Error.none { return key, root_error; } var current = root;
    var instances: blot_check_types::NominalIdentity[max_parameters] = [blot_check_types::NominalIdentity {..}; max_parameters]; var has_instances = false;
    let producer .= generator.unit(key.target.unit).body(key.target.binding); var limit = max_parameters; if producer != null && producer.parameters.len != 0 { limit = producer.parameters.len; }
    while generator.unit(source_id).types.node(current).tag == blot_check_types::Tag.function && key.count < limit {
        if key.count == max_parameters { return key, decline(generator, source_id, span, blot_check_diagnostic_code::Code.complexity); }
        let n = generator.unit(source_id).types.node(current); let input = generator.unit(source_id).types.node(n.a);
        if input.tag == blot_check_types::Tag.scoped {
            has_instances = true; instances[key.count] = blot_check_types::selectionAtom(generator.unit(source_id).types, blot_backend_layout::mappedInstance(blot_check_types::NominalIdentity { unit: input.b, decl: input.c , ..}, mappings));
        } else if has_instances { instances[key.count] = blot_check_types::NominalIdentity {..}; }
        if complete { let parameter, error = typeLayout(generator, source_id, n.a, mappings, span); if error != blot_error::Error.none { return key, error; } key.parameters[key.count] = parameter; }
        else { let parameter, error = codeLayoutWithRows(generator, source_id, n.a, mappings, rows, span); if error != blot_error::Error.none { return key, error; } key.parameters[key.count] = parameter; }
        let effects, error = generator.representations.store.rowFromType(generator.unit(source_id), n.c, mappings, rows, !complete);
        if error == blot_error::Error.out_of_memory { return key, error; } if error != blot_error::Error.none { return key, decline(generator, source_id, span, blot_check_diagnostic_code::Code.unresolved_type); }
        key.effects[key.count] = effects; key.count++; current = n.b;
    }
    if has_instances {
        let identity, error = generator.representations.instance_arguments.intern(instances[..key.count]);
        if error == blot_error::Error.out_of_memory { return key, error; } if error != blot_error::Error.none { return key, decline(generator, source_id, span, blot_check_diagnostic_code::Code.complexity); } key.instance_arguments = identity;
    }
    if complete { let result, error = typeLayout(generator, source_id, current, mappings, span); if error != blot_error::Error.none { return key, error; } key.result = result; }
    else { let result, error = codeLayoutWithRows(generator, source_id, current, mappings, rows, span); if error != blot_error::Error.none { return key, error; } key.result = result; }
    return key, blot_error::Error.none;
}
fn entrySignature(generator: Generator&, target: blot_check_core::BindingRef, ty: blot_check_types::Id, span: blot_check_core::Span) -> Key, blot_error::Error {
    let physical, initial_error = generator.representations.store.fromType(generator.unit(target.unit), ty, []);
    if initial_error == blot_error::Error.none { return signature(generator, target, ty, target.unit, [], [], span, true); }
    if initial_error == blot_error::Error.out_of_memory { return Key {..}, initial_error; }
    let value, evaluated = generator.evaluator.richValue(target);
    if evaluated != blot_error::Error.none { if evaluated == blot_error::Error.out_of_memory { return Key {..}, evaluated; } return Key {..}, evaluationFailure(generator); }
    let inferred, inference_error = generator.evaluator.inferEntryClosure(value);
    if inference_error != blot_error::Error.none {
        if inference_error == blot_error::Error.out_of_memory { return Key {..}, inference_error; }
        if inference_error == blot_error::Error.declined && generator.evaluator.diagnostic.present && generator.evaluator.diagnostic.value.code == blot_check_diagnostic_code::Code.unsupported { return Key {..}, decline(generator, target.unit, span, blot_check_diagnostic_code::Code.unresolved_type); }
        return Key {..}, evaluationFailure(generator);
    }
    if !inferred.present { return Key {..}, decline(generator, target.unit, span, blot_check_diagnostic_code::Code.entry_type); }
    let concrete, converted = generator.representations.fromEvidence(generator.evaluator.evidenceStore(), generator.evaluator.valueEvidence(inferred.value));
    if converted == blot_error::Error.out_of_memory { return Key {..}, converted; } if converted != blot_error::Error.none { return Key {..}, decline(generator, target.unit, span, blot_check_diagnostic_code::Code.unresolved_type); }
    var mappings: Mapping[>..<] = []; var rows: RowMapping[>..<] = [];
    let mapped = mapTypeDepth(generator, target.unit, mappings, rows, ty, concrete, span, 0); if mapped != blot_error::Error.none { return Key {..}, mapped; }
    let physical_final, checked = generator.representations.store.fromTypeWithRows(generator.unit(target.unit), ty, mappings, rows, false);
    if checked == blot_error::Error.out_of_memory { return Key {..}, checked; } if checked != blot_error::Error.none { return Key {..}, decline(generator, target.unit, span, blot_check_diagnostic_code::Code.unresolved_type); }
    return signature(generator, target, ty, target.unit, mappings, rows, span, false);
}
fn seedNamedInstance<M>(generator: Generator&, key: Key, mappings: M&) -> blot_error::Error {
    if key.instance_arguments == 0 { return blot_error::Error.none; } let source .= generator.unit(key.target.unit); let binding = source.binding(key.target.binding);
    let initial, error = functionRoot(generator, key.target.unit, binding.ty, binding.span); if error != blot_error::Error.none { return error; } var root = initial;
    for instance in generator.representations.instance_arguments.get(key.instance_arguments) {
        let arrow = source.types.node(root); if arrow.tag != blot_check_types::Tag.function { return decline(generator, key.target.unit, binding.span, blot_check_diagnostic_code::Code.unresolved_type); } root = arrow.b;
        let input = source.types.node(arrow.a); if input.tag != blot_check_types::Tag.scoped || input.b != 0 || instance.unit == 0 { continue; }
        var found = false; for entry in mappingItems(mappings) { if entry.variable != input.c { continue; } if entry.instance != instance { return decline(generator, key.target.unit, binding.span, blot_check_diagnostic_code::Code.unresolved_type); } found = true; break; }
        if !found { let appended = appendMappings(mappings,Mapping { variable: input.c,layout: blot_backend_layout::erased,instance: instance , ..}); if appended != blot_error::Error.none { return appended; } }
    }
    return blot_error::Error.none;
}
fn findRetained(generator: Generator&, retained: blot_reuse_artifact_fragment::State&, request: blot_reuse_code_artifacts::Request) -> blot_support::Option<u32>, blot_error::Error {
    let timing = generator.work_timing.enter(blot_backend_backend_timing::Phase.lookup); let found, error = retained.find(generator, request); timing.deinit(); return found, error;
}
fn reconstructRetained(generator: Generator&, retained: blot_reuse_artifact_fragment::State&, id: u32, request: blot_reuse_code_artifacts::Request, scope: blot_reuse_code_artifacts::Scope&?) -> u32, blot_error::Error {
    let timing = generator.work_timing.enter(blot_backend_backend_timing::Phase.replay); let rebuilt, error = retained.reconstruct(generator, id, request, scope); timing.deinit(); return rebuilt, error;
}
fn replayRequest(generator: Generator&, request: blot_reuse_code_artifacts::Request) -> u32, blot_error::Error {
    match request {
        named value => { return function(generator, value.key); },
        closure value => { return closureFunction(generator, value.key); },
        callable value => { return callable(generator, value.key); },
        constructor value => { return constructorFunction(generator, value.key); },
        primitive value => { return primitiveFunction(generator, value.key); },
        operation value => { return operationFunction(generator, value.key); },
        host value => { return hostFunction(generator, value.key); },
        constant value => { return 0, blot_error::Error.invalid_function_reference; },
        runtime_global value => { return 0, blot_error::Error.invalid_function_reference; },
    }
}
fn replayScalarConstant(generator: Generator&, request: blot_reuse_code_artifacts::Request) -> blot_error::Error {
    match request { constant value => { let scalar, error = constant(generator, value.key.target, value.key.ty); return error; }, _ => abort("expected constant artifact request") }
}
fn replayConstant(generator: Generator&, request: blot_reuse_code_artifacts::Request) -> u32, blot_error::Error {
    match request {
        constant item => { let value, error = constant(generator, item.key.target, item.key.ty); if error != blot_error::Error.none { return 0, error; } if value.scalar != blot_backend_runtime_ir::SC_pointer { return 0, blot_error::Error.invalid_function_reference; } return value.bits, blot_error::Error.none; },
        _ => abort("expected constant artifact request"),
    }
}
fn publishRetained(generator: Generator&, request: blot_reuse_code_artifacts::Request, function_id: u32) -> blot_error::Error {
    match request { named value => generator.planning.instances.insert(value.key, function_id), closure value => generator.planning.closures.insert(value.key, function_id), _ => return blot_error::Error.invalid_function_reference }
    return blot_error::Error.none;
}
fn publishRetainedStatic(generator: Generator&, function_id: u32) -> blot_error::Error { return generator.static_data.closures.push(function_id); }
fn publishRetainedResult(generator: Generator&, request: blot_reuse_code_artifacts::Request, template: blot_support::Option<u32>) -> blot_error::Error {
    if !template.present { return blot_error::Error.none; }
    match request { named value => generator.planning.template_results.insert(value.key, template.value), closure value => generator.planning.closure_template_results.insert(value.key, template.value), _ => return blot_error::Error.invalid_function_reference }
    return blot_error::Error.none;
}
fn unusedAggregate(generator: Generator&, unit_id: u32, binding: blot_check_core::BindingId) -> bool, blot_error::Error {
    block { let known = generator.planning.discard_proofs.get(unit_id); if known { return known.admits(binding), blot_error::Error.none; } }
    let proof,error = blot_backend_discarded_bindings::init(generator.planning.discard_flags, generator.unit(unit_id), unit_id);if error!=blot_error::Error.none {return false,error;}
    let admitted = proof.admits(binding); generator.planning.discard_proofs.insert(unit_id, proof); return admitted, blot_error::Error.none;
}
fn specializer(generator: Generator&) -> blot_eval_specialization::Service, blot_error::Error {
    let bridge, error = generator.representations.representationBridge(generator.evaluator.evidenceStore());
    return blot_eval_specialization::Service { timing: generator.work_timing, units: generator.units, evaluator: generator.evaluator, layouts: generator.representations.store, bridge: bridge, refinement_stats: generator.refinement_stats, refinement_regions: generator.work.refinement_regions, cache: generator , ..}, error;
}
fn lookupRefinement(generator: Generator&, root: blot_reuse_refinement_receipt::Root, shape: blot_reuse_code_expectation::View, expected: u32, seeds: const blot_eval_type_evidence::Mapping[:], rows: const blot_eval_type_evidence::RowMapping[:]) -> blot_support::Option<blot_eval_core_eval::SolvedEvidence>, blot_error::Error {
    let local, error = blot_reuse_refinement_receipt::lookupLocal(generator, root, expected, seeds, rows); if error != blot_error::Error.none || local.present { return local, error; }
    return blot_reuse_refinement_receipt::lookup(generator, root, shape, expected, seeds, rows);
}
fn recordRefinement(generator: Generator&, record: blot_eval_specialization::Record) -> blot_error::Error {
    return blot_reuse_refinement_receipt::record(generator, record.root, record.expected, record.seeds, record.rows, record.result, record.tape, record.observed, record.before_values, record.before_children, record.before_steps);
}
fn specializationFailure(generator: Generator&, service: blot_eval_specialization::Service, error: blot_error::Error) -> blot_error::Error {
    if error == blot_error::Error.out_of_memory { return error; } assert(service.failure.present); let failure = service.failure.value;
    match failure.code {
        evaluation => { return evaluationFailure(generator); }, complexity => { return decline(generator, failure.unit, failure.span, blot_check_diagnostic_code::Code.complexity); }, unresolved_type => { return decline(generator, failure.unit, failure.span, blot_check_diagnostic_code::Code.unresolved_type); },
    }
}
fn mapType<M>(generator: Generator&, unit_id: u32, mappings: M&, ty: blot_check_types::Id, concrete: u32, span: blot_check_core::Span) -> blot_error::Error {
    let service, error = specializer(generator); if error != blot_error::Error.none { return error; } let mapped = service.mapType(unit_id, mappings, ty, concrete, span); if mapped != blot_error::Error.none { return specializationFailure(generator, service, mapped); } return blot_error::Error.none;
}
fn mapTypeDepth(generator: Generator&, unit_id: u32, mappings: Mapping[>..<]&, rows: RowMapping[>..<]&?, ty: blot_check_types::Id, concrete: u32, span: blot_check_core::Span, depth: i64) -> blot_error::Error {
    let service, error = specializer(generator); if error != blot_error::Error.none { return error; } let mapped = service.mapTypeDepth(unit_id, mappings, rows, ty, concrete, span, depth); if mapped != blot_error::Error.none { return specializationFailure(generator, service, mapped); } return blot_error::Error.none;
}
fn mapTypeDepth(generator: Generator&,unit_id: u32,mappings: blot_backend_substitution_buffers::Mappings&,rows: blot_backend_substitution_buffers::Rows?,ty: u32,concrete: u32,span: blot_check_core::Span,depth: i64) -> blot_error::Error {
    let service,error = specializer(generator); if error != blot_error::Error.none { return error; } let mapped = service.mapTypeDepth(unit_id,mappings,rows,ty,concrete,span,depth); if mapped != blot_error::Error.none { return specializationFailure(generator,service,mapped); } return blot_error::Error.none;
}
fn mapFunctionResult<M,R>(generator: Generator&, unit_id: u32, mappings: M&, rows: R&, ty: blot_check_types::Id, concrete: u32, span: blot_check_core::Span) -> blot_error::Error {
    let service, error = specializer(generator); if error != blot_error::Error.none { return error; } let mapped = service.mapFunctionResult(unit_id, mappings, rows, ty, concrete, span, 0); if mapped != blot_error::Error.none { return specializationFailure(generator, service, mapped); } return blot_error::Error.none;
}
fn mapRow<M,R>(generator: Generator&, unit_id: u32, mappings: M&, rows: R&, source_row: u32, actual_row: u32, span: blot_check_core::Span, covariant: bool) -> blot_error::Error {
    let service, error = specializer(generator); if error != blot_error::Error.none { return error; } let mapped = service.mapRow(unit_id, mappings, rows, source_row, actual_row, span, covariant); if mapped != blot_error::Error.none { return specializationFailure(generator, service, mapped); } return blot_error::Error.none;
}
fn refineMappings<M,R>(generator: Generator&, unit_id: u32, root: blot_reuse_refinement_receipt::Root, expected: u32, mappings: M&, rows: R&, span: blot_check_core::Span) -> blot_error::Error {
    let service, error = specializer(generator); if error != blot_error::Error.none { return error; } let mapped = service.refineMappings(unit_id, root, expected, mappings, rows, span); if mapped != blot_error::Error.none { return specializationFailure(generator, service, mapped); } return blot_error::Error.none;
}
fn refineMappingsCaptures<M,R>(generator: Generator&, unit_id: u32, root: blot_reuse_refinement_receipt::Root, expected: u32, mappings: M&, rows: R&, span: blot_check_core::Span, captures: const blot_eval_core_eval::RetainedCapture[:]) -> blot_error::Error {
    let service, error = specializer(generator); if error != blot_error::Error.none { return error; } let mapped = service.refineMappingsCaptures(unit_id, root, expected, mappings, rows, span, captures); if mapped != blot_error::Error.none { return specializationFailure(generator, service, mapped); } return blot_error::Error.none;
}
fn refineAccessorMappings<M,R>(generator: Generator&, unit_id: u32, catalog: u32, expected: u32, mappings: M&, rows: R&, span: blot_check_core::Span, captures: const blot_eval_core_eval::RetainedCapture[:]) -> blot_error::Error {
    let projection,projection_error = blot_eval_specialization::physicalProjection(generator.representations.store,mappings); if projection_error != blot_error::Error.none { return projection_error; } let service, error = specializer(generator); if error != blot_error::Error.none { return error; }
    let selected = blot_eval_core_eval::CodeProjection.static_code { projection , ..}; service.code_projection = blot_support::some(selected);
    let mapped = service.refineMappingsCaptures(unit_id, blot_reuse_refinement_receipt::Root.closure { unit: unit_id, catalog: catalog , ..}, expected, mappings, rows, span, captures);
    if mapped != blot_error::Error.none { return specializationFailure(generator, service, mapped); } return blot_error::Error.none;
}
fn mapCapturedFunction<M,R>(generator: Generator&, unit_id: u32, function_type: blot_check_types::Id, expected: u32, mappings: M&, rows: R&, span: blot_check_core::Span) -> blot_error::Error {
    let source = unit(generator, unit_id).types.node(function_type); let actual = generator.representations.store.node(expected);
    if source.tag != blot_check_types::Tag.function || actual.tag != blot_backend_layout::Tag.function { return decline(generator, unit_id, span, blot_check_diagnostic_code::Code.unresolved_type); }
    let a = mapTypeDepth(generator, unit_id, mappings, rows, source.a, actual.a, span, 0); if a != blot_error::Error.none { return a; }
    let b = mapTypeDepth(generator, unit_id, mappings, rows, source.b, actual.b, span, 0); if b != blot_error::Error.none { return b; }
    return mapRow(generator, unit_id, mappings, rows, source.c, actual.c, span, true);
}
fn completedQueryLookup(generator: Generator&, session: blot_eval_core_eval::Session&, input: u32, expected: u32) -> blot_support::Option<u32>, blot_error::Error {
    if !(session .== generator.evaluator) { return blot_support::none<u32>(), blot_error::Error.none; }
    let query .= generator.query_state; if query { return query.lookup(generator, input, expected); } return blot_support::none<u32>(), blot_error::Error.none;
}
fn completedMemberLookup(generator: Generator&, session: blot_eval_core_eval::Session&, target: blot_check_core::BindingRef, input: u32, expected: u32) -> blot_support::Option<u32>, blot_error::Error {
    if !(session .== generator.evaluator) { return blot_support::none<u32>(), blot_error::Error.none; }
    let query .= generator.query_state; if query { return query.lookupMember(generator, target, input, expected); } return blot_support::none<u32>(), blot_error::Error.none;
}
fn lookupSpecialization(generator: Generator&, session: blot_eval_core_eval::Session&, input: u32, expected: u32) -> blot_support::Option<u32>, blot_error::Error { return completedQueryLookup(generator, session, input, expected); }
fn lookupMemberSpecialization(generator: Generator&, session: blot_eval_core_eval::Session&, target: blot_check_core::BindingRef, input: u32, expected: u32) -> blot_support::Option<u32>, blot_error::Error { return completedMemberLookup(generator, session, target, input, expected); }
fn constantLookup(generator: Generator&, session: blot_eval_core_eval::Session&, target: blot_check_core::BindingRef, inputs: blot_reuse_constant_receipt::Inputs) -> blot_support::Option<blot_reuse_constant_receipt::Lookup>, blot_error::Error {
    if !(session .== generator.evaluator) { return blot_support::none<blot_reuse_constant_receipt::Lookup>(), blot_error::Error.none; }
    if generator.constant_state != null { return generator.constant_state.lookup(generator, target, inputs); } return blot_support::none<blot_reuse_constant_receipt::Lookup>(), blot_error::Error.none;
}
fn principalLookup(generator: Generator&, target: blot_check_core::BindingRef, options: blot_eval_core_eval::Options) -> blot_support::Option<blot_eval_core_eval::SolvedEvidence>, blot_error::Error {
    if generator.persisted_principals != null { generator.persisted_principals.clearInputs(); }
    if generator.principal_state != null { let solved, error = generator.principal_state.lookup(generator, target, options); if error != blot_error::Error.none || solved.present { return solved, error; } }
    else { generator.principal_stats.requests++; generator.principal_stats.missing++; }
    if generator.persisted_principals != null { return generator.persisted_principals.lookup(generator.evaluator, target, options); }
    return blot_support::none<blot_eval_core_eval::SolvedEvidence>(), blot_error::Error.none;
}
fn principalGraphLookup(generator: Generator&, key: blot_eval_core_eval::PrincipalGraphKey) -> blot_eval_core_eval::PrincipalGraph&? {
    if generator.principal_state == null { return null; } let state .= generator.principal_state;
    if state.gate.source_pools == null || !state.old.metadata.pools.present { return null; }
    let gate_pools .= state.gate.source_pools; let captured_pools: const blot_reuse_code_artifacts::Pools& = state.old.metadata.pools.value;
    if !(gate_pools .== captured_pools) { return null; }
    if generator.allocation_owner == 0 || state.old.metadata.allocation_owner != generator.allocation_owner { return null; }
    return state.old.metadata.principal_graphs.lookup(key, state.gate);
}
fn principalRecord(generator: Generator&, target: blot_check_core::BindingRef, options: blot_eval_core_eval::Options, solved: blot_eval_core_eval::SolvedEvidence, inputs: const blot_reuse_principal_inputs::Key&?) -> blot_error::Error {
    var selected .= inputs;
    if selected == null && generator.principal_state != null { selected .= generator.principal_state.last_inputs; }
    if selected == null && generator.persisted_principals != null && generator.persisted_principals.last_inputs.present { selected .= generator.persisted_principals.last_inputs.value; }
    if generator.artifacts != null { return generator.artifacts.recordPrincipal(target, options, solved, selected); } return blot_error::Error.none;
}
fn principalStats(generator: const Generator&) -> blot_reuse_principal_evidence_reuse::Stats {
    var result = generator.principal_stats; if generator.principal_state != null { result = generator.principal_state.stats; } result.fresh_regions = generator.evaluator.principal_regions;
    if generator.persisted_principals != null {
        result.persisted_requests = generator.persisted_principals.stats.requests; result.persisted_hits = generator.persisted_principals.stats.hits;
        result.persisted_nonempty_hits = generator.persisted_principals.stats.nonempty_hits; result.persisted_call_proofs = generator.persisted_principals.stats.call_proofs; result.persisted_declines = generator.persisted_principals.stats.declined;
    }
    if generator.artifacts != null { result.captured = generator.artifacts.principal_queries.records.len; } return result;
}
struct NamedEmission { key: Key, body: const blot_check_core::Body&, parameter_locals: u32[16], runtime_count: u32, root: u32 }
fn emitNamedOwner(context: NamedEmission&, emitter: blot_backend_backend_emission::Owner&) -> blot_error::Error {
    let generator .= emitter.generator; let source .= unit(generator, context.key.target.unit); let body .= context.body; let key = context.key;
    for parameter, index in source.bodyParameters(body) {
        if parameter.binding == 0 { continue; } let local = context.parameter_locals[index]; if local == 4294967295 { continue; }
        let retained = capturedTemplate(generator, key.templates, parameter.binding);
        if retained.present {
            let template = retained.value; var environment = blot_support::none<u32>(); if template.has_environment { environment = blot_support::some(local); }
            emitter.templates.insert(parameter.binding, blot_backend_backend_emission::Template { scalar_environment: template.scalar_environment, callable_instances: template.callable_instances, staged: template.staged, unit: template.unit, node: template.node, environment: environment, captures: template.captures, templates: template.templates, computation: template.computation, evidence: template.evidence, rows: template.rows , ..});
        } else { emitter.locals.insert(parameter.binding, local); }
    }
    if key.dictionaries {
        let owner = blot_check_dictionary_owner::forBinding(source, body.binding); assert(owner.present);
        let error = emitter.installDictionary(body.root, context.runtime_count + 1, owner.value); if error != blot_error::Error.none { return error; }
    }
    if key.template_result {
        let error = emitter.bodyExpression(context.root, 0, true); if error != blot_error::Error.none { return error; }
        if !emitter.result_template.present { return fail(generator, key.target.unit, body.root, blot_check_diagnostic_code::Code.unresolved_type); } generator.planning.template_results.insert(key, emitter.result_template.value);
    } else {
        let error = emitter.bodyExpression(context.root, 0, false); if error != blot_error::Error.none { return error; }
        if source.types.node(source.typeOf(body.root)).tag == blot_check_types::Tag.never { return emitter.emit(blot_backend_runtime_ir::OP_unreachable_, 0); }
    }
    return blot_error::Error.none;
}
fn namedAlias(generator: Generator&, key: Key, body: const blot_check_core::Body&, function_id: u32, scope: blot_support::Option<blot_reuse_code_artifacts::Scope>&) -> u32, blot_error::Error {
    let unit_id = key.target.unit; let source .= unit(generator, unit_id); var full = key.result; var reverse = key.count as i64;
    while reverse > 0 { reverse--; let ty, error = internLayoutWithEffects(generator, blot_backend_layout::Tag.function, key.parameters[reverse], full, key.effects[reverse], []); if error != blot_error::Error.none { return 0, error; } full = ty; }
    if source.binding(key.target.binding).has_explicit {
        var mappings: Mapping[>..<] = []; var rows: RowMapping[>..<] = [];
        let error = refineMappings(generator, unit_id, blot_reuse_refinement_receipt::Root.body { key.target , ..}, full, mappings, rows, body.span); if error != blot_error::Error.none { return 0, error; }
    }
    let root = source.node(body.root);
    if !body.runtime && root.tag == blot_check_core::Tag.primitive_function {
        let primitive = source.primitives[root.a];
        if primitive.kind == blot_check_core::PrimitiveKind.scalar && primitive.arity == key.count && key.count != 0 {
            let operand = generator.representations.store.scalar(key.parameters[0]);
            if operand.present {
                let opcode = blot_backend_scalar_ops::opcode(primitive.op, operand.value);
                if opcode.present {
                    var mappings: Mapping[>..<] = []; let error = mapType(generator, unit_id, mappings, root.ty, full, body.span); if error != blot_error::Error.none { return 0, error; }
                    for index in 0..key.count { let emitted = generator.module.emit(function_id, blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, index as u32)); if emitted != blot_error::Error.none { return 0, emitted; } }
                    let emitted = generator.module.emit(function_id, blot_backend_runtime_ir::instruction(opcode.value)); if emitted != blot_error::Error.none { return 0, emitted; }
                    if scope.present { let completed = scope.value.complete(function_id, blot_support::none<u32>()); if completed != blot_error::Error.none { return 0, completed; } }
                    generator.planning.startup_facts.complete(function_id); return function_id, blot_error::Error.none;
                }
            }
        }
    }
    var global = blot_support::none<u32>(); if body.runtime { let value, error = generator.planning.runtimeGlobal(generator, key.target); if error != blot_error::Error.none { return 0, error; } global = blot_support::some(value); }
    var constant_value: Value;
    if !global.present { let value, error = constant(generator, key.target, full); if error != blot_error::Error.none { return 0, error; } constant_value = value; }
    let callee, local_error = generator.module.addLocal(function_id, blot_backend_runtime_ir::VT_i32); if local_error != blot_error::Error.none { return 0, local_error; }
    if global.present { let error = generator.module.emit(function_id, blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_get, global.value)); if error != blot_error::Error.none { return 0, error; } }
    else { let error = emitValue(generator, function_id, constant_value); if error != blot_error::Error.none { return 0, error; } }
    var ty = full;
    for index in 0..key.count {
        let arrow = generator.representations.store.node(ty); if arrow.tag != blot_backend_layout::Tag.function { return 0, decline(generator, unit_id, body.span, blot_check_diagnostic_code::Code.unresolved_type); }
        let inputs: blot_backend_runtime_ir::ValueType[3] = [blot_backend_runtime_ir::VT_i32, generator.representations.store.machine(arrow.a), blot_backend_runtime_ir::VT_i32];
        let signature, signature_error = generator.module.internType(inputs, generator.representations.store.machine(arrow.b)); if signature_error != blot_error::Error.none { return 0, signature_error; }
        let prefix: blot_backend_runtime_ir::Instruction[8] = [
            blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set, callee), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, callee),
            blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load, 4), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, index as u32),
            blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, key.count as u32), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, callee),
            blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load), blot_backend_runtime_ir::callResult(layoutRole(generator, arrow.b)),
        ];
        let emitted = generator.module.emitSlice(function_id, prefix); if emitted != blot_error::Error.none { return 0, emitted; }
        let called = generator.module.emit(function_id, blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call_indirect, signature)); if called != blot_error::Error.none { return 0, called; }
        if generator.request_owner.present { let guarded = blot_runtime_request_runtime::guard_(generator.module, function_id, generator.request_owner.value, []); if guarded != blot_error::Error.none { return 0, guarded; } }
        ty = arrow.b;
    }
    if scope.present { let completed = scope.value.complete(function_id, lookupValue(generator.planning.template_results, key)); if completed != blot_error::Error.none { return 0, completed; } }
    generator.planning.startup_facts.complete(function_id); return function_id, blot_error::Error.none;
}
fn function(generator: Generator&, key: Key) -> u32, blot_error::Error {
    let stage = generator.evaluator.enterInferenceStage(blot_work_counters::InferenceStage.specialization);
    recursive fn cleanup_continuation_28() -> u32, blot_error::Error {

    var scope = blot_support::none<blot_reuse_code_artifacts::Scope>();
    if generator.artifacts != null { let entered, error = generator.artifacts.enter(blot_reuse_code_artifacts::Request.named { key , ..}); if error != blot_error::Error.none { return 0, error; } scope = blot_support::some(entered); }

    recursive fn cleanup_continuation_27() -> u32, blot_error::Error {

    block {
        let existing = generator.planning.instances.get(key);
        if existing {
            let error = generator.planning.startup_facts.request(existing, blot_backend_startup_emission_facts::Kind.named, key.target.unit, key.target.binding, true); if error != blot_error::Error.none { return 0, error; }
            if scope.present { let hit = scope.value.hit(existing); if hit != blot_error::Error.none { return 0, hit; } } return existing, blot_error::Error.none;
        }
    }
    if generator.retained != null {
        let job, error = findRetained(generator, generator.retained, blot_reuse_code_artifacts::Request.named { key , ..}); if error != blot_error::Error.none { return 0, error; }
        if job.present {
            var actor: blot_reuse_code_artifacts::Scope&? = null; if scope.present { actor .= scope.value; }
            let function_id, replayed = reconstructRetained(generator, generator.retained, job.value, blot_reuse_code_artifacts::Request.named { key , ..}, actor); if replayed != blot_error::Error.none { return 0, replayed; }
            let requested = generator.planning.startup_facts.request(function_id, blot_backend_startup_emission_facts::Kind.named, key.target.unit, key.target.binding, true); if requested != blot_error::Error.none { return 0, requested; }
            generator.planning.startup_facts.complete(function_id); return function_id, blot_error::Error.none;
        }
    }
    generator.work.fresh_named++; let unit_id = key.target.unit; let source .= unit(generator, unit_id); let body .= source.body(key.target.binding);
    if body == null { return 0, decline(generator, unit_id, source.binding(key.target.binding).span, blot_check_diagnostic_code::Code.unsupported); }
    if body.is_function && body.parameters.len != key.count { return 0, decline(generator, unit_id, body.span, blot_check_diagnostic_code::Code.unsupported); }
    if generator.instance_depth >= 256 || generator.planning.instances.count >= 65536 { return 0, decline(generator, unit_id, body.span, blot_check_diagnostic_code::Code.complexity); }
    generator.instance_depth++;
    recursive fn cleanup_continuation_26() -> u32, blot_error::Error {

    var parameters: blot_backend_runtime_ir::ValueType[18]; var roles: blot_backend_runtime_ir::Role[18]; var parameter_locals: u32[16] = [4294967295; 16]; var runtime_count: u32 = 0;
    for item, index in key.parameters[..key.count] {
        if generator.representations.store.node(item).tag == blot_backend_layout::Tag.erased_proof { continue; }
        parameter_locals[index] = runtime_count; parameters[runtime_count] = generator.representations.store.machine(item); roles[runtime_count] = layoutRole(generator, item);
        if body.is_function { let template = capturedTemplate(generator, key.templates, source.bodyParameters(body)[index].binding); if template.present && template.value.scalar_environment { roles[runtime_count] = blot_backend_runtime_ir::ROLE_scalar; } }
        runtime_count++;
    }
    if !body.is_function && runtime_count != key.count { return 0, decline(generator, unit_id, body.span, blot_check_diagnostic_code::Code.unsupported); }
    parameters[runtime_count] = blot_backend_runtime_ir::VT_i32; roles[runtime_count] = blot_backend_runtime_ir::ROLE_reference; var machine_count = runtime_count + 1;
    if key.dictionaries {
        if !blot_check_dictionary_owner::forBinding(source, body.binding).present { return 0, decline(generator, unit_id, body.span, blot_check_diagnostic_code::Code.unsupported); }
        parameters[machine_count] = blot_backend_runtime_ir::VT_i32; roles[machine_count] = blot_backend_runtime_ir::ROLE_reference; machine_count++;
    }
    let function_id, added = generator.module.addTypedFunction(parameters[..machine_count], resultMachine(generator, key.result), bodyResultRole(generator, key.result, unit_id, body.root)); if added != blot_error::Error.none { return 0, added; }
    let described = setParameterRoles(generator, function_id, blot_backend_runtime_ir::packParameterRoles(roles[..machine_count]), blot_support::some(runtime_count as u16)); if described != blot_error::Error.none { return 0, described; }
    generator.planning.instances.insert(key, function_id);
    if scope.present { let reserved = scope.value.reserve(function_id); if reserved != blot_error::Error.none { return 0, reserved; } }
    let requested = generator.planning.startup_facts.request(function_id, blot_backend_startup_emission_facts::Kind.named, unit_id, key.target.binding, false); if requested != blot_error::Error.none { return 0, requested; }
    let caller = generator.planning.startup_facts.active; generator.planning.startup_facts.active = function_id;
    recursive fn cleanup_continuation_25() -> u32, blot_error::Error {

    if !body.is_function { return namedAlias(generator, key, body, function_id, scope); }
    let service, service_error = specializer(generator); if service_error != blot_error::Error.none { return 0, service_error; }
    var mappings: Mapping[>..<] = []; var rows: RowMapping[>..<] = [];
    let resolved, resolved_error = service.named(key, generator.representations.instance_arguments.get(key.instance_arguments), mappings, rows);
    if resolved_error != blot_error::Error.none { return 0, specializationFailure(generator, service, resolved_error); }
    if key.dictionaries {
        let owner = blot_check_dictionary_owner::forBinding(source, body.binding); if !owner.present { return 0, decline(generator, unit_id, body.span, blot_check_diagnostic_code::Code.unsupported); }
        let error = blot_backend_dictionary_layout::bindOwner(source, generator.representations.store, mappings, owner.value, 0, owner.value.formals(source), false);
        if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0, error; } return 0, fail(generator, unit_id, body.root, blot_check_diagnostic_code::Code.unresolved_type); }
    }
    var context = NamedEmission { key, body, parameter_locals, runtime_count, resolved.root , ..};
    let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { generator: generator, unit_id: unit_id, function_id: function_id, provider_local: blot_support::some(runtime_count), mappings: mappings, row_mappings: rows, factory_template: key.template_result , ..}, context, emitNamedOwner);
    if emitted != blot_error::Error.none { return 0, emitted; }
    if scope.present {
        let solved = scope.value.solved(mappings, rows, generator.representations.template_keys.get(key.templates)); if solved != blot_error::Error.none { return 0, solved; }
        let completed = scope.value.complete(function_id, lookupValue(generator.planning.template_results, key)); if completed != blot_error::Error.none { return 0, completed; }
    }
    generator.planning.startup_facts.complete(function_id); return function_id, blot_error::Error.none;

    }
    let cleanup_result_25_0,cleanup_result_25_1 = cleanup_continuation_25();
     generator.planning.startup_facts.active = caller;
    return cleanup_result_25_0,cleanup_result_25_1;

    }
    let cleanup_result_26_0,cleanup_result_26_1 = cleanup_continuation_26();
     generator.instance_depth--;
    return cleanup_result_26_0,cleanup_result_26_1;

    }
    let cleanup_result_27_0,cleanup_result_27_1 = cleanup_continuation_27();
     if scope.present { scope.value.deinit(); }
    return cleanup_result_27_0,cleanup_result_27_1;

    }
    let cleanup_result_28_0,cleanup_result_28_1 = cleanup_continuation_28();
     stage.deinit();
    return cleanup_result_28_0,cleanup_result_28_1;
}

fn lookupValue<K,V>(map: const dictionary<K,V>&, key: K) -> blot_support::Option<V> { let value = map.get(key); if value { return blot_support::some(value); } return blot_support::none<V>(); }
fn captureTemplate(generator: Generator&, template: blot_backend_backend_emission::Template) -> u32, blot_error::Error {
    let retained = CapturedTemplate { unit: template.unit, node: template.node, captures: template.captures, templates: template.templates, staged: template.staged, has_environment: template.environment.present, scalar_environment: template.scalar_environment, computation: template.computation, evidence: template.evidence, rows: template.rows, callable_instances: template.callable_instances , ..};
    block { let existing = generator.planning.template_instances.get(retained); if existing { return existing, blot_error::Error.none; } }
    if generator.planning.template_catalog.len >= 4294967295 { return 0, blot_error::Error.module_too_large; }
    let id = (generator.planning.template_catalog.len + 1) as u32; let pushed=generator.planning.template_catalog.push(retained);if pushed!=blot_error::Error.none {return 0,pushed;} generator.planning.template_instances.insert(retained, id); return id, blot_error::Error.none;
}
reusable[] var retained_rows: blot_eval_type_evidence::RowMapping[>..] = [];
reusable[] var retained_values: blot_eval_core_eval::RetainedValue[>..] = [];
reusable[] var retained_children: blot_eval_core_eval::RetainedCapture[>..] = [];
recursive fn releaseRetainedCapture(capture: blot_eval_core_eval::RetainedCapture) {
    for child in capture.captures { releaseRetainedCapture(child); }
    if capture.rows.len != 0 { let first: const blot_eval_type_evidence::RowMapping& = capture.rows[0]; let at = retained_rows.index_of(first); retained_rows.free_slice(retained_rows[at..at + capture.rows.len]); }
    if capture.values.len != 0 { let first: const blot_eval_core_eval::RetainedValue& = capture.values[0]; let at = retained_values.index_of(first); retained_values.free_slice(retained_values[at..at + capture.values.len]); }
    if capture.captures.len != 0 { let first: const blot_eval_core_eval::RetainedCapture& = capture.captures[0]; let at = retained_children.index_of(first); retained_children.free_slice(retained_children[at..at + capture.captures.len]); }
}
recursive fn retainedCapture(generator: Generator&, binding: blot_check_core::BindingId, template: CapturedTemplate, depth: i64) -> blot_eval_core_eval::RetainedCapture, blot_error::Error {
    if depth >= 256 { return default<blot_eval_core_eval::RetainedCapture>(), fail(generator, template.unit, template.node, blot_check_diagnostic_code::Code.complexity); }
    var rows: blot_eval_type_evidence::RowMapping[>..<] = []; for row in generator.representations.row_keys.get(template.rows) { rows.push(blot_eval_type_evidence::RowMapping { row.variable, row.value , ..}); }
    var children: blot_eval_core_eval::RetainedCapture[>..<] = []; var values: blot_eval_core_eval::RetainedValue[>..<] = []; var published = false;

    recursive fn cleanup_continuation_24() -> blot_eval_core_eval::RetainedCapture, blot_error::Error {

    let source .= unit(generator, template.unit); let n = source.node(template.node);
    if n.tag == blot_check_core::Tag.closure {
        let capture_list = source.extra[source.closures[n.a].captures.start..source.closures[n.a].captures.start + source.closures[n.a].captures.len];
        for captured, index in capture_list {
            let child = capturedTemplate(generator, template.templates, captured);
            if child.present { let value, error = retainedCapture(generator, captured, child.value, depth + 1); if error != blot_error::Error.none { return default<blot_eval_core_eval::RetainedCapture>(), error; } children.push(value); }
            else if index < generator.representations.store.children(template.captures).len {
                let actual, error = generator.representations.toEvidence(generator.evaluator.evidenceStore(), generator.representations.store.children(template.captures)[index]);
                if error != blot_error::Error.none { if error == blot_error::Error.unresolved_type { continue; } if error == blot_error::Error.out_of_memory { return default<blot_eval_core_eval::RetainedCapture>(), error; } return default<blot_eval_core_eval::RetainedCapture>(), fail(generator, template.unit, template.node, blot_check_diagnostic_code::Code.unresolved_type); }
                values.push(blot_eval_core_eval::RetainedValue { captured, actual , ..});
            }
        }
    }
    let owned_rows = retained_rows.alloc_slice(rows.len); for row, index in rows { owned_rows[index] = row; }
    let owned_values = retained_values.alloc_slice(values.len); for value, index in values { owned_values[index] = value; }
    let owned_children = retained_children.alloc_slice(children.len); for child, index in children { owned_children[index] = child; }
    published = true; return blot_eval_core_eval::RetainedCapture { binding: binding, unit: template.unit, node: template.node, mappings: template.evidence, rows: owned_rows, values: owned_values, captures: owned_children, computation: template.computation , ..}, blot_error::Error.none;

    }
    let cleanup_result_24_0,cleanup_result_24_1 = cleanup_continuation_24();
     if !published { for child in children { releaseRetainedCapture(child); } }
    return cleanup_result_24_0,cleanup_result_24_1;
}
fn resolveClosureMappings<M,R>(generator: Generator&, key: blot_reuse_code_artifacts::ClosureKey, mappings: M&, rows: R&) -> blot_error::Error {
    let source .= unit(generator, key.unit); let metadata = source.closures[key.catalog]; let captures = source.extra[metadata.captures.start..metadata.captures.start + metadata.captures.len]; let fn_type = generator.representations.store.node(key.ty);
    for entry in generator.representations.row_keys.get(key.rows) {
        let concrete, error = generator.representations.rowFromEvidence(generator.evaluator.evidenceStore(), entry.value); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return error; } return fail(generator, key.unit, metadata.body, blot_check_diagnostic_code::Code.unresolved_type); }
        let appended = appendRows(rows,RowMapping { entry.variable,concrete , ..}); if appended != blot_error::Error.none { return appended; }
    }
    if key.evidence != 0 {
        let words = generator.evaluator.storage.evidence.children(key.evidence); var index: i64 = 0;
        while index < words.len {
            let concrete, error = generator.representations.fromEvidence(generator.evaluator.evidenceStore(), words[index + 1]); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return error; } return fail(generator, key.unit, metadata.body, blot_check_diagnostic_code::Code.unresolved_type); }
            let mapped = mapType(generator, key.unit, mappings, words[index], concrete, source.span(metadata.body)); if mapped != blot_error::Error.none { return mapped; } index += 2;
        }
    }
    for binding, index in captures {
        if capturedTemplate(generator, key.templates, binding).present || capturedStatic(generator, key.static_values, binding).present { continue; }
        let error = mapType(generator, key.unit, mappings, source.binding(binding).ty, generator.representations.store.children(key.captures)[index], source.span(metadata.body)); if error != blot_error::Error.none { return error; }
    }
    let input = mapType(generator, key.unit, mappings, metadata.parameter.ty, fn_type.a, metadata.parameter.span); if input != blot_error::Error.none { return input; }
    let output = mapType(generator, key.unit, mappings, source.typeOf(metadata.body), fn_type.b, source.span(metadata.body)); if output != blot_error::Error.none { return output; }
    if metadata.function_type != 0 { let error = mapTypeDepth(generator, key.unit, mappings, rows, metadata.function_type, key.ty, source.span(metadata.body), 0); if error != blot_error::Error.none { return error; } }
    var hints = blot_backend_substitution_buffers::Hints {..};
    recursive fn cleanup_continuation_23() -> blot_error::Error {

    for binding in captures {
        let captured = capturedStatic(generator, key.static_values, binding);
        if captured.present { let appended = hints.push(blot_eval_core_eval::RetainedCapture { value: captured.value,binding: binding,unit: key.unit,node: 0 , ..}); if appended != blot_error::Error.none { return appended; } }
        else { let template = capturedTemplate(generator, key.templates, binding); if template.present { let hint, error = retainedCapture(generator, binding, template.value, 0); if error != blot_error::Error.none { return error; } let appended = hints.push(hint); if appended != blot_error::Error.none { releaseRetainedCapture(hint); return appended; } } }
    }
    if key.parameter_template != 0 { let hint, error = retainedCapture(generator, metadata.parameter.binding, generator.planning.template_catalog.items[key.parameter_template - 1], 0); if error != blot_error::Error.none { return error; } let appended = hints.push(hint); if appended != blot_error::Error.none { releaseRetainedCapture(hint); return appended; } }
    return refineMappingsCaptures(generator, key.unit, blot_reuse_refinement_receipt::Root.closure { key.unit, key.catalog , ..}, key.ty, mappings, rows, source.span(metadata.body), hints.items);

    }
    let cleanup_result_23_0 = cleanup_continuation_23();
     for hint in hints.items { releaseRetainedCapture(hint); } hints.deinit();
    return cleanup_result_23_0;
}
fn templateMetadata(template: CapturedTemplate, local: u32) -> blot_backend_backend_emission::Template {
    var environment = blot_support::none<u32>(); if template.has_environment { environment = blot_support::some(local); }
    return blot_backend_backend_emission::Template { scalar_environment: template.scalar_environment, callable_instances: template.callable_instances, staged: template.staged, unit: template.unit, node: template.node, environment: environment, captures: template.captures, templates: template.templates, computation: template.computation, evidence: template.evidence, rows: template.rows , ..};
}
fn enterScope(generator: Generator&, request: blot_reuse_code_artifacts::Request) -> blot_support::Option<blot_reuse_code_artifacts::Scope>, blot_error::Error {
    if generator.artifacts == null { return blot_support::none<blot_reuse_code_artifacts::Scope>(), blot_error::Error.none; }
    let entered, error = generator.artifacts.enter(request); if error != blot_error::Error.none { return blot_support::none<blot_reuse_code_artifacts::Scope>(), error; } return blot_support::some(entered), blot_error::Error.none;
}
struct ClosureEmission { key: blot_reuse_code_artifacts::ClosureKey }
fn emitClosureOwner(context: ClosureEmission&, emitter: blot_backend_backend_emission::Owner&) -> blot_error::Error {
    let generator .= emitter.generator; let key = context.key; let source .= unit(generator, key.unit); let metadata = source.closures[key.catalog]; let captures = source.extra[metadata.captures.start..metadata.captures.start + metadata.captures.len];
    if metadata.parameter.binding != 0 {
        if key.parameter_template != 0 { emitter.templates.insert(metadata.parameter.binding, templateMetadata(generator.planning.template_catalog.items[key.parameter_template - 1], 1)); }
        else { emitter.locals.insert(metadata.parameter.binding, 1); }
    }
    for binding, index in captures {
        let captured = capturedStatic(generator, key.static_values, binding); if captured.present { emitter.static_values.insert(binding, captured.value); continue; }
        let capture_type = generator.representations.store.children(key.captures)[index]; let machine = generator.representations.store.machine(capture_type);
        let local, local_error = generator.module.addLocal(emitter.function_id, machine); if local_error != blot_error::Error.none { return local_error; }
        let get = emitter.emit(blot_backend_runtime_ir::OP_local_get, 0); if get != blot_error::Error.none { return get; }
        if !key.scalar_environment { var opcode = blot_backend_runtime_ir::OP_i32_load; if machine == blot_backend_runtime_ir::VT_f32 { opcode = blot_backend_runtime_ir::OP_f32_load; } let loaded = emitter.emit(opcode, (index * 4) as u32); if loaded != blot_error::Error.none { return loaded; } }
        let stored = emitter.emit(blot_backend_runtime_ir::OP_local_set, local); if stored != blot_error::Error.none { return stored; }
        let template = capturedTemplate(generator, key.templates, binding); if template.present { emitter.templates.insert(binding, templateMetadata(template.value, local)); } else { emitter.locals.insert(binding, local); }
    }
    if key.dictionaries {
        if source.types.node(metadata.function_type).tag != blot_check_types::Tag.forall || source.types.quantifierGoals(metadata.function_type).len == 0 { return decline(generator, key.unit, source.span(metadata.body), blot_check_diagnostic_code::Code.unsupported); }
        let installed = emitter.installUniversalDictionary(metadata.body, 3, metadata.function_type); if installed != blot_error::Error.none { return installed; }
    }
    if key.template_result {
        let error = emitter.bodyExpression(metadata.body, 0, true); if error != blot_error::Error.none { return error; }
        if !emitter.result_template.present { return fail(generator, key.unit, metadata.body, blot_check_diagnostic_code::Code.unresolved_type); } generator.planning.closure_template_results.insert(key, emitter.result_template.value);
    } else {
        let error = emitter.bodyExpression(metadata.body, 0, false); if error != blot_error::Error.none { return error; }
        if source.types.node(source.typeOf(metadata.body)).tag == blot_check_types::Tag.never { return emitter.emit(blot_backend_runtime_ir::OP_unreachable_, 0); }
    }
    return blot_error::Error.none;
}
fn closureFunction(generator: Generator&, key: blot_reuse_code_artifacts::ClosureKey) -> u32, blot_error::Error {
    let stage = generator.evaluator.enterInferenceStage(blot_work_counters::InferenceStage.specialization);
    recursive fn cleanup_continuation_22() -> u32, blot_error::Error {

    let scope, scope_error = enterScope(generator, blot_reuse_code_artifacts::Request.closure { key , ..}); if scope_error != blot_error::Error.none { return 0, scope_error; }
    recursive fn cleanup_continuation_21() -> u32, blot_error::Error {

    block {
        let existing = generator.planning.closures.get(key);
        if existing { let error = generator.planning.startup_facts.request(existing, blot_backend_startup_emission_facts::Kind.anonymous, key.unit, key.catalog, true); if error != blot_error::Error.none { return 0, error; } if scope.present { let hit = scope.value.hit(existing); if hit != blot_error::Error.none { return 0, hit; } } return existing, blot_error::Error.none; }
    }
    if key.staged == 0 && generator.retained != null {
        let job, error = findRetained(generator, generator.retained, blot_reuse_code_artifacts::Request.closure { key , ..}); if error != blot_error::Error.none { return 0, error; }
        if job.present {
            var actor: blot_reuse_code_artifacts::Scope&? = null; if scope.present { actor .= scope.value; }
            let function_id, rebuilt = reconstructRetained(generator, generator.retained, job.value, blot_reuse_code_artifacts::Request.closure { key , ..}, actor); if rebuilt != blot_error::Error.none { return 0, rebuilt; }
            let requested = generator.planning.startup_facts.request(function_id, blot_backend_startup_emission_facts::Kind.anonymous, key.unit, key.catalog, true); if requested != blot_error::Error.none { return 0, requested; } generator.planning.startup_facts.complete(function_id); return function_id, blot_error::Error.none;
        }
    }
    generator.work.fresh_closures++; let source .= unit(generator, key.unit); let metadata = source.closures[key.catalog]; let captures = source.extra[metadata.captures.start..metadata.captures.start + metadata.captures.len]; let fn_type = generator.representations.store.node(key.ty);
    if fn_type.tag != blot_backend_layout::Tag.function || captures.len != generator.representations.store.children(key.captures).len { return 0, fail(generator, key.unit, metadata.body, blot_check_diagnostic_code::Code.unresolved_type); }
    if key.scalar_environment && (!generator.representations.store.scalarEnvironment(key.captures) || key.templates != 0 || key.static_values != 0) { return 0, fail(generator, key.unit, metadata.body, blot_check_diagnostic_code::Code.unresolved_type); }
    if generator.instance_depth >= 256 { return 0, fail(generator, key.unit, metadata.body, blot_check_diagnostic_code::Code.complexity); } generator.instance_depth++;
    recursive fn cleanup_continuation_20() -> u32, blot_error::Error {

    let ordinary_signature, signature_error = closureSignature(generator, fn_type.a, fn_type.b); if signature_error != blot_error::Error.none { return 0, signature_error; }
    var wrapper_signature = ordinary_signature; var roles = closureRoles(generator, fn_type.a);
    if key.dictionaries { let dictionary_signature, error = dictionaryClosureSignature(generator, fn_type.a, fn_type.b); if error != blot_error::Error.none { return 0, error; } wrapper_signature = dictionary_signature; roles = dictionaryClosureRoles(generator, fn_type.a); }
    if key.parameter_template != 0 && generator.planning.template_catalog.items[key.parameter_template - 1].scalar_environment { roles = (roles & ~((3 as u64) << 2)) | ((blot_backend_runtime_ir::ROLE_scalar as u64) << 2); }
    if key.scalar_environment { roles = (roles & ~(3 as u64)) | (blot_backend_runtime_ir::ROLE_scalar as u64); }
    let function_id, added = generator.module.addTypedFunctionForSignature(wrapper_signature, bodyResultRole(generator, fn_type.b, key.unit, metadata.body)); if added != blot_error::Error.none { return 0, added; }
    let described = setParameterRoles(generator, function_id, roles, blot_support::some(2 as u16)); if described != blot_error::Error.none { return 0, described; }
    let callable = callableLayout(generator, function_id, key.ty); if callable != blot_error::Error.none { return 0, callable; } generator.planning.closures.insert(key, function_id);
    if scope.present { let reserved = scope.value.reserve(function_id); if reserved != blot_error::Error.none { return 0, reserved; } }
    let requested = generator.planning.startup_facts.request(function_id, blot_backend_startup_emission_facts::Kind.anonymous, key.unit, key.catalog, false); if requested != blot_error::Error.none { return 0, requested; }
    let caller = generator.planning.startup_facts.active; generator.planning.startup_facts.active = function_id;
    recursive fn cleanup_continuation_19() -> u32, blot_error::Error {

    var mappings: Mapping[>..<] = []; var rows: RowMapping[>..<] = []; let resolved = resolveClosureMappings(generator, key, mappings, rows); if resolved != blot_error::Error.none { return 0, resolved; }
    if key.dictionaries {
        let owner = source.types.node(metadata.function_type); let bound = blot_backend_dictionary_layout::bind(source, generator.representations.store, mappings, metadata.function_type, 0, blot_check_types::List { owner.b, owner.c , ..}, false);
        if bound != blot_error::Error.none { if bound == blot_error::Error.out_of_memory { return 0, bound; } return 0, fail(generator, key.unit, metadata.body, blot_check_diagnostic_code::Code.unresolved_type); }
    }
    var staged = blot_support::none<u32>(); if key.staged != 0 { staged = blot_support::some(key.staged); } var context = ClosureEmission { key , ..};
    let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { staged: staged, generator: generator, unit_id: key.unit, function_id: function_id, provider_local: blot_support::some(2 as u32), mappings: mappings, row_mappings: rows, factory_template: key.template_result , ..}, context, emitClosureOwner);
    if emitted != blot_error::Error.none { return 0, emitted; }
    if key.static_values == 0 && scope.present { let solved = scope.value.solved(mappings, rows, generator.representations.template_keys.get(key.templates)); if solved != blot_error::Error.none { return 0, solved; } }
    if scope.present { let completed = scope.value.complete(function_id, lookupValue(generator.planning.closure_template_results, key)); if completed != blot_error::Error.none { return 0, completed; } }
    generator.planning.startup_facts.complete(function_id); return function_id, blot_error::Error.none;

    }
    let cleanup_result_19_0,cleanup_result_19_1 = cleanup_continuation_19();
     generator.planning.startup_facts.active = caller;
    return cleanup_result_19_0,cleanup_result_19_1;

    }
    let cleanup_result_20_0,cleanup_result_20_1 = cleanup_continuation_20();
     generator.instance_depth--;
    return cleanup_result_20_0,cleanup_result_20_1;

    }
    let cleanup_result_21_0,cleanup_result_21_1 = cleanup_continuation_21();
     if scope.present { scope.value.deinit(); }
    return cleanup_result_21_0,cleanup_result_21_1;

    }
    let cleanup_result_22_0,cleanup_result_22_1 = cleanup_continuation_22();
     stage.deinit();
    return cleanup_result_22_0,cleanup_result_22_1;
}
fn emitOps(emitter: blot_backend_backend_emission::Owner&, code: const blot_backend_runtime_ir::Instruction[:]) -> blot_error::Error {
    for instruction in code { let error = emitter.emit(instruction.op, instruction.operand); if error != blot_error::Error.none { return error; } } return blot_error::Error.none;
}
fn selectMemberTemplate(generator: Generator&, unit_id: u32, node: blot_check_core::Id, reference: blot_check_core::BindingRef, expected: u32) -> blot_check_core::BindingRef, blot_error::Error {
    if !generator.evaluator.has_implementations { return reference, blot_error::Error.none; }
    var declaration_unit = unit_id; if reference.unit != 0 { declaration_unit = reference.unit; } let declaration .= unit(generator, declaration_unit); var template = false;
    for member in declaration.member_templates { if member.binding == reference.binding { template = true; break; } } if !template { return reference, blot_error::Error.none; }
    var owner: i64 = -1; for source, index in generator.units { if source.unit == unit_id { owner = index; break; } } if owner < 0 { return reference, fail(generator, unit_id, node, blot_check_diagnostic_code::Code.unsupported); }
    let actual, actual_error = generator.representations.toEvidence(generator.evaluator.evidenceStore(), expected); if actual_error != blot_error::Error.none { if actual_error == blot_error::Error.out_of_memory { return reference, actual_error; } return reference, fail(generator, unit_id, node, blot_check_diagnostic_code::Code.unresolved_type); }
    let selected, error = generator.evaluator.selectTemplate(owner, node, reference, actual); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return reference, error; } return reference, evaluationFailure(generator); } return selected, blot_error::Error.none;
}
struct CallableEmission { key: blot_reuse_code_artifacts::CallableKey, direct: Key, current: blot_backend_layout::Node, provider_local: u32, count: i64 }
fn emitCallableOwner(context: CallableEmission&, emitter: blot_backend_backend_emission::Owner&) -> blot_error::Error {
    let generator .= emitter.generator; let key = context.key; let direct = context.direct; let current = context.current;
    let erased_argument = generator.representations.store.node(current.a).tag == blot_backend_layout::Tag.erased_proof;
    if key.applied + 1 == context.count {
        let target, error = function(generator, direct); if error != blot_error::Error.none { return error; } var stored: u32 = 0;
        for parameter in direct.parameters[..key.applied] {
            if generator.representations.store.node(parameter).tag == blot_backend_layout::Tag.erased_proof { continue; }
            let get = emitter.emit(blot_backend_runtime_ir::OP_local_get, 0); if get != blot_error::Error.none { return get; }
            if key.dictionaries || !directCallableEnvironment(generator, key.ty, key.applied) {
                var load = blot_backend_runtime_ir::OP_i32_load; if generator.representations.store.machine(parameter) == blot_backend_runtime_ir::VT_f32 { load = blot_backend_runtime_ir::OP_f32_load; }
                var prefix: u32 = 0; if key.dictionaries { prefix = 1; } let loaded = emitter.emit(load, (stored + prefix) * 4); if loaded != blot_error::Error.none { return loaded; }
            }
            stored++;
        }
        if !erased_argument { let get = emitter.emit(blot_backend_runtime_ir::OP_local_get, 1); if get != blot_error::Error.none { return get; } }
        let head = emitter.providerHead(); if head != blot_error::Error.none { return head; }
        if key.dictionaries {
            if key.applied == 0 && !key.bound_dictionaries { let get = emitter.emit(blot_backend_runtime_ir::OP_local_get, context.provider_local + 1); if get != blot_error::Error.none { return get; } }
            else { let loaded = emitOps(emitter, [blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 0), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load)]); if loaded != blot_error::Error.none { return loaded; } }
        }
        return emitter.emit(blot_backend_runtime_ir::OP_call, target);
    }
    let next_key = blot_reuse_code_artifacts::CallableKey { target: key.target, ty: key.ty, applied: key.applied + 1, templates: key.templates, dictionaries: key.dictionaries, bound_dictionaries: key.bound_dictionaries, instance_arguments: key.instance_arguments , ..};
    if erased_argument { let next, error = callable(generator, next_key); if error != blot_error::Error.none { return error; } return emitter.descriptor(next, blot_support::some(0 as u32)); }
    if !key.dictionaries && directCallableEnvironment(generator, key.ty, key.applied + 1) { let next, error = callable(generator, next_key); if error != blot_error::Error.none { return error; } return emitter.descriptor(next, blot_support::some(1 as u32)); }
    var retained: u32[17]; var count: u32 = 0;
    if key.dictionaries { let dictionary_array, error = internLayout(generator, blot_backend_layout::Tag.array, 3, 0, []); if error != blot_error::Error.none { return error; } retained[0] = dictionary_array; count = 1; }
    for parameter in direct.parameters[..key.applied + 1] { if generator.representations.store.node(parameter).tag == blot_backend_layout::Tag.erased_proof { continue; } retained[count] = parameter; count++; }
    var environment_roles: blot_backend_runtime_ir::Role[17]; for parameter, index in retained[..count] { environment_roles[index] = layoutRole(generator, parameter); }
    let environment, allocated = emitter.allocate(count * 4, blot_backend_backend_emission::AllocationRoles { words: environment_roles[..count] , ..}); if allocated != blot_error::Error.none { return allocated; } var stored: u32 = 0;
    if key.dictionaries {
        let get = emitter.emit(blot_backend_runtime_ir::OP_local_get, environment); if get != blot_error::Error.none { return get; }
        if key.applied == 0 && !key.bound_dictionaries { let argument = emitter.emit(blot_backend_runtime_ir::OP_local_get, context.provider_local + 1); if argument != blot_error::Error.none { return argument; } }
        else { let load = emitOps(emitter, [blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 0), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load)]); if load != blot_error::Error.none { return load; } }
        let written = emitter.emit(blot_backend_runtime_ir::OP_i32_store, 0); if written != blot_error::Error.none { return written; } stored = 1;
    }
    for parameter in direct.parameters[..key.applied] {
        if generator.representations.store.node(parameter).tag == blot_backend_layout::Tag.erased_proof { continue; }
        let floating = generator.representations.store.machine(parameter) == blot_backend_runtime_ir::VT_f32; var load = blot_backend_runtime_ir::OP_i32_load; var store = blot_backend_runtime_ir::OP_i32_store; if floating { load = blot_backend_runtime_ir::OP_f32_load; store = blot_backend_runtime_ir::OP_f32_store; }
        let prefix = emitOps(emitter, [blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, environment), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 0)]); if prefix != blot_error::Error.none { return prefix; }
        if key.dictionaries || !directCallableEnvironment(generator, key.ty, key.applied) { let loaded = emitter.emit(load, stored * 4); if loaded != blot_error::Error.none { return loaded; } }
        let written = emitter.emit(store, stored * 4); if written != blot_error::Error.none { return written; } stored++;
    }
    var store = blot_backend_runtime_ir::OP_i32_store; if generator.representations.store.machine(current.a) == blot_backend_runtime_ir::VT_f32 { store = blot_backend_runtime_ir::OP_f32_store; }
    let stored_argument = emitOps(emitter, [blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, environment), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 1), blot_backend_runtime_ir::instruction(store, stored * 4)]); if stored_argument != blot_error::Error.none { return stored_argument; }
    let next, error = callable(generator, next_key); if error != blot_error::Error.none { return error; } return emitter.descriptor(next, blot_support::some(environment));
}
fn callableAlias(generator: Generator&, key: blot_reuse_code_artifacts::CallableKey, body: const blot_check_core::Body&, scope: blot_support::Option<blot_reuse_code_artifacts::Scope>&) -> u32, blot_error::Error {
    if key.applied != 0 { return 0, decline(generator, key.target.unit, body.span, blot_check_diagnostic_code::Code.unsupported); }
    let arrow = generator.representations.store.node(key.ty); if arrow.tag != blot_backend_layout::Tag.function { return 0, decline(generator, key.target.unit, body.span, blot_check_diagnostic_code::Code.unresolved_type); }
    if generator.representations.store.node(arrow.a).tag == blot_backend_layout::Tag.erased_proof { return 0, decline(generator, key.target.unit, body.span, blot_check_diagnostic_code::Code.unsupported); }
    let inputs: blot_backend_runtime_ir::ValueType[3] = [blot_backend_runtime_ir::VT_i32, generator.representations.store.machine(arrow.a), blot_backend_runtime_ir::VT_i32];
    let function_id, added = generator.module.addTypedFunction(inputs, generator.representations.store.machine(arrow.b), layoutRole(generator, arrow.b)); if added != blot_error::Error.none { return 0, added; }
    let described = setParameterRoles(generator, function_id, closureRoles(generator, arrow.a), blot_support::some(2 as u16)); if described != blot_error::Error.none { return 0, described; }
    let layout = callableLayout(generator, function_id, key.ty); if layout != blot_error::Error.none { return 0, layout; } generator.planning.callables.insert(key, function_id);
    if scope.present { let reserved = scope.value.reserve(function_id); if reserved != blot_error::Error.none { return 0, reserved; } }
    var global = blot_support::none<u32>(); if body.runtime { let value, error = generator.planning.runtimeGlobal(generator, key.target); if error != blot_error::Error.none { return 0, error; } global = blot_support::some(value); }
    var constant_value = blot_support::none<Value>(); if !global.present { let value, error = constant(generator, key.target, key.ty); if error != blot_error::Error.none { return 0, error; } constant_value = blot_support::some(value); }
    if constant_value.present {
        let value = constant_value.value;
        if value.scalar == blot_backend_runtime_ir::SC_pointer && value.bits <= generator.module.data.len && generator.module.data.len - value.bits >= blot_runtime_runtime_layout::Closure_bytes {
            let target_id = readDataWord(generator.module, value.bits + blot_runtime_runtime_layout::Closure_function); let environment = readDataWord(generator.module, value.bits + blot_runtime_runtime_layout::Closure_environment);
            if target_id != function_id && target_id < generator.module.functions.len {
                let target = generator.module.functions[target_id];
                if !target.entry && target.signature == generator.module.functions[function_id].signature && target.result_role == layoutRole(generator, arrow.b) && target.parameter_roles == closureRoles(generator, arrow.a) {
                    let marker = generator.module.emit(function_id, blot_backend_runtime_ir::immortalReference()); if marker != blot_error::Error.none { return 0, marker; }
                    let address = generator.module.emitReference(function_id, blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const, environment), blot_reuse_artifact_emitter::Role.static_address); if address != blot_error::Error.none { return 0, address; }
                    let emitted = generator.module.emitSlice(function_id, [blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 1), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 2), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call, target_id)]); if emitted != blot_error::Error.none { return 0, emitted; }
                    if generator.request_owner.present { let guarded = blot_runtime_request_runtime::guard_(generator.module, function_id, generator.request_owner.value, []); if guarded != blot_error::Error.none { return 0, guarded; } }
                    if scope.present { let completed = scope.value.complete(function_id, blot_support::none<u32>()); if completed != blot_error::Error.none { return 0, completed; } } return function_id, blot_error::Error.none;
                }
            }
        }
    }
    let callee, local_error = generator.module.addLocal(function_id, blot_backend_runtime_ir::VT_i32); if local_error != blot_error::Error.none { return 0, local_error; }
    if global.present { let error = generator.module.emit(function_id, blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_get, global.value)); if error != blot_error::Error.none { return 0, error; } } else { let error = emitValue(generator, function_id, constant_value.value); if error != blot_error::Error.none { return 0, error; } }
    let signature, signature_error = generator.module.internType(inputs, generator.representations.store.machine(arrow.b)); if signature_error != blot_error::Error.none { return 0, signature_error; }
    let code: blot_backend_runtime_ir::Instruction[9] = [
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set, callee), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, callee), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load, 4),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 1), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 2), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, callee), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load),
        blot_backend_runtime_ir::callResult(layoutRole(generator, arrow.b)), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call_indirect, signature),
    ];
    let emitted = generator.module.emitSlice(function_id, code); if emitted != blot_error::Error.none { return 0, emitted; }
    if generator.request_owner.present { let guarded = blot_runtime_request_runtime::guard_(generator.module, function_id, generator.request_owner.value, []); if guarded != blot_error::Error.none { return 0, guarded; } }
    if scope.present { let completed = scope.value.complete(function_id, blot_support::none<u32>()); if completed != blot_error::Error.none { return 0, completed; } } return function_id, blot_error::Error.none;
}
fn readDataWord(module: blot_backend_wasm::Module&, at: u32) -> u32 { let start = at as i64; return module.data[start] as u32 | ((module.data[start + 1] as u32) << 8) | ((module.data[start + 2] as u32) << 16) | ((module.data[start + 3] as u32) << 24); }
recursive fn callable(generator: Generator&, key: blot_reuse_code_artifacts::CallableKey) -> u32, blot_error::Error {
    if key.bound_dictionaries && !key.dictionaries { return 0, decline(generator, key.target.unit, unit(generator, key.target.unit).binding(key.target.binding).span, blot_check_diagnostic_code::Code.unsupported); }
    let selected, selection_error = selectMemberTemplate(generator, key.target.unit, 0, key.target, key.ty); if selection_error != blot_error::Error.none { return 0, selection_error; }
    if selected != key.target { var actual = key; actual.target = selected; actual.templates = 0; return callable(generator, actual); }
    let scope, scope_error = enterScope(generator, blot_reuse_code_artifacts::Request.callable { key , ..}); if scope_error != blot_error::Error.none { return 0, scope_error; }
    recursive fn cleanup_continuation_18() -> u32, blot_error::Error {

    block { let existing = generator.planning.callables.get(key); if existing { if scope.present { let hit = scope.value.hit(existing); if hit != blot_error::Error.none { return 0, hit; } } return existing, blot_error::Error.none; } }
    let source .= unit(generator, key.target.unit); let body .= source.body(key.target.binding); if body == null { return 0, decline(generator, key.target.unit, source.binding(key.target.binding).span, blot_check_diagnostic_code::Code.unsupported); }
    if body.parameters.len == 0 { return callableAlias(generator, key, body, scope); }
    if body.parameters.len > max_parameters || key.applied >= body.parameters.len { return 0, decline(generator, key.target.unit, body.span, blot_check_diagnostic_code::Code.unsupported); }
    var direct = Key { dictionaries: key.dictionaries, instance_arguments: key.instance_arguments, target: key.target, count: body.parameters.len as u8, templates: key.templates , ..}; var ty = key.ty; var current: blot_backend_layout::Node;
    for index in 0..body.parameters.len {
        let n = generator.representations.store.node(ty); if n.tag != blot_backend_layout::Tag.function { return 0, decline(generator, key.target.unit, body.span, blot_check_diagnostic_code::Code.unresolved_type); }
        direct.parameters[index] = n.a; direct.effects[index] = n.c; if index == key.applied { current = n; } ty = n.b;
    }
    direct.result = ty; let erased_argument = generator.representations.store.node(current.a).tag == blot_backend_layout::Tag.erased_proof;
    let ordinary, signature_error = closureSignature(generator, current.a, current.b); if signature_error != blot_error::Error.none { return 0, signature_error; } var wrapper_type = ordinary;
    if key.dictionaries && !key.bound_dictionaries && key.applied == 0 { let selected_type, error = dictionaryClosureSignature(generator, current.a, current.b); if error != blot_error::Error.none { return 0, error; } wrapper_type = selected_type; }
    let function_id, added = generator.module.addTypedFunctionForSignature(wrapper_type, layoutRole(generator, current.b)); if added != blot_error::Error.none { return 0, added; }
    var provider_local: u32 = 2; if erased_argument { provider_local = 1; } var parameter_roles = closureRoles(generator, current.a); if key.dictionaries && !key.bound_dictionaries && key.applied == 0 { parameter_roles = dictionaryClosureRoles(generator, current.a); }
    let described = setParameterRoles(generator, function_id, parameter_roles, blot_support::some(provider_local as u16)); if described != blot_error::Error.none { return 0, described; }
    let complete_type, type_error = internLayoutWithEffects(generator, blot_backend_layout::Tag.function, current.a, current.b, current.c, []); if type_error != blot_error::Error.none { return 0, type_error; }
    let layout = callableLayout(generator, function_id, complete_type); if layout != blot_error::Error.none { return 0, layout; } generator.planning.callables.insert(key, function_id);
    if scope.present { let reserved = scope.value.reserve(function_id); if reserved != blot_error::Error.none { return 0, reserved; } }
    var context = CallableEmission { key, direct, current, provider_local, body.parameters.len , ..};
    let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { generator: generator, unit_id: key.target.unit, function_id: function_id, provider_local: blot_support::some(provider_local), mappings: [] , ..}, context, emitCallableOwner); if emitted != blot_error::Error.none { return 0, emitted; }
    if scope.present { let completed = scope.value.complete(function_id, blot_support::none<u32>()); if completed != blot_error::Error.none { return 0, completed; } } return function_id, blot_error::Error.none;

    }
    let cleanup_result_18_0,cleanup_result_18_1 = cleanup_continuation_18();
     if scope.present { scope.value.deinit(); }
    return cleanup_result_18_0,cleanup_result_18_1;
}
struct ConstructorEmission { key: blot_reuse_code_artifacts::ConstructorKey, fn_type: blot_backend_layout::Node }
fn emitConstructorOwner(context: ConstructorEmission&, emitter: blot_backend_backend_emission::Owner&) -> blot_error::Error {
    let generator .= emitter.generator; let key = context.key; let fn_type = context.fn_type; let source .= unit(generator, key.unit); let metadata = source.constructor(key.catalog);
    if source.nominal(metadata.nominal).is_opaque { return emitter.emit(blot_backend_runtime_ir::OP_local_get, 1); }
    let payload_type = source.types.node(metadata.payload); var record_local = blot_support::none<u32>();
    if payload_type.tag == blot_check_types::Tag.record && payload_type.b == 1 {
        let roles: blot_backend_runtime_ir::Role[1] = [layoutRole(generator, fn_type.a)]; let record, error = emitter.allocate(4, blot_backend_backend_emission::AllocationRoles { words: roles , ..}); if error != blot_error::Error.none { return error; }
        var store = blot_backend_runtime_ir::OP_i32_store; if generator.representations.store.machine(fn_type.a) == blot_backend_runtime_ir::VT_f32 { store = blot_backend_runtime_ir::OP_f32_store; }
        let emitted = emitOps(emitter, [blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, record), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 1), blot_backend_runtime_ir::instruction(store)]); if emitted != blot_error::Error.none { return emitted; } record_local = blot_support::some(record);
    } else if payload_type.tag == blot_check_types::Tag.record { let record, error = emitter.recordRepresentation(payload_type, 1, true); if error != blot_error::Error.none { return error; } record_local = blot_support::some(record); }
    if record_local.present && record_local.value != 1 { let marked = emitter.markAcyclic(record_local.value, fn_type.a); if marked != blot_error::Error.none { return marked; } }
    var role = layoutRole(generator, fn_type.a); if record_local.present { role = blot_backend_runtime_ir::ROLE_reference; } let roles: blot_backend_runtime_ir::Role[2] = [blot_backend_runtime_ir::ROLE_scalar, role];
    let address, allocated = emitter.allocate(8, blot_backend_backend_emission::AllocationRoles { words: roles , ..}); if allocated != blot_error::Error.none { return allocated; }
    if record_local.present || layoutRole(generator, fn_type.a) == blot_backend_runtime_ir::ROLE_reference { let marked = emitter.markAcyclic(address, fn_type.b); if marked != blot_error::Error.none { return marked; } }
    var payload: u32 = 1; if record_local.present { payload = record_local.value; } var store = blot_backend_runtime_ir::OP_i32_store; if !record_local.present && generator.representations.store.machine(fn_type.a) == blot_backend_runtime_ir::VT_f32 { store = blot_backend_runtime_ir::OP_f32_store; }
    return emitOps(emitter, [
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, address), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const, metadata.tag), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, address), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, payload), blot_backend_runtime_ir::instruction(store, 4), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, address),
    ]);
}
fn constructorFunction(generator: Generator&, key: blot_reuse_code_artifacts::ConstructorKey) -> u32, blot_error::Error {
    let scope, scope_error = enterScope(generator, blot_reuse_code_artifacts::Request.constructor { key , ..}); if scope_error != blot_error::Error.none { return 0, scope_error; }
    recursive fn cleanup_continuation_17() -> u32, blot_error::Error {

    block { let existing = generator.planning.constructor_functions.get(key); if existing { if scope.present { let hit = scope.value.hit(existing); if hit != blot_error::Error.none { return 0, hit; } } return existing, blot_error::Error.none; } }
    let fn_type = generator.representations.store.node(key.ty); if fn_type.tag != blot_backend_layout::Tag.function { return 0, decline(generator, key.unit, blot_check_core::Span { 0, 0 , ..}, blot_check_diagnostic_code::Code.unresolved_type); }
    let parameters: blot_backend_runtime_ir::ValueType[3] = [blot_backend_runtime_ir::VT_i32, generator.representations.store.machine(fn_type.a), blot_backend_runtime_ir::VT_i32];
    let function_id, added = generator.module.addTypedFunction(parameters, generator.representations.store.machine(fn_type.b), layoutRole(generator, fn_type.b)); if added != blot_error::Error.none { return 0, added; }
    let described = setParameterRoles(generator, function_id, closureRoles(generator, fn_type.a), blot_support::some(2 as u16)); if described != blot_error::Error.none { return 0, described; }
    let layout = callableLayout(generator, function_id, key.ty); if layout != blot_error::Error.none { return 0, layout; } generator.planning.constructor_functions.insert(key, function_id);
    if scope.present { let reserved = scope.value.reserve(function_id); if reserved != blot_error::Error.none { return 0, reserved; } }
    var context = ConstructorEmission { key, fn_type , ..}; let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { generator: generator, unit_id: key.unit, function_id: function_id, provider_local: blot_support::some(2 as u32), mappings: [] , ..}, context, emitConstructorOwner); if emitted != blot_error::Error.none { return 0, emitted; }
    if scope.present { let completed = scope.value.complete(function_id, blot_support::none<u32>()); if completed != blot_error::Error.none { return 0, completed; } } return function_id, blot_error::Error.none;

    }
    let cleanup_result_17_0,cleanup_result_17_1 = cleanup_continuation_17();
     if scope.present { scope.value.deinit(); }
    return cleanup_result_17_0,cleanup_result_17_1;
}
struct PrimitiveEmission { key: blot_reuse_code_artifacts::PrimitiveKey, parameters: u32[3], current: blot_backend_layout::Node, result: u32 }
fn emitPrimitiveOwner(context: PrimitiveEmission&, emitter: blot_backend_backend_emission::Owner&) -> blot_error::Error {
    let generator .= emitter.generator; let key = context.key; let metadata = unit(generator, key.unit).primitives[key.catalog]; let parameters = context.parameters;
    if key.applied + 1 == metadata.arity {
        var locals: u32[3]; var machines: blot_backend_runtime_ir::ValueType[3];
        for parameter, index in parameters[..metadata.arity] {
            let machine = generator.representations.store.machine(parameter); machines[index] = machine;
            if index == key.applied { locals[index] = 1; } else {
                let local, error = emitter.temporary(machine); if error != blot_error::Error.none { return error; } locals[index] = local; var load = blot_backend_runtime_ir::OP_i32_load; if machine == blot_backend_runtime_ir::VT_f32 { load = blot_backend_runtime_ir::OP_f32_load; }
                let emitted = emitOps(emitter, [blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 0), blot_backend_runtime_ir::instruction(load, (index * 4) as u32), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set, local)]); if emitted != blot_error::Error.none { return emitted; }
            }
        }
        if metadata.kind == blot_check_core::PrimitiveKind.scalar {
            if generator.representations.store.node(parameters[0]).tag == blot_backend_layout::Tag.product {
                if blot_backend_simd_intrinsics::literalLanes(metadata.op) { return fail(generator, key.unit, 0, blot_check_diagnostic_code::Code.simd_lane_literal); }
                var operands: u32[3]; operands[0] = locals[0]; var count: i64 = 1;
                if metadata.arity == 2 && blot_backend_simd_intrinsics::pairs(metadata.op) { let paired = emitter.simdPairLocals(locals[1], operands[1..3]); if paired != blot_error::Error.none { return paired; } count = 3; }
                else if metadata.arity == 2 { operands[1] = locals[1]; count = 2; }
                return emitter.simdLocals(metadata.op, operands[..count], blot_support::none<u32>(), parameters[0], context.result);
            }
            let scalar_type = generator.representations.store.scalar(parameters[0]); if !scalar_type.present { return fail(generator, key.unit, 0, blot_check_diagnostic_code::Code.unsupported); }
            let opcode = blot_backend_scalar_ops::opcode(metadata.op, scalar_type.value); if !opcode.present { return fail(generator, key.unit, 0, blot_check_diagnostic_code::Code.unsupported); }
            for local in locals[..metadata.arity] { let get = emitter.emit(blot_backend_runtime_ir::OP_local_get, local); if get != blot_error::Error.none { return get; } } return emitter.emit(opcode.value, 0);
        }
        return emitter.arrayLocals(0, metadata.array_op, locals[..metadata.arity], machines[..metadata.arity], context.result, parameters[0]);
    }
    var roles: blot_backend_runtime_ir::Role[3]; for parameter, index in parameters[..key.applied + 1] { roles[index] = layoutRole(generator, parameter); }
    let environment, allocated = emitter.allocate((key.applied + 1) * 4, blot_backend_backend_emission::AllocationRoles { words: roles[..key.applied + 1] , ..}); if allocated != blot_error::Error.none { return allocated; }
    for parameter, index in parameters[..key.applied] {
        var load = blot_backend_runtime_ir::OP_i32_load; var store = blot_backend_runtime_ir::OP_i32_store; if generator.representations.store.machine(parameter) == blot_backend_runtime_ir::VT_f32 { load = blot_backend_runtime_ir::OP_f32_load; store = blot_backend_runtime_ir::OP_f32_store; }
        let emitted = emitOps(emitter, [blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, environment), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 0), blot_backend_runtime_ir::instruction(load, (index * 4) as u32), blot_backend_runtime_ir::instruction(store, (index * 4) as u32)]); if emitted != blot_error::Error.none { return emitted; }
    }
    var store = blot_backend_runtime_ir::OP_i32_store; if generator.representations.store.machine(context.current.a) == blot_backend_runtime_ir::VT_f32 { store = blot_backend_runtime_ir::OP_f32_store; }
    let emitted = emitOps(emitter, [blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, environment), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 1), blot_backend_runtime_ir::instruction(store, key.applied * 4)]); if emitted != blot_error::Error.none { return emitted; }
    let next, error = primitiveFunction(generator, blot_reuse_code_artifacts::PrimitiveKey { unit: key.unit, catalog: key.catalog, ty: key.ty, applied: key.applied + 1 , ..}); if error != blot_error::Error.none { return error; } return emitter.descriptor(next, blot_support::some(environment));
}
recursive fn primitiveFunction(generator: Generator&, key: blot_reuse_code_artifacts::PrimitiveKey) -> u32, blot_error::Error {
    let scope, scope_error = enterScope(generator, blot_reuse_code_artifacts::Request.primitive { key , ..}); if scope_error != blot_error::Error.none { return 0, scope_error; }
    recursive fn cleanup_continuation_16() -> u32, blot_error::Error {

    block { let existing = generator.planning.primitive_functions.get(key); if existing { if scope.present { let hit = scope.value.hit(existing); if hit != blot_error::Error.none { return 0, hit; } } return existing, blot_error::Error.none; } }
    let metadata = unit(generator, key.unit).primitives[key.catalog]; if metadata.arity == 0 || metadata.arity > 3 || key.applied >= metadata.arity { return 0, fail(generator, key.unit, 0, blot_check_diagnostic_code::Code.unsupported); }
    var parameters: u32[3]; var current: blot_backend_layout::Node; var ty = key.ty;
    for index in 0..metadata.arity { let arrow = generator.representations.store.node(ty); if arrow.tag != blot_backend_layout::Tag.function { return 0, fail(generator, key.unit, 0, blot_check_diagnostic_code::Code.unresolved_type); } parameters[index] = arrow.a; if index == key.applied { current = arrow; } ty = arrow.b; }
    if generator.planning.primitive_functions.count >= 65536 { return 0, fail(generator, key.unit, 0, blot_check_diagnostic_code::Code.complexity); }
    let inputs: blot_backend_runtime_ir::ValueType[3] = [blot_backend_runtime_ir::VT_i32, generator.representations.store.machine(current.a), blot_backend_runtime_ir::VT_i32]; let function_id, added = generator.module.addTypedFunction(inputs, generator.representations.store.machine(current.b), layoutRole(generator, current.b)); if added != blot_error::Error.none { return 0, added; }
    let described = setParameterRoles(generator, function_id, closureRoles(generator, current.a), blot_support::some(2 as u16)); if described != blot_error::Error.none { return 0, described; }
    let complete_type, error = internLayoutWithEffects(generator, blot_backend_layout::Tag.function, current.a, current.b, current.c, []); if error != blot_error::Error.none { return 0, error; }
    let layout = callableLayout(generator, function_id, complete_type); if layout != blot_error::Error.none { return 0, layout; } generator.planning.primitive_functions.insert(key, function_id);
    if scope.present { let reserved = scope.value.reserve(function_id); if reserved != blot_error::Error.none { return 0, reserved; } }
    var context = PrimitiveEmission { key, parameters, current, ty , ..}; let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { generator: generator, unit_id: key.unit, function_id: function_id, provider_local: blot_support::some(2 as u32), mappings: [] , ..}, context, emitPrimitiveOwner); if emitted != blot_error::Error.none { return 0, emitted; }
    if scope.present { let completed = scope.value.complete(function_id, blot_support::none<u32>()); if completed != blot_error::Error.none { return 0, completed; } } return function_id, blot_error::Error.none;

    }
    let cleanup_result_16_0,cleanup_result_16_1 = cleanup_continuation_16();
     if scope.present { scope.value.deinit(); }
    return cleanup_result_16_0,cleanup_result_16_1;
}
fn runtimeDataWord(generator: Generator&, address: u32, operation: blot_backend_runtime_operations::Id) -> blot_error::Error {
    let error = generator.planning.runtime_operations.dataWord(generator.module, address, operation); if error == blot_error::Error.invalid_operation { return blot_error::Error.invalid_function_reference; } return error;
}
fn runtimeOperation(generator: Generator&, label: u32, unit_id: u32, span: blot_check_core::Span) -> u32, blot_error::Error {
    var descriptor_label = label; let descriptor = generator.evaluator.storage.evidence.effects.view().operation(label);
    if descriptor.instance.decl != 0 {
        let unscoped, error = generator.evaluator.storage.evidence.effects.internOperation(descriptor.identity, generator.evaluator.storage.evidence.effects.view().operationArguments(label));
        if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0, error; } return 0, decline(generator, unit_id, span, blot_check_diagnostic_code::Code.unresolved_type); } descriptor_label = unscoped;
    }
    let previous_count = generator.planning.runtime_operations.entries.len; let operation, error = generator.planning.runtime_operations.intern(generator.evaluator.storage.evidence.view(), descriptor_label);
    if error != blot_error::Error.none { if error == blot_error::Error.invalid_operation { return 0, decline(generator, unit_id, span, blot_check_diagnostic_code::Code.unresolved_type); } return 0, error; }
    let demanded = generator.module.demandResource(blot_reuse_artifact_emitter::ResourceKind.operation, operation, operation <= previous_count); if demanded != blot_error::Error.none { return 0, demanded; } return operation, blot_error::Error.none;
}
fn operationLabel(generator: Generator&, unit_id: u32, catalog: u32, mappings: const Mapping[:], rows: const RowMapping[:], span: blot_check_core::Span) -> u32, blot_error::Error {
    let source .= unit(generator, unit_id); if catalog >= source.operation_values.len { return 0, decline(generator, unit_id, span, blot_check_diagnostic_code::Code.unsupported); }
    let operation = source.operation_values[catalog]; var arguments: u32[>..<] = [];
    for argument in source.types.list(operation.arguments) {
        let concrete, layout_error = codeLayoutWithRows(generator, unit_id, argument, mappings, rows, span); if layout_error != blot_error::Error.none { return 0, layout_error; }
        let actual, error = generator.representations.toEvidence(generator.evaluator.evidenceStore(), concrete); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0, error; } return 0, decline(generator, unit_id, span, blot_check_diagnostic_code::Code.unresolved_type); } arguments.push(actual);
    }
    let semantic, error = generator.evaluator.storage.evidence.effects.internOperationInstance(operation.identity, arguments, blot_backend_layout::mappedInstance(operation.instance, mappings));
    if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0, error; } return 0, decline(generator, unit_id, span, blot_check_diagnostic_code::Code.unresolved_type); } return semantic, blot_error::Error.none;
}
fn operationLayoutLabel(generator: Generator&, operation_type: u32, unit_id: u32, span: blot_check_core::Span) -> u32, blot_error::Error {
    let operation = generator.representations.store.node(operation_type); if operation.tag != blot_backend_layout::Tag.nominal { return 0, decline(generator, unit_id, span, blot_check_diagnostic_code::Code.unresolved_type); }
    var source_arguments: u32[>..<] = []; source_arguments.append(generator.representations.store.children(operation_type)); var arguments: u32[>..<] = [];
    for argument in source_arguments { let actual, error = generator.representations.toEvidence(generator.evaluator.evidenceStore(), argument); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0, error; } return 0, decline(generator, unit_id, span, blot_check_diagnostic_code::Code.unresolved_type); } arguments.push(actual); }
    let semantic, error = generator.evaluator.storage.evidence.effects.internOperation(blot_check_types::NominalIdentity { operation.a, operation.b , ..}, arguments);
    if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0, error; } return 0, decline(generator, unit_id, span, blot_check_diagnostic_code::Code.unresolved_type); } return semantic, blot_error::Error.none;
}
fn requestLabel(generator: Generator&, unit_id: u32, label: u32, mappings: const Mapping[:], rows: const RowMapping[:], span: blot_check_core::Span) -> u32, blot_error::Error {
    let source .= unit(generator, unit_id); let operation = source.types.operation(label); var arguments: u32[>..<] = [];
    for argument in source.types.list(operation.arguments) {
        let concrete, layout_error = codeLayoutWithRows(generator, unit_id, argument, mappings, rows, span); if layout_error != blot_error::Error.none { return 0, layout_error; }
        let actual, error = generator.representations.toEvidence(generator.evaluator.evidenceStore(), concrete); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0, error; } return 0, decline(generator, unit_id, span, blot_check_diagnostic_code::Code.unresolved_type); } arguments.push(actual);
    }
    let semantic, error = generator.evaluator.storage.evidence.effects.internOperationInstance(operation.identity, arguments, operation.instance);
    if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0, error; } return 0, decline(generator, unit_id, span, blot_check_diagnostic_code::Code.unresolved_type); } return semantic, blot_error::Error.none;
}
fn foreignRow(generator: const Generator&, row: u32, singleton: bool) -> bool {
    if row == blot_backend_layout::unknown_row { return false; } let view = generator.representations.store.effects.view(); let labels = view.rowLabels(row); if singleton && labels.len != 1 { return false; }
    for label in labels { let operation = view.operation(label); if operation.instance.unit != 0 || operation.instance.decl != 0 || operation.identity.unit != 0 || operation.identity.decl != 1 || operation.arguments.len != 0 { return false; } } return true;
}
fn hostCallback(generator: const Generator&, ty: u32) -> blot_support::Option<blot_backend_wasm::Callback> {
    let arrow = generator.representations.store.node(ty); if arrow.tag != blot_backend_layout::Tag.function || !foreignRow(generator, arrow.c, true) { return blot_support::none<blot_backend_wasm::Callback>(); }
    let argument = generator.representations.store.node(arrow.a);
    if argument.tag == blot_backend_layout::Tag.owning {
        if argument.b != blot_check_types::usagekind_unique || generator.representations.store.node(arrow.b).tag != blot_backend_layout::Tag.unit { return blot_support::none<blot_backend_wasm::Callback>(); }
        let payload = generator.representations.store.node(argument.a);
        if payload.tag == blot_backend_layout::Tag.unit || payload.tag == blot_backend_layout::Tag.boolean || payload.tag == blot_backend_layout::Tag.unsigned32 || payload.tag == blot_backend_layout::Tag.floating32 || (payload.tag == blot_backend_layout::Tag.array && (generator.representations.store.node(payload.a).tag == blot_backend_layout::Tag.unsigned32 || generator.representations.store.node(payload.a).tag == blot_backend_layout::Tag.floating32)) {
            let parameter = generator.representations.store.abi(argument.a); if !parameter.present { return blot_support::none<blot_backend_wasm::Callback>(); }
            return blot_support::some(blot_backend_wasm::Callback { parameter: parameter.value, result: blot_backend_runtime_ir::SC_unit, cleanup: true, owned: generator.persistent_outputs , ..});
        }
        return blot_support::some(blot_backend_wasm::Callback { parameter: blot_backend_runtime_ir::SC_u32, result: blot_backend_runtime_ir::SC_unit, cleanup: true, owned: generator.persistent_outputs, data: true, schema: argument.a , ..});
    }
    let parameter = generator.representations.store.abi(arrow.a); let result = generator.representations.store.abi(arrow.b); if !parameter.present || !result.present { return blot_support::none<blot_backend_wasm::Callback>(); }
    return blot_support::some(blot_backend_wasm::Callback { parameter: parameter.value, result: result.value , ..});
}
fn hostFunction(generator: Generator&, key: blot_reuse_code_artifacts::HostKey) -> u32, blot_error::Error {
    let scope, scope_error = enterScope(generator, blot_reuse_code_artifacts::Request.host { key , ..}); if scope_error != blot_error::Error.none { return 0, scope_error; }
    recursive fn cleanup_continuation_15() -> u32, blot_error::Error {

    block { let existing = generator.planning.host_functions.get(key); if existing { if scope.present { let hit = scope.value.hit(existing); if hit != blot_error::Error.none { return 0, hit; } } return existing, blot_error::Error.none; } }
    let selected = hostCallback(generator, key.ty); if !selected.present { return 0, decline(generator, 1, blot_check_core::Span { 0, 0 , ..}, blot_check_diagnostic_code::Code.entry_type); } var callback = selected.value;
    if key.owned && !callback.cleanup { return 0, blot_error::Error.invalid_function_reference; } callback.owned = key.owned;
    let references, references_error = generator.module.ensureHostReferences(); if references_error != blot_error::Error.none { return 0, references_error; }
    let imported, import_error = generator.module.importHostCallback(callback); if import_error != blot_error::Error.none { return 0, import_error; }
    let arrow = generator.representations.store.node(key.ty); let parameters: blot_backend_runtime_ir::ValueType[3] = [blot_backend_runtime_ir::VT_i32, generator.representations.store.machine(arrow.a), blot_backend_runtime_ir::VT_i32];
    let function_id, added = generator.module.addTypedFunction(parameters, blot_backend_runtime_ir::machine(callback.result), blot_backend_runtime_ir::role(callback.result)); if added != blot_error::Error.none { return 0, added; }
    let roles: blot_backend_runtime_ir::Role[3] = [blot_backend_runtime_ir::ROLE_reference, layoutRole(generator, arrow.a), blot_backend_runtime_ir::ROLE_reference]; let described = setParameterRoles(generator, function_id, blot_backend_runtime_ir::packParameterRoles(roles), blot_support::some(2 as u16)); if described != blot_error::Error.none { return 0, described; }
    let layout = callableLayout(generator, function_id, key.ty); if layout != blot_error::Error.none { return 0, layout; } generator.planning.host_functions.insert(key, function_id);
    if scope.present { let reserved = scope.value.reserve(function_id); if reserved != blot_error::Error.none { return 0, reserved; } }
    let borrowed = blot_backend_runtime_ir::Ownership { kind: blot_backend_runtime_ir::OWN_scope, chunk: 14 , ..}; let marker = generator.module.emit(function_id, blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_ownership, blot_backend_runtime_ir::pack(borrowed))); if marker != blot_error::Error.none { return 0, marker; }
    if !callback.owned {
        let emitted = generator.module.emitSlice(function_id, [
            blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 0), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_get, references.active), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ne), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),
            blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 0), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load, 8), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_host_ref_get), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 1),
        ]); if emitted != blot_error::Error.none { return 0, emitted; }
    } else { let emitted = generator.module.emitSlice(function_id, [blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 0), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::HostClosure_handle), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 1)]); if emitted != blot_error::Error.none { return 0, emitted; } }
    if callback.data {
        let payload, error = generator.module.addLocal(function_id, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return 0, error; }
        let emitted = generator.module.emitSlice(function_id, [blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set, payload), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const, callback.schema), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, payload)]); if emitted != blot_error::Error.none { return 0, emitted; }
    }
    if callback.cleanup { var load = blot_backend_runtime_ir::OP_i32_load; if callback.parameter == blot_backend_runtime_ir::SC_f32 { load = blot_backend_runtime_ir::OP_f32_load; } let emitted = generator.module.emit(function_id, blot_backend_runtime_ir::instruction(load, blot_runtime_runtime_layout::Owning_payload)); if emitted != blot_error::Error.none { return 0, emitted; } }
    let called = generator.module.emit(function_id, blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call_import, imported)); if called != blot_error::Error.none { return 0, called; }
    if scope.present { let completed = scope.value.complete(function_id, blot_support::none<u32>()); if completed != blot_error::Error.none { return 0, completed; } } return function_id, blot_error::Error.none;

    }
    let cleanup_result_15_0,cleanup_result_15_1 = cleanup_continuation_15();
     if scope.present { scope.value.deinit(); }
    return cleanup_result_15_0,cleanup_result_15_1;
}
fn I(op: blot_backend_runtime_ir::Op, operand: u32 = 0) -> blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::instruction(op, operand) }
struct OperationEmission { key: blot_reuse_code_artifacts::OperationKey, arrow: blot_backend_layout::Node, argument_machine: blot_backend_runtime_ir::ValueType, result_machine: blot_backend_runtime_ir::ValueType }
fn emitOperationOwner(context: OperationEmission&, emitter: blot_backend_backend_emission::Owner&) -> blot_error::Error {
    let generator .= emitter.generator; let key = context.key; let arrow = context.arrow;
    if key.scoped {
        let guarded = emitOps(emitter, [I(blot_backend_runtime_ir::OP_local_get, 0), I(blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::EffectAuthority_active), I(blot_backend_runtime_ir::OP_i32_eqz), I(blot_backend_runtime_ir::OP_if_), I(blot_backend_runtime_ir::OP_unreachable_), I(blot_backend_runtime_ir::OP_end)]); if guarded != blot_error::Error.none { return guarded; }
    }
    let frame, frame_error = emitter.temporary(blot_backend_runtime_ir::VT_i32); if frame_error != blot_error::Error.none { return frame_error; }
    let implementation, implementation_error = emitter.temporary(blot_backend_runtime_ir::VT_i32); if implementation_error != blot_error::Error.none { return implementation_error; }
    let start = emitOps(emitter, [
        I(blot_backend_runtime_ir::OP_local_get, 2), I(blot_backend_runtime_ir::OP_local_set, frame), I(blot_backend_runtime_ir::OP_block), I(blot_backend_runtime_ir::OP_loop),
        I(blot_backend_runtime_ir::OP_local_get, frame), I(blot_backend_runtime_ir::OP_i32_eqz), I(blot_backend_runtime_ir::OP_if_), I(blot_backend_runtime_ir::OP_unreachable_), I(blot_backend_runtime_ir::OP_end), I(blot_backend_runtime_ir::OP_local_get, frame), I(blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::ProviderFrame_operation),
    ]); if start != blot_error::Error.none { return start; }
    let operation = emitter.operationConstant(key.operation); if operation != blot_error::Error.none { return operation; }
    let compared = emitter.emit(blot_backend_runtime_ir::OP_i32_eq, 0); if compared != blot_error::Error.none { return compared; }
    if generator.scoped_effects { let matched = emitter.operationOwnerMatch(frame, key.scoped); if matched != blot_error::Error.none { return matched; } let combined = emitter.emit(blot_backend_runtime_ir::OP_i32_and, 0); if combined != blot_error::Error.none { return combined; } }
    let skip = emitOps(emitter, [I(blot_backend_runtime_ir::OP_br_if, 1), I(blot_backend_runtime_ir::OP_local_get, frame), I(blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::StateFrame_kind), I(blot_backend_runtime_ir::OP_i32_const, blot_runtime_runtime_layout::StateFrame_tag), I(blot_backend_runtime_ir::OP_i32_eq)]); if skip != blot_error::Error.none { return skip; }
    if generator.scoped_effects {
        let scoped = emitOps(emitter, [I(blot_backend_runtime_ir::OP_local_get, frame), I(blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::StateFrame_kind), I(blot_backend_runtime_ir::OP_i32_const, blot_runtime_runtime_layout::ScopedStateFrame_tag), I(blot_backend_runtime_ir::OP_i32_eq), I(blot_backend_runtime_ir::OP_i32_or)]); if scoped != blot_error::Error.none { return scoped; }
    }
    let state = emitOps(emitter, [I(blot_backend_runtime_ir::OP_if_), I(blot_backend_runtime_ir::OP_local_get, frame), I(blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::StateFrame_write)]); if state != blot_error::Error.none { return state; }
    let write_operation = emitter.operationConstant(key.operation); if write_operation != blot_error::Error.none { return write_operation; }
    let equal_write = emitter.emit(blot_backend_runtime_ir::OP_i32_eq, 0); if equal_write != blot_error::Error.none { return equal_write; }
    if generator.scoped_effects { let matched = emitter.operationOwnerMatch(frame, key.scoped); if matched != blot_error::Error.none { return matched; } let combined = emitter.emit(blot_backend_runtime_ir::OP_i32_and, 0); if combined != blot_error::Error.none { return combined; } }
    let next = emitOps(emitter, [
        I(blot_backend_runtime_ir::OP_br_if, 2), I(blot_backend_runtime_ir::OP_end), I(blot_backend_runtime_ir::OP_local_get, frame), I(blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::ProviderFrame_outer), I(blot_backend_runtime_ir::OP_local_set, frame), I(blot_backend_runtime_ir::OP_br), I(blot_backend_runtime_ir::OP_end), I(blot_backend_runtime_ir::OP_end),
        I(blot_backend_runtime_ir::OP_local_get, frame), I(blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::StateFrame_kind), I(blot_backend_runtime_ir::OP_i32_const, blot_runtime_runtime_layout::StateFrame_tag), I(blot_backend_runtime_ir::OP_i32_eq),
    ]); if next != blot_error::Error.none { return next; }
    if generator.scoped_effects {
        let scoped = emitOps(emitter, [I(blot_backend_runtime_ir::OP_local_get, frame), I(blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::StateFrame_kind), I(blot_backend_runtime_ir::OP_i32_const, blot_runtime_runtime_layout::ScopedStateFrame_tag), I(blot_backend_runtime_ir::OP_i32_eq), I(blot_backend_runtime_ir::OP_i32_or)]); if scoped != blot_error::Error.none { return scoped; }
    }
    let read = emitOps(emitter, [I(blot_backend_runtime_ir::OP_if_, context.result_machine as u32), I(blot_backend_runtime_ir::OP_local_get, frame), I(blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::StateFrame_read)]); if read != blot_error::Error.none { return read; }
    let read_operation = emitter.operationConstant(key.operation); if read_operation != blot_error::Error.none { return read_operation; }
    let read_case = emitOps(emitter, [I(blot_backend_runtime_ir::OP_i32_eq), I(blot_backend_runtime_ir::OP_if_, context.result_machine as u32)]); if read_case != blot_error::Error.none { return read_case; }
    if arrow.a == blot_check_types::unit {
        var load = blot_backend_runtime_ir::OP_i32_load; if context.result_machine == blot_backend_runtime_ir::VT_f32 { load = blot_backend_runtime_ir::OP_f32_load; }
        let value = emitOps(emitter, [I(blot_backend_runtime_ir::OP_local_get, frame), I(load, blot_runtime_runtime_layout::StateFrame_value)]); if value != blot_error::Error.none { return value; }
    } else { let trap = emitter.emit(blot_backend_runtime_ir::OP_unreachable_, 0); if trap != blot_error::Error.none { return trap; } }
    let alternate = emitter.emit(blot_backend_runtime_ir::OP_else_, 0); if alternate != blot_error::Error.none { return alternate; }
    if arrow.b == blot_check_types::unit {
        var scalar = blot_backend_runtime_ir::SC_pointer; let actual = generator.representations.store.scalar(arrow.a); if actual.present { scalar = actual.value; }
        let written = emitter.storeTypedWord(frame, blot_runtime_runtime_layout::StateFrame_value, 1, scalar, 0); if written != blot_error::Error.none { return written; }
        let unit_value = emitter.emit(blot_backend_runtime_ir::OP_i32_const, 0); if unit_value != blot_error::Error.none { return unit_value; }
    } else { let trap = emitter.emit(blot_backend_runtime_ir::OP_unreachable_, 0); if trap != blot_error::Error.none { return trap; } }
    let callback = emitOps(emitter, [I(blot_backend_runtime_ir::OP_end), I(blot_backend_runtime_ir::OP_else_), I(blot_backend_runtime_ir::OP_local_get, frame), I(blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::ProviderFrame_kind), I(blot_backend_runtime_ir::OP_i32_const, blot_runtime_runtime_layout::ProviderKind_callback), I(blot_backend_runtime_ir::OP_i32_eq)]); if callback != blot_error::Error.none { return callback; }
    if generator.scoped_effects {
        let scoped = emitOps(emitter, [I(blot_backend_runtime_ir::OP_local_get, frame), I(blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::ProviderFrame_kind), I(blot_backend_runtime_ir::OP_i32_const, blot_runtime_runtime_layout::ScopedFrame_tag), I(blot_backend_runtime_ir::OP_i32_eq), I(blot_backend_runtime_ir::OP_i32_or)]); if scoped != blot_error::Error.none { return scoped; }
    }
    let implementation_body = emitOps(emitter, [
        I(blot_backend_runtime_ir::OP_if_, context.result_machine as u32), I(blot_backend_runtime_ir::OP_local_get, frame), I(blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::ProviderFrame_target), I(blot_backend_runtime_ir::OP_local_set, implementation), I(blot_backend_runtime_ir::OP_local_get, implementation), I(blot_backend_runtime_ir::OP_i32_load, 4),
        I(blot_backend_runtime_ir::OP_local_get, 1), I(blot_backend_runtime_ir::OP_local_get, frame), I(blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::ProviderFrame_outer), I(blot_backend_runtime_ir::OP_local_get, implementation), I(blot_backend_runtime_ir::OP_i32_load),
    ]); if implementation_body != blot_error::Error.none { return implementation_body; }
    let result = generator.module.emit(emitter.function_id, blot_backend_runtime_ir::callResult(layoutRole(generator, arrow.b))); if result != blot_error::Error.none { return result; }
    let parameters: blot_backend_runtime_ir::ValueType[3] = [blot_backend_runtime_ir::VT_i32, context.argument_machine, blot_backend_runtime_ir::VT_i32]; let signature, signature_error = generator.module.internType(parameters, context.result_machine); if signature_error != blot_error::Error.none { return signature_error; }
    let invoked = emitOps(emitter, [I(blot_backend_runtime_ir::OP_call_indirect, signature), I(blot_backend_runtime_ir::OP_else_)]); if invoked != blot_error::Error.none { return invoked; }
    if generator.request_owner.present {
        let request = emitOps(emitter, [I(blot_backend_runtime_ir::OP_local_get, frame), I(blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::ProviderFrame_kind), I(blot_backend_runtime_ir::OP_i32_const, blot_runtime_request_runtime::request_kind), I(blot_backend_runtime_ir::OP_i32_eq)]); if request != blot_error::Error.none { return request; }
        if generator.scoped_effects {
            let scoped = emitOps(emitter, [I(blot_backend_runtime_ir::OP_local_get, frame), I(blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::ProviderFrame_kind), I(blot_backend_runtime_ir::OP_i32_const, blot_runtime_runtime_layout::ScopedRequestFrame_tag), I(blot_backend_runtime_ir::OP_i32_eq), I(blot_backend_runtime_ir::OP_i32_or)]); if scoped != blot_error::Error.none { return scoped; }
        }
        let branch = emitter.emit(blot_backend_runtime_ir::OP_if_, context.result_machine as u32); if branch != blot_error::Error.none { return branch; }
        let requested = emitter.invokeRequest(frame, 1, context.argument_machine, context.result_machine, layoutRole(generator, arrow.a)); if requested != blot_error::Error.none { return requested; }
        let rejected = emitOps(emitter, [I(blot_backend_runtime_ir::OP_else_), I(blot_backend_runtime_ir::OP_unreachable_), I(blot_backend_runtime_ir::OP_end)]); if rejected != blot_error::Error.none { return rejected; }
    } else { let trap = emitter.emit(blot_backend_runtime_ir::OP_unreachable_, 0); if trap != blot_error::Error.none { return trap; } }
    return emitOps(emitter, [I(blot_backend_runtime_ir::OP_end), I(blot_backend_runtime_ir::OP_end)]);
}
fn operationFunction(generator: Generator&, key: blot_reuse_code_artifacts::OperationKey) -> u32, blot_error::Error {
    let scope, scope_error = enterScope(generator, blot_reuse_code_artifacts::Request.operation { key , ..}); if scope_error != blot_error::Error.none { return 0, scope_error; }
    recursive fn cleanup_continuation_14() -> u32, blot_error::Error {

    block { let existing = generator.planning.operation_functions.get(key); if existing { if scope.present { let hit = scope.value.hit(existing); if hit != blot_error::Error.none { return 0, hit; } } return existing, blot_error::Error.none; } }
    let arrow = generator.representations.store.node(key.ty); if arrow.tag != blot_backend_layout::Tag.function { return 0, decline(generator, 1, blot_check_core::Span { 0, 0 , ..}, blot_check_diagnostic_code::Code.unresolved_type); }
    let argument_machine = generator.representations.store.machine(arrow.a); let result_machine = generator.representations.store.machine(arrow.b); let parameters: blot_backend_runtime_ir::ValueType[3] = [blot_backend_runtime_ir::VT_i32, argument_machine, blot_backend_runtime_ir::VT_i32];
    let function_id, added = generator.module.addTypedFunction(parameters, result_machine, layoutRole(generator, arrow.b)); if added != blot_error::Error.none { return 0, added; }
    let described = setParameterRoles(generator, function_id, closureRoles(generator, arrow.a), blot_support::some(2 as u16)); if described != blot_error::Error.none { return 0, described; }
    let layout = callableLayout(generator, function_id, key.ty); if layout != blot_error::Error.none { return 0, layout; } generator.planning.operation_functions.insert(key, function_id);
    if scope.present { let reserved = scope.value.reserve(function_id); if reserved != blot_error::Error.none { return 0, reserved; } }
    var context = OperationEmission { key, arrow, argument_machine, result_machine , ..}; let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { generator: generator, unit_id: 1, function_id: function_id, provider_local: blot_support::some(2 as u32), mappings: [] , ..}, context, emitOperationOwner); if emitted != blot_error::Error.none { return 0, emitted; }
    if scope.present { let completed = scope.value.complete(function_id, blot_support::none<u32>()); if completed != blot_error::Error.none { return 0, completed; } } return function_id, blot_error::Error.none;

    }
    let cleanup_result_14_0,cleanup_result_14_1 = cleanup_continuation_14();
     if scope.present { scope.value.deinit(); }
    return cleanup_result_14_0,cleanup_result_14_1;
}
struct HostSchemaContext { generator: Generator&, layouts: blot_backend_layout::Store& }
struct HostPhysical { floating: bool = false, reference: bool = false }
recursive fn physical(context: HostSchemaContext, id: u32, remaining: i64&, depth: i64) -> HostPhysical, blot_error::Error {
    if depth >= 128 || remaining == 0 || id == 0 || id >= context.layouts.nodes.len { return HostPhysical {..}, blot_error::Error.layout_limit; } remaining--; let n = context.layouts.node(id);
    if n.tag == blot_backend_layout::Tag.unit || n.tag == blot_backend_layout::Tag.boolean || n.tag == blot_backend_layout::Tag.unsigned32 { return HostPhysical {..}, blot_error::Error.none; }
    if n.tag == blot_backend_layout::Tag.floating32 { return HostPhysical { floating: true , ..}, blot_error::Error.none; }
    if n.tag == blot_backend_layout::Tag.product || n.tag == blot_backend_layout::Tag.record || n.tag == blot_backend_layout::Tag.array || n.tag == blot_backend_layout::Tag.list { return HostPhysical { reference: true , ..}, blot_error::Error.none; }
    if n.tag != blot_backend_layout::Tag.nominal || n.a == 0 || n.a > context.generator.units.len { return HostPhysical {..}, blot_error::Error.layout_limit; }
    let source .= unit(context.generator,n.a); var selected: i64 = -1;
    for candidate,index in source.nominals { if remaining == 0 { return HostPhysical {..}, blot_error::Error.layout_limit; } remaining--; if candidate.identity.unit == n.a && candidate.identity.decl == n.b { selected = index; break; } }
    if selected < 0 { return HostPhysical {..}, blot_error::Error.layout_limit; } let definition = source.nominals[selected];
    if !definition.closed_storage || definition.has_usage { return HostPhysical {..}, blot_error::Error.layout_limit; } if !definition.is_opaque { return HostPhysical { reference: true , ..}, blot_error::Error.none; }
    match definition.storage.kind {
        unit,boolean,unsigned32 => { return HostPhysical {..}, blot_error::Error.none; }, floating32 => { return HostPhysical { floating: true , ..}, blot_error::Error.none; }, reference => { return HostPhysical { reference: true , ..}, blot_error::Error.none; },
        parameter => {
            let parameters = source.types.list(definition.parameters); let actuals = context.layouts.children(id);
            if definition.storage.parameter >= parameters.len || parameters.len != actuals.len { return HostPhysical {..}, blot_error::Error.layout_limit; } var ordinal: u32 = 0;
            let selected,error = selectParameter(context,source,parameters[definition.storage.parameter],actuals[definition.storage.parameter],definition.storage.selector,ordinal,remaining,depth + 1); if error != blot_error::Error.none { return HostPhysical {..},error; }
            if !selected.present { return HostPhysical {..},blot_error::Error.layout_limit; } return physical(context,selected.value,remaining,depth + 1);
        },
        unknown => { return HostPhysical {..},blot_error::Error.layout_limit; },
    }
}
recursive fn selectParameter(context: HostSchemaContext, source: const blot_check_core::Module&, parameter: u32, actual: u32, target: u32, ordinal: u32&, remaining: i64&, depth: i64) -> blot_support::Option<u32>, blot_error::Error {
    if depth >= 128 || remaining == 0 || parameter == 0 || parameter >= source.types.nodes.len || actual == 0 || actual >= context.layouts.nodes.len { return blot_support::none<u32>(),blot_error::Error.layout_limit; } remaining--; let n = source.types.node(parameter);
    if n.tag == blot_check_types::Tag.variable { let selected = ordinal; ordinal++; if selected == target { return blot_support::some(actual),blot_error::Error.none; } return blot_support::none<u32>(),blot_error::Error.none; }
    let supplied = context.layouts.node(actual);
    if n.tag == blot_check_types::Tag.product && supplied.tag == blot_backend_layout::Tag.product && n.b == supplied.b {
        let actuals = context.layouts.children(actual); for child,index in source.types.list(blot_check_types::List { n.a,n.b }) { let selected,error = selectParameter(context,source,child,actuals[index],target,ordinal,remaining,depth + 1); if error != blot_error::Error.none || selected.present { return selected,error; } }
    } else if n.tag == blot_check_types::Tag.record && supplied.tag == blot_backend_layout::Tag.record {
        let fields = context.layouts.children(actual); for index in 0..n.b {
            let field = source.types.recordField(n,index); for slot in 0..fields.len / 2 {
                if remaining == 0 { return blot_support::none<u32>(),blot_error::Error.layout_limit; } remaining--; if fields[slot * 2] != field.name { continue; }
                let selected,error = selectParameter(context,source,field.ty,fields[slot * 2 + 1],target,ordinal,remaining,depth + 1); if error != blot_error::Error.none || selected.present { return selected,error; } break;
            }
        }
    }
    return blot_support::none<u32>(),blot_error::Error.none;
}
fn rowWords(context: HostSchemaContext, id: u32, remaining: i64&, depth: i64) -> u32, blot_error::Error { return rowWords(context.generator,id); }
fn nominal(context: HostSchemaContext, id: u32, remaining: i64&) -> blot_backend_host_cleanup_shapes::Facts, blot_error::Error {
    let generator .= context.generator; let n = context.layouts.node(id); if n.a == 0 || n.a > generator.units.len { return default<blot_backend_host_cleanup_shapes::Facts>(),blot_error::Error.layout_limit; }
    let source .= unit(generator,n.a); var selected: i64 = -1;
    for definition,index in source.nominals { if remaining == 0 { return default<blot_backend_host_cleanup_shapes::Facts>(),blot_error::Error.layout_limit; } remaining--; if definition.identity.unit == n.a && definition.identity.decl == n.b { selected = index; break; } }
    if selected < 0 { return default<blot_backend_host_cleanup_shapes::Facts>(),blot_error::Error.layout_limit; } let definition = source.nominals[selected];
    if !definition.closed_storage || definition.has_usage || context.layouts.children(id).len != definition.parameters.len { return default<blot_backend_host_cleanup_shapes::Facts>(),blot_error::Error.layout_limit; }
    let hidden = definition.is_opaque || definition.private; var variants: blot_backend_host_cleanup_shapes::Variant[>..<] = []; var mappings: Mapping[>..<] = []; let actuals = context.layouts.children(id);
    for parameter,index in source.types.list(definition.parameters) {
        let charged = shapeTypeWork(source,parameter,remaining,0); if charged != blot_error::Error.none { return default<blot_backend_host_cleanup_shapes::Facts>(),charged; }
        let error = mapType(generator,n.a,mappings,parameter,actuals[index],blot_check_core::Span { 0,0 , ..}); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return default<blot_backend_host_cleanup_shapes::Facts>(),error; } return default<blot_backend_host_cleanup_shapes::Facts>(),blot_error::Error.layout_limit; }
    }
    if hidden { return blot_backend_host_cleanup_shapes::Facts { source.name(definition.diagnostic_name),true,[] , ..},blot_error::Error.none; }
    for constructor in source.constructors {
        if remaining == 0 { return default<blot_backend_host_cleanup_shapes::Facts>(),blot_error::Error.layout_limit; } remaining--; if source.nominal(constructor.nominal).identity != definition.identity { continue; }
        let charged = shapeTypeWork(source,constructor.payload,remaining,0); if charged != blot_error::Error.none { return default<blot_backend_host_cleanup_shapes::Facts>(),charged; }
        let child,error = codeLayoutWithRows(generator,n.a,constructor.payload,mappings,[],blot_check_core::Span { 0,0 , ..}); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return default<blot_backend_host_cleanup_shapes::Facts>(),error; } return default<blot_backend_host_cleanup_shapes::Facts>(),blot_error::Error.layout_limit; }
        variants.push(blot_backend_host_cleanup_shapes::Variant { constructor.tag,child , ..});
    }
    return blot_backend_host_cleanup_shapes::Facts { source.name(definition.diagnostic_name),false,blot_backend_host_cleanup_shapes::copyVariants(variants) , ..},blot_error::Error.none;
}
recursive fn shapeTypeWork(module: const blot_check_core::Module&, id: u32, remaining: i64&, depth: i64) -> blot_error::Error {
    if remaining == 0 || depth >= 128 || id == 0 || id >= module.types.nodes.len { return blot_error::Error.layout_limit; } remaining--; let n = module.types.node(id);
    if n.tag == blot_check_types::Tag.unit || n.tag == blot_check_types::Tag.boolean || n.tag == blot_check_types::Tag.unsigned32 || n.tag == blot_check_types::Tag.floating32 || n.tag == blot_check_types::Tag.variable { return blot_error::Error.none; }
    if n.tag == blot_check_types::Tag.array || n.tag == blot_check_types::Tag.list { return shapeTypeWork(module,n.a,remaining,depth + 1); }
    if n.tag == blot_check_types::Tag.product { for child in module.types.list(blot_check_types::List { n.a,n.b }) { let error = shapeTypeWork(module,child,remaining,depth + 1); if error != blot_error::Error.none { return error; } } return blot_error::Error.none; }
    if n.tag == blot_check_types::Tag.record {
        let count = n.b as u64; if count != 0 && count > 9223372036854775807 / count { return blot_error::Error.layout_limit; } let pairs = (count * count) as i64; if remaining < pairs { return blot_error::Error.layout_limit; } remaining -= pairs;
        for index in 0..n.b { let error = shapeTypeWork(module,module.types.recordField(n,index).ty,remaining,depth + 1); if error != blot_error::Error.none { return error; } } return blot_error::Error.none;
    }
    if n.tag == blot_check_types::Tag.nominal { for child in module.types.nominalArguments(n) { let error = shapeTypeWork(module,child,remaining,depth + 1); if error != blot_error::Error.none { return error; } } return blot_error::Error.none; }
    return blot_error::Error.layout_limit;
}
fn emitHostDataSchemas(generator: Generator&) -> blot_error::Error {
    var roots: u32[>..<] = []; for item in generator.module.exports { if item.callback.present && item.callback.value.data { roots.push(item.callback.value.schema); } } if roots.len == 0 { return blot_error::Error.none; }
    var bytes: u8[>..<] = []; let error = blot_backend_host_cleanup_shapes::build(HostSchemaContext { generator,generator.representations.store , ..},roots,bytes);
    if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return error; } return decline(generator,1,blot_check_core::Span { 0,0 , ..},blot_check_diagnostic_code::Code.complexity); } return generator.module.setCleanupDataMetadata(bytes);
}
fn ownerRuntime(generator: Generator&) -> blot_runtime_public_owners::Runtime, blot_error::Error {
    if generator.public_owners.present { return generator.public_owners.value,blot_error::Error.none; }
    let runtime,error = blot_runtime_public_owners::emit(generator.module); if error != blot_error::Error.none { return runtime,error; }
    let release = generator.module.exportOwnerFunction(runtime.release,"blot:owner_release",blot_backend_runtime_ir::SC_u32,blot_backend_runtime_ir::SC_unit,false,blot_support::none<blot_backend_wasm::OwnerBoundary>(),blot_support::none<blot_backend_wasm::OwnerBoundary>(),true); if release != blot_error::Error.none { return runtime,release; }
    let token = generator.module.exportOwnerFunction(runtime.token,"blot:owner_token",blot_backend_runtime_ir::SC_u32,blot_backend_runtime_ir::SC_u32,false,blot_support::none<blot_backend_wasm::OwnerBoundary>(),blot_support::none<blot_backend_wasm::OwnerBoundary>(),true); if token != blot_error::Error.none { return runtime,token; }
    generator.public_owners = blot_support::some(runtime); return runtime,blot_error::Error.none;
}
fn ownerBoundary(generator: const Generator&, ty: u32) -> blot_support::Option<blot_backend_wasm::OwnerBoundary> {
    let n = generator.representations.store.node(ty); if n.tag != blot_backend_layout::Tag.owning { return blot_support::none<blot_backend_wasm::OwnerBoundary>(); } var kind: u8 = 1; if n.b == blot_check_types::usagekind_shared { kind = 2; } return blot_support::some(blot_backend_wasm::OwnerBoundary { schema: n.a,kind: kind , ..});
}
fn freshOwnerInput(generator: const Generator&, ty: u32) -> blot_support::Option<Scalar> {
    let payload = generator.representations.store.node(ty);
    if payload.tag == blot_backend_layout::Tag.unit || payload.tag == blot_backend_layout::Tag.boolean || payload.tag == blot_backend_layout::Tag.unsigned32 || payload.tag == blot_backend_layout::Tag.floating32 { return generator.representations.store.abi(ty); }
    if payload.tag == blot_backend_layout::Tag.array { let element = generator.representations.store.node(payload.a); if element.tag == blot_backend_layout::Tag.unsigned32 || element.tag == blot_backend_layout::Tag.floating32 { return generator.representations.store.abi(ty); } }
    return blot_support::none<Scalar>();
}
fn publishOwner(generator: Generator&, emitter: blot_backend_backend_emission::Owner&, owner: blot_backend_wasm::OwnerBoundary) -> blot_error::Error {
    let runtime,error = ownerRuntime(generator); if error != blot_error::Error.none { return error; } return emitOps(emitter,[I(blot_backend_runtime_ir::OP_i32_const,owner.schema),I(blot_backend_runtime_ir::OP_i32_const,owner.kind as u32),I(blot_backend_runtime_ir::OP_call,runtime.publish)]);
}
fn onceEntry(generator: Generator&, wrapper: u32, guard_: blot_support::Option<u32>) -> blot_error::Error {
    if !guard_.present { return blot_error::Error.none; } return generator.module.emitSlice(wrapper,[I(blot_backend_runtime_ir::OP_global_get,guard_.value),I(blot_backend_runtime_ir::OP_if_),I(blot_backend_runtime_ir::OP_unreachable_),I(blot_backend_runtime_ir::OP_end),I(blot_backend_runtime_ir::OP_i32_const,1),I(blot_backend_runtime_ir::OP_global_set,guard_.value)]);
}
fn hostDescriptor(generator: Generator&, emitter: blot_backend_backend_emission::Owner&, stub: u32, handle: u32) -> u32,blot_error::Error {
    let roles: blot_backend_runtime_ir::Role[3] = [blot_backend_runtime_ir::ROLE_scalar,blot_backend_runtime_ir::ROLE_scalar,blot_backend_runtime_ir::ROLE_scalar];
    let descriptor,error = emitter.allocate(blot_runtime_runtime_layout::HostClosure_bytes,blot_backend_backend_emission::AllocationRoles { words: roles , ..}); if error != blot_error::Error.none { return 0,error; }
    let pointer = emitter.emit(blot_backend_runtime_ir::OP_local_get,descriptor); if pointer != blot_error::Error.none { return 0,pointer; }
    let code = emitter.referenceConstant(stub,blot_reuse_artifact_emitter::Role.table_function); if code != blot_error::Error.none { return 0,code; }
    let prefix = emitOps(emitter,[I(blot_backend_runtime_ir::OP_i32_store),I(blot_backend_runtime_ir::OP_local_get,descriptor),I(blot_backend_runtime_ir::OP_local_get,descriptor)]); if prefix != blot_error::Error.none { return 0,prefix; }
    let identity = blot_backend_runtime_ir::selfIdentityStore(); let tagged = emitter.emit(identity.op,identity.operand); if tagged != blot_error::Error.none { return 0,tagged; }
    let fields = emitOps(emitter,[I(blot_backend_runtime_ir::OP_i32_store,4),I(blot_backend_runtime_ir::OP_local_get,descriptor),I(blot_backend_runtime_ir::OP_local_get,handle),I(blot_backend_runtime_ir::OP_i32_store,blot_runtime_runtime_layout::HostClosure_handle)]); if fields != blot_error::Error.none { return 0,fields; } return descriptor,blot_error::Error.none;
}
struct CallbackEntryEmission { target: u32,parameter: u32,result: Scalar,callback: blot_backend_wasm::Callback,stub: u32,arena: blot_backend_wasm::Arena,references: blot_backend_wasm::HostReferences,output: blot_support::Option<blot_backend_wasm::OwnerBoundary> }
fn emitCallbackEntryOwner(context: CallbackEntryEmission&, emitter: blot_backend_backend_emission::Owner&) -> blot_error::Error {
    let generator .= emitter.generator; let callback = context.callback; let references = context.references; let arena = context.arena;
    let confined = blot_backend_host_entry::confined(generator.module,context.target,context.stub,context.parameter,generator.request_owner); var previous = blot_support::none<u32>();
    if confined {
        let saved,error = emitter.temporary(blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return error; } previous = blot_support::some(saved);
        let emitted = emitOps(emitter,[I(blot_backend_runtime_ir::OP_global_get,references.active),I(blot_backend_runtime_ir::OP_local_set,saved)]); if emitted != blot_error::Error.none { return emitted; }
    }
    if generator.request_owner.present { let cleared = emitOps(emitter,[I(blot_backend_runtime_ir::OP_i32_const),I(blot_backend_runtime_ir::OP_global_set,generator.request_owner.value)]); if cleared != blot_error::Error.none { return cleared; } }
    let revoked = emitOps(emitter,[I(blot_backend_runtime_ir::OP_i32_const),I(blot_backend_runtime_ir::OP_call,references.release),I(blot_backend_runtime_ir::OP_i32_const),I(blot_backend_runtime_ir::OP_call,arena.reset),I(blot_backend_runtime_ir::OP_drop)]); if revoked != blot_error::Error.none { return revoked; }
    let handle,error = emitter.temporary(blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return error; }
    let argument = emitter.emit(blot_backend_runtime_ir::OP_local_get,0); if argument != blot_error::Error.none { return argument; }
    if callback.owned {
        if callback.data { let schema = emitter.emit(blot_backend_runtime_ir::OP_i32_const,callback.schema); if schema != blot_error::Error.none { return schema; } }
        let imported,import_error = generator.module.importOwnedCleanupBind(callback); if import_error != blot_error::Error.none { return import_error; }
        let bound = emitter.emit(blot_backend_runtime_ir::OP_call_import,imported); if bound != blot_error::Error.none { return bound; }
    } else { let retained = emitter.emit(blot_backend_runtime_ir::OP_call,references.retain); if retained != blot_error::Error.none { return retained; } }
    let saved = emitter.emit(blot_backend_runtime_ir::OP_local_set,handle); if saved != blot_error::Error.none { return saved; } var descriptor: u32;
    if confined {
        let selected,selected_error = emitter.temporary(blot_backend_runtime_ir::VT_i32); if selected_error != blot_error::Error.none { return selected_error; } descriptor = selected; assert(previous.present);
        let branch = emitOps(emitter,[I(blot_backend_runtime_ir::OP_local_get,previous.value),I(blot_backend_runtime_ir::OP_if_)]); if branch != blot_error::Error.none { return branch; }
        let nested,nested_error = hostDescriptor(generator,emitter,context.stub,handle); if nested_error != blot_error::Error.none { return nested_error; }
        let nested_store = emitOps(emitter,[I(blot_backend_runtime_ir::OP_local_get,nested),I(blot_backend_runtime_ir::OP_local_set,descriptor),I(blot_backend_runtime_ir::OP_else_)]); if nested_store != blot_error::Error.none { return nested_store; }
        let address = generator.module.data.len as u32; let allocated,allocated_error = generator.module.dataObject([context.stub,address,0]); if allocated_error != blot_error::Error.none { return allocated_error; }
        let code = generator.module.dataReference(address,blot_reuse_artifact_emitter::Operand { role: blot_reuse_artifact_emitter::Role.callable_function,value: context.stub , ..}); if code != blot_error::Error.none { return code; }
        let environment = generator.module.dataReference(address + 4,blot_reuse_artifact_emitter::Operand { role: blot_reuse_artifact_emitter::Role.static_address,value: address , ..}); if environment != blot_error::Error.none { return environment; }
        let checked = emitOps(emitter,[I(blot_backend_runtime_ir::OP_local_get,handle),I(blot_backend_runtime_ir::OP_if_),I(blot_backend_runtime_ir::OP_unreachable_),I(blot_backend_runtime_ir::OP_end)]); if checked != blot_error::Error.none { return checked; }
        let reference = emitter.referenceConstant(address,blot_reuse_artifact_emitter::Role.static_address); if reference != blot_error::Error.none { return reference; }
        let stored = emitter.emit(blot_backend_runtime_ir::OP_local_set,descriptor); if stored != blot_error::Error.none { return stored; }
        for offset in [0 as u32,4 as u32,8 as u32] {
            let field = emitOps(emitter,[I(blot_backend_runtime_ir::OP_local_get,descriptor),I(blot_backend_runtime_ir::OP_i32_load,offset)]); if field != blot_error::Error.none { return field; }
            if offset == 0 { let expected = emitter.referenceConstant(context.stub,blot_reuse_artifact_emitter::Role.table_function); if expected != blot_error::Error.none { return expected; } }
            else if offset == 4 { let expected = emitter.referenceConstant(address,blot_reuse_artifact_emitter::Role.static_address); if expected != blot_error::Error.none { return expected; } }
            else { let expected = emitter.emit(blot_backend_runtime_ir::OP_i32_const,0); if expected != blot_error::Error.none { return expected; } }
            let compared = emitOps(emitter,[I(blot_backend_runtime_ir::OP_i32_ne),I(blot_backend_runtime_ir::OP_if_),I(blot_backend_runtime_ir::OP_unreachable_),I(blot_backend_runtime_ir::OP_end)]); if compared != blot_error::Error.none { return compared; }
        }
        let ended = emitter.emit(blot_backend_runtime_ir::OP_end,0); if ended != blot_error::Error.none { return ended; }
    } else { let created,created_error = hostDescriptor(generator,emitter,context.stub,handle); if created_error != blot_error::Error.none { return created_error; } descriptor = created; }
    let called = emitOps(emitter,[I(blot_backend_runtime_ir::OP_local_get,descriptor),I(blot_backend_runtime_ir::OP_global_set,references.active),I(blot_backend_runtime_ir::OP_local_get,descriptor),I(blot_backend_runtime_ir::OP_i32_const),I(blot_backend_runtime_ir::OP_call,context.target)]); if called != blot_error::Error.none { return called; }
    if context.output.present { let published = publishOwner(generator,emitter,context.output.value); if published != blot_error::Error.none { return published; } }
    let result,result_error = emitter.temporary(blot_backend_runtime_ir::machine(context.result)); if result_error != blot_error::Error.none { return result_error; }
    return emitOps(emitter,[I(blot_backend_runtime_ir::OP_local_set,result),I(blot_backend_runtime_ir::OP_i32_const),I(blot_backend_runtime_ir::OP_call,references.release),I(blot_backend_runtime_ir::OP_local_get,result)]);
}
fn entryCallbackFunction(generator: Generator&,target: u32,parameter: u32,result: Scalar,guard_: blot_support::Option<u32>,output: blot_support::Option<blot_backend_wasm::OwnerBoundary>) -> u32,blot_error::Error {
    let callback = hostCallback(generator,parameter); if !callback.present { return 0,blot_error::Error.invalid_function_reference; }
    let stub,stub_error = hostFunction(generator,blot_reuse_code_artifacts::HostKey { ty: parameter,owned: callback.value.owned , ..}); if stub_error != blot_error::Error.none { return 0,stub_error; }
    let arena,arena_error = generator.module.ensureArena(); if arena_error != blot_error::Error.none { return 0,arena_error; }
    let references,references_error = generator.module.ensureHostReferences(); if references_error != blot_error::Error.none { return 0,references_error; }
    let wrapper,wrapper_error = generator.module.addTypedFunction([blot_backend_runtime_ir::VT_externref],blot_backend_runtime_ir::machine(result),blot_backend_runtime_ir::role(result)); if wrapper_error != blot_error::Error.none { return 0,wrapper_error; }
    let once = onceEntry(generator,wrapper,guard_); if once != blot_error::Error.none { return 0,once; }
    var context = CallbackEntryEmission { target,parameter,result,callback.value,stub,arena,references,output , ..};
    let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { generator: generator,unit_id: 1,function_id: wrapper,mappings: [] , ..},context,emitCallbackEntryOwner); if emitted != blot_error::Error.none { return 0,emitted; } return wrapper,blot_error::Error.none;
}
struct EntryEmission { target: u32,owning: blot_support::Option<u32>,input: blot_support::Option<blot_backend_wasm::OwnerBoundary>,output: blot_support::Option<blot_backend_wasm::OwnerBoundary>,leased: bool }
fn emitEntryOwner(context: EntryEmission&,emitter: blot_backend_backend_emission::Owner&) -> blot_error::Error {
    let generator .= emitter.generator; let argument = emitter.emit(blot_backend_runtime_ir::OP_local_get,0); if argument != blot_error::Error.none { return argument; }
    if context.leased {
        assert(context.input.present); let owner = context.input.value; let runtime,error = ownerRuntime(generator); if error != blot_error::Error.none { return error; } var unique: u32 = 0; if owner.kind == 1 { unique = 1; }
        let taken = emitOps(emitter,[I(blot_backend_runtime_ir::OP_i32_const,owner.schema),I(blot_backend_runtime_ir::OP_i32_const,owner.kind as u32),I(blot_backend_runtime_ir::OP_i32_const,unique),I(blot_backend_runtime_ir::OP_call,runtime.take)]); if taken != blot_error::Error.none { return taken; }
    } else if context.owning.present { let boxed = emitter.boxOwner(context.owning.value); if boxed != blot_error::Error.none { return boxed; } }
    let called = emitOps(emitter,[I(blot_backend_runtime_ir::OP_i32_const),I(blot_backend_runtime_ir::OP_call,context.target)]); if called != blot_error::Error.none { return called; }
    if context.output.present { return publishOwner(generator,emitter,context.output.value); } return blot_error::Error.none;
}
fn entryFunction(generator: Generator&,target: u32,parameter: Scalar,result: Scalar,owning: blot_support::Option<u32>,guard_: blot_support::Option<u32>,input: blot_support::Option<blot_backend_wasm::OwnerBoundary>,output: blot_support::Option<blot_backend_wasm::OwnerBoundary>,leased: bool) -> u32,blot_error::Error {
    let wrapper,wrapper_error = generator.module.addTypedFunction([blot_backend_runtime_ir::machine(parameter)],blot_backend_runtime_ir::machine(result),blot_backend_runtime_ir::role(result)); if wrapper_error != blot_error::Error.none { return 0,wrapper_error; }
    let described = setParameterRoles(generator,wrapper,blot_backend_runtime_ir::packParameterRoles([blot_backend_runtime_ir::role(parameter)]),blot_support::none<u16>()); if described != blot_error::Error.none { return 0,described; }
    let once = onceEntry(generator,wrapper,guard_); if once != blot_error::Error.none { return 0,once; }
    if generator.request_owner.present { let cleared = generator.module.emitSlice(wrapper,[I(blot_backend_runtime_ir::OP_i32_const),I(blot_backend_runtime_ir::OP_global_set,generator.request_owner.value)]); if cleared != blot_error::Error.none { return 0,cleared; } }
    if parameter != blot_backend_runtime_ir::SC_array_u32 && parameter != blot_backend_runtime_ir::SC_array_f32 && generator.module.arena.present {
        let reset = generator.module.emitSlice(wrapper,[I(blot_backend_runtime_ir::OP_i32_const),I(blot_backend_runtime_ir::OP_call,generator.module.arena.value.reset),I(blot_backend_runtime_ir::OP_drop)]); if reset != blot_error::Error.none { return 0,reset; }
    }
    var context = EntryEmission { target,owning,input,output,leased , ..}; let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { generator: generator,unit_id: 1,function_id: wrapper,mappings: [] , ..},context,emitEntryOwner); if emitted != blot_error::Error.none { return 0,emitted; } return wrapper,blot_error::Error.none;
}
fn entryData(view: blot_eval_type_evidence::View,id: u32,arrays: bool) -> bool {
    let n = view.node(id); if n.tag == blot_eval_type_evidence::Tag.unit || n.tag == blot_eval_type_evidence::Tag.boolean || n.tag == blot_eval_type_evidence::Tag.unsigned32 || n.tag == blot_eval_type_evidence::Tag.floating32 { return true; }
    if n.tag == blot_eval_type_evidence::Tag.array && arrays { let child = view.node(n.a); return child.tag == blot_eval_type_evidence::Tag.unsigned32 || child.tag == blot_eval_type_evidence::Tag.floating32; } return false;
}
fn entryForeign(view: blot_eval_type_evidence::View,row: u32,exactly_one: bool) -> bool {
    let labels = view.effects.rowLabels(row); if exactly_one && labels.len != 1 { return false; } for label in labels { let operation = view.effects.operation(label); if operation.instance.unit != 0 || operation.instance.decl != 0 || operation.identity.unit != 0 || operation.identity.decl != 1 || operation.arguments.len != 0 { return false; } } return true;
}
recursive fn entryClosedData(generator: const Generator&,view: blot_eval_type_evidence::View,id: u32,depth: i64,remaining: i64&) -> bool {
    if remaining == 0 || depth >= 128 || id >= view.nodes.len { return false; } remaining--; let n = view.node(id);
    if n.tag == blot_eval_type_evidence::Tag.unit || n.tag == blot_eval_type_evidence::Tag.boolean || n.tag == blot_eval_type_evidence::Tag.unsigned32 || n.tag == blot_eval_type_evidence::Tag.floating32 { return true; }
    if n.tag == blot_eval_type_evidence::Tag.array || n.tag == blot_eval_type_evidence::Tag.list { return entryClosedData(generator,view,n.a,depth + 1,remaining); }
    if n.tag != blot_eval_type_evidence::Tag.product && n.tag != blot_eval_type_evidence::Tag.record && n.tag != blot_eval_type_evidence::Tag.nominal { return false; }
    if n.tag == blot_eval_type_evidence::Tag.nominal {
        if n.a == 0 || n.a > generator.units.len { return false; } var found = false;
        for nominal in generator.units[n.a - 1].nominals {
            if remaining == 0 { return false; } remaining--; if nominal.identity.unit != n.a || nominal.identity.decl != n.b { continue; }
            if found || !nominal.closed_storage || nominal.has_usage || view.children(id).len != nominal.parameters.len { return false; } found = true;
        }
        if !found { return false; }
    }
    for child,index in view.children(id) { if n.tag == blot_eval_type_evidence::Tag.record && index % 2 == 0 { continue; } if !entryClosedData(generator,view,child,depth + 1,remaining) { return false; } } return true;
}
fn entryOwnerPayload(generator: const Generator&,view: blot_eval_type_evidence::View,id: u32) -> bool { var remaining: i64 = 65536; return entryClosedData(generator,view,id,0,remaining); }
fn entryOwner(generator: const Generator&,view: blot_eval_type_evidence::View,id: u32) -> bool {
    let owner = view.node(id); if owner.tag != blot_eval_type_evidence::Tag.usage || owner.c != 0 || (owner.b != blot_check_types::usagekind_unique && owner.b != blot_check_types::usagekind_shared) { return false; } var remaining: i64 = 65536; return entryClosedData(generator,view,owner.a,0,remaining);
}
fn entryInterfaceAdmissible(generator: const Generator&,view: blot_eval_type_evidence::View,id: u32) -> bool {
    let n = view.node(id); if n.tag != blot_eval_type_evidence::Tag.function { return entryData(view,id,false); }
    if (!entryData(view,n.b,true) && !entryOwner(generator,view,n.b)) || !entryForeign(view,n.c,false) { return false; }
    if entryData(view,n.a,true) { return true; } let parameter = view.node(n.a);
    if parameter.tag == blot_eval_type_evidence::Tag.usage && parameter.b == blot_check_types::usagekind_concurrent && parameter.c == 0 {
        let host = view.node(parameter.a); return host.tag == blot_eval_type_evidence::Tag.function && entryData(view,host.a,true) && entryData(view,host.b,true) && entryForeign(view,host.c,true);
    }
    if parameter.tag == blot_eval_type_evidence::Tag.usage && parameter.b == blot_check_types::usagekind_cleanup && parameter.c == 0 {
        let cleanup = view.node(parameter.a); if cleanup.tag != blot_eval_type_evidence::Tag.function || view.node(cleanup.b).tag != blot_eval_type_evidence::Tag.unit || !entryForeign(view,cleanup.c,true) { return false; }
        let owner = view.node(cleanup.a); return owner.tag == blot_eval_type_evidence::Tag.usage && owner.b == blot_check_types::usagekind_unique && owner.c == 0 && entryOwnerPayload(generator,view,owner.a);
    }
    if entryOwner(generator,view,n.a) { return true; } return parameter.tag == blot_eval_type_evidence::Tag.function && entryData(view,parameter.a,true) && entryData(view,parameter.b,true) && entryForeign(view,parameter.c,true);
}
let entry_abi_rule = "entry functions take or return Unit, U32, F32, Bool, Array U32, Array F32, or unique/shared owners of closed data; one exact Foreign scalar/numeric-array callback or synchronous cleanup descriptor is also accepted as input; every other effect must be handled; entry values are Unit, U32, F32 or Bool";
fn validateEntryInterfaces(generator: Generator&,entry: u32) -> blot_error::Error {
    let timing = generator.work_timing.enter(blot_backend_backend_timing::Phase.interfaces);
    recursive fn cleanup_continuation_13() -> blot_error::Error {
 let source .= unit(generator,entry);
    var headers: blot_eval_core_eval::SourceInterface[>..<] = []; for body in source.bodies { headers.push(blot_eval_core_eval::SourceInterface {..}); }
    for functions in [true,false] { for body,index in source.bodies[1..] {
        if !body.exported || body.is_function != functions { continue; } let target = blot_check_core::BindingRef { entry,body.binding , ..}; let before = generator.evaluator.steps;
        let header,error = generator.evaluator.sourceInterface(target); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return error; } return evaluationFailure(generator); } headers[index + 1] = header; assert(generator.evaluator.steps == before);
    } }
    for functions in [true,false] { for body,index in source.bodies[1..] {
        if !body.exported || body.is_function != functions { continue; } let header = headers[index + 1];
        if !header.selected || header.generic || (header.evidence != 0 && !entryInterfaceAdmissible(generator,generator.evaluator.evidenceView(),header.evidence)) { return declineEntryInterface(generator,entry,body,header); }
        if source.has_usage_contracts && header.evidence != 0 { let view = generator.evaluator.evidenceView(); let interface = view.node(header.evidence); if interface.tag == blot_eval_type_evidence::Tag.function && entryOwner(generator,view,interface.b) { generator.persistent_outputs = true; } }
    } }
    return blot_error::Error.none;

    }
    let cleanup_result_13_0 = cleanup_continuation_13();
     timing.deinit();
    return cleanup_result_13_0;
}
fn generate(generator: Generator&,entry: u32,unit_order: const u32[:]) -> blot_error::Error {
    if entry == 0 || entry > generator.units.len { return decline(generator,1,blot_check_core::Span { 0,0 , ..},blot_check_diagnostic_code::Code.unsupported); } let source .= unit(generator,entry); var exports: i64 = 0;
    block {
        let timing = generator.work_timing.enter(blot_backend_backend_timing::Phase.principals);  let valid = validateEntryInterfaces(generator,entry); if valid != blot_error::Error.none { let __cleanup_result_1_0: blot_error::Error = valid; { timing.deinit(); } return __cleanup_result_1_0; }
        for functions in [true,false] { for body in source.bodies[1..] {
            if !body.exported || body.is_function != functions { continue; } exports++; let error = generator.evaluator.prepare(blot_check_core::BindingRef { entry,body.binding , ..}); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { let __cleanup_result_2_0: blot_error::Error = error; { timing.deinit(); } return __cleanup_result_2_0; } let __cleanup_result_3_0: blot_error::Error = evaluationFailure(generator); { timing.deinit(); } return __cleanup_result_3_0; }
        } }
        if exports == 0 { let __cleanup_result_4_0: blot_error::Error = decline(generator,entry,blot_check_core::Span { 0,0 , ..},blot_check_diagnostic_code::Code.no_entry); { timing.deinit(); } return __cleanup_result_4_0; }
     { timing.deinit(); } }
    block { let timing = generator.work_timing.enter(blot_backend_backend_timing::Phase.startup);  let planned = generator.planning.planRuntime(generator,entry,unit_order); if planned != blot_error::Error.none { let __cleanup_result_5_0: blot_error::Error = planned; { timing.deinit(); } return __cleanup_result_5_0; }  { timing.deinit(); } }
    for body in source.bodies[1..] {
        if !body.exported { continue; } let target = blot_check_core::BindingRef { entry,body.binding , ..};
        if body.is_function || source.types.node(source.binding(body.binding).ty).tag == blot_check_types::Tag.function {
            let key,key_error = entrySignature(generator,target,body.scheme.root,body.span); if key_error != blot_error::Error.none { return key_error; }
            if key.count != 1 || !foreignRow(generator,key.effects[0],false) { return decline(generator,entry,body.span,blot_check_diagnostic_code::Code.entry_type); }
            let output = ownerBoundary(generator,key.result); var result = generator.representations.store.abi(key.result); if output.present { result = blot_support::some(blot_backend_runtime_ir::SC_u32); } if !result.present { return decline(generator,entry,body.span,blot_check_diagnostic_code::Code.entry_type); }
            let callback = hostCallback(generator,key.parameters[0]); let input = generator.representations.store.node(key.parameters[0]); var owner_input = ownerBoundary(generator,key.parameters[0]); var payload = blot_support::none<u32>(); var parameter = generator.representations.store.abi(key.parameters[0]); var leased = false;
            if owner_input.present { owner_input.value.fresh = freshOwnerInput(generator,input.a); parameter = owner_input.value.fresh; if !parameter.present { parameter = blot_support::some(blot_backend_runtime_ir::SC_u32); leased = true; } else { payload = blot_support::some(input.a); } }
            if !generator.persistent_outputs && payload.present { owner_input = blot_support::none<blot_backend_wasm::OwnerBoundary>(); } if !callback.present && !parameter.present { return decline(generator,entry,body.span,blot_check_diagnostic_code::Code.entry_type); }
            let function_id,function_error = function(generator,key); if function_error != blot_error::Error.none { return function_error; }
            var header = source.types.node(body.scheme.root); while header.tag == blot_check_types::Tag.forall { header = source.types.node(header.a); }
            let once = header.tag == blot_check_types::Tag.usage && header.b == blot_check_types::usagekind_once; var guard_ = blot_support::none<u32>();
            if once { let global,error = generator.module.addGlobal(blot_backend_runtime_ir::SC_u32,0,true); if error != blot_error::Error.none { return error; } guard_ = blot_support::some(global); }
            if callback.present {
                var host = callback.value; var signature = source.types.node(body.scheme.root); while signature.tag == blot_check_types::Tag.forall || signature.tag == blot_check_types::Tag.usage { signature = source.types.node(signature.a); } let qualified = source.types.node(signature.a);
                if qualified.tag == blot_check_types::Tag.usage && qualified.b == blot_check_types::usagekind_concurrent { host.concurrent = true; let runtime,error = taskRuntime(generator); if error != blot_error::Error.none { return error; } }
                let wrapper,error = entryCallbackFunction(generator,function_id,key.parameters[0],result.value,guard_,output); if error != blot_error::Error.none { return error; }
                let exported = generator.module.exportOwnerCallbackFunction(wrapper,source.name(body.export_name),host,result.value,once,output); if exported != blot_error::Error.none { return exported; }
            } else {
                let wrapper,error = entryFunction(generator,function_id,parameter.value,result.value,payload,guard_,owner_input,output,leased); if error != blot_error::Error.none { return error; }
                let exported = generator.module.exportOwnerFunction(wrapper,source.name(body.export_name),parameter.value,result.value,once,owner_input,output,false); if exported != blot_error::Error.none { return exported; }
                if owner_input.present && !leased {
                    var name: u8[>..<] = []; name.append("blot:owner_call/"); name.append(source.name(body.export_name));
                    let adapter,adapter_error = entryFunction(generator,function_id,blot_backend_runtime_ir::SC_u32,result.value,blot_support::none<u32>(),guard_,owner_input,output,true); if adapter_error != blot_error::Error.none { return adapter_error; }
                    let exported_adapter = generator.module.exportOwnerFunction(adapter,name,blot_backend_runtime_ir::SC_u32,result.value,once,blot_support::none<blot_backend_wasm::OwnerBoundary>(),blot_support::none<blot_backend_wasm::OwnerBoundary>(),true); if exported_adapter != blot_error::Error.none { return exported_adapter; }
                }
            }
            if owner_input.present || output.present { let runtime,error = ownerRuntime(generator); if error != blot_error::Error.none { return error; } }
        } else if body.runtime {
            let concrete,layout_error = typeLayout(generator,entry,body.scheme.root,[],body.span); if layout_error != blot_error::Error.none { return layout_error; }
            let scalar = generator.representations.store.abi(concrete); if !scalar.present || scalar.value == blot_backend_runtime_ir::SC_array_u32 || scalar.value == blot_backend_runtime_ir::SC_array_f32 { return decline(generator,entry,body.span,blot_check_diagnostic_code::Code.entry_type); }
            let global,error = generator.planning.runtimeGlobal(generator,target); if error != blot_error::Error.none { return error; } let exported = generator.module.exportGlobal(global,source.name(body.export_name)); if exported != blot_error::Error.none { return exported; }
        } else {
            let evaluated,error = generator.evaluator.richValue(target); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return error; } return evaluationFailure(generator); }
            let value = generator.evaluator.valueScalar(evaluated); if !value.present { return decline(generator,entry,body.span,blot_check_diagnostic_code::Code.entry_type); }
            let exported = generator.module.exportConstant(source.name(body.export_name),value.value.scalar,value.value.bits); if exported != blot_error::Error.none { return exported; }
        }
    }
    if exports == 0 { return decline(generator,entry,blot_check_core::Span { 0,0 , ..},blot_check_diagnostic_code::Code.no_entry); } return emitHostDataSchemas(generator);
}
struct EntryDisplay { generator: Generator&,text: u8[>..<]& }
fn append(display: EntryDisplay&,bytes: const u8[:]) -> blot_error::Error { display.text.append(bytes); return blot_error::Error.none; }
fn qualified(display: EntryDisplay&,owner: u32,name: const u8[:],saved_origin: const u8[:]) -> bool,blot_error::Error {
    let generator .= display.generator; if owner == 0 || owner > generator.units.len || name.len == 0 { return false,blot_error::Error.none; }
    let context = generator.evaluator.diagnostic_context; var path: u8[>..<] = []; var origin: const u8[:] = saved_origin;
    if context.identity.present {
        if owner == context.prelude && context.prelude != 0 { origin = "std/prelude"; }
        else if context.source_mode && owner == context.entry { origin = "main"; }
        else {
            let entry_path = context.identity.value.owner(context.entry); let owner_path = context.identity.value.owner(owner); if !entry_path.present || !owner_path.present { return false,blot_error::Error.none; }
            let directory = blot_support_path::dirname(entry_path.value); if !directory.present { return false,blot_error::Error.none; }
            let error = blot_support_path::relative(directory.value,owner_path.value,path); if error != blot_error::Error.none { return false,error; } origin = path;
        }
    }
    if origin.len == 0 { return false,blot_error::Error.none; } display.text.append(origin); display.text.append("::"); display.text.append(name); return true,blot_error::Error.none;
}
fn nominal(display: EntryDisplay&,node: blot_eval_type_evidence::Node) -> bool,blot_error::Error {
    let generator .= display.generator; if node.a == 0 || node.a > generator.units.len { return false,blot_error::Error.none; } let source .= unit(generator,node.a);
    for item in source.nominals { if item.identity.decl == node.b && (item.identity.unit == 0 || item.identity.unit == node.a) { return qualified(display,node.a,source.name(item.diagnostic_name),source.name(item.diagnostic_origin)); } }
    return false,blot_error::Error.none;
}
fn operationName(display: EntryDisplay&,identity: blot_check_types::NominalIdentity) -> bool,blot_error::Error {
    if identity.unit == 0 && identity.decl == 1 { display.text.append("blot:compiler::Foreign"); return true,blot_error::Error.none; }
    let generator .= display.generator; if identity.unit == 0 || identity.unit > generator.units.len { return false,blot_error::Error.none; } let source .= unit(generator,identity.unit);
    for item in source.operation_names { if item.identity.decl == identity.decl && (item.identity.unit == 0 || item.identity.unit == identity.unit) { return qualified(display,identity.unit,source.name(item.diagnostic_name),source.name(item.diagnostic_origin)); } } return false,blot_error::Error.none;
}
recursive fn children(display: EntryDisplay&,values: const u32[:],depth: u8,arguments: bool) -> bool,blot_error::Error {
    if depth == 0 { display.text.append("..."); return true,blot_error::Error.none; } if values.len == 0 { return true,blot_error::Error.none; }
    if arguments { display.text.append(" ("); } let printed,error = ty(display,values[0],depth - 1); if error != blot_error::Error.none || !printed { return printed,error; }
    if arguments { display.text.append(")"); } else if values.len > 1 { display.text.append(", "); } if !arguments && values.len == 1 { return true,blot_error::Error.none; } return children(display,values[1..],depth - 1,arguments);
}
fn row(display: EntryDisplay&,id: u32,depth: u8) -> bool,blot_error::Error {
    let view = display.generator.evaluator.evidenceView(); let labels = view.effects.rowLabels(id); if labels.len == 0 { return true,blot_error::Error.none; } display.text.append(" ! {");
    for label,index in labels {
        if index != 0 { display.text.append(", "); } let operation = view.effects.operation(label); let printed,error = operationName(display,operation.identity); if error != blot_error::Error.none || !printed { return printed,error; }
        for argument in view.effects.operationArguments(label) { display.text.append(" ("); let child,child_error = ty(display,argument,depth); if child_error != blot_error::Error.none || !child { return child,child_error; } display.text.append(")"); }
    }
    display.text.append("}"); return true,blot_error::Error.none;
}
recursive fn ty(display: EntryDisplay&,id: u32,depth: u8) -> bool,blot_error::Error {
    if depth == 0 { display.text.append("..."); return true,blot_error::Error.none; } let view = display.generator.evaluator.evidenceView(); let n = view.node(id);
    match n.tag {
        unit => { display.text.append("Unit"); }, boolean => { display.text.append("Bool"); }, unsigned32 => { display.text.append("U32"); }, floating32 => { display.text.append("F32"); }, never => { display.text.append("Never"); },
        function => {
            display.text.push('('); let argument,error = ty(display,n.a,depth - 1); if error != blot_error::Error.none || !argument { return argument,error; } display.text.append(" -> ");
            let result,result_error = ty(display,n.b,depth - 1); if result_error != blot_error::Error.none || !result { return result,result_error; } let effects,effect_error = row(display,n.c,depth - 1); if effect_error != blot_error::Error.none || !effects { return effects,effect_error; } display.text.push(')');
        },
        array,list,cursor => {
            if n.tag == blot_eval_type_evidence::Tag.cursor { display.text.append("Cursor ("); } else if n.tag == blot_eval_type_evidence::Tag.list { display.text.append("List ("); } else { display.text.append("Array ("); }
            let child,error = ty(display,n.a,depth - 1); if error != blot_error::Error.none || !child { return child,error; } display.text.push(')');
        },
        product => { display.text.push('('); let printed,error = children(display,view.children(id),depth - 1,false); if error != blot_error::Error.none || !printed { return printed,error; } display.text.push(')'); },
        nominal => { let printed,error = nominal(display,n); if error != blot_error::Error.none || !printed { return printed,error; } return children(display,view.children(id),depth - 1,true); },
        _ => { return false,blot_error::Error.none; },
    }
    return true,blot_error::Error.none;
}
fn declineEntryInterface(generator: Generator&,entry: u32,body: const blot_check_core::Body&,header: blot_eval_core_eval::SourceInterface) -> blot_error::Error {
    let point = unit(generator,entry).sourceNamePoint(body.binding); var code = blot_check_diagnostic_code::Code.entry_type; if body.runtime { code = blot_check_diagnostic_code::Code.entry_let_type; } let failure = decline(generator,entry,blot_check_core::Span { point,point , ..},code);
    var message: u8[>..<] = []; let name = unit(generator,entry).name(body.export_name);
    if !header.selected { message.append("entry `"); message.append(name); message.append("` has a generic type, so it cannot be a Wasm export: "); message.append(entry_abi_rule); }
    else {
        if header.generic || header.evidence == 0 { return failure; } var text: u8[>..<] = []; var display = EntryDisplay { generator,text , ..}; let printed,error = ty(display,header.evidence,64); if error != blot_error::Error.none { return error; } if !printed { return failure; }
        if body.runtime {
            message.append("entry let `"); message.append(name); message.append("` initializes a runtime value of type "); message.append(text); message.append("; the guest ABI exports runtime-initialized values only as Unit, U32, F32 or Bool globals or as functions that fit it: "); message.append(entry_abi_rule);
        } else { message.append("entry `"); message.append(name); message.append("` has type "); message.append(text); message.append(", which does not fit the guest ABI: "); message.append(entry_abi_rule); }
    }
    generator.evaluator.owned_diagnostic_message.clear(); generator.evaluator.owned_diagnostic_message.append(message); if generator.diagnostic.present { generator.diagnostic.value.detail = generator.evaluator.owned_diagnostic_message; } return failure;
}
fn deinit(generator: Generator&) {
    generator.diagnostic_contexts.deinit(); generator.spawn_units = []; generator.numeric_rows.deinit(); generator.planning.deinit(); generator.module.deinit(); generator.representations.deinit(); generator.static_data.deinit();
}
fn quantifiedVariable(generator: Generator&,unit_id: u32,variable: u32,row: bool) -> bool,blot_error::Error {
    block { let known = generator.planning.quantified.get(unit_id); if known { return known.has(variable,row),blot_error::Error.none; } }
    let set,error = blot_backend_unit_index::initQuantified(unit(generator,unit_id)); if error != blot_error::Error.none { return false,error; }
    let found = set.has(variable,row); generator.planning.quantified.insert(unit_id,set); return found,blot_error::Error.none;
}
fn unitUses(generator: Generator&,unit_id: u32,need: blot_backend_unit_index::Need) -> const blot_backend_unit_index::Uses&,blot_error::Error {
    var index: blot_backend_unit_index::Uses&? = null; block { let known = generator.planning.uses.get(unit_id); if known { index .= known; } }
    if index == null { let fresh,error = blot_backend_unit_index::createUses(unit(generator,unit_id),unit_id); if error != blot_error::Error.none { return fresh,error; } generator.planning.uses.insert(unit_id,fresh); index .= fresh; }
    let error = index.ensure(unit(generator,unit_id),unit_id,need); return index,error;
}
fn ownsArrayUpdate(generator: Generator&,unit_id: u32,id: u32) -> bool,blot_error::Error {
    block { let proof = generator.planning.array_proofs.get(unit_id); if proof { return proof.admits(id),blot_error::Error.none; } }
    let proof,error = blot_backend_owned_arrays::init(generator.units,unit_id); if error != blot_error::Error.none { return false,error; } let admitted = proof.admits(id); generator.planning.array_proofs.insert(unit_id,proof); return admitted,blot_error::Error.none;
}
fn numericCheck(generator: Generator&,unit_id: u32,id: u32) -> bool,blot_error::Error {
    if id == 0 { return false,blot_error::Error.none; } block { let known = generator.planning.numeric_plans.get(unit_id); if known { return known.admits(id),blot_error::Error.none; } }
    var units: (const blot_check_core::Module&)[>..<] = []; for source in generator.units { units.push(source); }
    let plan,error = blot_check_numeric_proof_core::analyze(unit(generator,unit_id),units,blot_check_numeric_proof_core::Options {..}); if error != blot_error::Error.none { return false,error; }
    let admitted = plan.admits(id); generator.planning.numeric_plans.insert(unit_id,plan); return admitted,blot_error::Error.none;
}
let default_artifact_replay = blot_compiler_defaults::artifact_replay;
struct ConstantLimits { steps: blot_support::Option<i64>,values: blot_support::Option<i64>,children: blot_support::Option<i64>,depth: blot_support::Option<i64>,calls: blot_support::Option<i64> }
struct CompileOptions {
    completed_core_validation: blot_reuse_completed_core_validation::Borrow&? = null,source_completion: blot_reuse_source_completion::Borrow,
    storage: blot_support::Option<blot_backend_storage_plan::Config>,inline_named: bool = true,explain_allocations: bool = false,ragged_builders: bool = true,constant_receipts: bool = true,constant_limits: ConstantLimits,
    ragged_probe_limit: u32 = blot_backend_ragged_builder::probe_limit,checkpoint: const blot_backend_backend_checkpoint::Checkpoint&? = null,io: bool = false,profile_backend: bool = false,policy: blot_execution_policy::Policy,observe_startup: bool = false,
    identity: blot_support::Option<blot_backend_runtime_identity::View>,diagnostic_source_digests: const u8[32][:] = [],compiler_identity: blot_support::Option<u8[32]>,evidence_noise: bool = false,unit_order: const u32[:] = default<const u32[:]>(),diagnostic_source_mode: bool = false,diagnostic_prelude_unit: u32 = 0,
    artifact_replay: bool = false,artifact_dump: bool = false,retain_artifacts: bool = false,previous: const blot_reuse_artifact_capture::Capture&? = null,principal_previous: const blot_reuse_artifact_capture::Capture&? = null,query_previous: const blot_reuse_artifact_capture::Capture&? = null,cached_units: i64 = 0,validate_pins: bool = false,
}
// Every mutable owner is placed by the driver before provider borrows bind.
// Successful retained output keeps its own contexts until Result.deinit.
struct CompileWorkspace {
    publication_owner: blot_backend_result_publication::Owner,compiled_units: const blot_check_core::Module[:] = default<const blot_check_core::Module[:]>(),
    allocation_owner: u64,generator: Generator&,session_tables: blot_eval_core_eval::SessionTables,
    module_stamps: blot_reuse_code_artifacts::ModuleStamps&,journal: blot_reuse_artifact_emitter::Recorder&,metadata: blot_reuse_code_artifacts::Context&,
    retained: blot_reuse_artifact_fragment::State&,principal_state: blot_reuse_principal_evidence_reuse::State&,persisted_principals: blot_reuse_principal_archive::Reader&,query_state: blot_eval_completed_specialization_query::State&,constant_state: blot_reuse_constant_receipt_reuse::State&,
    origins: blot_backend_source_origins::View&,candidate: blot_backend_region_candidate::Extension&,vectors: blot_backend_simd_abi::View&,optimized: blot_backend_optimized_bodies::Capture&,
    capture: blot_reuse_artifact_capture::Capture&,allocation_snapshot: blot_backend_allocation_emission::Snapshot&,startup_snapshot: blot_backend_startup_emission_facts::Snapshot&,explanation: blot_reuse_dispatch_explanation::Explanation&,
    bytes: u8[>..<]&,message: u8[>..<]&,replay_module: blot_backend_wasm::Module&,replay_origins: blot_backend_source_origins::View&,replay_candidate: blot_backend_region_candidate::Extension&,replay_vectors: blot_backend_simd_abi::View&,replay_contexts: blot_backend_source_origins::Context[>..<]&,replay_bytes: u8[>..<]&,
}
struct CompileRun {
    workspace: CompileWorkspace&,units: const blot_check_core::Module[:],entry: u32,options: CompileOptions,clock: blot_backend_backend_timing::Clock,timing: blot_backend_backend_timing::Stats,
    recording: bool = false,speculative_locals: bool = true,stamps_alive: bool = false,stamps: blot_reuse_code_artifacts::ModuleStamps&? = null,journal_alive: bool = false,metadata_alive: bool = false,generator_alive: bool = false,
    retained: blot_reuse_artifact_fragment::State&? = null,principal_state: blot_reuse_principal_evidence_reuse::State&? = null,persisted_principals: blot_reuse_principal_archive::Reader&? = null,query_state: blot_eval_completed_specialization_query::State&? = null,constant_state: blot_reuse_constant_receipt_reuse::State&? = null,
    origins: blot_backend_source_origins::View&? = null,candidate: blot_backend_region_candidate::Extension&? = null,vectors: blot_backend_simd_abi::View&? = null,optimized: blot_backend_optimized_bodies::Capture&? = null,
}
fn emptyResult(workspace: CompileWorkspace&) -> Result { assert(blot_backend_result_publication::canMutate(workspace.publication_owner)); workspace.bytes.clear(); workspace.message.clear(); return Result {..}; }
fn deinit(result: Result&) {
    if result.publication_owner.slot != 0 { assert(blot_backend_result_publication::resultValid(result.publication_owner,result.publication_epoch,result.publication_pinned)); }
    if !result.detached { let allocation .= result.allocation_emission; if allocation { allocation.deinit(); } let explanation .= result.explanation; if explanation { explanation.deinit(); } let observation .= result.startup_observation; if observation { observation.deinit(); } }
    let capture .= result.capture; if capture { capture.deinit(); } result.capture .= null; result.allocation_emission .= null; result.explanation .= null; result.startup_observation .= null;
    if result.output_owner.slot != 0 { result.output_owner.deinit(); }
    if result.publication_owner.slot != 0 { blot_backend_result_publication::releaseResult(result.publication_owner,result.publication_epoch,result.publication_pinned); }
    result.publication_owner = blot_backend_result_publication::Owner {..}; result.publication_epoch = 0; result.publication_pinned = false; result.publication_units = []; result.active = false; result.detached = false; result.message_source = []; result.diagnostic = blot_support::none<Diagnostic>(); result.bytes .= inactive_result_bytes; result.owned_message .= inactive_result_message;
}
fn deinit(run: CompileRun&) {
    if run.optimized != null { run.optimized.deinit(); } if run.vectors != null { run.vectors.deinit(); } if run.candidate != null { run.candidate.deinit(); } if run.origins != null { run.origins.deinit(); }
    if run.constant_state != null { run.constant_state.deinit(); } if run.query_state != null { run.query_state.deinit(); } if run.persisted_principals != null { run.persisted_principals.deinit(); } if run.principal_state != null { run.principal_state.deinit(); } if run.retained != null { run.retained.deinit(); }
    if run.generator_alive { run.workspace.generator.deinit(); } if run.metadata_alive { run.workspace.metadata.deinit(); } if run.journal_alive { run.workspace.journal.deinit(); } if run.stamps_alive { run.workspace.module_stamps.deinit(); }
}
fn resetGenerator(workspace: CompileWorkspace&,units: const blot_check_core::Module[:],journal: blot_reuse_artifact_emitter::Recorder&?) -> blot_error::Error {
    assert(blot_backend_result_publication::canMutate(workspace.publication_owner));
    let generator .= workspace.generator; generator.diagnostic_contexts.deinit(); generator.numeric_rows.deinit(); generator.planning.deinit(); generator.module.reset(); generator.static_data.deinit();
    let evaluator_error = generator.evaluator.reset(workspace.session_tables,units); if evaluator_error != blot_error::Error.none { return evaluator_error; }
    let representation_error = generator.representations.init(units); if representation_error != blot_error::Error.none { return representation_error; }
    generator.allocation_owner = workspace.allocation_owner; generator.inline_named = true; generator.speculative_locals = true; generator.speculated = false; generator.ragged_probe_limit = blot_backend_ragged_builder::probe_limit; generator.work_timing = blot_backend_backend_timing::Work {..}; generator.units = units; generator.spawn_units = [];
    generator.artifacts .= null; generator.retained .= null; generator.principal_state .= null; generator.persisted_principals .= null; generator.query_state .= null; generator.constant_state .= null; generator.refinement_owner .= null;
    generator.principal_stats = blot_reuse_principal_evidence_reuse::Stats {..}; generator.refinement_stats = blot_reuse_refinement_receipt::Stats {..}; generator.work = blot_reuse_artifact_fragment::Stats {..}; generator.persistent_outputs = false; generator.memory_profile = false;
    generator.public_owners = blot_support::none<blot_runtime_public_owners::Runtime>(); generator.task_context = blot_support::none<blot_runtime_task_context::Functions>(); generator.request_owner = blot_support::none<u32>(); generator.scoped_effects = false; generator.diagnostic = blot_support::none<Diagnostic>(); generator.staging_trace = blot_check_staging_origins::Trace {..}; generator.instance_depth = 0;
    generator.planning.runtime_operations.identity = blot_support::none<blot_backend_runtime_identity::View>(); generator.planning.runtime_operations.artifacts .= null; generator.planning.init(); return init(generator,journal);
}
fn prepare(run: CompileRun&,skip_constant_replay: bool) -> blot_error::Error {
    let workspace .= run.workspace; let generator .= workspace.generator; run.clock = blot_backend_backend_timing::init(run.options.io); run.timing = blot_backend_backend_timing::Stats {..};
    if run.options.identity.present {
        let names = run.options.identity.value; if names.owners.len != run.units.len { return blot_error::Error.invalid_function_reference; }
        for source,index in run.units { if source.unit != index + 1 || !names.owner(source.unit).present { return blot_error::Error.invalid_function_reference; } }
    }
    run.recording = run.options.artifact_replay || run.options.retain_artifacts || run.options.previous != null || run.options.query_previous != null;
    var query_previous .= run.options.query_previous; if query_previous == null { query_previous .= run.options.previous; }
    if query_previous == null && run.options.checkpoint != null && run.options.checkpoint.semantic != null { query_previous .= run.options.checkpoint.semantic.capture; }
    workspace.module_stamps.deinit(); workspace.module_stamps.current = run.units; workspace.module_stamps.previous .= null;
    if query_previous != null && query_previous.metadata.pools.present { workspace.module_stamps.previous .= query_previous.metadata.pools.value; }
    workspace.module_stamps.compare_contents = true; workspace.module_stamps.validate = run.options.validate_pins; workspace.module_stamps.computed = 0; workspace.module_stamps.reused = 0; workspace.module_stamps.comparisons = 0; workspace.module_stamps.copied = 0; workspace.module_stamps.hashed = 0; run.stamps_alive = true;
    if workspace.module_stamps.previous != null { run.stamps .= workspace.module_stamps; }
    workspace.journal.reset(); run.journal_alive = true;
    workspace.metadata.deinit(); workspace.metadata.allocation_owner = workspace.allocation_owner; workspace.metadata.active_job = 0; workspace.metadata.clock = 0; run.metadata_alive = true;
    if run.recording { workspace.journal.owner .= workspace.metadata.active_job; workspace.journal.clock .= workspace.metadata.clock; }
    var journal: blot_reuse_artifact_emitter::Recorder&? = null; if run.recording { journal .= workspace.journal; } run.generator_alive = true;
    let initialized = resetGenerator(workspace,run.units,journal); if initialized != blot_error::Error.none { return initialized; }
    generator.inline_named = run.options.inline_named; generator.memory_profile = run.options.policy.memory_profile; generator.speculative_locals = run.speculative_locals;
    let limits = run.options.constant_limits; if limits.steps.present { generator.evaluator.options.max_steps = limits.steps.value; } if limits.values.present { generator.evaluator.options.max_values = limits.values.value; } if limits.children.present { generator.evaluator.options.max_children = limits.children.value; } if limits.depth.present { generator.evaluator.options.max_depth = limits.depth.value; } if limits.calls.present { generator.evaluator.options.max_call_depth = limits.calls.value; }
    generator.ragged_probe_limit = run.options.ragged_probe_limit; if !run.options.ragged_builders { generator.ragged_probe_limit = 0; } generator.evaluator.ragged_probe_limit = generator.ragged_probe_limit;
    generator.work_timing.clock = blot_backend_backend_timing::init(run.options.profile_backend && run.options.io); generator.work_timing.cpu_clock = blot_backend_backend_timing::initKind(run.options.profile_backend && run.options.io && blot_native::thread_cpu_available(),true);
    if run.options.profile_backend { generator.evaluator.timing .= generator.work_timing; } else { generator.evaluator.timing .= null; }
    if run.recording { generator.artifacts .= workspace.metadata; } generator.refinement_owner .= workspace.metadata;
    generator.evaluator.diagnostic_context = blot_eval_core_eval::DiagnosticContext { identity: run.options.identity,entry: run.entry,prelude: run.options.diagnostic_prelude_unit,source_mode: run.options.diagnostic_source_mode , ..};
    generator.planning.startup_facts.enabled = run.options.observe_startup; generator.planning.runtime_operations.identity = run.options.identity; if run.recording { generator.planning.runtime_operations.artifacts .= workspace.journal; }
    let reused = prepareReuse(run,skip_constant_replay); if reused != blot_error::Error.none { return reused; }
    if run.options.evidence_noise {
        for index in 0..7 { let operation,error = generator.evaluator.storage.evidence.effects.internOperation(blot_check_types::NominalIdentity { 4294967295,(9000 + index) as u32 , ..},[blot_check_types::f32_type]); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return error; } return blot_error::Error.module_too_large; } }
    }
    run.timing.prepare_us = run.clock.lap(); return blot_error::Error.none;
}
fn prepareReuse(run: CompileRun&,skip_constant_replay: bool) -> blot_error::Error {
    let workspace .= run.workspace; let generator .= workspace.generator; var principal_previous .= run.options.principal_previous; if principal_previous == null { principal_previous .= run.options.previous; }
    var query_previous .= run.options.query_previous; if query_previous == null { query_previous .= run.options.previous; } if query_previous == null && run.options.checkpoint != null && run.options.checkpoint.semantic != null { query_previous .= run.options.checkpoint.semantic.capture; }
    if !run.options.policy.memory_profile && run.options.previous != null {
        let previous .= run.options.previous; if previous.emission.sealed && previous.metadata.pools.present {
            let error = blot_reuse_artifact_fragment::initInto(workspace.retained,previous,run.units,run.options.identity,run.options.cached_units,run.stamps,workspace.allocation_owner); if error != blot_error::Error.none { return error; }
            run.retained .= workspace.retained; generator.retained .= workspace.retained;
        }
    }
    if run.options.checkpoint != null { let error = blot_reuse_principal_archive::initInto(workspace.persisted_principals,run.options.checkpoint.principal,run.units,run.options.identity,workspace.allocation_owner); if error != blot_error::Error.none { return error; } run.persisted_principals .= workspace.persisted_principals; }
    if run.options.retain_artifacts || run.options.previous != null || run.options.checkpoint != null {
        if run.persisted_principals != null { generator.persisted_principals .= run.persisted_principals; }
        if principal_previous != null && principal_previous.emission.sealed && principal_previous.metadata.pools.present {
            var admission = blot_support::none<blot_reuse_principal_reuse_gate::Gate>();
            if run.retained != null && run.retained.importer.code_gate != null { admission = blot_reuse_shared_query_gate::share(workspace.allocation_owner,principal_previous.metadata.pools.value,run.units,run.retained.importer.code_gate.semantic); }
            let error = blot_reuse_principal_evidence_reuse::initInto(workspace.principal_state,principal_previous,run.units,run.options.identity,run.stamps,workspace.allocation_owner,admission); if error != blot_error::Error.none { return error; }
            run.principal_state .= workspace.principal_state; generator.principal_state .= workspace.principal_state;
        }
        generator.evaluator.generator .= generator; generator.evaluator.principal_provider_enabled = true; generator.evaluator.principal_graph_provider_enabled = true;
    }
    generator.evaluator.retain_specialization_receipts = run.recording; generator.evaluator.retain_constant_receipts = run.recording && run.options.constant_receipts;
    if query_previous != null && query_previous.metadata.pools.present {
        var admission = blot_support::none<blot_reuse_principal_reuse_gate::Gate>(); if run.principal_state != null { admission = blot_reuse_shared_query_gate::share(workspace.allocation_owner,query_previous.metadata.pools.value,run.units,run.principal_state.gate); }
        let shared = admission.present; let error = blot_eval_completed_specialization_query::initInto(workspace.query_state,query_previous,run.units,run.options.identity,run.stamps,workspace.allocation_owner,admission); if error != blot_error::Error.none { return error; }
        run.query_state .= workspace.query_state; if shared { workspace.query_state.stats.shared_gates = 1; workspace.query_state.stats.shared_gate_bytes = blot_reuse_shared_query_gate::validationBytes(workspace.query_state.gate); } else { workspace.query_state.stats.gate_fresh = 1; }
        workspace.query_state.io = run.options.io; workspace.query_state.semantic_workers = run.options.policy.semantic_workers; generator.query_state .= workspace.query_state; generator.evaluator.generator .= generator; generator.evaluator.specialization_provider_enabled = true;
    }
    if run.options.constant_receipts && !skip_constant_replay && run.query_state != null {
        let pools .= run.query_state.old.metadata.pools.value;
        if blot_reuse_constant_receipt::hasProductiveRecord(pools.constant_records,generator.evaluator.minimum_constant_steps) {
            let error = blot_reuse_constant_receipt_reuse::initInto(workspace.constant_state,pools,run.units,run.options.identity,run.stamps,workspace.allocation_owner,run.query_state.gate); if error != blot_error::Error.none { return error; }
            run.constant_state .= workspace.constant_state; generator.constant_state .= workspace.constant_state; generator.evaluator.generator .= generator; generator.evaluator.constant_provider_enabled = true;
        }
    }
    return blot_error::Error.none;
}
enum EmissionResult { complete,diagnostic { value: Result } }
fn emit(run: CompileRun&) -> EmissionResult,blot_error::Error {
    let workspace .= run.workspace; let generator .= workspace.generator; generator.evaluator.semantic_io = run.options.io; generator.evaluator.semantic_component_workers = 0;
    if run.options.policy.semantic_components || run.options.policy.semantic_workers > 1 { generator.evaluator.semantic_component_workers = run.options.policy.semantic_workers; }
    let generated = generate(generator,run.entry,run.options.unit_order);
    if generated != blot_error::Error.none {
        if generated != blot_error::Error.out_of_memory && generator.evaluator.constant_receipt_retry { return EmissionResult.complete,blot_error::Error.constant_receipt_retry; }
        if generated != blot_error::Error.declined { return EmissionResult.complete,generated; }
        var result = emptyResult(workspace); result.diagnostic = generator.diagnostic;
        if result.diagnostic.present {
            workspace.message.append(result.diagnostic.value.detail); result.diagnostic.value.detail = workspace.message;
            if result.diagnostic.value.implementation_trace.present {
                let explanation,error = explainImplementation(generator,result.diagnostic.value.implementation_trace.value); if error != blot_error::Error.none { result.deinit(); return EmissionResult.complete,error; } workspace.explanation = explanation; result.explanation .= workspace.explanation;
            } else if result.diagnostic.value.dispatch.present {
                let explanation,error = explainDispatch(generator,result.diagnostic.value.dispatch.value); if error != blot_error::Error.none { result.deinit(); return EmissionResult.complete,error; } workspace.explanation = explanation; result.explanation .= workspace.explanation;
            }
        }
        if run.options.observe_startup { let snapshot,error = generator.planning.startup_facts.capture(generator.module); if error != blot_error::Error.none { result.deinit(); return EmissionResult.complete,error; } workspace.startup_snapshot = snapshot; result.startup_observation .= workspace.startup_snapshot; }
        result.counters = generator.evaluator.counters; result.principal = principalStats(generator); result.code_instances = generator.planning.codeCount(generator.static_data.closures.len); result.callable_wrappers = generator.planning.wrapperCount(); result.emitted_functions = generator.module.functions.len; result.constant_steps = generator.evaluator.steps; result.constant_receipts = generator.evaluator.constant_stats; return EmissionResult.diagnostic { result , ..},blot_error::Error.none;
    }
    if generator.evaluator.constant_receipt_retry { return EmissionResult.complete,blot_error::Error.constant_receipt_retry; } run.timing.generate_us = run.clock.lap();
    if run.options.policy.memory_profile { let arena,error = generator.module.ensureArena(); if error != blot_error::Error.none { return EmissionResult.complete,error; } }
    let initialized = generator.planning.initializeRuntime(generator); if initialized != blot_error::Error.none { return EmissionResult.complete,initialized; }
    if run.recording { let recorded = workspace.journal.captureOperations(generator.planning.runtime_operations); if recorded != blot_error::Error.none { return EmissionResult.complete,recorded; } }
    let operations = generator.planning.runtime_operations.finish(generator.module); if operations != blot_error::Error.none { if operations == blot_error::Error.invalid_operation { return EmissionResult.complete,blot_error::Error.invalid_function_reference; } return EmissionResult.complete,operations; }
    let cycles = generator.module.prepareCycles(); if cycles != blot_error::Error.none { return EmissionResult.complete,cycles; } run.timing.initialize_us = run.clock.lap(); return EmissionResult.complete,blot_error::Error.none;
}
fn fallbackSpelling(fallback: blot_backend_wasm::OwnershipFallback) -> const u8[:] { match fallback { none=>"none",no_arena=>"no_arena",public_arena=>"public_arena",host_references=>"host_references",imports=>"imports",initializer=>"initializer",static_sequence_cache=>"static_sequence_cache",unproven_body=>"unproven_body" } }
fn ownershipRejection(workspace: CompileWorkspace&,location: Diagnostic,rejection: blot_backend_wasm::OwnershipFailure) -> Result {
    var result = emptyResult(workspace); let message .= workspace.message; message.append(blot_check_diagnostic_code::Code.ownership_unproved.message(""));
    if rejection.function.present { message.append(" (function "); format(message,rejection.function.value); message.append("; "); } else { message.append(" (module; "); }
    message.append(fallbackSpelling(rejection.fallback)); message.append(": ");
    match rejection.fallback {
        none=>message.append("ownership roots are unavailable"),no_arena=>message.append("the module has no allocation arena"),public_arena=>message.append("a public arena has no checked ownership roots"),host_references=>message.append("host references have no checked ownership roots"),imports=>message.append("imports have no checked ownership roots"),initializer=>message.append("the initializer has no checked ownership roots"),static_sequence_cache=>message.append("static sequence storage has no complete ownership proof"),unproven_body=>message.append("the function body has no complete allocation and exit proof"),
    }
    message.push(')'); var diagnostic = location; diagnostic.ownership = blot_support::some(rejection); diagnostic.detail = message; result.diagnostic = blot_support::some(diagnostic); return result;
}
struct CandidatePreparation { run: CompileRun&,source: const blot_backend_wasm::Module& }
fn prepareCandidate(context: CandidatePreparation&,model: blot_backend_activation_model::Model) -> blot_error::Error {
    let present,error = blot_backend_region_candidate::prepareInto(context.run.workspace.candidate,context.source,model); if error != blot_error::Error.none { return error; } if present { context.run.candidate .= context.run.workspace.candidate; } return blot_error::Error.none;
}
fn assemble(run: CompileRun&) -> Result,blot_error::Error {
    let workspace .= run.workspace; let generator .= workspace.generator; var source_module: const blot_backend_wasm::Module& .= generator.module;
    if run.options.policy.memory_profile {
        let error = blot_backend_source_origins::initInto(workspace.origins,source_module,run.units,run.options.identity,run.options.diagnostic_source_digests,generator.diagnostic_contexts.records); if error != blot_error::Error.none { return emptyResult(workspace),error; }
        run.origins .= workspace.origins; source_module .= workspace.origins.code.module;
    }
    if blot_backend_cohort_candidate::possible(source_module) {
        var context = CandidatePreparation { run,source_module , ..}; let error = blot_backend_activation_model::withBorrowed(generator,run.options.identity,context,prepareCandidate); if error != blot_error::Error.none { return emptyResult(workspace),error; }
    }
    var assembled_module: const blot_backend_wasm::Module& .= source_module; if run.candidate != null { assembled_module .= run.candidate.view.module; }
    if run.options.policy.codegen_tier == blot_compilation_tier::Tier.optimized {
        let present,error = blot_backend_simd_abi::prepareInto(workspace.vectors,assembled_module); if error != blot_error::Error.none { return emptyResult(workspace),error; } if present { run.vectors .= workspace.vectors; assembled_module .= workspace.vectors.module; }
    }
    if run.options.retain_artifacts { let error = blot_backend_optimized_bodies::initInto(workspace.optimized); if error != blot_error::Error.none { return emptyResult(workspace),error; } run.optimized .= workspace.optimized; }
    var optimized_previous: const blot_backend_optimized_bodies::Capture&? = null; if run.options.previous != null && run.options.previous.optimized != null { optimized_previous .= run.options.previous.optimized; }
    if optimized_previous == null && run.options.checkpoint != null && run.options.checkpoint.optimizer != null { optimized_previous .= run.options.checkpoint.optimizer; }
    var runtime_optimization = blot_backend_optimized_bodies::Stats {..}; var rejection = blot_backend_wasm::OwnershipFailure {..}; var collector_rejection = blot_backend_collector_contract::Certificate {..};
    var memory_profile = blot_support::none<const blot_backend_source_origins::Site[:]>(); if run.origins != null { memory_profile = blot_support::some(run.origins.sites); }
    workspace.bytes.clear(); let emitted = assembled_module.assembleCheckedWithOptions(blot_backend_wasm::AssembleOptions { compiler_identity: run.options.compiler_identity,source_digests: run.options.diagnostic_source_digests,source_names: run.options.identity,require_collector_free: run.options.policy.require_collector_free,collector_rejection: collector_rejection,memory_profile: memory_profile,rejection: rejection,io: run.options.io,workers: run.options.policy.codegen_workers,profile: run.options.profile_backend,tier: run.options.policy.codegen_tier,share_machine_code: run.options.policy.share_machine_code,previous: optimized_previous,current: run.optimized,stats: runtime_optimization },workspace.bytes);
    if emitted != blot_error::Error.none {
        if emitted == blot_error::Error.collector_free_unproven {
            var result = emptyResult(workspace); workspace.message.append("Collector-free proof declined: "); workspace.message.append(blot_backend_collector_contract::reasonName(collector_rejection.reason)); workspace.message.append("; function ");
            if collector_rejection.function.present { format(workspace.message,collector_rejection.function.value); } else { workspace.message.append("null"); } workspace.message.append(", instruction ");
            if collector_rejection.instruction.present { format(workspace.message,collector_rejection.instruction.value); } else { workspace.message.append("null"); }
            workspace.message.append(". Ordinary builds retain collection. The current certificate requires scalar host inputs, direct calls and heap allocations with no owning fields.");
            var location = Diagnostic { unit: run.entry,span: blot_check_core::Span { 0,0 , ..},code: blot_check_diagnostic_code::Code.collector_free_unproved,detail: workspace.message , ..};
            if collector_rejection.function.present { for site in assembled_module.semantic_sites { if site.function != collector_rejection.function.value || site.unit == 0 || site.unit > run.units.len { continue; } location.unit = site.unit; location.span = run.units[site.unit - 1].span(site.root); break; } }
            result.diagnostic = blot_support::some(location); return result,blot_error::Error.none;
        }
        if emitted == blot_error::Error.incomplete_ownership {
            var location = Diagnostic { unit: run.entry,span: blot_check_core::Span { 0,0 , ..},code: blot_check_diagnostic_code::Code.ownership_unproved , ..};
            if rejection.function.present {
                var found = false; let failed = rejection.function.value;
                generator.planning.instances.each() { key,function_id => { if !found && function_id == failed { location.unit = key.target.unit; location.span = generator.unit(key.target.unit).binding(key.target.binding).span; found = true; } } }
                if location.span.end == 0 { found = false; generator.planning.template_instances.each() { key,function_id => { if !found && function_id == failed { location.unit = key.unit; location.span = generator.unit(key.unit).span(key.node); found = true; } } } }
                if location.span.end == 0 { found = false; generator.planning.closures.each() { key,function_id => { if !found && function_id == failed { location.unit = key.unit; location.span = generator.unit(key.unit).span(generator.unit(key.unit).closures[key.catalog].body); found = true; } } } }
            }
            if location.span.end == 0 { location.unit = run.entry; for body in generator.unit(run.entry).bodies[1..] { if body.exported { location.span = generator.unit(run.entry).binding(body.binding).span; break; } } }
            var result = ownershipRejection(workspace,location,rejection); result.counters = generator.evaluator.counters; result.constant_steps = generator.evaluator.steps; return result,blot_error::Error.none;
        }
        if emitted == blot_error::Error.out_of_memory || emitted == blot_error::Error.module_too_large || emitted == blot_error::Error.invalid_global_reference { return emptyResult(workspace),emitted; } return emptyResult(workspace),blot_error::Error.invalid_function_reference;
    }
    workspace.message.clear(); var result,result_error = ownedResult(workspace.bytes[..],blot_support::none<blot_backend_allocation_emission::Snapshot>()); if result_error != blot_error::Error.none { return result,result_error; } result.detached = false; result.runtime_optimization = runtime_optimization; result.code_instances = generator.planning.codeCount(generator.static_data.closures.items.len); result.callable_wrappers = generator.planning.wrapperCount(); result.emitted_functions = assembled_module.functions.len; result.constant_steps = generator.evaluator.steps; result.constant_receipts = generator.evaluator.constant_stats; return result,blot_error::Error.none;
}
fn addFields<T>(destination: T&,source: T) { const for <N,A> in fields<T> { destination.A += source.A; } }
fn observe(run: CompileRun&,result: Result&) -> blot_error::Error {
    let workspace .= run.workspace; let generator .= workspace.generator;
    if run.retained != null && run.retained.importer.code_gate != null { result.source_validation.observe(run.retained.importer.code_gate.semantic); }
    if run.principal_state != null { result.source_validation.observe(run.principal_state.gate); } if run.query_state != null { result.source_validation.observe(run.query_state.gate); }
    result.emitted_functions -= result.runtime_optimization.shared; run.timing.assemble_us = run.clock.lap(); run.timing.profiled = run.options.profile_backend; if run.options.profile_backend { run.timing.work = generator.work_timing.snapshot(); }
    result.optimization = generator.planning.facts.stats; result.optimization.region_requests = generator.evaluator.regions.region_arena_pool.stats.requested; result.optimization.region_reused = generator.evaluator.regions.region_arena_pool.stats.reused; result.optimization.region_retained_bytes = generator.evaluator.regions.region_arena_pool.stats.retained_bytes; result.optimization.region_arena = generator.evaluator.regions.region_arena_pool.stats;
    result.optimization.evidence_import_requests = generator.evaluator.evidence_import_requests; result.optimization.evidence_import_reused = generator.evaluator.evidence_import_reused; result.optimization.closed_source_imports = generator.evaluator.closed_source_imports; result.optimization.closed_source_reused = generator.evaluator.closed_source_reused; result.optimization.split_attempts = generator.evaluator.split_attempts; result.optimization.split_accepted = generator.evaluator.split_accepted; result.optimization.split_declined = generator.evaluator.split_declined; result.counters = generator.evaluator.counters;
    if run.options.explain_allocations { let snapshot,error = blot_backend_allocation_emission::capture(run.units,run.options.identity,generator.module,run.entry,run.options.diagnostic_prelude_unit); if error != blot_error::Error.none { return error; } workspace.allocation_snapshot.deinit(); workspace.allocation_snapshot = snapshot; result.allocation_emission .= workspace.allocation_snapshot; }
    if run.options.observe_startup { let snapshot,error = generator.planning.startup_facts.capture(generator.module); if error != blot_error::Error.none { return error; } workspace.startup_snapshot = snapshot; result.startup_observation .= workspace.startup_snapshot; }
    result.principal = principalStats(generator); if run.query_state != null { result.completed_queries = run.query_state.stats; } result.completed_queries.recorded = generator.evaluator.retained.specialization_receipts.len;
    for record in generator.evaluator.retained.specialization_receipts.items { if record.complete { result.completed_queries.complete_records++; if record.member.present { result.completed_queries.member_recorded++; } } }
    result.reuse = generator.work; if run.principal_state != null && run.principal_state.graphs.present { result.reuse.graph_imports.principals = run.principal_state.graphs.value.census; }
    if run.query_state != null && run.query_state.semantic != null { result.reuse.graph_imports.queries = run.query_state.semantic.census; } if run.retained != null { result.reuse.graph_imports.fragments = run.retained.importer.census; }
    result.refinements = generator.refinement_stats; result.query_tables.canonical = generator.evaluator.specializations.canonical_specializations.table.storage(); if run.persisted_principals != null { result.query_tables.portable_principal = run.persisted_principals.storage(); }
    let principal_storage = generator.evaluator.principalQueryStorage(); result.query_tables.source_description = principal_storage.source_description; result.query_tables.open_residual = principal_storage.open_residual;
    if run.retained != null {
        let state .= run.retained;
        if state.importer.static_scratch != null { result.reuse.static_graph_scratch = state.importer.static_scratch.stats; result.reuse.static_graph_scratch_bytes = state.importer.static_scratch.payloadBytes(); }
        if state.match_scratch != null { addFields(result.reuse.static_graph_scratch,state.match_scratch.stats); result.reuse.static_graph_scratch_bytes += state.match_scratch.payloadBytes(); }
        result.reuse.reused_named = state.stats.reused_named; result.reuse.reused_closures = state.stats.reused_closures; result.reuse.candidates = state.stats.candidates; result.reuse.lookup_positions = state.stats.lookup_positions; result.reuse.request_checks = state.stats.request_checks; result.reuse.request_hits = state.stats.request_hits; result.reuse.declined = state.stats.declined; result.reuse.reused_scalar_constants = state.stats.reused_scalar_constants; result.reuse.reused_aggregate_constants = state.stats.reused_aggregate_constants;
    }
    return blot_error::Error.none;
}
struct ArtifactCounts { globals: i64,imports: i64,signatures: i64,data_bytes: i64 }
fn recordArtifact(run: CompileRun&,result: Result&) -> blot_error::Error {
    if !run.recording { return blot_error::Error.none; } let workspace .= run.workspace; let generator .= workspace.generator; let metadata .= workspace.metadata; let journal .= workspace.journal;
    let graphs = metadata.principal_graphs.capture(generator.evaluator); if graphs != blot_error::Error.none { return graphs; }
    for record in generator.evaluator.retained.specialization_receipts.items {
        var input = record.input; if record.member.present { input = record.member.value.function; }
        let cloned,clone_error = record.clone(); if clone_error != blot_error::Error.none { return clone_error; }
        let remembered,error = blot_eval_selected_query::remember(metadata.specialization_queries,generator.evaluator.closureInfo(input),cloned); if error != blot_error::Error.none { return error; }
    }
    for record in metadata.specialization_queries.records { if record.dependencies.member.present { result.completed_queries.member_payload_bytes += blot_support_host_layout::selected_query_record + blot_reuse_specialization_receipt::ownedBytes(record.dependencies); } }
    if run.query_state != null && run.options.policy.semantic_workers > 1 { for record in run.query_state.independent_calls.items { let cloned,error = record.clone(); if error != blot_error::Error.none { return error; } metadata.independent_calls.push(cloned); } }
    result.query_tables.selected = metadata.specialization_queries.storage(); result.query_tables.principal = metadata.principal_queries.storage();
    var stamps: blot_reuse_code_artifacts::ModuleStamps&? = null; if run.stamps != null || run.options.validate_pins { stamps .= workspace.module_stamps; }
    let captured = metadata.capturePoolsWithStamps(generator,run.options.identity,stamps); if captured != blot_error::Error.none { return captured; } result.counters = generator.evaluator.counters; assert(metadata.pools.present);
    if run.principal_state != null {
        let certificate,error = run.principal_state.gate.freezeValidation(metadata.pools.value.modules); if error != blot_error::Error.none { return error; } metadata.pools.value.dependency_certificate = certificate;
    } else if run.retained != null && run.retained.importer.code_gate != null {
        let certificate,error = run.retained.importer.code_gate.semantic.freezeValidation(metadata.pools.value.modules); if error != blot_error::Error.none { return error; } metadata.pools.value.dependency_certificate = certificate;
    }
    if metadata.pools.value.dependency_certificate.present { let certificate = metadata.pools.value.dependency_certificate.value; result.source_validation.retained = certificate.storage(); result.source_validation.reused_images = certificate.reused_images; }
    journal.seal(); let functions = journal.freezeFunctions(metadata.function_jobs.items); if functions != blot_error::Error.none { return functions; }
    for function_id in generator.static_data.closures.items { journal.functions[function_id].role = blot_reuse_artifact_emitter::FunctionRole.static_closure; }
    for slot in metadata.pools.value.runtime_globals { journal.functions[slot.initializer].role = blot_reuse_artifact_emitter::FunctionRole.runtime_initializer; }
    generator.planning.task_movers.each() { layout,function_id => { journal.functions[function_id].role = blot_reuse_artifact_emitter::FunctionRole.task_mover; } }
    for function in journal.functions { if function.role == blot_reuse_artifact_emitter::FunctionRole.unknown { return blot_error::Error.invalid_function_reference; } }
    if journal.functions.len != generator.module.functions.len { return blot_error::Error.invalid_function_reference; }
    for job in metadata.jobs.items { if job.state == blot_reuse_code_artifacts::State.failed || job.state == blot_reuse_code_artifacts::State.pending || job.state == blot_reuse_code_artifacts::State.reserved { return blot_error::Error.invalid_function_reference; } }
    for function in metadata.pools.value.functions {
        if function.function >= journal.functions.len { return blot_error::Error.invalid_function_reference; } let owner = journal.functions[function.function].owner; if owner == 0 || owner > metadata.jobs.len { return blot_error::Error.invalid_function_reference; } let job = metadata.jobs.items[owner - 1];
        if job.state != blot_reuse_code_artifacts::State.complete || !job.function.present || job.function.value != function.function || job.request != function.request || job.result_template != function.result_template { return blot_error::Error.invalid_function_reference; }
    }
    let counts = ArtifactCounts { generator.module.globals.len,generator.module.imports.len,generator.module.signatures.len,generator.module.data.len , ..};
    if run.options.artifact_replay { let replayed = replayArtifact(run,result); if replayed != blot_error::Error.none { return replayed; } }
    result.artifacts = blot_support::some(ArtifactSummary { demands: metadata.jobs.len,jobs: metadata.pools.value.functions.len,functions: journal.functions.len,helpers: journal.functions.len - metadata.pools.value.functions.len,emission_events: journal.records.len,metadata_events: metadata.events.len,operation_symbols: journal.operations.len,templates: metadata.pools.value.captures.len,pinned_modules: metadata.pools.value.modules.len , ..});
    if run.options.artifact_dump { return dumpArtifact(run,result,counts); } return blot_error::Error.none;
}
fn replayArtifact(run: CompileRun&,result: Result&) -> blot_error::Error {
    let workspace .= run.workspace; let generator .= workspace.generator; workspace.replay_contexts.clear(); if run.options.policy.memory_profile { workspace.replay_contexts.append(generator.diagnostic_contexts.records); }
    recursive fn cleanup_continuation_12() -> blot_error::Error {

    generator.deinit(); run.generator_alive = false; workspace.replay_module.reset();
    let materialized = workspace.journal.materialize(workspace.replay_module); if materialized != blot_error::Error.none { if materialized == blot_error::Error.out_of_memory || materialized == blot_error::Error.module_too_large { return materialized; } return blot_error::Error.invalid_function_reference; }
    recursive fn cleanup_continuation_11() -> blot_error::Error {

    var origins_alive = false;
    recursive fn cleanup_continuation_10() -> blot_error::Error {

    var source: const blot_backend_wasm::Module& .= workspace.replay_module;
    if run.options.policy.memory_profile {
        let error = blot_backend_source_origins::initInto(workspace.replay_origins,source,run.units,run.options.identity,run.options.diagnostic_source_digests,workspace.replay_contexts); if error != blot_error::Error.none { return error; }
        origins_alive = true; source .= workspace.replay_origins.code.module;
    }
    assert(workspace.metadata.pools.present); let candidate,candidate_error = blot_backend_region_candidate::prepareInto(workspace.replay_candidate,source,blot_backend_activation_model::fromPools(run.units,workspace.metadata.pools.value)); if candidate_error != blot_error::Error.none { return candidate_error; }

    recursive fn cleanup_continuation_9() -> blot_error::Error {

    var module: const blot_backend_wasm::Module& .= source; if candidate { module .= workspace.replay_candidate.view.module; } var vectors = false;
    if run.options.policy.codegen_tier == blot_compilation_tier::Tier.optimized { let present,error = blot_backend_simd_abi::prepareInto(workspace.replay_vectors,module); if error != blot_error::Error.none { return error; } vectors = present; }

    recursive fn cleanup_continuation_8() -> blot_error::Error {
 if vectors { module .= workspace.replay_vectors.module; }
    var memory_profile = blot_support::none<const blot_backend_source_origins::Site[:]>(); if origins_alive { memory_profile = blot_support::some(workspace.replay_origins.sites); }
    workspace.replay_bytes.clear();
    recursive fn cleanup_continuation_7() -> blot_error::Error {

    let assembled = module.assembleCheckedWithOptions(blot_backend_wasm::AssembleOptions { compiler_identity: run.options.compiler_identity,source_digests: run.options.diagnostic_source_digests,source_names: run.options.identity,require_collector_free: run.options.policy.require_collector_free,memory_profile: memory_profile,tier: run.options.policy.codegen_tier,share_machine_code: run.options.policy.share_machine_code },workspace.replay_bytes);
    if assembled != blot_error::Error.none { if assembled == blot_error::Error.out_of_memory || assembled == blot_error::Error.module_too_large || assembled == blot_error::Error.invalid_global_reference { return assembled; } return blot_error::Error.invalid_function_reference; }
    if !blot_backend_wasm::equal(result.bytes,workspace.replay_bytes) { return blot_error::Error.invalid_function_reference; }
    result.bytes.clear(); return result.bytes.append(workspace.replay_bytes[..]);

    }
    let cleanup_result_7_0 = cleanup_continuation_7();
     workspace.replay_bytes.clear();
    return cleanup_result_7_0;

    }
    let cleanup_result_8_0 = cleanup_continuation_8();
     if vectors { workspace.replay_vectors.deinit(); }
    return cleanup_result_8_0;

    }
    let cleanup_result_9_0 = cleanup_continuation_9();
     if candidate { workspace.replay_candidate.deinit(); }
    return cleanup_result_9_0;

    }
    let cleanup_result_10_0 = cleanup_continuation_10();
     if origins_alive { workspace.replay_origins.deinit(); }
    return cleanup_result_10_0;

    }
    let cleanup_result_11_0 = cleanup_continuation_11();
     workspace.replay_module.deinit();
    return cleanup_result_11_0;

    }
    let cleanup_result_12_0 = cleanup_continuation_12();
     workspace.replay_contexts.clear();
    return cleanup_result_12_0;
}
fn publish(run: CompileRun&,result: Result&) -> blot_error::Error {
    let workspace .= run.workspace;
    if run.options.retain_artifacts {
        workspace.capture = blot_reuse_artifact_capture::init(workspace.metadata,workspace.journal,workspace.capture.executable_queries,run.options.cached_units); workspace.capture.optimized .= run.optimized;
        result.capture .= workspace.capture; run.optimized .= null; run.metadata_alive = false; run.journal_alive = false;
        let sealed = workspace.capture.sealExecutableQueries(); if sealed != blot_error::Error.none { return sealed; } result.query_tables.executable_fragment = workspace.capture.executable_queries.storage();
        if workspace.capture.optimized != null { result.query_tables.executable_optimizer = workspace.capture.optimized.queries.storage(); }
    }
    result.module_stamps = ModuleStamps { workspace.module_stamps.computed,workspace.module_stamps.reused,workspace.module_stamps.comparisons,workspace.module_stamps.copied,workspace.module_stamps.hashed , ..};
    run.timing.capture_us = run.clock.lap(); result.timing = run.timing; return blot_error::Error.none;
}
fn compileAttempt(workspace: CompileWorkspace&,units: const blot_check_core::Module[:],entry: u32,options: CompileOptions,skip_constant_replay: bool,speculative_locals: bool) -> Result,blot_error::Error {
    var run = CompileRun { workspace: workspace,units: units,entry: entry,options: options,speculative_locals: speculative_locals , ..};
    recursive fn cleanup_continuation_6() -> Result,blot_error::Error {

    let prepared = prepare(run,skip_constant_replay); if prepared != blot_error::Error.none { return emptyResult(workspace),prepared; }
    let emitted,error = emit(run); if error != blot_error::Error.none { return emptyResult(workspace),error; }
    match emitted {
        diagnostic failure=>{ var result = failure.value; if !workspace.generator.speculated { return result,blot_error::Error.none; } result.deinit(); return emptyResult(workspace),blot_error::Error.speculative_local_retry; },complete=>{},
    }
    let speculated = workspace.generator.speculated; let assembled,assembly_error = assemble(run); if assembly_error != blot_error::Error.none { return assembled,assembly_error; } var result = assembled;
    if result.diagnostic.present { if !speculated { return result,blot_error::Error.none; } result.deinit(); return emptyResult(workspace),blot_error::Error.speculative_local_retry; }
    let observed = observe(run,result); if observed != blot_error::Error.none { result.deinit(); return emptyResult(workspace),observed; }
    let recorded = recordArtifact(run,result); if recorded != blot_error::Error.none { result.deinit(); return emptyResult(workspace),recorded; }
    let published = publish(run,result); if published != blot_error::Error.none { result.deinit(); return emptyResult(workspace),published; } return result,blot_error::Error.none;

    }
    let cleanup_result_6_0,cleanup_result_6_1 = cleanup_continuation_6();
     run.deinit();
    return cleanup_result_6_0,cleanup_result_6_1;
}
fn compileLocals(workspace: CompileWorkspace&,units: const blot_check_core::Module[:],entry: u32,options: CompileOptions,speculative: bool) -> Result,blot_error::Error {
    let first,error = compileAttempt(workspace,units,entry,options,false,speculative); if error != blot_error::Error.constant_receipt_retry { return first,error; } assert(options.constant_receipts);
    let retried,retry_error = compileAttempt(workspace,units,entry,options,true,speculative); assert(retry_error != blot_error::Error.constant_receipt_retry); if retry_error != blot_error::Error.none { return retried,retry_error; } var result = retried; result.constant_receipts.retries = 1; return result,blot_error::Error.none;
}
fn compileWithOptions(workspace: CompileWorkspace&,source_units: const blot_check_core::Module[:],entry: u32,options: CompileOptions) -> Result,blot_error::Error {
    let units,input_error = blot_backend_result_publication::inputUnits(workspace.publication_owner,source_units); if input_error != blot_error::Error.none { return Result {..},input_error; }
    let publication_epoch,publication_error = blot_backend_result_publication::beginCompile(workspace.publication_owner); if publication_error != blot_error::Error.none { return Result {..},publication_error; } workspace.compiled_units = units;
    let trace_space = blot_phase_profile::enterSpace(blot_phase_profile::Space.core);
    recursive fn cleanup_continuation_5() -> Result,blot_error::Error {

    let required,error = blot_backend_scoped_backend::required(units,entry); if error != blot_error::Error.none { return emptyResult(workspace),error; }
    if required {
        var storage = options.policy.storage.config(); if options.storage.present { storage = options.storage.value; }
        return blot_backend_scoped_backend::compileWithOptions(workspace,units,entry,blot_backend_scoped_backend::CompileOptions { identity: options.identity,storage: storage,tier: options.policy.codegen_tier,workers: options.policy.codegen_workers,share_machine_code: options.policy.share_machine_code,io: options.io,profile: options.profile_backend,completed_core_validation: options.completed_core_validation,source_completion: options.source_completion , ..});
    }
    let first,first_error = compileLocals(workspace,units,entry,options,true); if first_error != blot_error::Error.speculative_local_retry { return first,first_error; } return compileLocals(workspace,units,entry,options,false);

    }
    var cleanup_result_5_0,cleanup_result_5_1 = cleanup_continuation_5();
     trace_space.restore();
    if cleanup_result_5_1 != blot_error::Error.none { cleanup_result_5_0.deinit(); blot_backend_result_publication::abortCompile(workspace.publication_owner,publication_epoch); return Result {..},cleanup_result_5_1; }
    blot_backend_result_publication::finishCompile(workspace.publication_owner,publication_epoch); cleanup_result_5_0.active = true; cleanup_result_5_0.publication_owner = workspace.publication_owner; cleanup_result_5_0.publication_epoch = publication_epoch; cleanup_result_5_0.publication_units = units; cleanup_result_5_0.message_source = workspace.message[..];
    return cleanup_result_5_0,cleanup_result_5_1;
}
fn compile(workspace: CompileWorkspace&,units: const blot_check_core::Module[:],entry: u32) -> Result,blot_error::Error { return compileWithOptions(workspace,units,entry,CompileOptions { artifact_replay: default_artifact_replay,artifact_dump: default_artifact_replay , ..}); }
fn compileWithIdentity(workspace: CompileWorkspace&,units: const blot_check_core::Module[:],entry: u32,names: blot_backend_runtime_identity::View) -> Result,blot_error::Error { return compileWithOptions(workspace,units,entry,CompileOptions { identity: blot_support::some(names),artifact_replay: default_artifact_replay,artifact_dump: default_artifact_replay , ..}); }
fn compileWithEvidenceNoise(workspace: CompileWorkspace&,units: const blot_check_core::Module[:],entry: u32,noise: bool) -> Result,blot_error::Error { return compileWithOptions(workspace,units,entry,CompileOptions { evidence_noise: noise , ..}); }
fn taskRuntime(generator: Generator&) -> blot_runtime_task_context::Functions,blot_error::Error {
    if generator.task_context.present { return generator.task_context.value,blot_error::Error.none; } if generator.artifacts != null { generator.artifacts.requireFreshCode(); }
    let ensured = blot_runtime_task_abi::ensure(generator.module); if ensured != blot_error::Error.none { return default<blot_runtime_task_context::Functions>(),ensured; }
    let references,reference_error = generator.module.ensureHostReferences(); if reference_error != blot_error::Error.none { return default<blot_runtime_task_context::Functions>(),reference_error; }
    let functions,error = blot_runtime_task_context::emit(generator.module,generator.request_owner); if error != blot_error::Error.none { return functions,error; }
    const for <N,A> in fields<blot_runtime_task_context::Functions> {
        var name: u8[>..<] = []; name.append("blot:task_context/"); name.append(N); let exported = generator.module.exportTaskAdapter(functions.A,name,true); if exported != blot_error::Error.none { return functions,exported; }
    }
    assert(generator.module.arena.present); let arena = generator.module.arena.value; let names = ["retain","release"]; let targets: u32[2] = [arena.retain,arena.release];
    for target,index in targets {
        let wrapper,wrapper_error = generator.module.addTypedFunction([blot_backend_runtime_ir::VT_i32],blot_backend_runtime_ir::VT_none,blot_backend_runtime_ir::ROLE_scalar); if wrapper_error != blot_error::Error.none { return functions,wrapper_error; }
        let emitted = generator.module.emitSlice(wrapper,[I(blot_backend_runtime_ir::OP_local_get),I(blot_backend_runtime_ir::OP_call,target)]); if emitted != blot_error::Error.none { return functions,emitted; }
        var name: u8[>..<] = []; name.append("blot:task_"); name.append(names[index]); let exported = generator.module.exportTaskAdapter(wrapper,name,true); if exported != blot_error::Error.none { return functions,exported; }
    }
    generator.task_context = blot_support::some(functions); return functions,blot_error::Error.none;
}
struct TaskMoverEmission { ty: u32 }
fn emitTaskMoverOwner(context: TaskMoverEmission&,emitter: blot_backend_backend_emission::Owner&) -> blot_error::Error { emitter.taskMoveBody(context.ty,0,0) }
fn taskMover(generator: Generator&,ty: u32) -> u32,blot_error::Error {
    block { let known = generator.planning.task_movers.get(ty); if known { return known,blot_error::Error.none; } }
    let function_id,error = generator.module.addTypedFunction([blot_backend_runtime_ir::VT_i32],blot_backend_runtime_ir::VT_none,blot_backend_runtime_ir::ROLE_scalar); if error != blot_error::Error.none { return 0,error; }
    let described = setParameterRoles(generator,function_id,blot_backend_runtime_ir::packParameterRoles([blot_backend_runtime_ir::ROLE_reference]),blot_support::none<u16>()); if described != blot_error::Error.none { return 0,described; } generator.planning.task_movers.insert(ty,function_id);
    var context = TaskMoverEmission { ty , ..}; let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { generator: generator,unit_id: 1,function_id: function_id,mappings: [] , ..},context,emitTaskMoverOwner); if emitted != blot_error::Error.none { return 0,emitted; } return function_id,blot_error::Error.none;
}
struct ResourceAdapterEmission { machine: blot_backend_runtime_ir::ValueType,role: blot_backend_runtime_ir::Role }
fn emitResourceAdapterOwner(context: ResourceAdapterEmission&,emitter: blot_backend_backend_emission::Owner&) -> blot_error::Error { emitter.boxOwnerStorage(context.machine,context.role) }
fn resourceAdapter(generator: Generator&,payload: u32) -> u32,blot_error::Error {
    let role = layoutRole(generator,payload); let machine = generator.representations.store.machine(payload); var selected: u32 = 0; if machine == blot_backend_runtime_ir::VT_f32 { selected = 1; } if role == blot_backend_runtime_ir::ROLE_reference { selected = 2; }
    if role != blot_backend_runtime_ir::ROLE_scalar && role != blot_backend_runtime_ir::ROLE_reference { return 0,blot_error::Error.declined; } let present = generator.module.resourceCount(); if present > selected { return selected,blot_error::Error.none; }
    let arena,error = generator.module.ensureArena(); if error != blot_error::Error.none { return 0,error; } var count: i64 = 2; if selected == 2 { count = 3; }
    for index in present..count {
        var payload_role = blot_backend_runtime_ir::ROLE_scalar; if index == 2 { payload_role = blot_backend_runtime_ir::ROLE_reference; } var argument_machine = blot_backend_runtime_ir::VT_i32; if index == 1 { argument_machine = blot_backend_runtime_ir::VT_f32; }
        let parameters: blot_backend_runtime_ir::ValueType[3] = [blot_backend_runtime_ir::VT_i32,blot_backend_runtime_ir::VT_i32,blot_backend_runtime_ir::VT_i32]; let roles: blot_backend_runtime_ir::Role[3] = [payload_role,blot_backend_runtime_ir::ROLE_reference,blot_backend_runtime_ir::ROLE_reference];
        let cleanup,cleanup_error = generator.module.addTypedFunction(parameters,blot_backend_runtime_ir::VT_none,blot_backend_runtime_ir::ROLE_scalar); if cleanup_error != blot_error::Error.none { return 0,cleanup_error; }
        let described = setParameterRoles(generator,cleanup,blot_backend_runtime_ir::packParameterRoles(roles),blot_support::some(2 as u16)); if described != blot_error::Error.none { return 0,described; }
        let loaded = generator.module.emitSlice(cleanup,[I(blot_backend_runtime_ir::OP_local_get,1),I(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_environment),I(blot_backend_runtime_ir::OP_local_get)]); if loaded != blot_error::Error.none { return 0,loaded; }
        if index == 1 { let reinterpreted = generator.module.emit(cleanup,I(blot_backend_runtime_ir::OP_f32_reinterpret_i32)); if reinterpreted != blot_error::Error.none { return 0,reinterpreted; } }
        var context = ResourceAdapterEmission { argument_machine,payload_role , ..}; let boxed = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { generator: generator,unit_id: 1,function_id: cleanup,mappings: [] , ..},context,emitResourceAdapterOwner); if boxed != blot_error::Error.none { return 0,boxed; }
        let signature,signature_error = generator.module.internType(parameters,blot_backend_runtime_ir::VT_i32); if signature_error != blot_error::Error.none { return 0,signature_error; }
        let called = generator.module.emitSlice(cleanup,[I(blot_backend_runtime_ir::OP_local_get,2),I(blot_backend_runtime_ir::OP_local_get,1),I(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_function),blot_backend_runtime_ir::callResult(blot_backend_runtime_ir::ROLE_scalar),I(blot_backend_runtime_ir::OP_call_indirect,signature),I(blot_backend_runtime_ir::OP_drop)]); if called != blot_error::Error.none { return 0,called; }
        let drop,drop_error = generator.module.addTypedFunction(parameters,blot_backend_runtime_ir::VT_none,blot_backend_runtime_ir::ROLE_scalar); if drop_error != blot_error::Error.none { return 0,drop_error; }
        let drop_roles = setParameterRoles(generator,drop,blot_backend_runtime_ir::packParameterRoles(roles),blot_support::some(2 as u16)); if drop_roles != blot_error::Error.none { return 0,drop_roles; }
        var first: i64 = 1; if index == 2 { first = 0; } for local in first..3 { let released = generator.module.emitSlice(drop,[I(blot_backend_runtime_ir::OP_local_get,local as u32),I(blot_backend_runtime_ir::OP_call,arena.release)]); if released != blot_error::Error.none { return 0,released; } }
        var cleanup_name: u8[>..<] = []; cleanup_name.append("blot:resource_cleanup/"); format(cleanup_name,index); var drop_name: u8[>..<] = []; drop_name.append("blot:resource_drop/"); format(drop_name,index);
        let cleanup_exported = generator.module.exportResourceAdapter(cleanup,cleanup_name); if cleanup_exported != blot_error::Error.none { return 0,cleanup_exported; } let drop_exported = generator.module.exportResourceAdapter(drop,drop_name); if drop_exported != blot_error::Error.none { return 0,drop_exported; }
    }
    return selected,blot_error::Error.none;
}
fn explainDispatch(generator: Generator&,record: blot_eval_core_eval::DispatchRecord) -> blot_reuse_dispatch_explanation::Explanation,blot_error::Error {
    var builder = blot_reuse_dispatch_explanation::Builder {..};
    recursive fn cleanup_continuation_4() -> blot_reuse_dispatch_explanation::Explanation,blot_error::Error {

    for candidate in record.items() {
        var text: u8[>..<] = []; var display = EntryDisplay { generator,text , ..}; var spelled = false;
        if candidate.operand != 0 { let success,error = ty(display,candidate.operand,16); if error != blot_error::Error.none { return default<blot_reuse_dispatch_explanation::Explanation>(),error; } spelled = success; }
        var operand = blot_support::none<const u8[:]>(); if spelled { let owned,error = builder.own(text); if error != blot_error::Error.none { return default<blot_reuse_dispatch_explanation::Explanation>(),error; } operand = blot_support::some(owned); }
        builder.add(candidate.side,operand,candidate.outcome);
    }
    var named = blot_support::none<const u8[:]>(); if record.member != 0 && generator.evaluator.diagnostic_context.identity.present { named = generator.evaluator.diagnostic_context.identity.value.symbol(record.member); }
    var member = blot_reuse_dispatch_explanation::operatorMember(record.op); if named.present { member = named; }
    let finished,finish_error = builder.finish(blot_reuse_dispatch_explanation::operatorSymbol(record.op),member); if finish_error != blot_error::Error.none { return finished,finish_error; } var result = finished;
    if record.context_len != 0 {
        var contexts: blot_reuse_dispatch_explanation::Context[>..<] = [];
        for source in record.contexts[..record.context_len] {
            var kind = blot_reuse_dispatch_explanation::ContextKind.left_operand; if source.kind == blot_eval_core_eval::DispatchContextKind.right_operand { kind = blot_reuse_dispatch_explanation::ContextKind.right_operand; }
            var context = blot_reuse_dispatch_explanation::Context { kind: kind,span: source.span , ..};
            if generator.evaluator.diagnostic_context.identity.present {
                let path = generator.evaluator.diagnostic_context.identity.value.owner(source.unit);
                if path.present { if path.value.len <= blot_reuse_dispatch_explanation::max_text { let copied,error = builder.ownText(path.value); if error != blot_error::Error.none { result.deinit(); return default<blot_reuse_dispatch_explanation::Explanation>(),error; } context.path = blot_support::some(copied); } else { result.truncated = true; } }
            }
            contexts.push(context);
        }
        result.contexts = blot_reuse_dispatch_explanation::copyContexts(contexts); let error = result.fit(); if error != blot_error::Error.none { result.deinit(); return default<blot_reuse_dispatch_explanation::Explanation>(),error; }
    }
    return result,blot_error::Error.none;

    }
    let cleanup_result_4_0,cleanup_result_4_1 = cleanup_continuation_4();
     builder.deinit();
    return cleanup_result_4_0,cleanup_result_4_1;
}
fn explainImplementation(generator: Generator&,trace: blot_eval_implementation_trace::Record) -> blot_reuse_dispatch_explanation::Explanation,blot_error::Error {
    var builder = blot_reuse_dispatch_explanation::Builder { truncated: trace.truncated , ..};
    recursive fn cleanup_continuation_3() -> blot_reuse_dispatch_explanation::Explanation,blot_error::Error {
 let names = generator.evaluator.diagnostic_context.identity;
    for candidate in trace.candidates[..trace.len] {
        var declaration = blot_support::none<blot_check_core::Implementation>();
        for source in generator.units { for known in source.implementations { if known.identity == candidate.identity { declaration = blot_support::some(known); break; } } if declaration.present { break; } }
        if !declaration.present { continue; } let known = declaration.value; var name: const u8[:] = "implementation"; var path = blot_support::none<const u8[:]>();
        if names.present { let symbol = names.value.symbol(known.name); if symbol.present { name = symbol.value; } path = names.value.owner(known.identity.unit); }
        let origin,error = builder.makeOrigin(name,path,blot_support::none<blot_check_core::Span>()); if error != blot_error::Error.none { return default<blot_reuse_dispatch_explanation::Explanation>(),error; } builder.addOrigin(blot_support::none<const u8[:]>(),candidate.outcome,origin);
    }
    for step in trace.steps[..trace.step_len] {
        var text: u8[>..<] = []; var display = EntryDisplay { generator,text , ..}; var spelling = blot_support::none<const u8[:]>();
        if step.ty != 0 {
            let printed,error = ty(display,step.ty,16); if error != blot_error::Error.none { return default<blot_reuse_dispatch_explanation::Explanation>(),error; }
            if printed { let copied,copy_error = builder.own(text); if copy_error != blot_error::Error.none { return default<blot_reuse_dispatch_explanation::Explanation>(),copy_error; } spelling = blot_support::some(copied); }
        }
        var member = blot_support::none<const u8[:]>(); if names.present && step.member != 0 { member = names.value.symbol(step.member); } let added = builder.addStep(member,spelling,step.outcome); if added != blot_error::Error.none { return default<blot_reuse_dispatch_explanation::Explanation>(),added; }
    }
    var member = blot_support::none<const u8[:]>(); if names.present { member = names.value.symbol(trace.contract.decl & ~blot_check_types::opaque_name_bit); } return builder.finish(blot_support::none<const u8[:]>(),member);

    }
    let cleanup_result_3_0,cleanup_result_3_1 = cleanup_continuation_3();
     builder.deinit();
    return cleanup_result_3_0,cleanup_result_3_1;
}
struct WireEnum<T> { value: T }
fn wireEnum<T>(value: T) -> WireEnum<T> { WireEnum<T> { value } }
fn jsonStringify<T>(value: WireEnum<T>,writer: blot_json::Writer&) -> blot_error::Error { writer.enumValue(value.value) }
struct WireScalar { value: Scalar }
fn jsonStringify(value: WireScalar,writer: blot_json::Writer&) -> blot_error::Error {
    let scalar = value.value; if scalar == blot_backend_runtime_ir::SC_unit { return writer.quoted("unit"); } if scalar == blot_backend_runtime_ir::SC_u32 { return writer.quoted("u32"); } if scalar == blot_backend_runtime_ir::SC_bool { return writer.quoted("bool"); } if scalar == blot_backend_runtime_ir::SC_f32 { return writer.quoted("f32"); } if scalar == blot_backend_runtime_ir::SC_array_u32 { return writer.quoted("array_u32"); } if scalar == blot_backend_runtime_ir::SC_array_f32 { return writer.quoted("array_f32"); } assert(scalar == blot_backend_runtime_ir::SC_pointer); return writer.quoted("pointer");
}
struct WireOptionalScalar { value: blot_support::Option<Scalar> }
fn jsonStringify(value: WireOptionalScalar,writer: blot_json::Writer&) -> blot_error::Error { if !value.value.present { return writer.nullValue(); } return writer.write(WireScalar { value.value.value , ..}); }
struct WireValueType { value: blot_backend_runtime_ir::ValueType }
fn jsonStringify(value: WireValueType,writer: blot_json::Writer&) -> blot_error::Error {
    let ty = value.value; if ty == blot_backend_runtime_ir::VT_i32 { return writer.quoted("i32"); } if ty == blot_backend_runtime_ir::VT_f32 { return writer.quoted("f32"); } if ty == blot_backend_runtime_ir::VT_v128 { return writer.quoted("v128"); } if ty == blot_backend_runtime_ir::VT_externref { return writer.quoted("externref"); } assert(ty == blot_backend_runtime_ir::VT_none); return writer.quoted("none");
}
struct WireValueTypes { values: const blot_backend_runtime_ir::ValueType[:] }
fn jsonStringify(value: WireValueTypes,writer: blot_json::Writer&) -> blot_error::Error { writer.beginArray(); for ty in value.values { writer.element(WireValueType { ty , ..}); } return writer.endArray(); }
struct WireRole { value: blot_backend_runtime_ir::Role }
fn jsonStringify(value: WireRole,writer: blot_json::Writer&) -> blot_error::Error { let role = value.value; if role == blot_backend_runtime_ir::ROLE_unknown { return writer.quoted("unknown"); } if role == blot_backend_runtime_ir::ROLE_scalar { return writer.quoted("scalar"); } if role == blot_backend_runtime_ir::ROLE_reference { return writer.quoted("reference"); } assert(role == blot_backend_runtime_ir::ROLE_value); return writer.quoted("value"); }
struct WireOp { value: blot_backend_runtime_ir::Op }
fn jsonStringify(value: WireOp,writer: blot_json::Writer&) -> blot_error::Error { writer.quoted(blot_backend_runtime_ir::opName(value.value)) }
struct WireRequest { value: blot_reuse_code_artifacts::Request }
fn jsonStringify(value: WireRequest,writer: blot_json::Writer&) -> blot_error::Error {
    writer.beginObject(); match value.value {
        named r=>writer.field("named",r.key),closure r=>writer.field("closure",r.key),callable r=>writer.field("callable",r.key),constructor r=>writer.field("constructor",r.key),primitive r=>writer.field("primitive",r.key),operation r=>writer.field("operation",r.key),host r=>writer.field("host",r.key),constant r=>writer.field("constant",r.key),runtime_global r=>writer.field("runtime_global",r.target),
    } return writer.endObject();
}
struct WireList<T> { items: const T[:],capacity: i64 }
struct WireJob { metadata: const blot_reuse_code_artifacts::Context&,job: blot_reuse_code_artifacts::Job }
fn jsonStringify(value: WireJob,writer: blot_json::Writer&) -> blot_error::Error {
    let metadata .= value.metadata; let job = value.job; writer.beginObject(); writer.field("parent",job.parent); writer.field("request",WireRequest { job.request , ..}); writer.field("reusable",job.reusable_);
    writer.field("inline_bodies",WireList<blot_check_core::BindingRef> { metadata.inline_bodies.items[job.inline_bodies.start..job.inline_bodies.start + job.inline_bodies.len],job.inline_capacity , ..});
    writer.field("static_reads",WireList<blot_reuse_code_artifacts::StaticRead> { metadata.static_reads.items[job.static_reads.start..job.static_reads.start + job.static_reads.len],job.static_capacity , ..});
    writer.field("state",wireEnum(job.state)); writer.field("function",job.function); writer.field("target_job",job.target_job); writer.field("mappings",metadata.mappings.items[job.mappings.start..job.mappings.start + job.mappings.len]); writer.field("rows",metadata.rows.items[job.rows.start..job.rows.start + job.rows.len]); writer.field("templates",metadata.templates.items[job.templates.start..job.templates.start + job.templates.len]); writer.field("solved",job.solved); writer.field("result_template",job.result_template); writer.field("value",job.value); writer.field("global",job.global); return writer.endObject();
}
struct WireJobs { metadata: const blot_reuse_code_artifacts::Context& }
fn jsonStringify(value: WireJobs,writer: blot_json::Writer&) -> blot_error::Error { writer.beginArray(); for job in value.metadata.jobs.items { writer.element(WireJob { value.metadata,job , ..}); } return writer.endArray(); }
struct WireDemandEvent { value: blot_reuse_code_artifacts::Event }
fn jsonStringify(value: WireDemandEvent,writer: blot_json::Writer&) -> blot_error::Error {
    match value.value { enter e=>{ writer.beginObject(); writer.field("enter",e.job); return writer.endObject(); },solved e=>{ writer.beginObject(); writer.field("solved",e.job); return writer.endObject(); },_=>{ return writer.unionValue(value.value); }, }
}
struct WireDemandEvents { values: const blot_reuse_code_artifacts::StampedEvent[:] }
fn jsonStringify(value: WireDemandEvents,writer: blot_json::Writer&) -> blot_error::Error { writer.beginArray(); for event in value.values { writer.separator(blot_json::FrameKind.array); writer.beginObject(); writer.field("sequence",event.sequence); writer.field("event",WireDemandEvent { event.event , ..}); writer.endObject(); } return writer.endArray(); }
struct WireOperand { value: blot_reuse_artifact_emitter::Operand }
fn jsonStringify(value: WireOperand,writer: blot_json::Writer&) -> blot_error::Error { writer.beginObject(); writer.field("role",wireEnum(value.value.role)); writer.field("value",value.value.value); return writer.endObject(); }
struct WireSymbolicInstructions { values: const blot_reuse_artifact_emitter::SymbolicInstruction[:] }
fn jsonStringify(value: WireSymbolicInstructions,writer: blot_json::Writer&) -> blot_error::Error { writer.beginArray(); for instruction in value.values { writer.separator(blot_json::FrameKind.array); writer.beginObject(); writer.field("op",WireOp { instruction.op , ..}); writer.field("operand",WireOperand { instruction.operand , ..}); writer.endObject(); } return writer.endArray(); }
struct WireFunctionArtifacts { values: const blot_reuse_artifact_emitter::FunctionArtifact[:] }
fn jsonStringify(value: WireFunctionArtifacts,writer: blot_json::Writer&) -> blot_error::Error { writer.beginArray(); for function in value.values { writer.separator(blot_json::FrameKind.array); writer.beginObject(); writer.field("owner",function.owner); writer.field("resource_owner",function.resource_owner); writer.field("role",wireEnum(function.role)); writer.field("signature",function.signature); writer.field("creation_sequence",function.creation_sequence); writer.field("locals",function.locals); writer.field("instructions",function.instructions); writer.endObject(); } return writer.endArray(); }
struct WireCallback { value: blot_support::Option<blot_backend_wasm::Callback> }
fn jsonStringify(value: WireCallback,writer: blot_json::Writer&) -> blot_error::Error {
    if !value.value.present { return writer.nullValue(); } let callback = value.value.value; writer.beginObject(); writer.field("parameter",WireScalar { callback.parameter , ..}); writer.field("result",WireScalar { callback.result , ..}); writer.field("cleanup",callback.cleanup); writer.field("owned",callback.owned); writer.field("data",callback.data); writer.field("schema",callback.schema); writer.field("concurrent",callback.concurrent); return writer.endObject();
}
struct WireOwnerBoundary { value: blot_support::Option<blot_backend_wasm::OwnerBoundary> }
fn jsonStringify(value: WireOwnerBoundary,writer: blot_json::Writer&) -> blot_error::Error {
    if !value.value.present { return writer.nullValue(); } let owner = value.value.value; writer.beginObject(); writer.field("schema",owner.schema); writer.key("kind"); if owner.kind == 1 { writer.quoted("unique"); } else { assert(owner.kind == 2); writer.quoted("shared"); } writer.field("fresh",WireOptionalScalar { owner.fresh , ..}); return writer.endObject();
}
struct WireSemanticSite { value: blot_backend_wasm::SemanticSite }
fn jsonStringify(value: WireSemanticSite,writer: blot_json::Writer&) -> blot_error::Error {
    let site = value.value; writer.beginObject(); writer.field("diagnostic_context",site.diagnostic_context); writer.field("function",site.function); writer.field("place",site.place); writer.field("unit",site.unit); writer.field("node",site.node); writer.field("root",site.root); writer.field("mappings",site.mappings); writer.field("rows",site.rows); writer.field("kind",wireEnum(site.kind)); return writer.endObject();
}
struct WireEmissionEvent { value: blot_reuse_artifact_emitter::Event }
fn jsonStringify(value: WireEmissionEvent,writer: blot_json::Writer&) -> blot_error::Error {
    match value.value {
        demand event=>{ writer.beginObject(); writer.key("demand"); writer.beginObject(); writer.field("kind",wireEnum(event.kind)); writer.field("id",event.id); writer.field("hit",event.hit); writer.endObject(); return writer.endObject(); },
        signature event=>{ writer.beginObject(); writer.key("signature"); writer.beginObject(); writer.field("id",event.id); writer.field("parameters",event.parameters); writer.field("result",WireValueType { event.result , ..}); writer.endObject(); return writer.endObject(); },
        function event=>{ writer.beginObject(); writer.key("function"); writer.beginObject(); writer.field("id",event.id); writer.field("signature",event.signature); writer.field("result_role",WireRole { event.result_role , ..}); writer.endObject(); return writer.endObject(); },
        semantic_site event=>{ writer.beginObject(); writer.field("semantic_site",WireSemanticSite { event.value , ..}); return writer.endObject(); },
        local event=>{ writer.beginObject(); writer.key("local"); writer.beginObject(); writer.field("function",event.function); writer.field("ty",WireValueType { event.ty , ..}); writer.endObject(); return writer.endObject(); },
        instruction event=>{ writer.beginObject(); writer.key("instruction"); writer.beginObject(); writer.field("function",event.function); writer.field("op",WireOp { event.op , ..}); writer.field("operand",WireOperand { event.operand , ..}); writer.endObject(); return writer.endObject(); },
        global event=>{ writer.beginObject(); writer.key("global"); writer.beginObject(); writer.field("id",event.id); writer.field("scalar",WireScalar { event.scalar , ..}); writer.field("bits",WireOperand { event.bits , ..}); writer.field("mutable",event.mutable); writer.endObject(); return writer.endObject(); },
        global_bits event=>{ writer.beginObject(); writer.key("global_bits"); writer.beginObject(); writer.field("id",event.id); writer.field("bits",WireOperand { event.bits , ..}); writer.endObject(); return writer.endObject(); },
        data_word event=>{ writer.beginObject(); writer.key("data_word"); writer.beginObject(); writer.field("address",event.address); writer.field("operand",WireOperand { event.operand , ..}); writer.endObject(); return writer.endObject(); },
        host_references event=>{ writer.beginObject(); writer.field("host_references",event.value); return writer.endObject(); },public_owners event=>{ writer.beginObject(); writer.field("public_owners",event.value); return writer.endObject(); },cleanup_data event=>{ writer.beginObject(); writer.field("cleanup_data",event.span); return writer.endObject(); },
        export_ event=>{
            writer.beginObject(); writer.key("export_"); writer.beginObject(); writer.field("name",event.name); writer.field("index",event.index); writer.field("parameter",WireScalar { event.parameter , ..}); writer.field("result",WireScalar { event.result , ..}); writer.field("global",event.global); writer.field("callback",WireCallback { event.callback , ..}); writer.field("once",event.once); writer.field("parameter_owner",WireOwnerBoundary { event.parameter_owner , ..}); writer.field("result_owner",WireOwnerBoundary { event.result_owner , ..}); writer.field("owner_adapter",event.owner_adapter); writer.field("task_adapter",event.task_adapter); writer.field("task_runtime",event.task_runtime); writer.field("entry",event.entry); writer.endObject(); return writer.endObject();
        },
        static_field event=>{ writer.beginObject(); writer.key("static_field"); writer.beginObject(); writer.field("address",event.address); writer.field("role",WireRole { event.role , ..}); writer.endObject(); return writer.endObject(); },start event=>{ writer.beginObject(); writer.field("start",event.id); return writer.endObject(); },
        _=>{ return writer.unionValue(value.value); },
    }
}
struct WireEmissionRecords { values: const blot_reuse_artifact_emitter::Record[:] }
fn jsonStringify(value: WireEmissionRecords,writer: blot_json::Writer&) -> blot_error::Error { writer.beginArray(); for record in value.values { writer.separator(blot_json::FrameKind.array); writer.beginObject(); writer.field("sequence",record.sequence); writer.field("owner",record.owner); writer.field("event",WireEmissionEvent { record.event , ..}); writer.endObject(); } return writer.endArray(); }
struct WireEmission { journal: const blot_reuse_artifact_emitter::Recorder& }
fn jsonStringify(value: WireEmission,writer: blot_json::Writer&) -> blot_error::Error {
    let journal .= value.journal; writer.beginObject(); writer.field("records",WireEmissionRecords { journal.records.items , ..}); writer.field("bytes",journal.bytes.items[..]); writer.field("parameters",WireValueTypes { journal.parameters.items , ..}); writer.field("operations",journal.operations.items[..]); writer.field("functions",WireFunctionArtifacts { journal.functions , ..}); writer.field("locals",WireValueTypes { journal.locals , ..}); writer.field("instructions",WireSymbolicInstructions { journal.instructions , ..}); return writer.endObject();
}
struct WireLayoutNodes { values: const blot_backend_layout::Node[:] }
fn jsonStringify(value: WireLayoutNodes,writer: blot_json::Writer&) -> blot_error::Error { writer.beginArray(); for node in value.values { writer.separator(blot_json::FrameKind.array); writer.beginObject(); writer.field("tag",wireEnum(node.tag)); writer.field("a",node.a); writer.field("b",node.b); writer.field("c",node.c); writer.endObject(); } return writer.endArray(); }
struct WireEvidenceNodes { values: const blot_eval_type_evidence::Node[:] }
fn jsonStringify(value: WireEvidenceNodes,writer: blot_json::Writer&) -> blot_error::Error { writer.beginArray(); for node in value.values { writer.separator(blot_json::FrameKind.array); writer.beginObject(); writer.field("tag",wireEnum(node.tag)); writer.field("a",node.a); writer.field("b",node.b); writer.field("c",node.c); writer.endObject(); } return writer.endArray(); }
struct WireEffects { value: blot_check_effect_evidence::Snapshot }
fn jsonStringify(value: WireEffects,writer: blot_json::Writer&) -> blot_error::Error { writer.beginObject(); writer.field("operations",value.value.operations); writer.field("arguments",value.value.arguments); writer.field("rows",value.value.rows); writer.field("labels",value.value.labels); return writer.endObject(); }
struct WireLayouts { value: blot_reuse_code_artifacts::Layouts }
fn jsonStringify(value: WireLayouts,writer: blot_json::Writer&) -> blot_error::Error { writer.beginObject(); writer.field("nodes",WireLayoutNodes { value.value.nodes , ..}); writer.field("extra",value.value.extra); writer.field("effects",WireEffects { value.value.effects , ..}); writer.field("universal_dictionaries",value.value.universal_dictionaries); return writer.endObject(); }
struct WireEvidenceGoals { values: const blot_eval_type_evidence::Goal[:] }
fn jsonStringify(value: WireEvidenceGoals,writer: blot_json::Writer&) -> blot_error::Error {
    writer.beginArray(); for goal in value.values { writer.separator(blot_json::FrameKind.array); writer.beginObject(); writer.field("ty",goal.ty); writer.field("kind",wireEnum(goal.kind)); writer.field("name",goal.name); writer.field("result",goal.result); writer.field("other",goal.other); writer.field("signature",goal.signature); writer.field("operator",wireEnum(goal.operator)); writer.field("identity",goal.identity); writer.field("explicit",goal.explicit); writer.endObject(); } return writer.endArray();
}
struct WireEvidence { value: blot_eval_type_evidence::Snapshot }
fn jsonStringify(value: WireEvidence,writer: blot_json::Writer&) -> blot_error::Error { writer.beginObject(); writer.field("nodes",WireEvidenceNodes { value.value.nodes , ..}); writer.field("extra",value.value.extra); writer.field("effects",WireEffects { value.value.effects , ..}); writer.field("quantifier_goals",value.value.quantifier_goals); writer.field("quantifier_obligations",WireEvidenceGoals { value.value.quantifier_obligations , ..}); return writer.endObject(); }
struct WireValues { values: const blot_eval_eval_values::ValueInfo[:] }
fn jsonStringify(value: WireValues,writer: blot_json::Writer&) -> blot_error::Error { writer.beginArray(); for info in value.values { writer.separator(blot_json::FrameKind.array); writer.beginObject(); writer.field("nominal",info.nominal); writer.field("start",info.start); writer.field("len",info.len); writer.field("bits",info.bits); writer.field("kind",wireEnum(info.kind)); writer.field("scalar",WireScalar { info.scalar , ..}); writer.endObject(); } return writer.endArray(); }
struct WireClosures { values: const blot_eval_eval_values::ClosureValue[:] }
fn jsonStringify(value: WireClosures,writer: blot_json::Writer&) -> blot_error::Error { writer.beginArray(); for closure in value.values { writer.separator(blot_json::FrameKind.array); writer.beginObject(); writer.field("staged",closure.staged); writer.field("unit",closure.unit); writer.field("identity",closure.identity); writer.field("applied",closure.applied); writer.field("origin",wireEnum(closure.origin)); writer.field("mappings",closure.mappings); writer.field("row_mappings",closure.row_mappings); writer.field("ty",closure.ty); writer.endObject(); } return writer.endArray(); }
struct WireImplementationFact { value: blot_eval_implementation_evidence::Fact }
fn jsonStringify(value: WireImplementationFact,writer: blot_json::Writer&) -> blot_error::Error { let fact = value.value; writer.beginObject(); writer.field("kind",wireEnum(fact.kind)); writer.field("operator",wireEnum(fact.operator)); writer.field("identity",fact.identity); writer.field("name",fact.name); writer.field("operands",fact.operands[..]); writer.field("target",fact.target); return writer.endObject(); }
struct WireImplementationProofs { values: const blot_eval_implementation_evidence::Proof[:] }
fn jsonStringify(value: WireImplementationProofs,writer: blot_json::Writer&) -> blot_error::Error { writer.beginArray(); for proof in value.values { writer.separator(blot_json::FrameKind.array); writer.beginObject(); writer.field("kind",wireEnum(proof.kind)); writer.field("predicate",WireImplementationFact { proof.predicate , ..}); writer.field("context",proof.context); writer.field("implementation",proof.implementation); writer.field("contract",proof.contract); writer.field("arguments",proof.arguments); writer.field("members",proof.members); writer.field("prerequisites",proof.prerequisites); writer.endObject(); } return writer.endArray(); }
struct WireImplementationMembers { values: const blot_eval_implementation_evidence::Member[:] }
fn jsonStringify(value: WireImplementationMembers,writer: blot_json::Writer&) -> blot_error::Error { writer.beginArray(); for member in value.values { writer.separator(blot_json::FrameKind.array); writer.beginObject(); writer.field("name",member.name); writer.field("kind",wireEnum(member.kind)); writer.field("root",member.root); writer.field("target",member.target); writer.endObject(); } return writer.endArray(); }
struct WireImplementationSnapshot { value: blot_eval_implementation_evidence::Snapshot }
fn jsonStringify(value: WireImplementationSnapshot,writer: blot_json::Writer&) -> blot_error::Error { writer.beginObject(); writer.field("proofs",WireImplementationProofs { value.value.proofs , ..}); writer.field("arguments",value.value.arguments); writer.field("members",WireImplementationMembers { value.value.members , ..}); writer.field("edges",value.value.edges); return writer.endObject(); }
struct WireEvaluatorSnapshot { value: blot_eval_core_eval::Snapshot }
fn jsonStringify(value: WireEvaluatorSnapshot,writer: blot_json::Writer&) -> blot_error::Error {
    let snapshot = value.value; writer.beginObject(); writer.field("code_origins",snapshot.code_origins); writer.field("values",WireValues { snapshot.values , ..}); writer.field("children",snapshot.children); writer.field("closures",WireClosures { snapshot.closures , ..}); writer.field("value_evidence",snapshot.value_evidence); writer.field("type_mappings",snapshot.type_mappings); writer.field("row_mappings",snapshot.row_mappings); writer.field("evidence",WireEvidence { snapshot.evidence , ..}); writer.field("value_records",snapshot.value_records); writer.field("record_layouts",snapshot.record_layouts); writer.field("field_names",snapshot.field_names); writer.field("implementation_proofs",WireImplementationSnapshot { snapshot.implementation_proofs , ..}); return writer.endObject();
}
struct WireBridge { value: blot_support::Option<blot_reuse_code_artifacts::Bridge> }
fn jsonStringify(value: WireBridge,writer: blot_json::Writer&) -> blot_error::Error { if !value.value.present { return writer.nullValue(); } let bridge = value.value.value; writer.beginObject(); writer.field("nodes",WireEvidenceNodes { bridge.nodes , ..}); writer.field("extra",bridge.extra); writer.field("to",bridge.to); writer.field("from",bridge.from); writer.field("row_to",bridge.row_to); writer.field("row_from",bridge.row_from); writer.field("shapes",bridge.shapes); return writer.endObject(); }
struct WireFunctions { values: const blot_reuse_code_artifacts::Function[:] }
fn jsonStringify(value: WireFunctions,writer: blot_json::Writer&) -> blot_error::Error { writer.beginArray(); for function in value.values { writer.separator(blot_json::FrameKind.array); writer.beginObject(); writer.field("request",WireRequest { function.request , ..}); writer.field("function",function.function); writer.field("result_template",function.result_template); writer.endObject(); } return writer.endArray(); }
struct WireOperationLocation { value: blot_reuse_code_artifacts::OperationLocation }
fn jsonStringify(value: WireOperationLocation,writer: blot_json::Writer&) -> blot_error::Error { match value.value { word address=>{ writer.beginObject(); writer.field("word",address.address); return writer.endObject(); },_=>{ return writer.unionValue(value.value); }, } }
struct WireOperationRelocations { values: const blot_reuse_code_artifacts::OperationRelocation[:] }
fn jsonStringify(value: WireOperationRelocations,writer: blot_json::Writer&) -> blot_error::Error { writer.beginArray(); for relocation in value.values { writer.separator(blot_json::FrameKind.array); writer.beginObject(); writer.field("operation",relocation.operation); writer.field("location",WireOperationLocation { relocation.location , ..}); writer.endObject(); } return writer.endArray(); }
struct WireOwnedPools { value: const blot_reuse_code_artifacts::Pools& }
fn jsonStringify(value: WireOwnedPools,writer: blot_json::Writer&) -> blot_error::Error {
    let pools .= value.value; writer.beginObject(); writer.field("project_identity",pools.project_identity); writer.field("identity",pools.identity); writer.field("layouts",WireLayouts { pools.layouts , ..}); writer.field("evaluator",WireEvaluatorSnapshot { pools.evaluator , ..}); writer.field("rows",pools.rows); writer.field("templates",pools.templates); writer.field("captures",pools.captures); writer.field("bridge",WireBridge { pools.bridge , ..}); writer.field("field_locations",pools.field_locations); writer.field("field_locations_stamp",pools.field_locations_stamp[..]); writer.field("functions",WireFunctions { pools.functions , ..}); writer.field("serialized",pools.serialized); writer.field("runtime_globals",pools.runtime_globals); writer.field("runtime_order",pools.runtime_order); writer.field("operations",pools.operations); writer.field("operation_relocations",WireOperationRelocations { pools.operation_relocations , ..}); writer.field("operations_finalized",pools.operations_finalized); return writer.endObject();
}
fn printArtifact<T>(label: const u8[:],value: T) -> blot_error::Error {
    var bytes: u8[>..<] = []; let error = blot_json::toBytes(value,bytes,blot_json::Options { emit_strings_as_arrays: true,emit_nonportable_numbers_as_strings: true , ..}); if error != blot_error::Error.none { return error; }
    var line: u8[>..<] = []; line.append(label); line.push(' '); line.append(bytes); line.push('\n'); blot_native::debug_write(line); return blot_error::Error.none;
}
struct WireModulePin { unit: u32,path: const u8[:],token: blot_reuse_code_artifacts::Token,stamp: u8[32] }
fn jsonStringify(value: WireModulePin,writer: blot_json::Writer&) -> blot_error::Error { writer.beginObject(); writer.field("unit",value.unit); writer.field("path",value.path); writer.field("token",value.token); writer.field("stamp",value.stamp[..]); return writer.endObject(); }
fn dumpArtifact(run: CompileRun&,result: Result&,counts: ArtifactCounts) -> blot_error::Error {
    let metadata .= run.workspace.metadata; let journal .= run.workspace.journal; assert(metadata.pools.present); let pools: const blot_reuse_code_artifacts::Pools& = metadata.pools.value;
    let jobs = printArtifact("ARTIFACT_JOBS",WireJobs { metadata , ..}); if jobs != blot_error::Error.none { return jobs; } let demands = printArtifact("ARTIFACT_DEMAND_EVENTS",WireDemandEvents { metadata.events.items , ..}); if demands != blot_error::Error.none { return demands; }
    let emission = printArtifact("ARTIFACT_EMISSION",WireEmission { journal , ..}); if emission != blot_error::Error.none { return emission; }
    for pin in pools.modules { let error = printArtifact("ARTIFACT_MODULE_PIN",WireModulePin { pin.unit,pin.canonical_path,pin.token,pin.stamp , ..}); if error != blot_error::Error.none { return error; } }
    let owned = printArtifact("ARTIFACT_OWNED_POOLS",WireOwnedPools { pools , ..}); if owned != blot_error::Error.none { return owned; }
    var line: u8[>..<] = []; line.append("ARTIFACT_METADATA {\"demands\":"); format(line,metadata.jobs.len); line.append(",\"events\":"); format(line,metadata.events.len); line.append(",\"complete_functions\":"); format(line,pools.functions.len); line.append(",\"templates\":"); format(line,pools.captures.len); line.append(",\"pinned_modules\":"); format(line,pools.modules.len); line.append("}\n"); blot_native::debug_write(line); line.clear();
    line.append("ARTIFACT_REPLAY {\"events\":"); format(line,journal.records.len); line.append(",\"owned_bytes\":"); format(line,journal.bytes.len); line.append(",\"functions\":"); format(line,result.emitted_functions); line.append(",\"globals\":"); format(line,counts.globals); line.append(",\"imports\":"); format(line,counts.imports); line.append(",\"signatures\":"); format(line,counts.signatures); line.append(",\"data_bytes\":"); format(line,counts.data_bytes); line.append(",\"source_work_during_replay\":0,\"semantic_reuse\":false}\n"); blot_native::debug_write(line); return blot_error::Error.none;
}
fn associatedTarget(generator: Generator&,origin: u32,identity: blot_check_types::NominalIdentity,member: u32,op: blot_check_types::Operator) -> blot_support::Option<blot_check_core::BindingRef>,blot_error::Error {
    let target,error = generator.evaluator.associatedTarget(origin,identity,member,op); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return target,error; } return blot_support::none<blot_check_core::BindingRef>(),evaluationFailure(generator); } return target,blot_error::Error.none;
}
struct CapturedClosureEmission { header: blot_eval_core_eval::ClosureValue,captured: const blot_eval_core_eval::ValueId[:] }
fn emitCapturedClosureOwner(context: CapturedClosureEmission&,emitter: blot_backend_backend_emission::Owner&) -> blot_error::Error {
    let generator .= emitter.generator; let source .= unit(generator,context.header.unit); let metadata = source.closures[context.header.identity]; let bindings = source.extra[metadata.captures.start..metadata.captures.start + metadata.captures.len]; assert(bindings.len == context.captured.len);
    if metadata.parameter.binding != 0 { emitter.locals.insert(metadata.parameter.binding,1); } for binding,index in bindings { emitter.static_values.insert(binding,context.captured[index]); }
    let body = emitter.bodyExpression(metadata.body,0,false); if body != blot_error::Error.none { return body; } if source.types.node(source.typeOf(metadata.body)).tag == blot_check_types::Tag.never { return emitter.emit(blot_backend_runtime_ir::OP_unreachable_,0); } return blot_error::Error.none;
}
fn capturedClosureFunction(generator: Generator&,header: blot_eval_core_eval::ClosureValue,ty: u32,captured: const blot_eval_core_eval::ValueId[:],mappings: const Mapping[:],rows: const RowMapping[:]) -> u32,blot_error::Error {
    let source .= unit(generator,header.unit); let metadata = source.closures[header.identity]; if generator.instance_depth >= 256 { return 0,fail(generator,header.unit,metadata.body,blot_check_diagnostic_code::Code.complexity); } generator.instance_depth++;
    recursive fn cleanup_continuation_2() -> u32,blot_error::Error {

    if generator.artifacts != null { generator.artifacts.requireFreshCode(); } let arrow = generator.representations.store.node(ty); let parameters: blot_backend_runtime_ir::ValueType[3] = [blot_backend_runtime_ir::VT_i32,generator.representations.store.machine(arrow.a),blot_backend_runtime_ir::VT_i32];
    let function_id,error = generator.module.addTypedFunction(parameters,generator.representations.store.machine(arrow.b),bodyResultRole(generator,arrow.b,header.unit,metadata.body)); if error != blot_error::Error.none { return 0,error; }
    let described = setParameterRoles(generator,function_id,closureRoles(generator,arrow.a),blot_support::some(2 as u16)); if described != blot_error::Error.none { return 0,described; } generator.static_data.closures.push(function_id); generator.work.fresh_closures++;
    let requested = generator.planning.startup_facts.request(function_id,blot_backend_startup_emission_facts::Kind.anonymous,header.unit,header.identity,false); if requested != blot_error::Error.none { return 0,requested; }
    let caller = generator.planning.startup_facts.active; generator.planning.startup_facts.active = function_id;
    recursive fn cleanup_continuation_1() -> u32,blot_error::Error {

    var context = CapturedClosureEmission { header,captured , ..}; let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { generator: generator,unit_id: header.unit,function_id: function_id,provider_local: blot_support::some(2 as u32),mappings: mappings,row_mappings: rows , ..},context,emitCapturedClosureOwner); if emitted != blot_error::Error.none { return 0,emitted; } generator.planning.startup_facts.complete(function_id); return function_id,blot_error::Error.none;

    }
    let cleanup_result_1_0,cleanup_result_1_1 = cleanup_continuation_1();
     generator.planning.startup_facts.active = caller;
    return cleanup_result_1_0,cleanup_result_1_1;

    }
    let cleanup_result_2_0,cleanup_result_2_1 = cleanup_continuation_2();
     generator.instance_depth--;
    return cleanup_result_2_0,cleanup_result_2_1;
}

// The canonical driver binds a distinct workspace owner before public emission.
fn bindPublicationOwner(workspace: CompileWorkspace&,driver_owner: u64) -> blot_error::Error {
    if workspace.publication_owner.slot != 0 { return blot_error::Error.invalid_artifact; } let owner,error = blot_backend_result_publication::init(driver_owner,workspace.allocation_owner); if error != blot_error::Error.none { return error; } workspace.publication_owner = owner; return blot_error::Error.none;
}
// Pin before assigning units to evaluator, generator, metadata or replay contexts.
fn pinWorkspaceInputs(workspace: CompileWorkspace&,units: const blot_check_core::Module[:],catalog_owner: blot_reuse_dependency_payload::Owner,unit_owners: const blot_reuse_dependency_payload::Owner[:],seed_owners: const blot_reuse_dependency_payload::Owner[:]) -> blot_error::Error {
    let error = blot_backend_result_publication::stageInputs(workspace.publication_owner,units,catalog_owner,unit_owners,seed_owners); if error != blot_error::Error.none { return error; }
    let held,held_error = blot_backend_result_publication::inputUnits(workspace.publication_owner,units); assert(held_error == blot_error::Error.none); workspace.compiled_units = held; return blot_error::Error.none;
}
fn publicationCanReclaim(workspace: const CompileWorkspace&) -> bool { return blot_backend_result_publication::canReclaim(workspace.publication_owner); }
fn pinResult(result: Result&,catalog_owner: blot_reuse_dependency_payload::Owner,unit_owners: const blot_reuse_dependency_payload::Owner[:],seed_owners: const blot_reuse_dependency_payload::Owner[:]) -> blot_error::Error {
    if !result.active { assert(result.publication_owner.slot == 0 && !result.publication_pinned && result.capture == null && result.allocation_emission == null && result.explanation == null && result.startup_observation == null && !result.diagnostic.present && result.bytes.len == 0 && result.owned_message.len == 0); return blot_error::Error.none; }
    if result.publication_owner.slot == 0 || result.publication_pinned { return blot_error::Error.invalid_artifact; }
    let captured .=result.capture;let modules=if captured {if captured.metadata.pools.present {captured.metadata.pools.value.modules}else {default<const blot_reuse_code_artifacts::ModulePin[:]>()}}else {default<const blot_reuse_code_artifacts::ModulePin[:]>()};
    var pins,error = blot_backend_result_publication::prepare(result.publication_owner,result.publication_epoch,result.publication_units,catalog_owner,unit_owners,seed_owners,modules); if error != blot_error::Error.none { return error; }
    if captured && captured.metadata.pools.present { let rebound = blot_reuse_code_artifacts::rebindModuleHeaders(captured.metadata.pools.value,pins.headers); if rebound != blot_error::Error.none { pins.deinit(); return rebound; } }
    blot_backend_result_publication::commit(result.publication_owner,result.publication_epoch,pins); result.publication_pinned = true; result.publication_units = blot_backend_result_publication::units(result.publication_owner,result.publication_epoch); return blot_error::Error.none;
}

fn ownedResult(bytes: const u8[:],allocation: blot_support::Option<blot_backend_allocation_emission::Snapshot>) -> Result,blot_error::Error {
    var owner,error = blot_backend_result_owner::init(); if error != blot_error::Error.none { return Result {..},error; } let entry .= blot_backend_result_owner::get(owner); let copied = entry.bytes.append(bytes); if copied != blot_error::Error.none { owner.deinit(); return Result {..},copied; } var result = Result { active: true,output_owner: owner,detached: true,bytes: entry.bytes,owned_message: entry.message,..};
    if allocation.present { let snapshot,snapshot_error = allocation.value.clone(); if snapshot_error != blot_error::Error.none { owner.deinit(); return Result {..},snapshot_error; } entry.allocation = snapshot; result.allocation_emission .= entry.allocation; } return result,blot_error::Error.none;
}
// Capture transfer is explicit and precedes this hook. The factory can then
// tear down the workspace and compile another revision while this result lives.
fn detachResult(result: Result&) -> blot_error::Error {
    if result.capture != null { return blot_error::Error.invalid_artifact; } if result.detached && result.publication_owner.slot == 0 { return blot_error::Error.none; } if !result.active { return blot_error::Error.none; }
    if result.output_owner.slot == 0 { let owner,error = blot_backend_result_owner::init(); if error != blot_error::Error.none { return error; } result.output_owner = owner; } let entry .= blot_backend_result_owner::get(result.output_owner);
    if !(result.bytes .== entry.bytes) { let copied = entry.bytes.append(result.bytes.items); if copied != blot_error::Error.none { return copied; } }
    entry.message.clear(); let copied = entry.message.append(result.message_source); if copied != blot_error::Error.none { return copied; } entry.diagnostic_text.clear(); if result.diagnostic.present { let detail = entry.diagnostic_text.append(result.diagnostic.value.detail); if detail != blot_error::Error.none { return detail; } }
    if result.allocation_emission { entry.allocation = result.allocation_emission; result.allocation_emission = blot_backend_allocation_emission::Snapshot {..}; result.allocation_emission .= entry.allocation; }
    if result.startup_observation { entry.startup = result.startup_observation; result.startup_observation = blot_backend_startup_emission_facts::Snapshot {..}; result.startup_observation .= entry.startup; }
    if result.explanation { entry.explanation = result.explanation; result.explanation = blot_reuse_dispatch_explanation::Explanation {..}; result.explanation .= entry.explanation; }
    result.bytes .= entry.bytes; result.owned_message .= entry.message; if result.diagnostic.present { result.diagnostic.value.detail = entry.diagnostic_text.items; } result.message_source = []; result.detached = true;
    if result.publication_owner.slot != 0 { blot_backend_result_publication::releaseResult(result.publication_owner,result.publication_epoch,result.publication_pinned); } result.publication_owner = blot_backend_result_publication::Owner {..}; result.publication_epoch = 0; result.publication_pinned = false; result.publication_units = []; return blot_error::Error.none;
}
