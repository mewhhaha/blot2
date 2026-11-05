// Source authority is minted only after these factories check and lower source.
// Prefix snapshots and Prepared owners stay pinned throughout their borrowers.
namespace blot_reuse_source_completion;
import check.core;
import reuse.project;
import reuse.project_check;
import reuse.partial_dependency;
import reuse.dependency_closure;
import reuse.retained_dependency;
import reuse.frozen_dependency;
import reuse.completed_core_validation;
import reuse.entry_frontend_cutoff;
import backend.runtime_identity;
import support.error;
import support.option;
import support.native;
type Error=blot_error::Error;
type Core=blot_check_core::Module;
type Frozen=blot_reuse_frozen_dependency::FrozenDependency;
type Identity=blot_backend_runtime_identity::View;
struct Prefix {slot:u32=0,generation:u64=0}
struct PrefixState {
 graph:Frozen=Frozen{symbols:[],modules:[], ..},validation:blot_reuse_completed_core_validation::Receipt=blot_reuse_completed_core_validation::Receipt{..},
 generation:u64=0,live:bool=false,canonical:Prefix=Prefix{..},
}
reusable var prefixes:PrefixState[>..]=[];
fn valid(self:const Prefix&)->bool {return self.slot!=0 && self.slot-1<prefixes.len && prefixes[self.slot-1].live && prefixes[self.slot-1].generation==self.generation;}
fn deinit(self:Prefix&) {if self.slot==0 {return;}assert(valid(self));let at=self.slot-1;prefixes[at]=PrefixState{..};prefixes.free(at);}
fn owns(self:const Prefix&,graph:const Frozen&)->bool {if !valid(self) {return false;}let saved=prefixes[self.slot-1].graph;return saved.modules .== graph.modules && saved.symbols .== graph.symbols;}
fn prefix(self:const Prefix&,units:const Core[:],entry:u32,names:Identity)->i64 {
 if !valid(self) {return 0;}let state:const PrefixState&=prefixes[self.slot-1];let count=state.graph.modules.len;
 if count==0 || state.validation.borrow(state.graph).prefix(units,entry,names)!=count {return 0;}
 for module,index in state.graph.modules {let path=names.owner((index+1) as u32);if !path.present || path.value!=module.identity.normalized_path {return 0;}}return count;
}
struct Entry {slot:u32=0,generation:u64=0}
struct EntryState {
 prefix:Prefix=Prefix{..},module:Core=default<Core>(),names:blot_backend_runtime_identity::Metadata=blot_backend_runtime_identity::Metadata{..},
 generation:u64=0,live:bool=false,canonical:Entry=Entry{..},
}
reusable var entries:EntryState[>..]=[];
fn valid(self:const Entry&)->bool {return self.slot!=0 && self.slot-1<entries.len && entries[self.slot-1].live && entries[self.slot-1].generation==self.generation;}
fn deinit(self:Entry&) {if self.slot==0 {return;}assert(valid(self));let at=self.slot-1;entries[at].names.deinit();entries[at]=EntryState{..};entries.free(at);}
fn matches(self:const Entry&,units:const Core[:],entry:u32,names:Identity)->bool {
 if !valid(self) {return false;}let state:const EntryState&=entries[self.slot-1];if units.len==0 || entry!=units.len || state.prefix.prefix(units,entry,names)!=units.len-1 {return false;}
 if blot_check_core::stampView(state.module)!=blot_check_core::stampView(units[entry-1]) {return false;}
 let saved=state.names.view();if saved.bytes!=names.bytes || saved.symbols.len!=names.symbols.len || saved.owners.len!=names.owners.len {return false;}
 for left,index in saved.symbols {if left!=names.symbols[index] {return false;}}for left,index in saved.owners {if left!=names.owners[index] {return false;}}return true;
}
struct Borrow {prefix:const Prefix?=null,entry:const Entry?=null}
fn covered(self:Borrow,units:const Core[:],entry:u32,names:Identity)->i64 {
 let current .= self.entry;if current && current.matches(units,entry,names) {return units.len;}
 let prefix .= self.prefix;if prefix {return prefix.prefix(units,entry,names);}return 0;
}
struct Population {checked:blot_reuse_project_check::CheckedProject,snapshot:blot_reuse_retained_dependency::Snapshot?=null}
fn checkAndFreezeDependencies<E>(executor:E&,source:blot_reuse_project::Project&,previous:blot_support::Option<blot_reuse_entry_frontend_cutoff::Previous>)->Population,Error {
 let value,error=blot_reuse_project_check::checkProjectDeferringEntryToFirstDiagnostic(executor,source,previous);if error!=Error.none {return default<Population>(),error;}var checked=value;
 if !checked.deferred_entry.present || checked.diagnostics.len!=0 {return Population{checked:checked, ..},Error.none;}
 let result,error=blot_reuse_dependency_closure::freezeDeferringEntrySnapshot(executor,source,checked);
 if error!=Error.none {if error==Error.out_of_memory {checked.deinit();return default<Population>(),error;}return Population{checked:checked, ..},Error.none;}
 let owner .= result;assert(owner!=null);
 if !previous.present && source.compiled_modules.len==0 {
 if prefixes.len>=0xffffffff {owner.deinit();checked.deinit();return default<Population>(),Error.out_of_memory;}
 let validation .= owner.core_validation;assert(validation!=null);let generation=blot_native::fresh_owner_id();let at=prefixes.alloc_index(PrefixState{graph:owner.value,validation:validation,generation:generation,live:true, ..});prefixes[at].canonical=Prefix{(at+1) as u32,generation, ..};owner.source_completion .= prefixes[at].canonical;
 }
 return Population{checked,owner, ..},Error.none;
}
fn prepareEntry<E,P>(executor:E&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,options:blot_reuse_project::Options,owner:const blot_reuse_retained_dependency::Snapshot&,inputs:P&,previous:blot_support::Option<blot_reuse_partial_dependency::EntryPrevious>)->blot_reuse_partial_dependency::Preparation,Error {
 let value,error=blot_reuse_partial_dependency::prepareReadOnlyWithBodies(executor,entry_path,output_identity,options,owner.value,inputs,previous);if error!=Error.none {return default<blot_reuse_partial_dependency::Preparation>(),error;}var prepared=value;
 match prepared {blot_reuse_partial_dependency::Preparation.ready &payload=>{
 let value,error=owner.pinInputs();if error!=Error.none {prepared.deinit();return default<blot_reuse_partial_dependency::Preparation>(),error;}var pin=value;
 let error=payload.value.attachSeedPin(pin);if error!=Error.none {pin.deinit();prepared.deinit();return default<blot_reuse_partial_dependency::Preparation>(),error;}
 let error=payload.value.rebindFrozenPrefix(owner.value);if error!=Error.none {prepared.deinit();return default<blot_reuse_partial_dependency::Preparation>(),error;}
 if !previous.present {let error=mintEntry(payload.value,owner);if error!=Error.none {prepared.deinit();return default<blot_reuse_partial_dependency::Preparation>(),error;}}
 },_=>{}}
 return prepared,Error.none;
}
fn mintEntry(value:blot_reuse_partial_dependency::Prepared&,owner:const blot_reuse_retained_dependency::Snapshot&)->Error {
 let prefix .= owner.source_completion;if !prefix || !prefix.owns(owner.value) {return Error.none;}
 if value.source_mode || value.units.len!=owner.value.modules.len+1 || value.entry!=value.units.len || value.cached!=owner.value.modules.len {return Error.none;}
 if prefix.prefix(value.units,value.entry,value.identity.view())!=owner.value.modules.len {return Error.none;}
 if entries.len>=0xffffffff {return Error.out_of_memory;}let names,error=blot_backend_runtime_identity::copy(value.identity.view());if error!=Error.none {return error;}
 let generation=blot_native::fresh_owner_id();let at=entries.alloc_index(EntryState{prefix:prefix,module:value.units[value.entry-1],names:names,generation:generation,live:true, ..});entries[at].canonical=Entry{(at+1) as u32,generation, ..};value.source_completion .= entries[at].canonical;return Error.none;
}
