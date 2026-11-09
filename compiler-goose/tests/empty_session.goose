// The persistent workspace starts without borrowing a caller catalog.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import eval.core_eval;
import driver.compile_workspace;
import support.error;
import support.native;
fn inspectWorkspace(frame:blot_compile_workspace::Frame) {
    let workspace .=frame.borrow();assert(workspace!=null);
    assert(workspace.generator.evaluator.units.len==0 && workspace.capture.metadata().validContext());
    let key=blot_backend_backend_static_data::SerializedKey{1,2};assert(workspace.generator.static_data.cache.insert(key,17)==blot_error::Error.none);let stored=workspace.generator.static_data.cache.get(key);assert(stored && stored==17);
}
fn workspaceLifecycle() {
    var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && frame.valid());
    inspectWorkspace(frame);assert(frame.release()==blot_error::Error.none && !frame.valid());
}
fn tableViews() {
    var tables,error=blot_eval_core_eval::initSessionTables();assert(error==blot_error::Error.none);
    let state:blot_eval_core_eval::SessionTableState& =blot_eval_core_eval::tableState(tables);
    state.binding_offsets.push(17);state.binding_offsets.push(23);state.node_offsets.push(31);
    state.slots.push(blot_eval_core_eval::Slot{state:blot_eval_core_eval::State.complete,value:41});
    let bindings=blot_eval_core_eval::registeredOffsets(state.binding_offsets);
    let nodes=blot_eval_core_eval::registeredOffsets(state.node_offsets);
    let slots=blot_eval_core_eval::registeredSlots(state.slots);
    assert(bindings.len==2 && bindings[0]==17 && bindings[1]==23 && nodes.len==1 && nodes[0]==31);
    assert(slots.len==1 && slots[0].state==blot_eval_core_eval::State.complete && slots[0].value==41);
    assert(blot_support::same_slice_identity(bindings,state.binding_offsets.items));
    assert(blot_support::same_slice_identity(nodes,state.node_offsets.items));
    assert(blot_support::same_slice_identity(slots,state.slots.items));
    tables.deinit();assert(tables.lease==0);
}
fn checkedModule(success:bool)->blot_reuse_project_check::Module,blot_error::Error {
    if !success {return default<blot_reuse_project_check::Module>(),blot_error::Error.invalid_artifact;}
    let owner,error=blot_check_check::newCheckedOwner();assert(error==blot_error::Error.none);
    let types,error=blot_check_types::initPooled();assert(error==blot_error::Error.none);
    let patterns,error=blot_check_parameter_patterns::initPooled();assert(error==blot_error::Error.none);
    var checked=blot_check_check::Checked{owner:owner,types:blot_check_types::checkedView(types),parameter_patterns:blot_check_parameter_patterns::checkedView(patterns),unit:1,..};
    checked.expr_types=blot_check_check::ownChecked_expr_types(owner,[blot_check_types::u32_type]);
    checked.resolved=blot_check_check::ownChecked_resolved(owner,[0 as u32,1 as u32]);
    checked.usage_loans=blot_check_check::ownChecked_usage_loans(owner,[blot_check_check::UsageLoan{source:1,callback:1,parameter:1,region:blot_check_types::u32_type,mutable:false}]);
    checked.proof_bodies=blot_check_numeric_proof_bodies::Owned{operands:blot_check_check::ownChecked_body_operands(owner,[blot_check_numeric_proof_terms::Term{tag:blot_check_numeric_proof_terms::Tag.literal,a:19}]),..};
    checked.capability_contracts=blot_check_capability_contracts::Collection{words:blot_check_check::ownChecked_cap_words(owner,[29 as u32]),..};
    let nodes=blot_reuse_hole_diagnostics::node_pool.alloc_slice(1);nodes[0]=blot_reuse_hole_diagnostics::Node{kind:blot_reuse_hole_diagnostics::Kind.unsigned32};
    let context=blot_reuse_hole_diagnostics::Snapshot{nodes:nodes};
    let capture=blot_check_check::EditorCapture{names:blot_check_check::ownChecked_editor_names(owner,[blot_check_check::EditorName{name:7,kind:blot_check_check::EditorName_kind.value}]),kind:blot_reuse_completion_probe::Kind.expression,node:1,scope:blot_check_types::List{},owner:1,context:blot_support::Option<blot_reuse_hole_diagnostics::Snapshot>{true,context},..};
    checked.editor=blot_support::Option<blot_check_check::EditorCapture>{true,capture};
    return blot_reuse_project_check::Module{checked:checked,exports:default<blot_reuse_project_check::Export[:]>(),valid:true},blot_error::Error.none;
}
fn modulePublication() {
    var result,error=blot_reuse_project_check::initResult();assert(error==blot_error::Error.none);
    assert(result.allocateModules(1,false)==blot_error::Error.none);
    let module,error=checkedModule(true);assert(error==blot_error::Error.none);
    blot_reuse_project_check::publishModule(result,1,module);
    let jobs=blot_reuse_project_check::project_jobs.alloc_slice(1);jobs[0]=blot_reuse_project_check::ParallelJob{};
    {let slots=blot_reuse_project_check::moduleSlots(result);jobs[0].module=blot_support::Option<blot_reuse_project_check::Module>{true,blot_reuse_project_check::canonicalModule(slots[0].value)};slots[0]=blot_support::none<blot_reuse_project_check::Module>();}
    assert(jobs[0].module.present && jobs[0].module.value.checked.unit==1);
    blot_reuse_project_check::publishModule(result,1,jobs[0].module.value);jobs[0].module=blot_support::none<blot_reuse_project_check::Module>();
    workspaceLifecycle();assert(result.modules[0].present && result.modules[0].value.checked.types.valid());
    result.deinit();jobs[0].deinit();blot_reuse_project_check::project_jobs.free_slice(jobs);
}
fn packetModule()->blot_reuse_project_check::Module,blot_project_packet::Owner {
    var source,error=checkedModule(true);assert(error==blot_error::Error.none);
    var bytes:u8[>..<]=[];
    {var writer=blot_project_packet::Writer{bytes};blot_project_packet::put(writer,source.checked);assert(writer.failure==blot_error::Error.none);}
    var packet,error=blot_project_packet::initOwner();assert(error==blot_error::Error.none);
    var input,error=blot_project_packet::initOwner();assert(error==blot_error::Error.none);let encoded,error=blot_project_packet::allocate(input,bytes.len,0 as u8);assert(error==blot_error::Error.none);for byte,index in bytes {encoded[index]=byte;}
    var checked=default<blot_check_check::Checked>();
    {var reader=blot_project_packet::Reader{bytes:encoded,owner:packet};blot_project_packet::get(reader,checked);assert(reader.failure==blot_error::Error.none && reader.at==bytes.len);}
    var shared,error=packet.retain();assert(error==blot_error::Error.none);
    packet.deinit();input.deinit();bytes.clear();source.checked.deinit();
    assert(blot_check_check::checkedPacket(checked.owner).valid() && shared.valid());
    return blot_reuse_project_check::Module{checked:checked,exports:default<blot_reuse_project_check::Export[:]>(),valid:true},shared;
}
fn packetPublication() {
    var result,error=blot_reuse_project_check::initResult();assert(error==blot_error::Error.none && result.allocateModules(1,false)==blot_error::Error.none);
    let decoded,held=packetModule();var shared=held;
    blot_reuse_project_check::publishModule(result,1,decoded);shared.deinit();
    let jobs=blot_reuse_project_check::project_jobs.alloc_slice(1);jobs[0]=blot_reuse_project_check::ParallelJob{};
    {let slots=blot_reuse_project_check::moduleSlots(result);jobs[0].module=blot_support::Option<blot_reuse_project_check::Module>{true,blot_reuse_project_check::canonicalModule(slots[0].value)};slots[0]=blot_support::none<blot_reuse_project_check::Module>();}
    blot_reuse_project_check::publishModule(result,1,jobs[0].module.value);jobs[0].module=blot_support::none<blot_reuse_project_check::Module>();
    workspaceLifecycle();let checked:const blot_check_check::Checked& =result.modules[0].value.checked;
    assert(checked.types.valid() && checked.expr_types[0]==blot_check_types::u32_type && checked.resolved[1]==1);
    assert(checked.usage_loans.len==1 && checked.usage_loans[0].source==1 && checked.proof_bodies.operands[0].a==19 && checked.capability_contracts.words[0]==29);
    assert(checked.editor.present && checked.editor.value.names[0].name==7 && checked.editor.value.context.present && checked.editor.value.context.value.nodes[0].kind==blot_reuse_hole_diagnostics::Kind.unsigned32);
    result.deinit();jobs[0].deinit();blot_reuse_project_check::project_jobs.free_slice(jobs);
}
fn emptyPatternsPacket() {
    var bytes:u8[>..<]=[];
    {var writer=blot_project_packet::Writer{bytes};blot_project_packet::put(writer,blot_check_parameter_patterns::Store{});assert(writer.failure==blot_error::Error.none);}
    var packet,error=blot_project_packet::initOwner();assert(error==blot_error::Error.none);
    var input,error=blot_project_packet::initOwner();assert(error==blot_error::Error.none);
    let encoded,error=blot_project_packet::allocate(input,bytes.len,0 as u8);assert(error==blot_error::Error.none);for byte,index in bytes {encoded[index]=byte;}
    var store=blot_check_parameter_patterns::Store{};
    {var reader=blot_project_packet::Reader{bytes:encoded,owner:packet};blot_project_packet::get(reader,store);assert(reader.failure==blot_error::Error.none && reader.at==bytes.len);}
    assert(store.valid() && store.nodes().len==0 && store.extra().len==0);
    store.deinit();packet.deinit();input.deinit();bytes.clear();
}
type Prepared=blot_reuse_partial_dependency::Prepared;
type Preparation=blot_reuse_partial_dependency::Preparation;
fn preparedOfferValue()->Preparation {
 var owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
 let units,error=blot_reuse_dependency_payload::alloc<blot_check_core::Module>(owner,1);assert(error==blot_error::Error.none);units[0]=default<blot_check_core::Module>();units[0].unit=1;
 let order,error=owner.copy([1 as u32]);assert(error==blot_error::Error.none);
 let borrowed,error=owner.copy([false]);assert(error==blot_error::Error.none);
 let bytes,error=owner.copy("/tmp/probe.blot");assert(error==blot_error::Error.none);
 let paths,error=blot_reuse_dependency_payload::alloc<blot_reuse_dependency_payload::HeaderPath>(owner,1);assert(error==blot_error::Error.none);paths[0]=bytes;
 let symbols,error=blot_reuse_dependency_payload::alloc<blot_backend_runtime_identity::Name>(owner,1);assert(error==blot_error::Error.none);symbols[0]=blot_backend_runtime_identity::Name{};
 let names,error=blot_reuse_dependency_payload::alloc<blot_backend_runtime_identity::Name>(owner,1);assert(error==blot_error::Error.none);names[0]=blot_backend_runtime_identity::Name{0,bytes.len as u32};
 let unit_owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
 let unit_owners=blot_reuse_partial_dependency::core_owners.alloc_slice(1);unit_owners[0]=unit_owner;
 var value=blot_reuse_partial_dependency::publishPrepared(Prepared{units:units,identity:blot_backend_runtime_identity::Metadata{bytes,symbols,names},unit_order:order,paths:paths,borrowed:borrowed,entry:1,catalog_owner:owner,unit_owners:unit_owners,..});
 var seed_owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
 let seed_symbols,error=blot_reuse_dependency_payload::alloc<blot_reuse_frozen_dependency::Symbol>(seed_owner,1);assert(error==blot_error::Error.none);seed_symbols[0]=blot_reuse_frozen_dependency::Symbol{text:default<u8[:]>()};
 let seed,error=blot_reuse_retained_dependency::create(seed_symbols,0,seed_owner);assert(error==blot_error::Error.none && seed);
 let generation=blot_native::fresh_owner_id();let at=blot_reuse_source_completion::prefixes.alloc_index(blot_reuse_source_completion::PrefixState{graph:seed.value,generation:generation,live:true,..});
 blot_reuse_source_completion::prefixes[at].canonical=blot_reuse_source_completion::Prefix{(at+1) as u32,generation};seed.source_completion .= blot_reuse_source_completion::prefixes[at].canonical;
 var pin,error=seed.pinInputs();assert(error==blot_error::Error.none && pin.owners().len==1);
 assert(value.attachSeedPin(pin)==blot_error::Error.none && pin.len==0);
 assert(value.rebindFrozenPrefix(seed.value)==blot_error::Error.none);
 assert(blot_reuse_source_completion::mintEntry(value,seed)==blot_error::Error.none && value.source_completion);
 let completion=value.source_completion;let pin_start=value.seed_pin.start;
 value=blot_reuse_partial_dependency::publishPrepared(value);
 assert(value.source_completion .== completion && value.seed_pin.len==1 && value.seed_pin.start==pin_start);
 seed.deinit();assert(value.seed_pin.owners()[0].valid());
 return Preparation.ready{value};
}
fn preparedOffer()->blot_support::Option<Preparation> {let value=preparedOfferValue();return blot_support::Option<Preparation>{true,value};}
fn preparationPublication() {
    var offer=preparedOffer();assert(offer.present);
    match offer.value {ready bound=>{
        var ready=blot_reuse_partial_dependency::publishPrepared(bound.value);offer.value=blot_reuse_partial_dependency::Preparation.inactive;
        var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);
        let catalog=ready.catalog_owner;let unit_owner=ready.unit_owners[0];
        let unpinned,error=blot_backend_result_publication::inputUnits(blot_backend_result_publication::Owner{},ready.units);assert(error==blot_error::Error.invalid_artifact && unpinned.len==0);
        {let workspace=frame.borrow();assert(workspace);assert(blot_backend_core_backend::pinWorkspaceInputs(workspace,ready.units,ready.catalog_owner,ready.unit_owners,ready.seed_pin.owners())==blot_error::Error.none);
         let held=workspace.compiled_units;assert(held.len==1 && held[0].unit==1 && ready.source_completion && ready.seed_pin.owners().len==1);
         ready.deinit();let registered,error=blot_backend_scoped_backend::registeredModule(held,1);assert(error==blot_error::Error.none && registered && registered.unit==1);assert(catalog.valid() && unit_owner.valid() && held[0].unit==1);}
        assert(frame.release()==blot_error::Error.none && !catalog.valid() && !unit_owner.valid());
    },_=>{abort("ready preparation expected");}}
    offer.value.deinit();
}
fn seedPublication() {
    var owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
    let symbols,error=blot_reuse_dependency_payload::alloc<blot_reuse_frozen_dependency::Symbol>(owner,1);assert(error==blot_error::Error.none);symbols[0]=blot_reuse_frozen_dependency::Symbol{text:default<u8[:]>()};
    var owned=blot_reuse_dependency_payload::Owned<blot_reuse_frozen_dependency::FrozenDependency>{blot_reuse_frozen_dependency::FrozenDependency{symbols,default<blot_reuse_frozen_dependency::Module[:]>()},owner};
    let snapshot,error=blot_reuse_retained_dependency::adopt(owned);assert(error==blot_error::Error.none && snapshot && owned.owner.lease==0);
    var key=blot_reuse_retained_dependency::seed(snapshot);let stale=key;
    assert(key.valid());workspaceLifecycle();assert(key.value().symbols.len==1 && key.snapshot() .== snapshot);
    key.deinit();assert(!key.valid() && !stale.valid());
}
fn inputPublication() {
    let sources=[blot_reuse_source_overlays::Source{path:"/tmp/frame-input.blot",contents:blot_support::some<const u8[:]>("const value = 17\n")},blot_reuse_source_overlays::Source{path:"/tmp/frame-hidden.blot",contents:blot_support::none<const u8[:]>()}];
    var snapshot,error=blot_reuse_revision_inputs::initWithSources(blot_reuse_project::Options{..},sources[..]);assert(error==blot_error::Error.none);
    let stale=snapshot;let path,error=snapshot.canonical("/tmp/frame-input.blot");assert(error==blot_error::Error.none);
    let bytes,error=snapshot.read(path);assert(error==blot_error::Error.none && bytes=="const value = 17\n");
    let missing,error=snapshot.read("/tmp/frame-hidden.blot");assert(error==blot_error::Error.file_not_found && missing.len==0);var provider=snapshot.provider();assert(provider.cause(error)=="FileNotFound");
    workspaceLifecycle();assert(snapshot.valid() && snapshot.counts().source_reads==2);
    var frozen=snapshot.freeze();assert(!snapshot.valid() && !stale.valid() && frozen.valid());
    workspaceLifecycle();let captured=frozen.capturedSource(path);assert(captured.present && captured.value==bytes);
    let old=frozen;frozen.deinit();assert(!frozen.valid() && !old.valid());
}
fn main() {
    var previous:u64=0;
    for cycle in 0..4 {
        tableViews();
        modulePublication();
        packetPublication();
        emptyPatternsPacket();
        preparationPublication();
        seedPublication();
        inputPublication();
        let allocation_owner=blot_native::fresh_owner_id();
        let session,error=blot_eval_core_eval::initOwnedEmptySession(allocation_owner);
        assert(error==blot_error::Error.none && session);
        assert(session.units.len==0 && session.binding_offsets.len==0 && session.node_offsets.len==0 && session.slots.len==0);
        assert(session.allocation_owner==allocation_owner && session.session_owner_slot!=0);
        let generation=session.session_owner_generation;
        assert(generation>previous);
        previous=generation;
        blot_eval_core_eval::deinitOwnedSession(session);
        workspaceLifecycle();
    }
}
