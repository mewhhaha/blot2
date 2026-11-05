// Retained project outputs own every checker, cache, remap and diagnostic run.
namespace blot_reuse_project_check;
import .project_check;
struct ResultOwner {slot:u32=0,generation:u64=0}
struct ResultState {relocated:blot_reuse_dependency_payload::Owner[:]=default<blot_reuse_dependency_payload::Owner[:]>(),generation:u64=0,live:bool=false}
reusable var result_states:ResultState[>..]=[];
reusable[] var owned_u8:u8[>..]=[];
fn copyOwned(values:const u8[:])->u8[:] {if values.len==0 {return default<u8[:]>();}let run=owned_u8.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const u8[:]) {if values.len==0 {return;}owned_u8.free_slice(values);}
reusable[] var owned_u32:u32[>..]=[];
fn copyOwned(values:const u32[:])->u32[:] {if values.len==0 {return default<u32[:]>();}let run=owned_u32.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const u32[:]) {if values.len==0 {return;}owned_u32.free_slice(values);}
reusable[] var owned_bool:bool[>..]=[];
fn copyOwned(values:const bool[:])->bool[:] {if values.len==0 {return default<bool[:]>();}let run=owned_bool.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const bool[:]) {if values.len==0 {return;}owned_bool.free_slice(values);}
reusable[] var owned_Export:Export[>..]=[];
fn copyOwned(values:const Export[:])->Export[:] {if values.len==0 {return default<Export[:]>();}let run=owned_Export.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Export[:]) {if values.len==0 {return;}owned_Export.free_slice(values);}
reusable[] var owned_Diagnostic:Diagnostic[>..]=[];
fn copyOwned(values:const Diagnostic[:])->Diagnostic[:] {if values.len==0 {return default<Diagnostic[:]>();}let run=owned_Diagnostic.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Diagnostic[:]) {if values.len==0 {return;}owned_Diagnostic.free_slice(values);}
reusable[] var owned_blot_reuse_body_check_cache__Cache:blot_reuse_body_check_cache::Cache[>..]=[];
fn copyOwned(values:const blot_reuse_body_check_cache::Cache[:])->blot_reuse_body_check_cache::Cache[:] {if values.len==0 {return default<blot_reuse_body_check_cache::Cache[:]>();}let run=owned_blot_reuse_body_check_cache__Cache.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_reuse_body_check_cache::Cache[:]) {if values.len==0 {return;}owned_blot_reuse_body_check_cache__Cache.free_slice(values);}
reusable[] var owned_blot_support__Option_Module_:blot_support::Option<Module>[>..]=[];
fn copyOwned(values:const blot_support::Option<Module>[:])->blot_support::Option<Module>[:] {if values.len==0 {return default<blot_support::Option<Module>[:]>();}let run=owned_blot_support__Option_Module_.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_support::Option<Module>[:]) {if values.len==0 {return;}owned_blot_support__Option_Module_.free_slice(values);}
reusable[] var owned_blot_reuse_entry_frontend_cutoff__Color:blot_reuse_entry_frontend_cutoff::Color[>..]=[];
fn copyOwned(values:const blot_reuse_entry_frontend_cutoff::Color[:])->blot_reuse_entry_frontend_cutoff::Color[:] {if values.len==0 {return default<blot_reuse_entry_frontend_cutoff::Color[:]>();}let run=owned_blot_reuse_entry_frontend_cutoff__Color.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_reuse_entry_frontend_cutoff::Color[:]) {if values.len==0 {return;}owned_blot_reuse_entry_frontend_cutoff__Color.free_slice(values);}
reusable[] var owned_blot_support__Option_BindingMap_:blot_support::Option<BindingMap>[>..]=[];
fn copyOwned(values:const blot_support::Option<BindingMap>[:])->blot_support::Option<BindingMap>[:] {if values.len==0 {return default<blot_support::Option<BindingMap>[:]>();}let run=owned_blot_support__Option_BindingMap_.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_support::Option<BindingMap>[:]) {if values.len==0 {return;}owned_blot_support__Option_BindingMap_.free_slice(values);}
reusable[] var owned_blot_support__Option_FrozenModule_:blot_support::Option<FrozenModule>[>..]=[];
fn copyOwned(values:const blot_support::Option<FrozenModule>[:])->blot_support::Option<FrozenModule>[:] {if values.len==0 {return default<blot_support::Option<FrozenModule>[:]>();}let run=owned_blot_support__Option_FrozenModule_.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_support::Option<FrozenModule>[:]) {if values.len==0 {return;}owned_blot_support__Option_FrozenModule_.free_slice(values);}
reusable[] var owned_blot_reuse_dependency_payload__Owner:blot_reuse_dependency_payload::Owner[>..]=[];
fn copyOwned(values:const blot_reuse_dependency_payload::Owner[:])->blot_reuse_dependency_payload::Owner[:] {if values.len==0 {return default<blot_reuse_dependency_payload::Owner[:]>();}let run=owned_blot_reuse_dependency_payload__Owner.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_reuse_dependency_payload::Owner[:]) {if values.len==0 {return;}owned_blot_reuse_dependency_payload__Owner.free_slice(values);}
fn valid(self_:ResultOwner)->bool {return self_.slot!=0 && self_.slot-1<result_states.len && result_states[self_.slot-1].live && result_states[self_.slot-1].generation==self_.generation;}
fn initResult()->CheckedProject,Error {if result_states.len>=0xffffffff {return CheckedProject{..},blot_error::Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=result_states.alloc_index(ResultState{generation:generation,live:true, ..});return CheckedProject{owner:ResultOwner{(at+1) as u32,generation, ..}, ..},blot_error::Error.none;}
fn allocateModules(self_:CheckedProject&,count:i64,retain_bodies:bool)->Error {assert(self_.owner.valid());self_.modules=owned_blot_support__Option_Module_.alloc_slice(count);for &value in self_.modules {value=blot_support::none<Module>();}if retain_bodies {self_.body_caches=owned_blot_reuse_body_check_cache__Cache.alloc_slice(count);for &cache in self_.body_caches {cache=blot_reuse_body_check_cache::Cache{..};}}return blot_error::Error.none;}
fn allocateReuse(self_:CheckedProject&,count:i64)->Error {
 assert(self_.owner.valid());self_.reused_modules=owned_bool.alloc_slice(count);for &value in self_.reused_modules {value=false;}
 self_.interface_colors=owned_blot_reuse_entry_frontend_cutoff__Color.alloc_slice(count);for &value in self_.interface_colors {value=blot_reuse_entry_frontend_cutoff::Color.unknown;}
 self_.binding_maps=owned_blot_support__Option_BindingMap_.alloc_slice(count);for &value in self_.binding_maps {value=blot_support::none<BindingMap>();}
 self_.relocated_modules=owned_blot_support__Option_FrozenModule_.alloc_slice(count);for &value in self_.relocated_modules {value=blot_support::none<FrozenModule>();}
 let owners=owned_blot_reuse_dependency_payload__Owner.alloc_slice(count);for &value in owners {value=blot_reuse_dependency_payload::Owner{..};}result_states[self_.owner.slot-1].relocated=owners;return blot_error::Error.none;
}
fn deinit(self_:Module&) {self_.checked.deinit();releaseOwned(self_.exports);self_.exports=[];self_.valid=false;}
fn takeBodyCaches(self_:CheckedProject&)->blot_reuse_body_check_cache::Cache[:],Error {assert(self_.owner.valid());let value=self_.body_caches;self_.body_caches=[];return value,blot_error::Error.none;}
fn releaseBodyCaches(values:blot_reuse_body_check_cache::Cache[:]) {for &cache in values {cache.deinit();}releaseOwned(values);}
fn deinit(self_:Diagnostic&) {if self_.purity.present && self_.purity.value.operation_name.present {releaseOwned(self_.purity.value.operation_name.value);}if self_.detail.present {releaseOwned(self_.detail.value);}if self_.hole.present {self_.hole.value.deinit();}if self_.explanation.present {self_.explanation.value.deinit();}self_.purity=blot_support::none<blot_check_check::PurityWitness>();self_.detail=blot_support::none<const u8[:]>();self_.hole=blot_support::none<blot_reuse_hole_diagnostics::Snapshot>();self_.explanation=blot_support::none<blot_reuse_dispatch_explanation::Explanation>();}
fn deinit(self_:CheckedProject&) {
 if self_.owner.slot==0 {return;}assert(self_.owner.valid());
 for &cache in self_.body_caches {cache.deinit();}releaseOwned(self_.body_caches);for &item in self_.modules {if item.present {item.value.deinit();}}releaseOwned(self_.modules);
 releaseOwned(self_.reused_modules);releaseOwned(self_.interface_colors);for &item in self_.binding_maps {if item.present {item.value.deinit();}}releaseOwned(self_.binding_maps);
 let state:ResultState& =result_states[self_.owner.slot-1];for &owner in state.relocated {owner.deinit();}releaseOwned(state.relocated);releaseOwned(self_.relocated_modules);
 for &diagnostic in self_.diagnostics {diagnostic.deinit();}releaseOwned(self_.diagnostics);let at=self_.owner.slot-1;state=ResultState{..};result_states.free(at);self_=CheckedProject{..};
}
