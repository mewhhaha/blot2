//! Lookup names from the checker's actual exposed catalogs. No export guesses.
const std = @import("std");
const C = @import("check.zig");
const T = @import("types.zig");
const Allocator = std.mem.Allocator;
pub const builtin_types = [_][]const u8{ "Unit", "Bool", "U32", "F32", "Array", "List", "Cursor", "EffectSet", "EffectDescriptor" };
const Builder = struct {
    allocator: Allocator,
    names: std.ArrayList(C.EditorName) = .empty,
    prefix: []const u8,
    pool: *@import("symbols.zig").Pool,
    truncated: *bool,
    constructor_prefix: bool,

    fn earlier(self: *const Builder, left: C.EditorName, right: C.EditorName) bool {
        if (left.distance != right.distance) return left.distance < right.distance;
        const left_text = self.pool.get(left.name);
        const right_text = self.pool.get(right.name);
        if (!self.constructor_prefix) {
            if (left.kind == .constructor and right.kind != .constructor) return '#' < right_text[0];
            if (left.kind != .constructor and right.kind == .constructor) return left_text[0] < '#';
        }
        const name = std.mem.order(u8, left_text, right_text);
        if (name != .eq) return name == .lt;
        if (left.kind != right.kind) return @backingInt(left.kind) < @backingInt(right.kind);
        if (left.identity.unit != right.identity.unit) return left.identity.unit < right.identity.unit;
        return left.identity.decl < right.identity.decl;
    }
    fn finish(self: *Builder) ![]C.EditorName {
        // Fitting spends a shared budget. Visit candidates in semantic order so
        // hash-table iteration cannot decide which matches get proved first.
        std.mem.sort(C.EditorName, self.names.items, self, earlier);
        return self.names.toOwnedSlice(self.allocator);
    }

    fn add(self: *Builder, item: C.EditorName) !void {
        const text = self.pool.get(item.name);
        if (!std.mem.startsWith(u8, text, self.prefix)) return;
        for (self.names.items) |old| {
            if (old.kind == item.kind and old.name == item.name and std.meta.eql(old.identity, item.identity)) return;
        }
        if (self.names.items.len == 4096) {
            self.truncated.* = true;
            var worst: usize = 0;
            for (self.names.items, 0..) |old, index| if (self.earlier(self.names.items[worst], old)) {
                worst = index;
            };
            if (self.earlier(item, self.names.items[worst])) self.names.items[worst] = item;
            return;
        }
        try self.names.append(self.allocator, item);
    }
};

fn declaration(engine: anytype, binding: C.Binding) C.Identity {
    if (binding.external) |target| return .{ .unit = target.unit, .decl = 0 };
    return .{ .unit = engine.unit, .decl = binding.declaration };
}
fn distance(engine: anytype, binding: C.Binding) u32 {
    if (binding.external) |target| {
        if (target.unit == engine.prelude_unit) return 1_000_002;
        return 1_000_001;
    }
    return 1_000_000;
}
fn valueName(engine: anytype, name: u32, id: u32, depth: u32) C.EditorName {
    const binding = engine.bindings.items[id];
    var kind: @FieldType(C.EditorName, "kind") = .value;
    if (engine.types.node(engine.types.head(binding.ty, 0)).tag == .function) kind = .function;
    var scheme = binding.scheme;
    if (scheme.root == 0) scheme.root = binding.ty;
    return .{ .name = name, .kind = kind, .scheme = scheme, .distance = depth, .identity = declaration(engine, binding), .external = binding.external };
}

