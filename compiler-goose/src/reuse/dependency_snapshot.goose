// Chronological projection publishes independently owned source interfaces.
namespace blot_reuse_dependency_snapshot;
import dictionary;
import parse.ast;
import check.check;
import check.types;
import check.effects;
import check.frozen_types;
import check.parameter_patterns;
import check.quantifier_goals;
import check.numeric_proof_headers;
import check.capability_contracts;
import reuse.principal_interface;
import reuse.dependency_payload;
import eval.implementation_predicates;
import support.error;
import support.option;
import support.pooled_buffer;
import support.pooled_map;
type Error=blot_error::Error;
type Tree=blot_parse_ast::Tree;
type Checked=blot_check_check::Checked;
type Node=blot_check_types::Node;
type Tag=blot_check_types::Tag;
type List=blot_check_types::List;
type Identity=blot_check_types::NominalIdentity;
type Graph=blot_check_frozen_types::Graph;
type Interface=blot_reuse_principal_interface::Interface;
type Owner=blot_reuse_dependency_payload::Owner;
type OwnedGraph=blot_reuse_dependency_payload::Owned<Graph>;
type OwnedInterface=blot_reuse_dependency_payload::Owned<Interface>;
struct Words { storage: u32[:]=[],items: u32[:]=[],len: i64=0 }
reusable[] var pool_Words: u32[>..]=[];
fn push(self: Words&,value: u32) -> Error { let error=blot_support_pooled_buffer::push(self,value,pool_Words); self.len=self.items.len; return error; }
fn append(self: Words&,values: const u32[:]) -> Error { let error=blot_support_pooled_buffer::append(self,values,pool_Words); self.len=self.items.len; return error; }
fn fill(self: Words&,count: i64,value: u32) -> Error { for index in count { let error=self.push(value); if error!=Error.none { return error; } } return Error.none; }
fn clear(self: Words&) { blot_support_pooled_buffer::clear(self); self.len=0; }
fn deinit(self: Words&) { blot_support_pooled_buffer::deinit(self,pool_Words); self.len=0; }
struct Nodes { storage: Node[:]=[],items: Node[:]=[],len: i64=0 }
reusable[] var pool_Nodes: Node[>..]=[];
fn push(self: Nodes&,value: Node) -> Error { let error=blot_support_pooled_buffer::push(self,value,pool_Nodes); self.len=self.items.len; return error; }
fn append(self: Nodes&,values: const Node[:]) -> Error { let error=blot_support_pooled_buffer::append(self,values,pool_Nodes); self.len=self.items.len; return error; }
fn fill(self: Nodes&,count: i64,value: Node) -> Error { for index in count { let error=self.push(value); if error!=Error.none { return error; } } return Error.none; }
fn clear(self: Nodes&) { blot_support_pooled_buffer::clear(self); self.len=0; }
fn deinit(self: Nodes&) { blot_support_pooled_buffer::deinit(self,pool_Nodes); self.len=0; }
struct Goals { storage: blot_check_types::QuantifierGoals[:]=[],items: blot_check_types::QuantifierGoals[:]=[],len: i64=0 }
reusable[] var pool_Goals: blot_check_types::QuantifierGoals[>..]=[];
fn push(self: Goals&,value: blot_check_types::QuantifierGoals) -> Error { let error=blot_support_pooled_buffer::push(self,value,pool_Goals); self.len=self.items.len; return error; }
fn append(self: Goals&,values: const blot_check_types::QuantifierGoals[:]) -> Error { let error=blot_support_pooled_buffer::append(self,values,pool_Goals); self.len=self.items.len; return error; }
fn fill(self: Goals&,count: i64,value: blot_check_types::QuantifierGoals) -> Error { for index in count { let error=self.push(value); if error!=Error.none { return error; } } return Error.none; }
fn clear(self: Goals&) { blot_support_pooled_buffer::clear(self); self.len=0; }
fn deinit(self: Goals&) { blot_support_pooled_buffer::deinit(self,pool_Goals); self.len=0; }
struct Obligations { storage: blot_check_types::Obligation[:]=[],items: blot_check_types::Obligation[:]=[],len: i64=0 }
reusable[] var pool_Obligations: blot_check_types::Obligation[>..]=[];
fn push(self: Obligations&,value: blot_check_types::Obligation) -> Error { let error=blot_support_pooled_buffer::push(self,value,pool_Obligations); self.len=self.items.len; return error; }
fn append(self: Obligations&,values: const blot_check_types::Obligation[:]) -> Error { let error=blot_support_pooled_buffer::append(self,values,pool_Obligations); self.len=self.items.len; return error; }
fn fill(self: Obligations&,count: i64,value: blot_check_types::Obligation) -> Error { for index in count { let error=self.push(value); if error!=Error.none { return error; } } return Error.none; }
fn clear(self: Obligations&) { blot_support_pooled_buffer::clear(self); self.len=0; }
fn deinit(self: Obligations&) { blot_support_pooled_buffer::deinit(self,pool_Obligations); self.len=0; }
struct Spans { storage: blot_parse_ast::Span[:]=[],items: blot_parse_ast::Span[:]=[],len: i64=0 }
reusable[] var pool_Spans: blot_parse_ast::Span[>..]=[];
fn push(self: Spans&,value: blot_parse_ast::Span) -> Error { let error=blot_support_pooled_buffer::push(self,value,pool_Spans); self.len=self.items.len; return error; }
fn append(self: Spans&,values: const blot_parse_ast::Span[:]) -> Error { let error=blot_support_pooled_buffer::append(self,values,pool_Spans); self.len=self.items.len; return error; }
fn fill(self: Spans&,count: i64,value: blot_parse_ast::Span) -> Error { for index in count { let error=self.push(value); if error!=Error.none { return error; } } return Error.none; }
fn clear(self: Spans&) { blot_support_pooled_buffer::clear(self); self.len=0; }
fn deinit(self: Spans&) { blot_support_pooled_buffer::deinit(self,pool_Spans); self.len=0; }
struct Rows { storage: blot_check_effects::Row[:]=[],items: blot_check_effects::Row[:]=[],len: i64=0 }
reusable[] var pool_Rows: blot_check_effects::Row[>..]=[];
fn push(self: Rows&,value: blot_check_effects::Row) -> Error { let error=blot_support_pooled_buffer::push(self,value,pool_Rows); self.len=self.items.len; return error; }
fn append(self: Rows&,values: const blot_check_effects::Row[:]) -> Error { let error=blot_support_pooled_buffer::append(self,values,pool_Rows); self.len=self.items.len; return error; }
fn fill(self: Rows&,count: i64,value: blot_check_effects::Row) -> Error { for index in count { let error=self.push(value); if error!=Error.none { return error; } } return Error.none; }
fn clear(self: Rows&) { blot_support_pooled_buffer::clear(self); self.len=0; }
fn deinit(self: Rows&) { blot_support_pooled_buffer::deinit(self,pool_Rows); self.len=0; }
struct Operations { storage: blot_check_types::Operation[:]=[],items: blot_check_types::Operation[:]=[],len: i64=0 }
reusable[] var pool_Operations: blot_check_types::Operation[>..]=[];
fn push(self: Operations&,value: blot_check_types::Operation) -> Error { let error=blot_support_pooled_buffer::push(self,value,pool_Operations); self.len=self.items.len; return error; }
fn append(self: Operations&,values: const blot_check_types::Operation[:]) -> Error { let error=blot_support_pooled_buffer::append(self,values,pool_Operations); self.len=self.items.len; return error; }
fn fill(self: Operations&,count: i64,value: blot_check_types::Operation) -> Error { for index in count { let error=self.push(value); if error!=Error.none { return error; } } return Error.none; }
fn clear(self: Operations&) { blot_support_pooled_buffer::clear(self); self.len=0; }
fn deinit(self: Operations&) { blot_support_pooled_buffer::deinit(self,pool_Operations); self.len=0; }
struct Patterns { storage: blot_check_parameter_patterns::Node[:]=[],items: blot_check_parameter_patterns::Node[:]=[],len: i64=0 }
reusable[] var pool_Patterns: blot_check_parameter_patterns::Node[>..]=[];
fn push(self: Patterns&,value: blot_check_parameter_patterns::Node) -> Error { let error=blot_support_pooled_buffer::push(self,value,pool_Patterns); self.len=self.items.len; return error; }
fn append(self: Patterns&,values: const blot_check_parameter_patterns::Node[:]) -> Error { let error=blot_support_pooled_buffer::append(self,values,pool_Patterns); self.len=self.items.len; return error; }
fn fill(self: Patterns&,count: i64,value: blot_check_parameter_patterns::Node) -> Error { for index in count { let error=self.push(value); if error!=Error.none { return error; } } return Error.none; }
fn clear(self: Patterns&) { blot_support_pooled_buffer::clear(self); self.len=0; }
fn deinit(self: Patterns&) { blot_support_pooled_buffer::deinit(self,pool_Patterns); self.len=0; }
type PatternMap=blot_support_pooled_map::Map<u32,u32>;
reusable[] var pattern_slots: dictionary_slot<u32,u32>[>..]=[];
reusable[] var mapping_words: u32[>..]=[];
struct NoPrivate {}
fn physical(self: NoPrivate&,identity_: Identity,selection: bool) -> Identity,Error { return Identity {0,0},Error.dependency_limit; }
fn rigid(self: NoPrivate&,scope: u32) -> u32,Error { return 0,Error.dependency_limit; }
fn version(self: NoPrivate&,id: u32) -> Identity,Error { return Identity {0,0},Error.dependency_limit; }
struct Projector<C> {
 private_ctx: C,private_enabled: bool=false,allow_rank: bool=false,checked: Checked,tree: Tree,
 type_nodes: Nodes=Nodes {},quantifier_goals: Goals=Goals {},quantifier_obligations: Obligations=Obligations {},type_extra: Words=Words {},
 effect_rows: Rows=Rows {},effect_labels: Words=Words {},effect_operations: Operations=Operations {},obligations: Obligations=Obligations {},obligation_spans: Spans=Spans {},
 pattern_nodes: Patterns=Patterns {},pattern_extra: Words=Words {},pattern_map: PatternMap=PatternMap {},type_map: u32[:]=[],variable_map: u32[:]=[],effect_row_map: u32[:]=[],effect_variable_map: u32[:]=[],effect_operation_map: u32[:]=[],variable_count: u32=0,effect_variable_count: u32=0
}
fn allocateMap(count: i64) -> u32[:] { let values=mapping_words.alloc_slice(count); for &value in values { value=0; } return values; }
fn initialize<C>(self: Projector<C>&) -> Error {
 self.type_map=allocateMap(self.checked.types.nodes.len); self.variable_map=allocateMap(self.checked.types.variables.len); self.effect_row_map=allocateMap(self.checked.types.effects.rows.len); self.effect_variable_map=allocateMap(self.checked.types.effects.variables.len); self.effect_operation_map=allocateMap(self.checked.types.operations.len);
 for node in self.checked.types.nodes.items[..6] { let error=self.type_nodes.push(Node {tag:node.tag,a:node.a,b:node.b,c:node.c}); if error!=Error.none { return error; } } for index in 6 { self.type_map[index]=index as u32; }
 let row=self.effect_rows.push(blot_check_effects::Row {}); if row!=Error.none { return row; } let operations=self.effect_operations.append([blot_check_types::Operation {identity:Identity {0,0}},blot_check_types::Operation {identity:Identity {0,1}}]); if operations!=Error.none { return operations; } self.effect_operation_map[blot_check_types::foreign_operation]=blot_check_types::foreign_operation; return Error.none;
}
fn deinit<C>(self: Projector<C>&) { self.pattern_nodes.deinit(); self.pattern_extra.deinit(); blot_support_pooled_map::deinit(self.pattern_map,pattern_slots); self.type_nodes.deinit(); self.quantifier_goals.deinit(); self.quantifier_obligations.deinit(); self.type_extra.deinit(); self.effect_rows.deinit(); self.effect_labels.deinit(); self.effect_operations.deinit(); self.obligations.deinit(); self.obligation_spans.deinit(); mapping_words.free_slice(self.type_map); mapping_words.free_slice(self.variable_map); mapping_words.free_slice(self.effect_row_map); mapping_words.free_slice(self.effect_variable_map); mapping_words.free_slice(self.effect_operation_map); self.type_map=[]; self.variable_map=[]; self.effect_row_map=[]; self.effect_variable_map=[]; self.effect_operation_map=[]; }
fn addType<C>(self: Projector<C>&,value: Node) -> u32,Error { if self.type_nodes.len==0xffffffff { return 0,Error.dependency_limit; } let id=self.type_nodes.len as u32; return id,self.type_nodes.push(value); }
fn saveTypes<C>(self: Projector<C>&,values: const u32[:]) -> List,Error { if values.len>0xffffffff-self.type_extra.len { return List {},Error.dependency_limit; } let start=self.type_extra.len as u32; let error=self.type_extra.append(values); if error!=Error.none { return List {},error; } return List {start,values.len as u32},Error.none; }
