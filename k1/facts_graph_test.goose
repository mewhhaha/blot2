// Exhaustive small independent graph oracle over all two-guard source shapes.
import std;
import facts_engine;
import facts_validate;
// Floyd-Warshall over (left,right,strict-seen); no production graph helper.
fn oracle(a: u32,b: u32,as_: bool,c: u32,d: u32,bs: bool,truth: bool,left: u32,right: u32,want: bool) -> u32 {
    var reach: bool[18] = [false;18];
    for i in 3 { reach[(i*3+i)*2]=true; }
    let from=if truth { c } else { d }; let to=if truth { d } else { c }; let strict=if truth { bs } else { !bs };
    reach[((a-1)*3+(b-1))*2+(if as_ { 1 } else { 0 })]=true;
    reach[((from-1)*3+(to-1))*2+(if strict { 1 } else { 0 })]=true;
    for k in 3 { for i in 3 { for j in 3 { for p in 2 { for q in 2 {
        if reach[(i*3+k)*2+p] && reach[(k*3+j)*2+q] { reach[(i*3+j)*2+(if p==1 || q==1 { 1 } else { 0 })]=true; }
    } } } } }
    for i in 3 { if reach[(i*3+i)*2+1] { return 2; } }
    let base=((left-1)*3+(right-1))*2;
    return if reach[base+1] || (!want && reach[base]) { 1 } else { 0 };
}
fn main() {
    let names = ["a","b","c"];
    var checked: u32=0;
    for a in 1..4 { for b in 1..4 { if a==b { continue; }
      for c in 1..4 { for d in 1..4 { if c==d { continue; }
        for sa in 2 { for sb in 2 { for branch in 2 {
          let source=str("let f: (U32,U32,U32)->U32 = fn (a,b,c) => do:\n  if ",names[a-1],
              if sa==1 { " < " } else { " <= " },names[b-1],":\n    if ",names[c-1],
              if sb==1 { " < " } else { " <= " },names[d-1],":\n      ()\n    else:\n      ()\n    return a\n  else:\n    return c\n");
          for l in 1..4 { for r in 1..4 { for requested in 2 {
            let expected=oracle(a as u32,b as u32,sa==1,c as u32,d as u32,sb==1,branch==1,l as u32,r as u32,requested==1);
            var job=facts_engine::Job {}; assert(facts_engine::begin(source,job,true).status==0);
            let entered=facts_engine::enter_inner(job,branch==1);
            if expected==2 { assert(entered.status==6 && facts_engine::finish(job).status==0); }
            else {
                assert(entered.status==0);
                let left=facts_engine::term(l as u32); let right=facts_engine::term(r as u32);
                let result=facts_engine::query(job,left,right,requested==1);
                if expected==1 {
                    assert(result.status==0 && facts_validate::verify(source,job,result.proof,left,right,requested==1).status==0);
                    assert(facts_engine::drop_proof(job).status==0);
                } else { assert(result.status==5); }
                assert(facts_engine::finish(job).status==0 && job.graph.meter.proof_edges==0);
            }
            checked+=1;
          } } }
        } } }
      } }
    } }
    assert(checked==5184);
    print("source-checked two-guard finite graph oracle passed");
}
