//! Bounded diagnostic rendering. Numeric identities remain in semantic tables;
//! presentation allocates only when an editor hole is present.
const std = @import("std");
const T = @import("types.zig");

pub fn append(engine: anytype, bytes: *std.ArrayList(u8), ty: T.Id) T.Error!void {
    var budget: usize = 256;
    try appendBounded(engine, bytes, ty, &budget);
}
pub fn appendBounded(engine: anytype, bytes: *std.ArrayList(u8), ty: T.Id, budget: *usize) T.Error!void {
    try render(engine, bytes, ty, 0, budget, false);
}
pub fn appendStable(engine: anytype, bytes: *std.ArrayList(u8), ty: T.Id) T.Error!void {
    var budget: usize = 256;
    try render(engine, bytes, ty, 0, &budget, true);
}
pub fn text(engine: anytype, bytes: *std.ArrayList(u8), value: []const u8) T.Error!void {
    const limit = 8192;
    if (bytes.items.len >= limit) return;
    const remaining = limit - bytes.items.len;
    if (value.len <= remaining) return bytes.appendSlice(engine.allocator, value);
    var count = remaining -| 3;
    // A symbol can contain UTF-8. Truncation must preserve valid diagnostic JSON.
    while (count != 0 and value[count] & 0xc0 == 0x80) count -= 1;
    try bytes.appendSlice(engine.allocator, value[0..count]);
    try bytes.appendSlice(engine.allocator, "..."[0..@min(remaining - count, 3)]);
}
fn number(engine: anytype, bytes: *std.ArrayList(u8), value: u32) T.Error!void {
    var buffer: [16]u8 = undefined;
    try text(engine, bytes, std.mem.print(&buffer, "{d}", .{value}) catch unreachable);
}
fn render(engine: anytype, bytes: *std.ArrayList(u8), ty: T.Id, depth: usize, budget: *usize, comptime stable: bool) T.Error!void {
    if (depth >= 32 or budget.* == 0) return text(engine, bytes, "...");
    budget.* -= 1;
    var root = engine.types.head(ty, 0);
    if (!stable) root = try engine.types.resolve(ty, 0);
    const node = engine.types.node(root);
    switch (node.tag) {
        .scoped => {
            try render(engine, bytes, node.a, depth + 1, budget, stable);
            try text(engine, bytes, " @scope");
            try number(engine, bytes, node.b);
            try text(engine, bytes, ":");
            try number(engine, bytes, node.c);
        },
        .absent => try text(engine, bytes, "?"),
        .unit => try text(engine, bytes, "Unit"),
        .boolean => try text(engine, bytes, "Bool"),
        .u32 => try text(engine, bytes, "U32"),
        .f32 => try text(engine, bytes, "F32"),
        .never => try text(engine, bytes, "Never"),
        .variable => {
            try text(engine, bytes, "?t");
            try number(engine, bytes, node.a);
        },
        .array, .list, .cursor, .demand => {
            try text(engine, bytes, switch (node.tag) {
                .array => "Array ",
                .list => "List ",
                .cursor => "Cursor ",
                else => "~",
            });
            try render(engine, bytes, node.a, depth + 1, budget, stable);
        },
        .function => {
            try text(engine, bytes, "(");
            try render(engine, bytes, node.a, depth + 1, budget, stable);
            try text(engine, bytes, " -> ");
            try render(engine, bytes, node.b, depth + 1, budget, stable);
            var row_id = node.c;
            if (!stable) row_id = try engine.types.resolveEffects(node.c, 0);
            const row = engine.types.effects.node(row_id);
            if (row.labels.len != 0 or row.tail != .closed) {
                try text(engine, bytes, " ! {");
                for (0..row.labels.len) |index| {
                    if (budget.* == 0) {
                        try text(engine, bytes, "...");
                        break;
                    }
                    budget.* -= 1;
                    const label = engine.types.effects.list(row.labels)[index];
                    if (index != 0) try text(engine, bytes, ", ");
                    if (label == T.foreign_operation) {
                        try text(engine, bytes, "Foreign");
                        continue;
                    }
                    const operation = engine.types.operation(label);
                    var name: u32 = 0;
                    for (engine.effect_templates.items) |template| if (std.meta.eql(template.identity, operation.identity)) {
                        name = template.name;
                        break;
                    };
                    try text(engine, bytes, if (name == 0) "operation" else engine.pool.get(name));
                    if (operation.instance.decl != 0) {
                        try text(engine, bytes, " @scope");
                        try number(engine, bytes, operation.instance.unit);
                        try text(engine, bytes, ":");
                        try number(engine, bytes, operation.instance.decl);
                    }
                    for (0..operation.arguments.len) |argument_index| {
                        if (budget.* == 0) {
                            try text(engine, bytes, " ...");
                            break;
                        }
                        const argument = engine.types.list(operation.arguments)[argument_index];
                        try text(engine, bytes, " ");
                        try render(engine, bytes, argument, depth + 1, budget, stable);
                    }
                }
                if (row.tail != .closed) try text(engine, bytes, " | ?e");
                try text(engine, bytes, "}");
            }
            try text(engine, bytes, ")");
        },
        .product => {
            try text(engine, bytes, "(");
            for (0..node.b) |index| {
                if (budget.* == 0) {
                    try text(engine, bytes, ", ...");
                    break;
                }
                const item = engine.types.list(.{ .start = node.a, .len = node.b })[index];
                if (index != 0) try text(engine, bytes, ", ");
                try render(engine, bytes, item, depth + 1, budget, stable);
            }
            if (node.b == 1) try text(engine, bytes, ",");
            try text(engine, bytes, ")");
        },
        .record => {
            try text(engine, bytes, "{ ");
            for (0..node.b) |index| {
                if (budget.* == 0) {
                    try text(engine, bytes, ", ...");
                    break;
                }
                if (index != 0) try text(engine, bytes, ", ");
                const field = engine.types.recordField(node, index);
                try text(engine, bytes, engine.pool.get(field.name));
                try text(engine, bytes, ": ");
                try render(engine, bytes, field.ty, depth + 1, budget, stable);
            }
            try text(engine, bytes, " }");
        },
        .nominal, .type_constructor => {
            var name: u32 = 0;
            for (engine.nominals.items) |nominal| if (nominal.identity.unit == node.a and nominal.identity.decl == node.b) {
                name = nominal.name;
                break;
            };
            try text(engine, bytes, if (name == 0) "Type" else engine.pool.get(name));
            if (node.tag == .nominal) for (0..engine.types.nominalArguments(node).len) |index| {
                if (budget.* == 0) {
                    try text(engine, bytes, " ...");
                    break;
                }
                const argument = engine.types.nominalArguments(node)[index];
                try text(engine, bytes, " ");
                try render(engine, bytes, argument, depth + 1, budget, stable);
            };
        },
        .projection => {
            var name: u32 = 0;
            for (engine.contracts.items) |contract| if (contract.identity.unit == node.a and contract.identity.decl == node.b) {
                name = contract.name;
                break;
            };
            try text(engine, bytes, engine.pool.get(name));
            try text(engine, bytes, ".");
            try text(engine, bytes, engine.pool.get(engine.types.projectionMember(node)));
            for (0..engine.types.nominalArguments(node).len) |index| {
                const argument = engine.types.nominalArguments(node)[index];
                try text(engine, bytes, " ");
                try render(engine, bytes, argument, depth + 1, budget, stable);
            }
        },
        .resolver, .provider, .state_provider => try text(engine, bytes, @tagName(node.tag)),
    }
}
