namespace blot_backend_opaque_storage;
import check.types;
import check.frozen_types;
import support.option;

enum Kind { unknown, unit, boolean, unsigned32, floating32, reference, parameter }
struct Storage { kind: Kind = Kind.unknown, parameter: u32 = 0, selector: u32 = 0 }
fn kindCode(kind: Kind) -> u8 {
    for value, index in [Kind.unknown, Kind.unit, Kind.boolean, Kind.unsigned32, Kind.floating32, Kind.reference, Kind.parameter] { if value == kind { return index as u8; } } abort("invalid opaque storage kind");
}
struct Authority { graph: blot_check_frozen_types::Graph, parameters: blot_check_types::List, storage: Storage, is_opaque: bool }
struct AuthorityEntry { identity: blot_check_types::NominalIdentity, authority: Authority }
struct Resolver { entries: const AuthorityEntry[:] }
fn lookup(resolver: Resolver,identity: blot_check_types::NominalIdentity) -> const Authority? {
    for &entry in resolver.entries { if entry.identity == identity { return entry.authority; } } return null;
}
struct Frame { parameters: const blot_check_types::Id[:] = [],arguments: const blot_check_types::Id[:] = [],parent: u32 = 0 }
struct Context { frames: Frame[256]&,current: u32 = 0 }
fn infer<N, C>(source: blot_check_frozen_types::Source, nominals: const N[:], constructors: const C[:], nominal_index: u32, remaining: i64&) -> Storage {
    let nominal = nominals[nominal_index]; let constructor_ids = source.list(nominal.constructors);
    if !nominal.is_opaque || constructor_ids.len != 1 { return Storage {}; }
    return inferPayload(source, nominals, constructors, constructors[constructor_ids[0]].payload, nominal.parameters, remaining);
}
fn inferPayload<N, C>(source: blot_check_frozen_types::Source, nominals: const N[:], constructors: const C[:], payload: blot_check_types::Id, parameters: blot_check_types::List, remaining: i64&) -> Storage {
    var frames: Frame[256] = [Frame {};256]; frames[0] = Frame { parameters: source.list(parameters),arguments: [] }; let context = Context { frames };
    return expression(source, nominals, constructors, payload, context, 0, remaining, false, 0, Resolver { entries: [] });
}
fn inferPayloadAuthoritative<N, C>(source: blot_check_frozen_types::Source, nominals: const N[:], constructors: const C[:], payload: blot_check_types::Id, parameters: blot_check_types::List, local_unit: u32, resolver: Resolver, remaining: i64&) -> Storage {
    var frames: Frame[256] = [Frame {};256]; frames[0] = Frame { parameters: source.list(parameters),arguments: [] }; let context = Context { frames };
    return authoritativeExpression(source, nominals, constructors, payload, context, local_unit, resolver, 0, remaining);
}
recursive fn authoritativeExpression<N, C>(source: blot_check_frozen_types::Source, nominals: const N[:], constructors: const C[:], original: blot_check_types::Id, context: const Context&, local_unit: u32, resolver: Resolver, depth: i64, remaining: i64&) -> Storage {
    expression(source, nominals, constructors, original, context, depth, remaining, true, local_unit, resolver)
}
recursive fn expression<N, C>(source: blot_check_frozen_types::Source, nominals: const N[:], constructors: const C[:], original: blot_check_types::Id, context: const Context&, depth: i64, remaining: i64&, authoritative: bool, local_unit: u32, resolver: Resolver) -> Storage {
    if depth >= 256 || remaining == 0 { return Storage {}; } remaining--;
    let ty = source.head(original, 0); let node = source.node(ty);
    if node.tag == blot_check_types::Tag.unit { return Storage { kind: Kind.unit }; }
    if node.tag == blot_check_types::Tag.boolean { return Storage { kind: Kind.boolean }; }
    if node.tag == blot_check_types::Tag.unsigned32 || node.tag == blot_check_types::Tag.never || node.tag == blot_check_types::Tag.type_constructor { return Storage { kind: Kind.unsigned32 }; }
    if node.tag == blot_check_types::Tag.floating32 { return Storage { kind: Kind.floating32 }; }
    if node.tag == blot_check_types::Tag.variable {
        for parameter, index in context.frames[context.current].parameters {
            if remaining == 0 { return Storage {}; } remaining--;
            var selector: u32 = 0; var actual: blot_check_types::Id = 0;
            if context.frames[context.current].parent != 0 { if index >= context.frames[context.current].arguments.len { return Storage {}; } actual = context.frames[context.current].arguments[index]; }
            let selected = select(source, parameter, actual, Target { by_ordinal: false, value: ty }, selector, depth + 1, remaining);
            if !selected.present { continue; }
            if context.frames[context.current].parent != 0 { return expression(source, nominals, constructors, selected.value.actual, Context { context.frames,context.frames[context.current].parent - 1 }, depth + 1, remaining, authoritative, local_unit, resolver); }
            return Storage { kind: Kind.parameter, parameter: index as u32, selector: selected.value.selector };
        }
        return Storage {};
    }
    if node.tag == blot_check_types::Tag.nominal {
        let arguments = source.nominalArguments(node);
        if authoritative && node.a != local_unit {
            let authority .= lookup(resolver, blot_check_types::NominalIdentity { unit: node.a, decl: node.b }); if authority == null { return Storage {}; }
            if !authority.is_opaque { return Storage { kind: Kind.reference }; }
            let storage = authority.storage; if storage.kind == Kind.unknown { return Storage {}; } if storage.kind != Kind.parameter { return storage; }
            let parameter_source = blot_check_frozen_types::Source.frozen { value: authority.graph }; let declared = parameter_source.list(authority.parameters);
            if storage.parameter >= declared.len || storage.parameter >= arguments.len { return Storage {}; }
            var ordinal: u32 = 0;
            let argument = selectAcross(parameter_source, declared[storage.parameter], source, arguments[storage.parameter], storage.selector, ordinal, depth + 1, remaining);
            if !argument.present { return Storage {}; }
            return expression(source, nominals, constructors, argument.value, context, depth + 1, remaining, true, local_unit, resolver);
        }
        for nominal in nominals {
            if remaining == 0 { return Storage {}; } remaining--;
            if nominal.identity.unit != node.a || nominal.identity.decl != node.b { continue; }
            if !nominal.is_opaque { return Storage { kind: Kind.reference }; }
            if !authoritative && nominal.storage.kind != Kind.unknown {
                if nominal.storage.kind != Kind.parameter { return nominal.storage; }
                if nominal.storage.parameter >= arguments.len { return Storage {}; }
                var ordinal: u32 = 0;
                let argument = selectOrdinal(source, source.list(nominal.parameters)[nominal.storage.parameter], arguments[nominal.storage.parameter], nominal.storage.selector, ordinal, depth + 1, remaining);
                if !argument.present { return Storage {}; }
                return expression(source, nominals, constructors, argument.value, context, depth + 1, remaining, false, local_unit, resolver);
            }
            let ids = source.list(blot_check_types::List { start: nominal.constructors.start, len: nominal.constructors.len });
            if ids.len != 1 { return Storage {}; }
            if context.current + 1 >= 256 { return Storage {}; } let frame = context.current + 1; context.frames[frame] = Frame { parameters: source.list(blot_check_types::List { start: nominal.parameters.start,len: nominal.parameters.len }),arguments,parent: context.current + 1 }; let nested = Context { context.frames,frame };
            return expression(source, nominals, constructors, constructors[ids[0]].payload, nested, depth + 1, remaining, authoritative, local_unit, resolver);
        }
        return Storage {};
    }
    if node.tag == blot_check_types::Tag.array || node.tag == blot_check_types::Tag.list || node.tag == blot_check_types::Tag.cursor || node.tag == blot_check_types::Tag.record || node.tag == blot_check_types::Tag.product || node.tag == blot_check_types::Tag.function || node.tag == blot_check_types::Tag.provider || node.tag == blot_check_types::Tag.state_provider { return Storage { kind: Kind.reference }; }
    if node.tag == blot_check_types::Tag.usage {
        if node.b == blot_check_types::usagekind_unique || node.b == blot_check_types::usagekind_shared { return Storage { kind: Kind.reference }; }
        return expression(source, nominals, constructors, node.a, context, depth + 1, remaining, authoritative, local_unit, resolver);
    }
    return Storage {};
}
struct Selected { selector: u32, actual: blot_check_types::Id }
struct Target { by_ordinal: bool, value: u32 }
recursive fn select(source: blot_check_frozen_types::Source, parameter: blot_check_types::Id, actual: blot_check_types::Id, target: Target, ordinal: u32&, depth: i64, remaining: i64&) -> blot_support::Option<Selected> {
    if depth >= 256 || remaining == 0 { return blot_support::none<Selected>(); } remaining--;
    let node = source.node(source.head(parameter, 0));
    if node.tag == blot_check_types::Tag.variable {
        let selected = ordinal; ordinal++; var matches = selected == target.value; if !target.by_ordinal { matches = source.head(parameter, 0) == target.value; }
        if matches { return blot_support::some(Selected { selector: selected, actual: actual }); } return blot_support::none<Selected>();
    }
    let argument = source.node(source.head(actual, 0));
    if node.tag == blot_check_types::Tag.product {
        let children = source.list(blot_check_types::List { start: node.a, len: node.b });
        for child, index in children {
            var supplied: u32 = 0;
            if actual != 0 { if argument.tag != blot_check_types::Tag.product || argument.b != node.b { return blot_support::none<Selected>(); } supplied = source.list(blot_check_types::List { start: argument.a, len: argument.b })[index]; }
            let found = select(source, child, supplied, target, ordinal, depth + 1, remaining); if found.present { return found; }
        }
    } else if node.tag == blot_check_types::Tag.record {
        for index in 0..node.b {
            let field = source.recordField(node, index); var supplied: u32 = 0;
            if actual != 0 {
                if argument.tag != blot_check_types::Tag.record { return blot_support::none<Selected>(); }
                for slot in 0..argument.b { if remaining == 0 { return blot_support::none<Selected>(); } remaining--; let candidate = source.recordField(argument, slot); if candidate.name == field.name { supplied = candidate.ty; break; } }
                if supplied == 0 { return blot_support::none<Selected>(); }
            }
            let found = select(source, field.ty, supplied, target, ordinal, depth + 1, remaining); if found.present { return found; }
        }
    }
    return blot_support::none<Selected>();
}
recursive fn selectAcross(parameter_source: blot_check_frozen_types::Source, parameter: blot_check_types::Id, actual_source: blot_check_frozen_types::Source, actual: blot_check_types::Id, target: u32, ordinal: u32&, depth: i64, remaining: i64&) -> blot_support::Option<blot_check_types::Id> {
    if depth >= 256 || remaining == 0 { return blot_support::none<blot_check_types::Id>(); } remaining--;
    let node = parameter_source.node(parameter_source.head(parameter, 0));
    if node.tag == blot_check_types::Tag.variable { let selected = ordinal; ordinal++; if selected == target { return blot_support::some(actual); } return blot_support::none<blot_check_types::Id>(); }
    let argument = actual_source.node(actual_source.head(actual, 0));
    if node.tag == blot_check_types::Tag.product {
        let children = parameter_source.list(blot_check_types::List { start: node.a, len: node.b });
        if actual != 0 && (argument.tag != blot_check_types::Tag.product || argument.b != node.b) { return blot_support::none<blot_check_types::Id>(); }
        for child, index in children {
            var supplied: u32 = 0; if actual != 0 { supplied = actual_source.list(blot_check_types::List { start: argument.a, len: argument.b })[index]; }
            let found = selectAcross(parameter_source, child, actual_source, supplied, target, ordinal, depth + 1, remaining); if found.present { return found; }
        }
    } else if node.tag == blot_check_types::Tag.record {
        if actual != 0 && argument.tag != blot_check_types::Tag.record { return blot_support::none<blot_check_types::Id>(); }
        for index in 0..node.b {
            let field = parameter_source.recordField(node, index); var supplied: u32 = 0;
            if actual != 0 {
                for slot in 0..argument.b { if remaining == 0 { return blot_support::none<blot_check_types::Id>(); } remaining--; let candidate = actual_source.recordField(argument, slot); if candidate.name == field.name { supplied = candidate.ty; break; } }
                if supplied == 0 { return blot_support::none<blot_check_types::Id>(); }
            }
            let found = selectAcross(parameter_source, field.ty, actual_source, supplied, target, ordinal, depth + 1, remaining); if found.present { return found; }
        }
    }
    return blot_support::none<blot_check_types::Id>();
}
fn selectOrdinal(source: blot_check_frozen_types::Source, parameter: blot_check_types::Id, actual: blot_check_types::Id, target: u32, ordinal: u32&, depth: i64, remaining: i64&) -> blot_support::Option<blot_check_types::Id> {
    let selected = select(source, parameter, actual, Target { by_ordinal: true, value: target }, ordinal, depth, remaining);
    if !selected.present { return blot_support::none<blot_check_types::Id>(); } return blot_support::some(selected.value.actual);
}
