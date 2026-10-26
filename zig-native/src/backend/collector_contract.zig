//! Whole-module certificate for a deliberately bounded no-owning-fields case.
//! Final checked ownership roles are the authority. Unknown calls, incoming
//! references and reference-bearing allocations decline; observations never
//! substitute for proof. Administrative root/RC helpers retain their contracts.
const std = @import("std");
const w = @import("wasm.zig");
pub const Reason = enum { proven, unchecked_module, host_import, incoming_reference, public_arena, mutable_static, indirect_call, owning_allocation, unknown_runtime_helper, invalid_call, work_limit };
pub const Certificate = struct {
    version: u32 = 1,
    certified: bool = false,
    scope: []const u8 = "complete_module_arena",
    proof: []const u8 = "no_owning_user_heap_fields_v1",
    reason: Reason = .proven,
    function: ?u32 = null,
    instruction: ?u32 = null,
    covered_functions: usize = 0,
    assumption: []const u8 = "Call source exports through the ownership ABI; do not mutate raw memory, tables or runtime globals or invoke private helpers.",
};
fn helper(a: w.Arena, id: u32) bool {
    inline for (.{ "allocate_scalar", "retain", "release", "release_lease", "retire", "free", "store_word", "copy_words", "decrement", "recycle", "reset", "root_reserve", "root_pop", "root_open", "root_close", "root_enter", "root_leave", "root_store", "root_force", "root_authority", "cycle_safe", "cycle_collect", "mark_acyclic" }) |name| if (id == @field(a, name)) return true;
    return false;
}
pub fn analyze(module: *const w.Module, bodies: anytype) std.mem.Allocator.Error!Certificate {
    var result: Certificate = .{};
    if (module.public_arena) {
        result.reason = .public_arena;
        return result;
    }
    if (module.imports.items.len != 0 or module.host_references != null) {
        result.reason = .host_import;
        return result;
    }
    if (module.mutable_static) {
        result.reason = .mutable_static;
        return result;
    }
    // All emitted non-helper bodies are covered, including initialization,
    // persistent roots and every source export. A recursive direct component
    // needs no recursive proof: each member's body must pass the same rule.
    var remaining: usize = 4_000_000;
    for (module.functions.items, 0..) |*function, id| {
        if (module.runtimeHelper(@intCast(id))) continue;
        result.function = @intCast(id);
        if (function.entry) for (function.parameters, 0..) |_, parameter| {
            const role = function.parameterRole(parameter);
            if (role != .scalar) {
                result.reason = .incoming_reference;
                return result;
            }
        };
        result.covered_functions += 1;
        const instructions = if (bodies[id].body) |body| body.instructions.items else function.instructions.items;
        for (instructions, 0..) |inst, at| {
            result.instruction = @intCast(at);
            if (remaining == 0) {
                result.reason = .work_limit;
                return result;
            }
            remaining -= 1;
            if (inst.op == .call_indirect or inst.op == .call_import) {
                result.reason = .indirect_call;
                return result;
            }
            if (inst.op != .call) continue;
            if (inst.operand >= module.functions.items.len) {
                result.reason = .invalid_call;
                return result;
            }
            if (!module.runtimeHelper(inst.operand)) continue;
            if (module.arena) |arena| {
                if (inst.operand == arena.allocate_typed or inst.operand == arena.root_allocate) {
                    if (at != 0 and instructions[at - 1].op == .i32_const and instructions[at - 1].operand == 0) continue;
                    result.reason = .owning_allocation;
                    return result;
                }
                if (inst.operand == arena.allocate or inst.operand == arena.allocate_shaped or inst.operand == arena.root_allocate_shaped) {
                    result.reason = .owning_allocation;
                    return result;
                }
                if (helper(arena, inst.operand)) continue;
            }
            result.reason = .unknown_runtime_helper;
            return result;
        }
    }
    result.function = null;
    result.instruction = null;
    result.certified = true;
    return result;
}
