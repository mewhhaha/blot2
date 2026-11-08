// Bounded owned semantic graphs for editor holes; IDs are diagnostic-local.
namespace blot_reuse_hole_diagnostics;
import dictionary;
import check.types;
import check.effects;
import parse.ast;
import support.option;
import support.error;
import support.pooled_buffer;
import support.pooled_map;
import support.json;
type Error=blot_error::Error;
type Text=blot_support::Option<const u8[:]>;
type IdOption=blot_support::Option<u32>;
enum Kind {truncated,absent,unit,boolean,unsigned32,floating32,never,variable,function,product,record,nominal,projection,array,list,cursor,type_constructor,resolver,provider,state_provider,effects,operation,row_variable,row_parameter}
struct Span {start:u32=0,len:u32=0}
struct Node {kind:Kind=Kind.truncated,name:Text=blot_support::none<const u8[:]>(),identity:blot_support::Option<blot_check_types::NominalIdentity> =blot_support::none<blot_check_types::NominalIdentity>(),variable:IdOption=blot_support::none<u32>(),children:Span=Span{},effects:IdOption=blot_support::none<u32>()}
struct Edge {name:Text=blot_support::none<const u8[:]>(),ty:u32=0}
struct Binding {name:const u8[:]=default<const u8[:]>(),ty:u32=0,requirements:Span=Span{}}
struct Requirement {kind:blot_check_types::ObligationKind,name:Text=blot_support::none<const u8[:]>(),subject:u32=0,argument:IdOption=blot_support::none<u32>(),result:IdOption=blot_support::none<u32>(),signature:IdOption=blot_support::none<u32>(),explicit:bool=false}
struct Snapshot {expected:u32=0,nodes:Node[:]=default<Node[:]>(),edges:Edge[:]=default<Edge[:]>(),scope:Binding[:]=default<Binding[:]>(),requirements:Requirement[:]=default<Requirement[:]>(),enclosing:Span=Span{},truncated:bool=false}
reusable[] var text_pool:u8[>..]=[];
reusable[] var node_pool:Node[>..]=[];
reusable[] var edge_pool:Edge[>..]=[];
reusable[] var binding_pool:Binding[>..]=[];
reusable[] var requirement_pool:Requirement[>..]=[];
reusable[] var memo_pool:dictionary_slot<u32,u32>[>..]=[];
fn copyText(text:const u8[:])->const u8[:] {let result=text_pool.alloc_slice(text.len);for byte,index in text {result[index]=byte;}return result;}
fn freeText(text:const u8[:]) {if text.len==0 {return;}text_pool.free_slice(text);}
fn freeText(text:Text) {if text.present {freeText(text.value);}}
fn cloneText(text:Text)->Text {if !text.present {return blot_support::none<const u8[:]>();}return blot_support::some(copyText(text.value));}
fn deinit(self_:Snapshot&) {
 for node in self_.nodes {freeText(node.name);}for edge in self_.edges {freeText(edge.name);}for binding in self_.scope {freeText(binding.name);}for requirement in self_.requirements {freeText(requirement.name);}
 if self_.nodes.len!=0 {node_pool.free_slice(self_.nodes);}if self_.edges.len!=0 {edge_pool.free_slice(self_.edges);}if self_.scope.len!=0 {binding_pool.free_slice(self_.scope);}if self_.requirements.len!=0 {requirement_pool.free_slice(self_.requirements);}self_=Snapshot{};
}
fn clone(self_:Snapshot)->Snapshot,Error {
 var result=Snapshot{expected:self_.expected,enclosing:self_.enclosing,truncated:self_.truncated};result.nodes=node_pool.alloc_slice(self_.nodes.len);for node,index in self_.nodes {result.nodes[index]=Node{kind:node.kind,name:cloneText(node.name),identity:node.identity,variable:node.variable,children:node.children,effects:node.effects};}
 result.edges=edge_pool.alloc_slice(self_.edges.len);for edge,index in self_.edges {result.edges[index]=Edge{name:cloneText(edge.name),ty:edge.ty};}result.scope=binding_pool.alloc_slice(self_.scope.len);for binding,index in self_.scope {result.scope[index]=Binding{name:copyText(binding.name),ty:binding.ty,requirements:binding.requirements};}
 result.requirements=requirement_pool.alloc_slice(self_.requirements.len);for requirement,index in self_.requirements {result.requirements[index]=Requirement{kind:requirement.kind,name:cloneText(requirement.name),subject:requirement.subject,argument:requirement.argument,result:requirement.result,signature:requirement.signature,explicit:requirement.explicit};}return result,blot_error::Error.none;
}
fn jsonStringify(self_:Span,writer:blot_json::Writer&)->Error {return blot_json::jsonStringify(self_,writer);}
fn jsonStringify(self_:Node,writer:blot_json::Writer&)->Error {writer.beginObject();writer.key("kind");writer.enumValue(self_.kind);writer.field("name",self_.name);writer.key("identity");if self_.identity.present {writer.beginObject();writer.field("unit",self_.identity.value.unit);writer.field("decl",self_.identity.value.decl);writer.endObject();}else {writer.nullValue();}writer.field("variable",self_.variable);writer.field("children",self_.children);writer.field("effects",self_.effects);writer.endObject();return writer.failure;}
fn jsonStringify(self_:Edge,writer:blot_json::Writer&)->Error {writer.beginObject();writer.field("name",self_.name);writer.field("type",self_.ty);writer.endObject();return writer.failure;}
fn jsonStringify(self_:Binding,writer:blot_json::Writer&)->Error {writer.beginObject();writer.field("name",self_.name);writer.field("type",self_.ty);writer.field("requirements",self_.requirements);writer.endObject();return writer.failure;}
fn jsonStringify(self_:Requirement,writer:blot_json::Writer&)->Error {writer.beginObject();writer.key("kind");writer.enumValue(self_.kind);writer.field("name",self_.name);writer.field("subject",self_.subject);writer.field("argument",self_.argument);writer.field("result",self_.result);writer.field("signature",self_.signature);writer.field("explicit",self_.explicit);writer.endObject();return writer.failure;}
fn jsonStringify(self_:Snapshot,writer:blot_json::Writer&)->Error {writer.beginObject();writer.field("expected",self_.expected);writer.field("nodes",self_.nodes);writer.field("edges",self_.edges);writer.field("scope",self_.scope);writer.field("requirements",self_.requirements);writer.field("enclosing",self_.enclosing);writer.field("truncated",self_.truncated);writer.endObject();return writer.failure;}
struct Builder {nodes:blot_support_pooled_buffer::Buffer<Node> =blot_support_pooled_buffer::Buffer<Node>{},edges:blot_support_pooled_buffer::Buffer<Edge> =blot_support_pooled_buffer::Buffer<Edge>{},scope:blot_support_pooled_buffer::Buffer<Binding> =blot_support_pooled_buffer::Buffer<Binding>{},requirements:blot_support_pooled_buffer::Buffer<Requirement> =blot_support_pooled_buffer::Buffer<Requirement>{},memo:blot_support_pooled_map::Map<u32,u32> =blot_support_pooled_map::Map<u32,u32>{},remaining:i64=1024,name_bytes:i64=0,truncated:bool=false}
fn deinit(self_:Builder&) {for node in self_.nodes.items {freeText(node.name);}for edge in self_.edges.items {freeText(edge.name);}for binding in self_.scope.items {freeText(binding.name);}for requirement in self_.requirements.items {freeText(requirement.name);}self_.nodes.deinit(node_pool);self_.edges.deinit(edge_pool);self_.scope.deinit(binding_pool);self_.requirements.deinit(requirement_pool);self_.memo.deinit(memo_pool);}
fn saveName(self_:Builder&,text:const u8[:])->const u8[:] {var length=min(text.len,16384-self_.name_bytes);while length!=0 && length<text.len && (text[length]&0xc0)==0x80 {length--;}if length<text.len {self_.truncated=true;}self_.name_bytes+=length;return copyText(text[..length]);}
fn addNode(self_:Builder&,value:Node)->u32,Error {let id=self_.nodes.items.len as u32;let error=self_.nodes.push(value,node_pool);if error!=blot_error::Error.none {return 0,error;}return id,blot_error::Error.none;}
fn budget(self_:Builder&,depth:i64)->bool {if self_.remaining==0 || depth>=32 {self_.truncated=true;return false;}self_.remaining--;return true;}
fn save(self_:Builder&,values:const Edge[:])->Span,Error {let start=self_.edges.items.len as u32;let error=self_.edges.append(values,edge_pool);if error!=blot_error::Error.none {return Span{},error;}return Span{start,values.len as u32},blot_error::Error.none;}
fn nodeKind(tag:blot_check_types::Tag)->Kind {match tag {
 absent=>{return Kind.absent;},
 unit=>{return Kind.unit;},
 boolean=>{return Kind.boolean;},
 unsigned32=>{return Kind.unsigned32;},
 floating32=>{return Kind.floating32;},
 never=>{return Kind.never;},
 variable=>{return Kind.variable;},
 function=>{return Kind.function;},
 product=>{return Kind.product;},
 record=>{return Kind.record;},
 nominal=>{return Kind.nominal;},
 projection=>{return Kind.projection;},
 array=>{return Kind.array;},
 list=>{return Kind.list;},
 cursor=>{return Kind.cursor;},
 type_constructor=>{return Kind.type_constructor;},
 resolver=>{return Kind.resolver;},
 provider=>{return Kind.provider;},
 state_provider=>{return Kind.state_provider;},
 _=>{abort("type has no hole diagnostic kind");},}}
