// Immutable graph correspondence preserves binder identities across constructor sharing.
namespace blot_reuse_frontend_graph_correspondence;
import std;
import dictionary;
import check.frozen_types;
import check.types;
import check.effects;
import support.error;
import support.option;
import support.pooled_map;
type Error=blot_error::Error;
type Tag=blot_check_types::Tag;
type List=blot_check_types::List;
let missing:u32=0xffffffff;
enum Reason {none,size_limit,depth_limit,work_limit,invalid_index,type_sharing,row_sharing,row_variable_sharing,variable_sharing,unsupported_type,unsupported_row,tag,content,catalog}
struct Diagnostic {reason:Reason=Reason.none,located:bool=false,row:bool=false,left:u32=0,right:u32=0,left_tag:Tag=Tag.absent,right_tag:Tag=Tag.absent,depth:i64=0,remaining:i64=0}
struct Bijection {forward:u32[:]=[],reverse:u32[:]=[]}
reusable[] var bijection_words:u32[>..]=[];
fn initBijection(left:i64,right:i64)->Bijection {let forward=bijection_words.alloc_slice(left);let reverse=bijection_words.alloc_slice(right);for &item in forward {item=missing;}for &item in reverse {item=missing;}return Bijection {forward,reverse};}
fn deinit(self:Bijection&) {if self.forward.len!=0 {bijection_words.free_slice(self.forward);}if self.reverse.len!=0 {bijection_words.free_slice(self.reverse);}self=Bijection {};}
fn enter(self:Bijection&,left:u32,right:u32)->bool,Error {
 if left>=self.forward.len||right>=self.reverse.len {return false,Error.invalid_index;}let prior=self.forward[left];
 if prior!=missing {if prior!=right||self.reverse[right]!=left {return false,Error.sharing;}return true,Error.none;}
 if self.reverse[right]!=missing {return false,Error.sharing;}self.forward[left]=right;self.reverse[right]=left;return false,Error.none;
}
type Pairs=blot_support_pooled_map::Map<u64,bool>;
type Variables=blot_support_pooled_map::Map<u32,u32>;
reusable[] var pair_slots:dictionary_slot<u64,bool>[>..]=[];
reusable[] var variable_slots:dictionary_slot<u32,u32>[>..]=[];
struct Match {
 left:blot_check_frozen_types::Source=blot_check_frozen_types::Source.inactive,right:blot_check_frozen_types::Source=blot_check_frozen_types::Source.inactive,
 types:Bijection=Bijection {},rows:Bijection=Bijection {},row_variables:Bijection=Bijection {},type_pairs:Pairs=Pairs {},row_pairs:Pairs=Pairs {},variables:Variables=Variables {},reverse_variables:Variables=Variables {},remaining:i64=65536,diagnostic:Diagnostic=Diagnostic {},
}
fn init(left:const blot_check_frozen_types::Graph&,right:const blot_check_frozen_types::Graph&)->blot_support::Option<Match>,Error {
 if left.nodes.len>65536||right.nodes.len>65536||left.rows.len>65536||right.rows.len>65536||left.row_variable_count>65536||right.row_variable_count>65536 {return blot_support::none<Match>(),Error.none;}
 let result=Match {left:blot_check_frozen_types::Source.frozen {copy(left)},right:blot_check_frozen_types::Source.frozen {copy(right)},types:initBijection(left.nodes.len,right.nodes.len),rows:initBijection(left.rows.len,right.rows.len),row_variables:initBijection(left.row_variable_count,right.row_variable_count)};
 return blot_support::some(result),Error.none;
}
fn deinit(self:Match&) {self.types.deinit();self.rows.deinit();self.row_variables.deinit();blot_support_pooled_map::deinit(self.type_pairs,pair_slots);blot_support_pooled_map::deinit(self.row_pairs,pair_slots);blot_support_pooled_map::deinit(self.variables,variable_slots);blot_support_pooled_map::deinit(self.reverse_variables,variable_slots);self=Match {};}
fn decline(self:Match&,reason:Reason)->Error {if self.diagnostic.reason==Reason.none {self.diagnostic.reason=reason;}return Error.declined;}
fn work(self:Match&,depth:i64)->Error {if depth>=128 {return self.decline(Reason.depth_limit);}if self.remaining==0 {return self.decline(Reason.work_limit);}self.remaining--;return Error.none;}
fn enter(self:Match&,map:Bijection&,left:u32,right:u32,reason:Reason)->bool,Error {
 let known,error=map.enter(left,right);if error==Error.invalid_index {return false,self.decline(Reason.invalid_index);}if error!=Error.none {return false,self.decline(reason);}return known,Error.none;
}
fn structuralEnter(self:Match&,map:Bijection&,pairs:Pairs&,left:u32,right:u32)->bool,Error {
 let known,error=map.enter(left,right);if error==Error.none {return known,Error.none;}if error==Error.invalid_index {return false,self.decline(Reason.invalid_index);}
 let key=(left as u64)<<32|right as u64;let found=blot_support_pooled_map::contains(pairs,key);blot_support_pooled_map::insert(pairs,key,true,pair_slots);return found,Error.none;
}
fn ty(self:Match&,left:u32,right:u32)->Error {return self.typeDepth(left,right,0);}
recursive fn typeDepth(self:Match&,left:u32,right:u32,depth:i64)->Error {
 let error=self.typeNode(left,right,depth);
 if error==Error.declined&&!self.diagnostic.located {
  self.diagnostic.located=true;self.diagnostic.left=left;self.diagnostic.right=right;if left<self.types.forward.len {self.diagnostic.left_tag=self.left.node(left).tag;}if right<self.types.reverse.len {self.diagnostic.right_tag=self.right.node(right).tag;}self.diagnostic.depth=depth;self.diagnostic.remaining=self.remaining;
 }
 return error;
}
recursive fn typeNode(self:Match&,left:u32,right:u32,depth:i64)->Error {
 { let propagated_error = self.work(depth); if propagated_error != Error.none { return propagated_error; } }if left==0||right==0 {if left!=right {return self.decline(Reason.content);}return Error.none;}
 let known,error=self.structuralEnter(self.types,self.type_pairs,left,right);if error!=Error.none {return error;}if known {return Error.none;}
 let before=self.left.node(left);let after=self.right.node(right);if before.tag!=after.tag {return self.decline(Reason.tag);}
 match before.tag {
  Tag.unit,Tag.boolean,Tag.unsigned32,Tag.floating32,Tag.never=>{if before.a!=after.a||before.b!=after.b||before.c!=after.c {return self.decline(Reason.content);}},
  Tag.variable=>{
   if before.b!=0||after.b!=0||before.c!=0||after.c!=0 {return self.decline(Reason.content);}
   let prior=blot_support_pooled_map::get(self.variables,before.a);
   if prior {if prior!=after.a {return self.decline(Reason.variable_sharing);}}
   else {if blot_support_pooled_map::contains(self.reverse_variables,after.a) {return self.decline(Reason.variable_sharing);}blot_support_pooled_map::insert(self.reverse_variables,after.a,before.a,variable_slots);blot_support_pooled_map::insert(self.variables,before.a,after.a,variable_slots);}
  },
  Tag.function=>{{ let propagated_error = self.typeDepth(before.a,after.a,depth+1); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.typeDepth(before.b,after.b,depth+1); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.rowDepth(before.c,after.c,depth+1); if propagated_error != Error.none { return propagated_error; } }},
  Tag.array,Tag.list,Tag.cursor,Tag.resolver=>{if before.b!=after.b||before.c!=after.c {return self.decline(Reason.content);}{ let propagated_error = self.typeDepth(before.a,after.a,depth+1); if propagated_error != Error.none { return propagated_error; } }},
  Tag.provider=>{if before.b!=after.b {return self.decline(Reason.content);}{ let propagated_error = self.typeDepth(before.a,after.a,depth+1); if propagated_error != Error.none { return propagated_error; } }{ let propagated_error = self.rowDepth(before.c,after.c,depth+1); if propagated_error != Error.none { return propagated_error; } }},
  Tag.product=>{if before.c!=after.c {return self.decline(Reason.content);}{ let propagated_error = self.typeListDepth(List {before.a,before.b},List {after.a,after.b},depth+1); if propagated_error != Error.none { return propagated_error; } }},
  Tag.record=>{
   if before.b!=after.b||before.c!=after.c {return self.decline(Reason.content);}
   for index in 0..before.b {{ let propagated_error = self.work(depth+1); if propagated_error != Error.none { return propagated_error; } }let from=self.left.recordField(before,index);let to=self.right.recordField(after,index);if from.name!=to.name {return self.decline(Reason.content);}{ let propagated_error = self.typeDepth(from.ty,to.ty,depth+1); if propagated_error != Error.none { return propagated_error; } }}
  },
  Tag.nominal,Tag.type_constructor,Tag.projection=>{
   if before.a!=after.a||before.b!=after.b {return self.decline(Reason.content);}
   if before.tag==Tag.type_constructor {if before.c!=after.c {return self.decline(Reason.content);}}
   else {if before.tag==Tag.projection&&self.left.projectionMember(before)!=self.right.projectionMember(after) {return self.decline(Reason.content);}let arguments=self.left.nominalArguments(before);let supplied=self.right.nominalArguments(after);if arguments.len!=supplied.len {return self.decline(Reason.content);}for from,index in arguments {{ let propagated_error = self.typeDepth(from,supplied[index],depth+1); if propagated_error != Error.none { return propagated_error; } }}}
  },
  _=>{return self.decline(Reason.unsupported_type);},
 }
 return Error.none;
}
fn typeList(self:Match&,left:List,right:List)->Error {return self.typeListDepth(left,right,0);}
recursive fn typeListDepth(self:Match&,left:List,right:List,depth:i64)->Error {{ let propagated_error = self.work(depth); if propagated_error != Error.none { return propagated_error; } }if left.len!=right.len {return self.decline(Reason.content);}let to=self.right.list(right);for from,index in self.left.list(left) {{ let propagated_error = self.typeDepth(from,to[index],depth+1); if propagated_error != Error.none { return propagated_error; } }}return Error.none;}
fn rowVariables(self:Match&,left:List,right:List)->Error {
 if left.len!=right.len {return self.decline(Reason.content);}let after=self.right.list(right);
 for from,index in self.left.list(left) {let to=after[index];{ let propagated_error = self.work(0); if propagated_error != Error.none { return propagated_error; } }if blot_check_types::rowKeyFormal(from).present||blot_check_types::rowKeyFormal(to).present {return self.decline(Reason.content);}let entered,error=self.enter(self.row_variables,from,to,Reason.row_variable_sharing);if error!=Error.none {return error;}}
 return Error.none;
}
fn rowList(self:Match&,left:List,right:List)->Error {{ let propagated_error = self.work(0); if propagated_error != Error.none { return propagated_error; } }if left.len!=right.len {return self.decline(Reason.content);}let after=self.right.list(right);for from,index in self.left.list(left) {{ let propagated_error = self.rowDepth(from,after[index],1); if propagated_error != Error.none { return propagated_error; } }}return Error.none;}
recursive fn rowDepth(self:Match&,left:u32,right:u32,depth:i64)->Error {
 let error=self.rowNode(left,right,depth);if error==Error.declined&&!self.diagnostic.located {self.diagnostic.located=true;self.diagnostic.row=true;self.diagnostic.left=left;self.diagnostic.right=right;self.diagnostic.depth=depth;self.diagnostic.remaining=self.remaining;}return error;
}
recursive fn rowNode(self:Match&,left:u32,right:u32,depth:i64)->Error {
 { let propagated_error = self.work(depth); if propagated_error != Error.none { return propagated_error; } }let known,error=self.structuralEnter(self.rows,self.row_pairs,left,right);if error!=Error.none {return error;}if known {return Error.none;}
 let before=self.left.row(left);let after=self.right.row(right);if before.cursor!=0||after.cursor!=0||before.labels.len!=after.labels.len||blot_check_effects::tailCode(before.tail)!=blot_check_effects::tailCode(after.tail) {return self.decline(Reason.content);}
 match before.tail {
  blot_check_effects::Tail.closed=>{},
  blot_check_effects::Tail.variable value=>{match after.tail {blot_check_effects::Tail.variable current=>{let known,error=self.enter(self.row_variables,value.value,current.value,Reason.row_variable_sharing);if error!=Error.none {return error;}},_=>{return self.decline(Reason.content);}}},
  blot_check_effects::Tail.formal value=>{match after.tail {blot_check_effects::Tail.formal current=>{{ let propagated_error = self.typeDepth(value.value,current.value,depth+1); if propagated_error != Error.none { return propagated_error; } }},_=>{return self.decline(Reason.content);}}},
  blot_check_effects::Tail.parameter=>{return self.decline(Reason.unsupported_row);},
 }
 let supplied=self.right.rowLabels(after.labels);
 for from,index in self.left.rowLabels(before.labels) {
  { let propagated_error = self.work(depth+1); if propagated_error != Error.none { return propagated_error; } }let old=self.left.operation(from);let current=self.right.operation(supplied[index]);if old.identity!=current.identity {return self.decline(Reason.content);}
  if old.instance.unit==0&&current.instance.unit==0&&old.instance.decl!=0&&current.instance.decl!=0 {{ let propagated_error = self.typeDepth(old.instance.decl,current.instance.decl,depth+1); if propagated_error != Error.none { return propagated_error; } }}else if old.instance!=current.instance {return self.decline(Reason.content);}
  { let propagated_error = self.typeListDepth(old.arguments,current.arguments,depth+1); if propagated_error != Error.none { return propagated_error; } }
 }
 return Error.none;
}
