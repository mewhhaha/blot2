// Native execution for the source-checked one-owner U32 fixture. All openings
// refer to the same immutable scalar payload; scalar results are host values.
// The surrounding type/contract, non-copied runtime State and single shared
// owner clock remain trusted. This does not emit K1 Wasm or admit general types.
namespace ownership_runtime;
import ownership_syntax;
import ownership_check;
import owned_scalar_runtime;
// control 0 fallthrough, 1 lexical break, 2 Unit return, 3 Owned transfer,
// 4 U32 return. All accepted scalar variables come from this same U32 payload.
struct Frame {control:i64=0,handle:owned_scalar_runtime::Handle=owned_scalar_runtime::Handle {},value:u32=0,has_value:bool=false}
struct Result {status:i64=1,returned_owner:bool=false,handle:owned_scalar_runtime::Handle=owned_scalar_runtime::Handle {},value:u32=0}
recursive fn exec(t:ownership_syntax::Tree&,id:i64,state:owned_scalar_runtime::State&,f:Frame,mode:i64,flag:bool,depth:i64) -> Frame {
    assert(depth<=256 && id>=1 && id<=t.nodes.len);let n=t.nodes[id-1];var out=f;
    if n.tag==8 {let a=exec(t,n.a,state,f,mode,flag,depth+1);if a.control!=0 {return a;}return exec(t,n.b,state,a,mode,flag,depth+1);}
    if n.tag==1 {let moved=owned_scalar_runtime::move(state,f.handle);assert(moved.status==0);out.handle=moved.handle;return out;}
    if n.tag==2 {assert(owned_scalar_runtime::close(state,f.handle).status==0);out.handle=owned_scalar_runtime::Handle {};return out;}
    if n.tag==3 {
        let opening=owned_scalar_runtime::open(state,f.handle);assert(opening.status==0);
        let inside=exec(t,n.a,state,f,mode,flag,depth+1);assert(inside.control==1);
        assert(owned_scalar_runtime::end_open(state,f.handle,opening.loan).status==0);
        out.value=opening.value;out.has_value=true;return out;
    }
    if n.tag==4 {if flag {return exec(t,n.a,state,f,mode,flag,depth+1);}if n.b!=0 {return exec(t,n.b,state,f,mode,flag,depth+1);}return f;}
    if n.tag==5 {out.control=2;return out;}
    if n.tag==6 {if mode==1 {out.control=3;}else {assert(mode==2 && out.has_value);out.control=4;}return out;}
    if n.tag==7 {out.control=1;return out;}
    assert(false);return Frame {};
}
fn run(t:ownership_syntax::Tree&,source:u8[:],contract:ownership_check::Contract&,state:owned_scalar_runtime::State&,
       handle:owned_scalar_runtime::Handle,flag:bool) -> Result {
    // At most 128 declarations and 256 nodes can execute. Preflight all
    // fixture counters before an affine input is moved or a loan is opened.
    if ownership_check::check(t,source,contract)!=0 || !owned_scalar_runtime::live(state,handle) || state.loan_count!=0 ||
       state.stamp>18446744073709551487 || state.next_loan>18446744073709551359 {return Result {};}
    let out=exec(t,t.root,state,Frame {handle:handle},contract.return_mode,flag,0);
    if contract.return_mode==0 {assert(out.control==2 && state.slot==0 && state.loan_count==0);return Result {status:0};}
    if contract.return_mode==1 {assert(out.control==3 && owned_scalar_runtime::live(state,out.handle) && state.loan_count==0);return Result {status:0,returned_owner:true,handle:out.handle};}
    assert(out.control==4 && state.slot==0 && state.loan_count==0 && out.has_value);
    return Result {status:0,value:out.value};
}