recursive fn typeNode<E>(self_:Builder&,engine:E&,ty:u32,depth:i64)->u32,Error {
 if !self_.budget(depth) {return 0,blot_error::Error.none;}let resolved,error=engine.types.resolve(ty,0);if error!=blot_error::Error.none {return 0,error;}let cached .= self_.memo.get(resolved);if cached {return cached,blot_error::Error.none;}
 let value=engine.types.node(resolved);let id,error=self_.addNode(Node{kind:nodeKind(value.tag)});if error!=blot_error::Error.none {return 0,error;}self_.memo.insert(resolved,id,memo_pool);
 var children=blot_support_pooled_buffer::Buffer<Edge>{};var saved=false;
 match value.tag {
  variable=>{self_.nodes.items[id].variable=blot_support::some(value.a);},
  nominal,projection,type_constructor=>{
   self_.nodes.items[id].identity=blot_support::some(blot_check_types::NominalIdentity{value.a,value.b});for nominal in engine.nominals {if nominal.identity.unit==value.a && nominal.identity.decl==value.b {self_.nodes.items[id].name=blot_support::some(self_.saveName(engine.pool.get(nominal.name)));break;}}
   if value.tag==blot_check_types::Tag.projection {let member=engine.types.projectionMember(value);var contract_name:u32=0;for contract in engine.contracts {if contract.identity.unit==value.a && contract.identity.decl==value.b {contract_name=contract.name;break;}}let left=engine.pool.get(contract_name);let right=engine.pool.get(member);let text=text_pool.alloc_slice(left.len+1+right.len);for byte,index in left {text[index]=byte;}text[left.len]='.';for byte,index in right {text[left.len+1+index]=byte;}freeText(self_.nodes.items[id].name);self_.nodes.items[id].name=blot_support::some(self_.saveName(text));text_pool.free_slice(text);}
   if value.tag==blot_check_types::Tag.nominal || value.tag==blot_check_types::Tag.projection {let span=blot_check_types::List{value.c+1,engine.types.nominalArguments(value).len as u32};for index in span.len {if self_.remaining==0 {self_.truncated=true;break;}let child=engine.types.list(span)[index];let projected,error=self_.typeNode(engine,child,depth+1);if error!=blot_error::Error.none {let __cleanup_result_1_0: u32 = 0; let __cleanup_result_1_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_1_0, __cleanup_result_1_1;}let error=children.push(Edge{ty:projected},edge_pool);if error!=blot_error::Error.none {let __cleanup_result_2_0: u32 = 0; let __cleanup_result_2_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_2_0, __cleanup_result_2_1;}}}
  },
  function,state_provider=>{
   for child in [value.a,value.b] {let projected,error=self_.typeNode(engine,child,depth+1);if error!=blot_error::Error.none {let __cleanup_result_3_0: u32 = 0; let __cleanup_result_3_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_3_0, __cleanup_result_3_1;}let error=children.push(Edge{ty:projected},edge_pool);if error!=blot_error::Error.none {let __cleanup_result_4_0: u32 = 0; let __cleanup_result_4_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_4_0, __cleanup_result_4_1;}}
   if value.tag==blot_check_types::Tag.state_provider {let child,error=self_.typeNode(engine,value.c,depth+1);if error!=blot_error::Error.none {let __cleanup_result_5_0: u32 = 0; let __cleanup_result_5_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_5_0, __cleanup_result_5_1;}let error=children.push(Edge{ty:child},edge_pool);if error!=blot_error::Error.none {let __cleanup_result_6_0: u32 = 0; let __cleanup_result_6_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_6_0, __cleanup_result_6_1;}}
   else {let effects,error=self_.row(engine,value.c,depth+1);if error!=blot_error::Error.none {let __cleanup_result_7_0: u32 = 0; let __cleanup_result_7_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_7_0, __cleanup_result_7_1;}self_.nodes.items[id].effects=blot_support::some(effects);}
  },
  array,list,cursor,resolver,provider=>{
   let child,error=self_.typeNode(engine,value.a,depth+1);if error!=blot_error::Error.none {let __cleanup_result_8_0: u32 = 0; let __cleanup_result_8_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_8_0, __cleanup_result_8_1;}let error=children.push(Edge{ty:child},edge_pool);if error!=blot_error::Error.none {let __cleanup_result_9_0: u32 = 0; let __cleanup_result_9_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_9_0, __cleanup_result_9_1;}
   if value.tag==blot_check_types::Tag.provider {let effects,error=self_.row(engine,value.c,depth+1);if error!=blot_error::Error.none {let __cleanup_result_10_0: u32 = 0; let __cleanup_result_10_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_10_0, __cleanup_result_10_1;}self_.nodes.items[id].effects=blot_support::some(effects);}
  },
  product,record=>{for index in value.b {if self_.remaining==0 {self_.truncated=true;break;}var field=blot_check_types::Field{0,0};if value.tag==blot_check_types::Tag.record {field=engine.types.recordField(value,index);}else {field.ty=engine.types.list(blot_check_types::List{value.a,value.b})[index];}let child,error=self_.typeNode(engine,field.ty,depth+1);if error!=blot_error::Error.none {let __cleanup_result_11_0: u32 = 0; let __cleanup_result_11_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_11_0, __cleanup_result_11_1;}var name=blot_support::none<const u8[:]>();if field.name!=0 {name=blot_support::some(self_.saveName(engine.pool.get(field.name)));}let error=children.push(Edge{name,child},edge_pool);if error!=blot_error::Error.none {freeText(name);let __cleanup_result_12_0: u32 = 0; let __cleanup_result_12_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_12_0, __cleanup_result_12_1;}}},_=>{},
 }
 let span,error=self_.save(children.items);if error!=blot_error::Error.none {let __cleanup_result_13_0: u32 = 0; let __cleanup_result_13_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_13_0, __cleanup_result_13_1;}self_.nodes.items[id].children=span;saved=true;let __cleanup_result_14_0: u32 = id; let __cleanup_result_14_1: Error = blot_error::Error.none; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_14_0, __cleanup_result_14_1;
 {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} }
