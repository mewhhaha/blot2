// Source contract: compiler/src/parse/source_operators.zig. Validation follows
// lowering order, with lexical-prefix restoration and explicit context authority.
namespace blot_parse_source_operators;
import .ast;
import .symbols;
import support.error;
type Id=u32;
type Symbol=blot_parse_symbols::Symbol;
type Error=blot_error::Error;
type Tree=blot_parse_ast::Tree;
type Pool=blot_parse_symbols::Pool;
type Code=u32;
type Terminator=u32;
let terminator_none: Terminator=0; let terminator_return: Terminator=1;
let terminator_break: Terminator=2; let terminator_yield: Terminator=3;
let record_target_record: u32=0; let record_target_other: u32=1; let record_target_missing: u32=2;
struct Issue {
 code: Code=0, node: Id=0, point: u32=0, symbol: Symbol=0,
 implicit_type_witness: bool=false, terminator: Terminator=0,
 has_numeric_literal: bool=false, numeric_literal: blot_parse_ast::NumericFault=blot_parse_ast::NumericFault {0,0,blot_parse_ast::Span {},0}
}
fn origin(tree: Tree&,id: Id) -> u32 { for item in tree.operator_origins { if item.node==id { return item.span.start; } } return tree.span(id).start; }
fn numeric_issue(tree: Tree&,id: Id,point: u32) -> Issue {
 let fault=tree.numeric_fault(id); var code=c_float_literal;
 if fault.code==blot_parse_ast::numericcode_integer_range { code=c_integer_range; } else if fault.code==blot_parse_ast::numericcode_float_range { code=c_float_range; }
 return Issue {code:code,node:id,point:point,has_numeric_literal:true,numeric_literal:fault};
}
fn named(pool: Pool&,symbol: Symbol) -> bool {
 let text=pool.get(symbol); if text.len==0 { return false; } let c=text[0]; return (c>='a'&&c<='z')||(c>='A'&&c<='Z')||c=='_';
}
struct Validator<C> {
 tree: Tree&, pool: Pool&, context: C&, locals: Symbol[>..<]&, issue: Issue=Issue {}, has_issue: bool=false,
 pattern_scope: i64=-1, record_constructor: Symbol=0, loops: i64=0, replies: bool=false,
 permitted_requests: Id=0, failure: Error=Error.none
}
fn annotations_stopped<C>(self: Validator<C>&) -> bool { return self.failure!=Error.none||self.context.source_annotations_stopped(); }
fn validate_controls<C>(self: Validator<C>&) -> bool { return self.context.source_control_validation(); }
fn stopped<C>(self: Validator<C>&) -> bool { return self.has_issue||annotations_stopped(self); }
fn fail<C>(self: Validator<C>&,code: Code,id: Id,point: u32,symbol: Symbol) {
 if !stopped(self) { self.issue=Issue {code:code,node:id,point:point,symbol:symbol}; self.has_issue=true; }
}
fn numeric_failure<C>(self: Validator<C>&,id: Id) { if stopped(self) { return; } self.issue=numeric_issue(self.tree,id,self.context.source_literal_point(id)); self.has_issue=true; }
fn local<C>(self: Validator<C>&,symbol: Symbol) -> bool {
 var end=self.locals.len; if self.pattern_scope>=0 { end=self.pattern_scope; }
 for item in self.locals[..end] { if item==symbol { return true; } }
 let text=self.pool.get(symbol);
 for c,index in text { if c=='.' { let root,found=self.pool.lookup(text[..index]); if found { for item in self.locals[..end] { if item==root { return true; } } } break; } }
 return false;
}
fn name<C>(self: Validator<C>&,symbol: Symbol,id: Id,point: u32) {
 if stopped(self)||self.context.source_editor_probe(id) { return; }
 if !local(self,symbol) { let exists,err=self.context.source_value_exists(symbol); self.failure=err; if err==Error.none&&!exists { fail(self,c_unknown_value,id,point,symbol); } }
}
fn bind<C>(self: Validator<C>&,symbol: Symbol) { if !stopped(self)&&symbol!=0&&self.pool.get(symbol)!="_" { self.locals.push(symbol); } }
fn record_target<C>(self: Validator<C>&,id: Id,symbol: Symbol) -> bool {
 if stopped(self) { return false; } let point=self.tree.span(id).start+1;
 if self.context.source_private_constructor(symbol) { fail(self,c_private_access,id,point,symbol); return false; }
 var end=self.locals.len; if self.pattern_scope>=0 { end=self.pattern_scope; }
 for item in self.locals[..end] { if item==symbol { fail(self,c_record_constructor,id,point,0); return false; } }
 let target,err=self.context.source_record_target(symbol); self.failure=err; if err!=Error.none { return false; }
 if target==record_target_record { return true; } if target==record_target_other { fail(self,c_record_constructor,id,point,0); } else { fail(self,c_unknown_constructor,id,point,symbol); } return false;
}
fn type_application<C>(self: Validator<C>&,id: Id) -> bool {
 var head=id;
 loop { let n=self.tree.node(head); if n.tag==a_apply||n.tag==a_group { head=n.a; } else if n.tag==a_name { return !local(self,n.a)&&self.context.source_type_application(n.a); } else { return false; } }
}
fn pattern<C>(self: Validator<C>&,id: Id,depth: i64) {
 let previous=self.pattern_scope; if previous<0 { self.pattern_scope=self.locals.len; }
 pattern_result(self,id,depth); self.pattern_scope=previous;
}
fn pattern_names<C>(self: Validator<C>&,id: Id,depth: i64) { let saved=self.locals.len; pattern(self,id,depth); self.locals.resize(saved); }
fn unique_pattern<C>(self: Validator<C>&,first: const Symbol[:],second: const Symbol[:],id: Id) {
 for a in first { for b in second { if a==b { fail(self,c_duplicate_pattern_binding,id,self.tree.span(id).start,0); return; } } }
}
fn pattern_result<C>(self: Validator<C>&,id: Id,depth: i64) {
 if id==0||stopped(self) { return; } if depth>=1024 { fail(self,c_nesting_limit,id,self.tree.span(id).start,0); return; }
 let n=self.tree.node(id);
 if n.tag==a_numeric_error { numeric_failure(self,id); }
 else if n.tag==a_pattern_name { bind(self,n.a); }
 else if n.tag==a_pattern_field { if n.b==0 { bind(self,n.a); } else { pattern_result(self,n.b,depth+1); } }
 else if n.tag==a_pattern_constructor {
  if n.b!=0&&self.tree.node(n.b).tag==a_pattern_record { if !record_target(self,id,n.a) { return; } } else { name(self,n.a,id,self.tree.span(id).start+1); }
  let previous=self.record_constructor; self.record_constructor=n.a; pattern_result(self,n.b,depth+1); self.record_constructor=previous;
 } else if n.tag==a_pattern_product||n.tag==a_pattern_record {
  let base=self.locals.len; let children=self.tree.children(id);
  for child,index in children {
   if n.tag==a_pattern_record {
    let field=self.tree.node(child).a; let known,has_known=self.context.source_record_field_exists(self.record_constructor,field);
    if has_known&&!known { fail(self,c_unknown_record_field,child,self.tree.span(child).start,field); return; }
    for earlier in children[..index] { if self.tree.node(earlier).a==field { fail(self,c_duplicate_record_field,child,self.tree.span(child).start,field); return; } }
   }
   let start=self.locals.len; pattern_result(self,child,depth+1); if stopped(self) { return; }
   unique_pattern(self,self.locals[base..start],self.locals[start..],child); if stopped(self) { return; }
  }
 } else if n.tag==a_pattern_row {
  var starts: i64[>..]=[]; let children=self.tree.children(id);
  for child in children { starts.push(self.locals.len); pattern_result(self,child,depth+1); if stopped(self) { return; } }
  starts.push(self.locals.len); var index=children.len;
  while index!=0 { index--; unique_pattern(self,self.locals[starts[index]..starts[index+1]],self.locals[starts[index+1]..],children[index]); if stopped(self) { return; } }
 } else if n.tag==a_pattern_value { name(self,n.a,id,self.tree.span(id).start+1); }
}
fn request_input<C>(self: Validator<C>&,id: Id) -> bool {
 var head=id; while self.tree.node(head).tag==a_apply||self.tree.node(head).tag==a_group { head=self.tree.node(head).a; }
 return self.tree.node(head).tag==a_intrinsic&&self.pool.get(self.tree.node(head).a)=="@requests";
}
struct Deferred { node: Id, locals: i64, handlers: bool=false }
fn suite<C>(self: Validator<C>&,children: const Id[:],depth: i64) {
 var deferred: Deferred[>..]=[];
 for child,index in children {
  if stopped(self) { return; } let n=self.tree.node(child); var terminator=terminator_none;
  if n.tag==a_return_stmt||n.tag==a_function_return_stmt { terminator=terminator_return; }
  else if n.tag==a_break_stmt||n.tag==a_continue_stmt { terminator=terminator_break; }
  else if n.tag==a_yield_stmt { terminator=terminator_yield; }
  if terminator!=terminator_none&&index+1<children.len { let following=children[index+1]; fail(self,c_unreachable_statement,following,self.tree.span(following).start,0); if self.has_issue { self.issue.terminator=terminator; } return; }
  if n.tag==a_for_stmt&&request_input(self,n.b) { self.failure=self.context.source_request_header(child); if annotations_stopped(self) { return; } }
  let dispatch,has_dispatch=request_dispatch(self,child);
  if n.tag==a_for_stmt&&request_input(self,n.b)&&has_dispatch {
   let saved_request=self.permitted_requests; var head=n.b; while self.tree.node(head).tag==a_apply||self.tree.node(head).tag==a_group { head=self.tree.node(head).a; }
   self.permitted_requests=head; walk(self,n.b,depth+1); self.permitted_requests=saved_request;
   let saved=self.locals.len; pattern(self,n.a,depth+1); request_case(self,dispatch,true,depth+1); self.locals.resize(saved); deferred.push(Deferred {child,saved,true});
  } else if n.tag==a_for_stmt&&!request_input(self,n.b) {
   let body=self.tree.extra[n.c+1]; loop_scope(self,n.a,body,depth+1); deferred.push(Deferred {child,self.locals.len,false});
  } else if n.tag==a_range_stmt { loop_scope(self,0,n.c,depth+1); deferred.push(Deferred {child,self.locals.len,false}); }
  else { walk(self,child,depth+1); }
  if stopped(self) { return; }
 }
 var index=deferred.len;
 while index!=0 {
  index--; let item=deferred[index]; self.locals.resize(item.locals); let n=self.tree.node(item.node);
  if item.handlers { pattern(self,n.a,depth+1); let dispatch,found=request_dispatch(self,item.node); request_case(self,dispatch,false,depth+1); }
  else if n.tag==a_for_stmt { walk(self,n.b,depth+1); walk(self,self.tree.extra[n.c],depth+1); }
  else { walk(self,n.a,depth+1); walk(self,n.b,depth+1); } if stopped(self) { return; }
 }
}
fn request_dispatch<C>(self: Validator<C>&,id: Id) -> Id,bool {
 let n=self.tree.node(id); if n.tag!=a_for_stmt { return 0,false; }
 let body=self.tree.extra[n.c+1]; if self.tree.node(body).tag!=a_block { return 0,false; }
 let statements=self.tree.children(body); if statements.len!=1||self.tree.node(statements[0]).tag!=a_request_case { return 0,false; } return statements[0],true;
}
fn request_case<C>(self: Validator<C>&,id: Id,completion: bool,depth: i64) {
 if stopped(self) { return; } let saved_replies=self.replies; let saved_loops=self.loops; self.replies=!completion; self.loops++;
 defer { self.replies=saved_replies; self.loops=saved_loops; }
 let n=self.tree.node(id);
 if completion { let start=self.tree.extra[n.a]; let len=self.tree.extra[n.a+1]; for child in self.tree.list(blot_parse_ast::List {start,len}) { walk(self,child,depth+1); } }
 for child in self.tree.list(blot_parse_ast::List {n.b,n.c}) { if (self.tree.node(child).a==0)==completion { walk(self,child,depth+1); } }
}
fn scope<C>(self: Validator<C>&,pattern_id: Id,body: Id,depth: i64) { let saved=self.locals.len; pattern(self,pattern_id,depth); walk(self,body,depth); self.locals.resize(saved); }
fn loop_scope<C>(self: Validator<C>&,pattern_id: Id,body: Id,depth: i64) { self.loops++; scope(self,pattern_id,body,depth); self.loops--; }
fn operator<C>(self: Validator<C>&,symbol: Symbol,is_named: bool,id: Id) {
 let spelling=self.pool.get(symbol); if spelling=="and"||spelling=="or" { return; } let point=origin(self.tree,id);
 if is_named { name(self,symbol,id,point); } else if !self.context.source_symbolic_declared(symbol) { fail(self,c_unknown_operator,id,point,symbol); }
}
fn primitive<C>(self: Validator<C>&,id: Id,head: Id,argument_count: i64,depth: i64) {
 if stopped(self) { return; } let symbol=self.tree.node(head).a; let spelling=self.pool.get(symbol);
 if validate_controls(self)&&spelling=="@requests"&&head!=self.permitted_requests { fail(self,c_requests_scope,head,self.tree.span(head).start,0); return; }
 if !self.context.source_intrinsic_known(symbol) { fail(self,c_unknown_intrinsic,head,self.tree.span(head).start,symbol); return; }
 let arity,has_arity=self.context.source_intrinsic_arity(symbol);
 if !has_arity { let application=self.tree.node(id); if application.tag==a_apply { walk(self,application.a,depth); walk(self,application.b,depth); } return; }
 if argument_count!=arity||argument_count>4 { fail(self,c_call_arity,head,self.tree.span(head).start,0); return; }
 var arguments: Id[4]=[0,0,0,0]; var current=id; var index=argument_count;
 while self.tree.node(current).tag==a_apply { index--; arguments[index]=self.tree.node(current).b; current=self.tree.node(current).a; }
 let descriptor=spelling=="@type.call"||spelling=="@type.result"||spelling=="@panic";
 if descriptor&&self.tree.node(arguments[0]).tag!=a_string { fail(self,c_literal_required,arguments[0],self.tree.span(arguments[0]).start,0); return; }
 var selectors=0; if spelling=="@effect.state"||spelling=="@effect.run" { selectors=2; } else if spelling=="@effect.provider"||spelling=="@effect.reader"||spelling=="@effect.writer" { selectors=1; }
 for i in 0..selectors { let arg=arguments[i]; if self.tree.node(arg).tag==a_name&&self.pool.get(self.tree.node(arg).a)=="Foreign" { fail(self,c_sealed_effect,arg,self.tree.span(arg).start,0); return; } }
 for i in 0..arity {
  let arg=arguments[i]; if i==0&&descriptor { continue; }
  if spelling=="@product.get"&&i==1 {
   if self.tree.node(arg).tag==a_numeric_error&&self.tree.numeric_fault(arg).code==blot_parse_ast::numericcode_integer_range { numeric_failure(self,arg); }
   else if self.tree.node(arg).tag!=a_integer { fail(self,c_product_index_literal,arg,self.tree.span(arg).start,0); } return;
  }
  let foreign_descriptor=(spelling=="@effect.descriptor"&&i==0)||(spelling=="@effect.has"&&i==1);
  if foreign_descriptor&&self.tree.node(arg).tag==a_name&&self.pool.get(self.tree.node(arg).a)=="Foreign" { continue; }
  walk(self,arg,depth); if stopped(self) { return; }
 }
}
let c_private_access: Code=0;
let c_effect_member: Code=1;
let c_constructor_marker: Code=2;
let c_integer_range: Code=3;
let c_float_range: Code=4;
let c_float_literal: Code=5;
let c_duplicate_name: Code=6;
let c_unknown_operator: Code=7;
let c_unknown_value: Code=8;
let c_unknown_rebinding: Code=9;
let c_unreachable_statement: Code=10;
let c_operator_associativity: Code=11;
let c_operator_header_order: Code=12;
let c_operator_precedence: Code=13;
let c_duplicate_operator: Code=14;
let c_unsupported_prefix: Code=15;
let c_unknown_intrinsic: Code=16;
let c_unsupported_expression: Code=17;
let c_unknown_constructor: Code=18;
let c_sealed_effect: Code=19;
let c_call_arity: Code=20;
let c_requests_scope: Code=21;
let c_yield_scope: Code=22;
let c_break_scope: Code=23;
let c_continue_scope: Code=24;
let c_literal_required: Code=25;
let c_product_index_literal: Code=26;
let c_alternative_bindings: Code=27;
let c_duplicate_pattern_binding: Code=28;
let c_duplicate_record_field: Code=29;
let c_unknown_record_field: Code=30;
let c_record_constructor: Code=31;
let c_missing_record_field: Code=32;
let c_unknown_modifier: Code=33;
let c_nesting_limit: Code=34;
let a_invalid=blot_parse_ast::tag_invalid;
let a_value_decl=blot_parse_ast::tag_value_decl;
let a_import_decl=blot_parse_ast::tag_import_decl;
let a_export_decl=blot_parse_ast::tag_export_decl;
let a_import_binding=blot_parse_ast::tag_import_binding;
let a_data_decl=blot_parse_ast::tag_data_decl;
let a_type_alias_decl=blot_parse_ast::tag_type_alias_decl;
let a_contract_decl=blot_parse_ast::tag_contract_decl;
let a_contract_type_member=blot_parse_ast::tag_contract_type_member;
let a_contract_value_member=blot_parse_ast::tag_contract_value_member;
let a_implementation_decl=blot_parse_ast::tag_implementation_decl;
let a_effect_decl=blot_parse_ast::tag_effect_decl;
let a_effect_type_decl=blot_parse_ast::tag_effect_type_decl;
let a_fixity_decl=blot_parse_ast::tag_fixity_decl;
let a_attribute=blot_parse_ast::tag_attribute;
let a_constraint=blot_parse_ast::tag_constraint;
let a_where_clause=blot_parse_ast::tag_where_clause;
let a_constructors=blot_parse_ast::tag_constructors;
let a_effect_operations=blot_parse_ast::tag_effect_operations;
let a_effect_operation=blot_parse_ast::tag_effect_operation;
let a_name=blot_parse_ast::tag_name;
let a_intrinsic=blot_parse_ast::tag_intrinsic;
let a_integer=blot_parse_ast::tag_integer;
let a_float=blot_parse_ast::tag_float;
let a_string=blot_parse_ast::tag_string;
let a_boolean=blot_parse_ast::tag_boolean;
let a_unit=blot_parse_ast::tag_unit;
let a_lambda=blot_parse_ast::tag_lambda;
let a_parameter=blot_parse_ast::tag_parameter;
let a_apply=blot_parse_ast::tag_apply;
let a_group=blot_parse_ast::tag_group;
let a_unary=blot_parse_ast::tag_unary;
let a_binary=blot_parse_ast::tag_binary;
let a_infix_chain=blot_parse_ast::tag_infix_chain;
let a_operator_tail=blot_parse_ast::tag_operator_tail;
let a_product=blot_parse_ast::tag_product;
let a_array=blot_parse_ast::tag_array;
let a_block=blot_parse_ast::tag_block;
let a_record=blot_parse_ast::tag_record;
let a_field=blot_parse_ast::tag_field;
let a_selector=blot_parse_ast::tag_selector;
let a_constructor_ref=blot_parse_ast::tag_constructor_ref;
let a_type_witness=blot_parse_ast::tag_type_witness;
let a_field_access=blot_parse_ast::tag_field_access;
let a_index_access=blot_parse_ast::tag_index_access;
let a_let_stmt=blot_parse_ast::tag_let_stmt;
let a_rebind_stmt=blot_parse_ast::tag_rebind_stmt;
let a_use_stmt=blot_parse_ast::tag_use_stmt;
let a_iterator_bind=blot_parse_ast::tag_iterator_bind;
let a_function_return_stmt=blot_parse_ast::tag_function_return_stmt;
let a_return_stmt=blot_parse_ast::tag_return_stmt;
let a_yield_stmt=blot_parse_ast::tag_yield_stmt;
let a_break_stmt=blot_parse_ast::tag_break_stmt;
let a_continue_stmt=blot_parse_ast::tag_continue_stmt;
let a_if_expr=blot_parse_ast::tag_if_expr;
let a_if_stmt=blot_parse_ast::tag_if_stmt;
let a_if_let_stmt=blot_parse_ast::tag_if_let_stmt;
let a_for_stmt=blot_parse_ast::tag_for_stmt;
let a_range_stmt=blot_parse_ast::tag_range_stmt;
let a_forever_stmt=blot_parse_ast::tag_forever_stmt;
let a_case_expr=blot_parse_ast::tag_case_expr;
let a_case_arm=blot_parse_ast::tag_case_arm;
let a_pattern_row=blot_parse_ast::tag_pattern_row;
let a_request_case=blot_parse_ast::tag_request_case;
let a_request_arm=blot_parse_ast::tag_request_arm;
let a_pattern_name=blot_parse_ast::tag_pattern_name;
let a_pattern_integer=blot_parse_ast::tag_pattern_integer;
let a_pattern_boolean=blot_parse_ast::tag_pattern_boolean;
let a_pattern_product=blot_parse_ast::tag_pattern_product;
let a_pattern_constructor=blot_parse_ast::tag_pattern_constructor;
let a_pattern_record=blot_parse_ast::tag_pattern_record;
let a_pattern_field=blot_parse_ast::tag_pattern_field;
let a_pattern_value=blot_parse_ast::tag_pattern_value;
let a_type_name=blot_parse_ast::tag_type_name;
let a_type_apply=blot_parse_ast::tag_type_apply;
let a_type_function=blot_parse_ast::tag_type_function;
let a_type_effect=blot_parse_ast::tag_type_effect;
let a_type_product=blot_parse_ast::tag_type_product;
let a_type_array=blot_parse_ast::tag_type_array;
let a_type_record=blot_parse_ast::tag_type_record;
let a_type_field=blot_parse_ast::tag_type_field;
let a_effect_row=blot_parse_ast::tag_effect_row;
let a_numeric_error=blot_parse_ast::tag_numeric_error;
let a_type_binder=blot_parse_ast::tag_type_binder;
let a_type_usage=blot_parse_ast::tag_type_usage;
let a_type_forall=blot_parse_ast::tag_type_forall;
let a_type_exists=blot_parse_ast::tag_type_exists;
let a_quantified_binder=blot_parse_ast::tag_quantified_binder;
let a_package_pack=blot_parse_ast::tag_package_pack;
let a_package_unpack=blot_parse_ast::tag_package_unpack;
let a_type_code=blot_parse_ast::tag_type_code;
let a_type_descriptor=blot_parse_ast::tag_type_descriptor;
let a_task_region=blot_parse_ast::tag_task_region;
fn walk<C>(self: Validator<C>&,id: Id,depth: i64) {
 if id!=0 { let tag=self.tree.node(id).tag; if (tag==a_name||tag==a_constructor_ref||tag==a_intrinsic)&&self.context.source_editor_probe(id) { return; } }
 if id==0||stopped(self) { return; } if depth>=1024 { fail(self,c_nesting_limit,id,self.tree.span(id).start,0); return; }
 let n=self.tree.node(id);
 if n.tag==a_numeric_error { numeric_failure(self,id); }
 else if n.tag==a_string {}
 else if n.tag==a_name {
  if validate_controls(self)&&!local(self,n.a)&&self.context.source_non_callable_effect(n.a) { fail(self,c_effect_member,id,self.tree.span(id).start,0); }
  else { name(self,n.a,id,self.tree.span(id).start); }
 } else if n.tag==a_intrinsic {
  if validate_controls(self)&&self.pool.get(n.a)=="@requests"&&id!=self.permitted_requests { fail(self,c_requests_scope,id,self.tree.span(id).start,0); }
  else if !self.context.source_intrinsic_known(n.a) { fail(self,c_unknown_intrinsic,id,self.tree.span(id).start,n.a); }
  else { let arity,found=self.context.source_intrinsic_arity(n.a); if found&&arity!=0 { fail(self,c_call_arity,id,self.tree.span(id).start,0); } }
 } else if n.tag==a_constructor_ref {
  let exists,err=self.context.source_operator_target_exists(n.a); self.failure=err; if err==Error.none&&!exists { fail(self,c_unknown_value,id,self.tree.span(id).start+1,n.a); }
 } else if n.tag==a_type_witness {
  walk(self,n.a,depth+1); if stopped(self) { return; } let constructor,found=self.pool.lookup("Type"); var exists=false;
  if found { let value,err=self.context.source_operator_target_exists(constructor); self.failure=err; exists=value; }
  if self.failure==Error.none&&(!found||!exists) { self.issue=Issue {code:c_unknown_value,node:id,point:self.tree.span(id).start,symbol:constructor,implicit_type_witness:!found}; self.has_issue=true; }
 } else if n.tag==a_group||n.tag==a_return_stmt||n.tag==a_function_return_stmt { walk(self,n.a,depth+1); }
 else if n.tag==a_yield_stmt { if validate_controls(self)&&!self.replies { fail(self,c_yield_scope,id,self.tree.span(id).start,0); } else { walk(self,n.a,depth+1); } }
 else if n.tag==a_break_stmt { if validate_controls(self)&&self.loops==0 { fail(self,c_break_scope,id,self.tree.span(id).start,0); } }
 else if n.tag==a_continue_stmt { if validate_controls(self)&&self.loops==0 { fail(self,c_continue_scope,id,self.tree.span(id).start,0); } }
 else if n.tag==a_forever_stmt { loop_scope(self,0,n.a,depth+1); }
 else if n.tag==a_field_access {
  var base=n.a; while self.tree.node(base).tag==a_group { base=self.tree.node(base).a; } let source=self.tree.node(base);
  if source.tag==a_name&&!local(self,source.a)&&self.context.source_qualified_exists(source.a,n.b) { return; } walk(self,n.a,depth+1);
 } else if n.tag==a_field { if n.b!=0 { walk(self,n.b,depth+1); } else { name(self,n.a,id,self.tree.span(id).start); } }
 else if n.tag==a_unary { walk(self,n.b,depth+1); if self.pool.get(n.a)!="-" { fail(self,c_unsupported_prefix,id,self.tree.span(id).start,0); } }
 else if n.tag==a_binary {
  walk(self,n.b,depth+1); if stopped(self) { return; } operator(self,n.a,named(self.pool,n.a),id); walk(self,n.c,depth+1);
 } else if n.tag==a_infix_chain {
  walk(self,n.a,depth+1); let tails=self.tree.list(blot_parse_ast::List {n.b,n.c});
  for tail in tails { if stopped(self) { return; } let op=self.tree.node(tail); operator(self,op.a,(op.c&1)!=0,tail); walk(self,op.b,depth+1); }
  if stopped(self) { return; } var stack: Id[>..<]=[];
  for tail in tails {
   let flags=self.tree.node(tail).c; let power=flags>>4; let association=(flags>>2)&3;
   while stack.len!=0 {
    let previous=self.tree.node(stack[stack.len-1]).c; if previous>>4<power { break; }
    if previous>>4==power { if ((previous>>2)&3)!=association||association==2 { fail(self,c_operator_associativity,tail,origin(self.tree,tail),0); return; } if association==1 { break; } }
    stack.resize(stack.len-1);
   }
   stack.push(tail);
  }
 } else if n.tag==a_apply {
  var head=id; var argument_count=0;
  loop { let current=self.tree.node(head); if current.tag==a_apply { argument_count++; head=current.a; } else { break; } }
  let callee=self.tree.node(head);
  if validate_controls(self)&&callee.tag==a_name&&self.tree.node(n.b).tag==a_record&&self.context.source_constructor_exists(callee.a)&&!local(self,callee.a) { fail(self,c_constructor_marker,id,self.tree.span(id).start,0); return; }
  if callee.tag==a_intrinsic { primitive(self,id,head,argument_count,depth+1); return; }
  walk(self,n.a,depth+1); if stopped(self) { return; }
  var type_argument=type_application(self,n.a);
  if type_argument&&validate_controls(self) { let is_type,err=self.context.source_argument_is_type(n.a,n.b); self.failure=err; type_argument=is_type; }
  if !type_argument { walk(self,n.b,depth+1); }
 } else if n.tag==a_index_access { walk(self,n.a,depth+1); walk(self,n.b,depth+1); }
 else if n.tag==a_record {
  if n.a!=0&&!record_target(self,id,n.a) { return; } let fields=self.tree.children(id);
  for child,index in fields {
   let field=self.tree.node(child).a;
   if n.a!=0 { let known,has_known=self.context.source_record_field_exists(n.a,field); if has_known&&!known { fail(self,c_unknown_record_field,child,self.tree.span(child).start,field); return; } }
   for earlier in fields[..index] { if self.tree.node(earlier).a==field { fail(self,c_duplicate_record_field,child,self.tree.span(child).start,field); return; } }
   walk(self,child,depth+1); if stopped(self) { return; }
  }
  if n.a!=0 { let field,missing=self.context.source_missing_record_field(n.a,fields); if missing { fail(self,c_missing_record_field,id,self.tree.span(id).start+1,field); } }
 } else if n.tag==a_product||n.tag==a_array { for child in self.tree.children(id) { walk(self,child,depth+1); } }
 else if n.tag==a_lambda {
  self.failure=self.context.source_expression_annotations(id); if annotations_stopped(self) { return; }
  let saved_loops=self.loops; let saved_replies=self.replies; self.loops=0; self.replies=false;
  let saved=self.locals.len; bind(self,self.tree.parameter(n.a).name); walk(self,n.b,depth+1);
  self.locals.resize(saved); self.loops=saved_loops; self.replies=saved_replies;
 } else if n.tag==a_block {
  let saved=self.locals.len; suite(self,self.tree.children(id),depth+1); self.locals.resize(saved); walk(self,n.c,depth+1);
 } else if n.tag==a_let_stmt {
  let binding=self.tree.binding(id); let scope,err=self.context.source_binding_start(id); self.failure=err; if err!=Error.none { return; }
  defer { self.context.source_binding_end(scope); }
  pattern_names(self,binding.pattern,depth+1); if stopped(self) { return; }
  self.failure=self.context.source_binding_annotation(id); if annotations_stopped(self) { return; }
  walk(self,binding.value,depth+1); if stopped(self) { return; }
  self.failure=self.context.source_binding_finish(id); if annotations_stopped(self) { return; }
  walk(self,binding.fallback,depth+1); pattern(self,binding.pattern,depth+1);
 } else if n.tag==a_use_stmt||n.tag==a_iterator_bind {
  self.failure=self.context.source_expression_annotations(id); walk(self,n.b,depth+1); bind(self,n.a);
 } else if n.tag==a_rebind_stmt {
  var root=n.a; while self.tree.node(root).tag==a_field_access||self.tree.node(root).tag==a_index_access { root=self.tree.node(root).a; } let target=self.tree.node(root);
  if target.tag==a_name&&!local(self,target.a) { fail(self,c_unknown_rebinding,id,self.tree.span(root).start,target.a); return; }
  let saved=self.locals.len; let symbol,found=self.pool.lookup("self"); bind(self,symbol); walk(self,n.a,depth+1); walk(self,n.b,depth+1); self.locals.resize(saved);
 } else if n.tag==a_if_expr||n.tag==a_if_stmt||n.tag==a_range_stmt { walk(self,n.a,depth+1); scope(self,0,n.b,depth+1); scope(self,0,n.c,depth+1); }
 else if n.tag==a_if_let_stmt {
  pattern_names(self,n.a,depth+1); walk(self,n.b,depth+1); let body=self.tree.extra[n.c]; let fallback=self.tree.extra[n.c+1]; scope(self,n.a,body,depth+1); scope(self,0,fallback,depth+1);
 } else if n.tag==a_for_stmt {
  walk(self,n.b,depth+1); let end=self.tree.extra[n.c]; let body=self.tree.extra[n.c+1]; walk(self,end,depth+1); scope(self,n.a,body,depth+1);
 } else if n.tag==a_case_expr {
  let input=blot_parse_ast::List {self.tree.extra[n.a],self.tree.extra[n.a+1]}; for child in self.tree.list(input) { walk(self,child,depth+1); }
  for child in self.tree.list(blot_parse_ast::List {n.b,n.c}) { walk(self,child,depth+1); }
 } else if n.tag==a_request_case { request_case(self,id,true,depth+1); request_case(self,id,false,depth+1); }
 else if n.tag==a_case_arm {
  let saved=self.locals.len; defer { self.locals.resize(saved); }
  let rows=self.tree.list(blot_parse_ast::List {n.a,n.b}); if rows.len!=0 { pattern(self,rows[0],depth+1); }
  let canonical_end=self.locals.len; var index=0; if rows.len!=0 { index=1; }
  while index<rows.len {
   let row=rows[index]; let previous=self.pattern_scope; self.pattern_scope=saved; pattern(self,row,depth+1); self.pattern_scope=previous; if stopped(self) { return; }
   var same=canonical_end-saved==self.locals.len-canonical_end;
   for name in self.locals[saved..canonical_end] { var found=false; for other in self.locals[canonical_end..] { if name==other { found=true; break; } } same=same&&found; }
   if !same { fail(self,c_alternative_bindings,row,self.tree.span(row).start,0); }
   self.locals.resize(canonical_end); if stopped(self) { return; } index++;
  }
  let guard=self.tree.extra[n.c]; let body=self.tree.extra[n.c+1]; walk(self,body,depth+1); walk(self,guard,depth+1);
 } else if n.tag==a_request_arm { walk(self,n.a,depth+1); scope(self,n.b,n.c,depth+1); }
}
fn validate<C>(tree: Tree&,pool: Pool&,context: C&) -> Issue,bool,Error {
 let duplicate,has_duplicate=context.source_duplicate_name(); var collected=tree.roots.len;
 while collected!=0 {
  collected--; let id=tree.roots[collected];
  if has_duplicate&&duplicate==id { return Issue {code:c_duplicate_name,node:id,point:tree.span(id).start},true,Error.none; }
  if tree.node(id).tag!=a_data_decl { continue; }
  for constructor in tree.children(tree.node(id).b) {
   let payload=tree.node(constructor).b; if payload==0||tree.node(payload).tag!=a_type_record||tree.type_conversion_origin(payload)!=tree.span(payload).start { continue; }
   let fields=tree.children(payload);
   for field,index in fields { for earlier in fields[..index] { if tree.node(field).a==tree.node(earlier).a { return Issue {code:c_duplicate_record_field,node:field,point:tree.span(field).start,symbol:tree.node(field).a},true,Error.none; } } }
  }
 }
 if has_duplicate { return Issue {code:c_duplicate_name,node:duplicate,point:tree.span(duplicate).start},true,Error.none; }
 var index=tree.roots.len;
 while index!=0 {
  index--; let id=tree.roots[index]; if tree.node(id).tag!=a_fixity_decl { continue; } let fixity=tree.fixity(id);
  for earlier in tree.roots[..index] { if tree.node(earlier).tag!=a_import_decl&&tree.node(earlier).tag!=a_fixity_decl { return Issue {code:c_operator_header_order,node:id,point:tree.span(id).start},true,Error.none; } }
  if fixity.literal_error!=0 { return numeric_issue(tree,fixity.literal_error,tree.span(fixity.literal_error).start),true,Error.none; }
  for later in tree.roots[index+1..] { if tree.node(later).tag==a_fixity_decl { let other=tree.fixity(later); if fixity.operator==other.operator&&fixity.named==other.named { return Issue {code:c_duplicate_operator,node:id,point:tree.span(id).start},true,Error.none; } } }
  if fixity.precedence>255 { return Issue {code:c_operator_precedence,node:id,point:tree.span(id).start},true,Error.none; }
  let exists,err=context.source_operator_target_exists(fixity.target); if err!=Error.none { return Issue {},false,err; }
  if !exists { return Issue {code:c_unknown_value,node:id,point:origin(tree,id),symbol:fixity.target},true,Error.none; }
 }
 var locals: Symbol[>..<]=[]; var validator=Validator<C> {tree:tree,pool:pool,context:context,locals:locals}; index=tree.roots.len;
 while index!=0 {
  index--; let id=tree.roots[index]; validator.failure=context.source_declaration_header(id);
  if annotations_stopped(validator) { return Issue {},false,validator.failure; }
  if tree.node(id).tag==a_implementation_decl {
   let saved=locals.len; let implementation=tree.implementation(id);
   for member in tree.list(implementation.members) { if tree.node(member).tag==a_value_decl { locals.push(tree.node(member).a); } }
   let scope,err=context.source_implementation_start(id); if err!=Error.none { locals.resize(saved); return Issue {},false,err; }
   for member in tree.list(implementation.members) {
    if tree.node(member).tag!=a_value_decl { continue; }
    validator.failure=context.source_binding_annotation(member);
    if annotations_stopped(validator) { break; } walk(validator,tree.value_decl(member).body,0); if stopped(validator) { break; }
   }
   context.source_implementation_end(scope); locals.resize(saved);
   if validator.has_issue { return validator.issue,true,validator.failure; }
   if annotations_stopped(validator) { return Issue {},false,validator.failure; } continue;
  }
  if tree.node(id).tag!=a_value_decl { continue; } let value=tree.value_decl(id);
  if value.modifier!=0&&pool.get(value.modifier)!="entry" { return Issue {code:c_unknown_modifier,node:id,point:tree.span(id).start},true,Error.none; }
  let scope,err=context.source_binding_start(id); if err!=Error.none { return Issue {},false,err; }
  validator.failure=context.source_binding_annotation(id);
  if !annotations_stopped(validator) {
   walk(validator,value.body,0); let attributes=tree.list(value.attributes); var attribute_index=value.attributes.len;
   while attribute_index!=0 { attribute_index--; walk(validator,tree.node(attributes[attribute_index]).a,0); }
   if !validator.has_issue&&!annotations_stopped(validator) { validator.failure=context.source_binding_finish(id); }
  }
  context.source_binding_end(scope);
  if validator.has_issue { return validator.issue,true,validator.failure; }
  if annotations_stopped(validator) { return Issue {},false,validator.failure; }
 }
 return Issue {},false,Error.none;
}
