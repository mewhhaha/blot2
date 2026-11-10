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
import support.pooled_map;
import support.pooled_buffer;
import .optimizer_buffers;

type Error = blot_error::Error;
type Key = blot_reuse_code_artifacts::Key;
type Mapping = blot_backend_layout::Mapping;
type RowMapping = blot_backend_layout::RowMapping;
// Concrete pools preserve Goose's reusable-pool authority across cached headers.
struct KeyCache {count:i64=0,slots:dictionary_slot<Key,u32>[:]=default<dictionary_slot<Key,u32>[:]>()}
reusable[] var slots_KeyCache:dictionary_slot<Key,u32>[>..]=[];
fn insert(cache:KeyCache&,key:Key,value:u32)->bool {return blot_support_pooled_map::insert(cache,key,value,slots_KeyCache);}
struct TemplateCache {count:i64=0,slots:dictionary_slot<blot_reuse_code_artifacts::CapturedTemplate,u32>[:]=default<dictionary_slot<blot_reuse_code_artifacts::CapturedTemplate,u32>[:]>()}
reusable[] var slots_TemplateCache:dictionary_slot<blot_reuse_code_artifacts::CapturedTemplate,u32>[>..]=[];
fn insert(cache:TemplateCache&,key:blot_reuse_code_artifacts::CapturedTemplate,value:u32)->bool {return blot_support_pooled_map::insert(cache,key,value,slots_TemplateCache);}
struct ClosureCache {count:i64=0,slots:dictionary_slot<blot_reuse_code_artifacts::ClosureKey,u32>[:]=default<dictionary_slot<blot_reuse_code_artifacts::ClosureKey,u32>[:]>()}
reusable[] var slots_ClosureCache:dictionary_slot<blot_reuse_code_artifacts::ClosureKey,u32>[>..]=[];
fn insert(cache:ClosureCache&,key:blot_reuse_code_artifacts::ClosureKey,value:u32)->bool {return blot_support_pooled_map::insert(cache,key,value,slots_ClosureCache);}
struct CallableCache {count:i64=0,slots:dictionary_slot<blot_reuse_code_artifacts::CallableKey,u32>[:]=default<dictionary_slot<blot_reuse_code_artifacts::CallableKey,u32>[:]>()}
reusable[] var slots_CallableCache:dictionary_slot<blot_reuse_code_artifacts::CallableKey,u32>[>..]=[];
fn insert(cache:CallableCache&,key:blot_reuse_code_artifacts::CallableKey,value:u32)->bool {return blot_support_pooled_map::insert(cache,key,value,slots_CallableCache);}
struct CarrierCache {count:i64=0,slots:dictionary_slot<blot_backend_backend_emission::CarrierKey,u32>[:]=default<dictionary_slot<blot_backend_backend_emission::CarrierKey,u32>[:]>()}
reusable[] var slots_CarrierCache:dictionary_slot<blot_backend_backend_emission::CarrierKey,u32>[>..]=[];
fn insert(cache:CarrierCache&,key:blot_backend_backend_emission::CarrierKey,value:u32)->bool {return blot_support_pooled_map::insert(cache,key,value,slots_CarrierCache);}
struct ConstructorCache {count:i64=0,slots:dictionary_slot<blot_reuse_code_artifacts::ConstructorKey,u32>[:]=default<dictionary_slot<blot_reuse_code_artifacts::ConstructorKey,u32>[:]>()}
reusable[] var slots_ConstructorCache:dictionary_slot<blot_reuse_code_artifacts::ConstructorKey,u32>[>..]=[];
fn insert(cache:ConstructorCache&,key:blot_reuse_code_artifacts::ConstructorKey,value:u32)->bool {return blot_support_pooled_map::insert(cache,key,value,slots_ConstructorCache);}
struct PrimitiveCache {count:i64=0,slots:dictionary_slot<blot_reuse_code_artifacts::PrimitiveKey,u32>[:]=default<dictionary_slot<blot_reuse_code_artifacts::PrimitiveKey,u32>[:]>()}
reusable[] var slots_PrimitiveCache:dictionary_slot<blot_reuse_code_artifacts::PrimitiveKey,u32>[>..]=[];
fn insert(cache:PrimitiveCache&,key:blot_reuse_code_artifacts::PrimitiveKey,value:u32)->bool {return blot_support_pooled_map::insert(cache,key,value,slots_PrimitiveCache);}
struct OperationCache {count:i64=0,slots:dictionary_slot<blot_reuse_code_artifacts::OperationKey,u32>[:]=default<dictionary_slot<blot_reuse_code_artifacts::OperationKey,u32>[:]>()}
reusable[] var slots_OperationCache:dictionary_slot<blot_reuse_code_artifacts::OperationKey,u32>[>..]=[];
fn insert(cache:OperationCache&,key:blot_reuse_code_artifacts::OperationKey,value:u32)->bool {return blot_support_pooled_map::insert(cache,key,value,slots_OperationCache);}
struct HostCache {count:i64=0,slots:dictionary_slot<blot_reuse_code_artifacts::HostKey,u32>[:]=default<dictionary_slot<blot_reuse_code_artifacts::HostKey,u32>[:]>()}
reusable[] var slots_HostCache:dictionary_slot<blot_reuse_code_artifacts::HostKey,u32>[>..]=[];
fn insert(cache:HostCache&,key:blot_reuse_code_artifacts::HostKey,value:u32)->bool {return blot_support_pooled_map::insert(cache,key,value,slots_HostCache);}
struct RuntimeCache {count:i64=0,slots:dictionary_slot<blot_check_core::BindingRef,RuntimeSlot>[:]=default<dictionary_slot<blot_check_core::BindingRef,RuntimeSlot>[:]>()}
reusable[] var slots_RuntimeCache:dictionary_slot<blot_check_core::BindingRef,RuntimeSlot>[>..]=[];
fn insert(cache:RuntimeCache&,key:blot_check_core::BindingRef,value:RuntimeSlot)->bool {return blot_support_pooled_map::insert(cache,key,value,slots_RuntimeCache);}
struct ArrayProofCache {count:i64=0,slots:dictionary_slot<u32,blot_backend_owned_arrays::Proof>[:]=default<dictionary_slot<u32,blot_backend_owned_arrays::Proof>[:]>()}
reusable[] var slots_ArrayProofCache:dictionary_slot<u32,blot_backend_owned_arrays::Proof>[>..]=[];
fn insert(cache:ArrayProofCache&,key:u32,value:blot_backend_owned_arrays::Proof)->bool {return blot_support_pooled_map::insert(cache,key,value,slots_ArrayProofCache);}
struct NumericPlanCache {count:i64=0,slots:dictionary_slot<u32,blot_check_numeric_proof_core::Plan>[:]=default<dictionary_slot<u32,blot_check_numeric_proof_core::Plan>[:]>()}
reusable[] var slots_NumericPlanCache:dictionary_slot<u32,blot_check_numeric_proof_core::Plan>[>..]=[];
fn insert(cache:NumericPlanCache&,key:u32,value:blot_check_numeric_proof_core::Plan)->bool {return blot_support_pooled_map::insert(cache,key,value,slots_NumericPlanCache);}
struct DiscardCache {count:i64=0,slots:dictionary_slot<u32,blot_backend_discarded_bindings::Proof>[:]=default<dictionary_slot<u32,blot_backend_discarded_bindings::Proof>[:]>()}
reusable[] var slots_DiscardCache:dictionary_slot<u32,blot_backend_discarded_bindings::Proof>[>..]=[];
fn insert(cache:DiscardCache&,key:u32,value:blot_backend_discarded_bindings::Proof)->bool {return blot_support_pooled_map::insert(cache,key,value,slots_DiscardCache);}
struct QuantifiedCache {count:i64=0,slots:dictionary_slot<u32,blot_backend_unit_index::Quantified>[:]=default<dictionary_slot<u32,blot_backend_unit_index::Quantified>[:]>()}
reusable[] var slots_QuantifiedCache:dictionary_slot<u32,blot_backend_unit_index::Quantified>[>..]=[];
fn insert(cache:QuantifiedCache&,key:u32,value:blot_backend_unit_index::Quantified)->bool {return blot_support_pooled_map::insert(cache,key,value,slots_QuantifiedCache);}
struct UsesCache {count:i64=0,slots:dictionary_slot<u32,blot_backend_unit_index::Uses&?>[:]=default<dictionary_slot<u32,blot_backend_unit_index::Uses&?>[:]>()}
reusable[] var slots_UsesCache:dictionary_slot<u32,blot_backend_unit_index::Uses&?>[>..]=[];
fn insert(cache:UsesCache&,key:u32,value:blot_backend_unit_index::Uses&?)->bool {return blot_support_pooled_map::insert(cache,key,value,slots_UsesCache);}
struct WordCache {count:i64=0,slots:dictionary_slot<u32,u32>[:]=default<dictionary_slot<u32,u32>[:]>()}
reusable[] var slots_WordCache:dictionary_slot<u32,u32>[>..]=[];
fn insert(cache:WordCache&,key:u32,value:u32)->bool {return blot_support_pooled_map::insert(cache,key,value,slots_WordCache);}
// Uses already carries a nullable canonical header reference; avoid another pointer layer.
fn get(cache:UsesCache&,key:u32)->blot_backend_unit_index::Uses? {let index=blot_support_pooled_map::probe(cache,key);if index<0 {return null;}return cache.slots[index].val;}
fn each<F>(cache:UsesCache&) {for slot in cache.slots {if slot.tag!=0 {F(slot.key,slot.val);}}}
fn get<M,K>(cache:M&,key:K) {return blot_support_pooled_map::get(cache,key);}
fn contains<M,K>(cache:const M&,key:K)->bool {return blot_support_pooled_map::contains(cache,key);}
fn clear<M>(cache:M&) {blot_support_pooled_map::clear(cache);}
fn each<M,F>(cache:M&) {blot_support_pooled_map::each(cache,F);}
struct TemplateCatalog {storage:blot_reuse_code_artifacts::CapturedTemplate[:]=default<blot_reuse_code_artifacts::CapturedTemplate[:]>(),items:blot_reuse_code_artifacts::CapturedTemplate[:]=default<blot_reuse_code_artifacts::CapturedTemplate[:]>(),len:i64=0}
reusable[] var template_catalog_runs:blot_reuse_code_artifacts::CapturedTemplate[>..]=[];
fn push(catalog:TemplateCatalog&,value:blot_reuse_code_artifacts::CapturedTemplate)->Error {let error=blot_support_pooled_buffer::push(catalog,value,template_catalog_runs);catalog.len=catalog.items.len;return error;}
fn clear(catalog:TemplateCatalog&) {blot_support_pooled_buffer::clear(catalog);catalog.len=0;}
fn resize(catalog:TemplateCatalog&,length:i64) {blot_support_pooled_buffer::resize(catalog,length);catalog.len=length;}
struct RuntimeSlot { global: u32,initializer: u32,active: bool = true }
struct State {
    instances: KeyCache&,template_results: KeyCache&,template_catalog: TemplateCatalog&,template_instances: TemplateCache&,
    closures: ClosureCache&,closure_template_results: ClosureCache&,callables: CallableCache&,carrier_adapters: CarrierCache&,
    constructor_functions: ConstructorCache&,primitive_functions: PrimitiveCache&,operation_functions: OperationCache&,runtime_operations: blot_backend_runtime_operations::Store&,
    host_functions: HostCache&,runtime_globals: RuntimeCache&,
    runtime_plan_confirmed: bool = false,occurrence_plan_active: bool = false,occurrence_plan_cells: const blot_check_core::BindingRef[:] = default<const blot_check_core::BindingRef[:]>(),startup_facts: blot_backend_startup_emission_facts::Store&,runtime_order: blot_backend_optimizer_buffers::Words&,
    array_proofs: ArrayProofCache&,numeric_plans: NumericPlanCache&,facts: blot_backend_function_facts::Store&,
    discard_proofs: DiscardCache&,discard_flags: blot_backend_optimizer_buffers::Flags&,quantified: QuantifiedCache&,uses: UsesCache&,task_movers: WordCache&,
}
fn init(state: State&) { state.runtime_plan_confirmed = false; state.occurrence_plan_active = false; state.occurrence_plan_cells = default<const blot_check_core::BindingRef[:]>(); }
fn deinit(state: State&) {
    blot_backend_resolved_body::deinit();
    state.instances.clear(); state.template_results.clear(); state.template_catalog.clear(); state.template_instances.clear(); state.closures.clear(); state.closure_template_results.clear(); state.callables.clear(); state.carrier_adapters.clear();
    state.constructor_functions.clear(); state.primitive_functions.clear(); state.operation_functions.clear(); state.runtime_operations.deinit(); state.host_functions.clear(); state.runtime_globals.clear(); state.startup_facts.deinit(); state.runtime_order.clear();
    state.array_proofs.each() { key,proof => proof.deinit(); } state.array_proofs.clear(); state.numeric_plans.each() { key,plan => plan.deinit(); } state.numeric_plans.clear(); state.facts.deinit(); state.discard_proofs.clear(); state.discard_flags.clear();
    state.quantified.each() { key,set => set.deinit(); } state.quantified.clear(); state.uses.each() { key,index => { assert(index); index.deinit(); blot_backend_unit_index::release(index); } } state.uses.clear(); state.task_movers.clear(); init(state);
}
fn runtimeGlobal(state: State&,generator: blot_backend_core_backend::Generator&,target: blot_check_core::BindingRef) -> u32,Error {
    let scope,error = blot_backend_core_backend::enterScope(generator,blot_reuse_code_artifacts::Request.runtime_global { target , ..}); if error != blot_error::Error.none { return 0,error; }


    if state.occurrence_plan_active { var included = false; for cell in state.occurrence_plan_cells { if cell == target { included = true; break; } } if !included { let __runtime_global_result_0_0: u32 = 0; let __runtime_global_result_0_1: Error = generator.decline(target.unit,generator.unit(target.unit).binding(target.binding).span,blot_check_diagnostic_code::Code.constant_expression); if scope.present { scope.value.deinit(); } return __runtime_global_result_0_0,__runtime_global_result_0_1; } }
    var global = blot_backend_startup_emission_facts::none; var active = true; block { let slot = state.runtime_globals.get(target); if slot { global = slot.global; active = slot.active; } }
    let event = state.startup_facts.event(blot_backend_startup_emission_facts::Event { kind: blot_backend_startup_emission_facts::EventKind.runtime_global_request,caller: state.startup_facts.active,target: global,unit: target.unit,identity: target.binding,flag: active , ..}); if event != blot_error::Error.none { let __runtime_global_result_1_0: u32 = 0; let __runtime_global_result_1_1: Error = event; if scope.present { scope.value.deinit(); } return __runtime_global_result_1_0,__runtime_global_result_1_1; }
    block {
        let slot = state.runtime_globals.get(target);
        if slot {
            if !state.runtime_plan_confirmed && slot.active { let __runtime_global_result_2_0: u32 = 0; let __runtime_global_result_2_1: Error = generator.decline(target.unit,generator.unit(target.unit).binding(target.binding).span,blot_check_diagnostic_code::Code.constant_expression); if scope.present { scope.value.deinit(); } return __runtime_global_result_2_0,__runtime_global_result_2_1; }
            if scope.present { let hit = scope.value.hitGlobal(slot.global); if hit != blot_error::Error.none { let __runtime_global_result_3_0: u32 = 0; let __runtime_global_result_3_1: Error = hit; if scope.present { scope.value.deinit(); } return __runtime_global_result_3_0,__runtime_global_result_3_1; } } let __runtime_global_result_4_0: u32 = slot.global; let __runtime_global_result_4_1: Error = blot_error::Error.none; if scope.present { scope.value.deinit(); } return __runtime_global_result_4_0,__runtime_global_result_4_1;
        }
    }
    let source .= generator.unit(target.unit); let body .= source.body(target.binding); if body == null { let __runtime_global_result_5_0: u32 = 0; let __runtime_global_result_5_1: Error = generator.decline(target.unit,source.binding(target.binding).span,blot_check_diagnostic_code::Code.unsupported); if scope.present { scope.value.deinit(); } return __runtime_global_result_5_0,__runtime_global_result_5_1; }
    if !body.runtime || body.is_function { let __runtime_global_result_6_0: u32 = 0; let __runtime_global_result_6_1: Error = generator.decline(target.unit,body.span,blot_check_diagnostic_code::Code.unsupported); if scope.present { scope.value.deinit(); } return __runtime_global_result_6_0,__runtime_global_result_6_1; }
    let expected,layout_error = generator.codeLayout(target.unit,body.scheme.root,[],body.span); if layout_error != blot_error::Error.none { let __runtime_global_result_7_0: u32 = 0; let __runtime_global_result_7_1: Error = layout_error; if scope.present { scope.value.deinit(); } return __runtime_global_result_7_0,__runtime_global_result_7_1; }
    var scalar = blot_backend_runtime_ir::SC_pointer; let primitive = generator.representations.store.scalar(expected); if primitive.present { scalar = primitive.value; }
    let global_id,global_error = generator.module.addGlobal(scalar,0,true); if global_error != blot_error::Error.none { let __runtime_global_result_8_0: u32 = 0; let __runtime_global_result_8_1: Error = global_error; if scope.present { scope.value.deinit(); } return __runtime_global_result_8_0,__runtime_global_result_8_1; }
    let initializer,initializer_error = generator.module.addTypedFunction([],blot_backend_runtime_ir::VT_none,blot_backend_runtime_ir::ROLE_scalar); if initializer_error != blot_error::Error.none { let __runtime_global_result_9_0: u32 = 0; let __runtime_global_result_9_1: Error = initializer_error; if scope.present { scope.value.deinit(); } return __runtime_global_result_9_0,__runtime_global_result_9_1; }
    state.runtime_globals.insert(target,RuntimeSlot { global_id,initializer , ..});
    let registered = state.startup_facts.event(blot_backend_startup_emission_facts::Event { kind: blot_backend_startup_emission_facts::EventKind.cell_registration,target: global_id,unit: target.unit,identity: target.binding,auxiliary: initializer , ..}); if registered != blot_error::Error.none { let __runtime_global_result_10_0: u32 = 0; let __runtime_global_result_10_1: Error = registered; if scope.present { scope.value.deinit(); } return __runtime_global_result_10_0,__runtime_global_result_10_1; }
    if !state.runtime_plan_confirmed { let emitted = emitRuntimeInitializer(state,generator,target); if emitted != blot_error::Error.none { let __runtime_global_result_11_0: u32 = 0; let __runtime_global_result_11_1: Error = emitted; if scope.present { scope.value.deinit(); } return __runtime_global_result_11_0,__runtime_global_result_11_1; } }
    if scope.present { let hit = scope.value.hitGlobal(global_id); if hit != blot_error::Error.none { let __runtime_global_result_12_0: u32 = 0; let __runtime_global_result_12_1: Error = hit; if scope.present { scope.value.deinit(); } return __runtime_global_result_12_0,__runtime_global_result_12_1; } } let __runtime_global_result_13_0: u32 = global_id; let __runtime_global_result_13_1: Error = blot_error::Error.none; if scope.present { scope.value.deinit(); } return __runtime_global_result_13_0,__runtime_global_result_13_1;


}
struct InitializerEmission { root: u32,global: u32 }
fn emitInitializerOwner(context: InitializerEmission&,emitter: blot_backend_backend_emission::Owner&) -> Error { let body = emitter.bodyExpression(context.root,0,false); if body != blot_error::Error.none { return body; } return emitter.emit(blot_backend_runtime_ir::OP_global_set,context.global); }
fn emitRuntimeInitializer(state: State&,generator: blot_backend_core_backend::Generator&,target: blot_check_core::BindingRef) -> Error {
    var slot: RuntimeSlot; block { let found = state.runtime_globals.get(target); if found == null { return blot_error::Error.invalid_global_reference; } slot = found; } if !slot.active { return blot_error::Error.none; }
    let scope,scope_error = blot_backend_core_backend::enterScope(generator,blot_reuse_code_artifacts::Request.runtime_global { target , ..}); if scope_error != blot_error::Error.none { return scope_error; }


    let requested = state.startup_facts.request(slot.initializer,blot_backend_startup_emission_facts::Kind.runtime_initializer,target.unit,target.binding,false); if requested != blot_error::Error.none { let __runtime_initializer_final_result_0 = requested; if scope.present { scope.value.deinit(); } return __runtime_initializer_final_result_0; }
    let caller = state.startup_facts.active; state.startup_facts.active = slot.initializer;


    let source .= generator.unit(target.unit); let body .= source.body(target.binding); if body == null { let __runtime_initializer_body_result_0 = blot_error::Error.invalid_global_reference; state.startup_facts.active = caller; let __runtime_initializer_final_result_1 = __runtime_initializer_body_result_0; if scope.present { scope.value.deinit(); } return __runtime_initializer_final_result_1; }
    var mappings = blot_backend_substitution_buffers::Mappings {..}; var rows = blot_backend_substitution_buffers::Rows {..}; let expected,error = generator.codeLayout(target.unit,body.scheme.root,[],body.span); if error != blot_error::Error.none { let __runtime_initializer_body_result_1 = error; rows.deinit(); mappings.deinit(); state.startup_facts.active = caller; let __runtime_initializer_final_result_2 = __runtime_initializer_body_result_1; if scope.present { scope.value.deinit(); } return __runtime_initializer_final_result_2; }
    let mapped = generator.mapTypeDepth(target.unit,mappings,rows,source.binding(target.binding).ty,expected,body.span,0); if mapped != blot_error::Error.none { let __runtime_initializer_body_result_2 = mapped; rows.deinit(); mappings.deinit(); state.startup_facts.active = caller; let __runtime_initializer_final_result_3 = __runtime_initializer_body_result_2; if scope.present { scope.value.deinit(); } return __runtime_initializer_final_result_3; }
    let refined = generator.refineMappings(target.unit,blot_reuse_refinement_receipt::Root.body { target , ..},expected,mappings,rows,body.span); if refined != blot_error::Error.none { let __runtime_initializer_body_result_3 = refined; rows.deinit(); mappings.deinit(); state.startup_facts.active = caller; let __runtime_initializer_final_result_4 = __runtime_initializer_body_result_3; if scope.present { scope.value.deinit(); } return __runtime_initializer_final_result_4; }
    var context = InitializerEmission { body.root,slot.global , ..}; let emitted = blot_backend_backend_emission::withOwner(blot_backend_backend_emission::Config { generator: generator,unit_id: target.unit,function_id: slot.initializer,mappings: mappings.items,row_mappings: rows.items , ..},context,emitInitializerOwner); if emitted != blot_error::Error.none { let __runtime_initializer_body_result_4 = emitted; rows.deinit(); mappings.deinit(); state.startup_facts.active = caller; let __runtime_initializer_final_result_5 = __runtime_initializer_body_result_4; if scope.present { scope.value.deinit(); } return __runtime_initializer_final_result_5; }
    block { let found = state.runtime_globals.get(target); assert(found); found.active = false; } state.startup_facts.complete(slot.initializer); let ordered=state.runtime_order.push(slot.initializer);if ordered!=blot_error::Error.none {let __runtime_initializer_body_result_5 = ordered; rows.deinit(); mappings.deinit(); state.startup_facts.active = caller; let __runtime_initializer_final_result_6 = __runtime_initializer_body_result_5; if scope.present { scope.value.deinit(); } return __runtime_initializer_final_result_6;}
    if scope.present { let __runtime_initializer_body_result_6 = scope.value.completeGlobal(slot.global); rows.deinit(); mappings.deinit(); state.startup_facts.active = caller; let __runtime_initializer_final_result_7 = __runtime_initializer_body_result_6; if scope.present { scope.value.deinit(); } return __runtime_initializer_final_result_7; } let __runtime_initializer_body_result_7 = blot_error::Error.none; rows.deinit(); mappings.deinit(); state.startup_facts.active = caller; let __runtime_initializer_final_result_8 = __runtime_initializer_body_result_7; if scope.present { scope.value.deinit(); } return __runtime_initializer_final_result_8;




}
fn initializeRuntime(state: State&,generator: blot_backend_core_backend::Generator&) -> Error {
    var pending = false; state.runtime_globals.each() { key,slot => { if slot.active { pending = true; } } } if pending { return blot_error::Error.invalid_global_reference; }
    if state.runtime_order.len == 0 && generator.module.static_fields.len == 0 { return blot_error::Error.none; }
    let fields = generator.module.finishStaticFields(); if fields != blot_error::Error.none { return fields; }
    let start,error = generator.module.addTypedFunction([],blot_backend_runtime_ir::VT_none,blot_backend_runtime_ir::ROLE_scalar); if error != blot_error::Error.none { return error; }
    for initializer in state.runtime_order.items { let emitted = generator.module.emit(start,blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,initializer)); if emitted != blot_error::Error.none { return emitted; } }
    if generator.module.arena.present { let arena = generator.module.arena.value; let emitted = generator.module.emitSlice(start,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_get,arena.heap),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_set,arena.base)]); if emitted != blot_error::Error.none { return emitted; } } return generator.module.setStart(start);
}
fn codeCount(state: const State&,static_closures: i64) -> i64 { state.instances.count + state.closures.count + static_closures }
fn wrapperCount(state: const State&) -> i64 { state.callables.count + state.constructor_functions.count + state.primitive_functions.count + state.operation_functions.count + state.host_functions.count }
fn addStartupSelections(generator: blot_backend_core_backend::Generator&,target: blot_check_core::BindingRef,processed: dictionary<blot_check_core::BindingRef,bool>&,selections: blot_backend_startup_graph::Selection[>..<]&,confirmed: bool&) -> Error {
    let facts,error = generator.evaluator.startupDependencies(target); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return error; } return generator.evaluationFailure(); }
    block {
 if !facts.complete { confirmed = false; }
    for method in facts.selected { selections.push(blot_backend_startup_graph::Selection { target,method , ..}); let prepared = generator.evaluator.prepare(method); if prepared != blot_error::Error.none { if prepared == blot_error::Error.out_of_memory { let __flat_cleanup_0_0_0: Error = prepared; block {
facts.deinit();
} return __flat_cleanup_0_0_0; } let __flat_cleanup_0_1_0: Error = generator.evaluationFailure(); block {
facts.deinit();
} return __flat_cleanup_0_1_0; } } ::insert(processed,target,true); let __flat_cleanup_0_2_0: Error = blot_error::Error.none; block {
facts.deinit();
} return __flat_cleanup_0_2_0;


    }
}
fn planRuntime(state: State&,generator: blot_backend_core_backend::Generator&,entry: u32,supplied_order: const u32[:]) -> Error {
    var has_runtime = false; for source in generator.units { for body in source.bodies[1..] { if body.runtime && !body.is_function { has_runtime = true; } } } if !has_runtime { return blot_error::Error.none; }
    var order: u32[>..<] = []; if supplied_order.len == 0 { for index in 0..generator.units.len { order.push((index + 1) as u32); } } else { if supplied_order.len != generator.units.len { return blot_error::Error.invalid_function_reference; } order.append(supplied_order); }
    var selections: blot_backend_startup_graph::Selection[>..<] = []; var processed: dictionary<blot_check_core::BindingRef,bool> = dictionary<blot_check_core::BindingRef,bool>{}; var confirmed = true;
    for body in generator.unit(entry).bodies[1..] {
        if !body.exported || !body.is_function { continue; } let target = blot_check_core::BindingRef { entry,body.binding , ..};
        let facts,error = generator.evaluator.startupDependencies(target); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return error; } return generator.evaluationFailure(); }
        for method in facts.selected { selections.push(blot_backend_startup_graph::Selection { target,method , ..}); let prepared = generator.evaluator.prepare(method); if prepared != blot_error::Error.none { if prepared == blot_error::Error.out_of_memory { let __cleanup_result_6_0: Error = prepared; { facts.deinit(); } return __cleanup_result_6_0; } let __cleanup_result_7_0: Error = generator.evaluationFailure(); { facts.deinit(); } return __cleanup_result_7_0; } }
     { facts.deinit(); } }
    for source,index in generator.units { for body in source.bodies[1..] {
        if !body.runtime || body.is_function { continue; } let target = blot_check_core::BindingRef { (index + 1) as u32,body.binding , ..};
        let traced,error = generator.evaluator.bindingTraced(target); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return error; } return generator.evaluationFailure(); } if !traced { continue; }
        let selected = addStartupSelections(generator,target,processed,selections,confirmed); if selected != blot_error::Error.none { return selected; }
    } }
    while true {
        let declarations,declaration_error = blot_backend_startup_graph::fromCoreWithSelections(generator.units,order,selections); if declaration_error != blot_error::Error.none { if declaration_error == blot_error::Error.out_of_memory { return declaration_error; } return blot_error::Error.invalid_function_reference; }
        var selected: bool[>..<] = [];
        for node in declarations.nodes { let traced,error = generator.evaluator.bindingTraced(node.target); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { let __cleanup_result_8_0: Error = error; { declarations.deinit(); } return __cleanup_result_8_0; } let __cleanup_result_9_0: Error = generator.evaluationFailure(); { declarations.deinit(); } return __cleanup_result_9_0; } selected.push(traced); }
        let reachable,reach_error = blot_backend_startup_runtime_reach::collect(generator.units,declarations,generator.evaluator,selected,entry);
        if reach_error != blot_error::Error.none {
            if reach_error == blot_error::Error.out_of_memory { let __cleanup_result_10_0: Error = reach_error; { declarations.deinit(); } return __cleanup_result_10_0; } if reach_error == blot_error::Error.declined || reach_error == blot_error::Error.request_unwind { let __cleanup_result_11_0: Error = generator.evaluationFailure(); { declarations.deinit(); } return __cleanup_result_11_0; }
            if reach_error == blot_error::Error.core_limit { let __cleanup_result_12_0: Error = generator.decline(entry,blot_check_core::Span { 0,0 , ..},blot_check_diagnostic_code::Code.complexity); { declarations.deinit(); } return __cleanup_result_12_0; } let __cleanup_result_13_0: Error = blot_error::Error.invalid_function_reference; { declarations.deinit(); } return __cleanup_result_13_0;
        }
         if reachable.const_only.present { let __cleanup_result_14_0: Error = generator.fail(reachable.const_only.value.unit,reachable.const_only.value.node,blot_check_diagnostic_code::Code.backend_const_only); { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_14_0; }
        var changed = false;
        for node,index in declarations.nodes { if !reachable.reached[index] || !node.runtime || node.is_function || ::contains(processed,node.target) { continue; } let selected = addStartupSelections(generator,node.target,processed,selections,confirmed); if selected != blot_error::Error.none { let __cleanup_result_15_0: Error = selected; { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_15_0; } changed = true; }
        if changed { { reachable.deinit(); } { declarations.deinit(); } continue; }
        var initializer_roots: bool[>..<] = []; for node,index in declarations.nodes { initializer_roots.push(reachable.reached[index] && node.runtime && !node.is_function); }
        let coverage,coverage_error = blot_backend_startup_runtime_reach::collect(generator.units,declarations,generator.evaluator,initializer_roots,entry); if coverage_error != blot_error::Error.none { if coverage_error == blot_error::Error.out_of_memory { let __cleanup_result_17_0: Error = coverage_error; { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_17_0; } let __cleanup_result_18_0: Error = blot_error::Error.invalid_function_reference; { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_18_0; }
        for value in coverage.callable_values { let complete,error = generator.evaluator.startupCallableComplete(value); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { let __cleanup_result_19_0: Error = error; { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_19_0; } let __cleanup_result_20_0: Error = generator.evaluationFailure(); { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_20_0; } if !complete { confirmed = false; } }
        var occurrence = blot_support::none<blot_backend_startup_occurrence_flow::Result>();
        var original = blot_support::none<blot_backend_startup_graph::Graph>();
        if !confirmed {
            var roots: blot_check_core::BindingRef[>..<] = []; for node,index in declarations.nodes { if reachable.reached[index] && node.runtime && !node.is_function { roots.push(node.target); } }
            if roots.len == 0 { let __cleanup_result_21_0: Error = generator.decline(entry,blot_check_core::Span { 0,0 , ..},blot_check_diagnostic_code::Code.constant_expression); { if original.present { original.value.deinit(); } } { if occurrence.present { occurrence.value.deinit(); } } { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_21_0; }
            let facts,error = blot_backend_startup_occurrence_flow::collect(generator.units,generator.evaluator,roots);
            if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { let __cleanup_result_22_0: Error = error; { if original.present { original.value.deinit(); } } { if occurrence.present { occurrence.value.deinit(); } } { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_22_0; } let __cleanup_result_23_0: Error = generator.decline(roots[0].unit,generator.unit(roots[0].unit).binding(roots[0].binding).span,blot_check_diagnostic_code::Code.constant_expression); { if original.present { original.value.deinit(); } } { if occurrence.present { occurrence.value.deinit(); } } { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_23_0; } occurrence = blot_support::some(facts);
            var discovered = false;
            for edge in occurrence.value.edges {
                var found = false; for node,index in declarations.nodes { if node.target == edge.target { found = reachable.reached[index]; break; } } if found { continue; }
                let prepared = generator.evaluator.prepare(edge.target); if prepared != blot_error::Error.none { if prepared == blot_error::Error.out_of_memory { let __cleanup_result_24_0: Error = prepared; { if original.present { original.value.deinit(); } } { if occurrence.present { occurrence.value.deinit(); } } { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_24_0; } let __cleanup_result_25_0: Error = generator.evaluationFailure(); { if original.present { original.value.deinit(); } } { if occurrence.present { occurrence.value.deinit(); } } { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_25_0; }
                selections.push(blot_backend_startup_graph::Selection { edge.root,edge.target , ..}); discovered = true;
            }
            if discovered { { if original.present { original.value.deinit(); } } { if occurrence.present { occurrence.value.deinit(); } } { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } continue; }
            let graph,graph_error = blot_backend_startup_graph::fromCore(generator.units,order); if graph_error != blot_error::Error.none { if graph_error == blot_error::Error.out_of_memory { let __cleanup_result_27_0: Error = graph_error; { if original.present { original.value.deinit(); } } { if occurrence.present { occurrence.value.deinit(); } } { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_27_0; } let __cleanup_result_28_0: Error = blot_error::Error.invalid_function_reference; { if original.present { original.value.deinit(); } } { if occurrence.present { occurrence.value.deinit(); } } { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_28_0; } original = blot_support::some(graph);
        }
        var plan: blot_backend_startup_graph::Plan; var plan_error: Error;
        if occurrence.present { plan,plan_error = blot_backend_startup_occurrence_plan::plan(original.value,occurrence.value.edges,reachable.reached); } else { plan,plan_error = declarations.plan(reachable.reached); }
        if plan_error != blot_error::Error.none { if plan_error == blot_error::Error.out_of_memory { let __cleanup_result_29_0: Error = plan_error; { if original.present { original.value.deinit(); } } { if occurrence.present { occurrence.value.deinit(); } } { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_29_0; } let __cleanup_result_30_0: Error = blot_error::Error.invalid_function_reference; { if original.present { original.value.deinit(); } } { if occurrence.present { occurrence.value.deinit(); } } { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_30_0; }
        if plan.cycle.present { let target = plan.cycle.value; let point = generator.unit(target.unit).runtimeNamePoint(target.binding); let __cleanup_result_31_0: Error = generator.decline(target.unit,blot_check_core::Span { point,point , ..},blot_check_diagnostic_code::Code.initialization_cycle); { plan.deinit(); } { if original.present { original.value.deinit(); } } { if occurrence.present { occurrence.value.deinit(); } } { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_31_0; }
        state.runtime_plan_confirmed = confirmed || occurrence.present; state.occurrence_plan_active = occurrence.present; state.occurrence_plan_cells = default<const blot_check_core::BindingRef[:]>(); if occurrence.present { state.occurrence_plan_cells = plan.initializers; }

        for target in plan.initializers { let global,error = runtimeGlobal(state,generator,target); if error != blot_error::Error.none { let __cleanup_result_32_0: Error = error; { state.runtime_plan_confirmed = false; state.occurrence_plan_active = false; state.occurrence_plan_cells = default<const blot_check_core::BindingRef[:]>(); } { plan.deinit(); } { if original.present { original.value.deinit(); } } { if occurrence.present { occurrence.value.deinit(); } } { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_32_0; } }
        if state.runtime_plan_confirmed { for target in plan.initializers { let error = emitRuntimeInitializer(state,generator,target); if error != blot_error::Error.none { let __cleanup_result_33_0: Error = error; { state.runtime_plan_confirmed = false; state.occurrence_plan_active = false; state.occurrence_plan_cells = default<const blot_check_core::BindingRef[:]>(); } { plan.deinit(); } { if original.present { original.value.deinit(); } } { if occurrence.present { occurrence.value.deinit(); } } { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_33_0; } } }
        var pending = false; state.runtime_globals.each() { key,slot => { if slot.active { pending = true; } } } if pending { let __cleanup_result_34_0: Error = blot_error::Error.invalid_global_reference; { state.runtime_plan_confirmed = false; state.occurrence_plan_active = false; state.occurrence_plan_cells = default<const blot_check_core::BindingRef[:]>(); } { plan.deinit(); } { if original.present { original.value.deinit(); } } { if occurrence.present { occurrence.value.deinit(); } } { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_34_0; } let __cleanup_result_35_0: Error = blot_error::Error.none; { state.runtime_plan_confirmed = false; state.occurrence_plan_active = false; state.occurrence_plan_cells = default<const blot_check_core::BindingRef[:]>(); } { plan.deinit(); } { if original.present { original.value.deinit(); } } { if occurrence.present { occurrence.value.deinit(); } } { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } return __cleanup_result_35_0;
     { state.runtime_plan_confirmed = false; state.occurrence_plan_active = false; state.occurrence_plan_cells = default<const blot_check_core::BindingRef[:]>(); } { plan.deinit(); } { if original.present { original.value.deinit(); } } { if occurrence.present { occurrence.value.deinit(); } } { coverage.deinit(); } { reachable.deinit(); } { declarations.deinit(); } }
}
