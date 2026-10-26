// Source-local adapter plan; none of these records or event offsets grant a
// live loan, trusted invocation region, machine ABI or checked target.
namespace m12_adapter_core;
import i08_link_core;
import i08_affine_core;
import i08_transition_core;
struct Event {kind:i64=0,site:i64=0}
struct Program {module:u8[]=[],split:i64=0,linked:i08_link_core::Program=i08_link_core::Program {},
 affine:i08_affine_core::Plan=i08_affine_core::Plan {},transition:i08_transition_core::Proof=i08_transition_core::Proof {},events:Event[]= []}
