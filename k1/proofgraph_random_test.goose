// Independent closure oracle over generated source requirements. These tests
// do not use the engine's traversal or equality-union helpers as an oracle.
import std;
import proofgraph_engine;
import proofgraph_validate;
struct Random { state:u32=72725119 }
fn rnd(r:Random&)->u32 { r.state^=r.state<<13; r.state^=r.state>>17; r.state^=r.state<<5; return r.state; }
struct F { kind:u32=0,left:u32=0,right:u32=0 }
fn main() {
    let names=["a","b","c","d","e","f","g","h"];
    var random=Random {}; var total:u32=0; var consistent:u32=0;
    for example in 96 {
        let n=2+rnd(random)%7; let count=1+rnd(random)%12;
        var source:u8[>..]=[]; source.append("pub let fn_main: (");
        for i in n { if i>0 { source.append(","); } source.append("U32"); }
        source.append(")->U32 ! {} requires [");
        var facts:F[16]=[F {};16]; var reach:bool[128]=[false;128]; var equal:bool[64]=[false;64];
        for i in n { reach[(i*8+i)*2]=true; equal[i*8+i]=true; }
        for i in count {
            if i>0 { source.append(","); }
            let k=1+rnd(random)%3; let l=rnd(random)%n; let r=rnd(random)%n;
            facts[i]=F {kind:k,left:l,right:r};
            source.append(if k==1 {"Le("} else if k==2 {"Lt("} else {"Eq("});
            source.append(str("arg.",l,",arg.",r,")"));
            reach[(l*8+r)*2+(if k==2 {1} else {0})]=true;
            if k==3 { reach[(r*8+l)*2]=true; equal[l*8+r]=true; equal[r*8+l]=true; }
        }
        source.append("] resources {depth:1,frame:0} = fn (");
        for i in n { if i>0 { source.append(","); } source.append(names[i]); }
        source.append(") => return a\n");
        for k in n { for i in n { for j in n {
            if equal[i*8+k] && equal[k*8+j] { equal[i*8+j]=true; }
            for p in 2 { for q in 2 {
                if reach[(i*8+k)*2+p] && reach[(k*8+j)*2+q] { reach[(i*8+j)*2+(if p==1 || q==1 {1} else {0})]=true; }
            } }
        } } }
        var inconsistent=false; for i in n { if reach[(i*8+i)*2+1] { inconsistent=true; } }
        for trial in 6 {
            var job=proofgraph_engine::Job {}; let begun=proofgraph_engine::begin(source,job);
            if inconsistent { assert(begun.status==6 && job.failed); total+=1; continue; }
            assert(begun.status==0); consistent+=1;
            let id=rnd(random)%n; var smallest=id;
            for k in n { if equal[id*8+k] && k<smallest { smallest=k; } }
            let representative=proofgraph_engine::root(job,id+1);
            assert(representative.status==0 && representative.id==smallest+1);
            assert(proofgraph_validate::verify_class(source,job,proofgraph_engine::term(id+1),smallest+1).status==0);
            let l=rnd(random)%n; let r=rnd(random)%n; let strict=rnd(random)%2==1;
            let expected=reach[(l*8+r)*2+1] || (!strict && reach[(l*8+r)*2]);
            let left=proofgraph_engine::term(l+1); let right=proofgraph_engine::term(r+1);
            let q=proofgraph_engine::query(job,left,right,strict);
            if expected {
                assert(q.status==0 && proofgraph_validate::verify(source,job,q.proof,left,right,strict).status==0);
                assert(proofgraph_engine::drop(job).status==0);
            } else { assert(q.status==5); }
            assert(proofgraph_engine::finish(job).status==0 && job.meter.proof_edges==0); total+=1;
        }
    }
    assert(total==576 && consistent>0);
    print("source requirement graph and equality oracle passed");
}
