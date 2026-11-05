// Validate the whole prelude payload before relocation or publication.
namespace blot_reuse_dependency_admission;
import reuse.frozen_dependency;
import reuse.principal_interface;
import reuse.dependency_interface_validation;
import reuse.dependency_format;
import reuse.module_abstraction_validation;
import check.core;
import check.check;
import check.frozen_core_validation;
import check.associated_admission;
import eval.implementation_admission;
import support.error;
import support.option;
type Error = blot_error::Error;
type FrozenDependency = blot_reuse_frozen_dependency::FrozenDependency;
fn require(condition: bool) -> Error { if !condition { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; }
fn external(value: const FrozenDependency&, current: i64, target: blot_reuse_principal_interface::ExternalTarget) -> Error {
    var unit = target.unit as i64; if unit == 0 { unit = current + 1; }
    { let propagated_error = require(unit != 0 && unit <= value.modules.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = require(target.binding != 0 && target.binding < value.modules[unit - 1].interface.bindings.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
    return blot_error::Error.none;
}
fn validatePrelude(value: const FrozenDependency&, source: const u8[:], producer_identity: const u8[:]) -> Error {
    { let propagated_error = require(value.modules.len == 1 && value.symbols.len != 0 && value.symbols[0].text.len == 0); if propagated_error != blot_error::Error.none { return propagated_error; } }
    var associated_remaining: i64 = 1000000; let owner .= value.modules[0];
    { let propagated_error = require(owner.identity.prelude && owner.imports.len == 0); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = require(owner.identity.normalized_path == producer_identity); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = require(owner.identity.source_bytes == source.len && owner.identity.source_digest == blot_reuse_dependency_format::digest(source)); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = require(owner.core.unit == 1 && owner.interface.unit == 1); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = blot_reuse_dependency_interface_validation::validate(owner.interface, value.symbols.len, value.modules.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = blot_reuse_dependency_interface_validation::validateGraphWithBudget(owner.interface, associated_remaining); if propagated_error != blot_error::Error.none { return propagated_error; } }
    let units = [blot_check_frozen_core_validation::ModuleRef { owner.core , ..}];
    let context = blot_check_frozen_core_validation::Context { units: units, symbol_count: blot_support::some(value.symbols.len), source_length: blot_support::some(owner.identity.source_bytes) , ..};
    { let propagated_error = blot_check_frozen_core_validation::validateWithBudget(owner.core, context, associated_remaining); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = blot_reuse_module_abstraction_validation::publicView(owner.interface); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = blot_reuse_module_abstraction_validation::storageContracts(owner.interface, owner.core); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = blot_check_associated_admission::publicCoreWithBudget(owner.interface, owner.core, associated_remaining); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = blot_eval_implementation_admission::publicCore(owner.interface, owner.core, associated_remaining); if propagated_error != blot_error::Error.none { return propagated_error; } }
    for field in owner.core.field_names { { let propagated_error = require(owner.core.name(field.spelling) == value.symbols[field.symbol].text); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    for binding in owner.interface.bindings { if binding.external.present { { let propagated_error = external(value, 0, binding.external.value); if propagated_error != blot_error::Error.none { return propagated_error; } } } }
    for entry in owner.exports {
        { let propagated_error = require(entry.name != 0 && entry.name < value.symbols.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
        match entry.kind {
            value => {
                { let propagated_error = external(value, 0, entry.target); if propagated_error != blot_error::Error.none { return propagated_error; } } let definition = owner.interface.bindings[entry.target.binding];
                { let propagated_error = require(definition.kind == blot_reuse_principal_interface::Kind.global && !definition.private && definition.name == entry.name); if propagated_error != blot_error::Error.none { return propagated_error; } }
            },
            nominal => { { let propagated_error = require(entry.catalog != 0 && entry.catalog < owner.interface.nominals.len && !owner.interface.nominals[entry.catalog].private && owner.interface.nominals[entry.catalog].name == entry.name); if propagated_error != blot_error::Error.none { return propagated_error; } } },
            constructor => { { let propagated_error = require(entry.catalog != 0 && entry.catalog < owner.interface.constructors.len && !owner.interface.constructors[entry.catalog].private && owner.interface.constructors[entry.catalog].name == entry.name); if propagated_error != blot_error::Error.none { return propagated_error; } } },
            effect_family => { { let propagated_error = require(entry.catalog != 0 && entry.catalog < owner.interface.effect_families.len && !owner.interface.effect_families[entry.catalog].private && owner.interface.effect_families[entry.catalog].name == entry.name); if propagated_error != blot_error::Error.none { return propagated_error; } } },
            implementation => { { let propagated_error = require(entry.catalog < owner.interface.implementations.len && !owner.interface.implementations[entry.catalog].private && owner.interface.implementations[entry.catalog].name == entry.name); if propagated_error != blot_error::Error.none { return propagated_error; } } },
            contract => { { let propagated_error = require(entry.catalog < owner.interface.contracts.len && !owner.interface.contracts[entry.catalog].private && owner.interface.contracts[entry.catalog].name == entry.name); if propagated_error != blot_error::Error.none { return propagated_error; } } },
        }
    }
    for fixity in owner.fixities {
        { let propagated_error = require(fixity.operator != 0 && fixity.operator < value.symbols.len && fixity.target != 0 && fixity.target < value.symbols.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
        { let propagated_error = require(fixity.precedence <= 255 && fixity.association <= 2); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = external(value, 0, fixity.producer); if propagated_error != blot_error::Error.none { return propagated_error; } }
    }
    return blot_error::Error.none;
}
