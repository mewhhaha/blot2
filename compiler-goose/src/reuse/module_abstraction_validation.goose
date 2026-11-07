// Semantic visibility and opaque storage contracts are independent proofs.
namespace blot_reuse_module_abstraction_validation;
import std;
import dictionary;
import check.core;
import check.types;
import check.frozen_types;
import check.frozen_core_validation;
import check.capability_contracts;
import reuse.principal_interface;
import reuse.frozen_dependency;
import reuse.module_visibility;
import backend.opaque_storage;
import support.error;
import support.option;
type Error = blot_error::Error;
type Interface = blot_reuse_principal_interface::Interface;
type Module = blot_check_core::Module;
type ModuleRef = blot_check_frozen_core_validation::ModuleRef;
type Scan = blot_reuse_module_visibility::Scan;
type Storage = blot_backend_opaque_storage::Storage;
type Resolver = blot_backend_opaque_storage::Resolver;
fn require(condition: bool) -> Error { if !condition { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; }
struct PublicContext { owner: const Interface& }
fn publicView(owner: const Interface&) -> Error {
    var abstraction = false;
    for nominal in owner.nominals { abstraction = abstraction || nominal.private || nominal.is_opaque; }
    for binding in owner.bindings { abstraction = abstraction || binding.private; }
    for family in owner.effect_families { abstraction = abstraction || family.private; }
    for contract in owner.contracts { abstraction = abstraction || contract.private; }
    if !abstraction { return blot_error::Error.none; }
    var context = PublicContext { owner , ..};
    let error = blot_reuse_module_visibility::withScan(blot_check_frozen_types::Source.frozen { owner.graph , ..}, owner.nominals, owner.effect_families, owner.effect_templates, context, publicScan);
    if error == blot_error::Error.type_limit { return blot_error::Error.invalid_artifact; } return error;
}
fn publicScan(context: PublicContext&, scan: Scan&) -> Error {
    let owner .= context.owner;
    for contract in owner.contracts { if contract.private { scan.blocked.insert(contract.identity, true); } }
    for binding in owner.bindings {
        if binding.private {
            { let propagated_error = require(binding.name == 0 && binding.ty == 0 && binding.scheme.root == 0 && binding.scheme.generative.len == 0 && !binding.external.present); if propagated_error != blot_error::Error.none { return propagated_error; } }
            continue;
        }
        { let propagated_error = allowed(scan, binding.scheme.root); if propagated_error != blot_error::Error.none { return propagated_error; } }
        for root in owner.graph.extra[binding.scheme.generative.start..binding.scheme.generative.start + binding.scheme.generative.len] { { let propagated_error = allowed(scan, root); if propagated_error != blot_error::Error.none { return propagated_error; } } }
        for predicate in owner.obligations[binding.scheme.obligations.start..binding.scheme.obligations.start + binding.scheme.obligations.len] { { let propagated_error = requirement(scan, owner, predicate); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    }
    var identities: dictionary<blot_check_types::NominalIdentity,bool>;
    for nominal in owner.nominals {
        if nominal.identity.unit != 0 { { let propagated_error = require(!identities.contains(nominal.identity)); if propagated_error != blot_error::Error.none { return propagated_error; } } identities.insert(nominal.identity, true); }
        if nominal.private {
            { let propagated_error = require(nominal.name == 0 && nominal.alias == 0 && nominal.parameters.len == 0 && nominal.constructors.len == 0); if propagated_error != blot_error::Error.none { return propagated_error; } }
            continue;
        }
        if nominal.is_opaque { { let propagated_error = require(nominal.name == (nominal.identity.decl & ~blot_check_types::opaque_name_bit)); if propagated_error != blot_error::Error.none { return propagated_error; } } }
        { let propagated_error = allowed(scan, nominal.alias); if propagated_error != blot_error::Error.none { return propagated_error; } }
        for parameter in owner.graph.extra[nominal.parameters.start..nominal.parameters.start + nominal.parameters.len] { { let propagated_error = allowed(scan, parameter); if propagated_error != blot_error::Error.none { return propagated_error; } } }
        for index in owner.graph.extra[nominal.constructors.start..nominal.constructors.start + nominal.constructors.len] { { let propagated_error = allowed(scan, owner.constructors[index].payload); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    }
    for constructor in owner.constructors {
        if constructor.private { { let propagated_error = require(constructor.name == 0 && constructor.payload == 0 && constructor.scheme.root == 0); if propagated_error != blot_error::Error.none { return propagated_error; } } continue; }
        { let propagated_error = require(!owner.nominals[constructor.nominal].is_opaque && !owner.nominals[constructor.nominal].private); if propagated_error != blot_error::Error.none { return propagated_error; } }
        { let propagated_error = allowed(scan, constructor.payload); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = allowed(scan, constructor.scheme.root); if propagated_error != blot_error::Error.none { return propagated_error; } }
    }
    for family in owner.effect_families {
        if family.private { { let propagated_error = require(family.name == 0 && family.parameters.len == 0 && family.operations.len == 0); if propagated_error != blot_error::Error.none { return propagated_error; } } continue; }
        for parameter in owner.graph.extra[family.parameters.start..family.parameters.start + family.parameters.len] { { let propagated_error = allowed(scan, parameter); if propagated_error != blot_error::Error.none { return propagated_error; } } }
        for index in owner.graph.extra[family.operations.start..family.operations.start + family.operations.len] { { let propagated_error = allowed(scan, owner.effect_templates[index].parameter); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = allowed(scan, owner.effect_templates[index].result); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    }
    for contract in owner.contracts {
        if contract.private { { let propagated_error = require(contract.name == 0 && contract.parameters.len == 0 && contract.predicates.len == 0); if propagated_error != blot_error::Error.none { return propagated_error; } } continue; }
        for parameter in owner.graph.extra[contract.parameters.start..contract.parameters.start + contract.parameters.len] { { let propagated_error = allowed(scan, parameter); if propagated_error != blot_error::Error.none { return propagated_error; } } }
        for member in owner.contract_members[contract.members.start..contract.members.start + contract.members.len] { { let propagated_error = allowed(scan, member.root); if propagated_error != blot_error::Error.none { return propagated_error; } } }
        for predicate in owner.contract_predicates[contract.predicates.start..contract.predicates.start + contract.predicates.len] { { let propagated_error = requirement(scan, owner, predicate); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    }
    for implementation in owner.implementations {
        if implementation.private { { let propagated_error = require(implementation.name == 0 && implementation.head.len == 0 && implementation.members.len == 0 && implementation.predicates.len == 0); if propagated_error != blot_error::Error.none { return propagated_error; } } continue; }
        { let propagated_error = require(!scan.blocked.contains(implementation.contract)); if propagated_error != blot_error::Error.none { return propagated_error; } }
        for root in owner.graph.extra[implementation.head.start..implementation.head.start + implementation.head.len] { { let propagated_error = allowed(scan, root); if propagated_error != blot_error::Error.none { return propagated_error; } } }
        for member in owner.implementation_members[implementation.members.start..implementation.members.start + implementation.members.len] { { let propagated_error = allowed(scan, member.root); if propagated_error != blot_error::Error.none { return propagated_error; } } }
        for predicate in owner.implementation_predicates[implementation.predicates.start..implementation.predicates.start + implementation.predicates.len] { { let propagated_error = requirement(scan, owner, predicate); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    }
    for member in owner.associated { { let propagated_error = require(member.binding < owner.bindings.len && !owner.bindings[member.binding].private); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    return blot_error::Error.none;
}
fn allowed(scan: Scan&, ty: u32) -> Error {
    let allowed, error = scan.allowed(ty);
    if error == blot_error::Error.out_of_memory { return error; }
    if error != blot_error::Error.none || !allowed { return blot_error::Error.invalid_artifact; } return blot_error::Error.none;
}
fn requirement(scan: Scan&, owner: const Interface&, predicate: blot_check_types::Obligation) -> Error {
    if predicate.kind == blot_check_types::ObligationKind.callee_use && predicate.identity.unit == owner.unit { { let propagated_error = require(predicate.identity.decl < owner.bindings.len && !owner.bindings[predicate.identity.decl].private); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    if predicate.kind == blot_check_types::ObligationKind.contract { { let propagated_error = require(!scan.blocked.contains(predicate.identity)); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    for ty in [predicate.ty, predicate.result, predicate.other, predicate.signature] { { let propagated_error = allowed(scan, ty); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    return blot_error::Error.none;
}
fn coreGraph(module: const Module&) -> blot_check_frozen_types::Graph {
    return blot_check_frozen_types::Graph { nodes: module.types.nodes, extra: module.types.extra, rows: module.types.effects.rows, labels: module.types.effects.labels, operations: module.types.operations, row_variable_count: module.types.effects.variable_count, quantifier_goals: module.types.quantifier_goals, quantifier_obligations: module.types.quantifier_obligations, .. };
}
fn storageContracts(owner: const Interface&, implementation: const Module&) -> Error {
    var entries: blot_backend_opaque_storage::AuthorityEntry[>..<] = [];
    for nominal in implementation.nominals {
        if nominal.identity.unit != implementation.unit { continue; }
        entries.push(blot_backend_opaque_storage::AuthorityEntry { nominal.identity, blot_backend_opaque_storage::Authority { coreGraph(implementation), blot_check_types::List { nominal.parameters.start, nominal.parameters.len , ..}, nominal.storage, nominal.is_opaque , ..} , ..});
    }
    return storageContractsResolved(owner, implementation, Resolver { entries , ..});
}
fn storageClosure(owners: const blot_reuse_frozen_dependency::Module[:], units: const ModuleRef[:]) -> Error {
    { let propagated_error = require(owners.len == units.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
    var offsets: i64[>..<] = [0]; var recipes: Storage[>..<] = []; var entry_indices: i64[>..<] = [];
    var entries: blot_backend_opaque_storage::AuthorityEntry[>..<] = [];
    for ref, index in units {
        let module .= ref.value;
        if module.nominals.len > 0x7fffffffffffffff - offsets[index] { return blot_error::Error.invalid_artifact; }
        offsets.push(offsets[index] + module.nominals.len);
        var first_owner = true; for previous in units[..index] { if previous.value.unit == module.unit { first_owner = false; break; } }
        for nominal in module.nominals {
            recipes.push(Storage {..}); var at: i64 = -1;
            if first_owner && nominal.identity.unit == module.unit {
                at = entries.len; entries.push(blot_backend_opaque_storage::AuthorityEntry { nominal.identity, blot_backend_opaque_storage::Authority { coreGraph(module), blot_check_types::List { nominal.parameters.start, nominal.parameters.len , ..}, Storage {..}, nominal.is_opaque , ..} , ..});
            }
            entry_indices.push(at);
        }
    }
    let resolver = Resolver { entries , ..}; var remaining: i64 = 1000000; var changed = true;
    while changed && remaining != 0 {
        changed = false;
        for ref, unit_index in units {
            let module .= ref.value; let graph = coreGraph(module);
            for nominal, nominal_index in module.nominals {
                if !nominal.is_opaque || nominal.identity.unit != module.unit { continue; }
                let index = offsets[unit_index] + nominal_index;
                if recipes[index].kind != blot_backend_opaque_storage::Kind.unknown { continue; }
                { let propagated_error = require(nominal.constructors.len == 1); if propagated_error != blot_error::Error.none { return propagated_error; } }
                let constructor = module.constructors[module.extra[nominal.constructors.start]];
                let inferred = blot_backend_opaque_storage::inferPayloadAuthoritative(blot_check_frozen_types::Source.frozen { graph , ..}, module.nominals, module.constructors, constructor.payload, blot_check_types::List { nominal.parameters.start, nominal.parameters.len , ..}, module.unit, resolver, remaining);
                if inferred.kind != blot_backend_opaque_storage::Kind.unknown {
                    recipes[index] = inferred; if entry_indices[index] >= 0 { entries[entry_indices[index]].authority.storage = inferred; }
                    changed = true;
                }
            }
        }
    }
    for &owner in owners { { let propagated_error = storageContractsResolved(owner.interface, owner.core, resolver); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    return blot_error::Error.none;
}
fn storageContractsResolved(owner: const Interface&, implementation: const Module&, resolver: Resolver) -> Error {
    { let propagated_error = require(owner.bindings.len <= implementation.bindings.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
    for binding, index in owner.bindings {
        let private = implementation.bindings[index];
        { let propagated_error = require(binding.private == private.private); if propagated_error != blot_error::Error.none { return propagated_error; } }
        if binding.ty != 0 { { let propagated_error = require(binding.scheme.generative.len == private.scheme.generative.len); if propagated_error != blot_error::Error.none { return propagated_error; } } }
        if binding.ty != 0 && !binding.external.present {
            { let propagated_error = require(binding.capability_flow == private.capability_flow && binding.capability_parameters == private.capability_parameters); if propagated_error != blot_error::Error.none { return propagated_error; } }
            let public = owner.capability_contracts.header(index as u32, binding.capability_parameters.arity() as u32);
            let private = implementation.capability_contracts.header(index as u32, implementation.bindings[index].capability_parameters.arity() as u32);
            { let propagated_error = require(public.present == private.present); if propagated_error != blot_error::Error.none { return propagated_error; } }
            if public.present {
                { let propagated_error = require(public.value.arity == private.value.arity); if propagated_error != blot_error::Error.none { return propagated_error; } }
                let same, error = blot_check_capability_contracts::equivalent(public.value.view(), public.value.root, private.value.view(), private.value.root);
                if error != blot_error::Error.none { return blot_error::Error.invalid_artifact; } { let propagated_error = require(same); if propagated_error != blot_error::Error.none { return propagated_error; } }
            }
        }
    }
    { let propagated_error = require(owner.nominals.len == implementation.nominals.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
    for public, index in owner.nominals {
        let private = implementation.nominals[index];
        { let propagated_error = require(public.identity == private.identity && public.private == private.private && public.is_opaque == private.is_opaque); if propagated_error != blot_error::Error.none { return propagated_error; } }
        { let propagated_error = require(public.affine == private.affine && public.has_usage == private.has_usage && public.closed_storage == private.closed_storage); if propagated_error != blot_error::Error.none { return propagated_error; } }
    }
    for constructor in owner.constructors { let nominal = implementation.nominals[constructor.nominal]; { let propagated_error = require(constructor.private == (nominal.private || nominal.is_opaque)); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    for node in implementation.nodes {
        if node.tag != blot_check_core::Tag.construct && node.tag != blot_check_core::Tag.constructor_function { continue; }
        let nominal = implementation.nominals[implementation.constructors[node.a].nominal]; if nominal.is_opaque { { let propagated_error = require(nominal.identity.unit == implementation.unit); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    }
    for pattern in implementation.patterns {
        if pattern.tag != blot_check_core::PatternTag.constructor { continue; }
        let nominal = implementation.nominals[implementation.constructors[pattern.a].nominal]; if nominal.is_opaque { { let propagated_error = require(nominal.identity.unit == implementation.unit); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    }
    for projection in implementation.projections { if projection.nominal.unit != 0 && projection.nominal.decl & blot_check_types::opaque_name_bit != 0 { { let propagated_error = require(projection.nominal.unit == implementation.unit); if propagated_error != blot_error::Error.none { return propagated_error; } } } }
    let graph = coreGraph(implementation); var remaining: i64 = 1000000;
    for nominal in implementation.nominals {
        if !nominal.is_opaque || nominal.identity.unit != implementation.unit { continue; }
        { let propagated_error = require(nominal.constructors.len == 1); if propagated_error != blot_error::Error.none { return propagated_error; } } let constructor = implementation.constructors[implementation.extra[nominal.constructors.start]];
        let inferred = blot_backend_opaque_storage::inferPayloadAuthoritative(blot_check_frozen_types::Source.frozen { graph , ..}, implementation.nominals, implementation.constructors, constructor.payload, blot_check_types::List { nominal.parameters.start, nominal.parameters.len , ..}, implementation.unit, resolver, remaining);
        { let propagated_error = require(nominal.storage == inferred); if propagated_error != blot_error::Error.none { return propagated_error; } }
    }
    for nominal in owner.nominals {
        if !nominal.is_opaque || nominal.private || nominal.identity.unit != implementation.unit { continue; }
        var found = false;
        for private in implementation.nominals {
            if private.identity != nominal.identity { continue; }
            { let propagated_error = require(private.is_opaque && private.private == nominal.private && private.storage == nominal.storage); if propagated_error != blot_error::Error.none { return propagated_error; } }
            found = true; break;
        }
        { let propagated_error = require(found); if propagated_error != blot_error::Error.none { return propagated_error; } }
    }
    return blot_error::Error.none;
}
