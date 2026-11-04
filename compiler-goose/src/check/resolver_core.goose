// Dispatch belongs to declaration catalogs; selected arrows describe a use.
namespace blot_check_resolver_core;
import support.error;
import support.option;
import .staging_type_match;
type Error = blot_error::Error;
type Module = blot_check_core::Module;
type Id = blot_check_core::Id;
type BindingRef = blot_check_core::BindingRef;
type Identity = blot_check_types::NominalIdentity;
type Workspace = blot_check_scheme_equations::Workspace;
fn owner(m: const Module&, units: const (const Module&)[:], target: BindingRef) -> const Module?, Error { return ownerWorkspace(m, units, target, null); }
fn ownerWorkspace(m: const Module&, units: const (const Module&)[:], target: BindingRef, workspace: Workspace?) -> const Module?, Error {
    if target.unit == 0 || target.unit == m.unit { if target.binding >= m.bindings.len { return null, Error.invalid_artifact; } return m, Error.none; }
    var found: const Module? = null; for candidate in units { if candidate.unit != target.unit { continue; } if found != null || target.binding >= candidate.bindings.len { return null, Error.invalid_artifact; }
        let error = blot_check_scheme_equations::bounds(workspace, candidate, blot_check_frozen_core_validation::Options { units }); if error != Error.none { return null, error; } found = candidate;
    } if found == null { return null, Error.invalid_artifact; } return found, Error.none;
}
fn family(m: const Module&, id: Id) -> Identity, Error {
    let metadata = m.resolverInfo(id); var token = m.types.node(m.typeOf(metadata.resolver));
    if metadata.operation != blot_check_core::ResolverOperation.monad { if token.tag != blot_check_types::Tag.resolver || token.b != 0 || token.c != 0 { return Identity {}, Error.invalid_artifact; } token = m.types.node(token.a); }
    if token.tag != blot_check_types::Tag.type_constructor || token.c != 0 { return Identity {}, Error.invalid_artifact; } return Identity { token.a, token.b }, Error.none;
}
fn shape(m: const Module&, id: Id) -> Error {
    let node = m.node(id); if node.tag != blot_check_core::Tag.resolver_op || node.b != 0 || node.c != 0 || node.op != blot_check_core::Op.none { return Error.invalid_artifact; }
    let metadata = m.resolverInfo(id); let identity, error = family(m, id); if error != Error.none { return error; } let arguments = m.resolverArguments(id); var arity: i64 = 0;
    match metadata.operation { blot_check_core::ResolverOperation.monad {} blot_check_core::ResolverOperation.pure, blot_check_core::ResolverOperation.forward, blot_check_core::ResolverOperation.run { arity = 1; } blot_check_core::ResolverOperation.bind, blot_check_core::ResolverOperation.iterate { arity = 2; } }
    if arguments.len != arity { return Error.invalid_artifact; } let output = m.types.node(m.typeOf(id));
    if metadata.operation == blot_check_core::ResolverOperation.monad { if output.tag != blot_check_types::Tag.resolver || output.b != 0 || output.c != 0 { return Error.invalid_artifact; } let token = m.types.node(output.a); if token.tag != blot_check_types::Tag.type_constructor || token.a != identity.unit || token.b != identity.decl || token.c != 0 { return Error.invalid_artifact; } }
    else if output.tag != blot_check_types::Tag.nominal || output.a != identity.unit || output.b != identity.decl { return Error.invalid_artifact; }
    if metadata.operation == blot_check_core::ResolverOperation.monad || metadata.operation == blot_check_core::ResolverOperation.forward || metadata.operation == blot_check_core::ResolverOperation.run { if metadata.member != 0 || metadata.method.unit != 0 || metadata.method.binding != 0 || metadata.method_type != 0 { return Error.invalid_artifact; } } return Error.none;
}
fn call(m: const Module&, units: const (const Module&)[:], id: Id, remaining: i64&) -> blot_check_core::Call, Error { return callWorkspace(m, units, id, remaining, null); }
fn callWorkspace(m: const Module&, units: const (const Module&)[:], id: Id, remaining: i64&, workspace: Workspace?) -> blot_check_core::Call, Error {
    if m.node(id).tag == blot_check_core::Tag.call { return m.call(id), Error.none; } if m.node(id).tag != blot_check_core::Tag.resolver_op { return default<blot_check_core::Call>(), Error.invalid_artifact; }
    let error = shape(m, id); if error != Error.none { return default<blot_check_core::Call>(), error; } let metadata = m.resolverInfo(id);
    if metadata.operation != blot_check_core::ResolverOperation.pure && metadata.operation != blot_check_core::ResolverOperation.bind && metadata.operation != blot_check_core::ResolverOperation.iterate { return default<blot_check_core::Call>(), Error.invalid_artifact; }
    if metadata.member == 0 || metadata.method_type == 0 { return default<blot_check_core::Call>(), Error.invalid_artifact; }
    let identity, error = family(m, id); if error != Error.none { return default<blot_check_core::Call>(), error; } let actual, error = methodWorkspace(m, units, identity, metadata.member, remaining, workspace); if error != Error.none { return default<blot_check_core::Call>(), error; }
    if metadata.method.binding != 0 { var selected = metadata.method; if selected.unit == 0 { selected.unit = m.unit; } if selected != actual { return default<blot_check_core::Call>(), Error.invalid_artifact; } }
    return blot_check_core::Call { actual, metadata.method_type, m.resolverArguments(id) }, Error.none;
}
fn method(m: const Module&, units: const (const Module&)[:], identity: Identity, member: u32, remaining: i64&) -> BindingRef, Error { return methodWorkspace(m, units, identity, member, remaining, null); }
fn methodWorkspace(m: const Module&, units: const (const Module&)[:], identity: Identity, member: u32, remaining: i64&, workspace: Workspace?) -> BindingRef, Error {
    var nominal_owner: const Module& = m;
    let storage = blot_check_storage_types::identity(identity.unit, identity.decl);
    if identity.unit != 0 && identity.unit != m.unit && !storage.present {
        var found: const Module? = null; for unit in units { if unit.unit == identity.unit { if found != null { return BindingRef {}, Error.invalid_artifact; } found = unit; } }
        if let found = found { nominal_owner = found; } else { return BindingRef {}, Error.invalid_artifact; }
        let error = blot_check_scheme_equations::bounds(workspace, nominal_owner, blot_check_frozen_core_validation::Options { units }); if error != Error.none { return BindingRef {}, error; }
    }
    var target = blot_support::none<BindingRef>(); let catalogs: (const Module&)[2] = [m, nominal_owner];
    for catalog, index in catalogs { if index == 1 && catalog.owner_id == m.owner_id { continue; }
        for entry in catalog.associated { if remaining == 0 { return BindingRef {}, Error.invalid_artifact; } remaining -= 1;
            if entry.member != member || !blot_check_staging_type_match::sameIdentity(catalog, entry.identity, m, identity) { continue; } var selected = entry.target; if selected.unit == 0 { selected.unit = catalog.unit; }
            let producer, error = ownerWorkspace(m, units, selected, workspace); if error != Error.none { return BindingRef {}, error; }
            if let producer = producer { if producer.owner_id != m.owner_id && producer.bindings[selected.binding].private { continue; } } else { return BindingRef {}, Error.invalid_artifact; }
            if target.present && target.value != selected { return BindingRef {}, Error.invalid_artifact; } target = blot_support::some(selected);
        } if target.present { break; }
    } if !target.present { return BindingRef {}, Error.invalid_artifact; } return target.value, Error.none;
}
struct Judgments { factory: blot_support::Option<blot_check_core::Obligation> = blot_support::none<blot_check_core::Obligation>(), dispatch: blot_support::Option<blot_check_core::Obligation> = blot_support::none<blot_check_core::Obligation>(), result: blot_support::Option<blot_check_core::Obligation> = blot_support::none<blot_check_core::Obligation>(), callback: Id = 0 }
fn judgments(m: const Module&, id: Id) -> Judgments, Error {
    let node = m.node(id); if node.tag != blot_check_core::Tag.resolver_op || node.op != blot_check_core::Op.none || node.b != 0 || node.c != 0 { return Judgments {}, Error.invalid_artifact; }
    let info = m.resolverInfo(id); let arguments = m.resolverArguments(id); var arity: i64 = 1; if info.operation == blot_check_core::ResolverOperation.monad { arity = 0; } if info.operation == blot_check_core::ResolverOperation.bind || info.operation == blot_check_core::ResolverOperation.iterate { arity = 2; }
    if arguments.len != arity { return Judgments {}, Error.invalid_artifact; } let span = m.span(id); let provider = m.typeOf(info.resolver); var result = Judgments {};
    if info.operation == blot_check_core::ResolverOperation.monad || info.operation == blot_check_core::ResolverOperation.forward || info.operation == blot_check_core::ResolverOperation.run { if info.member != 0 || info.method.unit != 0 || info.method.binding != 0 || info.method_type != 0 { return result, Error.invalid_artifact; } }
    else { if info.member == 0 || info.method_type == 0 { return result, Error.invalid_artifact; } result.dispatch = blot_support::some(blot_check_core::Obligation { kind: blot_check_types::ObligationKind.resolver_dispatch, ty: provider, other: info.method_type, result: node.ty, name: info.member, span }); }
    if info.operation == blot_check_core::ResolverOperation.monad { result.factory = blot_support::some(blot_check_core::Obligation { kind: blot_check_types::ObligationKind.monad_factory, ty: provider, result: node.ty, span }); }
    else { result.result = blot_support::some(blot_check_core::Obligation { kind: blot_check_types::ObligationKind.resolver_shape, ty: provider, result: node.ty, span }); }
    if info.operation == blot_check_core::ResolverOperation.run { result.callback = arguments[0]; } return result, Error.none;
}
fn resolverIdentity(m: const Module&, resolver: blot_check_types::Id) -> blot_support::Option<Identity> {
    let provider = m.types.node(resolver); if provider.tag != blot_check_types::Tag.resolver || provider.b != 0 || provider.c != 0 { return blot_support::none<Identity>(); } let token = m.types.node(provider.a); if token.tag != blot_check_types::Tag.type_constructor || token.c != 0 { return blot_support::none<Identity>(); } return blot_support::some(Identity { token.a, token.b });
}
fn nominal(m: const Module&, units: const (const Module&)[:], family: Identity, remaining: i64&, workspace: Workspace?) -> blot_check_core::Nominal, Error {
    var producer: const Module& = m;
    if family.unit != 0 && family.unit != m.unit { var found: const Module? = null; for unit in units { if unit.unit == family.unit { if found != null { return default<blot_check_core::Nominal>(), Error.invalid_artifact; } found = unit; } }
        if let found = found { producer = found; } else { return default<blot_check_core::Nominal>(), Error.invalid_artifact; }
        let error = blot_check_scheme_equations::bounds(workspace, producer, blot_check_frozen_core_validation::Options { units }); if error != Error.none { return default<blot_check_core::Nominal>(), error; }
    }
    var found = blot_support::none<blot_check_core::Nominal>();
    for entry in producer.nominals { if remaining == 0 { return default<blot_check_core::Nominal>(), Error.invalid_artifact; } remaining -= 1;
        if !blot_check_staging_type_match::sameIdentity(producer, entry.identity, m, family) { continue; } if found.present || (entry.private && producer.owner_id != m.owner_id) { return default<blot_check_core::Nominal>(), Error.invalid_artifact; } found = blot_support::some(entry);
    } if !found.present { return default<blot_check_core::Nominal>(), Error.invalid_artifact; } return found.value, Error.none;
}
fn factory(m: const Module&, units: const (const Module&)[:], goal: blot_check_core::Obligation, remaining: i64&) -> bool, Error { return factoryWorkspace(m, units, goal, remaining, null); }
fn factoryWorkspace(m: const Module&, units: const (const Module&)[:], goal: blot_check_core::Obligation, remaining: i64&, workspace: Workspace?) -> bool, Error {
    if goal.kind != blot_check_types::ObligationKind.monad_factory { return false, Error.invalid_artifact; } let token = m.types.node(goal.ty); if token.tag != blot_check_types::Tag.type_constructor || token.c != 0 { return false, Error.none; }
    let declaration, error = nominal(m, units, Identity { token.a, token.b }, remaining, workspace); if error != Error.none { return false, error; } let actual = resolverIdentity(m, goal.result); if !actual.present { return false, Error.none; }
    return blot_check_staging_type_match::sameIdentity(m, Identity { token.a, token.b }, m, actual.value), Error.none;
}
fn resultShape(m: const Module&, units: const (const Module&)[:], goal: blot_check_core::Obligation, remaining: i64&) -> bool, Error { return resultShapeWorkspace(m, units, goal, remaining, null); }
fn resultShapeWorkspace(m: const Module&, units: const (const Module&)[:], goal: blot_check_core::Obligation, remaining: i64&, workspace: Workspace?) -> bool, Error {
    if goal.kind != blot_check_types::ObligationKind.resolver_shape { return false, Error.invalid_artifact; } let family = resolverIdentity(m, goal.ty); if !family.present { return false, Error.none; }
    let declaration, error = nominal(m, units, family.value, remaining, workspace); if error != Error.none { return false, error; } let output = m.types.node(goal.result);
    return output.tag == blot_check_types::Tag.nominal && blot_check_staging_type_match::sameIdentity(m, family.value, m, Identity { output.a, output.b }) && m.types.nominalArguments(output).len == declaration.parameters.len, Error.none;
}
fn selectedCall(m: const Module&, units: const (const Module&)[:], id: Id, remaining: i64&) -> blot_support::Option<blot_check_core::Call>, Error { return selectedCallWorkspace(m, units, id, remaining, null); }
fn selectedCallWorkspace(m: const Module&, units: const (const Module&)[:], id: Id, remaining: i64&, workspace: Workspace?) -> blot_support::Option<blot_check_core::Call>, Error {
    let info = m.resolverInfo(id); let evidence, error = judgments(m, id); if error != Error.none { return blot_support::none<blot_check_core::Call>(), error; }
    let family = resolverIdentity(m, m.typeOf(info.resolver)); if family.present { let actual, error = methodWorkspace(m, units, family.value, info.member, remaining, workspace); if error != Error.none { return blot_support::none<blot_check_core::Call>(), error; }
        if info.method.binding != 0 { var target = info.method; if target.unit == 0 { target.unit = m.unit; } if actual != target { return blot_support::none<blot_check_core::Call>(), Error.invalid_artifact; } }
        return blot_support::some(blot_check_core::Call { actual, info.method_type, m.resolverArguments(id) }), Error.none;
    } if info.method.unit != 0 || info.method.binding != 0 { return blot_support::none<blot_check_core::Call>(), Error.invalid_artifact; } return blot_support::none<blot_check_core::Call>(), Error.none;
}
