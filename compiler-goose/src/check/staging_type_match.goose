// Staged producer comparison is read-only across independently owned graphs.
namespace blot_check_staging_type_match;
import check.core;
import check.effects;
import check.types;
import support.error;

type Error = blot_error::Error;
fn identity(m: const blot_check_core::Module&, value: blot_check_types::NominalIdentity) -> blot_check_types::NominalIdentity {
    var result = value; if result.unit == 0 && result.decl != 0 { result.unit = m.unit; } return result;
}
fn sameIdentity(left: const blot_check_core::Module&, a: blot_check_types::NominalIdentity,
                 right: const blot_check_core::Module&, b: blot_check_types::NominalIdentity) -> bool { return identity(left, a) == identity(right, b); }
fn step(remaining: i64&, depth: i64) -> Error { if depth >= 128 || remaining == 0 { return blot_error::Error.comparison_limit; } remaining -= 1; return blot_error::Error.none; }
fn row(left: const blot_check_core::Module&, a: blot_check_effects::Id, right: const blot_check_core::Module&, b: blot_check_effects::Id,
        remaining: i64&, depth: i64) -> Error { let error = rowDepth(left, a, right, b, remaining, depth); if error != blot_error::Error.none { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; }
recursive fn rowDepth(left: const blot_check_core::Module&, a: blot_check_effects::Id, right: const blot_check_core::Module&, b: blot_check_effects::Id,
                      remaining: i64&, depth: i64) -> Error {
    let charged = step(remaining, depth); if charged != blot_error::Error.none { return charged; }
    let first = left.types.rowLabels(a); let second = right.types.rowLabels(b);
    if first.len != second.len || first.len > 256 { return blot_error::Error.invalid_artifact; }
    var consumed: bool[256] = [false; 256];
    for label in first {
        let operation = left.types.operations[label]; var matched = false;
        for other, index in second {
            let charged = step(remaining, depth); if charged != blot_error::Error.none { return charged; } if consumed[index] { continue; }
            let candidate = right.types.operations[other];
            if !sameIdentity(left, operation.identity, right, candidate.identity) || !sameIdentity(left, operation.instance, right, candidate.instance) { continue; }
            let xs = left.types.list(operation.arguments); let ys = right.types.list(candidate.arguments); if xs.len != ys.len { continue; }
            var arguments_match = true; var substitutions: blot_check_types::Id[0] = [];
            for x, i in xs { let error = matchDepth(left, x, right, ys[i], [], substitutions, remaining, depth + 1); if error != blot_error::Error.none { if error == blot_error::Error.comparison_limit { return error; } arguments_match = false; break; } }
            if !arguments_match { continue; } matched = true; consumed[index] = true; break;
        }
        if !matched { return blot_error::Error.invalid_artifact; }
    }
    return blot_error::Error.none;
}
fn matchTypes(left: const blot_check_core::Module&, a: blot_check_types::Id, right: const blot_check_core::Module&, b: blot_check_types::Id,
               variables: const blot_check_types::Id[:], substitutions: blot_check_types::Id[:], remaining: i64&, depth: i64) -> Error {
    let error = matchDepth(left, a, right, b, variables, substitutions, remaining, depth); if error != blot_error::Error.none { return blot_error::Error.invalid_artifact; } return blot_error::Error.none;
}
recursive fn matchDepth(left: const blot_check_core::Module&, a: blot_check_types::Id, right: const blot_check_core::Module&, b: blot_check_types::Id,
                        variables: const blot_check_types::Id[:], substitutions: blot_check_types::Id[:], remaining: i64&, depth: i64) -> Error {
    let charged = step(remaining, depth); if charged != blot_error::Error.none { return charged; } let first = left.types.node(a);
    if first.tag == blot_check_types::Tag.variable {
        var index: i64 = -1; for variable, ordinal in variables { if variable == a { index = ordinal; break; } }
        if index < 0 { if left.owner_id == 0 || left.owner_id != right.owner_id || a != b { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; }
        if index >= substitutions.len { return blot_error::Error.invalid_artifact; }
        if substitutions[index] == 0 { substitutions[index] = b; }
        else { var none: blot_check_types::Id[0] = []; return matchDepth(right, substitutions[index], right, b, [], none, remaining, depth + 1); }
        return blot_error::Error.none;
    }
    let second = right.types.node(b); if first.tag != second.tag { return blot_error::Error.invalid_artifact; }
    match first.tag {
        unit, boolean, unsigned32, floating32, never => {},
        array, list => { return matchDepth(left, first.a, right, second.a, variables, substitutions, remaining, depth + 1); },
        usage => {
            if first.b != second.b { return blot_error::Error.invalid_artifact; }
            if first.c == 0 || second.c == 0 { if first.c != second.c { return blot_error::Error.invalid_artifact; } }
            else { let region = matchDepth(left, first.c, right, second.c, variables, substitutions, remaining, depth + 1); if region != blot_error::Error.none { return region; } }
            return matchDepth(left, first.a, right, second.a, variables, substitutions, remaining, depth + 1);
        },
        product => {
            if first.b != second.b { return blot_error::Error.invalid_artifact; }
            let xs = left.types.list(blot_check_types::List { first.a, first.b , ..}); let ys = right.types.list(blot_check_types::List { second.a, second.b , ..});
            for x, i in xs { let error = matchDepth(left, x, right, ys[i], variables, substitutions, remaining, depth + 1); if error != blot_error::Error.none { return error; } }
        },
        record => {
            if first.b != second.b { return blot_error::Error.invalid_artifact; }
            for index in first.b { let field = left.types.recordField(first, index); var found = false;
                for other in second.b { let charged = step(remaining, depth); if charged != blot_error::Error.none { return charged; } let candidate = right.types.recordField(second, other); if field.name != candidate.name { continue; }
                    let error = matchDepth(left, field.ty, right, candidate.ty, variables, substitutions, remaining, depth + 1); if error != blot_error::Error.none { return error; } found = true; break; }
                if !found { return blot_error::Error.invalid_artifact; }
            }
        },
        nominal => {
            if !sameIdentity(left, blot_check_types::NominalIdentity { first.a, first.b , ..}, right, blot_check_types::NominalIdentity { second.a, second.b , ..}) { return blot_error::Error.invalid_artifact; }
            let xs = left.types.nominalArguments(first); let ys = right.types.nominalArguments(second); if xs.len != ys.len { return blot_error::Error.invalid_artifact; }
            for x, i in xs { let error = matchDepth(left, x, right, ys[i], variables, substitutions, remaining, depth + 1); if error != blot_error::Error.none { return error; } }
        },
        function => {
            if left.types.row(first.c).tail != blot_check_effects::Tail.closed || right.types.row(second.c).tail != blot_check_effects::Tail.closed { return blot_error::Error.invalid_artifact; }
            let rows = rowDepth(left, first.c, right, second.c, remaining, depth + 1); if rows != blot_error::Error.none { return rows; }
            let parameter = matchDepth(left, first.a, right, second.a, variables, substitutions, remaining, depth + 1); if parameter != blot_error::Error.none { return parameter; }
            return matchDepth(left, first.b, right, second.b, variables, substitutions, remaining, depth + 1);
        },
        _ => { return blot_error::Error.invalid_artifact; },
    }
    return blot_error::Error.none;
}
