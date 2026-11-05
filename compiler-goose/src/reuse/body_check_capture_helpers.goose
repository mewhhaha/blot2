// Binding creation order and the complete semantic read frontier.
namespace blot_reuse_body_check_cache;
import .body_check_cache;
import check.source_sort;
struct BindingOrderEntry {binding:Binding,origin:u32,slot:u32}
struct BindingOrder {entries:BindingOrderEntry[:]}
reusable[] var binding_order_runs:BindingOrderEntry[>..]=[];
fn lessThan(self:BindingOrder,left:i64,right:i64)->bool {return self.entries[left].origin<self.entries[right].origin;}
fn swap(self:BindingOrder,left:i64,right:i64) {let before=self.entries[left];self.entries[left]=self.entries[right];self.entries[right]=before;}
fn orderBindings(bindings:Binding[:],origins:u32[:],facts:Fact[:],merges:Merge[:],carries:LoopCarry[:],exits:u32[:],rebindings:Rebinding[:])->Error {
 var ordered=true;var previous:u32=0;for origin,index in origins {let binding=bindings[index];if binding.kind!=blot_check_check::Kind.local && binding.kind!=blot_check_check::Kind.parameter {continue;}if previous>origin {ordered=false;}previous=origin;}if ordered {return Error.none;}
 let entries=binding_order_runs.alloc_slice(bindings.len);for binding,index in bindings {entries[index]=BindingOrderEntry{binding,origins[index],index as u32};}blot_check_source_sort::pdqContext(0,entries.len,BindingOrder{entries});
 for entry,index in entries {origins[entry.slot]=(index+1) as u32;}
 for &fact in facts {if fact.binding!=0 {fact.binding=origins[fact.binding-1];}}
 for &merge in merges {merge.result=origins[merge.result-1];merge.yes=origins[merge.yes-1];merge.no=origins[merge.no-1];}
 for &carry in carries {carry.incoming=origins[carry.incoming-1];carry.iteration=origins[carry.iteration-1];carry.backedge=origins[carry.backedge-1];carry.outgoing=origins[carry.outgoing-1];}
 for &binding in exits {binding=origins[binding-1];}
 for &binding in rebindings {binding.root=origins[binding.root-1];binding.self_binding=origins[binding.self_binding-1];}
 for entry,index in entries {bindings[index]=entry.binding;origins[index]=entry.origin;}binding_order_runs.free_slice(entries);return Error.none;
}
fn instantiatedReference(tree:const Tree&,checked:const blot_check_check::Checked&,predicate:blot_check_types::Obligation)->u32 {let tag=tree.node(predicate.source).tag;if tag!=blot_parse_ast::tag_name && tag!=blot_parse_ast::tag_binary {return 0;}let target=checked.resolved[predicate.source];if target==0 || checked.bindings[target].scheme.obligations.len==0 {return 0;}if tag==blot_parse_ast::tag_name && directPathField(checked,predicate) {return 0;}return target;}
fn directPathField(checked:const blot_check_check::Checked&,predicate:blot_check_types::Obligation)->bool {
 if predicate.kind!=blot_check_types::ObligationKind.field || predicate.explicit || predicate.name==0 || predicate.result==0 {return false;}let path=checked.types.list(checked.access_paths[predicate.source]);let types=checked.types.list(checked.access_types[predicate.source]);if path.len==0 || types.len!=path.len+1 {return false;}
 for projection,index in path {if projection>=checked.projection_catalog.len {return false;}let step=checked.projection_catalog[projection];if step.field==predicate.name && checked.types.head(predicate.ty,0)==checked.types.head(types[index],0) && checked.types.head(predicate.result,0)==checked.types.head(types[index+1],0) {return true;}}return false;
}
fn forwardsShared(checked:const blot_check_check::Checked&,target:u32,identity_:Identity)->bool {
 if identity_.unit!=checked.unit || identity_.decl==0 || identity_.decl>=checked.bindings.len || target==0 || target>=checked.bindings.len {return false;}var pending:u32[64]=default<u32[64]>();var length:i64=1;var next:i64=0;var budget:i64=4096;pending[0]=target;
 while next<length {let id=pending[next];next+=1;if id==identity_.decl {return true;}if id==0 || id>=checked.bindings.len {return false;}let scheme=checked.bindings[id].scheme;if scheme.obligations.start>checked.obligations.len || scheme.obligations.len>checked.obligations.len-scheme.obligations.start {return false;}
 for predicate in checked.obligations[scheme.obligations.start..scheme.obligations.start+scheme.obligations.len] {if budget==0 {return false;}budget-=1;if !sharedPredicate(predicate,checked.unit) {continue;}let callee=predicate.identity.decl;if position(pending[..length],callee).present {continue;}if length==64 {return false;}pending[length]=callee;length+=1;}}
 return false;
}
fn captureRead(context:CaptureEnvironment&,scratch:CaptureScratch&,id:u32)->blot_support::Option<u32>,Error {
 let slot=position(scratch.old_bindings.items,id);if slot.present {return blot_support::some(slot.value+1),Error.none;}
 let checked .= context.checked;if id==0 || id>=checked.bindings.len || scratch.bindings.items.len>=4096 {return blot_support::none<u32>(),Error.none;}
 let old=checked.bindings[id];let local=old.kind==blot_check_check::Kind.local || old.kind==blot_check_check::Kind.parameter;if old.scheme.generative.len!=0 && !local {return blot_support::none<u32>(),Error.none;}
 let declaration=position(context.shape.ids,old.declaration);let owner=position(context.shape.ids,old.owner);if local && (!declaration.present || !owner.present) {return blot_support::none<u32>(),Error.none;}if !context.catalog.values.present {return blot_support::none<u32>(),Error.none;}
 var digest=default<Digest>();var ty:u32=0;if local {ty=old.ty;}else {let current=readDigest(Source.store{checked.types},old,checked.obligations,context.catalog.values.value.names,context.catalog);if !current.present {return blot_support::none<u32>(),Error.none;}digest=current.value;}
 var declaration_position:u32=0;var owner_position:u32=0;if declaration.present {declaration_position=declaration.value;}if owner.present {owner_position=owner.value;}
 let name=copyOwned(context.pool.get(old.name));let error=scratch.bindings.push(Binding{name:name,kind:old.kind,private:old.private,declaration:declaration_position,owner:owner_position,ty:ty,scheme:old.scheme.root!=0,named_function:old.named_function,capability_flow:old.capability_flow,capability_parameters:old.capability_parameters,runtime:runtimeBinding(context.catalog.values.value.tree,old),external:old.external,interface:digest});
 if error!=Error.none {releaseOwned(name);return blot_support::none<u32>(),error;}let error=scratch.old_bindings.push(id);if error!=Error.none {return blot_support::none<u32>(),error;}return blot_support::some(scratch.old_bindings.items.len as u32),Error.none;
}
fn captureLocal(context:CaptureEnvironment&,scratch:CaptureScratch&,id:u32)->blot_support::Option<u32>,Error {
 let slot=position(scratch.old_bindings.items,id);if slot.present {return blot_support::some(slot.value+1),Error.none;}let checked .= context.checked;if id==0 || id>=checked.bindings.len {return blot_support::none<u32>(),Error.none;}let old=checked.bindings[id];if old.kind!=blot_check_check::Kind.local && old.kind!=blot_check_check::Kind.parameter {return blot_support::none<u32>(),Error.none;}
 let declaration=position(context.shape.ids,old.declaration);let owner=position(context.shape.ids,old.owner);if !declaration.present || !owner.present {return blot_support::none<u32>(),Error.none;}let ignored,error=proveType(Source.store{checked.types},old.ty,context.catalog);if error!=Error.none {if error==Error.dependency_limit {return blot_support::none<u32>(),Error.none;}return blot_support::none<u32>(),error;}
 let name=copyOwned(context.pool.get(old.name));let error=scratch.bindings.push(Binding{name:name,kind:old.kind,private:old.private,declaration:declaration.value,owner:owner.value,ty:old.ty,scheme:old.scheme.root!=0,named_function:old.named_function,capability_flow:old.capability_flow,capability_parameters:old.capability_parameters,runtime:false,external:blot_support::none<blot_check_check::ExternalTarget>(),interface:default<Digest>()});if error!=Error.none {releaseOwned(name);return blot_support::none<u32>(),error;}let error=scratch.old_bindings.push(id);if error!=Error.none {return blot_support::none<u32>(),error;}return blot_support::some(scratch.old_bindings.items.len as u32),Error.none;
}
struct AuxiliaryBindings {context:CaptureEnvironment&,scratch:CaptureScratch&}
fn map_scope(self:AuxiliaryBindings&,value:u32)->u32,Error {if value!=0 && !self.context.catalog.private.value.rigid(value) {return 0,Error.dependency_limit;}return value,Error.none;}
fn map_instance(self:AuxiliaryBindings&,value:Identity)->Identity,Error {if (value.unit!=0 || value.decl!=0) && !self.context.catalog.private.value.physical(value,false).present {return Identity{0,0},Error.dependency_limit;}return value,Error.none;}
fn map_callee_identity(self:AuxiliaryBindings&,value:Identity)->Identity,Error {if value.unit!=self.context.checked.unit || value.decl==0 {return Identity{0,0},Error.dependency_limit;}let captured,error=captureRead(self.context,self.scratch,value.decl);if error!=Error.none {return Identity{0,0},error;}if !captured.present {return Identity{0,0},Error.dependency_limit;}return value,Error.none;}
fn map_binding(self:AuxiliaryBindings&,value:u32)->u32,Error {if value!=0 {let captured,error=captureRead(self.context,self.scratch,value);if error!=Error.none {return 0,error;}if !captured.present {return 0,Error.dependency_limit;}}return value,Error.none;}
fn map_ty(self:AuxiliaryBindings&,value:u32)->u32,Error {let ignored,error=proveType(Source.store{self.context.checked.types},value,self.context.catalog);return value,error;}
struct AuxiliaryBindingSlots {origins:const u32[:]}
fn map_callee_identity(self:AuxiliaryBindingSlots&,value:Identity)->Identity,Error {let slot=position(self.origins,value.decl);if !slot.present {return Identity{0,0},Error.dependency_limit;}return Identity{0,slot.value+1},Error.none;}
fn map_binding(self:AuxiliaryBindingSlots&,value:u32)->u32,Error {if value==0 {return 0,Error.none;}let slot=position(self.origins,value);if !slot.present {return 0,Error.dependency_limit;}return slot.value+1,Error.none;}
fn map_node(self:AuxiliaryBindings&,value:u32)->u32,Error {return value,Error.none;}
fn map_row(self:AuxiliaryBindings&,value:u32)->u32,Error {return value,Error.none;}
fn map_label(self:AuxiliaryBindings&,value:u32)->u32,Error {return value,Error.none;}
fn map_name(self:AuxiliaryBindings&,value:u32)->u32,Error {return value,Error.none;}
fn map_constructor(self:AuxiliaryBindings&,value:u32)->u32,Error {return value,Error.none;}
fn map_types(self:AuxiliaryBindings&,value:List)->List,Error {return value,Error.none;}
fn map_bindings(self:AuxiliaryBindings&,value:List)->List,Error {return value,Error.none;}
fn map_request_arms(self:AuxiliaryBindings&,value:List)->List,Error {return value,Error.none;}
fn map_resolver_ops(self:AuxiliaryBindings&,value:u32)->u32,Error {return value,Error.none;}
fn map_resolver_completions(self:AuxiliaryBindings&,value:u32)->u32,Error {return value,Error.none;}
fn map_carries(self:AuxiliaryBindings&,value:List)->List,Error {return value,Error.none;}
fn map_template(self:AuxiliaryBindings&,value:u32)->u32,Error {return value,Error.none;}
fn map_goal(self:AuxiliaryBindings&,value:u32)->u32,Error {return value,Error.none;}
fn map_proof(self:AuxiliaryBindings&,value:blot_check_check::DictionaryProof)->blot_check_check::DictionaryProof,Error {return value,Error.none;}
fn map_contract_identity(self:AuxiliaryBindings&,value:Identity)->Identity,Error {return value,Error.none;}
fn map_operation_identity(self:AuxiliaryBindings&,value:Identity)->Identity,Error {return value,Error.none;}
fn map_nodes_pair(self:AuxiliaryBindings&,value:u32[2])->u32[2],Error {return value,Error.none;}
fn map_proposition(self:AuxiliaryBindings&,value:blot_check_numeric_proof_terms::Proposition)->blot_check_numeric_proof_terms::Proposition,Error {return value,Error.none;}
fn map_node(self:AuxiliaryBindingSlots&,value:u32)->u32,Error {return value,Error.none;}
fn map_ty(self:AuxiliaryBindingSlots&,value:u32)->u32,Error {return value,Error.none;}
fn map_row(self:AuxiliaryBindingSlots&,value:u32)->u32,Error {return value,Error.none;}
fn map_label(self:AuxiliaryBindingSlots&,value:u32)->u32,Error {return value,Error.none;}
fn map_name(self:AuxiliaryBindingSlots&,value:u32)->u32,Error {return value,Error.none;}
fn map_instance(self:AuxiliaryBindingSlots&,value:Identity)->Identity,Error {return value,Error.none;}
fn map_scope(self:AuxiliaryBindingSlots&,value:u32)->u32,Error {return value,Error.none;}
fn map_constructor(self:AuxiliaryBindingSlots&,value:u32)->u32,Error {return value,Error.none;}
fn map_types(self:AuxiliaryBindingSlots&,value:List)->List,Error {return value,Error.none;}
fn map_bindings(self:AuxiliaryBindingSlots&,value:List)->List,Error {return value,Error.none;}
fn map_request_arms(self:AuxiliaryBindingSlots&,value:List)->List,Error {return value,Error.none;}
fn map_resolver_ops(self:AuxiliaryBindingSlots&,value:u32)->u32,Error {return value,Error.none;}
fn map_resolver_completions(self:AuxiliaryBindingSlots&,value:u32)->u32,Error {return value,Error.none;}
fn map_carries(self:AuxiliaryBindingSlots&,value:List)->List,Error {return value,Error.none;}
fn map_template(self:AuxiliaryBindingSlots&,value:u32)->u32,Error {return value,Error.none;}
fn map_goal(self:AuxiliaryBindingSlots&,value:u32)->u32,Error {return value,Error.none;}
fn map_proof(self:AuxiliaryBindingSlots&,value:blot_check_check::DictionaryProof)->blot_check_check::DictionaryProof,Error {return value,Error.none;}
fn map_contract_identity(self:AuxiliaryBindingSlots&,value:Identity)->Identity,Error {return value,Error.none;}
fn map_operation_identity(self:AuxiliaryBindingSlots&,value:Identity)->Identity,Error {return value,Error.none;}
fn map_nodes_pair(self:AuxiliaryBindingSlots&,value:u32[2])->u32[2],Error {return value,Error.none;}
fn map_proposition(self:AuxiliaryBindingSlots&,value:blot_check_numeric_proof_terms::Proposition)->blot_check_numeric_proof_terms::Proposition,Error {return value,Error.none;}
