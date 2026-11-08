// Read-only counting interpreter. No value publication, source mutation or fuel.
namespace blot_eval_eval_ragged_count;
import backend.ragged_builder;
import backend.runtime_ir;
import backend.scalar_ops;
import check.core;
import support.error;

import backend.wasm;
import support.option;
type Scalar=blot_backend_scalar_ops::Value;
struct Value { is_borrowed: bool=false,scalar: Scalar=Scalar {blot_backend_runtime_ir::SC_unit,0},borrowed: u32=0 }
struct Local { binding: u32,value: Value }
struct Counter<A> { adapter: A&,plan: blot_backend_ragged_builder::Plan,remaining: i64=blot_backend_ragged_builder::probe_limit,visits: i64=0,limit: u32,count: u32=0,locals: Local[80],local_count: i64=0,failure: bool=false }
fn step<A>(self_: Counter<A>&) -> bool { if self_.failure { return false; } if self_.remaining==0 { self_.failure=true; return false; } self_.remaining--; self_.visits++; return true; }
fn put<A>(self_: Counter<A>&,binding: u32,value: Value) { if self_.failure { return; } for i in 0..self_.local_count { if self_.locals[i].binding==binding { self_.locals[i].value=value; return; } } if self_.local_count==80 { self_.failure=true; return; } self_.locals[self_.local_count]=Local {binding,value}; self_.local_count++; }
fn number<A>(self_: Counter<A>&,value: Value) -> Scalar { if !value.is_borrowed { return value.scalar; } let result=self_.adapter.scalar(value.borrowed); if !result.present { self_.failure=true; return default<Scalar>(); } return result.value; }
recursive fn expression<A>(self_: Counter<A>&,id: u32) -> Value {
 if id==0 { return Value {}; } if !step(self_) { return Value {}; } let m=self_.adapter.module; let n=m.node(id); let tag=n.tag;
 if tag==blot_check_core::Tag.constant { let scalar=self_.adapter.constantType(id); if !scalar.present { self_.failure=true; return Value {}; } return Value {scalar:Scalar {scalar.value,n.a}}; }
 if tag==blot_check_core::Tag.reference {
  let reference=m.reference(id); if reference.unit==0||reference.unit==m.unit { for slot in self_.locals[..self_.local_count] { if slot.binding==reference.binding { return slot.value; } } }
  let value=self_.adapter.lookup(reference); if !value.present { self_.failure=true; return Value {}; } return value.value;
 }
 if tag==blot_check_core::Tag.scalar||tag==blot_check_core::Tag.associated||tag==blot_check_core::Tag.call {
  let operation=self_.adapter.operation(id); if !operation.present { self_.failure=true; return Value {}; } var first=n.a; var second=n.b;
  if tag==blot_check_core::Tag.call { let args=m.children(id); first=args[0]; second=args[1]; }
  let lv=expression(self_,first); var left=number(self_,lv); let rv=expression(self_,second); var right=number(self_,rv); if self_.failure { return Value {}; }
  if operation.value.reverse { let previous=left; left=right; right=previous; }
  let result,err=blot_backend_scalar_ops::evaluate(operation.value.op,left,right); if err!=blot_error::Error.none { self_.failure=true; return Value {}; } return Value {scalar:result};
 }
 if tag==blot_check_core::Tag.logical {
  let value=expression(self_,n.a); let left=number(self_,value); if self_.failure||left.scalar!=blot_backend_runtime_ir::SC_bool { self_.failure=true; return Value {}; }
  if n.op==blot_check_core::Op.and_&&left.bits==0 { return Value {scalar:left}; } if n.op==blot_check_core::Op.or_&&left.bits!=0 { return Value {scalar:left}; } return expression(self_,n.b);
 }
 if tag==blot_check_core::Tag.if_value { let value=expression(self_,n.a); let condition=number(self_,value); if self_.failure { return Value {}; } if condition.bits!=0 { return expression(self_,n.b); } return expression(self_,n.c); }
 if tag==blot_check_core::Tag.array_op { let operand=expression(self_,m.children(id)[0]); if !operand.is_borrowed { self_.failure=true; return Value {}; } let len=self_.adapter.length(operand.borrowed); if !len.present { self_.failure=true; return Value {}; } return Value {scalar:Scalar {blot_backend_runtime_ir::SC_u32,len.value}}; }
 if tag==blot_check_core::Tag.project { let operand=expression(self_,n.a); if !operand.is_borrowed { self_.failure=true; return Value {}; } let result=self_.adapter.project(id,operand.borrowed); if !result.present { self_.failure=true; return Value {}; } return result.value; }
 self_.failure=true; return Value {};
}
recursive fn pattern<A>(self_: Counter<A>&,id: u32,value: Value) {
 if id==0 { return; } if !step(self_) { return; } let m=self_.adapter.module; let p=m.pattern(id);
 if p.tag==blot_check_core::PatternTag.wildcard { return; } if p.tag==blot_check_core::PatternTag.bind { put(self_,p.a,value); return; }
 if p.tag==blot_check_core::PatternTag.product {
  if !value.is_borrowed { self_.failure=true; return; } let children=self_.adapter.children(value.borrowed); let patterns=m.patternChildren(id); if children.len!=patterns.len { self_.failure=true; return; }
  for child,index in patterns { pattern(self_,child,Value {is_borrowed:true,borrowed:children[index]}); if self_.failure { return; } } return;
 }
 self_.failure=true;
}
recursive fn program<A>(self_: Counter<A>&,id: u32) {
 if id==0||id==self_.plan.storage.initial { return; } if !step(self_) { return; }
 if id==self_.plan.storage.append { if self_.count==self_.limit { self_.failure=true; return; } self_.count++; return; }
 if id==self_.plan.storage.conversion { return; } let m=self_.adapter.module; let n=m.node(id); let tag=n.tag;
 if tag==blot_check_core::Tag.block_||tag==blot_check_core::Tag.suite { for child in m.children(id) { program(self_,child); if self_.failure { return; } } return; }
 if tag==blot_check_core::Tag.bind { if self_.plan.alias(n.a) { program(self_,n.b); return; } if n.a!=self_.plan.payload_binding { let value=expression(self_,n.b); put(self_,n.a,value); } return; }
 if tag==blot_check_core::Tag.return_ { if m.node(n.a).tag==blot_check_core::Tag.reference { return; } program(self_,n.a); return; }
 if tag==blot_check_core::Tag.reference { return; }
 if tag==blot_check_core::Tag.if_stmt { let value=expression(self_,n.a); let condition=number(self_,value); if self_.failure { return; } if condition.bits!=0 { program(self_,n.b); } else { program(self_,n.c); } return; }
 if tag==blot_check_core::Tag.loop_ {
  let loop_=m.loopInfo(id); let source=expression(self_,loop_.first); var first: u32=0; var end: u32=0;
  if loop_.kind==blot_check_core::LoopKind.range { first=number(self_,source).bits; let value=expression(self_,loop_.end); end=number(self_,value).bits; }
  else { if !source.is_borrowed { self_.failure=true; return; } let length=self_.adapter.length(source.borrowed); if !length.present { self_.failure=true; return; } end=length.value; }
  if self_.failure { return; } let before=self_.local_count;
  while first<end { if !step(self_) { { self_.local_count=before; } return; } var element=Value {scalar:Scalar {blot_backend_runtime_ir::SC_u32,first}}; if loop_.kind==blot_check_core::LoopKind.array { element=Value {is_borrowed:true,borrowed:self_.adapter.children(source.borrowed)[first]}; } pattern(self_,loop_.pattern,element); program(self_,loop_.body); if self_.failure { { self_.local_count=before; } return; } first++; } { self_.local_count=before; } return;
  { self_.local_count=before; } }
 self_.failure=true;
}
fn run<A>(self_: Counter<A>&) -> u32,bool { program(self_,self_.plan.root); return self_.count,!self_.failure; }
