// Conservative body capture: every decline leaves ordinary checking available.
namespace blot_reuse_body_check_cache;
import .body_check_cache;
import .principal_type_graph;
struct Scratch_Fact {storage:Fact[:]=[],items:Fact[:]=[]}
fn push(self:Scratch_Fact&,value:Fact)->Error {return blot_support_pooled_buffer::push(self,value,owned_Fact);}
fn append(self:Scratch_Fact&,values:const Fact[:])->Error {return blot_support_pooled_buffer::append(self,values,owned_Fact);}
fn deinit(self:Scratch_Fact&) {blot_support_pooled_buffer::deinit(self,owned_Fact);}
struct Scratch_Binding {storage:Binding[:]=[],items:Binding[:]=[]}
fn push(self:Scratch_Binding&,value:Binding)->Error {return blot_support_pooled_buffer::push(self,value,owned_Binding);}
fn append(self:Scratch_Binding&,values:const Binding[:])->Error {return blot_support_pooled_buffer::append(self,values,owned_Binding);}
fn deinit(self:Scratch_Binding&) {blot_support_pooled_buffer::deinit(self,owned_Binding);}
struct Scratch_u32 {storage:u32[:]=[],items:u32[:]=[]}
fn push(self:Scratch_u32&,value:u32)->Error {return blot_support_pooled_buffer::push(self,value,owned_u32);}
fn append(self:Scratch_u32&,values:const u32[:])->Error {return blot_support_pooled_buffer::append(self,values,owned_u32);}
fn deinit(self:Scratch_u32&) {blot_support_pooled_buffer::deinit(self,owned_u32);}
struct Scratch_TypeRead {storage:TypeRead[:]=[],items:TypeRead[:]=[]}
fn push(self:Scratch_TypeRead&,value:TypeRead)->Error {return blot_support_pooled_buffer::push(self,value,owned_TypeRead);}
fn append(self:Scratch_TypeRead&,values:const TypeRead[:])->Error {return blot_support_pooled_buffer::append(self,values,owned_TypeRead);}
fn deinit(self:Scratch_TypeRead&) {blot_support_pooled_buffer::deinit(self,owned_TypeRead);}
struct Scratch_Predicate {storage:Predicate[:]=[],items:Predicate[:]=[]}
fn push(self:Scratch_Predicate&,value:Predicate)->Error {return blot_support_pooled_buffer::push(self,value,owned_Predicate);}
fn append(self:Scratch_Predicate&,values:const Predicate[:])->Error {return blot_support_pooled_buffer::append(self,values,owned_Predicate);}
fn deinit(self:Scratch_Predicate&) {blot_support_pooled_buffer::deinit(self,owned_Predicate);}
struct Scratch_u8___ {storage:u8[:][:]=[],items:u8[:][:]=[]}
fn push(self:Scratch_u8___&,value:u8[:])->Error {return blot_support_pooled_buffer::push(self,value,owned_u8___);}
fn append(self:Scratch_u8___&,values:const u8[:][:])->Error {return blot_support_pooled_buffer::append(self,values,owned_u8___);}
fn deinit(self:Scratch_u8___&) {blot_support_pooled_buffer::deinit(self,owned_u8___);}
struct Scratch_Projection {storage:Projection[:]=[],items:Projection[:]=[]}
fn push(self:Scratch_Projection&,value:Projection)->Error {return blot_support_pooled_buffer::push(self,value,owned_Projection);}
fn append(self:Scratch_Projection&,values:const Projection[:])->Error {return blot_support_pooled_buffer::append(self,values,owned_Projection);}
fn deinit(self:Scratch_Projection&) {blot_support_pooled_buffer::deinit(self,owned_Projection);}
struct Scratch_Signature {storage:Signature[:]=[],items:Signature[:]=[]}
fn push(self:Scratch_Signature&,value:Signature)->Error {return blot_support_pooled_buffer::push(self,value,owned_Signature);}
fn append(self:Scratch_Signature&,values:const Signature[:])->Error {return blot_support_pooled_buffer::append(self,values,owned_Signature);}
fn deinit(self:Scratch_Signature&) {blot_support_pooled_buffer::deinit(self,owned_Signature);}
struct Scratch_Merge {storage:Merge[:]=[],items:Merge[:]=[]}
fn push(self:Scratch_Merge&,value:Merge)->Error {return blot_support_pooled_buffer::push(self,value,owned_Merge);}
fn append(self:Scratch_Merge&,values:const Merge[:])->Error {return blot_support_pooled_buffer::append(self,values,owned_Merge);}
fn deinit(self:Scratch_Merge&) {blot_support_pooled_buffer::deinit(self,owned_Merge);}
struct Scratch_LoopCarry {storage:LoopCarry[:]=[],items:LoopCarry[:]=[]}
fn push(self:Scratch_LoopCarry&,value:LoopCarry)->Error {return blot_support_pooled_buffer::push(self,value,owned_LoopCarry);}
fn append(self:Scratch_LoopCarry&,values:const LoopCarry[:])->Error {return blot_support_pooled_buffer::append(self,values,owned_LoopCarry);}
fn deinit(self:Scratch_LoopCarry&) {blot_support_pooled_buffer::deinit(self,owned_LoopCarry);}
struct Scratch_LoopExit {storage:LoopExit[:]=[],items:LoopExit[:]=[]}
fn push(self:Scratch_LoopExit&,value:LoopExit)->Error {return blot_support_pooled_buffer::push(self,value,owned_LoopExit);}
fn append(self:Scratch_LoopExit&,values:const LoopExit[:])->Error {return blot_support_pooled_buffer::append(self,values,owned_LoopExit);}
fn deinit(self:Scratch_LoopExit&) {blot_support_pooled_buffer::deinit(self,owned_LoopExit);}
struct Scratch_Rebinding {storage:Rebinding[:]=[],items:Rebinding[:]=[]}
fn push(self:Scratch_Rebinding&,value:Rebinding)->Error {return blot_support_pooled_buffer::push(self,value,owned_Rebinding);}
fn append(self:Scratch_Rebinding&,values:const Rebinding[:])->Error {return blot_support_pooled_buffer::append(self,values,owned_Rebinding);}
fn deinit(self:Scratch_Rebinding&) {blot_support_pooled_buffer::deinit(self,owned_Rebinding);}
struct Scratch_Constructor {storage:Constructor[:]=[],items:Constructor[:]=[]}
fn push(self:Scratch_Constructor&,value:Constructor)->Error {return blot_support_pooled_buffer::push(self,value,owned_Constructor);}
fn append(self:Scratch_Constructor&,values:const Constructor[:])->Error {return blot_support_pooled_buffer::append(self,values,owned_Constructor);}
fn deinit(self:Scratch_Constructor&) {blot_support_pooled_buffer::deinit(self,owned_Constructor);}
struct Scratch_Access {storage:Access[:]=[],items:Access[:]=[]}
fn push(self:Scratch_Access&,value:Access)->Error {return blot_support_pooled_buffer::push(self,value,owned_Access);}
fn append(self:Scratch_Access&,values:const Access[:])->Error {return blot_support_pooled_buffer::append(self,values,owned_Access);}
fn deinit(self:Scratch_Access&) {blot_support_pooled_buffer::deinit(self,owned_Access);}
struct Scratch_FieldProjection {storage:FieldProjection[:]=[],items:FieldProjection[:]=[]}
fn push(self:Scratch_FieldProjection&,value:FieldProjection)->Error {return blot_support_pooled_buffer::push(self,value,owned_FieldProjection);}
fn append(self:Scratch_FieldProjection&,values:const FieldProjection[:])->Error {return blot_support_pooled_buffer::append(self,values,owned_FieldProjection);}
fn deinit(self:Scratch_FieldProjection&) {blot_support_pooled_buffer::deinit(self,owned_FieldProjection);}
struct Scratch_LocalScheme {storage:LocalScheme[:]=[],items:LocalScheme[:]=[]}
fn push(self:Scratch_LocalScheme&,value:LocalScheme)->Error {return blot_support_pooled_buffer::push(self,value,owned_LocalScheme);}
fn append(self:Scratch_LocalScheme&,values:const LocalScheme[:])->Error {return blot_support_pooled_buffer::append(self,values,owned_LocalScheme);}
fn deinit(self:Scratch_LocalScheme&) {blot_support_pooled_buffer::deinit(self,owned_LocalScheme);}
struct CaptureScratch {
facts:Scratch_Fact=Scratch_Fact{},
bindings:Scratch_Binding=Scratch_Binding{},
old_bindings:Scratch_u32=Scratch_u32{},
closed_rows:Scratch_u32=Scratch_u32{},
type_reads:Scratch_TypeRead=Scratch_TypeRead{},
predicates:Scratch_Predicate=Scratch_Predicate{},
members:Scratch_u8___=Scratch_u8___{},
projections:Scratch_Projection=Scratch_Projection{},
signatures:Scratch_Signature=Scratch_Signature{},
merges:Scratch_Merge=Scratch_Merge{},
loop_carries:Scratch_LoopCarry=Scratch_LoopCarry{},
loop_exits:Scratch_LoopExit=Scratch_LoopExit{},
exit_bindings:Scratch_u32=Scratch_u32{},
rebindings:Scratch_Rebinding=Scratch_Rebinding{},
constructors:Scratch_Constructor=Scratch_Constructor{},
accesses:Scratch_Access=Scratch_Access{},
fields:Scratch_FieldProjection=Scratch_FieldProjection{},
field_tags:Scratch_u32=Scratch_u32{},
local_schemes:Scratch_LocalScheme=Scratch_LocalScheme{},
}
fn deinit(self:CaptureScratch&) {for binding in self.bindings.items {releaseOwned(binding.name);}for predicate in self.predicates.items {releaseOwned(predicate.name);}for member in self.members.items {releaseOwned(member);}
self.facts.deinit();
self.bindings.deinit();
self.old_bindings.deinit();
self.closed_rows.deinit();
self.type_reads.deinit();
self.predicates.deinit();
self.members.deinit();
self.projections.deinit();
self.signatures.deinit();
self.merges.deinit();
self.loop_carries.deinit();
self.loop_exits.deinit();
self.exit_bindings.deinit();
self.rebindings.deinit();
self.constructors.deinit();
self.accesses.deinit();
self.fields.deinit();
self.field_tags.deinit();
self.local_schemes.deinit();
}
struct CaptureEnvironment {tree:const Tree&,pool:const Pool&,text:const u8[:],checked:const blot_check_check::Checked&,root:u32,shape:Syntax,catalog:Catalog,memo:MemoOwner}
fn appendMember(members:Scratch_u8___&,name:const u8[:])->Error {for member in members.items {if member==name {return Error.none;}}let owned=copyOwned(name);let error=members.push(owned);if error!=Error.none {releaseOwned(owned);}return error;}
recursive fn appendSchemeMembers(members:Scratch_u8___&,scheme:blot_check_types::Scheme,obligations:const blot_check_types::Obligation[:],catalog:Catalog,budget:i64&,implementations:bool&)->bool,Error {
 if budget==0 || scheme.generative.len!=0 {return false,Error.none;}budget-=1;
 for predicate in obligations[scheme.obligations.start..scheme.obligations.start+scheme.obligations.len] {
 if supportedPredicate(predicate) || declaredPredicate(predicate) || operationPredicate(predicate,catalog) {if predicate.name!=0 {let error=appendMember(members,catalog.pool.get(predicate.name));if error!=Error.none {return false,error;}}}
 else if contractPredicate(predicate,catalog) {implementations=true;}
 else if sharedPredicate(predicate,catalog.unit) {if !catalog.values.present || predicate.identity.decl>=catalog.values.value.bindings.len {return false,Error.none;}let accepted,error=appendSchemeMembers(members,catalog.values.value.bindings[predicate.identity.decl].scheme,obligations,catalog,budget,implementations);if error!=Error.none || !accepted {return false,error;}}
 else {return false,Error.none;}}
 return true,Error.none;
}
fn captureBody(tree:const Tree&,pool:const Pool&,text:const u8[:],checked:const blot_check_check::Checked&,root:u32,shape:Syntax,names:blot_support::Option<ExternalNames>,annotations:blot_support::Option<AnnotationLookup>)->blot_support::Option<Body>,Error {
 if unretainedFacts() {return blot_support::none<Body>(),Error.none;}
 for id in shape.ids {if tree.node(id).tag==blot_parse_ast::tag_function_return_stmt {return blot_support::none<Body>(),Error.none;}}
 let auxiliary,error=blot_reuse_body_auxiliary::capture(checked,shape.ids);if error!=Error.none {if error==Error.out_of_memory {return blot_support::none<Body>(),error;}return blot_support::none<Body>(),Error.none;}
 let value,error=initMemoOwner();if error!=Error.none {let owner .= auxiliary;if owner {owner.deinit();}return blot_support::none<Body>(),error;}var memo=value;
 let catalog=Catalog{private:blot_support::some(PrivateFacts{tree:tree,checked:checked,ids:shape.ids}),recipes:memo.borrow(),implementation_read:memo.implementationRead(),unit:checked.unit,pool:pool,nominals:checked.nominals,constructors:checked.constructors,effect_families:checked.effect_families,effect_templates:checked.effect_templates,contracts:checked.contracts,contract_members:checked.contract_members,contract_predicates:checked.contract_predicates,implementations:checked.implementations,implementation_members:checked.implementation_members,implementation_predicates:checked.implementation_predicates,patterns:blot_support::some(blot_check_frozen_types::Patterns.store{checked.parameter_patterns}),values:blot_support::some(Values{bindings:checked.bindings,tree:tree,names:names,annotations:annotations,proof_contracts:checked.proof_contracts,capability_contracts:checked.capability_contracts})};
 var context=CaptureEnvironment{tree,pool,text,checked,root,shape,catalog,memo};var scratch=CaptureScratch{};var result=Body{};
 let error=captureBodyInto(context,scratch,auxiliary,result);scratch.deinit();memo.deinit();
 if error!=Error.none {let owner .= auxiliary;if owner {owner.deinit();}if error==Error.dependency_limit {return blot_support::none<Body>(),Error.none;}return blot_support::none<Body>(),error;}
 return blot_support::some(result),Error.none;
}
fn require(condition:bool)->Error {if !condition {return Error.dependency_limit;}return Error.none;}
fn proveType(source:Source,ty:u32,catalog:Catalog)->i64,Error {var proof=blot_support_blake3::init();var budget:i64=4096;if !typeHash(source,ty,proof,budget,0,true,[],[],catalog) {return 0,Error.dependency_limit;}return 4096-budget,Error.none;}
fn captureBodyInto(context:CaptureEnvironment&,scratch:CaptureScratch&,auxiliary:blot_reuse_body_auxiliary::Owner?,result:Body&)->Error {
 let tree .= context.tree;let pool .= context.pool;let checked .= context.checked;let shape=context.shape;let catalog=context.catalog;let source=Source.store{checked.types};let root=context.root;
 let source_nodes,present=tree.declaration_nodes(root);{ let propagated_error = require(present); if propagated_error != Error.none { return propagated_error; } }
 var effect_heads:bool[4096]=default<bool[4096]>();
 for id in shape.ids {let node=tree.node(id);if node.tag!=blot_parse_ast::tag_effect_row {continue;}for label in tree.list(blot_parse_ast::List{node.a,node.b}) {var head=label;var budget:i64=128;while tree.node(head).tag==blot_parse_ast::tag_type_apply && budget!=0 {head=tree.node(head).a;budget-=1;}{ let propagated_error = require(budget!=0 || tree.node(head).tag!=blot_parse_ast::tag_type_apply); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = require(head>=source_nodes.start && head-source_nodes.start<source_nodes.len); if propagated_error != Error.none { return propagated_error; } }effect_heads[head-source_nodes.start]=true;}}
 let global=checked.resolved[root];for template in checked.member_templates {{ let propagated_error = require(template.binding!=global); if propagated_error != Error.none { return propagated_error; } }}
 let span=tree.span(root);let implementation_selection .= context.memo.implementationRead();
 for use in checked.selected_uses {let selected=tree.span(use.source);if selected.start<span.start || selected.end>span.end {continue;}if tree.node(use.source).tag!=blot_parse_ast::tag_name {var owned=false;for selection in checked.dictionary_selections {if selection.source!=use.source {continue;}match selection.proof {blot_check_check::DictionaryProof.selected payload=>{if payload.value==use.proof {owned=true;break;}},_=>{}}}{ let propagated_error = require(owned); if propagated_error != Error.none { return propagated_error; } }}implementation_selection=true;}
 { let propagated_error = require(global!=0 && interfaceDigest(source,checked.bindings[global],checked.obligations,catalog).present); if propagated_error != Error.none { return propagated_error; } }
 let principal=checked.bindings[global].scheme;
 for predicate in checked.obligations[principal.obligations.start..principal.obligations.start+principal.obligations.len] {
 { let propagated_error = require(supportedPredicate(predicate) || declaredPredicate(predicate) || sharedPredicate(predicate,checked.unit) || contractPredicate(predicate,catalog) || operationPredicate(predicate,catalog)); if propagated_error != Error.none { return propagated_error; } }
 if predicate.explicit && tree.node(predicate.source).tag==blot_parse_ast::tag_constraint {{ let propagated_error = require(position(shape.ids,predicate.source).present); if propagated_error != Error.none { return propagated_error; } }continue;}
 let target=instantiatedReference(tree,checked,predicate);if target!=0 {{ let propagated_error = require(predicate.kind!=blot_check_types::ObligationKind.callee_use || checked.bindings[target].kind==blot_check_check::Kind.local || forwardsShared(checked,target,predicate.identity)); if propagated_error != Error.none { return propagated_error; } }continue;}
 let at=position(shape.ids,predicate.source);{ let propagated_error = require(at.present); if propagated_error != Error.none { return propagated_error; } }var value=predicate;value.name=0;value.source=0;let name=copyOwned(pool.get(predicate.name));let error=scratch.predicates.push(Predicate{value:value,position:at.value,name:name});if error!=Error.none {releaseOwned(name);return error;}
 }
 var type_work:i64=0;let scope=checked.bindings[global].declaration;
 for covered in checked.covered_requirements {if covered.scope!=scope {continue;}let predicate=covered.value;if instantiatedReference(tree,checked,predicate)!=0 {continue;}{ let propagated_error = require(!predicate.qualification_span.present && predicate.qualification_unit==0); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = require(supportedPredicate(predicate) || contractPredicate(predicate,catalog) || operationPredicate(predicate,catalog)); if propagated_error != Error.none { return propagated_error; } }let at=position(shape.ids,predicate.source);{ let propagated_error = require(at.present); if propagated_error != Error.none { return propagated_error; } }
 for part in [predicate.ty,predicate.other,predicate.result,predicate.signature] {let work,error=proveType(source,part,catalog);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }type_work+=work;}
 var value=predicate;value.name=0;value.source=0;let name=copyOwned(pool.get(predicate.name));let error=scratch.predicates.push(Predicate{value:value,position:at.value,name:name,covered:true});if error!=Error.none {releaseOwned(name);return error;}}
 let auxiliary_owner .= auxiliary;if auxiliary_owner && auxiliary_owner.selections.len!=0 {implementation_selection=true;}
 var needs_selection=false;
 for predicate in scratch.predicates.items {if predicate.name.len==0 || predicate.covered {continue;}if predicate.value.kind!=blot_check_types::ObligationKind.dispatch && predicate.value.kind!=blot_check_types::ObligationKind.result_dispatch {needs_selection=true;}{ let propagated_error = appendMember(scratch.members,predicate.name); if propagated_error != Error.none { return propagated_error; } }}
 for id,at in shape.ids {
 let path=checked.types.list(checked.access_paths[id]);
 if path.len!=0 {
 { let propagated_error = require(tree.node(id).tag==blot_parse_ast::tag_name && checked.access_nodes[id].len==0 && path.len<=128 && path.len<=4096-scratch.accesses.items.len); if propagated_error != Error.none { return propagated_error; } }
 let types=checked.types.list(checked.access_types[id]);{ let propagated_error = require(types.len==path.len+1); if propagated_error != Error.none { return propagated_error; } }for ty in types {let ignored,error=proveType(source,ty,catalog);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }}
 for projection,index in path {{ let propagated_error = require(projection<checked.projection_catalog.len); if propagated_error != Error.none { return propagated_error; } }let step=checked.projection_catalog[projection];let variants=checked.types.list(step.variants);{ let propagated_error = require(variants.len%2==0 && variants.len/2<=4096-scratch.field_tags.items.len && pool.get(step.field).len!=0); if propagated_error != Error.none { return propagated_error; } }
 if variants.len==0 {needs_selection=true;{ let propagated_error = appendMember(scratch.members,pool.get(step.field)); if propagated_error != Error.none { return propagated_error; } }}
 let start=scratch.field_tags.items.len as u32;for offset in variants.len/2 {{ let propagated_error = scratch.field_tags.push(variants[offset*2]); if propagated_error != Error.none { return propagated_error; } }}{ let propagated_error = scratch.accesses.push(Access{position:at as u32,ty:types[index],nominal:step.nominal,field:step.field,tags:List{start,(variants.len/2) as u32}}); if propagated_error != Error.none { return propagated_error; } }
 }}
 let field_id=checked.projection_resolved[id];if field_id!=0 {{ let propagated_error = require(tree.node(id).tag==blot_parse_ast::tag_field_access); if propagated_error != Error.none { return propagated_error; } }let field=checked.projection_catalog[field_id];let variants=checked.types.list(field.variants);{ let propagated_error = require(variants.len%2==0 && variants.len/2<=4096-scratch.field_tags.items.len); if propagated_error != Error.none { return propagated_error; } }
 if variants.len==0 {{ let propagated_error = require(field.field==tree.node(id).b); if propagated_error != Error.none { return propagated_error; } }needs_selection=true;{ let propagated_error = appendMember(scratch.members,pool.get(field.field)); if propagated_error != Error.none { return propagated_error; } }}
 let start=scratch.field_tags.items.len as u32;for offset in variants.len/2 {{ let propagated_error = scratch.field_tags.push(variants[offset*2]); if propagated_error != Error.none { return propagated_error; } }}{ let propagated_error = scratch.fields.push(FieldProjection{at as u32,field.nominal,List{start,(variants.len/2) as u32}}); if propagated_error != Error.none { return propagated_error; } }
 }
 let constructor_id=checked.constructor_resolved[id];if constructor_id!=0 {let constructor=checked.constructors[constructor_id];let nominal=checked.nominals[constructor.nominal];{ let propagated_error = require(nominalDigest(source,catalog,constructor.nominal).present); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = scratch.constructors.push(Constructor{at as u32,nominal.identity,constructor.tag}); if propagated_error != Error.none { return propagated_error; } }}
 if tree.node(id).tag==blot_parse_ast::tag_string {{ let propagated_error = appendMember(scratch.members,pool.get(tree.node(id).a)); if propagated_error != Error.none { return propagated_error; } }}
 if tree.node(id).tag==blot_parse_ast::tag_constraint && pool.get(tree.node(id).a)=="associated" {needs_selection=true;{ let propagated_error = appendMember(scratch.members,pool.get(tree.node(id).b)); if propagated_error != Error.none { return propagated_error; } }}
 if checked.dispatch_signatures[id]!=0 {needs_selection=true;{ let propagated_error = scratch.signatures.push(Signature{at as u32,checked.dispatch_signatures[id]}); if propagated_error != Error.none { return propagated_error; } }}
 let ty=checked.expr_types[id];let work,error=proveType(source,ty,catalog);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }type_work+=work;
 if tree.node(id).tag==blot_parse_ast::tag_effect_row {let digest=effectAnnotationDigest(source,catalog,tree,id);{ let propagated_error = require(digest.present); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = scratch.type_reads.push(TypeRead{at as u32,digest.value,true}); if propagated_error != Error.none { return propagated_error; } }}
 if tree.node(id).tag==blot_parse_ast::tag_type_name && !effect_heads[id-source_nodes.start] {let name=pool.get(tree.node(id).a);var dotted=false;for byte in name {if byte=='.' as u8 {dotted=true;break;}}let variable=name.len!=0 && ((name[0]>='a' as u8 && name[0]<='z' as u8) || name[0]=='_' as u8) && !dotted;
 if !variable && name!="U32" && name!="F32" && name!="Bool" && name!="Unit" && name!="Array" && name!="List" {let digest=annotationDigest(source,catalog,name);{ let propagated_error = require(digest.present); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = scratch.type_reads.push(TypeRead{at as u32,digest.value,false}); if propagated_error != Error.none { return propagated_error; } }}}
 if checked.projections[id]!=0xffffffff {var owner:u32=0;if tree.node(id).tag==blot_parse_ast::tag_pattern_field {for parent,parent_position in shape.ids {if tree.node(parent).tag==blot_parse_ast::tag_pattern_record && position(tree.children(parent),id).present {owner=(parent_position+1) as u32;break;}}{ let propagated_error = require(owner!=0); if propagated_error != Error.none { return propagated_error; } }}{ let propagated_error = scratch.projections.push(Projection{at as u32,checked.projections[id],owner}); if propagated_error != Error.none { return propagated_error; } }}
 var fact=Fact{ty:ty};let rows=checked.types.list(checked.lambda_closed_rows[id]);fact.closed_rows=List{scratch.closed_rows.items.len as u32,rows.len as u32};{ let propagated_error = scratch.closed_rows.append(rows); if propagated_error != Error.none { return propagated_error; } }
 let old_id=checked.resolved[id];if old_id!=0 && old_id!=global {let old=checked.bindings[old_id];if old.kind!=blot_check_check::Kind.local && old.kind!=blot_check_check::Kind.parameter && !position(scratch.old_bindings.items,old_id).present && old.scheme.obligations.len!=0 {needs_selection=true;var member_budget:i64=64;let accepted,error=appendSchemeMembers(scratch.members,old.scheme,checked.obligations,catalog,member_budget,implementation_selection);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = require(accepted); if propagated_error != Error.none { return propagated_error; } }}
 let binding,error=captureRead(context,scratch,old_id);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = require(binding.present); if propagated_error != Error.none { return propagated_error; } }fact.binding=binding.value;
 }else {{ let propagated_error = require(old_id!=global || id==root); if propagated_error != Error.none { return propagated_error; } }}
 { let propagated_error = scratch.facts.push(fact); if propagated_error != Error.none { return propagated_error; } }
 }
 for predicate in scratch.predicates.items {if predicate.value.kind!=blot_check_types::ObligationKind.callee_use {continue;}let target=predicate.value.identity.decl;let read,error=captureRead(context,scratch,target);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = require(read.present); if propagated_error != Error.none { return propagated_error; } }needs_selection=true;var member_budget:i64=64;let accepted,error=appendSchemeMembers(scratch.members,checked.bindings[target].scheme,checked.obligations,catalog,member_budget,implementation_selection);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = require(accepted); if propagated_error != Error.none { return propagated_error; } }}
 for merge in checked.merges {let at=position(shape.ids,merge.node);if !at.present {continue;}let result,error=captureLocal(context,scratch,merge.result);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }let yes,error=captureLocal(context,scratch,merge.then_binding);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }let no,error=captureLocal(context,scratch,merge.else_binding);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = require(result.present && yes.present && no.present); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = scratch.merges.push(Merge{at.value,result.value,yes.value,no.value}); if propagated_error != Error.none { return propagated_error; } }}
 for id,at in shape.ids {let tag=tree.node(id).tag;if tag!=blot_parse_ast::tag_for_stmt && tag!=blot_parse_ast::tag_range_stmt && tag!=blot_parse_ast::tag_forever_stmt {continue;}let carries=checked.loop_ranges[id];{ let propagated_error = require(carries.len<=4096-scratch.loop_carries.items.len); if propagated_error != Error.none { return propagated_error; } }
 for carry in checked.loop_carries[carries.start..carries.start+carries.len] {{ let propagated_error = require(carry.node==id); if propagated_error != Error.none { return propagated_error; } }let incoming,error=captureLocal(context,scratch,carry.incoming);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }let iteration,error=captureLocal(context,scratch,carry.iteration);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }let backedge,error=captureLocal(context,scratch,carry.backedge);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }let outgoing,error=captureLocal(context,scratch,carry.outgoing);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = require(incoming.present && iteration.present && backedge.present && outgoing.present); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = scratch.loop_carries.push(LoopCarry{at as u32,incoming.value,iteration.value,backedge.value,outgoing.value}); if propagated_error != Error.none { return propagated_error; } }}}
 for exit in checked.loop_exits {let at=position(shape.ids,exit.node);if !at.present {continue;}let target=position(shape.ids,exit.loop);{ let propagated_error = require(target.present); if propagated_error != Error.none { return propagated_error; } }let current=checked.types.list(exit.bindings);{ let propagated_error = require(scratch.loop_exits.items.len!=4096 && current.len<=4096-scratch.exit_bindings.items.len); if propagated_error != Error.none { return propagated_error; } }let start=scratch.exit_bindings.items.len as u32;for binding in current {let value,error=captureLocal(context,scratch,binding);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = require(value.present); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = scratch.exit_bindings.push(value.value); if propagated_error != Error.none { return propagated_error; } }}{ let propagated_error = scratch.loop_exits.push(LoopExit{at.value,target.value,List{start,current.len as u32}}); if propagated_error != Error.none { return propagated_error; } }}
 for id,at in shape.ids {let update=checked.rebindings[id];if update.path.len==0 {continue;}{ let propagated_error = require(tree.node(id).tag==blot_parse_ast::tag_rebind_stmt && update.path.len<=128 && scratch.rebindings.items.len!=4096); if propagated_error != Error.none { return propagated_error; } }let nodes=checked.types.list(checked.access_nodes[id]);let types=checked.types.list(checked.access_types[id]);{ let propagated_error = require(nodes.len==update.path.len && types.len==nodes.len+1); if propagated_error != Error.none { return propagated_error; } }var current=tree.node(id).a;var remaining=nodes.len;
 while remaining!=0 {remaining-=1;{ let propagated_error = require(nodes[remaining]==current && position(shape.ids,current).present); if propagated_error != Error.none { return propagated_error; } }let selector=tree.node(current);{ let propagated_error = require(selector.tag==blot_parse_ast::tag_field_access || selector.tag==blot_parse_ast::tag_index_access); if propagated_error != Error.none { return propagated_error; } }let same,error=blot_reuse_principal_type_graph::sameOpen(checked.types,checked.expr_types[current],types[remaining+1],128,4096);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = require(same); if propagated_error != Error.none { return propagated_error; } }current=selector.a;}
 { let propagated_error = require(tree.node(current).tag==blot_parse_ast::tag_name && position(shape.ids,current).present); if propagated_error != Error.none { return propagated_error; } }let same,error=blot_reuse_principal_type_graph::sameOpen(checked.types,checked.expr_types[current],types[0],128,4096);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = require(same); if propagated_error != Error.none { return propagated_error; } }let root_binding,error=captureLocal(context,scratch,update.root);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }let self_binding,error=captureLocal(context,scratch,update.self_binding);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = require(root_binding.present && self_binding.present); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = scratch.rebindings.push(Rebinding{at as u32,root_binding.value,self_binding.value}); if propagated_error != Error.none { return propagated_error; } }
 }
 if auxiliary_owner {var mapper=AuxiliaryBindings{context:context,scratch:scratch};let error=auxiliary_owner.transform(mapper);if error!=Error.none {if error==Error.out_of_memory {return error;}return Error.dependency_limit;}
 for node,id in checked.types.nodes.items {if node.tag!=blot_check_types::Tag.instance_version {continue;}let version=catalog.private.value.version(id as u32);if !version.present || version.value.kind!=PrivateVersionKind.binding {continue;}let read,error=captureRead(context,scratch,version.value.operand);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = require(read.present); if propagated_error != Error.none { return propagated_error; } }}}
 var semantic_index:i64=0;while semantic_index<scratch.old_bindings.items.len {let binding=checked.bindings[scratch.old_bindings.items[semantic_index]];semantic_index+=1;if binding.kind!=blot_check_check::Kind.local {continue;}for predicate in checked.obligations[binding.scheme.obligations.start..binding.scheme.obligations.start+binding.scheme.obligations.len] {if !sharedPredicate(predicate,checked.unit) {continue;}let read,error=captureRead(context,scratch,predicate.identity.decl);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = require(read.present); if propagated_error != Error.none { return propagated_error; } }}}
 { let propagated_error = orderBindings(scratch.bindings.items,scratch.old_bindings.items,scratch.facts.items,scratch.merges.items,scratch.loop_carries.items,scratch.exit_bindings.items,scratch.rebindings.items); if propagated_error != Error.none { return propagated_error; } }
 if auxiliary_owner {var mapper=AuxiliaryBindingSlots{scratch.old_bindings.items};{ let propagated_error = auxiliary_owner.transform(mapper); if propagated_error != Error.none { return propagated_error; } }var operation_bindings:blot_reuse_body_auxiliary::OperationBinding[>..<]=[];for origin,slot in scratch.old_bindings.items {let old=checked.bindings[origin];if old.kind!=blot_check_check::Kind.parameter && old.kind!=blot_check_check::Kind.local {continue;}if old.operation_ref==0 {continue;}let operation,error=blot_reuse_body_auxiliary::index_operation_uses(checked,shape.ids,old.operation_ref);if error!=Error.none {return Error.dependency_limit;}operation_bindings.push(blot_reuse_body_auxiliary::OperationBinding{(slot+1) as u32,operation});}auxiliary_owner.operation_bindings=blot_reuse_body_auxiliary::copyOwned(operation_bindings[:]);auxiliary_owner.binding_origins=blot_reuse_body_auxiliary::copyOwned(scratch.old_bindings.items);}
 for old_id,index in scratch.old_bindings.items {let predecessor=checked.bindings[old_id].predecessor;if predecessor!=0 {let slot=position(scratch.old_bindings.items,predecessor);{ let propagated_error = require(slot.present); if propagated_error != Error.none { return propagated_error; } }scratch.bindings.items[index].predecessor=slot.value+1;}}
 for &predicate in scratch.predicates.items {if predicate.value.kind!=blot_check_types::ObligationKind.callee_use {continue;}let target=position(scratch.old_bindings.items,predicate.value.identity.decl);{ let propagated_error = require(target.present); if propagated_error != Error.none { return propagated_error; } }predicate.value.identity=Identity{0,target.value+1};}
 var local_requirement_budget:i64=4096;
 for id,index in scratch.old_bindings.items {let old=checked.bindings[id];if old.kind!=blot_check_check::Kind.local || (old.scheme.variables.len==0 && old.scheme.row_variables.len==0 && old.scheme.closed_rows.len==0 && old.scheme.obligations.len==0 && old.scheme.generative.len==0) {continue;}
 { let propagated_error = require(old.scheme.obligations.len<=4096-scratch.predicates.items.len); if propagated_error != Error.none { return propagated_error; } }if old.scheme.obligations.len!=0 {needs_selection=true;var member_budget:i64=64;let accepted,error=appendSchemeMembers(scratch.members,old.scheme,checked.obligations,catalog,member_budget,implementation_selection);{ let propagated_error = error; if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = require(accepted); if propagated_error != Error.none { return propagated_error; } }}
 var local=old.scheme;local.obligations=List{scratch.predicates.items.len as u32,old.scheme.obligations.len};
 for predicate in checked.obligations[old.scheme.obligations.start..old.scheme.obligations.start+old.scheme.obligations.len] {
 { let propagated_error = require((supportedPredicate(predicate) || declaredPredicate(predicate) || sharedPredicate(predicate,checked.unit) || contractPredicate(predicate,catalog) || operationPredicate(predicate,catalog)) && local_requirement_budget!=0); if propagated_error != Error.none { return propagated_error; } }
 let synthetic_contract=predicate.kind==blot_check_types::ObligationKind.contract && !predicate.qualification_span.present && predicate.qualification_unit==0;
 if predicate.explicit && !synthetic_contract {{ let propagated_error = require(predicate.qualification_span.present); if propagated_error != Error.none { return propagated_error; } }let origin=predicate.qualification_span.value;{ let propagated_error = require(predicate.qualification_unit==checked.unit && origin.start>=span.start && origin.end<=span.end && origin.start<=origin.end); if propagated_error != Error.none { return propagated_error; } }}
 local_requirement_budget-=1;let at=position(shape.ids,predicate.source);{ let propagated_error = require(at.present); if propagated_error != Error.none { return propagated_error; } }var proof=blot_support_blake3::init();for part in [predicate.ty,predicate.other,predicate.result,predicate.signature] {{ let propagated_error = require(typeHash(source,part,proof,local_requirement_budget,0,true,[],[],catalog)); if propagated_error != Error.none { return propagated_error; } }}
 var identity=predicate.identity;if predicate.kind==blot_check_types::ObligationKind.callee_use {let target=position(scratch.old_bindings.items,predicate.identity.decl);{ let propagated_error = require(target.present); if propagated_error != Error.none { return propagated_error; } }let kind=scratch.bindings.items[target.value].kind;{ let propagated_error = require(kind==blot_check_check::Kind.global || kind==blot_check_check::Kind.external); if propagated_error != Error.none { return propagated_error; } }identity=Identity{0,target.value+1};}
 var value=predicate;value.identity=identity;value.name=0;value.source=0;if value.qualification_span.present {var origin=value.qualification_span.value;origin.start-=span.start;origin.end-=span.start;value.qualification_span=blot_support::some(origin);value.qualification_unit=0;}
 let name=copyOwned(pool.get(predicate.name));let error=scratch.predicates.push(Predicate{value:value,position:at.value,name:name,local:true});if error!=Error.none {releaseOwned(name);return error;}
 }{ let propagated_error = scratch.local_schemes.push(LocalScheme{(index+1) as u32,local}); if propagated_error != Error.none { return propagated_error; } }
 }
 var selection_digest=blot_support::none<Digest>();if implementation_selection {needs_selection=true;for requirements in [checked.contract_predicates,checked.implementation_predicates] {for predicate in requirements {if predicate.kind==blot_check_types::ObligationKind.dispatch || predicate.kind==blot_check_types::ObligationKind.result_dispatch {{ let propagated_error = appendMember(scratch.members,pool.get(predicate.name)); if propagated_error != Error.none { return propagated_error; } }}}}}
 if needs_selection {selection_digest=associatedDigest(source,catalog,tree,checked.associated,checked.bindings,checked.obligations,catalog.values.value.names,scratch.members.items);{ let propagated_error = require(selection_digest.present); if propagated_error != Error.none { return propagated_error; } }}
 if implementation_selection {selection_digest=implementationDigest(source,catalog,selection_digest.value);{ let propagated_error = require(selection_digest.present); if propagated_error != Error.none { return propagated_error; } }}
 let body_row_start=scratch.closed_rows.items.len as u32;for row in checked.body_closed_rows {if row.owner==global {{ let propagated_error = scratch.closed_rows.push(row.variable); if propagated_error != Error.none { return propagated_error; } }}}
 let body_rows=List{body_row_start,(scratch.closed_rows.items.len-body_row_start) as u32};
 var loops:Loops?=null;if scratch.loop_carries.items.len!=0 || scratch.loop_exits.items.len!=0 || scratch.exit_bindings.items.len!=0 {let at=loop_owners.alloc_index(Loops{carries:copyOwned(scratch.loop_carries.items),exits:copyOwned(scratch.loop_exits.items),bindings:copyOwned(scratch.exit_bindings.items),live:true});loops .= loop_owners[at];}
 result=Body{auxiliary:auxiliary,name:copyOwned(pool.get(tree.value_decl(root).name)),source:copyOwned(context.text[span.start..span.end]),syntax:shape.digest,facts:copyOwned(scratch.facts.items),bindings:copyOwned(scratch.bindings.items),closed_rows:copyOwned(scratch.closed_rows.items),body_closed_rows:body_rows,type_work:type_work,type_reads:copyOwned(scratch.type_reads.items),predicates:copyOwned(scratch.predicates.items),signatures:copyOwned(scratch.signatures.items),projections:copyOwned(scratch.projections.items),merges:copyOwned(scratch.merges.items),loops:loops,rebindings:copyOwned(scratch.rebindings.items),constructors:copyOwned(scratch.constructors.items),local_schemes:copyOwned(scratch.local_schemes.items),fields:copyOwned(scratch.fields.items),accesses:copyOwned(scratch.accesses.items),field_tags:copyOwned(scratch.field_tags.items),members:copyOwned(scratch.members.items),selection_digest:selection_digest,implementation_selection:implementation_selection};
 // String runs transfer to the immutable body; only scratch capacity remains.
 scratch.bindings.items=scratch.bindings.storage[..0];scratch.predicates.items=scratch.predicates.storage[..0];scratch.members.items=scratch.members.storage[..0];return Error.none;
}
