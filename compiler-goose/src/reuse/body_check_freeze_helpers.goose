// Owned identity dictionaries and private graph projection for body chunks.
namespace blot_reuse_body_check_cache;
import .body_check_cache;
import .dependency_snapshot;
struct PrivateScope {old:u32,current:u32}
struct AuxiliaryGraph {tree:Tree,checked:blot_check_check::Checked,bodies:Body[:],scopes:PrivateScope[>..<]&}
fn physical(self_:AuxiliaryGraph&,identity_:Identity,selection:bool)->Identity,Error {
 for body,index in self_.bodies {let owner .= body.auxiliary;if !owner {continue;}let proof=PrivateFacts{self_.tree,self_.checked,owner.origins, ..};let slot=proof.physical(identity_,selection);if slot.present {return Identity{(index+1) as u32,slot.value, ..},blot_error::Error.none;}}return Identity{0,0, ..},blot_error::Error.dependency_limit;
}
fn version(self_:AuxiliaryGraph&,id:u32)->Identity,Error {
 for body,index in self_.bodies {let owner .= body.auxiliary;if !owner {continue;}let proof=PrivateFacts{self_.tree,self_.checked,owner.origins, ..};let origin=proof.version(id);if !origin.present {continue;}if index+1>0x7fffffff {return Identity{0,0, ..},blot_error::Error.dependency_limit;}let namespace_=(index+1) as u32;if origin.value.kind==PrivateVersionKind.source {return Identity{namespace_,origin.value.operand, ..},blot_error::Error.none;}let binding=position(owner.binding_origins,origin.value.operand);if !binding.present {return Identity{0,0, ..},blot_error::Error.dependency_limit;}return Identity{namespace_|0x80000000,binding.value+1, ..},blot_error::Error.none;}
 return Identity{0,0, ..},blot_error::Error.dependency_limit;
}
fn rigid(self_:AuxiliaryGraph&,scope:u32)->u32,Error {
 for entry in self_.scopes {if entry.old==scope {return entry.current,blot_error::Error.none;}}
 for body in self_.bodies {let owner .= body.auxiliary;if !owner {continue;}let proof=PrivateFacts{self_.tree,self_.checked,owner.origins, ..};if !proof.rigid(scope) {continue;}let current=(self_.scopes.len+1) as u32;self_.scopes.push(PrivateScope{scope,current, ..});return current,blot_error::Error.none;}return 0,blot_error::Error.dependency_limit;
}
fn ownFieldName(names:u8[:][>..<]&,name:const u8[:])->u32,Error {for known,index in names {if known==name {return index as u32,blot_error::Error.none;}}let index=names.len as u32;names.push(copyOwned(name));return index,blot_error::Error.none;}
fn ownIdentityRead(catalog:Catalog,source:Source,reads:IdentityRead[>..<]&,identity_:Identity,is_contract:bool)->u32,Error {
 var kind=NominalKind.type_;var name:const u8[:]=default<const u8[:]>();var nominal_index:i64=0;
 if is_contract {kind=NominalKind.contract;let declaration=catalog.contract(identity_);if !declaration.present {return 0,blot_error::Error.dependency_limit;}name=catalog.pool.get(declaration.value.name);}else {let index=catalog.identity(identity_);if !index.present {return 0,blot_error::Error.dependency_limit;}nominal_index=index.value;name=catalog.pool.get(catalog.nominals[nominal_index].name);}
 for read,index in reads {if read.kind==kind && read.unit==identity_.unit && read.name==name {return index as u32,blot_error::Error.none;}}
 var digest=blot_support::none<Digest>();if is_contract {digest=contractDigest(catalog,identity_);}else {digest=nominalDigest(source,catalog,nominal_index);}if !digest.present {return 0,blot_error::Error.dependency_limit;}
 let origin=catalog.unitOrigin(identity_.unit);if !origin.present {return 0,blot_error::Error.dependency_limit;}let slot=reads.len as u32;reads.push(IdentityRead{identity_.unit,origin.value,copyOwned(name),digest.value,kind, ..});return slot,blot_error::Error.none;
}
fn ownFamilyRead(catalog:Catalog,source:Source,reads:IdentityRead[>..<]&,identity_:Identity)->u32,Error {
 let index=catalog.familyIdentity(identity_);if !index.present {return 0,blot_error::Error.dependency_limit;}let declaration=catalog.effect_families[index.value];let name=catalog.pool.get(declaration.name);for read,slot in reads {if read.kind==NominalKind.family && read.unit==identity_.unit && read.name==name {return slot as u32,blot_error::Error.none;}}
 let digest=familyDigest(source,catalog,index.value);let origin=catalog.unitOrigin(identity_.unit);if !digest.present || !origin.present {return 0,blot_error::Error.dependency_limit;}let slot=reads.len as u32;reads.push(IdentityRead{identity_.unit,origin.value,copyOwned(name),digest.value,NominalKind.family, ..});return slot,blot_error::Error.none;
}
fn operationName(family:const u8[:],member:const u8[:])->u8[:] {
 var digits:u8[20]=default<u8[20]>();var start:i64=20;var size=family.len as u64;loop {start-=1;digits[start]=('0' as u8)+(size%10) as u8;size/=10;if size==0 {break;}}
 let prefix=20-start;let name=owned_u8.alloc_slice(prefix+1+family.len+member.len);for value,index in digits[start..] {name[index]=value;}name[prefix]=':' as u8;for value,index in family {name[prefix+1+index]=value;}for value,index in member {name[prefix+1+family.len+index]=value;}return name;
}
fn ownOperationRead(catalog:Catalog,source:Source,reads:IdentityRead[>..<]&,identity_:Identity)->u32,Error {
 var budget:i64=4096;let index=catalog.operation(identity_,budget);if !index.present {return 0,blot_error::Error.dependency_limit;}let operation=catalog.effect_templates[index.value];let digest=operationDigest(source,catalog,index.value);if !digest.present {return 0,blot_error::Error.dependency_limit;}let family=catalog.effect_families[operation.family];let name=operationName(catalog.pool.get(family.name),catalog.pool.get(operation.name));
 for read,slot in reads {if budget==0 {releaseOwned(name);return 0,blot_error::Error.dependency_limit;}budget-=1;if read.kind==NominalKind.operation && read.unit==identity_.unit && read.name==name {releaseOwned(name);return slot as u32,blot_error::Error.none;}}
 let origin=catalog.unitOrigin(identity_.unit);if !origin.present {releaseOwned(name);return 0,blot_error::Error.dependency_limit;}let slot=reads.len as u32;reads.push(IdentityRead{identity_.unit,origin.value,name,digest.value,NominalKind.operation, ..});return slot,blot_error::Error.none;
}
fn frozenNominal(catalog:Catalog,reads:const IdentityRead[:],identity_:Identity)->Identity,Error {
 if identity_.unit==0 {return identity_,blot_error::Error.none;}let index=catalog.identity(identity_);if !index.present {return Identity{0,0, ..},blot_error::Error.dependency_limit;}let original=catalog.nominals[index.value];for read,slot in reads {if read.kind==NominalKind.type_ && read.unit==original.identity.unit && read.name==catalog.pool.get(original.name) {return Identity{(slot+1) as u32,0, ..},blot_error::Error.none;}}return Identity{0,0, ..},blot_error::Error.dependency_limit;
}
struct AuxiliaryRoots {types:u32[>..<]&,rows:u32[>..<]&,labels:u32[>..<]&}
fn map_ty(self_:AuxiliaryRoots&,value:u32)->u32,Error {self_.types.push(value);return value,blot_error::Error.none;}
fn map_row(self_:AuxiliaryRoots&,value:u32)->u32,Error {self_.rows.push(value);return value,blot_error::Error.none;}
fn map_label(self_:AuxiliaryRoots&,value:u32)->u32,Error {self_.labels.push(value);return value,blot_error::Error.none;}
struct AuxiliaryFreeze {
 catalog:Catalog,source:Source,nominals:IdentityRead[>..<]&,fields:u8[:][>..<]&,dependencies:u32[>..<]&,constructors:blot_reuse_body_auxiliary::Constructor[>..<]&,
 roots:const u32[:],rows:const u32[:],labels:const u32[:],next_type:i64&,next_row:i64&,next_label:i64&,private:AuxiliaryGraph&,
}
fn depend(self_:AuxiliaryFreeze&,slot:u32)->Error {if !position(self_.dependencies[..],slot).present {self_.dependencies.push(slot);}return blot_error::Error.none;}
fn map_contract_identity(self_:AuxiliaryFreeze&,value:Identity)->Identity,Error {let slot,error=ownIdentityRead(self_.catalog,self_.source,self_.nominals,value,true);if error!=blot_error::Error.none {return Identity{0,0, ..},error;}let error=self_.depend(slot);return Identity{slot+1,0, ..},error;}
fn map_operation_identity(self_:AuxiliaryFreeze&,value:Identity)->Identity,Error {let slot,error=ownOperationRead(self_.catalog,self_.source,self_.nominals,value);if error!=blot_error::Error.none {return Identity{0,0, ..},error;}let error=self_.depend(slot);return Identity{slot+1,0, ..},error;}
fn map_scope(self_:AuxiliaryFreeze&,value:u32)->u32,Error {if value==0 {return 0,blot_error::Error.none;}return self_.private.rigid(value);}
fn map_instance(self_:AuxiliaryFreeze&,value:Identity)->Identity,Error {if value.unit==0 && value.decl==0 {return value,blot_error::Error.none;}return self_.private.physical(value,false);}
fn map_ty(self_:AuxiliaryFreeze&,value:u32)->u32,Error {let mapped=self_.roots[self_.next_type];self_.next_type+=1;return mapped,blot_error::Error.none;}
fn map_row(self_:AuxiliaryFreeze&,value:u32)->u32,Error {let mapped=self_.rows[self_.next_row];self_.next_row+=1;return mapped,blot_error::Error.none;}
fn map_label(self_:AuxiliaryFreeze&,value:u32)->u32,Error {let mapped=self_.labels[self_.next_label];self_.next_label+=1;return mapped,blot_error::Error.none;}
fn map_name(self_:AuxiliaryFreeze&,value:u32)->u32,Error {if value==0 {return 0,blot_error::Error.none;}let slot,error=ownFieldName(self_.fields,self_.catalog.pool.get(value));return slot+1,error;}
fn map_template(self_:AuxiliaryFreeze&,value:u32)->u32,Error {if value>=self_.catalog.effect_templates.len {return 0,blot_error::Error.dependency_limit;}let slot,error=ownOperationRead(self_.catalog,self_.source,self_.nominals,self_.catalog.effect_templates[value].identity);if error!=blot_error::Error.none {return 0,error;}let error=self_.depend(slot);return slot+1,error;}
fn map_constructor(self_:AuxiliaryFreeze&,value:u32)->u32,Error {if value==0 {return 0,blot_error::Error.none;}if value>=self_.catalog.constructors.len {return 0,blot_error::Error.dependency_limit;}let constructor=self_.catalog.constructors[value];if constructor.nominal>=self_.catalog.nominals.len {return 0,blot_error::Error.dependency_limit;}let identity_=self_.catalog.nominals[constructor.nominal].identity;let slot,error=ownIdentityRead(self_.catalog,self_.source,self_.nominals,identity_,false);if error!=blot_error::Error.none {return 0,error;}let error=self_.depend(slot);if error!=blot_error::Error.none {return 0,error;}self_.constructors.push(blot_reuse_body_auxiliary::Constructor{Identity{slot+1,0},constructor.tag, ..});return self_.constructors.len as u32,blot_error::Error.none;}
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
