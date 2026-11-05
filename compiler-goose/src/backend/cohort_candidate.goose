// Detached late bodies for a freshly rederived closed activation.
namespace blot_backend_cohort_candidate;
import .wasm;
import .runtime_ir;
import .activation_graph;
import .activation_intersection;
import .provider_origins;
import reuse.code_artifacts;
import runtime.runtime_layout;
import runtime.cohort_runtime;
import runtime.cycles_runtime;
import support.error;
import support.option;
import support.pooled_buffer;
type Error = blot_error::Error;
type Module = blot_backend_wasm::Module;
type Function = blot_backend_runtime_ir::Function;
type Instruction = blot_backend_runtime_ir::Instruction;
struct Flags { storage: bool[:] = [],items: bool[:] = [] }
struct Code { storage: Instruction[:] = [],items: Instruction[:] = [] }
reusable[] var flag_runs: bool[>..] = [];
reusable[] var code_runs: Instruction[>..] = [];
fn push(flags: Flags&,value: bool) -> Error { blot_support_pooled_buffer::push(flags,value,flag_runs) }
fn deinit(flags: Flags&) { blot_support_pooled_buffer::deinit(flags,flag_runs); }
fn push(code: Code&,value: Instruction) -> Error { blot_support_pooled_buffer::push(code,value,code_runs) }
fn append(code: Code&,values: const Instruction[:]) -> Error { blot_support_pooled_buffer::append(code,values,code_runs) }
fn deinit(code: Code&) { blot_support_pooled_buffer::deinit(code,code_runs); }
struct Extension { module: Module&,original_functions: i64 = 0,original_signatures: i64 = 0,owned: Flags,active: bool = false }
fn init(module: Module&) -> Extension { Extension { module } }
fn deinit(view: Extension&) { if view.active { view.module.reset(); } view.owned.deinit(); view.original_functions = 0; view.original_signatures = 0; view.active = false; }
fn possible(source: const Module&) -> bool { if !source.arena.present || source.semantic_sites.len == 0 || source.cohorts.present { return false; } for origin in source.table_origins { if origin.kind == blot_backend_runtime_ir::TABLE_callable { return true; } } return false; }
fn own(view: Extension&,id: u32) -> Function?,Error {
    if !view.active || id >= view.module.functions.len { return null,Error.invalid_function_reference; } if id < view.original_functions && !view.owned.items[id] { let error = view.module.materializeBody(id); if error != Error.none { return null,error; } view.owned.items[id] = true; } return view.module.functions[id],Error.none;
}
fn mutableInstructions(view: Extension&,id: u32) -> Instruction[:],Error { let body,error = own(view,id); if error != Error.none { return [],error; } assert(body != null); return view.module.instructions[body.instructions.start..body.instructions.start + body.instructions.len],Error.none; }
fn replaceBody(view: Extension&,id: u32,code: const Instruction[:]) -> Error { let body,error = own(view,id); if error != Error.none { return error; } assert(body != null); return view.module.publishInstructions(id,code); }
fn detachedInto(view: Extension&,source: const Module&) -> Error {
    assert(!(view.module .== source)); deinit(view); let destination .= view.module;
    let types .= destination.types; let instructions .= destination.instructions; let names .= destination.names; let functions .= destination.functions; let signatures .= destination.signatures; let imports .= destination.imports; let globals .= destination.globals; let exports .= destination.exports; let data .= destination.data; let static_fields .= destination.static_fields; let table_functions .= destination.table_functions; let table_origins .= destination.table_origins; let semantic_sites .= destination.semantic_sites;
    destination = source; destination.types .= types; destination.instructions .= instructions; destination.names .= names; destination.functions .= functions; destination.signatures .= signatures; destination.imports .= imports; destination.globals .= globals; destination.exports .= exports; destination.data .= data; destination.static_fields .= static_fields; destination.table_functions .= table_functions; destination.table_origins .= table_origins; destination.semantic_sites .= semantic_sites; destination.artifacts .= null;
    view.active = true; view.original_functions = source.functions.len; view.original_signatures = source.signatures.len;
    recursive fn cloneContainers() -> Error {
        destination.types.append(source.types); destination.names.append(source.names); destination.signatures.append(source.signatures); destination.imports.append(source.imports); destination.globals.append(source.globals); destination.exports.append(source.exports); destination.data.append(source.data); destination.static_fields.append(source.static_fields); destination.table_functions.append(source.table_functions); destination.table_origins.append(source.table_origins); destination.semantic_sites.append(source.semantic_sites);
        for original in source.functions { var function = original; function.borrowed_body = true; function.borrowed_locals = source.locals(original); function.borrowed_instructions = source.instructions(original); destination.functions.push(function); let flag = view.owned.push(false); if flag != Error.none { return flag; } } return Error.none;
    }
    let error = cloneContainers(); if error != Error.none { view.deinit(); } return error;
}
fn namedFunction(model: blot_backend_activation_intersection::Model,id: i64) -> bool { for entry in model.functions { if entry.function != id { continue; } match entry.request { named=>{ return true; },_=>{}, } } return false; }
fn prepareInto(view: Extension&,source: const Module&,model: blot_backend_activation_intersection::Model) -> bool,Error {
    if !possible(source) { return false,Error.none; }
    for body,id in source.functions { if body.entry || body.result_role != blot_backend_runtime_ir::ROLE_scalar || !namedFunction(model,id) { continue; } var installation = false; for instruction,at in source.instructions(body) { if blot_backend_provider_origins::constructor(source,body,at).present { installation = true; break; } } if !installation { continue; } let admitted,error = checkedInto(view,source,model,id as u32); if error != Error.none || admitted { return admitted,error; } } return false,Error.none;
}
fn checkedInto(view: Extension&,source: const Module&,model: blot_backend_activation_intersection::Model,boundary: u32) -> bool,Error {
    let selected,error = blot_backend_activation_intersection::analyze(source,model,boundary); if error != Error.none { return false,error; } if !selected.present { return false,Error.none; } var proof = selected.value; let extended = extendInto(view,source,proof.runtime); proof.deinit(); if extended == Error.out_of_memory { return false,extended; } if extended != Error.none { return false,Error.none; } return true,Error.none;
}
fn rewriteSource(view: Extension&,proof: const blot_backend_activation_graph::Cohort&,helpers: blot_runtime_cohort_runtime::Runtime) -> Error {
    let owner = proof.graph.sites[proof.owner]; var owner_end = blot_support::none<i64>(); var owner_local = blot_support::none<u32>(); let original_owner = view.module.functions[owner.function];
    for instruction,at in view.module.instructions(original_owner) { let fact = blot_backend_provider_origins::constructor(view.module,original_owner,at); if !fact.present || fact.value.allocation != owner.at { continue; } owner_end = blot_support::some(fact.value.end); owner_local = blot_support::some(fact.value.local); } if !owner_end.present { return Error.unsupported_cohort; }
    for function in 0..view.original_functions {
        var touched = owner.function == function; for site,id in proof.graph.sites { if (proof.members & (1 as u64 << id)) != 0 && site.function == function { touched = true; } } if !touched { continue; } let body,body_error = own(view,function as u32); if body_error != Error.none { return body_error; } assert(body != null); var replacement = Code {..};
        recursive fn lower() -> Error {
            for instruction,at in view.module.instructions(body) {
                var member = false; for site,id in proof.graph.sites { if (proof.members & (1 as u64 << id)) != 0 && site.function == function && site.at == at { member = true; } }
                if member {
                    let annotations = blot_backend_runtime_ir::allocationAnnotations(view.module.instructions(body),at); var mask: u32 = 0; var matched = false;
                    for site,id in proof.graph.sites { if (proof.members & (1 as u64 << id)) == 0 || site.function != function || site.at != at { continue; } if site.bytes / 4 > 31 { return Error.unsupported_cohort; } for word in 0..site.bytes / 4 { let role = blot_backend_runtime_ir::wordRole(annotations,word); if role == blot_backend_runtime_ir::ROLE_reference { mask |= 1 as u32 << word; } else if role != blot_backend_runtime_ir::ROLE_scalar { return Error.unsupported_cohort; } } matched = true; break; }
                    assert(view.module.arena.present); if !matched || instruction.op != blot_backend_runtime_ir::OP_call || !blot_backend_wasm::isAllocation(view.module.arena.value,instruction.operand) || body.provider_parameter >= body.parameters.len { return Error.unsupported_cohort; } let appended = replacement.append([blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,mask),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,body.provider_parameter as u32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,helpers.allocate)]); if appended != Error.none { return appended; }
                } else { let appended = replacement.push(instruction); if appended != Error.none { return appended; } }
                if owner.function == function && at == owner_end.value { assert(owner_local.present); let appended = replacement.append([blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,owner_local.value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,helpers.begin)]); if appended != Error.none { return appended; } }
            } return replaceBody(view,function as u32,replacement.items);
        }
        let error = lower(); replacement.deinit(); if error != Error.none { return error; }
    } return Error.none;
}
fn insert(view: Extension&,id: u32,position: i64,inserted: const Instruction[:]) -> Error {
    let body,error = own(view,id); if error != Error.none { return error; } assert(body != null); let original = view.module.instructions(body); if position < 0 || position > original.len { return Error.unsupported_cohort; } var replacement = Code {..};
    fn lower() -> Error { let prefix = replacement.append(original[..position]); if prefix != Error.none { return prefix; } let middle = replacement.append(inserted); if middle != Error.none { return middle; } let suffix = replacement.append(original[position..]); if suffix != Error.none { return suffix; } return replaceBody(view,id,replacement.items); }
    let result = lower(); replacement.deinit(); return result;
}
fn storeFastpath(view: Extension&) -> Error {
    assert(view.module.arena.present); let id = view.module.arena.value.store_word; let body,error = own(view,id); if error != Error.none { return error; } assert(body != null); var at = blot_support::none<i64>(); for instruction,index in view.module.instructions(body) { if instruction.op == blot_backend_runtime_ir::OP_wide_layouts { at = blot_support::some(index); break; } } if !at.present { return Error.unsupported_cohort; }
    let header = blot_runtime_runtime_layout::ArenaHeader_bytes; let flags = blot_runtime_runtime_layout::ArenaHeader_flags;
    return insert(view,id,at.value,[
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,header),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,flags),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,blot_runtime_cohort_runtime::member),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_and),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,header),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,flags),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,blot_runtime_cohort_runtime::owner),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_and),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eqz),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eqz),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,1),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eq),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_and),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_or),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,1),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,2),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_return_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)
    ]);
}
fn closedRetirement(view: Extension&,proof: const blot_backend_activation_graph::Cohort&,helper: u32) -> Error {
    var allowed = proof.members | (1 as u64 << proof.owner); for site,id in proof.graph.sites { if site.kind == blot_backend_activation_graph::SiteKind.static_data { allowed |= 1 as u64 << id; } } for site,id in proof.graph.sites { if (proof.members & (1 as u64 << id)) != 0 && (site.borrowed_head || (site.children & ~allowed) != 0) { return Error.unsupported_cohort; } }
    assert(view.module.arena.present); let arena = view.module.arena.value; let body = view.module.functions[helper]; var replacement = Code {..}; var found: i64 = 0;
    fn lower() -> Error {
        for instruction in view.module.instructions(body) {
            if instruction.op != blot_backend_runtime_ir::OP_call || instruction.operand != arena.retire { let copied = replacement.push(instruction); if copied != Error.none { return copied; } continue; }
            let appended = replacement.append([blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_get,arena.rc_destroyed),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,1),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_set,arena.rc_destroyed),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,arena.free)]); if appended != Error.none { return appended; } found++;
        }
        if found != 1 { return Error.unsupported_cohort; } return replaceBody(view,helper,replacement.items);
    }
    let error = lower(); replacement.deinit(); return error;
}
fn extendInto(view: Extension&,source: const Module&,proof: const blot_backend_activation_graph::Cohort&) -> Error {
    let detached = detachedInto(view,source); if detached != Error.none { return detached; }
    fn lower() -> Error {
        let helpers,error = blot_runtime_cohort_runtime::install(view.module); if error != Error.none { return error; } let rewritten = rewriteSource(view,proof,helpers); if rewritten != Error.none { return rewritten; } assert(source.arena.present); let arena = source.arena.value; let retired = insert(view,arena.retire,0,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,helpers.retire_members)]); if retired != Error.none { return retired; }
        let ids: u32[2] = [arena.cycle_enqueue,arena.cycle_visit]; let masks: u32[2] = [blot_runtime_cycles_runtime::enqueue_guard,blot_runtime_cycles_runtime::visit_guard];
        for id,index in ids { let instructions,error = mutableInstructions(view,id); if error != Error.none { return error; } var matched: i64 = 0; for &instruction in instructions { if instruction.op == blot_backend_runtime_ir::OP_i32_const && instruction.operand == masks[index] { instruction.operand |= blot_runtime_cohort_runtime::member | blot_runtime_cohort_runtime::owner; matched++; } } if matched != 1 { return Error.unsupported_cohort; } }
        let fastpath = storeFastpath(view); if fastpath != Error.none { return fastpath; } return closedRetirement(view,proof,helpers.retire_members);
    }
    let error = lower(); if error != Error.none { view.deinit(); } return error;
}