pub fn capture(engine: anytype, captured: *C.EditorCapture, receiver_identity: ?C.Identity) T.Error![]C.EditorName {
    var out: Builder = .{ .allocator = engine.allocator, .prefix = engine.editor_marker.?.prefix, .pool = engine.pool, .truncated = &captured.truncated, .constructor_prefix = captured.kind == .constructor };
    errdefer out.names.deinit(out.allocator);
    if (captured.kind == .intrinsic) return out.finish();
    if (captured.receiver != 0 and captured.namespace == 0) {
        const receiver = engine.types.node(engine.types.head(captured.receiver, 0));
        if (receiver.tag == .record) {
            for (0..receiver.b) |index| {
                const field = engine.types.recordField(receiver, index);
                var ty = field.ty;
                if (captured.kind == .selector) ty = try engine.types.function(captured.receiver, ty);
                try out.add(.{ .name = field.name, .kind = .field, .scheme = .{ .root = ty } });
            }
        } else if (receiver.tag == .nominal) {
            for (engine.nominals.items) |nominal| {
                if (!std.meta.eql(nominal.identity, receiver_identity.?)) continue;
                const constructors = try engine.allocator.dupe(u32, engine.types.list(nominal.constructors));
                defer engine.allocator.free(constructors);
                const variables = try engine.allocator.dupe(u32, engine.types.list(nominal.variables));
                defer engine.allocator.free(variables);
                const arguments = try engine.allocator.dupe(u32, engine.types.nominalArguments(receiver));
                defer engine.allocator.free(arguments);
                if (constructors.len == 0) break;
                const first = engine.types.node(engine.constructors.items[constructors[0]].payload);
                if (first.tag != .record) break;
                for (0..first.b) |index| {
                    const field = engine.types.recordField(first, index);
                    var common = true;
                    for (constructors[1..]) |constructor| {
                        const payload = engine.types.node(engine.constructors.items[constructor].payload);
                        var found = false;
                        if (payload.tag == .record) for (0..payload.b) |part| {
                            const other = engine.types.recordField(payload, part);
                            if (other.name == field.name and (other.ty == field.ty or try engine.types.equalClosed(other.ty, field.ty))) found = true;
                        };
                        if (!found) common = false;
                    }
                    if (!common) continue;
                    var ty = field.ty;
                    if (nominal.variables.len == engine.types.nominalArguments(receiver).len)
                        ty = try engine.types.substitute(ty, variables, arguments);
                    if (captured.kind == .selector) ty = try engine.types.function(captured.receiver, ty);
                    try out.add(.{ .name = field.name, .kind = .field, .scheme = .{ .root = ty }, .identity = nominal.identity });
                }
                break;
            }
        }
        if (receiver_identity) |identity| for (engine.associated.items) |member| {
            if (!std.meta.eql(identity, member.identity)) continue;
            var item = valueName(engine, member.member, member.binding, 0);
            item.kind = .member;
            item.receiver = true;
            try out.add(item);
        };
        for (out.names.items) |*item| for (out.names.items) |other| {
            if (item.name == other.name and item.kind != other.kind) item.ambiguous = true;
        };
        return out.finish();
    }
    const type_context = captured.kind == .type_;
    const constructors_only = captured.kind == .constructor;
    var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer seen.deinit(out.allocator);
    if (captured.namespace == 0 and !type_context and !constructors_only) {
        for (engine.types.list(captured.visible), 0..) |binding, index| {
            const name = engine.types.list(captured.visible_names)[index];
            try seen.put(out.allocator, name, {});
            try out.add(valueName(engine, name, binding, @intCast(index)));
        }
        var globals = engine.globals.iterator();
        while (globals.next()) |entry| {
            if (seen.contains(entry.key_ptr.*)) continue;
            try out.add(valueName(engine, entry.key_ptr.*, entry.value_ptr.*, distance(engine, engine.bindings.items[entry.value_ptr.*])));
        }
    } else if (!type_context and !constructors_only) {
        var values = engine.qualified.iterator();
        while (values.next()) |entry| {
            if (entry.key_ptr.namespace == captured.namespace)
                try out.add(valueName(engine, entry.key_ptr.member, entry.value_ptr.*, 0));
        }
    }
    if (!type_context) {
        var constructors = engine.constructor_names.iterator();
        while (constructors.next()) |entry| {
            if (entry.key_ptr.namespace != captured.namespace or seen.contains(entry.key_ptr.member)) continue;
            const constructor = engine.constructors.items[entry.value_ptr.*];
            var depth: u32 = 1_000_001;
            if (constructor.identity.unit == engine.unit) depth = 1_000_000;
            if (constructor.identity.unit == engine.prelude_unit) depth = 1_000_002;
            try out.add(.{ .name = entry.key_ptr.member, .kind = .constructor, .scheme = constructor.scheme, .identity = constructor.identity, .distance = depth });
        }
    } else {
        const locals = engine.types.list(captured.type_scope);
        var index: usize = 0;
        while (index < locals.len) : (index += 2) {
            try seen.put(out.allocator, locals[index], {});
            try out.add(.{ .name = locals[index], .kind = .type_, .scheme = .{ .root = locals[index + 1] }, .distance = @intCast(index / 2) });
        }
        if (captured.namespace == 0) for (builtin_types, 0..) |text, builtin_index| {
            const roots = [_]T.Id{ T.unit, T.boolean, T.u32_type, T.f32_type, 0, 0, 0, 0, 0 };
            const name = engine.pool.lookup(text) orelse continue;
            if (seen.contains(name)) continue;
            try seen.put(out.allocator, name, {});
            try out.add(.{ .scheme = .{ .root = roots[builtin_index] }, .name = name, .kind = .type_, .distance = 1_000_002 });
        };
        inline for (.{ .{ "nominal_names", "nominals" }, .{ "contract_names", "contracts" }, .{ "effect_family_names", "effect_families" } }) |pair| {
            var types = @field(engine, pair[0]).iterator();
            while (types.next()) |entry| {
                if (entry.key_ptr.namespace != captured.namespace or seen.contains(entry.key_ptr.member)) continue;
                const declaration_ = @field(engine, pair[1]).items[entry.value_ptr.*];
                const identity = declaration_.identity;
                var scheme: T.Scheme = .{};
                if (comptime std.mem.eql(u8, pair[0], "nominal_names")) {
                    if (declaration_.parameters.len == 0) {
                        scheme.row_variables = declaration_.alias_rows;
                        scheme.root = declaration_.alias;
                        if (scheme.root == 0) scheme.root = try engine.types.nominal(identity, &.{});
                    }
                }
                var depth: u32 = 1_000_001;
                if (identity.unit == engine.unit) depth = 1_000_000;
                if (identity.unit == engine.prelude_unit) depth = 1_000_002;
                try out.add(.{ .name = entry.key_ptr.member, .kind = .type_, .scheme = scheme, .identity = identity, .distance = depth });
            }
        }
    }
    if (!type_context and !constructors_only) {
        var types = engine.nominal_names.iterator();
        while (types.next()) |entry| {
            if (entry.key_ptr.namespace != captured.namespace or seen.contains(entry.key_ptr.member)) continue;
            const declaration_ = engine.nominals.items[entry.value_ptr.*];
            if (declaration_.alias != 0) continue;
            if (declaration_.identity.unit == engine.unit and engine.tree.node(declaration_.declaration).tag == .type_alias_decl) continue;
            try out.add(.{ .name = entry.key_ptr.member, .kind = .type_, .scheme = .{ .root = try engine.types.typeConstructor(declaration_.identity) }, .identity = declaration_.identity, .distance = 1_000_000 });
        }
    }
    if (captured.namespace == 0 and !constructors_only) {
        inline for (.{ "qualified", "nominal_names", "constructor_names", "contract_names", "effect_family_names", "effect_operation_names" }) |map| {
            var keys = @field(engine, map).keyIterator();
            while (keys.next()) |key| {
                if (key.namespace == 0 or seen.contains(key.namespace)) continue;
                try out.add(.{ .name = key.namespace, .kind = .module, .distance = 1_000_001 });
            }
        }
    }
    return out.finish();
}
