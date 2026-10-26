// Execute only the source-checked restricted fixture. Caller supplies a live,
// internally created scalar Owned handle, trusted non-copied State/Clock and a
// Bool input. This is a native model, not emitted K1 Wasm or a general runtime.
namespace affine_runtime;
import affine_syntax;
import affine_check;
import owned_scalar_runtime;
// control 0 fallthrough, 1 opening break, 2 Unit return, 3 Owned transfer.
struct Frame { control:i64 = 0, handle:owned_scalar_runtime::Handle = owned_scalar_runtime::Handle {} }
struct Result { status:i64 = 1, returned:bool = false, handle:owned_scalar_runtime::Handle = owned_scalar_runtime::Handle {} }
recursive fn exec(tree:affine_syntax::Tree&, id:i64, state:owned_scalar_runtime::State&,
                  handle:owned_scalar_runtime::Handle, flag:bool, depth:i64) -> Frame {
    assert(depth<=256 && id>=1 && id<=tree.nodes.len);
    let n=tree.nodes[id-1];
    if n.tag==8 {
        let a=exec(tree,n.a,state,handle,flag,depth+1);
        if a.control!=0 {return a;}
        return exec(tree,n.b,state,a.handle,flag,depth+1);
    }
    if n.tag==1 {
        let moved=owned_scalar_runtime::move(state,handle); assert(moved.status==0);
        return Frame {handle:moved.handle};
    }
    if n.tag==2 {
        assert(owned_scalar_runtime::close(state,handle).status==0);
        return Frame {};
    }
    if n.tag==3 {
        let opening=owned_scalar_runtime::open(state,handle); assert(opening.status==0);
        let inside=exec(tree,n.a,state,handle,flag,depth+1);
        assert(inside.control==1);
        assert(owned_scalar_runtime::end_open(state,handle,opening.loan).status==0);
        return Frame {handle:handle};
    }
    if n.tag==4 {
        if flag {return exec(tree,n.a,state,handle,flag,depth+1);}
        if n.b!=0 {return exec(tree,n.b,state,handle,flag,depth+1);}
        return Frame {handle:handle};
    }
    if n.tag==5 {return Frame {control:2};}
    if n.tag==6 {return Frame {control:3,handle:handle};}
    if n.tag==7 {return Frame {control:1,handle:handle};}
    assert(false); return Frame {};
}
fn run(tree:affine_syntax::Tree&, source:u8[:], mode:i64, state:owned_scalar_runtime::State&,
       handle:owned_scalar_runtime::Handle, flag:bool) -> Result {
    // Conservative preflight covers every possible bounded opening/move before
    // consuming the incoming owner. No failure result may lose that handle.
    if affine_check::check(tree,source,mode)!=0 || !owned_scalar_runtime::live(state,handle) || state.loan_count!=0 ||
       state.stamp==18446744073709551615 || state.next_loan>18446744073709551359 {return Result {};}
    let out=exec(tree,tree.root,state,handle,flag,0);
    if mode==0 {assert(out.control==2 && state.slot==0 && state.loan_count==0); return Result {status:0};}
    assert(out.control==3 && owned_scalar_runtime::live(state,out.handle) && state.loan_count==0);
    return Result {status:0,returned:true,handle:out.handle};
}
