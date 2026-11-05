// A settled source prefix can skip the frontend without transporting values.
namespace blot_reuse_module_frontend_cutoff;
import reuse.entry_frontend_cutoff;
import reuse.project;
import reuse.project_check;
import reuse.dependency_format;
import support.error;
type Error = blot_error::Error;
fn confirm<P,C>(source: const P&, checked: C&, previous: blot_reuse_entry_frontend_cutoff::Previous, unit: u32, stats: blot_reuse_entry_frontend_cutoff::Stats&) -> bool, Error {
    stats.offered++;
    if source.input_mode != blot_reuse_project::InputMode.project || source.entry == 0 || source.entry != source.units.len || source.compiled_modules.len + 1 != source.units.len || source.compiled_reuse.len != source.compiled_modules.len || source.order.len == 0 || source.order[source.order.len - 1] != source.entry { return false, Error.none; }
    if unit == 0 || unit > source.compiled_modules.len || previous.entry != source.entry || previous.prelude != source.prelude_unit || checked.compiledModule(source, unit) != null { return false, Error.none; }
    let old .= source.compiled_modules[unit - 1]; let current .= source.unit(unit);
    if current.source.len != old.identity.source_bytes || blot_reuse_dependency_format::digest(current.source) != old.identity.source_digest || current.implicit_prelude != old.implicit_prelude { return false, Error.none; }
    let imports = source.unitImports(unit);
    if imports.len != old.source_imports.len { return false, Error.none; }
    for fresh, index in imports { let prior = old.source_imports[index]; if fresh.target != prior.target || source.symbols.get(fresh.path) != prior.path { return false, Error.none; } }
    stats.source_matches++;
    if !blot_reuse_entry_frontend_cutoff::namespaceMatches(source, previous.names) { return false, Error.none; }
    stats.namespace_matches++;
    var found = false;
    for prior in source.order {
        if prior == unit { found = true; break; }
        if prior == source.entry || prior == 0 || prior > source.compiled_modules.len { return false, Error.none; }
        if checked.compiledModule(source, prior) != null { continue; }
        let matches, error = blot_reuse_entry_frontend_cutoff::interfaceMatches(source, checked, prior, stats);
        if error != Error.none || !matches { return false, error; }
    }
    if !found || !blot_reuse_entry_frontend_cutoff::storageInputsMatch(source, checked, unit, old.core, stats) { return false, Error.none; }
    for imported in imports { if !settled(source, checked, imported.target) { return false, Error.none; } }
    if current.implicit_prelude && !settled(source, checked, source.prelude_unit) { return false, Error.none; }
    return true, Error.none;
}
fn settled<P,C>(source: const P&, checked: const C&, unit: u32) -> bool {
    if unit == 0 || unit > source.compiled_modules.len { return false; }
    if checked.compiledModule(source, unit) != null { return true; }
    if unit > checked.interface_colors.len || (checked.interface_colors[unit - 1] != blot_reuse_entry_frontend_cutoff::Color.green && checked.interface_colors[unit - 1] != blot_reuse_entry_frontend_cutoff::Color.green_storage) { return false; }
    let current = checked.modules[unit - 1];
    if !current.present { return false; }
    return current.value.valid && current.value.checked.diagnostics.len == 0;
}
