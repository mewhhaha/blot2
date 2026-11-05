// Copied worker evidence images. Decoded runs carry no parent addresses or IDs.
namespace blot_evidence_packet;
import eval.type_evidence;
import check.effect_evidence;
import check.types;
import support.blake3;
import support.bytes;
import support.error;
import support.native;
type Error=blot_error::Error;
type Snapshot=blot_eval_type_evidence::Snapshot;
type View=blot_eval_type_evidence::View;
let magic: const u8[:]="BLOTEVID";
let version: u32=1;
let header: i64=84;
let byte_limit: i64=67108864;
let element_limit: i64=4194304;
fn digest(bytes: const u8[:]) -> u8[32] { return blot_support_blake3::hash(bytes); }
fn schema() -> u8[32] { return digest("BLOT evidence worker v1: nodes[tag8,a32,b32,c32];extra32;operations[identity32x2,arguments32x2,instance32x2];arguments32;rows[start32,len32,formal32];labels32;quantifiers[owner32,start32,len32];goals[ty32,kind32,name32,result32,other32,signature32,operator32,identity32x2,explicit8]"); }
fn emptySnapshot() -> Snapshot { return Snapshot {owner_id:0,nodes:[],extra:[],effects:blot_check_effect_evidence::Snapshot {operations:[],arguments:[],rows:[],labels:[],owner_id:0},quantifier_goals:[],quantifier_obligations:[]}; }
struct OwnedSnapshot { snapshot: Snapshot,lease: u32=0,generation: u64=0 }
struct Lease { generation: u64,snapshot: Snapshot }
reusable var leases: Lease[>..]=[];
reusable[] var node_pool: blot_eval_type_evidence::Node[>..]=[];
reusable[] var word_pool: u32[>..]=[];
reusable[] var operation_pool: blot_check_effect_evidence::Operation[>..]=[];
reusable[] var row_pool: blot_check_effect_evidence::Row[>..]=[];
reusable[] var quantifier_pool: blot_eval_type_evidence::QuantifierGoals[>..]=[];
reusable[] var goal_pool: blot_eval_type_evidence::Goal[>..]=[];
var next_generation: u64=1;
fn valid(self: const OwnedSnapshot&) -> bool { return self.lease!=0&&self.lease<=leases.len&&leases[self.lease-1].generation==self.generation&&self.generation!=0; }
fn release(snapshot: Snapshot) { node_pool.free_slice(snapshot.nodes); word_pool.free_slice(snapshot.extra); operation_pool.free_slice(snapshot.effects.operations); word_pool.free_slice(snapshot.effects.arguments); row_pool.free_slice(snapshot.effects.rows); word_pool.free_slice(snapshot.effects.labels); quantifier_pool.free_slice(snapshot.quantifier_goals); goal_pool.free_slice(snapshot.quantifier_obligations); }
fn deinit(self: OwnedSnapshot&) { if self.lease==0 { return; } assert(valid(self)); let index=self.lease-1; release(leases[index].snapshot); leases[index].generation=0; leases.free(index); self.snapshot=emptySnapshot(); self.lease=0; self.generation=0; }
struct Writer { output: u8[>..<]&,start: i64,failure: Error=Error.none,total: i64=0 }
fn room(self: Writer&,count: i64) -> bool { if self.failure!=Error.none { return false; } let used=self.output.len-self.start; if count<0||used>byte_limit||count>byte_limit-used { self.failure=Error.artifact_limit; return false; } return true; }
fn u8value(self: Writer&,value: u8) { if room(self,1) { self.output.push(value); } }
fn u32value(self: Writer&,value: u32) { if room(self,4) { for shift in 0..4 { self.output.push((value>>((shift*8) as u32)) as! u8); } } }
fn count(self: Writer&,length: i64) -> bool { if self.failure!=Error.none { return false; } if length<0||length>element_limit||self.total>element_limit-length { self.failure=Error.artifact_limit; return false; } self.total+=length; u32value(self,length as u32); return self.failure==Error.none; }
fn words(self: Writer&,values: const u32[:]) { if !count(self,values.len) { return; } for value in values { u32value(self,value); } }
fn encode(view: View,output: u8[>..<]&) -> Error { let begin=output.len; output.append(magic); for index in 0..header-magic.len { output.push(0); } var writer=Writer {output,output.len};
 if count(writer,view.nodes.len) { for node in view.nodes { u8value(writer,blot_eval_type_evidence::tagCode(node.tag)); u32value(writer,node.a); u32value(writer,node.b); u32value(writer,node.c); } } words(writer,view.extra);
 if count(writer,view.effects.operations.len) { for operation in view.effects.operations { u32value(writer,operation.identity.unit); u32value(writer,operation.identity.decl); u32value(writer,operation.arguments.start); u32value(writer,operation.arguments.len); u32value(writer,operation.instance.unit); u32value(writer,operation.instance.decl); } } words(writer,view.effects.arguments);
 if count(writer,view.effects.rows.len) { for row in view.effects.rows { u32value(writer,row.start); u32value(writer,row.len); u32value(writer,row.formal); } } words(writer,view.effects.labels);
 if count(writer,view.quantifier_goals.len) { for goals in view.quantifier_goals { u32value(writer,goals.owner); u32value(writer,goals.goals.start); u32value(writer,goals.goals.len); } }
 if count(writer,view.quantifier_obligations.len) { for goal in view.quantifier_obligations { u32value(writer,goal.ty); u32value(writer,blot_check_types::obligationKindCode(goal.kind)); u32value(writer,goal.name); u32value(writer,goal.result); u32value(writer,goal.other); u32value(writer,goal.signature); u32value(writer,blot_check_types::operatorCode(goal.operator)); u32value(writer,goal.identity.unit); u32value(writer,goal.identity.decl); var flag: u8=0; if goal.explicit { flag=1; } u8value(writer,flag); } }
 if writer.failure!=Error.none { output.resize(begin); return writer.failure; } let payload=output[begin+header..]; let fingerprint=digest(payload); let schema_hash=schema(); blot_bytes::put_u32(output,begin+8,version); for byte,index in schema_hash { output[begin+12+index]=byte; } blot_bytes::put_u64(output,begin+44,payload.len as u64); for byte,index in fingerprint { output[begin+52+index]=byte; } return Error.none;
}
struct Reader { bytes: const u8[:],at: i64=0,failure: Error=Error.none,total: i64=0,snapshot: Snapshot }
fn available(self: Reader&,count: i64) -> bool { if self.failure!=Error.none { return false; } if count<0||self.at<0||self.at>self.bytes.len||count>self.bytes.len-self.at { self.failure=Error.invalid_artifact; return false; } return true; }
fn byte(self: Reader&) -> u8 { if !available(self,1) { return 0; } let value=self.bytes[self.at]; self.at++; return value; }
fn word(self: Reader&) -> u32 { if !available(self,4) { return 0; } let value=blot_bytes::get_u32(self.bytes,self.at); self.at+=4; return value; }
fn length(self: Reader&,width: i64) -> i64 { let count=word(self) as i64; if self.failure!=Error.none { return 0; } if count>element_limit||self.total>element_limit-count||width<=0||count>(self.bytes.len-self.at)/width { self.failure=Error.artifact_limit; return 0; } self.total+=count; return count; }
fn readWords(self: Reader&) -> u32[:] { let count=length(self,4); if self.failure!=Error.none { return []; } let values=word_pool.alloc_slice(count); for &value in values { value=word(self); } return values; }
fn read(self: Reader&) -> Error {
 let node_count=length(self,13); if self.failure!=Error.none { return self.failure; } let nodes=node_pool.alloc_slice(node_count); self.snapshot.nodes=nodes; for &node in nodes { let code=byte(self); let tag,known=blot_eval_type_evidence::tagFromCode(code); if !known { self.failure=Error.invalid_artifact; return self.failure; } let a=word(self); let b=word(self); let c=word(self); node=blot_eval_type_evidence::Node {tag,a,b,c}; }
 self.snapshot.extra=readWords(self); if self.failure!=Error.none { return self.failure; }
 let operation_count=length(self,24); if self.failure!=Error.none { return self.failure; } let operations=operation_pool.alloc_slice(operation_count); self.snapshot.effects.operations=operations; for &operation in operations { let unit=word(self); let declaration=word(self); let start=word(self); let count=word(self); let owner=word(self); let instance=word(self); operation=blot_check_effect_evidence::Operation {blot_check_types::NominalIdentity {unit,declaration},blot_check_effect_evidence::List {start,count},blot_check_types::NominalIdentity {owner,instance}}; }
 self.snapshot.effects.arguments=readWords(self); if self.failure!=Error.none { return self.failure; }
 let row_count=length(self,12); if self.failure!=Error.none { return self.failure; } let rows=row_pool.alloc_slice(row_count); self.snapshot.effects.rows=rows; for &row in rows { let start=word(self); let count=word(self); let formal=word(self); row=blot_check_effect_evidence::Row {start,count,formal}; }
 self.snapshot.effects.labels=readWords(self); if self.failure!=Error.none { return self.failure; }
 let quantifier_count=length(self,12); if self.failure!=Error.none { return self.failure; } let quantifiers=quantifier_pool.alloc_slice(quantifier_count); self.snapshot.quantifier_goals=quantifiers; for &quantifier in quantifiers { let owner=word(self); let start=word(self); let count=word(self); quantifier=blot_eval_type_evidence::QuantifierGoals {owner,blot_check_types::List {start,count}}; }
 let goal_count=length(self,37); if self.failure!=Error.none { return self.failure; } let goals=goal_pool.alloc_slice(goal_count); self.snapshot.quantifier_obligations=goals; for &goal in goals { let ty=word(self); let kind_code=word(self); let kind,error=blot_check_types::obligationKindFromCode(kind_code); if error!=Error.none { return Error.invalid_artifact; } let name=word(self); let result=word(self); let other=word(self); let signature=word(self); let operator_code=word(self); let operator,e=blot_check_types::operatorFromCode(operator_code); if e!=Error.none { return Error.invalid_artifact; } let unit=word(self); let declaration=word(self); let explicit=byte(self); if explicit>1 { return Error.invalid_artifact; } goal=blot_eval_type_evidence::Goal {ty:ty,kind:kind,name:name,result:result,other:other,signature:signature,operator:operator,identity:blot_check_types::NominalIdentity {unit,declaration},explicit:explicit==1}; } return self.failure;
}
fn shape(snapshot: const Snapshot&) -> bool { let nodes=snapshot.nodes; if nodes.len<6||snapshot.effects.rows.len==0||snapshot.effects.operations.len==0 { return false; } let expected: blot_eval_type_evidence::Tag[6]=[blot_eval_type_evidence::Tag.absent,blot_eval_type_evidence::Tag.unit,blot_eval_type_evidence::Tag.boolean,blot_eval_type_evidence::Tag.unsigned32,blot_eval_type_evidence::Tag.floating32,blot_eval_type_evidence::Tag.never]; for tag,index in expected { if nodes[index].tag!=tag||nodes[index].a!=0||nodes[index].b!=0||nodes[index].c!=0 { return false; } } for operation in snapshot.effects.operations { if operation.arguments.start>snapshot.effects.arguments.len||operation.arguments.len>snapshot.effects.arguments.len-operation.arguments.start { return false; } } for row in snapshot.effects.rows { if row.start>snapshot.effects.labels.len||row.len>snapshot.effects.labels.len-row.start||row.formal>=nodes.len { return false; } } for label in snapshot.effects.labels { if label==0||label>=snapshot.effects.operations.len { return false; } } for argument in snapshot.effects.arguments { if argument>=nodes.len { return false; } } let zero=snapshot.effects.rows[0]; return zero.start==0&&zero.len==0&&zero.formal==0; }
fn decode(bytes: const u8[:]) -> OwnedSnapshot,Error { let empty=OwnedSnapshot {snapshot:emptySnapshot()}; if bytes.len<header||bytes[..8]!=magic { return empty,Error.invalid_artifact; } if blot_bytes::get_u32(bytes,8)!=version { return empty,Error.unsupported_version; } let schema_hash=schema(); if bytes[12..44]!=schema_hash { return empty,Error.schema_mismatch; } let count=blot_bytes::get_u64(bytes,44); if count>byte_limit as u64 { return empty,Error.artifact_limit; } if count!=(bytes.len-header) as u64 { return empty,Error.invalid_artifact; } let checksum=digest(bytes[header..]); if bytes[52..84]!=checksum { return empty,Error.invalid_artifact; } var reader=Reader {bytes:bytes[header..],snapshot:emptySnapshot()}; let error=read(reader); if error!=Error.none||reader.at!=reader.bytes.len||!shape(reader.snapshot) { release(reader.snapshot); if error!=Error.none { return empty,error; } return empty,Error.invalid_artifact; } if next_generation==0xffffffffffffffff||leases.len>=0xffffffff { release(reader.snapshot); return empty,Error.out_of_memory; } reader.snapshot.owner_id=blot_native::fresh_owner_id(); reader.snapshot.effects.owner_id=blot_native::fresh_owner_id(); let generation=next_generation; next_generation++; let slot=leases.alloc_index(Lease {generation,reader.snapshot}); return OwnedSnapshot {reader.snapshot,(slot+1) as u32,generation},Error.none; }
