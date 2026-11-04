namespace blot_eval_eval_indexed_builder;
import check.core;
import check.types;
type Id=u32;
type Module=blot_check_core::Module;
struct Edit { index: Id=0,value: Id=0,self_binding: u32=0,bounds_first: bool=true,update: Id }
struct Plan { incoming: u32,outgoing: u32,aliases: u32[64],alias_count: i64=0,edits: Edit[16],edit_count: i64=0,budget: i64=256 }
fn alias(self: Plan&,binding: u32) -> bool { for item in self.aliases[..self.alias_count] { if item==binding { return true; } } return false; }
fn addAlias(self: Plan&,binding: u32) -> bool { if alias(self,binding) { return true; } if self.alias_count==64 { return false; } self.aliases[self.alias_count]=binding; self.alias_count++; return true; }
fn localAlias(self: Plan&,m: const Module&,id: Id) -> bool { if m.node(id).tag!=blot_check_core::Tag.reference { return false; } let ref=m.reference(id); return (ref.unit==0||ref.unit==m.unit)&&alias(self,ref.binding); }
fn collect(self: Plan&,m: const Module&,id: Id) -> bool {
 if self.budget==0 { return false; } self.budget--; let n=m.node(id);
 if n.tag==blot_check_core::Tag.suite { for child in m.children(id) { if !collect(self,m,child) { return false; } } }
 else if n.tag==blot_check_core::Tag.bind {}
 else if n.tag==blot_check_core::Tag.loop_ {
  let loop=m.loopInfo(id); if loop.kind!=blot_check_core::LoopKind.range&&loop.kind!=blot_check_core::LoopKind.array { return false; }
  for carry in m.loopCarries(id) {
   if alias(self,carry.incoming) { if !addAlias(self,carry.iteration)||!addAlias(self,carry.backedge)||!addAlias(self,carry.outgoing) { return false; } }
   else { let tag=m.types.node(m.binding(carry.incoming).ty).tag; if tag!=blot_check_types::Tag.unit&&tag!=blot_check_types::Tag.boolean&&tag!=blot_check_types::Tag.unsigned32&&tag!=blot_check_types::Tag.floating32 { return false; } }
  }
  if !collect(self,m,loop.body) { return false; }
 } else { return false; } return true;
}
fn independent(self: Plan&,m: const Module&,id: Id) -> bool {
 if id==0 { return true; } if self.budget==0 { return false; } self.budget--; let n=m.node(id);
 if n.tag==blot_check_core::Tag.constant { return true; }
 if n.tag==blot_check_core::Tag.reference { return !localAlias(self,m,id); }
 if n.tag==blot_check_core::Tag.scalar||n.tag==blot_check_core::Tag.associated||n.tag==blot_check_core::Tag.apply { return independent(self,m,n.a)&&independent(self,m,n.b); }
 if n.tag==blot_check_core::Tag.project { return independent(self,m,n.a); }
 if n.tag==blot_check_core::Tag.if_value { return independent(self,m,n.a)&&independent(self,m,n.b)&&independent(self,m,n.c); }
 if n.tag==blot_check_core::Tag.call { for arg in m.call(id).arguments { if !independent(self,m,arg) { return false; } } return true; }
 if n.tag==blot_check_core::Tag.construct { return independent(self,m,n.b); }
 if n.tag==blot_check_core::Tag.array_op||n.tag==blot_check_core::Tag.product||n.tag==blot_check_core::Tag.record||n.tag==blot_check_core::Tag.array { for arg in m.children(id) { if !independent(self,m,arg) { return false; } } return true; }
 return false;
}
fn edit(self: Plan&,m: const Module&,id: Id) -> bool {
 if self.edit_count==16 { return false; } var item=Edit {update:id}; var root: Id=0; let n=m.node(id);
 if n.tag==blot_check_core::Tag.update { let update=m.updateInfo(id); let path=m.updateSelectors(id); if path.len!=1||path[0].kind!=blot_check_core::UpdateKind.index { return false; } root=update.root; item.index=path[0].index; item.value=update.value; item.self_binding=update.self_binding; }
 else if n.tag==blot_check_core::Tag.array_op { if m.arrayOperation(id)!=blot_check_core::ArrayOp.set { return false; } let args=m.children(id); item.bounds_first=false; root=args[0]; item.index=args[1]; item.value=args[2]; }
 else { return false; }
 if !localAlias(self,m,root)||!independent(self,m,item.index)||!independent(self,m,item.value) { return false; } self.edits[self.edit_count]=item; self.edit_count++; return true;
}
fn check(self: Plan&,m: const Module&,id: Id) -> bool {
 if self.budget==0 { return false; } self.budget--; let n=m.node(id);
 if n.tag==blot_check_core::Tag.suite { for child in m.children(id) { if !check(self,m,child) { return false; } } return true; }
 if n.tag==blot_check_core::Tag.bind { if alias(self,n.a) { return edit(self,m,n.b); } return independent(self,m,n.b); }
 if n.tag==blot_check_core::Tag.loop_ { let loop=m.loopInfo(id); return independent(self,m,loop.first)&&independent(self,m,loop.end)&&check(self,m,loop.body); } return false;
}
fn analyze(m: const Module&,id: Id) -> Plan,bool {
 var plan=default<Plan>(); var found=false;
 for carry in m.loopCarries(id) { let ty=m.types.node(m.binding(carry.incoming).ty); if ty.tag==blot_check_types::Tag.array||ty.tag==blot_check_types::Tag.list { plan=Plan {incoming:carry.incoming,outgoing:carry.outgoing}; found=true; break; } }
 if !found||!addAlias(plan,plan.incoming)||!collect(plan,m,id)||!check(plan,m,id)||plan.edit_count==0 { return plan,false; } return plan,true;
}
