//! First bundle boundary before relocation. Wire ownership, principal facts and
//! complete Core bounds/cycles are proved before publishing any imported owner.
const std = @import("std");
const D = @import("frozen_dependency.zig");
const PI = @import("principal_interface.zig");
const validation = @import("dependency_interface_validation.zig");
const format = @import("dependency_format.zig");
const core_validation = @import("frozen_core_validation.zig");
pub const Error = error{InvalidArtifact};
fn require(condition: bool) Error!void {
    if (!condition) return error.InvalidArtifact;
}
fn external(value: *const D.FrozenDependency, current: usize, target: PI.ExternalTarget) Error!void {
    const unit = if (target.unit == 0) current + 1 else target.unit;
    try require(unit != 0 and unit <= value.modules.len);
    try require(target.binding != 0 and target.binding < value.modules[unit - 1].interface.bindings.len);
}
pub fn validatePrelude(allocator: std.mem.Allocator, value: *const D.FrozenDependency, source: []const u8, producer_identity: []const u8) (Error || std.mem.Allocator.Error)!void {
    try require(value.modules.len == 1 and value.symbols.len != 0 and value.symbols[0].text.len == 0);
    const owner = &value.modules[0];
    try require(owner.identity.prelude and owner.imports.len == 0);
    try require(std.mem.eql(u8, owner.identity.normalized_path, producer_identity));
    try require(owner.identity.source_bytes == source.len and std.mem.eql(u8, &owner.identity.source_digest, &format.digest(source)));
    try require(owner.core.unit == 1 and owner.interface.unit == 1);
    try validation.validate(&owner.interface, value.symbols.len, value.modules.len);
    try validation.validateGraph(allocator, &owner.interface);
    try core_validation.validate(allocator, &owner.core, .{ .units = &.{&owner.core}, .symbol_count = value.symbols.len, .source_length = owner.identity.source_bytes });
    for (owner.core.field_names) |field| try require(std.mem.eql(u8, owner.core.name(field.spelling), value.symbols[field.symbol].text));
    for (owner.interface.bindings) |binding| if (binding.external) |target| try external(value, 0, target);
    for (owner.exports) |entry| {
        try require(entry.name != 0 and entry.name < value.symbols.len);
        switch (entry.kind) {
            .value => {
                try external(value, 0, entry.target);
                const definition = owner.interface.bindings[entry.target.binding];
                try require(definition.kind == .global and definition.name == entry.name);
            },
            .nominal => try require(entry.catalog != 0 and entry.catalog < owner.interface.nominals.len and owner.interface.nominals[entry.catalog].name == entry.name),
            .constructor => try require(entry.catalog != 0 and entry.catalog < owner.interface.constructors.len and owner.interface.constructors[entry.catalog].name == entry.name),
            .effect_family => try require(entry.catalog != 0 and entry.catalog < owner.interface.effect_families.len and owner.interface.effect_families[entry.catalog].name == entry.name),
            .contract => try require(entry.catalog < owner.interface.contracts.len and owner.interface.contracts[entry.catalog].name == entry.name),
        }
    }
    for (owner.fixities) |fixity| {
        try require(fixity.operator != 0 and fixity.operator < value.symbols.len and fixity.target != 0 and fixity.target < value.symbols.len);
        try require(fixity.precedence <= 255 and fixity.association <= 2);
        try external(value, 0, fixity.producer);
    }
}
