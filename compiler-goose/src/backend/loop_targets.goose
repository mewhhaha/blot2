// Loop carries follow statement suites; nested expressions own their successors.
namespace blot_backend_loop_targets;
import dictionary;
import parse.ast;
import parse.symbols;
import support.error;
type Error=blot_error::Error;
type Tree=blot_parse_ast::Tree;
type Pool=blot_parse_symbols::Pool;
type Symbol=u32;
struct Collector {tree:const Tree&,pool:const Pool&,shadowed:dictionary<Symbol,u32>&,seen:dictionary<Symbol,bool>&,trail:Symbol[>..<]&,targets:Symbol[>..<]&}
fn shadow(self_:Collector&,name:Symbol)->Error {
 if name==0||self_.pool.get(name)=="_" {return blot_error::Error.none;}let count .= ::get_or_insert(self_.shadowed,name,0);if count==0xffffffff {return blot_error::Error.target_limit;}count++;self_.trail.push(name);return blot_error::Error.none;
}
fn restore(self_:Collector&,mark:i64) {
 var index=self_.trail.len;while index>mark {index--;let name=self_.trail[index];var remove=false;{let found=self_.shadowed.get(name);assert(found!=null);let count=copy(found);if count==1 {remove=true;}else {found=count-1;}}if remove {self_.shadowed.remove(name);}}self_.trail.resize(mark);
}
recursive fn pattern(self_:Collector&,id:u32,depth:i64)->Error {
 if id==0 {return blot_error::Error.none;}if depth>=1024 {return blot_error::Error.target_limit;}let value=self_.tree.node(id);
 match value.tag {
  blot_parse_ast::tag_pattern_name=>{{ let propagated_error = self_.shadow(value.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  blot_parse_ast::tag_pattern_product,blot_parse_ast::tag_pattern_record=>{for child in self_.tree.children(id) {{ let propagated_error = self_.pattern(child,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }}},
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
   blot_parse_ast::tag_name=>{if self_.shadowed.contains(value.a)||self_.seen.contains(value.a) {return blot_error::Error.none;}self_.seen.insert(value.a,true);self_.targets.push(value.a);return blot_error::Error.none;},
   blot_parse_ast::tag_field_access,blot_parse_ast::tag_index_access=>{root=value.a;},
   _=>{return blot_error::Error.none;},
  }
 }
 if root!=0 {return blot_error::Error.target_limit;}return blot_error::Error.none;
}
recursive fn scope(self_:Collector&,body:u32,pat:u32,depth:i64)->Error {
 if body==0 {return blot_error::Error.none;}let mark=self_.trail.len;var error=self_.pattern(pat,depth+1);if error==blot_error::Error.none {error=self_.suite(body,depth+1);}self_.restore(mark);return error;
}
recursive fn caseScope(self_:Collector&,arm:blot_parse_ast::Node,body:u32,depth:i64)->Error {
 let mark=self_.trail.len;let error=self_.casePatterns(arm,body,depth);self_.restore(mark);return error;
}
recursive fn casePatterns(self_:Collector&,arm:blot_parse_ast::Node,body:u32,depth:i64)->Error {
 for row in self_.tree.list(blot_parse_ast::List {arm.a,arm.b, ..}) {for id in self_.tree.children(row) {{ let propagated_error = self_.pattern(id,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }}}return self_.suite(body,depth+1);
}
recursive fn suite(self_:Collector&,body:u32,depth:i64)->Error {
 if depth>=1024 {return blot_error::Error.target_limit;}
 for id in self_.tree.children(body) {
  let value=self_.tree.node(id);
  match value.tag {
   blot_parse_ast::tag_rebind_stmt=>{{ let propagated_error = self_.target(value.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_let_stmt=>{{ let propagated_error = self_.pattern(value.a,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_use_stmt=>{{ let propagated_error = self_.shadow(value.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_if_stmt=>{{ let propagated_error = self_.scope(value.b,0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.scope(value.c,0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_if_let_stmt=>{let bodies=self_.tree.extra.items[value.c..value.c+2];{ let propagated_error = self_.scope(bodies[0],value.a,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.scope(bodies[1],0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_request_case=>{for id in self_.tree.list(blot_parse_ast::List {value.b,value.c, ..}) {let arm=self_.tree.node(id);{ let propagated_error = self_.scope(arm.c,arm.b,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }}},
   blot_parse_ast::tag_case_expr=>{for id in self_.tree.list(blot_parse_ast::List {value.b,value.c, ..}) {let arm=self_.tree.node(id);let arm_body=self_.tree.extra.items[arm.c+1];if self_.tree.node(arm_body).tag!=blot_parse_ast::tag_block||self_.tree.node(arm_body).c!=0 {continue;}{ let propagated_error = self_.caseScope(arm,arm_body,depth); if propagated_error != blot_error::Error.none { return propagated_error; } }}},
   blot_parse_ast::tag_for_stmt=>{{ let propagated_error = self_.scope(self_.tree.extra.items[value.c+1],value.a,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_range_stmt=>{{ let propagated_error = self_.scope(value.c,0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   blot_parse_ast::tag_forever_stmt=>{{ let propagated_error = self_.scope(value.a,0,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   _=>{},
  }
 }
 return blot_error::Error.none;
}
reusable[] var returned:Symbol[>..]=[];
fn release(values:const Symbol[:]) {if values.len==0 {return;}let first:const Symbol& =values[0];let at=returned.index_of(first);assert(at>=0);returned.free_slice(returned[at..at+values.len]);}
fn collect(tree:const Tree&,pool:const Pool&,iterator_pattern:u32,body:u32)->const Symbol[:],Error {
 // Owners stay in this nonrecursive wrapper, and the result owns a separate run.
 var shadowed:dictionary<Symbol,u32> =dictionary<Symbol,u32> {};var seen:dictionary<Symbol,bool> =dictionary<Symbol,bool> {};var trail:Symbol[>..<]=[];var targets:Symbol[>..<]=[];
 var collector=Collector {tree,pool,shadowed,seen,trail,targets, ..};let error=collector.scope(body,iterator_pattern,0);if error!=blot_error::Error.none {return [],error;}let result=returned.alloc_slice(targets.len);for value,index in targets {result[index]=value;}return result,blot_error::Error.none;
}
