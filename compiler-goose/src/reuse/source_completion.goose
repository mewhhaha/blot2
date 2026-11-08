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
 graph:Frozen=default<Frozen>(),validation:blot_reuse_completed_core_validation::Receipt=blot_reuse_completed_core_validation::Receipt{..},
 generation:u64=0,live:bool=false,canonical:Prefix=Prefix{..},
}
reusable var prefixes:PrefixState[>..]=[];
fn valid(self_:const Prefix&)->bool {return self_.slot!=0 && self_.slot-1<prefixes.len && prefixes[self_.slot-1].live && prefixes[self_.slot-1].generation==self_.generation;}
fn deinit(self_:Prefix&) {if self_.slot==0 {return;}assert(valid(self_));let at=self_.slot-1;prefixes[at]=PrefixState{..};prefixes.free(at);}
fn owns(self_:const Prefix&,graph:const Frozen&)->bool {if !valid(self_) {return false;}let saved=prefixes[self_.slot-1].graph;return blot_support::same_slice_identity(saved.modules,graph.modules) && blot_support::same_slice_identity(saved.symbols,graph.symbols);}
fn prefix(self_:const Prefix&,units:const Core[:],entry:u32,names:Identity)->i64 {
 if !valid(self_) {return 0;}let state:const PrefixState& =prefixes[self_.slot-1];let count=state.graph.modules.len;
 if count==0 || state.validation.borrow(state.graph).prefix(units,entry,names)!=count {return 0;}
 for module,index in state.graph.modules {let path=names.owner((index+1) as u32);if !path.present || path.value!=module.identity.normalized_path {return 0;}}return count;
}
struct Entry {slot:u32=0,generation:u64=0}
struct EntryState {
 prefix:Prefix=Prefix{..},module:Core=default<Core>(),names:blot_backend_runtime_identity::Metadata=blot_backend_runtime_identity::Metadata{..},
 generation:u64=0,live:bool=false,canonical:Entry=Entry{..},
}
reusable var entries:EntryState[>..]=[];
fn valid(self_:const Entry&)->bool {return self_.slot!=0 && self_.slot-1<entries.len && entries[self_.slot-1].live && entries[self_.slot-1].generation==self_.generation;}
fn deinit(self_:Entry&) {if self_.slot==0 {return;}assert(valid(self_));let at=self_.slot-1;entries[at].names.deinit();entries[at]=EntryState{..};entries.free(at);}
fn matches(self_:const Entry&,units:const Core[:],entry:u32,names:Identity)->bool {
 if !valid(self_) {return false;}let state:const EntryState& =entries[self_.slot-1];if units.len==0 || entry!=units.len || state.prefix.prefix(units,entry,names)!=units.len-1 {return false;}
 if blot_check_core::stampView(state.module)!=blot_check_core::stampView(units[entry-1]) {return false;}
 let saved=state.names.view();if saved.bytes!=names.bytes || saved.symbols.len!=names.symbols.len || saved.owners.len!=names.owners.len {return false;}
 for left,index in saved.symbols {if left!=names.symbols[index] {return false;}}for left,index in saved.owners {if left!=names.owners[index] {return false;}}return true;
}
struct Borrow {prefix:const Prefix?=null,entry:const Entry?=null}
fn covered(self_:Borrow,units:const Core[:],entry:u32,names:Identity)->i64 {
 let current .= self_.entry;if current && current.matches(units,entry,names) {return units.len;}
 let prefix .= self_.prefix;if prefix {return prefix.prefix(units,entry,names);}return 0;
}
struct Population {checked:blot_reuse_project_check::CheckedProject,snapshot:blot_reuse_retained_dependency::Snapshot?=null}
fn checkAndFreezeDependencies<E>(executor:E&,source:blot_reuse_project::Project&,previous:blot_support::Option<blot_reuse_entry_frontend_cutoff::Previous>)->Population,Error {
 let value,error=blot_reuse_project_check::checkProjectDeferringEntryToFirstDiagnostic(executor,source,previous);if error!=blot_error::Error.none {return default<Population>(),error;}var checked=value;
 if !checked.deferred_entry.present || checked.diagnostics.len!=0 {return Population{checked:checked, ..},blot_error::Error.none;}
 let result,error=blot_reuse_dependency_closure::freezeDeferringEntrySnapshot(executor,source,checked);
 if error!=blot_error::Error.none {if error==blot_error::Error.out_of_memory {checked.deinit();return default<Population>(),error;}return Population{checked:checked, ..},blot_error::Error.none;}
 let owner .= result;assert(owner!=null);
 if !previous.present && source.compiled_modules.len==0 {
 if prefixes.len>=0xffffffff {owner.deinit();checked.deinit();return default<Population>(),blot_error::Error.out_of_memory;}
 let validation .= owner.core_validation;assert(validation!=null);let generation=blot_native::fresh_owner_id();let at=prefixes.alloc_index(PrefixState{graph:owner.value,validation:validation,generation:generation,live:true, ..});prefixes[at].canonical=Prefix{(at+1) as u32,generation, ..};owner.source_completion .= prefixes[at].canonical;
 }
 return Population{checked,owner, ..},blot_error::Error.none;
}
fn prepareEntry<E,P>(executor:E&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,options:blot_reuse_project::Options,owner:const blot_reuse_retained_dependency::Snapshot&,inputs:P&,previous:blot_support::Option<blot_reuse_partial_dependency::EntryPrevious>)->blot_reuse_partial_dependency::Preparation,Error {
 let value,error=blot_reuse_partial_dependency::prepareReadOnlyWithBodies(executor,entry_path,output_identity,options,owner.value,inputs,previous);if error!=blot_error::Error.none {return default<blot_reuse_partial_dependency::Preparation>(),error;}var prepared=value;
 match prepared {ready &payload=>{
 let value,error=owner.pinInputs();if error!=blot_error::Error.none {prepared.deinit();return default<blot_reuse_partial_dependency::Preparation>(),error;}var pin=value;
 let error=payload.value.attachSeedPin(pin);if error!=blot_error::Error.none {pin.deinit();prepared.deinit();return default<blot_reuse_partial_dependency::Preparation>(),error;}
 let error=payload.value.rebindFrozenPrefix(owner.value);if error!=blot_error::Error.none {prepared.deinit();return default<blot_reuse_partial_dependency::Preparation>(),error;}
 if !previous.present {let error=mintEntry(payload.value,owner);if error!=blot_error::Error.none {prepared.deinit();return default<blot_reuse_partial_dependency::Preparation>(),error;}}
 },_=>{}}
 return prepared,blot_error::Error.none;
}
fn mintEntry(value:blot_reuse_partial_dependency::Prepared&,owner:const blot_reuse_retained_dependency::Snapshot&)->Error {
 let prefix .= owner.source_completion;if !prefix || !prefix.owns(owner.value) {return blot_error::Error.none;}
 if value.source_mode || value.units.len!=owner.value.modules.len+1 || value.entry!=value.units.len || value.cached!=owner.value.modules.len {return blot_error::Error.none;}
 if prefix.prefix(value.units,value.entry,value.identity.view())!=owner.value.modules.len {return blot_error::Error.none;}
 if entries.len>=0xffffffff {return blot_error::Error.out_of_memory;}let names,error=blot_backend_runtime_identity::copy(value.identity.view());if error!=blot_error::Error.none {return error;}
 let generation=blot_native::fresh_owner_id();let at=entries.alloc_index(EntryState{prefix:prefix,module:value.units[value.entry-1],names:names,generation:generation,live:true, ..});entries[at].canonical=Entry{(at+1) as u32,generation, ..};value.source_completion .= entries[at].canonical;return blot_error::Error.none;
}
