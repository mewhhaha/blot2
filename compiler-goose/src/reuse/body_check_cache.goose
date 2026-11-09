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
fn lookup(self_:ExternalNames,target:blot_check_check::ExternalTarget)->blot_support::Option<const u8[:]> {return self_.context.lookup(target);}
fn unitOrigin(self_:ExternalNames,unit:u32)->blot_support::Option<Digest> {if !self_.has_unit_origin {return blot_support::none<Digest>();}return self_.context.unitOrigin(unit);}
fn closedRows(self_:ExternalNames,target:blot_check_check::ExternalTarget)->blot_support::Option<Digest> {if !self_.has_closed_rows {return blot_support::none<Digest>();}return self_.context.closedRows(target);}
fn qualification(self_:ExternalNames,unit:u32,span:blot_parse_ast::Span)->blot_support::Option<Digest> {if !self_.has_qualification {return blot_support::none<Digest>();}return self_.context.qualification(unit,span);}
fn capabilities(self_:ExternalNames,target:blot_check_check::ExternalTarget)->blot_support::Option<Digest> {if !self_.has_capabilities {return blot_support::none<Digest>();}return self_.context.capabilities(target);}
struct EffectAnnotation {family:u32,member:blot_support::Option<u32> =blot_support::none<u32>()}
struct AnnotationLookup {engine:const blot_check_check::Engine?=null}
fn lookup(self_:AnnotationLookup,name:const u8[:])->blot_support::Option<i64> {let engine .= self_.engine;if !engine {return blot_support::none<i64>();}return engine.bodyAnnotationLookup(name);}
fn effect(self_:AnnotationLookup,name:const u8[:])->blot_support::Option<EffectAnnotation> {let engine .= self_.engine;if !engine {return blot_support::none<EffectAnnotation>();}return engine.bodyEffectAnnotation(name);}
struct Ready {engine:const blot_check_check::Engine?=null}
fn lookup(self_:Ready,binding:u32)->bool {let engine .= self_.engine;if !engine {return false;}return engine.calleeSettled(binding);}
struct Values {
 capability_contracts:blot_check_capability_contracts::Collection=blot_check_capability_contracts::Collection{..},
 proof_contracts:const blot_check_check::ProofContract[:]=default<const blot_check_check::ProofContract[:]>(),bindings:const blot_check_check::Binding[:],tree:Tree,
 names:blot_support::Option<ExternalNames> =blot_support::none<ExternalNames>(),
 annotations:blot_support::Option<AnnotationLookup> =blot_support::none<AnnotationLookup>(),
 ready:blot_support::Option<Ready> =blot_support::none<Ready>(),
}
struct RecipeEntry {index:i64=0,depth:i64=0,cost:i64=0,digest:Digest=default<Digest>()}
struct RecipeMemo {entries:RecipeEntry[64]=default<RecipeEntry[64]>(),len:i64=0}
fn lookup(self_:const RecipeMemo&,index:i64,depth:i64)->blot_support::Option<RecipeEntry> {for entry in self_.entries[..self_.len] {if entry.index==index && entry.depth==depth {return blot_support::some(entry);}}return blot_support::none<RecipeEntry>();}
fn save(self_:RecipeMemo&,index:i64,depth:i64,cost:i64,digest:Digest) {if self_.len==64 {return;}self_.entries[self_.len]=RecipeEntry{index,depth,cost,digest, ..};self_.len+=1;}
struct MemoFrame {memo:RecipeMemo=RecipeMemo{..},implementation_read:bool=false,generation:u64=0,live:bool=false}
struct MemoOwner {slot:u32=0,generation:u64=0}
reusable var memo_frames:MemoFrame[>..]=[];
fn initMemoOwner()->MemoOwner,Error {if memo_frames.len>=0xffffffff {return MemoOwner{..},blot_error::Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=memo_frames.alloc_index(MemoFrame{generation:generation,live:true, ..});return MemoOwner{(at+1) as u32,generation, ..},blot_error::Error.none;}
fn borrow(self_:const MemoOwner&)->RecipeMemo& {assert(self_.slot!=0 && self_.slot-1<memo_frames.len);let frame:MemoFrame& =memo_frames[self_.slot-1];assert(frame.live && frame.generation==self_.generation);return frame.memo;}
fn implementationRead(self_:const MemoOwner&)->bool& {let ignored=self_.borrow();return memo_frames[self_.slot-1].implementation_read;}
fn deinit(self_:MemoOwner&) {if self_.slot==0 {return;}let ignored=self_.borrow();let at=self_.slot-1;memo_frames[at]=MemoFrame{..};memo_frames.free(at);self_=MemoOwner{..};}
struct Catalog {
 bound_scope:u32=0,private:blot_support::Option<PrivateFacts> =blot_support::none<PrivateFacts>(),recipes:RecipeMemo?=null,implementation_read:bool?=null,
 unit:u32,pool:const Pool&,nominals:const blot_check_check::Nominal[:],constructors:const blot_check_check::Constructor[:],
 effect_families:const blot_check_check::EffectFamily[:]=default<const blot_check_check::EffectFamily[:]>(),effect_templates:const blot_check_check::EffectTemplate[:]=default<const blot_check_check::EffectTemplate[:]>(),
 contracts:const blot_check_check::Contract[:]=default<const blot_check_check::Contract[:]>(),contract_members:const blot_check_check::ContractMember[:]=default<const blot_check_check::ContractMember[:]>(),contract_predicates:const blot_check_types::Obligation[:]=default<const blot_check_types::Obligation[:]>(),
 implementations:const blot_check_check::Implementation[:]=default<const blot_check_check::Implementation[:]>(),implementation_members:const blot_check_check::ImplementationMember[:]=default<const blot_check_check::ImplementationMember[:]>(),implementation_predicates:const blot_check_types::Obligation[:]=default<const blot_check_types::Obligation[:]>(),
 values:blot_support::Option<Values> =blot_support::none<Values>(),patterns:blot_support::Option<blot_check_frozen_types::Patterns> =blot_support::none<blot_check_frozen_types::Patterns>(),
}
enum NominalKind {type_,contract,operation,family}
type IdentityKind=NominalKind;
struct IdentityRead {unit:u32,origin:Digest,name:u8[:],digest:Digest,kind:NominalKind=NominalKind.type_}
struct TypeRead {position:u32,digest:Digest,effect:bool=false}
struct Fact {ty:u32,binding:u32=0,closed_rows:List=List{..}}
struct Binding {
 name:u8[:],kind:blot_check_check::Kind,private:bool,declaration:u32,owner:u32,ty:u32,scheme:bool,named_function:bool,
 capability_flow:blot_check_check::CapabilityFlow=blot_check_capability_flow::Contract.unknown,
 capability_parameters:blot_check_capability_flow::Parameters=blot_check_capability_flow::Parameters{..},runtime:bool,
 external:blot_support::Option<blot_check_check::ExternalTarget>,interface:Digest,predecessor:u32=0,
}
struct FieldProjection {position:u32,nominal:Identity,tags:List}
struct Access {position:u32,ty:u32,nominal:Identity,tags:List,field:u32}
struct LocalScheme {binding:u32,principal:blot_check_types::Scheme}
struct Constructor {position:u32,nominal:Identity,tag:u32}
struct Merge {position:u32,result:u32,yes:u32,no:u32}
struct LoopCarry {position:u32,incoming:u32,iteration:u32,backedge:u32,outgoing:u32}
struct LoopExit {position:u32,loop_:u32,bindings:List}
struct Loops {carries:LoopCarry[:]=default<LoopCarry[:]>(),exits:LoopExit[:]=default<LoopExit[:]>(),bindings:u32[:]=default<u32[:]>(),live:bool=false,slot:u32=0}
struct Rebinding {position:u32,root:u32,self_binding:u32}
struct Projection {position:u32,index:u32,owner:u32=0}
struct Signature {position:u32,ty:u32}
struct Predicate {value:blot_check_types::Obligation,position:u32,local:bool=false,covered:bool=false,name:u8[:]}
struct Body {
 owner:Chunk& =inactive_chunk,name:u8[:]=default<u8[:]>(),source:u8[:]=default<u8[:]>(),syntax:Digest=default<Digest>(),facts:Fact[:]=default<Fact[:]>(),bindings:Binding[:]=default<Binding[:]>(),closed_rows:u32[:]=default<u32[:]>(),
 body_closed_rows:List=List{..},type_work:i64=0,nominals:u32[:]=default<u32[:]>(),type_reads:TypeRead[:]=default<TypeRead[:]>(),predicates:Predicate[:]=default<Predicate[:]>(),signatures:Signature[:]=default<Signature[:]>(),projections:Projection[:]=default<Projection[:]>(),merges:Merge[:]=default<Merge[:]>(),
 loops:Loops?=null,auxiliary:blot_reuse_body_auxiliary::Owner?=null,rebindings:Rebinding[:]=default<Rebinding[:]>(),constructors:Constructor[:]=default<Constructor[:]>(),local_schemes:LocalScheme[:]=default<LocalScheme[:]>(),fields:FieldProjection[:]=default<FieldProjection[:]>(),accesses:Access[:]=default<Access[:]>(),field_tags:u32[:]=default<u32[:]>(),
 members:u8[:][:]=default<u8[:][:]>(),selection_digest:blot_support::Option<Digest> =blot_support::none<Digest>(),implementation_selection:bool=false,
}
struct Qualification {name:u32,tag:blot_parse_ast::Tag,ordinal:u32,private:bool}
struct Chunk {
 references:i64=1,graph:blot_check_frozen_types::Graph=default<blot_check_frozen_types::Graph>(),graph_owner:blot_reuse_dependency_payload::Owner=blot_reuse_dependency_payload::Owner{..},
 nominals:IdentityRead[:]=default<IdentityRead[:]>(),field_names:u8[:][:]=default<u8[:][:]>(),qualifications:Qualification[:]=default<Qualification[:]>(),bodies:Body[:]=default<Body[:]>(),body_bytes:i64=0,type_work:i64=0,live:bool=false,slot:u32=0,
}
var inactive_chunk:Chunk=Chunk{..};
reusable var chunks:Chunk[>..]=[];
fn chunkIndex(owner:const Chunk&)->i64 {assert(owner.live && owner.slot!=0);let index=owner.slot as i64-1;assert(index<chunks.len);let canonical:const Chunk& =chunks[index];assert(canonical .== owner);return index;}
reusable var loop_owners:Loops[>..]=[];
fn loopIndex(owner:const Loops&)->i64 {assert(owner.live && owner.slot!=0);let index=owner.slot as i64-1;assert(index<loop_owners.len);let canonical:const Loops& =loop_owners[index];assert(canonical .== owner);return index;}
struct Lease {owner:Chunk& =inactive_chunk,index:i64=0}
fn body(self_:Lease)->const Body& {assert(self_.owner.live && self_.index>=0 && self_.index<self_.owner.bodies.len);return self_.owner.bodies[self_.index];}
struct LeaseBuffer {storage:Lease[:]=default<Lease[:]>(),items:Lease[:]=default<Lease[:]>(),len:i64=0}
struct NameSlot {body:i64=0,tag:u32=0}
struct NameMap {count:i64=0,slots:NameSlot[:]=default<NameSlot[:]>()}
struct CacheState {minimum_nodes:i64=64,bodies:LeaseBuffer=LeaseBuffer{..},index:NameMap=NameMap{..},generation:u64=0,live:bool=false,canonical:Cache=Cache{..}}
struct InactiveCache {minimum_nodes:i64=64,bodies:LeaseBuffer=LeaseBuffer{..},index:NameMap=NameMap{..}}
var inactive_cache:InactiveCache=InactiveCache{..};
struct Cache {minimum_nodes:i64& =inactive_cache.minimum_nodes,bodies:LeaseBuffer& =inactive_cache.bodies,index:NameMap& =inactive_cache.index,lease:u32=0,generation:u64=0}
reusable var cache_states:CacheState[>..]=[];
reusable[] var lease_runs:Lease[>..]=[];
reusable[] var name_slots:NameSlot[>..]=[];
fn valid(self_:const Cache&)->bool {return self_.lease!=0 && self_.lease-1<cache_states.len && cache_states[self_.lease-1].live && cache_states[self_.lease-1].generation==self_.generation;}
fn initPooled()->Cache,Error {
 if cache_states.len>=0xffffffff {return Cache{..},blot_error::Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=cache_states.alloc_index(CacheState{generation:generation,live:true, ..});let state:CacheState& =cache_states[at];
 let result=Cache{cache_states[at].minimum_nodes,cache_states[at].bodies,cache_states[at].index,(at+1) as u32,generation, ..};state.canonical=result;return result,blot_error::Error.none;
}
fn init()->Cache,Error {return initPooled();}
fn initPooledRef()->Cache?,Error {let result,error=initPooled();if error!=blot_error::Error.none {return null,error;}return cache_states[result.lease-1].canonical,blot_error::Error.none;}
fn find(self_:const Cache&,name:const u8[:])->const Body? {if self_.lease==0 {return null;}assert(valid(self_));let slot=probeName(self_,name);if slot<0 {return null;}return self_.bodies.items[self_.index.slots[slot].body].body();}
fn activate(self_:Cache&)->Error {if self_.lease!=0 {assert(valid(self_));return blot_error::Error.none;}let value,error=initPooled();if error!=blot_error::Error.none {return error;}self_=value;return blot_error::Error.none;}
fn setBodyLength(self_:Cache&,length:i64) {let storage=lease_runs.realloc_slice(self_.bodies.storage,self_.bodies.storage.len);self_.bodies.storage=storage;self_.bodies.items=storage[..length];self_.bodies.len=length;}
fn removeBody(self_:Cache&,index:i64) {let length=self_.bodies.len-1;let storage=lease_runs.realloc_slice(self_.bodies.storage,self_.bodies.storage.len);storage[index]=storage[length];self_.bodies.storage=storage;self_.bodies.items=storage[..length];self_.bodies.len=length;}
fn retain(self_:Cache&,body:const Body&)->Error {
 let opened=self_.activate();if opened!=blot_error::Error.none {return opened;}assert(body.owner.live);var index:i64=-1;for &candidate,at in body.owner.bodies {if candidate .== body {index=at;break;}}
 if index<0 {return blot_error::Error.dependency_limit;}let error=blot_support_pooled_buffer::ensure(self_.bodies,self_.bodies.len+1,lease_runs);if error!=blot_error::Error.none {return error;}
 reserveNames(self_,self_.index.count+1);let owner_at=chunkIndex(body.owner);assert(owner_at>=0);let at=self_.bodies.len;self_.bodies.storage[at]=Lease{chunks[owner_at],index, ..};setBodyLength(self_,at+1);insertName(self_,at);chunks[owner_at].references+=1;return blot_error::Error.none;
}
// Compaction repairs a moved slot after truncation; its old lease remains in storage.
fn nameAt(self_:const Cache&,body:i64)->const u8[:] {assert(body>=0 && body<self_.bodies.storage.len);return self_.bodies.storage[body].body().name;}
fn probeName(self_:const Cache&,name:const u8[:])->i64 {
 if self_.index.count==0 {return -1;}let hash=::hash(name);let tag=(hash as! u32)|2147483648;let mask=self_.index.slots.len-1;var index=(hash&(mask as u64)) as i64;
 loop {let slot=self_.index.slots[index];if slot.tag==tag && nameAt(self_,slot.body)==name {return index;}if slot.tag==0 {return -1;}index=(index+1)&mask;}
}
fn reserveNames(self_:Cache&,needed:i64) {
 var capacity=max(8,self_.index.slots.len);while needed*3>capacity*2 {capacity*=2;}if capacity==self_.index.slots.len {return;}
 // Keep the old run until every scalar slot has been rehashed.
 let old=self_.index.slots;let slots=name_slots.alloc_slice(capacity);for &slot in slots {slot=NameSlot{..};}let mask=capacity-1;
 for slot in old {if slot.tag==0 {continue;}let name=nameAt(self_,slot.body);var index=(::hash(name)&(mask as u64)) as i64;while slots[index].tag!=0 {index=(index+1)&mask;}slots[index]=slot;}
 self_.index.slots=slots;if old.len!=0 {name_slots.free_slice(old);}
}
fn insertName(self_:Cache&,body:i64) {
 reserveNames(self_,self_.index.count+1);let name=nameAt(self_,body);let hash=::hash(name);let tag=(hash as! u32)|2147483648;let mask=self_.index.slots.len-1;var index=(hash&(mask as u64)) as i64;
 loop {let slot=self_.index.slots[index];if slot.tag==0 {self_.index.slots[index]=NameSlot{body,tag};self_.index.count+=1;return;}if slot.tag==tag && nameAt(self_,slot.body)==name {self_.index.slots[index]=NameSlot{body,tag};return;}index=(index+1)&mask;}
}
fn removeName(self_:Cache&,name:const u8[:])->bool {
 var hole=probeName(self_,name);if hole<0 {return false;}let mask=self_.index.slots.len-1;var index=hole;
 loop {index=(index+1)&mask;let slot=self_.index.slots[index];if slot.tag==0 {break;}let key=nameAt(self_,slot.body);let home=(::hash(key)&(mask as u64)) as i64;if ((index-home)&mask)>=((index-hole)&mask) {self_.index.slots[hole]=slot;hole=index;}}
 self_.index.slots[hole]=NameSlot{..};self_.index.count-=1;return true;
}
fn deinit(self_:Cache&) {
 if self_.lease==0 {return;}assert(valid(self_));if self_.index.slots.len!=0 {name_slots.free_slice(self_.index.slots);}self_.index=NameMap{..};for lease in self_.bodies.items {lease.owner.release();}blot_support_pooled_buffer::deinit(self_.bodies,lease_runs);let at=self_.lease-1;cache_states[at].live=false;self_=Cache{..};cache_states.free(at);
}
struct LiveBytes {bytes:i64=0,types:i64=0}
fn compact(self_:Cache&)->Error {
 let opened=self_.activate();if opened!=blot_error::Error.none {return opened;}var live=dictionary<u64,LiveBytes>{};for lease in self_.bodies.items {let body=lease.body();let slot=chunkIndex(body.owner) as u64;let current .= live.get(slot);var entry=LiveBytes{..};if current {entry=current;}entry.bytes+=body.bytes();entry.types+=body.type_work;live.insert(slot,entry);}
 var index:i64=0;while index<self_.bodies.len {let body=self_.bodies.items[index].body();let slot=chunkIndex(body.owner) as u64;let active .= live.get(slot);assert(active!=null);if active.bytes>=(body.owner.body_bytes+1)/2 && active.types>=(body.owner.type_work+1)/2 {index+=1;continue;}
 removeName(self_,body.name);removeBody(self_,index);if index<self_.bodies.len {insertName(self_,index);}body.owner.release();}return blot_error::Error.none;
}
struct Payload {bytes:i64=0,graph_nodes:i64=0,chunks:i64=0}
fn payload(self_:const Cache&)->Payload,Error {
 if self_.lease==0 {return Payload{..},blot_error::Error.none;}assert(valid(self_));var seen=dictionary<u64,bool>{};var result=Payload{bytes:self_.bodies.len*16, ..};for lease in self_.bodies.items {let owner .= lease.owner;let at=chunkIndex(owner) as u64;if seen.contains(at) {continue;}seen.insert(at,true);let graph=owner.graph;
 result.bytes+=chunk_footprint+owner.qualifications.len*qualification_footprint+owner.body_bytes+graph.nodes.len*type_node_footprint+graph.extra.len*4+graph.rows.len*effect_row_footprint+graph.labels.len*4+graph.operations.len*operation_footprint+graph.quantifier_goals.len*12+graph.quantifier_obligations.len*obligation_footprint;
 result.bytes+=owner.nominals.len*identity_read_footprint;for nominal in owner.nominals {result.bytes+=nominal.name.len;}result.bytes+=owner.field_names.len*16;for name in owner.field_names {result.bytes+=name.len;}result.graph_nodes+=graph.nodes.len;}
 result.chunks=seen.count;return result,blot_error::Error.none;
}
fn clone(self_:const Cache&)->Cache,Error {let value,error=initPooled();if error!=blot_error::Error.none {return Cache{..},error;}var result=value;result.minimum_nodes=self_.minimum_nodes;for lease in self_.bodies.items {let error=result.retain(lease.body());if error!=blot_error::Error.none {result.deinit();return Cache{..},error;}}return result,blot_error::Error.none;}
