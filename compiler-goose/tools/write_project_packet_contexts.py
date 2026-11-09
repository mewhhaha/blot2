from pathlib import Path
import json,re,sys
from normalize_syntax import normalize,finish_syntax
R=Path(__file__).resolve().parents[1]/'src'
M=json.loads((R.parent/'build/project-packet-model.json').read_text());D=M['definitions']
def q(t,n):return re.sub(r'(?<![\w:])\b\w+\b(?!::)',lambda m:n+'::'+m[0] if n+'::'+m[0] in D else m[0],t)
imports=set(M['imports'])|{'support.project_packet','check.type_store_packet','reuse.body_check_packet','check.check_packet_owner'}
C=['// Concrete owner/context reconstruction for copied checker/lowering jobs.','namespace blot_project_packet;']+['import '+x+';' for x in sorted(imports)]
# Checked is immutable except its separately restored mutable solver store. Raw
# read tables retain the concrete packet owner; diagnostics have native clones.
fields=D['blot_check_check::Checked'][2]
C+=['fn put(self:Writer&,value:blot_check_check::Checked) {if !self.enter() {return;}'+''.join('put(self,value.'+f+');' for f,t in fields if f!='owner')+'self.depth--;}']
C+=['''fn get(self:Reader&,value:blot_check_check::Checked&) {
 if !self.enter() {return;}value=default<blot_check_check::Checked>();let owner,error=blot_check_check::newCheckedOwner();if error!=Error.none {self.failure=error;self.depth--;return;}value.owner=owner;
'''+''.join('get(self,value.'+f+');' for f,t in fields if f!='owner')+'''
 if self.failure!=Error.none {value.types.deinit();value.parameter_patterns.deinit();value.owner.deinit();value=default<blot_check_check::Checked>();self.depth--;return;}
 let diagnostics=value.diagnostics;value.diagnostics=default<blot_check_check::Diagnostic[:]>();let cloned,error=blot_check_check::cloneDiagnostics(value.owner,diagnostics);if error!=Error.none {value.types.deinit();value.parameter_patterns.deinit();value.owner.deinit();value=default<blot_check_check::Checked>();self.failure=error;self.depth--;return;}value.diagnostics=cloned;
 if value.editor.present&&value.editor.value.context.present {let source=value.editor.value.context.value;value.editor.value.context=blot_support::none<blot_reuse_hole_diagnostics::Snapshot>();let context,error=source.clone();if error!=Error.none {value.deinit();self.failure=error;self.depth--;return;}value.editor.value.context=blot_support::Option<blot_reuse_hole_diagnostics::Snapshot>{true,context};}
 let attached=blot_check_check::attachCheckedPacket(value.owner,self.owner);if attached!=Error.none {value.deinit();self.failure=attached;}self.depth--;
}''']
C+=['''fn put(self:Writer&,value:blot_check_types::Store) {var snapshot,error=blot_check_type_store_snapshot::captureStore(value);if error!=Error.none {self.failure=error;return;}put(self,snapshot);let cleanup=blot_check_type_store_snapshot::deinit(snapshot);if cleanup!=Error.none&&self.failure==Error.none {self.failure=cleanup;}}
fn get(self:Reader&,value:blot_check_types::Store&) {var snapshot=default<blot_check_type_store_snapshot::Snapshot>();get(self,snapshot);if self.failure!=Error.none {return;}let store,error=blot_check_types::initPooled();if error!=Error.none {self.failure=error;return;}value=store;let restored=blot_check_type_store_snapshot::restorePacketStore(snapshot,value);if restored!=Error.none {value.deinit();self.failure=restored;}}
fn put(self:Writer&,value:blot_check_parameter_patterns::Store) {put(self,value.nodes.items);put(self,value.extra.items);}
fn get(self:Reader&,value:blot_check_parameter_patterns::Store&) {var nodes:blot_check_parameter_patterns::Node[:]=[];var words:u32[:]=[];get(self,nodes);get(self,words);if self.failure!=Error.none {return;}let store,error=blot_check_parameter_patterns::initPooled();if error!=Error.none {self.failure=error;return;}value=store;value.nodes.append(nodes);value.extra.append(words);self.failure=value.nodes.failure;if self.failure==Error.none {self.failure=value.extra.failure;}if self.failure!=Error.none {value.deinit();}}
fn put(self:Writer&,value:blot_parse_symbols::Pool) {put(self,value.read_only);put(self,value.missing_name);put(self,value.bytes.items);put(self,value.entries.items);put(self,value.buckets.items);}
fn get(self:Reader&,value:blot_parse_symbols::Pool&) {var read_only=false;var missing=false;var bytes:u8[:]=[];var entries:blot_parse_symbols::Entry[:]=[];var buckets:u32[:]=[];get(self,read_only);get(self,missing);get(self,bytes);get(self,entries);get(self,buckets);if self.failure!=Error.none {return;}for entry in entries {if entry.offset>bytes.len||entry.len>bytes.len-entry.offset {self.failure=Error.invalid_artifact;return;}}for symbol in buckets {if symbol>entries.len {self.failure=Error.invalid_artifact;return;}}let pool,error=blot_parse_symbols::initPooled();if error!=Error.none {self.failure=error;return;}value=pool;value.bytes.append(bytes);value.entries.append(entries);value.buckets.append(buckets);self.failure=value.bytes.failure;if self.failure==Error.none {self.failure=value.entries.failure;}if self.failure==Error.none {self.failure=value.buckets.failure;}if self.failure!=Error.none {value.deinit();return;}value.read_only=read_only;value.missing_name=missing;}
''']
# Tree data is copied into the canonical syntax owner; ordinal lanes are exact.
fs=[]
for f,t in D['blot_parse_ast::Tree'][2]:
 if t.endswith('&'):
  bt=q(t[:-1],'blot_parse_ast');table=D[bt];item=dict(table[2])['items'];fs.append((f,q(item,table[3])))
