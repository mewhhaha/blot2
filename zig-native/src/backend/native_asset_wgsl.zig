//! Bounded WGSL reflection for generated asset modules. No shader body is retained.
const std = @import("std");
const Allocator = std.mem.Allocator;
pub const Issue = struct { start: u32 = 0, end: u32 = 0, code: []const u8, message: []const u8 };
pub const Result = union(enum) { source: []u8, issue: Issue };
const Error = Allocator.Error || error{InvalidAsset};
const limit = 16 * 1024 * 1024;

pub fn deinit(allocator: Allocator, result: *Result) void {
    switch (result.*) {
        .source => |source| allocator.free(source),
        .issue => |issue| allocator.free(issue.message),
    }
    result.* = undefined;
}

pub fn generate(allocator: Allocator, bytes: []const u8) Allocator.Error!Result {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var reader: Reader = .{ .a = arena.allocator(), .input = bytes };
    reader.run() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidAsset => {
            var issue = reader.issue.?;
            issue.message = try allocator.dupe(u8, issue.message);
            return .{ .issue = issue };
        },
    };
    const length = std.math.add(usize, reader.header.items.len, reader.body.items.len) catch return error.OutOfMemory;
    const source = try allocator.alloc(u8, length);
    @memcpy(source[0..reader.header.items.len], reader.header.items);
    @memcpy(source[reader.header.items.len..], reader.body.items);
    return .{ .source = source };
}

