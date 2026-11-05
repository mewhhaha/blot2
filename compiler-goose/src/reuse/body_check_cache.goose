// Owned relocatable body facts. Digest and capture engines share this namespace.
namespace blot_reuse_body_check_cache;
import dictionary;
import check.check;
import check.types;
import check.effects;
import check.frozen_types;
import check.capability_contracts;
import check.capability_flow;
import check.numeric_proof_headers;
import parse.ast;
import parse.symbols;
import reuse.body_auxiliary;
import reuse.project_check;
import reuse.dependency_payload;
import support.error;
import support.option;
import support.native;
import support.pooled_map;
import support.pooled_buffer;
import support.blake3;
import .body_check_digests;
import .body_check_owners;
import .body_check_syntax;
import .body_check_capture;
import .body_check_capture_helpers;
import .body_check_freeze_helpers;
import .body_check_reads;
import .body_check_freeze;
import .body_check_schema;
type Error=blot_error::Error;
type Digest=u8[32];
type Tree=blot_parse_ast::Tree;
type Pool=blot_parse_symbols::Pool;
type Id=u32;
type List=blot_check_types::List;
type Source=blot_check_frozen_types::Source;
type Identity=blot_check_types::NominalIdentity;
struct ExternalNames {
 context:blot_reuse_project_check::BodyNameContext=blot_reuse_project_check::BodyNameContext{..},
 has_unit_origin:bool=false,has_closed_rows:bool=false,has_qualification:bool=false,has_capabilities:bool=false,
}
fn lookup(self:ExternalNames,target:blot_check_check::ExternalTarget)->blot_support::Option<const u8[:]> {return self.context.lookup(target);}
fn unitOrigin(self:ExternalNames,unit:u32)->blot_support::Option<Digest> {if !self.has_unit_origin {return blot_support::none<Digest>();}return self.context.unitOrigin(unit);}
fn closedRows(self:ExternalNames,target:blot_check_check::ExternalTarget)->blot_support::Option<Digest> {if !self.has_closed_rows {return blot_support::none<Digest>();}return self.context.closedRows(target);}
fn qualification(self:ExternalNames,unit:u32,span:blot_parse_ast::Span)->blot_support::Option<Digest> {if !self.has_qualification {return blot_support::none<Digest>();}return self.context.qualification(unit,span);}
fn capabilities(self:ExternalNames,target:blot_check_check::ExternalTarget)->blot_support::Option<Digest> {if !self.has_capabilities {return blot_support::none<Digest>();}return self.context.capabilities(target);}
struct EffectAnnotation {family:u32,member:blot_support::Option<u32>=blot_support::none<u32>()}
struct AnnotationLookup {engine:const blot_check_check::Engine?=null}
fn lookup(self:AnnotationLookup,name:const u8[:])->blot_support::Option<i64> {let engine .= self.engine;if !engine {return blot_support::none<i64>();}return engine.bodyAnnotationLookup(name);}
fn effect(self:AnnotationLookup,name:const u8[:])->blot_support::Option<EffectAnnotation> {let engine .= self.engine;if !engine {return blot_support::none<EffectAnnotation>();}return engine.bodyEffectAnnotation(name);}
struct Ready {engine:const blot_check_check::Engine?=null}
fn lookup(self:Ready,binding:u32)->bool {let engine .= self.engine;if !engine {return false;}return engine.calleeSettled(binding);}
struct Values {
 capability_contracts:blot_check_capability_contracts::Collection=blot_check_capability_contracts::Collection{..},
 proof_contracts:const blot_check_check::ProofContract[:]=[],bindings:const blot_check_check::Binding[:],tree:Tree,
 names:blot_support::Option<ExternalNames>=blot_support::none<ExternalNames>(),
 annotations:blot_support::Option<AnnotationLookup>=blot_support::none<AnnotationLookup>(),
 ready:blot_support::Option<Ready>=blot_support::none<Ready>(),
}
struct RecipeEntry {index:i64=0,depth:i64=0,cost:i64=0,digest:Digest=default<Digest>()}
struct RecipeMemo {entries:RecipeEntry[64]=default<RecipeEntry[64]>(),len:i64=0}
fn lookup(self:const RecipeMemo&,index:i64,depth:i64)->blot_support::Option<RecipeEntry> {for entry in self.entries[..self.len] {if entry.index==index && entry.depth==depth {return blot_support::some(entry);}}return blot_support::none<RecipeEntry>();}
fn save(self:RecipeMemo&,index:i64,depth:i64,cost:i64,digest:Digest) {if self.len==64 {return;}self.entries[self.len]=RecipeEntry{index,depth,cost,digest, ..};self.len+=1;}
struct MemoFrame {memo:RecipeMemo=RecipeMemo{..},implementation_read:bool=false,generation:u64=0,live:bool=false}
struct MemoOwner {slot:u32=0,generation:u64=0}
reusable var memo_frames:MemoFrame[>..]=[];
fn initMemoOwner()->MemoOwner,Error {if memo_frames.len>=0xffffffff {return MemoOwner{..},Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=memo_frames.alloc_index(MemoFrame{generation:generation,live:true, ..});return MemoOwner{(at+1) as u32,generation, ..},Error.none;}
fn borrow(self:const MemoOwner&)->RecipeMemo& {assert(self.slot!=0 && self.slot-1<memo_frames.len);let frame:MemoFrame&=memo_frames[self.slot-1];assert(frame.live && frame.generation==self.generation);return frame.memo;}
fn implementationRead(self:const MemoOwner&)->bool& {let ignored=self.borrow();return memo_frames[self.slot-1].implementation_read;}
fn deinit(self:MemoOwner&) {if self.slot==0 {return;}let ignored=self.borrow();let at=self.slot-1;memo_frames[at]=MemoFrame{..};memo_frames.free(at);self=MemoOwner{..};}
struct Catalog {
 bound_scope:u32=0,private:blot_support::Option<PrivateFacts>=blot_support::none<PrivateFacts>(),recipes:RecipeMemo?=null,implementation_read:bool?=null,
 unit:u32,pool:const Pool&,nominals:const blot_check_check::Nominal[:],constructors:const blot_check_check::Constructor[:],
 effect_families:const blot_check_check::EffectFamily[:]=[],effect_templates:const blot_check_check::EffectTemplate[:]=[],
 contracts:const blot_check_check::Contract[:]=[],contract_members:const blot_check_check::ContractMember[:]=[],contract_predicates:const blot_check_types::Obligation[:]=[],
 implementations:const blot_check_check::Implementation[:]=[],implementation_members:const blot_check_check::ImplementationMember[:]=[],implementation_predicates:const blot_check_types::Obligation[:]=[],
 values:blot_support::Option<Values>=blot_support::none<Values>(),patterns:blot_support::Option<blot_check_frozen_types::Patterns>=blot_support::none<blot_check_frozen_types::Patterns>(),
}
enum NominalKind {type_,contract,operation,family}
type IdentityKind=NominalKind;
struct IdentityRead {unit:u32,origin:Digest,name:u8[:],digest:Digest,kind:NominalKind=NominalKind.type_}
struct TypeRead {position:u32,digest:Digest,effect:bool=false}
struct Fact {ty:u32,binding:u32=0,closed_rows:List=List{..}}
struct Binding {
 name:u8[:],kind:blot_check_check::Kind,private:bool,declaration:u32,owner:u32,ty:u32,scheme:bool,named_function:bool,
 capability_flow:blot_check_check::CapabilityFlow=blot_check_check::CapabilityFlow.unknown,
 capability_parameters:blot_check_capability_flow::Parameters=blot_check_capability_flow::Parameters{..},runtime:bool,
 external:blot_support::Option<blot_check_check::ExternalTarget>,interface:Digest,predecessor:u32=0,
}
struct FieldProjection {position:u32,nominal:Identity,tags:List}
struct Access {position:u32,ty:u32,nominal:Identity,tags:List,field:u32}
struct LocalScheme {binding:u32,principal:blot_check_types::Scheme}
struct Constructor {position:u32,nominal:Identity,tag:u32}
struct Merge {position:u32,result:u32,yes:u32,no:u32}
struct LoopCarry {position:u32,incoming:u32,iteration:u32,backedge:u32,outgoing:u32}
struct LoopExit {position:u32,loop:u32,bindings:List}
struct Loops {carries:LoopCarry[:]=[],exits:LoopExit[:]=[],bindings:u32[:]=[],live:bool=false}
struct Rebinding {position:u32,root:u32,self_binding:u32}
struct Projection {position:u32,index:u32,owner:u32=0}
struct Signature {position:u32,ty:u32}
struct Predicate {value:blot_check_types::Obligation,position:u32,local:bool=false,covered:bool=false,name:u8[:]}
struct Body {
 owner:Chunk&=inactive_chunk,name:u8[:]=[],source:u8[:]=[],syntax:Digest=default<Digest>(),facts:Fact[:]=[],bindings:Binding[:]=[],closed_rows:u32[:]=[],
 body_closed_rows:List=List{..},type_work:i64=0,nominals:u32[:]=[],type_reads:TypeRead[:]=[],predicates:Predicate[:]=[],signatures:Signature[:]=[],projections:Projection[:]=[],merges:Merge[:]=[],
 loops:Loops?=null,auxiliary:blot_reuse_body_auxiliary::Owner?=null,rebindings:Rebinding[:]=[],constructors:Constructor[:]=[],local_schemes:LocalScheme[:]=[],fields:FieldProjection[:]=[],accesses:Access[:]=[],field_tags:u32[:]=[],
 members:u8[:][:]=[],selection_digest:blot_support::Option<Digest>=blot_support::none<Digest>(),implementation_selection:bool=false,
}
struct Qualification {name:u32,tag:blot_parse_ast::Tag,ordinal:u32,private:bool}
struct Chunk {
 references:i64=1,graph:blot_check_frozen_types::Graph=default<blot_check_frozen_types::Graph>(),graph_owner:blot_reuse_dependency_payload::Owner=blot_reuse_dependency_payload::Owner{..},
 nominals:IdentityRead[:]=[],field_names:u8[:][:]=[],qualifications:Qualification[:]=[],bodies:Body[:]=[],body_bytes:i64=0,type_work:i64=0,live:bool=false,
}
var inactive_chunk:Chunk=Chunk{..};
reusable var chunks:Chunk[>..]=[];
reusable var loop_owners:Loops[>..]=[];
struct Lease {owner:Chunk&=inactive_chunk,index:i64=0}
fn body(self:Lease)->const Body& {assert(self.owner.live && self.index>=0 && self.index<self.owner.bodies.len);return self.owner.bodies[self.index];}
struct LeaseBuffer {storage:Lease[:]=[],items:Lease[:]=[],len:i64=0}
type NameMap=blot_support_pooled_map::Map<const u8[:],i64>;
struct CacheState {minimum_nodes:i64=64,bodies:LeaseBuffer=LeaseBuffer{..},index:NameMap=NameMap{..},generation:u64=0,live:bool=false,canonical:Cache=Cache{..}}
struct InactiveCache {minimum_nodes:i64=64,bodies:LeaseBuffer=LeaseBuffer{..},index:NameMap=NameMap{..}}
var inactive_cache:InactiveCache=InactiveCache{..};
struct Cache {minimum_nodes:i64&=inactive_cache.minimum_nodes,bodies:LeaseBuffer&=inactive_cache.bodies,index:NameMap&=inactive_cache.index,lease:u32=0,generation:u64=0}
reusable var cache_states:CacheState[>..]=[];
reusable[] var lease_runs:Lease[>..]=[];
reusable[] var name_slots:dictionary_slot<const u8[:],i64>[>..]=[];
fn valid(self:const Cache&)->bool {return self.lease!=0 && self.lease-1<cache_states.len && cache_states[self.lease-1].live && cache_states[self.lease-1].generation==self.generation;}
fn initPooled()->Cache,Error {
 if cache_states.len>=0xffffffff {return Cache{..},Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=cache_states.alloc_index(CacheState{generation:generation,live:true, ..});let state:CacheState&=cache_states[at];
 state.canonical=Cache{state.minimum_nodes,state.bodies,state.index,(at+1) as u32,generation, ..};return state.canonical,Error.none;
}
fn init()->Cache,Error {return initPooled();}
fn initPooledRef()->Cache?,Error {let result,error=initPooled();if error!=Error.none {return null,error;}return cache_states[result.lease-1].canonical,Error.none;}
fn find(self:const Cache&,name:const u8[:])->const Body? {if self.lease==0 {return null;}assert(valid(self));let index .= blot_support_pooled_map::get(self.index,name);if !index {return null;}return self.bodies.items[index].body();}
fn activate(self:Cache&)->Error {if self.lease!=0 {assert(valid(self));return Error.none;}let value,error=initPooled();if error!=Error.none {return error;}self=value;return Error.none;}
fn retain(self:Cache&,body:const Body&)->Error {
 let opened=self.activate();if opened!=Error.none {return opened;}assert(body.owner.live);var index:i64=-1;for &candidate,at in body.owner.bodies {if candidate .== body {index=at;break;}}
 if index<0 {return Error.dependency_limit;}let error=blot_support_pooled_buffer::ensure(self.bodies,self.bodies.len+1,lease_runs);if error!=Error.none {return error;}
 reserveNames(self.index,self.index.count+1);let at=self.bodies.len;self.bodies.storage[at]=Lease{body.owner,index, ..};self.bodies.items=self.bodies.storage[..at+1];self.bodies.len=at+1;blot_support_pooled_map::insert(self.index,body.name,at,name_slots);let owner_at=chunks.index_of(body.owner);assert(owner_at>=0);chunks[owner_at].references+=1;return Error.none;
}
fn reserveNames(map:NameMap&,needed:i64) {var capacity=max(8,map.slots.len);while needed*3>capacity*2 {capacity*=2;}if capacity!=map.slots.len {blot_support_pooled_map::grow(map,capacity,name_slots);}}
fn deinit(self:Cache&) {
 if self.lease==0 {return;}assert(valid(self));blot_support_pooled_map::deinit(self.index,name_slots);for lease in self.bodies.items {lease.owner.release();}blot_support_pooled_buffer::deinit(self.bodies,lease_runs);let at=self.lease-1;cache_states[at].live=false;self=Cache{..};cache_states.free(at);
}
struct LiveBytes {bytes:i64=0,types:i64=0}
fn compact(self:Cache&)->Error {
 let opened=self.activate();if opened!=Error.none {return opened;}var live=dictionary<u64,LiveBytes>{};for lease in self.bodies.items {let body=lease.body();let slot=chunks.index_of(body.owner) as u64;let current .= live.get(slot);var entry=LiveBytes{..};if current {entry=current;}entry.bytes+=body.bytes();entry.types+=body.type_work;live.insert(slot,entry);}
 var index:i64=0;while index<self.bodies.len {let body=self.bodies.items[index].body();let slot=chunks.index_of(body.owner) as u64;let active .= live.get(slot);assert(active!=null);if active.bytes>=(body.owner.body_bytes+1)/2 && active.types>=(body.owner.type_work+1)/2 {index+=1;continue;}
 blot_support_pooled_map::remove(self.index,body.name);let length=self.bodies.len-1;self.bodies.storage[index]=self.bodies.storage[length];self.bodies.items=self.bodies.storage[..length];self.bodies.len=length;if index<length {blot_support_pooled_map::insert(self.index,self.bodies.items[index].body().name,index,name_slots);}body.owner.release();}return Error.none;
}
struct Payload {bytes:i64=0,graph_nodes:i64=0,chunks:i64=0}
fn payload(self:const Cache&)->Payload,Error {
 if self.lease==0 {return Payload{..},Error.none;}assert(valid(self));var seen=dictionary<u64,bool>{};var result=Payload{bytes:self.bodies.len*16, ..};for lease in self.bodies.items {let owner .= lease.owner;let at=chunks.index_of(owner) as u64;if seen.contains(at) {continue;}seen.insert(at,true);let graph=owner.graph;
 result.bytes+=chunk_footprint+owner.qualifications.len*qualification_footprint+owner.body_bytes+graph.nodes.len*type_node_footprint+graph.extra.len*4+graph.rows.len*effect_row_footprint+graph.labels.len*4+graph.operations.len*operation_footprint+graph.quantifier_goals.len*12+graph.quantifier_obligations.len*obligation_footprint;
 result.bytes+=owner.nominals.len*identity_read_footprint;for nominal in owner.nominals {result.bytes+=nominal.name.len;}result.bytes+=owner.field_names.len*16;for name in owner.field_names {result.bytes+=name.len;}result.graph_nodes+=graph.nodes.len;}
 result.chunks=seen.count;return result,Error.none;
}
fn clone(self:const Cache&)->Cache,Error {let value,error=initPooled();if error!=Error.none {return Cache{..},error;}var result=value;result.minimum_nodes=self.minimum_nodes;for lease in self.bodies.items {let error=result.retain(lease.body());if error!=Error.none {result.deinit();return Cache{..},error;}}return result,Error.none;}
