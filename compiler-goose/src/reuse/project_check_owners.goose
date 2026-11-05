// Retained project outputs own every checker, cache, remap and diagnostic run.
namespace blot_reuse_project_check;
import .project_check;
struct ResultOwner {slot:u32=0,generation:u64=0}
struct ResultState {relocated:blot_reuse_dependency_payload::Owner[:]=[],generation:u64=0,live:bool=false}
reusable var result_states:ResultState[>..]=[];
reusable[] var owned_u8:u8[>..]=[];
fn copyOwned(values:const u8[:])->u8[:] {if values.len==0 {return [];}let run=owned_u8.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const u8[:]) {if values.len==0 {return;}let first:const u8&=values[0];let at=owned_u8.index_of(first);assert(at>=0);owned_u8.free_slice(owned_u8[at..at+values.len]);}
reusable[] var owned_u32:u32[>..]=[];
fn copyOwned(values:const u32[:])->u32[:] {if values.len==0 {return [];}let run=owned_u32.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const u32[:]) {if values.len==0 {return;}let first:const u32&=values[0];let at=owned_u32.index_of(first);assert(at>=0);owned_u32.free_slice(owned_u32[at..at+values.len]);}
reusable[] var owned_bool:bool[>..]=[];
fn copyOwned(values:const bool[:])->bool[:] {if values.len==0 {return [];}let run=owned_bool.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const bool[:]) {if values.len==0 {return;}let first:const bool&=values[0];let at=owned_bool.index_of(first);assert(at>=0);owned_bool.free_slice(owned_bool[at..at+values.len]);}
reusable[] var owned_Export:Export[>..]=[];
fn copyOwned(values:const Export[:])->Export[:] {if values.len==0 {return [];}let run=owned_Export.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Export[:]) {if values.len==0 {return;}let first:const Export&=values[0];let at=owned_Export.index_of(first);assert(at>=0);owned_Export.free_slice(owned_Export[at..at+values.len]);}
reusable[] var owned_Diagnostic:Diagnostic[>..]=[];
fn copyOwned(values:const Diagnostic[:])->Diagnostic[:] {if values.len==0 {return [];}let run=owned_Diagnostic.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Diagnostic[:]) {if values.len==0 {return;}let first:const Diagnostic&=values[0];let at=owned_Diagnostic.index_of(first);assert(at>=0);owned_Diagnostic.free_slice(owned_Diagnostic[at..at+values.len]);}
reusable[] var owned_blot_reuse_body_check_cache__Cache:blot_reuse_body_check_cache::Cache[>..]=[];
fn copyOwned(values:const blot_reuse_body_check_cache::Cache[:])->blot_reuse_body_check_cache::Cache[:] {if values.len==0 {return [];}let run=owned_blot_reuse_body_check_cache__Cache.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_reuse_body_check_cache::Cache[:]) {if values.len==0 {return;}let first:const blot_reuse_body_check_cache::Cache&=values[0];let at=owned_blot_reuse_body_check_cache__Cache.index_of(first);assert(at>=0);owned_blot_reuse_body_check_cache__Cache.free_slice(owned_blot_reuse_body_check_cache__Cache[at..at+values.len]);}
reusable[] var owned_blot_support__Option_Module_:blot_support::Option<Module>[>..]=[];
fn copyOwned(values:const blot_support::Option<Module>[:])->blot_support::Option<Module>[:] {if values.len==0 {return [];}let run=owned_blot_support__Option_Module_.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_support::Option<Module>[:]) {if values.len==0 {return;}let first:const blot_support::Option<Module>&=values[0];let at=owned_blot_support__Option_Module_.index_of(first);assert(at>=0);owned_blot_support__Option_Module_.free_slice(owned_blot_support__Option_Module_[at..at+values.len]);}
reusable[] var owned_blot_reuse_entry_frontend_cutoff__Color:blot_reuse_entry_frontend_cutoff::Color[>..]=[];
fn copyOwned(values:const blot_reuse_entry_frontend_cutoff::Color[:])->blot_reuse_entry_frontend_cutoff::Color[:] {if values.len==0 {return [];}let run=owned_blot_reuse_entry_frontend_cutoff__Color.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_reuse_entry_frontend_cutoff::Color[:]) {if values.len==0 {return;}let first:const blot_reuse_entry_frontend_cutoff::Color&=values[0];let at=owned_blot_reuse_entry_frontend_cutoff__Color.index_of(first);assert(at>=0);owned_blot_reuse_entry_frontend_cutoff__Color.free_slice(owned_blot_reuse_entry_frontend_cutoff__Color[at..at+values.len]);}
reusable[] var owned_blot_support__Option_BindingMap_:blot_support::Option<BindingMap>[>..]=[];
fn copyOwned(values:const blot_support::Option<BindingMap>[:])->blot_support::Option<BindingMap>[:] {if values.len==0 {return [];}let run=owned_blot_support__Option_BindingMap_.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_support::Option<BindingMap>[:]) {if values.len==0 {return;}let first:const blot_support::Option<BindingMap>&=values[0];let at=owned_blot_support__Option_BindingMap_.index_of(first);assert(at>=0);owned_blot_support__Option_BindingMap_.free_slice(owned_blot_support__Option_BindingMap_[at..at+values.len]);}
reusable[] var owned_blot_support__Option_FrozenModule_:blot_support::Option<FrozenModule>[>..]=[];
fn copyOwned(values:const blot_support::Option<FrozenModule>[:])->blot_support::Option<FrozenModule>[:] {if values.len==0 {return [];}let run=owned_blot_support__Option_FrozenModule_.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_support::Option<FrozenModule>[:]) {if values.len==0 {return;}let first:const blot_support::Option<FrozenModule>&=values[0];let at=owned_blot_support__Option_FrozenModule_.index_of(first);assert(at>=0);owned_blot_support__Option_FrozenModule_.free_slice(owned_blot_support__Option_FrozenModule_[at..at+values.len]);}
reusable[] var owned_blot_reuse_dependency_payload__Owner:blot_reuse_dependency_payload::Owner[>..]=[];
fn copyOwned(values:const blot_reuse_dependency_payload::Owner[:])->blot_reuse_dependency_payload::Owner[:] {if values.len==0 {return [];}let run=owned_blot_reuse_dependency_payload__Owner.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_reuse_dependency_payload::Owner[:]) {if values.len==0 {return;}let first:const blot_reuse_dependency_payload::Owner&=values[0];let at=owned_blot_reuse_dependency_payload__Owner.index_of(first);assert(at>=0);owned_blot_reuse_dependency_payload__Owner.free_slice(owned_blot_reuse_dependency_payload__Owner[at..at+values.len]);}
fn valid(self:ResultOwner)->bool {return self.slot!=0 && self.slot-1<result_states.len && result_states[self.slot-1].live && result_states[self.slot-1].generation==self.generation;}
fn initResult()->CheckedProject,Error {if result_states.len>=0xffffffff {return CheckedProject{..},Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=result_states.alloc_index(ResultState{generation:generation,live:true, ..});return CheckedProject{owner:ResultOwner{(at+1) as u32,generation, ..}, ..},Error.none;}
fn allocateModules(self:CheckedProject&,count:i64,retain_bodies:bool)->Error {assert(self.owner.valid());self.modules=owned_blot_support__Option_Module_.alloc_slice(count);for &value in self.modules {value=blot_support::none<Module>();}if retain_bodies {self.body_caches=owned_blot_reuse_body_check_cache__Cache.alloc_slice(count);for &cache in self.body_caches {cache=blot_reuse_body_check_cache::Cache{..};}}return Error.none;}
fn allocateReuse(self:CheckedProject&,count:i64)->Error {
 assert(self.owner.valid());self.reused_modules=owned_bool.alloc_slice(count);for &value in self.reused_modules {value=false;}
 self.interface_colors=owned_blot_reuse_entry_frontend_cutoff__Color.alloc_slice(count);for &value in self.interface_colors {value=blot_reuse_entry_frontend_cutoff::Color.unknown;}
 self.binding_maps=owned_blot_support__Option_BindingMap_.alloc_slice(count);for &value in self.binding_maps {value=blot_support::none<BindingMap>();}
 self.relocated_modules=owned_blot_support__Option_FrozenModule_.alloc_slice(count);for &value in self.relocated_modules {value=blot_support::none<FrozenModule>();}
 let owners=owned_blot_reuse_dependency_payload__Owner.alloc_slice(count);for &value in owners {value=blot_reuse_dependency_payload::Owner{..};}result_states[self.owner.slot-1].relocated=owners;return Error.none;
}
fn deinit(self:Module&) {self.checked.deinit();releaseOwned(self.exports);self.exports=[];self.valid=false;}
fn takeBodyCaches(self:CheckedProject&)->blot_reuse_body_check_cache::Cache[:],Error {assert(self.owner.valid());let value=self.body_caches;self.body_caches=[];return value,Error.none;}
fn releaseBodyCaches(values:blot_reuse_body_check_cache::Cache[:]) {for &cache in values {cache.deinit();}releaseOwned(values);}
fn deinit(self:Diagnostic&) {if self.purity.present && self.purity.value.operation_name.present {releaseOwned(self.purity.value.operation_name.value);}if self.detail.present {releaseOwned(self.detail.value);}if self.hole.present {self.hole.value.deinit();}if self.explanation.present {self.explanation.value.deinit();}self.purity=blot_support::none<blot_check_check::PurityWitness>();self.detail=blot_support::none<const u8[:]>();self.hole=blot_support::none<blot_reuse_hole_diagnostics::Snapshot>();self.explanation=blot_support::none<blot_reuse_dispatch_explanation::Explanation>();}
fn deinit(self:CheckedProject&) {
 if self.owner.slot==0 {return;}assert(self.owner.valid());
 for &cache in self.body_caches {cache.deinit();}releaseOwned(self.body_caches);for &item in self.modules {if item.present {item.value.deinit();}}releaseOwned(self.modules);
 releaseOwned(self.reused_modules);releaseOwned(self.interface_colors);for &item in self.binding_maps {if item.present {item.value.deinit();}}releaseOwned(self.binding_maps);
 let state:ResultState&=result_states[self.owner.slot-1];for &owner in state.relocated {owner.deinit();}releaseOwned(state.relocated);releaseOwned(self.relocated_modules);
 for &diagnostic in self.diagnostics {diagnostic.deinit();}releaseOwned(self.diagnostics);let at=self.owner.slot-1;state=ResultState{..};result_states.free(at);self=CheckedProject{..};
}
