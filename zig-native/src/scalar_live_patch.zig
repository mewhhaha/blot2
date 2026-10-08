//! Executable live-patching experiment for closed, stateless scalar modules.
//! Heap storage, globals, imports, captured functions and suspended effects are
//! rejected. All calls use stable table slots; exported trampolines keep their
//! original Wasm function identities. A replacement module never runs startup
//! or writes the table while instantiating.
const std = @import("std");
const wasm = @import("wasm.zig");
const ir = @import("runtime_ir.zig");
const function_key = @import("runtime_function_key.zig");
const format = @import("dependency_format.zig");
const A = std.mem.Allocator;

pub const Delta = struct {
    allocator: A,
    bytes: []u8,
    slots: []u32,
    base: format.Digest,
    next: format.Digest,
    pub fn deinit(self: *Delta) void {
        self.allocator.free(self.bytes);
        self.allocator.free(self.slots);
        self.* = undefined;
    }
};
pub const Image = struct {
    module: wasm.Module,
    digest: format.Digest,
    pub fn deinit(self: *Image) void {
        self.module.deinit();
        self.* = undefined;
    }
    /// Owns every type, name, local and instruction after the producer dies.
    /// This admission is intentionally stronger than machine-signature equality.
    pub fn capture(a: A, source: *const wasm.Module) !?Image {
        if (!admitted(source)) return null;
        var module = try signatures(a, source);
        errdefer module.deinit();
        for (source.functions.items) |function| {
            const id = try module.addFunction(function.parameters, function.result);
            for (function.locals.items) |ty| _ = try module.addLocal(id, ty);
            try module.emitSlice(id, function.instructions.items);
        }
        for (source.exports.items) |item| try module.exportFunction(item.index, item.name, item.parameter, item.result);
        const bytes = try module.assemble();
        defer a.free(bytes);
        return .{ .module = module, .digest = format.digest(bytes) };
    }
    pub fn initial(self: *const Image) ![]u8 {
        const a = self.module.allocator;
        var module = try signatures(a, &self.module);
        defer module.deinit();
        for (self.module.functions.items) |function| _ = try linkFunction(&module, &self.module, function);
        // Exported wrappers remain in the original instance. Every call enters
        // the current function through its stable slot, including recursive calls.
        for (self.module.exports.items) |item| {
            const source = self.module.functions.items[item.index];
            const wrapper = try module.addFunction(source.parameters, source.result);
            for (source.parameters, 0..) |_, index| try module.emit(wrapper, .{ .op = .local_get, .operand = @intCast(index) });
            try module.emit(wrapper, .{ .op = .i32_const, .operand = item.index });
            try module.emit(wrapper, .{ .op = .call_indirect, .operand = source.signature });
            try module.exportFunction(wrapper, item.name, item.parameter, item.result);
        }
        module.indirect = true;
        const bytes = try module.assembleWithOptions(.{ .export_function_table = true });
        defer a.free(bytes);
        var payload = wasm.Bytes.init(a);
        defer payload.deinit();
        try payload.raw(&.{ 1, 0 }); // version, initial image
        try payload.raw(&self.digest);
        try word(&payload, @intCast(self.module.functions.items.len));
        return withManifest(a, bytes, payload.items());
    }
    /// Changed functions only. The host checks base/next, instantiates without
    /// side effects, then updates these slots while no guest call is active.
    pub fn delta(self: *const Image, previous: *const Image) !?Delta {
        if (!sameABI(&previous.module, &self.module)) return null;
        const a = self.module.allocator;
        var module = try signatures(a, &self.module);
        defer module.deinit();
        var slots: std.ArrayList(u32) = .empty;
        defer slots.deinit(a);
        for (self.module.functions.items, previous.module.functions.items, 0..) |function, prior, index| {
            if (function_key.equal(function, prior)) continue;
            const id = try linkFunction(&module, &self.module, function);
            const name = try a.print("{d}", .{index});
            defer a.free(name);
            // Patch exports are raw Wasm functions; the ordinary guest ABI is
            // present only in the initial module's stable wrappers.
            try module.exportFunction(id, name, .unit, .unit);
            try slots.append(a, @intCast(index));
        }
        const compiled = try module.assembleWithOptions(.{ .import_function_table = @intCast(self.module.functions.items.len) });
        defer a.free(compiled);
        var payload = wasm.Bytes.init(a);
        defer payload.deinit();
        try payload.raw(&.{ 1, 1 }); // version, delta
        try payload.raw(&previous.digest);
        try payload.raw(&self.digest);
        try word(&payload, @intCast(slots.items.len));
        for (slots.items) |slot| try word(&payload, slot);
        const bytes = try withManifest(a, compiled, payload.items());
        errdefer a.free(bytes);
        return .{ .allocator = a, .bytes = bytes, .slots = try slots.toOwnedSlice(a), .base = previous.digest, .next = self.digest };
    }
};
fn word(bytes: *wasm.Bytes, value: u32) A.Error!void {
    var encoded: [4]u8 = undefined;
    std.mem.writeInt(u32, &encoded, value, .little);
    try bytes.raw(&encoded);
}
fn withManifest(a: A, bytes: []const u8, manifest: []const u8) ![]u8 {
    var output = wasm.Bytes.init(a);
    defer output.deinit();
    try output.raw(bytes);
    var payload = wasm.Bytes.init(a);
    defer payload.deinit();
    try payload.name("blot:scalar-patch");
    try payload.raw(manifest);
    try output.section(0, payload.items());
    return output.buffer.toOwnedSlice(a);
}
fn signatures(a: A, source: *const wasm.Module) !wasm.Module {
    var module = wasm.Module.init(a);
    errdefer module.deinit();
    for (source.signatures.items) |signature| _ = try module.internType(signature.parameters, signature.result);
    return module;
}
fn linkFunction(module: *wasm.Module, source: *const wasm.Module, function: wasm.Function) !u32 {
    const id = try module.addFunction(function.parameters, function.result);
    for (function.locals.items) |ty| _ = try module.addLocal(id, ty);
    for (function.instructions.items) |instruction| {
        if (instruction.op == .call) {
            try module.emit(id, .{ .op = .i32_const, .operand = instruction.operand });
            try module.emit(id, .{ .op = .call_indirect, .operand = source.functions.items[instruction.operand].signature });
        } else try module.emit(id, instruction);
    }
    return id;
}
fn scalar(ty: ir.ValueType) bool {
    return ty == .i32 or ty == .f32;
}
fn boundary(ty: ir.Scalar) bool {
    return switch (ty) {
        .unit, .u32, .bool, .f32 => true,
        else => false,
    };
}
fn admitted(module: *const wasm.Module) bool {
    if (module.functions.items.len == 0 or module.functions.items.len > 65536 or module.exports.items.len == 0) return false;
    if (module.arena != null or module.host_references != null or module.indirect or module.start != null or module.public_arena or module.imports.items.len != 0 or module.globals.items.len != 0 or module.data.items.len != 0) return false;
    for (module.exports.items) |item| {
        if (item.global or item.callback != null or item.index >= module.functions.items.len or !boundary(item.parameter) or !boundary(item.result) or std.mem.eql(u8, item.name, "blot:patch:table")) return false;
        const function = module.functions.items[item.index];
        if (function.parameters.len != 1 or function.parameters[0] != item.parameter.machine() or function.result != item.result.machine()) return false;
    }
    for (module.signatures.items) |signature| {
        if (signature.result != .none and !scalar(signature.result)) return false;
        for (signature.parameters) |ty| if (!scalar(ty)) return false;
    }
    for (module.functions.items) |function| {
        if (function.signature >= module.signatures.items.len) return false;
        const signature = module.signatures.items[function.signature];
        if (function.result != signature.result or !std.mem.eql(ir.ValueType, function.parameters, signature.parameters)) return false;
        for (function.locals.items) |ty| if (!scalar(ty)) return false;
        for (function.instructions.items) |instruction| {
            if (instruction.op == .call) {
                if (instruction.operand >= module.functions.items.len) return false;
                continue;
            }
            // Fail closed on every operation with state, external observations
            // or hidden references. New opcodes inherit the IR effect contract.
            const contract = ir.fixed(instruction.op);
            switch (contract.effect) {
                .pure, .local, .control, .trap => {},
                else => return false,
            }
            if (contract.result != .none and !scalar(contract.result)) return false;
            for (contract.inputs[0..contract.arity]) |ty| if (ty != .none and !scalar(ty)) return false;
            switch (instruction.op) {
                .block, .loop, .if_ => if (instruction.operand != 0 and instruction.operand != @backingInt(ir.ValueType.none) and instruction.operand != @backingInt(ir.ValueType.i32) and instruction.operand != @backingInt(ir.ValueType.f32)) return false,
                .local_get, .local_set, .local_tee => if (instruction.operand >= function.parameters.len + function.locals.items.len) return false,
                else => {},
            }
        }
    }
    return true;
}
fn sameABI(a: *const wasm.Module, b: *const wasm.Module) bool {
    if (a.functions.items.len != b.functions.items.len or a.exports.items.len != b.exports.items.len or a.signatures.items.len != b.signatures.items.len) return false;
    for (a.signatures.items, b.signatures.items) |x, y| if (x.result != y.result or !std.mem.eql(ir.ValueType, x.parameters, y.parameters)) return false;
    for (a.functions.items, b.functions.items) |x, y| if (x.signature != y.signature) return false;
    for (a.exports.items, b.exports.items) |x, y| if (x.index != y.index or x.parameter != y.parameter or x.result != y.result or !std.mem.eql(u8, x.name, y.name)) return false;
    return true;
}
