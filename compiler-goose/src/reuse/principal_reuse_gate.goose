// Principal proof admission owns immutable flags, never executable values.
namespace blot_reuse_principal_reuse_gate;
import std;
import dictionary;
import check.core;
import check.types;
import check.check;
import check.frozen_core_validation;
import check.package_core;
import backend.runtime_identity;
import reuse.code_artifacts;
import reuse.declaration_origins;
import reuse.declaration_dependencies;
import reuse.declaration_projection;
import reuse.dependency_certificate;
import reuse.source_value_template;
import support.error;
import support.option;
import support.structural;
type Error = blot_error::Error;
type Module = blot_check_core::Module;
type BindingRef = blot_check_core::BindingRef;
type View = blot_backend_runtime_identity::View;
type Pools = blot_reuse_code_artifacts::Pools;
struct Gate {
    constant_types: bool = false, has_generative_sources: bool = false,
    allocation_owner: u64 = 0, units: const Module[:] = default<const Module[:]>(), source_pools: const Pools? = null,
    enabled: bool = false, dependency_validations: i64 = 0, reused_dependency_validations: i64 = 0,
    projection_scans: i64 = 0, projection_visits: i64 = 0, projection_workspace_peak_bytes: i64 = 0,
    dependencies_validated: bool = false, validation_symbols: i64 = 0,
    validation_names: blot_support::Option<View>,
    structural_units: const bool[:] = default<const bool[:]>(), certified_images: const bool[:] = default<const bool[:]>(),
    closure_owners: const u32[:] = default<const u32[:]>(), closure_offsets: const i64[:] = default<const i64[:]>(), offsets: const i64[:] = default<const i64[:]>(),
    dirty: const bool[:] = default<const bool[:]>(), local_dirty: const bool[:] = default<const bool[:]>(), call_origins: const bool[:] = default<const bool[:]>(),
    storage: u32 = 0, generation: u64 = 0,
}
struct Storage { references: u64 = 0, generation: u64 = 0 }
reusable[] var storage: Storage[>..] = [];
reusable[] var bits: bool[>..] = [];
reusable[] var sizes: i64[>..] = [];
reusable[] var words: u32[>..] = [];
var next_generation: u64 = 1;
fn release(run: const bool[:]) { if run.len != 0 { bits.free_slice(run); } }
fn release(run: const i64[:]) { if run.len != 0 { sizes.free_slice(run); } }
fn release(run: const u32[:]) { if run.len != 0 { words.free_slice(run); } }
fn live(self_: const Gate&) -> bool {
    return self_.storage != 0 && self_.storage <= storage.len && storage[self_.storage - 1].references != 0 && storage[self_.storage - 1].generation == self_.generation;
}
fn retain(self_: const Gate&) -> Gate {
    assert(self_.live()); assert(storage[self_.storage - 1].references != 0xffffffffffffffff);
    storage[self_.storage - 1].references++; var result = self_;
    result.dependency_validations = 0; result.reused_dependency_validations = 0;
    result.projection_scans = 0; result.projection_visits = 0; result.projection_workspace_peak_bytes = 0;
    return result;
}
fn deinit(self_: Gate&) {
    assert(self_.live()); let at = self_.storage - 1; storage[at].references--;
    if storage[at].references == 0 {
        release(self_.structural_units); release(self_.certified_images); release(self_.closure_owners);
        release(self_.closure_offsets); release(self_.offsets); release(self_.dirty); release(self_.local_dirty); release(self_.call_origins);
        storage.free(at);
    }
    self_ = Gate {..};
}
fn init(allocation_owner: u64, old: const Pools&, units: const Module[:], names: blot_support::Option<View>) -> Gate, Error {
    return initWithStamps(allocation_owner, old, units, names, null);
}
fn initWithStamps(allocation_owner: u64, old: const Pools&, units: const Module[:], names: blot_support::Option<View>, stamps: blot_reuse_code_artifacts::ModuleStamps?) -> Gate, Error {
    return initMode(allocation_owner, old, units, names, stamps, false);
}
fn initConstantReceipts(allocation_owner: u64, old: const Pools&, units: const Module[:], names: blot_support::Option<View>, stamps: blot_reuse_code_artifacts::ModuleStamps?) -> Gate, Error {
    return initMode(allocation_owner, old, units, names, stamps, true);
}
fn initMode(allocation_owner: u64, old: const Pools&, units: const Module[:], names: blot_support::Option<View>, stamps: blot_reuse_code_artifacts::ModuleStamps?, constant_types: bool) -> Gate, Error {
    if units.len == 0x7fffffffffffffff || next_generation == 0xffffffffffffffff || storage.len >= 0xffffffff { return Gate {..}, blot_error::Error.out_of_memory; }
    var binding_count: i64 = 0; var closure_count: i64 = 0;
    for module in units {
        if module.bindings.len > 0x7fffffffffffffff - binding_count || module.closures.len > 0x7fffffffffffffff - closure_count { return Gate {..}, blot_error::Error.out_of_memory; }
        binding_count += module.bindings.len; closure_count += module.closures.len;
    }
    let structural = bits.alloc_slice(units.len); let certified = bits.alloc_slice(units.len);
    let dirty = bits.alloc_slice(binding_count); let local_dirty = bits.alloc_slice(binding_count); let origins = bits.alloc_slice(binding_count);
    let offsets = sizes.alloc_slice(units.len + 1); let closure_offsets = sizes.alloc_slice(units.len + 1);
    let closures = words.alloc_slice(closure_count);
    for &flag in structural { flag = false; } for &flag in certified { flag = false; }
    for &flag in dirty { flag = false; } for &flag in local_dirty { flag = true; } for &flag in origins { flag = false; }
    for &owner in closures { owner = 0; } offsets[0] = 0; closure_offsets[0] = 0;
    for module, index in units { offsets[index + 1] = offsets[index] + module.bindings.len; closure_offsets[index + 1] = closure_offsets[index] + module.closures.len; }
    let generation = next_generation; next_generation++;
    let slot = storage.alloc_index(Storage { 1, generation , ..});
    var result = Gate { constant_types: constant_types, allocation_owner: allocation_owner, units: units, source_pools: old,
        structural_units: structural, certified_images: certified, closure_owners: closures, closure_offsets: closure_offsets,
        offsets: offsets, dirty: dirty, local_dirty: local_dirty, call_origins: origins, storage: (slot + 1) as u32, generation: generation , ..};
    let error = initialize(result, old, names, stamps, structural, certified, closures, dirty, local_dirty, origins);
    if error != blot_error::Error.none { result.deinit(); return Gate {..}, error; }
    return result, blot_error::Error.none;
}
fn initialize(result: Gate&, old: const Pools&, names: blot_support::Option<View>, stamps: blot_reuse_code_artifacts::ModuleStamps?,
    structural: bool[:], certified: bool[:], closures: u32[:], dirty: bool[:], local_dirty: bool[:], origins: bool[:]) -> Error {
    let units = result.units;
    if !old.project_identity || !old.identity.present || !names.present || old.modules.len != units.len || units.len == 0 || units.len >= 0xffffffff { return blot_error::Error.none; }
    for module, index in units { if module.unit != 0 && module.unit != index + 1 { return blot_error::Error.none; } }
    for &pin, index in old.modules {
        let intact, error = blot_reuse_code_artifacts::pinIntact(pin, stamps); if error != blot_error::Error.none { return error; }
        if !intact || (pin.module.unit != 0 && pin.module.unit != index + 1) { return blot_error::Error.none; }
    }
    for &module, unit in units {
        result.has_generative_sources = result.has_generative_sources || blot_reuse_source_value_template::moduleGenerative(module) || blot_reuse_source_value_template::moduleGenerative(old.modules[unit].module);
    }
    let previous = old.identity.value.view(); let current = names.value;
    if !namespaceEqual(old, units, previous, current) { return blot_error::Error.none; }
    var all_structural = true;
    for &module, unit in units {
        let pin = old.modules[unit]; var exact = false;
        if stamps { let found, error = stamps.proveSame(pin.module, module); if error != blot_error::Error.none { return error; } exact = found; }
        structural[unit] = exact || moduleEqual(pin.module, module); certified[unit] = exact; all_structural = all_structural && structural[unit];
    }
    if !all_structural { for &module, unit in units { if !structural[unit] && !catalogEqual(old.modules[unit].module, module, result.constant_types) { return blot_error::Error.none; } } }
    var old_units: blot_check_frozen_core_validation::ModuleRef[>..<] = [];
    var current_units: blot_check_frozen_core_validation::ModuleRef[>..<] = [];
    for &module, unit in units { old_units.push(blot_check_frozen_core_validation::ModuleRef { old.modules[unit].module , ..}); current_units.push(blot_check_frozen_core_validation::ModuleRef { module , ..}); }
    let old_context = blot_check_frozen_core_validation::Context { units: old_units[..], symbol_count: blot_support::some(previous.symbols.len) , ..};
    let current_context = blot_check_frozen_core_validation::Context { units: current_units[..], symbol_count: blot_support::some(current.symbols.len) , ..};
    let equivalent_context = blot_check_frozen_core_validation::equivalentContext(old_context, current_context, old_units[..], current_units[..]);
    var certified_context = false; var same_context = false;
    if old.dependency_certificate.present {
        certified_context = old.dependency_certificate.value.matches(old_context, previous, old_units[..]);
        if !certified_context { same_context = old.dependency_certificate.value.sameContext(old_context, previous, old.modules); }
    }
    for &module, unit in units {
        let pin = old.modules[unit];
        if same_context || (certified_context && old.dependency_certificate.value.admits(unit, pin)) { result.reused_dependency_validations++; }
        else {
            certified[unit] = false; result.dependency_validations++;
            let valid, error = validDependencies(pin.module, old_units[..], previous.symbols.len); if error != blot_error::Error.none { return error; } if !valid { return blot_error::Error.none; }
        }
        if !structural[unit] || !equivalent_context {
            result.dependency_validations++;
            let valid, error = validDependencies(module, current_units[..], current.symbols.len); if error != blot_error::Error.none { return error; } if !valid { return blot_error::Error.none; }
        }
    }
    result.dependencies_validated = true; result.validation_symbols = current.symbols.len; result.validation_names = names;
    for &module, unit in units {
        let error = blot_reuse_declaration_origins::mark(old.modules[unit].module, module, origins[result.offsets[unit]..result.offsets[unit + 1]]); if error != blot_error::Error.none { return error; }
    }
    for module, unit in units {
        for binding, index in module.bindings[1..] {
            let id = (index + 1) as u32;
            if binding.kind == blot_reuse_principal_interface::Kind.global && binding.body_id == 0 { return blot_error::Error.none; }
            if binding.kind == blot_reuse_principal_interface::Kind.external && !result.declaration(BindingRef { (unit + 1) as u32, id , ..}).present { return blot_error::Error.none; }
        }
        for reference in module.dependency_references { var target = reference; if target.unit == 0 { target.unit = (unit + 1) as u32; } if !result.declaration(target).present { return blot_error::Error.none; } }
        for candidate in module.associated { var target = candidate.target; if target.unit == 0 { target.unit = (unit + 1) as u32; } if !result.declaration(target).present { return blot_error::Error.none; } }
    }
    var reached: u32[>..<] = [];
    for &module, unit in units {
        let pin = old.modules[unit];
        if !structural[unit] {
            for &flag in dirty[result.offsets[unit]..result.offsets[unit + 1]] { flag = true; }
            let error = blot_reuse_declaration_projection::withWorkspace(pin.module, ProjectContext { result, module, unit, dirty, origins, closures, reached , ..}, projectUnit);
            if error != blot_error::Error.none { return error; }
            continue;
        }
        for node, id in module.nodes {
            if node.a == pin.module.nodes[id].a { continue; }
            let owner = scalarRoot(module, id as u32); if !owner.present { return blot_error::Error.none; } dirty[result.offsets[unit] + owner.value] = true;
        }
    }
    for flag, index in dirty { local_dirty[index] = flag; }
    propagateReferences(result, dirty); let error = dirtySelections(result, dirty); if error != blot_error::Error.none { return error; }
    result.enabled = true; return blot_error::Error.none;
}
// A named callback returns locally so Workspace's lexical cleanup always runs.
struct ProjectContext { gate: Gate&, module: const Module&, unit: i64, dirty: bool[:], origins: bool[:], closures: u32[:], reached: u32[>..<]& }
fn projectUnit(context: ProjectContext, workspace: blot_reuse_declaration_projection::Workspace&) -> Error {
    let gate .= context.gate; let module .= context.module; let unit = context.unit;
    let dirty = context.dirty; let origins = context.origins; let closures = context.closures; let reached .= context.reached;
    let pin = gate.source_pools.modules[unit]; var failure = blot_error::Error.none;
    for binding, index in module.bindings[1..] {
        let id = (index + 1) as u32; reached.clear(); var same = false;
        match binding.kind {
            global => { let found, error = workspace.definitionEqualWithOrigins(pin.module, module, id, reached, gate.constant_types, origins[gate.offsets[unit]..gate.offsets[unit + 1]]); if error != blot_error::Error.none { failure = error; break; } same = found; },
            external => { same = id < pin.module.bindings.len && blot_structural::equal(pin.module.bindings[id], binding); },
            _ => {},
        }
        dirty[gate.offsets[unit] + id] = !same;
        if same { for closure in reached { closures[gate.closure_offsets[unit] + closure] = id; } }
    }
    gate.projection_scans += workspace.scans; gate.projection_visits += workspace.visits;
    gate.projection_workspace_peak_bytes = max(gate.projection_workspace_peak_bytes, workspace.capacityBytes()); return failure;
}
fn admits(self_: const Gate&, target: BindingRef) -> bool {
    if !self_.enabled || target.unit == 0 || target.unit > self_.units.len || target.binding == 0 { return false; }
    if !self_.structural_units[target.unit - 1] { return false; } return self_.admitsPrincipal(target);
}
fn admitsCatalog(self_: const Gate&, pools: const Pools&, unit: u32) -> bool {
    return self_.enabled && self_.source_pools .== pools && unit != 0 && unit <= pools.modules.len && unit <= self_.units.len;
}
fn admitsPrincipal(self_: const Gate&, target: BindingRef) -> bool {
    if !self_.enabled || target.unit == 0 || target.unit > self_.units.len || target.binding == 0 { return false; }
    let module = self_.units[target.unit - 1]; if target.binding >= module.bindings.len { return false; }
    let binding = module.bindings[target.binding]; return binding.kind == blot_reuse_principal_interface::Kind.global && binding.body_id != 0 && !self_.dirty[self_.offsets[target.unit - 1] + target.binding];
}
fn admitsReceipt<R>(self_: const Gate&, record: const R&) -> bool {
    for source in record.sources { if !self_.admits(source) { return false; } }
    for read in record.scalar_reads { if !self_.admits(read.target) { return false; } }
    for read in record.call_reads { if !self_.admits(BindingRef { read.unit, read.binding , ..}) { return false; } }
    for call in record.call_publications { if !self_.admits(BindingRef { call.unit, call.binding , ..}) { return false; } } return true;
}
fn admitsLocalSource(self_: const Gate&, target: BindingRef) -> bool { return self_.admitsCallIdentity(target) && !self_.local_dirty[self_.offsets[target.unit - 1] + target.binding]; }
fn admitsCheckedInterface(self_: const Gate&, target: BindingRef) -> bool { return self_.checkedInterfaceEqual(target, true); }
fn checkedInterfaceEqual(self_: const Gate&, target: BindingRef, functions_only: bool) -> bool {
    if self_.constant_types || !self_.admitsCallIdentity(target) { return false; }
    let old .= self_.source_pools.modules[target.unit - 1].module; let current: const Module& = self_.units[target.unit - 1];
    let before .= old.body(target.binding); let after .= current.body(target.binding); assert(before && after);
    let left = old.binding(target.binding); let right = current.binding(target.binding);
    if (functions_only && (!before.is_function || !after.is_function)) || !blot_structural::equal(left.scheme, right.scheme) || left.has_explicit != right.has_explicit || before.parameters.len != after.parameters.len ||
        !blot_structural::equal(old.types.list(left.public_variables), current.types.list(right.public_variables)) || !blot_structural::equal(old.types.list(left.public_rows), current.types.list(right.public_rows)) ||
        !blot_structural::equal(old.types.list(before.closed_rows), current.types.list(after.closed_rows)) { return false; }
    if !blot_reuse_declaration_projection::parameterHeadersEqual(old, before, current, after) { return false; }
    return blot_structural::equal(old.obligations[left.scheme.obligations.start..left.scheme.obligations.start + left.scheme.obligations.len], current.obligations[right.scheme.obligations.start..right.scheme.obligations.start + right.scheme.obligations.len]);
}
fn admitsCompletedInterface(self_: const Gate&, target: BindingRef) -> bool, Error {
    if !self_.checkedInterfaceEqual(target, false) { return false, blot_error::Error.none; }
    let current: const Module& = self_.units[target.unit - 1]; let scheme = current.binding(target.binding).scheme;
    let body .= current.body(target.binding); assert(body); var needs_proof = !body.is_function;
    for requirement in current.obligations[scheme.obligations.start..scheme.obligations.start + scheme.obligations.len] { needs_proof = needs_proof || !requirement.explicit; }
    if needs_proof {
        var owners: blot_check_frozen_core_validation::ModuleRef[>..<] = []; for &module in self_.units { owners.push(blot_check_frozen_core_validation::ModuleRef { module , ..}); }
        var remaining: i64 = 65536;
        let error = blot_check_package_core::checkedInterfaceBody(current, target.binding, blot_check_frozen_core_validation::Context { units: owners[..] , ..}, remaining);
        if error == blot_error::Error.out_of_memory { return false, error; } if error != blot_error::Error.none { return false, blot_error::Error.none; }
    }
    return true, blot_error::Error.none;
}
fn admitsClosure(self_: const Gate&, unit: u32, catalog: u32) -> bool {
    if !self_.enabled || unit == 0 || unit > self_.units.len || catalog >= self_.units[unit - 1].closures.len { return false; }
    if self_.structural_units[unit - 1] { return true; } let owner = self_.closure_owners[self_.closure_offsets[unit - 1] + catalog];
    return owner != 0 && self_.admitsLocalSource(BindingRef { unit, owner , ..});
}
enum IdentityFailure { none, disabled, bounds, kind, binding_type, source_position, declaration_origin, body, scheme_root, scheme, flags }
fn admitsCallIdentity(self_: const Gate&, target: BindingRef) -> bool { return self_.callIdentityFailure(target) == IdentityFailure.none; }
fn callIdentityFailure(self_: const Gate&, target: BindingRef) -> IdentityFailure {
    if !self_.enabled { return IdentityFailure.disabled; } if target.unit == 0 || target.unit > self_.units.len || target.binding == 0 { return IdentityFailure.bounds; }
    let current: const Module& = self_.units[target.unit - 1]; let old .= self_.source_pools.modules[target.unit - 1].module;
    if target.binding >= current.bindings.len || target.binding >= old.bindings.len { return IdentityFailure.bounds; }
    let left = old.binding(target.binding); let right = current.binding(target.binding);
    if left.kind != blot_reuse_principal_interface::Kind.global || right.kind != blot_reuse_principal_interface::Kind.global { return IdentityFailure.kind; }
    if left.ty != right.ty && (!self_.constant_types || !blot_reuse_declaration_projection::equalConstantType(old.types, left.ty, current.types, right.ty)) { return IdentityFailure.binding_type; }
    let before .= old.body(target.binding); let after .= current.body(target.binding); if !before || !after { return IdentityFailure.body; }
    if before.declaration_name.len != 0 || after.declaration_name.len != 0 { if !self_.call_origins[self_.offsets[target.unit - 1] + target.binding] { return IdentityFailure.declaration_origin; } }
    else if old.sourceNamePoint(target.binding) != current.sourceNamePoint(target.binding) { return IdentityFailure.source_position; }
    var scheme = before.scheme;
    if scheme.root != after.scheme.root { if !self_.constant_types || !blot_reuse_declaration_projection::equalConstantType(old.types, scheme.root, current.types, after.scheme.root) { return IdentityFailure.scheme_root; } scheme.root = after.scheme.root; }
    if before.runtime != after.runtime || before.is_function != after.is_function { return IdentityFailure.flags; }
    if blot_structural::equal(scheme, after.scheme) { return IdentityFailure.none; } return IdentityFailure.scheme;
}
fn admitsRefinement<R>(self_: const Gate&, record: const R&) -> bool {
    for source in record.sources { if !self_.admitsLocalSource(source) { return false; } }
    for read in record.scalar_reads { if !self_.admits(read.target) { return false; } }
    for read in record.call_reads { let target = BindingRef { read.unit, read.binding , ..}; if read.present { if !self_.admitsCallIdentity(target) { return false; } } else if !self_.admitsLocalSource(target) { return false; } }
    for call in record.call_publications { if !self_.admitsLocalSource(BindingRef { call.unit, call.binding , ..}) { return false; } } return true;
}
fn freezeValidation(self_: const Gate&, pins: const blot_reuse_code_artifacts::ModulePin[:]) -> blot_support::Option<blot_reuse_dependency_certificate::Certificate>, Error {
    if !self_.dependencies_validated || pins.len != self_.units.len || !self_.validation_names.present { return blot_support::none<blot_reuse_dependency_certificate::Certificate>(), blot_error::Error.none; }
    var units: blot_check_frozen_core_validation::ModuleRef[>..<] = [];
    for pin, index in pins { let module: const Module& = self_.units[index]; if pin.module .!= module { return blot_support::none<blot_reuse_dependency_certificate::Certificate>(), blot_error::Error.none; } units.push(blot_check_frozen_core_validation::ModuleRef { module , ..}); }
    var previous: const blot_reuse_dependency_certificate::Certificate? = null;
    if self_.source_pools && self_.source_pools.dependency_certificate.present { previous .= self_.source_pools.dependency_certificate.value; }
    let certificate, error = blot_reuse_dependency_certificate::captureReusing(blot_check_frozen_core_validation::Context { units: units[..], symbol_count: blot_support::some(self_.validation_symbols) , ..}, pins, self_.validation_names.value, previous, self_.certified_images);
    return certificate, error;
}
fn targetDirty(self_: const Gate&, owner: i64, target: BindingRef) -> bool { var unit = owner; if target.unit != 0 { unit = target.unit - 1; } return self_.dirty[self_.offsets[unit] + target.binding]; }
fn declaration(self_: const Gate&, initial: BindingRef) -> blot_support::Option<BindingRef> {
    var target = initial; var remaining = self_.dirty.len;
    while remaining != 0 {
        remaining--; if target.unit == 0 || target.unit > self_.units.len || target.binding == 0 { return blot_support::none<BindingRef>(); }
        let module = self_.units[target.unit - 1]; if target.binding >= module.bindings.len { return blot_support::none<BindingRef>(); }
        let binding = module.bindings[target.binding]; if binding.kind == blot_reuse_principal_interface::Kind.global { if binding.body_id == 0 { return blot_support::none<BindingRef>(); } return blot_support::some(target); }
        if binding.kind != blot_reuse_principal_interface::Kind.external { return blot_support::none<BindingRef>(); }
        if binding.target.unit != 0 { target.unit = binding.target.unit; } target.binding = binding.target.binding;
    }
    return blot_support::none<BindingRef>();
}
fn propagateReferences(gate: const Gate&, dirty: bool[:]) {
    var changed = true;
    while changed {
        changed = false;
        for module, unit in gate.units { for binding, offset in module.bindings[1..] {
            let index = gate.offsets[unit] + offset + 1; if dirty[index] { continue; }
            if binding.kind == blot_reuse_principal_interface::Kind.external { if gate.targetDirty(unit, binding.target) { dirty[index] = true; changed = true; } }
            else if binding.kind == blot_reuse_principal_interface::Kind.global { let recipe = module.declaration_dependencies[binding.body_id]; for target in module.dependency_references[recipe.references.start..recipe.references.start + recipe.references.len] { if gate.targetDirty(unit, target) { dirty[index] = true; changed = true; break; } } }
        } }
    }
}
fn selects(use: blot_check_core::DependencyMember, candidate: blot_check_core::Associated) -> bool { if use.name != 0 { return use.name == candidate.member; } return use.operator != blot_check_types::Operator.none && use.operator == candidate.operator; }
struct MemberSpan { start: i64, len: i64 }
fn dirtySelections(gate: const Gate&, dirty: bool[:]) -> Error {
    var candidates: blot_check_core::Associated[>..<] = []; var members: blot_check_core::DependencyMember[>..<] = [];
    var scanned: dictionary<i64,MemberSpan> = default<dictionary<i64,MemberSpan>>();
    while true {
        let known = candidates.len;
        for module, unit in gate.units { for candidate in module.associated {
            if !gate.targetDirty(unit, candidate.target) { continue; } var present = false;
            for prior in candidates { if prior.member == candidate.member && prior.operator == candidate.operator { present = true; break; } }
            if !present { candidates.push(candidate); }
        } }
        if candidates.len == known { return blot_error::Error.none; } var changed = false;
        for &module, unit in gate.units { for binding, offset in module.bindings[1..] {
            let index = gate.offsets[unit] + offset + 1; if dirty[index] || binding.kind != blot_reuse_principal_interface::Kind.global { continue; }
            var span = MemberSpan { members.len, 0 , ..}; let prior .= scanned.get(index);
            if prior { span = prior; }
            else {
                let error = blot_reuse_declaration_dependencies::selectionMembers(module, module.bodies[binding.body_id], members);
                if error != blot_error::Error.none { members.resize(span.start); if error == blot_error::Error.out_of_memory { return error; } if error == blot_error::Error.core_limit { dirty[index] = true; changed = true; continue; } return error; }
                span.len = members.len - span.start; scanned.insert(index, span);
            }
            var selected = false; for use in members[span.start..span.start + span.len] { for candidate in candidates { if selects(use, candidate) { selected = true; break; } } if selected { break; } }
            if selected { dirty[index] = true; changed = true; }
        } }
        if changed { propagateReferences(gate, dirty); }
    }
}
fn obligationsEqual(previous: const blot_check_core::Obligation[:], current: const blot_check_core::Obligation[:]) -> bool {
    if previous.len != current.len { return false; }
    for before, index in previous {
        var left = before; var right = current[index]; left.span = blot_check_core::Span { 0, 0 , ..}; right.span = left.span;
        if left.qualification_span.present { left.qualification_span.value = left.span; } if right.qualification_span.present { right.qualification_span.value = right.span; }
        if !blot_structural::equal(left, right) { return false; }
    } return true;
}
fn catalogEqual(previous: const Module&, current: const Module&, constant_types: bool) -> bool {
    let shared = min(previous.bindings.len, current.bindings.len);
    for before, index in previous.bindings[..shared] { if before.private != current.bindings[index].private { return false; } }
    for binding in previous.bindings[shared..] { if binding.private { return false; } } for binding in current.bindings[shared..] { if binding.private { return false; } }
    let left = blot_check_core::stampView(previous); let right = blot_check_core::stampView(current);
    const for <N,A> in fields<blot_check_core::StampView> {
        if N == "unit" || N == "nominals" || N == "constructors" || N == "associated" || N == "contracts" || N == "contract_members" || N == "implementations" || N == "implementation_members" || N == "member_templates" || N == "selected_proofs" || N == "selected_members" || N == "selected_edges" || N == "selected_uses" || N == "dictionary_selections" || N == "dictionary_uses" || N == "operation_names" || N == "names" || N == "field_names" || N == "operation_values" || N == "capability_contracts" || N == "proof_contracts" || N == "has_rank_contracts" || N == "has_numeric_proofs" || N == "has_usage_contracts" { if !blot_structural::equal(left.A, right.A) { return false; } }
        else if N == "types" { if !blot_structural::equal(left.A, right.A) && (!constant_types || !duplicateTypeTail(previous.types, current.types)) { return false; } }
        else if N == "obligations" { if !obligationsEqual(previous.obligations, current.obligations) { return false; } }
        else if N == "diagnostics" { if previous.diagnostics.len != 0 || current.diagnostics.len != 0 { return false; } }
        else if N == "runtime_names" || N == "source_names" || N == "declaration_dependencies" || N == "dependency_references" || N == "dependency_members" || N == "erased_declaration_references" || N == "request_loops" || N == "request_arms" || N == "tag_calls" || N == "nodes" || N == "spans" || N == "extra" || N == "bindings" || N == "bodies" || N == "parameters" || N == "references" || N == "calls" || N == "merges" || N == "merge_ranges" || N == "projections" || N == "projection_variants" || N == "patterns" || N == "pattern_rows" || N == "match_arms" || N == "matches" || N == "updates" || N == "update_steps" || N == "closures" || N == "primitives" || N == "loops" || N == "loop_carries" || N == "resolver_ops" || N == "handle_effects" || N == "dispatch_signatures" || N == "body_lowerings" { }
        else { return false; }
    }
    for nominal in previous.nominals { let list = nominal.constructors; if list.start > previous.extra.len || list.len > previous.extra.len - list.start || list.start > current.extra.len || list.len > current.extra.len - list.start { return false; } if !blot_structural::equal(previous.extra[list.start..list.start + list.len], current.extra[list.start..list.start + list.len]) { return false; } }
    return true;
}
fn namespaceEqual(old: const Pools&, units: const Module[:], previous: View, current: View) -> bool {
    if previous.owners.len != units.len || current.owners.len != units.len || previous.symbols.len == 0 || previous.symbols.len != current.symbols.len || !blot_structural::equal(previous, current) { return false; }
    if current.symbols[0].start != 0 || current.symbols[0].len != 0 { return false; }
    var paths: dictionary<const u8[:],bool> = default<dictionary<const u8[:],bool>>();
    for module, index in units {
        let pin = old.modules[index]; if module.unit != index + 1 || pin.unit != index + 1 || pin.module.unit != pin.unit { return false; }
        let path = current.owner((index + 1) as u32); if !path.present || !validText(path.value) || path.value != pin.canonical_path || paths.contains(path.value) { return false; } paths.insert(path.value, true);
    }
    var spellings: dictionary<const u8[:],bool> = default<dictionary<const u8[:],bool>>();
    for index in 1..current.symbols.len { let spelling = current.symbol(index as u32); if !spelling.present || !validText(spelling.value) || spellings.contains(spelling.value) { return false; } spellings.insert(spelling.value, true); } return true;
}
fn validText(bytes: const u8[:]) -> bool { if bytes.len == 0 || !blot_backend_runtime_identity::validUtf8(bytes) { return false; } for byte in bytes { if byte == 0 { return false; } } return true; }
fn validDependencies(module: const Module&, units: const blot_check_frozen_core_validation::ModuleRef[:], symbol_count: i64) -> bool, Error {
    let error = blot_check_frozen_core_validation::validate(module, blot_check_frozen_core_validation::Context { units: units, symbol_count: blot_support::some(symbol_count) , ..});
    if error == blot_error::Error.out_of_memory { return false, error; } if error != blot_error::Error.none { return false, blot_error::Error.none; }
    var erased: i64 = 0;
    for node, id in module.nodes { if node.tag != blot_check_core::Tag.effect_reflection || node.a != blot_check_check::reflectionKindCode(blot_check_check::ReflectionKind.of) { continue; } if erased >= module.erased_declaration_references.len || module.erased_declaration_references[erased].node != id { return false, blot_error::Error.none; } erased++; }
    if erased != module.erased_declaration_references.len { return false, blot_error::Error.none; }
    var scanned = module; scanned.declaration_dependencies = []; scanned.dependency_references = []; scanned.dependency_members = [];
    var declarations: blot_check_core::DeclarationDependencies[>..<] = []; var references: BindingRef[>..<] = []; var members: blot_check_core::DependencyMember[>..<] = [];
    let captured = blot_reuse_declaration_dependencies::capture(scanned, declarations, references, members);
    if captured == blot_error::Error.out_of_memory { return false, captured; } if captured != blot_error::Error.none { return false, blot_error::Error.none; }
    return blot_structural::equal(module.declaration_dependencies, declarations[..]) && blot_structural::equal(module.dependency_references, references[..]) && blot_structural::equal(module.dependency_members, members[..]), blot_error::Error.none;
}
fn moduleEqual(previous: const Module&, current: const Module&) -> bool {
    let left = blot_check_core::stampView(previous); let right = blot_check_core::stampView(current);
    const for <N,A> in fields<blot_check_core::StampView> { if N != "nodes" { if !blot_structural::equal(left.A, right.A) { return false; } } }
    if previous.nodes.len != current.nodes.len { return false; }
    for before, id in previous.nodes { var after = current.nodes[id]; if before.a != after.a { if !scalarRoot(previous, id as u32).present || !scalarRoot(current, id as u32).present { return false; } after.a = before.a; } if !blot_structural::equal(before, after) { return false; } } return true;
}
fn rangeHas<R>(values: const u32[:], range: R, id: u32) -> bool { if range.start > values.len || range.len > values.len - range.start { return true; } for value in values[range.start..range.start + range.len] { if value == id { return true; } } return false; }
fn scalarRoot(module: const Module&, id: u32) -> blot_support::Option<u32> {
    let no = blot_support::none<u32>(); if id == 0 || id >= module.nodes.len || module.bodies.len == 0 { return no; }
    let node = module.nodes[id]; if node.tag != blot_check_core::Tag.constant || node.op != blot_check_core::Op.none || node.b != 0 || node.c != 0 || node.ty >= module.types.nodes.len { return no; }
    match module.types.nodes[node.ty].tag { boolean, unsigned32, floating32 => {}, _ => { return no; } }
    var owner = no;
    for body in module.bodies[1..] { if body.root != id { continue; } if owner.present || body.binding == 0 || body.binding >= module.bindings.len || body.is_function || body.runtime || body.parameters.len != 0 || module.bindings[body.binding].kind != blot_reuse_principal_interface::Kind.global { return no; } owner = blot_support::some(body.binding); }
    if !owner.present { return no; } for value, index in module.bindings { if value.initializer == id && index != owner.value { return no; } }
    for value in module.nodes { match value.tag {
        scalar, logical, apply, associated, record_merge, type_same, effect_provider, handle => { if value.a == id || value.b == id { return no; } },
        if_value, if_stmt, state_provider => { if value.a == id || value.b == id || value.c == id { return no; } },
        bind, construct => { if value.b == id { return no; } },
        return_, project, computation, result_associated => { if value.a == id { return no; } },
        block_, suite, product, record, array, array_op, storage => { if rangeHas(module.extra, blot_check_core::List { value.a, value.b , ..}, id) { return no; } },
        call, break_ => { if rangeHas(module.extra, blot_check_core::List { value.b, value.c , ..}, id) { return no; } },
        pattern_bind, request_decision => { if value.b == id || value.c == id { return no; } },
        effect_reflection => { if value.a >= blot_check_check::reflectionKindCode(blot_check_check::ReflectionKind.count) && (value.b == id || value.c == id) { return no; } },
        _ => {},
    } }
    for value in module.closures { if value.body == id { return no; } } for value in module.patterns { if value.tag == blot_check_core::PatternTag.value && value.a == id { return no; } }
    for value in module.matches { if rangeHas(module.extra, value.inputs, id) { return no; } } for value in module.match_arms { if value.body == id || value.guard_ == id { return no; } }
    for value in module.updates { if value.root == id || value.value == id { return no; } } for value in module.update_steps { if value.kind == blot_check_core::UpdateKind.index && value.index == id { return no; } }
    for value in module.loops { if value.first == id || value.end == id || value.body == id { return no; } } for value in module.resolver_ops { if value.resolver == id || rangeHas(module.extra, value.arguments, id) { return no; } }
    for value in module.operation_values { if value.witness == id { return no; } } for value in module.request_loops { if value.computation == id || value.completion_body == id { return no; } } for value in module.request_arms { if value.callback == id { return no; } } return owner;
}
fn duplicateTypeTail(left: blot_check_core::Types, right: blot_check_core::Types) -> bool {
    if !blot_structural::equal(left.extra, right.extra) || !blot_structural::equal(left.effects, right.effects) || !blot_structural::equal(left.operations, right.operations) { return false; }
    let shared = min(left.nodes.len, right.nodes.len); if !blot_structural::equal(left.nodes[..shared], right.nodes[..shared]) { return false; }
    let left_count = left.nodes.len - shared; let right_count = right.nodes.len - shared; if left_count > 4096 || right_count > 4096 - left_count { return false; }
    let tails = [left.nodes[shared..], right.nodes[shared..]];
    for tail in tails { for node in tail {
        match node.tag {
            unit, boolean, unsigned32, floating32, never => {},
            array, list, cursor => {
                if node.a >= shared || node.b != 0 || node.c != 0 { return false; }
                match left.nodes[node.a].tag { unit, boolean, unsigned32, floating32, never => {}, _ => { return false; } }
            }, _ => { return false; },
        }
        var found = false; for existing in left.nodes[..shared] { if blot_structural::equal(existing, node) { found = true; break; } } if !found { return false; }
    } } return true;
}
