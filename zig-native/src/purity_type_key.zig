//! Frozen state_specialize TypeKey grammar. Used only for diagnostic snapshots.
const std = @import("std");
const T = @import("types.zig");
const A = std.mem.Allocator;
pub const OriginError = T.Error || error{SourceIdentityUnavailable};
pub const Error = OriginError || error{ AmbiguousTypeKey, SpecializationLimit };
pub const Kind = enum { nominal, operation };
pub const Identity = struct {
    module: []const u8,
    declaration: []const u8,
    pub fn deinit(self: Identity, allocator: A) void {
        allocator.free(self.module);
        allocator.free(self.declaration);
    }
};
pub const Context = struct {
    allocator: A,
    types: *T.Store,
    source: *anyopaque,
    origin: *const fn (*anyopaque, A, T.NominalIdentity, Kind) OriginError!Identity,
    arguments: *const fn (*anyopaque, A, T.NominalIdentity, Kind, []const T.Id) OriginError![]T.Id,

    fn count(text: []const u8) Error!usize {
        return std.unicode.utf8CountCodepoints(text) catch error.TypeLimit;
    }
    fn pack(self: Context, text: []const u8) Error![]u8 {
        return self.allocator.print("{d}:{s}", .{ try count(text), text });
    }
    fn nominal(self: Context, identity: Identity) Error![]u8 {
        const module = try self.pack(identity.module);
        defer self.allocator.free(module);
        const declaration = try self.pack(identity.declaration);
        defer self.allocator.free(declaration);
        return std.mem.concat(self.allocator, u8, &.{ module, declaration });
    }
    pub fn typesKey(self: Context, values: []const T.Id, fuel: usize) Error![]u8 {
        const owned_values = try self.allocator.dupe(T.Id, values);
        defer self.allocator.free(owned_values);
        var bytes: std.ArrayList(u8) = .empty;
        errdefer bytes.deinit(self.allocator);
        var remaining = fuel;
        for (owned_values) |value| {
            if (remaining == 0) return error.SpecializationLimit;
            remaining -= 1;
            const key = try self.typeKey(value, remaining);
            defer self.allocator.free(key);
            const packed_key = try self.pack(key);
            defer self.allocator.free(packed_key);
            try bytes.appendSlice(self.allocator, packed_key);
        }
        if (remaining == 0) return error.SpecializationLimit;
        return bytes.toOwnedSlice(self.allocator);
    }
    pub fn operation(self: Context, label: T.Effects.Label, fuel: usize) Error!Identity {
        const operation_ = self.types.operation(label);
        if (label == T.foreign_operation) return self.fixed("blot:compiler", "Foreign");
        if (operation_.identity.unit == std.math.maxInt(u32) and (operation_.identity.decl == 1 or operation_.identity.decl == 2)) {
            const args = self.types.list(operation_.arguments);
            if (args.len != 1) return error.AmbiguousTypeKey;
            const key = try self.typeKey(args[0], fuel);
            defer self.allocator.free(key);
            const module = try self.allocator.dupe(u8, "blot:state");
            errdefer self.allocator.free(module);
            return .{ .module = module, .declaration = try self.allocator.print("{s}:{s}", .{ if (operation_.identity.decl == 1) @as([]const u8, "read") else "write", key }) };
        }
        const identity = try self.origin(self.source, self.allocator, operation_.identity, .operation);
        errdefer identity.deinit(self.allocator);
        const args = try self.arguments(self.source, self.allocator, operation_.identity, .operation, self.types.list(operation_.arguments));
        defer self.allocator.free(args);
        if (args.len == 0 and operation_.arguments.len == 0) return identity;
        const key = try self.typesKey(args, fuel);
        defer self.allocator.free(key);
        const declaration = try self.allocator.print("{s}<{s}>", .{ identity.declaration, key });
        self.allocator.free(identity.declaration);
        return .{ .module = identity.module, .declaration = declaration };
    }
    fn fixed(self: Context, module: []const u8, declaration: []const u8) Error!Identity {
        const owned_module = try self.allocator.dupe(u8, module);
        errdefer self.allocator.free(owned_module);
        return .{ .module = owned_module, .declaration = try self.allocator.dupe(u8, declaration) };
    }
    fn less(_: void, left: Identity, right: Identity) bool {
        const order = std.mem.order(u8, left.module, right.module);
        return order == .lt or order == .eq and std.mem.lessThan(u8, left.declaration, right.declaration);
    }
    fn rowKey(self: Context, row: T.Effects.Id, _: usize) Error![]u8 {
        const resolved = try self.types.resolveEffects(row, 0);
        if (self.types.row(resolved).tail != .closed) return error.AmbiguousTypeKey;
        var identities: std.ArrayList(Identity) = .empty;
        defer {
            for (identities.items) |identity| identity.deinit(self.allocator);
            identities.deinit(self.allocator);
        }
        // Row order is canonicalized only inside TypeKey, as frozen row_key.
        // Ambient purity selects its original first label before this formatter.
        const labels = try self.allocator.dupe(T.Effects.Label, self.types.rowLabels(resolved));
        defer self.allocator.free(labels);
        for (labels) |label| {
            const identity = try self.operation(label, 65536);
            errdefer identity.deinit(self.allocator);
            try identities.append(self.allocator, identity);
        }
        std.mem.sort(Identity, identities.items, {}, less);
        var bytes: std.ArrayList(u8) = .empty;
        errdefer bytes.deinit(self.allocator);
        for (identities.items) |identity| {
            const nominal_key = try self.nominal(identity);
            defer self.allocator.free(nominal_key);
            const key = try self.pack(nominal_key);
            defer self.allocator.free(key);
            try bytes.appendSlice(self.allocator, key);
        }
        return bytes.toOwnedSlice(self.allocator);
    }
    fn functionKey(self: Context, parameter_id: T.Id, result_id: T.Id, row: T.Effects.Id, fuel: usize) Error![]u8 {
        if (fuel == 0) return error.SpecializationLimit;
        const parameter = try self.typeKey(parameter_id, fuel - 1);
        defer self.allocator.free(parameter);
        const result = try self.typeKey(result_id, fuel - 1);
        defer self.allocator.free(result);
        const effects = try self.rowKey(row, fuel - 1);
        defer self.allocator.free(effects);
        const parameter_key = try self.pack(parameter);
        defer self.allocator.free(parameter_key);
        const result_key = try self.pack(result);
        defer self.allocator.free(result_key);
        const effect_key = try self.pack(effects);
        defer self.allocator.free(effect_key);
        return std.mem.concat(self.allocator, u8, &.{ "c", parameter_key, result_key, effect_key });
    }
    pub fn typeKey(self: Context, id: T.Id, fuel: usize) Error![]u8 {
        if (fuel == 0) return error.SpecializationLimit;
        const rest = fuel - 1;
        const resolved = try self.types.resolve(id, 0);
        const node = self.types.node(resolved);
        switch (node.tag) {
            .unit => return self.allocator.dupe(u8, "u"),
            .u32 => return self.allocator.dupe(u8, "i"),
            .f32 => return self.allocator.dupe(u8, "f"),
            .boolean => return self.allocator.dupe(u8, "b"),
            .nominal => {
                const identity = try self.origin(self.source, self.allocator, .{ .unit = node.a, .decl = node.b }, .nominal);
                defer identity.deinit(self.allocator);
                const name = try self.nominal(identity);
                defer self.allocator.free(name);
                const logical = try self.arguments(self.source, self.allocator, .{ .unit = node.a, .decl = node.b }, .nominal, self.types.nominalArguments(node));
                defer self.allocator.free(logical);
                const args = try self.typesKey(logical, rest);
                defer self.allocator.free(args);
                const packed_args = try self.pack(args);
                defer self.allocator.free(packed_args);
                return std.mem.concat(self.allocator, u8, &.{ "n", name, packed_args });
            },
            .array, .list => {
                const element = try self.typeKey(node.a, rest);
                defer self.allocator.free(element);
                const key = try self.pack(element);
                defer self.allocator.free(key);
                return std.mem.concat(self.allocator, u8, &.{ if (node.tag == .list) "l" else "a", key });
            },
            .product => {
                const elements = try self.typesKey(self.types.extra.items[node.a..][0..node.b], rest);
                defer self.allocator.free(elements);
                const key = try self.pack(elements);
                defer self.allocator.free(key);
                return std.mem.concat(self.allocator, u8, &.{ "p", key });
            },
            .function => return self.functionKey(node.a, node.b, node.c, fuel),
            .demand => {
                // Native Demand owns payload+row; frozen AppliedTy owns one
                // Unit callback. Encode its exact logical source representation.
                if (rest == 0) return error.SpecializationLimit;
                const computation = try self.functionKey(T.unit, node.a, node.c, rest - 1);
                defer self.allocator.free(computation);
                const argument = try self.pack(computation);
                defer self.allocator.free(argument);
                const arguments_key = try self.pack(argument);
                defer self.allocator.free(arguments_key);
                const identity = try self.fixed("blot:compiler", "Demand");
                defer identity.deinit(self.allocator);
                const nominal_key = try self.nominal(identity);
                defer self.allocator.free(nominal_key);
                return std.mem.concat(self.allocator, u8, &.{ "n", nominal_key, arguments_key });
            },
            else => return error.AmbiguousTypeKey,
        }
    }
};