const Token = struct { text: []const u8, start: u32, end: u32, number: bool = false };
const Kind = enum { unknown, x32, f32_value, u32_value, i32_value, boolean, f16_value };
const Value = struct { kind: Kind = .unknown, n: f64 = 0, elements: []const Value = &.{}, literal: bool = true };
const Binding = struct { name: []const u8, value: Value };
const Field = struct { name: []const u8, type_name: []const u8, token: Token };
const Text = std.ArrayList(u8);
const Reader = struct {
    a: Allocator,
    input: []const u8,
    tokens: std.ArrayList(Token) = .empty,
    at: usize = 0,
    visits: usize = 0,
    bindings: std.ArrayList(Binding) = .empty,
    binding_index: std.StringHashMapUnmanaged(u32) = .empty,
    aliases: std.StringHashMapUnmanaged([]const u8) = .empty,
    fields: std.ArrayList(Field) = .empty,
    parameters: bool = false,
    constant_mode: bool = false,
    call_depth: usize = 0,
    header: Text = .empty,
    body: Text = .empty,
    issue: ?Issue = null,

    fn fail(self: *Reader, token: Token, code: []const u8, message: []const u8) Error {
        self.issue = .{ .start = token.start, .end = token.end, .code = code, .message = message };
        return error.InvalidAsset;
    }
    fn syntax(self: *Reader) Error {
        return self.fail(self.peek(), "asset_wgsl", "Malformed WGSL asset");
    }
    fn budget(self: *Reader, depth: usize) Error!void {
        self.visits += 1;
        if (depth > 128 or self.visits > 1_000_000) return self.fail(self.peek(), "asset_limit", "WGSL asset exceeds the structural budget");
    }
    fn peek(self: *Reader) Token {
        return self.tokens.items[self.at];
    }
    fn is(self: *Reader, text: []const u8) bool {
        return std.mem.eql(u8, self.peek().text, text);
    }
    fn take(self: *Reader, text: []const u8) bool {
        if (!self.is(text)) return false;
        self.at += 1;
        return true;
    }
    fn expect(self: *Reader, text: []const u8) Error!void {
        if (!self.take(text)) return self.syntax();
    }
    fn name(self: *Reader) Error!Token {
        const token = self.peek();
        if (token.text.len == 0 or !identifierStart(token.text[0])) return self.syntax();
        self.at += 1;
        return token;
    }
    fn put(self: *Reader, out: *Text, text: []const u8) Error!void {
        if (text.len > limit or out.items.len > limit - text.len) return self.fail(self.peek(), "asset_limit", "Generated asset module exceeds 16 MiB");
        try out.appendSlice(self.a, text);
    }
    fn lex(self: *Reader) Error!void {
        if (self.input.len > limit) return self.fail(.{ .text = "", .start = 0, .end = 0 }, "asset_limit", "WGSL asset exceeds 16 MiB");
        if (!std.unicode.utf8ValidateSlice(self.input)) return self.fail(.{ .text = "", .start = 0, .end = @intCast(self.input.len) }, "asset_unicode", "WGSL asset must be valid UTF-8");
        var pos: usize = 0;
        while (pos < self.input.len) {
            const byte = self.input[pos];
            if (std.mem.findScalar(u8, " \t\r\n", byte) != null) {
                pos += 1;
                continue;
            }
            if (std.mem.startsWith(u8, self.input[pos..], "//")) {
                while (pos < self.input.len and self.input[pos] != '\n') pos += 1;
                continue;
            }
            if (std.mem.startsWith(u8, self.input[pos..], "/*")) {
                const start = pos;
                pos += 2;
                var nesting: usize = 1;
                while (pos < self.input.len and nesting != 0) {
                    if (std.mem.startsWith(u8, self.input[pos..], "/*")) {
                        nesting += 1;
                        if (nesting > 128) return self.fail(.{ .text = "", .start = @intCast(start), .end = @intCast(pos + 2) }, "asset_limit", "WGSL comment nesting exceeds 128");
                        pos += 2;
                    } else if (std.mem.startsWith(u8, self.input[pos..], "*/")) {
                        nesting -= 1;
                        pos += 2;
                    } else pos += 1;
                }
                if (nesting != 0) return self.fail(.{ .text = "", .start = @intCast(start), .end = @intCast(pos) }, "asset_wgsl", "Unterminated WGSL block comment");
                continue;
            }
            const start = pos;
            var number = false;
            if (identifierStart(byte)) {
                pos += 1;
                while (pos < self.input.len and identifierContinue(self.input[pos])) pos += 1;
            } else if (std.ascii.isDigit(byte) or (byte == '.' and pos + 1 < self.input.len and std.ascii.isDigit(self.input[pos + 1]))) {
                number = true;
                pos += 1;
                while (pos < self.input.len) {
                    const c = self.input[pos];
                    if (std.ascii.isAlphanumeric(c) or c == '.' or c == '_') {
                        pos += 1;
                    } else if ((c == '+' or c == '-') and pos > start and std.mem.findScalar(u8, "eEpP", self.input[pos - 1]) != null) {
                        pos += 1;
                    } else break;
                }
            } else {
                if (std.mem.findScalar(u8, "@{}()[]<>,:;.=+-*/%!~&|^", byte) == null) return self.fail(.{ .text = "", .start = @intCast(start), .end = @intCast(start + 1) }, "asset_wgsl", "Invalid WGSL token");
                pos += 1;
                // Angle brackets remain individual tokens: template closers and
                // shift operators share spelling and are disambiguated by syntax.
                if (pos < self.input.len and byte != '<' and byte != '>') {
                    const pair = self.input[start .. pos + 1];
                    for ([_][]const u8{ "->", "==", "!=", "&&", "||", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "++", "--" }) |op_text| {
                        if (std.mem.eql(u8, pair, op_text)) {
                            pos += 1;
                            break;
                        }
                    }
                }
            }
            if (self.tokens.items.len == 1_000_000) return self.fail(.{ .text = "", .start = @intCast(start), .end = @intCast(pos) }, "asset_limit", "WGSL token count exceeds 1000000");
            try self.tokens.append(self.a, .{ .text = self.input[start..pos], .start = @intCast(start), .end = @intCast(pos), .number = number });
        }
        try self.tokens.append(self.a, .{ .text = "", .start = @intCast(pos), .end = @intCast(pos) });
    }
    fn attributes(self: *Reader) Error!void {
        while (self.take("@")) {
            _ = try self.name();
            if (self.take("(")) {
                if (!self.take(")")) {
                    while (true) {
                        _ = try self.expression(0, 0);
                        if (self.take(")")) break;
                        try self.expect(",");
                        if (self.take(")")) break;
                    }
                }
            }
        }
    }
    fn typeName(self: *Reader, depth: usize) Error![]const u8 {
        try self.budget(depth);
        const token = try self.name();
        if (self.take("<")) {
            var parameter: usize = 0;
            while (true) {
                if (self.peek().number or (std.mem.eql(u8, token.text, "array") and parameter == 1)) {
                    _ = try self.expression(8, depth + 1);
                } else {
                    _ = try self.typeName(depth + 1);
                }
                if (self.take(">")) break;
                try self.expect(",");
                parameter += 1;
            }
            return "";
        }
        return token.text;
    }
    fn structure(self: *Reader) Error!void {
        const token = try self.name();
        const selected = std.mem.eql(u8, token.text, "Parameters") and !self.parameters;
        if (selected) self.parameters = true;
        try self.expect("{");
        while (!self.take("}")) {
            try self.attributes();
            const field = try self.name();
            try self.expect(":");
            const type_name = try self.typeName(0);
            if (selected) try self.fields.append(self.a, .{ .name = field.text, .type_name = type_name, .token = field });
            if (self.take("}")) break;
            try self.expect(",");
        }
        _ = self.take(";");
    }
    fn variable(self: *Reader, is_const: bool, retain: bool) Error!void {
        if (self.take("<")) {
            _ = try self.name();
            if (self.take(",")) _ = try self.name();
            try self.expect(">");
        }
        const token = try self.name();
        if (self.take(":")) _ = try self.typeName(0);
        var value: Value = .{};
        if (self.take("=")) {
            const saved_mode = self.constant_mode;
            self.constant_mode = retain;
            value = try self.expression(0, 0);
            self.constant_mode = saved_mode;
        } else if (is_const) return self.syntax();
        try self.expect(";");
        if (retain) {
            const entry = try self.binding_index.getOrPut(self.a, token.text);
            if (entry.found_existing) {
                self.bindings.items[entry.value_ptr.*].value = value;
            } else {
                entry.value_ptr.* = @intCast(self.bindings.items.len);
                try self.bindings.append(self.a, .{ .name = token.text, .value = value });
            }
        }
    }
    fn function(self: *Reader) Error!void {
        _ = try self.name();
        try self.expect("(");
        if (!self.take(")")) {
            while (true) {
                try self.attributes();
                _ = try self.name();
                try self.expect(":");
                _ = try self.typeName(0);
                if (self.take(")")) break;
                try self.expect(",");
                if (self.take(")")) break;
            }
        }
        if (self.take("->")) {
            try self.attributes();
            _ = try self.typeName(0);
        }
        try self.block(0);
    }
    fn block(self: *Reader, depth: usize) Error!void {
        try self.budget(depth);
        try self.expect("{");
        while (!self.take("}")) try self.statement(depth + 1);
    }
    fn statement(self: *Reader, depth: usize) Error!void {
        try self.budget(depth);
        try self.attributes();
        if (self.is("{")) return self.block(depth + 1);
        if (self.take(";")) return;
        if (self.take("var") or self.take("let") or self.take("const")) return self.variable(false, false);
        if (self.take("if")) {
            _ = try self.expression(0, 0);
            try self.block(depth + 1);
            if (self.take("else")) {
                if (self.is("if")) return self.statement(depth + 1);
                try self.block(depth + 1);
            }
            return;
        }
        if (self.take("for")) {
            try self.expect("(");
            if (!self.take(";")) {
                if (self.take("var") or self.take("let")) {
                    try self.variable(false, false);
                } else {
                    try self.simpleStatement(";");
                }
            }
            if (!self.take(";")) {
                _ = try self.expression(0, 0);
                try self.expect(";");
            }
            if (!self.take(")")) try self.simpleStatement(")");
            return self.block(depth + 1);
        }
        if (self.take("while")) {
            _ = try self.expression(0, 0);
            return self.block(depth + 1);
        }
        if (self.take("loop") or self.take("continuing")) return self.block(depth + 1);
        if (self.take("switch")) {
            _ = try self.expression(0, 0);
            try self.expect("{");
            while (!self.take("}")) {
                if (self.take("case")) {
                    while (true) {
                        if (!self.take("default")) _ = try self.expression(0, 0);
                        if (!self.take(",")) break;
                    }
                } else try self.expect("default");
                _ = self.take(":");
                try self.block(depth + 1);
            }
            return;
        }
        if (self.take("return")) {
            if (!self.take(";")) {
                _ = try self.expression(0, 0);
                try self.expect(";");
            }
            return;
        }
        if (self.take("break")) {
            if (self.take("if")) _ = try self.expression(0, 0);
            return self.expect(";");
        }
        if (self.take("continue") or self.take("discard")) return self.expect(";");
        if (self.take("const_assert")) {
            _ = try self.expression(0, 0);
            return self.expect(";");
        }
        return self.simpleStatement(";");
    }
    fn simpleStatement(self: *Reader, closing: []const u8) Error!void {
        _ = try self.expression(0, 0);
        if (self.take("++") or self.take("--")) {} else {
            for ([_][]const u8{ "=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=" }) |op_text| {
                if (self.take(op_text)) {
                    _ = try self.expression(0, 0);
                    break;
                }
            }
        }
        try self.expect(closing);
    }
    fn run(self: *Reader) Error!void {
        try self.lex();
        while (!self.is("")) {
            try self.budget(0);
            try self.attributes();
            if (self.take(";")) continue;
            if (self.take("struct")) {
                try self.structure();
            } else if (self.take("alias") or self.take("type")) {
                const token = try self.name();
                try self.expect("=");
                const target = try self.typeName(0);
                try self.expect(";");
                try self.aliases.put(self.a, token.text, target);
            } else if (self.take("const")) {
                try self.variable(true, true);
            } else if (self.take("var") or self.take("override")) {
                try self.variable(false, false);
            } else if (self.take("fn")) {
                try self.function();
            } else if (self.take("enable") or self.take("requires")) {
                _ = try self.name();
                while (self.take(",")) _ = try self.name();
                try self.expect(";");
            } else if (self.take("diagnostic")) {
                try self.expect("(");
                _ = try self.name();
                try self.expect(",");
                _ = try self.name();
                if (self.take(".")) _ = try self.name();
                try self.expect(")");
                try self.expect(";");
            } else if (self.take("const_assert")) {
                _ = try self.expression(0, 0);
                try self.expect(";");
            } else return self.syntax();
        }
        if (self.parameters) {
            if (self.fields.items.len > 4) return self.fail(self.fields.items[4].token, "asset_wgsl_parameters", "Parameters must contain at most four f32 fields");
            try self.put(&self.header, "type Parameters is data = #Parameters { ");
            for (self.fields.items, 0..) |field, index| {
                if (!std.mem.eql(u8, self.resolve(field.type_name), "f32")) return self.fail(field.token, "asset_wgsl_parameters", "Parameters fields must resolve to f32");
                if (!blotName(field.name)) return self.fail(field.token, "asset_identifier", "WGSL field is not a Blot identifier");
                if (index != 0) try self.put(&self.header, ", ");
                try self.put(&self.header, field.name);
                try self.put(&self.header, ": F32");
            }
            try self.put(&self.header, " }\n");
        }
        for (self.bindings.items) |binding| {
            const value = binding.value;
            if (!value.literal) continue;
            const type_name = switch (value.kind) {
                .f32_value => "F32",
                .u32_value => "U32",
                .boolean => "Bool",
                else => continue,
            };
            if (!blotName(binding.name)) return self.fail(self.peek(), "asset_identifier", "WGSL constant is not a Blot identifier");
            if (!std.math.isFinite(value.n)) return self.fail(self.peek(), "asset_number", "WGSL constant must fit finite F32");
            try self.put(&self.body, "const ");
            try self.put(&self.body, binding.name);
            try self.put(&self.body, ": ");
            try self.put(&self.body, type_name);
            try self.put(&self.body, " = ");
            if (value.kind == .boolean) {
                if (value.n != 0) {
                    try self.put(&self.body, "#True");
                } else try self.put(&self.body, "#False");
            } else if (value.kind == .u32_value) {
                var buffer: [32]u8 = undefined;
                try self.put(&self.body, std.mem.print(&buffer, "{d}", .{@as(u32, @intFromFloat(value.n))}) catch unreachable);
            } else try self.float(value.n);
            try self.put(&self.body, "\n");
        }
        if (self.header.items.len > limit - self.body.items.len) return self.fail(self.peek(), "asset_limit", "Generated asset module exceeds 16 MiB");
    }
    fn resolve(self: *Reader, original: []const u8) []const u8 {
        var name_text = original;
        for (0..128) |_| {
            if (self.aliases.get(name_text)) |target| {
                name_text = target;
            } else return name_text;
        }
        return "";
    }
    fn float(self: *Reader, number: f64) Error!void {
        const magnitude = @abs(number);
        const negative = std.math.signbit(number);
        if (negative) try self.put(&self.body, "(-");
        var buffer: [400]u8 = undefined;
        var mode: std.fmt.float.Mode = .decimal;
        if (magnitude >= 1e21 or (magnitude != 0 and magnitude < 1e-6)) mode = .scientific;
        const text = std.fmt.float.render(&buffer, magnitude, .{ .mode = mode }) catch unreachable;
        if (std.mem.findScalar(u8, text, 'e')) |exponent| {
            try self.put(&self.body, text[0 .. exponent + 1]);
            if (text[exponent + 1] != '-') try self.put(&self.body, "+");
            try self.put(&self.body, text[exponent + 1 ..]);
        } else {
            try self.put(&self.body, text);
            if (std.mem.findScalar(u8, text, '.') == null) try self.put(&self.body, ".0");
        }
        if (negative) try self.put(&self.body, ")");
    }
    fn expression(self: *Reader, minimum: u8, depth: usize) Error!Value {
        try self.budget(depth);
        var left = try self.prefix(depth + 1);
        while (true) {
            const op = self.operator();
            if (op.precedence == 0 or op.precedence < minimum) break;
            self.at += op.count;
            const right = try self.expression(op.precedence + 1, depth + 1);
            left = try self.binaryValue(op.text, left, right, depth + 1);
        }
        return left;
    }
    const Op = struct { text: []const u8 = "", precedence: u8 = 0, count: usize = 1 };
    fn operator(self: *Reader) Op {
        const text = self.peek().text;
        if ((self.is("<") or self.is(">")) and self.at + 1 < self.tokens.items.len) {
            const next = self.tokens.items[self.at + 1];
            if (std.mem.eql(u8, next.text, text) and next.start == self.peek().end) {
                if (self.is("<")) return .{ .text = "<<", .precedence = 8, .count = 2 };
                return .{ .text = ">>", .precedence = 8, .count = 2 };
            }
            if (std.mem.eql(u8, next.text, "=")) {
                if (self.is("<")) return .{ .text = "<=", .precedence = 7, .count = 2 };
                return .{ .text = ">=", .precedence = 7, .count = 2 };
            }
        }
        for ([_][]const u8{ "||", "&&", "|", "^", "&", "==", "!=", "<", ">", "+", "-", "*", "/", "%" }, [_]u8{ 1, 2, 3, 4, 5, 6, 6, 7, 7, 9, 9, 10, 10, 10 }) |candidate, precedence| {
            if (std.mem.eql(u8, text, candidate)) return .{ .text = text, .precedence = precedence };
        }
        return .{};
    }
    fn prefix(self: *Reader, depth: usize) Error!Value {
        try self.budget(depth);
        const token = self.peek();
        var value: Value = .{};
        if (self.take("-") or self.take("+") or self.take("!") or self.take("~") or self.take("&") or self.take("*")) {
            const operand = try self.prefix(depth + 1);
            value = try self.unaryValue(token.text, operand, depth + 1);
        } else if (self.take("(")) {
            value = try self.expression(0, depth + 1);
            try self.expect(")");
        } else if (token.number) {
            self.at += 1;
            value = try self.literal(token);
        } else {
            const name_token = try self.name();
            var spelling = name_token.text;
            if (std.mem.eql(u8, spelling, "true")) {
                value = .{ .kind = .boolean, .n = 1 };
            } else if (std.mem.eql(u8, spelling, "false")) {
                value = .{ .kind = .boolean };
            } else {
                if (self.binding_index.get(spelling)) |index| value = self.bindings.items[index].value;
            }
            // Only constructors admit template parameters. Comparisons after an
            // ordinary identifier stay in the Pratt parser.
            var element_type: []const u8 = "";
            if (constructor(spelling) and self.take("<")) {
                element_type = try self.typeName(depth + 1);
                while (self.take(",")) _ = try self.expression(8, depth + 1);
                try self.expect(">");
            }
            if (self.take("(")) {
                var args: std.ArrayList(Value) = .empty;
                if (!self.take(")")) {
                    while (true) {
                        try args.append(self.a, try self.expression(0, depth + 1));
                        if (self.take(")")) break;
                        try self.expect(",");
                        if (self.take(")")) break;
                    }
                }
                spelling = self.resolve(spelling);
                value = try self.call(spelling, element_type, args.items);
            }
        }
        while (true) {
            if (self.take("[")) {
                const index = try self.expression(0, depth + 1);
                try self.expect("]");
                if (std.math.isFinite(index.n) and index.n >= 0 and index.n < @as(f64, @floatFromInt(value.elements.len)) and index.n == @trunc(index.n)) {
                    value = value.elements[@intFromFloat(index.n)];
                } else value = .{};
            } else if (self.take(".")) {
                const field = try self.name();
                value = try self.swizzle(value, field.text);
            } else break;
        }
        return value;
    }
    fn literal(self: *Reader, token: Token) Error!Value {
        var text = token.text;
        var kind: Kind = .x32;
        if (text.len == 0) return self.syntax();
        const last = text[text.len - 1];
        const hex = std.mem.startsWith(u8, text, "0x");
        const floating_hex = hex and std.mem.findAny(u8, text, ".pP") != null;
        if (last == 'u' or last == 'i' or ((!hex or floating_hex) and (last == 'f' or last == 'h'))) {
            text = text[0 .. text.len - 1];
            kind = switch (last) {
                'u' => .u32_value,
                'i' => .i32_value,
                'f' => .f32_value,
                'h' => .f16_value,
                else => unreachable,
            };
        } else if ((!hex and std.mem.findAny(u8, text, ".eE") != null) or floating_hex) kind = .f32_value;
        var number: f64 = 0;
        if (floating_hex) {
            // The pinned reflector evaluates hexadecimal floating tokens with
            // JavaScript parseFloat, yielding zero. Preserve its asset ABI.
            _ = std.fmt.parseFloat(f64, text) catch return self.fail(token, "asset_wgsl", "Invalid WGSL number");
        } else if (hex) {
            const integer = std.fmt.parseInt(u64, text[2..], 16) catch return self.fail(token, "asset_wgsl", "Invalid WGSL number");
            number = @floatFromInt(integer);
        } else {
            number = std.fmt.parseFloat(f64, text) catch return self.fail(token, "asset_wgsl", "Invalid WGSL number");
        }
        return scalar(kind, number);
    }
    fn swizzle(self: *Reader, value: Value, text: []const u8) Error!Value {
        if (text.len == 0 or text.len > 4 or value.elements.len == 0) return .{};
        const elements = try self.a.alloc(Value, text.len);
        for (text, elements) |byte, *element| {
            var index: usize = 99;
            if (std.mem.findScalar(u8, "xyzw", byte)) |found| index = found;
            if (std.mem.findScalar(u8, "rgba", byte)) |found| index = found;
            if (index >= value.elements.len) return .{};
            element.* = value.elements[index];
        }
        if (elements.len == 1) return elements[0];
        return .{ .elements = elements };
    }
    fn unaryValue(self: *Reader, op: []const u8, value: Value, depth: usize) Error!Value {
        try self.budget(depth);
        if (value.elements.len == 0) return unary(op, value);
        const elements = try self.a.alloc(Value, value.elements.len);
        for (value.elements, elements) |element, *result| result.* = try self.unaryValue(op, element, depth + 1);
        return .{ .elements = elements };
    }
    fn binaryValue(self: *Reader, op: []const u8, left: Value, right: Value, depth: usize) Error!Value {
        try self.budget(depth);
        if (left.elements.len == 0 and right.elements.len == 0) return binary(op, left, right);
        const count = @max(left.elements.len, right.elements.len);
        if ((left.elements.len != 0 and left.elements.len != count) or (right.elements.len != 0 and right.elements.len != count)) return .{};
        const elements = try self.a.alloc(Value, count);
        for (elements, 0..) |*element, index| {
            var a = left;
            var b = right;
            if (left.elements.len != 0) a = left.elements[index];
            if (right.elements.len != 0) b = right.elements[index];
            element.* = try self.binaryValue(op, a, b, depth + 1);
        }
        return .{ .elements = elements };
    }
    fn byteSize(self: *Reader, value: Value, depth: usize) Error!usize {
        try self.budget(depth);
        if (value.elements.len == 0) {
            if (value.kind == .f16_value) return 2;
            return 4;
        }
        var bytes: usize = 0;
        for (value.elements) |element| bytes = std.math.add(usize, bytes, try self.byteSize(element, depth + 1)) catch return self.fail(self.peek(), "asset_limit", "WGSL reflected size exceeds the structural budget");
        return bytes;
    }
    fn call(self: *Reader, name_text: []const u8, element_type: []const u8, args: []const Value) Error!Value {
        self.call_depth += 1;
        defer self.call_depth -= 1;
        try self.budget(self.call_depth);
        if (std.mem.eql(u8, name_text, "bitcast") and args.len == 1) {
            const kind = scalarKind(element_type);
            if (args[0].kind == .unknown) return .{};
            var representation = bits(args[0].n);
            if (args[0].kind == .f32_value) representation = @bitCast(@as(f32, @floatCast(args[0].n)));
            var value = scalar(kind, @floatFromInt(representation));
            if (kind == .f32_value) value = scalar(kind, @as(f32, @bitCast(representation)));
            // A direct bitcast stays a bitcastExpr in wgsl_reflect. It can still
            // be consumed by a surrounding foldable expression or scalar cast.
            value.literal = false;
            return value;
        }
        if ((std.mem.eql(u8, name_text, "all") or std.mem.eql(u8, name_text, "any")) and args.len == 1 and args[0].elements.len != 0) {
            var truth = std.mem.eql(u8, name_text, "all");
            for (args[0].elements) |element| {
                if (element.kind == .unknown) return .{};
                if (std.mem.eql(u8, name_text, "all")) {
                    truth = truth and element.n != 0;
                } else truth = truth or element.n != 0;
            }
            return scalar(.boolean, @floatFromInt(@intFromBool(truth)));
        }
        if (std.mem.eql(u8, name_text, "arrayLength") and args.len == 1 and args[0].elements.len != 0) return scalar(.u32_value, @floatFromInt(try self.byteSize(args[0], 0)));
        if ((std.mem.eql(u8, name_text, "dot") or std.mem.eql(u8, name_text, "length") or std.mem.eql(u8, name_text, "distance")) and args.len >= 1 and args.len <= 2 and args[0].elements.len != 0) {
            const first = args[0].elements;
            const dot = std.mem.eql(u8, name_text, "dot");
            const distance = std.mem.eql(u8, name_text, "distance");
            if ((dot or distance) and (args.len != 2 or args[1].elements.len != first.len)) return .{};
            var sum: f64 = 0;
            for (first, 0..) |element, index| {
                if (element.kind == .unknown) return .{};
                var x = element.n;
                var y = x;
                if (dot or distance) {
                    const other = args[1].elements[index];
                    if (other.kind == .unknown) return .{};
                    if (distance) {
                        x -= other.n;
                        y = x;
                    } else y = other.n;
                }
                sum += x * y;
            }
            if (!dot) sum = @sqrt(sum);
            return scalar(first[0].kind, sum);
        }
        // Arithmetic builtins act independently on vector lanes. Constructors
        // and reducers above preserve their distinct aggregate behavior.
        if (!constructor(name_text) and args.len <= 4) {
            var lanes: usize = 0;
            for (args) |arg| lanes = @max(lanes, arg.elements.len);
            if (lanes != 0) {
                const elements = try self.a.alloc(Value, lanes);
                for (elements, 0..) |*element, index| {
                    var lane_args: [4]Value = undefined;
                    for (args, 0..) |arg, arg_index| {
                        if (arg.elements.len == 0) {
                            lane_args[arg_index] = arg;
                        } else if (arg.elements.len == lanes) {
                            lane_args[arg_index] = arg.elements[index];
                        } else return .{};
                    }
                    element.* = try self.call(name_text, element_type, lane_args[0..args.len]);
                }
                return .{ .elements = elements };
            }
        }
        const kind = scalarKind(name_text);
        if (kind != .unknown) {
            if (args.len == 0) return scalar(kind, 0);
            if (args.len != 1 or args[0].kind == .unknown) return .{};
            return scalar(kind, args[0].n);
        }
        if (std.mem.eql(u8, name_text, "array")) return .{ .elements = try self.a.dupe(Value, args) };
        if (std.mem.startsWith(u8, name_text, "vec") or std.mem.startsWith(u8, name_text, "mat")) {
            var elements: std.ArrayList(Value) = .empty;
            var lane_kind = scalarKind(element_type);
            if (std.mem.endsWith(u8, name_text, "f")) lane_kind = .f32_value;
            if (std.mem.endsWith(u8, name_text, "u")) lane_kind = .u32_value;
            if (std.mem.endsWith(u8, name_text, "i")) lane_kind = .i32_value;
            if (std.mem.endsWith(u8, name_text, "h")) lane_kind = .f16_value;
            for (args) |arg| {
                if (arg.elements.len != 0) {
                    for (arg.elements) |element| {
                        try self.budget(0);
                        try elements.append(self.a, castLane(lane_kind, element));
                    }
                } else try elements.append(self.a, castLane(lane_kind, arg));
            }
            if (std.mem.startsWith(u8, name_text, "vec") and name_text.len >= 4 and std.ascii.isDigit(name_text[3])) {
                const lanes: usize = name_text[3] - '0';
                if (elements.items.len == 0) {
                    for (0..lanes) |_| try elements.append(self.a, scalar(lane_kind, 0));
                } else if (elements.items.len == 1) {
                    const first = elements.items[0];
                    for (1..lanes) |_| try elements.append(self.a, first);
                }
            }
            return .{ .elements = elements.items };
        }
        if (std.mem.eql(u8, name_text, "select") and args.len == 3) {
            if (args[2].kind == .unknown) return .{};
            if (args[2].n != 0) return args[1];
            return args[0];
        }
        if (self.constant_mode) {
            for ([_][]const u8{ "cross", "determinant", "dot4U8Packed", "dot4I8Packed", "faceForward", "frexp", "modf", "normalize", "reflect", "refract", "transpose", "pack4x8snorm", "pack4x8unorm", "pack4xI8", "pack4xU8", "pack2x16snorm", "pack2x16unorm", "pack2x16float", "unpack4x8snorm", "unpack4x8unorm", "unpack4xI8", "unpack4xU8", "unpack2x16snorm", "unpack2x16unorm", "unpack2x16float" }) |unsupported| {
                if (std.mem.eql(u8, name_text, unsupported)) return self.fail(self.peek(), "asset_wgsl_evaluation", "WGSL constant uses an unsupported reflection builtin");
            }
        }
        for (args) |arg| if (arg.kind == .unknown) return .{};
        if (args.len == 0 or args.len > 4) return .{};
        const x = args[0].n;
        var y: f64 = 0;
        var z: f64 = 0;
        if (args.len > 1) y = args[1].n;
        if (args.len > 2) z = args[2].n;
        var n: f64 = 0;
        var output_kind = args[0].kind;
        if (std.mem.eql(u8, name_text, "abs") and args.len == 1) {
            n = @abs(x);
        } else if (std.mem.eql(u8, name_text, "acos") and args.len == 1) {
            n = std.math.acos(x);
        } else if (std.mem.eql(u8, name_text, "asin") and args.len == 1) {
            n = std.math.asin(x);
        } else if (std.mem.eql(u8, name_text, "atan") and args.len == 1) {
            n = std.math.atan(x);
        } else if (std.mem.eql(u8, name_text, "atan2") and args.len == 2) {
            n = std.math.atan2(x, y);
        } else if (std.mem.eql(u8, name_text, "acosh") and args.len == 1) {
            n = std.math.acosh(x);
        } else if (std.mem.eql(u8, name_text, "asinh") and args.len == 1) {
            n = std.math.asinh(x);
        } else if (std.mem.eql(u8, name_text, "atanh") and args.len == 1) {
            n = std.math.atanh(x);
        } else if (std.mem.eql(u8, name_text, "cosh") and args.len == 1) {
            // wgsl_reflect 1.6.0 dispatches Cosh to Math.cos.
            n = @cos(x);
        } else if (std.mem.eql(u8, name_text, "sinh") and args.len == 1) {
            n = std.math.sinh(x);
        } else if (std.mem.eql(u8, name_text, "tanh") and args.len == 1) {
            n = std.math.tanh(x);
        } else if (std.mem.eql(u8, name_text, "fma") and args.len == 3) {
            n = x * y + z;
        } else if (std.mem.eql(u8, name_text, "ldexp") and args.len == 2) {
            n = x * @exp2(y);
        } else if (std.mem.eql(u8, name_text, "quantizeToF16") and args.len == 1) {
            n = @as(f16, @floatCast(x));
        } else if (std.mem.eql(u8, name_text, "length") and args.len == 1) {
            n = @abs(x);
        } else if (std.mem.eql(u8, name_text, "distance") and args.len == 2) {
            n = @abs(x - y);
        } else if (std.mem.eql(u8, name_text, "dot") and args.len == 2) {
            n = x * y;
        } else if (std.mem.eql(u8, name_text, "extractBits") and args.len == 3) {
            // The pinned interpreter declines unsigned ExtractBits.
            if (args[0].kind != .i32_value) return .{};
            const offset = @min(bits(y), 32);
            const count = @min(bits(z), 32 - offset);
            var mask: u32 = 0;
            if (count == 32) {
                mask = std.math.maxInt(u32);
            } else mask = (@as(u32, 1) << @as(u5, @intCast(count))) - 1;
            var extracted: u32 = 0;
            if (offset != 32) extracted = (bits(x) >> @as(u5, @intCast(offset))) & mask;
            if (args[0].kind == .i32_value and count != 0 and count != 32 and extracted & (@as(u32, 1) << @as(u5, @intCast(count - 1))) != 0) extracted |= ~mask;
            n = @floatFromInt(extracted);
        } else if (std.mem.eql(u8, name_text, "insertBits") and args.len == 4) {
            const offset = @min(bits(z), 32);
            const count = @min(bits(args[3].n), 32 - offset);
            var mask: u32 = 0;
            if (count == 32) {
                mask = std.math.maxInt(u32);
            } else if (offset != 32) mask = ((@as(u32, 1) << @as(u5, @intCast(count))) - 1) << @as(u5, @intCast(offset));
            var inserted = bits(x);
            if (offset != 32) inserted = (inserted & ~mask) | ((bits(y) << @as(u5, @intCast(offset))) & mask);
            n = @floatFromInt(inserted);
        } else if (std.mem.eql(u8, name_text, "firstTrailingBit") and args.len == 1) {
            var index: u32 = std.math.maxInt(u32);
            if (bits(x) != 0) index = @ctz(bits(x));
            n = @floatFromInt(index);
        } else if (std.mem.eql(u8, name_text, "firstLeadingBit") and args.len == 1) {
            var integer = bits(x);
            if (args[0].kind == .i32_value and x < 0) integer = ~integer;
            var index: u32 = std.math.maxInt(u32);
            if (integer != 0) index = 31 - @as(u32, @clz(integer));
            n = @floatFromInt(index);
        } else if (std.mem.eql(u8, name_text, "ceil") and args.len == 1) {
            n = @ceil(x);
        } else if (std.mem.eql(u8, name_text, "floor") and args.len == 1) {
            n = @floor(x);
        } else if (std.mem.eql(u8, name_text, "round") and args.len == 1) {
            n = @floor(x + 0.5);
        } else if (std.mem.eql(u8, name_text, "trunc") and args.len == 1) {
            n = @trunc(x);
        } else if (std.mem.eql(u8, name_text, "fract") and args.len == 1) {
            n = x - @floor(x);
        } else if (std.mem.eql(u8, name_text, "sqrt") and args.len == 1) {
            n = @sqrt(x);
        } else if (std.mem.eql(u8, name_text, "inverseSqrt") and args.len == 1) {
            n = 1 / @sqrt(x);
        } else if (std.mem.eql(u8, name_text, "sin") and args.len == 1) {
            n = @sin(x);
        } else if (std.mem.eql(u8, name_text, "cos") and args.len == 1) {
            n = @cos(x);
        } else if (std.mem.eql(u8, name_text, "tan") and args.len == 1) {
            n = @tan(x);
        } else if (std.mem.eql(u8, name_text, "exp") and args.len == 1) {
            n = @exp(x);
        } else if (std.mem.eql(u8, name_text, "exp2") and args.len == 1) {
            n = @exp2(x);
        } else if (std.mem.eql(u8, name_text, "log") and args.len == 1) {
            n = @log(x);
        } else if (std.mem.eql(u8, name_text, "log2") and args.len == 1) {
            n = @log2(x);
        } else if (std.mem.eql(u8, name_text, "pow") and args.len == 2) {
            n = std.math.pow(f64, x, y);
        } else if (std.mem.eql(u8, name_text, "min") and args.len == 2) {
            n = @min(x, y);
        } else if (std.mem.eql(u8, name_text, "max") and args.len == 2) {
            n = @max(x, y);
        } else if (std.mem.eql(u8, name_text, "clamp") and args.len == 3) {
            n = @min(@max(x, y), z);
        } else if (std.mem.eql(u8, name_text, "saturate") and args.len == 1) {
            n = @min(@max(x, 0), 1);
        } else if (std.mem.eql(u8, name_text, "mix") and args.len == 3) {
            n = x * (1 - z) + y * z;
        } else if (std.mem.eql(u8, name_text, "step") and args.len == 2) {
            if (y >= x) n = 1;
        } else if (std.mem.eql(u8, name_text, "smoothstep") and args.len == 3) {
            const t = @min(@max((z - x) / (y - x), 0), 1);
            n = t * t * (3 - 2 * t);
        } else if (std.mem.eql(u8, name_text, "sign") and args.len == 1) {
            if (x > 0) n = 1;
            if (x < 0) n = -1;
        } else if (std.mem.eql(u8, name_text, "radians") and args.len == 1) {
            n = x * (std.math.pi / 180.0);
        } else if (std.mem.eql(u8, name_text, "degrees") and args.len == 1) {
            n = x * (180.0 / std.math.pi);
        } else if (std.mem.eql(u8, name_text, "all") or std.mem.eql(u8, name_text, "any")) {
            n = x;
            output_kind = .boolean;
        } else if (std.mem.eql(u8, name_text, "countOneBits") and args.len == 1) {
            n = @floatFromInt(@popCount(bits(x)));
        } else if (std.mem.eql(u8, name_text, "countLeadingZeros") and args.len == 1) {
            n = @floatFromInt(@clz(bits(x)));
        } else if (std.mem.eql(u8, name_text, "countTrailingZeros") and args.len == 1) {
            n = @floatFromInt(@ctz(bits(x)));
        } else if (std.mem.eql(u8, name_text, "reverseBits") and args.len == 1) {
            n = @floatFromInt(@bitReverse(bits(x)));
        } else return .{};
        return scalar(output_kind, n);
    }
};

