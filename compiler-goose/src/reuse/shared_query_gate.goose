// Share only an already checked exact owner pair within one compile epoch.
namespace blot_reuse_shared_query_gate;
import check.core;
import reuse.code_artifacts;
import reuse.principal_reuse_gate;
import support.option;
import backend.runtime_identity;
type Gate = blot_reuse_principal_reuse_gate::Gate;
fn share(allocation_owner: u64, old: const blot_reuse_code_artifacts::Pools&,
    units: const blot_check_core::Module[:], names:blot_support::Option<blot_backend_runtime_identity::View>, checked: const Gate&) -> blot_support::Option<Gate> {
    if allocation_owner == 0 || checked.allocation_owner != allocation_owner ||
        checked.source_pools .!= old || !blot_support::same_slice_identity(checked.units, units) { return blot_support::none<Gate>(); }
    if checked.structural_units.len != units.len || checked.offsets.len != units.len + 1 ||
        checked.offsets[0] != 0 || checked.offsets[units.len] != checked.dirty.len { return blot_support::none<Gate>(); }
    for unit, index in units {
        if checked.offsets[index] > checked.offsets[index + 1] || checked.offsets[index + 1] - checked.offsets[index] != unit.bindings.len {
            return blot_support::none<Gate>();
        }
    }
    if checked.validation_names.present {
        if !names.present {return blot_support::none<Gate>();}
        let old_names=checked.validation_names.value;let current=names.value;
        if !blot_support::same_slice_identity(old_names.bytes,current.bytes)||!blot_support::same_slice_identity(old_names.symbols,current.symbols)||!blot_support::same_slice_identity(old_names.owners,current.owners) {return blot_support::none<Gate>();}
    }
    var retained=checked.retainOwned();retained.units=units;retained.source_pools .=old;
    if checked.validation_names.present {retained.validation_names=names;}
    return blot_support::Option<Gate>{true,retained};
}
fn validationBytes(gate: const Gate&) -> i64 {
    return gate.structural_units.len + gate.certified_images.len + gate.dirty.len + gate.local_dirty.len + gate.call_origins.len +
        (gate.offsets.len + gate.closure_offsets.len) * 8 + gate.closure_owners.len * 4;
}
