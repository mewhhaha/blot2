// Binding discovery follows evaluation order without importing or running bodies.
namespace blot_reuse_global_references;
import parse.ast;
import support.error;
import support.option;
type Error=blot_error::Error;
type Id=blot_parse_ast::Id;
type Tree=blot_parse_ast::Tree;
enum Kind {name,qualified,operator}
struct Reference {binding:u32,source:Id}
enum Event {visit {id:Id},restore {count:i64},bind {name:u32},pattern_bind {id:Id},pattern_read {id:Id}}
struct Walker<C> {tree:const Tree&,resolver:C&,self_name:u32,transitions:i64&,limit:i64,work:Event[>..<]&,locals:u32[>..<]&,references:Reference[>..<]&}
fn push<C>(self_:Walker<C>&,event:Event)->Error {self_.work.push(event);return blot_error::Error.none;}
fn visit<C>(self_:Walker<C>&,id:Id)->Error {if id!=0 {{ let propagated_error = self_.push(Event.visit {id, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }}return blot_error::Error.none;}
fn list<C>(self_:Walker<C>&,ids:const Id[:])->Error {var index=ids.len;while index!=0 {index--;{ let propagated_error = self_.visit(ids[index]); if propagated_error != blot_error::Error.none { return propagated_error; } }}return blot_error::Error.none;}
fn reference<C>(self_:Walker<C>&,kind:Kind,name:u32,member:u32,source:Id)->bool,Error {
 let binding,error=self_.resolver.resolve(kind,name,member,self_.locals[..]);if error!=blot_error::Error.none {return false,error;}
 if !binding.present {return false,blot_error::Error.none;}self_.references.push(Reference {binding.value,source, ..});return true,blot_error::Error.none;
}
fn note<C>(self_:Walker<C>&,kind:Kind,name:u32,member:u32,source:Id)->Error {let found,error=self_.reference(kind,name,member,source);return error;}
fn patternEvent<C>(self_:Walker<C>&,id:Id,bind:bool)->Error {if bind {return self_.push(Event.pattern_bind {id, ..});}return self_.push(Event.pattern_read {id, ..});}
fn pattern<C>(self_:Walker<C>&,id:Id,bind:bool)->Error {
 if id==0 {return blot_error::Error.none;}let node=self_.tree.node(id);
 match node.tag {
  blot_parse_ast::tag_pattern_name=>{if bind&&node.a!=0 {self_.locals.push(node.a);}},
  blot_parse_ast::tag_pattern_value=>{if !bind {{ let propagated_error = self_.note(Kind.name,node.a,0,id); if propagated_error != blot_error::Error.none { return propagated_error; } }}},
  blot_parse_ast::tag_pattern_field=>{if node.b==0 {if bind&&node.a!=0 {self_.locals.push(node.a);}}else {{ let propagated_error = self_.patternEvent(node.b,bind); if propagated_error != blot_error::Error.none { return propagated_error; } }}},
  blot_parse_ast::tag_pattern_constructor=>{if node.b!=0 {{ let propagated_error = self_.patternEvent(node.b,bind); if propagated_error != blot_error::Error.none { return propagated_error; } }}},
  blot_parse_ast::tag_pattern_row,blot_parse_ast::tag_pattern_product,blot_parse_ast::tag_pattern_record=>{let ast_children_source=id;let ast_children_count=self_.tree.children(ast_children_source).len;var index=ast_children_count;while index!=0 {index--;{ let propagated_error = self_.patternEvent(self_.tree.children(ast_children_source)[index],bind); if propagated_error != blot_error::Error.none { return propagated_error; } }}},
  _=>{},
 }
 return blot_error::Error.none;
}
fn processNode<C>(self_:Walker<C>&,id:Id)->Error {
 let n=self_.tree.node(id);
 match n.tag {
  blot_parse_ast::tag_name=>{{ let propagated_error = self_.note(Kind.name,n.a,0,id); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_lambda=>{{ let propagated_error = self_.push(Event.restore {self_.locals.len, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(n.b); if propagated_error != blot_error::Error.none { return propagated_error; } }let parameter=self_.tree.parameter(n.a);if !parameter.is_unit&&parameter.name!=0 {{ let propagated_error = self_.push(Event.bind {parameter.name, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }}},
  blot_parse_ast::tag_block=>{{ let propagated_error = self_.push(Event.restore {self_.locals.len, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.list(self_.tree.children(id)); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(n.c); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_let_stmt=>{let binding=self_.tree.binding(id);{ let propagated_error = self_.push(Event.pattern_bind {binding.pattern, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(binding.fallback); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.push(Event.pattern_read {binding.pattern, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(binding.value); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_use_stmt,blot_parse_ast::tag_iterator_bind=>{if n.a!=0 {{ let propagated_error = self_.push(Event.bind {n.a, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }}{ let propagated_error = self_.visit(n.b); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_field_access=>{
   var parent=n.a;while self_.tree.node(parent).tag==blot_parse_ast::tag_group {parent=self_.tree.node(parent).a;}let base=self_.tree.node(parent);var found=false;
   if base.tag==blot_parse_ast::tag_name {let result,error=self_.reference(Kind.qualified,base.a,n.b,id);if error!=blot_error::Error.none {return error;}found=result;}
   if !found {{ let propagated_error = self_.visit(n.a); if propagated_error != blot_error::Error.none { return propagated_error; } }}
  },
  blot_parse_ast::tag_field=>{if n.b==0 {{ let propagated_error = self_.note(Kind.name,n.a,0,id); if propagated_error != blot_error::Error.none { return propagated_error; } }}else {{ let propagated_error = self_.visit(n.b); if propagated_error != blot_error::Error.none { return propagated_error; } }}},
  blot_parse_ast::tag_binary=>{{ let propagated_error = self_.visit(n.c); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(n.b); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.note(Kind.operator,n.a,0,id); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_infix_chain=>{let tails=blot_parse_ast::List {n.b,n.c, ..};let ast_tails_count=self_.tree.list(tails).len;let ast_visit_1_source=tails;let ast_visit_1_count=self_.tree.list(ast_visit_1_source).len;for ast_visit_1_index in 0..ast_visit_1_count {let tail=self_.tree.list(ast_visit_1_source)[ast_visit_1_index];{ let propagated_error = self_.note(Kind.operator,self_.tree.node(tail).a,0,tail); if propagated_error != blot_error::Error.none { return propagated_error; } }}{ let propagated_error = self_.list(self_.tree.list(tails)); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(n.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_operator_tail,blot_parse_ast::tag_unary=>{{ let propagated_error = self_.visit(n.b); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_group,blot_parse_ast::tag_return_stmt,blot_parse_ast::tag_function_return_stmt,blot_parse_ast::tag_yield_stmt=>{{ let propagated_error = self_.visit(n.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_forever_stmt=>{{ let propagated_error = self_.push(Event.restore {self_.locals.len, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(n.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_apply,blot_parse_ast::tag_index_access=>{{ let propagated_error = self_.visit(n.b); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(n.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_rebind_stmt=>{{ let propagated_error = self_.push(Event.restore {self_.locals.len, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(n.b); if propagated_error != blot_error::Error.none { return propagated_error; } }if self_.self_name!=0 {{ let propagated_error = self_.push(Event.bind {self_.self_name, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }}{ let propagated_error = self_.visit(n.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_if_expr,blot_parse_ast::tag_if_stmt=>{{ let propagated_error = self_.push(Event.restore {self_.locals.len, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(n.c); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.push(Event.restore {self_.locals.len, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(n.b); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(n.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_if_let_stmt,blot_parse_ast::tag_for_stmt=>{
   let ast_metadata_start=(n.c) as i64;let ast_metadata_count=self_.tree.extra.items[ast_metadata_start..].len;{ let propagated_error = self_.push(Event.restore {self_.locals.len, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }
   if n.tag==blot_parse_ast::tag_if_let_stmt {{ let propagated_error = self_.visit(self_.tree.extra.items[ast_metadata_start..ast_metadata_start+ast_metadata_count][1]); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.push(Event.restore {self_.locals.len, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(self_.tree.extra.items[ast_metadata_start..ast_metadata_start+ast_metadata_count][0]); if propagated_error != blot_error::Error.none { return propagated_error; } }}else {{ let propagated_error = self_.visit(self_.tree.extra.items[ast_metadata_start..ast_metadata_start+ast_metadata_count][1]); if propagated_error != blot_error::Error.none { return propagated_error; } }if ast_metadata_count>3 {{ let propagated_error = self_.visit(self_.tree.extra.items[ast_metadata_start..ast_metadata_start+ast_metadata_count][3]); if propagated_error != blot_error::Error.none { return propagated_error; } }}}
   { let propagated_error = self_.push(Event.pattern_bind {n.a, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.push(Event.pattern_read {n.a, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }if n.tag==blot_parse_ast::tag_for_stmt {{ let propagated_error = self_.visit(self_.tree.extra.items[ast_metadata_start..ast_metadata_start+ast_metadata_count][0]); if propagated_error != blot_error::Error.none { return propagated_error; } }}{ let propagated_error = self_.visit(n.b); if propagated_error != blot_error::Error.none { return propagated_error; } }
  },
  blot_parse_ast::tag_range_stmt=>{{ let propagated_error = self_.push(Event.restore {self_.locals.len, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(n.c); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(n.b); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(n.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_case_expr,blot_parse_ast::tag_request_case=>{{ let propagated_error = self_.list(self_.tree.list(blot_parse_ast::List {n.b,n.c, ..})); if propagated_error != blot_error::Error.none { return propagated_error; } }let ast_inputs_start=(n.a) as i64;let ast_inputs_count=self_.tree.extra.items[ast_inputs_start..n.a+2].len;{ let propagated_error = self_.list(self_.tree.list(blot_parse_ast::List {self_.tree.extra.items[ast_inputs_start..ast_inputs_start+ast_inputs_count][0],self_.tree.extra.items[ast_inputs_start..ast_inputs_start+ast_inputs_count][1], ..})); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_case_arm=>{
   let ast_metadata_start=(n.c) as i64;let ast_metadata_count=self_.tree.extra.items[ast_metadata_start..n.c+2].len;let rows=blot_parse_ast::List {n.a,n.b, ..};let ast_rows_count=self_.tree.list(rows).len;{ let propagated_error = self_.push(Event.restore {self_.locals.len, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(self_.tree.extra.items[ast_metadata_start..ast_metadata_start+ast_metadata_count][1]); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(self_.tree.extra.items[ast_metadata_start..ast_metadata_start+ast_metadata_count][0]); if propagated_error != blot_error::Error.none { return propagated_error; } }if ast_rows_count!=0 {{ let propagated_error = self_.push(Event.pattern_bind {self_.tree.list(rows)[0], ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }}
   var index=ast_rows_count;while index!=0 {index--;{ let propagated_error = self_.push(Event.pattern_read {self_.tree.list(rows)[index], ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }}
  },
  blot_parse_ast::tag_request_arm=>{{ let propagated_error = self_.push(Event.restore {self_.locals.len, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(n.c); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.push(Event.pattern_bind {n.b, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.push(Event.pattern_read {n.b, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.visit(n.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_product,blot_parse_ast::tag_array,blot_parse_ast::tag_record=>{{ let propagated_error = self_.list(self_.tree.children(id)); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_attribute=>{{ let propagated_error = self_.visit(n.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  _=>{},
 }
 return blot_error::Error.none;
}
reusable[] var owned_references:Reference[>..]=[];
fn release(values:const Reference[:]) {if values.len==0 {return;}owned_references.free_slice(values);}
fn discover<C>(tree:const Tree&,declaration:Id,resolver:C&,self_name:u32,transitions:i64&,limit:i64)->const Reference[:],Error {
 var work:Event[>..<]=[];var locals:u32[>..<]=[];var references:Reference[>..<]=[];var walker=Walker<C> {tree,resolver,self_name,transitions,limit,work,locals,references, ..};
 let error=walk(walker,declaration);if error!=blot_error::Error.none {return default<const Reference[:]>(),error;}
 let result=owned_references.alloc_slice(references.len);for reference,index in references {result[index]=reference;}return result,blot_error::Error.none;
}
fn walk<C>(walker:Walker<C>&,declaration:Id)->Error {
 let value=walker.tree.value_decl(declaration);{ let propagated_error = walker.visit(value.body); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = walker.list(walker.tree.list(value.attributes)); if propagated_error != blot_error::Error.none { return propagated_error; } }
 while walker.work.len!=0 {
  let event=walker.work[walker.work.len-1];walker.work.resize(walker.work.len-1);if walker.transitions>=walker.limit {return blot_error::Error.type_limit;}walker.transitions++;
  match event {
   visit value=>{{ let propagated_error = walker.processNode(value.id); if propagated_error != blot_error::Error.none { return propagated_error; } }},restore value=>{walker.locals.resize(value.count);},bind value=>{walker.locals.push(value.name);},pattern_bind value=>{{ let propagated_error = walker.pattern(value.id,true); if propagated_error != blot_error::Error.none { return propagated_error; } }},pattern_read value=>{{ let propagated_error = walker.pattern(value.id,false); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  }
 }
 return blot_error::Error.none;
}