fn identifierStart(byte: u8) bool {
    return std.ascii.isAlphabetic(byte) or byte == '_';
}
fn identifierContinue(byte: u8) bool {
    return identifierStart(byte) or std.ascii.isDigit(byte);
}
fn blotName(text: []const u8) bool {
    if (text.len == 0 or std.mem.eql(u8, text, "_") or !(std.ascii.isLower(text[0]) or text[0] == '_')) return false;
    var words = std.mem.tokenizeScalar(u8, "const let type data effect is fn do use return yield break for ever in case of if then else as import infix infixl infixr self where", ' ');
    while (words.next()) |word| if (std.mem.eql(u8, word, text)) return false;
    for (text) |byte| if (!identifierContinue(byte)) return false;
    return true;
}
fn constructor(text: []const u8) bool {
    return std.mem.eql(u8, text, "array") or std.mem.eql(u8, text, "bitcast") or std.mem.startsWith(u8, text, "vec") or std.mem.startsWith(u8, text, "mat");
}
fn scalarKind(text: []const u8) Kind {
    if (std.mem.eql(u8, text, "f32")) return .f32_value;
    if (std.mem.eql(u8, text, "u32")) return .u32_value;
    if (std.mem.eql(u8, text, "i32")) return .i32_value;
    if (std.mem.eql(u8, text, "bool")) return .boolean;
    if (std.mem.eql(u8, text, "f16")) return .f16_value;
    return .unknown;
}
fn bits(n: f64) u32 {
    if (!std.math.isFinite(n)) return 0;
    const wrapped = @mod(@trunc(n), 4294967296.0);
    return @intFromFloat(wrapped);
}
fn scalar(kind: Kind, n: f64) Value {
    var number = n;
    switch (kind) {
        .f32_value => number = @as(f32, @floatCast(n)),
        .f16_value => number = @as(f16, @floatCast(n)),
        .u32_value => number = @floatFromInt(bits(n)),
        .x32 => {
            number = @floatFromInt(bits(n));
            if (n < 0) number = @floatFromInt(@as(i32, @bitCast(bits(n))));
        },
        .i32_value => number = @floatFromInt(@as(i32, @bitCast(bits(n)))),
        .boolean => {
            number = 0;
            if (n != 0) number = 1;
        },
        .unknown => {},
    }
    return .{ .kind = kind, .n = number };
}
fn castLane(kind: Kind, value: Value) Value {
    if (kind == .unknown or value.kind == .unknown) return value;
    return scalar(kind, value.n);
}
fn unary(op: []const u8, value: Value) Value {
    if (value.kind == .unknown) return .{};
    if (std.mem.eql(u8, op, "-")) return scalar(value.kind, -value.n);
    if (std.mem.eql(u8, op, "+")) return value;
    if (std.mem.eql(u8, op, "!")) return scalar(.boolean, @floatFromInt(@intFromBool(value.n == 0)));
    if (std.mem.eql(u8, op, "~")) {
        var kind = value.kind;
        if (kind == .x32) kind = .i32_value;
        return scalar(kind, @floatFromInt(~bits(value.n)));
    }
    return .{};
}
fn promoted(left: Kind, right: Kind) Kind {
    if (left == .f32_value or right == .f32_value) return .f32_value;
    if (left == .f16_value or right == .f16_value) return .f16_value;
    if (left == .u32_value or right == .u32_value) return .u32_value;
    if (left == .i32_value or right == .i32_value) return .i32_value;
    return left;
}
fn binary(op: []const u8, left: Value, right: Value) Value {
    if (left.kind == .unknown or right.kind == .unknown) return .{};
    var kind = promoted(left.kind, right.kind);
    const x = left.n;
    const y = right.n;
    var n: f64 = 0;
    if (std.mem.eql(u8, op, "+")) {
        n = x + y;
    } else if (std.mem.eql(u8, op, "-")) {
        n = x - y;
    } else if (std.mem.eql(u8, op, "*")) {
        n = x * y;
    } else if (std.mem.eql(u8, op, "/")) {
        n = x / y;
    } else if (std.mem.eql(u8, op, "%")) {
        n = @rem(x, y);
    } else if (std.mem.eql(u8, op, "&")) {
        n = @floatFromInt(bits(x) & bits(y));
    } else if (std.mem.eql(u8, op, "|")) {
        n = @floatFromInt(bits(x) | bits(y));
    } else if (std.mem.eql(u8, op, "^")) {
        n = @floatFromInt(bits(x) ^ bits(y));
    } else if (std.mem.eql(u8, op, "<<")) {
        n = @floatFromInt(bits(x) << @as(u5, @truncate(bits(y))));
    } else if (std.mem.eql(u8, op, ">>")) {
        if (kind == .i32_value) {
            n = @floatFromInt(@as(i32, @bitCast(bits(x))) >> @as(u5, @truncate(bits(y))));
        } else n = @floatFromInt(bits(x) >> @as(u5, @truncate(bits(y))));
    } else {
        var truth = false;
        if (std.mem.eql(u8, op, "==")) {
            truth = x == y;
        } else if (std.mem.eql(u8, op, "!=")) {
            truth = x != y;
        } else if (std.mem.eql(u8, op, "<")) {
            truth = x < y;
        } else if (std.mem.eql(u8, op, ">")) {
            truth = x > y;
        } else if (std.mem.eql(u8, op, "<=")) {
            truth = x <= y;
        } else if (std.mem.eql(u8, op, ">=")) {
            truth = x >= y;
        } else if (std.mem.eql(u8, op, "&&")) {
            truth = x != 0 and y != 0;
        } else if (std.mem.eql(u8, op, "||")) {
            truth = x != 0 or y != 0;
        } else return .{};
        return scalar(.boolean, @floatFromInt(@intFromBool(truth)));
    }
    if (kind == .x32 and n < 0) kind = .i32_value;
    return scalar(kind, n);
}

