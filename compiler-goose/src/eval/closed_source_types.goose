namespace blot_eval_closed_source_types;
import dictionary;
import check.core;
import check.types;
import check.effects;
import support.error;
import support.native;
struct Facts { owner_id: u64=blot_native::fresh_owner_id(),answers: dictionary<u64,bool>& }
fn key(owner: i64,ty: u32) -> u64 { return (owner as u64)<<32|ty; }
fn closed(self: Facts&,units: const blot_check_core::Module[:],owner: i64,ty: u32,depth: i64) -> bool,blot_error::Error {
 if ty<=5 { return ty!=0,blot_error::Error.none; } if depth>=256 { return false,blot_error::Error.none; }
 let id=key(owner,ty); let known=self.answers.get(id); if known { return known,blot_error::Error.none; }
 let source=units[owner].types; let n=source.node(ty); let tag=n.tag; var result=false;
 if tag==blot_check_types::Tag.unit||tag==blot_check_types::Tag.boolean||tag==blot_check_types::Tag.unsigned32||tag==blot_check_types::Tag.floating32||tag==blot_check_types::Tag.never||tag==blot_check_types::Tag.type_constructor { result=true; }
 else if tag==blot_check_types::Tag.array||tag==blot_check_types::Tag.list||tag==blot_check_types::Tag.cursor||tag==blot_check_types::Tag.resolver { let value,err=closed(self,units,owner,n.a,depth+1); if err!=blot_error::Error.none { return false,err; } result=value; }
 else if tag==blot_check_types::Tag.function||tag==blot_check_types::Tag.provider {
  let a,e=closed(self,units,owner,n.a,depth+1); if e!=blot_error::Error.none { return false,e; } result=a;
  if result&&tag==blot_check_types::Tag.function { let b,error=closed(self,units,owner,n.b,depth+1); if error!=blot_error::Error.none { return false,error; } result=b; }
  if result { let row,err=closedRow(self,units,owner,n.c,depth+1); if err!=blot_error::Error.none { return false,err; } result=row; }
 } else if tag==blot_check_types::Tag.state_provider {
  result=true; let children: u32[3]=[n.a,n.b,n.c]; for child in children { let value,err=closed(self,units,owner,child,depth+1); if err!=blot_error::Error.none { return false,err; } if !value { result=false; break; } }
 } else if tag==blot_check_types::Tag.product||tag==blot_check_types::Tag.nominal {
  var children=source.list(blot_check_types::List {n.a,n.b}); if tag==blot_check_types::Tag.nominal { children=source.nominalArguments(n); } result=true;
  for child in children { let value,err=closed(self,units,owner,child,depth+1); if err!=blot_error::Error.none { return false,err; } if !value { result=false; break; } }
 } else if tag==blot_check_types::Tag.record { result=true; for index in 0..n.b { let value,err=closed(self,units,owner,source.recordField(n,index).ty,depth+1); if err!=blot_error::Error.none { return false,err; } if !value { result=false; break; } } }
 self.answers.insert(id,result); return result,blot_error::Error.none;
}
fn closedRow(self: Facts&,units: const blot_check_core::Module[:],owner: i64,row: u32,depth: i64) -> bool,blot_error::Error {
 if depth>=256 { return false,blot_error::Error.none; } let source=units[owner].types; if source.row(row).tail!=blot_check_effects::Tail.closed { return false,blot_error::Error.none; }
 for label in source.rowLabels(row) { for arg in source.operationArguments(label) { let value,err=closed(self,units,owner,arg,depth+1); if err!=blot_error::Error.none||!value { return value,err; } } } return true,blot_error::Error.none;
}
struct CacheKey { source: u64,depth: i64 }
fn hash(key: CacheKey) -> u64 { return ::hash_combine(::hash(key.source),::hash(key.depth)); }
struct Cache { owner_id: u64=blot_native::fresh_owner_id(),answers: dictionary<CacheKey,u32>&,generation: u16=0,physical: u64=0,max_depth: i64=0 }
fn clearRetainingCapacity(self: Cache&) { self.answers.clear(); self.generation=0; self.physical=0; self.max_depth=0; }
fn activate(self: Cache&,solver: const blot_check_types::Store&,max_depth: i64) -> bool {
 if self.generation!=solver.closed_generation||self.physical!=solver.effects.physical_epoch||self.max_depth!=max_depth { self.answers.clear(); self.generation=solver.closed_generation; self.physical=solver.effects.physical_epoch; self.max_depth=max_depth; }
 return self.generation!=0xffff&&self.physical!=0xffffffffffffffff;
}
fn cacheKey(owner: i64,ty: u32,depth: i64) -> CacheKey { return CacheKey {key(owner,ty),depth}; }
