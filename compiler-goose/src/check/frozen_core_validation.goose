// Immutable decoded-Core validation. It never resolves or repairs source types.
namespace blot_check_frozen_core_validation;
import check.capability_flow;

import check.check_packet_owner;
import check.core;
import check.types;
import support.error;
import support.option;
import support.structural_adapters;

import std;
import .check;
import .frozen_core_bounds;
import .frozen_core_graph;
import .frozen_core_scopes;
import support.structural;
type Error = blot_error::Error;
type Module = blot_check_core::Module;
var inactive_module:Module=default<Module>();
struct ModuleRef { value: const Module& =inactive_module }
struct Context {
    units: const ModuleRef[:] = default<const ModuleRef[:]>(), symbol_count: blot_support::Option<i64>,
    source_length: blot_support::Option<u32>, forbidden_owner: blot_support::Option<u32>,
}
struct Batch { context: Context, spawn_contracts: bool }
fn moduleHasSpawnContracts(module: const Module&) -> bool { for binding in module.bindings { if binding.capability_flow == blot_check_capability_flow::Contract.spawn_task { return true; } } return false; }
fn withBatch<C,F>(context: Context, state: C) {
    var spawn = false; for owner in context.units { if moduleHasSpawnContracts(owner.value) { spawn = true; break; } }
    let batch = Batch { context, spawn , ..}; return F(state, batch);
}
fn units(self_: const Batch&) -> const ModuleRef[:] { return self_.context.units; }
fn hasSpawnContracts(self_: const Batch&, module: const Module&) -> bool { return self_.spawn_contracts || moduleHasSpawnContracts(module); }
fn validateWithBudget(self_: const Batch&, module: const Module&, source_length: blot_support::Option<u32>, remaining: i64&) -> Error {
    var context = self_.context; context.source_length = source_length; return validateBatchWithBudget(module, context, remaining, self_);
}
struct OwnerBounds { binding_count: i64 }
fn ownerBounds(module: const Module&) -> OwnerBounds { return OwnerBounds { module.bindings.len , ..}; }
fn reusableModules(modules: const ModuleRef[:], caller: bool) -> bool {
    for ref in modules {
        let module .= ref.value;
        if module.has_usage_contracts || module.has_rank_contracts || module.capability_contracts.bindings.len != 0 || (caller && module.has_numeric_proofs) { return false; }
        for node in module.nodes { if node.tag == blot_check_core::Tag.staging || node.tag == blot_check_core::Tag.effect_scope { return false; } }
        for binding in module.bindings {
            let flow = binding.capability_flow;
            if binding.scheme.generative.len != 0 || binding.capability_parameters.invokes() || flow == blot_check_capability_flow::Contract.input_shape || flow == blot_check_capability_flow::Contract.consume_task || flow == blot_check_capability_flow::Contract.scope_task || flow == blot_check_capability_flow::Contract.spawn_task { return false; }
        }
        for node in module.types.nodes { if node.tag == blot_check_types::Tag.existential || node.tag == blot_check_types::Tag.forall || node.tag == blot_check_types::Tag.instance_version || node.tag == blot_check_types::Tag.scoped { return false; } }
    } return true;
}
fn reusableContext(context: Context, callers: const ModuleRef[:]) -> bool { return callers.len != 0 && reusableModules(callers, true); }
struct NominalFact { identity: blot_check_types::NominalIdentity, affine: bool, has_usage: bool, closed_storage: bool }
fn nominalFact(value: blot_check_core::Nominal) -> NominalFact { return NominalFact { value.identity, value.affine, value.has_usage, value.closed_storage , ..}; }
struct ImageOwner { unit: u32, bounds: OwnerBounds, nominals: blot_check_core::List }
struct ContextImage {
    owners: const ImageOwner[:] = default<const ImageOwner[:]>(), nominal_facts: const NominalFact[:] = default<const NominalFact[:]>(), reusable_: bool = false,
    symbol_count: blot_support::Option<i64>, source_length: blot_support::Option<u32>, forbidden_owner: blot_support::Option<u32>,
}
reusable[] var image_owners: ImageOwner[>..] = [];
reusable[] var image_facts: NominalFact[>..] = [];
fn capture(context: Context, callers: const ModuleRef[:]) -> ContextImage, Error {
    var count: i64 = 0; for ref in context.units { if ref.value.nominals.len > 0xffffffff - count { return ContextImage {..}, blot_error::Error.out_of_memory; } count += ref.value.nominals.len; }
    let owners = image_owners.alloc_slice(context.units.len); let facts = image_facts.alloc_slice(count); var offset: u32 = 0;
    for ref, index in context.units { let module .= ref.value; owners[index] = ImageOwner { module.unit, ownerBounds(module), blot_check_core::List { offset, module.nominals.len as u32 , ..} , ..}; for nominal, n in module.nominals { facts[offset + n] = nominalFact(nominal); } offset += module.nominals.len as u32; }
    return ContextImage { owners: owners, nominal_facts: facts, reusable_: reusableContext(context, callers), symbol_count: context.symbol_count, source_length: context.source_length, forbidden_owner: context.forbidden_owner , ..}, blot_error::Error.none;
}
fn deinit(self_: ContextImage&) {
    if self_.owners.len != 0 { let first: const ImageOwner&  = self_.owners[0]; let at = image_owners.index_of(first); assert(at >= 0); image_owners.free_slice(image_owners[at..at + self_.owners.len]); }
    if self_.nominal_facts.len != 0 { let first: const NominalFact&  = self_.nominal_facts[0]; let at = image_facts.index_of(first); assert(at >= 0); image_facts.free_slice(image_facts[at..at + self_.nominal_facts.len]); }
    self_ = ContextImage {..};
}
fn matches(self_: const ContextImage&, context: Context, callers: const ModuleRef[:]) -> bool {
    if !self_.reusable_ || !reusableContext(context, callers) || self_.owners.len != context.units.len || !blot_structural::equal(self_.symbol_count, context.symbol_count) || !blot_structural::equal(self_.source_length, context.source_length) || !blot_structural::equal(self_.forbidden_owner, context.forbidden_owner) { return false; }
    for owner, index in self_.owners {
        let module .= context.units[index].value;
        if owner.unit != module.unit || owner.bounds != ownerBounds(module) || owner.nominals.len != module.nominals.len { return false; }
        for old, n in self_.nominal_facts[owner.nominals.start..owner.nominals.start + owner.nominals.len] { if old != nominalFact(module.nominals[n]) { return false; } }
    } return true;
}
fn equivalentContext(before: Context, after: Context, before_callers: const ModuleRef[:], after_callers: const ModuleRef[:]) -> bool { return reusableContext(before, before_callers) && reusableContext(after, after_callers) && equivalentContextFacts(before, after); }
fn equivalentContextFacts(before: Context, after: Context) -> bool {
    if before.units.len != after.units.len || !blot_structural::equal(before.symbol_count, after.symbol_count) || !blot_structural::equal(before.source_length, after.source_length) || !blot_structural::equal(before.forbidden_owner, after.forbidden_owner) { return false; }
    for ref, index in before.units { let old .= ref.value; let current .= after.units[index].value; if old.unit != current.unit || ownerBounds(old) != ownerBounds(current) || old.nominals.len != current.nominals.len { return false; } for left, n in old.nominals { if nominalFact(left) != nominalFact(current.nominals[n]) { return false; } } } return true;
}
fn require(condition: bool) -> Error { if !condition { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; }
fn range(total: i64, start: u32, len: u32) -> Error { return require(start <= total && len <= total - start); }
fn index(total: i64, value: u32) -> Error { return require(value < total); }
fn requiredIndex(total: i64, value: u32) -> Error { return require(value != 0 && value < total); }
fn sum(a: i64, b: i64) -> i64, Error { if a < 0 || b < 0 || b > 0x7fffffffffffffff - a { return 0, blot_error::Error.invalid_artifact; } return a + b, blot_error::Error.none; }