recursive fn row<E>(self_:Builder&,engine:E&,input:u32,depth:i64)->u32,Error {
 if !self_.budget(depth) {return 0,blot_error::Error.none;}let id,error=self_.addNode(Node{kind:Kind.effects});if error!=blot_error::Error.none {return 0,error;}let resolved,error=engine.types.resolveEffects(input,0);if error!=blot_error::Error.none {return 0,error;}let row=engine.types.effects.node(resolved);
 var children=blot_support_pooled_buffer::Buffer<Edge>{};
 for index in row.labels.len {
  if !self_.budget(depth+1) {break;}let label=engine.types.effects.list(row.labels)[index];let operation=engine.types.operation(label);let op,error=self_.addNode(Node{kind:Kind.operation,identity:blot_support::some(operation.identity)});if error!=blot_error::Error.none {let __cleanup_result_15_0: u32 = 0; let __cleanup_result_15_1: Error = error; {children.deinit(edge_pool);} return __cleanup_result_15_0, __cleanup_result_15_1;}
  if label==blot_check_types::foreign_operation {self_.nodes.items[op].name=blot_support::some(self_.saveName("Foreign"));}else {for template in engine.effect_templates {if template.identity==operation.identity {self_.nodes.items[op].name=blot_support::some(self_.saveName(engine.pool.get(template.name)));break;}}}
  var arguments=blot_support_pooled_buffer::Buffer<Edge>{};
  for index in operation.arguments.len {if self_.remaining==0 {self_.truncated=true;break;}let argument=engine.types.list(operation.arguments)[index];let child,error=self_.typeNode(engine,argument,depth+1);if error!=blot_error::Error.none {let __cleanup_result_16_0: u32 = 0; let __cleanup_result_16_1: Error = error; {arguments.deinit(edge_pool);} {children.deinit(edge_pool);} return __cleanup_result_16_0, __cleanup_result_16_1;}let error=arguments.push(Edge{ty:child},edge_pool);if error!=blot_error::Error.none {let __cleanup_result_17_0: u32 = 0; let __cleanup_result_17_1: Error = error; {arguments.deinit(edge_pool);} {children.deinit(edge_pool);} return __cleanup_result_17_0, __cleanup_result_17_1;}}
  let span,error=self_.save(arguments.items);if error!=blot_error::Error.none {let __cleanup_result_18_0: u32 = 0; let __cleanup_result_18_1: Error = error; {arguments.deinit(edge_pool);} {children.deinit(edge_pool);} return __cleanup_result_18_0, __cleanup_result_18_1;}self_.nodes.items[op].children=span;let error=children.push(Edge{ty:op},edge_pool);if error!=blot_error::Error.none {let __cleanup_result_19_0: u32 = 0; let __cleanup_result_19_1: Error = error; {arguments.deinit(edge_pool);} {children.deinit(edge_pool);} return __cleanup_result_19_0, __cleanup_result_19_1;}
  {arguments.deinit(edge_pool);} }
 match row.tail {
  closed=>{},formal payload=>{let child,error=self_.typeNode(engine,payload.value,depth+1);if error!=blot_error::Error.none {let __cleanup_result_20_0: u32 = 0; let __cleanup_result_20_1: Error = error; {children.deinit(edge_pool);} return __cleanup_result_20_0, __cleanup_result_20_1;}let error=children.push(Edge{ty:child},edge_pool);if error!=blot_error::Error.none {let __cleanup_result_21_0: u32 = 0; let __cleanup_result_21_1: Error = error; {children.deinit(edge_pool);} return __cleanup_result_21_0, __cleanup_result_21_1;}},
  variable payload=>{var tail:u32=0;if self_.budget(depth+1) {let child,error=self_.addNode(Node{kind:Kind.row_variable,variable:blot_support::some(payload.value)});if error!=blot_error::Error.none {let __cleanup_result_22_0: u32 = 0; let __cleanup_result_22_1: Error = error; {children.deinit(edge_pool);} return __cleanup_result_22_0, __cleanup_result_22_1;}tail=child;}let error=children.push(Edge{ty:tail},edge_pool);if error!=blot_error::Error.none {let __cleanup_result_23_0: u32 = 0; let __cleanup_result_23_1: Error = error; {children.deinit(edge_pool);} return __cleanup_result_23_0, __cleanup_result_23_1;}},
  parameter payload=>{var tail:u32=0;if self_.budget(depth+1) {let child,error=self_.addNode(Node{kind:Kind.row_parameter,variable:blot_support::some(payload.value)});if error!=blot_error::Error.none {let __cleanup_result_24_0: u32 = 0; let __cleanup_result_24_1: Error = error; {children.deinit(edge_pool);} return __cleanup_result_24_0, __cleanup_result_24_1;}tail=child;}let error=children.push(Edge{ty:tail},edge_pool);if error!=blot_error::Error.none {let __cleanup_result_25_0: u32 = 0; let __cleanup_result_25_1: Error = error; {children.deinit(edge_pool);} return __cleanup_result_25_0, __cleanup_result_25_1;}},
 }
 let span,error=self_.save(children.items);if error!=blot_error::Error.none {let __cleanup_result_26_0: u32 = 0; let __cleanup_result_26_1: Error = error; {children.deinit(edge_pool);} return __cleanup_result_26_0, __cleanup_result_26_1;}self_.nodes.items[id].children=span;let __cleanup_result_27_0: u32 = id; let __cleanup_result_27_1: Error = blot_error::Error.none; {children.deinit(edge_pool);} return __cleanup_result_27_0, __cleanup_result_27_1;
 {children.deinit(edge_pool);} }
