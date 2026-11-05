// Stored dictionaries are reconstructed from selected proofs and exact openings.
namespace blot_check_dictionary_contracts;
import check.core;
import check.package_contracts;
import check.types;
import reuse.principal_interface;
import support.error;
import support.option;

type Error = blot_error::Error;
type Module = blot_check_core::Module;
type Id = blot_check_core::Id;
type List = blot_check_types::List;
type Context = blot_check_package_contracts::Context;
type Principal = blot_check_package_contracts::Principal;
fn step(scopes: Context&) -> Error { if scopes.remaining == 0 { return blot_error::Error.invalid_artifact; } scopes.remaining -= 1; return blot_error::Error.none; }
fn contract(module: const Module&, goal: blot_check_types::Obligation) -> blot_check_core::Contract, Error {
    if goal.kind != blot_check_types::ObligationKind.contract { return default<blot_check_core::Contract>(), blot_error::Error.invalid_artifact; }
    for candidate in module.contracts { if candidate.identity.unit == goal.identity.unit && candidate.identity.decl == goal.identity.decl { return candidate, blot_error::Error.none; } } return default<blot_check_core::Contract>(), blot_error::Error.invalid_artifact;
}
fn sameTarget(module: const Module&, reference: blot_check_core::BindingRef, target: blot_reuse_principal_interface::ExternalTarget) -> bool { var left = reference.unit; if left == 0 { left = module.unit; } var right = target.unit; if right == 0 { right = module.unit; } return left == right && reference.binding == target.binding; }
fn implementationGiven(module: const Module&, body: u32, goal: blot_check_core::Obligation, scopes: Context&) -> bool, Error {
    if body == 0 { return false, blot_error::Error.none; } let arguments = module.types.node(goal.ty); if arguments.tag != blot_check_types::Tag.product { return false, blot_error::Error.none; }
    for implementation in module.implementations { let error = step(scopes); if error != blot_error::Error.none { return false, error; }
        if implementation.contract.unit != goal.identity.unit || implementation.contract.decl != goal.identity.decl || implementation.head.len != arguments.b { continue; } var owns = false;
        for member in module.implementation_members[implementation.members.start..implementation.members.start + implementation.members.len] { let error = step(scopes); if error != blot_error::Error.none { return false, error; } if member.kind == blot_reuse_principal_interface::ImplementationMemberKind.value && sameTarget(module, blot_check_core::BindingRef { 0, body , ..}, member.target) { owns = true; } } if !owns { continue; }
        var matches = true; let actuals = module.types.list(List { arguments.a, arguments.b , ..});
        for expected, index in module.types.list(implementation.head) { var comparison = Principal { left: module.types, right: module.types, remaining: scopes.remaining, views: scopes , ..}; if comparison.validate(expected, actuals[index]) != blot_error::Error.none { matches = false; break; } } if matches { return true, blot_error::Error.none; }
    } return false, blot_error::Error.none;
}
fn requirements(module: const Module&, predicates: List, scopes: Context&, body: u32) -> Error {
    for goal in module.obligations[predicates.start..predicates.start + predicates.len] { let error = step(scopes); if error != blot_error::Error.none { return error; } if goal.kind != blot_check_types::ObligationKind.contract { return blot_error::Error.invalid_artifact; }
        let arguments = module.types.node(goal.ty); if arguments.tag != blot_check_types::Tag.product { return blot_error::Error.invalid_artifact; } let implementation, error = implementationGiven(module, body, goal, scopes); if error != blot_error::Error.none { return error; } if implementation { continue; } var found = false;
        for proof in module.selected_proofs { let error = step(scopes); if error != blot_error::Error.none { return error; } if proof.kind != blot_reuse_principal_interface::SelectedProofKind.implementation || proof.contract.unit != goal.identity.unit || proof.contract.decl != goal.identity.decl || proof.arguments.len != arguments.b { continue; }
            var same = Principal { left: module.types, right: module.types, remaining: scopes.remaining , ..}; var matches = true; let actuals = module.types.list(proof.arguments);
            for expected, index in module.types.list(List { arguments.a, arguments.b , ..}) { if same.validate(expected, actuals[index]) != blot_error::Error.none { matches = false; break; } } if !matches { continue; } found = true; break;
        } if !found { return blot_error::Error.invalid_artifact; }
    } return blot_error::Error.none;
}
fn givenBinders(module: const Module&, given: blot_check_core::DictionaryGiven, scopes: Context&) -> List, Error {
    let owner = module.types.node(given.quantifier);
    if given.introduction != 0 { if given.opening != 0 || owner.tag != blot_check_types::Tag.forall { return List {..}, blot_error::Error.invalid_artifact; }
        for index in 0..scopes.formal_count { let error = step(scopes); if error != blot_error::Error.none { return List {..}, error; } if scopes.formals[index] == given.quantifier && scopes.introductions[index] == given.introduction { return List { owner.b, owner.c , ..}, blot_error::Error.none; } }
    } else { if owner.tag != blot_check_types::Tag.existential { return List {..}, blot_error::Error.invalid_artifact; } for index in 0..scopes.opening_count { let error = step(scopes); if error != blot_error::Error.none { return List {..}, error; } let opening = scopes.openings[index]; if opening.binding == given.opening && opening.quantifier == given.quantifier { return opening.binders, blot_error::Error.none; } } }
    return List {..}, blot_error::Error.invalid_artifact;
}
fn givenArguments(module: const Module&, given: blot_check_core::DictionaryGiven, wanted: blot_check_types::Obligation, scopes: Context&) -> Error {
    let opened, error = givenBinders(module, given, scopes); if error != blot_error::Error.none { return error; } let owner = module.types.node(given.quantifier); let goals = module.types.quantifierGoals(given.quantifier); if given.goal >= goals.len { return blot_error::Error.invalid_artifact; } let goal = goals[given.goal];
    if goal.kind != blot_check_types::ObligationKind.contract || goal.identity.unit != wanted.identity.unit || goal.identity.decl != wanted.identity.decl { return blot_error::Error.invalid_artifact; } let arguments = module.types.node(goal.ty); if arguments.tag != blot_check_types::Tag.product || arguments.b != given.arguments.len { return blot_error::Error.invalid_artifact; }
    var comparison = Principal { left: module.types, right: module.types, remaining: scopes.remaining, views: scopes , ..}; let actuals = module.types.list(given.arguments);
    for expected, index in module.types.list(List { arguments.a, arguments.b , ..}) { let error = comparison.substituted(List { owner.b, owner.c , ..}, module.types.list(opened), expected, actuals[index]); if error != blot_error::Error.none { return error; } } return blot_error::Error.none;
}
fn pack(module: const Module&, id: Id, scopes: Context&) -> Error {
    let node = module.node(id); let owner = module.types.node(node.ty); let goals = module.types.quantifierGoals(node.ty); var count: i64 = 0; var content_slot: i64 = 1; let contents = module.children(id);
    for goal, ordinal in goals { let error = step(scopes); if error != blot_error::Error.none { return error; } let declaration, error = contract(module, goal); if error != blot_error::Error.none { return error; }
        var selected = blot_support::none<blot_check_core::DictionarySelection>();
        for candidate in module.dictionary_selections { let error = step(scopes); if error != blot_error::Error.none { return error; } if candidate.owner != id || candidate.goal != ordinal { continue; } if selected.present { return blot_error::Error.invalid_artifact; } selected = blot_support::some(candidate); }
        if !selected.present { return blot_error::Error.invalid_artifact; } let selection = selected.value; let arguments = module.types.node(goal.ty); if arguments.tag != blot_check_types::Tag.product { return blot_error::Error.invalid_artifact; }
        let formals = List { owner.b, owner.c , ..}; let witnesses = module.types.list(List { node.b, node.c , ..}); let nodes = module.extra[selection.members.start..selection.members.start + selection.members.len];
        match selection.proof {
            selected match_payload_32 => { let selected_proof = match_payload_32.value;
                let proof = module.selected_proofs[selected_proof]; if proof.kind != blot_reuse_principal_interface::SelectedProofKind.implementation || proof.contract.unit != goal.identity.unit || proof.contract.decl != goal.identity.decl || arguments.b != proof.arguments.len { return blot_error::Error.invalid_artifact; }
                var substitution = Principal { left: module.types, right: module.types, remaining: scopes.remaining, views: scopes , ..}; let actuals = module.types.list(proof.arguments);
                for expected, index in module.types.list(List { arguments.a, arguments.b , ..}) { let error = substitution.substituted(formals, witnesses, expected, actuals[index]); if error != blot_error::Error.none { return error; } }
                if proof.members.len != declaration.members.len || selection.members.len != proof.members.len { return blot_error::Error.invalid_artifact; }
                for member, index in module.selected_members[proof.members.start..proof.members.start + proof.members.len] { let error = step(scopes); if error != blot_error::Error.none { return error; } let value = nodes[index]; if member.kind == blot_reuse_principal_interface::ImplementationMemberKind.type_ { if value != 0 { return blot_error::Error.invalid_artifact; } continue; }
                    if value == 0 || module.node(value).tag != blot_check_core::Tag.reference || module.typeOf(value) != member.root || !sameTarget(module, module.reference(value), member.target) || content_slot >= contents.len || contents[content_slot] != value { return blot_error::Error.invalid_artifact; } content_slot += 1;
                }
            },
            given match_payload_33 => { let given = match_payload_33.value;
                let error = givenArguments(module, given, goal, scopes); if error != blot_error::Error.none { return error; } if arguments.b != given.arguments.len || selection.members.len != declaration.members.len { return blot_error::Error.invalid_artifact; }
                var substitution = Principal { left: module.types, right: module.types, remaining: scopes.remaining, views: scopes , ..}; let actuals = module.types.list(given.arguments);
                for expected, index in module.types.list(List { arguments.a, arguments.b , ..}) { let error = substitution.substituted(formals, witnesses, expected, actuals[index]); if error != blot_error::Error.none { return error; } }
                for member, ordinal in module.contract_members[declaration.members.start..declaration.members.start + declaration.members.len] { let error = step(scopes); if error != blot_error::Error.none { return error; } let value = nodes[ordinal];
                    if member.kind != blot_reuse_principal_interface::ContractMemberKind.value { if value != 0 { return blot_error::Error.invalid_artifact; } continue; }
                    if value == 0 || module.node(value).tag != blot_check_core::Tag.reference { return blot_error::Error.invalid_artifact; } var matching = false;
                    for method in module.dictionary_uses { let error = step(scopes); if error != blot_error::Error.none { return error; } if method.node != value { continue; }
                        if matching || method.opening != given.opening || method.introduction != given.introduction || method.quantifier != given.quantifier || method.goal != given.goal || method.member != ordinal { return blot_error::Error.invalid_artifact; } matching = true;
                    }
                    if !matching { return blot_error::Error.invalid_artifact; } let error = use(module, value, scopes); if error != blot_error::Error.none { return error; } if content_slot >= contents.len || contents[content_slot] != value { return blot_error::Error.invalid_artifact; } content_slot += 1;
                }
            },
        } count += 1;
    }
    for selection in module.dictionary_selections { let error = step(scopes); if error != blot_error::Error.none { return error; } if selection.owner == id {
        if selection.quantifier != node.ty || selection.goal >= goals.len || selection.contents.len != contents.len || count == 0 { return blot_error::Error.invalid_artifact; }
        if module.extra[selection.contents.start..selection.contents.start + selection.contents.len] != contents { return blot_error::Error.invalid_artifact; } count -= 1;
    } }
    if count != 0 || content_slot != contents.len { return blot_error::Error.invalid_artifact; } return blot_error::Error.none;
}
struct PackProjection { module: const Module&, owner: Id }
fn resolver(self_: PackProjection&) -> PackProjection& { return self_; }
fn validate(self_: PackProjection&, substitution: const blot_check_package_contracts::Substitution&, expected: Id, actual: Id) -> Error {
    let module = self_.module; let node = module.node(self_.owner);
    if node.tag != blot_check_core::Tag.package_pack || !blot_check_package_contracts::sameTypes(substitution.types, module.types) { return blot_error::Error.invalid_artifact; } let owner = module.types.node(node.ty);
    if substitution.formal.start != owner.b || substitution.formal.len != owner.c { return blot_error::Error.invalid_artifact; } let witnesses = module.types.list(List { node.b, node.c , ..}); if witnesses != substitution.witnesses { return blot_error::Error.invalid_artifact; }
    let projection = module.types.node(expected); if projection.tag != blot_check_types::Tag.projection { return blot_error::Error.invalid_artifact; } let arguments = module.types.nominalArguments(projection); let goals = module.types.quantifierGoals(node.ty);
    for selection in module.dictionary_selections { if substitution.remaining == 0 { return blot_error::Error.invalid_artifact; } substitution.remaining -= 1; if selection.owner != self_.owner || selection.quantifier != node.ty { continue; } if selection.goal >= goals.len { return blot_error::Error.invalid_artifact; } let goal = goals[selection.goal];
        if goal.kind != blot_check_types::ObligationKind.contract || goal.identity.unit != projection.a || goal.identity.decl != projection.b { continue; }
        var selected: u32 = 0; match selection.proof { selected match_payload_30 => { let value = match_payload_30.value;  selected = value; }, given match_payload_31 => { let value = match_payload_31.value;  continue; }, }
        let proof = module.selected_proofs[selected]; let goal_arguments = module.types.node(goal.ty); if goal_arguments.tag != blot_check_types::Tag.product || goal_arguments.b != proof.arguments.len { return blot_error::Error.invalid_artifact; } if arguments.len != proof.arguments.len { continue; }
        var comparison = Principal { left: module.types, right: module.types, remaining: substitution.remaining, views: substitution.views , ..}; var matches = true; let required = module.types.list(List { goal_arguments.a, goal_arguments.b , ..}); let actuals = module.types.list(proof.arguments);
        for argument, index in arguments {
            if comparison.substituted(substitution.formal, substitution.witnesses, required[index], actuals[index]) != blot_error::Error.none { matches = false; break; }
            if comparison.substituted(substitution.formal, substitution.witnesses, argument, actuals[index]) != blot_error::Error.none { matches = false; break; }
        } if !matches { if substitution.remaining == 0 { return blot_error::Error.invalid_artifact; } continue; }
        let member_name = module.types.projectionMember(projection); let declaration, error = contract(module, goal); if error != blot_error::Error.none { return error; } if declaration.members.len != proof.members.len { return blot_error::Error.invalid_artifact; }
        let selected_members = module.selected_members[proof.members.start..proof.members.start + proof.members.len];
        for member, index in module.contract_members[declaration.members.start..declaration.members.start + declaration.members.len] { if substitution.remaining == 0 { return blot_error::Error.invalid_artifact; } substitution.remaining -= 1; if member.name != member_name { continue; } let selected = selected_members[index];
            if member.kind == blot_reuse_principal_interface::ContractMemberKind.value || selected.kind != blot_reuse_principal_interface::ImplementationMemberKind.type_ || selected.name != member_name { return blot_error::Error.invalid_artifact; } return comparison.validate(selected.root, actual);
        } return blot_error::Error.invalid_artifact;
    } return blot_error::Error.invalid_artifact;
}
fn use(module: const Module&, id: Id, scopes: Context&) -> Error {
    if module.dictionary_uses.len == 0 { return blot_error::Error.none; } let reference = module.reference(id); if reference.unit != 0 && reference.unit != module.unit { return blot_error::Error.none; } var synthetic = false; var found = false;
    for value in module.dictionary_uses { let error = step(scopes); if error != blot_error::Error.none { return error; } if value.binding == reference.binding { synthetic = true; } if value.node != id { continue; } if found { return blot_error::Error.invalid_artifact; } found = true;
        let owner = module.types.node(value.quantifier); var opened = List {..};
        if value.introduction != 0 { if value.opening != 0 || owner.tag != blot_check_types::Tag.forall { return blot_error::Error.invalid_artifact; } var active = false; for index in 0..scopes.formal_count { if scopes.formals[index] == value.quantifier && scopes.introductions[index] == value.introduction { active = true; } } if !active { return blot_error::Error.invalid_artifact; } opened = List { owner.b, owner.c , ..}; }
        else { var active = blot_support::none<List>(); for index in 0..scopes.opening_count { let error = step(scopes); if error != blot_error::Error.none { return error; } let opening = scopes.openings[index]; if opening.binding == value.opening { active = blot_support::some(opening.binders); } } if !active.present { return blot_error::Error.invalid_artifact; } opened = active.value; var source: Id = 0;
            for node, ordinal in module.nodes { let error = step(scopes); if error != blot_error::Error.none { return error; } if node.tag != blot_check_core::Tag.package_unpack || node.b != value.opening { continue; } if source != 0 { return blot_error::Error.invalid_artifact; } source = ordinal as u32; }
            if source == 0 || module.typeOf(module.node(source).a) != value.quantifier { return blot_error::Error.invalid_artifact; }
        }
        let goals = module.types.quantifierGoals(value.quantifier); if value.goal >= goals.len { return blot_error::Error.invalid_artifact; } let goal = goals[value.goal]; let declaration, error = contract(module, goal); if error != blot_error::Error.none { return error; }
        if value.member >= declaration.members.len || declaration.variables.len > 128 { return blot_error::Error.invalid_artifact; } let member = module.contract_members[declaration.members.start + value.member]; if member.kind != blot_reuse_principal_interface::ContractMemberKind.value { return blot_error::Error.invalid_artifact; }
        let arguments = module.types.node(goal.ty); if arguments.tag != blot_check_types::Tag.product || arguments.b != declaration.parameters.len { return blot_error::Error.invalid_artifact; }
        var replacements: Id[128] = [0; 128]; var selector = Principal { left: module.types, right: module.types, remaining: scopes.remaining, views: scopes , ..}; let actuals = module.types.list(List { arguments.a, arguments.b , ..});
        for parameter, index in module.types.list(declaration.parameters) { let error = selector.substituted(declaration.variables, replacements[..declaration.variables.len], parameter, actuals[index]); if error != blot_error::Error.none { return error; } for ordinal in 0..declaration.variables.len { replacements[ordinal] = selector.witnesses[ordinal]; } }
        for replacement in replacements[..declaration.variables.len] { if replacement == 0 { return blot_error::Error.invalid_artifact; } } var proof = Principal { left: module.types, right: module.types, remaining: scopes.remaining, views: scopes , ..};
        let error = proof.composed(declaration.variables, replacements[..declaration.variables.len], List { owner.b, owner.c , ..}, module.types.list(opened), member.root, module.typeOf(id)); if error != blot_error::Error.none { return error; }
    } if synthetic && !found { return blot_error::Error.invalid_artifact; } return blot_error::Error.none;
}
fn matchInstantiated(module: const Module&, producer: const Module&, formals: List, witnesses: const Id[:], inputs: const Id[:], actuals: const Id[:], scopes: Context&) -> bool {
    for expected, index in inputs { var comparison = Principal { left: producer.types, right: module.types, remaining: scopes.remaining, views: scopes , ..}; if comparison.substituted(formals, witnesses, expected, actuals[index]) != blot_error::Error.none { return false; } } return true;
}
fn instantiated(module: const Module&, producer: const Module&, quantifier: Id, witnesses: const Id[:], scopes: Context&) -> Error {
    let owner = producer.types.node(quantifier); let formals = List { owner.b, owner.c , ..}; if owner.tag != blot_check_types::Tag.forall || formals.len != witnesses.len { return blot_error::Error.invalid_artifact; }
    for goal in producer.types.quantifierGoals(quantifier) { let error = step(scopes); if error != blot_error::Error.none { return error; } if goal.kind != blot_check_types::ObligationKind.contract { return blot_error::Error.invalid_artifact; } let arguments = producer.types.node(goal.ty); if arguments.tag != blot_check_types::Tag.product { return blot_error::Error.invalid_artifact; }
        let inputs = producer.types.list(List { arguments.a, arguments.b , ..}); var found = false;
        for proof in module.selected_proofs { let error = step(scopes); if error != blot_error::Error.none { return error; } if proof.kind != blot_reuse_principal_interface::SelectedProofKind.implementation || proof.contract.unit != goal.identity.unit || proof.contract.decl != goal.identity.decl || proof.arguments.len != inputs.len { continue; }
            if matchInstantiated(module, producer, formals, witnesses, inputs, module.types.list(proof.arguments), scopes) { found = true; break; }
        }
        if !found { for index in 0..scopes.formal_count { for given in module.types.quantifierGoals(scopes.formals[index]) { let error = step(scopes); if error != blot_error::Error.none { return error; } if given.kind != blot_check_types::ObligationKind.contract || given.identity.unit != goal.identity.unit || given.identity.decl != goal.identity.decl { continue; }
                    let parameters = module.types.node(given.ty); if parameters.tag != blot_check_types::Tag.product || parameters.b != inputs.len { continue; }
                    if matchInstantiated(module, producer, formals, witnesses, inputs, module.types.list(List { parameters.a, parameters.b , ..}), scopes) { found = true; break; }
                } if found { break; }
        } }
        if !found { for index in 0..scopes.scheme_count { let goals, error = scopes.schemeGoals(scopes.schemes[index]); if error != blot_error::Error.none { return error; } for given in goals { let error = step(scopes); if error != blot_error::Error.none { return error; } if given.kind != blot_check_types::ObligationKind.contract || given.identity.unit != goal.identity.unit || given.identity.decl != goal.identity.decl { continue; }
                    let parameters = module.types.node(given.ty); if parameters.tag != blot_check_types::Tag.product || parameters.b != inputs.len { continue; }
                    if matchInstantiated(module, producer, formals, witnesses, inputs, module.types.list(List { parameters.a, parameters.b , ..}), scopes) { found = true; break; }
                } if found { break; }
        } }
        if !found { return blot_error::Error.invalid_artifact; }
    } return blot_error::Error.none;
}
