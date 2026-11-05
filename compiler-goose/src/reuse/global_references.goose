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
fn push<C>(self:Walker<C>&,event:Event)->Error {self.work.push(event);return Error.none;}
fn visit<C>(self:Walker<C>&,id:Id)->Error {if id!=0 {{ let propagated_error = self.push(Event.visit {id}); if propagated_error != Error.none { return propagated_error; } }}return Error.none;}
fn list<C>(self:Walker<C>&,ids:const Id[:])->Error {var index=ids.len;while index!=0 {index--;{ let propagated_error = self.visit(ids[index]); if propagated_error != Error.none { return propagated_error; } }}return Error.none;}
fn reference<C>(self:Walker<C>&,kind:Kind,name:u32,member:u32,source:Id)->bool,Error {
 let binding,error=self.resolver.resolve(kind,name,member,self.locals[..]);if error!=Error.none {return false,error;}
 if !binding.present {return false,Error.none;}self.references.push(Reference {binding.value,source});return true,Error.none;
}
fn note<C>(self:Walker<C>&,kind:Kind,name:u32,member:u32,source:Id)->Error {let found,error=self.reference(kind,name,member,source);return error;}
fn patternEvent<C>(self:Walker<C>&,id:Id,bind:bool)->Error {if bind {return self.push(Event.pattern_bind {id});}return self.push(Event.pattern_read {id});}
fn pattern<C>(self:Walker<C>&,id:Id,bind:bool)->Error {
 if id==0 {return Error.none;}let node=self.tree.node(id);
 match node.tag {
  blot_parse_ast::tag_pattern_name=>{if bind&&node.a!=0 {self.locals.push(node.a);}},
  blot_parse_ast::tag_pattern_value=>{if !bind {{ let propagated_error = self.note(Kind.name,node.a,0,id); if propagated_error != Error.none { return propagated_error; } }}},
  blot_parse_ast::tag_pattern_field=>{if node.b==0 {if bind&&node.a!=0 {self.locals.push(node.a);}}else {{ let propagated_error = self.patternEvent(node.b,bind); if propagated_error != Error.none { return propagated_error; } }}},
  blot_parse_ast::tag_pattern_constructor=>{if node.b!=0 {{ let propagated_error = self.patternEvent(node.b,bind); if propagated_error != Error.none { return propagated_error; } }}},
  blot_parse_ast::tag_pattern_row,blot_parse_ast::tag_pattern_product,blot_parse_ast::tag_pattern_record=>{let children=self.tree.children(id);var index=children.len;while index!=0 {index--;{ let propagated_error = self.patternEvent(children[index],bind); if propagated_error != Error.none { return propagated_error; } }}},
  _=>{},
 }
 return Error.none;
}
fn processNode<C>(self:Walker<C>&,id:Id)->Error {
 let n=self.tree.node(id);
 match n.tag {
  blot_parse_ast::tag_name=>{{ let propagated_error = self.note(Kind.name,n.a,0,id); if propagated_error != Error.none { return propagated_error; } }},
  blot_parse_ast::tag_lambda=>{{ let propagated_error = self.push(Event.restore {self.locals.len}); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(n.b); if propagated_error != Error.none { return propagated_error; } }let parameter=self.tree.parameter(n.a);if !parameter.is_unit&&parameter.name!=0 {{ let propagated_error = self.push(Event.bind {parameter.name}); if propagated_error != Error.none { return propagated_error; } }}},
  blot_parse_ast::tag_block=>{{ let propagated_error = self.push(Event.restore {self.locals.len}); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.list(self.tree.children(id)); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(n.c); if propagated_error != Error.none { return propagated_error; } }},
  blot_parse_ast::tag_let_stmt=>{let binding=self.tree.binding(id);{ let propagated_error = self.push(Event.pattern_bind {binding.pattern}); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(binding.fallback); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.push(Event.pattern_read {binding.pattern}); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(binding.value); if propagated_error != Error.none { return propagated_error; } }},
  blot_parse_ast::tag_use_stmt,blot_parse_ast::tag_iterator_bind=>{if n.a!=0 {{ let propagated_error = self.push(Event.bind {n.a}); if propagated_error != Error.none { return propagated_error; } }}{ let propagated_error = self.visit(n.b); if propagated_error != Error.none { return propagated_error; } }},
  blot_parse_ast::tag_field_access=>{
   var parent=n.a;while self.tree.node(parent).tag==blot_parse_ast::tag_group {parent=self.tree.node(parent).a;}let base=self.tree.node(parent);var found=false;
   if base.tag==blot_parse_ast::tag_name {let result,error=self.reference(Kind.qualified,base.a,n.b,id);if error!=Error.none {return error;}found=result;}
   if !found {{ let propagated_error = self.visit(n.a); if propagated_error != Error.none { return propagated_error; } }}
  },
  blot_parse_ast::tag_field=>{if n.b==0 {{ let propagated_error = self.note(Kind.name,n.a,0,id); if propagated_error != Error.none { return propagated_error; } }}else {{ let propagated_error = self.visit(n.b); if propagated_error != Error.none { return propagated_error; } }}},
  blot_parse_ast::tag_binary=>{{ let propagated_error = self.visit(n.c); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(n.b); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.note(Kind.operator,n.a,0,id); if propagated_error != Error.none { return propagated_error; } }},
  blot_parse_ast::tag_infix_chain=>{let tails=self.tree.list(blot_parse_ast::List {n.b,n.c});for tail in tails {{ let propagated_error = self.note(Kind.operator,self.tree.node(tail).a,0,tail); if propagated_error != Error.none { return propagated_error; } }}{ let propagated_error = self.list(tails); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(n.a); if propagated_error != Error.none { return propagated_error; } }},
  blot_parse_ast::tag_operator_tail,blot_parse_ast::tag_unary=>{{ let propagated_error = self.visit(n.b); if propagated_error != Error.none { return propagated_error; } }},
  blot_parse_ast::tag_group,blot_parse_ast::tag_return_stmt,blot_parse_ast::tag_function_return_stmt,blot_parse_ast::tag_yield_stmt=>{{ let propagated_error = self.visit(n.a); if propagated_error != Error.none { return propagated_error; } }},
  blot_parse_ast::tag_forever_stmt=>{{ let propagated_error = self.push(Event.restore {self.locals.len}); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(n.a); if propagated_error != Error.none { return propagated_error; } }},
  blot_parse_ast::tag_apply,blot_parse_ast::tag_index_access=>{{ let propagated_error = self.visit(n.b); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(n.a); if propagated_error != Error.none { return propagated_error; } }},
  blot_parse_ast::tag_rebind_stmt=>{{ let propagated_error = self.push(Event.restore {self.locals.len}); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(n.b); if propagated_error != Error.none { return propagated_error; } }if self.self_name!=0 {{ let propagated_error = self.push(Event.bind {self.self_name}); if propagated_error != Error.none { return propagated_error; } }}{ let propagated_error = self.visit(n.a); if propagated_error != Error.none { return propagated_error; } }},
  blot_parse_ast::tag_if_expr,blot_parse_ast::tag_if_stmt=>{{ let propagated_error = self.push(Event.restore {self.locals.len}); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(n.c); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.push(Event.restore {self.locals.len}); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(n.b); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(n.a); if propagated_error != Error.none { return propagated_error; } }},
  blot_parse_ast::tag_if_let_stmt,blot_parse_ast::tag_for_stmt=>{
   let metadata=self.tree.extra.items[n.c..];{ let propagated_error = self.push(Event.restore {self.locals.len}); if propagated_error != Error.none { return propagated_error; } }
   if n.tag==blot_parse_ast::tag_if_let_stmt {{ let propagated_error = self.visit(metadata[1]); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.push(Event.restore {self.locals.len}); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(metadata[0]); if propagated_error != Error.none { return propagated_error; } }}else {{ let propagated_error = self.visit(metadata[1]); if propagated_error != Error.none { return propagated_error; } }if metadata.len>3 {{ let propagated_error = self.visit(metadata[3]); if propagated_error != Error.none { return propagated_error; } }}}
   { let propagated_error = self.push(Event.pattern_bind {n.a}); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.push(Event.pattern_read {n.a}); if propagated_error != Error.none { return propagated_error; } }if n.tag==blot_parse_ast::tag_for_stmt {{ let propagated_error = self.visit(metadata[0]); if propagated_error != Error.none { return propagated_error; } }}{ let propagated_error = self.visit(n.b); if propagated_error != Error.none { return propagated_error; } }
  },
  blot_parse_ast::tag_range_stmt=>{{ let propagated_error = self.push(Event.restore {self.locals.len}); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(n.c); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(n.b); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(n.a); if propagated_error != Error.none { return propagated_error; } }},
  blot_parse_ast::tag_case_expr,blot_parse_ast::tag_request_case=>{{ let propagated_error = self.list(self.tree.list(blot_parse_ast::List {n.b,n.c})); if propagated_error != Error.none { return propagated_error; } }let inputs=self.tree.extra.items[n.a..n.a+2];{ let propagated_error = self.list(self.tree.list(blot_parse_ast::List {inputs[0],inputs[1]})); if propagated_error != Error.none { return propagated_error; } }},
  blot_parse_ast::tag_case_arm=>{
   let metadata=self.tree.extra.items[n.c..n.c+2];let rows=self.tree.list(blot_parse_ast::List {n.a,n.b});{ let propagated_error = self.push(Event.restore {self.locals.len}); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(metadata[1]); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(metadata[0]); if propagated_error != Error.none { return propagated_error; } }if rows.len!=0 {{ let propagated_error = self.push(Event.pattern_bind {rows[0]}); if propagated_error != Error.none { return propagated_error; } }}
   var index=rows.len;while index!=0 {index--;{ let propagated_error = self.push(Event.pattern_read {rows[index]}); if propagated_error != Error.none { return propagated_error; } }}
  },
  blot_parse_ast::tag_request_arm=>{{ let propagated_error = self.push(Event.restore {self.locals.len}); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(n.c); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.push(Event.pattern_bind {n.b}); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.push(Event.pattern_read {n.b}); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.visit(n.a); if propagated_error != Error.none { return propagated_error; } }},
  blot_parse_ast::tag_product,blot_parse_ast::tag_array,blot_parse_ast::tag_record=>{{ let propagated_error = self.list(self.tree.children(id)); if propagated_error != Error.none { return propagated_error; } }},
  blot_parse_ast::tag_attribute=>{{ let propagated_error = self.visit(n.a); if propagated_error != Error.none { return propagated_error; } }},
  _=>{},
 }
 return Error.none;
}
reusable[] var owned_references:Reference[>..]=[];
fn release(values:const Reference[:]) {if values.len==0 {return;}let first:const Reference&=values[0];let at=owned_references.index_of(first);assert(at>=0);owned_references.free_slice(owned_references[at..at+values.len]);}
fn discover<C>(tree:const Tree&,declaration:Id,resolver:C&,self_name:u32,transitions:i64&,limit:i64)->const Reference[:],Error {
 var work:Event[>..<]=[];var locals:u32[>..<]=[];var references:Reference[>..<]=[];var walker=Walker<C> {tree,resolver,self_name,transitions,limit,work,locals,references};
 let error=walk(walker,declaration);if error!=Error.none {return [],error;}
 let result=owned_references.alloc_slice(references.len);for reference,index in references {result[index]=reference;}return result,Error.none;
}
fn walk<C>(walker:Walker<C>&,declaration:Id)->Error {
 let value=walker.tree.value_decl(declaration);{ let propagated_error = walker.visit(value.body); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = walker.list(walker.tree.list(value.attributes)); if propagated_error != Error.none { return propagated_error; } }
 while walker.work.len!=0 {
  let event=walker.work[walker.work.len-1];walker.work.resize(walker.work.len-1);if walker.transitions>=walker.limit {return Error.type_limit;}walker.transitions++;
  match event {
   Event.visit value=>{{ let propagated_error = walker.processNode(value.id); if propagated_error != Error.none { return propagated_error; } }},Event.restore value=>{walker.locals.resize(value.count);},Event.bind value=>{walker.locals.push(value.name);},Event.pattern_bind value=>{{ let propagated_error = walker.pattern(value.id,true); if propagated_error != Error.none { return propagated_error; } }},Event.pattern_read value=>{{ let propagated_error = walker.pattern(value.id,false); if propagated_error != Error.none { return propagated_error; } }},
  }
 }
 return Error.none;
}
