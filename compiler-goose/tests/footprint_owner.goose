// Cached dispatch spellings own their bytes; target lists grow without borrowing keys.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import backend.storage_global_footprint;
import backend.host_cleanup_shapes;
import backend.storage_recursive_admission;
import backend.storage_parameter_fields;
import backend.scoped_backend;
import backend.storage_type_arguments;
import driver.compile_workspace;
import support.error;
import support.native;
import reuse.dependency_closure;
import reuse.dependency_owned_headers;
type FrozenModule=blot_reuse_frozen_dependency::Module;
fn typeCursors() {
    var journal=blot_backend_storage_type_arguments::Journal{..};var heads=blot_backend_storage_type_arguments::Heads{..};var published:blot_backend_storage_type_arguments::TypeArgument[>..<]=[];
    var owner=blot_backend_storage_type_arguments::Owner{journal:journal,heads:heads,published:published,..};var stack=blot_backend_storage_type_arguments::init(owner);
    assert(stack.append(blot_backend_storage_type_arguments::TypeArgument{unit:1,parameter:2,argument:3,argument_unit:1,..})==blot_error::Error.none);
    let before=blot_backend_storage_type_arguments::cursor(stack);let saved=blot_backend_storage_type_arguments::isolate(stack);assert(stack.id!=before.id && stack.len==0);
    assert(stack.append(blot_backend_storage_type_arguments::TypeArgument{unit:1,parameter:2,argument:7,argument_unit:1,..})==blot_error::Error.none);
    let nested=blot_backend_storage_type_arguments::isolate(stack);assert(stack.len==0);blot_backend_storage_type_arguments::restore(stack,nested);assert(stack.len==1);
    blot_backend_storage_type_arguments::restore(stack,saved);assert(stack.id==before.id && stack.len==before.len && stack.stats.synchronized==before.stats.synchronized);
    let entry=blot_backend_storage_type_arguments::heads(stack,1,2);assert(entry.any.present && blot_backend_storage_type_arguments::at(stack,entry.any.value).argument==3);stack.deinit();
}
struct NameArena {bytes:u8[>..<]&}
fn nameRanges() {
 var bytes:u8[>..<]=[];var metadata=NameArena{bytes};var source:u8[>..]=[];source.append("zebra");
 var z=default<blot_backend_scoped_backend::Value>();z.name=blot_backend_scoped_backend::publishName(metadata,source[..]);source=[];
 var a=default<blot_backend_scoped_backend::Value>();a.name=blot_backend_scoped_backend::publishName(metadata,"alpha");
 var same=default<blot_backend_scoped_backend::Value>();same.name=blot_backend_scoped_backend::publishName(metadata,"zebra");
 for index in 0..4096 {bytes.push(0);}assert(z.name.start!=same.name.start && blot_backend_scoped_backend::valueName(metadata,z)==blot_backend_scoped_backend::valueName(metadata,same));
 var values=[z,a];blot_backend_scoped_backend::orderFields(metadata,values[..]);assert(blot_backend_scoped_backend::valueName(metadata,values[0])=="alpha" && blot_backend_scoped_backend::valueName(metadata,values[1])=="zebra");
 let copied=z;assert(copied.name.start==z.name.start && copied.name.len==z.name.len && bytes.len==4111);
}
struct GoalArena {goals:blot_check_core::Obligation[>..<]&}
struct GoalReader {metadata:GoalArena&,units:const blot_check_core::Module[:]}
fn goalContexts() {
 let cache=blot_backend_storage_field_plan::init();assert(cache.entries.count==0 && cache.maximum_entries==65536);let startup=blot_eval_core_eval::StartupDependencies{};assert(startup.selected.len==0 && !startup.complete);let relocation=blot_reuse_dependency_closure::Relocation{};assert(relocation.seed==null && relocation.library==null && relocation.relocated==0);
 let empty=blot_backend_scoped_backend::GoalContext{};assert(empty.unit==0 && empty.span.len==0);
 var owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
 let obligations,error=owner.copy([blot_check_core::Obligation{name:17,..}]);assert(error==blot_error::Error.none);
 let units=blot_backend_result_publication::module_runs.alloc_slice(1);units[0]=blot_reuse_dependency_owned_headers::canonical(owner,blot_check_core::Module{unit:1,obligations:obligations,..});
 var goals:blot_check_core::Obligation[>..<]=[];var metadata=GoalArena{goals};var reader=GoalReader{metadata,units};
 let source=blot_backend_scoped_backend::GoalContext{unit:1,span:blot_backend_scoped_backend::Range{start:0,len:1}};assert(blot_backend_scoped_backend::contextGoals(reader,source)[0].name==17);
 let saved=blot_backend_scoped_backend::captureGoals(reader,source);let captured=blot_backend_scoped_backend::GoalContext{span:saved};for index in 0..100 {goals.push(blot_check_core::Obligation{name:index as u32,..});}
 let before=goals.len;let again=blot_backend_scoped_backend::captureGoals(reader,captured);assert(again.start==saved.start && again.len==saved.len && goals.len==before && blot_backend_scoped_backend::contextGoals(reader,captured)[0].name==17);
 blot_backend_result_publication::module_runs.free_slice(units);owner.deinit();var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);assert(blot_backend_scoped_backend::contextGoals(reader,captured)[0].name==17);
}
fn rootRuns() {
    var regions=blot_backend_scoped_backend::IndexSet{};assert(regions.insert(-7,true)==blot_error::Error.none && regions.contains(-7));regions.clear();assert(!regions.contains(-7));regions.deinit();
    var bytes:u8[>..<]=[];var arena=NameArena{bytes};let spelling=blot_backend_scoped_backend::publishName(arena,"element");
    var layouts=blot_backend_scoped_backend::PlainLayouts{};let shape=default<blot_backend_scoped_backend::Value>();
    assert(blot_backend_scoped_backend::insert(layouts,1 as u64,shape)==blot_error::Error.none);assert(blot_backend_scoped_backend::contains(layouts,1 as u64));layouts.deinit();
    var roots=blot_backend_scoped_backend::Roots{};
    for ordinal in 0..24 {var root=default<blot_backend_scoped_backend::Root>();root.stack=ordinal as u32;root.element.name=spelling;assert(blot_backend_scoped_backend::push(roots,root)==blot_error::Error.none);}
    let registered=blot_backend_scoped_backend::registeredRoots(roots);
    for ordinal in 0..registered.len {let word=blot_backend_runtime_code::Local{(ordinal+1) as u32};registered[ordinal].word=word;registered[ordinal].global_ready=blot_support::Option<blot_backend_runtime_code::Local>{true,word};}
    var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
    assert(registered.len==24 && registered[23].stack==23 && registered[23].word.id==24 && registered[23].global_ready.present && blot_backend_scoped_backend::valueName(arena,registered[23].element)=="element");
    roots.deinit();
}
// Exercise the owned header projection with nonempty Core payloads; semantic
// receipt admission remains the separate validated empty-closure control above.
fn nonemptyCompletedViews() {
 var owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
 let names,error=owner.copy("completed-core");assert(error==blot_error::Error.none);let nodes,error=owner.copy([blot_check_types::Node{tag:blot_check_types::Tag.boolean,..}]);assert(error==blot_error::Error.none);
 var module=default<FrozenModule>();module.core.unit=1;module.core.names=names;module.core.types.nodes=nodes;module.identity.source_bytes=23;
 let source,error=blot_reuse_dependency_payload::alloc<FrozenModule>(owner,1);assert(error==blot_error::Error.none);source[0]=blot_reuse_dependency_owned_headers::canonical(owner,module);let graph=blot_reuse_frozen_dependency::FrozenDependency{modules:source,..};
 let modules,lengths=blot_reuse_dependency_closure::completedModuleViews(graph,owner);
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
 assert(modules.len==1 && modules[0].unit==1 && modules[0].names=="completed-core" && modules[0].types.nodes[0].tag==blot_check_types::Tag.boolean && lengths[0]==23);
 blot_reuse_dependency_closure::completed_modules.free_slice(modules);blot_reuse_dependency_closure::completed_lengths.free_slice(lengths);owner.deinit();
}
fn typeKeyHeader() {
 var key=blot_backend_storage_type_key::init(100);var output=blot_backend_storage_type_key::Words{};
 let reference=blot_backend_storage_type_key::Reference{unit:1,ty:2,..};let pending,error=key.enter(reference,0);assert(error==blot_error::Error.none && !pending.present);
 let start=key.beginDescriptor();assert(key.descriptorWord(start,42)==blot_error::Error.none);
 let result,error=key.completeDescriptor(reference,start,1);assert(error==blot_error::Error.none);key.endDescriptor(start);
 assert(key.root(output,result)==blot_error::Error.none && key.finish(output)==blot_error::Error.none);
 assert(output.items.len==7 && output.items[0]==0 && output.items[1]==0x53444b31 && output.items[2]==1 && output.items[3]==1 && output.items[4]==1 && output.items[5]==1 && output.items[6]==42);
 output.deinit();key.deinit();
}

