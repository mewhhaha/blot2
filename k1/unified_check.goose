// Full source/shape/type and checked-add verifier; never accepts an unproved candidate.
namespace unified_check;
import unified_core;
import unified_guard;
fn verify(source:u8[:],p:unified_core::Program&) -> bool {return unified_guard::check(source,p).status==0;}
