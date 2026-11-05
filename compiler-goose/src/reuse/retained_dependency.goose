// Immutable modules are retained independently of the preceding revision.
namespace blot_reuse_retained_dependency;
import reuse.frozen_dependency;
import reuse.dependency_payload;
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
 slot:u32=0,generation:u64=0,live:bool=false,value:Frozen=Frozen {symbols:[],modules:[], ..},modules:ModuleHandle[:]=default<ModuleHandle[:]>(),initialized:i64=0,validated:bool=false,
 core_validation:blot_reuse_completed_core_validation::Receipt?=null,source_completion:blot_reuse_source_completion::Prefix?=null,owner:Owner=Owner {..},
}
reusable var snapshots:Snapshot[>..]=[];
reusable[] var handles:ModuleHandle[>..]=[];
struct InputPin {owners:Owner[:]=default<Owner[:]>()}
reusable[] var input_owner_runs:Owner[>..]=[];
fn pinInputs(self_:const Snapshot&)->InputPin,Error {
 if !self_.valid() || self_.initialized!=self_.modules.len {return InputPin{..},blot_error::Error.invalid_artifact;}
 let owners=input_owner_runs.alloc_slice(self_.modules.len+1);for &owner in owners {owner=Owner{..};}
 let root,error=self_.owner.retain();if error!=blot_error::Error.none {input_owner_runs.free_slice(owners);return InputPin{..},error;}owners[0]=root;
 for handle,index in self_.modules {assert(handle.valid());let owner,error=module_owners[handle.slot-1].owner.retain();if error!=blot_error::Error.none {for &prior in owners[..index+1] {prior.release();}input_owner_runs.free_slice(owners);return InputPin{..},error;}owners[index+1]=owner;}
 return InputPin{owners, ..},blot_error::Error.none;
}
fn deinit(self_:InputPin&) {for &owner in self_.owners {owner.release();}if self_.owners.len!=0 {input_owner_runs.free_slice(self_.owners);}self_=InputPin{..};}
fn valid(self_:const Snapshot&)->bool {return self_.live&&self_.slot!=0&&self_.slot-1<snapshots.len&&snapshots[self_.slot-1].live&&snapshots[self_.slot-1].generation==self_.generation;}
fn allocateSnapshot(count:i64)->Snapshot?,Error {
 if count<0||count>0xffffffff||snapshots.len>=0xffffffff {return null,blot_error::Error.out_of_memory;}
 let slots=handles.alloc_slice(count);for &slot in slots {slot=ModuleHandle {..};}
 let generation=blot_native::fresh_owner_id();let at=snapshots.alloc_index(Snapshot {generation:generation,live:true,modules:slots, ..});snapshots[at].slot=(at+1) as u32;return snapshots[at],blot_error::Error.none;
}
fn discardBookkeeping(self_:Snapshot&) {assert(self_.valid()&&self_.initialized==0&&self_.owner.lease==0);if self_.modules.len!=0 {handles.free_slice(self_.modules);}let at=self_.slot-1;self_.live=false;snapshots.free(at);}
fn create(symbols:blot_reuse_frozen_dependency::Symbol[:],count:i64,owner:Owner&)->Snapshot?,Error {
 let self_,error=allocateSnapshot(count);if error!=blot_error::Error.none {return null,error;}assert(self_!=null);let views,failure=owner.alloc<FrozenModule>(count);if failure!=blot_error::Error.none {self_.discardBookkeeping();return null,failure;}
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
 for module,index in value.value.modules {
  let destination:Module& =module_owners[self_.modules[index].slot-1];value.owner.partitionInto(destination.owner,module);destination.value=module;
 }
 self_.value=value.value;self_.owner=value.owner;self_.initialized=self_.modules.len;value=default<OwnedFrozen>();return self_,blot_error::Error.none;
}
fn append(self_:Snapshot&,handle:ModuleHandle) {assert(self_.valid()&&!self_.validated&&self_.initialized<self_.modules.len&&handle.valid());self_.modules[self_.initialized]=handle;self_.value.modules[self_.initialized]=module_owners[handle.slot-1].value;self_.initialized++;}
fn appendOwned(self_:Snapshot&,value:OwnedModule&)->Error {
 let handle,error=allocateModule();if error!=blot_error::Error.none {value.deinit();return error;}
 let module:Module& =module_owners[handle.slot-1];module.value=value.value;module.owner=value.owner;value=default<OwnedModule>();self_.append(handle);return blot_error::Error.none;
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
struct Seed {value:Frozen=Frozen {symbols:[],modules:[], ..},snapshot:Snapshot?=null,owner:Owner=Owner {..}}
fn deinit(self_:Seed&) {let snapshot=self_.snapshot;if snapshot {snapshot.deinit();}else {self_.owner.deinit();}self_=Seed {..};}
