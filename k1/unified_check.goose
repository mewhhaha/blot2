// Full source, producer proof and independently re-evaluated successor safety.
// Private fixture only; no complete K1 fact policy or artifact authority.
namespace unified_check;
import unified_core;
import unified_guard;
import refinement_guard_verify;
fn verify(source:u8[:],p:unified_core::Program&) -> bool {
    return unified_guard::check(source,p).status==0 && refinement_guard_verify::check(source,p);
}
