// Scalar frame handles keep recursive package walkers free of stack references.
namespace blot_check_package_owner_frames;
struct Scope { unit:u32, decl:u32, parent:i64=0 }
struct Control { node:u32, parent:i64=0 }
struct Decision { callback:u32, ty:u32, parent:i64=0 }
reusable var scopes:Scope[>..];
reusable var controls:Control[>..];
reusable var decisions:Decision[>..];
var active_frames:i64=0;
fn active()->i64 { return active_frames; }
fn pushScope(unit:u32,decl:u32,parent:i64)->i64 {
    let id=scopes.alloc_index(Scope{unit:unit,decl:decl,parent:parent,..})+1;
    active_frames+=1; return id;
}
fn pushControl(node:u32,parent:i64)->i64 {
    let id=controls.alloc_index(Control{node:node,parent:parent,..})+1;
    active_frames+=1; return id;
}
fn pushDecision(callback:u32,ty:u32,parent:i64)->i64 {
    let id=decisions.alloc_index(Decision{callback:callback,ty:ty,parent:parent,..})+1;
    active_frames+=1; return id;
}
fn scope(id:i64)->Scope { assert(id!=0); return scopes[id-1]; }
fn control(id:i64)->Control { assert(id!=0); return controls[id-1]; }
fn decision(id:i64)->Decision { assert(id!=0); return decisions[id-1]; }
fn restoreScopes(head:i64&,prior:i64) {
    while head!=prior { assert(head!=0); let index=head-1; head=scopes[index].parent; scopes.free(index); active_frames-=1; }
}
fn restoreControls(head:i64&,prior:i64) {
    while head!=prior { assert(head!=0); let index=head-1; head=controls[index].parent; controls.free(index); active_frames-=1; }
}
fn restoreDecisions(head:i64&,prior:i64) {
    while head!=prior { assert(head!=0); let index=head-1; head=decisions[index].parent; decisions.free(index); active_frames-=1; }
}