fn predicates<E>(self_:Builder&,engine:E&,scheme:blot_check_types::Scheme)->Span,Error {
 let start=self_.requirements.items.len as u32;
 for index in scheme.obligations.len {if self_.requirements.items.len==64 || self_.remaining==0 {self_.truncated=true;break;}let predicate=engine.obligations[scheme.obligations.start+index];if predicate.kind==blot_check_types::ObligationKind.callee_use {continue;}
  let subject,error=self_.typeNode(engine,predicate.ty,0);if error!=blot_error::Error.none {return Span{},error;}var argument=blot_support::none<u32>();var result=blot_support::none<u32>();var signature=blot_support::none<u32>();
  if predicate.other!=0 {let projected,error=self_.typeNode(engine,predicate.other,0);if error!=blot_error::Error.none {return Span{},error;}argument=blot_support::some(projected);}if predicate.result!=0 {let projected,error=self_.typeNode(engine,predicate.result,0);if error!=blot_error::Error.none {return Span{},error;}result=blot_support::some(projected);}if predicate.signature!=0 {let projected,error=self_.typeNode(engine,predicate.signature,0);if error!=blot_error::Error.none {return Span{},error;}signature=blot_support::some(projected);}
  var name=blot_support::none<const u8[:]>();if predicate.name!=0 {name=blot_support::some(self_.saveName(engine.pool.get(predicate.name)));}let error=self_.requirements.push(Requirement{kind:predicate.kind,name:name,subject:subject,argument:argument,result:result,signature:signature,explicit:predicate.explicit},requirement_pool);if error!=blot_error::Error.none {freeText(name);return Span{},error;}
 }return Span{start,(self_.requirements.items.len as u32)-start},blot_error::Error.none;
}
fn build<E>(engine:E&,source:u32,scope:blot_check_types::List,owner:u32)->Snapshot,Error {return buildNamed(engine,source,scope,owner,[]);}
fn buildNamed<E>(engine:E&,source:u32,scope:blot_check_types::List,owner:u32,scope_names:const u32[:])->Snapshot,Error {
 var builder=Builder{};let ignored,error=builder.addNode(Node{kind:Kind.truncated});if error!=blot_error::Error.none {let __cleanup_result_28_0: Snapshot = Snapshot{}; let __cleanup_result_28_1: Error = error; {builder.deinit();} return __cleanup_result_28_0, __cleanup_result_28_1;}var result=Snapshot{};
 let expected,error=builder.typeNode(engine,engine.expr_types[source],0);if error!=blot_error::Error.none {let __cleanup_result_29_0: Snapshot = Snapshot{}; let __cleanup_result_29_1: Error = error; {builder.deinit();} return __cleanup_result_29_0, __cleanup_result_29_1;}result.expected=expected;
 if owner!=0 {let enclosing,error=builder.predicates(engine,engine.bindings[owner].scheme);if error!=blot_error::Error.none {let __cleanup_result_30_0: Snapshot = Snapshot{}; let __cleanup_result_30_1: Error = error; {builder.deinit();} return __cleanup_result_30_0, __cleanup_result_30_1;}result.enclosing=enclosing;}
 for index in 0..min(scope.len,32) {let binding=engine.bindings[engine.types.list(scope)[index]];let ty,error=builder.typeNode(engine,binding.ty,0);if error!=blot_error::Error.none {let __cleanup_result_31_0: Snapshot = Snapshot{}; let __cleanup_result_31_1: Error = error; {builder.deinit();} return __cleanup_result_31_0, __cleanup_result_31_1;}let requirements,error=builder.predicates(engine,binding.scheme);if error!=blot_error::Error.none {let __cleanup_result_32_0: Snapshot = Snapshot{}; let __cleanup_result_32_1: Error = error; {builder.deinit();} return __cleanup_result_32_0, __cleanup_result_32_1;}var symbol=binding.name;if index<scope_names.len {symbol=scope_names[index];}let name=builder.saveName(engine.pool.get(symbol));let error=builder.scope.push(Binding{name,ty,requirements},binding_pool);if error!=blot_error::Error.none {freeText(name);let __cleanup_result_33_0: Snapshot = Snapshot{}; let __cleanup_result_33_1: Error = error; {builder.deinit();} return __cleanup_result_33_0, __cleanup_result_33_1;}}
 if scope.len>32 {builder.truncated=true;}
 result.nodes=node_pool.alloc_slice(builder.nodes.items.len);for node,index in builder.nodes.items {result.nodes[index]=node;builder.nodes.items[index].name=blot_support::none<const u8[:]>();}
 result.edges=edge_pool.alloc_slice(builder.edges.items.len);for edge,index in builder.edges.items {result.edges[index]=edge;builder.edges.items[index].name=blot_support::none<const u8[:]>();}
 result.scope=binding_pool.alloc_slice(builder.scope.items.len);for binding,index in builder.scope.items {result.scope[index]=binding;builder.scope.items[index].name=[];}
 result.requirements=requirement_pool.alloc_slice(builder.requirements.items.len);for requirement,index in builder.requirements.items {result.requirements[index]=requirement;builder.requirements.items[index].name=blot_support::none<const u8[:]>();}result.truncated=builder.truncated;let __cleanup_result_34_0: Snapshot = result; let __cleanup_result_34_1: Error = blot_error::Error.none; {builder.deinit();} return __cleanup_result_34_0, __cleanup_result_34_1;
 {builder.deinit();} }

// Recover this owned diagnostic view without copying or retaining its live runs.
fn canonicalOwned(value:Snapshot)->Snapshot{return Snapshot{expected:value.expected,nodes:node_pool.realloc_slice(value.nodes,value.nodes.len),edges:edge_pool.realloc_slice(value.edges,value.edges.len),scope:binding_pool.realloc_slice(value.scope,value.scope.len),requirements:requirement_pool.realloc_slice(value.requirements,value.requirements.len),enclosing:value.enclosing,truncated:value.truncated};}
