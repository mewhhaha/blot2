// Executable admission adds exact reachable bodies to semantic catalog proof.
namespace blot_reuse_code_body_validity;
import check.core;
import check.check;
import backend.runtime_identity;
import reuse.code_artifacts;
import reuse.principal_reuse_gate;
import reuse.declaration_projection;
import support.error;
import support.option;
type Error = blot_error::Error;
struct Gate { semantic: blot_reuse_principal_reuse_gate::Gate, exact: bool[:] = [] }
reusable[] var exact_flags: bool[>..] = [];
fn init(allocation_owner: u64, old: const blot_reuse_code_artifacts::Pools&, units: const blot_check_core::Module[:], names: blot_support::Option<blot_backend_runtime_identity::View>, stamps: blot_reuse_code_artifacts::ModuleStamps?) -> Gate, Error {
    let semantic, error = blot_reuse_principal_reuse_gate::initWithStamps(allocation_owner, old, units, names, stamps);
    if error != Error.none { return default<Gate>(), error; }
    var result = Gate { semantic, exact_flags.alloc_slice(semantic.dirty.len) , ..}; for &flag in result.exact { flag = false; }
    if semantic.enabled { for &module, unit in units { for binding, id in module.bindings {
        let target = blot_check_core::BindingRef { (unit + 1) as u32, id as u32 , ..};
        if binding.kind != blot_check_check::Kind.global || !semantic.admitsPrincipal(target) { continue; }
        var exact = semantic.structural_units[unit];
        if !exact { let same, failure = blot_reuse_declaration_projection::definitionEqual(old.modules[unit].module, module, id as u32); if failure != Error.none { result.deinit(); return default<Gate>(), failure; } exact = same; }
        result.exact[semantic.offsets[unit] + id] = exact;
    } } }
    return result, Error.none;
}
fn deinit(self: Gate&) {
    if self.exact.len != 0 { let first: const bool& = self.exact[0]; let at = exact_flags.index_of(first); assert(at >= 0); exact_flags.free_slice(exact_flags[at..at + self.exact.len]); }
    self.exact = []; self.semantic.deinit();
}
fn body(self: const Gate&, target: blot_check_core::BindingRef) -> bool { return self.semantic.admitsPrincipal(target) && self.exact[self.semantic.offsets[target.unit - 1] + target.binding]; }
fn catalog(self: const Gate&, unit: u32) -> bool { return self.semantic.enabled && unit != 0 && unit <= self.semantic.units.len; }
fn expressionRoot(self: const Gate&, unit: u32, root: u32) -> bool {
    if !self.catalog(unit) || root == 0 { return false; } let module = self.semantic.units[unit - 1]; if root >= module.nodes.len { return false; }
    for body in module.bodies { if body.root == root && self.body(blot_check_core::BindingRef { unit, body.binding , ..}) { return true; } }
    for closure, index in module.closures {
        if closure.body != root { continue; } if self.semantic.structural_units[unit - 1] { return true; }
        let owner = self.semantic.closure_owners[self.semantic.closure_offsets[unit - 1] + index]; if owner != 0 && self.body(blot_check_core::BindingRef { unit, owner , ..}) { return true; }
    } return false;
}
