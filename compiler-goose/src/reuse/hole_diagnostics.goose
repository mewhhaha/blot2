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
struct Node {kind:Kind=Kind.truncated,name:Text=blot_support::none<const u8[:]>(),identity:blot_support::Option<blot_check_types::NominalIdentity>=blot_support::none<blot_check_types::NominalIdentity>(),variable:IdOption=blot_support::none<u32>(),children:Span=Span{},effects:IdOption=blot_support::none<u32>()}
struct Edge {name:Text=blot_support::none<const u8[:]>(),ty:u32=0}
struct Binding {name:const u8[:]=[],ty:u32=0,requirements:Span=Span{}}
struct Requirement {kind:blot_check_types::ObligationKind,name:Text=blot_support::none<const u8[:]>(),subject:u32=0,argument:IdOption=blot_support::none<u32>(),result:IdOption=blot_support::none<u32>(),signature:IdOption=blot_support::none<u32>(),explicit:bool=false}
struct Snapshot {expected:u32=0,nodes:Node[:]=[],edges:Edge[:]=[],scope:Binding[:]=[],requirements:Requirement[:]=[],enclosing:Span=Span{},truncated:bool=false}
reusable[] var text_pool:u8[>..]=[];
reusable[] var node_pool:Node[>..]=[];
reusable[] var edge_pool:Edge[>..]=[];
reusable[] var binding_pool:Binding[>..]=[];
reusable[] var requirement_pool:Requirement[>..]=[];
reusable[] var memo_pool:dictionary_slot<u32,u32>[>..]=[];
fn copyText(text:const u8[:])->const u8[:] {let result=text_pool.alloc_slice(text.len);for byte,index in text {result[index]=byte;}return result;}
fn freeText(text:const u8[:]) {if text.len==0 {return;}let first:const u8&=text[0];let at=text_pool.index_of(first);text_pool.free_slice(text_pool[at..at+text.len]);}
fn freeText(text:Text) {if text.present {freeText(text.value);}}
fn cloneText(text:Text)->Text {if !text.present {return text;}return blot_support::some(copyText(text.value));}
fn deinit(self:Snapshot&) {
 for node in self.nodes {freeText(node.name);}for edge in self.edges {freeText(edge.name);}for binding in self.scope {freeText(binding.name);}for requirement in self.requirements {freeText(requirement.name);}
 if self.nodes.len!=0 {node_pool.free_slice(self.nodes);}if self.edges.len!=0 {edge_pool.free_slice(self.edges);}if self.scope.len!=0 {binding_pool.free_slice(self.scope);}if self.requirements.len!=0 {requirement_pool.free_slice(self.requirements);}self=Snapshot{};
}
fn clone(self:Snapshot)->Snapshot,Error {
 var result=Snapshot{expected:self.expected,enclosing:self.enclosing,truncated:self.truncated};result.nodes=node_pool.alloc_slice(self.nodes.len);for node,index in self.nodes {result.nodes[index]=node;result.nodes[index].name=cloneText(node.name);}
 result.edges=edge_pool.alloc_slice(self.edges.len);for edge,index in self.edges {result.edges[index]=edge;result.edges[index].name=cloneText(edge.name);}result.scope=binding_pool.alloc_slice(self.scope.len);for binding,index in self.scope {result.scope[index]=binding;result.scope[index].name=copyText(binding.name);}
 result.requirements=requirement_pool.alloc_slice(self.requirements.len);for requirement,index in self.requirements {result.requirements[index]=requirement;result.requirements[index].name=cloneText(requirement.name);}return result,Error.none;
}
fn jsonStringify(self:Span,writer:blot_json::Writer&)->Error {return blot_json::jsonStringify(self,writer);}
fn jsonStringify(self:Node,writer:blot_json::Writer&)->Error {writer.beginObject();writer.key("kind");writer.enumValue(self.kind);writer.field("name",self.name);writer.key("identity");if self.identity.present {writer.beginObject();writer.field("unit",self.identity.value.unit);writer.field("decl",self.identity.value.decl);writer.endObject();}else {writer.nullValue();}writer.field("variable",self.variable);writer.field("children",self.children);writer.field("effects",self.effects);writer.endObject();return writer.failure;}
fn jsonStringify(self:Edge,writer:blot_json::Writer&)->Error {writer.beginObject();writer.field("name",self.name);writer.field("type",self.ty);writer.endObject();return writer.failure;}
fn jsonStringify(self:Binding,writer:blot_json::Writer&)->Error {writer.beginObject();writer.field("name",self.name);writer.field("type",self.ty);writer.field("requirements",self.requirements);writer.endObject();return writer.failure;}
fn jsonStringify(self:Requirement,writer:blot_json::Writer&)->Error {writer.beginObject();writer.key("kind");writer.enumValue(self.kind);writer.field("name",self.name);writer.field("subject",self.subject);writer.field("argument",self.argument);writer.field("result",self.result);writer.field("signature",self.signature);writer.field("explicit",self.explicit);writer.endObject();return writer.failure;}
fn jsonStringify(self:Snapshot,writer:blot_json::Writer&)->Error {writer.beginObject();writer.field("expected",self.expected);writer.field("nodes",self.nodes);writer.field("edges",self.edges);writer.field("scope",self.scope);writer.field("requirements",self.requirements);writer.field("enclosing",self.enclosing);writer.field("truncated",self.truncated);writer.endObject();return writer.failure;}
struct Builder {nodes:blot_support_pooled_buffer::Buffer<Node>=blot_support_pooled_buffer::Buffer<Node>{},edges:blot_support_pooled_buffer::Buffer<Edge>=blot_support_pooled_buffer::Buffer<Edge>{},scope:blot_support_pooled_buffer::Buffer<Binding>=blot_support_pooled_buffer::Buffer<Binding>{},requirements:blot_support_pooled_buffer::Buffer<Requirement>=blot_support_pooled_buffer::Buffer<Requirement>{},memo:blot_support_pooled_map::Map<u32,u32>=blot_support_pooled_map::Map<u32,u32>{},remaining:i64=1024,name_bytes:i64=0,truncated:bool=false}
fn deinit(self:Builder&) {for node in self.nodes.items {freeText(node.name);}for edge in self.edges.items {freeText(edge.name);}for binding in self.scope.items {freeText(binding.name);}for requirement in self.requirements.items {freeText(requirement.name);}self.nodes.deinit(node_pool);self.edges.deinit(edge_pool);self.scope.deinit(binding_pool);self.requirements.deinit(requirement_pool);self.memo.deinit(memo_pool);}
fn saveName(self:Builder&,text:const u8[:])->const u8[:] {var length=min(text.len,16384-self.name_bytes);while length!=0 && length<text.len && (text[length]&0xc0)==0x80 {length--;}if length<text.len {self.truncated=true;}self.name_bytes+=length;return copyText(text[..length]);}
fn addNode(self:Builder&,value:Node)->u32,Error {let id=self.nodes.items.len as u32;let error=self.nodes.push(value,node_pool);if error!=Error.none {return 0,error;}return id,Error.none;}
fn budget(self:Builder&,depth:i64)->bool {if self.remaining==0 || depth>=32 {self.truncated=true;return false;}self.remaining--;return true;}
fn save(self:Builder&,values:const Edge[:])->Span,Error {let start=self.edges.items.len as u32;let error=self.edges.append(values,edge_pool);if error!=Error.none {return Span{},error;}return Span{start,values.len as u32},Error.none;}
fn nodeKind(tag:blot_check_types::Tag)->Kind {match tag {
 blot_check_types::Tag.absent=>{return Kind.absent;},
 blot_check_types::Tag.unit=>{return Kind.unit;},
 blot_check_types::Tag.boolean=>{return Kind.boolean;},
 blot_check_types::Tag.unsigned32=>{return Kind.unsigned32;},
 blot_check_types::Tag.floating32=>{return Kind.floating32;},
 blot_check_types::Tag.never=>{return Kind.never;},
 blot_check_types::Tag.variable=>{return Kind.variable;},
 blot_check_types::Tag.function=>{return Kind.function;},
 blot_check_types::Tag.product=>{return Kind.product;},
 blot_check_types::Tag.record=>{return Kind.record;},
 blot_check_types::Tag.nominal=>{return Kind.nominal;},
 blot_check_types::Tag.projection=>{return Kind.projection;},
 blot_check_types::Tag.array=>{return Kind.array;},
 blot_check_types::Tag.list=>{return Kind.list;},
 blot_check_types::Tag.cursor=>{return Kind.cursor;},
 blot_check_types::Tag.type_constructor=>{return Kind.type_constructor;},
 blot_check_types::Tag.resolver=>{return Kind.resolver;},
 blot_check_types::Tag.provider=>{return Kind.provider;},
 blot_check_types::Tag.state_provider=>{return Kind.state_provider;},
 _=>{abort("type has no hole diagnostic kind");},}}
