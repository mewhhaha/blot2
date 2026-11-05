// Read-only counting interpreter. No value publication, source mutation or fuel.
namespace blot_eval_eval_ragged_count;
import check.core;
import backend.scalar_ops;
import backend.wasm;
import backend.runtime_ir;
import backend.ragged_builder;
import support.error;
import support.option;
type Scalar=blot_backend_scalar_ops::Value;
struct Value { is_borrowed: bool=false,scalar: Scalar=Scalar {blot_backend_runtime_ir::SC_unit,0},borrowed: u32=0 }
struct Local { binding: u32,value: Value }
struct Counter<A> { adapter: A&,plan: blot_backend_ragged_builder::Plan,remaining: i64=blot_backend_ragged_builder::probe_limit,visits: i64=0,limit: u32,count: u32=0,locals: Local[80],local_count: i64=0,failure: bool=false }
fn step<A>(self: Counter<A>&) -> bool { if self.failure { return false; } if self.remaining==0 { self.failure=true; return false; } self.remaining--; self.visits++; return true; }
fn put<A>(self: Counter<A>&,binding: u32,value: Value) { if self.failure { return; } for i in 0..self.local_count { if self.locals[i].binding==binding { self.locals[i].value=value; return; } } if self.local_count==80 { self.failure=true; return; } self.locals[self.local_count]=Local {binding,value}; self.local_count++; }
fn number<A>(self: Counter<A>&,value: Value) -> Scalar { if !value.is_borrowed { return value.scalar; } let result=self.adapter.scalar(value.borrowed); if !result.present { self.failure=true; return default<Scalar>(); } return result.value; }
fn expression<A>(self: Counter<A>&,id: u32) -> Value {
 if id==0 { return Value {}; } if !step(self) { return Value {}; } let m=self.adapter.module; let n=m.node(id); let tag=n.tag;
 if tag==blot_check_core::Tag.constant { let scalar=self.adapter.constantType(id); if !scalar.present { self.failure=true; return Value {}; } return Value {scalar:Scalar {scalar.value,n.a}}; }
 if tag==blot_check_core::Tag.reference {
  let reference=m.reference(id); if reference.unit==0||reference.unit==m.unit { for slot in self.locals[..self.local_count] { if slot.binding==reference.binding { return slot.value; } } }
  let value=self.adapter.lookup(reference); if !value.present { self.failure=true; return Value {}; } return value.value;
 }
 if tag==blot_check_core::Tag.scalar||tag==blot_check_core::Tag.associated||tag==blot_check_core::Tag.call {
  let operation=self.adapter.operation(id); if !operation.present { self.failure=true; return Value {}; } var first=n.a; var second=n.b;
  if tag==blot_check_core::Tag.call { let args=m.children(id); first=args[0]; second=args[1]; }
  let lv=expression(self,first); var left=number(self,lv); let rv=expression(self,second); var right=number(self,rv); if self.failure { return Value {}; }
  if operation.value.reverse { let previous=left; left=right; right=previous; }
  let result,err=blot_backend_scalar_ops::evaluate(operation.value.op,left,right); if err!=blot_error::Error.none { self.failure=true; return Value {}; } return Value {scalar:result};
 }
 if tag==blot_check_core::Tag.logical {
  let value=expression(self,n.a); let left=number(self,value); if self.failure||left.scalar!=blot_backend_runtime_ir::SC_bool { self.failure=true; return Value {}; }
  if n.op==blot_check_core::Op.and_&&left.bits==0 { return Value {scalar:left}; } if n.op==blot_check_core::Op.or_&&left.bits!=0 { return Value {scalar:left}; } return expression(self,n.b);
 }
 if tag==blot_check_core::Tag.if_value { let value=expression(self,n.a); let condition=number(self,value); if self.failure { return Value {}; } if condition.bits!=0 { return expression(self,n.b); } return expression(self,n.c); }
 if tag==blot_check_core::Tag.array_op { let operand=expression(self,m.children(id)[0]); if !operand.is_borrowed { self.failure=true; return Value {}; } let len=self.adapter.length(operand.borrowed); if !len.present { self.failure=true; return Value {}; } return Value {scalar:Scalar {blot_backend_runtime_ir::SC_u32,len.value}}; }
 if tag==blot_check_core::Tag.project { let operand=expression(self,n.a); if !operand.is_borrowed { self.failure=true; return Value {}; } let result=self.adapter.project(id,operand.borrowed); if !result.present { self.failure=true; return Value {}; } return result.value; }
 self.failure=true; return Value {};
}
fn pattern<A>(self: Counter<A>&,id: u32,value: Value) {
 if id==0 { return; } if !step(self) { return; } let m=self.adapter.module; let p=m.pattern(id);
 if p.tag==blot_check_core::PatternTag.wildcard { return; } if p.tag==blot_check_core::PatternTag.bind { put(self,p.a,value); return; }
 if p.tag==blot_check_core::PatternTag.product {
  if !value.is_borrowed { self.failure=true; return; } let children=self.adapter.children(value.borrowed); let patterns=m.patternChildren(id); if children.len!=patterns.len { self.failure=true; return; }
  for child,index in patterns { pattern(self,child,Value {is_borrowed:true,borrowed:children[index]}); if self.failure { return; } } return;
 }
 self.failure=true;
}
fn program<A>(self: Counter<A>&,id: u32) {
 if id==0||id==self.plan.storage.initial { return; } if !step(self) { return; }
 if id==self.plan.storage.append { if self.count==self.limit { self.failure=true; return; } self.count++; return; }
 if id==self.plan.storage.conversion { return; } let m=self.adapter.module; let n=m.node(id); let tag=n.tag;
 if tag==blot_check_core::Tag.block_||tag==blot_check_core::Tag.suite { for child in m.children(id) { program(self,child); if self.failure { return; } } return; }
 if tag==blot_check_core::Tag.bind { if self.plan.alias(n.a) { program(self,n.b); return; } if n.a!=self.plan.payload_binding { let value=expression(self,n.b); put(self,n.a,value); } return; }
 if tag==blot_check_core::Tag.return_ { if m.node(n.a).tag==blot_check_core::Tag.reference { return; } program(self,n.a); return; }
 if tag==blot_check_core::Tag.reference { return; }
 if tag==blot_check_core::Tag.if_stmt { let value=expression(self,n.a); let condition=number(self,value); if self.failure { return; } if condition.bits!=0 { program(self,n.b); } else { program(self,n.c); } return; }
 if tag==blot_check_core::Tag.loop_ {
  let loop=m.loopInfo(id); let source=expression(self,loop.first); var first: u32=0; var end: u32=0;
  if loop.kind==blot_check_core::LoopKind.range { first=number(self,source).bits; let value=expression(self,loop.end); end=number(self,value).bits; }
  else { if !source.is_borrowed { self.failure=true; return; } let length=self.adapter.length(source.borrowed); if !length.present { self.failure=true; return; } end=length.value; }
  if self.failure { return; } let before=self.local_count; 
  while first<end { if !step(self) { { self.local_count=before; } return; } var element=Value {scalar:Scalar {blot_backend_runtime_ir::SC_u32,first}}; if loop.kind==blot_check_core::LoopKind.array { element=Value {is_borrowed:true,borrowed:self.adapter.children(source.borrowed)[first]}; } pattern(self,loop.pattern,element); program(self,loop.body); if self.failure { { self.local_count=before; } return; } first++; } { self.local_count=before; } return;
  { self.local_count=before; } }
 self.failure=true;
}
fn run<A>(self: Counter<A>&) -> u32,bool { program(self,self.plan.root); return self.count,!self.failure; }
