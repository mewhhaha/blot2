// Exact per-body reachable payload and identity reads within an immutable chunk.
namespace blot_reuse_body_check_cache;
import .body_check_cache;
struct AuxiliaryReads {source:Source,pending:u32[>..<]&,reads:u32[>..<]&,nominals:const IdentityRead[:],bytes:i64=0}
fn addRead(self:AuxiliaryReads&,index:u32)->Error {if index>=self.nominals.len {return Error.dependency_limit;}if !position(self.reads[:],index).present {self.reads.push(index);self.bytes+=identity_read_footprint+self.nominals[index].name.len;}return Error.none;}
fn label(self:AuxiliaryReads&,id:u32)->Error {
 if id==0 || id==blot_check_types::foreign_operation {return Error.none;}if id>=self.source.operationCount() {return Error.dependency_limit;}let operation=self.source.operation(id);if operation.identity.unit==0 || operation.identity.unit>self.nominals.len {return Error.dependency_limit;}let index=operation.identity.unit-1;if self.nominals[index].kind!=NominalKind.operation {return Error.dependency_limit;}
 let error=self.addRead(index);if error!=Error.none {return error;}self.bytes+=operation_footprint+operation.arguments.len*4;self.pending.append(self.source.list(operation.arguments));if operation.instance.unit==0 && operation.instance.decl!=0 {self.pending.push(operation.instance.decl);}return Error.none;
}
fn map_ty(self:AuxiliaryReads&,value:u32)->u32,Error {self.pending.push(value);return value,Error.none;}
fn map_label(self:AuxiliaryReads&,value:u32)->u32,Error {let error=self.label(value);return value,error;}
fn map_row(self:AuxiliaryReads&,value:u32)->u32,Error {let row=self.source.row(value);self.bytes+=effect_row_footprint+row.labels.len*4;for operation in self.source.rowLabels(row.labels) {let error=self.label(operation);if error!=Error.none {return 0,error;}}return value,Error.none;}
struct BodyReads {nominals:u32[:]=[],bytes:i64=0}
fn bodyReads(graph:const blot_check_frozen_types::Graph&,body:const Body&,names:const u8[:][:],nominals:const IdentityRead[:])->BodyReads,Error {
 var pending:u32[>..<]=[];var reads:u32[>..<]=[];var mapper=AuxiliaryReads{Source.frozen{graph},pending,reads,nominals};let error=bodyReadsInto(body,names,mapper);if error!=Error.none {return BodyReads{},error;}return BodyReads{copyOwned(reads[:]),mapper.bytes},Error.none;
}
fn bodyReadsInto(body:const Body&,names:const u8[:][:],mapper:AuxiliaryReads&)->Error {
 let source=mapper.source;
 for fact in body.facts {mapper.pending.push(fact.ty);}for binding in body.bindings {mapper.pending.push(binding.ty);}for signature in body.signatures {mapper.pending.push(signature.ty);}for access in body.accesses {mapper.pending.push(access.ty);}
 for local in body.local_schemes {mapper.pending.push(local.principal.root);mapper.pending.append(source.list(local.principal.variables));mapper.pending.append(source.list(local.principal.generative));}
 for predicate in body.predicates {mapper.pending.append([predicate.value.ty,predicate.value.other,predicate.value.result,predicate.value.signature]);}
 let owner .= body.auxiliary;if owner {{ let propagated_error = owner.transform(mapper); if propagated_error != Error.none { return propagated_error; } }for index in owner.dependencies {{ let propagated_error = mapper.addRead(index); if propagated_error != Error.none { return propagated_error; } }}}
 var budget:i64=16384;for local in body.local_schemes {mapper.bytes+=(local.principal.variables.len+local.principal.row_variables.len+local.principal.closed_rows.len+local.principal.generative.len)*4;}
 var seen=dictionary<u32,bool>{};while mapper.pending.len!=0 {let id=mapper.pending.pop();{ let propagated_error = require(budget!=0 && mapper.pending.len<=16384); if propagated_error != Error.none { return propagated_error; } }budget-=1;{ let propagated_error = require(seen.count<4096); if propagated_error != Error.none { return propagated_error; } }if seen.contains(id) {continue;}seen.insert(id,true);let node=source.node(id);mapper.bytes+=type_node_footprint;
 match node.tag {
 blot_check_types::Tag.nominal,blot_check_types::Tag.projection=>{
  let arguments=source.nominalArguments(node);if node.tag==blot_check_types::Tag.nominal && blot_check_types::compilerNominalArity(Identity{node.a,node.b}).present {mapper.pending.append(arguments);mapper.bytes+=(arguments.len+1)*4;continue;}
  { let propagated_error = mapper.addRead(node.a-1); if propagated_error != Error.none { return propagated_error; } }mapper.bytes+=(arguments.len+1)*4;if node.tag==blot_check_types::Tag.projection {mapper.bytes+=4+16+names[source.projectionMember(node)].len;}mapper.pending.append(arguments);
 },
 blot_check_types::Tag.type_constructor=>{{ let propagated_error = mapper.addRead(node.a-1); if propagated_error != Error.none { return propagated_error; } }},
 blot_check_types::Tag.function,blot_check_types::Tag.provider=>{
  let row=source.row(node.c);mapper.bytes+=effect_row_footprint+row.labels.len*4;for label in source.rowLabels(row.labels) {{ let propagated_error = require(budget!=0); if propagated_error != Error.none { return propagated_error; } }budget-=1;if label==blot_check_types::foreign_operation {continue;}{ let propagated_error = require(label!=0 && label<source.operationCount()); if propagated_error != Error.none { return propagated_error; } }let operation=source.operation(label);{ let propagated_error = require(operation.identity.unit!=0); if propagated_error != Error.none { return propagated_error; } }let index=operation.identity.unit-1;{ let propagated_error = require(index<mapper.nominals.len && mapper.nominals[index].kind==NominalKind.operation); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = mapper.addRead(index); if propagated_error != Error.none { return propagated_error; } }mapper.bytes+=operation_footprint+operation.arguments.len*4;{ let propagated_error = require(operation.arguments.len<=max(16384-mapper.pending.len,0)); if propagated_error != Error.none { return propagated_error; } }mapper.pending.append(source.list(operation.arguments));if operation.instance.unit==0 && operation.instance.decl!=0 {mapper.pending.push(operation.instance.decl);}}
  mapper.pending.push(node.a);if node.tag==blot_check_types::Tag.function {mapper.pending.push(node.b);}
 },
 blot_check_types::Tag.product=>{mapper.bytes+=node.b*4;mapper.pending.append(source.list(List{node.a,node.b}));},
 blot_check_types::Tag.record=>{for index in node.b {let field=source.recordField(node,index);mapper.bytes+=8+16+names[field.name].len;mapper.pending.push(field.ty);}},
 blot_check_types::Tag.scoped=>{mapper.pending.push(node.a);if node.b==0 {mapper.pending.push(node.c);}},
 blot_check_types::Tag.instance_selection=>{mapper.pending.append(source.nominalArguments(node));},
 blot_check_types::Tag.forall,blot_check_types::Tag.existential=>{mapper.pending.push(node.a);mapper.pending.append(source.list(List{node.b,node.c}));mapper.bytes+=node.c*4;for goal in source.quantifierGoals(id) {mapper.pending.append([goal.ty,goal.other,goal.result,goal.signature]);if goal.kind==blot_check_types::ObligationKind.contract || goal.kind==blot_check_types::ObligationKind.effect_operation {{ let propagated_error = require(goal.identity.unit!=0 && goal.identity.unit<=mapper.nominals.len); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = mapper.addRead(goal.identity.unit-1); if propagated_error != Error.none { return propagated_error; } }}}},
 blot_check_types::Tag.state_provider=>{mapper.pending.append([node.a,node.b,node.c]);},
 blot_check_types::Tag.array,blot_check_types::Tag.list,blot_check_types::Tag.cursor,blot_check_types::Tag.resolver,blot_check_types::Tag.usage=>{mapper.pending.push(node.a);},_=>{},
 }}
 for constructor in body.constructors {{ let propagated_error = mapper.addRead(constructor.nominal.unit-1); if propagated_error != Error.none { return propagated_error; } }}for field in body.fields {if field.nominal.unit!=0 {{ let propagated_error = mapper.addRead(field.nominal.unit-1); if propagated_error != Error.none { return propagated_error; } }}}for predicate in body.predicates {if predicate.value.kind==blot_check_types::ObligationKind.contract || predicate.value.kind==blot_check_types::ObligationKind.effect_operation {{ let propagated_error = mapper.addRead(predicate.value.identity.unit-1); if propagated_error != Error.none { return propagated_error; } }}}return Error.none;
}
fn map_node(self:AuxiliaryReads&,value:u32)->u32,Error {return value,Error.none;}
fn map_binding(self:AuxiliaryReads&,value:u32)->u32,Error {return value,Error.none;}
fn map_name(self:AuxiliaryReads&,value:u32)->u32,Error {return value,Error.none;}
fn map_instance(self:AuxiliaryReads&,value:Identity)->Identity,Error {return value,Error.none;}
fn map_scope(self:AuxiliaryReads&,value:u32)->u32,Error {return value,Error.none;}
fn map_constructor(self:AuxiliaryReads&,value:u32)->u32,Error {return value,Error.none;}
fn map_types(self:AuxiliaryReads&,value:List)->List,Error {return value,Error.none;}
fn map_bindings(self:AuxiliaryReads&,value:List)->List,Error {return value,Error.none;}
fn map_request_arms(self:AuxiliaryReads&,value:List)->List,Error {return value,Error.none;}
fn map_resolver_ops(self:AuxiliaryReads&,value:u32)->u32,Error {return value,Error.none;}
fn map_resolver_completions(self:AuxiliaryReads&,value:u32)->u32,Error {return value,Error.none;}
fn map_carries(self:AuxiliaryReads&,value:List)->List,Error {return value,Error.none;}
fn map_template(self:AuxiliaryReads&,value:u32)->u32,Error {return value,Error.none;}
fn map_goal(self:AuxiliaryReads&,value:u32)->u32,Error {return value,Error.none;}
fn map_proof(self:AuxiliaryReads&,value:blot_check_check::DictionaryProof)->blot_check_check::DictionaryProof,Error {return value,Error.none;}
fn map_contract_identity(self:AuxiliaryReads&,value:Identity)->Identity,Error {return value,Error.none;}
fn map_operation_identity(self:AuxiliaryReads&,value:Identity)->Identity,Error {return value,Error.none;}
fn map_callee_identity(self:AuxiliaryReads&,value:Identity)->Identity,Error {return value,Error.none;}
fn map_nodes_pair(self:AuxiliaryReads&,value:u32[2])->u32[2],Error {return value,Error.none;}
fn map_proposition(self:AuxiliaryReads&,value:blot_check_numeric_proof_terms::Proposition)->blot_check_numeric_proof_terms::Proposition,Error {return value,Error.none;}
