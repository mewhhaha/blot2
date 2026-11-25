// Loop carries follow statement suites and record builders that publish successors.
namespace blot_backend_loop_targets;
import dictionary;
import parse.ast;
import parse.symbols;
import support.error;
import support.pooled_map;
import support.pooled_buffer;
type Error=blot_error::Error;
type Tree=blot_parse_ast::Tree;
type Pool=blot_parse_symbols::Pool;
type Symbol=u32;
type Shadowed=blot_support_pooled_map::Map<Symbol,u32>;
type Seen=blot_support_pooled_map::Map<Symbol,bool>;
type Symbols=blot_support_pooled_buffer::Buffer<Symbol>;
reusable[] var shadow_slots:dictionary_slot<Symbol,u32>[>..]=[];
reusable[] var seen_slots:dictionary_slot<Symbol,bool>[>..]=[];
reusable[] var scratch_words:Symbol[>..]=[];
struct Collector {tree:const Tree&,pool:const Pool&,shadowed:Shadowed=Shadowed{..},seen:Seen=Seen{..},trail:Symbols=Symbols{..},targets:Symbols=Symbols{..}}
fn deinit(self_:Collector&) {
 blot_support_pooled_map::deinit(self_.shadowed,shadow_slots);
 blot_support_pooled_map::deinit(self_.seen,seen_slots);
 blot_support_pooled_buffer::deinit(self_.trail,scratch_words);
 blot_support_pooled_buffer::deinit(self_.targets,scratch_words);
}
fn shadow(self_:Collector&,name:Symbol)->Error {
 if name==0||self_.pool.get(name)=="_" {return blot_error::Error.none;}
 let count .= blot_support_pooled_map::get(self_.shadowed,name);
 if count {if count==0xffffffff {return blot_error::Error.target_limit;}count++;}
 else {blot_support_pooled_map::insert(self_.shadowed,name,1 as u32,shadow_slots);}
 return blot_support_pooled_buffer::push(self_.trail,name,scratch_words);
}
fn restore(self_:Collector&,mark:i64) {
 var index=self_.trail.items.len;while index>mark {index--;let name=self_.trail.items[index];var remove=false;{let found=blot_support_pooled_map::get(self_.shadowed,name);assert(found!=null);let count=copy(found);if count==1 {remove=true;}else {found=count-1;}}if remove {blot_support_pooled_map::remove(self_.shadowed,name,shadow_slots);}}blot_support_pooled_buffer::resize(self_.trail,mark);
}
recursive fn pattern(self_:Collector&,id:u32,depth:i64)->Error {
 if id==0 {return blot_error::Error.none;}if depth>=1024 {return blot_error::Error.target_limit;}let value=self_.tree.node(id);
 match value.tag {
  blot_parse_ast::tag_pattern_name=>{{ let propagated_error = self_.shadow(value.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_pattern_product,blot_parse_ast::tag_pattern_record=>{let child_count=self_.tree.children(id).len;for child_index in 0..child_count {let child=self_.tree.children(id)[child_index];{ let propagated_error = self_.pattern(child,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }}},
  blot_parse_ast::tag_pattern_constructor=>{{ let propagated_error = self_.pattern(value.b,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_pattern_field=>{if value.b==0 {{ let propagated_error = self_.shadow(value.a); if propagated_error != blot_error::Error.none { return propagated_error; } }}else {{ let propagated_error = self_.pattern(value.b,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }}},
  _=>{},
 }
 return blot_error::Error.none;
}
fn target(self_:Collector&,id:u32)->Error {
 var root=id;var steps:i64=0;while root!=0&&steps<1024 {
  steps++;let value=self_.tree.node(root);
  match value.tag {
   blot_parse_ast::tag_name=>{if blot_support_pooled_map::contains(self_.shadowed,value.a)||blot_support_pooled_map::contains(self_.seen,value.a) {return blot_error::Error.none;}blot_support_pooled_map::insert(self_.seen,value.a,true,seen_slots);return blot_support_pooled_buffer::push(self_.targets,value.a,scratch_words);},
   blot_parse_ast::tag_field_access,blot_parse_ast::tag_index_access,blot_parse_ast::tag_comptime_project=>{root=value.a;},
   _=>{return blot_error::Error.none;},
  }
 }
 if root!=0 {return blot_error::Error.target_limit;}return blot_error::Error.none;
}
recursive fn scope(self_:Collector&,body:u32,pat:u32,depth:i64)->Error {
 if body==0 {return blot_error::Error.none;}let mark=self_.trail.items.len;var error=self_.pattern(pat,depth+1);if error==blot_error::Error.none {error=self_.suite(body,depth+1);}self_.restore(mark);return error;
}
recursive fn withHandlerTargets(self_:Collector&,expr:u32,depth:i64)->Error {
 if expr==0||depth>=1024 {return blot_error::Error.none;}
 let node=self_.tree.node(expr);
 if node.tag==blot_parse_ast::tag_group {return self_.withHandlerTargets(node.a,depth+1);}
 if node.tag==blot_parse_ast::tag_record {
  let child_count=self_.tree.children(expr).len;
  for child_index in 0..child_count {
   let field=self_.tree.node(self_.tree.children(expr)[child_index]);
   if field.b!=0 {{ let propagated_error = self_.withHandlerTargets(field.b,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }}
  }
  return blot_error::Error.none;
 }
 if node.tag==blot_parse_ast::tag_lambda {
  let mark=self_.trail.items.len;
  let param=self_.tree.parameter(node.a);
  var error=self_.shadow(param.name);
  if error==blot_error::Error.none {error=self_.withHandlerTargets(node.b,depth+1);}
  self_.restore(mark);
  return error;
 }
 if node.tag==blot_parse_ast::tag_block {return self_.scope(expr,0,depth+1);}
 return blot_error::Error.none;
}
recursive fn comptimeScope(self_:Collector&,node:blot_parse_ast::Node,depth:i64)->Error {
 let mark=self_.trail.items.len;
 var error=self_.shadow(node.a);
 if error==blot_error::Error.none {error=self_.suite(self_.tree.extra.items[node.c],depth+1);}
 self_.restore(mark);
 return error;
}
recursive fn caseArmTargets(self_:Collector&,arm:blot_parse_ast::Node,guard_source:u32,body:u32,depth:i64)->Error {
 let mark=self_.trail.items.len;
 let rows=blot_parse_ast::List{arm.a,arm.b,..};
 let row_count=self_.tree.list(rows).len;
 var error=blot_error::Error.none;
 for row_index in 0..row_count {
  let row=self_.tree.list(rows)[row_index];
  let child_count=self_.tree.children(row).len;
  for child_index in 0..child_count {
   let id=self_.tree.children(row)[child_index];
   error=self_.pattern(id,depth+1);
   if error!=blot_error::Error.none { break; }
  }
  if error!=blot_error::Error.none { break; }
 }
 if error==blot_error::Error.none && guard_source!=0 {
  error=self_.expressionTargets(guard_source,depth+1);
 }
 if error==blot_error::Error.none {
  if self_.tree.node(body).tag==blot_parse_ast::tag_block && self_.tree.node(body).c==0 {
   error=self_.suite(body,depth+1);
  } else {
   error=self_.expressionTargets(body,depth+1);
  }
 }
 self_.restore(mark);
 return error;
}
recursive fn caseExprTargets(self_:Collector&,value:blot_parse_ast::Node,depth:i64)->Error {
 let inputs=blot_parse_ast::List{self_.tree.extra.items[value.a],self_.tree.extra.items[value.a+1],..};
 let input_count=self_.tree.list(inputs).len;
 for input_index in 0..input_count {
  let error=self_.expressionTargets(self_.tree.list(inputs)[input_index],depth+1);
  if error!=blot_error::Error.none { return error; }
 }
 let arms=blot_parse_ast::List{value.b,value.c,..};
 let arm_count=self_.tree.list(arms).len;
 for arm_index in 0..arm_count {
  let id=self_.tree.list(arms)[arm_index];
  let arm=self_.tree.node(id);
  let guard_source=self_.tree.extra.items[arm.c];
  let arm_body=self_.tree.extra.items[arm.c+1];
  let error=self_.caseArmTargets(arm,guard_source,arm_body,depth);
  if error!=blot_error::Error.none { return error; }
 }
 return blot_error::Error.none;
}
recursive fn expressionTargets(self_:Collector&,id:u32,depth:i64)->Error {
 if id==0 {return blot_error::Error.none;}
 if depth>=1024 {return blot_error::Error.target_limit;}
 let node=self_.tree.node(id);
 match node.tag {
  blot_parse_ast::tag_comptime_for=>{return self_.comptimeScope(node,depth+1);},
  blot_parse_ast::tag_case_expr=>{return self_.caseExprTargets(node,depth+1);},
  blot_parse_ast::tag_group,blot_parse_ast::tag_field_access,blot_parse_ast::tag_comptime_project,
  blot_parse_ast::tag_type_witness,blot_parse_ast::tag_return_stmt,blot_parse_ast::tag_function_return_stmt=>{
   return self_.expressionTargets(node.a,depth+1);
  },
  blot_parse_ast::tag_unary,blot_parse_ast::tag_field=>{
   return self_.expressionTargets(node.b,depth+1);
  },
  blot_parse_ast::tag_apply,blot_parse_ast::tag_index_access,blot_parse_ast::tag_binary,blot_parse_ast::tag_if_expr=>{
   var first=node.a;
   var second=node.b;
   if node.tag==blot_parse_ast::tag_binary {first=node.b;second=node.c;}
   let error=self_.expressionTargets(first,depth+1);
   if error!=blot_error::Error.none {return error;}
   let error=self_.expressionTargets(second,depth+1);
   if error!=blot_error::Error.none {return error;}
   if node.tag==blot_parse_ast::tag_if_expr {return self_.expressionTargets(node.c,depth+1);}
  },
  blot_parse_ast::tag_product,blot_parse_ast::tag_array,blot_parse_ast::tag_record=>{
   let count=self_.tree.children(id).len;
   for at in 0..count {
    let error=self_.expressionTargets(self_.tree.children(id)[at],depth+1);
    if error!=blot_error::Error.none {return error;}
   }
  },
  _=>{},
 }
 return blot_error::Error.none;
}
recursive fn suite(self_:Collector&,body:u32,depth:i64)->Error {
 if depth>=1024 {return blot_error::Error.target_limit;}
 let child_count=self_.tree.children(body).len;for child_index in 0..child_count {let id=self_.tree.children(body)[child_index];
  let value=self_.tree.node(id);
  match value.tag {
   blot_parse_ast::tag_rebind_stmt=>{let error=self_.expressionTargets(value.a,depth+1);if error!=blot_error::Error.none {return error;}let error=self_.expressionTargets(value.b,depth+1);if error!=blot_error::Error.none {return error;}{ let propagated_error = self_.target(value.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_let_stmt=>{let binding=self_.tree.binding(id);let error=self_.expressionTargets(binding.value,depth+1);if error!=blot_error::Error.none {return error;}if binding.fallback!=0 {let error=self_.scope(binding.fallback,0,depth+1);if error!=blot_error::Error.none {return error;}}{ let propagated_error = self_.pattern(binding.pattern,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_use_stmt,blot_parse_ast::tag_iterator_bind=>{let error=self_.expressionTargets(value.b,depth+1);if error!=blot_error::Error.none {return error;}{ let propagated_error = self_.shadow(value.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_if_stmt=>{let error=self_.expressionTargets(value.a,depth+1);if error!=blot_error::Error.none {return error;}{ let propagated_error = self_.scope(value.b,0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.scope(value.c,0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_if_let_stmt=>{let error=self_.expressionTargets(value.b,depth+1);if error!=blot_error::Error.none {return error;}let bodies=self_.tree.extra.items[value.c..value.c+2];let first_body=bodies[0];let second_body=bodies[1];{ let propagated_error = self_.scope(first_body,value.a,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.scope(second_body,0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_case_expr=>{let error=self_.caseExprTargets(value,depth+1);if error!=blot_error::Error.none {return error;}},
   blot_parse_ast::tag_for_stmt=>{let error=self_.expressionTargets(value.b,depth+1);if error!=blot_error::Error.none {return error;}let error=self_.expressionTargets(self_.tree.extra.items[value.c],depth+1);if error!=blot_error::Error.none {return error;}{ let propagated_error = self_.scope(self_.tree.extra.items[value.c+1],value.a,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_range_stmt=>{let error=self_.expressionTargets(value.a,depth+1);if error!=blot_error::Error.none {return error;}let error=self_.expressionTargets(value.b,depth+1);if error!=blot_error::Error.none {return error;}{ let propagated_error = self_.scope(value.c,0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_forever_stmt=>{{ let propagated_error = self_.scope(value.a,0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_with_stmt=>{
    let entries=blot_parse_ast::List{value.a,value.b,..};
    let entry_count=self_.tree.list(entries).len;
    for entry_index in 0..entry_count {
     let entry=self_.tree.node(self_.tree.list(entries)[entry_index]);
     if entry.c==1 {{ let propagated_error = self_.withHandlerTargets(entry.b,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }}
    }
    { let propagated_error = self_.scope(value.c,0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }
   },
   blot_parse_ast::tag_comptime_for=>{let error=self_.comptimeScope(value,depth+1);if error!=blot_error::Error.none {return error;}},
   blot_parse_ast::tag_comptime_if=>{let error=self_.expressionTargets(value.a,depth+1);if error!=blot_error::Error.none {return error;}{ let propagated_error = self_.scope(value.b,0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.scope(value.c,0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   _=>{let error=self_.expressionTargets(id,depth+1);if error!=blot_error::Error.none {return error;}},
  }
 }
 return blot_error::Error.none;
}
reusable[] var returned:Symbol[>..]=[];
fn release(values:const Symbol[:]) {if values.len==0 {return;}returned.free_slice(values);}
fn collect(tree:const Tree&,pool:const Pool&,iterator_pattern:u32,body:u32)->const Symbol[:],Error {
 // The collector owns fixed scratch descriptors; results use a separate run.
 var collector=Collector{tree,pool,..};
 let error=collector.scope(body,iterator_pattern,0);
 if error!=blot_error::Error.none {collector.deinit();return default<const Symbol[:]>(),error;}
 let result=returned.alloc_slice(collector.targets.items.len);
 for value,index in collector.targets.items {result[index]=value;}
 collector.deinit();return result,blot_error::Error.none;
}