fn expectSource(allocator: Allocator, input: []const u8, expected: []const u8) !void {
    var result = try generate(allocator, input);
    defer deinit(allocator, &result);
    switch (result) {
        .source => |source| try std.testing.expectEqualStrings(expected, source),
        .issue => return error.UnexpectedIssue,
    }
}
test "WGSL reflection folds scalar constants and resolves Parameters aliases" {
    try expectSource(std.testing.allocator, "alias Scalar = f32; struct Parameters { amount: Scalar, time: f32, } const integer: u32 = 2; const count = 1u + 2u; const amount = clamp(2.0, 0.0, 1.0); const origin = -4.0; const enabled = true && !false; const ignored = vec3f(1., 2., 3.); const lane = ignored.y;", "type Parameters is data = #Parameters { amount: F32, time: F32 }\nconst count: U32 = 3\nconst amount: F32 = 1.0\nconst origin: F32 = (-4.0)\nconst enabled: Bool = #True\nconst lane: F32 = 2.0\n");
}
test "WGSL syntax validates bodies and rejects malformed reflected declarations" {
    const inputs = [_][]const u8{ "struct Parameters { a: vec2f, }", "struct Parameters { a:f32,b:f32,c:f32,d:f32,e:f32 }", "@vertex fn main( -> {", "fn main() { let x = ; }", "/* unclosed", "const broken=1.0+;" };
    for (inputs) |input| {
        var result = try generate(std.testing.allocator, input);
        defer deinit(std.testing.allocator, &result);
        try std.testing.expect(result == .issue);
        try std.testing.expect(result.issue.start <= result.issue.end);
        try std.testing.expect(result.issue.end <= input.len);
    }
    try expectSource(std.testing.allocator, "@fragment fn main(@location(0) uv: vec2f) -> @location(0) vec4f { var n = 0u; for (var i = 0u; i < 4u; i++) { n += i; } if (n > 0u) { return vec4f(uv, f32(n), 1.0); } else { return vec4f(0.0); } }", "");
}
test "WGSL generated ownership survives every allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, expectSource, .{ "struct Parameters { x:f32 } const x = sqrt(4.0);", "type Parameters is data = #Parameters { x: F32 }\nconst x: F32 = 2.0\n" });
}

