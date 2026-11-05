namespace blot_backend_discarded_bindings;
import check.core;
import .optimizer_buffers;
import support.error;

var inactive_flags:blot_backend_optimizer_buffers::Flags=blot_backend_optimizer_buffers::Flags{..};
struct Proof { owner: blot_backend_optimizer_buffers::Flags& =inactive_flags, start: i64 = 0, len: i64 = 0 }
fn admits(proof: Proof&, binding: blot_check_core::BindingId) -> bool { binding < proof.len && proof.owner.items[proof.start + binding] }
fn mark(proof: Proof&, binding: blot_check_core::BindingId) { if binding < proof.len { proof.owner.items[proof.start + binding] = false; } }
fn init(unused: blot_backend_optimizer_buffers::Flags&, module: const blot_check_core::Module&, unit_id: u32) -> Proof,blot_error::Error {
    var proof = Proof { owner: unused, start: unused.len , ..}; var candidate = false;
    for node in module.nodes {
        if node.tag != blot_check_core::Tag.bind { continue; }
        let value = module.node(node.b);
        if value.tag == blot_check_core::Tag.product || value.tag == blot_check_core::Tag.record { candidate = true; break; }
    }
    if !candidate { return proof,blot_error::Error.none; }
    proof.len = module.bindings.len;if proof.len>0x7fffffffffffffff-proof.start {return proof,blot_error::Error.out_of_memory;}let grown=unused.resize(proof.start+proof.len,true);if grown!=blot_error::Error.none {return proof,grown;}
    for reference in module.references { if reference.unit == 0 || reference.unit == unit_id { mark(proof, reference.binding); } }
    for closure in module.closures { for binding in module.extra[closure.captures.start..closure.captures.start + closure.captures.len] { mark(proof, binding); } }
    for merge in module.merges { mark(proof, merge.then_binding); mark(proof, merge.else_binding); mark(proof, merge.result); }
    for carry in module.loop_carries { mark(proof, carry.incoming); mark(proof, carry.iteration); mark(proof, carry.backedge); mark(proof, carry.outgoing); }
    for request_loop in module.request_loops { for binding in module.extra[request_loop.completion_state_bindings.start..request_loop.completion_state_bindings.start + request_loop.completion_state_bindings.len] { mark(proof, binding); } }
    return proof,blot_error::Error.none;
}

fn values(proof: Proof&) -> const bool[:] { proof.owner.items[proof.start..proof.start + proof.len] }