recursive fn typeNode<E>(self:Builder&,engine:E&,ty:u32,depth:i64)->u32,Error {
 if !self.budget(depth) {return 0,Error.none;}let resolved,error=engine.types.resolve(ty,0);if error!=Error.none {return 0,error;}let cached .= self.memo.get(resolved);if cached {return cached,Error.none;}
 let value=engine.types.node(resolved);let id,error=self.addNode(Node{kind:nodeKind(value.tag)});if error!=Error.none {return 0,error;}self.memo.insert(resolved,id,memo_pool);
 var children=blot_support_pooled_buffer::Buffer<Edge>{};var saved=false;
 match value.tag {
  blot_check_types::Tag.variable=>{self.nodes.items[id].variable=blot_support::some(value.a);},
  blot_check_types::Tag.nominal,blot_check_types::Tag.projection,blot_check_types::Tag.type_constructor=>{
   self.nodes.items[id].identity=blot_support::some(blot_check_types::NominalIdentity{value.a,value.b});for nominal in engine.nominals {if nominal.identity.unit==value.a && nominal.identity.decl==value.b {self.nodes.items[id].name=blot_support::some(self.saveName(engine.pool.get(nominal.name)));break;}}
   if value.tag==blot_check_types::Tag.projection {let member=engine.types.projectionMember(value);var contract_name:u32=0;for contract in engine.contracts {if contract.identity.unit==value.a && contract.identity.decl==value.b {contract_name=contract.name;break;}}let left=engine.pool.get(contract_name);let right=engine.pool.get(member);let text=text_pool.alloc_slice(left.len+1+right.len);for byte,index in left {text[index]=byte;}text[left.len]='.';for byte,index in right {text[left.len+1+index]=byte;}freeText(self.nodes.items[id].name);self.nodes.items[id].name=blot_support::some(self.saveName(text));text_pool.free_slice(text);}
   if value.tag==blot_check_types::Tag.nominal || value.tag==blot_check_types::Tag.projection {let span=blot_check_types::List{value.c+1,engine.types.nominalArguments(value).len as u32};for index in span.len {if self.remaining==0 {self.truncated=true;break;}let child=engine.types.list(span)[index];let projected,error=self.typeNode(engine,child,depth+1);if error!=Error.none {let __cleanup_result_1_0: u32 = 0; let __cleanup_result_1_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_1_0, __cleanup_result_1_1;}let error=children.push(Edge{ty:projected},edge_pool);if error!=Error.none {let __cleanup_result_2_0: u32 = 0; let __cleanup_result_2_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_2_0, __cleanup_result_2_1;}}}
  },
  blot_check_types::Tag.function,blot_check_types::Tag.state_provider=>{
   for child in [value.a,value.b] {let projected,error=self.typeNode(engine,child,depth+1);if error!=Error.none {let __cleanup_result_3_0: u32 = 0; let __cleanup_result_3_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_3_0, __cleanup_result_3_1;}let error=children.push(Edge{ty:projected},edge_pool);if error!=Error.none {let __cleanup_result_4_0: u32 = 0; let __cleanup_result_4_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_4_0, __cleanup_result_4_1;}}
   if value.tag==blot_check_types::Tag.state_provider {let child,error=self.typeNode(engine,value.c,depth+1);if error!=Error.none {let __cleanup_result_5_0: u32 = 0; let __cleanup_result_5_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_5_0, __cleanup_result_5_1;}let error=children.push(Edge{ty:child},edge_pool);if error!=Error.none {let __cleanup_result_6_0: u32 = 0; let __cleanup_result_6_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_6_0, __cleanup_result_6_1;}}
   else {let effects,error=self.row(engine,value.c,depth+1);if error!=Error.none {let __cleanup_result_7_0: u32 = 0; let __cleanup_result_7_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_7_0, __cleanup_result_7_1;}self.nodes.items[id].effects=blot_support::some(effects);}
  },
  blot_check_types::Tag.array,blot_check_types::Tag.list,blot_check_types::Tag.cursor,blot_check_types::Tag.resolver,blot_check_types::Tag.provider=>{
   let child,error=self.typeNode(engine,value.a,depth+1);if error!=Error.none {let __cleanup_result_8_0: u32 = 0; let __cleanup_result_8_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_8_0, __cleanup_result_8_1;}let error=children.push(Edge{ty:child},edge_pool);if error!=Error.none {let __cleanup_result_9_0: u32 = 0; let __cleanup_result_9_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_9_0, __cleanup_result_9_1;}
   if value.tag==blot_check_types::Tag.provider {let effects,error=self.row(engine,value.c,depth+1);if error!=Error.none {let __cleanup_result_10_0: u32 = 0; let __cleanup_result_10_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_10_0, __cleanup_result_10_1;}self.nodes.items[id].effects=blot_support::some(effects);}
  },
  blot_check_types::Tag.product,blot_check_types::Tag.record=>{for index in value.b {if self.remaining==0 {self.truncated=true;break;}var field=blot_check_types::Field{0,0};if value.tag==blot_check_types::Tag.record {field=engine.types.recordField(value,index);}else {field.ty=engine.types.list(blot_check_types::List{value.a,value.b})[index];}let child,error=self.typeNode(engine,field.ty,depth+1);if error!=Error.none {let __cleanup_result_11_0: u32 = 0; let __cleanup_result_11_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_11_0, __cleanup_result_11_1;}var name=blot_support::none<const u8[:]>();if field.name!=0 {name=blot_support::some(self.saveName(engine.pool.get(field.name)));}let error=children.push(Edge{name,child},edge_pool);if error!=Error.none {freeText(name);let __cleanup_result_12_0: u32 = 0; let __cleanup_result_12_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_12_0, __cleanup_result_12_1;}}},_=>{},
 }
 let span,error=self.save(children.items);if error!=Error.none {let __cleanup_result_13_0: u32 = 0; let __cleanup_result_13_1: Error = error; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_13_0, __cleanup_result_13_1;}self.nodes.items[id].children=span;saved=true;let __cleanup_result_14_0: u32 = id; let __cleanup_result_14_1: Error = Error.none; {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} return __cleanup_result_14_0, __cleanup_result_14_1;
 {if !saved {for edge in children.items {freeText(edge.name);}}children.deinit(edge_pool);} }
