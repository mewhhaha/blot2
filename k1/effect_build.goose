// Candidate construction only; use effect_verify against independently retained
// source and bounds before consuming the summary. All accepted bodies are pure
// and use zero language-managed linear-frame bytes in this private model.
namespace effect_build;
import module_frontend;
import effect_core;

fn build(source: u8[:], bounds: effect_core::Bound[:]) -> effect_core::Summary, bool {
    var module, status = module_frontend::parse(source);
    if status != 0 || bounds.len != module.declarations.len { return effect_core::Summary {}, false; }
    var core = module_frontend::to_core(module);
    if module_frontend::verify_core(module, core) != 0 { return effect_core::Summary {}, false; }
    var entries: effect_core::Entry[>..] = [];
    for i in core.functions.len {
        let f = core.functions[i];
        let b = bounds[i];
        if b.name_start != f.name_start || b.name_end != f.name_end ||
           b.effects < 0 || (b.effects & 7) != b.effects ||
           b.depth < 1 || b.depth > 128 || b.frame < 0 || b.frame > 4294967295 { return effect_core::Summary {}, false; }
        var callee: i64 = -1;
        let result = f.values[f.result_id];
        if result.producer == 4 { callee = result.callee_id; }
        if callee >= 0 {
            let child = bounds[callee];
            if b.depth <= child.depth || b.frame < child.frame || (b.effects & child.effects) != child.effects {
                return effect_core::Summary {}, false;
            }
        }
        entries.push(effect_core::Entry { bound: b, callee: callee, actual_depth: f.depth });
    }
    return effect_core::Summary { source: copy(module.source), entries: entries }, true;
}
