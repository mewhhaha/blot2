// Retained project outputs own every checker, cache, remap and diagnostic run.
namespace blot_reuse_project_check;
import .project_check;
import reuse.dependency_owned_headers;
struct ResultOwner {slot:u32=0,generation:u64=0}
struct ResultState {generation:u64=0,live:bool=false}
reusable var result_states:ResultState[>..]=[];
reusable[] var owned_u8:u8[>..]=[];
fn copyOwned(values:const u8[:])->u8[:] {if values.len==0 {return default<u8[:]>();}let run=owned_u8.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const u8[:]) {if values.len==0 {return;}owned_u8.free_slice(values);}
fn canonicalDiagnosticText(value:const u8[:])->const u8[:] {let text=owned_u8.realloc_slice(value,value.len);assert(blot_support::same_slice_identity(text,value));return text;}
fn canonicalOwnedDiagnostic(value:Diagnostic)->Diagnostic {
 var purity=blot_support::none<blot_check_check::PurityWitness>();if value.purity.present {let old=value.purity.value;var name=blot_support::none<const u8[:]>();if old.operation_name.present {name=blot_support::some<const u8[:]>(canonicalDiagnosticText(old.operation_name.value));}purity=blot_support::Option<blot_check_check::PurityWitness>{true,blot_check_check::PurityWitness{identity:old.identity,family:old.family,member:old.member,compound:old.compound,foreign:old.foreign,specialized:old.specialized,origin_unavailable:old.origin_unavailable,operation_name:name}};}
 var detail=blot_support::none<const u8[:]>();if value.detail.present {detail=blot_support::some<const u8[:]>(canonicalDiagnosticText(value.detail.value));}
 var hole=blot_support::none<blot_reuse_hole_diagnostics::Snapshot>();if value.hole.present {hole=blot_support::Option<blot_reuse_hole_diagnostics::Snapshot>{true,blot_reuse_hole_diagnostics::canonicalOwned(value.hole.value)};}
 var explanation=blot_support::none<blot_reuse_dispatch_explanation::Explanation>();if value.explanation.present {explanation=blot_support::Option<blot_reuse_dispatch_explanation::Explanation>{true,blot_reuse_dispatch_explanation::canonicalOwned(value.explanation.value)};}
 var source=blot_support::none<blot_reuse_project::Diagnostic>();if value.source.present {source=blot_support::Option<blot_reuse_project::Diagnostic>{true,blot_reuse_project::canonicalOwnedDiagnostic(value.source.value)};}
 return Diagnostic{unit:value.unit,span:value.span,code:value.code,semantic:value.semantic,type_application:value.type_application,symbol:value.symbol,implicit_type_witness:value.implicit_type_witness,source_terminator:value.source_terminator,numeric_literal:value.numeric_literal,purity:purity,detail:detail,hole:hole,explanation:explanation,contexts:value.contexts,context_len:value.context_len,source:source};
}
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
fn copyDiagnostics(buffer:DiagnosticBuffer)->Diagnostic[:] {
 if buffer.items.len==0 {return default<Diagnostic[:]>();}let source=owned_Diagnostic.realloc_slice(buffer.storage,buffer.storage.len);assert(blot_support::same_slice_identity(source,buffer.storage));
 let run=owned_Diagnostic.alloc_slice(buffer.items.len);for index in 0..buffer.items.len {run[index]=canonicalOwnedDiagnostic(source[index]);}return run;
}
fn releaseOwned(values:const Diagnostic[:]) {if values.len==0 {return;}owned_Diagnostic.free_slice(values);}
reusable[] var owned_blot_support__Option_Module_:blot_support::Option<Module>[>..]=[];
fn copyOwned(values:const blot_support::Option<Module>[:])->blot_support::Option<Module>[:] {if values.len==0 {return default<blot_support::Option<Module>[:]>();}let run=owned_blot_support__Option_Module_.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn moduleSlots(self_:CheckedProject)->blot_support::Option<Module>[:] {
 assert(self_.owner.valid());let length=self_.modules.len;if length==0 {return default<blot_support::Option<Module>[:]>();}
 let owned=owned_blot_support__Option_Module_.realloc_slice(self_.modules,length);assert(blot_support::same_slice_identity(owned,self_.modules));
 let start=owned_blot_support__Option_Module_.index_of(owned[0]);return owned_blot_support__Option_Module_[start..start+length];
}
fn canonicalModule(value:Module)->Module {let checked=blot_check_check::canonicalOwnedChecked(value.checked);let length=value.exports.len;if length==0 {return Module{checked:checked,exports:default<Export[:]>(),valid:value.valid};}let owned=owned_Export.realloc_slice(value.exports,length);assert(blot_support::same_slice_identity(owned,value.exports));let start=owned_Export.index_of(owned[0]);return Module{checked:checked,exports:owned_Export[start..start+length],valid:value.valid};}
fn publishModule(self_:CheckedProject,unit:u32,value:Module) {let modules=moduleSlots(self_);modules[unit-1]=blot_support::Option<Module>{true,canonicalModule(value)};}
fn releaseOwned(values:const blot_support::Option<Module>[:]) {if values.len==0 {return;}owned_blot_support__Option_Module_.free_slice(values);}
fn valid(self_:ResultOwner)->bool {return self_.slot!=0 && self_.slot-1<result_states.len && result_states[self_.slot-1].live && result_states[self_.slot-1].generation==self_.generation;}
fn initResult()->CheckedProject,Error {if result_states.len>=0xffffffff {return CheckedProject{..},blot_error::Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=result_states.alloc_index(ResultState{generation:generation,live:true, ..});return CheckedProject{owner:ResultOwner{(at+1) as u32,generation, ..}, ..},blot_error::Error.none;}
// Publish the exact owned runs without retaining the temporary Engine header.
fn canonicalOwnedResult(value:CheckedProject)->CheckedProject {
 assert(value.owner.valid());
 let modules=owned_blot_support__Option_Module_.realloc_slice(value.modules,value.modules.len);assert(blot_support::same_slice_identity(modules,value.modules));
 let diagnostics=owned_Diagnostic.realloc_slice(value.diagnostics,value.diagnostics.len);assert(blot_support::same_slice_identity(diagnostics,value.diagnostics));
 return CheckedProject{owner:value.owner,modules:modules,diagnostics:diagnostics,body_elaborations:value.body_elaborations,imported_schemes:value.imported_schemes,normalization:value.normalization};
}
fn allocateModules(self_:CheckedProject&,count:i64)->Error {assert(self_.owner.valid());self_.modules=owned_blot_support__Option_Module_.alloc_slice(count);for &value in self_.modules {value=blot_support::none<Module>();}return blot_error::Error.none;}
fn deinit(self_:Module&) {self_.checked.deinit();releaseOwned(self_.exports);self_.exports=default<blot_reuse_project_check::Export[:]>();self_.valid=false;}
fn deinit(self_:Diagnostic&) {if self_.purity.present && self_.purity.value.operation_name.present {releaseOwned(self_.purity.value.operation_name.value);}if self_.detail.present {releaseOwned(self_.detail.value);}if self_.hole.present {self_.hole.value.deinit();}if self_.explanation.present {self_.explanation.value.deinit();}self_.purity=blot_support::none<blot_check_check::PurityWitness>();self_.detail=blot_support::none<const u8[:]>();self_.hole=blot_support::none<blot_reuse_hole_diagnostics::Snapshot>();self_.explanation=blot_support::none<blot_reuse_dispatch_explanation::Explanation>();}
fn deinit(self_:CheckedProject&) {
 if self_.owner.slot==0 {return;}assert(self_.owner.valid());
 for &item in self_.modules {if item.present {item.value.deinit();}}releaseOwned(self_.modules);
 let state:ResultState& =result_states[self_.owner.slot-1];
 for &diagnostic in self_.diagnostics {diagnostic.deinit();}releaseOwned(self_.diagnostics);let at=self_.owner.slot-1;state=ResultState{..};result_states.free(at);self_=CheckedProject{..};
}
