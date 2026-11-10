// Detached late bodies for a freshly rederived closed activation.
namespace blot_backend_cohort_candidate;
import .wasm;
import .region_candidate;
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
struct Flags { storage: bool[:] = default<bool[:]>(),items: bool[:] = default<bool[:]>() }
struct Code { storage: Instruction[:] = default<Instruction[:]>(),items: Instruction[:] = default<Instruction[:]>() }
reusable[] var flag_runs: bool[>..] = [];
reusable[] var code_runs: Instruction[>..] = [];
fn push(flags: Flags&,value: bool) -> Error { blot_support_pooled_buffer::push(flags,value,flag_runs) }
fn deinit(flags: Flags&) { blot_support_pooled_buffer::deinit(flags,flag_runs); }
fn push(code: Code&,value: Instruction) -> Error { blot_support_pooled_buffer::push(code,value,code_runs) }
fn append(code: Code&,values: const Instruction[:]) -> Error { blot_support_pooled_buffer::append(code,values,code_runs) }
fn deinit(code: Code&) { blot_support_pooled_buffer::deinit(code,code_runs); }
struct Extension { module: Module&,original_functions: i64 = 0,original_signatures: i64 = 0,owned: Flags,active: bool = false,region_members:blot_runtime_region_runtime::Member[:]=default<blot_runtime_region_runtime::Member[:]>(),region_scopes:blot_runtime_region_runtime::Scope[:]=default<blot_runtime_region_runtime::Scope[:]>() }
fn init(module: Module&) -> Extension { Extension { module } }
fn deinit(view: Extension&) { if view.active { view.module.reset(); } view.owned.deinit();if view.region_members.len!=0 {blot_backend_region_candidate::member_runs.free_slice(view.region_members);}if view.region_scopes.len!=0 {blot_backend_region_candidate::scope_runs.free_slice(view.region_scopes);}view.region_members=default<blot_runtime_region_runtime::Member[:]>();view.region_scopes=default<blot_runtime_region_runtime::Scope[:]>(); view.original_functions = 0; view.original_signatures = 0; view.active = false; }
fn possible(source: const Module&) -> bool { if !source.arena.present || source.semantic_sites.len == 0 || source.cohorts.present { return false; } for origin in source.table_origins { if origin.kind == blot_backend_runtime_ir::TABLE_callable { return true; } } return false; }
fn own(view: Extension&,id: u32) -> Function?,Error {
    if !view.active || id >= view.module.functions.len { return null,blot_error::Error.invalid_function_reference; } if id < view.original_functions && !view.owned.items[id] { let error = view.module.materializeBody(id); if error != blot_error::Error.none { return null,error; } view.owned.items[id] = true; } return view.module.functions[id],blot_error::Error.none;
}
fn mutableInstructions(view: Extension&,id: u32) -> Instruction[:],Error { let body,error = own(view,id); if error != blot_error::Error.none { return default<Instruction[:]>(),error; } assert(body != null); return view.module.instructions[body.instructions.start..body.instructions.start + body.instructions.len],blot_error::Error.none; }
fn replaceBody(view: Extension&,id: u32,code: const Instruction[:]) -> Error { let body,error = own(view,id); if error != blot_error::Error.none { return error; } assert(body != null); return view.module.publishInstructions(id,code); }
fn detachedInto(view: Extension&,source: const Module&) -> Error {
    assert(!(view.module .== source)); deinit(view); let destination .= view.module;
    destination=Module{
        memory_model:source.memory_model,artifacts:null,
        types:destination.types,instructions:destination.instructions,names:destination.names,
        functions:destination.functions,signatures:destination.signatures,imports:destination.imports,globals:destination.globals,exports:destination.exports,data:destination.data,
        fixed_memory_bytes:source.fixed_memory_bytes,array_transport:source.array_transport,arena:source.arena,
        fixture_helpers_present:source.fixture_helpers_present,fixture_helpers:source.fixture_helpers,
        lists:source.lists,cohorts:source.cohorts,regions:blot_support::none<blot_runtime_region_runtime::Prepared>(),host_references:source.host_references,public_arena:source.public_arena,
        cleanup_data:source.cleanup_data,defer_cycles:source.defer_cycles,mutable_static:source.mutable_static,
        static_fields:destination.static_fields,table_functions:destination.table_functions,table_origins:destination.table_origins,semantic_sites:destination.semantic_sites,
        indirect:source.indirect,start:source.start
    };
    view.active=true;view.original_functions=source.functions.len;view.original_signatures=source.signatures.len;
    if source.regions.present {
        let region=source.regions.value;let members=blot_backend_region_candidate::member_runs.alloc_slice(region.plan.members.len);let scopes=blot_backend_region_candidate::scope_runs.alloc_slice(region.scopes.len);
        for member,index in region.plan.members {members[index]=member;}for scope,index in region.scopes {scopes[index]=scope;}
        view.region_members=members;view.region_scopes=scopes;
        destination.regions=blot_support::some(blot_runtime_region_runtime::Prepared{runtime:region.runtime,plan:blot_runtime_region_runtime::Plan{frame_bytes:region.plan.frame_bytes,bytes:region.plan.bytes,mask:region.plan.mask,members:members},scopes:scopes});
    }
    destination.types.append(source.types);destination.instructions.append(source.instructions);destination.names.append(source.names);destination.signatures.append(source.signatures);destination.imports.append(source.imports);destination.globals.append(source.globals);destination.exports.append(source.exports);destination.data.append(source.data);destination.static_fields.append(source.static_fields);destination.table_functions.append(source.table_functions);destination.table_origins.append(source.table_origins);destination.semantic_sites.append(source.semantic_sites);
    // Bodies use destination ranges, never slices into a growable source owner.
    // Ordinary ranges remain unchanged; a pre-detached body is copied once.
    for id in view.original_functions {
        let original=source.functions[id];var locals=original.locals;var instructions=original.instructions;
        if original.borrowed_body {let body=blot_backend_wasm::publishBody(destination,original.borrowed_locals,original.borrowed_instructions);locals=body.locals;instructions=body.instructions;}
        destination.functions.push(Function{parameters:original.parameters,result:original.result,result_role:original.result_role,entry:original.entry,provider_parameter:original.provider_parameter,callable_layout:original.callable_layout,signature:original.signature,parameter_roles:original.parameter_roles,annotations:original.annotations,locals:locals,instructions:instructions,..});
        let flag=view.owned.push(true);if flag!=blot_error::Error.none {view.deinit();return flag;}
    }
    return blot_error::Error.none;
}
fn namedFunction(model: blot_backend_activation_intersection::Model,id: i64) -> bool { for entry in model.functions { if entry.function != id { continue; } match entry.request { named=>{ return true; },_=>{}, } } return false; }
fn prepareInto(view: Extension&,source: const Module&,model: blot_backend_activation_intersection::Model) -> bool,Error {
    if !possible(source) { return false,blot_error::Error.none; }
    for body,id in source.functions { if body.entry || body.result_role != blot_backend_runtime_ir::ROLE_scalar || !namedFunction(model,id) { continue; } var installation = false; for instruction,at in blot_backend_wasm::instructions(source,body) { if blot_backend_provider_origins::constructor(source,body,at).present { installation = true; break; } } if !installation { continue; } let admitted,error = checkedInto(view,source,model,id as u32); if error != blot_error::Error.none || admitted { return admitted,error; } } return false,blot_error::Error.none;
}
fn checkedInto(view: Extension&,source: const Module&,model: blot_backend_activation_intersection::Model,boundary: u32) -> bool,Error {
    let selected,error = blot_backend_activation_intersection::analyze(source,model,boundary); if error != blot_error::Error.none { return false,error; } if !selected.present { return false,blot_error::Error.none; } var proof = selected.value; let extended = extendInto(view,source,proof.runtime); proof.deinit(); if extended == blot_error::Error.out_of_memory { return false,extended; } if extended != blot_error::Error.none { return false,blot_error::Error.none; } return true,blot_error::Error.none;
}
fn rewriteSource(view: Extension&,proof: const blot_backend_activation_graph::Cohort&,helpers: blot_runtime_cohort_runtime::Runtime) -> Error {
    let owner = proof.graph.sites[proof.owner]; var owner_end = blot_support::none<i64>(); var owner_local = blot_support::none<u32>(); let original_owner = view.module.functions[owner.function];
    for instruction,at in blot_backend_wasm::instructions(view.module,original_owner) { let fact = blot_backend_provider_origins::constructor(view.module,original_owner,at); if !fact.present || fact.value.allocation != owner.at { continue; } owner_end = blot_support::some(fact.value.end); owner_local = blot_support::some(fact.value.local); } if !owner_end.present { return blot_error::Error.unsupported_cohort; }
    for function in 0..view.original_functions {
        var touched = owner.function == function; for site,id in proof.graph.sites { if (proof.members & (1 as u64 << id)) != 0 && site.function == function { touched = true; } } if !touched { continue; } let body,body_error = own(view,function as u32); if body_error != blot_error::Error.none { return body_error; } assert(body != null); var replacement = Code {..};
        recursive fn lower() -> Error {
            for instruction,at in blot_backend_wasm::instructions(view.module,body) {
                var member = false; for site,id in proof.graph.sites { if (proof.members & (1 as u64 << id)) != 0 && site.function == function && site.at == at { member = true; } }
                if member {
                    let annotations = blot_backend_runtime_ir::allocationAnnotations(blot_backend_wasm::instructions(view.module,body),at); var mask: u32 = 0; var matched = false;
                    for site,id in proof.graph.sites { if (proof.members & (1 as u64 << id)) == 0 || site.function != function || site.at != at { continue; } if site.bytes / 4 > 31 { return blot_error::Error.unsupported_cohort; } for word in 0..site.bytes / 4 { let role = blot_backend_runtime_ir::wordRole(annotations,word); if role == blot_backend_runtime_ir::ROLE_reference { mask |= 1 as u32 << word; } else if role != blot_backend_runtime_ir::ROLE_scalar { return blot_error::Error.unsupported_cohort; } } matched = true; break; }
                    assert(view.module.arena.present); if !matched || instruction.op != blot_backend_runtime_ir::OP_call || !blot_backend_wasm::isAllocation(view.module.arena.value,instruction.operand) || body.provider_parameter >= body.parameters.len { return blot_error::Error.unsupported_cohort; } let appended = replacement.append([blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,mask),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,body.provider_parameter as u32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,helpers.allocate)]); if appended != blot_error::Error.none { return appended; }
                } else { let appended = replacement.push(instruction); if appended != blot_error::Error.none { return appended; } }
                if owner.function == function && at == owner_end.value { assert(owner_local.present); let appended = replacement.append([blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,owner_local.value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,helpers.begin)]); if appended != blot_error::Error.none { return appended; } }
            } return replaceBody(view,function as u32,replacement.items);
        }
        let error = lower(); replacement.deinit(); if error != blot_error::Error.none { return error; }
    } return blot_error::Error.none;
}
fn insert(view: Extension&,id: u32,position: i64,inserted: const Instruction[:]) -> Error {
    let body,error = own(view,id); if error != blot_error::Error.none { return error; } assert(body != null); let original = blot_backend_wasm::instructions(view.module,body); if position < 0 || position > original.len { return blot_error::Error.unsupported_cohort; } var replacement = Code {..};
    fn lower() -> Error { let prefix = replacement.append(original[..position]); if prefix != blot_error::Error.none { return prefix; } let middle = replacement.append(inserted); if middle != blot_error::Error.none { return middle; } let suffix = replacement.append(original[position..]); if suffix != blot_error::Error.none { return suffix; } return replaceBody(view,id,replacement.items); }
    let result = lower(); replacement.deinit(); return result;
}
fn storeFastpath(view: Extension&) -> Error {
    assert(view.module.arena.present); let id = view.module.arena.value.store_word; let body,error = own(view,id); if error != blot_error::Error.none { return error; } assert(body != null); var at = blot_support::none<i64>(); for instruction,index in blot_backend_wasm::instructions(view.module,body) { if instruction.op == blot_backend_runtime_ir::OP_wide_layouts { at = blot_support::some(index); break; } } if !at.present { return blot_error::Error.unsupported_cohort; }
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
    var allowed = proof.members | (1 as u64 << proof.owner); for site,id in proof.graph.sites { if site.kind == blot_backend_activation_graph::SiteKind.static_data { allowed |= 1 as u64 << id; } } for site,id in proof.graph.sites { if (proof.members & (1 as u64 << id)) != 0 && (site.borrowed_head || (site.children & ~allowed) != 0) { return blot_error::Error.unsupported_cohort; } }
    assert(view.module.arena.present); let arena = view.module.arena.value; let body = view.module.functions[helper]; var replacement = Code {..}; var found: i64 = 0;
    fn lower() -> Error {
        for instruction in blot_backend_wasm::instructions(view.module,body) {
            if instruction.op != blot_backend_runtime_ir::OP_call || instruction.operand != arena.retire { let copied = replacement.push(instruction); if copied != blot_error::Error.none { return copied; } continue; }
            let appended = replacement.append([blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_get,arena.rc_destroyed),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,1),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_set,arena.rc_destroyed),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,arena.free)]); if appended != blot_error::Error.none { return appended; } found++;
        }
        if found != 1 { return blot_error::Error.unsupported_cohort; } return replaceBody(view,helper,replacement.items);
    }
    let error = lower(); replacement.deinit(); return error;
}
fn extendInto(view: Extension&,source: const Module&,proof: const blot_backend_activation_graph::Cohort&) -> Error {
    let detached = detachedInto(view,source); if detached != blot_error::Error.none { return detached; }
    fn lower() -> Error {
        let helpers,error = blot_runtime_cohort_runtime::install(view.module); if error != blot_error::Error.none { return error; } let rewritten = rewriteSource(view,proof,helpers); if rewritten != blot_error::Error.none { return rewritten; } assert(source.arena.present); let arena = source.arena.value; let retired = insert(view,arena.retire,0,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,helpers.retire_members)]); if retired != blot_error::Error.none { return retired; }
        let ids: u32[2] = [arena.cycle_enqueue,arena.cycle_visit]; let masks: u32[2] = [blot_runtime_cycles_runtime::enqueue_guard,blot_runtime_cycles_runtime::visit_guard];
        for id,index in ids { let instructions,error = mutableInstructions(view,id); if error != blot_error::Error.none { return error; } var matched: i64 = 0; for &instruction in instructions { if instruction.op == blot_backend_runtime_ir::OP_i32_const && instruction.operand == masks[index] { instruction.operand |= blot_runtime_cohort_runtime::member | blot_runtime_cohort_runtime::owner; matched++; } } if matched != 1 { return blot_error::Error.unsupported_cohort; } }
        let fastpath = storeFastpath(view); if fastpath != blot_error::Error.none { return fastpath; } return closedRetirement(view,proof,helpers.retire_members);
    }
    let error = lower(); if error != blot_error::Error.none { view.deinit(); } return error;
}