C+=['fn put(self:Writer&,value:blot_parse_ast::Tree) {put(self,value.lease!=0);if value.lease==0 {return;}put(self,value.has_typed_staging);put(self,value.has_numeric_proofs);'+''.join('put(self,value.'+f+'.items);' for f,t in fs)+'}']
C+=['fn get(self:Reader&,value:blot_parse_ast::Tree&) {var present=false;get(self,present);if self.failure!=Error.none||!present {value=blot_parse_ast::Tree{..};return;}var staging=false;var proofs=false;get(self,staging);get(self,proofs);'+''.join('var '+f+':'+t+'=[];get(self,'+f+');' for f,t in fs)+'''if self.failure!=Error.none {return;}if nodes.len!=spans.len {self.failure=Error.invalid_artifact;return;}for root in roots {if root>=nodes.len {self.failure=Error.invalid_artifact;return;}}let tree,error=blot_parse_ast::initPooled();if error!=Error.none {self.failure=error;return;}value=tree;value.nodes.clear();value.spans.clear();value.has_typed_staging=staging;value.has_numeric_proofs=proofs;'''+''.join('value.'+f+'.append('+f+');' for f,t in fs)+'self.failure=value.failure();if self.failure!=Error.none {value.deinit();}}']
for t,skip in [('blot_reuse_body_check_cache::Body',{'owner'}),('blot_reuse_body_check_cache::Chunk',{'references','graph_owner','live','slot'})]:
 fs=D[t][2]
 C+=['fn put(self:Writer&,value:'+t+') {if !self.enter() {return;}'+''.join(('putOptional' if ty.endswith('?') else 'put')+'(self,value.'+f+');' for f,ty in fs if f not in skip)+'self.depth--;}']
 C+=['fn get(self:Reader&,value:'+t+'&) {if !self.enter() {return;}value='+t+'{..};'+''.join('value.'+f+' .= readOptional(self,default<'+q(ty[:-1],D[t][3])+'>());' if ty.endswith('?') else 'get(self,value.'+f+');' for f,ty in fs if f not in skip)+'self.depth--;}']
