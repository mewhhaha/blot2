//! Package publication reuses explicit lexical slots and the owned Core graph.
//! Callers first validate table bounds and cycles; no producer claim is trusted.
const core = @import("core.zig");
const T = @import("types.zig");
const PI = @import("../reuse/principal_interface.zig");
const C = @import("package_contracts.zig");
const Error = error{InvalidArtifact};
fn require(ok: bool) Error!void {
    if (!ok) return error.InvalidArtifact;
}
pub fn present(nodes: []const T.Node) bool {
    for (nodes) |node| if (node.tag == .existential) return true;
    return false;
}
fn scheme(types: *const core.Types, value: T.Scheme) Error!void {
    if (value.variables.len != 0) {
        const owner = types.node(value.root);
        if (owner.tag == .forall) {
            try require(owner.c == value.variables.len);
            try require(@import("std").mem.eql(T.Id, types.list(value.variables), types.list(.{ .start = owner.b, .len = owner.c })));
        } else for (types.list(value.variables)) |variable| try require(types.node(variable).tag == .variable);
    }
    if (comptime @hasField(T.Scheme, "generative")) try require(value.generative.len == 0);
}
fn closedViews(context: *C.Context, certificates: T.List) Error!void {
    context.pure_rows = @splat(false);
    context.closed_rows = @splat(false);
    for (context.types.effects.rows, 0..) |row, id| {
        try require(context.remaining.* != 0);
        context.remaining.* -= 1;
        if (row.tail != .variable) continue;
        for (context.types.list(certificates)) |variable| {
            try require(context.remaining.* != 0);
            context.remaining.* -= 1;
            if (row.tail.variable != variable) continue;
            context.closed_rows[id] = true;
            if (row.labels.len == 0) context.pure_rows[id] = true;
        }
    }
}
pub fn interface(owner: *const PI.Interface) Error!void {
    try require(owner.has_rank_contracts);
    var remaining: usize = 65_536;
    const view = @import("associated_admission.zig").typesView(&owner.graph);
    var context: C.Context = .{ .types = &view, .remaining = &remaining, .source_obligations = owner.obligations };
    try context.initialize();
    for (owner.bindings, 0..) |binding, slot| {
        if (binding.ty == 0) continue;
        // The enclosing generic admission reconstructs erased method recipes
        // against their exact declared contract and scheme before this pass.
        var template = false;
        for (owner.member_templates) |member| {
            try require(remaining != 0);
            remaining -= 1;
            if (member.binding == slot) template = true;
        }
        if (template) continue;
        try closedViews(&context, binding.scheme.closed_rows);
        try context.generic(binding.scheme);
        try context.visit(binding.ty);
        try scheme(&view, binding.scheme);
        try @import("scheme_predicates.zig").scope(&context, owner.obligations[binding.scheme.obligations.start..][0..binding.scheme.obligations.len]);
        var proof: C.Principal = .{ .left = &view, .right = &view, .remaining = &remaining, .views = &context, .left_rows = binding.scheme.closed_rows };
        try proof.validate(binding.ty, binding.scheme.root);
    }
    for (owner.nominals) |nominal| {
        // Generic declarations use the enclosing catalog scope validator.
        if (nominal.alias != 0 and nominal.variables.len == 0 and nominal.alias_rows.len == 0) try context.visit(nominal.alias);
    }
}
pub fn publicCore(owner: *const PI.Interface, module: *const core.Module) Error!void {
    try require(owner.has_rank_contracts and module.has_rank_contracts);
    const view = @import("associated_admission.zig").typesView(&owner.graph);
    var remaining: usize = 65_536;
    var context: C.Context = .{ .types = &module.types, .remaining = &remaining, .obligations = module.obligations };
    try context.initialize();
    var proof: C.Principal = .{ .left = &view, .right = &module.types, .remaining = &remaining, .views = &context };
    for (owner.bindings, 0..) |binding, id| {
        if (binding.ty == 0) continue;
        try require(id < module.bindings.len);
        var template = false;
        for (owner.member_templates) |member| {
            try require(remaining != 0);
            remaining -= 1;
            if (member.binding != id) continue;
            for (module.member_templates) |candidate| {
                try require(remaining != 0);
                remaining -= 1;
                if (candidate.binding == id and candidate.name == member.name and @import("std").meta.eql(candidate.contract, member.contract)) template = true;
            }
            try require(template);
        }
        if (template) {
            try require(binding.scheme.variables.len == module.bindings[id].scheme.variables.len);
            var method: C.Principal = .{ .left = &view, .right = &module.types, .remaining = &remaining };
            try method.substituted(binding.scheme.variables, module.types.list(module.bindings[id].scheme.variables), binding.ty, module.bindings[id].ty);
            try method.substituted(binding.scheme.variables, module.types.list(module.bindings[id].scheme.variables), binding.scheme.root, module.bindings[id].scheme.root);
            continue;
        }
        const producer = module.bindings[id];
        try require(binding.scheme.closed_rows.len == producer.scheme.closed_rows.len);
        if (producer.scheme.closed_rows.len != 0) {
            if (producer.kind == .external) {
                // Imported slots copy the producer's principal; executable
                // references are checked against that exact sibling body by
                // package_core, rather than inventing a local body here.
                try require(producer.target.unit != 0 and producer.target.unit != module.unit and producer.target.binding != 0);
            } else {
                const body = module.body(@intCast(id)) orelse return error.InvalidArtifact;
                for (module.types.list(producer.scheme.closed_rows)) |variable| {
                    try require(remaining != 0);
                    remaining -= 1;
                    try require(@import("std").mem.findScalar(u32, module.types.list(body.closed_rows), variable) != null);
                }
            }
        }
        try closedViews(&context, producer.scheme.closed_rows);
        try context.generic(producer.scheme);
        proof.left_rows = binding.scheme.closed_rows;
        try proof.schemeGoals(binding.scheme, producer.scheme, owner.obligations[binding.scheme.obligations.start..][0..binding.scheme.obligations.len], module.obligations[producer.scheme.obligations.start..][0..producer.scheme.obligations.len]);
        if (view.node(binding.scheme.root).tag != .forall and (binding.scheme.variables.len != 0 or binding.scheme.row_variables.len != 0)) {
            try require(binding.scheme.variables.len == producer.scheme.variables.len and binding.scheme.row_variables.len == producer.scheme.row_variables.len);
            try proof.instantiateScheme(binding.scheme, producer.ty);
            try proof.instantiateScheme(binding.scheme, producer.scheme.root);
        } else {
            try proof.validate(binding.ty, producer.ty);
            try proof.validate(binding.scheme.root, producer.scheme.root);
        }
    }
}
