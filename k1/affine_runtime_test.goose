import owned_scalar_source;
import owned_scalar_runtime;
import affine_parse;
import affine_runtime;
fn main() {
    let owned="owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,7)\n";
    let scalar=owned_scalar_source::parse(owned); assert(scalar.status==0);
    let closes="do:\n  if flag:\n    let value = owned.open(h) as r payload in do:\n      break payload\n    owned.close(h)\n    return ()\n  else:\n    let m = h\n    owned.close(m)\n    return ()\n";
    let returns="do:\n  if flag:\n    let m = h\n    return m\n  else:\n    return h\n";
    let early="do:\n  if flag:\n    owned.close(h)\n    return ()\n  owned.close(h)\n  return ()\n";
    var a=affine_parse::parse(closes); var b=affine_parse::parse(returns); var c=affine_parse::parse(early);
    assert(a.status==0 && b.status==0 && c.status==0);
    var clock=owned_scalar_runtime::Clock {}; var state=owned_scalar_runtime::State {};
    assert(owned_scalar_runtime::initialize(state,clock));
    for choice in 2 {
        let built=owned_scalar_runtime::construct(state,owned,scalar.core); assert(built.status==0);
        let done=affine_runtime::run(a.tree,closes,0,state,built.handle,choice==1);
        assert(done.status==0 && !done.returned && state.slot==0 && state.bitmap[0]==0 && state.loan_count==0);
        let again=owned_scalar_runtime::construct(state,owned,scalar.core); assert(again.status==0);
        let transferred=affine_runtime::run(b.tree,returns,1,state,again.handle,choice==1);
        assert(transferred.status==0 && transferred.returned && owned_scalar_runtime::live(state,transferred.handle));
        if choice==1 {assert(!owned_scalar_runtime::live(state,again.handle));}
        let opened=owned_scalar_runtime::open(state,transferred.handle);
        assert(opened.status==0 && opened.value==7);
        assert(owned_scalar_runtime::end_open(state,transferred.handle,opened.loan).status==0);
        assert(owned_scalar_runtime::close(state,transferred.handle).status==0);
        let third=owned_scalar_runtime::construct(state,owned,scalar.core); assert(third.status==0);
        let early_exit=affine_runtime::run(c.tree,early,0,state,third.handle,choice==1);
        assert(early_exit.status==0 && state.slot==0 && state.bitmap[0]==0 && state.loan_count==0);
    }
    let built=owned_scalar_runtime::construct(state,owned,scalar.core); assert(built.status==0);
    let before=copy(state.memory); let old=state.slots[0]; let stamp=state.stamp;
    assert(affine_runtime::run(a.tree,returns,0,state,built.handle,true).status==1);
    assert(owned_scalar_runtime::live(state,built.handle) && state.stamp==stamp && state.slots[0].top==old.top && state.memory[..]==before[..]);
    let loan=owned_scalar_runtime::open(state,built.handle); assert(loan.status==0);
    assert(affine_runtime::run(a.tree,closes,0,state,built.handle,true).status==1);
    assert(owned_scalar_runtime::live(state,built.handle) && state.loan_count==1);
    assert(owned_scalar_runtime::end_open(state,built.handle,loan.loan).status==0);
    state.next_loan=18446744073709551615;
    assert(affine_runtime::run(a.tree,closes,0,state,built.handle,true).status==1);
    assert(owned_scalar_runtime::live(state,built.handle));
    state.next_loan=0;
    assert(owned_scalar_runtime::close(state,built.handle).status==0);
    print("checked affine branching executes and cleans up");
}
