import common_frontend;
import common_guard;
import common_proof;
fn main(){let s="let f: U32 -> Bool = fn x => do:\n  let y = x\n  return y < 4294967295 && (y + 1) < 100\n";var p=common_frontend::parse(s);assert(p.status==0);var proof=common_guard::check(s,p.program);assert(proof.status==0 && proof.evidence.len==1 && common_proof::verify_evidence(s,p.program,proof.evidence));
 for f in 9 {let old=proof.evidence[0];if f==0 {proof.evidence[0].guard_id+=1;}else if f==1 {proof.evidence[0].guard_true=!proof.evidence[0].guard_true;}else if f==2 {proof.evidence[0].subject+=1;}else if f==3 {proof.evidence[0].reference+=1;}else if f==4 {proof.evidence[0].one+=1;}else if f==5 {proof.evidence[0].addition+=1;}else if f==6 {proof.evidence[0].path_count+=1;}else if f==7 {proof.evidence[0].path_guard[15]=1;}else {proof.evidence[0].path_true[15]=true;}assert(!common_proof::verify_evidence(s,p.program,proof.evidence));proof.evidence[0]=old;}
 print("forged Bool-return evidence controls passed");}
