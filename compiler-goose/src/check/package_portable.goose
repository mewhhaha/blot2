// Publication reconstructs lexical package scope from the owned graph.
namespace blot_check_package_portable;
import support.error;
import .package_contracts;
type Error = blot_error::Error;
fn present(nodes: const blot_check_types::Node[:]) -> bool { for node in nodes { if node.tag == blot_check_types::Tag.existential { return true; } } return false; }
fn scheme(types: const blot_check_core::Types&, value: blot_check_types::Scheme) -> Error {
    if value.variables.len != 0 { let owner = types.node(value.root);
        if owner.tag == blot_check_types::Tag.forall { if owner.c != value.variables.len || types.list(value.variables) != types.list(blot_check_types::List { owner.b, owner.c }) { return Error.invalid_artifact; } }
        else { for variable in types.list(value.variables) { if types.node(variable).tag != blot_check_types::Tag.variable { return Error.invalid_artifact; } } }
    } if value.generative.len != 0 { return Error.invalid_artifact; } return Error.none;
}
fn closedViews(context: blot_check_package_contracts::Context&, certificates: blot_check_types::List) -> Error {
    context.pure_rows = blot_check_package_row_facts::Facts {}; context.closed_rows = blot_check_package_row_facts::Facts {};
    for row, id in context.types.effects.rows { if context.remaining == 0 { return Error.invalid_artifact; } context.remaining -= 1;
        match row.tail { blot_check_effects::Tail.variable { value } {
            for variable in context.types.list(certificates) { if context.remaining == 0 { return Error.invalid_artifact; } context.remaining -= 1; if value != variable { continue; }
                let error = context.closed_rows.set(id); if error != Error.none { return error; } if row.labels.len == 0 { let error = context.pure_rows.set(id); if error != Error.none { return error; } }
            }
        } else {} }
    } return Error.none;
}
fn interface(owner: const blot_reuse_principal_interface::Interface&) -> Error {
    if !owner.has_rank_contracts { return Error.invalid_artifact; } var remaining: i64 = 65536; let view = blot_check_associated_admission::typesView(owner.graph);
    var context = blot_check_package_contracts::Context { types: view, remaining, source_obligations: owner.obligations }; let error = context.initialize(); if error != Error.none { return error; }
    for binding, slot in owner.bindings {
        if binding.ty == 0 { continue; } var template = false;
        for member in owner.member_templates { if remaining == 0 { return Error.invalid_artifact; } remaining -= 1; if member.binding == slot { template = true; } } if template { continue; }
        let error = closedViews(context, binding.scheme.closed_rows); if error != Error.none { return error; } let error = context.generic(binding.scheme); if error != Error.none { return error; }
        let error = context.visit(binding.ty); if error != Error.none { return error; } let error = scheme(view, binding.scheme); if error != Error.none { return error; }
        let error = blot_check_scheme_predicates::scope(context, owner.obligations[binding.scheme.obligations.start..binding.scheme.obligations.start + binding.scheme.obligations.len]); if error != Error.none { return error; }
        var proof = blot_check_package_contracts::Principal { left: view, right: view, remaining, views: context, left_rows: binding.scheme.closed_rows }; let error = proof.validate(binding.ty, binding.scheme.root); if error != Error.none { return error; }
    }
    for nominal in owner.nominals { if nominal.alias != 0 && nominal.variables.len == 0 && nominal.alias_rows.len == 0 { let error = context.visit(nominal.alias); if error != Error.none { return error; } } } return Error.none;
}
fn publicCore(owner: const blot_reuse_principal_interface::Interface&, module: const blot_check_core::Module&) -> Error {
    if !owner.has_rank_contracts || !module.has_rank_contracts { return Error.invalid_artifact; }
    let view = blot_check_associated_admission::typesView(owner.graph); var remaining: i64 = 65536;
    var context = blot_check_package_contracts::Context { types: module.types, remaining, obligations: module.obligations }; let error = context.initialize(); if error != Error.none { return error; }
    var proof = blot_check_package_contracts::Principal { left: view, right: module.types, remaining, views: context };
    for binding, id in owner.bindings {
        if binding.ty == 0 { continue; } if id >= module.bindings.len { return Error.invalid_artifact; } var template = false;
        for member in owner.member_templates { if remaining == 0 { return Error.invalid_artifact; } remaining -= 1; if member.binding != id { continue; }
            for candidate in module.member_templates { if remaining == 0 { return Error.invalid_artifact; } remaining -= 1; if candidate.binding == id && candidate.name == member.name && candidate.contract == member.contract { template = true; } } if !template { return Error.invalid_artifact; }
        }
        if template {
            if binding.scheme.variables.len != module.bindings[id].scheme.variables.len { return Error.invalid_artifact; }
            var method = blot_check_package_contracts::Principal { left: view, right: module.types, remaining };
            let error = method.substituted(binding.scheme.variables, module.types.list(module.bindings[id].scheme.variables), binding.ty, module.bindings[id].ty); if error != Error.none { return error; }
            let error = method.substituted(binding.scheme.variables, module.types.list(module.bindings[id].scheme.variables), binding.scheme.root, module.bindings[id].scheme.root); if error != Error.none { return error; } continue;
        }
        let producer = module.bindings[id]; if binding.scheme.closed_rows.len != producer.scheme.closed_rows.len { return Error.invalid_artifact; }
        if producer.scheme.closed_rows.len != 0 {
            if producer.kind == blot_check_check::Kind.external { if producer.target.unit == 0 || producer.target.unit == module.unit || producer.target.binding == 0 { return Error.invalid_artifact; } }
            else { if let body = module.body(id as u32) { for variable in module.types.list(producer.scheme.closed_rows) { if remaining == 0 { return Error.invalid_artifact; } remaining -= 1; if !blot_check_package_contracts::hasVariable(module.types, body.closed_rows, variable) { return Error.invalid_artifact; } } } else { return Error.invalid_artifact; } }
        }
        let error = closedViews(context, producer.scheme.closed_rows); if error != Error.none { return error; } let error = context.generic(producer.scheme); if error != Error.none { return error; }
        proof.left_rows = binding.scheme.closed_rows;
        let error = proof.schemeGoals(binding.scheme, producer.scheme, owner.obligations[binding.scheme.obligations.start..binding.scheme.obligations.start + binding.scheme.obligations.len], module.obligations[producer.scheme.obligations.start..producer.scheme.obligations.start + producer.scheme.obligations.len]); if error != Error.none { return error; }
        if view.node(binding.scheme.root).tag != blot_check_types::Tag.forall && (binding.scheme.variables.len != 0 || binding.scheme.row_variables.len != 0) {
            if binding.scheme.variables.len != producer.scheme.variables.len || binding.scheme.row_variables.len != producer.scheme.row_variables.len { return Error.invalid_artifact; }
            let error = proof.instantiateScheme(binding.scheme, producer.ty); if error != Error.none { return error; } let error = proof.instantiateScheme(binding.scheme, producer.scheme.root); if error != Error.none { return error; }
        } else { let error = proof.validate(binding.ty, producer.ty); if error != Error.none { return error; } let error = proof.validate(binding.scheme.root, producer.scheme.root); if error != Error.none { return error; } }
    } return Error.none;
}
