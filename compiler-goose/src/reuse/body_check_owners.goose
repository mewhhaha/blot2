// Concrete immutable cache runs and packed C.2 payload accounting.
namespace blot_reuse_body_check_cache;
import .body_check_cache;
// Frozen graph publication reifies only the owner's exact registered live runs.
fn canonicalFrozenGraph(owner:blot_reuse_dependency_payload::Owner,value:blot_check_frozen_types::Graph)->blot_check_frozen_types::Graph {
 assert(blot_reuse_dependency_payload::unique(owner));
 return blot_check_frozen_types::Graph{nodes:owner.mutable(value.nodes),extra:owner.mutable(value.extra),rows:owner.mutable(value.rows),labels:owner.mutable(value.labels),operations:owner.mutable(value.operations),row_variable_count:value.row_variable_count,quantifier_goals:owner.mutable(value.quantifier_goals),quantifier_obligations:owner.mutable(value.quantifier_obligations)};
}
fn canonicalOwnedName(value:u8[:])->u8[:] {if value.len==0 {return default<u8[:]>();}let owned=owned_u8.realloc_slice(value,value.len);assert(blot_support::same_slice_identity(owned,value));return owned;}
fn canonicalIdentityRead(value:IdentityRead)->IdentityRead {return IdentityRead{unit:value.unit,origin:value.origin,name:canonicalOwnedName(value.name),digest:value.digest,kind:value.kind};}
fn canonicalQualification(value:Qualification)->Qualification {return Qualification{name:value.name,tag:value.tag,ordinal:value.ordinal,private:value.private};}
reusable[] var owned_u8:u8[>..]=[];
fn copyOwned(values:const u8[:])->u8[:] {if values.len==0 {return default<u8[:]>();}let run=owned_u8.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const u8[:]) {if values.len==0 {return;}owned_u8.free_slice(values);}
reusable[] var owned_u32:u32[>..]=[];
fn copyOwned(values:const u32[:])->u32[:] {if values.len==0 {return default<u32[:]>();}let run=owned_u32.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const u32[:]) {if values.len==0 {return;}owned_u32.free_slice(values);}
reusable[] var owned_bool:bool[>..]=[];
fn copyOwned(values:const bool[:])->bool[:] {if values.len==0 {return default<bool[:]>();}let run=owned_bool.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const bool[:]) {if values.len==0 {return;}owned_bool.free_slice(values);}
reusable[] var owned_Fact:Fact[>..]=[];
fn copyOwned(values:const Fact[:])->Fact[:] {if values.len==0 {return default<Fact[:]>();}let run=owned_Fact.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Fact[:]) {if values.len==0 {return;}owned_Fact.free_slice(values);}
reusable[] var owned_Binding:Binding[>..]=[];
fn copyOwned(values:const Binding[:])->Binding[:] {if values.len==0 {return default<Binding[:]>();}let run=owned_Binding.alloc_slice(values.len);for value,index in values {let name=canonicalOwnedName(value.name);run[index]=Binding{name:name,kind:value.kind,private:value.private,declaration:value.declaration,owner:value.owner,ty:value.ty,scheme:value.scheme,named_function:value.named_function,capability_flow:value.capability_flow,capability_parameters:value.capability_parameters,runtime:value.runtime,external:value.external,interface:value.interface,predecessor:value.predecessor};}return run;}
fn cloneBindings(values:const Binding[:])->Binding[:] {if values.len==0 {return default<Binding[:]>();}let run=owned_Binding.alloc_slice(values.len);for value,index in values {let name=copyOwned(value.name);run[index]=Binding{name:name,kind:value.kind,private:value.private,declaration:value.declaration,owner:value.owner,ty:value.ty,scheme:value.scheme,named_function:value.named_function,capability_flow:value.capability_flow,capability_parameters:value.capability_parameters,runtime:value.runtime,external:value.external,interface:value.interface,predecessor:value.predecessor};}return run;}
fn releaseOwned(values:const Binding[:]) {if values.len==0 {return;}owned_Binding.free_slice(values);}
reusable[] var owned_TypeRead:TypeRead[>..]=[];
fn copyOwned(values:const TypeRead[:])->TypeRead[:] {if values.len==0 {return default<TypeRead[:]>();}let run=owned_TypeRead.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const TypeRead[:]) {if values.len==0 {return;}owned_TypeRead.free_slice(values);}
reusable[] var owned_Predicate:Predicate[>..]=[];
fn copyOwned(values:const Predicate[:])->Predicate[:] {if values.len==0 {return default<Predicate[:]>();}let run=owned_Predicate.alloc_slice(values.len);for value,index in values {let name=canonicalOwnedName(value.name);run[index]=Predicate{value:value.value,position:value.position,local:value.local,covered:value.covered,name:name};}return run;}
fn clonePredicates(values:const Predicate[:])->Predicate[:] {if values.len==0 {return default<Predicate[:]>();}let run=owned_Predicate.alloc_slice(values.len);for value,index in values {let name=copyOwned(value.name);run[index]=Predicate{value:value.value,position:value.position,local:value.local,covered:value.covered,name:name};}return run;}
fn releaseOwned(values:const Predicate[:]) {if values.len==0 {return;}owned_Predicate.free_slice(values);}
reusable[] var owned_Signature:Signature[>..]=[];
fn copyOwned(values:const Signature[:])->Signature[:] {if values.len==0 {return default<Signature[:]>();}let run=owned_Signature.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Signature[:]) {if values.len==0 {return;}owned_Signature.free_slice(values);}
reusable[] var owned_Projection:Projection[>..]=[];
fn copyOwned(values:const Projection[:])->Projection[:] {if values.len==0 {return default<Projection[:]>();}let run=owned_Projection.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Projection[:]) {if values.len==0 {return;}owned_Projection.free_slice(values);}
reusable[] var owned_Merge:Merge[>..]=[];
fn copyOwned(values:const Merge[:])->Merge[:] {if values.len==0 {return default<Merge[:]>();}let run=owned_Merge.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Merge[:]) {if values.len==0 {return;}owned_Merge.free_slice(values);}
reusable[] var owned_Rebinding:Rebinding[>..]=[];
fn copyOwned(values:const Rebinding[:])->Rebinding[:] {if values.len==0 {return default<Rebinding[:]>();}let run=owned_Rebinding.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Rebinding[:]) {if values.len==0 {return;}owned_Rebinding.free_slice(values);}
reusable[] var owned_Constructor:Constructor[>..]=[];
fn copyOwned(values:const Constructor[:])->Constructor[:] {if values.len==0 {return default<Constructor[:]>();}let run=owned_Constructor.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Constructor[:]) {if values.len==0 {return;}owned_Constructor.free_slice(values);}
reusable[] var owned_LocalScheme:LocalScheme[>..]=[];
fn copyOwned(values:const LocalScheme[:])->LocalScheme[:] {if values.len==0 {return default<LocalScheme[:]>();}let run=owned_LocalScheme.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const LocalScheme[:]) {if values.len==0 {return;}owned_LocalScheme.free_slice(values);}
reusable[] var owned_FieldProjection:FieldProjection[>..]=[];
fn copyOwned(values:const FieldProjection[:])->FieldProjection[:] {if values.len==0 {return default<FieldProjection[:]>();}let run=owned_FieldProjection.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const FieldProjection[:]) {if values.len==0 {return;}owned_FieldProjection.free_slice(values);}
reusable[] var owned_Access:Access[>..]=[];
fn copyOwned(values:const Access[:])->Access[:] {if values.len==0 {return default<Access[:]>();}let run=owned_Access.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Access[:]) {if values.len==0 {return;}owned_Access.free_slice(values);}
reusable[] var owned_LoopCarry:LoopCarry[>..]=[];
fn copyOwned(values:const LoopCarry[:])->LoopCarry[:] {if values.len==0 {return default<LoopCarry[:]>();}let run=owned_LoopCarry.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const LoopCarry[:]) {if values.len==0 {return;}owned_LoopCarry.free_slice(values);}
reusable[] var owned_LoopExit:LoopExit[>..]=[];
fn copyOwned(values:const LoopExit[:])->LoopExit[:] {if values.len==0 {return default<LoopExit[:]>();}let run=owned_LoopExit.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const LoopExit[:]) {if values.len==0 {return;}owned_LoopExit.free_slice(values);}
reusable[] var owned_IdentityRead:IdentityRead[>..]=[];
fn copyOwned(values:const IdentityRead[:])->IdentityRead[:] {if values.len==0 {return default<IdentityRead[:]>();}let run=owned_IdentityRead.alloc_slice(values.len);for value,index in values {run[index]=canonicalIdentityRead(value);}return run;}
fn cloneIdentityReads(values:const IdentityRead[:])->IdentityRead[:] {if values.len==0 {return default<IdentityRead[:]>();}let run=owned_IdentityRead.alloc_slice(values.len);for value,index in values {let name=copyOwned(value.name);run[index]=IdentityRead{unit:value.unit,origin:value.origin,name:name,digest:value.digest,kind:value.kind};}return run;}
fn releaseOwned(values:const IdentityRead[:]) {if values.len==0 {return;}owned_IdentityRead.free_slice(values);}
reusable[] var owned_Qualification:Qualification[>..]=[];
fn copyOwned(values:const Qualification[:])->Qualification[:] {if values.len==0 {return default<Qualification[:]>();}let run=owned_Qualification.alloc_slice(values.len);for value,index in values {run[index]=canonicalQualification(value);}return run;}
fn releaseOwned(values:const Qualification[:]) {if values.len==0 {return;}owned_Qualification.free_slice(values);}
reusable[] var owned_Body:Body[>..]=[];
// Freeze transfers existing runs; the containing chunk publishes body.owner afterward.
fn canonicalBody(value:Body)->Body {return Body{owner:inactive_chunk,name:canonicalOwnedName(value.name),source:canonicalOwnedName(value.source),syntax:value.syntax,facts:owned_Fact.realloc_slice(value.facts,value.facts.len),bindings:owned_Binding.realloc_slice(value.bindings,value.bindings.len),closed_rows:owned_u32.realloc_slice(value.closed_rows,value.closed_rows.len),body_closed_rows:value.body_closed_rows,type_work:value.type_work,nominals:owned_u32.realloc_slice(value.nominals,value.nominals.len),type_reads:owned_TypeRead.realloc_slice(value.type_reads,value.type_reads.len),predicates:owned_Predicate.realloc_slice(value.predicates,value.predicates.len),signatures:owned_Signature.realloc_slice(value.signatures,value.signatures.len),projections:owned_Projection.realloc_slice(value.projections,value.projections.len),merges:owned_Merge.realloc_slice(value.merges,value.merges.len),loops:ownedLoops(value.loops),auxiliary:ownedAuxiliary(value.auxiliary),rebindings:owned_Rebinding.realloc_slice(value.rebindings,value.rebindings.len),constructors:owned_Constructor.realloc_slice(value.constructors,value.constructors.len),local_schemes:owned_LocalScheme.realloc_slice(value.local_schemes,value.local_schemes.len),fields:owned_FieldProjection.realloc_slice(value.fields,value.fields.len),accesses:owned_Access.realloc_slice(value.accesses,value.accesses.len),field_tags:owned_u32.realloc_slice(value.field_tags,value.field_tags.len),members:owned_u8___.realloc_slice(value.members,value.members.len),selection_digest:value.selection_digest,implementation_selection:value.implementation_selection};}
fn copyOwned(values:const Body[:])->Body[:] {if values.len==0 {return default<Body[:]>();}let run=owned_Body.alloc_slice(values.len);for value,index in values {run[index]=canonicalBody(value);}return run;}
fn ownedLoops(value:Loops?)->Loops? {if value {let index=loopIndex(value);return loop_owners[index];}return null;}
fn ownedAuxiliary(value:blot_reuse_body_auxiliary::Owner?)->blot_reuse_body_auxiliary::Owner? {if value {let index=blot_reuse_body_auxiliary::ownerIndex(value);return blot_reuse_body_auxiliary::owners[index];}return null;}
fn releaseOwned(values:const Body[:]) {if values.len==0 {return;}owned_Body.free_slice(values);}
reusable[] var owned_u8___:u8[:][>..]=[];
fn copyOwned(values:const (u8[:])[:])->u8[:][:] {if values.len==0 {return default<u8[:][:]>();}let run=owned_u8___.alloc_slice(values.len);for value,index in values {run[index]=canonicalOwnedName(value);}return run;}
fn cloneNames(values:const (u8[:])[:])->u8[:][:] {if values.len==0 {return default<u8[:][:]>();}let run=owned_u8___.alloc_slice(values.len);for value,index in values {run[index]=copyOwned(value);}return run;}
fn releaseOwned(values:const (u8[:])[:]) {if values.len==0 {return;}owned_u8___.free_slice(values);}
let body_footprint:i64=394;
let chunk_footprint:i64=217;
let qualification_footprint:i64=13;
let identity_read_footprint:i64=85;
let type_node_footprint:i64=16;
let effect_row_footprint:i64=17;
let operation_footprint:i64=24;
let obligation_footprint:i64=48;
fn bytes(self_:const Body&)->i64 {var total=body_footprint+self_.name.len+self_.source.len;
total+=self_.facts.len*16;
total+=self_.bindings.len*92;
total+=self_.closed_rows.len*4;
total+=self_.nominals.len*4;
total+=self_.type_reads.len*37;
total+=self_.predicates.len*70;
total+=self_.fields.len*20;
total+=self_.field_tags.len*4;
total+=self_.local_schemes.len*48;
total+=self_.constructors.len*16;
total+=self_.merges.len*16;
total+=self_.projections.len*12;
total+=self_.signatures.len*8;
total+=self_.accesses.len*28;
total+=self_.rebindings.len*12;
total+=self_.members.len*16;
for binding in self_.bindings {total+=binding.name.len;}for predicate in self_.predicates {total+=predicate.name.len;}for member in self_.members {total+=member.len;}let loops .= self_.loops;if loops {total+=49+loops.carries.len*20+loops.exits.len*16+loops.bindings.len*4;}let auxiliary .= self_.auxiliary;if auxiliary {total+=auxiliary.bytes();}return total;}
fn deinit(self_:Loops&) {let at=loopIndex(self_);releaseOwned(self_.carries);releaseOwned(self_.exits);releaseOwned(self_.bindings);self_=Loops{..};loop_owners.free(at);}
fn deinit(self_:Body&) {
releaseOwned(self_.name);
releaseOwned(self_.source);
releaseOwned(self_.facts);
releaseOwned(self_.closed_rows);
releaseOwned(self_.nominals);
releaseOwned(self_.type_reads);
for binding in self_.bindings {releaseOwned(binding.name);}releaseOwned(self_.bindings);for predicate in self_.predicates {releaseOwned(predicate.name);}releaseOwned(self_.predicates);
releaseOwned(self_.signatures);
releaseOwned(self_.projections);
releaseOwned(self_.merges);
releaseOwned(self_.rebindings);
releaseOwned(self_.constructors);
releaseOwned(self_.local_schemes);
releaseOwned(self_.fields);
releaseOwned(self_.accesses);
releaseOwned(self_.field_tags);
let loops .= self_.loops;if loops {loops.deinit();}let auxiliary .= self_.auxiliary;if auxiliary {auxiliary.deinit();}for member in self_.members {releaseOwned(member);}releaseOwned(self_.members);self_=Body{..};}
fn release(self_:Chunk&) {assert(self_.live && self_.references>0);self_.references-=1;if self_.references!=0 {return;}for &body in self_.bodies {body.deinit();}releaseOwned(self_.bodies);self_.graph_owner.deinit();for nominal in self_.nominals {releaseOwned(nominal.name);}releaseOwned(self_.nominals);for name in self_.field_names {releaseOwned(name);}releaseOwned(self_.field_names);releaseOwned(self_.qualifications);let at=chunkIndex(self_);assert(at>=0);self_=Chunk{..};chunks.free(at);}
fn publishChunk(cache:Cache&,owner:Chunk&)->Error {let error=publishChunkBodies(cache,owner);owner.release();return error;}
fn publishChunkBodies(cache:Cache&,owner:Chunk&)->Error {for &body in owner.bodies {let error=cache.retain(body);if error!=blot_error::Error.none {return error;}}return blot_error::Error.none;}
