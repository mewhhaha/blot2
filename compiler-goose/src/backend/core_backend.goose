// Named code instances and constants share the checked immutable Core graph.
namespace blot_backend_core_backend;
import std;
import dictionary;
import check.core;
import check.types;
import check.diagnostic_code;
import check.dictionary_owner;
import check.staging_origins;
import check.numeric_proof_core;
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
import .source_origins;
import .ragged_builder;
import .optimized_bodies;
import .function_facts;
import .startup_emission_facts;
import eval.core_eval;
import eval.type_evidence;
import eval.specialization;
import eval.completed_specialization_query;
import eval.implementation_trace;
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
import reuse.dependency_certificate;
import runtime.runtime_layout;
import runtime.request_runtime;
import runtime.public_owners;
import runtime.task_context;
import runtime.task_abi;
import work_counters;
import support.option;
import support.error;

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
struct Result {
    allocation_emission: blot_backend_allocation_emission::Snapshot&? = null, timing: blot_backend_backend_timing::Stats,
    counters: blot_work_counters::Counters, optimization: blot_backend_function_facts::Stats, runtime_optimization: blot_backend_optimized_bodies::Stats,
    module_stamps: ModuleStamps, refinements: blot_reuse_refinement_receipt::Stats, completed_queries: blot_eval_completed_specialization_query::Stats, query_tables: QueryTables,
    artifacts: blot_support::Option<ArtifactSummary>, capture: blot_reuse_artifact_capture::Capture&? = null, whole_module_only: bool = false,
    reuse: blot_reuse_artifact_fragment::Stats, principal: blot_reuse_principal_evidence_reuse::Stats, source_validation: blot_reuse_dependency_certificate::Stats,
    bytes: u8[>..<]&, diagnostic: blot_support::Option<Diagnostic>, code_instances: i64 = 0, callable_wrappers: i64 = 0, emitted_functions: i64 = 0, constant_steps: i64 = 0,
    constant_receipts: blot_reuse_constant_receipt::Stats, owned_message: u8[>..<]&, explanation: blot_reuse_dispatch_explanation::Explanation&? = null,
    startup_observation: blot_backend_startup_emission_facts::Snapshot&? = null,
}
struct Generator {
    allocation_owner: u64 = 0,
    inline_named: bool = true, speculative_locals: bool = true, speculated: bool = false, ragged_probe_limit: u32 = blot_backend_ragged_builder::probe_limit,
    work_timing: blot_backend_backend_timing::Work, units: const blot_check_core::Module[:], spawn_units: const blot_check_core::Module[:] = [],
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
    if !generator.diagnostic.present { generator.diagnostic = blot_support::some(Diagnostic { unit: unit_id, span: span, code: code, origins: generator.staging_trace }); }
    return blot_error::Error.declined;
}
fn fail(generator: Generator&, unit_id: u32, node: blot_check_core::Id, code: Code) -> blot_error::Error { decline(generator, unit_id, generator.unit(unit_id).span(node), code) }
fn failSpecialization(generator: Generator&, unit_id: u32, node: blot_check_core::Id, code: Code) -> blot_error::Error {
    let fresh = !generator.diagnostic.present; let failure = fail(generator, unit_id, node, code);
    if fresh && blot_eval_core_eval::callerDependentUse(generator.unit(unit_id), node) && generator.evaluator.specialization_origin.present {
        let origin = generator.evaluator.specialization_origin.value; let diagnostic = generator.diagnostic.value;
        if unit_id != origin.unit || diagnostic.span != origin.span { generator.diagnostic.value.related = blot_support::some(blot_eval_core_eval::SourceLocation { unit: unit_id, span: diagnostic.span }); generator.diagnostic.value.unit = origin.unit; generator.diagnostic.value.span = origin.span; }
    }
    return failure;
}
fn functionRoot(generator: Generator&, unit_id: u32, ty: blot_check_types::Id, span: blot_check_core::Span) -> blot_check_types::Id, blot_error::Error {
    let root, error = generator.unit(unit_id).types.withoutForall(ty); if error != blot_error::Error.none { return 0, decline(generator, unit_id, span, Code.complexity); } return root, blot_error::Error.none;
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
    if depth >= 128 { return 0, decline(generator, 1, blot_check_core::Span {}, Code.unresolved_type); } if requested == blot_backend_layout::erased { return actual, blot_error::Error.none; }
    let wanted = generator.representations.store.node(requested); let proven = generator.representations.store.node(actual);
    if wanted.tag != proven.tag { return 0, decline(generator, 1, blot_check_core::Span {}, Code.unresolved_type); }
    if wanted.tag != blot_backend_layout::Tag.function { return requested, blot_error::Error.none; }
    let input, input_error = completeRetainedRows(generator, wanted.a, proven.a, depth + 1); if input_error != blot_error::Error.none { return 0, input_error; }
    let output, output_error = completeRetainedRows(generator, wanted.b, proven.b, depth + 1); if output_error != blot_error::Error.none { return 0, output_error; }
    var row = wanted.c; if row == blot_backend_layout::unknown_row { row = proven.c; } return internLayoutWithEffects(generator, blot_backend_layout::Tag.function, input, output, row, []);
}
fn acyclicLayout(generator: Generator&, ty: blot_backend_layout::Id) -> bool, blot_error::Error { blot_backend_acyclic_layout::proven(generator.representations.store, generator.units, ty) }
fn scalar(generator: Generator&, unit_id: u32, ty: blot_check_types::Id, mappings: const Mapping[:], span: blot_check_core::Span) -> Scalar, blot_error::Error {
    let selected, error = codeLayout(generator, unit_id, ty, mappings, span); if error != blot_error::Error.none { return 0, error; }
    let scalar = generator.representations.store.scalar(selected); if scalar.present { return scalar.value, blot_error::Error.none; } return blot_backend_runtime_ir::SC_pointer, blot_error::Error.none;
}
fn typeLayout(generator: Generator&, unit_id: u32, ty: blot_check_types::Id, mappings: const Mapping[:], span: blot_check_core::Span) -> blot_backend_layout::Id, blot_error::Error {
    let timing = generator.work_timing.enter(blot_backend_backend_timing::Phase.layouts); let selected, error = generator.representations.store.fromType(generator.unit(unit_id), ty, mappings); timing.deinit();
    if error == blot_error::Error.out_of_memory { return 0, error; } if error != blot_error::Error.none { return 0, decline(generator, unit_id, span, Code.unresolved_type); } return selected, blot_error::Error.none;
}
fn codeLayout(generator: Generator&, unit_id: u32, ty: blot_check_types::Id, mappings: const Mapping[:], span: blot_check_core::Span) -> blot_backend_layout::Id, blot_error::Error {
    let timing = generator.work_timing.enter(blot_backend_backend_timing::Phase.layouts); let selected, error = generator.representations.store.fromTypePartial(generator.unit(unit_id), ty, mappings); timing.deinit();
    if error == blot_error::Error.out_of_memory { return 0, error; } if error != blot_error::Error.none { return 0, decline(generator, unit_id, span, Code.unresolved_type); } return selected, blot_error::Error.none;
}
fn internLayout(generator: Generator&, tag: blot_backend_layout::Tag, a: u32, b: u32, values: const u32[:]) -> blot_backend_layout::Id, blot_error::Error {
    let selected, error = generator.representations.store.intern(tag, a, b, values); if error == blot_error::Error.out_of_memory { return 0, error; } if error != blot_error::Error.none { return 0, decline(generator, 1, blot_check_core::Span {}, Code.complexity); } return selected, blot_error::Error.none;
}
fn internLayoutWithEffects(generator: Generator&, tag: blot_backend_layout::Tag, a: u32, b: u32, row: u32, values: const u32[:]) -> blot_backend_layout::Id, blot_error::Error {
    let selected, error = generator.representations.store.internWithEffects(tag, a, b, row, values); if error == blot_error::Error.out_of_memory { return 0, error; } if error != blot_error::Error.none { return 0, decline(generator, 1, blot_check_core::Span {}, Code.complexity); } return selected, blot_error::Error.none;
}
fn codeLayoutWithRows(generator: Generator&, unit_id: u32, ty: blot_check_types::Id, mappings: const Mapping[:], rows: const RowMapping[:], span: blot_check_core::Span) -> blot_backend_layout::Id, blot_error::Error {
    let timing = generator.work_timing.enter(blot_backend_backend_timing::Phase.layouts); let selected, error = generator.representations.store.fromTypeWithRows(generator.unit(unit_id), ty, mappings, rows, true); timing.deinit();
    if error == blot_error::Error.out_of_memory { return 0, error; } if error != blot_error::Error.none { return 0, decline(generator, unit_id, span, Code.unresolved_type); } return selected, blot_error::Error.none;
}
fn scalarWithRows(generator: Generator&, unit_id: u32, ty: blot_check_types::Id, mappings: const Mapping[:], rows: const RowMapping[:], span: blot_check_core::Span) -> Scalar, blot_error::Error {
    let selected, error = codeLayoutWithRows(generator, unit_id, ty, mappings, rows, span); if error != blot_error::Error.none { return 0, error; }
    let scalar = generator.representations.store.scalar(selected); if scalar.present { return scalar.value, blot_error::Error.none; } return blot_backend_runtime_ir::SC_pointer, blot_error::Error.none;
}
fn evaluationFailure(generator: Generator&) -> blot_error::Error {
    if generator.evaluator.diagnostic.present {
        let item = generator.evaluator.diagnostic.value; var code = item.code;
        if code == Code.unsupported || code == Code.cycle { code = Code.constant_expression; }
        var span = item.span;
        if code == Code.const_panic && !item.tag_origin && item.origins.len == 0 && generator.staging_trace.len == 0 { span = blot_check_core::Span {}; }
        let fresh = !generator.diagnostic.present; let result = decline(generator, item.unit, span, code); generator.diagnostic.value.detail = item.detail;
        if fresh { generator.diagnostic.value.dispatch = item.dispatch; generator.diagnostic.value.implementation_trace = item.implementation_trace; generator.diagnostic.value.related = item.related; if item.origins.len != 0 { generator.diagnostic.value.origins = item.origins; } }
        return result;
    }
    return decline(generator, 1, blot_check_core::Span {}, Code.constant_expression);
}
fn constant(generator: Generator&, target: blot_check_core::BindingRef, ty: blot_backend_layout::Id) -> Value, blot_error::Error {
    let timing = generator.work_timing.enter(blot_backend_backend_timing::Phase.constants);
    var scope = blot_support::none<blot_reuse_code_artifacts::Scope>();
    if generator.artifacts {
        let opened, error = generator.artifacts.enter(blot_reuse_code_artifacts::Request.constant { key: blot_reuse_code_artifacts::ConstantKey { target: target, ty: ty } });
        if error != blot_error::Error.none { timing.deinit(); return Value {}, error; } scope = blot_support::some(opened);
    }
    let value, error = constantScoped(generator, target, ty, scope);
    if scope.present { scope.value.deinit(); } timing.deinit(); return value, error;
}
fn constantScoped(generator: Generator&, target: blot_check_core::BindingRef, ty: blot_backend_layout::Id, scope: blot_support::Option<blot_reuse_code_artifacts::Scope>&) -> Value, blot_error::Error {
    let id, evaluated = generator.evaluator.richValue(target);
    if evaluated != blot_error::Error.none { if evaluated == blot_error::Error.out_of_memory { return Value {}, evaluated; } return Value {}, evaluationFailure(generator); }
    if generator.representations.store.node(ty).tag != blot_backend_layout::Tag.owning {
        let scalar = generator.evaluator.valueScalar(id);
        if scalar.present { if scope.present { let error = scope.value.completeValue(id, ty); if error != blot_error::Error.none { return Value {}, error; } } return scalar.value, blot_error::Error.none; }
    }
    let bits, serialized = generator.static_data.serialize(generator, id, ty, 0); if serialized != blot_error::Error.none { return Value {}, serialized; }
    if scope.present { let error = scope.value.completeValue(id, ty); if error != blot_error::Error.none { return Value {}, error; } }
    let scalar = generator.representations.store.scalar(ty); var kind = blot_backend_runtime_ir::SC_pointer; if scalar.present { kind = scalar.value; } return Value { scalar: kind, bits: bits }, blot_error::Error.none;
}
fn discardableClosure(generator: Generator&, owner: u32, catalog: u32) -> bool {
    let source = generator.unit(owner); let metadata = source.closures[catalog];
    if metadata.qualifier != 0 && source.binding(metadata.qualifier).scheme.obligations.len != 0 { return false; }
    let body = source.node(metadata.body); if body.tag == blot_check_core::Tag.constant || body.tag == blot_check_core::Tag.panic { return true; }
    if body.tag != blot_check_core::Tag.reference { return false; } let reference = source.reference(metadata.body);
    return (reference.unit == 0 || reference.unit == owner) && reference.binding == metadata.parameter.binding;
}
recursive fn discardableValue(generator: Generator&, id: blot_eval_core_eval::ValueId, depth: i64) -> bool {
    if depth >= 256 { return false; } let info = generator.evaluator.valueInfo(id);
    if info.kind == blot_eval_core_eval::ValueKind.closure {
        let metadata = generator.evaluator.closureInfo(id); let source = generator.unit(metadata.unit);
        if metadata.origin == blot_eval_core_eval::ClosureOrigin.named { let body .= source.body(metadata.identity); if body == null || body.scheme.obligations.len != 0 { return false; } }
        else if metadata.origin == blot_eval_core_eval::ClosureOrigin.anonymous { if !discardableClosure(generator, metadata.unit, metadata.identity) { return false; } }
        else if metadata.origin == blot_eval_core_eval::ClosureOrigin.operation { return false; }
    } else if info.kind != blot_eval_core_eval::ValueKind.scalar && info.kind != blot_eval_core_eval::ValueKind.array && info.kind != blot_eval_core_eval::ValueKind.list && info.kind != blot_eval_core_eval::ValueKind.cursor && info.kind != blot_eval_core_eval::ValueKind.product && info.kind != blot_eval_core_eval::ValueKind.record && info.kind != blot_eval_core_eval::ValueKind.nominal { return false; }
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
    let owner = (family >> 32) as u32; let declaration = family as! u32; let source = generator.unit(owner);
    for constructor in source.constructors {
        let nominal = source.nominal(constructor.nominal); if nominal.identity.unit != owner || nominal.identity.decl != declaration || constructor.tag != tag { continue; }
        let parameters = source.types.list(nominal.parameters); let arguments = generator.representations.store.children(ty);
        if parameters.len != arguments.len { return 0, decline(generator, owner, blot_check_core::Span {}, Code.unresolved_type); }
        if constructor.payload == 0 { return 1, blot_error::Error.none; } var mappings: Mapping[>..<] = [];
        for parameter, index in parameters { let error = mapType(generator, owner, mappings, parameter, arguments[index], blot_check_core::Span {}); if error != blot_error::Error.none { return 0, error; } }
        return codeLayout(generator, owner, constructor.payload, mappings, blot_check_core::Span {});
    }
    return 0, decline(generator, owner, blot_check_core::Span {}, Code.unresolved_type);
}
fn captureLayout(generator: Generator&, owner: u32, binding: blot_check_core::BindingId, value: blot_eval_core_eval::ValueId, mappings: Mapping[>..<]&, rows: RowMapping[>..<]&) -> blot_backend_layout::Id, blot_error::Error { let declaration = generator.unit(owner).binding(binding); return captureTypeLayout(generator, owner, declaration.ty, declaration.span, value, mappings, rows); }
fn captureTypeLayout(generator: Generator&, owner: u32, ty: blot_check_types::Id, span: blot_check_core::Span, value: blot_eval_core_eval::ValueId, mappings: Mapping[>..<]&, rows: RowMapping[>..<]&) -> blot_backend_layout::Id, blot_error::Error {
    let source = generator.unit(owner); let concrete, initial = generator.representations.store.fromTypeWithRows(source, ty, mappings, rows, false);
    if initial == blot_error::Error.none { return concrete, initial; } if initial == blot_error::Error.out_of_memory { return 0, initial; }
    let actual = generator.evaluator.valueEvidence(value);
    if actual != 0 {
        let selected, converted = generator.representations.fromEvidence(generator.evaluator.evidenceStore(), actual);
        if converted == blot_error::Error.out_of_memory { return 0, converted; } if converted != blot_error::Error.none { return 0, decline(generator, owner, span, Code.unresolved_type); }
        let error = mapTypeDepth(generator, owner, mappings, rows, ty, selected, span, 0); if error != blot_error::Error.none { return 0, error; }
    }
    return codeLayoutWithRows(generator, owner, ty, mappings, rows, span);
}
fn normalize(generator: Generator&, owner: u32, reference: blot_check_core::BindingRef) -> blot_check_core::BindingRef, blot_error::Error {
    var target = reference; if target.unit == 0 { target.unit = owner; }
    for step in 0..256 {
        if target.unit == 0 || target.unit > generator.units.len || target.binding == 0 || target.binding >= generator.unit(target.unit).bindings.len { return blot_check_core::BindingRef {}, decline(generator, owner, blot_check_core::Span {}, Code.unsupported); }
        let source = generator.unit(target.unit); let binding = source.binding(target.binding);
        if binding.kind == blot_check_core::BindingKind.external { let previous = target.unit; target = binding.target; if target.unit == 0 { target.unit = previous; } continue; }
        let body .= source.body(target.binding);
        if body != null { let tag = source.types.node(binding.ty).tag; if (tag == blot_check_types::Tag.function || tag == blot_check_types::Tag.forall) && body.parameters.len == 0 && source.node(body.root).tag == blot_check_core::Tag.reference { let previous = target.unit; target = source.reference(body.root); if target.unit == 0 { target.unit = previous; } continue; } }
        return target, blot_error::Error.none;
    }
    return blot_check_core::BindingRef {}, decline(generator, owner, blot_check_core::Span {}, Code.complexity);
}
fn mappingEvidence(generator: Generator&, mappings: const Mapping[:]) -> u32, blot_error::Error {
    var words: u32[>..<] = [];
    for mapping in mappings {
        if mapping.instance.decl != 0 { continue; }
        let actual, error = generator.representations.toEvidence(generator.evaluator.evidenceStore(), mapping.layout);
        if error == blot_error::Error.unresolved_type { continue; } if error == blot_error::Error.out_of_memory { return 0, error; } if error != blot_error::Error.none { return 0, decline(generator, 1, blot_check_core::Span {}, Code.unresolved_type); }
        words.append([mapping.variable, actual]);
    }
    let result, error = generator.evaluator.storage.evidence.intern(blot_eval_type_evidence::Tag.record, 0, 0, words);
    if error == blot_error::Error.out_of_memory { return 0, error; } if error != blot_error::Error.none { return 0, decline(generator, 1, blot_check_core::Span {}, Code.unresolved_type); } return result, blot_error::Error.none;
}
fn rowMappingEvidence(generator: Generator&, rows: const RowMapping[:]) -> u32, blot_error::Error {
    var entries: blot_reuse_substitution_keys::Entry[>..<] = [];
    for mapping in rows {
        if mapping.row == blot_backend_layout::unknown_row { continue; }
        let actual, error = generator.representations.rowToEvidence(generator.evaluator.evidenceStore(), mapping.row);
        if error == blot_error::Error.unresolved_type { continue; } if error == blot_error::Error.out_of_memory { return 0, error; } if error != blot_error::Error.none { return 0, decline(generator, 1, blot_check_core::Span {}, Code.unresolved_type); }
        entries.push(blot_reuse_substitution_keys::Entry { variable: mapping.variable, value: actual });
    }
    let result, error = generator.representations.row_keys.intern(entries);
    if error == blot_error::Error.out_of_memory { return 0, error; } if error != blot_error::Error.none { return 0, decline(generator, 1, blot_check_core::Span {}, Code.unresolved_type); } return result, blot_error::Error.none;
}
fn loadSemanticRows(generator: Generator&, mappings: const blot_eval_type_evidence::RowMapping[:], rows: RowMapping[>..<]&) -> blot_error::Error {
    for mapping in mappings {
        let concrete, error = generator.representations.rowFromEvidence(generator.evaluator.evidenceStore(), mapping.evidence);
        if error == blot_error::Error.out_of_memory { return error; } if error != blot_error::Error.none { return decline(generator, 1, blot_check_core::Span {}, Code.unresolved_type); }
        rows.push(RowMapping { variable: mapping.variable, row: concrete });
    }
    return blot_error::Error.none;
}
fn capturedTemplate(generator: Generator&, key: u32, binding: blot_check_core::BindingId) -> blot_support::Option<CapturedTemplate> {
    for entry in generator.representations.template_keys.get(key) { if entry.variable == binding { return blot_support::some(generator.planning.template_catalog[entry.value - 1]); } } return blot_support::none<CapturedTemplate>();
}
fn capturedStatic(generator: Generator&, key: u32, binding: blot_check_core::BindingId) -> blot_support::Option<blot_eval_core_eval::ValueId> {
    for entry in generator.representations.static_keys.get(key) { if entry.variable == binding { return blot_support::some(entry.value); } } return blot_support::none<blot_eval_core_eval::ValueId>();
}
fn directCallableEnvironment(generator: Generator&, ty: blot_backend_layout::Id, applied: i64) -> bool {
    var current = ty; var retained = blot_support::none<blot_backend_layout::Id>();
    for index in 0..applied { let arrow = generator.representations.store.node(current); if arrow.tag != blot_backend_layout::Tag.function { return false; } current = arrow.b; if generator.representations.store.node(arrow.a).tag == blot_backend_layout::Tag.erased_proof { continue; } if retained.present { return false; } retained = blot_support::some(arrow.a); }
    return retained.present && layoutRole(generator, retained.value) == blot_backend_runtime_ir::ROLE_reference;
}
let max_parameters: i64 = blot_reuse_code_artifacts::max_parameters;
fn signature(generator: Generator&, target: blot_check_core::BindingRef, ty: blot_check_types::Id, source_id: u32, mappings: const Mapping[:], rows: const RowMapping[:], span: blot_check_core::Span, complete: bool) -> Key, blot_error::Error {
    let normalized, normalized_error = normalize(generator, source_id, target); if normalized_error != blot_error::Error.none { return Key {}, normalized_error; }
    var key = Key { target: normalized }; let root, root_error = functionRoot(generator, source_id, ty, span); if root_error != blot_error::Error.none { return key, root_error; } var current = root;
    var instances: blot_check_types::NominalIdentity[max_parameters] = [blot_check_types::NominalIdentity {}; max_parameters]; var has_instances = false;
    let producer .= generator.unit(key.target.unit).body(key.target.binding); var limit = max_parameters; if producer != null && producer.parameters.len != 0 { limit = producer.parameters.len; }
    while generator.unit(source_id).types.node(current).tag == blot_check_types::Tag.function && key.count < limit {
        if key.count == max_parameters { return key, decline(generator, source_id, span, Code.complexity); }
        let n = generator.unit(source_id).types.node(current); let input = generator.unit(source_id).types.node(n.a);
        if input.tag == blot_check_types::Tag.scoped {
            has_instances = true; instances[key.count] = blot_check_types::selectionAtom(generator.unit(source_id).types, blot_backend_layout::mappedInstance(blot_check_types::NominalIdentity { unit: input.b, decl: input.c }, mappings));
        } else if has_instances { instances[key.count] = blot_check_types::NominalIdentity {}; }
        if complete { let parameter, error = typeLayout(generator, source_id, n.a, mappings, span); if error != blot_error::Error.none { return key, error; } key.parameters[key.count] = parameter; }
        else { let parameter, error = codeLayoutWithRows(generator, source_id, n.a, mappings, rows, span); if error != blot_error::Error.none { return key, error; } key.parameters[key.count] = parameter; }
        let effects, error = generator.representations.store.rowFromType(generator.unit(source_id), n.c, mappings, rows, !complete);
        if error == blot_error::Error.out_of_memory { return key, error; } if error != blot_error::Error.none { return key, decline(generator, source_id, span, Code.unresolved_type); }
        key.effects[key.count] = effects; key.count++; current = n.b;
    }
    if has_instances {
        let identity, error = generator.representations.instance_arguments.intern(instances[..key.count]);
        if error == blot_error::Error.out_of_memory { return key, error; } if error != blot_error::Error.none { return key, decline(generator, source_id, span, Code.complexity); } key.instance_arguments = identity;
    }
    if complete { let result, error = typeLayout(generator, source_id, current, mappings, span); if error != blot_error::Error.none { return key, error; } key.result = result; }
    else { let result, error = codeLayoutWithRows(generator, source_id, current, mappings, rows, span); if error != blot_error::Error.none { return key, error; } key.result = result; }
    return key, blot_error::Error.none;
}
fn entrySignature(generator: Generator&, target: blot_check_core::BindingRef, ty: blot_check_types::Id, span: blot_check_core::Span) -> Key, blot_error::Error {
    let physical, initial_error = generator.representations.store.fromType(generator.unit(target.unit), ty, []);
    if initial_error == blot_error::Error.none { return signature(generator, target, ty, target.unit, [], [], span, true); }
    if initial_error == blot_error::Error.out_of_memory { return Key {}, initial_error; }
    let value, evaluated = generator.evaluator.richValue(target);
    if evaluated != blot_error::Error.none { if evaluated == blot_error::Error.out_of_memory { return Key {}, evaluated; } return Key {}, evaluationFailure(generator); }
    let inferred, inference_error = generator.evaluator.inferEntryClosure(value);
    if inference_error != blot_error::Error.none {
        if inference_error == blot_error::Error.out_of_memory { return Key {}, inference_error; }
        if inference_error == blot_error::Error.declined && generator.evaluator.diagnostic.present && generator.evaluator.diagnostic.value.code == Code.unsupported { return Key {}, decline(generator, target.unit, span, Code.unresolved_type); }
        return Key {}, evaluationFailure(generator);
    }
    if !inferred.present { return Key {}, decline(generator, target.unit, span, Code.entry_type); }
    let concrete, converted = generator.representations.fromEvidence(generator.evaluator.evidenceStore(), generator.evaluator.valueEvidence(inferred.value));
    if converted == blot_error::Error.out_of_memory { return Key {}, converted; } if converted != blot_error::Error.none { return Key {}, decline(generator, target.unit, span, Code.unresolved_type); }
    var mappings: Mapping[>..<] = []; var rows: RowMapping[>..<] = [];
    let mapped = mapTypeDepth(generator, target.unit, mappings, rows, ty, concrete, span, 0); if mapped != blot_error::Error.none { return Key {}, mapped; }
    let physical_final, checked = generator.representations.store.fromTypeWithRows(generator.unit(target.unit), ty, mappings, rows, false);
    if checked == blot_error::Error.out_of_memory { return Key {}, checked; } if checked != blot_error::Error.none { return Key {}, decline(generator, target.unit, span, Code.unresolved_type); }
    return signature(generator, target, ty, target.unit, mappings, rows, span, false);
}
fn seedNamedInstance(generator: Generator&, key: Key, mappings: Mapping[>..<]&) -> blot_error::Error {
    if key.instance_arguments == 0 { return blot_error::Error.none; } let source = generator.unit(key.target.unit); let binding = source.binding(key.target.binding);
    let initial, error = functionRoot(generator, key.target.unit, binding.ty, binding.span); if error != blot_error::Error.none { return error; } var root = initial;
    for instance in generator.representations.instance_arguments.get(key.instance_arguments) {
        let arrow = source.types.node(root); if arrow.tag != blot_check_types::Tag.function { return decline(generator, key.target.unit, binding.span, Code.unresolved_type); } root = arrow.b;
        let input = source.types.node(arrow.a); if input.tag != blot_check_types::Tag.scoped || input.b != 0 || instance.unit == 0 { continue; }
        var found = false; for entry in mappings { if entry.variable != input.c { continue; } if entry.instance != instance { return decline(generator, key.target.unit, binding.span, Code.unresolved_type); } found = true; break; }
        if !found { mappings.push(Mapping { variable: input.c, layout: blot_backend_layout::erased, instance: instance }); }
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
        named value => return function(generator, value.key), closure value => return closureFunction(generator, value.key), callable value => return callable(generator, value.key),
        constructor value => return constructorFunction(generator, value.key), primitive value => return primitiveFunction(generator, value.key), operation value => return operationFunction(generator, value.key), host value => return hostFunction(generator, value.key),
        constant value => return 0, blot_error::Error.invalid_function_reference, runtime_global value => return 0, blot_error::Error.invalid_function_reference,
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
fn publishRetainedStatic(generator: Generator&, function_id: u32) -> blot_error::Error { generator.static_data.closures.push(function_id); return blot_error::Error.none; }
fn publishRetainedResult(generator: Generator&, request: blot_reuse_code_artifacts::Request, template: blot_support::Option<u32>) -> blot_error::Error {
    if !template.present { return blot_error::Error.none; }
    match request { named value => generator.planning.template_results.insert(value.key, template.value), closure value => generator.planning.closure_template_results.insert(value.key, template.value), _ => return blot_error::Error.invalid_function_reference }
    return blot_error::Error.none;
}
fn unusedAggregate(generator: Generator&, unit_id: u32, binding: blot_check_core::BindingId) -> bool, blot_error::Error {
    block { let known = generator.planning.discard_proofs.get(unit_id); if known { return known.admits(binding), blot_error::Error.none; } }
    let proof = blot_backend_discarded_bindings::init(generator.planning.discard_flags, generator.unit(unit_id), unit_id);
    let admitted = proof.admits(binding); generator.planning.discard_proofs.insert(unit_id, proof); return admitted, blot_error::Error.none;
}
fn specializer(generator: Generator&) -> blot_eval_specialization::Service, blot_error::Error {
    let bridge, error = generator.representations.representationBridge(generator.evaluator.evidenceStore()); if error != blot_error::Error.none { return default<blot_eval_specialization::Service>(), error; }
    return blot_eval_specialization::Service { timing: generator.work_timing, units: generator.units, evaluator: generator.evaluator, layouts: generator.representations.store, bridge: bridge, refinement_stats: generator.refinement_stats, refinement_regions: generator.work.refinement_regions, cache: generator }, blot_error::Error.none;
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
        evaluation => return evaluationFailure(generator), complexity => return decline(generator, failure.unit, failure.span, Code.complexity), unresolved_type => return decline(generator, failure.unit, failure.span, Code.unresolved_type),
    }
}
fn mapType(generator: Generator&, unit_id: u32, mappings: Mapping[>..<]&, ty: blot_check_types::Id, concrete: u32, span: blot_check_core::Span) -> blot_error::Error {
    let service, error = specializer(generator); if error != blot_error::Error.none { return error; } let mapped = service.mapType(unit_id, mappings, ty, concrete, span); if mapped != blot_error::Error.none { return specializationFailure(generator, service, mapped); } return blot_error::Error.none;
}
fn mapTypeDepth(generator: Generator&, unit_id: u32, mappings: Mapping[>..<]&, rows: RowMapping[>..<]&?, ty: blot_check_types::Id, concrete: u32, span: blot_check_core::Span, depth: i64) -> blot_error::Error {
    let service, error = specializer(generator); if error != blot_error::Error.none { return error; } let mapped = service.mapTypeDepth(unit_id, mappings, rows, ty, concrete, span, depth); if mapped != blot_error::Error.none { return specializationFailure(generator, service, mapped); } return blot_error::Error.none;
}
fn mapFunctionResult(generator: Generator&, unit_id: u32, mappings: Mapping[>..<]&, rows: RowMapping[>..<]&, ty: blot_check_types::Id, concrete: u32, span: blot_check_core::Span) -> blot_error::Error {
    let service, error = specializer(generator); if error != blot_error::Error.none { return error; } let mapped = service.mapFunctionResult(unit_id, mappings, rows, ty, concrete, span, 0); if mapped != blot_error::Error.none { return specializationFailure(generator, service, mapped); } return blot_error::Error.none;
}
fn mapRow(generator: Generator&, unit_id: u32, mappings: Mapping[>..<]&, rows: RowMapping[>..<]&, source_row: u32, actual_row: u32, span: blot_check_core::Span, covariant: bool) -> blot_error::Error {
    let service, error = specializer(generator); if error != blot_error::Error.none { return error; } let mapped = service.mapRow(unit_id, mappings, rows, source_row, actual_row, span, covariant); if mapped != blot_error::Error.none { return specializationFailure(generator, service, mapped); } return blot_error::Error.none;
}
fn refineMappings(generator: Generator&, unit_id: u32, root: blot_reuse_refinement_receipt::Root, expected: u32, mappings: Mapping[>..<]&, rows: RowMapping[>..<]&, span: blot_check_core::Span) -> blot_error::Error {
    let service, error = specializer(generator); if error != blot_error::Error.none { return error; } let mapped = service.refineMappings(unit_id, root, expected, mappings, rows, span); if mapped != blot_error::Error.none { return specializationFailure(generator, service, mapped); } return blot_error::Error.none;
}
fn refineMappingsCaptures(generator: Generator&, unit_id: u32, root: blot_reuse_refinement_receipt::Root, expected: u32, mappings: Mapping[>..<]&, rows: RowMapping[>..<]&, span: blot_check_core::Span, captures: const blot_eval_core_eval::RetainedCapture[:]) -> blot_error::Error {
    let service, error = specializer(generator); if error != blot_error::Error.none { return error; } let mapped = service.refineMappingsCaptures(unit_id, root, expected, mappings, rows, span, captures); if mapped != blot_error::Error.none { return specializationFailure(generator, service, mapped); } return blot_error::Error.none;
}
fn refineAccessorMappings(generator: Generator&, unit_id: u32, catalog: u32, expected: u32, mappings: Mapping[>..<]&, rows: RowMapping[>..<]&, span: blot_check_core::Span, captures: const blot_eval_core_eval::RetainedCapture[:]) -> blot_error::Error {
    var projection = StaticCodeProjection { layouts: generator.representations.store, mappings: mappings }; let service, error = specializer(generator); if error != blot_error::Error.none { return error; }
    var selected = blot_eval_core_eval::CodeProjection.static_code { projection }; service.code_projection .= selected;
    let mapped = service.refineMappingsCaptures(unit_id, blot_reuse_refinement_receipt::Root.closure { unit: unit_id, catalog: catalog }, expected, mappings, rows, span, captures);
    if mapped != blot_error::Error.none { return specializationFailure(generator, service, mapped); } return blot_error::Error.none;
}
fn mapCapturedFunction(generator: Generator&, unit_id: u32, function_type: blot_check_types::Id, expected: u32, mappings: Mapping[>..<]&, rows: RowMapping[>..<]&, span: blot_check_core::Span) -> blot_error::Error {
    let source = unit(generator, unit_id).types.node(function_type); let actual = generator.representations.store.node(expected);
    if source.tag != blot_check_types::Tag.function || actual.tag != blot_backend_layout::Tag.function { return decline(generator, unit_id, span, Code.unresolved_type); }
    let a = mapTypeDepth(generator, unit_id, mappings, rows, source.a, actual.a, span, 0); if a != blot_error::Error.none { return a; }
    let b = mapTypeDepth(generator, unit_id, mappings, rows, source.b, actual.b, span, 0); if b != blot_error::Error.none { return b; }
    return mapRow(generator, unit_id, mappings, rows, source.c, actual.c, span, true);
}
fn completedQueryLookup(generator: Generator&, session: blot_eval_core_eval::Session&, input: u32, expected: u32) -> blot_support::Option<u32>, blot_error::Error {
    if !(session .== generator.evaluator) { return blot_support::none<u32>(), blot_error::Error.none; }
    if generator.query_state != null { return generator.query_state.lookup(generator, input, expected); } return blot_support::none<u32>(), blot_error::Error.none;
}
fn completedMemberLookup(generator: Generator&, session: blot_eval_core_eval::Session&, target: blot_check_core::BindingRef, input: u32, expected: u32) -> blot_support::Option<u32>, blot_error::Error {
    if !(session .== generator.evaluator) { return blot_support::none<u32>(), blot_error::Error.none; }
    if generator.query_state != null { return generator.query_state.lookupMember(generator, target, input, expected); } return blot_support::none<u32>(), blot_error::Error.none;
}
fn lookupSpecialization(generator: Generator&, session: blot_eval_core_eval::Session&, input: u32, expected: u32) -> blot_support::Option<u32>, blot_error::Error { completedQueryLookup(generator, session, input, expected) }
fn lookupMemberSpecialization(generator: Generator&, session: blot_eval_core_eval::Session&, target: blot_check_core::BindingRef, input: u32, expected: u32) -> blot_support::Option<u32>, blot_error::Error { completedMemberLookup(generator, session, target, input, expected) }
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
    let generator .= emitter.generator; let source = unit(generator, context.key.target.unit); let body .= context.body; let key = context.key;
    for parameter, index in source.bodyParameters(body) {
        if parameter.binding == 0 { continue; } let local = context.parameter_locals[index]; if local == 4294967295 { continue; }
        let retained = capturedTemplate(generator, key.templates, parameter.binding);
        if retained.present {
            let template = retained.value; var environment = blot_support::none<u32>(); if template.has_environment { environment = blot_support::some(local); }
            emitter.templates.insert(parameter.binding, blot_backend_backend_emission::Template { scalar_environment: template.scalar_environment, callable_instances: template.callable_instances, staged: template.staged, unit: template.unit, node: template.node, environment: environment, captures: template.captures, templates: template.templates, computation: template.computation, evidence: template.evidence, rows: template.rows });
        } else { emitter.locals.insert(parameter.binding, local); }
    }
    if key.dictionaries {
        let owner = blot_check_dictionary_owner::forBinding(source, body.binding); assert(owner.present);
        let error = emitter.installDictionary(body.root, context.runtime_count + 1, owner.value); if error != blot_error::Error.none { return error; }
    }
    if key.template_result {
        let error = emitter.bodyExpression(context.root, 0, true); if error != blot_error::Error.none { return error; }
        if !emitter.result_template.present { return fail(generator, key.target.unit, body.root, Code.unresolved_type); } generator.planning.template_results.insert(key, emitter.result_template.value);
    } else {
        let error = emitter.bodyExpression(context.root, 0, false); if error != blot_error::Error.none { return error; }
        if source.types.node(source.typeOf(body.root)).tag == blot_check_types::Tag.never { return emitter.emit(blot_backend_runtime_ir::OP_unreachable_, 0); }
    }
    return blot_error::Error.none;
}
fn namedAlias(generator: Generator&, key: Key, body: const blot_check_core::Body&, function_id: u32, scope: blot_support::Option<blot_reuse_code_artifacts::Scope>&) -> u32, blot_error::Error {
    let unit_id = key.target.unit; let source = unit(generator, unit_id); var full = key.result; var reverse = key.count as i64;
    while reverse > 0 { reverse--; let ty, error = internLayoutWithEffects(generator, blot_backend_layout::Tag.function, key.parameters[reverse], full, key.effects[reverse], []); if error != blot_error::Error.none { return 0, error; } full = ty; }
    if source.binding(key.target.binding).has_explicit {
        var mappings: Mapping[>..<] = []; var rows: RowMapping[>..<] = [];
        let error = refineMappings(generator, unit_id, blot_reuse_refinement_receipt::Root.body { key.target }, full, mappings, rows, body.span); if error != blot_error::Error.none { return 0, error; }
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
        let arrow = generator.representations.store.node(ty); if arrow.tag != blot_backend_layout::Tag.function { return 0, decline(generator, unit_id, body.span, Code.unresolved_type); }
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
        if generator.request_owner.present { let guarded = blot_runtime_request_runtime::guard(generator.module, function_id, generator.request_owner.value, []); if guarded != blot_error::Error.none { return 0, guarded; } }
        ty = arrow.b;
    }
    if scope.present { let completed = scope.value.complete(function_id, lookupValue(generator.planning.template_results, key)); if completed != blot_error::Error.none { return 0, completed; } }
    generator.planning.startup_facts.complete(function_id); return function_id, blot_error::Error.none;
}
fn function(generator: Generator&, key: Key) -> u32, blot_error::Error {
    let stage = generator.evaluator.enterInferenceStage(blot_work_counters::InferenceStage.specialization); defer { stage.deinit(); }
    var scope = blot_support::none<blot_reuse_code_artifacts::Scope>();
    if generator.artifacts != null { let entered, error = generator.artifacts.enter(blot_reuse_code_artifacts::Request.named { key }); if error != blot_error::Error.none { return 0, error; } scope = blot_support::some(entered); }
    defer { if scope.present { scope.value.deinit(); } }
    block {
        let existing = generator.planning.instances.get(key);
        if existing {
            let error = generator.planning.startup_facts.request(existing, blot_backend_startup_emission_facts::Kind.named, key.target.unit, key.target.binding, true); if error != blot_error::Error.none { return 0, error; }
            if scope.present { let hit = scope.value.hit(existing); if hit != blot_error::Error.none { return 0, hit; } } return existing, blot_error::Error.none;
        }
    }
    if generator.retained != null {
        let job, error = findRetained(generator, generator.retained, blot_reuse_code_artifacts::Request.named { key }); if error != blot_error::Error.none { return 0, error; }
        if job.present {
            var actor: blot_reuse_code_artifacts::Scope&? = null; if scope.present { actor .= scope.value; }
            let function_id, replayed = reconstructRetained(generator, generator.retained, job.value, blot_reuse_code_artifacts::Request.named { key }, actor); if replayed != blot_error::Error.none { return 0, replayed; }
            let requested = generator.planning.startup_facts.request(function_id, blot_backend_startup_emission_facts::Kind.named, key.target.unit, key.target.binding, true); if requested != blot_error::Error.none { return 0, requested; }
            generator.planning.startup_facts.complete(function_id); return function_id, blot_error::Error.none;
        }
    }
    generator.work.fresh_named++; let unit_id = key.target.unit; let source = unit(generator, unit_id); let body .= source.body(key.target.binding);
    if body == null { return 0, decline(generator, unit_id, source.binding(key.target.binding).span, Code.unsupported); }
    if body.is_function && body.parameters.len != key.count { return 0, decline(generator, unit_id, body.span, Code.unsupported); }
    if generator.instance_depth >= 256 || generator.planning.instances.count >= 65536 { return 0, decline(generator, unit_id, body.span, Code.complexity); }
    generator.instance_depth++; defer { generator.instance_depth--; }
    var parameters: blot_backend_runtime_ir::ValueType[18]; var roles: blot_backend_runtime_ir::Role[18]; var parameter_locals: u32[16] = [4294967295; 16]; var runtime_count: u32 = 0;
    for item, index in key.parameters[..key.count] {
        if generator.representations.store.node(item).tag == blot_backend_layout::Tag.erased_proof { continue; }
        parameter_locals[index] = runtime_count; parameters[runtime_count] = generator.representations.store.machine(item); roles[runtime_count] = layoutRole(generator, item);
        if body.is_function { let template = capturedTemplate(generator, key.templates, source.bodyParameters(body)[index].binding); if template.present && template.value.scalar_environment { roles[runtime_count] = blot_backend_runtime_ir::ROLE_scalar; } }
        runtime_count++;
    }
    if !body.is_function && runtime_count != key.count { return 0, decline(generator, unit_id, body.span, Code.unsupported); }
    parameters[runtime_count] = blot_backend_runtime_ir::VT_i32; roles[runtime_count] = blot_backend_runtime_ir::ROLE_reference; var machine_count = runtime_count + 1;
    if key.dictionaries {
        if !blot_check_dictionary_owner::forBinding(source, body.binding).present { return 0, decline(generator, unit_id, body.span, Code.unsupported); }
        parameters[machine_count] = blot_backend_runtime_ir::VT_i32; roles[machine_count] = blot_backend_runtime_ir::ROLE_reference; machine_count++;
    }
    let function_id, added = generator.module.addTypedFunction(parameters[..machine_count], resultMachine(generator, key.result), bodyResultRole(generator, key.result, unit_id, body.root)); if added != blot_error::Error.none { return 0, added; }
    let described = setParameterRoles(generator, function_id, blot_backend_runtime_ir::packParameterRoles(roles[..machine_count]), blot_support::some(runtime_count as u16)); if described != blot_error::Error.none { return 0, described; }
    generator.planning.instances.insert(key, function_id);
    if scope.present { let reserved = scope.value.reserve(function_id); if reserved != blot_error::Error.none { return 0, reserved; } }
    let requested = generator.planning.startup_facts.request(function_id, blot_backend_startup_emission_facts::Kind.named, unit_id, key.target.binding, false); if requested != blot_error::Error.none { return 0, requested; }
    let caller = generator.planning.startup_facts.active; generator.planning.startup_facts.active = function_id; defer { generator.planning.startup_facts.active = caller; }
    if !body.is_function { return namedAlias(generator, key, body, function_id, scope); }
    let service, service_error = specializer(generator); if service_error != blot_error::Error.none { return 0, service_error; }
    var mappings: Mapping[>..<] = []; var rows: RowMapping[>..<] = [];
    let resolved, resolved_error = service.named(key, generator.representations.instance_arguments.get(key.instance_arguments), mappings, rows);
    if resolved_error != blot_error::Error.none { return 0, specializationFailure(generator, service, resolved_error); }
    if key.dictionaries {
        let owner = blot_check_dictionary_owner::forBinding(source, body.binding); if !owner.present { return 0, decline(generator, unit_id, body.span, Code.unsupported); }
        let error = blot_backend_dictionary_layout::bindOwner(source, generator.representations.store, mappings, owner.value, 0, owner.value.formals(source), false);
        if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0, error; } return 0, fail(generator, unit_id, body.root, Code.unresolved_type); }
    }
    var context = NamedEmission { key, body, parameter_locals, runtime_count, resolved.root };
    let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { generator: generator, unit_id: unit_id, function_id: function_id, provider_local: blot_support::some(runtime_count), mappings: mappings, row_mappings: rows, factory_template: key.template_result }, context, emitNamedOwner);
    if emitted != blot_error::Error.none { return 0, emitted; }
    if scope.present {
        let solved = scope.value.solved(mappings, rows, generator.representations.template_keys.get(key.templates)); if solved != blot_error::Error.none { return 0, solved; }
        let completed = scope.value.complete(function_id, lookupValue(generator.planning.template_results, key)); if completed != blot_error::Error.none { return 0, completed; }
    }
    generator.planning.startup_facts.complete(function_id); return function_id, blot_error::Error.none;
}

