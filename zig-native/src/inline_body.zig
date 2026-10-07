//! Bounded inlining of ordinary typed source bodies. Handlers and staging
//! stay separate jobs; small data operations and callback adapters can expose
//! their allocations and known call targets to backend optimization.
const core = @import("core.zig");
pub fn admits(m: *const core.Module, id: core.Id, expose_data: bool) bool {
    // Larger expansion needs a representation benefit: aggregate results in
    // loops or known callbacks. Other helpers stay tiny to avoid multiplying
    // code and refinement work throughout a large application. The caller also
    // bounds nesting and total emitted instructions.
    var budget: usize = if (expose_data) 64 else 4;
    return visit(m, id, &budget);
}
fn visit(m: *const core.Module, id: core.Id, budget: *usize) bool {
    if (id == 0) return true;
    if (budget.* == 0) return false;
    budget.* -= 1;
    const n = m.node(id);
    return switch (n.tag) {
        .constant, .reference, .panic, .constructor_function, .primitive_function, .break_ => true,
        .scalar, .associated, .apply, .logical => visit(m, n.a, budget) and visit(m, n.b, budget),
        .if_value, .if_stmt => visit(m, n.a, budget) and visit(m, n.b, budget) and visit(m, n.c, budget),
        .project, .return_ => visit(m, n.a, budget),
        .construct, .bind => visit(m, n.b, budget),
        .pattern_bind => visit(m, n.b, budget) and visit(m, n.c, budget),
        .match => blk: {
            for (m.matchInputs(id)) |input| if (!visit(m, input, budget)) break :blk false;
            for (m.matchArms(id)) |arm| if (!visit(m, arm.guard, budget) or !visit(m, arm.body, budget)) break :blk false;
            break :blk true;
        },
        .loop => blk: {
            const loop = m.loopInfo(id);
            break :blk visit(m, loop.first, budget) and visit(m, loop.end, budget) and visit(m, loop.body, budget);
        },
        .product, .record, .array, .array_op, .block, .suite => blk: {
            for (m.children(id)) |child| if (!visit(m, child, budget)) break :blk false;
            break :blk true;
        },
        .call => blk: {
            for (m.call(id).arguments) |child| if (!visit(m, child, budget)) break :blk false;
            break :blk true;
        },
        .closure => visit(m, m.closures[n.a].body, budget),
        else => false,
    };
}