C+=['''fn putNameSlots(self:Writer&,value:blot_reuse_body_check_cache::Cache) {
 if !self.enter() {return;}count(self,value.index.slots.len);
 for slot in value.index.slots {var wire=default<dictionary_slot<const u8[:],i64>>();wire.tag=slot.tag;if slot.tag!=0 {wire.key=blot_reuse_body_check_cache::nameAt(value,slot.body);wire.val=slot.body;}put(self,wire);}self.depth--;
}
fn put(self:Writer&,value:blot_reuse_body_check_cache::Cache) {
 put(self,value.minimum_nodes);var owners:u32[>..<]=[];for lease in value.bodies.items {let index=blot_reuse_body_check_cache::chunkIndex(lease.owner);assert(index>=0);var found=false;for prior in owners {if prior==index {found=true;break;}}if !found {owners.push(index as u32);}}
 count(self,owners.len);for index in owners {put(self,blot_reuse_body_check_cache::chunks[index]);}count(self,value.bodies.len);for lease in value.bodies.items {let index=blot_reuse_body_check_cache::chunkIndex(lease.owner);var ordinal:i64=-1;for owner,position in owners {if owner==index {ordinal=position;break;}}assert(ordinal>=0);put(self,ordinal);put(self,lease.index);}putNameSlots(self,value);put(self,value.index.count);
}
fn get(self:Reader&,value:blot_reuse_body_check_cache::Cache&) {
 var minimum:i64=0;get(self,minimum);let chunk_count=count(self);if self.failure!=Error.none {return;}var chunks:(blot_reuse_body_check_cache::Chunk?)[>..<]=[];
 for index in chunk_count {var wire=blot_reuse_body_check_cache::Chunk{..};get(self,wire);if self.failure!=Error.none {for chunk in chunks {if chunk {chunk.release();}}return;}let chunk,error=blot_reuse_body_check_cache::clonePacketChunk(wire);if error!=Error.none {for chunk in chunks {if chunk {chunk.release();}}self.failure=error;return;}chunks.push(chunk);}
 let cache,error=blot_reuse_body_check_cache::initPooled();if error!=Error.none {for chunk in chunks {if chunk {chunk.release();}}self.failure=error;return;}value=cache;value.minimum_nodes=minimum;let length=count(self);
 for index in length {var ordinal:i64=0;var body:i64=0;get(self,ordinal);get(self,body);if self.failure!=Error.none {break;}if ordinal<0||ordinal>=chunks.len {self.failure=Error.invalid_artifact;break;}let chunk=chunks[ordinal];assert(chunk);if body<0||body>=chunk.bodies.len {self.failure=Error.invalid_artifact;break;}let error=value.retain(chunk.bodies[body]);if error!=Error.none {self.failure=error;break;}}
 var slots:dictionary_slot<const u8[:],i64>[:]=[];var occupied:i64=0;if self.failure==Error.none {get(self,slots);get(self,occupied);}if self.failure==Error.none {self.failure=blot_reuse_body_check_cache::restorePacketIndex(value,slots,occupied);}
 for chunk in chunks {if chunk {chunk.release();}}if self.failure!=Error.none {value.deinit();}
}''']
types={'bool','u8','u16','u32','u64','i8','i16','i32','i64','f32','f64'}|{name.split('::')[-1] for name in D}
source=finish_syntax(normalize('\n'.join(C)+'\n',types))
source=re.sub(r'(\b\w+:\s*)((?:const\s+)?[A-Za-z_]\w*(?:::\w+)*(?:<[^{};\n]+>)?(?:\[:\])+)(\s*=\s*)\[\]',lambda m:m[1]+m[2]+m[3]+'default<'+m[2]+'>()',source)
(R/'support/project_packet_contexts.goose').write_text(source)
if '--support-only' in sys.argv:
 raise SystemExit(0)
