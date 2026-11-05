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
struct Diagnostic {reason:Reason=Reason.none,located:bool=false,row:bool=false,left:u32=0,right:u32=0,left_tag:Tag=blot_check_types::Tag.absent,right_tag:Tag=blot_check_types::Tag.absent,depth:i64=0,remaining:i64=0}
struct Bijection {forward:u32[:]=default<u32[:]>(),reverse:u32[:]=default<u32[:]>()}
reusable[] var bijection_words:u32[>..]=[];
fn initBijection(left:i64,right:i64)->Bijection {let forward=bijection_words.alloc_slice(left);let reverse=bijection_words.alloc_slice(right);for &item in forward {item=missing;}for &item in reverse {item=missing;}return Bijection {forward,reverse, ..};}
fn deinit(self_:Bijection&) {if self_.forward.len!=0 {bijection_words.free_slice(self_.forward);}if self_.reverse.len!=0 {bijection_words.free_slice(self_.reverse);}self_=Bijection {..};}
fn enter(self_:Bijection&,left:u32,right:u32)->bool,Error {
 if left>=self_.forward.len||right>=self_.reverse.len {return false,blot_error::Error.invalid_index;}let prior=self_.forward[left];
 if prior!=missing {if prior!=right||self_.reverse[right]!=left {return false,blot_error::Error.sharing;}return true,blot_error::Error.none;}
 if self_.reverse[right]!=missing {return false,blot_error::Error.sharing;}self_.forward[left]=right;self_.reverse[right]=left;return false,blot_error::Error.none;
}
type Pairs=blot_support_pooled_map::Map<u64,bool>;
type Variables=blot_support_pooled_map::Map<u32,u32>;
reusable[] var pair_slots:dictionary_slot<u64,bool>[>..]=[];
reusable[] var variable_slots:dictionary_slot<u32,u32>[>..]=[];
struct Match {
 left:blot_check_frozen_types::Source=blot_check_frozen_types::Source.inactive,right:blot_check_frozen_types::Source=blot_check_frozen_types::Source.inactive,
 types:Bijection=Bijection {..},rows:Bijection=Bijection {..},row_variables:Bijection=Bijection {..},type_pairs:Pairs=Pairs {..},row_pairs:Pairs=Pairs {..},variables:Variables=Variables {..},reverse_variables:Variables=Variables {..},remaining:i64=65536,diagnostic:Diagnostic=Diagnostic {..},
}
fn init(left:const blot_check_frozen_types::Graph&,right:const blot_check_frozen_types::Graph&)->blot_support::Option<Match>,Error {
 if left.nodes.len>65536||right.nodes.len>65536||left.rows.len>65536||right.rows.len>65536||left.row_variable_count>65536||right.row_variable_count>65536 {return blot_support::none<Match>(),blot_error::Error.none;}
 let result=Match {left:blot_check_frozen_types::Source.frozen {copy(left), ..},right:blot_check_frozen_types::Source.frozen {copy(right), ..},types:initBijection(left.nodes.len,right.nodes.len),rows:initBijection(left.rows.len,right.rows.len),row_variables:initBijection(left.row_variable_count,right.row_variable_count), ..};
 return blot_support::some(result),blot_error::Error.none;
}
fn deinit(self_:Match&) {self_.types.deinit();self_.rows.deinit();self_.row_variables.deinit();blot_support_pooled_map::deinit(self_.type_pairs,pair_slots);blot_support_pooled_map::deinit(self_.row_pairs,pair_slots);blot_support_pooled_map::deinit(self_.variables,variable_slots);blot_support_pooled_map::deinit(self_.reverse_variables,variable_slots);self_=Match {..};}
fn decline(self_:Match&,reason:Reason)->Error {if self_.diagnostic.reason==Reason.none {self_.diagnostic.reason=reason;}return blot_error::Error.declined;}
fn work(self_:Match&,depth:i64)->Error {if depth>=128 {return self_.decline(Reason.depth_limit);}if self_.remaining==0 {return self_.decline(Reason.work_limit);}self_.remaining--;return blot_error::Error.none;}
fn enter(self_:Match&,map:Bijection&,left:u32,right:u32,reason:Reason)->bool,Error {
 let known,error=map.enter(left,right);if error==blot_error::Error.invalid_index {return false,self_.decline(Reason.invalid_index);}if error!=blot_error::Error.none {return false,self_.decline(reason);}return known,blot_error::Error.none;
}
fn structuralEnter(self_:Match&,map:Bijection&,pairs:Pairs&,left:u32,right:u32)->bool,Error {
 let known,error=map.enter(left,right);if error==blot_error::Error.none {return known,blot_error::Error.none;}if error==blot_error::Error.invalid_index {return false,self_.decline(Reason.invalid_index);}
 let key=(left as u64)<<32|right as u64;let found=blot_support_pooled_map::contains(pairs,key);blot_support_pooled_map::insert(pairs,key,true,pair_slots);return found,blot_error::Error.none;
}
fn ty(self_:Match&,left:u32,right:u32)->Error {return self_.typeDepth(left,right,0);}
recursive fn typeDepth(self_:Match&,left:u32,right:u32,depth:i64)->Error {
 let error=self_.typeNode(left,right,depth);
 if error==blot_error::Error.declined&&!self_.diagnostic.located {
  self_.diagnostic.located=true;self_.diagnostic.left=left;self_.diagnostic.right=right;if left<self_.types.forward.len {self_.diagnostic.left_tag=self_.left.node(left).tag;}if right<self_.types.reverse.len {self_.diagnostic.right_tag=self_.right.node(right).tag;}self_.diagnostic.depth=depth;self_.diagnostic.remaining=self_.remaining;
 }
 return error;
}
recursive fn typeNode(self_:Match&,left:u32,right:u32,depth:i64)->Error {
 { let propagated_error = self_.work(depth); if propagated_error != blot_error::Error.none { return propagated_error; } }if left==0||right==0 {if left!=right {return self_.decline(Reason.content);}return blot_error::Error.none;}
 let known,error=self_.structuralEnter(self_.types,self_.type_pairs,left,right);if error!=blot_error::Error.none {return error;}if known {return blot_error::Error.none;}
 let before=self_.left.node(left);let after=self_.right.node(right);if before.tag!=after.tag {return self_.decline(Reason.tag);}
 match before.tag {
  unit,boolean,unsigned32,floating32,never=>{if before.a!=after.a||before.b!=after.b||before.c!=after.c {return self_.decline(Reason.content);}},
  variable=>{
   if before.b!=0||after.b!=0||before.c!=0||after.c!=0 {return self_.decline(Reason.content);}
   let prior=blot_support_pooled_map::get(self_.variables,before.a);
   if prior {if prior!=after.a {return self_.decline(Reason.variable_sharing);}}
   else {if blot_support_pooled_map::contains(self_.reverse_variables,after.a) {return self_.decline(Reason.variable_sharing);}blot_support_pooled_map::insert(self_.reverse_variables,after.a,before.a,variable_slots);blot_support_pooled_map::insert(self_.variables,before.a,after.a,variable_slots);}
  },
  function=>{{ let propagated_error = self_.typeDepth(before.a,after.a,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.typeDepth(before.b,after.b,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.rowDepth(before.c,after.c,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  array,list,cursor,resolver=>{if before.b!=after.b||before.c!=after.c {return self_.decline(Reason.content);}{ let propagated_error = self_.typeDepth(before.a,after.a,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  provider=>{if before.b!=after.b {return self_.decline(Reason.content);}{ let propagated_error = self_.typeDepth(before.a,after.a,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = self_.rowDepth(before.c,after.c,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  product=>{if before.c!=after.c {return self_.decline(Reason.content);}{ let propagated_error = self_.typeListDepth(List {before.a,before.b, ..},List {after.a,after.b, ..},depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  record=>{
   if before.b!=after.b||before.c!=after.c {return self_.decline(Reason.content);}
   for index in 0..before.b {{ let propagated_error = self_.work(depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }let from=self_.left.recordField(before,index);let to=self_.right.recordField(after,index);if from.name!=to.name {return self_.decline(Reason.content);}{ let propagated_error = self_.typeDepth(from.ty,to.ty,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }}
  },
  nominal,type_constructor,projection=>{
   if before.a!=after.a||before.b!=after.b {return self_.decline(Reason.content);}
   if before.tag==blot_check_types::Tag.type_constructor {if before.c!=after.c {return self_.decline(Reason.content);}}
   else {if before.tag==blot_check_types::Tag.projection&&self_.left.projectionMember(before)!=self_.right.projectionMember(after) {return self_.decline(Reason.content);}let arguments=self_.left.nominalArguments(before);let supplied=self_.right.nominalArguments(after);if arguments.len!=supplied.len {return self_.decline(Reason.content);}for from,index in arguments {{ let propagated_error = self_.typeDepth(from,supplied[index],depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }}}
  },
  _=>{return self_.decline(Reason.unsupported_type);},
 }
 return blot_error::Error.none;
}
fn typeList(self_:Match&,left:List,right:List)->Error {return self_.typeListDepth(left,right,0);}
recursive fn typeListDepth(self_:Match&,left:List,right:List,depth:i64)->Error {{ let propagated_error = self_.work(depth); if propagated_error != blot_error::Error.none { return propagated_error; } }if left.len!=right.len {return self_.decline(Reason.content);}let to=self_.right.list(right);for from,index in self_.left.list(left) {{ let propagated_error = self_.typeDepth(from,to[index],depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }}return blot_error::Error.none;}
fn rowVariables(self_:Match&,left:List,right:List)->Error {
 if left.len!=right.len {return self_.decline(Reason.content);}let after=self_.right.list(right);
 for from,index in self_.left.list(left) {let to=after[index];{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }if blot_check_types::rowKeyFormal(from).present||blot_check_types::rowKeyFormal(to).present {return self_.decline(Reason.content);}let entered,error=self_.enter(self_.row_variables,from,to,Reason.row_variable_sharing);if error!=blot_error::Error.none {return error;}}
 return blot_error::Error.none;
}
fn rowList(self_:Match&,left:List,right:List)->Error {{ let propagated_error = self_.work(0); if propagated_error != blot_error::Error.none { return propagated_error; } }if left.len!=right.len {return self_.decline(Reason.content);}let after=self_.right.list(right);for from,index in self_.left.list(left) {{ let propagated_error = self_.rowDepth(from,after[index],1); if propagated_error != blot_error::Error.none { return propagated_error; } }}return blot_error::Error.none;}
recursive fn rowDepth(self_:Match&,left:u32,right:u32,depth:i64)->Error {
 let error=self_.rowNode(left,right,depth);if error==blot_error::Error.declined&&!self_.diagnostic.located {self_.diagnostic.located=true;self_.diagnostic.row=true;self_.diagnostic.left=left;self_.diagnostic.right=right;self_.diagnostic.depth=depth;self_.diagnostic.remaining=self_.remaining;}return error;
}
recursive fn rowNode(self_:Match&,left:u32,right:u32,depth:i64)->Error {
 { let propagated_error = self_.work(depth); if propagated_error != blot_error::Error.none { return propagated_error; } }let known,error=self_.structuralEnter(self_.rows,self_.row_pairs,left,right);if error!=blot_error::Error.none {return error;}if known {return blot_error::Error.none;}
 let before=self_.left.row(left);let after=self_.right.row(right);if before.cursor!=0||after.cursor!=0||before.labels.len!=after.labels.len||blot_check_effects::tailCode(before.tail)!=blot_check_effects::tailCode(after.tail) {return self_.decline(Reason.content);}
 match before.tail {
  closed=>{},
  variable value=>{match after.tail {variable current=>{let known,error=self_.enter(self_.row_variables,value.value,current.value,Reason.row_variable_sharing);if error!=blot_error::Error.none {return error;}},_=>{return self_.decline(Reason.content);}}},
  formal value=>{match after.tail {formal current=>{{ let propagated_error = self_.typeDepth(value.value,current.value,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }},_=>{return self_.decline(Reason.content);}}},
  parameter=>{return self_.decline(Reason.unsupported_row);},
 }
 let supplied=self_.right.rowLabels(after.labels);
 for from,index in self_.left.rowLabels(before.labels) {
  { let propagated_error = self_.work(depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }let old=self_.left.operation(from);let current=self_.right.operation(supplied[index]);if old.identity!=current.identity {return self_.decline(Reason.content);}
  if old.instance.unit==0&&current.instance.unit==0&&old.instance.decl!=0&&current.instance.decl!=0 {{ let propagated_error = self_.typeDepth(old.instance.decl,current.instance.decl,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }}else if old.instance!=current.instance {return self_.decline(Reason.content);}
  { let propagated_error = self_.typeListDepth(old.arguments,current.arguments,depth+1); if propagated_error != blot_error::Error.none { return propagated_error; } }
 }
 return blot_error::Error.none;
}
