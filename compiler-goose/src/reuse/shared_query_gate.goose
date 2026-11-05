// Share only an already checked exact owner pair within one compile epoch.
namespace blot_reuse_shared_query_gate;
import check.core;
import reuse.code_artifacts;
import reuse.principal_reuse_gate;
import support.option;
type Gate = blot_reuse_principal_reuse_gate::Gate;
fn share(allocation_owner: u64, old: const blot_reuse_code_artifacts::Pools&,
    units: const blot_check_core::Module[:], checked: const Gate&) -> blot_support::Option<Gate> {
    if allocation_owner == 0 || checked.allocation_owner != allocation_owner ||
        checked.source_pools .!= old || !blot_support::same_slice_identity(checked.units, units) { return blot_support::none<Gate>(); }
    if checked.structural_units.len != units.len || checked.offsets.len != units.len + 1 ||
        checked.offsets[0] != 0 || checked.offsets[units.len] != checked.dirty.len { return blot_support::none<Gate>(); }
    for unit, index in units {
        if checked.offsets[index] > checked.offsets[index + 1] || checked.offsets[index + 1] - checked.offsets[index] != unit.bindings.len {
            return blot_support::none<Gate>();
        }
    }
    return blot_support::some(checked.retain());
}
fn validationBytes(gate: const Gate&) -> i64 {
    return gate.structural_units.len + gate.certified_images.len + gate.dirty.len + gate.local_dirty.len + gate.call_origins.len +
        (gate.offsets.len + gate.closure_offsets.len) * 8 + gate.closure_owners.len * 4;
}
