// Code identities, immutable source proofs and startup storage for one run.
namespace blot_backend_backend_plan;
import dictionary;
import check.core;
import check.numeric_proof_core;
import .core_backend;
import .backend_emission;
import .wasm;
import .runtime_ir;
import .layout;
import .startup_graph;
import .startup_runtime_reach;
import .startup_occurrence_flow;
import .startup_occurrence_plan;
import .startup_emission_facts;
import .runtime_operations;
import .function_facts;
import .owned_arrays;
import .discarded_bindings;
import .unit_index;
import .resolved_body;
import reuse.code_artifacts;
import reuse.refinement_receipt;
import support.error;
import support.option;
type Error = blot_error::Error;
type Key = blot_reuse_code_artifacts::Key;
type Mapping = blot_backend_layout::Mapping;
type RowMapping = blot_backend_layout::RowMapping;
struct RuntimeSlot { global: u32,initializer: u32,active: bool = true }
struct State {
    bodies: blot_backend_resolved_body::Store<blot_backend_backend_emission::Plan>&,
    instances: dictionary<Key,u32>&,template_results: dictionary<Key,u32>&,template_catalog: blot_reuse_code_artifacts::CapturedTemplate[>..<]&,template_instances: dictionary<blot_reuse_code_artifacts::CapturedTemplate,u32>&,
    closures: dictionary<blot_reuse_code_artifacts::ClosureKey,u32>&,closure_template_results: dictionary<blot_reuse_code_artifacts::ClosureKey,u32>&,callables: dictionary<blot_reuse_code_artifacts::CallableKey,u32>&,carrier_adapters: dictionary<blot_backend_backend_emission::CarrierKey,u32>&,
    constructor_functions: dictionary<blot_reuse_code_artifacts::ConstructorKey,u32>&,primitive_functions: dictionary<blot_reuse_code_artifacts::PrimitiveKey,u32>&,operation_functions: dictionary<blot_reuse_code_artifacts::OperationKey,u32>&,runtime_operations: blot_backend_runtime_operations::Store&,
    host_functions: dictionary<blot_reuse_code_artifacts::HostKey,u32>&,runtime_globals: dictionary<blot_check_core::BindingRef,RuntimeSlot>&,
    runtime_plan_confirmed: bool = false,occurrence_plan_active: bool = false,occurrence_plan_cells: const blot_check_core::BindingRef[:] = [],startup_facts: blot_backend_startup_emission_facts::Store&,runtime_order: u32[>..<]&,
    array_proofs: dictionary<u32,blot_backend_owned_arrays::Proof>&,numeric_plans: dictionary<u32,blot_check_numeric_proof_core::Plan>&,facts: blot_backend_function_facts::Store&,
    discard_proofs: dictionary<u32,blot_backend_discarded_bindings::Proof>&,discard_flags: bool[>..<]&,quantified: dictionary<u32,blot_backend_unit_index::Quantified>&,uses: dictionary<u32,blot_backend_unit_index::Uses&?>&,task_movers: dictionary<u32,u32>&,
}
fn init(state: State&) { state.runtime_plan_confirmed = false; state.occurrence_plan_active = false; state.occurrence_plan_cells = []; }
fn deinit(state: State&) {
    state.bodies.deinit();
    state.instances.clear(); state.template_results.clear(); state.template_catalog.clear(); state.template_instances.clear(); state.closures.clear(); state.closure_template_results.clear(); state.callables.clear(); state.carrier_adapters.clear();
    state.constructor_functions.clear(); state.primitive_functions.clear(); state.operation_functions.clear(); state.runtime_operations.deinit(); state.host_functions.clear(); state.runtime_globals.clear(); state.startup_facts.deinit(); state.runtime_order.clear();
    state.array_proofs.each() { key,proof => proof.deinit(); } state.array_proofs.clear(); state.numeric_plans.each() { key,plan => plan.deinit(); } state.numeric_plans.clear(); state.facts.deinit(); state.discard_proofs.clear(); state.discard_flags.clear();
    state.quantified.each() { key,set => set.deinit(); } state.quantified.clear(); state.uses.each() { key,index => { assert(index); index.deinit(); blot_backend_unit_index::release(index); } } state.uses.clear(); state.task_movers.clear(); init(state);
}
fn runtimeGlobal(state: State&,generator: blot_backend_core_backend::Generator&,target: blot_check_core::BindingRef) -> u32,Error {
    let scope,error = blot_backend_core_backend::enterScope(generator,blot_reuse_code_artifacts::Request.runtime_global { target , ..}); if error != Error.none { return 0,error; } 
    recursive fn cleanup_continuation_4() -> u32,Error {

    if state.occurrence_plan_active { var included = false; for cell in state.occurrence_plan_cells { if cell == target { included = true; break; } } if !included { return 0,generator.decline(target.unit,generator.unit(target.unit).binding(target.binding).span,blot_backend_core_backend::Code.constant_expression); } }
    var global = blot_backend_startup_emission_facts::none; var active = true; block { let slot = state.runtime_globals.get(target); if slot { global = slot.global; active = slot.active; } }
    let event = state.startup_facts.event(blot_backend_startup_emission_facts::Event { kind: blot_backend_startup_emission_facts::EventKind.runtime_global_request,caller: state.startup_facts.active,target: global,unit: target.unit,identity: target.binding,flag: active , ..}); if event != Error.none { return 0,event; }
    block {
        let slot = state.runtime_globals.get(target);
        if slot {
            if !state.runtime_plan_confirmed && slot.active { return 0,generator.decline(target.unit,generator.unit(target.unit).binding(target.binding).span,blot_backend_core_backend::Code.constant_expression); }
            if scope.present { let hit = scope.value.hitGlobal(slot.global); if hit != Error.none { return 0,hit; } } return slot.global,Error.none;
        }
    }
    let source .= generator.unit(target.unit); let body .= source.body(target.binding); if body == null { return 0,generator.decline(target.unit,source.binding(target.binding).span,blot_backend_core_backend::Code.unsupported); }
    if !body.runtime || body.is_function { return 0,generator.decline(target.unit,body.span,blot_backend_core_backend::Code.unsupported); }
    let expected,layout_error = generator.codeLayout(target.unit,body.scheme.root,[],body.span); if layout_error != Error.none { return 0,layout_error; }
    var scalar = blot_backend_runtime_ir::SC_pointer; let primitive = generator.representations.store.scalar(expected); if primitive.present { scalar = primitive.value; }
    let global_id,global_error = generator.module.addGlobal(scalar,0,true); if global_error != Error.none { return 0,global_error; }
    let initializer,initializer_error = generator.module.addTypedFunction([],blot_backend_runtime_ir::VT_none,blot_backend_runtime_ir::ROLE_scalar); if initializer_error != Error.none { return 0,initializer_error; }
    state.runtime_globals.insert(target,RuntimeSlot { global_id,initializer , ..});
    let registered = state.startup_facts.event(blot_backend_startup_emission_facts::Event { kind: blot_backend_startup_emission_facts::EventKind.cell_registration,target: global_id,unit: target.unit,identity: target.binding,auxiliary: initializer , ..}); if registered != Error.none { return 0,registered; }
    if !state.runtime_plan_confirmed { let emitted = emitRuntimeInitializer(state,generator,target); if emitted != Error.none { return 0,emitted; } }
    if scope.present { let hit = scope.value.hitGlobal(global_id); if hit != Error.none { return 0,hit; } } return global_id,Error.none;

    }
    let cleanup_result_4_0,cleanup_result_4_1 = cleanup_continuation_4();
     if scope.present { scope.value.deinit(); } 
    return cleanup_result_4_0,cleanup_result_4_1;
}
struct InitializerEmission { root: u32,global: u32 }
fn emitInitializerOwner(context: InitializerEmission&,emitter: blot_backend_backend_emission::Owner&) -> Error { let body = emitter.bodyExpression(context.root,0,false); if body != Error.none { return body; } return emitter.emit(blot_backend_runtime_ir::OP_global_set,context.global); }
fn emitRuntimeInitializer(state: State&,generator: blot_backend_core_backend::Generator&,target: blot_check_core::BindingRef) -> Error {
    var slot: RuntimeSlot; block { let found = state.runtime_globals.get(target); if found == null { return Error.invalid_global_reference; } slot = found; } if !slot.active { return Error.none; }
    let scope,scope_error = blot_backend_core_backend::enterScope(generator,blot_reuse_code_artifacts::Request.runtime_global { target , ..}); if scope_error != Error.none { return scope_error; } 
    recursive fn cleanup_continuation_3() -> Error {

    let requested = state.startup_facts.request(slot.initializer,blot_backend_startup_emission_facts::Kind.runtime_initializer,target.unit,target.binding,false); if requested != Error.none { return requested; }
    let caller = state.startup_facts.active; state.startup_facts.active = slot.initializer; 
    recursive fn cleanup_continuation_2() -> Error {

    let source .= generator.unit(target.unit); let body .= source.body(target.binding); if body == null { return Error.invalid_global_reference; }
    var mappings: Mapping[>..<] = []; var rows: RowMapping[>..<] = []; let expected,error = generator.codeLayout(target.unit,body.scheme.root,[],body.span); if error != Error.none { return error; }
    let mapped = generator.mapTypeDepth(target.unit,mappings,rows,source.binding(target.binding).ty,expected,body.span,0); if mapped != Error.none { return mapped; }
    let refined = generator.refineMappings(target.unit,blot_reuse_refinement_receipt::Root.body { target , ..},expected,mappings,rows,body.span); if refined != Error.none { return refined; }
    var context = InitializerEmission { body.root,slot.global , ..}; let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { generator: generator,unit_id: target.unit,function_id: slot.initializer,mappings: mappings,row_mappings: rows , ..},context,emitInitializerOwner); if emitted != Error.none { return emitted; }
    block { let found = state.runtime_globals.get(target); assert(found); found.active = false; } state.startup_facts.complete(slot.initializer); state.runtime_order.push(slot.initializer);
    if scope.present { return scope.value.completeGlobal(slot.global); } return Error.none;

    }
    let cleanup_result_2_0 = cleanup_continuation_2();
     state.startup_facts.active = caller; 
    return cleanup_result_2_0;

    }
    let cleanup_result_3_0 = cleanup_continuation_3();
     if scope.present { scope.value.deinit(); } 
    return cleanup_result_3_0;
}
fn initializeRuntime(state: State&,generator: blot_backend_core_backend::Generator&) -> Error {
    var pending = false; state.runtime_globals.each() { key,slot => { if slot.active { pending = true; } } } if pending { return Error.invalid_global_reference; }
    if state.runtime_order.len == 0 && generator.module.static_fields.len == 0 { return Error.none; }
    let fields = generator.module.finishStaticFields(); if fields != Error.none { return fields; }
    let start,error = generator.module.addTypedFunction([],blot_backend_runtime_ir::VT_none,blot_backend_runtime_ir::ROLE_scalar); if error != Error.none { return error; }
    for initializer in state.runtime_order { let emitted = generator.module.emit(start,blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,initializer)); if emitted != Error.none { return emitted; } }
    if generator.module.arena.present { let arena = generator.module.arena.value; let emitted = generator.module.emitSlice(start,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_get,arena.heap),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_set,arena.base)]); if emitted != Error.none { return emitted; } } return generator.module.setStart(start);
}
fn codeCount(state: const State&,static_closures: i64) -> i64 { state.instances.count + state.closures.count + static_closures }
fn wrapperCount(state: const State&) -> i64 { state.callables.count + state.constructor_functions.count + state.primitive_functions.count + state.operation_functions.count + state.host_functions.count }
fn addStartupSelections(generator: blot_backend_core_backend::Generator&,target: blot_check_core::BindingRef,processed: dictionary<blot_check_core::BindingRef,bool>&,selections: blot_backend_startup_graph::Selection[>..<]&,confirmed: bool&) -> Error {
    let facts,error = generator.evaluator.startupDependencies(target); if error != Error.none { if error == Error.out_of_memory { return error; } return generator.evaluationFailure(); } 
    recursive fn cleanup_continuation_1() -> Error {
 if !facts.complete { confirmed = false; }
    for method in facts.selected { selections.push(blot_backend_startup_graph::Selection { target,method , ..}); let prepared = generator.evaluator.prepare(method); if prepared != Error.none { if prepared == Error.out_of_memory { return prepared; } return generator.evaluationFailure(); } } processed.insert(target,true); return Error.none;

    }
    let cleanup_result_1_0 = cleanup_continuation_1();
     facts.deinit(); 
    return cleanup_result_1_0;
}
fn planRuntime(state: State&,generator: blot_backend_core_backend::Generator&,entry: u32,supplied_order: const u32[:]) -> Error {
    var has_runtime = false; for source in generator.units { for body in source.bodies[1..] { if body.runtime && !body.is_function { has_runtime = true; } } } if !has_runtime { return Error.none; }
    var order: u32[>..<] = []; if supplied_order.len == 0 { for index in 0..generator.units.len { order.push((index + 1) as u32); } } else { if supplied_order.len != generator.units.len { return Error.invalid_function_reference; } order.append(supplied_order); }
    var selections: blot_backend_startup_graph::Selection[>..<] = []; var processed: dictionary<blot_check_core::BindingRef,bool>; var confirmed = true;
    for body in generator.unit(entry).bodies[1..] {
        if !body.exported || !body.is_function { continue; } let target = blot_check_core::BindingRef { entry,body.binding , ..};
        let facts,error = generator.evaluator.startupDependencies(target); if error != Error.none { if error == Error.out_of_memory { return error; } return generator.evaluationFailure(); } defer { facts.deinit(); }
        for method in facts.selected { selections.push(blot_backend_startup_graph::Selection { target,method , ..}); let prepared = generator.evaluator.prepare(method); if prepared != Error.none { if prepared == Error.out_of_memory { return prepared; } return generator.evaluationFailure(); } }
    }
    for source,index in generator.units { for body in source.bodies[1..] {
        if !body.runtime || body.is_function { continue; } let target = blot_check_core::BindingRef { (index + 1) as u32,body.binding , ..};
        let traced,error = generator.evaluator.bindingTraced(target); if error != Error.none { if error == Error.out_of_memory { return error; } return generator.evaluationFailure(); } if !traced { continue; }
        let selected = addStartupSelections(generator,target,processed,selections,confirmed); if selected != Error.none { return selected; }
    } }
    while true {
        let declarations,declaration_error = blot_backend_startup_graph::fromCoreWithSelections(generator.units,order,selections); if declaration_error != Error.none { if declaration_error == Error.out_of_memory { return declaration_error; } return Error.invalid_function_reference; } defer { declarations.deinit(); }
        var selected: bool[>..<] = [];
        for node in declarations.nodes { let traced,error = generator.evaluator.bindingTraced(node.target); if error != Error.none { if error == Error.out_of_memory { return error; } return generator.evaluationFailure(); } selected.push(traced); }
        let reachable,reach_error = blot_backend_startup_runtime_reach::collect(generator.units,declarations,generator.evaluator,selected,entry);
        if reach_error != Error.none {
            if reach_error == Error.out_of_memory { return reach_error; } if reach_error == Error.declined || reach_error == Error.request_unwind { return generator.evaluationFailure(); }
            if reach_error == Error.core_limit { return generator.decline(entry,blot_check_core::Span { 0,0 , ..},blot_backend_core_backend::Code.complexity); } return Error.invalid_function_reference;
        }
        defer { reachable.deinit(); } if reachable.const_only.present { return generator.fail(reachable.const_only.value.unit,reachable.const_only.value.node,blot_backend_core_backend::Code.backend_const_only); }
        var changed = false;
        for node,index in declarations.nodes { if !reachable.reached[index] || !node.runtime || node.is_function || processed.contains(node.target) { continue; } let selected = addStartupSelections(generator,node.target,processed,selections,confirmed); if selected != Error.none { return selected; } changed = true; }
        if changed { continue; }
        var initializer_roots: bool[>..<] = []; for node,index in declarations.nodes { initializer_roots.push(reachable.reached[index] && node.runtime && !node.is_function); }
        let coverage,coverage_error = blot_backend_startup_runtime_reach::collect(generator.units,declarations,generator.evaluator,initializer_roots,entry); if coverage_error != Error.none { if coverage_error == Error.out_of_memory { return coverage_error; } return Error.invalid_function_reference; } defer { coverage.deinit(); }
        for value in coverage.callable_values { let complete,error = generator.evaluator.startupCallableComplete(value); if error != Error.none { if error == Error.out_of_memory { return error; } return generator.evaluationFailure(); } if !complete { confirmed = false; } }
        var occurrence = blot_support::none<blot_backend_startup_occurrence_flow::Result>(); defer { if occurrence.present { occurrence.value.deinit(); } }
        var original = blot_support::none<blot_backend_startup_graph::Graph>(); defer { if original.present { original.value.deinit(); } }
        if !confirmed {
            var roots: blot_check_core::BindingRef[>..<] = []; for node,index in declarations.nodes { if reachable.reached[index] && node.runtime && !node.is_function { roots.push(node.target); } }
            if roots.len == 0 { return generator.decline(entry,blot_check_core::Span { 0,0 , ..},blot_backend_core_backend::Code.constant_expression); }
            let facts,error = blot_backend_startup_occurrence_flow::collect(generator.units,generator.evaluator,roots);
            if error != Error.none { if error == Error.out_of_memory { return error; } return generator.decline(roots[0].unit,generator.unit(roots[0].unit).binding(roots[0].binding).span,blot_backend_core_backend::Code.constant_expression); } occurrence = blot_support::some(facts);
            var discovered = false;
            for edge in occurrence.value.edges {
                var found = false; for node,index in declarations.nodes { if node.target == edge.target { found = reachable.reached[index]; break; } } if found { continue; }
                let prepared = generator.evaluator.prepare(edge.target); if prepared != Error.none { if prepared == Error.out_of_memory { return prepared; } return generator.evaluationFailure(); }
                selections.push(blot_backend_startup_graph::Selection { edge.root,edge.target , ..}); discovered = true;
            }
            if discovered { continue; }
            let graph,graph_error = blot_backend_startup_graph::fromCore(generator.units,order); if graph_error != Error.none { if graph_error == Error.out_of_memory { return graph_error; } return Error.invalid_function_reference; } original = blot_support::some(graph);
        }
        var plan: blot_backend_startup_graph::Plan; var plan_error: Error;
        if occurrence.present { plan,plan_error = blot_backend_startup_occurrence_plan::plan(original.value,occurrence.value.edges,reachable.reached); } else { plan,plan_error = declarations.plan(reachable.reached); }
        if plan_error != Error.none { if plan_error == Error.out_of_memory { return plan_error; } return Error.invalid_function_reference; } defer { plan.deinit(); }
        if plan.cycle.present { let target = plan.cycle.value; let point = generator.unit(target.unit).runtimeNamePoint(target.binding); return generator.decline(target.unit,blot_check_core::Span { point,point , ..},blot_backend_core_backend::Code.initialization_cycle); }
        state.runtime_plan_confirmed = confirmed || occurrence.present; state.occurrence_plan_active = occurrence.present; state.occurrence_plan_cells = []; if occurrence.present { state.occurrence_plan_cells = plan.initializers; }
        defer { state.runtime_plan_confirmed = false; state.occurrence_plan_active = false; state.occurrence_plan_cells = []; }
        for target in plan.initializers { let global,error = runtimeGlobal(state,generator,target); if error != Error.none { return error; } }
        if state.runtime_plan_confirmed { for target in plan.initializers { let error = emitRuntimeInitializer(state,generator,target); if error != Error.none { return error; } } }
        var pending = false; state.runtime_globals.each() { key,slot => { if slot.active { pending = true; } } } if pending { return Error.invalid_global_reference; } return Error.none;
    }
}
