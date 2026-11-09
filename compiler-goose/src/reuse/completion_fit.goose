// Request-local fitting uses private substitutions; no proof or solver ID escapes.
namespace blot_reuse_completion_fit;
import check.types;
import check.effects;
import check.frozen_types;
import reuse.principal_type_graph;
import support.error;
type Error=blot_error::Error;
type Store=blot_check_types::Store;
type Scheme=blot_check_types::Scheme;
type Obligation=blot_check_types::Obligation;
type Copy=blot_reuse_principal_type_graph::NormalizedCopy;
enum Match {exact,compatible,unknown,incompatible}
struct Budget {remaining:i64=1000000,exhausted:bool=false}
fn spend(self_:Budget&,amount:i64)->bool {if amount>self_.remaining {self_.exhausted=true;self_.remaining=0;return false;}self_.remaining-=amount;return true;}
fn contains(items:const u32[:],value:u32)->bool {for item in items {if item==value {return true;}}return false;}
struct Measure {source:Store,quantified:blot_check_types::List,closed_rows:blot_check_types::List,budget:Budget&,visits:i64=0,known:bool=true}
recursive fn ty(self_:Measure&,original:u32,depth:i64)->Error {
 if depth>=32 || self_.visits==1024 || !self_.budget.spend(1+self_.source.versions.len+self_.source.effects.versions.len) {return blot_error::Error.type_limit;}self_.visits++;
 let root=self_.source.head(original,0);let node=self_.source.node(root);
 match node.tag {
  absent=>{self_.known=false;},variable=>{if !contains(self_.source.list(self_.quantified),root) {self_.known=false;}},
  function=>{let error=self_.ty(node.a,depth+1);if error!=blot_error::Error.none {return error;}let error=self_.ty(node.b,depth+1);if error!=blot_error::Error.none {return error;}return self_.row(node.c,depth+1);},
  array,list,cursor,resolver=>{return self_.ty(node.a,depth+1);},
  provider=>{let error=self_.ty(node.a,depth+1);if error!=blot_error::Error.none {return error;}return self_.row(node.c,depth+1);},
  state_provider=>{for part in [node.a,node.b,node.c] {let error=self_.ty(part,depth+1);if error!=blot_error::Error.none {return error;}}},
  product=>{let span=blot_check_types::List{node.a,node.b};for index in span.len {let child=self_.source.list(span)[index];let error=self_.ty(child,depth+1);if error!=blot_error::Error.none {return error;}}},
  nominal=>{let span=blot_check_types::List{node.c+1,self_.source.nominalArguments(node).len as u32};for index in span.len {let child=self_.source.list(span)[index];let error=self_.ty(child,depth+1);if error!=blot_error::Error.none {return error;}}},
  record=>{for index in node.b {let error=self_.ty(self_.source.recordField(node,index).ty,depth+1);if error!=blot_error::Error.none {return error;}}},_=>{},
 }return blot_error::Error.none;
}
recursive fn row(self_:Measure&,id:u32,depth:i64)->Error {
 let row=self_.source.row(id);match row.tail {closed=>{},variable payload=>{if !contains(self_.source.list(self_.closed_rows),payload.value) {self_.known=false;}},_=>{self_.known=false;}}
 let source_visit_1_count=(self_.source.rowLabels(id)).len;for source_visit_1_index in 0..source_visit_1_count {let label=(self_.source.rowLabels(id))[source_visit_1_index];if self_.visits==1024 {return blot_error::Error.type_limit;}self_.visits++;if !self_.budget.spend(1) {return blot_error::Error.type_limit;}let source_visit_2_count=(self_.source.operationArguments(label)).len;for source_visit_2_index in 0..source_visit_2_count {let part=(self_.source.operationArguments(label))[source_visit_2_index];let error=self_.ty(part,depth+1);if error!=blot_error::Error.none {return error;}}}return blot_error::Error.none;
}
fn seedClosed(copy:Copy&,scheme:Scheme) {let source_visit_3_count=(copy.source.list(scheme.closed_rows)).len;for source_visit_3_index in 0..source_visit_3_count {let variable=(copy.source.list(scheme.closed_rows))[source_visit_3_index];copy.row_variables.insert(variable,0);}}
fn requirementHead(left:Obligation,right:Obligation)->bool {return left.kind==right.kind && left.name==right.name && left.operator==right.operator && left.identity==right.identity;}
fn covered(candidate:Copy&,context:Copy&,wanted:Obligation,declared:Obligation)->bool,Error {
 if !requirementHead(wanted,declared) {return false,blot_error::Error.none;}
 for pair in [[wanted.ty,declared.ty],[wanted.other,declared.other],[wanted.result,declared.result]] {
  if pair[0]==0 && pair[1]==0 {continue;}if pair[0]==0 || pair[1]==0 {return false,blot_error::Error.none;}let left,error=candidate.ty(pair[0],0);if error!=blot_error::Error.none {return false,error;}let right,error=context.ty(pair[1],0);if error!=blot_error::Error.none {return false,error;}
  let a,error=candidate.destination.resolve(left,0);if error!=blot_error::Error.none {return false,error;}let b,error=candidate.destination.resolve(right,0);if error!=blot_error::Error.none {return false,error;}let equal,error=candidate.destination.equalClosed(a,b);if error!=blot_error::Error.none || !equal {return false,error;}
 }
 if wanted.kind!=blot_check_types::ObligationKind.dispatch && (wanted.signature!=0 || declared.signature!=0) {
  if wanted.signature==0 || declared.signature==0 {return false,blot_error::Error.none;}let a,error=candidate.ty(wanted.signature,0);if error!=blot_error::Error.none {return false,error;}let b,error=context.ty(declared.signature,0);if error!=blot_error::Error.none {return false,error;}let left,error=candidate.destination.resolve(a,0);if error!=blot_error::Error.none {return false,error;}let right,error=candidate.destination.resolve(b,0);if error!=blot_error::Error.none {return false,error;}let equal,error=candidate.destination.equalClosed(left,right);if error!=blot_error::Error.none || !equal {return false,error;}
 }return true,blot_error::Error.none;
}
fn fit(source:const Store&,expected:u32,candidate_scheme:Scheme,enclosing:Scheme,obligations:const Obligation[:],budget:Budget&)->Match,Error {
 let result,error=fitPrivate(source,expected,candidate_scheme,enclosing,obligations,budget);if error==blot_error::Error.none {return result,blot_error::Error.none;}if error==blot_error::Error.out_of_memory {return Match.unknown,error;}
 if error==blot_error::Error.type_mismatch || error==blot_error::Error.effect_mismatch || error==blot_error::Error.infinite_type || error==blot_error::Error.infinite_effect {return Match.incompatible,blot_error::Error.none;}if error==blot_error::Error.type_limit {budget.exhausted=true;return Match.unknown,blot_error::Error.none;}return Match.unknown,error;
}
fn fitPrivate(source:const Store&,expected:u32,scheme:Scheme,enclosing:Scheme,obligations:const Obligation[:],budget:Budget&)->Match,Error {
 if expected==0 || scheme.root==0 {return Match.unknown,blot_error::Error.none;}
 if scheme.obligations.len>32 || enclosing.obligations.len>32 || scheme.variables.len>1024 || enclosing.variables.len>1024 || scheme.closed_rows.len>1024 || enclosing.closed_rows.len>1024 {budget.exhausted=true;return Match.unknown,blot_error::Error.none;}
 var expected_measure=Measure{source:source,quantified:enclosing.variables,closed_rows:enclosing.closed_rows,budget:budget};let error=expected_measure.ty(expected,0);if error!=blot_error::Error.none {return Match.unknown,error;}
 var candidate_measure=Measure{source:source,quantified:scheme.variables,closed_rows:scheme.closed_rows,budget:budget};let error=candidate_measure.ty(scheme.root,0);if error!=blot_error::Error.none {return Match.unknown,error;}
 for obligation in obligations[scheme.obligations.start..scheme.obligations.start+scheme.obligations.len] {for part in [obligation.ty,obligation.other,obligation.result] {if part!=0 {let error=candidate_measure.ty(part,0);if error!=blot_error::Error.none {return Match.unknown,error;}}}}
 for obligation in obligations[enclosing.obligations.start..enclosing.obligations.start+enclosing.obligations.len] {for part in [obligation.ty,obligation.other,obligation.result] {if part!=0 {let error=expected_measure.ty(part,0);if error!=blot_error::Error.none {return Match.unknown,error;}}}}
 for obligation in obligations[scheme.obligations.start..scheme.obligations.start+scheme.obligations.len] {if obligation.kind!=blot_check_types::ObligationKind.dispatch && obligation.signature!=0 {let error=candidate_measure.ty(obligation.signature,0);if error!=blot_error::Error.none {return Match.unknown,error;}}}
 for obligation in obligations[enclosing.obligations.start..enclosing.obligations.start+enclosing.obligations.len] {if obligation.kind!=blot_check_types::ObligationKind.dispatch && obligation.signature!=0 {let error=expected_measure.ty(obligation.signature,0);if error!=blot_error::Error.none {return Match.unknown,error;}}}
 let visits=expected_measure.visits+candidate_measure.visits;if !budget.spend(visits*visits) {return Match.unknown,blot_error::Error.none;}
 let value,error=blot_check_types::initPooled();if error!=blot_error::Error.none {return Match.unknown,error;}var private=value;
 let copied,error=blot_reuse_principal_type_graph::initPooled(blot_check_frozen_types::fromStore(source),private,32,1024,false);if error!=blot_error::Error.none {let __cleanup_result_1_0: Match = Match.unknown; let __cleanup_result_1_1: Error = error; {private.deinit();} return __cleanup_result_1_0, __cleanup_result_1_1;}var context=copied;
 let copied,error=blot_reuse_principal_type_graph::initPooled(blot_check_frozen_types::fromStore(source),private,32,1024,false);if error!=blot_error::Error.none {let __cleanup_result_2_0: Match = Match.unknown; let __cleanup_result_2_1: Error = error; {context.deinit();} {private.deinit();} return __cleanup_result_2_0, __cleanup_result_2_1;}var candidate=copied;
 seedClosed(context,enclosing);seedClosed(candidate,scheme);
 let source_visit_4_count=(source.list(enclosing.variables)).len;for source_visit_4_index in 0..source_visit_4_count {let variable=(source.list(enclosing.variables))[source_visit_4_index];let index=source_visit_4_index;let node=source.node(source.head(variable,0));if node.tag!=blot_check_types::Tag.variable {continue;}let rigid,error=private.typeConstructor(blot_check_types::NominalIdentity{0,(index+1) as u32});if error!=blot_error::Error.none {let __cleanup_result_3_0: Match = Match.unknown; let __cleanup_result_3_1: Error = error; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_3_0, __cleanup_result_3_1;}context.variables.insert(node.a,rigid);}
 let expected_copy,error=context.ty(expected,0);if error!=blot_error::Error.none {let __cleanup_result_4_0: Match = Match.unknown; let __cleanup_result_4_1: Error = error; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_4_0, __cleanup_result_4_1;}let candidate_copy,error=candidate.ty(scheme.root,0);if error!=blot_error::Error.none {let __cleanup_result_5_0: Match = Match.unknown; let __cleanup_result_5_1: Error = error; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_5_0, __cleanup_result_5_1;}
 var exact=false;if scheme.variables.len==0 && scheme.row_variables.len==0 {let equal,error=private.equalClosed(candidate_copy,expected_copy);if error!=blot_error::Error.none {let __cleanup_result_6_0: Match = Match.unknown; let __cleanup_result_6_1: Error = error; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_6_0, __cleanup_result_6_1;}exact=equal;}
 let error=private.unify(candidate_copy,expected_copy);if error!=blot_error::Error.none {let __cleanup_result_7_0: Match = Match.unknown; let __cleanup_result_7_1: Error = error; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_7_0, __cleanup_result_7_1;}if !expected_measure.known || !candidate_measure.known {let __cleanup_result_8_0: Match = Match.unknown; let __cleanup_result_8_1: Error = blot_error::Error.none; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_8_0, __cleanup_result_8_1;}
 for wanted in obligations[scheme.obligations.start..scheme.obligations.start+scheme.obligations.len] {
  if wanted.kind==blot_check_types::ObligationKind.callee_use {let __cleanup_result_9_0: Match = Match.unknown; let __cleanup_result_9_1: Error = blot_error::Error.none; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_9_0, __cleanup_result_9_1;}var entailed=false;
  for declared in obligations[enclosing.obligations.start..enclosing.obligations.start+enclosing.obligations.len] {if !budget.spend(visits*visits) {let __cleanup_result_10_0: Match = Match.unknown; let __cleanup_result_10_1: Error = blot_error::Error.none; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_10_0, __cleanup_result_10_1;}let found,error=covered(candidate,context,wanted,declared);if error!=blot_error::Error.none {let __cleanup_result_11_0: Match = Match.unknown; let __cleanup_result_11_1: Error = error; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_11_0, __cleanup_result_11_1;}if found {entailed=true;break;}}
  if !entailed {let __cleanup_result_12_0: Match = Match.unknown; let __cleanup_result_12_1: Error = blot_error::Error.none; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_12_0, __cleanup_result_12_1;}
 }if exact {let __cleanup_result_13_0: Match = Match.exact; let __cleanup_result_13_1: Error = blot_error::Error.none; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_13_0, __cleanup_result_13_1;}let __cleanup_result_14_0: Match = Match.compatible; let __cleanup_result_14_1: Error = blot_error::Error.none; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_14_0, __cleanup_result_14_1;
 {candidate.deinit();} {context.deinit();} {private.deinit();} }
