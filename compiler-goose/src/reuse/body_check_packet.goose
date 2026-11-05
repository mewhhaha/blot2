// Full immutable body-cache transport. Packet data never masquerades as a
// native chunk owner; every escaping field is copied into its actual pool.
namespace blot_reuse_body_check_cache;
import .body_check_cache;
import reuse.body_auxiliary;
import support.project_packet;
fn clonePacketBody(source:const Body&,owner:Chunk&)->Body,Error {var value=Body{owner:owner, ..};
value.name=copyOwned(source.name);
value.source=copyOwned(source.source);
value.syntax=source.syntax;
value.facts=copyOwned(source.facts);
value.bindings=cloneBindings(source.bindings);
value.closed_rows=copyOwned(source.closed_rows);
value.body_closed_rows=source.body_closed_rows;
value.type_work=source.type_work;
value.nominals=copyOwned(source.nominals);
value.type_reads=copyOwned(source.type_reads);
value.predicates=clonePredicates(source.predicates);
value.signatures=copyOwned(source.signatures);
value.projections=copyOwned(source.projections);
value.merges=copyOwned(source.merges);
value.rebindings=copyOwned(source.rebindings);
value.constructors=copyOwned(source.constructors);
value.local_schemes=copyOwned(source.local_schemes);
value.fields=copyOwned(source.fields);
value.accesses=copyOwned(source.accesses);
value.field_tags=copyOwned(source.field_tags);
value.members=cloneNames(source.members);
value.selection_digest=source.selection_digest;
value.implementation_selection=source.implementation_selection;
let loops .= source.loops;if loops {let index=loop_owners.alloc_index(Loops{carries:copyOwned(loops.carries),exits:copyOwned(loops.exits),bindings:copyOwned(loops.bindings),live:true,..});loop_owners[index].slot=(index+1) as u32;value.loops .= loop_owners[index];}
let auxiliary .= source.auxiliary;if auxiliary {var readable=copy(auxiliary);readable.live=true;let copied,error=blot_reuse_body_auxiliary::clone(readable);if error!=blot_error::Error.none {value.deinit();return Body{..},error;}value.auxiliary .= copied;}return value,blot_error::Error.none;
}
fn clonePacketChunk(source:const Chunk&)->Chunk?,Error {let owner,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {return null,error;}let at=chunks.alloc_index(Chunk{graph_owner:owner,live:true,..});let value:Chunk& =chunks[at];value.slot=(at+1) as u32;
let nodes,error=value.graph_owner.copy(source.graph.nodes);if error!=blot_error::Error.none {value.release();return null,error;}value.graph.nodes=nodes;
let extra,error=value.graph_owner.copy(source.graph.extra);if error!=blot_error::Error.none {value.release();return null,error;}value.graph.extra=extra;
let rows,error=value.graph_owner.copy(source.graph.rows);if error!=blot_error::Error.none {value.release();return null,error;}value.graph.rows=rows;
let labels,error=value.graph_owner.copy(source.graph.labels);if error!=blot_error::Error.none {value.release();return null,error;}value.graph.labels=labels;
let operations,error=value.graph_owner.copy(source.graph.operations);if error!=blot_error::Error.none {value.release();return null,error;}value.graph.operations=operations;
value.graph.row_variable_count=source.graph.row_variable_count;
let quantifier_goals,error=value.graph_owner.copy(source.graph.quantifier_goals);if error!=blot_error::Error.none {value.release();return null,error;}value.graph.quantifier_goals=quantifier_goals;
let quantifier_obligations,error=value.graph_owner.copy(source.graph.quantifier_obligations);if error!=blot_error::Error.none {value.release();return null,error;}value.graph.quantifier_obligations=quantifier_obligations;
value.nominals=cloneIdentityReads(source.nominals);
value.field_names=cloneNames(source.field_names);
value.qualifications=copyOwned(source.qualifications);value.body_bytes=source.body_bytes;value.type_work=source.type_work;
value.bodies=owned_Body.alloc_slice(source.bodies.len);for &body in value.bodies {body=Body{owner:value,..};}
for body,index in source.bodies {let copied,error=clonePacketBody(body,value);if error!=blot_error::Error.none {value.release();return null,error;}value.bodies[index]=copied;}return value,blot_error::Error.none;}
fn restorePacketIndex(cache:Cache&,slots:const dictionary_slot<const u8[:],i64>[:],count:i64)->Error {
 if count<0||count>slots.len {return blot_error::Error.invalid_artifact;}if slots.len!=0&&(slots.len&(slots.len-1))!=0 {return blot_error::Error.invalid_artifact;}var occupied:i64=0;
 for slot in slots {if slot.tag==0 {continue;}occupied++;if slot.val<0||slot.val>=cache.bodies.len||slot.key!=cache.bodies.items[slot.val].body().name {return blot_error::Error.invalid_artifact;}}if occupied!=count {return blot_error::Error.invalid_artifact;}
 blot_support_pooled_map::deinit(cache.index,name_slots);let owned=name_slots.alloc_slice(slots.len);for slot,index in slots {owned[index]=slot;if slot.tag!=0 {owned[index].key=cache.bodies.items[slot.val].body().name;}}cache.index.slots=owned;cache.index.count=count;return blot_error::Error.none;
}
