// Typed code arguments retain the result, latent row and qualifiers.
namespace blot_check_typed_staging;
import support.structural;
import support.error;
import support.option;
let code_identity = blot_check_types::NominalIdentity { 0xffffffff, 8 };
let descriptor_identity = blot_check_types::NominalIdentity { 0xffffffff, 9 };
enum Op { quote, splice, lift, emit, run, describe, same, fields, evaluate }
fn lookup(name: const u8[:]) -> Op, bool {
    if name == "@code.evaluate" { return Op.evaluate, true; }
    if name == "@code.quote" { return Op.quote, true; }
    if name == "@code.splice" { return Op.splice, true; }
    if name == "@code.lift" { return Op.lift, true; }
    if name == "@code.emit" { return Op.emit, true; }
    if name == "@code.run" { return Op.run, true; }
    if name == "@code.describe" { return Op.describe, true; }
    if name == "@descriptor.same" { return Op.same, true; }
    if name == "@descriptor.fields" { return Op.fields, true; }
    return Op.quote, false;
}
fn arity(op: Op) -> i64 { if op == Op.same { return 2; } return 1; }
fn isIdentity(unit: u32, declaration: u32) -> bool {
    return unit == code_identity.unit && (declaration == code_identity.decl || declaration == descriptor_identity.decl);
}
fn code(store: blot_check_types::Store&, result: blot_check_types::Id, effects: blot_check_effects::Id) -> blot_check_types::Id, blot_error::Error {
    let latent, error = store.functionWithEffects(blot_check_types::unit, blot_check_types::unit, effects);
    if error != blot_error::Error.none { return 0, error; }
    return store.nominal(code_identity, [result, latent]);
}
fn descriptor(store: blot_check_types::Store&, target: blot_check_types::Id) -> blot_check_types::Id, blot_error::Error { return store.nominal(descriptor_identity, [target]); }
struct Code { result: blot_check_types::Id, effects: blot_check_effects::Id }
fn codeInfo(source, id: blot_check_types::Id) -> blot_support::Option<Code> {
    let node = source.node(id);
    if node.tag != blot_check_types::Tag.nominal || node.a != code_identity.unit || node.b != code_identity.decl { return blot_support::Option<Code> { false, default<Code>() }; }
    let arguments = source.nominalArguments(node);
    if arguments.len != 2 { return blot_support::Option<Code> { false, default<Code>() }; }
    let latent = source.node(arguments[1]);
    if latent.tag != blot_check_types::Tag.function || latent.a != blot_check_types::unit || latent.b != blot_check_types::unit { return blot_support::Option<Code> { false, default<Code>() }; }
    return blot_support::Option<Code> { true, Code { arguments[0], latent.c } };
}
fn descriptorInfo(source, id: blot_check_types::Id) -> blot_support::Option<blot_check_types::Id> {
    let node = source.node(id);
    if node.tag != blot_check_types::Tag.nominal || node.a != descriptor_identity.unit || node.b != descriptor_identity.decl { return blot_support::Option<blot_check_types::Id> { false, 0 }; }
    let arguments = source.nominalArguments(node);
    if arguments.len != 1 { return blot_support::Option<blot_check_types::Id> { false, 0 }; }
    return blot_support::Option<blot_check_types::Id> { true, arguments[0] };
}
fn liftable(source, id: blot_check_types::Id) -> bool, blot_error::Error {
    var remaining: i64 = 4096; return liftableDepth(source, id, 0, remaining);
}
fn compileOnly(source, raw: blot_check_types::Id) -> bool, blot_error::Error {
    var remaining: i64 = 4096; return compileOnlyDepth(source, raw, 0, remaining);
}
recursive fn compileOnlyDepth(source, raw: blot_check_types::Id, depth: i64, remaining: i64&) -> bool, blot_error::Error {
    if depth >= 128 || remaining == 0 { return false, blot_error::Error.type_limit; }
    remaining -= 1;
    let node = source.node(source.head(raw, 0));
    match node.tag {
        nominal => {
            if isIdentity(node.a, node.b) { return true, blot_error::Error.none; }
            for child in source.nominalArguments(node) {
                let found, error = compileOnlyDepth(source, child, depth + 1, remaining);
                if error != blot_error::Error.none || found { return found, error; }
            }
        },
        product => {
            for child in source.list(blot_check_types::List { node.a, node.b }) {
                let found, error = compileOnlyDepth(source, child, depth + 1, remaining);
                if error != blot_error::Error.none || found { return found, error; }
            }
        },
        record => {
            for index in node.b {
                let found, error = compileOnlyDepth(source, source.recordField(node, index).ty, depth + 1, remaining);
                if error != blot_error::Error.none || found { return found, error; }
            }
        },
        function => {
            let first, error = compileOnlyDepth(source, node.a, depth + 1, remaining);
            if error != blot_error::Error.none || first { return first, error; }
            return compileOnlyDepth(source, node.b, depth + 1, remaining);
        },
        usage, array, list, cursor, forall, existential => { return compileOnlyDepth(source, node.a, depth + 1, remaining); },
        _ => {},
    }
    return false, blot_error::Error.none;
}
recursive fn liftableDepth(source, raw: blot_check_types::Id, depth: i64, remaining: i64&) -> bool, blot_error::Error {
    if depth >= 128 || remaining == 0 { return false, blot_error::Error.type_limit; }
    remaining -= 1;
    let node = source.node(source.head(raw, 0));
    match node.tag {
        unit, boolean, unsigned32, floating32 => { return true, blot_error::Error.none; },
        product => {
            for child in source.list(blot_check_types::List { node.a, node.b }) {
                let accepted, error = liftableDepth(source, child, depth + 1, remaining);
                if error != blot_error::Error.none || !accepted { return accepted, error; }
            }
        },
        record => {
            for index in node.b {
                let accepted, error = liftableDepth(source, source.recordField(node, index).ty, depth + 1, remaining);
                if error != blot_error::Error.none || !accepted { return accepted, error; }
            }
        },
        nominal => {
            if isIdentity(node.a, node.b) { return false, blot_error::Error.none; }
            for child in source.nominalArguments(node) {
                let accepted, error = liftableDepth(source, child, depth + 1, remaining);
                if error != blot_error::Error.none || !accepted { return accepted, error; }
            }
        },
        array, list => { return liftableDepth(source, node.a, depth + 1, remaining); },
        _ => { return false, blot_error::Error.none; },
    }
    return true, blot_error::Error.none;
}

fn opCode(value: Op) -> u32 {
    match value {
        quote => { return 0; },
        splice => { return 1; },
        lift => { return 2; },
        emit => { return 3; },
        run => { return 4; },
        describe => { return 5; },
        same => { return 6; },
        fields => { return 7; },
        evaluate => { return 8; },
    }
}
fn opFromCode(code: u32) -> Op, blot_error::Error {
    match code {
        0 => { return Op.quote, blot_error::Error.none; },
        1 => { return Op.splice, blot_error::Error.none; },
        2 => { return Op.lift, blot_error::Error.none; },
        3 => { return Op.emit, blot_error::Error.none; },
        4 => { return Op.run, blot_error::Error.none; },
        5 => { return Op.describe, blot_error::Error.none; },
        6 => { return Op.same, blot_error::Error.none; },
        7 => { return Op.fields, blot_error::Error.none; },
        8 => { return Op.evaluate, blot_error::Error.none; },
        _ => { return Op.quote, blot_error::Error.invalid_artifact; },
    }
}

fn blot_structural::equal(left: blot_check_typed_staging::Op, right: blot_check_typed_staging::Op) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_typed_staging::Op) { blot_structural::hash(sink, blot_check_typed_staging::opCode(value) as! u32); }
