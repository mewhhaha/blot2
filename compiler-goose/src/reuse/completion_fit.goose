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
fn spend(self:Budget&,amount:i64)->bool {if amount>self.remaining {self.exhausted=true;self.remaining=0;return false;}self.remaining-=amount;return true;}
fn contains(items:const u32[:],value:u32)->bool {for item in items {if item==value {return true;}}return false;}
struct Measure {source:Store,quantified:blot_check_types::List,closed_rows:blot_check_types::List,budget:Budget&,visits:i64=0,known:bool=true}
recursive fn ty(self:Measure&,original:u32,depth:i64)->Error {
 if depth>=32 || self.visits==1024 || !self.budget.spend(1+self.source.versions.len+self.source.effects.versions.len) {return Error.type_limit;}self.visits++;
 let root=self.source.head(original,0);let node=self.source.node(root);
 match node.tag {
  blot_check_types::Tag.absent=>{self.known=false;},blot_check_types::Tag.variable=>{if !contains(self.source.list(self.quantified),root) {self.known=false;}},
  blot_check_types::Tag.function=>{let error=self.ty(node.a,depth+1);if error!=Error.none {return error;}let error=self.ty(node.b,depth+1);if error!=Error.none {return error;}return self.row(node.c,depth+1);},
  blot_check_types::Tag.array,blot_check_types::Tag.list,blot_check_types::Tag.cursor,blot_check_types::Tag.resolver=>{return self.ty(node.a,depth+1);},
  blot_check_types::Tag.provider=>{let error=self.ty(node.a,depth+1);if error!=Error.none {return error;}return self.row(node.c,depth+1);},
  blot_check_types::Tag.state_provider=>{for part in [node.a,node.b,node.c] {let error=self.ty(part,depth+1);if error!=Error.none {return error;}}},
  blot_check_types::Tag.product=>{let span=blot_check_types::List{node.a,node.b};for index in span.len {let child=self.source.list(span)[index];let error=self.ty(child,depth+1);if error!=Error.none {return error;}}},
  blot_check_types::Tag.nominal=>{let span=blot_check_types::List{node.c+1,self.source.nominalArguments(node).len as u32};for index in span.len {let child=self.source.list(span)[index];let error=self.ty(child,depth+1);if error!=Error.none {return error;}}},
  blot_check_types::Tag.record=>{for index in node.b {let error=self.ty(self.source.recordField(node,index).ty,depth+1);if error!=Error.none {return error;}}},_=>{},
 }return Error.none;
}
recursive fn row(self:Measure&,id:u32,depth:i64)->Error {
 let row=self.source.row(id);match row.tail {blot_check_effects::Tail.closed=>{},blot_check_effects::Tail.variable payload=>{if !contains(self.source.list(self.closed_rows),payload.value) {self.known=false;}},_=>{self.known=false;}}
 for label in self.source.rowLabels(id) {if self.visits==1024 {return Error.type_limit;}self.visits++;if !self.budget.spend(1) {return Error.type_limit;}for part in self.source.operationArguments(label) {let error=self.ty(part,depth+1);if error!=Error.none {return error;}}}return Error.none;
}
fn seedClosed(copy:Copy&,scheme:Scheme) {for variable in copy.source.list(scheme.closed_rows) {copy.row_variables.insert(variable,0);}}
fn requirementHead(left:Obligation,right:Obligation)->bool {return left.kind==right.kind && left.name==right.name && left.operator==right.operator && left.identity==right.identity;}
fn covered(candidate:Copy&,context:Copy&,wanted:Obligation,declared:Obligation)->bool,Error {
 if !requirementHead(wanted,declared) {return false,Error.none;}
 for pair in [[wanted.ty,declared.ty],[wanted.other,declared.other],[wanted.result,declared.result]] {
  if pair[0]==0 && pair[1]==0 {continue;}if pair[0]==0 || pair[1]==0 {return false,Error.none;}let left,error=candidate.ty(pair[0],0);if error!=Error.none {return false,error;}let right,error=context.ty(pair[1],0);if error!=Error.none {return false,error;}
  let a,error=candidate.destination.resolve(left,0);if error!=Error.none {return false,error;}let b,error=candidate.destination.resolve(right,0);if error!=Error.none {return false,error;}let equal,error=candidate.destination.equalClosed(a,b);if error!=Error.none || !equal {return false,error;}
 }
 if wanted.kind!=blot_check_types::ObligationKind.dispatch && (wanted.signature!=0 || declared.signature!=0) {
  if wanted.signature==0 || declared.signature==0 {return false,Error.none;}let a,error=candidate.ty(wanted.signature,0);if error!=Error.none {return false,error;}let b,error=context.ty(declared.signature,0);if error!=Error.none {return false,error;}let left,error=candidate.destination.resolve(a,0);if error!=Error.none {return false,error;}let right,error=candidate.destination.resolve(b,0);if error!=Error.none {return false,error;}let equal,error=candidate.destination.equalClosed(left,right);if error!=Error.none || !equal {return false,error;}
 }return true,Error.none;
}
fn fit(source:const Store&,expected:u32,candidate_scheme:Scheme,enclosing:Scheme,obligations:const Obligation[:],budget:Budget&)->Match,Error {
 let result,error=fitPrivate(source,expected,candidate_scheme,enclosing,obligations,budget);if error==Error.none {return result,Error.none;}if error==Error.out_of_memory {return Match.unknown,error;}
 if error==Error.type_mismatch || error==Error.effect_mismatch || error==Error.infinite_type || error==Error.infinite_effect {return Match.incompatible,Error.none;}if error==Error.type_limit {budget.exhausted=true;return Match.unknown,Error.none;}return Match.unknown,error;
}
fn fitPrivate(source:const Store&,expected:u32,scheme:Scheme,enclosing:Scheme,obligations:const Obligation[:],budget:Budget&)->Match,Error {
 if expected==0 || scheme.root==0 {return Match.unknown,Error.none;}
 if scheme.obligations.len>32 || enclosing.obligations.len>32 || scheme.variables.len>1024 || enclosing.variables.len>1024 || scheme.closed_rows.len>1024 || enclosing.closed_rows.len>1024 {budget.exhausted=true;return Match.unknown,Error.none;}
 var expected_measure=Measure{source:source,quantified:enclosing.variables,closed_rows:enclosing.closed_rows,budget:budget};let error=expected_measure.ty(expected,0);if error!=Error.none {return Match.unknown,error;}
 var candidate_measure=Measure{source:source,quantified:scheme.variables,closed_rows:scheme.closed_rows,budget:budget};let error=candidate_measure.ty(scheme.root,0);if error!=Error.none {return Match.unknown,error;}
 for obligation in obligations[scheme.obligations.start..scheme.obligations.start+scheme.obligations.len] {for part in [obligation.ty,obligation.other,obligation.result] {if part!=0 {let error=candidate_measure.ty(part,0);if error!=Error.none {return Match.unknown,error;}}}}
 for obligation in obligations[enclosing.obligations.start..enclosing.obligations.start+enclosing.obligations.len] {for part in [obligation.ty,obligation.other,obligation.result] {if part!=0 {let error=expected_measure.ty(part,0);if error!=Error.none {return Match.unknown,error;}}}}
 for obligation in obligations[scheme.obligations.start..scheme.obligations.start+scheme.obligations.len] {if obligation.kind!=blot_check_types::ObligationKind.dispatch && obligation.signature!=0 {let error=candidate_measure.ty(obligation.signature,0);if error!=Error.none {return Match.unknown,error;}}}
 for obligation in obligations[enclosing.obligations.start..enclosing.obligations.start+enclosing.obligations.len] {if obligation.kind!=blot_check_types::ObligationKind.dispatch && obligation.signature!=0 {let error=expected_measure.ty(obligation.signature,0);if error!=Error.none {return Match.unknown,error;}}}
 let visits=expected_measure.visits+candidate_measure.visits;if !budget.spend(visits*visits) {return Match.unknown,Error.none;}
 let value,error=blot_check_types::initPooled();if error!=Error.none {return Match.unknown,error;}var private=value;
 let copied,error=blot_reuse_principal_type_graph::initPooled(blot_check_frozen_types::Source.store{source},private,32,1024,false);if error!=Error.none {let __cleanup_result_1_0: Match = Match.unknown; let __cleanup_result_1_1: Error = error; {private.deinit();} return __cleanup_result_1_0, __cleanup_result_1_1;}var context=copied;
 let copied,error=blot_reuse_principal_type_graph::initPooled(blot_check_frozen_types::Source.store{source},private,32,1024,false);if error!=Error.none {let __cleanup_result_2_0: Match = Match.unknown; let __cleanup_result_2_1: Error = error; {context.deinit();} {private.deinit();} return __cleanup_result_2_0, __cleanup_result_2_1;}var candidate=copied;
 seedClosed(context,enclosing);seedClosed(candidate,scheme);
 for variable,index in source.list(enclosing.variables) {let node=source.node(source.head(variable,0));if node.tag!=blot_check_types::Tag.variable {continue;}let rigid,error=private.typeConstructor(blot_check_types::NominalIdentity{0,(index+1) as u32});if error!=Error.none {let __cleanup_result_3_0: Match = Match.unknown; let __cleanup_result_3_1: Error = error; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_3_0, __cleanup_result_3_1;}context.variables.insert(node.a,rigid);}
 let expected_copy,error=context.ty(expected,0);if error!=Error.none {let __cleanup_result_4_0: Match = Match.unknown; let __cleanup_result_4_1: Error = error; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_4_0, __cleanup_result_4_1;}let candidate_copy,error=candidate.ty(scheme.root,0);if error!=Error.none {let __cleanup_result_5_0: Match = Match.unknown; let __cleanup_result_5_1: Error = error; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_5_0, __cleanup_result_5_1;}
 var exact=false;if scheme.variables.len==0 && scheme.row_variables.len==0 {let equal,error=private.equalClosed(candidate_copy,expected_copy);if error!=Error.none {let __cleanup_result_6_0: Match = Match.unknown; let __cleanup_result_6_1: Error = error; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_6_0, __cleanup_result_6_1;}exact=equal;}
 let error=private.unify(candidate_copy,expected_copy);if error!=Error.none {let __cleanup_result_7_0: Match = Match.unknown; let __cleanup_result_7_1: Error = error; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_7_0, __cleanup_result_7_1;}if !expected_measure.known || !candidate_measure.known {let __cleanup_result_8_0: Match = Match.unknown; let __cleanup_result_8_1: Error = Error.none; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_8_0, __cleanup_result_8_1;}
 for wanted in obligations[scheme.obligations.start..scheme.obligations.start+scheme.obligations.len] {
  if wanted.kind==blot_check_types::ObligationKind.callee_use {let __cleanup_result_9_0: Match = Match.unknown; let __cleanup_result_9_1: Error = Error.none; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_9_0, __cleanup_result_9_1;}var entailed=false;
  for declared in obligations[enclosing.obligations.start..enclosing.obligations.start+enclosing.obligations.len] {if !budget.spend(visits*visits) {let __cleanup_result_10_0: Match = Match.unknown; let __cleanup_result_10_1: Error = Error.none; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_10_0, __cleanup_result_10_1;}let found,error=covered(candidate,context,wanted,declared);if error!=Error.none {let __cleanup_result_11_0: Match = Match.unknown; let __cleanup_result_11_1: Error = error; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_11_0, __cleanup_result_11_1;}if found {entailed=true;break;}}
  if !entailed {let __cleanup_result_12_0: Match = Match.unknown; let __cleanup_result_12_1: Error = Error.none; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_12_0, __cleanup_result_12_1;}
 }if exact {let __cleanup_result_13_0: Match = Match.exact; let __cleanup_result_13_1: Error = Error.none; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_13_0, __cleanup_result_13_1;}let __cleanup_result_14_0: Match = Match.compatible; let __cleanup_result_14_1: Error = Error.none; {candidate.deinit();} {context.deinit();} {private.deinit();} return __cleanup_result_14_0, __cleanup_result_14_1;
 {candidate.deinit();} {context.deinit();} {private.deinit();} }
