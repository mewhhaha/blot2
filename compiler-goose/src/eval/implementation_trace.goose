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
fn candidate(self: Record&,identity: Identity,outcome: Outcome) {
 for index in 0..self.len { if self.candidates[index].identity.unit==identity.unit&&self.candidates[index].identity.decl==identity.decl { self.candidates[index].outcome=outcome; return; } }
 if self.len==self.candidates.len { self.truncated=true; return; } self.candidates[self.len]=Candidate {identity,outcome}; self.len++;
}
fn step(self: Record&,ty: u32,member: u32,outcome: Outcome) -> i64,bool {
 if self.step_len==self.steps.len { self.truncated=true; return 0,false; } let index=self.step_len; self.steps[index]=Step {ty,member,outcome}; self.step_len++; return index,true;
}
fn setOutcome(self: Record&,index: i64,present: bool,value: Outcome) { if present { self.steps[index].outcome=value; } }
