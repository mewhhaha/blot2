// A physical region is authorized only by freshly intersected owned graphs.
namespace blot_backend_region_candidate;
import .wasm;
import .runtime_ir;
import .cohort_candidate;
import .activation_graph;
import .activation_intersection;
import .provider_origins;
import runtime.region_runtime;
import runtime.runtime_layout;
import support.error;
import support.option;
import support.pooled_buffer;
type Error = blot_error::Error;
type Module = blot_backend_wasm::Module;
type Member = blot_runtime_region_runtime::Member;
type Scope = blot_runtime_region_runtime::Scope;
let absent: u32 = 4294967295;
struct Members { storage: Member[:] = default<Member[:]>(),items: Member[:] = default<Member[:]>() }
struct Scopes { storage: Scope[:] = default<Scope[:]>(),items: Scope[:] = default<Scope[:]>() }
reusable[] var member_runs: Member[>..] = [];
reusable[] var scope_runs: Scope[>..] = [];
fn push(buffer: Members&,member: Member) -> Error { blot_support_pooled_buffer::push(buffer,member,member_runs) }
fn push(buffer: Scopes&,scope: Scope) -> Error { blot_support_pooled_buffer::push(buffer,scope,scope_runs) }
fn deinit(buffer: Members&) { blot_support_pooled_buffer::deinit(buffer,member_runs); }
fn deinit(buffer: Scopes&) { blot_support_pooled_buffer::deinit(buffer,scope_runs); }
struct Extension { view: blot_backend_cohort_candidate::Extension&,members: Member[:] = default<Member[:]>(),scopes: Scope[:] = default<Scope[:]>(),boundary: u32 = 0 }
fn init(view: blot_backend_cohort_candidate::Extension&) -> Extension { Extension { view } }
fn deinit(extension: Extension&) { extension.view.deinit(); if extension.members.len != 0 { member_runs.free_slice(extension.members); } if extension.scopes.len != 0 { scope_runs.free_slice(extension.scopes); } extension.members=default<Member[:]>(); extension.scopes=default<Scope[:]>(); extension.boundary = 0; }
fn prepareInto(result: Extension&,source: const Module&,model: blot_backend_activation_intersection::Model) -> bool,Error {
    if !blot_backend_cohort_candidate::possible(source) || source.regions.present { return false,blot_error::Error.none; }
    for body,id in source.functions {
        if body.entry || body.result_role != blot_backend_runtime_ir::ROLE_scalar || !blot_backend_cohort_candidate::namedFunction(model,id) { continue; } var installation = false; for instruction,at in blot_backend_wasm::instructions(source,body) { if blot_backend_provider_origins::constructor(source,body,at).present { installation = true; break; } } if !installation { continue; }
        let admitted,error = checkedInto(result,source,model,id as u32); if error != blot_error::Error.none || admitted { return admitted,error; }
    } return false,blot_error::Error.none;
}
fn checkedInto(result: Extension&,source: const Module&,model: blot_backend_activation_intersection::Model,boundary: u32) -> bool,Error {
    let selected,error = blot_backend_activation_intersection::analyze(source,model,boundary); if error != blot_error::Error.none { return false,error; } if !selected.present { return false,blot_error::Error.none; } var proof = selected.value; let extended = extendInto(result,source,proof); proof.deinit(); if extended == blot_error::Error.out_of_memory { return false,extended; } if extended != blot_error::Error.none { return false,blot_error::Error.none; } return true,blot_error::Error.none;
}
fn extendInto(result: Extension&,source: const Module&,proof: const blot_backend_activation_intersection::Intersection&) -> Error {
    let graph .= proof.runtime.graph; let owner = graph.sites[proof.runtime.owner]; let original = source.functions[owner.function]; var constructor = blot_support::none<blot_backend_provider_origins::Fact>();
    for instruction,at in blot_backend_wasm::instructions(source,original) { let fact = blot_backend_provider_origins::constructor(source,original,at); if fact.present && fact.value.allocation == owner.at { constructor = fact; } }
    if !constructor.present { return blot_error::Error.unavailable; } let fact = constructor.value; if fact.kind != blot_runtime_runtime_layout::StateFrame_tag || fact.value_role != blot_backend_runtime_ir::ROLE_reference || owner.bytes != blot_runtime_runtime_layout::StateFrame_bytes { return blot_error::Error.unavailable; } var scopes = Scopes {..}; var members = Members {..};
    fn construct() -> Error {
        let owner_bit = 1 as u64 << proof.runtime.owner;
        for body,id in source.functions { var used = false; for context,context_id in graph.contexts { if context.function != id || context_id == 0 { continue; } if context.provider != owner_bit || context.outside_provider || body.provider_parameter >= body.parameters.len { return blot_error::Error.unavailable; } used = true; } if used { let appended = scopes.push(Scope { function: id as u32,parameter: body.provider_parameter as u32 , ..}); if appended != blot_error::Error.none { return appended; } } }
        var size = owner.bytes; var offsets: u32[64] = [absent;64];
        for site,id in graph.sites { if (proof.runtime.members & (1 as u64 << id)) == 0 { continue; } for previous,previous_id in graph.sites[..id] { if (proof.runtime.members & (1 as u64 << previous_id)) == 0 { continue; } if site.function == previous.function && site.at == previous.at { return blot_error::Error.unavailable; } } offsets[id] = size; let appended = members.push(Member { offset: size,bytes: site.bytes , ..}); if appended != blot_error::Error.none { return appended; } if site.bytes > 4294967295 - size { return blot_error::Error.unavailable; } size += site.bytes; }
        var mask: u32 = 0; let annotations = blot_backend_runtime_ir::allocationAnnotations(blot_backend_wasm::instructions(source,original),owner.at);
        for word in 0..owner.bytes / 4 { let role = blot_backend_runtime_ir::wordRole(annotations,word); if role != blot_backend_runtime_ir::ROLE_reference && role != blot_backend_runtime_ir::ROLE_scalar { return blot_error::Error.unavailable; } if word != blot_runtime_runtime_layout::StateFrame_value / 4 && role == blot_backend_runtime_ir::ROLE_reference { mask |= 1 as u32 << word; } }
        let plan = blot_runtime_region_runtime::Plan { frame_bytes: owner.bytes,bytes: size,mask: mask,members: members.items , ..}; if !plan.valid() { return blot_error::Error.unavailable; } let detached = blot_backend_cohort_candidate::detachedInto(result.view,source); if detached != blot_error::Error.none { return detached; } result.boundary = owner.function;
        if members.items.len != 0 { result.members = member_runs.alloc_slice(members.items.len); for member,index in members.items { result.members[index] = member; } } if scopes.items.len != 0 { result.scopes = scope_runs.alloc_slice(scopes.items.len); for scope,index in scopes.items { result.scopes[index] = scope; } }
        fn rewrite() -> Error {
            let owned_plan = blot_runtime_region_runtime::Plan { frame_bytes: plan.frame_bytes,bytes: plan.bytes,mask: plan.mask,members: result.members , ..}; let helpers,error = blot_runtime_region_runtime::install(result.view.module,owned_plan); if error != blot_error::Error.none { return error; } result.view.module.regions = blot_support::some(blot_runtime_region_runtime::Prepared { runtime: helpers,plan: owned_plan,scopes: result.scopes , ..});
            for function in 0..result.view.original_functions {
                var touched = function == owner.function; for site,id in graph.sites { if (proof.runtime.members & (1 as u64 << id)) != 0 && site.function == function { touched = true; } } if !touched { continue; } let body,body_error = result.view.own(function as u32); if body_error != blot_error::Error.none { return body_error; } assert(body != null); var replacement = blot_backend_cohort_candidate::Code {..};
                fn rewriteBody() -> Error {
                    for instruction,at in blot_backend_wasm::instructions(result.view.module,body) {
                        var offset = blot_support::none<u32>(); for site,id in graph.sites { if offsets[id] != absent && site.function == function && site.at == at { offset = blot_support::some(offsets[id]); } }
                        if offset.present { assert(source.arena.present); if instruction.op != blot_backend_runtime_ir::OP_call || !blot_backend_wasm::isAllocation(source.arena.value,instruction.operand) { return blot_error::Error.unavailable; } let appended = replacement.append([blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_drop),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,body.provider_parameter as u32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,offset.value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,helpers.member_at)]); if appended != blot_error::Error.none { return appended; } }
                        else if function == owner.function && at == owner.at { var changed = instruction; changed.operand = helpers.frame_allocate; let appended = replacement.push(changed); if appended != blot_error::Error.none { return appended; } } else { let appended = replacement.push(instruction); if appended != blot_error::Error.none { return appended; } }
                    } return blot_backend_cohort_candidate::replaceBody(result.view,function as u32,replacement.items);
                }
                let rewritten = rewriteBody(); replacement.deinit(); if rewritten != blot_error::Error.none { return rewritten; }
            } return blot_error::Error.none;
        }
        let rewritten = rewrite(); if rewritten != blot_error::Error.none { result.deinit(); } return rewritten;
    }
    let error = construct(); members.deinit(); scopes.deinit(); return error;
}
