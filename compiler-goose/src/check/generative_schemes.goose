// Invocation binders become fresh only when the declaring arrow is called.
namespace blot_check_generative_schemes;
import dictionary;
import support.error;
struct Binder { owner: u32 = 0, origin: u32 = 0, arrow: blot_check_types::Id = 0, selection: blot_check_types::Id }
let limit: i64 = 16;
fn sameArrow(store: blot_check_types::Store&, left: blot_check_types::Id, right: blot_check_types::Id) -> bool, blot_error::Error {
    let left_id, le = store.resolve(left, 0); if le != blot_error::Error.none { return false, le; }
    let right_id, re = store.resolve(right, 0); if re != blot_error::Error.none { return false, re; }
    let a = store.node(left_id); let b = store.node(right_id);
    if a.tag != blot_check_types::Tag.function || b.tag != blot_check_types::Tag.function { return false, blot_error::Error.none; }
    let arguments, ae = store.equalSymbolic(a.a, b.a); if ae != blot_error::Error.none { return false, ae; }
    if !arguments { return false, blot_error::Error.none; }
    let left_rows, lre = store.freeRowVariables(a.b); if lre != blot_error::Error.none { return false, lre; }
    let right_rows, rre = store.freeRowVariables(b.b); if rre != blot_error::Error.none { return false, rre; }
    let left_root, lrr = store.resolve(a.b, 0); if lrr != blot_error::Error.none { return false, lrr; }
    let right_root, rrr = store.resolve(b.b, 0); if rrr != blot_error::Error.none { return false, rrr; }
    let left_result, lc = store.closeCovariant(left_root, left_rows, []); if lc != blot_error::Error.none { return false, lc; }
    let right_result, rc = store.closeCovariant(right_root, right_rows, []); if rc != blot_error::Error.none { return false, rc; }
    let results, eq = store.equalSymbolic(left_result, right_result); if eq != blot_error::Error.none { return false, eq; }
    if !results { return false, blot_error::Error.none; }
    let ar, are = store.resolveEffects(a.c, 0); if are != blot_error::Error.none { return false, are; }
    let br, bre = store.resolveEffects(b.c, 0); if bre != blot_error::Error.none { return false, bre; }
    return store.rowLabels(ar) == store.rowLabels(br), blot_error::Error.none;
}
fn collect(store: blot_check_types::Store&, root: blot_check_types::Id, binders: const Binder[:]) -> blot_check_types::List, blot_error::Error {
    if binders.len == 0 { return blot_check_types::List {}, blot_error::Error.none; }
    var pending: blot_check_types::Id[>..<] = [];
    var visited = dictionary<blot_check_types::Id, bool> {};
    var result: blot_check_types::Id[>..] = [];
    pending.push(root);
    while pending.len > 0 {
        let original = pending.pop();
        let id, error = store.resolve(original, 0);
        if error != blot_error::Error.none { return blot_check_types::List {}, error; }
        if visited.contains(id) { continue; }
        if visited.count >= 4096 { return blot_check_types::List {}, blot_error::Error.type_limit; }
        visited.insert(id, true);
        let node = store.node(id);
        if node.tag == blot_check_types::Tag.function {
            for binder in binders {
                if binder.arrow == 0 { continue; }
                let same, comparison = sameArrow(store, binder.arrow, id);
                if comparison != blot_error::Error.none { return blot_check_types::List {}, comparison; }
                if !same { continue; }
                let selected, selection = store.resolve(binder.selection, 0);
                if selection != blot_error::Error.none { return blot_check_types::List {}, selection; }
                var duplicate = false;
                for index in result.len / 2 {
                    if result[index * 2] == id && result[index * 2 + 1] == selected { duplicate = true; break; }
                }
                if duplicate { continue; }
                if result.len == limit * 2 { return blot_check_types::List {}, blot_error::Error.type_limit; }
                result.push(id); result.push(selected);
            }
            pending.push(node.a); pending.push(node.b);
        } else {
            match node.tag {
                usage, array, list, cursor, resolver, provider => { pending.push(node.a); },
                state_provider => { pending.append([node.a, node.b, node.c]); },
                product => { pending.append(store.list(blot_check_types::List { node.a, node.b })); },
                record => { for index in node.b { pending.push(store.recordField(node, index).ty); } },
                nominal => { pending.append(store.nominalArguments(node)); },
                _ => {},
            }
        }
    }
    return store.saveList(result);
}
