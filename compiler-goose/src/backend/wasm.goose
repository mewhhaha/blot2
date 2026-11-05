// Flat symbolic functions and deterministic module assembly.
namespace blot_backend_wasm;
import std;
import .runtime_ir;
import .byte_encoder;
import support.error;
import support.option;
import reuse.artifact_emitter;
import runtime.arena_runtime;
import runtime.root_runtime;
import runtime.list_runtime;
import runtime.cycles_runtime;
import runtime.cohort_runtime;
import runtime.region_runtime;
import runtime.runtime_layout;
import runtime.shared_rc;
import runtime.task_abi;

type ValueType = blot_backend_runtime_ir::ValueType;
type Scalar = blot_backend_runtime_ir::Scalar;
type Op = blot_backend_runtime_ir::Op;
type Instruction = blot_backend_runtime_ir::Instruction;
type Signature = blot_backend_runtime_ir::Signature;
type Function = blot_backend_runtime_ir::Function;
type Range = blot_backend_runtime_ir::Range;
type Bytes = blot_backend_byte_encoder::Bytes;
struct Global { scalar: Scalar = blot_backend_runtime_ir::SC_unit, bits: u32 = 0, mutable: bool = false }
struct Import { module: Range, name: Range, signature: u32 = 0 }
struct Callback {
    parameter: Scalar = blot_backend_runtime_ir::SC_unit, result: Scalar = blot_backend_runtime_ir::SC_unit,
    cleanup: bool = false, owned: bool = false, data: bool = false, schema: u32 = 0, concurrent: bool = false,
}
enum OwnershipFallback { none, no_arena, public_arena, host_references, imports, initializer, static_sequence_cache, unproven_body }
struct OwnerBoundary { schema: u32 = 0, kind: u8 = 1, fresh: blot_support::Option<Scalar> }
struct Export {
    name: Range, index: u32 = 0, parameter: Scalar = blot_backend_runtime_ir::SC_unit,
    result: Scalar = blot_backend_runtime_ir::SC_unit, global: bool = false,
    callback: blot_support::Option<Callback>, once: bool = false,
    parameter_owner: blot_support::Option<OwnerBoundary>, result_owner: blot_support::Option<OwnerBoundary>,
    owner_adapter: bool = false, task_adapter: bool = false, task_runtime: bool = false,
}
struct Arena {
    mark_acyclic: u32 = 0,
    allocate_shaped: u32 = 0,
    root_allocate_shaped: u32 = 0,
    allocate: u32 = 0,
    allocate_scalar: u32 = 0,
    recycle: u32 = 0,
    reset: u32 = 0,
    heap: u32 = 0,
    base: u32 = 0,
    static_end: u32 = 0,
    allocated: u32 = 0,
    rc_enabled: u32 = 0,
    rc_leases: u32 = 0,
    rc_retains: u32 = 0,
    rc_releases: u32 = 0,
    rc_destroyed: u32 = 0,
    allocate_typed: u32 = 0,
    retain: u32 = 0,
    release: u32 = 0,
    release_lease: u32 = 0,
    retire: u32 = 0,
    free: u32 = 0,
    store_word: u32 = 0,
    copy_words: u32 = 0,
    decrement: u32 = 0,
    root_allocate: u32 = 0,
    root_reserve: u32 = 0,
    root_pop: u32 = 0,
    root_open: u32 = 0,
    root_close: u32 = 0,
    root_enter: u32 = 0,
    root_leave: u32 = 0,
    root_store: u32 = 0,
    root_public_allocate: u32 = 0,
    root_public_reset: u32 = 0,
    root_authority: u32 = 0,
    root_enabled: u32 = 0,
    root_page: u32 = 0,
    root_top: u32 = 0,
    root_frame: u32 = 0,
    root_active: u32 = 0,
    root_external: u32 = 0,
    root_count: u32 = 0,
    root_globals: u32 = 0,
    root_started: u32 = 0,
    root_host_cursor: u32 = 0,
    root_host_active: u32 = 0,
    root_static_map: u32 = 0,
    root_static_count: u32 = 0,
    root_global_count: u32 = 0,
    cycle_enqueue: u32 = 0,
    cycle_unlink: u32 = 0,
    cycle_visit: u32 = 0,
    cycle_collect: u32 = 0,
    cycle_safe: u32 = 0,
    cycle_head: u32 = 0,
    cycle_members: u32 = 0,
    cycle_work: u32 = 0,
    cycle_phase: u32 = 0,
    cycle_removed: u32 = 0,
    cycle_cadence: u32 = 0,
    cycle_passes: u32 = 0,
    cycle_vertices: u32 = 0,
    cycle_edges: u32 = 0,
    cycle_bytes: u32 = 0,
    cycle_threshold: u32 = 0,
}
let arena_function_fields = [ "allocate", "allocate_scalar", "recycle", "reset", "allocate_typed", "retain", "release", "release_lease", "retire", "free", "store_word", "copy_words", "decrement", "root_allocate", "root_reserve", "root_pop", "root_open", "root_close", "root_enter", "root_leave", "root_store", "root_public_allocate", "root_public_reset", "root_authority", "cycle_enqueue", "cycle_unlink", "cycle_visit", "cycle_collect", "cycle_safe", "mark_acyclic", "allocate_shaped", "root_allocate_shaped" ];
let arena_global_fields = [ "heap", "base", "static_end", "allocated", "rc_enabled", "rc_leases", "rc_retains", "rc_releases", "rc_destroyed", "root_enabled", "root_page", "root_top", "root_frame", "root_active", "root_external", "root_count", "root_globals", "root_started", "root_host_cursor", "root_host_active", "root_static_map", "root_static_count", "root_global_count", "cycle_head", "cycle_members", "cycle_work", "cycle_phase", "cycle_removed", "cycle_cadence", "cycle_passes", "cycle_vertices", "cycle_edges", "cycle_bytes", "cycle_threshold" ];
fn isAllocation(arena: Arena, function: u32) -> bool { function == arena.allocate || function == arena.allocate_scalar }
struct OwnershipFailure { fallback: OwnershipFallback = OwnershipFallback.none, function: blot_support::Option<u32> }
struct HostReferences { retain: u32 = 0, release: u32 = 0, cursor: u32 = 0, active: u32 = 0 }
struct ArrayTransport { allocate: u32 = 0, reset: u32 = 0 }
enum MemoryModel { counted, data_stacks }
enum SemanticKind { allocation, call, diagnostic_call, diagnostic_memory }
struct SemanticSite { diagnostic_context: u32 = 0, function: u32, place: u32, unit: u32, node: u32, root: u32, mappings: u32, rows: u32, kind: SemanticKind }
struct TableOrigin { target: u32 = 0, kind: blot_backend_runtime_ir::TableKind = blot_backend_runtime_ir::TABLE_unknown, function: blot_support::Option<u32>, place: u32 = 0 }
struct Module {
    memory_model: MemoryModel = MemoryModel.counted,
    artifacts: blot_reuse_artifact_emitter::Recorder&? = null,
    types: ValueType[>..<]&, instructions: Instruction[>..<]&, names: u8[>..<]&,
    functions: Function[>..<]&, signatures: Signature[>..<]&, imports: Import[>..<]&, globals: Global[>..<]&, exports: Export[>..<]&, data: u8[>..<]&,
    fixed_memory_bytes: u32 = 0, array_transport: blot_support::Option<ArrayTransport>, arena: blot_support::Option<Arena>,
    fixture_helpers_present: bool = false, fixture_helpers: u32[3] = [0, 0, 0],
    lists: blot_support::Option<blot_runtime_list_runtime::Runtime>,
    cohorts: blot_support::Option<blot_runtime_cohort_runtime::Runtime>,
    regions: blot_support::Option<blot_runtime_region_runtime::Prepared>,
    host_references: blot_support::Option<HostReferences>, public_arena: bool = false,
    cleanup_data: Range, defer_cycles: bool = false, mutable_static: bool = false,
    static_fields: u32[>..<]&, table_functions: u32[>..<]&, table_origins: TableOrigin[>..<]&, semantic_sites: SemanticSite[>..<]&,
    indirect: bool = false, start: blot_support::Option<u32>,
}
fn init(types: ValueType[>..<]&, instructions: Instruction[>..<]&, names: u8[>..<]&, functions: Function[>..<]&, signatures: Signature[>..<]&, imports: Import[>..<]&, globals: Global[>..<]&, exports: Export[>..<]&, data: u8[>..<]&, static_fields: u32[>..<]&, table_functions: u32[>..<]&, table_origins: TableOrigin[>..<]&, semantic_sites: SemanticSite[>..<]&) -> Module {
    return Module { types: types, instructions: instructions, names: names, functions: functions, signatures: signatures, imports: imports, globals: globals, exports: exports, data: data,
        static_fields: static_fields, table_functions: table_functions, table_origins: table_origins, semantic_sites: semantic_sites };
}
fn name(module: Module&, range: Range) -> const u8[:] { module.names[range.start..range.start + range.len] }
fn parameters(module: Module&, function: Function) -> const ValueType[:] { module.types[function.parameters.start..function.parameters.start + function.parameters.len] }
fn locals(module: Module&, function: Function) -> const ValueType[:] { module.types[function.locals.start..function.locals.start + function.locals.len] }
fn instructions(module: Module&, function: Function) -> const Instruction[:] { module.instructions[function.instructions.start..function.instructions.start + function.instructions.len] }
fn signatureParameters(module: Module&, signature: Signature) -> const ValueType[:] { module.types[signature.parameters.start..signature.parameters.start + signature.parameters.len] }
fn ownName(module: Module&, value: const u8[:]) -> Range {
    let result = Range { start: module.names.len, len: value.len }; module.names.append(value); return result;
}
fn equal<T>(left: const T[:], right: const T[:]) -> bool {
    if left.len != right.len { return false; } for value, index in left { if value != right[index] { return false; } } return true;
}
fn startsWith(value: const u8[:], prefix: const u8[:]) -> bool { value.len >= prefix.len && equal(value[..prefix.len], prefix) }
struct TailCheckpoint {
    owner: Module&,
    functions: i64, signatures: i64, imports: i64, globals: i64, exports: i64, data: i64,
    types: i64, instructions: i64, names: i64, static_fields: i64, table_functions: i64, table_origins: i64, semantic_sites: i64,
    fixed_memory_bytes: u32, array_transport: blot_support::Option<ArrayTransport>, fixture_helpers_present: bool, fixture_helpers: u32[3],
    host_references: blot_support::Option<HostReferences>, public_arena: bool, cleanup_data: Range, defer_cycles: bool,
    mutable_static: bool, indirect: bool, start: blot_support::Option<u32>,
}
fn tailCheckpoint(module: Module&) -> blot_support::Option<TailCheckpoint> {
    if module.memory_model != MemoryModel.data_stacks || module.fixed_memory_bytes == 0 || module.artifacts != null || module.arena.present || module.lists.present || module.cohorts.present || module.regions.present { return blot_support::none<TailCheckpoint>(); }
    return blot_support::some(TailCheckpoint {
        owner: module, functions: module.functions.len, signatures: module.signatures.len, imports: module.imports.len, globals: module.globals.len, exports: module.exports.len, data: module.data.len,
        types: module.types.len, instructions: module.instructions.len, names: module.names.len, static_fields: module.static_fields.len, table_functions: module.table_functions.len,
        table_origins: module.table_origins.len, semantic_sites: module.semantic_sites.len, fixed_memory_bytes: module.fixed_memory_bytes,
        array_transport: module.array_transport, fixture_helpers_present: module.fixture_helpers_present, fixture_helpers: module.fixture_helpers,
        host_references: module.host_references, public_arena: module.public_arena, cleanup_data: module.cleanup_data,
        defer_cycles: module.defer_cycles, mutable_static: module.mutable_static, indirect: module.indirect, start: module.start });
}
fn rollbackTail(module: Module&, mark: TailCheckpoint) {
    assert(mark.owner .== module && tailCheckpoint(module).present);
    assert(module.functions.len >= mark.functions && module.signatures.len >= mark.signatures && module.imports.len >= mark.imports && module.globals.len >= mark.globals && module.exports.len >= mark.exports && module.data.len >= mark.data);
    module.functions.resize(mark.functions); module.signatures.resize(mark.signatures); module.imports.resize(mark.imports); module.globals.resize(mark.globals); module.exports.resize(mark.exports); module.data.resize(mark.data);
    module.types.resize(mark.types); module.instructions.resize(mark.instructions); module.names.resize(mark.names);
    module.static_fields.resize(mark.static_fields); module.table_functions.resize(mark.table_functions); module.table_origins.resize(mark.table_origins); module.semantic_sites.resize(mark.semantic_sites);
    module.fixed_memory_bytes = mark.fixed_memory_bytes; module.array_transport = mark.array_transport;
    module.fixture_helpers_present = mark.fixture_helpers_present; module.fixture_helpers = mark.fixture_helpers;
    module.host_references = mark.host_references; module.public_arena = mark.public_arena; module.cleanup_data = mark.cleanup_data;
    module.defer_cycles = mark.defer_cycles; module.mutable_static = mark.mutable_static; module.indirect = mark.indirect; module.start = mark.start;
}
fn internType(module: Module&, parameters: const ValueType[:], result: ValueType) -> u32, blot_error::Error {
    for signature, index in module.signatures {
        if signature.result == result && equal(signatureParameters(module, signature), parameters) {
            let error = demandResource(module, blot_reuse_artifact_emitter::ResourceKind.signature, index as u32, true);
            return index as u32, error;
        }
    }
    if module.signatures.len == 4294967295 { return 0, blot_error::Error.module_too_large; }
    let id = module.signatures.len as u32;
    if module.artifacts {
        let error = blot_reuse_artifact_emitter::signature(module.artifacts, id, parameters, result); if error != blot_error::Error.none { return 0, error; }
    }
    let error = demandResource(module, blot_reuse_artifact_emitter::ResourceKind.signature, id, false); if error != blot_error::Error.none { return 0, error; }
    let range = Range { start: module.types.len, len: parameters.len }; module.types.append(parameters); module.signatures.push(Signature { parameters: range, result: result });
    return id, blot_error::Error.none;
}
fn addFunction(module: Module&, parameters: const ValueType[:], result: ValueType) -> u32, blot_error::Error { addTypedFunction(module, parameters, result, blot_backend_runtime_ir::ROLE_unknown) }
fn addTypedFunction(module: Module&, parameters: const ValueType[:], result: ValueType, role: blot_backend_runtime_ir::Role) -> u32, blot_error::Error {
    let signature, error = internType(module, parameters, result); if error != blot_error::Error.none { return 0, error; }
    return addTypedFunctionForSignature(module, signature, role);
}
fn addFunctionForSignature(module: Module&, signature: u32) -> u32, blot_error::Error { addTypedFunctionForSignature(module, signature, blot_backend_runtime_ir::ROLE_unknown) }
fn addTypedFunctionForSignature(module: Module&, signature: u32, role: blot_backend_runtime_ir::Role) -> u32, blot_error::Error {
    assert(signature < module.signatures.len);
    if module.functions.len == 4294967295 { return 0, blot_error::Error.module_too_large; }
    let id = module.functions.len as u32;
    if module.artifacts { let error = blot_reuse_artifact_emitter::recordFunction(module.artifacts, id, signature, role); if error != blot_error::Error.none { return 0, error; } }
    let error = demandResource(module, blot_reuse_artifact_emitter::ResourceKind.function, id, false); if error != blot_error::Error.none { return 0, error; }
    let signature_type = module.signatures[signature];
    module.functions.push(Function { parameters: signature_type.parameters, result: signature_type.result, result_role: role, signature: signature });
    return id, blot_error::Error.none;
}
fn setParameterRoles(module: Module&, id: u32, roles: u64) -> blot_error::Error {
    if roles == 0 { return blot_error::Error.none; }
    if module.artifacts { let error = blot_reuse_artifact_emitter::recordParameterRoles(module.artifacts, id, roles); if error != blot_error::Error.none { return error; } }
    module.functions[id].parameter_roles = roles; return blot_error::Error.none;
}
fn setProviderParameter(module: Module&, id: u32, index: u16) -> blot_error::Error {
    if id >= module.functions.len || index == blot_backend_runtime_ir::unknown_provider { return blot_error::Error.invalid_function_reference; }
    let function = module.functions[id];
    if index != blot_backend_runtime_ir::no_provider && (index >= function.parameters.len || module.types[function.parameters.start + index] != blot_backend_runtime_ir::VT_i32 || blot_backend_runtime_ir::parameterRole(function, index) != blot_backend_runtime_ir::ROLE_reference) { return blot_error::Error.invalid_function_reference; }
    if module.artifacts { let error = blot_reuse_artifact_emitter::recordProviderParameter(module.artifacts, id, index); if error != blot_error::Error.none { return error; } }
    module.functions[id].provider_parameter = index as u8; return blot_error::Error.none;
}
fn importFunction(module: Module&, namespace_name: const u8[:], imported_name: const u8[:], parameters: const ValueType[:], result: ValueType) -> u32, blot_error::Error {
    let signature, error = internType(module, parameters, result); if error != blot_error::Error.none { return 0, error; }
    for item, index in module.imports {
        if equal(name(module, item.module), namespace_name) && equal(name(module, item.name), imported_name) {
            if item.signature != signature { return 0, blot_error::Error.invalid_function_reference; }
            let demanded = demandResource(module, blot_reuse_artifact_emitter::ResourceKind.import_, index as u32, true); return index as u32, demanded;
        }
    }
    if module.imports.len >= 4294967295 { return 0, blot_error::Error.module_too_large; }
    let index = module.imports.len as u32;
    if module.artifacts { let error = blot_reuse_artifact_emitter::importFunction(module.artifacts, index, namespace_name, imported_name, signature); if error != blot_error::Error.none { return 0, error; } }
    let demanded = demandResource(module, blot_reuse_artifact_emitter::ResourceKind.import_, index, false); if demanded != blot_error::Error.none { return 0, demanded; }
    let owned_module = ownName(module, namespace_name); let owned_name = ownName(module, imported_name);
    module.imports.push(Import { module: owned_module, name: owned_name, signature: signature }); return index, blot_error::Error.none;
}
fn appendType(module: Module&, range: Range, ty: ValueType) -> Range {
    var result = range;
    if result.len == 0 { result.start = module.types.len; }
    else if result.start + result.len != module.types.len {
        let start = module.types.len; let count = result.len;
        for index in 0..count { let value = module.types[result.start + index]; module.types.push(value); }
        result.start = start;
    }
    module.types.push(ty); result.len++; return result;
}
fn appendInstruction(module: Module&, range: Range, inst: Instruction) -> Range {
    var result = range;
    if result.len == 0 { result.start = module.instructions.len; }
    else if result.start + result.len != module.instructions.len {
        let start = module.instructions.len; let count = result.len;
        for index in 0..count { let value = module.instructions[result.start + index]; module.instructions.push(value); }
        result.start = start;
    }
    module.instructions.push(inst); result.len++; return result;
}
fn addLocal(module: Module&, id: u32, ty: ValueType) -> u32, blot_error::Error {
    let function = module.functions[id]; let index = function.parameters.len + function.locals.len;
    if index > 4294967295 { return 0, blot_error::Error.module_too_large; }
    if module.artifacts { let error = blot_reuse_artifact_emitter::recordLocal(module.artifacts, id, ty); if error != blot_error::Error.none { return 0, error; } }
    module.functions[id].locals = appendType(module, function.locals, ty); return index as u32, blot_error::Error.none;
}
fn setCallableLayout(module: Module&, id: u32, ty: u32) -> blot_error::Error {
    if id >= module.functions.len || ty == 0 || ty >= 67108864 { return blot_error::Error.invalid_function_reference; }
    if module.artifacts { let error = blot_reuse_artifact_emitter::recordCallableLayout(module.artifacts, id, ty); if error != blot_error::Error.none { return error; } }
    module.functions[id].callable_layout = ty; return blot_error::Error.none;
}
fn emit(module: Module&, id: u32, instruction: Instruction) -> blot_error::Error {
    if instruction.op == blot_backend_runtime_ir::OP_ownership {
        let annotation = blot_backend_runtime_ir::ownership(instruction.operand);
        if annotation.kind == blot_backend_runtime_ir::OWN_rest && annotation.chunk == 7 && annotation.roles != 0 { return emitReference(module, id, blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_ownership, annotation.roles), blot_reuse_artifact_emitter::Role.callable_layout); }
    }
    if instruction.table_reference {
        var role = blot_reuse_artifact_emitter::Role.table_function;
        if instruction.table_kind == blot_backend_runtime_ir::TABLE_callable { role = blot_reuse_artifact_emitter::Role.callable_function; }
        return emitReference(module, id, instruction, role);
    }
    var role = blot_reuse_artifact_emitter::Role.literal;
    if instruction.op == blot_backend_runtime_ir::OP_call { role = blot_reuse_artifact_emitter::Role.function; }
    else if instruction.op == blot_backend_runtime_ir::OP_call_import { role = blot_reuse_artifact_emitter::Role.import_; }
    else if instruction.op == blot_backend_runtime_ir::OP_call_indirect { role = blot_reuse_artifact_emitter::Role.signature; }
    else if instruction.op == blot_backend_runtime_ir::OP_global_get || instruction.op == blot_backend_runtime_ir::OP_global_set { role = blot_reuse_artifact_emitter::Role.global; }
    else if instruction.op == blot_backend_runtime_ir::OP_host_ref_get || instruction.op == blot_backend_runtime_ir::OP_host_ref_set || instruction.op == blot_backend_runtime_ir::OP_host_ref_size || instruction.op == blot_backend_runtime_ir::OP_host_ref_grow { role = blot_reuse_artifact_emitter::Role.host_table; }
    return emitReference(module, id, instruction, role);
}
fn emitReference(module: Module&, id: u32, instruction: Instruction, role: blot_reuse_artifact_emitter::Role) -> blot_error::Error {
    let table = role == blot_reuse_artifact_emitter::Role.table_function || role == blot_reuse_artifact_emitter::Role.callable_function;
    assert(!table || instruction.op == blot_backend_runtime_ir::OP_i32_const);
    let error = recordTableReference(module, role, instruction.operand, blot_support::some(id), module.functions[id].instructions.len as u32); if error != blot_error::Error.none { return error; }
    if module.artifacts { let error = blot_reuse_artifact_emitter::appendInstruction(module.artifacts, id, instruction.op, blot_reuse_artifact_emitter::Operand { role: role, value: instruction.operand }); if error != blot_error::Error.none { return error; } }
    var owned = instruction;
    if role == blot_reuse_artifact_emitter::Role.callable_layout {
        assert(instruction.op == blot_backend_runtime_ir::OP_ownership && instruction.operand != 0 && instruction.operand < 67108864);
        owned = blot_backend_runtime_ir::callableCodeRead(instruction.operand);
    }
    owned.table_reference = table; owned.table_kind = blot_backend_runtime_ir::TABLE_unknown;
    if role == blot_reuse_artifact_emitter::Role.callable_function { owned.table_kind = blot_backend_runtime_ir::TABLE_callable; }
    module.functions[id].instructions = appendInstruction(module, module.functions[id].instructions, owned);
    if instruction.op == blot_backend_runtime_ir::OP_call_indirect { module.indirect = true; }
    if instruction.op == blot_backend_runtime_ir::OP_ownership { module.functions[id].annotations++; }
    return blot_error::Error.none;
}
fn emitSlice(module: Module&, id: u32, code: const Instruction[:]) -> blot_error::Error {
    for instruction in code { let error = emit(module, id, instruction); if error != blot_error::Error.none { return error; } } return blot_error::Error.none;
}
fn demandResource(module: Module&, kind: blot_reuse_artifact_emitter::ResourceKind, id: u32, hit: bool) -> blot_error::Error {
    if module.artifacts { return blot_reuse_artifact_emitter::recordDemand(module.artifacts, kind, id, hit); } return blot_error::Error.none;
}
fn recordTableReference(module: Module&, role: blot_reuse_artifact_emitter::Role, target: u32, function: blot_support::Option<u32>, place: u32) -> blot_error::Error {
    if role != blot_reuse_artifact_emitter::Role.table_function && role != blot_reuse_artifact_emitter::Role.callable_function { return blot_error::Error.none; }
    var kind = blot_backend_runtime_ir::TABLE_unknown; if role == blot_reuse_artifact_emitter::Role.callable_function { kind = blot_backend_runtime_ir::TABLE_callable; }
    module.table_functions.push(target); module.table_origins.push(TableOrigin { target: target, kind: kind, function: function, place: place }); return blot_error::Error.none;
}
fn recordSemanticSite(module: Module&, site: SemanticSite) -> blot_error::Error {
    if module.artifacts { let error = blot_reuse_artifact_emitter::recordSemanticSite(module.artifacts, site); if error != blot_error::Error.none { return error; } }
    module.semantic_sites.push(site); return blot_error::Error.none;
}
fn dataReference(module: Module&, address: u32, operand: blot_reuse_artifact_emitter::Operand) -> blot_error::Error {
    let error = recordTableReference(module, operand.role, operand.value, blot_support::none<u32>(), address); if error != blot_error::Error.none { return error; }
    if module.artifacts { return blot_reuse_artifact_emitter::recordDataWord(module.artifacts, address, operand); } return blot_error::Error.none;
}
fn setStart(module: Module&, id: u32) -> blot_error::Error {
    if module.artifacts { let error = blot_reuse_artifact_emitter::recordStart(module.artifacts, id); if error != blot_error::Error.none { return error; } }
    module.start = blot_support::some(id); return blot_error::Error.none;
}
fn publicArena(module: Module&) -> blot_error::Error {
    if !module.public_arena {
        if module.artifacts { let error = blot_reuse_artifact_emitter::recordPublicArena(module.artifacts); if error != blot_error::Error.none { return error; } }
        module.public_arena = true;
    }
    return blot_error::Error.none;
}
fn mutableStatic(module: Module&) -> blot_error::Error {
    if module.mutable_static { return blot_error::Error.none; }
    if module.artifacts { let error = blot_reuse_artifact_emitter::recordMutableStatic(module.artifacts); if error != blot_error::Error.none { return error; } }
    module.mutable_static = true; return blot_error::Error.none;
}
fn staticField(module: Module&, address: u32, role: blot_backend_runtime_ir::Role) -> blot_error::Error {
    if role != blot_backend_runtime_ir::ROLE_scalar && role != blot_backend_runtime_ir::ROLE_reference { return mutableStatic(module); }
    if address % 4 != 0 || address > module.data.len || module.data.len - address < 4 { return blot_error::Error.invalid_global_reference; }
    let encoded = address | role;
    for previous in module.static_fields { if previous == encoded { return blot_error::Error.none; } if (previous & 4294967292) == address { return blot_error::Error.invalid_global_reference; } }
    if module.artifacts { let error = blot_reuse_artifact_emitter::recordStaticField(module.artifacts, address, role); if error != blot_error::Error.none { return error; } }
    module.static_fields.push(encoded); return blot_error::Error.none;
}
fn addGlobal(module: Module&, scalar: Scalar, bits: u32, mutable: bool) -> u32, blot_error::Error {
    if module.globals.len == 4294967295 { return 0, blot_error::Error.module_too_large; }
    let id = module.globals.len as u32;
    if module.artifacts { let error = blot_reuse_artifact_emitter::recordGlobal(module.artifacts, id, scalar, blot_reuse_artifact_emitter::Operand { value: bits }, mutable); if error != blot_error::Error.none { return 0, error; } }
    let error = demandResource(module, blot_reuse_artifact_emitter::ResourceKind.global, id, false); if error != blot_error::Error.none { return 0, error; }
    module.globals.push(Global { scalar: scalar, bits: bits, mutable: mutable }); return id, blot_error::Error.none;
}
fn writeDataWord(module: Module&, address: i64, value: u32) {
    for index in 0..4 { module.data[address + index] = (value >> (index * 8)) as! u8; }
}
fn readDataWord(module: Module&, address: i64) -> u32 {
    return module.data[address] as u32 | (module.data[address + 1] as u32 << 8) | (module.data[address + 2] as u32 << 16) | (module.data[address + 3] as u32 << 24);
}
fn scopedDataWord(module: Module&, base_global: u32, word: u32) -> u32, blot_error::Error {
    if module.memory_model != MemoryModel.data_stacks || module.arena.present || module.artifacts != null || base_global >= module.globals.len || module.globals[base_global].bits != 0 { return 0, blot_error::Error.invalid_function_reference; }
    if module.data.len > 4294967291 { return 0, blot_error::Error.module_too_large; }
    let offset = module.data.len as u32; for index in 0..4 { module.data.push((word >> (index * 8)) as! u8); }
    return offset, blot_error::Error.none;
}
fn dataWords(module: Module&, words: const u32[:]) -> u32, blot_error::Error {
    let arena, error = ensureArena(module); if error != blot_error::Error.none { return 0, error; }
    if words.len > (4294967295 - module.data.len) / 4 { return 0, blot_error::Error.module_too_large; }
    let address = module.data.len as u32;
    for word in words { for index in 0..4 { module.data.push((word >> (index * 8)) as! u8); } }
    let finished = finishStaticData(module, address); return address, finished;
}
fn dataObject(module: Module&, fields: const u32[:]) -> u32, blot_error::Error { dataWords(module, fields) }
fn staticBytes(module: Module&, bytes: const u8[:]) -> u32, blot_error::Error {
    let arena, error = ensureArena(module); if error != blot_error::Error.none { return 0, error; }
    if bytes.len % 4 != 0 { return 0, blot_error::Error.invalid_function_reference; }
    if bytes.len > 4294967295 - module.data.len { return 0, blot_error::Error.module_too_large; }
    let address = module.data.len as u32; module.data.append(bytes);
    let finished = finishStaticData(module, address); return address, finished;
}
fn finishStaticData(module: Module&, address: u32) -> blot_error::Error {
    if module.artifacts { let error = blot_reuse_artifact_emitter::data(module.artifacts, address, module.data[address..]); if error != blot_error::Error.none { return error; } }
    let error = demandResource(module, blot_reuse_artifact_emitter::ResourceKind.static_data, address, false); if error != blot_error::Error.none { return error; }
    let end = module.data.len as u32; let arena = module.arena.value;
    for id in [arena.heap, arena.base, arena.static_end] {
        if module.artifacts { let error = blot_reuse_artifact_emitter::recordGlobalBits(module.artifacts, id, blot_reuse_artifact_emitter::Operand { role: blot_reuse_artifact_emitter::Role.static_address, value: end }); if error != blot_error::Error.none { return error; } }
        module.globals[id].bits = end;
    }
    return blot_error::Error.none;
}
fn finishStaticFields(module: Module&) -> blot_error::Error {
    if !module.arena.present { return blot_error::Error.none; }
    let arena = module.arena.value; var address: u32 = 0;
    if module.static_fields.len != 0 { let created, error = dataWords(module, module.static_fields[..]); if error != blot_error::Error.none { return error; } address = created; }
    for encoded, index in module.static_fields {
        let error = dataReference(module, address + (index * 4) as u32, blot_reuse_artifact_emitter::Operand { role: blot_reuse_artifact_emitter::Role.static_address, value: encoded }); if error != blot_error::Error.none { return error; }
    }
    let ids = [arena.root_static_map, arena.root_static_count, arena.root_global_count];
    let values = [address, module.static_fields.len as u32, module.globals.len as u32];
    for id, index in ids {
        var role = blot_reuse_artifact_emitter::Role.literal; if index == 0 { role = blot_reuse_artifact_emitter::Role.static_address; }
        if module.artifacts { let error = blot_reuse_artifact_emitter::recordGlobalBits(module.artifacts, id, blot_reuse_artifact_emitter::Operand { role: role, value: values[index] }); if error != blot_error::Error.none { return error; } }
        module.globals[id].bits = values[index];
    }
    return blot_error::Error.none;
}
fn ensureArena(module: Module&) -> Arena, blot_error::Error {
    if module.fixed_memory_bytes != 0 { return Arena {}, blot_error::Error.module_too_large; }
    if module.arena.present { let error = demandResource(module, blot_reuse_artifact_emitter::ResourceKind.arena, 0, true); return module.arena.value, error; }
    for index in 0..blot_runtime_arena_runtime::metadata_bytes { module.data.push(0); }
    writeDataWord(module, blot_runtime_arena_runtime::empty_list_address + blot_runtime_runtime_layout::ListDescriptor_immutable, 1);
    writeDataWord(module, blot_runtime_arena_runtime::empty_scalar_list_address + blot_runtime_runtime_layout::ListDescriptor_immutable, 1);
    writeDataWord(module, blot_runtime_arena_runtime::empty_scalar_list_address + blot_runtime_runtime_layout::ListDescriptor_scalar_elements, 1);
    writeDataWord(module, blot_runtime_arena_runtime::empty_acyclic_list_address + blot_runtime_runtime_layout::ListDescriptor_immutable, blot_runtime_list_runtime::frozen | blot_runtime_list_runtime::acyclic_elements);
    for address in [blot_runtime_arena_runtime::empty_list_address, blot_runtime_arena_runtime::empty_scalar_list_address, blot_runtime_arena_runtime::empty_acyclic_list_address] { writeDataWord(module, address + blot_runtime_runtime_layout::ListDescriptor_leaf_limit, blot_runtime_list_runtime::capacity); }
    for width in 2..17 {
        let address = blot_runtime_arena_runtime::empty_rows_address + (width - 2) * blot_runtime_runtime_layout::ListDescriptor_bytes;
        writeDataWord(module, address + blot_runtime_runtime_layout::ListDescriptor_scalar_elements, width as u32);
        writeDataWord(module, address + blot_runtime_runtime_layout::ListDescriptor_immutable, 1);
        writeDataWord(module, address + blot_runtime_runtime_layout::ListDescriptor_leaf_limit, blot_runtime_list_runtime::leafLimit(width as u32));
    }
    if module.artifacts { let error = blot_reuse_artifact_emitter::data(module.artifacts, 0, module.data[..]); if error != blot_error::Error.none { return Arena {}, error; } }
    var arena = Arena {};
    let heap, heap_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, blot_runtime_arena_runtime::metadata_bytes, true);
    if heap_error != blot_error::Error.none { return Arena {}, heap_error; } arena.heap = heap;
    let base, base_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, blot_runtime_arena_runtime::metadata_bytes, true);
    if base_error != blot_error::Error.none { return Arena {}, base_error; } arena.base = base;
    let static_end, static_end_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, blot_runtime_arena_runtime::metadata_bytes, false);
    if static_end_error != blot_error::Error.none { return Arena {}, static_end_error; } arena.static_end = static_end;
    let allocated, allocated_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if allocated_error != blot_error::Error.none { return Arena {}, allocated_error; } arena.allocated = allocated;
    let rc_enabled, rc_enabled_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, false);
    if rc_enabled_error != blot_error::Error.none { return Arena {}, rc_enabled_error; } arena.rc_enabled = rc_enabled;
    let rc_leases, rc_leases_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if rc_leases_error != blot_error::Error.none { return Arena {}, rc_leases_error; } arena.rc_leases = rc_leases;
    let rc_retains, rc_retains_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if rc_retains_error != blot_error::Error.none { return Arena {}, rc_retains_error; } arena.rc_retains = rc_retains;
    let rc_releases, rc_releases_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if rc_releases_error != blot_error::Error.none { return Arena {}, rc_releases_error; } arena.rc_releases = rc_releases;
    let rc_destroyed, rc_destroyed_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if rc_destroyed_error != blot_error::Error.none { return Arena {}, rc_destroyed_error; } arena.rc_destroyed = rc_destroyed;
    let root_enabled, root_enabled_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, false);
    if root_enabled_error != blot_error::Error.none { return Arena {}, root_enabled_error; } arena.root_enabled = root_enabled;
    let root_page, root_page_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if root_page_error != blot_error::Error.none { return Arena {}, root_page_error; } arena.root_page = root_page;
    let root_top, root_top_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if root_top_error != blot_error::Error.none { return Arena {}, root_top_error; } arena.root_top = root_top;
    let root_frame, root_frame_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if root_frame_error != blot_error::Error.none { return Arena {}, root_frame_error; } arena.root_frame = root_frame;
    let root_active, root_active_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if root_active_error != blot_error::Error.none { return Arena {}, root_active_error; } arena.root_active = root_active;
    let root_external, root_external_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if root_external_error != blot_error::Error.none { return Arena {}, root_external_error; } arena.root_external = root_external;
    let root_count, root_count_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if root_count_error != blot_error::Error.none { return Arena {}, root_count_error; } arena.root_count = root_count;
    let root_globals, root_globals_error = addGlobal(module, blot_backend_runtime_ir::SC_pointer, 0, true);
    if root_globals_error != blot_error::Error.none { return Arena {}, root_globals_error; } arena.root_globals = root_globals;
    let root_started, root_started_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if root_started_error != blot_error::Error.none { return Arena {}, root_started_error; } arena.root_started = root_started;
    let root_host_cursor, root_host_cursor_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if root_host_cursor_error != blot_error::Error.none { return Arena {}, root_host_cursor_error; } arena.root_host_cursor = root_host_cursor;
    let root_host_active, root_host_active_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if root_host_active_error != blot_error::Error.none { return Arena {}, root_host_active_error; } arena.root_host_active = root_host_active;
    let root_static_map, root_static_map_error = addGlobal(module, blot_backend_runtime_ir::SC_pointer, 0, false);
    if root_static_map_error != blot_error::Error.none { return Arena {}, root_static_map_error; } arena.root_static_map = root_static_map;
    let root_static_count, root_static_count_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, false);
    if root_static_count_error != blot_error::Error.none { return Arena {}, root_static_count_error; } arena.root_static_count = root_static_count;
    let root_global_count, root_global_count_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, false);
    if root_global_count_error != blot_error::Error.none { return Arena {}, root_global_count_error; } arena.root_global_count = root_global_count;
    let cycle_head, cycle_head_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if cycle_head_error != blot_error::Error.none { return Arena {}, cycle_head_error; } arena.cycle_head = cycle_head;
    let cycle_members, cycle_members_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if cycle_members_error != blot_error::Error.none { return Arena {}, cycle_members_error; } arena.cycle_members = cycle_members;
    let cycle_work, cycle_work_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if cycle_work_error != blot_error::Error.none { return Arena {}, cycle_work_error; } arena.cycle_work = cycle_work;
    let cycle_phase, cycle_phase_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if cycle_phase_error != blot_error::Error.none { return Arena {}, cycle_phase_error; } arena.cycle_phase = cycle_phase;
    let cycle_removed, cycle_removed_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if cycle_removed_error != blot_error::Error.none { return Arena {}, cycle_removed_error; } arena.cycle_removed = cycle_removed;
    let cycle_cadence, cycle_cadence_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if cycle_cadence_error != blot_error::Error.none { return Arena {}, cycle_cadence_error; } arena.cycle_cadence = cycle_cadence;
    let cycle_passes, cycle_passes_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if cycle_passes_error != blot_error::Error.none { return Arena {}, cycle_passes_error; } arena.cycle_passes = cycle_passes;
    let cycle_vertices, cycle_vertices_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if cycle_vertices_error != blot_error::Error.none { return Arena {}, cycle_vertices_error; } arena.cycle_vertices = cycle_vertices;
    let cycle_edges, cycle_edges_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if cycle_edges_error != blot_error::Error.none { return Arena {}, cycle_edges_error; } arena.cycle_edges = cycle_edges;
    let cycle_bytes, cycle_bytes_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if cycle_bytes_error != blot_error::Error.none { return Arena {}, cycle_bytes_error; } arena.cycle_bytes = cycle_bytes;
    let cycle_threshold, cycle_threshold_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, blot_runtime_cycles_runtime::minimum_traffic, true);
    if cycle_threshold_error != blot_error::Error.none { return Arena {}, cycle_threshold_error; } arena.cycle_threshold = cycle_threshold;
    let allocate, allocate_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_i32);
    if allocate_error != blot_error::Error.none { return Arena {}, allocate_error; } arena.allocate = allocate;
    let allocate_scalar, allocate_scalar_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_i32);
    if allocate_scalar_error != blot_error::Error.none { return Arena {}, allocate_scalar_error; } arena.allocate_scalar = allocate_scalar;
    let recycle, recycle_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none);
    if recycle_error != blot_error::Error.none { return Arena {}, recycle_error; } arena.recycle = recycle;
    let reset, reset_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_i32);
    if reset_error != blot_error::Error.none { return Arena {}, reset_error; } arena.reset = reset;
    let allocate_typed, allocate_typed_error = addFunction(module, [blot_backend_runtime_ir::VT_i32, blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_i32);
    if allocate_typed_error != blot_error::Error.none { return Arena {}, allocate_typed_error; } arena.allocate_typed = allocate_typed;
    let retain, retain_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none);
    if retain_error != blot_error::Error.none { return Arena {}, retain_error; } arena.retain = retain;
    let release, release_error = addTypedFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none, blot_backend_runtime_ir::ROLE_scalar);
    if release_error != blot_error::Error.none { return Arena {}, release_error; } arena.release = release;
    let release_lease, release_lease_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none);
    if release_lease_error != blot_error::Error.none { return Arena {}, release_lease_error; } arena.release_lease = release_lease;
    let retire, retire_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none);
    if retire_error != blot_error::Error.none { return Arena {}, retire_error; } arena.retire = retire;
    let free, free_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none);
    if free_error != blot_error::Error.none { return Arena {}, free_error; } arena.free = free;
    let store_word, store_word_error = addFunction(module, [blot_backend_runtime_ir::VT_i32, blot_backend_runtime_ir::VT_i32, blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none);
    if store_word_error != blot_error::Error.none { return Arena {}, store_word_error; } arena.store_word = store_word;
    let copy_words, copy_words_error = addFunction(module, [blot_backend_runtime_ir::VT_i32, blot_backend_runtime_ir::VT_i32, blot_backend_runtime_ir::VT_i32, blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none);
    if copy_words_error != blot_error::Error.none { return Arena {}, copy_words_error; } arena.copy_words = copy_words;
    let decrement, decrement_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none);
    if decrement_error != blot_error::Error.none { return Arena {}, decrement_error; } arena.decrement = decrement;
    let root_allocate, root_allocate_error = addFunction(module, [blot_backend_runtime_ir::VT_i32, blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_i32);
    if root_allocate_error != blot_error::Error.none { return Arena {}, root_allocate_error; } arena.root_allocate = root_allocate;
    let root_reserve, root_reserve_error = addFunction(module, [], blot_backend_runtime_ir::VT_i32);
    if root_reserve_error != blot_error::Error.none { return Arena {}, root_reserve_error; } arena.root_reserve = root_reserve;
    let root_pop, root_pop_error = addFunction(module, [], blot_backend_runtime_ir::VT_i32);
    if root_pop_error != blot_error::Error.none { return Arena {}, root_pop_error; } arena.root_pop = root_pop;
    let root_open, root_open_error = addFunction(module, [], blot_backend_runtime_ir::VT_i32);
    if root_open_error != blot_error::Error.none { return Arena {}, root_open_error; } arena.root_open = root_open;
    let root_close, root_close_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none);
    if root_close_error != blot_error::Error.none { return Arena {}, root_close_error; } arena.root_close = root_close;
    let root_enter, root_enter_error = addFunction(module, [], blot_backend_runtime_ir::VT_none);
    if root_enter_error != blot_error::Error.none { return Arena {}, root_enter_error; } arena.root_enter = root_enter;
    let root_leave, root_leave_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none);
    if root_leave_error != blot_error::Error.none { return Arena {}, root_leave_error; } arena.root_leave = root_leave;
    let root_store, root_store_error = addFunction(module, [blot_backend_runtime_ir::VT_i32, blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none);
    if root_store_error != blot_error::Error.none { return Arena {}, root_store_error; } arena.root_store = root_store;
    let root_public_allocate, root_public_allocate_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_i32);
    if root_public_allocate_error != blot_error::Error.none { return Arena {}, root_public_allocate_error; } arena.root_public_allocate = root_public_allocate;
    let root_authority, root_authority_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none);
    if root_authority_error != blot_error::Error.none { return Arena {}, root_authority_error; } arena.root_authority = root_authority;
    let root_public_reset, root_public_reset_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_i32);
    if root_public_reset_error != blot_error::Error.none { return Arena {}, root_public_reset_error; } arena.root_public_reset = root_public_reset;
    let cycle_enqueue, cycle_enqueue_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none);
    if cycle_enqueue_error != blot_error::Error.none { return Arena {}, cycle_enqueue_error; } arena.cycle_enqueue = cycle_enqueue;
    let cycle_unlink, cycle_unlink_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none);
    if cycle_unlink_error != blot_error::Error.none { return Arena {}, cycle_unlink_error; } arena.cycle_unlink = cycle_unlink;
    let cycle_visit, cycle_visit_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none);
    if cycle_visit_error != blot_error::Error.none { return Arena {}, cycle_visit_error; } arena.cycle_visit = cycle_visit;
    let cycle_collect, cycle_collect_error = addFunction(module, [], blot_backend_runtime_ir::VT_none);
    if cycle_collect_error != blot_error::Error.none { return Arena {}, cycle_collect_error; } arena.cycle_collect = cycle_collect;
    let cycle_safe, cycle_safe_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none);
    if cycle_safe_error != blot_error::Error.none { return Arena {}, cycle_safe_error; } arena.cycle_safe = cycle_safe;
    let mark_acyclic, mark_acyclic_error = addFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none);
    if mark_acyclic_error != blot_error::Error.none { return Arena {}, mark_acyclic_error; } arena.mark_acyclic = mark_acyclic;
    let allocate_shaped, allocate_shaped_error = addFunction(module, [blot_backend_runtime_ir::VT_i32, blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_i32);
    if allocate_shaped_error != blot_error::Error.none { return Arena {}, allocate_shaped_error; } arena.allocate_shaped = allocate_shaped;
    let root_allocate_shaped, root_allocate_shaped_error = addFunction(module, [blot_backend_runtime_ir::VT_i32, blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_i32);
    if root_allocate_shaped_error != blot_error::Error.none { return Arena {}, root_allocate_shaped_error; } arena.root_allocate_shaped = root_allocate_shaped;
    var error = blot_runtime_arena_runtime::emit(module, arena); if error != blot_error::Error.none { return Arena {}, error; }
    if !module.defer_cycles { error = blot_runtime_cycles_runtime::emit(module, arena); if error != blot_error::Error.none { return Arena {}, error; } }
    error = blot_runtime_root_runtime::emit(module, arena); if error != blot_error::Error.none { return Arena {}, error; }
    error = emitSlice(module, arena.reset, [
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_get, arena.cycle_head),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const, 1),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call, arena.cycle_safe),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_get, arena.heap),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_return_),
    ]); if error != blot_error::Error.none { return Arena {}, error; }
    if module.artifacts { error = blot_reuse_artifact_emitter::recordArena(module.artifacts, arena); if error != blot_error::Error.none { return Arena {}, error; } }
    module.arena = blot_support::some(arena);
    error = demandResource(module, blot_reuse_artifact_emitter::ResourceKind.arena, 0, false); return arena, error;
}
fn ensureHostReferences(module: Module&) -> HostReferences, blot_error::Error {
    if module.host_references.present { let error = demandResource(module, blot_reuse_artifact_emitter::ResourceKind.host_references, 0, true); return module.host_references.value, error; }
    let cursor, cursor_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true); if cursor_error != blot_error::Error.none { return HostReferences {}, cursor_error; }
    let active, active_error = addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true); if active_error != blot_error::Error.none { return HostReferences {}, active_error; }
    let retain, retain_error = addTypedFunction(module, [blot_backend_runtime_ir::VT_externref], blot_backend_runtime_ir::VT_i32, blot_backend_runtime_ir::ROLE_scalar); if retain_error != blot_error::Error.none { return HostReferences {}, retain_error; }
    let slot, slot_error = addLocal(module, retain, blot_backend_runtime_ir::VT_i32); if slot_error != blot_error::Error.none { return HostReferences {}, slot_error; }
    let retain_body_error = emitSlice(module, retain, [
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_get, cursor),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_tee, slot),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_host_ref_size),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eq),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_host_ref_null),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const, 1),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_host_ref_grow),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const, 4294967295),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eq),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, slot),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 0),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_host_ref_set),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, slot),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const, 1),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_set, cursor),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, slot),
    ]); if retain_body_error != blot_error::Error.none { return HostReferences {}, retain_body_error; }
    let release, release_error = addTypedFunction(module, [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none, blot_backend_runtime_ir::ROLE_scalar); if release_error != blot_error::Error.none { return HostReferences {}, release_error; }
    let current, current_error = addLocal(module, release, blot_backend_runtime_ir::VT_i32); if current_error != blot_error::Error.none { return HostReferences {}, current_error; }
    let release_body_error = emitSlice(module, release, [
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 0),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_get, cursor),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_gt_u),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 0),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set, current),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_block),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_loop),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, current),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_get, cursor),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ge_u),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_br_if, 1),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, current),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_host_ref_null),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_host_ref_set),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, current),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const, 1),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set, current),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_br),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 0),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_set, cursor),
    ]); if release_body_error != blot_error::Error.none { return HostReferences {}, release_body_error; }
    var error = emitSlice(module, release, [
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, 0),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eqz),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_set, active),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),
    ]); if error != blot_error::Error.none { return HostReferences {}, error; }
    let references = HostReferences { retain: retain, release: release, cursor: cursor, active: active };
    if module.artifacts { error = blot_reuse_artifact_emitter::recordHostReferences(module.artifacts, references); if error != blot_error::Error.none { return HostReferences {}, error; } }
    module.host_references = blot_support::some(references);
    if module.arena.present { error = blot_runtime_root_runtime::hostCleanup(module, module.arena.value); if error != blot_error::Error.none { return HostReferences {}, error; } }
    error = demandResource(module, blot_reuse_artifact_emitter::ResourceKind.host_references, 0, false); return references, error;
}
fn prepareCycles(module: Module&) -> blot_error::Error {
    if !module.arena.present { return blot_error::Error.none; }
    let arena = module.arena.value;
    if module.functions[arena.cycle_collect].instructions.len != 0 { return blot_error::Error.none; }
    if module.public_arena || module.host_references.present || module.start.present { return blot_runtime_cycles_runtime::emit(module, arena); }
    var seen: bool[>..<] = [];
    for function, id in module.functions { seen.push(!runtimeHelper(module, id)); }
    for item in module.exports { if !item.global { seen[item.index] = true; } }
    var changed = true;
    while changed {
        changed = false;
        let count = module.functions.len;
        for id in 0..count {
            if !seen[id] { continue; }
            if id == arena.allocate || id == arena.allocate_typed || id == arena.root_allocate || id == arena.root_public_allocate { return blot_runtime_cycles_runtime::emit(module, arena); }
            let code = module.functions[id].instructions;
            for index in 0..code.len {
                let inst = module.instructions[code.start + index];
                if inst.op != blot_backend_runtime_ir::OP_call && !inst.table_reference { continue; }
                if inst.op == blot_backend_runtime_ir::OP_call && inst.operand == arena.allocate_scalar { continue; }
                if inst.operand >= seen.len || seen[inst.operand] { continue; }
                seen[inst.operand] = true; changed = true;
            }
        }
    }
    return blot_error::Error.none;
}
fn ensureLists(module: Module&) -> blot_runtime_list_runtime::Runtime, blot_error::Error {
    if module.lists.present { let error = demandResource(module, blot_reuse_artifact_emitter::ResourceKind.lists, 0, true); return module.lists.value, error; }
    let arena, error = ensureArena(module); if error != blot_error::Error.none { return blot_runtime_list_runtime::Runtime {}, error; }
    let runtime, emitted = blot_runtime_list_runtime::emit(module, arena); if emitted != blot_error::Error.none { return runtime, emitted; }
    if module.artifacts { let error = blot_reuse_artifact_emitter::recordLists(module.artifacts, runtime); if error != blot_error::Error.none { return runtime, error; } }
    module.lists = blot_support::some(runtime);
    let demanded = demandResource(module, blot_reuse_artifact_emitter::ResourceKind.lists, 0, false); return runtime, demanded;
}
fn ensureListSnapshot(module: Module&) -> u32, blot_error::Error {
    let runtime, error = ensureLists(module); if error != blot_error::Error.none { return 0, error; }
    if runtime.snapshot.present { return runtime.snapshot.value, blot_error::Error.none; }
    let id, emitted = blot_runtime_list_runtime::emitSnapshot(module); if emitted != blot_error::Error.none { return 0, emitted; }
    var updated = runtime; updated.snapshot = blot_support::some(id);
    if module.artifacts { let error = blot_reuse_artifact_emitter::recordListsExtension(module.artifacts, updated); if error != blot_error::Error.none { return 0, error; } }
    module.lists = blot_support::some(updated); return id, blot_error::Error.none;
}
fn ensureUncheckedListAddress(module: Module&) -> u32, blot_error::Error {
    let runtime, error = ensureLists(module); if error != blot_error::Error.none { return 0, error; }
    if runtime.address_unchecked.present { return runtime.address_unchecked.value, blot_error::Error.none; }
    let id, emitted = blot_runtime_list_runtime::emitUncheckedAddress(module); if emitted != blot_error::Error.none { return 0, emitted; }
    var updated = runtime; updated.address_unchecked = blot_support::some(id);
    if module.artifacts { let error = blot_reuse_artifact_emitter::recordListsExtension(module.artifacts, updated); if error != blot_error::Error.none { return 0, error; } }
    module.lists = blot_support::some(updated); return id, blot_error::Error.none;
}
fn ensureUncheckedListSet(module: Module&) -> u32, blot_error::Error {
    let address, error = ensureUncheckedListAddress(module); if error != blot_error::Error.none { return 0, error; }
    let runtime = module.lists.value; if runtime.set_unchecked.present { return runtime.set_unchecked.value, blot_error::Error.none; }
    let id, emitted = blot_runtime_list_runtime::emitUncheckedSet(module, runtime); if emitted != blot_error::Error.none { return 0, emitted; }
    var updated = runtime; updated.set_unchecked = blot_support::some(id);
    if module.artifacts { let error = blot_reuse_artifact_emitter::recordListsExtension(module.artifacts, updated); if error != blot_error::Error.none { return 0, error; } }
    module.lists = blot_support::some(updated); return id, blot_error::Error.none;
}
fn isArray(scalar: Scalar) -> bool { scalar == blot_backend_runtime_ir::SC_array_u32 || scalar == blot_backend_runtime_ir::SC_array_f32 }
fn callbackName(scalar: Scalar) -> const u8[:], bool {
    if scalar == blot_backend_runtime_ir::SC_unit { return "unit", true; }
    if scalar == blot_backend_runtime_ir::SC_u32 { return "u32", true; }
    if scalar == blot_backend_runtime_ir::SC_bool { return "bool", true; }
    if scalar == blot_backend_runtime_ir::SC_f32 { return "f32", true; }
    if scalar == blot_backend_runtime_ir::SC_array_u32 { return "array_u32", true; }
    if scalar == blot_backend_runtime_ir::SC_array_f32 { return "array_f32", true; }
    return "", false;
}
fn exportFunction(module: Module&, id: u32, name: const u8[:], parameter: Scalar, result: Scalar) -> blot_error::Error { exportUsageFunction(module, id, name, parameter, result, false) }
fn exportUsageFunction(module: Module&, id: u32, name: const u8[:], parameter: Scalar, result: Scalar, once: bool) -> blot_error::Error { exportOwnerFunction(module, id, name, parameter, result, once, blot_support::none<OwnerBoundary>(), blot_support::none<OwnerBoundary>(), false) }
fn exportOwnerFunction(module: Module&, id: u32, exported_name: const u8[:], parameter: Scalar, result: Scalar, once: bool, parameter_owner: blot_support::Option<OwnerBoundary>, result_owner: blot_support::Option<OwnerBoundary>, owner_adapter: bool) -> blot_error::Error {
    if id >= module.functions.len { return blot_error::Error.invalid_function_reference; }
    if isArray(parameter) || isArray(result) {
        if !module.array_transport.present { let arena, error = ensureArena(module); if error != blot_error::Error.none { return error; } }
        let error = publicArena(module); if error != blot_error::Error.none { return error; }
    }
    let item = Export { name: ownName(module, exported_name), index: id, parameter: parameter, result: result, once: once, parameter_owner: parameter_owner, result_owner: result_owner, owner_adapter: owner_adapter };
    if module.artifacts { let error = blot_reuse_artifact_emitter::exportItem(module.artifacts, module, item, true); if error != blot_error::Error.none { return error; } }
    module.exports.push(item); module.functions[id].entry = true; return blot_error::Error.none;
}
fn resourceCount(module: Module&) -> u32 {
    var count: u32 = 0; for item in module.exports { if startsWith(name(module, item.name), "blot:resource_cleanup/") { count++; } } return count;
}
struct ResourceTransfers { reserve: u32 = 0, register: u32 = 0, release: u32 = 0, retire: u32 = 0, drain: u32 = 0 }
fn resourceTransferImports(module: Module&) -> ResourceTransfers, blot_error::Error {
    var result = ResourceTransfers {}; let published = publicArena(module); if published != blot_error::Error.none { return result, published; }
    let obsolete, error = importFunction(module, "blot:resource/1", "register", [blot_backend_runtime_ir::VT_i32; 5], blot_backend_runtime_ir::VT_none); if error != blot_error::Error.none { return result, error; }
    let reserve, reserve_error = importFunction(module, "blot:resource/1", "reserve", [], blot_backend_runtime_ir::VT_i32); if reserve_error != blot_error::Error.none { return result, reserve_error; } result.reserve = reserve;
    let release, release_error = importFunction(module, "blot:resource/1", "release", [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none); if release_error != blot_error::Error.none { return result, release_error; } result.release = release;
    let register, register_error = importFunction(module, "blot:resource/2", "register_owned", [blot_backend_runtime_ir::VT_i32; 6], blot_backend_runtime_ir::VT_none); if register_error != blot_error::Error.none { return result, register_error; } result.register = register;
    let retire, retire_error = importFunction(module, "blot:resource/2", "retire", [blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none); if retire_error != blot_error::Error.none { return result, retire_error; } result.retire = retire;
    let drain, drain_error = importFunction(module, "blot:resource/2", "drain", [], blot_backend_runtime_ir::VT_none); if drain_error != blot_error::Error.none { return result, drain_error; } result.drain = drain;
    return result, blot_error::Error.none;
}
fn resourceDrainImport(module: Module&) -> u32, bool {
    for item, index in module.imports {
        if !equal(name(module, item.module), "blot:resource/2") || !equal(name(module, item.name), "drain") { continue; }
        let signature = module.signatures[item.signature]; if signature.parameters.len == 0 && signature.result == blot_backend_runtime_ir::VT_none { return index as u32, true; }
    }
    return 0, false;
}
fn resourceRetireImport(module: Module&) -> u32, bool {
    for item, index in module.imports {
        if !equal(name(module, item.module), "blot:resource/2") || !equal(name(module, item.name), "retire") { continue; }
        let signature = module.signatures[item.signature]; if equal(signatureParameters(module, signature), [blot_backend_runtime_ir::VT_i32]) && signature.result == blot_backend_runtime_ir::VT_none { return index as u32, true; }
    }
    return 0, false;
}
fn resourceImport(module: Module&, id: i64) -> bool {
    if id >= module.imports.len || resourceCount(module) == 0 { return false; }
    let item = module.imports[id]; let signature = module.signatures[item.signature]; let parameters = signatureParameters(module, signature);
    let imported_name = name(module, item.name); let namespace_name = name(module, item.module);
    if equal(namespace_name, "blot:resource/2") {
        if equal(imported_name, "retire") { return equal(parameters, [blot_backend_runtime_ir::VT_i32]) && signature.result == blot_backend_runtime_ir::VT_none; }
        if equal(imported_name, "drain") { return parameters.len == 0 && signature.result == blot_backend_runtime_ir::VT_none; }
        if equal(imported_name, "register_owned") { return equal(parameters, [blot_backend_runtime_ir::VT_i32; 6]) && signature.result == blot_backend_runtime_ir::VT_none; }
        return false;
    }
    if !equal(namespace_name, "blot:resource/1") { return false; }
    if equal(imported_name, "reserve") { return parameters.len == 0 && signature.result == blot_backend_runtime_ir::VT_i32; }
    if equal(imported_name, "release") { return equal(parameters, [blot_backend_runtime_ir::VT_i32]) && signature.result == blot_backend_runtime_ir::VT_none; }
    if equal(imported_name, "register") { return equal(parameters, [blot_backend_runtime_ir::VT_i32; 5]) && signature.result == blot_backend_runtime_ir::VT_none; }
    return false;
}
fn exportResourceAdapter(module: Module&, id: u32, exported_name: const u8[:]) -> blot_error::Error {
    let item = Export { name: ownName(module, exported_name), index: id };
    if module.artifacts { let error = blot_reuse_artifact_emitter::exportItem(module.artifacts, module, item, false); if error != blot_error::Error.none { return error; } }
    module.exports.push(item); return blot_error::Error.none;
}
fn exportTaskAdapter(module: Module&, id: u32, exported_name: const u8[:], runtime: bool) -> blot_error::Error {
    let item = Export { name: ownName(module, exported_name), index: id, task_adapter: true, task_runtime: runtime };
    if module.artifacts { let error = blot_reuse_artifact_emitter::exportItem(module.artifacts, module, item, false); if error != blot_error::Error.none { return error; } }
    module.exports.push(item); return blot_error::Error.none;
}
fn taskAdapterFunction(module: Module&, id: i64) -> bool { for item in module.exports { if !item.global && item.index == id && item.task_adapter { return true; } } return false; }
fn taskCount(module: Module&) -> u32 { var count: u32 = 0; for item in module.exports { if item.task_adapter && startsWith(name(module, item.name), "blot:task_start/") { count++; } } return count; }
fn taskImport(module: Module&, id: i64) -> bool {
    if id >= module.imports.len { return false; }
    let item = module.imports[id]; if !equal(name(module, item.module), "blot:task/1") { return false; }
    let signature = module.signatures[item.signature];
    for entry in blot_runtime_task_abi::imports { if equal(name(module, item.name), entry.name) { return signature.result == entry.result && equal(signatureParameters(module, signature), entry.parameters); } }
    return false;
}
fn taskImportNamed(module: Module&, imported_name: const u8[:]) -> u32, bool {
    for item, index in module.imports { if equal(name(module, item.module), "blot:task/1") && equal(name(module, item.name), imported_name) && taskImport(module, index) { return index as u32, true; } } return 0, false;
}
fn resourceAdapter(module: Module&, item: Export) -> bool { let text = name(module, item.name); return startsWith(text, "blot:resource_cleanup/") || startsWith(text, "blot:resource_drop/"); }
fn resourceAdapterFunction(module: Module&, id: i64) -> bool {
    for item in module.exports { if !item.global && item.index == id && resourceAdapter(module, item) && !module.functions[id].entry { return true; } } return false;
}
fn fixtureHelper(module: Module&, id: i64) -> bool {
    if module.fixture_helpers_present { for helper in module.fixture_helpers { if id == helper { return true; } } } return false;
}
fn arenaFunctions(arena: Arena) -> u32[32] { return [arena.allocate, arena.allocate_scalar, arena.recycle, arena.reset, arena.allocate_typed, arena.retain, arena.release, arena.release_lease, arena.retire, arena.free, arena.store_word, arena.copy_words, arena.decrement, arena.root_allocate, arena.root_reserve, arena.root_pop, arena.root_open, arena.root_close, arena.root_enter, arena.root_leave, arena.root_store, arena.root_public_allocate, arena.root_public_reset, arena.root_authority, arena.cycle_enqueue, arena.cycle_unlink, arena.cycle_visit, arena.cycle_collect, arena.cycle_safe, arena.mark_acyclic, arena.allocate_shaped, arena.root_allocate_shaped]; }
fn runtimeHelper(module: Module&, id: i64) -> bool {
    for item in module.exports { if !item.global && item.index == id && item.task_runtime { return true; } }
    if fixtureHelper(module, id) { return true; }
    if module.regions.present && blot_runtime_region_runtime::contains(module.regions.value.runtime, id) { return true; }
    if module.arena.present { for function in arenaFunctions(module.arena.value) { if id == function { return true; } } }
    if module.lists.present && blot_runtime_list_runtime::contains(module.lists.value, id) { return true; }
    if module.cohorts.present { let cohorts = module.cohorts.value; if id == cohorts.begin || id == cohorts.allocate || id == cohorts.retire_members { return true; } }
    if module.host_references.present { let references = module.host_references.value; if id == references.retain || id == references.release { return true; } }
    return false;
}
let callback_scalars = [blot_backend_runtime_ir::SC_unit, blot_backend_runtime_ir::SC_u32, blot_backend_runtime_ir::SC_bool, blot_backend_runtime_ir::SC_f32, blot_backend_runtime_ir::SC_array_u32, blot_backend_runtime_ir::SC_array_f32];
fn callbackSpelling(parameter: Scalar, result: Scalar) -> u8[>..] {
    let parameter_name, parameter_valid = callbackName(parameter); let result_name, result_valid = callbackName(result);
    assert(parameter_valid && result_valid); var output: u8[>..] = []; output.append("call_"); output.append(parameter_name); output.push('_'); output.append(result_name); return output;
}
fn hostCallbackImport(module: Module&, id: i64) -> blot_support::Option<Callback> {
    if id >= module.imports.len { return blot_support::none<Callback>(); }
    let item = module.imports[id]; let namespace_name = name(module, item.module);
    let data = equal(namespace_name, "blot:cleanup_data/1") || equal(namespace_name, "blot:cleanup_data/2");
    if data {
        let owned = equal(namespace_name, "blot:cleanup_data/2");
        if item.signature >= module.signatures.len { return blot_support::none<Callback>(); }
        let signature = module.signatures[item.signature]; var handle = blot_backend_runtime_ir::VT_externref; if owned { handle = blot_backend_runtime_ir::VT_i32; }
        if !equal(name(module, item.name), "call_data_unit") || signature.result != blot_backend_runtime_ir::VT_i32 || !equal(signatureParameters(module, signature), [handle, blot_backend_runtime_ir::VT_i32, blot_backend_runtime_ir::VT_i32]) { return blot_support::none<Callback>(); }
        return blot_support::some(Callback { parameter: blot_backend_runtime_ir::SC_u32, cleanup: true, owned: owned, data: true });
    }
    let owned = equal(namespace_name, "blot:cleanup/2"); let cleanup = owned || equal(namespace_name, "blot:cleanup/1");
    if (!cleanup && !equal(namespace_name, "blot:host/1")) || item.signature >= module.signatures.len { return blot_support::none<Callback>(); }
    let signature = module.signatures[item.signature]; var handle = blot_backend_runtime_ir::VT_externref; if owned { handle = blot_backend_runtime_ir::VT_i32; }
    for parameter in callback_scalars {
        for result in callback_scalars {
            let expected = callbackSpelling(parameter, result);
            if (!cleanup || result == blot_backend_runtime_ir::SC_unit) && equal(name(module, item.name), expected) && signature.result == blot_backend_runtime_ir::machine(result) && equal(signatureParameters(module, signature), [handle, blot_backend_runtime_ir::machine(parameter)]) {
                return blot_support::some(Callback { parameter: parameter, result: result, cleanup: cleanup, owned: owned });
            }
        }
    }
    return blot_support::none<Callback>();
}
fn setCleanupDataMetadata(module: Module&, bytes: const u8[:]) -> blot_error::Error {
    if module.cleanup_data.len != 0 { return blot_error::Error.invalid_function_reference; }
    if module.artifacts { let error = blot_reuse_artifact_emitter::cleanupData(module.artifacts, bytes); if error != blot_error::Error.none { return error; } }
    module.cleanup_data = ownName(module, bytes); return blot_error::Error.none;
}
fn importHostCallback(module: Module&, callback: Callback) -> u32, blot_error::Error {
    if callback.data {
        if !callback.cleanup || callback.parameter != blot_backend_runtime_ir::SC_u32 || callback.result != blot_backend_runtime_ir::SC_unit || callback.schema == 0 { return 0, blot_error::Error.invalid_function_reference; }
        var namespace_name: const u8[:] = "blot:cleanup_data/1"; var handle = blot_backend_runtime_ir::VT_externref;
        if callback.owned { namespace_name = "blot:cleanup_data/2"; handle = blot_backend_runtime_ir::VT_i32; }
        return importFunction(module, namespace_name, "call_data_unit", [handle, blot_backend_runtime_ir::VT_i32, blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_i32);
    }
    let parameter_name, parameter_valid = callbackName(callback.parameter); let result_name, result_valid = callbackName(callback.result);
    if !parameter_valid || !result_valid { return 0, blot_error::Error.invalid_function_reference; }
    let imported_name = callbackSpelling(callback.parameter, callback.result); var namespace_name: const u8[:] = "blot:host/1";
    if callback.cleanup { if callback.result != blot_backend_runtime_ir::SC_unit { return 0, blot_error::Error.invalid_function_reference; } namespace_name = "blot:cleanup/1"; if callback.owned { namespace_name = "blot:cleanup/2"; } }
    var handle = blot_backend_runtime_ir::VT_externref;
    if callback.owned { if !callback.cleanup { return 0, blot_error::Error.invalid_function_reference; } handle = blot_backend_runtime_ir::VT_i32; }
    return importFunction(module, namespace_name, imported_name, [handle, blot_backend_runtime_ir::machine(callback.parameter)], blot_backend_runtime_ir::machine(callback.result));
}
fn ownedCleanupBindImport(module: Module&, id: i64) -> bool {
    if id >= module.imports.len { return false; }
    let item = module.imports[id]; let namespace_name = name(module, item.module);
    if equal(namespace_name, "blot:cleanup_data_bind/1") {
        if item.signature >= module.signatures.len || !equal(name(module, item.name), "call_data_unit") { return false; }
        let signature = module.signatures[item.signature]; return signature.result == blot_backend_runtime_ir::VT_i32 && equal(signatureParameters(module, signature), [blot_backend_runtime_ir::VT_externref, blot_backend_runtime_ir::VT_i32]);
    }
    if !equal(namespace_name, "blot:cleanup_bind/1") || item.signature >= module.signatures.len { return false; }
    let signature = module.signatures[item.signature]; if signature.result != blot_backend_runtime_ir::VT_i32 || !equal(signatureParameters(module, signature), [blot_backend_runtime_ir::VT_externref]) { return false; }
    for parameter in callback_scalars { let expected = callbackSpelling(parameter, blot_backend_runtime_ir::SC_unit); if equal(name(module, item.name), expected) { return true; } }
    return false;
}
fn importOwnedCleanupBind(module: Module&, callback: Callback) -> u32, blot_error::Error {
    if !callback.cleanup || !callback.owned || callback.result != blot_backend_runtime_ir::SC_unit { return 0, blot_error::Error.invalid_function_reference; }
    if callback.data { return importFunction(module, "blot:cleanup_data_bind/1", "call_data_unit", [blot_backend_runtime_ir::VT_externref, blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_i32); }
    let parameter_name, parameter_valid = callbackName(callback.parameter); if !parameter_valid { return 0, blot_error::Error.invalid_function_reference; }
    let imported_name = callbackSpelling(callback.parameter, blot_backend_runtime_ir::SC_unit);
    return importFunction(module, "blot:cleanup_bind/1", imported_name, [blot_backend_runtime_ir::VT_externref], blot_backend_runtime_ir::VT_i32);
}
fn exportCallbackFunction(module: Module&, id: u32, name: const u8[:], callback: Callback, result: Scalar) -> blot_error::Error { exportUsageCallbackFunction(module, id, name, callback, result, false) }
fn exportUsageCallbackFunction(module: Module&, id: u32, name: const u8[:], callback: Callback, result: Scalar, once: bool) -> blot_error::Error { exportOwnerCallbackFunction(module, id, name, callback, result, once, blot_support::none<OwnerBoundary>()) }
fn exportOwnerCallbackFunction(module: Module&, id: u32, exported_name: const u8[:], callback: Callback, result: Scalar, once: bool, result_owner: blot_support::Option<OwnerBoundary>) -> blot_error::Error {
    if id >= module.functions.len { return blot_error::Error.invalid_function_reference; }
    let parameter_name, parameter_valid = callbackName(callback.parameter); let result_name, result_valid = callbackName(callback.result); let output_name, output_valid = callbackName(result);
    if !parameter_valid || !result_valid || !output_valid { return blot_error::Error.invalid_function_reference; }
    if callback.data || isArray(callback.parameter) || isArray(callback.result) || isArray(result) {
        if !module.array_transport.present { let arena, error = ensureArena(module); if error != blot_error::Error.none { return error; } }
        let error = publicArena(module); if error != blot_error::Error.none { return error; }
    }
    let item = Export { name: ownName(module, exported_name), index: id, result: result, callback: blot_support::some(callback), once: once, result_owner: result_owner };
    if module.artifacts { let error = blot_reuse_artifact_emitter::exportItem(module.artifacts, module, item, true); if error != blot_error::Error.none { return error; } }
    module.exports.push(item); module.functions[id].entry = true; return blot_error::Error.none;
}
fn exportConstant(module: Module&, exported_name: const u8[:], scalar: Scalar, bits: u32) -> blot_error::Error {
    let id = module.globals.len as u32; let item = Export { name: ownName(module, exported_name), index: id, result: scalar, global: true };
    if module.artifacts {
        var role = blot_reuse_artifact_emitter::Role.literal; if scalar == blot_backend_runtime_ir::SC_pointer || isArray(scalar) { role = blot_reuse_artifact_emitter::Role.static_address; }
        var error = blot_reuse_artifact_emitter::recordGlobal(module.artifacts, id, scalar, blot_reuse_artifact_emitter::Operand { role: role, value: bits }, false); if error != blot_error::Error.none { return error; }
        error = blot_reuse_artifact_emitter::exportItem(module.artifacts, module, item, false); if error != blot_error::Error.none { return error; }
    }
    module.globals.push(Global { scalar: scalar, bits: bits }); module.exports.push(item); return blot_error::Error.none;
}
fn exportGlobal(module: Module&, id: u32, exported_name: const u8[:]) -> blot_error::Error {
    if id >= module.globals.len { return blot_error::Error.invalid_global_reference; }
    let item = Export { name: ownName(module, exported_name), index: id, result: module.globals[id].scalar, global: true };
    if module.artifacts { let error = blot_reuse_artifact_emitter::exportItem(module.artifacts, module, item, false); if error != blot_error::Error.none { return error; } }
    module.exports.push(item); return blot_error::Error.none;
}
fn scopedEngineBody(module: Module&, parameters: i64, locals: i64, bytes: i64) -> blot_error::Error {
    if module.memory_model != MemoryModel.data_stacks { return blot_error::Error.none; }
    if parameters > 50000 || locals > 50000 - parameters || bytes > 7654321 { return blot_error::Error.module_too_large; }
    return blot_error::Error.none;
}
fn abiValue(payload: Bytes&, scalar: Scalar, owner: blot_support::Option<OwnerBoundary>) {
    if owner.present {
        let boundary = owner.value; blot_backend_byte_encoder::byte(payload, 7 + boundary.kind); blot_backend_byte_encoder::uleb(payload, boundary.schema);
        var fresh: u8 = 255; if boundary.fresh.present { fresh = boundary.fresh.value; } blot_backend_byte_encoder::byte(payload, fresh);
    } else { blot_backend_byte_encoder::byte(payload, scalar); }
}
struct Prepared { body: blot_support::Option<blot_backend_runtime_ir::Body>, borrowed: bool = false }
fn publishBody(module: Module&, locals: const ValueType[:], code: const Instruction[:]) -> blot_backend_runtime_ir::Body {
    let local_range = Range { start: module.types.len, len: locals.len }; module.types.append(locals);
    let code_range = Range { start: module.instructions.len, len: code.len }; module.instructions.append(code);
    return blot_backend_runtime_ir::Body { locals: local_range, instructions: code_range };
}
fn preparedView(module: Module&, prepared: const Prepared[:], id: i64) -> Function {
    var result = module.functions[id];
    if prepared[id].body.present { result.locals = prepared[id].body.value.locals; result.instructions = prepared[id].body.value.instructions; }
    return result;
}
fn deinit(module: Module&) {
    module.functions.clear(); module.signatures.clear(); module.imports.clear(); module.globals.clear(); module.exports.clear(); module.data.clear();
    module.types.clear(); module.instructions.clear(); module.names.clear(); module.static_fields.clear(); module.table_functions.clear(); module.table_origins.clear(); module.semantic_sites.clear();
    module.fixed_memory_bytes = 0; module.array_transport = blot_support::none<ArrayTransport>(); module.arena = blot_support::none<Arena>(); module.fixture_helpers_present = false;
    module.lists = blot_support::none<blot_runtime_list_runtime::Runtime>(); module.cohorts = blot_support::none<blot_runtime_cohort_runtime::Runtime>(); module.regions = blot_support::none<blot_runtime_region_runtime::Prepared>();
    module.host_references = blot_support::none<HostReferences>(); module.public_arena = false; module.cleanup_data = Range {}; module.defer_cycles = false; module.mutable_static = false; module.indirect = false; module.start = blot_support::none<u32>();
}
// Derived immutable import spelling view for safepoint classification.
fn importName(module: Module&, id: i64) -> const u8[:] { name(module, module.imports[id].name) }
fn reset(module: Module&) {
    deinit(module);
    module = init(module.types,module.instructions,module.names,module.functions,module.signatures,module.imports,module.globals,module.exports,module.data,module.static_fields,module.table_functions,module.table_origins,module.semantic_sites);
}
