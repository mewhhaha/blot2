// Only an explicit private payload owner may renumber retained immutable views.
namespace blot_reuse_dependency_relink;
import std;
import parse.symbols;
import reuse.dependency_payload;
import reuse.frozen_dependency;
import reuse.principal_interface;
import reuse.dependency_symbol_slots;
import check.types;
import check.core;
import check.capability_contracts;
import check.source_sort;
import support.error;
type Error=blot_error::Error;
type Owner=blot_reuse_dependency_payload::Owner;
type Interface=blot_reuse_principal_interface::Interface;
type Module=blot_check_core::Module;
type Identity=blot_check_types::NominalIdentity;
type Slots=blot_reuse_dependency_symbol_slots::Slots;
struct Dictionary {names:const u32[:],units:const u32[:]}
fn symbol(self_:Dictionary,id:u32)->u32 {return self_.names[id];}
fn unit(self_:Dictionary,id:u32)->u32 {if id==0||id==0xffffffff {return id;}return self_.units[id-1];}
struct Retained {units:const u32[:],rejected:bool&}
fn symbol(self_:Retained,id:u32)->u32 {return id;}
fn unit(self_:Retained,id:u32)->u32 {if id==0||id==0xffffffff {return id;}if id<=self_.units.len&&self_.units[id-1]!=0 {return self_.units[id-1];}self_.rejected=true;return id;}
fn identity<M>(map:M,value:Identity&) {value.unit=map.unit(value.unit);if value.unit!=0&&value.unit!=0xffffffff&&value.decl&blot_check_types::opaque_name_bit!=0 {value.decl=blot_check_types::opaque_name_bit|map.symbol(value.decl&~blot_check_types::opaque_name_bit);}}
fn target<M,T>(map:M,value:T&) {value.unit=map.unit(value.unit);}
fn typeUnits<M>(nodes:blot_check_types::Node[:],map:M) {
 for &node in nodes {match node.tag {
  scoped=>{node.b=map.unit(node.b);},
  instance_selection,instance_version=>{node.a=map.unit(node.a);},
  nominal,projection,type_constructor=>{node.a=map.unit(node.a);if node.a!=0&&node.a!=0xffffffff&&node.b&blot_check_types::opaque_name_bit!=0 {node.b=blot_check_types::opaque_name_bit|map.symbol(node.b&~blot_check_types::opaque_name_bit);}},
  _=>{},
 }}
}
fn capabilityNodes<M>(nodes:blot_check_capability_contracts::Term[:],map:M) {for &node in nodes {if node.tag==blot_check_capability_contracts::Tag.project&&node.c==blot_check_capability_contracts::projectionCode(blot_check_capability_contracts::Projection.field) {node.b=map.symbol(node.b);}}}
fn implementations<T,M>(storage:Owner&,owner:T&,map:M) {
 for &value in storage.mutable(owner.implementations) {identity(map,value.identity);identity(map,value.contract);value.name=map.symbol(value.name);}
 for &value in storage.mutable(owner.implementation_members) {value.name=map.symbol(value.name);target(map,value.target);}
 for &value in storage.mutable(owner.member_templates) {identity(map,value.contract);value.name=map.symbol(value.name);}
 for &value in storage.mutable(owner.selected_members) {value.name=map.symbol(value.name);target(map,value.target);}
 for &value in storage.mutable(owner.selected_proofs) {target(map,value.predicate_target);value.context=map.unit(value.context);identity(map,value.implementation);identity(map,value.contract);identity(map,value.predicate.identity);value.predicate.name=map.symbol(value.predicate.name);value.predicate.qualification_unit=map.unit(value.predicate.qualification_unit);}
}
fn predicate<M,P>(map:M,value:P&) {value.name=map.symbol(value.name);identity(map,value.identity);value.qualification_unit=map.unit(value.qualification_unit);}
fn interfaceUnits(storage:Owner&,owner:Interface&,units:const u32[:])->Error {var rejected=false;interfaceWith(storage,owner,Retained {units,rejected, ..});if rejected {return blot_error::Error.invalid_artifact;}return blot_error::Error.none;}
fn interfaceWith<M>(storage:Owner&,owner:Interface&,map:M) {
 capabilityNodes(storage.mutable(owner.capability_contracts.nodes),map);implementations(storage,owner,map);owner.unit=map.unit(owner.unit);typeUnits(storage.mutable(owner.graph.nodes),map);
 for &goal in storage.mutable(owner.graph.quantifier_obligations) {predicate(map,goal);}
 for &operation in storage.mutable(owner.graph.operations) {identity(map,operation.identity);operation.instance.unit=map.unit(operation.instance.unit);}
 for &binding in storage.mutable(owner.bindings) {binding.name=map.symbol(binding.name);if binding.external.present {target(map,binding.external.value);}}
 for &obligation in storage.mutable(owner.obligations) {predicate(map,obligation);}
 for &nominal in storage.mutable(owner.nominals) {identity(map,nominal.identity);nominal.name=map.symbol(nominal.name);}
 for &contract in storage.mutable(owner.contracts) {identity(map,contract.identity);contract.name=map.symbol(contract.name);}
 for &member in storage.mutable(owner.contract_members) {identity(map,member.contract);member.name=map.symbol(member.name);}
 for &value in storage.mutable(owner.contract_predicates) {predicate(map,value);}for &value in storage.mutable(owner.implementation_predicates) {predicate(map,value);}
 for &constructor in storage.mutable(owner.constructors) {identity(map,constructor.identity);constructor.name=map.symbol(constructor.name);}
 for &family in storage.mutable(owner.effect_families) {identity(map,family.identity);family.name=map.symbol(family.name);}
 for &operation in storage.mutable(owner.effect_templates) {identity(map,operation.identity);operation.name=map.symbol(operation.name);}
 for &method in storage.mutable(owner.associated) {identity(map,method.identity);method.member=map.symbol(method.member);}
}
struct FieldOrder {values:blot_check_core::FieldName[:]}
fn lessThan(self_:FieldOrder,left:i64,right:i64)->bool {return self_.values[left].symbol<self_.values[right].symbol;}
fn swap(self_:FieldOrder,left:i64,right:i64) {let saved=self_.values[left];self_.values[left]=self_.values[right];self_.values[right]=saved;}
fn module(storage:Owner&,owner:Module&,names:const u32[:],units:const u32[:]) {
 let fields=storage.mutable(owner.field_names);for &field in fields {field.symbol=names[field.symbol];}blot_check_source_sort::pdqContext(0,fields.len,FieldOrder {fields, ..});moduleWith(storage,owner,Dictionary {names,units, ..});
}
fn moduleUnits(storage:Owner&,owner:Module&,units:const u32[:])->Error {var rejected=false;moduleWith(storage,owner,Retained {units,rejected, ..});if rejected {return blot_error::Error.invalid_artifact;}return blot_error::Error.none;}
fn moduleWith<M>(storage:Owner&,owner:Module&,map:M) {
 capabilityNodes(storage.mutable(owner.capability_contracts.nodes),map);implementations(storage,owner,map);owner.unit=map.unit(owner.unit);typeUnits(storage.mutable(owner.types.nodes),map);
 for &goal in storage.mutable(owner.types.quantifier_obligations) {predicate(map,goal);}
 for &operation in storage.mutable(owner.types.operations) {identity(map,operation.identity);operation.instance.unit=map.unit(operation.instance.unit);}
 for &node in storage.mutable(owner.nodes) {if node.tag==blot_check_core::Tag.associated {node.c=map.symbol(node.c);}else if node.tag==blot_check_core::Tag.result_associated {node.b=map.symbol(node.b);}}
 for &value in storage.mutable(owner.bindings) {target(map,value.target);}for &value in storage.mutable(owner.references) {target(map,value);}for &value in storage.mutable(owner.dependency_references) {target(map,value);}for &value in storage.mutable(owner.erased_declaration_references) {target(map,value.target);}
 for &value in storage.mutable(owner.dependency_members) {value.name=map.symbol(value.name);}for &value in storage.mutable(owner.calls) {target(map,value.target);}
 for &value in storage.mutable(owner.obligations) {predicate(map,value);}
 for &value in storage.mutable(owner.contracts) {identity(map,value.identity);value.name=map.symbol(value.name);}for &value in storage.mutable(owner.contract_members) {identity(map,value.contract);value.name=map.symbol(value.name);}
 for &value in storage.mutable(owner.nominals) {identity(map,value.identity);}for &value in storage.mutable(owner.operation_names) {identity(map,value.identity);}for &value in storage.mutable(owner.constructors) {identity(map,value.identity);}
 for &value in storage.mutable(owner.projections) {identity(map,value.nominal);value.field=map.symbol(value.field);}
 for &value in storage.mutable(owner.associated) {identity(map,value.identity);value.member=map.symbol(value.member);target(map,value.target);}
 for &value in storage.mutable(owner.resolver_ops) {value.member=map.symbol(value.member);target(map,value.method);}
 for &value in storage.mutable(owner.operation_values) {identity(map,value.identity);value.instance.unit=map.unit(value.instance.unit);}
}
fn checkWords(words:const u32[:],roles:const u8[:],count:i64)->Error {for word,index in words {if roles[index]==1&&word>=count {return blot_error::Error.invalid_artifact;}}return blot_error::Error.none;}
fn prepare(value:const blot_reuse_frozen_dependency::FrozenDependency&,pool:const blot_parse_symbols::Pool&,candidate:blot_parse_symbols::Pool&,names:u32[>..<]&,roles:Slots[>..<]&)->Error {
 for index in pool.entries.len {let id,error=candidate.intern(pool.get((index+1) as u32));if error!=blot_error::Error.none {return error;}}
 if value.symbols[0].text.len!=0 {return blot_error::Error.invalid_artifact;}names.resize(value.symbols.len,0);
 for old,index in value.symbols[1..] {let id,error=candidate.intern(old.text);if error!=blot_error::Error.none {return error;}names[index+1]=id;}
 var increasing=true;for index in 1..names.len {if names[index]<=names[index-1] {increasing=false;break;}}
 if !increasing {var seen:bool[>..<]=[];seen.resize(candidate.entries.len+1,false);for name in names[1..] {if name==0||seen[name] {return blot_error::Error.invalid_artifact;}seen[name]=true;}}
 for &owner in value.modules {
  let entry,error=blot_reuse_dependency_symbol_slots::collect(owner);if error!=blot_error::Error.none {return error;}roles.push(entry);
  { let propagated_error = checkWords(owner.interface.graph.extra,entry.interface_types,names.len); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = checkWords(owner.interface.patterns.extra,entry.patterns,names.len); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = checkWords(owner.core.types.extra,entry.core_types,names.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
  { let propagated_error = checkWords(owner.interface.capability_contracts.words,entry.interface_capabilities,names.len); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = checkWords(owner.core.capability_contracts.words,entry.core_capabilities,names.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
  for collection in [owner.interface.capability_contracts,owner.core.capability_contracts] {for node in collection.nodes {if node.tag==blot_check_capability_contracts::Tag.project&&node.c==blot_check_capability_contracts::projectionCode(blot_check_capability_contracts::Projection.field)&&node.b>=names.len {return blot_error::Error.invalid_artifact;}}}
 }
 return blot_error::Error.none;
}
fn relink(storage:Owner&,value:blot_reuse_frozen_dependency::FrozenDependency&,pool:blot_parse_symbols::Pool&,units:const u32[:])->Error {
 if units.len!=value.modules.len||value.symbols.len==0||value.symbols.len>0xffffffff {return blot_error::Error.invalid_artifact;}
 for id,index in units {if id==0||id==0xffffffff {return blot_error::Error.invalid_artifact;}for previous in units[..index] {if previous==id {return blot_error::Error.invalid_artifact;}}}
 var candidate,error=blot_parse_symbols::initPooled();if error!=blot_error::Error.none {return error;}var names:u32[>..<]=[];var roles:Slots[>..<]=[];
 let admitted=prepare(value,pool,candidate,names,roles);
 if admitted!=blot_error::Error.none {for &entry in roles {entry.deinit();}candidate.deinit();return admitted;}
 let previous=copy(pool);pool=candidate;candidate=previous;let map=Dictionary {names,units, ..};
 for &owner,index in value.modules {
  let entry=roles[index];blot_reuse_dependency_symbol_slots::rewrite(storage.mutable(owner.interface.graph.extra),entry.interface_types,names);blot_reuse_dependency_symbol_slots::rewrite(storage.mutable(owner.interface.patterns.extra),entry.patterns,names);blot_reuse_dependency_symbol_slots::rewrite(storage.mutable(owner.core.types.extra),entry.core_types,names);
  blot_reuse_dependency_symbol_slots::rewrite(storage.mutable(owner.interface.capability_contracts.words),entry.interface_capabilities,names);blot_reuse_dependency_symbol_slots::rewrite(storage.mutable(owner.core.capability_contracts.words),entry.core_capabilities,names);
  interfaceWith(storage,owner.interface,map);module(storage,owner.core,names,units);
  for &dependency in owner.imports {dependency=map.unit(dependency);}for &request in owner.source_imports {request.target=map.unit(request.target);}
  for &exported in owner.exports {exported.name=map.symbol(exported.name);target(map,exported.target);}for &fixity in owner.fixities {fixity.operator=map.symbol(fixity.operator);fixity.target=map.symbol(fixity.target);target(map,fixity.producer);}
 }
 for &entry in roles {entry.deinit();}candidate.deinit();return blot_error::Error.none;
}
