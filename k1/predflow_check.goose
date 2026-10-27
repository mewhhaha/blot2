// Full source, producer proof and independently re-evaluated successor safety.
// Private fixture only; no complete K1 fact policy or artifact authority.
namespace predflow_check;
import unified_core;
import predflow_guard;
import predflow_proof;
fn verify(source:u8[:],p:unified_core::Program&) -> bool {
    let built=predflow_guard::check(source,p);
    return built.status==0 && predflow_proof::verify_evidence(source,p,built.evidence);
}
