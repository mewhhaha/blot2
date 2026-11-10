// Both identity authorities retain their exact runs; shared journals are read-only.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import backend.runtime_identity;
import reuse.dependency_identity;
import driver.compile_workspace;
type View=blot_backend_runtime_identity::View;
type Owner=blot_reuse_dependency_payload::Owner;
fn sameIdentity(left:View,right:View) {
 assert(blot_support::same_slice_identity(left.bytes,right.bytes));
 assert(blot_support::same_slice_identity(left.symbols,right.symbols));
 assert(blot_support::same_slice_identity(left.owners,right.owners));
 assert(right.symbol(1).value=="value"&&right.owner(1).value=="/identity.blot");
}
fn sharedIdentity()->Owner,View {
 let symbols:blot_backend_runtime_identity::Name[2]=[blot_backend_runtime_identity::Name{},blot_backend_runtime_identity::Name{0,5}];
 let owners:blot_backend_runtime_identity::Name[1]=[blot_backend_runtime_identity::Name{5,14}];
 let input=View{bytes:"value/identity.blot",symbols:symbols[..],owners:owners[..]};
 var metadata,error=blot_backend_runtime_identity::copy(input);assert(error==blot_error::Error.none);
 let metadata_view=metadata.view();sameIdentity(metadata_view,blot_backend_runtime_identity::registeredMetadataView(metadata_view));
 var owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
 let bytes,error=owner.copy(metadata.bytes);assert(error==blot_error::Error.none);
 let names,error=owner.copy(metadata.symbols);assert(error==blot_error::Error.none);
 let paths,error=owner.copy(metadata.owners);assert(error==blot_error::Error.none);
 let source=View{bytes:bytes,symbols:names,owners:paths};
 let retained,error=owner.retain();assert(error==blot_error::Error.none&&!owner.unique());
 sameIdentity(source,blot_reuse_dependency_payload::registeredIdentity(retained,source));
 let empty=blot_reuse_dependency_payload::registeredIdentity(retained,default<View>());assert(empty.bytes.len==0&&empty.symbols.len==0&&empty.owners.len==0);
 metadata.deinit();owner.deinit();assert(retained.valid());
 return retained,blot_reuse_dependency_payload::registeredIdentity(retained,source);
}
fn main() {
 let empty=blot_backend_runtime_identity::registeredMetadataView(default<View>());assert(empty.bytes.len==0&&empty.symbols.len==0&&empty.owners.len==0);
 let key,names=sharedIdentity();var retained=key;
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
 sameIdentity(names,blot_reuse_dependency_payload::registeredIdentity(retained,names));
 let stale=retained;retained.deinit();assert(!stale.valid());
 print("identity owner views passed");
}