# Clone body-cache chunks into their native concrete allocation families.
B=['// Full immutable body-cache transport. Packet data never masquerades as a','// native chunk owner; every escaping field is copied into its actual pool.','namespace blot_reuse_body_check_cache;','import .body_check_cache;','import reuse.body_auxiliary;','import support.project_packet;']
B+=['''fn clonePacketBody(source:const Body&,owner:Chunk&)->Body,Error {var value=Body{owner:owner, ..};''']
for f,t in D['blot_reuse_body_check_cache::Body'][2]:
 if f=='owner':continue
 if f in ('loops','auxiliary'):continue
 if f=='bindings':B.append('value.bindings=cloneBindings(source.bindings);')
 elif f=='predicates':B.append('value.predicates=clonePredicates(source.predicates);')
 elif f=='members':B.append('value.members=cloneNames(source.members);')
 elif t.endswith('[:]'):B.append('value.'+f+'=copyOwned(source.'+f+');')
 else:B.append('value.'+f+'=source.'+f+';')
B+=[
'''let loops .= source.loops;if loops {let index=loop_owners.alloc_index(Loops{carries:copyOwned(loops.carries),exits:copyOwned(loops.exits),bindings:copyOwned(loops.bindings),live:true,..});loop_owners[index].slot=(index+1) as u32;value.loops .= loop_owners[index];}
let auxiliary .= source.auxiliary;if auxiliary {var readable=copy(auxiliary);readable.live=true;let copied,error=blot_reuse_body_auxiliary::clone(readable);if error!=Error.none {value.deinit();return Body{..},error;}value.auxiliary .= copied;}return value,Error.none;
}''']
B+=['fn clonePacketChunk(source:const Chunk&)->Chunk?,Error {let owner,error=blot_reuse_dependency_payload::init();if error!=Error.none {return null,error;}let at=chunks.alloc_index(Chunk{graph_owner:owner,live:true,..});let value:Chunk&=chunks[at];value.slot=(at+1) as u32;']
# Frozen graph consists solely of fixed scalars and typed immutable runs.
graph=D['blot_check_frozen_types::Graph']
for f,t in graph[2]:
 if f=='owner_id':B.append('value.graph.owner_id=blot_native::fresh_owner_id();');continue
 if t.endswith('[:]'):
  B.append('let '+f+',error=value.graph_owner.copy(source.graph.'+f+');if error!=Error.none {value.release();return null,error;}value.graph.'+f+'='+f+';')
 else:B.append('value.graph.'+f+'=source.graph.'+f+';')
B+=['value.nominals=cloneIdentityReads(source.nominals);','value.field_names=cloneNames(source.field_names);','value.qualifications=copyOwned(source.qualifications);value.body_bytes=source.body_bytes;value.type_work=source.type_work;','value.bodies=owned_Body.alloc_slice(source.bodies.len);for &body in value.bodies {body=Body{owner:value,..};}','for body,index in source.bodies {let copied,error=clonePacketBody(body,value);if error!=Error.none {value.release();return null,error;}value.bodies[index]=copied;}return value,Error.none;}']
B+=['''fn restorePacketIndex(cache:Cache&,slots:const dictionary_slot<const u8[:],i64>[:],count:i64)->Error {
 if count<0||count>slots.len {return Error.invalid_artifact;}if slots.len!=0&&(slots.len&(slots.len-1))!=0 {return Error.invalid_artifact;}var occupied:i64=0;
 for slot in slots {if slot.tag==0 {continue;}occupied++;if slot.val<0||slot.val>=cache.bodies.len||slot.key!=cache.bodies.items[slot.val].body().name {return Error.invalid_artifact;}}if occupied!=count {return Error.invalid_artifact;}
 if cache.index.slots.len!=0 {name_slots.free_slice(cache.index.slots);}cache.index=NameMap{..};let owned=name_slots.alloc_slice(slots.len);for slot,index in slots {owned[index]=NameSlot{..};if slot.tag!=0 {owned[index]=NameSlot{slot.val,slot.tag};}}cache.index.slots=owned;cache.index.count=count;return Error.none;
}''']
(R/'reuse/body_check_packet.goose').write_text(finish_syntax(normalize('\n'.join(B)+'\n',types)))
