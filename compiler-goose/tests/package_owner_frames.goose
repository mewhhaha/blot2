import std;
import check.package_owner_frames;
fn contains(head:i64,node:u32)->bool {
    var cursor=head;
    while cursor!=0 {let frame=blot_check_package_owner_frames::control(cursor);if frame.node==node {return true;}cursor=frame.parent;}
    return false;
}
recursive fn nested(scope:i64&,returns:i64&,loops:i64&,decision:i64&,depth:i64,fail_at:i64)->bool {
    let prior_scope=scope;let prior_return=returns;let prior_loop=loops;let prior_decision=decision;
    scope=blot_check_package_owner_frames::pushScope(7,depth as u32,scope);
    returns=blot_check_package_owner_frames::pushControl((100+depth) as u32,returns);
    loops=blot_check_package_owner_frames::pushControl((200+depth) as u32,loops);
    decision=blot_check_package_owner_frames::pushDecision((300+depth) as u32,(400+depth) as u32,decision);
    assert(contains(returns,(100+depth) as u32));assert(!contains(returns,(200+depth) as u32));
    assert(contains(loops,(200+depth) as u32));assert(!contains(loops,(100+depth) as u32));
    var accepted=depth!=fail_at;
    if accepted && depth!=0 {accepted=nested(scope,returns,loops,decision,depth-1,fail_at);}
    let frame=blot_check_package_owner_frames::scope(scope);assert(frame.unit==7 && frame.decl==depth);
    let callback=blot_check_package_owner_frames::decision(decision);assert(callback.callback==300+depth && callback.ty==400+depth);
    blot_check_package_owner_frames::restoreDecisions(decision,prior_decision);
    blot_check_package_owner_frames::restoreControls(loops,prior_loop);
    blot_check_package_owner_frames::restoreControls(returns,prior_return);
    blot_check_package_owner_frames::restoreScopes(scope,prior_scope);
    return accepted;
}
fn main() {
    var scope:i64=0;var returns:i64=0;var loops:i64=0;var decision:i64=0;
    assert(blot_check_package_owner_frames::active()==0);
    for failure in [-1 as i64,0,2,5] {
        let accepted=nested(scope,returns,loops,decision,5,failure);
        assert(accepted==(failure<0));assert(scope==0 && returns==0 && loops==0 && decision==0);
        assert(blot_check_package_owner_frames::active()==0);
    }
    // Scope chains have no new fixed depth cap, and retain exact parent order.
    for ordinal in 0..513 {scope=blot_check_package_owner_frames::pushScope(9,ordinal as u32,scope);}
    var cursor=scope;var expected:i64=512;
    while cursor!=0 {let frame=blot_check_package_owner_frames::scope(cursor);assert(frame.unit==9 && frame.decl==expected);expected-=1;cursor=frame.parent;}
    assert(expected == -1);assert(blot_check_package_owner_frames::active()==513);
    blot_check_package_owner_frames::restoreScopes(scope,0);assert(blot_check_package_owner_frames::active()==0);
    // Temporarily masking closure controls must retain the outer frames.
    returns=blot_check_package_owner_frames::pushControl(41,0);
    loops=blot_check_package_owner_frames::pushControl(42,0);
    decision=blot_check_package_owner_frames::pushDecision(43,44,0);
    let outer_return=returns;let outer_loop=loops;let outer_decision=decision;
    returns=0;loops=0;decision=0;
    assert(!nested(scope,returns,loops,decision,3,1));
    assert(returns==0 && loops==0 && decision==0 && blot_check_package_owner_frames::active()==3);
    returns=outer_return;loops=outer_loop;decision=outer_decision;
    assert(contains(returns,41) && !contains(returns,42));assert(contains(loops,42));
    assert(blot_check_package_owner_frames::decision(decision).ty==44);
    blot_check_package_owner_frames::restoreControls(returns,0);
    blot_check_package_owner_frames::restoreControls(loops,0);
    blot_check_package_owner_frames::restoreDecisions(decision,0);
    // Freed slots can be reused without inheriting their former parent/data.
    scope=blot_check_package_owner_frames::pushScope(1,2,0);let reusable_slot=scope;
    blot_check_package_owner_frames::restoreScopes(scope,0);
    scope=blot_check_package_owner_frames::pushScope(3,4,0);
    assert(scope==reusable_slot);let frame=blot_check_package_owner_frames::scope(scope);
    assert(frame.unit==3 && frame.decl==4 && frame.parent==0);
    blot_check_package_owner_frames::restoreScopes(scope,0);
    assert(blot_check_package_owner_frames::active()==0);
    print("package owner frames passed:nesting,control separation,error cleanup,masking,reuse");
}
