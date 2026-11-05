namespace blot_eval_implementation_trace;
import check.types;
import reuse.dispatch_explanation;

type Identity=blot_check_types::NominalIdentity;
type Outcome=blot_reuse_dispatch_explanation::Outcome;
struct Candidate { identity: Identity, outcome: Outcome }
struct Step { ty: u32, member: u32=0, outcome: Outcome }
struct Record {
 context: u32=0, request: u32=0, contract: Identity=Identity {0,0},
 candidates: Candidate[blot_reuse_dispatch_explanation::max_candidates], len: i64=0,
 steps: Step[blot_reuse_dispatch_explanation::max_steps], step_len: i64=0, truncated: bool=false
}
fn candidate(self_: Record&,identity: Identity,outcome: Outcome) {
 for index in 0..self_.len { if self_.candidates[index].identity.unit==identity.unit&&self_.candidates[index].identity.decl==identity.decl { self_.candidates[index].outcome=outcome; return; } }
 if self_.len==self_.candidates.len { self_.truncated=true; return; } self_.candidates[self_.len]=Candidate {identity,outcome}; self_.len++;
}
fn step(self_: Record&,ty: u32,member: u32,outcome: Outcome) -> i64,bool {
 if self_.step_len==self_.steps.len { self_.truncated=true; return 0,false; } let index=self_.step_len; self_.steps[index]=Step {ty,member,outcome}; self_.step_len++; return index,true;
}
fn setOutcome(self_: Record&,index: i64,present: bool,value: Outcome) { if present { self_.steps[index].outcome=value; } }
