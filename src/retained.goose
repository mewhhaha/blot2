// Reuse is available only from this process's previously admitted revision.
// Disk-loaded Core never enters this path merely by validating a receipt hash.
import .model;
import .frontend;
import .canonical;
import .relocate;
import .artifact;
import .validate;

struct ReuseStats { bodies: u32, lookups: u32, hits: u32, misses: u32, declines: u32, dependency_visits: u32, admission_visits: u64, dependency_invalidations: u32 }
// Provenance is supplied by the owning session, never read from artifact bytes.
let RETAINED_EXTERNAL: u32 = 0;
let RETAINED_CURRENT_PROCESS: u32 = 1;
fn with_retained_revision<F>(bytes: const u8[:], provenance: u32, stats: ReuseStats&) {
    if bytes.len == 0 { F(Core { .. }); return; }
    if provenance != RETAINED_CURRENT_PROCESS { stats.declines++; F(Core { .. }); return; }
    var admitted = false;
    with_core() { prior =>
        var diagnostics: Diagnostic[>..] = []; var validation = Work { .. };
        let valid = artifact::artifact_decode(bytes, prior, diagnostics) && validator::validate_core(core_view(prior), validator::OPTIONAL, validation, diagnostics);
        stats.admission_visits += validation.visits;
        if valid {
            admitted = true; F(core_view(prior));
        }
    };
    // Destroy rejected/partially decoded tables before running fresh completion.
    if !admitted { stats.declines++; F(Core { .. }); }
}
fn retained_module_prelude<Tick>(c: Core, module_id: u32) -> const u8[:] {
    let m = c.modules[module_id]; var end = m.source.count;
    for i in m.declarations.count { Tick(); let d = c.definitions[c.refs[m.declarations.start + i]]; if id_ok(d.origin, c.origins.len) { end = min(end, c.origins[d.origin].start); } }
    return c.bytes[m.source.start..m.source.start + end];
}
fn retained_imports_match<Tick>(prior: Core, old_module: u32, current: Core, new_module: u32) -> bool {
    let before = retained_module_prelude(prior, old_module, Tick); let after = retained_module_prelude(current, new_module, Tick);
    for i in prior.modules[old_module].imports.count { Tick(); }
    for i in current.modules[new_module].imports.count { Tick(); }
    var old_paths: Span[>..] = []; var old_aliases: Span[>..] = []; var new_paths: Span[>..] = []; var new_aliases: Span[>..] = []; var diags: Diagnostic[>..] = [];
    if !frontend_imports(before, old_paths, old_aliases, diags) || !frontend_imports(after, new_paths, new_aliases, diags) { return false; }
    if old_paths.len != new_paths.len { return false; }
    for path, i in old_paths {
        Tick();
        let next = new_paths[i]; let alias = old_aliases[i]; let next_alias = new_aliases[i];
        if before[path.start..path.start + path.count] != after[next.start..next.start + next.count] || before[alias.start..alias.start + alias.count] != after[next_alias.start..next_alias.start + next_alias.count] { return false; }
    }
    return true;
}
fn retained_module_namespace<Tick>(prior: Core, old_module: u32, current: Core, new_module: u32) -> bool {
    let before = prior.modules[old_module].declarations; let after = current.modules[new_module].declarations;
    if before.count != after.count { return false; }
    for i in before.count {
        Tick();
        let a = prior.definitions[prior.refs[before.start + i]]; let b = current.definitions[current.refs[after.start + i]];
        if a.kind != b.kind || a.visibility != b.visibility || name_bytes(prior, a.name) != name_bytes(current, b.name) { return false; }
    }
    return true;
}
fn complete_retained_module(prior: Core, source: const u8[:], module_name: const u8[:], b: CoreBuilder, work: Work&, stats: ReuseStats&, diags: Diagnostic[>..]&) -> bool {
    var ok = false;
    with_frontend_scratch() { scratch => ok = complete_retained_module_in(prior, source, module_name, b, work, stats, diags, scratch); };
    return ok;
}
fn complete_retained_module_in(prior: Core, source: const u8[:], module_name: const u8[:], b: CoreBuilder, work: Work&, stats: ReuseStats&, diags: Diagnostic[>..]&, scratch: FrontendScratch) -> bool {
    var projections: relocation::Projection[>..<] = [];
    var namespace_state: u32 = 0;
    var imports_state: u32 = 0;
    // Lookup budgets are optional-work budgets, independent of admission work.
    recursive fn reuse<Resolve>(definition: u32, source_span: Span, annotation: u32) -> u32 {
        stats.lookups++; var visits: u32 = 0; let mark = projections.len;
        fn tick() { visits++; stats.dependency_visits++; if visits > 4096 { projections.resize(mark); stats.declines++; return 0 from reuse; } }
        let target = b.definitions[definition]; let module_id = target.module;
        var old: u32 = 0;
        for row, i in prior.definitions {
            tick(); if i == 0 || row.kind != DEF_FUNCTION || row.name == 0 { continue; }
            if name_bytes(prior, row.name) != name_bytes(core_view(b), target.name) { continue; }
            if name_bytes(prior, prior.modules[row.module].path) != module_name { continue; }
            old = i as u32; break;
        }
        if old == 0 { stats.misses++; return 0; }
        let original = prior.definitions[old]; let origin = prior.origins[original.origin]; let old_module = prior.modules[origin.module];
        if namespace_state == 0 { namespace_state = if retained_module_namespace(prior, original.module, core_view(b), module_id, tick) { 1 } else { 2 }; }
        if namespace_state == 2 { stats.misses++; return 0; }
        let old_source = prior.bytes[old_module.source.start + origin.start..old_module.source.start + origin.end];
        if imports_state == 0 { imports_state = if retained_imports_match(prior, original.module, core_view(b), module_id, tick) { 1 } else { 2 }; }
        if old_source != source[source_span.start..source_span.start + source_span.count] || imports_state == 2 { stats.misses++; return 0; }
        var receipt: u32 = 0; for row, i in prior.receipts { tick(); if i != 0 && row.producer == old { receipt = i as u32; break; } }
        if receipt == 0 { stats.misses++; return 0; }
        let observation = prior.receipts[receipt];
        for i in observation.dependencies.count {
            tick(); let dep = prior.dependencies[prior.refs[observation.dependencies.start + i]];
            if dep.query_kind == 0 || !span_ok(dep.identity, prior.bytes.len) { projections.resize(mark); stats.misses++; return 0; }
            let identity = prior.bytes[dep.identity.start..dep.identity.start + dep.identity.count]; var split: i64 = 0;
            while split < identity.len && identity[split] != 0 { split++; }
            if split == identity.len { projections.resize(mark); stats.misses++; return 0; }
            let path = identity[..split]; let name = identity[split + 1..]; var found: u32 = 0;
            let kind = if dep.query_kind == 2 { DEF_TYPE } else { if dep.present { prior.definitions[dep.producer].kind } else { DEF_FUNCTION } };
            if path == module_name {
                let nid = add_name(b, name); found = Resolve(nid, kind);
                if found == 0 && !dep.present && dep.query_kind == 1 { found = Resolve(nid, DEF_STATIC); }
            } else {
                for row, j in b.definitions {
                    tick(); if j != 0 && row.kind == kind && row.visibility == VIS_PUBLIC && name_bytes(core_view(b), row.name) == name && name_bytes(core_view(b), b.modules[row.module].path) == path { found = j as u32; break; }
                }
            }
            if dep.present != (found != 0) { projections.resize(mark); stats.misses++; stats.dependency_invalidations++; return 0; }
            if dep.present && !retained_module_namespace(prior, prior.definitions[dep.producer].module, core_view(b), b.definitions[found].module, tick) { projections.resize(mark); stats.misses++; stats.dependency_invalidations++; return 0; }
            if dep.present && dep.kind == DEP_BODY {
                let before = prior.definitions[dep.producer]; let after = b.definitions[found];
                let bo = prior.origins[before.origin]; let ao = b.origins[after.origin];
                let bm = prior.modules[before.module]; let am = b.modules[after.module];
                if prior.bytes[bm.source.start + bo.start..bm.source.start + bo.end] != b.bytes[am.source.start + ao.start..am.source.start + ao.end] {
                    projections.resize(mark); stats.misses++; stats.dependency_invalidations++; return 0;
                }
            }
            if dep.present { projections.push(relocation::Projection { source_definition: dep.producer, target_definition: found }); }
        }
        b.definitions[definition].type_id = annotation;
        var relocation_work = Work { .. };
        let previous_functions = b.functions.len;
        let ok = relocation::relocate_function(prior, old, b, definition, projections[mark..], relocation_work);
        projections.resize(mark);
        if !ok { stats.misses++; if !relocation_work.exhausted { stats.dependency_invalidations++; } return 0; }
        stats.hits++; stats.bodies += (b.functions.len - previous_functions) as u32; return b.definitions[definition].function;
    }
    return frontend_complete_with_reuse_in(source, module_name, b, work, diags, scratch, reuse);
}
