namespace blot_eval_source_owners;
import dictionary;
import check.core;
import check.check;
import .body_recipe;
import support.error;
import support.native;
type Error=blot_error::Error;
let ambiguous: u32=0xffffffff;
struct Index { nodes: const u32[:]=[],bindings: const u32[:]=[],complete: bool=false }
fn record(slots: u32[:],id: u32,owner: u32) { if id==0||id>=slots.len { return; } if slots[id]==0 { slots[id]=owner; } else if slots[id]!=owner { slots[id]=ambiguous; } }
fn result(self: Index,slots: const u32[:],id: u32) -> u32,bool { if !self.complete||id==0||id>=slots.len||slots[id]==0||slots[id]==ambiguous { return 0,false; } return slots[id],true; }
fn retain(nodes: const u32[:],bindings: const u32[:],complete: bool,node_owner: u32[>..]&,binding_owner: u32[>..]&) -> Index { let ns=node_owner.len; let bs=binding_owner.len; node_owner.append(nodes); binding_owner.append(bindings); return Index {node_owner[ns..],binding_owner[bs..],complete}; }
fn build(module: const blot_check_core::Module&,limit: i64,node_owner: u32[>..]&,binding_owner: u32[>..]&) -> Index,Error {
 if module.nodes.len>limit||module.bindings.len>limit { return Index {},Error.none; }
 var nodes: u32[>..<]=[]; nodes.resize(module.nodes.len,0); var bindings: u32[>..<]=[]; bindings.resize(module.bindings.len,0); var seen: u32[>..<]=[]; seen.resize(module.nodes.len,0);
 var items: u32[>..<]=[]; var work=blot_eval_body_recipe::Pending {items,limit}; var remaining=limit;
 for body in module.bodies {
  if body.binding==0||body.binding>=module.bindings.len||module.bindings[body.binding].kind!=blot_check_check::Kind.global { continue; }
  if items.len==limit { return retain(nodes,bindings,false,node_owner,binding_owner),Error.none; } items.push(body.root); record(bindings,body.binding,body.binding);
  for parameter in module.bodyParameters(body) { record(bindings,parameter.binding,body.binding); }
  loop {
   let id,present=work.pop(); if !present { break; } if id==0 { continue; }
   if id>=module.nodes.len||remaining==0 { return retain(nodes,bindings,false,node_owner,binding_owner),Error.none; } if seen[id]==body.binding { continue; }
   seen[id]=body.binding; remaining--; record(nodes,id,body.binding); let n=module.node(id);
   if n.tag==blot_check_core::Tag.closure { let closure=module.closure(id); record(bindings,closure.parameter.binding,body.binding); let e=work.append(closure.body); if e==Error.plan_limit { return retain(nodes,bindings,false,node_owner,binding_owner),Error.none; } if e!=Error.none { return Index {},e; } }
   if n.tag==blot_check_core::Tag.bind { record(bindings,n.a,body.binding); }
   let e=blot_eval_body_recipe::appendChildren(work,module,id,false); if e==Error.plan_limit { return retain(nodes,bindings,false,node_owner,binding_owner),Error.none; } if e!=Error.none { return Index {},e; }
  }
 }
 for binding,id in module.bindings { if binding.kind!=blot_check_check::Kind.local||binding.initializer==0||binding.initializer>=nodes.len { continue; } let owner=nodes[binding.initializer]; if owner!=0 { record(bindings,id as u32,owner); } }
 return retain(nodes,bindings,true,node_owner,binding_owner),Error.none;
}
struct Cache { owner_id: u64=blot_native::fresh_owner_id(),units: dictionary<i64,Index>&,nodes: u32[>..]&,bindings: u32[>..]& }
fn index(self: Cache&,units: const blot_check_core::Module[:],owner: i64,limit: i64) -> Index,bool,Error {
 if owner>=units.len { return Index {},false,Error.none; } let known=self.units.get(owner); if known { return known,true,Error.none; }
 let created,e=build(units[owner],limit,self.nodes,self.bindings); if e!=Error.none { return Index {},false,e; } self.units.insert(owner,created); return created,true,Error.none;
}
fn binding(self: Cache&,units: const blot_check_core::Module[:],owner: i64,id: u32,limit: i64) -> u32,bool,Error { let view,present,error=index(self,units,owner,limit); if error!=Error.none||!present { return 0,false,error; } let value,found=result(view,view.bindings,id); return value,found,Error.none; }
fn node(self: Cache&,units: const blot_check_core::Module[:],owner: i64,id: u32,limit: i64) -> u32,bool,Error { let view,present,error=index(self,units,owner,limit); if error!=Error.none||!present { return 0,false,error; } let value,found=result(view,view.nodes,id); return value,found,Error.none; }
