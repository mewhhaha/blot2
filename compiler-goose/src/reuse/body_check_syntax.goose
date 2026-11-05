// Source ownership and evaluation-order syntax fingerprints for body receipts.
namespace blot_reuse_body_check_cache;
import .body_check_cache;
struct ShapeVisit {id:u32,depth:u32}
reusable[] var shape_visits:ShapeVisit[>..]=[];
struct Shape {
 pending:ShapeVisit[:],pending_len:i64=0,depth:u32=0,tree:const Tree&,pool:const Pool&,owner:blot_parse_ast::List,start:u32,
 hash:blot_support_blake3::State=blot_support_blake3::init(),
}
fn word(self:Shape&,value:u32) {hashWord(self.hash,value);}
fn flag(self:Shape&,value:bool) {var bit:u32=0;if value {bit=1;}self.word(bit);}
fn name(self:Shape&,symbol:u32) {let text=self.pool.get(symbol);self.word(text.len as u32);self.hash.update(text);}
fn edge(self:Shape&,id:u32)->bool {
 if id==0 {self.word(0);return true;}if id<self.owner.start || id-self.owner.start>=self.owner.len {return false;}
 self.word(id-self.owner.start+1);if self.depth>=128 || self.pending_len==self.pending.len {return false;}
 self.pending[self.pending_len]=ShapeVisit{id,self.depth+1, ..};self.pending_len+=1;return true;
}
fn edges(self:Shape&,ids:const u32[:])->bool {self.word(ids.len as u32);for id in ids {if !self.edge(id) {return false;}}return true;}
fn list(self:Shape&,range:blot_parse_ast::List)->bool {return self.edges(self.tree.list(range));}
fn node(self:Shape&,id:u32)->bool {
 let n=self.tree.node(id);let span=self.tree.span(id);if span.start<self.start || span.start>span.end {return false;}
 self.word(n.tag);self.word(span.start-self.start);self.word(span.end-self.start);
 match n.tag {
 blot_parse_ast::tag_task_region=>{return n.a==0 && n.b==0 && n.c==0;},
 blot_parse_ast::tag_value_decl=>{let d=self.tree.value_decl(id);self.name(d.name);self.flag(d.runtime);self.flag(d.exported);let traits=self.tree.declaration_traits(id);self.flag(traits.private);self.flag(traits.is_opaque);return self.edges([d.annotation,d.where_node,d.body]) && self.list(d.attributes);},
 blot_parse_ast::tag_lambda=>{return self.edges([n.a,n.c,n.b]);},
 blot_parse_ast::tag_if_expr,blot_parse_ast::tag_if_stmt,blot_parse_ast::tag_range_stmt,blot_parse_ast::tag_request_arm=>{return self.edges([n.a,n.b,n.c]);},
 blot_parse_ast::tag_parameter=>{let p=self.tree.parameter(id);self.name(p.name);self.flag(p.is_unit);return self.edges([p.annotation,p.where_node]);},
 blot_parse_ast::tag_apply,blot_parse_ast::tag_index_access,blot_parse_ast::tag_type_apply,blot_parse_ast::tag_type_effect,blot_parse_ast::tag_type_code=>{return self.edges([n.a,n.b]);},
 blot_parse_ast::tag_type_function=>{return self.edges([n.a,n.b,n.c]);},
 blot_parse_ast::tag_group,blot_parse_ast::tag_type_witness,blot_parse_ast::tag_type_descriptor,blot_parse_ast::tag_forever_stmt,blot_parse_ast::tag_attribute=>{return self.edge(n.a);},
 blot_parse_ast::tag_name,blot_parse_ast::tag_intrinsic,blot_parse_ast::tag_string,blot_parse_ast::tag_selector,blot_parse_ast::tag_type_name,blot_parse_ast::tag_pattern_name,blot_parse_ast::tag_pattern_value,blot_parse_ast::tag_constructor_ref=>{self.name(n.a);return true;},
 blot_parse_ast::tag_field_access=>{self.name(n.b);return self.edge(n.a);},
 blot_parse_ast::tag_type_binder=>{self.name(n.a);return self.edge(n.b);},
 blot_parse_ast::tag_field,blot_parse_ast::tag_type_field,blot_parse_ast::tag_pattern_field,blot_parse_ast::tag_pattern_constructor,blot_parse_ast::tag_iterator_bind=>{self.name(n.a);return self.edge(n.b);},
 blot_parse_ast::tag_binary=>{self.name(n.a);return self.edges([n.b,n.c]);},
 blot_parse_ast::tag_operator_tail=>{self.name(n.a);self.word(n.c);return self.edge(n.b);},
 blot_parse_ast::tag_unary=>{self.name(n.a);return self.edge(n.b);},
 blot_parse_ast::tag_infix_chain=>{return self.edge(n.a) && self.list(blot_parse_ast::List{n.b,n.c, ..});},
 blot_parse_ast::tag_where_clause,blot_parse_ast::tag_product,blot_parse_ast::tag_type_product,blot_parse_ast::tag_type_array,blot_parse_ast::tag_type_record,blot_parse_ast::tag_pattern_product,blot_parse_ast::tag_pattern_record,blot_parse_ast::tag_pattern_row=>{return self.list(blot_parse_ast::List{n.a,n.b, ..});},
 blot_parse_ast::tag_array=>{self.word(n.c);return self.list(blot_parse_ast::List{n.a,n.b, ..});},
 blot_parse_ast::tag_record=>{self.name(n.a);return self.list(blot_parse_ast::List{n.b,n.c, ..});},
 blot_parse_ast::tag_block,blot_parse_ast::tag_effect_row=>{return self.list(blot_parse_ast::List{n.a,n.b, ..}) && self.edge(n.c);},
 blot_parse_ast::tag_constraint=>{self.name(n.a);self.name(n.b);let x=self.tree.extra.items[n.c..n.c+3];return self.list(blot_parse_ast::List{x[0],x[1], ..}) && self.edge(x[2]);},
 blot_parse_ast::tag_let_stmt=>{let b=self.tree.binding(id);return self.edges([b.where_node,b.annotation,b.value,b.pattern,b.fallback]);},
 blot_parse_ast::tag_rebind_stmt,blot_parse_ast::tag_yield_stmt=>{return self.edges([n.a,n.b]);},
 blot_parse_ast::tag_function_return_stmt=>{return self.edge(n.a);},
 blot_parse_ast::tag_use_stmt=>{self.name(n.a);return self.edges([n.b,n.c]);},
 blot_parse_ast::tag_return_stmt=>{self.word(n.b);return self.edge(n.a);},
 blot_parse_ast::tag_for_stmt=>{let x=self.tree.extra.items[n.c..n.c+4];self.word(x[2]);return self.edges([n.a,n.b,x[0],x[1],x[3]]);},
 blot_parse_ast::tag_if_let_stmt=>{return self.edges([n.a,n.b]) && self.edges(self.tree.extra.items[n.c..n.c+2]);},
 blot_parse_ast::tag_case_expr,blot_parse_ast::tag_request_case=>{let x=self.tree.extra.items[n.a..n.a+2];return self.list(blot_parse_ast::List{x[0],x[1], ..}) && self.list(blot_parse_ast::List{n.b,n.c, ..});},
 blot_parse_ast::tag_case_arm=>{return self.list(blot_parse_ast::List{n.a,n.b, ..}) && self.edges(self.tree.extra.items[n.c..n.c+2]);},
 blot_parse_ast::tag_type_forall,blot_parse_ast::tag_type_exists,blot_parse_ast::tag_package_pack=>{return self.list(blot_parse_ast::List{n.a,n.b, ..}) && self.edges(self.tree.extra.items[n.c..n.c+2]);},
 blot_parse_ast::tag_package_unpack=>{let x=self.tree.extra.items[n.c..n.c+3];self.name(x[1]);return self.edge(n.a) && self.list(blot_parse_ast::List{n.b,x[0], ..}) && self.edge(x[2]);},
 blot_parse_ast::tag_type_usage=>{self.word(n.a);self.name(n.c);return self.edge(n.b);},
 blot_parse_ast::tag_quantified_binder=>{self.name(n.a);self.word(n.b);return true;},
 blot_parse_ast::tag_integer,blot_parse_ast::tag_float,blot_parse_ast::tag_boolean,blot_parse_ast::tag_pattern_integer,blot_parse_ast::tag_pattern_boolean=>{self.word(n.a);return true;},
 blot_parse_ast::tag_unit,blot_parse_ast::tag_break_stmt,blot_parse_ast::tag_continue_stmt=>{return true;},
 _=>{return false;},
 }
}
struct Syntax {ids:u32[:],digest:Digest}
fn syntax(tree:const Tree&,pool:const Pool&,root:u32)->blot_support::Option<Syntax>,Error {
 let owner,present=tree.declaration_nodes(root);if !present || owner.len>4096 {return blot_support::none<Syntax>(),Error.none;}
 let pending=shape_visits.alloc_slice(owner.len);let seen=owned_bool.alloc_slice(owner.len);for &value in seen {value=false;}
 let ids=owned_u32.alloc_slice(owner.len);var shape=Shape{pending:pending,tree:tree,pool:pool,owner:owner,start:tree.span(root).start, ..};
 let accepted=syntaxInto(shape,root,seen,ids);shape_visits.free_slice(pending);owned_bool.free_slice(seen);
 if !accepted {owned_u32.free_slice(ids);return blot_support::none<Syntax>(),Error.none;}
 return blot_support::some(Syntax{ids,shape.hash.final(), ..}),Error.none;
}
fn syntaxInto(shape:Shape&,root:u32,seen:bool[:],ids:u32[:])->bool {
 var count:i64=0;for index in shape.owner.len+1 {var start=root;if index!=0 {start=shape.owner.start+index-1;}if seen[start-shape.owner.start] {continue;}
 shape.pending[shape.pending_len]=ShapeVisit{start,0, ..};shape.pending_len+=1;
 while shape.pending_len!=0 {shape.pending_len-=1;let visit=shape.pending[shape.pending_len];if seen[visit.id-shape.owner.start] {continue;}seen[visit.id-shape.owner.start]=true;ids[count]=visit.id;count+=1;shape.depth=visit.depth;let first=shape.pending_len;if !shape.node(visit.id) {return false;}
 var left=first;var right=shape.pending_len;while left<right {right-=1;let old=shape.pending[left];shape.pending[left]=shape.pending[right];shape.pending[right]=old;left+=1;}
 }}assert(count==ids.len);return true;
}
fn releaseSyntax(value:Syntax) {releaseOwned(value.ids);}
fn position(ids:const u32[:],id:u32)->blot_support::Option<u32> {for value,index in ids {if value==id {return blot_support::some(index as u32);}}return blot_support::none<u32>();}
