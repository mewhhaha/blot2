// One owner for optimization scratch and detached replacements. Source IR stays
// immutable; replacing a prepared body releases its previous typed runs.
namespace blot_backend_runtime_pipeline;
import .runtime_ir;
import .wasm;
import .wasm_lifetimes;
import .wasm_inline;
import .wasm_sroa;
import .wasm_vectorize;
import .wasm_row_products;
import .wasm_row_reduce;
import .root_borrows;
import .root_lowering;
import .wasm_copy_coalesce;
import .wasm_stackify;
import .wasm_local_compact;
import .wasm_transport_cleanup;
import .wasm_local_order;
import .provider_modes;
import .host_entry;
import runtime.region_runtime;
import runtime.list_runtime;
import runtime.resource_safepoints;
import runtime.task_safepoints;
import compilation_tier;
import phase_profile;
import support.error;
import support.option;
type Error = blot_error::Error;
type Module = blot_backend_wasm::Module;
type Function = blot_backend_runtime_ir::Function;
type Body = blot_backend_runtime_ir::DetachedBody;
recursive fn borrowedParameter(module: const Module&,source: Function,depth: i64) -> blot_support::Option<u32> {
    if depth >= 32 || source.entry || source.result != blot_backend_runtime_ir::VT_i32 || source.result_role != blot_backend_runtime_ir::ROLE_value || module.locals(source).len != 0 { return blot_support::none<u32>(); } let instructions = module.instructions(source); var end = instructions.len; if end != 0 && instructions[end - 1].op == blot_backend_runtime_ir::OP_return_ { end--; } if end == 0 { return blot_support::none<u32>(); } let last = instructions[end - 1]; var parameter: u32;
    match last.op { blot_backend_runtime_ir::OP_local_get=>{ if end != 1 { return blot_support::none<u32>(); } parameter = last.operand; },blot_backend_runtime_ir::OP_call=>{ if last.operand >= module.functions.len { return blot_support::none<u32>(); } let callee = module.functions[last.operand]; let parameters = module.parameters(callee); let source_parameters = module.parameters(source); if end - 1 != parameters.len { return blot_support::none<u32>(); } for argument,index in instructions[..end - 1] { if argument.op != blot_backend_runtime_ir::OP_local_get || argument.operand >= source_parameters.len || source_parameters[argument.operand] != parameters[index] { return blot_support::none<u32>(); } } let returned = borrowedParameter(module,callee,depth + 1); if !returned.present { return blot_support::none<u32>(); } parameter = instructions[returned.value].operand; },_=>{ return blot_support::none<u32>(); }, }
    if parameter >= source.parameters.len || module.parameters(source)[parameter] != blot_backend_runtime_ir::VT_i32 || blot_backend_runtime_ir::parameterRole(source,parameter) != blot_backend_runtime_ir::ROLE_value { return blot_support::none<u32>(); } return blot_support::some(parameter);
}
struct Session {
    module: const Module? = null,summaries: blot_backend_wasm_lifetimes::Summaries,inline_facts: blot_backend_wasm_inline::Facts,providers: blot_backend_provider_modes::Catalog,
    roots: bool = false,needs_roots: bool = false,tier: blot_compilation_tier::Tier = blot_compilation_tier::Tier.optimized,
}
fn listCall(lists: blot_runtime_list_runtime::Runtime,id: u32) -> bool { const for <N,T> in fields<blot_runtime_list_runtime::Runtime> { let function = lists.functionId(N); if function.present && function.value == id { return true; } } return false; }
fn init(module: const Module&) -> Session,Error {
    let summaries,summary_error = blot_backend_wasm_lifetimes::initSummaries(module); if summary_error != Error.none { return Session {..},summary_error; } var owned_summaries = summaries; let facts,fact_error = blot_backend_wasm_inline::initFacts(module); if fact_error != Error.none { owned_summaries.deinit(); return Session {..},fact_error; } var result = Session { module,summaries: owned_summaries,inline_facts: facts,..};
    recursive fn prepare() -> Error {
        result.roots = module.arena.present && !module.mutable_static; for imported,index in module.imports { if !module.hostCallbackImport(index).present && !module.ownedCleanupBindImport(index) && !module.resourceImport(index) && !module.taskImport(index) { result.roots = false; break; } } for item in module.exports { if !item.global && !item.task_runtime && module.runtimeHelper(item.index) { result.roots = false; break; } }
        var needs_roots = module.host_references.present || module.public_arena || module.static_fields.len != 0 || module.start.present;
        if result.roots { for function,id in module.functions { if module.runtimeHelper(id) { continue; } if function.parameters.len >= 8192 || module.locals(function).len >= 8192 - function.parameters.len || (function.result_role != blot_backend_runtime_ir::ROLE_scalar && function.result_role != blot_backend_runtime_ir::ROLE_reference && !borrowedParameter(module,function,0).present) { result.roots = false; break; }
            for instruction in module.instructions(function) { if instruction.op == blot_backend_runtime_ir::OP_call { let arena = module.arena.value; if blot_backend_wasm::isAllocation(arena,instruction.operand) || instruction.operand == arena.allocate_typed || instruction.operand == arena.allocate_shaped || (module.regions.present && instruction.operand == module.regions.value.runtime.frame_allocate) { needs_roots = true; } if module.lists.present && listCall(module.lists.value,instruction.operand) { needs_roots = true; } }
                if instruction.op == blot_backend_runtime_ir::OP_global_set && blot_backend_runtime_ir::role(module.globals[instruction.operand].scalar) == blot_backend_runtime_ir::ROLE_reference && !module.start.present { result.roots = false; } if instruction.op != blot_backend_runtime_ir::OP_ownership { continue; } let scope = blot_backend_runtime_ir::ownership(instruction.operand); if scope.kind == blot_backend_runtime_ir::OWN_scope && scope.chunk == 15 { result.roots = false; }
            } if !result.roots { break; }
        } } if module.regions.present && !module.regions.value.valid(module) { result.roots = false; } result.needs_roots = needs_roots; if result.roots { let providers,error = blot_backend_provider_modes::init(module); if error != Error.none { return error; } result.providers = providers; } let providers = result.summaries.setProviders(result.providers.entries.items); if providers != Error.none { return providers; } return result.summaries.prepare();
    } let error = prepare(); if error != Error.none { result.deinit(); return Session {..},error; } return result,Error.none;
}
fn deinit(self: Session&) { self.inline_facts.deinit(); self.providers.deinit(); self.summaries.deinit(); self.module .= null; }
fn runtimeHelper(self: const Session&,id: u32) -> bool { assert(self.module); return self.module.runtimeHelper(id); }
fn borrowedHost(self: const Session&,function: Function) -> bool { assert(self.module); return function.result_role == blot_backend_runtime_ir::ROLE_scalar && blot_backend_host_entry::hostStub(self.module,function); }
fn borrowsOnly(self: const Session&,function: Function) -> bool {
    assert(self.module); let module .= self.module; if borrowedParameter(module,function,0).present { return true; } if function.result_role != blot_backend_runtime_ir::ROLE_scalar { return false; } let code = module.instructions(function);
    for instruction,at in code { match instruction.op {
        blot_backend_runtime_ir::OP_ownership=>{ let annotation = blot_backend_runtime_ir::ownership(instruction.operand); if annotation.kind == blot_backend_runtime_ir::OWN_scope && annotation.chunk != 0 && annotation.chunk != 1 && annotation.chunk != 14 { return false; } },
        blot_backend_runtime_ir::OP_call=>{ if module.runtimeHelper(instruction.operand) || module.functions[instruction.operand].result_role != blot_backend_runtime_ir::ROLE_scalar { return false; } },
        blot_backend_runtime_ir::OP_call_indirect=>{ if blot_backend_runtime_ir::indirectResult(code,at) != blot_backend_runtime_ir::ROLE_scalar { return false; } },blot_backend_runtime_ir::OP_call_import=>{ return false; },
        blot_backend_runtime_ir::OP_global_set=>{ if blot_backend_runtime_ir::role(module.globals[instruction.operand].scalar) == blot_backend_runtime_ir::ROLE_reference { return false; } },_=>{},
    } } return true;
}
fn viewBody(source: Function,body: Body) -> Function { var view = source; view.borrowed_body = true; view.borrowed_locals = body.locals; view.borrowed_instructions = body.instructions; view.locals = blot_backend_runtime_ir::Range { len: body.locals.len,..}; view.instructions = blot_backend_runtime_ir::Range { len: body.instructions.len,..}; view.annotations = 0; for instruction in body.instructions { if instruction.op == blot_backend_runtime_ir::OP_ownership { view.annotations++; } } return view; }
fn replace(owned: blot_support::Option<Body>&,view: Function&,replacement: Body) { if owned.present { owned.value.deinit(); } owned = blot_support::some(replacement); view = viewBody(view,replacement); }
enum Pass { inline_,scalar,vector,row_products,lifetime,reduce,rc }
fn telemetryPass(pass: Pass) -> blot_phase_profile::OptimizationPass { match pass { inline_=>blot_phase_profile::OptimizationPass.inline_,scalar=>blot_phase_profile::OptimizationPass.scalar,vector=>blot_phase_profile::OptimizationPass.vector,row_products=>blot_phase_profile::OptimizationPass.row_products,lifetime=>blot_phase_profile::OptimizationPass.lifetime,reduce=>blot_phase_profile::OptimizationPass.reduce,rc=>blot_phase_profile::OptimizationPass.rc } }
fn optimizePass(self: Session&,id: u32,view: Function,pass: Pass,scan: blot_backend_wasm_lifetimes::SharedScan&) -> blot_support::Option<Body>,Error {
    assert(self.module); if self.tier == blot_compilation_tier::Tier.development && pass != Pass.lifetime && pass != Pass.rc { return blot_support::none<Body>(),Error.none; }
    match pass {
        inline_=>{ return blot_backend_wasm_inline::runWithFacts(self.module,view,self.inline_facts); },scalar=>{ return blot_backend_wasm_sroa::runWithRoots(self.module,view,self.roots); },vector=>{ return blot_backend_wasm_vectorize::run(self.module,view); },row_products=>{ return blot_backend_wasm_row_products::run(self.module,view); },reduce=>{ return blot_backend_wasm_row_reduce::run(self.module,view); },
        rc=>{ if self.runtimeHelper(id) { return blot_support::none<Body>(),Error.none; } return blot_backend_wasm_lifetimes::runRc(self.module,view,self.summaries,scan); },lifetime=>{ return blot_backend_wasm_lifetimes::runWithSummaries(self.module,view,self.summaries,scan); },
    }
}
fn arenaHelper(self: const Session&,id: u32) -> bool { assert(self.module); let module .= self.module; if module.arena.present && blot_backend_wasm::arenaFunctionName(module.arena.value,id).present { return true; } if module.host_references.present { let references = module.host_references.value; if id == references.retain || id == references.release { return true; } } if module.cohorts.present && id == module.cohorts.value.allocate { return true; } return module.regions.present && module.regions.value.runtime.contains(id); }
fn optimize(self: Session&,id: u32) -> blot_support::Option<Body>,Error {
    assert(self.module && id < self.module.functions.len); let module .= self.module; let source = module.functions[id]; var function_region = blot_phase_profile::Region {..}; if module.instructions(source).len >= 256 { function_region = blot_phase_profile::region("runtime-ir.function",0,id,id); } var owned = blot_support::none<Body>(); var view = source; var provider_borrow = false; var scan = blot_backend_wasm_lifetimes::SharedScan {..};
    recursive fn transform() -> Error {
        if self.roots { let specialized,error = blot_backend_provider_modes::specialize(self.providers,blot_backend_provider_modes::functionView(module,source)); if error != Error.none { return error; } if specialized.present { owned = specialized; view = viewBody(source,specialized.value); provider_borrow = true; } }
        for pass in [Pass.inline_,Pass.scalar,Pass.vector,Pass.row_products,Pass.lifetime,Pass.reduce,Pass.rc] { let pass_region = blot_phase_profile::optimizationPass(telemetryPass(pass)); let before = module.instructions(view).len; let next,error = optimizePass(self,id,view,pass,scan); if next.present && error == Error.none { scan.invalidate(); replace(owned,view,next.value); } pass_region.exitWithItems(before,module.instructions(view).len); if error != Error.none { return error; } }
        if self.roots && !self.runtimeHelper(id) { let next,error = blot_backend_root_borrows::run(module,view); if error != Error.none { return error; } if next.present { replace(owned,view,next.value); } }
        if self.roots && !arenaHelper(self,id) { let entry = source.entry; let start = module.start.present && id == module.start.value; var borrows = borrowedHost(self,view) || borrowsOnly(self,view); if provider_borrow { borrows = borrowedHost(self,source) || borrowsOnly(self,source); } let framed = self.needs_roots && !self.runtimeHelper(id) && (entry || start || !borrows); var owner = blot_support::none<u32>(); let scope = blot_runtime_region_runtime::scope(module,id); if scope.present { owner = blot_support::some(scope.value.parameter); } let next,error = blot_backend_root_lowering::runScoped(module,view,framed,entry,start,provider_borrow,owner); if error != Error.none { return error; } if next.present { replace(owned,view,next.value); } }
        if !self.runtimeHelper(id) && !module.resourceAdapterFunction(id) { let next,error = blot_runtime_resource_safepoints::run(module,view); if error != Error.none { return error; } if next.present { replace(owned,view,next.value); } }
        if !self.runtimeHelper(id) && !module.resourceAdapterFunction(id) && !module.taskAdapterFunction(id) { let next,error = blot_runtime_task_safepoints::run(module,view); if error != Error.none { return error; } if next.present { replace(owned,view,next.value); } }
        if module.memory_model == blot_backend_wasm::MemoryModel.data_stacks {
            let coalesced,coalesce_error = blot_backend_wasm_copy_coalesce::runSingle(module,view); if coalesce_error != Error.none { return coalesce_error; } if coalesced.present { replace(owned,view,coalesced.value); }
            let stackified,stack_error = blot_backend_wasm_stackify::run(module,view); if stack_error != Error.none { return stack_error; } if stackified.present { replace(owned,view,stackified.value); }
            let compacted,compact_error = blot_backend_wasm_local_compact::run(module,view); if compact_error != Error.none { return compact_error; } if compacted.present { replace(owned,view,compacted.value); }
            let transport,transport_error = blot_backend_wasm_transport_cleanup::run(module,view); if transport_error != Error.none { return transport_error; } if transport.present { replace(owned,view,transport.value); }
            let ordered,order_error = blot_backend_wasm_local_order::run(module,view); if order_error != Error.none { return order_error; } if ordered.present { replace(owned,view,ordered.value); }
        } return Error.none;
    }
    let error = transform(); scan.deinit(); function_region.exit(); if error != Error.none { if owned.present { owned.value.deinit(); } return blot_support::none<Body>(),error; } return owned,Error.none;
}
