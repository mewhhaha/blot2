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
fn valid(self:ModuleHandle)->bool {return self.slot!=0&&self.slot-1<module_owners.len&&module_owners[self.slot-1].live&&module_owners[self.slot-1].generation==self.generation;}
fn allocateModule()->ModuleHandle,Error {if module_owners.len>=0xffffffff {return ModuleHandle {..},Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=module_owners.alloc_index(Module {live:true,generation:generation, ..});return ModuleHandle {(at+1) as u32,generation, ..},Error.none;}
fn release(self:ModuleHandle) {assert(self.valid());let at=self.slot-1;let module:Module&=module_owners[at];assert(module.references!=0);module.references--;if module.references!=0 {return;}module.owner.deinit();module.live=false;module_owners.free(at);}
struct Snapshot {
 slot:u32=0,generation:u64=0,live:bool=false,value:Frozen=Frozen {symbols:[],modules:[], ..},modules:ModuleHandle[:]=[],initialized:i64=0,validated:bool=false,
 core_validation:blot_reuse_completed_core_validation::Receipt?=null,source_completion:blot_reuse_source_completion::Prefix?=null,owner:Owner=Owner {..},
}
reusable var snapshots:Snapshot[>..]=[];
reusable[] var handles:ModuleHandle[>..]=[];
struct InputPin {owners:Owner[:]=[]}
reusable[] var input_owner_runs:Owner[>..]=[];
fn pinInputs(self:const Snapshot&)->InputPin,Error {
 if !self.valid() || self.initialized!=self.modules.len {return InputPin{..},Error.invalid_artifact;}
 let owners=input_owner_runs.alloc_slice(self.modules.len+1);for &owner in owners {owner=Owner{..};}
 let root,error=self.owner.retain();if error!=Error.none {input_owner_runs.free_slice(owners);return InputPin{..},error;}owners[0]=root;
 for handle,index in self.modules {assert(handle.valid());let owner,error=module_owners[handle.slot-1].owner.retain();if error!=Error.none {for &prior in owners[..index+1] {prior.release();}input_owner_runs.free_slice(owners);return InputPin{..},error;}owners[index+1]=owner;}
 return InputPin{owners, ..},Error.none;
}
fn deinit(self:InputPin&) {for &owner in self.owners {owner.release();}if self.owners.len!=0 {input_owner_runs.free_slice(self.owners);}self=InputPin{..};}
fn valid(self:const Snapshot&)->bool {return self.live&&self.slot!=0&&self.slot-1<snapshots.len&&snapshots[self.slot-1].live&&snapshots[self.slot-1].generation==self.generation;}
fn allocateSnapshot(count:i64)->Snapshot?,Error {
 if count<0||count>0xffffffff||snapshots.len>=0xffffffff {return null,Error.out_of_memory;}
 let slots=handles.alloc_slice(count);for &slot in slots {slot=ModuleHandle {..};}
 let generation=blot_native::fresh_owner_id();let at=snapshots.alloc_index(Snapshot {generation:generation,live:true,modules:slots, ..});snapshots[at].slot=(at+1) as u32;return snapshots[at],Error.none;
}
fn discardBookkeeping(self:Snapshot&) {assert(self.valid()&&self.initialized==0&&self.owner.lease==0);if self.modules.len!=0 {handles.free_slice(self.modules);}let at=self.slot-1;self.live=false;snapshots.free(at);}
fn create(symbols:blot_reuse_frozen_dependency::Symbol[:],count:i64,owner:Owner&)->Snapshot?,Error {
 let self,error=allocateSnapshot(count);if error!=Error.none {return null,error;}assert(self!=null);let views,failure=owner.alloc<FrozenModule>(count);if failure!=Error.none {self.discardBookkeeping();return null,failure;}
 self.owner=copy(owner);owner=Owner {..};self.value=Frozen {symbols,views, ..};return self,Error.none;
}
fn adopt(value:OwnedFrozen&)->Snapshot?,Error {
 let self,error=allocateSnapshot(value.value.modules.len);if error!=Error.none {return null,error;}assert(self!=null);var allocated:i64=0;var failure=Error.none;
 // Complete every metadata allocation before consuming any caller-owned run.
 for index in self.modules.len {
  let handle,created=allocateModule();if created!=Error.none {failure=created;break;}
  self.modules[index]=handle;allocated++;let owner,opened=blot_reuse_dependency_payload::init();if opened!=Error.none {failure=opened;break;}module_owners[handle.slot-1].owner=owner;
 }
 if failure!=Error.none {for handle in self.modules[..allocated] {handle.release();}self.discardBookkeeping();return null,failure;}
 for module,index in value.value.modules {
  let destination:Module&=module_owners[self.modules[index].slot-1];value.owner.partitionInto(destination.owner,module);destination.value=module;
 }
 self.value=value.value;self.owner=value.owner;self.initialized=self.modules.len;value=default<OwnedFrozen>();return self,Error.none;
}
fn append(self:Snapshot&,handle:ModuleHandle) {assert(self.valid()&&!self.validated&&self.initialized<self.modules.len&&handle.valid());self.modules[self.initialized]=handle;self.value.modules[self.initialized]=module_owners[handle.slot-1].value;self.initialized++;}
fn appendOwned(self:Snapshot&,value:OwnedModule&)->Error {
 let handle,error=allocateModule();if error!=Error.none {value.deinit();return error;}
 let module:Module&=module_owners[handle.slot-1];module.value=value.value;module.owner=value.owner;value=default<OwnedModule>();self.append(handle);return Error.none;
}
fn appendShared(self:Snapshot&,previous:const Snapshot&,index:i64)->Error {
 assert(previous.valid()&&index>=0&&index<previous.initialized);let handle=previous.modules[index];assert(handle.valid());let module:Module&=module_owners[handle.slot-1];if module.references==0xffffffffffffffff {return Error.dependency_limit;}module.references++;self.append(handle);return Error.none;
}
fn shares(self:const Snapshot&,previous:const Snapshot&,index:i64)->bool {return index>=0&&index<self.initialized&&index<previous.initialized&&self.modules[index]==previous.modules[index];}
fn references(self:const Snapshot&,index:i64)->u64 {assert(self.valid()&&index>=0&&index<self.initialized);let handle=self.modules[index];assert(handle.valid());return module_owners[handle.slot-1].references;}
fn deinit(self:Snapshot&) {
 if !self.live {return;}assert(self.valid());let completion=self.source_completion;if completion {completion.deinit();}let validation=self.core_validation;if validation {validation.deinit();}
 for handle in self.modules[..self.initialized] {handle.release();}if self.modules.len!=0 {handles.free_slice(self.modules);}self.owner.deinit();let at=self.slot-1;self.live=false;snapshots.free(at);
}
struct Seed {value:Frozen=Frozen {symbols:[],modules:[], ..},snapshot:Snapshot?=null,owner:Owner=Owner {..}}
fn deinit(self:Seed&) {let snapshot=self.snapshot;if snapshot {snapshot.deinit();}else {self.owner.deinit();}self=Seed {..};}
