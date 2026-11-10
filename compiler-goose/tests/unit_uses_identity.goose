// Unit use requests retain one canonical header while lazily adding indexes.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import dictionary;
import driver.compile_workspace;
import backend.core_backend;
import backend.unit_index;
import reuse.dependency_payload;
import support.native;
import support.error;
fn inspect(frame:blot_compile_workspace::Frame,units:const blot_check_core::Module[:],pin:blot_reuse_dependency_payload::Owner) {
 let workspace .=frame.borrow();assert(workspace);
 let owners=[pin];assert(blot_backend_core_backend::pinWorkspaceInputs(workspace,units,pin,owners[..],default<const blot_reuse_dependency_payload::Owner[:]>())==blot_error::Error.none);
 assert(blot_backend_core_backend::resetGenerator(workspace,null)==blot_error::Error.none);
 let generator .=workspace.generator;assert(generator.planning.uses.count==0);
 var held:const blot_backend_unit_index::Uses? =null;
 {let index,error .=generator.unitUses(1,blot_backend_unit_index::Need{});assert(error==blot_error::Error.none);held .=index;assert(index .==blot_backend_unit_index::owned_uses[index.allocation_index]);}
 assert(held && !held.has_parents && !held.has_flow && held.references.get(1)==[1 as u32] && generator.planning.uses.count==1);
 let cached .=generator.planning.uses.get(1);assert(cached .==held);
 let again,error .=generator.unitUses(1,blot_backend_unit_index::Need{});assert(error==blot_error::Error.none && again .==held && !held.has_parents && !held.has_flow && generator.planning.uses.count==1);
 let parents,error .=generator.unitUses(1,blot_backend_unit_index::Need{parents:true,..});assert(error==blot_error::Error.none && parents .==held && held.has_parents && !held.has_flow && held.parentOf(1).node==2 && held.parentOf(1).count==1);
 let parent_span=held.parents;
 let flow,error .=generator.unitUses(1,blot_backend_unit_index::Need{flow:true,..});assert(error==blot_error::Error.none && flow .==held && held.has_flow && held.has_parents && blot_support::same_slice_identity(held.parents,parent_span));
 let definitions=held.definitions.offsets;
 let complete,error .=generator.unitUses(1,blot_backend_unit_index::Need{parents:true,flow:true,..});assert(error==blot_error::Error.none && complete .==held && generator.planning.uses.count==1 && blot_support::same_slice_identity(held.definitions.offsets,definitions) && held.references.get(1)==[1 as u32]);
}
fn quantifiedLookup() {
 let empty=blot_backend_unit_index::Set{};assert(!empty.contains(1));
 var values:dictionary<u32,bool> =dictionary<u32,bool>{};var keys:u32[4];var count:i64=0;
 for candidate in 0..10000 {let key=candidate as u32;if (::hash(key)&7)==7 {keys[count]=key;count++;if count==4 {break;}}}assert(count==4);
 for key in keys[..3] {values.insert(key,true);}assert(values.slots.len==8 && values.slots[7].tag!=0 && values.slots[0].tag!=0 && values.slots[1].tag!=0);
 var frozen=blot_backend_unit_index::freezeSet(values);for key in keys[..3] {assert(frozen.contains(key));}assert(!frozen.contains(keys[3]));
 ::clear(values);for key in keys[..3] {assert(frozen.contains(key));}frozen.deinit();assert(frozen.slots.len==0 && !frozen.contains(keys[0]));
}
fn main() {quantifiedLookup();
 var pin,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
 let units,error=blot_reuse_dependency_payload::alloc<blot_check_core::Module>(pin,1);assert(error==blot_error::Error.none);
 let bindings,error=blot_reuse_dependency_payload::alloc<blot_check_core::Binding>(pin,2);assert(error==blot_error::Error.none);for &binding in bindings {binding=default<blot_check_core::Binding>();}
 let nodes,error=blot_reuse_dependency_payload::alloc<blot_check_core::Node>(pin,3);assert(error==blot_error::Error.none);for &node in nodes {node=default<blot_check_core::Node>();}nodes[0].tag=blot_check_core::Tag.constant;nodes[1]=blot_check_core::Node{tag:blot_check_core::Tag.reference,a:0,..};nodes[2]=blot_check_core::Node{tag:blot_check_core::Tag.block_,a:0,b:1,..};
 let references,error=pin.copy([blot_check_core::BindingRef{0,1,..}]);assert(error==blot_error::Error.none);let extra,error=pin.copy([1 as u32]);assert(error==blot_error::Error.none);
 units[0]=blot_reuse_dependency_owned_headers::canonical(pin,blot_check_core::Module{unit:1,nodes:nodes,extra:extra,bindings:bindings,references:references,..});
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);inspect(frame,units,pin);assert(frame.release()==blot_error::Error.none);pin.deinit();
 print("unit Uses identity passed: scoped alias, canonical cache, lazy parent/flow upgrade and reuse");
}
