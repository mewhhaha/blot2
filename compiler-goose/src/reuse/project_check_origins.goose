// Canonical display names belong to the loaded Project and survive its checks.
namespace blot_reuse_project_check;
import .project_check;
struct OriginState {source_id:u64=0,entries:blot_check_check::ModuleOrigin[:]=[],failure:Error=Error.none,live:bool=false}
reusable var origin_states:OriginState[>..]=[];
reusable[] var origin_entries:blot_check_check::ModuleOrigin[>..]=[];
fn moduleOrigins(source:const Project&)->blot_check_check::ModuleOrigins {
 if source.lease==0 || source.lease-1>=blot_reuse_project::projects.len {return blot_check_check::ModuleOrigins{has_lookup:true,failure:Error.type_limit, ..};}
 let project:blot_reuse_project::ProjectState&=blot_reuse_project::projects[source.lease-1];if project.owner!=source.owner_id {return blot_check_check::ModuleOrigins{has_lookup:true,failure:Error.type_limit, ..};}
 if project.origin_lease==0 {
 let entries=origin_entries.alloc_slice(source.units.len);for &entry in entries {entry=blot_check_check::ModuleOrigin{0,[],false, ..};}
 let at=origin_states.alloc_index(OriginState{source_id:source.owner_id,entries:entries,live:true, ..});project.origin_lease=(at+1) as u32;
 origin_states[at].failure=populateOrigins(source,entries);
 }
 let state:const OriginState&=origin_states[project.origin_lease-1];assert(state.live && state.source_id==source.owner_id);return blot_check_check::ModuleOrigins{entries:state.entries,has_source_available:true,has_lookup:true,failure:state.failure, ..};
}
fn populateOrigins(source:const Project&,entries:blot_check_check::ModuleOrigin[:])->Error {
 for index in entries.len {let unit=(index+1) as u32;var name:const u8[:]=[];
 if unit==source.prelude_unit {name="std/prelude";}else if source.input_mode==blot_reuse_project::InputMode.source && unit==source.entry {name="main";}
 else {
 if source.entry==0 || source.entry>source.units.len {return Error.type_limit;}let directory=blot_support_path::dirname(source.filename(source.entry));if !directory.present {return Error.type_limit;}
 var relative:u8[>..<]=[];let error=blot_support_path::relative(directory.value,source.filename(unit),relative);if error!=Error.none {return error;}entries[index]=blot_check_check::ModuleOrigin{unit,copyOwned(relative[:]),source.compiledModule(unit)==null, ..};continue;
 }
 entries[index]=blot_check_check::ModuleOrigin{unit,copyOwned(name),source.compiledModule(unit)==null, ..};
 }return Error.none;
}
fn releaseModuleOrigins(slot:u32) {if slot==0 {return;}let at=slot-1;assert(at<origin_states.len && origin_states[at].live);let state:OriginState&=origin_states[at];for entry in state.entries {releaseOwned(entry.name);}if state.entries.len!=0 {origin_entries.free_slice(state.entries);}state=OriginState{..};origin_states.free(at);}
fn diagnosticModuleOrigin(source:const Project&,unit:u32)->const u8[:],Error {return moduleOrigins(source).name(unit,source.entry);}