recursive fn row<E>(self:Builder&,engine:E&,input:u32,depth:i64)->u32,Error {
 if !self.budget(depth) {return 0,Error.none;}let id,error=self.addNode(Node{kind:Kind.effects});if error!=Error.none {return 0,error;}let resolved,error=engine.types.resolveEffects(input,0);if error!=Error.none {return 0,error;}let row=engine.types.effects.node(resolved);
 var children=blot_support_pooled_buffer::Buffer<Edge>{};
 for index in row.labels.len {
  if !self.budget(depth+1) {break;}let label=engine.types.effects.list(row.labels)[index];let operation=engine.types.operation(label);let op,error=self.addNode(Node{kind:Kind.operation,identity:blot_support::some(operation.identity)});if error!=Error.none {let __cleanup_result_15_0: u32 = 0; let __cleanup_result_15_1: Error = error; {children.deinit(edge_pool);} return __cleanup_result_15_0, __cleanup_result_15_1;}
  if label==blot_check_types::foreign_operation {self.nodes.items[op].name=blot_support::some(self.saveName("Foreign"));}else {for template in engine.effect_templates {if template.identity==operation.identity {self.nodes.items[op].name=blot_support::some(self.saveName(engine.pool.get(template.name)));break;}}}
  var arguments=blot_support_pooled_buffer::Buffer<Edge>{};
  for index in operation.arguments.len {if self.remaining==0 {self.truncated=true;break;}let argument=engine.types.list(operation.arguments)[index];let child,error=self.typeNode(engine,argument,depth+1);if error!=Error.none {let __cleanup_result_16_0: u32 = 0; let __cleanup_result_16_1: Error = error; {arguments.deinit(edge_pool);} {children.deinit(edge_pool);} return __cleanup_result_16_0, __cleanup_result_16_1;}let error=arguments.push(Edge{ty:child},edge_pool);if error!=Error.none {let __cleanup_result_17_0: u32 = 0; let __cleanup_result_17_1: Error = error; {arguments.deinit(edge_pool);} {children.deinit(edge_pool);} return __cleanup_result_17_0, __cleanup_result_17_1;}}
  let span,error=self.save(arguments.items);if error!=Error.none {let __cleanup_result_18_0: u32 = 0; let __cleanup_result_18_1: Error = error; {arguments.deinit(edge_pool);} {children.deinit(edge_pool);} return __cleanup_result_18_0, __cleanup_result_18_1;}self.nodes.items[op].children=span;let error=children.push(Edge{ty:op},edge_pool);if error!=Error.none {let __cleanup_result_19_0: u32 = 0; let __cleanup_result_19_1: Error = error; {arguments.deinit(edge_pool);} {children.deinit(edge_pool);} return __cleanup_result_19_0, __cleanup_result_19_1;}
  {arguments.deinit(edge_pool);} }
 match row.tail {
  blot_check_effects::Tail.closed=>{},blot_check_effects::Tail.formal payload=>{let child,error=self.typeNode(engine,payload.value,depth+1);if error!=Error.none {let __cleanup_result_20_0: u32 = 0; let __cleanup_result_20_1: Error = error; {children.deinit(edge_pool);} return __cleanup_result_20_0, __cleanup_result_20_1;}let error=children.push(Edge{ty:child},edge_pool);if error!=Error.none {let __cleanup_result_21_0: u32 = 0; let __cleanup_result_21_1: Error = error; {children.deinit(edge_pool);} return __cleanup_result_21_0, __cleanup_result_21_1;}},
  blot_check_effects::Tail.variable payload=>{var tail:u32=0;if self.budget(depth+1) {let child,error=self.addNode(Node{kind:Kind.row_variable,variable:blot_support::some(payload.value)});if error!=Error.none {let __cleanup_result_22_0: u32 = 0; let __cleanup_result_22_1: Error = error; {children.deinit(edge_pool);} return __cleanup_result_22_0, __cleanup_result_22_1;}tail=child;}let error=children.push(Edge{ty:tail},edge_pool);if error!=Error.none {let __cleanup_result_23_0: u32 = 0; let __cleanup_result_23_1: Error = error; {children.deinit(edge_pool);} return __cleanup_result_23_0, __cleanup_result_23_1;}},
  blot_check_effects::Tail.parameter payload=>{var tail:u32=0;if self.budget(depth+1) {let child,error=self.addNode(Node{kind:Kind.row_parameter,variable:blot_support::some(payload.value)});if error!=Error.none {let __cleanup_result_24_0: u32 = 0; let __cleanup_result_24_1: Error = error; {children.deinit(edge_pool);} return __cleanup_result_24_0, __cleanup_result_24_1;}tail=child;}let error=children.push(Edge{ty:tail},edge_pool);if error!=Error.none {let __cleanup_result_25_0: u32 = 0; let __cleanup_result_25_1: Error = error; {children.deinit(edge_pool);} return __cleanup_result_25_0, __cleanup_result_25_1;}},
 }
 let span,error=self.save(children.items);if error!=Error.none {let __cleanup_result_26_0: u32 = 0; let __cleanup_result_26_1: Error = error; {children.deinit(edge_pool);} return __cleanup_result_26_0, __cleanup_result_26_1;}self.nodes.items[id].children=span;let __cleanup_result_27_0: u32 = id; let __cleanup_result_27_1: Error = Error.none; {children.deinit(edge_pool);} return __cleanup_result_27_0, __cleanup_result_27_1;
 {children.deinit(edge_pool);} }
