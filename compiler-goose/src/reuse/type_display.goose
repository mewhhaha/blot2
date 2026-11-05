// Diagnostic rendering shares the source solver's bounded presentation policy.
namespace blot_reuse_type_display;
import check.types;
import check.effects;
import check.storage_types;
import support.error;
type Error = blot_error::Error;
type Tag = blot_check_types::Tag;
fn append<C>(context: C&, bytes: u8[>..<]&, ty: u32) -> Error { var budget: i64 = 256; return appendBounded(context, bytes, ty, budget); }
fn appendBounded<C>(context: C&, bytes: u8[>..<]&, ty: u32, budget: i64&) -> Error { return render(context, bytes, ty, 0, budget, false); }
fn appendStable<C>(context: C&, bytes: u8[>..<]&, ty: u32) -> Error { var budget: i64 = 256; return render(context, bytes, ty, 0, budget, true); }
fn text<C>(context: C&, bytes: u8[>..<]&, value: const u8[:]) -> Error {
    let limit: i64 = 8192;
    if bytes.len >= limit { return blot_error::Error.none; }
    let remaining = limit - bytes.len;
    if value.len <= remaining { bytes.append(value); return blot_error::Error.none; }
    var count = max(remaining - 3, 0);
    while count != 0 && value[count] & 0xc0 == 0x80 { count--; }
    bytes.append(value[..count]); let ellipsis: const u8[:] = "...";
    bytes.append(ellipsis[..min(remaining - count, 3)]); return blot_error::Error.none;
}
fn number<C>(context: C&, bytes: u8[>..<]&, value: u32) -> Error {
    var buffer: u8[16]; var at: i64 = 16; var rest = value;
    loop { at--; buffer[at] = ('0' + rest % 10) as u8; rest /= 10; if rest == 0 { break; } }
    return text(context, bytes, buffer[at..]);
}
fn usageName(code: u32) -> const u8[:] {
    match code { 0 => "unique", 1 => "shared", 2 => "borrow", 3 => "borrow_mut", 4 => "once", 5 => "many", 6 => "cleanup", 7 => "concurrent", _ => { abort("invalid diagnostic usage kind"); } }
}
recursive fn render<C>(context: C&, bytes: u8[>..<]&, ty: u32, depth: i64, budget: i64&, stable: bool) -> Error {
    if depth >= 32 || budget == 0 { return text(context, bytes, "..."); }
    budget--; var root = context.types.head(ty, 0);
    if !stable { let resolved, error = context.types.resolve(ty, 0); if error != blot_error::Error.none { return error; } root = resolved; }
    let node = context.types.node(root);
    match node.tag {
        forall, existential => {
            var keyword: const u8[:] = "forall ["; if node.tag == blot_check_types::Tag.existential { keyword = "exists ["; }
            { let propagated_error = text(context, bytes, keyword); if propagated_error != blot_error::Error.none { return propagated_error; } }
            for index in 0..node.c {
                if budget == 0 { { let propagated_error = text(context, bytes, "..."); if propagated_error != blot_error::Error.none { return propagated_error; } } break; }
                if index != 0 { { let propagated_error = text(context, bytes, ", "); if propagated_error != blot_error::Error.none { return propagated_error; } } }
                let binder = context.types.list(blot_check_types::List { node.b, node.c , ..})[index];
                { let propagated_error = render(context, bytes, binder, depth + 1, budget, stable); if propagated_error != blot_error::Error.none { return propagated_error; } }
            }
            { let propagated_error = text(context, bytes, "] => "); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = render(context, bytes, node.a, depth + 1, budget, stable); if propagated_error != blot_error::Error.none { return propagated_error; } }
        },
        bound => { { let propagated_error = text(context, bytes, "a"); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = number(context, bytes, node.a); if propagated_error != blot_error::Error.none { return propagated_error; } } },
        rigid => { { let propagated_error = text(context, bytes, "^a"); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = number(context, bytes, node.b); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = text(context, bytes, "@scope"); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = number(context, bytes, node.a); if propagated_error != blot_error::Error.none { return propagated_error; } } },
        usage => {
            { let propagated_error = text(context, bytes, usageName(node.b)); if propagated_error != blot_error::Error.none { return propagated_error; } }
            if node.c != 0 { { let propagated_error = text(context, bytes, " "); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = render(context, bytes, node.c, depth + 1, budget, stable); if propagated_error != blot_error::Error.none { return propagated_error; } } }
            { let propagated_error = text(context, bytes, " "); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = render(context, bytes, node.a, depth + 1, budget, stable); if propagated_error != blot_error::Error.none { return propagated_error; } }
        },
        instance_version => { { let propagated_error = text(context, bytes, "@invocation"); if propagated_error != blot_error::Error.none { return propagated_error; } } }, instance_selection => { { let propagated_error = text(context, bytes, "@selection"); if propagated_error != blot_error::Error.none { return propagated_error; } } },
        erased_proof => { { let propagated_error = text(context, bytes, "@proof"); if propagated_error != blot_error::Error.none { return propagated_error; } } },
        scoped => {
            { let propagated_error = render(context, bytes, node.a, depth + 1, budget, stable); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = text(context, bytes, " @scope"); if propagated_error != blot_error::Error.none { return propagated_error; } }
            { let propagated_error = number(context, bytes, node.b); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = text(context, bytes, ":"); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = number(context, bytes, node.c); if propagated_error != blot_error::Error.none { return propagated_error; } }
        },
        absent => { { let propagated_error = text(context, bytes, "?"); if propagated_error != blot_error::Error.none { return propagated_error; } } }, unit => { { let propagated_error = text(context, bytes, "Unit"); if propagated_error != blot_error::Error.none { return propagated_error; } } }, boolean => { { let propagated_error = text(context, bytes, "Bool"); if propagated_error != blot_error::Error.none { return propagated_error; } } },
        unsigned32 => { { let propagated_error = text(context, bytes, "U32"); if propagated_error != blot_error::Error.none { return propagated_error; } } }, floating32 => { { let propagated_error = text(context, bytes, "F32"); if propagated_error != blot_error::Error.none { return propagated_error; } } }, never => { { let propagated_error = text(context, bytes, "Never"); if propagated_error != blot_error::Error.none { return propagated_error; } } },
        variable => { { let propagated_error = text(context, bytes, "?t"); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = number(context, bytes, node.a); if propagated_error != blot_error::Error.none { return propagated_error; } } },
        array, list, cursor => {
            var keyword: const u8[:] = "Array "; if node.tag == blot_check_types::Tag.list { keyword = "List "; } else if node.tag == blot_check_types::Tag.cursor { keyword = "Cursor "; }
            { let propagated_error = text(context, bytes, keyword); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = render(context, bytes, node.a, depth + 1, budget, stable); if propagated_error != blot_error::Error.none { return propagated_error; } }
        },
        function => {
            { let propagated_error = text(context, bytes, "("); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = render(context, bytes, node.a, depth + 1, budget, stable); if propagated_error != blot_error::Error.none { return propagated_error; } }
            { let propagated_error = text(context, bytes, " -> "); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = render(context, bytes, node.b, depth + 1, budget, stable); if propagated_error != blot_error::Error.none { return propagated_error; } }
            var row_id = node.c;
            if !stable { let resolved, error = context.types.resolveEffects(node.c, 0); if error != blot_error::Error.none { return error; } row_id = resolved; }
            let row = context.types.effects.node(row_id);
            if row.labels.len != 0 || row.tail != blot_check_effects::Tail.closed {
                { let propagated_error = text(context, bytes, " ! {"); if propagated_error != blot_error::Error.none { return propagated_error; } }
                for index in 0..row.labels.len {
                    if budget == 0 { { let propagated_error = text(context, bytes, "..."); if propagated_error != blot_error::Error.none { return propagated_error; } } break; } budget--;
                    let label = context.types.effects.list(row.labels)[index];
                    if index != 0 { { let propagated_error = text(context, bytes, ", "); if propagated_error != blot_error::Error.none { return propagated_error; } } }
                    if label == blot_check_types::foreign_operation { { let propagated_error = text(context, bytes, "Foreign"); if propagated_error != blot_error::Error.none { return propagated_error; } } continue; }
                    let operation = context.types.operation(label); var name: u32 = 0;
                    for template in context.effect_templates { if template.identity == operation.identity { name = template.name; break; } }
                    if name == 0 { { let propagated_error = text(context, bytes, "operation"); if propagated_error != blot_error::Error.none { return propagated_error; } } } else { { let propagated_error = text(context, bytes, context.pool.get(name)); if propagated_error != blot_error::Error.none { return propagated_error; } } }
                    if operation.instance.decl != 0 { { let propagated_error = text(context, bytes, " @scope"); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = number(context, bytes, operation.instance.unit); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = text(context, bytes, ":"); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = number(context, bytes, operation.instance.decl); if propagated_error != blot_error::Error.none { return propagated_error; } } }
                    for argument_index in 0..operation.arguments.len {
                        if budget == 0 { { let propagated_error = text(context, bytes, " ..."); if propagated_error != blot_error::Error.none { return propagated_error; } } break; }
                        let argument = context.types.list(operation.arguments)[argument_index];
                        { let propagated_error = text(context, bytes, " "); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = render(context, bytes, argument, depth + 1, budget, stable); if propagated_error != blot_error::Error.none { return propagated_error; } }
                    }
                }
                if row.tail != blot_check_effects::Tail.closed { { let propagated_error = text(context, bytes, " | ?e"); if propagated_error != blot_error::Error.none { return propagated_error; } } }
                { let propagated_error = text(context, bytes, "}"); if propagated_error != blot_error::Error.none { return propagated_error; } }
            }
            { let propagated_error = text(context, bytes, ")"); if propagated_error != blot_error::Error.none { return propagated_error; } }
        },
        product => {
            { let propagated_error = text(context, bytes, "("); if propagated_error != blot_error::Error.none { return propagated_error; } }
            for index in 0..node.b {
                if budget == 0 { { let propagated_error = text(context, bytes, ", ..."); if propagated_error != blot_error::Error.none { return propagated_error; } } break; }
                let child = context.types.list(blot_check_types::List { node.a, node.b , ..})[index];
                if index != 0 { { let propagated_error = text(context, bytes, ", "); if propagated_error != blot_error::Error.none { return propagated_error; } } }
                { let propagated_error = render(context, bytes, child, depth + 1, budget, stable); if propagated_error != blot_error::Error.none { return propagated_error; } }
            }
            if node.b == 1 { { let propagated_error = text(context, bytes, ","); if propagated_error != blot_error::Error.none { return propagated_error; } } }
            { let propagated_error = text(context, bytes, ")"); if propagated_error != blot_error::Error.none { return propagated_error; } }
        },
        record => {
            { let propagated_error = text(context, bytes, "{ "); if propagated_error != blot_error::Error.none { return propagated_error; } }
            for index in 0..node.b {
                if budget == 0 { { let propagated_error = text(context, bytes, ", ..."); if propagated_error != blot_error::Error.none { return propagated_error; } } break; }
                if index != 0 { { let propagated_error = text(context, bytes, ", "); if propagated_error != blot_error::Error.none { return propagated_error; } } }
                let field = context.types.recordField(node, index);
                { let propagated_error = text(context, bytes, context.pool.get(field.name)); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = text(context, bytes, ": "); if propagated_error != blot_error::Error.none { return propagated_error; } }
                { let propagated_error = render(context, bytes, field.ty, depth + 1, budget, stable); if propagated_error != blot_error::Error.none { return propagated_error; } }
            }
            { let propagated_error = text(context, bytes, " }"); if propagated_error != blot_error::Error.none { return propagated_error; } }
        },
        nominal, type_constructor => {
            var name: u32 = 0;
            for nominal in context.nominals { if nominal.identity.unit == node.a && nominal.identity.decl == node.b { name = nominal.name; break; } }
            let storage = blot_check_storage_types::identity(node.a, node.b);
            if storage.present { { let propagated_error = text(context, bytes, blot_check_storage_types::name(storage.value)); if propagated_error != blot_error::Error.none { return propagated_error; } } }
            else if name == 0 { { let propagated_error = text(context, bytes, "Type"); if propagated_error != blot_error::Error.none { return propagated_error; } } }
            else { { let propagated_error = text(context, bytes, context.pool.get(name)); if propagated_error != blot_error::Error.none { return propagated_error; } } }
            if node.tag == blot_check_types::Tag.nominal {
                for index in 0..context.types.nominalArguments(node).len {
                    if budget == 0 { { let propagated_error = text(context, bytes, " ..."); if propagated_error != blot_error::Error.none { return propagated_error; } } break; }
                    let argument = context.types.nominalArguments(node)[index];
                    { let propagated_error = text(context, bytes, " "); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = render(context, bytes, argument, depth + 1, budget, stable); if propagated_error != blot_error::Error.none { return propagated_error; } }
                }
            }
        },
        projection => {
            var name: u32 = 0;
            for contract in context.contracts { if contract.identity.unit == node.a && contract.identity.decl == node.b { name = contract.name; break; } }
            { let propagated_error = text(context, bytes, context.pool.get(name)); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = text(context, bytes, "."); if propagated_error != blot_error::Error.none { return propagated_error; } }
            { let propagated_error = text(context, bytes, context.pool.get(context.types.projectionMember(node))); if propagated_error != blot_error::Error.none { return propagated_error; } }
            for argument in context.types.nominalArguments(node) { { let propagated_error = text(context, bytes, " "); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = render(context, bytes, argument, depth + 1, budget, stable); if propagated_error != blot_error::Error.none { return propagated_error; } } }
        },
        resolver => { { let propagated_error = text(context, bytes, "resolver"); if propagated_error != blot_error::Error.none { return propagated_error; } } }, provider => { { let propagated_error = text(context, bytes, "provider"); if propagated_error != blot_error::Error.none { return propagated_error; } } }, state_provider => { { let propagated_error = text(context, bytes, "state_provider"); if propagated_error != blot_error::Error.none { return propagated_error; } } },
    }
    return blot_error::Error.none;
}
