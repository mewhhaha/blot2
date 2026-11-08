// Loop carries follow statement suites; nested expressions own their successors.
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
 var index=self_.trail.items.len;while index>mark {index--;let name=self_.trail.items[index];var remove=false;{let found=blot_support_pooled_map::get(self_.shadowed,name);assert(found!=null);let count=copy(found);if count==1 {remove=true;}else {found=count-1;}}if remove {blot_support_pooled_map::remove(self_.shadowed,name);}}blot_support_pooled_buffer::resize(self_.trail,mark);
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
   blot_parse_ast::tag_field_access,blot_parse_ast::tag_index_access=>{root=value.a;},
   _=>{return blot_error::Error.none;},
  }
 }
 if root!=0 {return blot_error::Error.target_limit;}return blot_error::Error.none;
}
recursive fn scope(self_:Collector&,body:u32,pat:u32,depth:i64)->Error {
 if body==0 {return blot_error::Error.none;}let mark=self_.trail.items.len;var error=self_.pattern(pat,depth+1);if error==blot_error::Error.none {error=self_.suite(body,depth+1);}self_.restore(mark);return error;
}
recursive fn caseScope(self_:Collector&,arm:blot_parse_ast::Node,body:u32,depth:i64)->Error {
 let mark=self_.trail.items.len;let error=self_.casePatterns(arm,body,depth);self_.restore(mark);return error;
}
recursive fn casePatterns(self_:Collector&,arm:blot_parse_ast::Node,body:u32,depth:i64)->Error {
 let rows=blot_parse_ast::List{arm.a,arm.b,..};let row_count=self_.tree.list(rows).len;for row_index in 0..row_count {let row=self_.tree.list(rows)[row_index];let child_count=self_.tree.children(row).len;for child_index in 0..child_count {let id=self_.tree.children(row)[child_index];{ let propagated_error = self_.pattern(id,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }}}return self_.suite(body,depth+1);
}
recursive fn suite(self_:Collector&,body:u32,depth:i64)->Error {
 if depth>=1024 {return blot_error::Error.target_limit;}
 let child_count=self_.tree.children(body).len;for child_index in 0..child_count {let id=self_.tree.children(body)[child_index];
  let value=self_.tree.node(id);
  match value.tag {
   blot_parse_ast::tag_rebind_stmt=>{{ let propagated_error = self_.target(value.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_let_stmt=>{{ let propagated_error = self_.pattern(value.a,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_use_stmt=>{{ let propagated_error = self_.shadow(value.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_if_stmt=>{{ let propagated_error = self_.scope(value.b,0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.scope(value.c,0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_if_let_stmt=>{let bodies=self_.tree.extra.items[value.c..value.c+2];let first_body=bodies[0];let second_body=bodies[1];{ let propagated_error = self_.scope(first_body,value.a,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.scope(second_body,0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_request_case=>{let arms=blot_parse_ast::List{value.b,value.c,..};let arm_count=self_.tree.list(arms).len;for arm_index in 0..arm_count {let id=self_.tree.list(arms)[arm_index];let arm=self_.tree.node(id);{ let propagated_error = self_.scope(arm.c,arm.b,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }}},
   blot_parse_ast::tag_case_expr=>{let arms=blot_parse_ast::List{value.b,value.c,..};let arm_count=self_.tree.list(arms).len;for arm_index in 0..arm_count {let id=self_.tree.list(arms)[arm_index];let arm=self_.tree.node(id);let arm_body=self_.tree.extra.items[arm.c+1];if self_.tree.node(arm_body).tag!=blot_parse_ast::tag_block||self_.tree.node(arm_body).c!=0 {continue;}{ let propagated_error = self_.caseScope(arm,arm_body,depth); if propagated_error != blot_error::Error.none { return propagated_error; } }}},
   blot_parse_ast::tag_for_stmt=>{{ let propagated_error = self_.scope(self_.tree.extra.items[value.c+1],value.a,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_range_stmt=>{{ let propagated_error = self_.scope(value.c,0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_forever_stmt=>{{ let propagated_error = self_.scope(value.a,0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   _=>{},
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
