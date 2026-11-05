namespace blot_reuse_declaration_origins;
import std;
import dictionary;
import check.core;
import support.error;
import support.option;

type Error = blot_error::Error;
struct Pair { before: u32 = 0, after: u32 = 0, ambiguous: bool = false }
fn name(module: const blot_check_core::Module&, body: blot_check_core::Body) -> blot_support::Option<const u8[:]> {
    let span = body.declaration_name;
    if span.len == 0 || span.start > module.names.len || span.len > module.names.len - span.start {
        return blot_support::none<const u8[:]>();
    }
    return blot_support::some(module.names[span.start..span.start + span.len]);
}
fn collect(entries: dictionary<const u8[:], Pair>&, module: const blot_check_core::Module&, before: bool) -> Error {
    for body in module.bodies {
        if body.binding == 0 { continue; }
        let spelling = name(module, body); if !spelling.present { continue; }
        var pair = Pair {..};
        { let optional_source_1 .= entries.get(spelling.value); if optional_source_1 { let prior = optional_source_1; pair = prior;  } }
        if before {
            if pair.before != 0 { pair.ambiguous = true; }
            pair.before = body.binding;
        } else {
            if pair.after != 0 { pair.ambiguous = true; }
            pair.after = body.binding;
        }
        entries.insert(spelling.value, pair);
    }
    return blot_error::Error.none;
}
fn mark(old: const blot_check_core::Module&, current: const blot_check_core::Module&, admitted: bool[:]) -> Error {
    if admitted.len != current.bindings.len { abort("declaration origin admission shape"); }
    for &item in admitted { item = false; }
    var entries: dictionary<const u8[:], Pair> = default<dictionary<const u8[:], Pair>>();
    let first = collect(entries, old, true); if first != blot_error::Error.none { return first; }
    let second = collect(entries, current, false); if second != blot_error::Error.none { return second; }
    for slot in entries.slots {
        if slot.tag == 0 { continue; }
        let pair = slot.val;
        if !pair.ambiguous && pair.before != 0 && pair.before == pair.after && pair.after < admitted.len {
            admitted[pair.after] = true;
        }
    }
    return blot_error::Error.none;
}