fn transportAnchors() {
 var owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
 let bindings,error=owner.copy([blot_check_core::Binding{kind:blot_reuse_principal_interface::Kind.local,..},blot_check_core::Binding{kind:blot_reuse_principal_interface::Kind.parameter,..},blot_check_core::Binding{kind:blot_reuse_principal_interface::Kind.local,..},blot_check_core::Binding{kind:blot_reuse_principal_interface::Kind.local,..},blot_check_core::Binding{kind:blot_reuse_principal_interface::Kind.local,..}]);assert(error==blot_error::Error.none);
 let merges,error=owner.copy([blot_check_core::Merge{result:3,then_binding:1,else_binding:2,..},blot_check_core::Merge{result:4,then_binding:1,else_binding:1,..}]);assert(error==blot_error::Error.none);
 let units=blot_backend_result_publication::module_runs.alloc_slice(1);units[0]=blot_reuse_dependency_owned_headers::canonical(owner,blot_check_core::Module{unit:1,bindings:bindings,merges:merges,..});
 var index=blot_backend_storage_transport::Index{module:units[0],owner_id:1,lease:-1,..};blot_support_pooled_map::insert(index.merges,3 as u32,0 as i64,blot_backend_storage_transport::ordinal_slots);blot_support_pooled_map::insert(index.merges,4 as u32,1 as i64,blot_backend_storage_transport::ordinal_slots);
 for field in ["left","right"] {var query=blot_backend_storage_transport::LaneQuery{..};let changed,error=blot_backend_storage_transport::laneBinding(index,3,field,query,0);assert(error==blot_error::Error.none && !changed.present);let same,error=blot_backend_storage_transport::laneBinding(index,4,field,query,0);assert(error==blot_error::Error.none && same.present && same.value==1);}
 var query=blot_backend_storage_transport::LaneQuery{iteration:42,anchor:blot_support::some<u32>(1),..};let inherited,error=blot_backend_storage_transport::laneBinding(index,42,"left",query,0);assert(error==blot_error::Error.none && inherited.present && inherited.value==1);
 blot_support_pooled_map::deinit(index.merges,blot_backend_storage_transport::ordinal_slots);blot_backend_result_publication::module_runs.free_slice(units);owner.deinit();
}
fn pooledCleanup() {
 for cycle in 0..3 {
  let access=blot_backend_storage_recursive_admission::access_pool.alloc_slice(2);access[0]=blot_backend_storage_recursive_admission::Access{read:true,..};access[1]=blot_backend_storage_recursive_admission::Access{write:true,..};blot_backend_storage_recursive_admission::freeAccess(access);
  let owners=blot_backend_storage_recursive_admission::owner_pool.alloc_slice(1);owners[0]=blot_support::some<i64>(7);let edges=blot_backend_storage_recursive_admission::edge_pool.alloc_slice(1);edges[0]=blot_backend_storage_recursive_admission::Edge{target:blot_check_core::BindingRef{1,2},owners:owners};blot_backend_storage_recursive_admission::freeEdges(edges);
  let field=blot_backend_host_cleanup_shapes::owned_fields.alloc_slice(1);field[0]=blot_backend_host_cleanup_shapes::Field{name:"value",child:1};
  let node=blot_backend_host_cleanup_shapes::Node{id:1,tag:blot_backend_host_cleanup_shapes::Tag.record,children:blot_backend_host_cleanup_shapes::copyChildren([1 as u32,2 as u32]),fields:field,variants:blot_backend_host_cleanup_shapes::copyVariants([blot_backend_host_cleanup_shapes::Variant{tag:3,child:2}]),..};blot_backend_host_cleanup_shapes::deinit(node);
 }
}
fn parameterFieldWalk() {
 var owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
 let nodes,error=blot_reuse_dependency_payload::alloc<blot_check_core::Node>(owner,141);assert(error==blot_error::Error.none);for &node in nodes {node=blot_check_core::Node{tag:blot_check_core::Tag.invalid,..};}
 nodes[1]=blot_check_core::Node{tag:blot_check_core::Tag.reference,a:0,..};nodes[2]=blot_check_core::Node{tag:blot_check_core::Tag.project,a:1,b:0,..};nodes[3]=blot_check_core::Node{tag:blot_check_core::Tag.project,a:1,b:1,..};nodes[4]=blot_check_core::Node{tag:blot_check_core::Tag.product,a:0,b:3,..};nodes[5]=blot_check_core::Node{tag:blot_check_core::Tag.reference,a:1,..};nodes[6]=blot_check_core::Node{tag:blot_check_core::Tag.product,a:3,b:1,..};
 for index in 7..140 {nodes[index]=blot_check_core::Node{tag:blot_check_core::Tag.bind,b:(index-1) as u32,..};}nodes[140]=blot_check_core::Node{tag:blot_check_core::Tag.match_,..};
 let references,error=owner.copy([blot_check_core::BindingRef{0,11},blot_check_core::BindingRef{0,12}]);assert(error==blot_error::Error.none);let extra,error=owner.copy([2 as u32,3 as u32,2 as u32,5 as u32]);assert(error==blot_error::Error.none);
 let names,error=owner.copy("ab");assert(error==blot_error::Error.none);let fields,error=owner.copy([blot_check_core::FieldName{symbol:7,spelling:blot_check_core::Name{0,1}},blot_check_core::FieldName{symbol:9,spelling:blot_check_core::Name{1,1}}]);assert(error==blot_error::Error.none);
 let projections,error=owner.copy([blot_check_core::Projection{field:7,..},blot_check_core::Projection{field:9,..}]);assert(error==blot_error::Error.none);
 let modules,error=blot_reuse_dependency_payload::alloc<blot_check_core::Module>(owner,1);assert(error==blot_error::Error.none);modules[0]=blot_reuse_dependency_owned_headers::canonical(owner,blot_check_core::Module{field_names:fields,unit:1,nodes:nodes,extra:extra,references:references,names:names,projections:projections,..});
 let nominal=blot_support::none<blot_backend_storage_parameter_fields::NominalRecord>();
 var selected,error=blot_backend_storage_parameter_fields::collect(modules[0],4,11,nominal);assert(error==blot_error::Error.none && !selected.whole && selected.names.items.len==2 && selected.names.items[0]==7 && selected.names.items[1]==9);
 var foreign,error=blot_backend_storage_parameter_fields::collect(modules[0],6,11,nominal);assert(error==blot_error::Error.none && !foreign.whole && foreign.names.items.len==0);foreign.deinit();
 for root in [1 as u32,139 as u32,140 as u32] {var whole,error=blot_backend_storage_parameter_fields::collect(modules[0],root,11,nominal);assert(error==blot_error::Error.none && whole.whole);whole.deinit();}
 owner.deinit();var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && frame.release()==blot_error::Error.none);assert(selected.names.items.len==2 && selected.names.items[0]==7 && selected.names.items[1]==9);selected.deinit();
}
fn completedSlotCache() {
 var owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
 let nodes,error=owner.copy([blot_check_core::Node{tag:blot_check_core::Tag.invalid,..},blot_check_core::Node{tag:blot_check_core::Tag.reference,a:0,..},blot_check_core::Node{tag:blot_check_core::Tag.reference,a:1,..},blot_check_core::Node{tag:blot_check_core::Tag.product,a:0,b:2,..},blot_check_core::Node{tag:blot_check_core::Tag.reference,a:2,..}]);assert(error==blot_error::Error.none);
 let references,error=owner.copy([blot_check_core::BindingRef{0,22},blot_check_core::BindingRef{0,33},blot_check_core::BindingRef{0,44}]);assert(error==blot_error::Error.none);let extra,error=owner.copy([1 as u32,2 as u32]);assert(error==blot_error::Error.none);
 let bindings,error=blot_reuse_dependency_payload::alloc<blot_check_core::Binding>(owner,45);assert(error==blot_error::Error.none);for &binding in bindings {binding=blot_check_core::Binding{kind:blot_reuse_principal_interface::Kind.global,..};}
 bindings[44].body_id=1;let bodies,error=owner.copy([blot_check_core::Body{..},blot_check_core::Body{binding:44,root:2,..}]);assert(error==blot_error::Error.none);
 let units,error=blot_reuse_dependency_payload::alloc<blot_check_core::Module>(owner,1);assert(error==blot_error::Error.none);units[0]=blot_reuse_dependency_owned_headers::canonical(owner,blot_check_core::Module{unit:1,nodes:nodes,extra:extra,bindings:bindings,bodies:bodies,references:references,..});
 let globals=[blot_check_core::BindingRef{1,22},blot_check_core::BindingRef{1,33}];var index,error=blot_backend_storage_global_footprint::init(units,globals);assert(error==blot_error::Error.none);
 let first,error=index.slots(1,1,blot_check_types::Scheme{..});assert(error==blot_error::Error.none && first.len==1 && first[0]==0);
 let second,error=index.slots(1,2,blot_check_types::Scheme{..});assert(error==blot_error::Error.none && second.len==1 && second[0]==1);
 let both,error=index.slots(1,3,blot_check_types::Scheme{..});assert(error==blot_error::Error.none && both.len==2 && both[0]==0 && both[1]==1);
 let indirect,error=index.slots(1,4,blot_check_types::Scheme{..});assert(error==blot_error::Error.none && indirect.len==1 && indirect[0]==1);let edge .=blot_support_pooled_map::get(index.direct,blot_backend_storage_global_footprint::Node{unit:1,root:4,..});assert(edge && edge.nodes.len==1 && edge.nodes[0].root==2);
 let fallback,error=index.slots(2,0,blot_check_types::Scheme{..});assert(error==blot_error::Error.none && blot_support::same_slice_identity(fallback,index.all));
 let count=index.completed.count;let again,error=index.slots(1,1,blot_check_types::Scheme{..});assert(error==blot_error::Error.none && index.completed.count==count && blot_support::same_slice_identity(first,again));
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && frame.release()==blot_error::Error.none);assert(first[0]==0 && second[0]==1 && both[1]==1 && indirect[0]==1 && fallback.len==2);index.deinit();owner.deinit();
 let no_units:blot_check_core::Module[0]=default<blot_check_core::Module[0]>();let no_globals:blot_check_core::BindingRef[0]=default<blot_check_core::BindingRef[0]>();var empty,error=blot_backend_storage_global_footprint::init(no_units[..],no_globals[..]);assert(error==blot_error::Error.none);let no_slots,error=empty.slots(1,0,blot_check_types::Scheme{..});assert(error==blot_error::Error.none && no_slots.len==0 && empty.completed.count==0);empty.deinit();
}
fn main() {completedSlotCache();parameterFieldWalk();
    pooledCleanup();
    transportAnchors();
    typeKeyHeader();
    goalContexts();
    nameRanges();
    nonemptyCompletedViews();
    for cycle in 0..4 {
        rootRuns();
        typeCursors();
        var text:u8[>..]=[];text.append("dispatch");
        let names=[blot_check_core::FieldName{symbol:1,spelling:blot_check_core::Name{0,8}}];
        var associated:blot_check_core::Associated[12]=default<blot_check_core::Associated[12]>();
        var globals:blot_check_core::BindingRef[12]=default<blot_check_core::BindingRef[12]>();
        for index in 0..12 {let target=blot_check_core::BindingRef{1,(index+1) as u32};globals[index]=target;associated[index]=blot_check_core::Associated{identity:blot_check_types::NominalIdentity{..},member:1,operator:blot_check_types::Operator.none,target:target};}
        let units=[blot_check_core::Module{field_names:names[..],unit:1,names:text[..],associated:associated[..],..}];
        var index,error=blot_backend_storage_global_footprint::init(units[..],globals[..]);assert(error==blot_error::Error.none && index.names.count==1);
        {let found=index.names.get("dispatch");assert(found && found.items.len==12 && found.items[11].binding==12);}
        for slot in index.names.slots {if slot.tag!=0 {assert(slot.key==text[..] && !blot_support::same_slice_identity(slot.key,text[..]));}}
        var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
        index.deinit();text=[];
    }
}
