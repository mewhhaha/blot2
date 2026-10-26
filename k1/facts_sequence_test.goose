// Independent reachability oracle for repeated queries under one live job.
// The bounded fixture is not a complete K1 proof engine or work receipt.
import std;
import facts_engine;
import facts_validate;
struct Matrix { nonstrict: bool[9] = [false;9], strict: bool[9] = [false;9], contradiction: bool = false }
// Maintain separate 3x3 <= and < relations, unlike the producer's BFS over
// (term, strict-seen) states. At a join only explicit active edges are input.
fn oracle(a: i64, b: i64, outer_strict: bool, c: i64, d: i64, inner_strict: bool, truth: bool) -> Matrix {
    var m = Matrix {};
    for i in 3 { m.nonstrict[i*3+i] = true; }
    let outer = (a-1)*3+b-1; m.nonstrict[outer] = true; m.strict[outer] = outer_strict;
    let from = if truth { c } else { d }; let to = if truth { d } else { c };
    let inner = (from-1)*3+to-1; m.nonstrict[inner] = true;
    m.strict[inner] = m.strict[inner] || (if truth { inner_strict } else { !inner_strict });
    for k in 3 { for i in 3 { for j in 3 {
        let ik=i*3+k; let kj=k*3+j; let ij=i*3+j;
        m.strict[ij] = m.strict[ij] || (m.strict[ik] && m.nonstrict[kj]) || (m.nonstrict[ik] && m.strict[kj]);
        m.nonstrict[ij] = m.nonstrict[ij] || (m.nonstrict[ik] && m.nonstrict[kj]);
    } } }
    for i in 3 { if m.strict[i*3+i] { m.contradiction = true; } }
    return m;
}
fn main() {
    let names = ["a","b","c"]; var scenarios: i64 = 0; var queries: i64 = 0;
    for a in 1..4 { for b in 1..4 { if a==b { continue; }
      for c in 1..4 { for d in 1..4 { if c==d { continue; }
        for sa in 2 { for sb in 2 { for branch in 2 {
            let source=str("let f: (U32,U32,U32)->U32 = fn (a,b,c) => do:\n  if ",names[a-1],
                if sa==1 { " < " } else { " <= " },names[b-1],":\n    if ",names[c-1],
                if sb==1 { " < " } else { " <= " },names[d-1],":\n      ()\n    else:\n      ()\n    return a\n  else:\n    return c\n");
            let expected=oracle(a,b,sa==1,c,d,sb==1,branch==1);
            var job=facts_engine::Job {}; assert(facts_engine::begin(source,job,true).status==0);
            let inner=facts_engine::enter_inner(job,branch==1); scenarios+=1;
            if expected.contradiction { assert(inner.status==6 && facts_engine::finish(job).status==0); continue; }
            assert(inner.status==0);
            for left in 1..4 { for right in 1..4 { for strict in [false,true] {
                let l=facts_engine::term(left as u32); let r=facts_engine::term(right as u32);
                let result=facts_engine::query(job,l,r,strict);
                let k=(left-1)*3+right-1;
                let holds=if strict { expected.strict[k] } else { expected.nonstrict[k] };
                if holds {
                    assert(result.status==0 && facts_validate::verify(source,job,result.proof,l,r,strict).status==0);
                    assert(facts_engine::drop_proof(job).status==0);
                } else { assert(result.status==5); }
                queries+=1;
            } } }
            assert(facts_engine::finish(job).status==0 && job.graph.meter.proof_edges==0 && job.graph.meter.proof_terms==3);
        } } }
      } }
    } }
    assert(scenarios==288 && queries>0);
    print("independent repeated scoped fact queries passed");
}
