// Cached dispatch spellings own their bytes; target lists grow without borrowing keys.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import backend.storage_global_footprint;
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
fn rootRuns() {
    var layouts=blot_backend_scoped_backend::PlainLayouts{};let shape=default<blot_backend_scoped_backend::Value>();
    assert(blot_backend_scoped_backend::insert(layouts,1 as u64,shape)==blot_error::Error.none);assert(blot_backend_scoped_backend::contains(layouts,1 as u64));layouts.deinit();
    var roots=blot_backend_scoped_backend::Roots{};
    for ordinal in 0..24 {var root=default<blot_backend_scoped_backend::Root>();root.stack=ordinal as u32;root.element.name="element";assert(blot_backend_scoped_backend::push(roots,root)==blot_error::Error.none);}
    let registered=blot_backend_scoped_backend::registeredRoots(roots);
    for ordinal in 0..registered.len {let word=blot_backend_runtime_code::Local{(ordinal+1) as u32};registered[ordinal].word=word;registered[ordinal].global_ready=blot_support::Option<blot_backend_runtime_code::Local>{true,word};}
    var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
    assert(registered.len==24 && registered[23].stack==23 && registered[23].word.id==24 && registered[23].global_ready.present && registered[23].element.name=="element");
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
fn main() {
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
