// Full source, producer proof and independently re-evaluated successor safety.
// Private fixture only; no complete K1 fact policy or artifact authority.
namespace common_check;
import unified_core;
import common_guard;
import common_proof;
fn verify(source:u8[:],p:unified_core::Program&) -> bool {
    let built=common_guard::check(source,p);
    return built.status==0 && common_proof::verify_evidence(source,p,built.evidence);
}
