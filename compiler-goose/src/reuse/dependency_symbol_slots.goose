// A stored word has one role even when immutable lists overlap.
namespace blot_reuse_dependency_symbol_slots;
import check.core;
import check.types;
import check.parameter_patterns;
import check.capability_contracts;
import reuse.frozen_dependency;
import support.error;
type Error = blot_error::Error;
type List = blot_check_types::List;
type Tag = blot_check_types::Tag;
struct Slots { interface_types: u8[:], patterns: u8[:], core_types: u8[:], interface_capabilities: u8[:], core_capabilities: u8[:] }
reusable[] var owned_roles: u8[>..] = [];
fn deinit(self_: Slots&) {
    release(self_.interface_types); release(self_.patterns); release(self_.core_types); release(self_.interface_capabilities); release(self_.core_capabilities);
    self_ = default<Slots>();
}
fn release(values: u8[:]) { if values.len != 0 { owned_roles.free_slice(values); } }
fn mark(slots: u8[:], start: u32, len: u32, role: u8) -> Error {
    if start > slots.len || len > slots.len - start { return blot_error::Error.invalid_artifact; }
    for &old in slots[start..start + len] { if old != 0 && old != role { return blot_error::Error.invalid_artifact; } old = role; }
    return blot_error::Error.none;
}
fn list(slots: u8[:], value: List, role: u8) -> Error { return mark(slots, value.start, value.len, role); }
fn scheme(slots: u8[:], value: blot_check_types::Scheme) -> Error {
    { let propagated_error = list(slots, value.variables, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(slots, value.row_variables, 2); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = list(slots, value.closed_rows, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(slots, value.generative, 2); if propagated_error != blot_error::Error.none { return propagated_error; } }
    return blot_error::Error.none;
}
fn graph(slots: u8[:], nodes: const blot_check_types::Node[:], extra: const u32[:], operations: const blot_check_types::Operation[:]) -> Error {
    for node in nodes {
        match node.tag {
            record => {
                if node.b > 0x7fffffff { return blot_error::Error.invalid_artifact; }
                let width = node.b * 2;
                if node.a > slots.len || width > slots.len - node.a { return blot_error::Error.invalid_artifact; }
                for index in 0..node.b { { let propagated_error = mark(slots, node.a + (index * 2) as u32, 1, 1); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = mark(slots, node.a + (index * 2 + 1) as u32, 1, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } }
            },
            product => { { let propagated_error = mark(slots, node.a, node.b, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } },
            nominal, projection, instance_selection => {
                if node.c >= extra.len || node.c == 0xffffffff { return blot_error::Error.invalid_artifact; }
                { let propagated_error = mark(slots, node.c, 1, 2); if propagated_error != blot_error::Error.none { return propagated_error; } }
                let start = node.c + 1; { let propagated_error = mark(slots, start, extra[node.c], 2); if propagated_error != blot_error::Error.none { return propagated_error; } }
                if node.tag == blot_check_types::Tag.projection {
                    if extra[node.c] > 0xffffffff - start { return blot_error::Error.invalid_artifact; }
                    { let propagated_error = mark(slots, start + extra[node.c], 1, 1); if propagated_error != blot_error::Error.none { return propagated_error; } }
                }
            }, _ => {},
        }
    }
    for operation in operations { { let propagated_error = list(slots, operation.arguments, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    return blot_error::Error.none;
}
fn implementationLists<O>(slots: u8[:], owner: const O&) -> Error {
    for value in owner.implementations {
        { let propagated_error = list(slots, value.head, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(slots, value.variables, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(slots, value.parameter_names, 1); if propagated_error != blot_error::Error.none { return propagated_error; } }
        { let propagated_error = list(slots, value.row_variables, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(slots, value.row_parameter_names, 1); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(slots, value.row_parameters, 2); if propagated_error != blot_error::Error.none { return propagated_error; } }
    }
    for value in owner.member_templates { { let propagated_error = list(slots, value.arguments, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    for value in owner.selected_proofs { { let propagated_error = list(slots, value.arguments, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    return blot_error::Error.none;
}
fn coreRoles(slots: u8[:], ir: const blot_check_core::Module&) -> Error {
    for &slot in slots { slot = 0; }
    { let propagated_error = graph(slots, ir.types.nodes, ir.types.extra, ir.types.operations); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = implementationLists(slots, ir); if propagated_error != blot_error::Error.none { return propagated_error; } }
    for value in ir.bindings { { let propagated_error = scheme(slots, value.scheme); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    for value in ir.bodies { { let propagated_error = scheme(slots, value.scheme); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(slots, value.closed_rows, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    for value in ir.constructors { { let propagated_error = scheme(slots, value.scheme); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    for value in ir.contracts {
        { let propagated_error = list(slots, value.parameters, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(slots, value.variables, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(slots, value.row_variables, 2); if propagated_error != blot_error::Error.none { return propagated_error; } }
        { let propagated_error = list(slots, value.row_parameter_names, 1); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(slots, value.row_parameters, 2); if propagated_error != blot_error::Error.none { return propagated_error; } }
    }
    for value in ir.nominals { { let propagated_error = list(slots, value.parameters, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(slots, value.variables, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    for value in ir.closures { { let propagated_error = list(slots, value.closed_rows, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    for value in ir.operation_values { { let propagated_error = list(slots, value.arguments, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    return blot_error::Error.none;
}
fn capabilityRoles(roles: u8[:], owner: blot_check_capability_contracts::Collection) -> Error {
    for &role in roles { role = 0; }
    for node in owner.nodes {
        match node.tag {
            captures, product, join => { { let propagated_error = mark(roles, node.a, node.b, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } },
            record => {
                if node.b % 2 != 0 { return blot_error::Error.invalid_artifact; }
                for index in 0..node.b / 2 {
                    if index * 2 + 1 > 0xffffffff - node.a { return blot_error::Error.invalid_artifact; }
                    { let propagated_error = mark(roles, node.a + (index * 2) as u32, 1, 1); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = mark(roles, node.a + (index * 2 + 1) as u32, 1, 2); if propagated_error != blot_error::Error.none { return propagated_error; } }
                }
            }, _ => {},
        }
    }
    return blot_error::Error.none;
}
fn collect(owner: const blot_reuse_frozen_dependency::Module&) -> Slots, Error {
    let iface .= owner.interface; let ir .= owner.core;
    var slots = Slots { owned_roles.alloc_slice(iface.graph.extra.len), owned_roles.alloc_slice(iface.patterns.extra.len), owned_roles.alloc_slice(ir.types.extra.len), owned_roles.alloc_slice(iface.capability_contracts.words.len), owned_roles.alloc_slice(ir.capability_contracts.words.len) , ..};
    for &slot in slots.interface_types { slot = 0; } for &slot in slots.patterns { slot = 0; } for &slot in slots.core_types { slot = 0; }
    let error = collectInto(owner, slots);
    if error != blot_error::Error.none { slots.deinit(); return Slots { [], [], [], [], [] , ..}, error; }
    return slots, blot_error::Error.none;
}
fn collectInto(owner: const blot_reuse_frozen_dependency::Module&, slots: Slots&) -> Error {
    let iface .= owner.interface;
    let a = slots.interface_types; let b = slots.patterns;
    { let propagated_error = graph(a, iface.graph.nodes, iface.graph.extra, iface.graph.operations); if propagated_error != blot_error::Error.none { return propagated_error; } }
    for value in iface.bindings { { let propagated_error = scheme(a, value.scheme); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    for value in iface.constructors { { let propagated_error = scheme(a, value.scheme); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    for value in iface.nominals {
        { let propagated_error = list(a, value.parameters, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(a, value.variables, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(a, value.parameter_names, 1); if propagated_error != blot_error::Error.none { return propagated_error; } }
        { let propagated_error = list(a, value.constructors, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(a, value.alias_rows, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(b, value.patterns, 2); if propagated_error != blot_error::Error.none { return propagated_error; } }
    }
    for value in iface.effect_families {
        { let propagated_error = list(a, value.parameters, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(a, value.variables, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(a, value.parameter_names, 1); if propagated_error != blot_error::Error.none { return propagated_error; } }
        { let propagated_error = list(a, value.operations, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(b, value.patterns, 2); if propagated_error != blot_error::Error.none { return propagated_error; } }
    }
    for value in iface.contracts {
        { let propagated_error = list(a, value.parameters, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(a, value.variables, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(a, value.parameter_names, 1); if propagated_error != blot_error::Error.none { return propagated_error; } }
        { let propagated_error = list(a, value.row_variables, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(a, value.row_parameter_names, 1); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(a, value.row_parameters, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = list(b, value.patterns, 2); if propagated_error != blot_error::Error.none { return propagated_error; } }
    }
    { let propagated_error = implementationLists(a, iface); if propagated_error != blot_error::Error.none { return propagated_error; } }
    for node in iface.patterns.nodes {
        match node.kind {
            binding => {},
            tuple, array => { { let propagated_error = mark(b, node.a, node.b, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } },
            record => {
                if node.b > 0x7fffffff { return blot_error::Error.invalid_artifact; }
                let width = node.b * 2; if node.a > b.len || width > b.len - node.a { return blot_error::Error.invalid_artifact; }
                for index in 0..node.b { { let propagated_error = mark(b, node.a + (index * 2) as u32, 1, 1); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = mark(b, node.a + (index * 2 + 1) as u32, 1, 2); if propagated_error != blot_error::Error.none { return propagated_error; } } }
            },
        }
    }
    { let propagated_error = coreRoles(slots.core_types, owner.core); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = capabilityRoles(slots.interface_capabilities, iface.capability_contracts); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = capabilityRoles(slots.core_capabilities, owner.core.capability_contracts); if propagated_error != blot_error::Error.none { return propagated_error; } }
    return blot_error::Error.none;
}
fn rewrite(extra: u32[:], slots: const u8[:], symbols: const u32[:]) {
    assert(extra.len == slots.len);
    for &word, index in extra { if slots[index] == 1 { word = symbols[word]; } }
}