test "WGSL scalar and vector evaluation preserves the pinned reflector ABI" {
    try expectSource(std.testing.allocator, "const signed = f32(-2); const vector = (vec2f(1.) + vec2f(2.)).x; const dot_product = dot(vec2f(1.,2.),vec2f(3.,4.)); const direct = bitcast<f32>(1065353216u); const folded = f32(bitcast<f32>(1065353216u)); const hex = 0xffu; const hexadecimal_float = 0x1.fp2; const bytes = arrayLength(array<u32,2>(1u,2u)); const unsigned_extract = extractBits(255u,2u,3u); const hyperbolic = cosh(1.0);", "const signed: F32 = (-2.0)\nconst vector: F32 = 3.0\nconst dot_product: F32 = 11.0\nconst folded: F32 = 1.0\nconst hex: U32 = 255\nconst hexadecimal_float: F32 = 0.0\nconst bytes: U32 = 8\nconst hyperbolic: F32 = 0.5403022766113281\n");
}

test "WGSL aliases comments attributes and structured statements remain syntax" {
    try expectSource(std.testing.allocator, "/* outer /* inner */ */ alias Scalar=f32; struct Parameters { @align(16) gain: Scalar } const size=2u; @group(0) @binding(0) var<uniform> table: array<vec4f,size+2u>; fn work() { var i=0u; loop { i+=1u; if (i>=2u) { break; } continuing { break if i==3u; } } switch i { case 0u,1u: { return; } default: { discard; } } }", "type Parameters is data = #Parameters { gain: F32 }\nconst size: U32 = 2\n");
    try expectSource(std.testing.allocator, "struct Parameters {} const n = 2; const n = 3u;", "type Parameters is data = #Parameters {  }\nconst n: U32 = 3\n");
}

