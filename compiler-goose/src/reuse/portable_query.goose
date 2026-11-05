// Every portable section grants one complete claim; no owner-local handles wire.
namespace blot_reuse_portable_query;
import reuse.semantic_query_table;
import eval.type_evidence;
import check.types;
import check.package_evidence;
import support.error;
type Error=blot_error::Error;
type View=blot_eval_type_evidence::View;
type Tag=blot_eval_type_evidence::Tag;
let version:u32=1;
enum Claim {principal_complete_proof,optimizer_output,selected_complete_proof}
fn claimCode(value:Claim)->u32 {match value {Claim.principal_complete_proof=>1,Claim.optimizer_output=>2,Claim.selected_complete_proof=>3}}
fn claimFromCode(value:u32)->Claim,Error {match value {1=>{return Claim.principal_complete_proof,Error.none;},2=>{return Claim.optimizer_output,Error.none;},3=>{return Claim.selected_complete_proof,Error.none;},_=>{return Claim.principal_complete_proof,Error.invalid_artifact;}}}
struct Header {version:u32,kind:blot_reuse_semantic_query_table::Kind,schema:u32,claim:Claim}
fn header(claim:Claim)->Header {var kind=blot_reuse_semantic_query_table::Kind.principal;match claim {Claim.principal_complete_proof=>{},Claim.optimizer_output=>{kind=blot_reuse_semantic_query_table::Kind.executable;},Claim.selected_complete_proof=>{kind=blot_reuse_semantic_query_table::Kind.specialization;}}return Header{version,kind,1,claim, ..};}
struct Section<R> {header:Header,records:const R[:]}
fn admitted<R>(self:Section<R>,claim:Claim)->bool {return self.header==header(claim);}
fn validSpan(length:i64,start:i64,count:i64)->bool {return start<=length && count<=length-start;}
fn child(value:u32,parent:i64)->bool {return value!=0 && value<parent;}
fn validEvidence(evidence:View)->bool {
 if evidence.validateGoalTables()!=Error.none {return false;}var has_quantifiers=false;let primitives:Tag[6]=[Tag.absent,Tag.unit,Tag.boolean,Tag.unsigned32,Tag.floating32,Tag.never];
 if evidence.nodes.len<primitives.len {return false;}for node,index in evidence.nodes[..primitives.len] {if node!=blot_eval_type_evidence::Node{tag:primitives[index], ..} {return false;}}
 let effects=evidence.effects;if effects.operations.len==0 || effects.rows.len==0 || effects.rows[0].len!=0 || effects.rows[0].formal!=0 {return false;}
 for operation in effects.operations[1..] {if !validSpan(effects.arguments.len,operation.arguments.start,operation.arguments.len) {return false;}for argument in effects.arguments[operation.arguments.start..operation.arguments.start+operation.arguments.len] {if argument==0 || argument>=evidence.nodes.len {return false;}}}
 for row in effects.rows[1..] {if row.formal!=0 {if row.formal>=evidence.nodes.len {return false;}let formal=evidence.node(row.formal);if formal.tag!=Tag.bound || formal.b!=1 {return false;}}if !validSpan(effects.labels.len,row.start,row.len) {return false;}for label in effects.labels[row.start..row.start+row.len] {if label==0 || label>=effects.operations.len {return false;}}}
 let rows=effects.rows.len;
 for index in primitives.len..evidence.nodes.len {let node=evidence.nodes[index];match node.tag {
  Tag.forall,Tag.existential=>{if !child(node.a,index) || node.b==0 || node.b>128 || !validSpan(evidence.extra.len,node.c,node.b) {return false;}for binder,ordinal in evidence.children(index as u32) {if !child(binder,index) {return false;}let leaf=evidence.node(binder);if leaf.tag!=Tag.bound || leaf.a!=ordinal || leaf.b>2 || leaf.c!=0 {return false;}if node.tag==Tag.existential && leaf.b!=0 {return false;}}has_quantifiers=true;},
  Tag.bound=>{if node.a>=128 || node.b>2 || node.c>=128 {return false;}},Tag.scoped=>{return false;},
  Tag.absent,Tag.unit,Tag.boolean,Tag.unsigned32,Tag.floating32,Tag.never,Tag.erased_proof=>{return false;},
  Tag.usage=>{if !child(node.a,index) || node.b>6 {return false;}let loan=node.b==2 || node.b==3;if loan!=(node.c!=0) || (loan && !child(node.c,index)) {return false;}},
  Tag.array,Tag.list,Tag.cursor,Tag.resolver=>{if !child(node.a,index) || node.b!=0 || node.c!=0 {return false;}},
  Tag.provider=>{if !child(node.a,index) || node.b!=0 || node.c>=rows {return false;}},Tag.function=>{if !child(node.a,index) || !child(node.b,index) || node.c>=rows {return false;}},Tag.state_provider=>{if !child(node.a,index) || !child(node.b,index) || !child(node.c,index) {return false;}},
  Tag.type_constructor=>{if node.a==0 || node.b==0 || node.c!=0 {return false;}},
  Tag.product,Tag.record=>{var width:i64=1;if node.tag==Tag.record {width=2;}if node.b as u64>0x7fffffffffffffff/(width as u64) {return false;}let count=node.b as i64*width;if node.c!=0 || !validSpan(evidence.extra.len,node.a,count) {return false;}for value,ordinal in evidence.extra[node.a..node.a+count] {if node.tag==Tag.record && ordinal%2==0 {if value==0 {return false;}}else if !child(value,index) {return false;}}},
  Tag.projection=>{let start=node.c as i64+1;if node.a==0 || node.b==0 || node.c>=evidence.extra.len || !validSpan(evidence.extra.len,start,evidence.extra[node.c]) || evidence.extra.len-start-evidence.extra[node.c]<3 {return false;}for value in evidence.children(index as u32) {if !child(value,index) {return false;}}let descriptor=evidence.projection(index as u32);if descriptor.member==0 || descriptor.scope>=128 || descriptor.goal>=4096 {return false;}},
  Tag.nominal=>{let start=node.c as i64+1;if node.a==0 || node.c>=evidence.extra.len || !validSpan(evidence.extra.len,start,evidence.extra[node.c]) {return false;}for value in evidence.extra[start..start+evidence.extra[node.c]] {if !child(value,index) {return false;}}},
 }}
 if has_quantifiers {return blot_check_package_evidence::validate(evidence)==Error.none;}for node in evidence.nodes {if node.tag==Tag.bound || node.tag==Tag.projection {return false;}}return true;
}
fn closedEvidence(evidence:View,root:u32)->bool {var remaining:i64=65536;return evidence.closed(root,0,remaining)==Error.none;}
