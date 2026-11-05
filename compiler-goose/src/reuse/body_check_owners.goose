// Concrete immutable cache runs and packed C.2 payload accounting.
namespace blot_reuse_body_check_cache;
import .body_check_cache;
reusable[] var owned_u8:u8[>..]=[];
fn copyOwned(values:const u8[:])->u8[:] {if values.len==0 {return [];}let run=owned_u8.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const u8[:]) {if values.len==0 {return;}let first:const u8&=values[0];let at=owned_u8.index_of(first);assert(at>=0);owned_u8.free_slice(owned_u8[at..at+values.len]);}
reusable[] var owned_u32:u32[>..]=[];
fn copyOwned(values:const u32[:])->u32[:] {if values.len==0 {return [];}let run=owned_u32.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const u32[:]) {if values.len==0 {return;}let first:const u32&=values[0];let at=owned_u32.index_of(first);assert(at>=0);owned_u32.free_slice(owned_u32[at..at+values.len]);}
reusable[] var owned_bool:bool[>..]=[];
fn copyOwned(values:const bool[:])->bool[:] {if values.len==0 {return [];}let run=owned_bool.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const bool[:]) {if values.len==0 {return;}let first:const bool&=values[0];let at=owned_bool.index_of(first);assert(at>=0);owned_bool.free_slice(owned_bool[at..at+values.len]);}
reusable[] var owned_Fact:Fact[>..]=[];
fn copyOwned(values:const Fact[:])->Fact[:] {if values.len==0 {return [];}let run=owned_Fact.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Fact[:]) {if values.len==0 {return;}let first:const Fact&=values[0];let at=owned_Fact.index_of(first);assert(at>=0);owned_Fact.free_slice(owned_Fact[at..at+values.len]);}
reusable[] var owned_Binding:Binding[>..]=[];
fn copyOwned(values:const Binding[:])->Binding[:] {if values.len==0 {return [];}let run=owned_Binding.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Binding[:]) {if values.len==0 {return;}let first:const Binding&=values[0];let at=owned_Binding.index_of(first);assert(at>=0);owned_Binding.free_slice(owned_Binding[at..at+values.len]);}
reusable[] var owned_TypeRead:TypeRead[>..]=[];
fn copyOwned(values:const TypeRead[:])->TypeRead[:] {if values.len==0 {return [];}let run=owned_TypeRead.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const TypeRead[:]) {if values.len==0 {return;}let first:const TypeRead&=values[0];let at=owned_TypeRead.index_of(first);assert(at>=0);owned_TypeRead.free_slice(owned_TypeRead[at..at+values.len]);}
reusable[] var owned_Predicate:Predicate[>..]=[];
fn copyOwned(values:const Predicate[:])->Predicate[:] {if values.len==0 {return [];}let run=owned_Predicate.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Predicate[:]) {if values.len==0 {return;}let first:const Predicate&=values[0];let at=owned_Predicate.index_of(first);assert(at>=0);owned_Predicate.free_slice(owned_Predicate[at..at+values.len]);}
reusable[] var owned_Signature:Signature[>..]=[];
fn copyOwned(values:const Signature[:])->Signature[:] {if values.len==0 {return [];}let run=owned_Signature.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Signature[:]) {if values.len==0 {return;}let first:const Signature&=values[0];let at=owned_Signature.index_of(first);assert(at>=0);owned_Signature.free_slice(owned_Signature[at..at+values.len]);}
reusable[] var owned_Projection:Projection[>..]=[];
fn copyOwned(values:const Projection[:])->Projection[:] {if values.len==0 {return [];}let run=owned_Projection.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Projection[:]) {if values.len==0 {return;}let first:const Projection&=values[0];let at=owned_Projection.index_of(first);assert(at>=0);owned_Projection.free_slice(owned_Projection[at..at+values.len]);}
reusable[] var owned_Merge:Merge[>..]=[];
fn copyOwned(values:const Merge[:])->Merge[:] {if values.len==0 {return [];}let run=owned_Merge.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Merge[:]) {if values.len==0 {return;}let first:const Merge&=values[0];let at=owned_Merge.index_of(first);assert(at>=0);owned_Merge.free_slice(owned_Merge[at..at+values.len]);}
reusable[] var owned_Rebinding:Rebinding[>..]=[];
fn copyOwned(values:const Rebinding[:])->Rebinding[:] {if values.len==0 {return [];}let run=owned_Rebinding.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Rebinding[:]) {if values.len==0 {return;}let first:const Rebinding&=values[0];let at=owned_Rebinding.index_of(first);assert(at>=0);owned_Rebinding.free_slice(owned_Rebinding[at..at+values.len]);}
reusable[] var owned_Constructor:Constructor[>..]=[];
fn copyOwned(values:const Constructor[:])->Constructor[:] {if values.len==0 {return [];}let run=owned_Constructor.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Constructor[:]) {if values.len==0 {return;}let first:const Constructor&=values[0];let at=owned_Constructor.index_of(first);assert(at>=0);owned_Constructor.free_slice(owned_Constructor[at..at+values.len]);}
reusable[] var owned_LocalScheme:LocalScheme[>..]=[];
fn copyOwned(values:const LocalScheme[:])->LocalScheme[:] {if values.len==0 {return [];}let run=owned_LocalScheme.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const LocalScheme[:]) {if values.len==0 {return;}let first:const LocalScheme&=values[0];let at=owned_LocalScheme.index_of(first);assert(at>=0);owned_LocalScheme.free_slice(owned_LocalScheme[at..at+values.len]);}
reusable[] var owned_FieldProjection:FieldProjection[>..]=[];
fn copyOwned(values:const FieldProjection[:])->FieldProjection[:] {if values.len==0 {return [];}let run=owned_FieldProjection.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const FieldProjection[:]) {if values.len==0 {return;}let first:const FieldProjection&=values[0];let at=owned_FieldProjection.index_of(first);assert(at>=0);owned_FieldProjection.free_slice(owned_FieldProjection[at..at+values.len]);}
reusable[] var owned_Access:Access[>..]=[];
fn copyOwned(values:const Access[:])->Access[:] {if values.len==0 {return [];}let run=owned_Access.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Access[:]) {if values.len==0 {return;}let first:const Access&=values[0];let at=owned_Access.index_of(first);assert(at>=0);owned_Access.free_slice(owned_Access[at..at+values.len]);}
reusable[] var owned_LoopCarry:LoopCarry[>..]=[];
fn copyOwned(values:const LoopCarry[:])->LoopCarry[:] {if values.len==0 {return [];}let run=owned_LoopCarry.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const LoopCarry[:]) {if values.len==0 {return;}let first:const LoopCarry&=values[0];let at=owned_LoopCarry.index_of(first);assert(at>=0);owned_LoopCarry.free_slice(owned_LoopCarry[at..at+values.len]);}
reusable[] var owned_LoopExit:LoopExit[>..]=[];
fn copyOwned(values:const LoopExit[:])->LoopExit[:] {if values.len==0 {return [];}let run=owned_LoopExit.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const LoopExit[:]) {if values.len==0 {return;}let first:const LoopExit&=values[0];let at=owned_LoopExit.index_of(first);assert(at>=0);owned_LoopExit.free_slice(owned_LoopExit[at..at+values.len]);}
reusable[] var owned_IdentityRead:IdentityRead[>..]=[];
fn copyOwned(values:const IdentityRead[:])->IdentityRead[:] {if values.len==0 {return [];}let run=owned_IdentityRead.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const IdentityRead[:]) {if values.len==0 {return;}let first:const IdentityRead&=values[0];let at=owned_IdentityRead.index_of(first);assert(at>=0);owned_IdentityRead.free_slice(owned_IdentityRead[at..at+values.len]);}
reusable[] var owned_Qualification:Qualification[>..]=[];
fn copyOwned(values:const Qualification[:])->Qualification[:] {if values.len==0 {return [];}let run=owned_Qualification.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Qualification[:]) {if values.len==0 {return;}let first:const Qualification&=values[0];let at=owned_Qualification.index_of(first);assert(at>=0);owned_Qualification.free_slice(owned_Qualification[at..at+values.len]);}
reusable[] var owned_Body:Body[>..]=[];
fn copyOwned(values:const Body[:])->Body[:] {if values.len==0 {return [];}let run=owned_Body.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Body[:]) {if values.len==0 {return;}let first:const Body&=values[0];let at=owned_Body.index_of(first);assert(at>=0);owned_Body.free_slice(owned_Body[at..at+values.len]);}
reusable[] var owned_u8___:u8[:][>..]=[];
fn copyOwned(values:const u8[:][:])->u8[:][:] {if values.len==0 {return [];}let run=owned_u8___.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const u8[:][:]) {if values.len==0 {return;}let first:const u8[:]&=values[0];let at=owned_u8___.index_of(first);assert(at>=0);owned_u8___.free_slice(owned_u8___[at..at+values.len]);}
let body_footprint:i64=394;
let chunk_footprint:i64=217;
let qualification_footprint:i64=13;
let identity_read_footprint:i64=85;
let type_node_footprint:i64=16;
let effect_row_footprint:i64=17;
let operation_footprint:i64=24;
let obligation_footprint:i64=48;
fn bytes(self:const Body&)->i64 {var total=body_footprint+self.name.len+self.source.len;
total+=self.facts.len*16;
total+=self.bindings.len*92;
total+=self.closed_rows.len*4;
total+=self.nominals.len*4;
total+=self.type_reads.len*37;
total+=self.predicates.len*70;
total+=self.fields.len*20;
total+=self.field_tags.len*4;
total+=self.local_schemes.len*48;
total+=self.constructors.len*16;
total+=self.merges.len*16;
total+=self.projections.len*12;
total+=self.signatures.len*8;
total+=self.accesses.len*28;
total+=self.rebindings.len*12;
total+=self.members.len*16;
for binding in self.bindings {total+=binding.name.len;}for predicate in self.predicates {total+=predicate.name.len;}for member in self.members {total+=member.len;}let loops .= self.loops;if loops {total+=49+loops.carries.len*20+loops.exits.len*16+loops.bindings.len*4;}let auxiliary .= self.auxiliary;if auxiliary {total+=auxiliary.bytes();}return total;}
fn deinit(self:Loops&) {assert(self.live);releaseOwned(self.carries);releaseOwned(self.exits);releaseOwned(self.bindings);let at=loop_owners.index_of(self);assert(at>=0);self=Loops{..};loop_owners.free(at);}
fn deinit(self:Body&) {
releaseOwned(self.name);
releaseOwned(self.source);
releaseOwned(self.facts);
releaseOwned(self.closed_rows);
releaseOwned(self.nominals);
releaseOwned(self.type_reads);
for binding in self.bindings {releaseOwned(binding.name);}releaseOwned(self.bindings);for predicate in self.predicates {releaseOwned(predicate.name);}releaseOwned(self.predicates);
releaseOwned(self.signatures);
releaseOwned(self.projections);
releaseOwned(self.merges);
releaseOwned(self.rebindings);
releaseOwned(self.constructors);
releaseOwned(self.local_schemes);
releaseOwned(self.fields);
releaseOwned(self.accesses);
releaseOwned(self.field_tags);
let loops .= self.loops;if loops {loops.deinit();}let auxiliary .= self.auxiliary;if auxiliary {auxiliary.deinit();}for member in self.members {releaseOwned(member);}releaseOwned(self.members);self=Body{..};}
fn release(self:Chunk&) {assert(self.live && self.references>0);self.references-=1;if self.references!=0 {return;}for &body in self.bodies {body.deinit();}releaseOwned(self.bodies);self.graph_owner.deinit();for nominal in self.nominals {releaseOwned(nominal.name);}releaseOwned(self.nominals);for name in self.field_names {releaseOwned(name);}releaseOwned(self.field_names);releaseOwned(self.qualifications);let at=chunks.index_of(self);assert(at>=0);self=Chunk{..};chunks.free(at);}
fn publishChunk(cache:Cache&,owner:Chunk&)->Error {let error=publishChunkBodies(cache,owner);owner.release();return error;}
fn publishChunkBodies(cache:Cache&,owner:Chunk&)->Error {for &body in owner.bodies {let error=cache.retain(body);if error!=Error.none {return error;}}return Error.none;}
