//! Private engine replay of a pinned pre-outline IR capture.
const std = @import("std");
const ir = @import("backend/runtime_ir.zig");
const wasm = @import("backend/wasm.zig");
const outline = @import("backend/wasm_scope_outline.zig");
const Span = struct { offset: usize, bytes: usize, count: usize };
const Function = struct { id: u32, parameters: Span, locals: Span, instructions: Span, result: u8, signature: u32 };
const Signature = struct { parameters: Span, result: u8 };
const Root = struct { function: u32 };
const Helper = struct { function: u32, root: u32, rbd: Span, expressions: usize, layouts: usize };
const Capture = struct { format: u32, binary_bytes: usize, binary_sha256: []const u8, functions: []Function, roots: []Root, helpers: []Helper, signatures: []Signature, imports: []u32, globals: usize };
fn types(a: std.mem.Allocator, raw: []const u8, span: Span) ![]ir.ValueType {
    const output = try a.alloc(ir.ValueType, span.count);
    for (output, raw[span.offset..][0..span.bytes]) |*ty, byte| ty.* = @fromBackingInt(@intCast(byte));
    return output;
}
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len < 2 or args.len > 3) return error.CaptureDirectoryRequired;
    const path = try std.Io.Dir.path.join(a, &.{ args[1], "ir.json" });
    const raw = try std.Io.Dir.cwd().readFileAlloc(init.io, try std.Io.Dir.path.join(a, &.{ args[1], "ir.bin" }), a, .limited(200 * 1024 * 1024));
    const metadata = try std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(16 * 1024 * 1024));
    const parsed = try std.json.parseFromSlice(Capture, a, metadata, .{ .ignore_unknown_fields = true });
    const capture = parsed.value;
    var input_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(raw, &input_digest, .{});
    if (capture.format != 1 or capture.binary_bytes != raw.len or !std.mem.eql(u8, capture.binary_sha256, &std.fmt.bytesToHex(input_digest, .lower))) return error.InvalidCapture;
    var module = wasm.Module.init(a);
    module.memory_model = .data_stacks;
    for (capture.signatures) |signature| try module.signatures.append(a, .{ .parameters = try types(a, raw, signature.parameters), .result = @fromBackingInt(@intCast(signature.result)) });
    // All fields use the process arena, including partial construction.
    // zig-analyzer: disable-next-line missing-errdefer
    for (capture.imports) |signature| try module.imports.append(a, .{ .module = try a.dupe(u8, ""), .name = try a.dupe(u8, ""), .signature = signature });
    for (0..capture.globals) |_| try module.globals.append(a, .{ .scalar = .u32, .bits = 0, .mutable = true });
    for (capture.functions) |source| {
        var function: ir.Function = .{ .parameters = try types(a, raw, source.parameters), .result = @fromBackingInt(@intCast(source.result)), .signature = source.signature };
        function.locals = .fromOwnedSlice(try types(a, raw, source.locals));
        const code = try a.alloc(ir.Instruction, source.instructions.count);
        for (code, 0..) |*inst, index| inst.* = @bitCast(std.mem.readInt(u64, raw[source.instructions.offset + index * 8 ..][0..8], .little));
        function.instructions = .fromOwnedSlice(code);
        try module.functions.append(a, function);
    }
    var context = outline.Context.init(a, &module, .scoped_numeric_adapter_nonreentrant, .{});
    if (@hasField(outline.Options, "verify_copy_inputs")) context.options.verify_copy_inputs = args.len == 3;
    for (capture.roots) |root| try context.registerRoot(root.function);
    for (capture.helpers, 0..) |helper, ordinal| {
        const rbd = try a.alloc(u32, helper.rbd.count);
        for (rbd, 0..) |*id, index| id.* = std.mem.readInt(u32, raw[helper.rbd.offset + index * 4 ..][0..4], .little);
        try context.helpers.append(a, .{ .function = helper.function, .root = helper.root, .read_before_def = rbd, .credit = .{ .expressions = helper.expressions, .layouts = helper.layouts } });
        for (context.roots.items) |*root| if (root.function == helper.root) {
            try root.helpers.append(a, @intCast(ordinal));
        };
    }
    for (context.roots.items) |*root| {
        const source = &module.functions.items[root.function];
        try root.totals.appendNTimes(a, .{}, source.parameters.len + source.locals.items.len);
        root.scanned = source.instructions.items.len;
        for (source.instructions.items) |inst| if (inst.op == .local_get or inst.op == .local_set or inst.op == .local_tee) {
            root.totals.items[inst.operand].references += 1;
            if (inst.op != .local_get) root.totals.items[inst.operand].writes += 1;
        };
        for (root.helpers.items) |id| for (module.functions.items[context.helpers.items[id].function].instructions.items) |inst| if (inst.op == .local_get or inst.op == .local_set or inst.op == .local_tee) {
            root.totals.items[inst.operand].references += 1;
            if (inst.op != .local_get) root.totals.items[inst.operand].writes += 1;
        };
    }
    const start = std.Io.Clock.awake.now(init.io);
    const stats = try context.finalize();
    const duration = start.durationTo(std.Io.Clock.awake.now(init.io));
    var instructions: usize = 0;
    var locals: usize = 0;
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    for (module.functions.items) |function| {
        instructions += function.instructions.items.len;
        locals += function.locals.items.len;
        hash.update(std.mem.sliceAsBytes(function.locals.items));
        hash.update(std.mem.sliceAsBytes(function.instructions.items));
    }
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    const output = try std.json.Stringify.valueAlloc(a, .{ .stats = stats, .ns = duration.nanoseconds, .instructions = instructions, .locals = locals, .prepared_ir_sha256 = std.fmt.bytesToHex(digest, .lower) }, .{});
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    try stdout.interface.print("{s}\n", .{output});
    try stdout.interface.flush();
}
