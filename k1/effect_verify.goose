// Independent consumer. The expected bytes and bounds must be retained by the
// caller, immutable for this call. Re-recognize source/Core and walk each
// call chain independently; summary fields never authorize the next edge.
namespace effect_verify;
import module_frontend;
import effect_core;

fn verify(source: u8[:], bounds: effect_core::Bound[:], candidate: effect_core::Summary&) -> bool {
    if source != candidate.source[..] { return false; }
    var module, status = module_frontend::parse(source);
    if status != 0 || bounds.len != module.declarations.len || candidate.entries.len != bounds.len { return false; }
    var core = module_frontend::to_core(module);
    if module_frontend::verify_core(module, core) != 0 { return false; }
    let count = core.functions.len;
    for i in count {
        let f = core.functions[i];
        let b = bounds[i];
        let entry = candidate.entries[i];
        if b.name_start != f.name_start || b.name_end != f.name_end ||
           b.effects < 0 || (b.effects & 7) != b.effects || b.depth < 1 || b.depth > 128 ||
           b.frame < 0 || b.frame > 4294967295 || !effect_core::same_bound(entry.bound, b) ||
           entry.actual_effects != 0 || entry.actual_frame != 0 { return false; }
        var seen: bool[256] = [false; 256];
        var at = i;
        var depth: i64 = 0;
        var first: i64 = -1;
        loop {
            if at < 0 || at >= count || seen[at] { return false; }
            seen[at] = true;
            depth += 1;
            if depth > 128 { return false; }
            let current = core.functions[at];
            let result = current.values[current.result_id];
            if result.producer != 4 { break; }
            let next = result.callee_id;
            if next < 0 || next >= count { return false; }
            if at == i { first = next; }
            at = next;
        }
        if entry.callee != first || entry.actual_depth != depth || depth > b.depth { return false; }
        if first >= 0 {
            let child = bounds[first];
            if b.depth <= child.depth || b.frame < child.frame || (b.effects & child.effects) != child.effects { return false; }
        }
    }
    return true;
}
