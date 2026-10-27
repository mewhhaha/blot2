import std;
import short_frontend;
import short_check;
fn main(){
 var accepted:i64=0;var rejected:i64=0;
 for b in [0 as u64,1,5,10,4294967285,4294967290,4294967294,4294967295] {
  for k in [1 as u64,2,5,10,4294967295] {
   for mode in 4 {
    for alias in 2 {
     let head="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = x\n";
     let subject=if alias==0 {"x"} else {"y"};
     let cond=if mode==0 {str(subject," <= ",b)} else if mode==1 {str(subject," < ",b)} else if mode==2 {str(b," < ",subject)} else {str(b," <= ",subject)};
     let add=str("x + ",k);let src=if mode<2 {str(head,"  if ",cond,":\n    return ",add,"\n  return x\n")} else {str(head,"  if ",cond,":\n    return x\n  else:\n    return ",add,"\n")};
     var p=short_frontend::parse(src);if p.status==0 {assert(short_check::verify(src,p.program));accepted+=1;
      // A true <= or false > path permits b; a true < or false >= permits b-1.
      // b=0 for strict cases has no runtime inputs.
      if mode==0 || mode==2 {assert(b+k<=4294967295);} else if b>0 {assert(b-1+k<=4294967295);}
     }else {rejected+=1;}
    }
   }
  }
 }
 assert(accepted>0 && rejected>0);print("independent upper-bound / alias / false-edge matrix: accepted ",accepted," rejected ",rejected);
}