fn expectIssue(allocator: Allocator, input: []const u8, code: []const u8) !void {
    var result = try generate(allocator, input);
    defer deinit(allocator, &result);
    try std.testing.expect(result == .issue);
    try std.testing.expectEqualStrings(code, result.issue.code);
    try std.testing.expect(result.issue.start <= result.issue.end);
    try std.testing.expect(result.issue.end <= input.len);
}

test "WGSL limits and invalid generated identifiers reject with owned diagnostics" {
    try expectIssue(std.testing.allocator, "struct Parameters { where:f32 }", "asset_identifier");
    try expectIssue(std.testing.allocator, "const _ = 1u;", "asset_identifier");
    try expectIssue(std.testing.allocator, "const n = 1.0 / 0.0;", "asset_number");
    try expectIssue(std.testing.allocator, "const n = pack2x16float(vec2f(1.0));", "asset_wgsl_evaluation");
    var input: Text = .empty;
    defer input.deinit(std.testing.allocator);
    try input.appendSlice(std.testing.allocator, "const n=");
    for (0..200) |_| try input.append(std.testing.allocator, '(');
    try input.appendSlice(std.testing.allocator, "1.0");
    for (0..200) |_| try input.append(std.testing.allocator, ')');
    try input.append(std.testing.allocator, ';');
    try expectIssue(std.testing.allocator, input.items, "asset_limit");
}

test "WGSL rejected ownership survives every allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, expectIssue, .{ "struct Parameters { x:u32 }", "asset_wgsl_parameters" });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, expectIssue, .{ "const n = pack2x16float(vec2f(1.0));", "asset_wgsl_evaluation" });
}

test "WGSL shared constant graphs cannot multiply reflection work without bound" {
    var input: Text = .empty;
    defer input.deinit(std.testing.allocator);
    try input.appendSlice(std.testing.allocator, "const n0 = array(1u);\n");
    for (1..24) |index| {
        var buffer: [100]u8 = undefined;
        const line = try std.mem.print(&buffer, "const n{d} = array(n{d},n{d});\n", .{ index, index - 1, index - 1 });
        try input.appendSlice(std.testing.allocator, line);
    }
    try input.appendSlice(std.testing.allocator, "const size = arrayLength(n23);");
    try expectIssue(std.testing.allocator, input.items, "asset_limit");
}
