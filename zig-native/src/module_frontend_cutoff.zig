//! Private intermediate-module frontend cutoff. No evaluated values or code
//! cross this boundary: the backend still executes against current producer Core.
const std = @import("std");
const project = @import("project.zig");
const entry = @import("entry_frontend_cutoff.zig");
const format = @import("dependency_format.zig");
const Allocator = std.mem.Allocator;

pub fn confirm(a: Allocator, source: *const project.Project, checked: anytype, previous: entry.Previous, unit: u32, stats: *entry.Stats) Allocator.Error!bool {
    stats.offered += 1;
    if (source.input_mode != .project or source.entry == 0 or source.entry != source.units.items.len or source.compiled_modules.len + 1 != source.units.items.len or source.compiled_reuse.len != source.compiled_modules.len or source.order.items.len == 0 or source.order.items[source.order.items.len - 1] != source.entry) return false;
    if (unit == 0 or unit > source.compiled_modules.len or previous.entry != source.entry or previous.prelude != source.prelude_unit or checked.compiledModule(source, unit) != null) return false;
    const old = &source.compiled_modules[unit - 1];
    const current = source.unit(unit);
    if (current.source.len != old.identity.source_bytes or !std.mem.eql(u8, &format.digest(current.source), &old.identity.source_digest) or current.implicit_prelude != old.implicit_prelude) return false;
    const imports = source.unitImports(unit);
    if (imports.len != old.source_imports.len) return false;
    for (imports, old.source_imports) |fresh, prior| if (fresh.target != prior.target or !std.mem.eql(u8, source.symbols.get(fresh.path), prior.path)) return false;
    stats.source_matches += 1;
    if (previous.names.owners.len != source.units.items.len or previous.names.symbols.len != source.symbols.entries.items.len + 1) return false;
    for (source.units.items, 1..) |_, id| if (!std.mem.eql(u8, previous.names.owner(@intCast(id)) orelse return false, source.filename(@intCast(id)))) return false;
    for (source.symbols.entries.items, 1..) |_, id| if (!std.mem.eql(u8, previous.names.symbol(@intCast(id)) orelse return false, source.symbols.get(@intCast(id)))) return false;
    stats.namespace_matches += 1;

    // Confirm the whole settled prefix, including private declarations,
    // aliases, ordered associated catalogs and fixities. This is deliberately
    // broader than the immediate import list. Initial compiled modules were
    // already admitted transitively against the exact current raw inputs.
    var found = false;
    for (source.order.items) |prior| {
        if (prior == unit) {
            found = true;
            break;
        }
        if (prior == source.entry or prior == 0 or prior > source.compiled_modules.len) return false;
        if (checked.compiledModule(source, prior) != null) continue;
        if (!try entry.interfaceMatches(a, source, checked, prior, stats)) return false;
    }
    if (!found) return false;
    // Reject an incomplete or inconsistent dependency-first order instead of
    // obtaining a declaration from an unchecked future source module.
    for (imports) |imported| if (!settled(source, checked, imported.target)) return false;
    if (current.implicit_prelude and !settled(source, checked, source.prelude_unit)) return false;
    return true;
}

fn settled(source: *const project.Project, checked: anytype, unit: u32) bool {
    if (unit == 0 or unit > source.compiled_modules.len) return false;
    if (checked.compiledModule(source, unit) != null) return true;
    if (unit > checked.interface_colors.len or checked.interface_colors[unit - 1] != .green) return false;
    const current = if (checked.modules[unit - 1]) |*value| value else return false;
    return current.valid and current.checked.diagnostics.len == 0;
}