fn lookupValue<K,V>(map: const dictionary<K,V>&, key: K) -> blot_support::Option<V> { let value = map.get(key); if value { return blot_support::some(value); } return blot_support::none<V>(); }
fn captureTemplate(generator: Generator&, template: blot_backend_backend_emission::Template) -> u32, blot_error::Error {
    let retained = CapturedTemplate { unit: template.unit, node: template.node, captures: template.captures, templates: template.templates, staged: template.staged, has_environment: template.environment.present, scalar_environment: template.scalar_environment, computation: template.computation, evidence: template.evidence, rows: template.rows, callable_instances: template.callable_instances };
    block { let existing = generator.planning.template_instances.get(retained); if existing { return existing, blot_error::Error.none; } }
    if generator.planning.template_catalog.len >= 4294967295 { return 0, blot_error::Error.module_too_large; }
    let id = (generator.planning.template_catalog.len + 1) as u32; generator.planning.template_catalog.push(retained); generator.planning.template_instances.insert(retained, id); return id, blot_error::Error.none;
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
    if depth >= 256 { return default<blot_eval_core_eval::RetainedCapture>(), fail(generator, template.unit, template.node, Code.complexity); }
    var rows: blot_eval_type_evidence::RowMapping[>..<] = []; for row in generator.representations.row_keys.get(template.rows) { rows.push(blot_eval_type_evidence::RowMapping { row.variable, row.value }); }
    var children: blot_eval_core_eval::RetainedCapture[>..<] = []; var values: blot_eval_core_eval::RetainedValue[>..<] = []; var published = false;
    defer { if !published { for child in children { releaseRetainedCapture(child); } } }
    let source = unit(generator, template.unit); let n = source.node(template.node);
    if n.tag == blot_check_core::Tag.closure {
        let capture_list = source.extra[source.closures[n.a].captures.start..source.closures[n.a].captures.start + source.closures[n.a].captures.len];
        for captured, index in capture_list {
            let child = capturedTemplate(generator, template.templates, captured);
            if child.present { let value, error = retainedCapture(generator, captured, child.value, depth + 1); if error != blot_error::Error.none { return default<blot_eval_core_eval::RetainedCapture>(), error; } children.push(value); }
            else if index < generator.representations.store.children(template.captures).len {
                let actual, error = generator.representations.toEvidence(generator.evaluator.evidenceStore(), generator.representations.store.children(template.captures)[index]);
                if error != blot_error::Error.none { if error == blot_error::Error.unresolved_type { continue; } if error == blot_error::Error.out_of_memory { return default<blot_eval_core_eval::RetainedCapture>(), error; } return default<blot_eval_core_eval::RetainedCapture>(), fail(generator, template.unit, template.node, Code.unresolved_type); }
                values.push(blot_eval_core_eval::RetainedValue { captured, actual });
            }
        }
    }
    let owned_rows = retained_rows.alloc_slice(rows.len); for row, index in rows { owned_rows[index] = row; }
    let owned_values = retained_values.alloc_slice(values.len); for value, index in values { owned_values[index] = value; }
    let owned_children = retained_children.alloc_slice(children.len); for child, index in children { owned_children[index] = child; }
    published = true; return blot_eval_core_eval::RetainedCapture { binding: binding, unit: template.unit, node: template.node, mappings: template.evidence, rows: owned_rows, values: owned_values, captures: owned_children, computation: template.computation }, blot_error::Error.none;
}
fn resolveClosureMappings(generator: Generator&, key: blot_reuse_code_artifacts::ClosureKey, mappings: Mapping[>..<]&, rows: RowMapping[>..<]&) -> blot_error::Error {
    let source = unit(generator, key.unit); let metadata = source.closures[key.catalog]; let captures = source.extra[metadata.captures.start..metadata.captures.start + metadata.captures.len]; let fn_type = generator.representations.store.node(key.ty);
    for entry in generator.representations.row_keys.get(key.rows) {
        let concrete, error = generator.representations.rowFromEvidence(generator.evaluator.evidenceStore(), entry.value); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return error; } return fail(generator, key.unit, metadata.body, Code.unresolved_type); }
        rows.push(RowMapping { entry.variable, concrete });
    }
    if key.evidence != 0 {
        let words = generator.evaluator.storage.evidence.children(key.evidence); var index: i64 = 0;
        while index < words.len {
            let concrete, error = generator.representations.fromEvidence(generator.evaluator.evidenceStore(), words[index + 1]); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return error; } return fail(generator, key.unit, metadata.body, Code.unresolved_type); }
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
    var hints: blot_eval_core_eval::RetainedCapture[>..<] = []; defer { for hint in hints { releaseRetainedCapture(hint); } }
    for binding in captures {
        let captured = capturedStatic(generator, key.static_values, binding);
        if captured.present { hints.push(blot_eval_core_eval::RetainedCapture { value: captured.value, binding: binding, unit: key.unit, node: 0 }); }
        else { let template = capturedTemplate(generator, key.templates, binding); if template.present { let hint, error = retainedCapture(generator, binding, template.value, 0); if error != blot_error::Error.none { return error; } hints.push(hint); } }
    }
    if key.parameter_template != 0 { let hint, error = retainedCapture(generator, metadata.parameter.binding, generator.planning.template_catalog[key.parameter_template - 1], 0); if error != blot_error::Error.none { return error; } hints.push(hint); }
    return refineMappingsCaptures(generator, key.unit, blot_reuse_refinement_receipt::Root.closure { key.unit, key.catalog }, key.ty, mappings, rows, source.span(metadata.body), hints);
}
fn templateMetadata(template: CapturedTemplate, local: u32) -> blot_backend_backend_emission::Template {
    var environment = blot_support::none<u32>(); if template.has_environment { environment = blot_support::some(local); }
    return blot_backend_backend_emission::Template { scalar_environment: template.scalar_environment, callable_instances: template.callable_instances, staged: template.staged, unit: template.unit, node: template.node, environment: environment, captures: template.captures, templates: template.templates, computation: template.computation, evidence: template.evidence, rows: template.rows };
}
fn enterScope(generator: Generator&, request: blot_reuse_code_artifacts::Request) -> blot_support::Option<blot_reuse_code_artifacts::Scope>, blot_error::Error {
    if generator.artifacts == null { return blot_support::none<blot_reuse_code_artifacts::Scope>(), blot_error::Error.none; }
    let entered, error = generator.artifacts.enter(request); if error != blot_error::Error.none { return blot_support::none<blot_reuse_code_artifacts::Scope>(), error; } return blot_support::some(entered), blot_error::Error.none;
}
struct ClosureEmission { key: blot_reuse_code_artifacts::ClosureKey }
fn emitClosureOwner(context: ClosureEmission&, emitter: blot_backend_backend_emission::Owner&) -> blot_error::Error {
    let generator .= emitter.generator; let key = context.key; let source = unit(generator, key.unit); let metadata = source.closures[key.catalog]; let captures = source.extra[metadata.captures.start..metadata.captures.start + metadata.captures.len];
    if metadata.parameter.binding != 0 {
        if key.parameter_template != 0 { emitter.templates.insert(metadata.parameter.binding, templateMetadata(generator.planning.template_catalog[key.parameter_template - 1], 1)); }
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
        if source.types.node(metadata.function_type).tag != blot_check_types::Tag.forall || source.types.quantifierGoals(metadata.function_type).len == 0 { return decline(generator, key.unit, source.span(metadata.body), Code.unsupported); }
        let installed = emitter.installUniversalDictionary(metadata.body, 3, metadata.function_type); if installed != blot_error::Error.none { return installed; }
    }
    if key.template_result {
        let error = emitter.bodyExpression(metadata.body, 0, true); if error != blot_error::Error.none { return error; }
        if !emitter.result_template.present { return fail(generator, key.unit, metadata.body, Code.unresolved_type); } generator.planning.closure_template_results.insert(key, emitter.result_template.value);
    } else {
        let error = emitter.bodyExpression(metadata.body, 0, false); if error != blot_error::Error.none { return error; }
        if source.types.node(source.typeOf(metadata.body)).tag == blot_check_types::Tag.never { return emitter.emit(blot_backend_runtime_ir::OP_unreachable_, 0); }
    }
    return blot_error::Error.none;
}
fn closureFunction(generator: Generator&, key: blot_reuse_code_artifacts::ClosureKey) -> u32, blot_error::Error {
    let stage = generator.evaluator.enterInferenceStage(blot_work_counters::InferenceStage.specialization); defer { stage.deinit(); }
    let scope, scope_error = enterScope(generator, blot_reuse_code_artifacts::Request.closure { key }); if scope_error != blot_error::Error.none { return 0, scope_error; } defer { if scope.present { scope.value.deinit(); } }
    block {
        let existing = generator.planning.closures.get(key);
        if existing { let error = generator.planning.startup_facts.request(existing, blot_backend_startup_emission_facts::Kind.anonymous, key.unit, key.catalog, true); if error != blot_error::Error.none { return 0, error; } if scope.present { let hit = scope.value.hit(existing); if hit != blot_error::Error.none { return 0, hit; } } return existing, blot_error::Error.none; }
    }
    if key.staged == 0 && generator.retained != null {
        let job, error = findRetained(generator, generator.retained, blot_reuse_code_artifacts::Request.closure { key }); if error != blot_error::Error.none { return 0, error; }
        if job.present {
            var actor: blot_reuse_code_artifacts::Scope&? = null; if scope.present { actor .= scope.value; }
            let function_id, rebuilt = reconstructRetained(generator, generator.retained, job.value, blot_reuse_code_artifacts::Request.closure { key }, actor); if rebuilt != blot_error::Error.none { return 0, rebuilt; }
            let requested = generator.planning.startup_facts.request(function_id, blot_backend_startup_emission_facts::Kind.anonymous, key.unit, key.catalog, true); if requested != blot_error::Error.none { return 0, requested; } generator.planning.startup_facts.complete(function_id); return function_id, blot_error::Error.none;
        }
    }
    generator.work.fresh_closures++; let source = unit(generator, key.unit); let metadata = source.closures[key.catalog]; let captures = source.extra[metadata.captures.start..metadata.captures.start + metadata.captures.len]; let fn_type = generator.representations.store.node(key.ty);
    if fn_type.tag != blot_backend_layout::Tag.function || captures.len != generator.representations.store.children(key.captures).len { return 0, fail(generator, key.unit, metadata.body, Code.unresolved_type); }
    if key.scalar_environment && (!generator.representations.store.scalarEnvironment(key.captures) || key.templates != 0 || key.static_values != 0) { return 0, fail(generator, key.unit, metadata.body, Code.unresolved_type); }
    if generator.instance_depth >= 256 { return 0, fail(generator, key.unit, metadata.body, Code.complexity); } generator.instance_depth++; defer { generator.instance_depth--; }
    let ordinary_signature, signature_error = closureSignature(generator, fn_type.a, fn_type.b); if signature_error != blot_error::Error.none { return 0, signature_error; }
    var wrapper_signature = ordinary_signature; var roles = closureRoles(generator, fn_type.a);
    if key.dictionaries { let dictionary_signature, error = dictionaryClosureSignature(generator, fn_type.a, fn_type.b); if error != blot_error::Error.none { return 0, error; } wrapper_signature = dictionary_signature; roles = dictionaryClosureRoles(generator, fn_type.a); }
    if key.parameter_template != 0 && generator.planning.template_catalog[key.parameter_template - 1].scalar_environment { roles = (roles & ~((3 as u64) << 2)) | ((blot_backend_runtime_ir::ROLE_scalar as u64) << 2); }
    if key.scalar_environment { roles = (roles & ~(3 as u64)) | (blot_backend_runtime_ir::ROLE_scalar as u64); }
    let function_id, added = generator.module.addTypedFunctionForSignature(wrapper_signature, bodyResultRole(generator, fn_type.b, key.unit, metadata.body)); if added != blot_error::Error.none { return 0, added; }
    let described = setParameterRoles(generator, function_id, roles, blot_support::some(2 as u16)); if described != blot_error::Error.none { return 0, described; }
    let callable = callableLayout(generator, function_id, key.ty); if callable != blot_error::Error.none { return 0, callable; } generator.planning.closures.insert(key, function_id);
    if scope.present { let reserved = scope.value.reserve(function_id); if reserved != blot_error::Error.none { return 0, reserved; } }
    let requested = generator.planning.startup_facts.request(function_id, blot_backend_startup_emission_facts::Kind.anonymous, key.unit, key.catalog, false); if requested != blot_error::Error.none { return 0, requested; }
    let caller = generator.planning.startup_facts.active; generator.planning.startup_facts.active = function_id; defer { generator.planning.startup_facts.active = caller; }
    var mappings: Mapping[>..<] = []; var rows: RowMapping[>..<] = []; let resolved = resolveClosureMappings(generator, key, mappings, rows); if resolved != blot_error::Error.none { return 0, resolved; }
    if key.dictionaries {
        let owner = source.types.node(metadata.function_type); let bound = blot_backend_dictionary_layout::bind(source, generator.representations.store, mappings, metadata.function_type, 0, blot_check_types::List { owner.b, owner.c }, false);
        if bound != blot_error::Error.none { if bound == blot_error::Error.out_of_memory { return 0, bound; } return 0, fail(generator, key.unit, metadata.body, Code.unresolved_type); }
    }
    var staged = blot_support::none<u32>(); if key.staged != 0 { staged = blot_support::some(key.staged); } var context = ClosureEmission { key };
    let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { staged: staged, generator: generator, unit_id: key.unit, function_id: function_id, provider_local: blot_support::some(2 as u32), mappings: mappings, row_mappings: rows, factory_template: key.template_result }, context, emitClosureOwner);
    if emitted != blot_error::Error.none { return 0, emitted; }
    if key.static_values == 0 && scope.present { let solved = scope.value.solved(mappings, rows, generator.representations.template_keys.get(key.templates)); if solved != blot_error::Error.none { return 0, solved; } }
    if scope.present { let completed = scope.value.complete(function_id, lookupValue(generator.planning.closure_template_results, key)); if completed != blot_error::Error.none { return 0, completed; } }
    generator.planning.startup_facts.complete(function_id); return function_id, blot_error::Error.none;
}
fn emitOps(emitter: blot_backend_backend_emission::Owner&, code: const blot_backend_runtime_ir::Instruction[:]) -> blot_error::Error {
    for instruction in code { let error = emitter.emit(instruction.op, instruction.operand); if error != blot_error::Error.none { return error; } } return blot_error::Error.none;
}
fn selectMemberTemplate(generator: Generator&, unit_id: u32, node: blot_check_core::Id, reference: blot_check_core::BindingRef, expected: u32) -> blot_check_core::BindingRef, blot_error::Error {
    if !generator.evaluator.has_implementations { return reference, blot_error::Error.none; }
    var declaration_unit = unit_id; if reference.unit != 0 { declaration_unit = reference.unit; } let declaration = unit(generator, declaration_unit); var template = false;
    for member in declaration.member_templates { if member.binding == reference.binding { template = true; break; } } if !template { return reference, blot_error::Error.none; }
    var owner: i64 = -1; for source, index in generator.units { if source.unit == unit_id { owner = index; break; } } if owner < 0 { return reference, fail(generator, unit_id, node, Code.unsupported); }
    let actual, actual_error = generator.representations.toEvidence(generator.evaluator.evidenceStore(), expected); if actual_error != blot_error::Error.none { if actual_error == blot_error::Error.out_of_memory { return reference, actual_error; } return reference, fail(generator, unit_id, node, Code.unresolved_type); }
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
    let next_key = blot_reuse_code_artifacts::CallableKey { target: key.target, ty: key.ty, applied: key.applied + 1, templates: key.templates, dictionaries: key.dictionaries, bound_dictionaries: key.bound_dictionaries, instance_arguments: key.instance_arguments };
    if erased_argument { let next, error = callable(generator, next_key); if error != blot_error::Error.none { return error; } return emitter.descriptor(next, blot_support::some(0 as u32)); }
    if !key.dictionaries && directCallableEnvironment(generator, key.ty, key.applied + 1) { let next, error = callable(generator, next_key); if error != blot_error::Error.none { return error; } return emitter.descriptor(next, blot_support::some(1 as u32)); }
    var retained: u32[17]; var count: u32 = 0;
    if key.dictionaries { let dictionary_array, error = internLayout(generator, blot_backend_layout::Tag.array, 3, 0, []); if error != blot_error::Error.none { return error; } retained[0] = dictionary_array; count = 1; }
    for parameter in direct.parameters[..key.applied + 1] { if generator.representations.store.node(parameter).tag == blot_backend_layout::Tag.erased_proof { continue; } retained[count] = parameter; count++; }
    var environment_roles: blot_backend_runtime_ir::Role[17]; for parameter, index in retained[..count] { environment_roles[index] = layoutRole(generator, parameter); }
    let environment, allocated = emitter.allocate(count * 4, blot_backend_backend_emission::AllocationRoles { words: environment_roles[..count] }); if allocated != blot_error::Error.none { return allocated; } var stored: u32 = 0;
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
    if key.applied != 0 { return 0, decline(generator, key.target.unit, body.span, Code.unsupported); }
    let arrow = generator.representations.store.node(key.ty); if arrow.tag != blot_backend_layout::Tag.function { return 0, decline(generator, key.target.unit, body.span, Code.unresolved_type); }
    if generator.representations.store.node(arrow.a).tag == blot_backend_layout::Tag.erased_proof { return 0, decline(generator, key.target.unit, body.span, Code.unsupported); }
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
                    if generator.request_owner.present { let guarded = blot_runtime_request_runtime::guard(generator.module, function_id, generator.request_owner.value, []); if guarded != blot_error::Error.none { return 0, guarded; } }
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
    if generator.request_owner.present { let guarded = blot_runtime_request_runtime::guard(generator.module, function_id, generator.request_owner.value, []); if guarded != blot_error::Error.none { return 0, guarded; } }
    if scope.present { let completed = scope.value.complete(function_id, blot_support::none<u32>()); if completed != blot_error::Error.none { return 0, completed; } } return function_id, blot_error::Error.none;
}
fn readDataWord(module: blot_backend_wasm::Module&, at: u32) -> u32 { let start = at as i64; return module.data[start] as u32 | ((module.data[start + 1] as u32) << 8) | ((module.data[start + 2] as u32) << 16) | ((module.data[start + 3] as u32) << 24); }
recursive fn callable(generator: Generator&, key: blot_reuse_code_artifacts::CallableKey) -> u32, blot_error::Error {
    if key.bound_dictionaries && !key.dictionaries { return 0, decline(generator, key.target.unit, unit(generator, key.target.unit).binding(key.target.binding).span, Code.unsupported); }
    let selected, selection_error = selectMemberTemplate(generator, key.target.unit, 0, key.target, key.ty); if selection_error != blot_error::Error.none { return 0, selection_error; }
    if selected != key.target { var actual = key; actual.target = selected; actual.templates = 0; return callable(generator, actual); }
    let scope, scope_error = enterScope(generator, blot_reuse_code_artifacts::Request.callable { key }); if scope_error != blot_error::Error.none { return 0, scope_error; } defer { if scope.present { scope.value.deinit(); } }
    block { let existing = generator.planning.callables.get(key); if existing { if scope.present { let hit = scope.value.hit(existing); if hit != blot_error::Error.none { return 0, hit; } } return existing, blot_error::Error.none; } }
    let source = unit(generator, key.target.unit); let body .= source.body(key.target.binding); if body == null { return 0, decline(generator, key.target.unit, source.binding(key.target.binding).span, Code.unsupported); }
    if body.parameters.len == 0 { return callableAlias(generator, key, body, scope); }
    if body.parameters.len > max_parameters || key.applied >= body.parameters.len { return 0, decline(generator, key.target.unit, body.span, Code.unsupported); }
    var direct = Key { dictionaries: key.dictionaries, instance_arguments: key.instance_arguments, target: key.target, count: body.parameters.len as u8, templates: key.templates }; var ty = key.ty; var current: blot_backend_layout::Node;
    for index in 0..body.parameters.len {
        let n = generator.representations.store.node(ty); if n.tag != blot_backend_layout::Tag.function { return 0, decline(generator, key.target.unit, body.span, Code.unresolved_type); }
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
    var context = CallableEmission { key, direct, current, provider_local, body.parameters.len };
    let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { generator: generator, unit_id: key.target.unit, function_id: function_id, provider_local: blot_support::some(provider_local), mappings: [] }, context, emitCallableOwner); if emitted != blot_error::Error.none { return 0, emitted; }
    if scope.present { let completed = scope.value.complete(function_id, blot_support::none<u32>()); if completed != blot_error::Error.none { return 0, completed; } } return function_id, blot_error::Error.none;
}
struct ConstructorEmission { key: blot_reuse_code_artifacts::ConstructorKey, fn_type: blot_backend_layout::Node }
fn emitConstructorOwner(context: ConstructorEmission&, emitter: blot_backend_backend_emission::Owner&) -> blot_error::Error {
    let generator .= emitter.generator; let key = context.key; let fn_type = context.fn_type; let source = unit(generator, key.unit); let metadata = source.constructor(key.catalog);
    if source.nominal(metadata.nominal).is_opaque { return emitter.emit(blot_backend_runtime_ir::OP_local_get, 1); }
    let payload_type = source.types.node(metadata.payload); var record_local = blot_support::none<u32>();
    if payload_type.tag == blot_check_types::Tag.record && payload_type.b == 1 {
        let roles: blot_backend_runtime_ir::Role[1] = [layoutRole(generator, fn_type.a)]; let record, error = emitter.allocate(4, blot_backend_backend_emission::AllocationRoles { words: roles }); if error != blot_error::Error.none { return error; }
        var store = blot_backend_runtime_ir::OP_i32_store; if generator.representations.store.machine(fn_type.a) == blot_backend_runtime_ir::VT_f32 { store = blot_backend_runtime_ir::OP_f32_store; }
        let emitted = emitOps(emitter, [blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, record), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 1), blot_backend_runtime_ir::instruction(store)]); if emitted != blot_error::Error.none { return emitted; } record_local = blot_support::some(record);
    } else if payload_type.tag == blot_check_types::Tag.record { let record, error = emitter.recordRepresentation(payload_type, 1, true); if error != blot_error::Error.none { return error; } record_local = blot_support::some(record); }
    if record_local.present && record_local.value != 1 { let marked = emitter.markAcyclic(record_local.value, fn_type.a); if marked != blot_error::Error.none { return marked; } }
    var role = layoutRole(generator, fn_type.a); if record_local.present { role = blot_backend_runtime_ir::ROLE_reference; } let roles: blot_backend_runtime_ir::Role[2] = [blot_backend_runtime_ir::ROLE_scalar, role];
    let address, allocated = emitter.allocate(8, blot_backend_backend_emission::AllocationRoles { words: roles }); if allocated != blot_error::Error.none { return allocated; }
    if record_local.present || layoutRole(generator, fn_type.a) == blot_backend_runtime_ir::ROLE_reference { let marked = emitter.markAcyclic(address, fn_type.b); if marked != blot_error::Error.none { return marked; } }
    var payload: u32 = 1; if record_local.present { payload = record_local.value; } var store = blot_backend_runtime_ir::OP_i32_store; if !record_local.present && generator.representations.store.machine(fn_type.a) == blot_backend_runtime_ir::VT_f32 { store = blot_backend_runtime_ir::OP_f32_store; }
    return emitOps(emitter, [
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, address), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const, metadata.tag), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, address), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, payload), blot_backend_runtime_ir::instruction(store, 4), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, address),
    ]);
}
fn constructorFunction(generator: Generator&, key: blot_reuse_code_artifacts::ConstructorKey) -> u32, blot_error::Error {
    let scope, scope_error = enterScope(generator, blot_reuse_code_artifacts::Request.constructor { key }); if scope_error != blot_error::Error.none { return 0, scope_error; } defer { if scope.present { scope.value.deinit(); } }
    block { let existing = generator.planning.constructor_functions.get(key); if existing { if scope.present { let hit = scope.value.hit(existing); if hit != blot_error::Error.none { return 0, hit; } } return existing, blot_error::Error.none; } }
    let fn_type = generator.representations.store.node(key.ty); if fn_type.tag != blot_backend_layout::Tag.function { return 0, decline(generator, key.unit, blot_check_core::Span { 0, 0 }, Code.unresolved_type); }
    let parameters: blot_backend_runtime_ir::ValueType[3] = [blot_backend_runtime_ir::VT_i32, generator.representations.store.machine(fn_type.a), blot_backend_runtime_ir::VT_i32];
    let function_id, added = generator.module.addTypedFunction(parameters, generator.representations.store.machine(fn_type.b), layoutRole(generator, fn_type.b)); if added != blot_error::Error.none { return 0, added; }
    let described = setParameterRoles(generator, function_id, closureRoles(generator, fn_type.a), blot_support::some(2 as u16)); if described != blot_error::Error.none { return 0, described; }
    let layout = callableLayout(generator, function_id, key.ty); if layout != blot_error::Error.none { return 0, layout; } generator.planning.constructor_functions.insert(key, function_id);
    if scope.present { let reserved = scope.value.reserve(function_id); if reserved != blot_error::Error.none { return 0, reserved; } }
    var context = ConstructorEmission { key, fn_type }; let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { generator: generator, unit_id: key.unit, function_id: function_id, provider_local: blot_support::some(2 as u32), mappings: [] }, context, emitConstructorOwner); if emitted != blot_error::Error.none { return 0, emitted; }
    if scope.present { let completed = scope.value.complete(function_id, blot_support::none<u32>()); if completed != blot_error::Error.none { return 0, completed; } } return function_id, blot_error::Error.none;
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
                if blot_backend_simd_intrinsics::literalLanes(metadata.op) { return fail(generator, key.unit, 0, Code.simd_lane_literal); }
                var operands: u32[3]; operands[0] = locals[0]; var count: i64 = 1;
                if metadata.arity == 2 && blot_backend_simd_intrinsics::pairs(metadata.op) { let paired = emitter.simdPairLocals(locals[1], operands[1..3]); if paired != blot_error::Error.none { return paired; } count = 3; }
                else if metadata.arity == 2 { operands[1] = locals[1]; count = 2; }
                return emitter.simdLocals(metadata.op, operands[..count], blot_support::none<u32>(), parameters[0], context.result);
            }
            let scalar_type = generator.representations.store.scalar(parameters[0]); if !scalar_type.present { return fail(generator, key.unit, 0, Code.unsupported); }
            let opcode = blot_backend_scalar_ops::opcode(metadata.op, scalar_type.value); if !opcode.present { return fail(generator, key.unit, 0, Code.unsupported); }
            for local in locals[..metadata.arity] { let get = emitter.emit(blot_backend_runtime_ir::OP_local_get, local); if get != blot_error::Error.none { return get; } } return emitter.emit(opcode.value, 0);
        }
        return emitter.arrayLocals(0, metadata.array_op, locals[..metadata.arity], machines[..metadata.arity], context.result, parameters[0]);
    }
    var roles: blot_backend_runtime_ir::Role[3]; for parameter, index in parameters[..key.applied + 1] { roles[index] = layoutRole(generator, parameter); }
    let environment, allocated = emitter.allocate((key.applied + 1) * 4, blot_backend_backend_emission::AllocationRoles { words: roles[..key.applied + 1] }); if allocated != blot_error::Error.none { return allocated; }
    for parameter, index in parameters[..key.applied] {
        var load = blot_backend_runtime_ir::OP_i32_load; var store = blot_backend_runtime_ir::OP_i32_store; if generator.representations.store.machine(parameter) == blot_backend_runtime_ir::VT_f32 { load = blot_backend_runtime_ir::OP_f32_load; store = blot_backend_runtime_ir::OP_f32_store; }
        let emitted = emitOps(emitter, [blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, environment), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 0), blot_backend_runtime_ir::instruction(load, (index * 4) as u32), blot_backend_runtime_ir::instruction(store, (index * 4) as u32)]); if emitted != blot_error::Error.none { return emitted; }
    }
    var store = blot_backend_runtime_ir::OP_i32_store; if generator.representations.store.machine(context.current.a) == blot_backend_runtime_ir::VT_f32 { store = blot_backend_runtime_ir::OP_f32_store; }
    let emitted = emitOps(emitter, [blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, environment), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 1), blot_backend_runtime_ir::instruction(store, key.applied * 4)]); if emitted != blot_error::Error.none { return emitted; }
    let next, error = primitiveFunction(generator, blot_reuse_code_artifacts::PrimitiveKey { unit: key.unit, catalog: key.catalog, ty: key.ty, applied: key.applied + 1 }); if error != blot_error::Error.none { return error; } return emitter.descriptor(next, blot_support::some(environment));
}
recursive fn primitiveFunction(generator: Generator&, key: blot_reuse_code_artifacts::PrimitiveKey) -> u32, blot_error::Error {
    let scope, scope_error = enterScope(generator, blot_reuse_code_artifacts::Request.primitive { key }); if scope_error != blot_error::Error.none { return 0, scope_error; } defer { if scope.present { scope.value.deinit(); } }
    block { let existing = generator.planning.primitive_functions.get(key); if existing { if scope.present { let hit = scope.value.hit(existing); if hit != blot_error::Error.none { return 0, hit; } } return existing, blot_error::Error.none; } }
    let metadata = unit(generator, key.unit).primitives[key.catalog]; if metadata.arity == 0 || metadata.arity > 3 || key.applied >= metadata.arity { return 0, fail(generator, key.unit, 0, Code.unsupported); }
    var parameters: u32[3]; var current: blot_backend_layout::Node; var ty = key.ty;
    for index in 0..metadata.arity { let arrow = generator.representations.store.node(ty); if arrow.tag != blot_backend_layout::Tag.function { return 0, fail(generator, key.unit, 0, Code.unresolved_type); } parameters[index] = arrow.a; if index == key.applied { current = arrow; } ty = arrow.b; }
    if generator.planning.primitive_functions.count >= 65536 { return 0, fail(generator, key.unit, 0, Code.complexity); }
    let inputs: blot_backend_runtime_ir::ValueType[3] = [blot_backend_runtime_ir::VT_i32, generator.representations.store.machine(current.a), blot_backend_runtime_ir::VT_i32]; let function_id, added = generator.module.addTypedFunction(inputs, generator.representations.store.machine(current.b), layoutRole(generator, current.b)); if added != blot_error::Error.none { return 0, added; }
    let described = setParameterRoles(generator, function_id, closureRoles(generator, current.a), blot_support::some(2 as u16)); if described != blot_error::Error.none { return 0, described; }
    let complete_type, error = internLayoutWithEffects(generator, blot_backend_layout::Tag.function, current.a, current.b, current.c, []); if error != blot_error::Error.none { return 0, error; }
    let layout = callableLayout(generator, function_id, complete_type); if layout != blot_error::Error.none { return 0, layout; } generator.planning.primitive_functions.insert(key, function_id);
    if scope.present { let reserved = scope.value.reserve(function_id); if reserved != blot_error::Error.none { return 0, reserved; } }
    var context = PrimitiveEmission { key, parameters, current, ty }; let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { generator: generator, unit_id: key.unit, function_id: function_id, provider_local: blot_support::some(2 as u32), mappings: [] }, context, emitPrimitiveOwner); if emitted != blot_error::Error.none { return 0, emitted; }
    if scope.present { let completed = scope.value.complete(function_id, blot_support::none<u32>()); if completed != blot_error::Error.none { return 0, completed; } } return function_id, blot_error::Error.none;
}
fn runtimeDataWord(generator: Generator&, address: u32, operation: blot_backend_runtime_operations::Id) -> blot_error::Error {
    let error = generator.planning.runtime_operations.dataWord(generator.module, address, operation); if error == blot_error::Error.invalid_operation { return blot_error::Error.invalid_function_reference; } return error;
}
fn runtimeOperation(generator: Generator&, label: u32, unit_id: u32, span: blot_check_core::Span) -> u32, blot_error::Error {
    var descriptor_label = label; let descriptor = generator.evaluator.storage.evidence.effects.view().operation(label);
    if descriptor.instance.decl != 0 {
        let unscoped, error = generator.evaluator.storage.evidence.effects.internOperation(descriptor.identity, generator.evaluator.storage.evidence.effects.view().operationArguments(label));
        if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0, error; } return 0, decline(generator, unit_id, span, Code.unresolved_type); } descriptor_label = unscoped;
    }
    let previous_count = generator.planning.runtime_operations.entries.len; let operation, error = generator.planning.runtime_operations.intern(generator.evaluator.storage.evidence.view(), descriptor_label);
    if error != blot_error::Error.none { if error == blot_error::Error.invalid_operation { return 0, decline(generator, unit_id, span, Code.unresolved_type); } return 0, error; }
    let demanded = generator.module.demandResource(blot_reuse_artifact_emitter::ResourceKind.operation, operation, operation <= previous_count); if demanded != blot_error::Error.none { return 0, demanded; } return operation, blot_error::Error.none;
}
fn operationLabel(generator: Generator&, unit_id: u32, catalog: u32, mappings: const Mapping[:], rows: const RowMapping[:], span: blot_check_core::Span) -> u32, blot_error::Error {
    let source = unit(generator, unit_id); if catalog >= source.operation_values.len { return 0, decline(generator, unit_id, span, Code.unsupported); }
    let operation = source.operation_values[catalog]; var arguments: u32[>..<] = [];
    for argument in source.types.list(operation.arguments) {
        let concrete, layout_error = codeLayoutWithRows(generator, unit_id, argument, mappings, rows, span); if layout_error != blot_error::Error.none { return 0, layout_error; }
        let actual, error = generator.representations.toEvidence(generator.evaluator.evidenceStore(), concrete); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0, error; } return 0, decline(generator, unit_id, span, Code.unresolved_type); } arguments.push(actual);
    }
    let semantic, error = generator.evaluator.storage.evidence.effects.internOperationInstance(operation.identity, arguments, blot_backend_layout::mappedInstance(operation.instance, mappings));
    if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0, error; } return 0, decline(generator, unit_id, span, Code.unresolved_type); } return semantic, blot_error::Error.none;
}
fn operationLayoutLabel(generator: Generator&, operation_type: u32, unit_id: u32, span: blot_check_core::Span) -> u32, blot_error::Error {
    let operation = generator.representations.store.node(operation_type); if operation.tag != blot_backend_layout::Tag.nominal { return 0, decline(generator, unit_id, span, Code.unresolved_type); }
    var source_arguments: u32[>..<] = []; source_arguments.append(generator.representations.store.children(operation_type)); var arguments: u32[>..<] = [];
    for argument in source_arguments { let actual, error = generator.representations.toEvidence(generator.evaluator.evidenceStore(), argument); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0, error; } return 0, decline(generator, unit_id, span, Code.unresolved_type); } arguments.push(actual); }
    let semantic, error = generator.evaluator.storage.evidence.effects.internOperation(blot_check_types::NominalIdentity { operation.a, operation.b }, arguments);
    if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0, error; } return 0, decline(generator, unit_id, span, Code.unresolved_type); } return semantic, blot_error::Error.none;
}
fn requestLabel(generator: Generator&, unit_id: u32, label: u32, mappings: const Mapping[:], rows: const RowMapping[:], span: blot_check_core::Span) -> u32, blot_error::Error {
    let source = unit(generator, unit_id); let operation = source.types.operation(label); var arguments: u32[>..<] = [];
    for argument in source.types.list(operation.arguments) {
        let concrete, layout_error = codeLayoutWithRows(generator, unit_id, argument, mappings, rows, span); if layout_error != blot_error::Error.none { return 0, layout_error; }
        let actual, error = generator.representations.toEvidence(generator.evaluator.evidenceStore(), concrete); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0, error; } return 0, decline(generator, unit_id, span, Code.unresolved_type); } arguments.push(actual);
    }
    let semantic, error = generator.evaluator.storage.evidence.effects.internOperationInstance(operation.identity, arguments, operation.instance);
    if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0, error; } return 0, decline(generator, unit_id, span, Code.unresolved_type); } return semantic, blot_error::Error.none;
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
            return blot_support::some(blot_backend_wasm::Callback { parameter: parameter.value, result: blot_backend_runtime_ir::SC_unit, cleanup: true, owned: generator.persistent_outputs });
        }
        return blot_support::some(blot_backend_wasm::Callback { parameter: blot_backend_runtime_ir::SC_u32, result: blot_backend_runtime_ir::SC_unit, cleanup: true, owned: generator.persistent_outputs, data: true, schema: argument.a });
    }
    let parameter = generator.representations.store.abi(arrow.a); let result = generator.representations.store.abi(arrow.b); if !parameter.present || !result.present { return blot_support::none<blot_backend_wasm::Callback>(); }
    return blot_support::some(blot_backend_wasm::Callback { parameter: parameter.value, result: result.value });
}
fn hostFunction(generator: Generator&, key: blot_reuse_code_artifacts::HostKey) -> u32, blot_error::Error {
    let scope, scope_error = enterScope(generator, blot_reuse_code_artifacts::Request.host { key }); if scope_error != blot_error::Error.none { return 0, scope_error; } defer { if scope.present { scope.value.deinit(); } }
    block { let existing = generator.planning.host_functions.get(key); if existing { if scope.present { let hit = scope.value.hit(existing); if hit != blot_error::Error.none { return 0, hit; } } return existing, blot_error::Error.none; } }
    let selected = hostCallback(generator, key.ty); if !selected.present { return 0, decline(generator, 1, blot_check_core::Span { 0, 0 }, Code.entry_type); } var callback = selected.value;
    if key.owned && !callback.cleanup { return 0, blot_error::Error.invalid_function_reference; } callback.owned = key.owned;
    let references, references_error = generator.module.ensureHostReferences(); if references_error != blot_error::Error.none { return 0, references_error; }
    let imported, import_error = generator.module.importHostCallback(callback); if import_error != blot_error::Error.none { return 0, import_error; }
    let arrow = generator.representations.store.node(key.ty); let parameters: blot_backend_runtime_ir::ValueType[3] = [blot_backend_runtime_ir::VT_i32, generator.representations.store.machine(arrow.a), blot_backend_runtime_ir::VT_i32];
    let function_id, added = generator.module.addTypedFunction(parameters, blot_backend_runtime_ir::machine(callback.result), blot_backend_runtime_ir::role(callback.result)); if added != blot_error::Error.none { return 0, added; }
    let roles: blot_backend_runtime_ir::Role[3] = [blot_backend_runtime_ir::ROLE_reference, layoutRole(generator, arrow.a), blot_backend_runtime_ir::ROLE_reference]; let described = setParameterRoles(generator, function_id, blot_backend_runtime_ir::packParameterRoles(roles), blot_support::some(2 as u16)); if described != blot_error::Error.none { return 0, described; }
    let layout = callableLayout(generator, function_id, key.ty); if layout != blot_error::Error.none { return 0, layout; } generator.planning.host_functions.insert(key, function_id);
    if scope.present { let reserved = scope.value.reserve(function_id); if reserved != blot_error::Error.none { return 0, reserved; } }
    let borrowed = blot_backend_runtime_ir::Ownership { kind: blot_backend_runtime_ir::OWN_scope, chunk: 14 }; let marker = generator.module.emit(function_id, blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_ownership, blot_backend_runtime_ir::pack(borrowed))); if marker != blot_error::Error.none { return 0, marker; }
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
    let scope, scope_error = enterScope(generator, blot_reuse_code_artifacts::Request.operation { key }); if scope_error != blot_error::Error.none { return 0, scope_error; } defer { if scope.present { scope.value.deinit(); } }
    block { let existing = generator.planning.operation_functions.get(key); if existing { if scope.present { let hit = scope.value.hit(existing); if hit != blot_error::Error.none { return 0, hit; } } return existing, blot_error::Error.none; } }
    let arrow = generator.representations.store.node(key.ty); if arrow.tag != blot_backend_layout::Tag.function { return 0, decline(generator, 1, blot_check_core::Span { 0, 0 }, Code.unresolved_type); }
    let argument_machine = generator.representations.store.machine(arrow.a); let result_machine = generator.representations.store.machine(arrow.b); let parameters: blot_backend_runtime_ir::ValueType[3] = [blot_backend_runtime_ir::VT_i32, argument_machine, blot_backend_runtime_ir::VT_i32];
    let function_id, added = generator.module.addTypedFunction(parameters, result_machine, layoutRole(generator, arrow.b)); if added != blot_error::Error.none { return 0, added; }
    let described = setParameterRoles(generator, function_id, closureRoles(generator, arrow.a), blot_support::some(2 as u16)); if described != blot_error::Error.none { return 0, described; }
    let layout = callableLayout(generator, function_id, key.ty); if layout != blot_error::Error.none { return 0, layout; } generator.planning.operation_functions.insert(key, function_id);
    if scope.present { let reserved = scope.value.reserve(function_id); if reserved != blot_error::Error.none { return 0, reserved; } }
    var context = OperationEmission { key, arrow, argument_machine, result_machine }; let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { generator: generator, unit_id: 1, function_id: function_id, provider_local: blot_support::some(2 as u32), mappings: [] }, context, emitOperationOwner); if emitted != blot_error::Error.none { return 0, emitted; }
    if scope.present { let completed = scope.value.complete(function_id, blot_support::none<u32>()); if completed != blot_error::Error.none { return 0, completed; } } return function_id, blot_error::Error.none;
}
