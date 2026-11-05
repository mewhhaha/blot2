namespace blot_backend_acyclic_layout;
import .layout;
import check.core;
import check.types;
import support.error;

let depth_limit: i64 = 128;
let default_budget: i64 = 65536;
fn proven(store: blot_backend_layout::Store&, units: const blot_check_core::Module[:], ty: blot_backend_layout::Id) -> bool, blot_error::Error {
    var active: blot_backend_layout::Id[128] = [0; 128]; var budget = default_budget; return within(store, units, ty, active, 0, budget);
}
recursive fn within(store: blot_backend_layout::Store&, units: const blot_check_core::Module[:], ty: blot_backend_layout::Id, active: blot_backend_layout::Id[:], depth: i64, budget: i64&) -> bool, blot_error::Error {
    if depth >= active.len || budget == 0 { return false, blot_error::Error.none; } budget--;
    for prior in active[..depth] { if prior == ty { return true, blot_error::Error.none; } } active[depth] = ty;
    let node = store.node(ty);
    if node.tag == blot_backend_layout::Tag.unit || node.tag == blot_backend_layout::Tag.boolean || node.tag == blot_backend_layout::Tag.unsigned32 || node.tag == blot_backend_layout::Tag.floating32 || node.tag == blot_backend_layout::Tag.never || node.tag == blot_backend_layout::Tag.type_constructor || node.tag == blot_backend_layout::Tag.resolver { return true, blot_error::Error.none; }
    if node.tag == blot_backend_layout::Tag.array || node.tag == blot_backend_layout::Tag.list { return within(store, units, node.a, active, depth + 1, budget); }
    if node.tag == blot_backend_layout::Tag.product || node.tag == blot_backend_layout::Tag.record {
        let count = store.children(ty).len; var index = 0; var step = 1; if node.tag == blot_backend_layout::Tag.record { index = 1; step = 2; }
        while index < count { let child = store.children(ty)[index]; let valid, error = within(store, units, child, active, depth + 1, budget); if error != blot_error::Error.none || !valid { return false, error; } index += step; } return true, blot_error::Error.none;
    }
    if node.tag == blot_backend_layout::Tag.nominal {
        if node.a == 0 || node.a > units.len { return false, blot_error::Error.none; } let source .= units[node.a - 1]; var found = false;
        for constructor in source.constructors {
            if budget == 0 { return false, blot_error::Error.none; } budget--;
            let nominal = source.nominal(constructor.nominal); if nominal.identity.unit != node.a || nominal.identity.decl != node.b { continue; } found = true;
            if constructor.payload == 0 { continue; } let parameters = source.types.list(nominal.parameters); let arguments = store.children(ty);
            if parameters.len != arguments.len || parameters.len > 32 { return false, blot_error::Error.none; }
            var mappings: blot_backend_layout::Mapping[32] = [blot_backend_layout::Mapping {}; 32];
            for parameter, index in parameters { if source.types.node(parameter).tag != blot_check_types::Tag.variable { return false, blot_error::Error.none; } mappings[index] = blot_backend_layout::Mapping { variable: parameter, layout: arguments[index] }; }
            let payload, payload_error = store.fromTypePartial(source, constructor.payload, mappings[..parameters.len]);
            if payload_error != blot_error::Error.none { if payload_error == blot_error::Error.out_of_memory { return false, payload_error; } return false, blot_error::Error.none; }
            let valid, error = within(store, units, payload, active, depth + 1, budget); if error != blot_error::Error.none || !valid { return false, error; }
        }
        return found, blot_error::Error.none;
    }
    return false, blot_error::Error.none;
}
