// Immutable modules are retained independently of the preceding revision.
namespace blot_reuse_retained_dependency;
import reuse.frozen_dependency;
import reuse.dependency_payload;
import reuse.dependency_owned_headers;
import reuse.completed_core_validation;
import reuse.source_completion;
import support.error;
import support.native;
type Error=blot_error::Error;
type Frozen=blot_reuse_frozen_dependency::FrozenDependency;
type FrozenModule=blot_reuse_frozen_dependency::Module;
type Owner=blot_reuse_dependency_payload::Owner;
type OwnedModule=blot_reuse_dependency_payload::Owned<FrozenModule>;
type OwnedFrozen=blot_reuse_dependency_payload::Owned<Frozen>;
struct Stats {shared_modules:i64=0,fresh_modules:i64=0,core_checked:i64=0,core_reused:i64=0,interface_checked:i64=0,interface_reused:i64=0}
struct ModuleHandle {slot:u32=0,generation:u64=0}
struct Module {live:bool=false,generation:u64=0,references:u64=1,value:FrozenModule=default<FrozenModule>(),owner:Owner=Owner {..}}
reusable var module_owners:Module[>..]=[];
fn valid(self_:ModuleHandle)->bool {return self_.slot!=0&&self_.slot-1<module_owners.len&&module_owners[self_.slot-1].live&&module_owners[self_.slot-1].generation==self_.generation;}
fn allocateModule()->ModuleHandle,Error {if module_owners.len>=0xffffffff {return ModuleHandle {..},blot_error::Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=module_owners.alloc_index(Module {live:true,generation:generation, ..});return ModuleHandle {(at+1) as u32,generation, ..},blot_error::Error.none;}
fn release(self_:ModuleHandle) {assert(self_.valid());let at=self_.slot-1;let module:Module& =module_owners[at];assert(module.references!=0);module.references--;if module.references!=0 {return;}module.owner.deinit();module.live=false;module_owners.free(at);}
struct Snapshot {
 slot:u32=0,generation:u64=0,live:bool=false,value:Frozen=default<Frozen>(),modules:ModuleHandle[:]=default<ModuleHandle[:]>(),initialized:i64=0,validated:bool=false,
 core_validation:blot_reuse_completed_core_validation::Receipt?=null,source_completion:blot_reuse_source_completion::Prefix?=null,owner:Owner=Owner {..},
}
reusable var snapshots:Snapshot[>..]=[];
reusable[] var handles:ModuleHandle[>..]=[];
struct InputPin {start:i64=0,len:i64=0}
reusable[] var input_owner_runs:Owner[>..]=[];
fn pinInputs(self_:const Snapshot&)->InputPin,Error {
 if !self_.valid() || self_.initialized!=self_.modules.len {return InputPin{..},blot_error::Error.invalid_artifact;}
 let owners=input_owner_runs.alloc_slice(self_.modules.len+1);for &owner in owners {owner=Owner{..};}
 let root,error=self_.owner.retain();if error!=blot_error::Error.none {input_owner_runs.free_slice(owners);return InputPin{..},error;}owners[0]=root;
 for handle,index in self_.modules {assert(handle.valid());let owner,error=module_owners[handle.slot-1].owner.retain();if error!=blot_error::Error.none {for &prior in owners[..index+1] {prior.release();}input_owner_runs.free_slice(owners);return InputPin{..},error;}owners[index+1]=owner;}
 let first:Owner& =owners[0];let start=input_owner_runs.index_of(first);return InputPin{start,owners.len},blot_error::Error.none;
}
fn owners(self_:InputPin)->Owner[:] {if self_.len==0 {return default<Owner[:]>();}assert(self_.start>=0 && self_.start<=input_owner_runs.len && self_.len<=input_owner_runs.len-self_.start);return input_owner_runs[self_.start..self_.start+self_.len];}
fn deinit(self_:InputPin&) {let owners=self_.owners();for &owner in owners {owner.release();}if owners.len!=0 {input_owner_runs.free_slice(owners);}self_=InputPin{..};}
fn valid(self_:const Snapshot&)->bool {return self_.live&&self_.slot!=0&&self_.slot-1<snapshots.len&&snapshots[self_.slot-1].live&&snapshots[self_.slot-1].generation==self_.generation;}
fn allocateSnapshot(count:i64)->Snapshot?,Error {
 if count<0||count>0xffffffff||snapshots.len>=0xffffffff {return null,blot_error::Error.out_of_memory;}
 let slots=handles.alloc_slice(count);for &slot in slots {slot=ModuleHandle {..};}
 let generation=blot_native::fresh_owner_id();let at=snapshots.alloc_index(Snapshot {generation:generation,live:true,modules:slots, ..});snapshots[at].slot=(at+1) as u32;return snapshots[at],blot_error::Error.none;
}
fn discardBookkeeping(self_:Snapshot&) {assert(self_.valid()&&self_.initialized==0&&self_.owner.lease==0);if self_.modules.len!=0 {handles.free_slice(self_.modules);}let at=self_.slot-1;self_.live=false;snapshots.free(at);}
fn create(symbols:blot_reuse_frozen_dependency::Symbol[:],count:i64,owner:Owner&)->Snapshot?,Error {
 let self_,error=allocateSnapshot(count);if error!=blot_error::Error.none {return null,error;}assert(self_!=null);let views,failure=blot_reuse_dependency_payload::alloc<FrozenModule>(owner,count);if failure!=blot_error::Error.none {self_.discardBookkeeping();return null,failure;}
 self_.owner=copy(owner);owner=Owner {..};self_.value=Frozen {symbols,views, ..};return self_,blot_error::Error.none;
}
fn adopt(value:OwnedFrozen&)->Snapshot?,Error {
 let self_,error=allocateSnapshot(value.value.modules.len);if error!=blot_error::Error.none {return null,error;}assert(self_!=null);var allocated:i64=0;var failure=blot_error::Error.none;
 // Complete every metadata allocation before consuming any caller-owned run.
 for index in self_.modules.len {
  let handle,created=allocateModule();if created!=blot_error::Error.none {failure=created;break;}
  self_.modules[index]=handle;allocated++;let owner,opened=blot_reuse_dependency_payload::init();if opened!=blot_error::Error.none {failure=opened;break;}module_owners[handle.slot-1].owner=owner;
 }
 if failure!=blot_error::Error.none {for handle in self_.modules[..allocated] {handle.release();}self_.discardBookkeeping();return null,failure;}
 // Rebind the outer journal runs before partitioning their child ownership.
 let modules=value.owner.mutable(value.value.modules);let symbols=value.owner.mutable(value.value.symbols);
 for module,index in modules {
  let destination:Module& =module_owners[self_.modules[index].slot-1];value.owner.partitionInto(destination.owner,module);destination.value=blot_reuse_dependency_owned_headers::canonical(destination.owner,module);
 }
 self_.value=Frozen{symbols,modules};self_.owner=value.owner;self_.initialized=self_.modules.len;value=default<OwnedFrozen>();return self_,blot_error::Error.none;
}
fn append(self_:Snapshot&,handle:ModuleHandle) {assert(self_.valid()&&!self_.validated&&self_.initialized<self_.modules.len&&handle.valid());self_.modules[self_.initialized]=handle;self_.value.modules[self_.initialized]=module_owners[handle.slot-1].value;self_.initialized++;}
fn appendOwned(self_:Snapshot&,value:OwnedModule&)->Error {
 let handle,error=allocateModule();if error!=blot_error::Error.none {value.deinit();return error;}
 let module:Module& =module_owners[handle.slot-1];module.value=blot_reuse_dependency_owned_headers::canonical(value.owner,value.value);module.owner=value.owner;value=default<OwnedModule>();self_.append(handle);return blot_error::Error.none;
}
fn appendShared(self_:Snapshot&,previous:const Snapshot&,index:i64)->Error {
 assert(previous.valid()&&index>=0&&index<previous.initialized);let handle=previous.modules[index];assert(handle.valid());let module:Module& =module_owners[handle.slot-1];if module.references==0xffffffffffffffff {return blot_error::Error.dependency_limit;}module.references++;self_.append(handle);return blot_error::Error.none;
}
fn shares(self_:const Snapshot&,previous:const Snapshot&,index:i64)->bool {return index>=0&&index<self_.initialized&&index<previous.initialized&&self_.modules[index]==previous.modules[index];}
fn references(self_:const Snapshot&,index:i64)->u64 {assert(self_.valid()&&index>=0&&index<self_.initialized);let handle=self_.modules[index];assert(handle.valid());return module_owners[handle.slot-1].references;}
fn deinit(self_:Snapshot&) {
 if !self_.live {return;}assert(self_.valid());let completion=self_.source_completion;if completion {completion.deinit();}let validation=self_.core_validation;if validation {validation.deinit();}
 for handle in self_.modules[..self_.initialized] {handle.release();}if self_.modules.len!=0 {handles.free_slice(self_.modules);}self_.owner.deinit();let at=self_.slot-1;self_.live=false;snapshots.free(at);
}
// A seed owns one registered snapshot; borrowed graph headers stay invocation-local.
struct Seed {slot:u32=0,generation:u64=0}
fn valid(self_:Seed)->bool {return self_.slot!=0 && self_.slot-1<snapshots.len && snapshots[self_.slot-1].live && snapshots[self_.slot-1].generation==self_.generation;}
fn seed(value:Snapshot&)->Seed {assert(value.valid());let owned:Snapshot& =snapshots[value.slot-1];assert(value .== owned);return Seed{slot:value.slot,generation:value.generation};}
fn snapshot(self_:Seed)->Snapshot? {if self_.slot==0 {assert(self_.generation==0);return null;}assert(self_.valid());return snapshots[self_.slot-1];}
fn value(self_:Seed)->const Frozen& {let owner=self_.snapshot();assert(owner);return owner.value;}
fn deinit(self_:Seed&) {let owner=self_.snapshot();if owner {owner.deinit();}self_=Seed{};}