fn predicates<E>(self:Builder&,engine:E&,scheme:blot_check_types::Scheme)->Span,Error {
 let start=self.requirements.items.len as u32;
 for index in scheme.obligations.len {if self.requirements.items.len==64 || self.remaining==0 {self.truncated=true;break;}let predicate=engine.obligations[scheme.obligations.start+index];if predicate.kind==blot_check_types::ObligationKind.callee_use {continue;}
  let subject,error=self.typeNode(engine,predicate.ty,0);if error!=Error.none {return Span{},error;}var argument=blot_support::none<u32>();var result=blot_support::none<u32>();var signature=blot_support::none<u32>();
  if predicate.other!=0 {let projected,error=self.typeNode(engine,predicate.other,0);if error!=Error.none {return Span{},error;}argument=blot_support::some(projected);}if predicate.result!=0 {let projected,error=self.typeNode(engine,predicate.result,0);if error!=Error.none {return Span{},error;}result=blot_support::some(projected);}if predicate.signature!=0 {let projected,error=self.typeNode(engine,predicate.signature,0);if error!=Error.none {return Span{},error;}signature=blot_support::some(projected);}
  var name=blot_support::none<const u8[:]>();if predicate.name!=0 {name=blot_support::some(self.saveName(engine.pool.get(predicate.name)));}let error=self.requirements.push(Requirement{kind:predicate.kind,name:name,subject:subject,argument:argument,result:result,signature:signature,explicit:predicate.explicit},requirement_pool);if error!=Error.none {freeText(name);return Span{},error;}
 }return Span{start,(self.requirements.items.len as u32)-start},Error.none;
}
fn build<E>(engine:E&,source:u32,scope:blot_check_types::List,owner:u32)->Snapshot,Error {return buildNamed(engine,source,scope,owner,[]);}
fn buildNamed<E>(engine:E&,source:u32,scope:blot_check_types::List,owner:u32,scope_names:const u32[:])->Snapshot,Error {
 var builder=Builder{};let ignored,error=builder.addNode(Node{kind:Kind.truncated});if error!=Error.none {let __cleanup_result_28_0: Snapshot = Snapshot{}; let __cleanup_result_28_1: Error = error; {builder.deinit();} return __cleanup_result_28_0, __cleanup_result_28_1;}var result=Snapshot{};
 let expected,error=builder.typeNode(engine,engine.expr_types[source],0);if error!=Error.none {let __cleanup_result_29_0: Snapshot = Snapshot{}; let __cleanup_result_29_1: Error = error; {builder.deinit();} return __cleanup_result_29_0, __cleanup_result_29_1;}result.expected=expected;
 if owner!=0 {let enclosing,error=builder.predicates(engine,engine.bindings[owner].scheme);if error!=Error.none {let __cleanup_result_30_0: Snapshot = Snapshot{}; let __cleanup_result_30_1: Error = error; {builder.deinit();} return __cleanup_result_30_0, __cleanup_result_30_1;}result.enclosing=enclosing;}
 for index in 0..min(scope.len,32) {let binding=engine.bindings[engine.types.list(scope)[index]];let ty,error=builder.typeNode(engine,binding.ty,0);if error!=Error.none {let __cleanup_result_31_0: Snapshot = Snapshot{}; let __cleanup_result_31_1: Error = error; {builder.deinit();} return __cleanup_result_31_0, __cleanup_result_31_1;}let requirements,error=builder.predicates(engine,binding.scheme);if error!=Error.none {let __cleanup_result_32_0: Snapshot = Snapshot{}; let __cleanup_result_32_1: Error = error; {builder.deinit();} return __cleanup_result_32_0, __cleanup_result_32_1;}var symbol=binding.name;if index<scope_names.len {symbol=scope_names[index];}let name=builder.saveName(engine.pool.get(symbol));let error=builder.scope.push(Binding{name,ty,requirements},binding_pool);if error!=Error.none {freeText(name);let __cleanup_result_33_0: Snapshot = Snapshot{}; let __cleanup_result_33_1: Error = error; {builder.deinit();} return __cleanup_result_33_0, __cleanup_result_33_1;}}
 if scope.len>32 {builder.truncated=true;}
 result.nodes=node_pool.alloc_slice(builder.nodes.items.len);for node,index in builder.nodes.items {result.nodes[index]=node;builder.nodes.items[index].name=blot_support::none<const u8[:]>();}
 result.edges=edge_pool.alloc_slice(builder.edges.items.len);for edge,index in builder.edges.items {result.edges[index]=edge;builder.edges.items[index].name=blot_support::none<const u8[:]>();}
 result.scope=binding_pool.alloc_slice(builder.scope.items.len);for binding,index in builder.scope.items {result.scope[index]=binding;builder.scope.items[index].name=[];}
 result.requirements=requirement_pool.alloc_slice(builder.requirements.items.len);for requirement,index in builder.requirements.items {result.requirements[index]=requirement;builder.requirements.items[index].name=blot_support::none<const u8[:]>();}result.truncated=builder.truncated;let __cleanup_result_34_0: Snapshot = result; let __cleanup_result_34_1: Error = Error.none; {builder.deinit();} return __cleanup_result_34_0, __cleanup_result_34_1;
 {builder.deinit();} }
