// Owned identity dictionaries and private graph projection for body chunks.
namespace blot_reuse_body_check_cache;
import .body_check_cache;
import .dependency_snapshot;
struct PrivateScope {old:u32,current:u32}
reusable[] var freeze_scheme_runs:blot_check_types::Scheme[>..]=[];
struct FreezeSchemes {storage:blot_check_types::Scheme[:]=default<blot_check_types::Scheme[:]>(),items:blot_check_types::Scheme[:]=default<blot_check_types::Scheme[:]>()}
fn push(self_:FreezeSchemes&,value:blot_check_types::Scheme)->Error {return blot_support_pooled_buffer::push(self_,value,freeze_scheme_runs);}
fn deinit(self_:FreezeSchemes&) {blot_support_pooled_buffer::deinit(self_,freeze_scheme_runs);}
fn clear(self_:FreezeSchemes&) {blot_support_pooled_buffer::clear(self_);}
struct FreezeIdentities {storage:IdentityRead[:]=default<IdentityRead[:]>(),items:IdentityRead[:]=default<IdentityRead[:]>()}
fn push(self_:FreezeIdentities&,value:IdentityRead)->Error {let name=owned_u8.realloc_slice(value.name,value.name.len);return blot_support_pooled_buffer::push(self_,IdentityRead{unit:value.unit,origin:value.origin,name:name,digest:value.digest,kind:value.kind},owned_IdentityRead);}
fn deinit(self_:FreezeIdentities&) {blot_support_pooled_buffer::deinit(self_,owned_IdentityRead);}
fn clear(self_:FreezeIdentities&) {blot_support_pooled_buffer::clear(self_);}
struct FreezeQualifications {storage:Qualification[:]=default<Qualification[:]>(),items:Qualification[:]=default<Qualification[:]>()}
fn push(self_:FreezeQualifications&,value:Qualification)->Error {return blot_support_pooled_buffer::push(self_,value,owned_Qualification);}
fn deinit(self_:FreezeQualifications&) {blot_support_pooled_buffer::deinit(self_,owned_Qualification);}
fn clear(self_:FreezeQualifications&) {blot_support_pooled_buffer::clear(self_);}
reusable[] var freeze_scope_runs:PrivateScope[>..]=[];
struct FreezeScopes {storage:PrivateScope[:]=default<PrivateScope[:]>(),items:PrivateScope[:]=default<PrivateScope[:]>()}
fn push(self_:FreezeScopes&,value:PrivateScope)->Error {return blot_support_pooled_buffer::push(self_,value,freeze_scope_runs);}
fn deinit(self_:FreezeScopes&) {blot_support_pooled_buffer::deinit(self_,freeze_scope_runs);}
fn clear(self_:FreezeScopes&) {blot_support_pooled_buffer::clear(self_);}
struct FreezeBodies {storage:Body[:]=default<Body[:]>(),items:Body[:]=default<Body[:]>()}
fn push(self_:FreezeBodies&,value:Body)->Error {return blot_support_pooled_buffer::push(self_,canonicalBody(value),owned_Body);}
fn deinit(self_:FreezeBodies&) {blot_support_pooled_buffer::deinit(self_,owned_Body);}
fn clear(self_:FreezeBodies&) {blot_support_pooled_buffer::clear(self_);}
reusable[] var freeze_constructor_runs:blot_reuse_body_auxiliary::Constructor[>..]=[];
struct FreezeConstructors {storage:blot_reuse_body_auxiliary::Constructor[:]=default<blot_reuse_body_auxiliary::Constructor[:]>(),items:blot_reuse_body_auxiliary::Constructor[:]=default<blot_reuse_body_auxiliary::Constructor[:]>()}
fn push(self_:FreezeConstructors&,value:blot_reuse_body_auxiliary::Constructor)->Error {return blot_support_pooled_buffer::push(self_,value,freeze_constructor_runs);}
fn deinit(self_:FreezeConstructors&) {blot_support_pooled_buffer::deinit(self_,freeze_constructor_runs);}
fn clear(self_:FreezeConstructors&) {blot_support_pooled_buffer::clear(self_);}
struct AuxiliaryGraph {tree:Tree,checked:blot_check_check::Checked,bodies:Body[:],scopes:FreezeScopes=FreezeScopes{..}}
fn physical(self_:AuxiliaryGraph&,identity_:Identity,selection:bool)->Identity,Error {
 for body,index in self_.bodies {let owner .= body.auxiliary;if !owner {continue;}let proof=PrivateFacts{self_.tree,self_.checked,owner.origins, ..};let slot=proof.physical(identity_,selection);if slot.present {return Identity{(index+1) as u32,slot.value, ..},blot_error::Error.none;}}return Identity{0,0, ..},blot_error::Error.dependency_limit;
}
fn version(self_:AuxiliaryGraph&,id:u32)->Identity,Error {
 for body,index in self_.bodies {let owner .= body.auxiliary;if !owner {continue;}let proof=PrivateFacts{self_.tree,self_.checked,owner.origins, ..};let origin=proof.version(id);if !origin.present {continue;}if index+1>0x7fffffff {return Identity{0,0, ..},blot_error::Error.dependency_limit;}let namespace_=(index+1) as u32;if origin.value.kind==PrivateVersionKind.source {return Identity{namespace_,origin.value.operand, ..},blot_error::Error.none;}let binding=position(owner.binding_origins,origin.value.operand);if !binding.present {return Identity{0,0, ..},blot_error::Error.dependency_limit;}return Identity{namespace_|0x80000000,binding.value+1, ..},blot_error::Error.none;}
 return Identity{0,0, ..},blot_error::Error.dependency_limit;
}
fn rigid(self_:AuxiliaryGraph&,scope:u32)->u32,Error {
 for entry in self_.scopes.items {if entry.old==scope {return entry.current,blot_error::Error.none;}}
 for body in self_.bodies {let owner .= body.auxiliary;if !owner {continue;}let proof=PrivateFacts{self_.tree,self_.checked,owner.origins, ..};if !proof.rigid(scope) {continue;}let current=(self_.scopes.items.len+1) as u32;let error=self_.scopes.push(PrivateScope{scope,current, ..});return current,error;}return 0,blot_error::Error.dependency_limit;
}
fn ownFieldName(names:Scratch_u8___&,name:const u8[:])->u32,Error {for known,index in names.items {if known==name {return index as u32,blot_error::Error.none;}}let index=names.items.len as u32;let owned=copyOwned(name);let error=names.push(owned);if error!=blot_error::Error.none {releaseOwned(owned);}return index,error;}
fn ownIdentityRead(catalog:Catalog,source:Source,reads:FreezeIdentities&,identity_:Identity,is_contract:bool)->u32,Error {
 var kind=NominalKind.type_;if is_contract {kind=NominalKind.contract;}let name,nominal_index,name_error=selectedIdentityName(catalog,identity_,is_contract);if name_error!=blot_error::Error.none {return 0,name_error;}
 for read,index in reads.items {if read.kind==kind && read.unit==identity_.unit && read.name==name {return index as u32,blot_error::Error.none;}}
 var digest=blot_support::none<Digest>();if is_contract {digest=contractDigest(catalog,identity_);}else {digest=nominalDigest(source,catalog,nominal_index);}if !digest.present {return 0,blot_error::Error.dependency_limit;}
 let origin=catalog.unitOrigin(identity_.unit);if !origin.present {return 0,blot_error::Error.dependency_limit;}let slot=reads.items.len as u32;let owned=copyOwned(name);let error=reads.push(IdentityRead{identity_.unit,origin.value,owned,digest.value,kind, ..});if error!=blot_error::Error.none {releaseOwned(owned);}return slot,error;
}
fn ownFamilyRead(catalog:Catalog,source:Source,reads:FreezeIdentities&,identity_:Identity)->u32,Error {
 let index=catalog.familyIdentity(identity_);if !index.present {return 0,blot_error::Error.dependency_limit;}let declaration=catalog.effect_families[index.value];let name=catalog.pool.get(declaration.name);for read,slot in reads.items {if read.kind==NominalKind.family && read.unit==identity_.unit && read.name==name {return slot as u32,blot_error::Error.none;}}
 let digest=familyDigest(source,catalog,index.value);let origin=catalog.unitOrigin(identity_.unit);if !digest.present || !origin.present {return 0,blot_error::Error.dependency_limit;}let slot=reads.items.len as u32;let owned=copyOwned(name);let error=reads.push(IdentityRead{identity_.unit,origin.value,owned,digest.value,NominalKind.family, ..});if error!=blot_error::Error.none {releaseOwned(owned);}return slot,error;
}
fn operationName(family:const u8[:],member:const u8[:])->u8[:] {
 var digits:u8[20]=default<u8[20]>();var start:i64=20;var size=family.len as u64;loop {start-=1;digits[start]=('0' as u8)+(size%10) as u8;size/=10;if size==0 {break;}}
 let prefix=20-start;let name=owned_u8.alloc_slice(prefix+1+family.len+member.len);for value,index in digits[start..] {name[index]=value;}name[prefix]=':' as u8;for value,index in family {name[prefix+1+index]=value;}for value,index in member {name[prefix+1+family.len+index]=value;}return name;
}
fn ownOperationRead(catalog:Catalog,source:Source,reads:FreezeIdentities&,identity_:Identity)->u32,Error {
 var budget:i64=4096;let index=catalog.operation(identity_,budget);if !index.present {return 0,blot_error::Error.dependency_limit;}let operation=catalog.effect_templates[index.value];let digest=operationDigest(source,catalog,index.value);if !digest.present {return 0,blot_error::Error.dependency_limit;}let family=catalog.effect_families[operation.family];let name=operationName(catalog.pool.get(family.name),catalog.pool.get(operation.name));
 for read,slot in reads.items {if budget==0 {releaseOwned(name);return 0,blot_error::Error.dependency_limit;}budget-=1;if read.kind==NominalKind.operation && read.unit==identity_.unit && read.name==name {releaseOwned(name);return slot as u32,blot_error::Error.none;}}
 let origin=catalog.unitOrigin(identity_.unit);if !origin.present {releaseOwned(name);return 0,blot_error::Error.dependency_limit;}let slot=reads.items.len as u32;let error=reads.push(IdentityRead{identity_.unit,origin.value,name,digest.value,NominalKind.operation, ..});if error!=blot_error::Error.none {releaseOwned(name);}return slot,error;
}
fn frozenNominal(catalog:Catalog,reads:const IdentityRead[:],identity_:Identity)->Identity,Error {
 if identity_.unit==0 {return identity_,blot_error::Error.none;}let index=catalog.identity(identity_);if !index.present {return Identity{0,0, ..},blot_error::Error.dependency_limit;}let original=catalog.nominals[index.value];for read,slot in reads {if read.kind==NominalKind.type_ && read.unit==original.identity.unit && read.name==catalog.pool.get(original.name) {return Identity{(slot+1) as u32,0, ..},blot_error::Error.none;}}return Identity{0,0, ..},blot_error::Error.dependency_limit;
}
struct AuxiliaryRoots {types:Scratch_u32=Scratch_u32{..},rows:Scratch_u32=Scratch_u32{..},labels:Scratch_u32=Scratch_u32{..}}
fn deinit(self_:AuxiliaryRoots&) {self_.types.deinit();self_.rows.deinit();self_.labels.deinit();}
fn map_ty(self_:AuxiliaryRoots&,value:u32)->u32,Error {let error=self_.types.push(value);return value,error;}
fn map_row(self_:AuxiliaryRoots&,value:u32)->u32,Error {let error=self_.rows.push(value);return value,error;}
fn map_label(self_:AuxiliaryRoots&,value:u32)->u32,Error {let error=self_.labels.push(value);return value,error;}
struct AuxiliaryFreeze {
 catalog:Catalog,source:Source,work:FreezeWork&,dependencies:Scratch_u32=Scratch_u32{..},constructors:FreezeConstructors=FreezeConstructors{..},
 roots:const u32[:],rows:const u32[:],labels:const u32[:],next_type:i64=0,next_row:i64=0,next_label:i64=0,private:AuxiliaryGraph,
}
fn depend(self_:AuxiliaryFreeze&,slot:u32)->Error {if !position(self_.dependencies.items,slot).present {return self_.dependencies.push(slot);}return blot_error::Error.none;}
fn map_contract_identity(self_:AuxiliaryFreeze&,value:Identity)->Identity,Error {let slot,error=ownIdentityRead(self_.catalog,self_.source,self_.work.nominals,value,true);if error!=blot_error::Error.none {return Identity{0,0, ..},error;}let error=self_.depend(slot);return Identity{slot+1,0, ..},error;}
fn map_operation_identity(self_:AuxiliaryFreeze&,value:Identity)->Identity,Error {let slot,error=ownOperationRead(self_.catalog,self_.source,self_.work.nominals,value);if error!=blot_error::Error.none {return Identity{0,0, ..},error;}let error=self_.depend(slot);return Identity{slot+1,0, ..},error;}
fn map_scope(self_:AuxiliaryFreeze&,value:u32)->u32,Error {if value==0 {return 0,blot_error::Error.none;}return self_.private.rigid(value);}
fn map_instance(self_:AuxiliaryFreeze&,value:Identity)->Identity,Error {if value.unit==0 && value.decl==0 {return value,blot_error::Error.none;}return self_.private.physical(value,false);}
fn map_ty(self_:AuxiliaryFreeze&,value:u32)->u32,Error {let mapped=self_.roots[self_.next_type];self_.next_type+=1;return mapped,blot_error::Error.none;}
fn map_row(self_:AuxiliaryFreeze&,value:u32)->u32,Error {let mapped=self_.rows[self_.next_row];self_.next_row+=1;return mapped,blot_error::Error.none;}
fn map_label(self_:AuxiliaryFreeze&,value:u32)->u32,Error {let mapped=self_.labels[self_.next_label];self_.next_label+=1;return mapped,blot_error::Error.none;}
fn map_name(self_:AuxiliaryFreeze&,value:u32)->u32,Error {if value==0 {return 0,blot_error::Error.none;}let slot,error=ownFieldName(self_.work.fields,self_.catalog.pool.get(value));return slot+1,error;}
fn map_template(self_:AuxiliaryFreeze&,value:u32)->u32,Error {if value>=self_.catalog.effect_templates.len {return 0,blot_error::Error.dependency_limit;}let slot,error=ownOperationRead(self_.catalog,self_.source,self_.work.nominals,self_.catalog.effect_templates[value].identity);if error!=blot_error::Error.none {return 0,error;}let error=self_.depend(slot);return slot+1,error;}
fn map_constructor(self_:AuxiliaryFreeze&,value:u32)->u32,Error {if value==0 {return 0,blot_error::Error.none;}if value>=self_.catalog.constructors.len {return 0,blot_error::Error.dependency_limit;}let constructor=self_.catalog.constructors[value];if constructor.nominal>=self_.catalog.nominals.len {return 0,blot_error::Error.dependency_limit;}let identity_=self_.catalog.nominals[constructor.nominal].identity;let slot,error=ownIdentityRead(self_.catalog,self_.source,self_.work.nominals,identity_,false);if error!=blot_error::Error.none {return 0,error;}let error=self_.depend(slot);if error!=blot_error::Error.none {return 0,error;}let pushed=self_.constructors.push(blot_reuse_body_auxiliary::Constructor{Identity{slot+1,0},constructor.tag, ..});return self_.constructors.items.len as u32,pushed;}
fn map_node(self_:AuxiliaryRoots&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_binding(self_:AuxiliaryRoots&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_name(self_:AuxiliaryRoots&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_instance(self_:AuxiliaryRoots&,value:Identity)->Identity,Error {return value,blot_error::Error.none;}
fn map_scope(self_:AuxiliaryRoots&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_constructor(self_:AuxiliaryRoots&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_types(self_:AuxiliaryRoots&,value:List)->List,Error {return value,blot_error::Error.none;}
fn map_bindings(self_:AuxiliaryRoots&,value:List)->List,Error {return value,blot_error::Error.none;}
fn map_request_arms(self_:AuxiliaryRoots&,value:List)->List,Error {return value,blot_error::Error.none;}
fn map_resolver_ops(self_:AuxiliaryRoots&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_resolver_completions(self_:AuxiliaryRoots&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_carries(self_:AuxiliaryRoots&,value:List)->List,Error {return value,blot_error::Error.none;}
fn map_template(self_:AuxiliaryRoots&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_goal(self_:AuxiliaryRoots&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_proof(self_:AuxiliaryRoots&,value:blot_check_check::DictionaryProof)->blot_check_check::DictionaryProof,Error {return value,blot_error::Error.none;}
fn map_contract_identity(self_:AuxiliaryRoots&,value:Identity)->Identity,Error {return value,blot_error::Error.none;}
fn map_operation_identity(self_:AuxiliaryRoots&,value:Identity)->Identity,Error {return value,blot_error::Error.none;}
fn map_callee_identity(self_:AuxiliaryRoots&,value:Identity)->Identity,Error {return value,blot_error::Error.none;}
fn map_nodes_pair(self_:AuxiliaryRoots&,value:u32[2])->u32[2],Error {return value,blot_error::Error.none;}
fn map_proposition(self_:AuxiliaryRoots&,value:blot_check_numeric_proof_terms::Proposition)->blot_check_numeric_proof_terms::Proposition,Error {return value,blot_error::Error.none;}
fn map_node(self_:AuxiliaryFreeze&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_binding(self_:AuxiliaryFreeze&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_types(self_:AuxiliaryFreeze&,value:List)->List,Error {return value,blot_error::Error.none;}
fn map_bindings(self_:AuxiliaryFreeze&,value:List)->List,Error {return value,blot_error::Error.none;}
fn map_request_arms(self_:AuxiliaryFreeze&,value:List)->List,Error {return value,blot_error::Error.none;}
fn map_resolver_ops(self_:AuxiliaryFreeze&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_resolver_completions(self_:AuxiliaryFreeze&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_carries(self_:AuxiliaryFreeze&,value:List)->List,Error {return value,blot_error::Error.none;}
fn map_goal(self_:AuxiliaryFreeze&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_proof(self_:AuxiliaryFreeze&,value:blot_check_check::DictionaryProof)->blot_check_check::DictionaryProof,Error {return value,blot_error::Error.none;}
fn map_callee_identity(self_:AuxiliaryFreeze&,value:Identity)->Identity,Error {return value,blot_error::Error.none;}
fn map_nodes_pair(self_:AuxiliaryFreeze&,value:u32[2])->u32[2],Error {return value,blot_error::Error.none;}
fn map_proposition(self_:AuxiliaryFreeze&,value:blot_check_numeric_proof_terms::Proposition)->blot_check_numeric_proof_terms::Proposition,Error {return value,blot_error::Error.none;}

fn selectedIdentityName(catalog:Catalog,identity_:Identity,is_contract:bool)->const u8[:],i64,Error {if is_contract {let declaration=catalog.contract(identity_);if !declaration.present {return default<const u8[:]>(),0,blot_error::Error.dependency_limit;}return catalog.pool.get(declaration.value.name),0,blot_error::Error.none;}let index=catalog.identity(identity_);if !index.present {return default<const u8[:]>(),0,blot_error::Error.dependency_limit;}return catalog.pool.get(catalog.nominals[index.value].name),index.value,blot_error::Error.none;}
