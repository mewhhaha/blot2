//! Versioned dependency payload; all IDs are artifact-owner local until the
//! loader validates and relinks units and exact UTF8 symbols explicitly.
const core = @import("core.zig");
const PI = @import("principal_interface.zig");

pub const Symbol = struct { text: []u8 };
pub const Identity = struct {
    normalized_path: []u8,
    source_digest: [32]u8,
    source_bytes: u32,
    prelude: bool,
};
pub const Export = struct {
    name: u32,
    target: PI.ExternalTarget,
    kind: enum { value, nominal, constructor, effect_family },
    catalog: u32,
};
pub const Fixity = struct {
    operator: u32,
    target: u32,
    precedence: u32,
    association: u32,
    named: bool,
    producer: PI.ExternalTarget,
};
pub const Module = struct {
    identity: Identity,
    imports: []u32,
    implicit_prelude: bool = false,
    source_imports: []ImportResolution = &.{},
    core: core.Module,
    interface: PI.Interface,
    exports: []Export,
    fixities: []Fixity,
};
/// Exact request supplied to the ordinary loader, before filesystem resolution.
/// Its target is an artifact module index; path bytes have no symbol-pool IDs.
pub const ImportResolution = struct { path: []u8, target: u32 };
pub const FrozenDependency = struct {
    /// Index zero is the absent symbol. Unit IDs are module index + 1.
    symbols: []Symbol,
    modules: []Module,
};
