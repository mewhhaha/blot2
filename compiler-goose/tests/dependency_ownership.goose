// Retained metadata admission/sharing uses real journals; semantic Core validation is a separate boundary.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import reuse.retained_dependency;
import reuse.dependency_owned_headers;
import support.error;
type Owner=blot_reuse_dependency_payload::Owner;
type FrozenModule=blot_reuse_frozen_dependency::Module;
fn module(seed:u32)->blot_reuse_dependency_payload::Owned<FrozenModule> {
    var owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);var value=default<FrozenModule>();
    let path,error=owner.copy("/tmp/owned-module.blot");assert(error==blot_error::Error.none);value.identity.normalized_path=path;value.identity.source_bytes=17;value.implicit_prelude=true;
    let imports,error=owner.copy([seed]);assert(error==blot_error::Error.none);value.imports=imports;
    let source_path,error=owner.copy("./owned-import");assert(error==blot_error::Error.none);
    let requests,error=blot_reuse_dependency_payload::alloc<blot_reuse_frozen_dependency::ImportResolution>(owner,1);assert(error==blot_error::Error.none);requests[0]=blot_reuse_frozen_dependency::ImportResolution{source_path,seed};value.source_imports=requests;
    value.core.unit=seed;let names,error=owner.copy("owned-core");assert(error==blot_error::Error.none);value.core.names=names;
    let nodes,error=owner.copy([blot_check_types::Node{tag:blot_check_types::Tag.boolean,..}]);assert(error==blot_error::Error.none);value.core.types.nodes=nodes;
    let words,error=owner.copy([7 as u32,9 as u32]);assert(error==blot_error::Error.none);value.core.types.extra=words;
    let capabilities,error=owner.copy([19 as u32]);assert(error==blot_error::Error.none);value.core.capability_contracts.words=capabilities;
    value.interface.unit=seed;let interface_nodes,error=owner.copy([blot_check_types::Node{tag:blot_check_types::Tag.unsigned32,..}]);assert(error==blot_error::Error.none);value.interface.graph.nodes=interface_nodes;
    let patterns,error=owner.copy([blot_check_parameter_patterns::Node{blot_check_parameter_patterns::Kind.binding,23}]);assert(error==blot_error::Error.none);value.interface.patterns.nodes=patterns;
    let bindings,error=blot_reuse_dependency_payload::alloc<blot_reuse_principal_interface::Binding>(owner,1);assert(error==blot_error::Error.none);bindings[0]=default<blot_reuse_principal_interface::Binding>();bindings[0].name=seed;value.interface.bindings=bindings;
    let interface_words,error=owner.copy([29 as u32]);assert(error==blot_error::Error.none);value.interface.capability_contracts.words=interface_words;
    return blot_reuse_dependency_payload::Owned<FrozenModule>{value,owner};
}
fn emptySnapshot()->blot_reuse_retained_dependency::Snapshot& {
    var owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
    let symbols,error=blot_reuse_dependency_payload::alloc<blot_reuse_frozen_dependency::Symbol>(owner,1);assert(error==blot_error::Error.none);symbols[0]=blot_reuse_frozen_dependency::Symbol{text:default<u8[:]>()};
    let result,error=blot_reuse_retained_dependency::create(symbols,1,owner);assert(error==blot_error::Error.none && result!=null);return result;
}
fn inspect(value:FrozenModule) {
    assert(value.identity.normalized_path=="/tmp/owned-module.blot" && value.identity.source_bytes==17 && value.implicit_prelude);
    assert(value.imports==[1 as u32] && value.source_imports[0].path=="./owned-import");assert(value.core.unit==1 && value.core.names=="owned-core");
    assert(value.core.types.nodes[0].tag==blot_check_types::Tag.boolean && value.core.types.extra==[7 as u32,9 as u32] && value.core.capability_contracts.words==[19 as u32]);
    assert(value.interface.unit==1 && value.interface.graph.nodes[0].tag==blot_check_types::Tag.unsigned32 && value.interface.patterns.nodes[0].a==23 && value.interface.bindings[0].name==1 && value.interface.capability_contracts.words==[29 as u32]);
}
fn shareAndRelease(source:blot_reuse_retained_dependency::Snapshot&) {
    let child=blot_reuse_retained_dependency::module_owners[source.modules[0].slot-1].owner;
    var pin,error=source.pinInputs();assert(error==blot_error::Error.none && !child.unique());
    let shared=emptySnapshot();assert(shared.appendShared(source,0)==blot_error::Error.none && shared.shares(source,0) && shared.references(0)==2);
    source.deinit();inspect(shared.value.modules[0]);pin.deinit();assert(child.valid() && child.unique());inspect(shared.value.modules[0]);shared.deinit();assert(!child.valid());
}
fn appended() {
    let source=emptySnapshot();var owned=module(1);let child=owned.owner;
    assert(source.appendOwned(owned)==blot_error::Error.none && owned.owner.lease==0 && source.initialized==1);inspect(source.value.modules[0]);assert(child.valid());shareAndRelease(source);
}
fn adopted() {
    var owned=module(1);var root,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
    owned.owner.partitionInto(root,owned.value);owned.owner.deinit();
    let symbols,error=blot_reuse_dependency_payload::alloc<blot_reuse_frozen_dependency::Symbol>(root,1);assert(error==blot_error::Error.none);symbols[0]=blot_reuse_frozen_dependency::Symbol{text:default<u8[:]>()};
    let modules,error=blot_reuse_dependency_payload::alloc<FrozenModule>(root,1);assert(error==blot_error::Error.none);modules[0]=blot_reuse_dependency_owned_headers::canonical(root,owned.value);
    var frozen=blot_reuse_dependency_payload::Owned<blot_reuse_frozen_dependency::FrozenDependency>{blot_reuse_frozen_dependency::FrozenDependency{symbols,modules},root};
    let source,error=blot_reuse_retained_dependency::adopt(frozen);assert(error==blot_error::Error.none && source!=null && frozen.owner.lease==0);inspect(source.value.modules[0]);shareAndRelease(source);
}
fn receiptReturn() {
    var executor=blot_project_executor::init();var source,error=blot_reuse_project::init();assert(error==blot_error::Error.none);
    let checked=default<blot_reuse_project_check::CheckedProject>();
    let value,receipt,error=blot_reuse_dependency_closure::freezeDeferred(executor,source,checked,true);
    assert(error==blot_error::Error.invalid_artifact && value.owner.lease==0 && receipt==null);source.deinit();executor.deinit();
}
fn main() {for cycle in 0..3 {appended();adopted();receiptReturn();}print("dependency ownership passed: owned admission, partition, pins, shared lifetime and cleanup");}
