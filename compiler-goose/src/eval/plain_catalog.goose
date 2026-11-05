// Positive plain-data proof over immutable source catalogs; false declines.
namespace blot_eval_plain_catalog;
import check.core;
import check.types;

type Module=blot_check_core::Module;
struct Walk { units: const Module[:],max_depth: i64,remaining: i64=65536 }
fn enter(self_: Walk&,depth: i64) -> bool { if depth>=self_.max_depth||self_.remaining==0 { return false; } self_.remaining--; return true; }
fn nominal(self_: Walk&,unit: u32,decl: u32,depth: i64) -> bool {
 if !enter(self_,depth) { return false; } var owner: i64=-1;
 for module,index in self_.units { var actual=module.unit; if actual==0 { actual=(index+1) as u32; } if actual==unit { owner=index; break; } }
 if owner<0 { return false; } let module=self_.units[owner];
 for definition in module.nominals {
  var actual=definition.identity.unit; if actual==0 { actual=unit; }
  if definition.identity.decl!=decl||actual!=unit { continue; } if definition.constructors.len==0 { return false; }
  for constructor in module.extra[definition.constructors.start..definition.constructors.start+definition.constructors.len] { let payload=module.constructor(constructor).payload; if payload!=0&&!data(self_,owner,payload,definition.variables,depth+1) { return false; } } return true;
 }
 return false;
}
fn data(self_: Walk&,owner: i64,id: u32,variables: blot_check_types::List,depth: i64) -> bool {
 if !enter(self_,depth)||id==0 { return false; } let module=self_.units[owner]; let value=module.types.node(id); let tag=value.tag;
 if tag==blot_check_types::Tag.unit||tag==blot_check_types::Tag.boolean||tag==blot_check_types::Tag.unsigned32||tag==blot_check_types::Tag.floating32||tag==blot_check_types::Tag.never { return true; }
 if tag==blot_check_types::Tag.variable { for child in module.types.list(variables) { if child==id { return true; } } return false; }
 if tag==blot_check_types::Tag.array||tag==blot_check_types::Tag.list||tag==blot_check_types::Tag.cursor { return data(self_,owner,value.a,variables,depth+1); }
 if tag==blot_check_types::Tag.product { for child in module.types.list(blot_check_types::List {value.a,value.b}) { if !data(self_,owner,child,variables,depth+1) { return false; } } return true; }
 if tag==blot_check_types::Tag.record { for index in 0..value.b { if !data(self_,owner,module.types.recordField(value,index).ty,variables,depth+1) { return false; } } return true; }
 if tag==blot_check_types::Tag.nominal {
  for child in module.types.nominalArguments(value) { if !data(self_,owner,child,variables,depth+1) { return false; } }
  var unit=value.a; if unit==0 { unit=module.unit; if unit==0 { unit=(owner+1) as u32; } } return nominal(self_,unit,value.b,depth+1);
 }
 return false;
}
fn prove(units: const Module[:],unit: u32,decl: u32,max_depth: i64) -> bool { var depth=max_depth; if depth>1024 { depth=1024; } var state=Walk {units,depth,65536}; return nominal(state,unit,decl,0); }
