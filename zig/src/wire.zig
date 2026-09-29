//! Single-pass native protocol decoder. Only the finished CST and request live
//! in semantic storage; cursors and parent frames are ordinary Zig data.
const std = @import("std");
const r = @import("runtime.zig");
const V = r.Value;
const version = @import("generated/protocol.zig").version;
const Invalid = error{InvalidRequest};

const Decoder = struct {
    ctx: *r.Context,
    words: []const V,
    position: usize = 0,
    strings: []V = &.{},
    failure_offset: usize = 0,
    failure_message: []const u8 = "",

    fn reject(self: *Decoder, offset: usize, message: []const u8) Invalid {
        self.failure_offset = offset;
        self.failure_message = message;
        return error.InvalidRequest;
    }
    fn read(self: *Decoder, label: []const u8) Invalid!u32 {
        if (self.position == self.words.len) {
            const message = std.fmt.allocPrint(self.ctx.allocator(), "truncated request while reading {s}", .{label}) catch @panic("out of memory");
            return self.reject(self.position, message);
        }
        const value = r.toWord(self.words[self.position]);
        self.position += 1;
        return value;
    }
    fn natural(self: *Decoder, comptime label: []const u8) Invalid!u64 {
        const low = try self.read(label ++ " low word");
        const high_offset = self.position;
        const high = try self.read(label ++ " high word");
        if (high > 0xffff) return self.reject(high_offset, "Nat high word exceeds 16 bits");
        return @as(u64, low) | (@as(u64, high) << 32);
    }
    fn dictionary(self: *Decoder) Invalid!void {
        const count = try self.read("dictionary count");
        if (count > self.words.len - self.position) return self.reject(self.position - 1, "dictionary count exceeds remaining request words");
        self.strings = self.ctx.allocator().alloc(V, count) catch @panic("out of memory");
        for (self.strings) |*entry| {
            const length = try self.read("dictionary string length");
            const available = @min(length, self.words.len - self.position);
            const points = self.ctx.allocator().alloc(u32, available) catch @panic("out of memory");
            // Check available scalars before reporting a truncated string: an
            // earlier invalid scalar has priority in the reference decoder.
            for (points) |*point| {
                const offset = self.position;
                const code = try self.read("dictionary string character");
                if (code > 0x10ffff or (code >= 0xd800 and code <= 0xdfff)) return self.reject(offset, "string contains an invalid Unicode scalar value");
                point.* = code;
            }
            if (available != length) {
                _ = try self.read("dictionary string character");
                unreachable;
            }
            entry.* = self.ctx.fromCodepoints(points);
        }
    }
    fn string(self: *Decoder, label: []const u8) Invalid!V {
        const index = try self.read(label);
        if (index >= self.strings.len) return self.reject(self.position - 1, "CST string ID is outside the request dictionary");
        return self.strings[index];
    }
    const Parent = struct {
        kind: V,
        field: V,
        text: V,
        offset: V,
        remaining: u32,
        reversed: V = r.empty(.Nil),
    };
    fn header(self: *Decoder) Invalid!Parent {
        const kind = try self.string("CST kind ID");
        const field = try self.string("CST field ID");
        const text = try self.string("CST text ID");
        const offset = try self.natural("CST offset");
        const children = try self.read("CST child count");
        return .{ .kind = kind, .field = field, .text = text, .offset = r.nat(offset), .remaining = children };
    }
    fn tree(self: *Decoder) Invalid!V {
        var parents: std.ArrayList(Parent) = .empty;
        defer parents.deinit(self.ctx.allocator());
        var fuel = self.words.len;
        while (true) {
            // Header errors precede the traversal-fuel diagnostic.
            var current = try self.header();
            if (fuel == 0) return self.reject(self.position, "CST traversal exceeded its request word-count bound");
            fuel -= 1;
            if (current.remaining != 0) {
                current.remaining -= 1;
                parents.append(self.ctx.allocator(), current) catch @panic("out of memory");
                continue;
            }
            var node = self.ctx.node(.cst_Cst, &.{ current.kind, current.field, current.text, current.offset, r.empty(.Nil) });
            while (true) {
                if (parents.items.len == 0) return node;
                if (fuel == 0) return self.reject(self.position, "CST traversal exceeded its request word-count bound");
                fuel -= 1;
                const parent = &parents.items[parents.items.len - 1];
                parent.reversed = self.ctx.node(.Cons, &.{ node, parent.reversed });
                if (parent.remaining != 0) {
                    parent.remaining -= 1;
                    break;
                }
                const complete = parents.pop().?;
                // These list cells are private to this decoder until the CST
                // is published. Reverse links rather than allocate a second list.
                const children = r.Context.reverseOwnedList(complete.reversed);
                node = self.ctx.node(.cst_Cst, &.{ complete.kind, complete.field, complete.text, complete.offset, children });
            }
        }
    }
    fn decode(self: *Decoder) Invalid!V {
        if (try self.read("protocol magic") != 0x424c4f54) return self.reject(0, "invalid protocol magic; expected BLOT");
        if (try self.read("protocol version") != version) return self.reject(1, std.fmt.comptimePrint("unsupported native protocol version; expected {d}", .{version}));
        const opcode = try self.read("operation");
        if (opcode > 9) return self.reject(2, "unknown operation; expected 0..9");
        const fuel = r.nat(if (opcode == 2) try self.natural("prelude fuel") else try self.natural("frontend fuel"));
        const steps = if (opcode == 2) r.nat(0) else r.nat(try self.natural("const steps"));
        try self.dictionary();
        const operation = switch (opcode) {
            0, 3, 5 => r.empty(.native_request_Analyze),
            1, 4, 6 => r.empty(.native_request_Compile),
            else => r.empty(.native_request_EmitWasm),
        };
        const request = switch (opcode) {
            2 => self.ctx.node(.native_request_OpenSession, &.{ try self.tree(), fuel }),
            0, 1, 7 => blk: {
                const root = try self.tree();
                const prelude = try self.tree();
                break :blk self.ctx.node(.native_request_Request, &.{ operation, fuel, steps, root, prelude });
            },
            3, 4, 8 => self.ctx.node(.native_request_SessionRequest, &.{ operation, fuel, steps, try self.tree() }),
            5, 6, 9 => blk: {
                const count = try self.read("declaration count");
                var reversed = r.empty(.Nil);
                for (0..count) |_| {
                    const at = self.position;
                    const value = switch (try self.read("declaration tag")) {
                        0 => self.ctx.node(.native_session_Retained, &.{r.nat(try self.natural("retained declaration identity"))}),
                        1 => self.ctx.node(.native_session_Replaced, &.{try self.tree()}),
                        else => return self.reject(at, "unknown declaration tag; expected 0 retained or 1 replaced"),
                    };
                    reversed = self.ctx.node(.Cons, &.{ value, reversed });
                }
                break :blk self.ctx.node(.native_request_SessionPatch, &.{ operation, fuel, steps, r.Context.reverseOwnedList(reversed) });
            },
            else => unreachable,
        };
        if (self.position != self.words.len) return self.reject(self.position, "trailing words after the request CST");
        return self.ctx.node(.Done, &.{request});
    }
};

pub fn decode(ctx: *r.Context, frame: V) V {
    r.assert(r.tag(frame) == .native_io_Frame);
    const words = r.arrayValues(r.field(frame, 0));
    const count = r.toWord(r.field(frame, 1));
    r.assert(count <= words.len);
    var decoder: Decoder = .{ .ctx = ctx, .words = words[0..count] };
    return decoder.decode() catch {
        var offset: [32]u8 = undefined;
        const subject = std.fmt.bufPrint(&offset, "word:{d}", .{decoder.failure_offset}) catch unreachable;
        const diagnostic = ctx.node(.model_Diagnostic, &.{ r.literal("native_protocol"), ctx.string(subject), ctx.string(decoder.failure_message) });
        return ctx.node(.Fail, &.{diagnostic});
    };
}
