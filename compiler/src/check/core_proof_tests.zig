const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const terms = @import("numeric_proof_terms.zig");

const source =
    \\const at: (values: Array U32) -> (index: U32) -> (@proof.Index values index) -> U32 = func values => return func index => return func proof => return @array.get values index
    \\const inspect = func (values: Array U32) => return func (index: U32) => return do:
    \\  let valid = @proof.index values index
    \\  let impossible = @proof.lt 1 0
    \\  let repeated = @proof.index values index
    \\  break at values index repeated
;
fn lower(allocator: std.mem.Allocator) !core.Module {
    return lowerSource(allocator, source);
}
fn lowerSource(allocator: std.mem.Allocator, input: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, input);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, input, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    var checked = try checker.checkModuleWithOptions(allocator, &tree, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    for (checked.diagnostics) |diagnostic| std.debug.print("proof fixture: {s}\n", .{@tagName(diagnostic.code)});
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &names, &checked);
    errdefer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}
fn ownedGuards(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator);
    defer module.deinit(allocator);
    var guards: usize = 0;
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .proof_guard) continue;
        try std.testing.expectEqual(@import("types.zig").Tag.erased_proof, module.types.node(node.ty).tag);
        try std.testing.expect(node.a < id and node.b < id);
        if (guards == 1) {
            try std.testing.expectEqual(@backingInt(terms.Relation.lt), node.c);
            try std.testing.expectEqual(@as(u32, 1), module.node(node.a).a);
            try std.testing.expectEqual(@as(u32, 0), module.node(node.b).a);
        } else {
            try std.testing.expectEqual(@backingInt(terms.Relation.index), node.c);
            try std.testing.expectEqual(core.Tag.reference, module.node(node.a).tag);
            try std.testing.expectEqual(core.Tag.reference, module.node(node.b).tag);
        }
        guards += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), guards);
}
test "numeric proof Core retains unused false and repeated ordered guards after source teardown through OOM" {
    try ownedGuards(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownedGuards, .{});
}

fn portableContracts(allocator: std.mem.Allocator) !void {
    var original = try lower(allocator);
    var copied = block: {
        defer original.deinit(allocator);
        break :block try @import("../reuse/dependency_closure.zig").copyCore(allocator, &original);
    };
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(0), .settings = @splat(0), .source = @splat(0), .dependencies = @splat(0) };
    const bytes = block: {
        defer copied.deinit(allocator);
        break :block try format.encode(allocator, key, copied);
    };
    defer allocator.free(bytes);
    var decoded = try format.decode(core.Module, allocator, bytes, key);
    defer decoded.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), decoded.proof_contracts.len);
    const contract = decoded.proof_contracts[0];
    try contract.header.signature().validate(allocator, .{});
    try std.testing.expectEqualSlices(u32, &.{ 0, 1 }, contract.header.value_slots);
    try std.testing.expectEqualSlices(u32, &.{2}, contract.header.proof_slots);
    const body = decoded.bodies[decoded.bindings[contract.binding].body_id];
    try std.testing.expectEqual(@as(u32, 3), body.parameters.len);
    try @import("frozen_core_validation.zig").validate(allocator, &decoded, .{});
}
test "numeric proof Core contracts own copied and portable operands after producer teardown through OOM" {
    try portableContracts(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, portableContracts, .{});
}

const universal_proof_source =
    \\const witness: forall [a] => (values: Array a) -> (index: U32) -> @proof.Index values index = func values => return func index => return @proof.index values index
    \\const at: forall [a] => (values: Array a) -> (index: U32) -> (@proof.Index values index) -> a = func values => return func index => return func proof => return @array.get values index
    \\entry const whole = func (index: U32) => return do:
    \\  let values = #[8, 13]
    \\  let proof = witness values index
    \\  break at values index proof
    \\entry const fraction = func (index: U32) => return do:
    \\  let values = #[1.25, 3.5]
    \\  let proof = witness values index
    \\  break at values index proof
;
fn universalProofAnnotations(allocator: std.mem.Allocator) !void {
    var module = try lowerSource(allocator, universal_proof_source);
    defer module.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    var dependent_arrays: usize = 0;
    for (module.bindings) |binding| {
        if (binding.kind != .parameter) continue;
        const ty = module.types.node(binding.ty);
        if (ty.tag != .array) continue;
        const element = module.types.node(ty.a);
        if (element.tag != .bound) continue;
        try std.testing.expectEqual(@as(u32, 0), element.a);
        try std.testing.expectEqual(@as(u32, 0), element.b);
        dependent_arrays += 1;
    }
    // Both annotation binders and both executable implementation binders
    // publish owned bound elements rather than temporary annotation rigids.
    try std.testing.expectEqual(@as(usize, 4), dependent_arrays);
    var copied = try @import("../reuse/dependency_closure.zig").copyCore(allocator, &module);
    defer copied.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &copied, .{});
    try std.testing.expectEqual(@as(usize, 2), copied.proof_contracts.len);
    try std.testing.expectEqualSlices(u32, &.{2}, copied.proof_contracts[1].header.proof_slots);
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(0), .settings = @splat(0), .source = @splat(0), .dependencies = @splat(0) };
    const bytes = try format.encode(allocator, key, copied);
    defer allocator.free(bytes);
    var decoded = try format.decode(core.Module, allocator, bytes, key);
    defer decoded.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &decoded, .{});
}
test "numeric proof universal dependent annotation slots own bound types through OOM" {
    try universalProofAnnotations(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, universalProofAnnotations, .{});
}

test "numeric proof universal slots reject forged guards storage and witness kinds" {
    const allocator = std.testing.allocator;
    var module = try lowerSource(allocator, universal_proof_source);
    defer module.deinit(allocator);
    const validate = @import("frozen_core_validation.zig").validate;
    var proof_type: @import("types.zig").Id = 0;
    for (module.nodes) |*node| {
        if (node.tag != .proof_guard) continue;
        proof_type = node.ty;
        const original = node.*;
        node.c = @backingInt(terms.Relation.lt);
        try std.testing.expectError(error.InvalidArtifact, validate(allocator, &module, .{}));
        node.* = original;
        node.a = original.b;
        node.b = original.a;
        try std.testing.expectError(error.InvalidArtifact, validate(allocator, &module, .{}));
        node.* = original;
        break;
    }
    try std.testing.expect(proof_type != 0);
    const slots = @constCast(module.proof_contracts[1].header.proof_slots);
    slots[0] = 0;
    try std.testing.expectError(error.InvalidArtifact, validate(allocator, &module, .{}));
    slots[0] = 2;
    for (module.types.nodes) |*ty| {
        if (ty.tag != .array) continue;
        const original = ty.a;
        ty.a = proof_type;
        try std.testing.expectError(error.InvalidArtifact, validate(allocator, &module, .{}));
        ty.a = original;
        break;
    }
    var remaining: usize = 65_536;
    var context: @import("package_contracts.zig").Context = .{ .types = &module.types, .remaining = &remaining, .witness = true };
    try context.initialize();
    try std.testing.expectError(error.InvalidArtifact, context.visit(proof_type));
    try validate(allocator, &module, .{});
}

test "numeric proof universal annotation slots do not replace executable rigid owners" {
    const allocator = std.testing.allocator;
    var tokens = try lexer.lex(allocator, universal_proof_source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, universal_proof_source, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    var checked = try checker.checkModuleWithOptions(allocator, &tree, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 2), checked.rank_implementations.len);
    checked.rank_implementations[0].scope = 0;
    try std.testing.expectError(error.CoreLimit, core.lower(allocator, &tree, &names, &checked));
}

fn importedUniversalProofAliases(allocator: std.mem.Allocator) !void {
    const library = universal_proof_source[0..std.mem.find(u8, universal_proof_source, "entry const whole").?];
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tokens = try lexer.lex(allocator, library);
    defer tokens.deinit(allocator);
    var tree = try parser.parse(allocator, library, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    var producer = try checker.checkModuleWithOptions(allocator, &tree, &names, &.{}, &.{}, 2, .{});
    defer producer.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), producer.diagnostics.len);
    const catalog: checker.ImportedCatalog = .{ .producer = &producer, .kind = .catalog, .index = 0, .origin = 0 };
    const imports = [_]checker.ImportedBinding{
        .{ .name = producer.bindings[1].name, .target = .{ .unit = 2, .binding = 1 }, .origin = 0, .interface = catalog.interface(1) },
        .{ .name = producer.bindings[2].name, .target = .{ .unit = 2, .binding = 2 }, .origin = 0, .interface = catalog.interface(2) },
    };
    const prefix =
        \\entry const run = func (index: U32) => return do:
        \\  let values = #[8, 13]
        \\  let other = #[8, 13]
        \\  let proof = witness values index
        \\  let alias = proof
    ;
    for ([_][]const u8{
        prefix ++ "\n  break at values index alias",
        prefix ++ "\n  break at other index alias",
        prefix ++ "\n  break at values (@u32.add index 1) alias",
    }, 0..) |consumer_source, revision| {
        var consumer_tokens = try lexer.lex(allocator, consumer_source);
        defer consumer_tokens.deinit(allocator);
        var consumer_tree = try parser.parse(allocator, consumer_source, consumer_tokens.tokens.items, &names);
        defer consumer_tree.deinit(allocator);
        try std.testing.expect(!consumer_tree.has_numeric_proofs);
        var consumer = try checker.checkModuleWithOptions(allocator, &consumer_tree, &names, &imports, &.{}, 1, .{});
        defer consumer.deinit(allocator);
        if (revision == 0) {
            try std.testing.expectEqual(@as(usize, 0), consumer.diagnostics.len);
            try std.testing.expect(consumer.types.has_proof_kinds);
            try std.testing.expectEqual(@as(usize, 1), consumer.proof_bodies.uses.len);
        } else {
            var rejected = false;
            for (consumer.diagnostics) |diagnostic| rejected = rejected or diagnostic.code == .proof_mismatch;
            try std.testing.expect(rejected);
        }
    }
}
test "numeric proof universal imported aliases retain exact operands without local proof syntax through OOM" {
    try importedUniversalProofAliases(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, importedUniversalProofAliases, .{});
}

test "numeric proof portable admission rejects coordinated result claims guard erasure and hidden feature markers" {
    const allocator = std.testing.allocator;
    var module = try lowerSource(allocator,
        \\const positive: (x: U32) -> @proof.U32Le 0 x = func x => return @proof.le 0 x
    );
    defer module.deinit(allocator);
    const validation = @import("frozen_core_validation.zig");
    try validation.validate(allocator, &module, .{});
    const original = module.proof_contracts[0].header.result.?;
    module.proof_contracts[0].header.result.?.relation = .eq;
    try module.proof_contracts[0].header.signature().validate(allocator, .{});
    try validation.validateBounds(&module, .{});
    try std.testing.expectError(error.InvalidArtifact, validation.validate(allocator, &module, .{}));
    module.proof_contracts[0].header.result = original;
    for (module.nodes) |*node| if (node.tag == .proof_guard) {
        const guard = node.*;
        node.* = .{ .tag = .constant, .ty = guard.ty };
        try validation.validateBounds(&module, .{});
        try std.testing.expectError(error.InvalidArtifact, validation.validate(allocator, &module, .{}));
        node.* = guard;
        break;
    };
    module.has_numeric_proofs = false;
    try std.testing.expectError(error.InvalidArtifact, validation.validateBounds(&module, .{}));
}

fn portableLengthProofs(allocator: std.mem.Allocator) !void {
    var module = try lowerSource(allocator,
        \\type Holder is data = $Holder { index: U32 }
        \\const unwrap = func (holder: Holder) => return case holder of
        \\  $Holder { index: i } => i
        \\const at: (values: Array U32) -> (index: U32) -> (@proof.U32Lt index (@array.length values)) -> U32 = func values => return func index => return func proof => return @array.get values index
        \\const inspect = func (values: Array U32) => return func (index: U32) => return do:
        \\  let count = @array.length values
        \\  let valid = @proof.lt index count
        \\  break at values index valid
    );
    defer module.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
}
test "numeric proof portable length recipes preserve their exact collection through aliases and OOM" {
    try portableLengthProofs(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, portableLengthProofs, .{});
}

fn portableWeakening(allocator: std.mem.Allocator) !void {
    var module = try lowerSource(allocator,
        \\const le: (x: U32) -> (y: U32) -> (@proof.U32Le x y) -> U32 = func x => return func y => return func proof => return x
        \\const index: (values: Array U32) -> (i: U32) -> (@proof.Index values i) -> U32 = func values => return func i => return func proof => return @array.get values i
        \\const inspect = func (values: Array U32) => return func (i: U32) => return do:
        \\  let proof = @proof.lt i (@array.length values)
        \\  let same = le i (@array.length values) proof
        \\  break index values i proof
        \\const result: (x: U32) -> (y: U32) -> @proof.U32Le x y = func x => return func y => return @proof.lt x y
    );
    defer module.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
}
test "numeric proof portable calls and results admit finite weakening and exact index length equivalence through OOM" {
    try portableWeakening(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, portableWeakening, .{});
}

fn checkPlan(allocator: std.mem.Allocator, input: []const u8, expected: bool, limits: terms.Limits) !void {
    var module = try lowerSource(allocator, input);
    defer module.deinit(allocator);
    var plan = try @import("numeric_proof_core.zig").analyze(allocator, &module, &.{}, limits);
    defer plan.deinit(allocator);
    var checks: usize = 0;
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .array_op or module.arrayOperation(@intCast(id)) != .get) continue;
        try std.testing.expectEqual(expected, plan.admits(@intCast(id)));
        checks += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), checks);
}
const guarded = "entry const run = func (values: Array U32) => return func (index: U32) => return if @u32.lt index (@array.length values) then @array.get values index else 0";
const guarded_helper =
    \\const within = func (index: U32) => return func (values: Array U32) => return @u32.lt index (@array.length values)
    \\entry const run = func (values: Array U32) => return func (index: U32) => return if within index values then @array.get values index else 0
;
fn helperCheckPlan(allocator: std.mem.Allocator) !void {
    try checkPlan(allocator, guarded_helper, true, .{});
}
test "numeric proof selected named comparison bodies preserve parameter order and exact collections through OOM" {
    try helperCheckPlan(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, helperCheckPlan, .{});
}
test "numeric proof selected comparisons decline changed operands reversed conditions and unproved helper bodies" {
    const allocator = std.testing.allocator;
    try checkPlan(allocator,
        \\const within = func (values: Array U32) => return func (index: U32) => return @u32.lt index (@array.length values)
        \\entry const run = func (values: Array U32) => return func (index: U32) => return if within values index then @array.get values (@u32.add index 1) else 0
    , false, .{});
    try checkPlan(allocator,
        \\const within = func (values: Array U32) => return func (index: U32) => return @u32.lt (@array.length values) index
        \\entry const run = func (values: Array U32) => return func (index: U32) => return if within values index then @array.get values index else 0
    , false, .{});
    try checkPlan(allocator,
        \\const within = func (values: Array U32) => return func (index: U32) => return @u32.lt (@u32.add index 1) (@array.length values)
        \\entry const run = func (values: Array U32) => return func (index: U32) => return if within values index then @array.get values index else 0
    , false, .{});
    try checkPlan(allocator, guarded_helper, false, .{ .visits = 2 });
}
fn booleanComparisonPlans(allocator: std.mem.Allocator) !void {
    const helpers =
        \\const both = func (left: Bool) => return func (right: Bool) => return left and right
        \\const either = func (left: Bool) => return func (right: Bool) => return left or right
        \\const inverted = func (left: Bool) => return func (right: Bool) => return if left then false else right
        \\const ignore = func (left: Bool) => return func (right: Bool) => return true
        \\
    ;
    try checkPlan(allocator, helpers ++ "entry const run = func (values: Array U32) => return func (index: U32) => return if both (@u32.lt index (@array.length values)) (@u32.eq index 0) then @array.get values index else 0", true, .{});
    try checkPlan(allocator, helpers ++ "entry const run = func (values: Array U32) => return func (index: U32) => return if both (@u32.eq index 0) (@u32.lt index (@array.length values)) then @array.get values index else 0", true, .{});
    try checkPlan(allocator, helpers ++ "entry const run = func (values: Array U32) => return func (index: U32) => return if either (@u32.lt (@array.length values) index) (@u32.eq index (@array.length values)) then 0 else @array.get values index", true, .{});
    try checkPlan(allocator, helpers ++ "entry const run = func (values: Array U32) => return func (index: U32) => return if inverted (@u32.lt (@array.length values) index) (@u32.lt index (@array.length values)) then @array.get values index else 0", true, .{});
    try checkPlan(allocator, helpers ++ "entry const run = func (values: Array U32) => return func (index: U32) => return if ignore (@u32.lt index (@array.length values)) (@u32.eq index 0) then @array.get values index else 0", false, .{});
    try checkPlan(allocator, helpers ++ "entry const run = func (values: Array U32) => return func (index: U32) => return if either (@u32.lt index (@array.length values)) (@u32.eq index 9) then @array.get values index else 0", false, .{});
}
test "numeric proof selected Boolean bodies establish only their actual Boolean edges through OOM" {
    try booleanComparisonPlans(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, booleanComparisonPlans, .{});
}
fn forwardedComparisonPlans(allocator: std.mem.Allocator) !void {
    const common =
        \\infixl 50 (<) = lt
        \\const lt = func left => return func right => return compare left right
        \\const within = func index => return func length => return lt index length
        \\const choose = func (left: Bool) => return func (right: Bool) => return left and right
        \\entry const run = func (values: Array U32) => return func (index: U32) => return if choose (within index (@array.length values)) (index < 2) then @array.get values index else 0
        \\
    ;
    try checkPlan(allocator, common ++ "const compare = func left => return func right => return @u32.lt left right", true, .{});
    try checkPlan(allocator, common ++ "const compare = func left => return func right => return @u32.lt right left", false, .{});
    try checkPlan(allocator, common ++ "const compare = func left => return func right => return true", false, .{});
    try checkPlan(allocator, common ++ "const compare = func left => return func right => return @u32.lt (@u32.add left 1) right", false, .{});
    try checkPlan(allocator, common ++ "const compare = func left => return func right => return @u32.lt left right", false, .{ .visits = 2 });
    try checkPlan(allocator, common ++ "const compare = func left => return func right => return @type.call \"lt\" left right\nconst U32.lt = func left => return func right => return @u32.lt left right", false, .{});
}
test "numeric proof selected comparison forwarding preserves exact arguments through OOM" {
    try forwardedComparisonPlans(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, forwardedComparisonPlans, .{});
}
const aliased_comparison =
    \\const within = func (index: U32) => return func (values: Array U32) => return do:
    \\  let copied = index
    \\  let selected = values
    \\  let length = @array.length selected
    \\  let valid = @u32.lt copied length
    \\  break valid
    \\entry const run = func (values: Array U32) => return func (index: U32) => return if within index values then @array.get values index else 0
;
fn localComparisonPlan(allocator: std.mem.Allocator) !void {
    try checkPlan(allocator, aliased_comparison, true, .{});
}
test "numeric proof selected comparison blocks retain exact local aliases through OOM" {
    try localComparisonPlan(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, localComparisonPlan, .{});
}
test "numeric proof selected comparison blocks retain checks after wrapping rebinding or unknown prefixes" {
    const allocator = std.testing.allocator;
    const caller = "\nentry const run = func (values: Array U32) => return func (index: U32) => return if within index values then @array.get values index else 0";
    try checkPlan(allocator,
        \\const within = func (index: U32) => return func (values: Array U32) => return do:
        \\  let copied = @u32.add index 1
        \\  break @u32.lt copied (@array.length values)
    ++ caller, false, .{});
    try checkPlan(allocator,
        \\const within = func (index: U32) => return func (values: Array U32) => return do:
        \\  index := 0
        \\  break @u32.lt index (@array.length values)
    ++ caller, false, .{});
    try checkPlan(allocator,
        \\const within = func (index: U32) => return func (values: Array U32) => return do:
        \\  let unknown = @u32.div 1 index
        \\  break @u32.lt index (@array.length values)
    ++ caller, false, .{});
    try checkPlan(allocator, aliased_comparison, false, .{ .visits = 2 });
}
fn ownedCheckPlan(allocator: std.mem.Allocator) !void {
    try checkPlan(allocator, guarded, true, .{});
    try checkPlan(allocator,
        \\entry const run = func (values: Array U32) => return func (index: U32) => return do:
        \\  let first = @proof.index values index
        \\  let repeated = @proof.index values index
        \\  break @array.get values index
    , true, .{});
}
test "numeric proof check plans own exact dominated facts and repeated guards through OOM" {
    try ownedCheckPlan(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownedCheckPlan, .{});
}
test "numeric proof check plans traverse ordinary callback bodies" {
    try checkPlan(std.testing.allocator,
        \\const force = func (value: Unit -> U32) => return value ()
        \\entry const run = func (values: Array U32) => return func (index: U32) => return force (func () => return if @u32.lt index (@array.length values) then @array.get values index else 0)
    , true, .{});
}
test "numeric proof check plans retain invalidated joins unrelated collections wrap and false edges" {
    const allocator = std.testing.allocator;
    try checkPlan(allocator, "entry const run = func (values: Array U32) => return func (index: U32) => return if @u32.lt index (@array.length values) then 0 else @array.get values index", false, .{});
    try checkPlan(allocator, "entry const run = func (values: Array U32) => return func (other: Array U32) => return func (index: U32) => return if @u32.lt index (@array.length values) then @array.get other index else 0", false, .{});
    try checkPlan(allocator,
        \\entry const run = func (values: Array U32) => return func (index: U32) => return do:
        \\  if @u32.lt index (@array.length values):
        \\    index := @u32.add self 1
        \\    break @array.get values index
        \\  break 0
    , false, .{});
    try checkPlan(allocator, "entry const run = func (flag: Bool) => return func (values: Array U32) => return func (index: U32) => return if (if flag then @u32.lt index (@array.length values) else @u32.eq 0 0) then @array.get values index else 0", false, .{});
    try checkPlan(allocator, guarded, false, .{ .visits = 8 });
    try checkPlan(allocator,
        \\type Maybe is data = $Some U32 | $None
        \\entry const run = func (values: Array U32) => return func (index: U32) => return do:
        \\  let $Some selected = $Some 1 else:
        \\    let valid = @proof.index values index
        \\    break 0
        \\  break @array.get values index
    , false, .{});
}
test "numeric proof check plans preserve range limits and only directed nonwrapping arithmetic" {
    const allocator = std.testing.allocator;
    try checkPlan(allocator,
        \\entry const run = func (values: Array U32) => return do:
        \\  let result = 0
        \\  for index in 0..@array.length values:
        \\    result := @array.get values index
        \\  break result
    , true, .{});
    try checkPlan(allocator,
        \\entry const run = func (values: Array U32) => return func (index: U32) => return do:
        \\  let bounded = @proof.index values index
        \\  let fits = @proof.sub_fits index 1
        \\  let previous = @u32.sub index 1
        \\  break @array.get values previous
    , true, .{});
    try checkPlan(allocator,
        \\entry const run = func (values: Array U32) => return func (index: U32) => return do:
        \\  let bounded = @proof.index values index
        \\  let previous = @u32.sub index 1
        \\  break @array.get values previous
    , false, .{});
}
test "numeric proof check plans refine false equality and short circuit edges without reevaluation" {
    const allocator = std.testing.allocator;
    try checkPlan(allocator,
        \\entry const run = func (values: Array U32) => return func (index: U32) => return do:
        \\  let length = @array.length values
        \\  if @u32.lt length index:
        \\    break 0
        \\  if @u32.eq index length:
        \\    break 0
        \\  break @array.get values index
    , true, .{});
    var module = try lowerSource(allocator, "entry const run = func (values: Array U32) => return func (index: U32) => return if (if @u32.lt index (@array.length values) then @u32.eq 0 0 else @u32.eq 0 1) then @array.get values index else 0");
    defer module.deinit(allocator);
    // Exercise the resolved short-circuit node directly. User-defined lazy
    // operators need separate admission of their selected implementation.
    for (module.nodes) |*node| if (node.tag == .if_value and module.node(node.a).tag == .scalar) {
        node.tag = .logical;
        node.op = .and_;
        node.c = 0;
        break;
    };
    var plan = try @import("numeric_proof_core.zig").analyze(allocator, &module, &.{}, .{});
    defer plan.deinit(allocator);
    for (module.nodes, 0..) |node, id| if (node.tag == .array_op and module.arrayOperation(@intCast(id)) == .get) try std.testing.expect(plan.admits(@intCast(id)));
}

test "numeric proof preserves exact collection identity through opaque reference adapters" {
    const allocator = std.testing.allocator;
    var module = try lowerSource(allocator,
        \\type Token is opaque = Array U32
        \\const make: Array U32 -> Token = func value => return $Token value
        \\const read: Token -> Array U32 = func ($Token value) => return value
        \\entry const exact = func () => return (read (make #[42]))[0]
        \\entry const checked = func (index: U32) => return @array.get (read (make #[42])) index
    );
    defer module.deinit(allocator);
    var plan = try @import("numeric_proof_core.zig").analyze(allocator, &module, &.{}, .{});
    defer plan.deinit(allocator);
    var admitted: usize = 0;
    var retained: usize = 0;
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .array_op or module.arrayOperation(@intCast(id)) != .get) continue;
        if (plan.admits(@intCast(id))) admitted += 1 else retained += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), admitted);
    try std.testing.expectEqual(@as(usize, 1), retained);
}

const list_runtime_inputs = [_][]const u8{
    \\entry const run = func (index: U32) => return @array.get #[8, 13] index
    ,
    \\entry const run = func (index: U32) => return do:
    \\  let values = #[8, 13]
    \\  if @u32.lt index (@array.length values):
    \\    break @array.get values index
    \\  break 0
    ,
    \\entry const run = func (index: U32) => return do:
    \\  let values = #[8, 13]
    \\  if @u32.lt index (@array.length values):
    \\    let changed = @array.set values index 21
    \\    break @array.get changed index
    \\  break 0
    ,
};
const selected_operand =
    \\const selected = func (unused: U32) => return func (index: U32) => return do:
    \\  let copied = index
    \\  break copied
    \\const forwarded = func (index: U32) => return selected 42 index
    \\const count = func (values: Array U32) => return do:
    \\  let copied = values
    \\  break @array.length copied
    \\entry const run = func (values: Array U32) => return func (index: U32) => return if @u32.lt index (count values) then @array.get values (forwarded index) else 0
;
fn expectOperandPlan(allocator: std.mem.Allocator, module: *const core.Module, expected: bool, limits: terms.Limits) !void {
    var plan = try @import("numeric_proof_core.zig").analyze(allocator, module, &.{}, limits);
    defer plan.deinit(allocator);
    var checks: usize = 0;
    for (module.nodes, 0..) |node, id| if (node.tag == .array_op and module.arrayOperation(@intCast(id)) == .get) {
        try std.testing.expectEqual(expected, plan.admits(@intCast(id)));
        checks += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), checks);
}
fn ownedSelectedOperand(allocator: std.mem.Allocator) !void {
    var original = try lowerSource(allocator, selected_operand);
    var copied = block: {
        defer original.deinit(allocator);
        break :block try @import("../reuse/dependency_closure.zig").copyCore(allocator, &original);
    };
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(0), .settings = @splat(0), .source = @splat(0), .dependencies = @splat(0) };
    const bytes = block: {
        defer copied.deinit(allocator);
        break :block try format.encode(allocator, key, copied);
    };
    defer allocator.free(bytes);
    var decoded = try format.decode(core.Module, allocator, bytes, key);
    defer decoded.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &decoded, .{});
    try expectOperandPlan(allocator, &decoded, true, .{});
}
test "numeric proof selected result operands own portable formal substitution and local aliases through OOM" {
    try ownedSelectedOperand(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownedSelectedOperand, .{});
}
test "numeric proof selected result operands decline forged owners substitutions and bounded recursion" {
    const allocator = std.testing.allocator;
    var module = try lowerSource(allocator, selected_operand);
    defer module.deinit(allocator);
    const body = for (module.bodies[1..]) |*candidate| {
        if (candidate.parameters.len == 2) break candidate;
    } else return error.MissingSelectedOperand;
    const owner = body.binding;
    body.binding = 0;
    try expectOperandPlan(allocator, &module, false, .{});
    body.binding = owner;
    const start = body.parameters.start;
    const parameter = module.parameters[start];
    module.parameters[start] = module.parameters[start + 1];
    try expectOperandPlan(allocator, &module, false, .{});
    module.parameters[start] = parameter;
    std.mem.swap(core.Parameter, &module.parameters[start], &module.parameters[start + 1]);
    try expectOperandPlan(allocator, &module, false, .{});
    std.mem.swap(core.Parameter, &module.parameters[start], &module.parameters[start + 1]);
    try expectOperandPlan(allocator, &module, true, .{});
    try expectOperandPlan(allocator, &module, false, .{ .visits = 2 });
    try expectOperandPlan(allocator, &module, false, .{ .terms = 1 });
    try checkPlan(allocator,
        \\const selected = func (index: U32) => return selected index
        \\entry const run = func (values: Array U32) => return func (index: U32) => return if @u32.lt index (@array.length values) then @array.get values (selected index) else 0
    , false, .{});
    try checkPlan(allocator,
        \\const selected = func (index: U32) => return @u32.add index 1
        \\entry const run = func (values: Array U32) => return func (index: U32) => return if @u32.lt index (@array.length values) then @array.get values (selected index) else 0
    , false, .{});
}
test "numeric proof selected conditional results preserve only identities common to both paths" {
    const allocator = std.testing.allocator;
    const caller = "\nentry const run = func (values: Array U32) => return func (index: U32) => return if @u32.lt index (@array.length values) then @array.get values (selected index) else 0";
    try checkPlan(allocator, "const selected = func (index: U32) => return if @u32.lt index 4 then index else index" ++ caller, true, .{});
    try checkPlan(allocator, "const selected = func (index: U32) => return if @u32.lt index 4 then index else @u32.add index 1" ++ caller, false, .{});
    try checkPlan(allocator, "const selected = func (index: U32) => return if @u32.lt index 4 then @u32.add index 1 else index" ++ caller, false, .{});
    try checkPlan(allocator, "const selected = func (index: U32) => return if @u32.lt index 4 then index else index" ++ caller, false, .{ .visits = 2 });
}

const prepared_associated_operand =
    \\type Probe is data = $Probe U32
    \\const Probe.choose = func (unused: Probe) => return func (index: U32) => return do:
    \\  let copied = index
    \\  break copied
    \\const Probe.within = func (unused: Probe) => return func (index: U32) => return @u32.lt index 2
    \\const lookup = func probe => return func (index: U32) => return do:
    \\  let values = #[8, 13]
    \\  if @type.call "within" probe index:
    \\    break @array.get values (@type.call "choose" probe index)
    \\  break 0
    \\entry const run = func (index: U32) => return lookup ($Probe 42) index
;
fn preparedSelections(module: *const core.Module, storage: []@import("numeric_proof_core.zig").Selected) ![]const @import("numeric_proof_core.zig").Selected {
    var count: usize = 0;
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .associated) continue;
        const target = for (module.associated) |member| {
            if (member.member == node.c) break member.target;
        } else return error.MissingSelectedMethod;
        try std.testing.expect(count < storage.len);
        storage[count] = .{ .node = @intCast(id), .target = target };
        count += 1;
    }
    return storage[0..count];
}
fn preparedOperandPlan(allocator: std.mem.Allocator, module: *const core.Module, selected: []const @import("numeric_proof_core.zig").Selected, expected: bool, limits: terms.Limits) !void {
    const body = for (module.bodies[1..]) |*candidate| {
        if (candidate.parameters.len != 2 or module.node(candidate.root).tag != .block) continue;
        const first = module.node(module.children(candidate.root)[0]);
        if (first.tag == .bind and module.node(first.b).tag == .array) break candidate;
    } else return error.MissingSelectedOperand;
    var plan = try @import("numeric_proof_core.zig").analyzePrepared(allocator, module, &.{}, body, selected, limits);
    defer plan.deinit(allocator);
    for (module.nodes, 0..) |node, id| if (node.tag == .array_op and module.arrayOperation(@intCast(id)) == .get) {
        try std.testing.expectEqual(expected, plan.admits(@intCast(id)));
    };
}
fn ownedPreparedOperand(allocator: std.mem.Allocator) !void {
    var original = try lowerSource(allocator, prepared_associated_operand);
    var module = block: {
        defer original.deinit(allocator);
        break :block try @import("../reuse/dependency_closure.zig").copyCore(allocator, &original);
    };
    defer module.deinit(allocator);
    var selected: [2]@import("numeric_proof_core.zig").Selected = undefined;
    const targets = try preparedSelections(&module, &selected);
    try std.testing.expectEqual(@as(usize, 2), targets.len);
    try expectOperandPlan(allocator, &module, false, .{});
    try preparedOperandPlan(allocator, &module, targets, true, .{});
    try preparedOperandPlan(allocator, &module, &.{}, false, .{});
    try preparedOperandPlan(allocator, &module, targets, false, .{ .visits = 2 });
    try preparedOperandPlan(allocator, &module, targets, false, .{ .terms = 1 });
}
test "numeric proof prepared selected targets own exact caller operands and body teardown through OOM" {
    try ownedPreparedOperand(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownedPreparedOperand, .{});
}
test "numeric proof prepared selected targets decline forged body owners and formal substitutions" {
    const allocator = std.testing.allocator;
    var module = try lowerSource(allocator, prepared_associated_operand);
    defer module.deinit(allocator);
    var selected: [2]@import("numeric_proof_core.zig").Selected = undefined;
    const targets = try preparedSelections(&module, &selected);
    const body = for (module.bodies[1..]) |*candidate| {
        if (candidate.parameters.len == 2 and module.node(candidate.root).tag == .block) break candidate;
    } else return error.MissingSelectedOperand;
    const owner = body.binding;
    body.binding = 0;
    try preparedOperandPlan(allocator, &module, targets, false, .{});
    body.binding = owner;
    const start = body.parameters.start;
    std.mem.swap(core.Parameter, &module.parameters[start], &module.parameters[start + 1]);
    try preparedOperandPlan(allocator, &module, targets, false, .{});
    std.mem.swap(core.Parameter, &module.parameters[start], &module.parameters[start + 1]);
    try preparedOperandPlan(allocator, &module, targets, true, .{});
}
const identity_operand_helpers =
    \\const identity = func (index: U32) => return do:
    \\  let zero = @u32.sub index index
    \\  let copied = @u32.add 0 index
    \\  break @u32.sub (@u32.add copied zero) zero
    \\const within = func (index: U32) => return func (values: Array U32) => return @u32.lt (identity index) (@u32.add (@array.length values) 0)
    \\entry const run = func (values: Array U32) => return func (index: U32) => return if within index values then @array.get values (identity index) else 0
;
fn ownedIdentityOperands(allocator: std.mem.Allocator) !void {
    var original = try lowerSource(allocator, identity_operand_helpers);
    var module = block: {
        defer original.deinit(allocator);
        break :block try @import("../reuse/dependency_closure.zig").copyCore(allocator, &original);
    };
    defer module.deinit(allocator);
    try expectOperandPlan(allocator, &module, true, .{});
    try expectOperandPlan(allocator, &module, false, .{ .visits = 2 });
    try expectOperandPlan(allocator, &module, false, .{ .terms = 1 });
}
test "numeric proof selected arithmetic identities preserve exact operands lengths and source teardown through OOM" {
    try ownedIdentityOperands(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownedIdentityOperands, .{});
}
test "numeric proof selected arithmetic identities decline forged primitives types and changed bodies" {
    const allocator = std.testing.allocator;
    const caller = "\nentry const run = func (values: Array U32) => return func (index: U32) => return if @u32.lt index (@array.length values) then @array.get values (identity index) else 0";
    const helper = "const identity = func (index: U32) => return @u32.add index 0";
    var module = try lowerSource(allocator, helper ++ caller);
    defer module.deinit(allocator);
    const scalar = for (module.nodes) |*node| {
        if (node.tag == .scalar and node.op == .add) break node;
    } else return error.MissingSelectedOperand;
    const original = scalar.*;
    try expectOperandPlan(allocator, &module, true, .{});
    scalar.c = 1;
    try expectOperandPlan(allocator, &module, false, .{});
    scalar.* = original;
    scalar.ty = @import("types.zig").f32_type;
    try expectOperandPlan(allocator, &module, false, .{});
    scalar.* = original;
    module.nodes[scalar.b].a = 1;
    try expectOperandPlan(allocator, &module, false, .{});
    module.nodes[scalar.b].a = 0;
    try expectOperandPlan(allocator, &module, true, .{});
    try checkPlan(allocator, "const identity = func (index: U32) => return @u32.sub 0 index" ++ caller, false, .{});
    try checkPlan(allocator, "const identity = func (index: U32) => return @u32.add index 1" ++ caller, false, .{});
    try checkPlan(allocator, "const identity = func (index: U32) => return @u32.sub index 1" ++ caller, false, .{});
}
const curried_associated_operand =
    \\type Probe is data = $Probe U32
    \\const Probe.choose = func (unused: Probe) => return do:
    \\  let copied = 0
    \\  break func (index: U32) => return @u32.add index copied
    \\const Probe.within = func (unused: Probe) => return do:
    \\  let limit = 2
    \\  break func (index: U32) => return @u32.lt index limit
    \\const lookup = func probe => return func (index: U32) => return do:
    \\  let values = #[8, 13]
    \\  if @type.call "within" probe index:
    \\    break @array.get values (@type.call "choose" probe index)
    \\  break 0
    \\entry const run = func (index: U32) => return lookup ($Probe 42) index
;
fn ownedCurriedOperand(allocator: std.mem.Allocator) !void {
    var original = try lowerSource(allocator, curried_associated_operand);
    var module = owned: {
        defer original.deinit(allocator);
        break :owned try @import("../reuse/dependency_closure.zig").copyCore(allocator, &original);
    };
    defer module.deinit(allocator);
    var storage: [2]@import("numeric_proof_core.zig").Selected = undefined;
    const selected = try preparedSelections(&module, &storage);
    try preparedOperandPlan(allocator, &module, selected, true, .{});
    try preparedOperandPlan(allocator, &module, &.{}, false, .{});
    try preparedOperandPlan(allocator, &module, selected, false, .{ .visits = 2 });
    try preparedOperandPlan(allocator, &module, selected, false, .{ .terms = 1 });
}
test "numeric proof prepared returned closures retain exact captures and bounded ownership through OOM" {
    try ownedCurriedOperand(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownedCurriedOperand, .{});
}
const bit_identity_helpers =
    \\const identity = func (index: U32) => return do:
    \\  let multiplied = @u32.mul index 1
    \\  let masked = @u32.bit_and 0xffffffff multiplied
    \\  let shifted = @u32.shl masked 32
    \\  let zero = @u32.bit_xor index index
    \\  break @u32.div (@u32.bit_or shifted zero) 1
    \\entry const run = func (index: U32) => return if @u32.lt index 2 then @array.get #[8, 13] (identity index) else 0
;
const remaining_associated_arguments =
    \\type Probe is data = $Probe U32
    \\const Probe.choose = func (unused: Probe) => return func (index: U32) => return func (last: Unit) => return index
    \\const lookup = func probe => return func (index: U32) => return do:
    \\  let values = #[8, 13]
    \\  if @u32.lt index 2:
    \\    break @array.get values ((@type.call "choose" probe index) ())
    \\  break 0
    \\entry const run = func (index: U32) => return lookup ($Probe 42) index
;
fn ownedRemainingArguments(allocator: std.mem.Allocator) !void {
    var original = try lowerSource(allocator, remaining_associated_arguments);
    var module = copied: {
        defer original.deinit(allocator);
        break :copied try @import("../reuse/dependency_closure.zig").copyCore(allocator, &original);
    };
    defer module.deinit(allocator);
    var storage: [1]@import("numeric_proof_core.zig").Selected = undefined;
    const selected = try preparedSelections(&module, &storage);
    try preparedOperandPlan(allocator, &module, selected, true, .{});
    try preparedOperandPlan(allocator, &module, &.{}, false, .{});
    try preparedOperandPlan(allocator, &module, selected, false, .{ .visits = 2 });
    try preparedOperandPlan(allocator, &module, selected, false, .{ .terms = 1 });
}
test "numeric proof remaining method arguments own exact plans and bounded fallback through OOM" {
    try ownedRemainingArguments(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownedRemainingArguments, .{});
}
const literal_associated_operand =
    \\type Probe is data = $Probe U32
    \\const Probe.choose = func (unused: Probe) => return func (index: U32) => return func (delta: U32) => return @u32.add index delta
    \\entry const run = func (index: U32) => return if @u32.lt index 2 then @array.get #[8, 13] ((@type.call "choose" ($Probe 42) index) 0) else 0
;
const nested_finite_selected =
    \\type Probe is data = $Probe U32
    \\const copy = func (value: U32) => return value
    \\const advance = func (value: U32) => return func (delta: U32) => return @u32.add (copy value) (copy delta)
    \\const forwarded = func (value: U32) => return advance (copy value) 0
    \\const Probe.choose = func (unused: Probe) => return do:
    \\  let copied = forwarded 0
    \\  break func (index: U32) => return func (delta: U32) => return advance (forwarded index) (advance copied delta)
    \\const lookup = func probe => return func (index: U32) => return do:
    \\  let values = #[8, 13]
    \\  if @u32.lt index 2:
    \\    break @array.get values ((@type.call "choose" probe index) 0)
    \\  break 0
    \\entry const run = func (index: U32) => return lookup ($Probe 42) index
;
fn ownedNestedFiniteSelected(allocator: std.mem.Allocator) !void {
    var original = try lowerSource(allocator, nested_finite_selected);
    var copied = block: {
        defer original.deinit(allocator);
        break :block try @import("../reuse/dependency_closure.zig").copyCore(allocator, &original);
    };
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(0), .settings = @splat(0), .source = @splat(0), .dependencies = @splat(0) };
    const bytes = block: {
        defer copied.deinit(allocator);
        break :block try format.encode(allocator, key, copied);
    };
    defer allocator.free(bytes);
    var module = try format.decode(core.Module, allocator, bytes, key);
    defer module.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    var storage: [1]@import("numeric_proof_core.zig").Selected = undefined;
    const selected = try preparedSelections(&module, &storage);
    try preparedOperandPlan(allocator, &module, selected, true, .{});
    try preparedOperandPlan(allocator, &module, &.{}, false, .{});
    try preparedOperandPlan(allocator, &module, selected, false, .{ .visits = 2 });
    try preparedOperandPlan(allocator, &module, selected, false, .{ .terms = 1 });
}
test "numeric finite nested helper and returned closure summaries own portable exact operands through OOM" {
    try ownedNestedFiniteSelected(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownedNestedFiniteSelected, .{});
}

fn finitePlanMeasurement(allocator: std.mem.Allocator, label: []const u8, input: []const u8, limits: terms.Limits, expected: bool, prepared: bool) !void {
    var module = try lowerSource(allocator, input);
    defer module.deinit(allocator);
    var tracked: @import("../memory.zig").TrackedAllocator = .{ .backing = allocator };
    const measured = tracked.allocator();
    var visits: usize = 0;
    {
        var plan: @import("numeric_proof_core.zig").Plan = undefined;
        if (prepared) {
            var storage: [1]@import("numeric_proof_core.zig").Selected = undefined;
            const selected = try preparedSelections(&module, &storage);
            const body = for (module.bodies[1..]) |*candidate| {
                if (candidate.parameters.len != 2 or module.node(candidate.root).tag != .block) continue;
                const first = module.node(module.children(candidate.root)[0]);
                if (first.tag == .bind and module.node(first.b).tag == .array) break candidate;
            } else return error.MissingSelectedOperand;
            plan = try @import("numeric_proof_core.zig").analyzePrepared(measured, &module, &.{}, body, selected, limits);
        } else plan = try @import("numeric_proof_core.zig").analyze(measured, &module, &.{}, limits);
        defer plan.deinit(measured);
        var accesses: usize = 0;
        for (module.nodes, 0..) |node, id| {
            if (node.tag != .array_op or module.arrayOperation(@intCast(id)) != .get) continue;
            try std.testing.expectEqual(expected, plan.admits(@intCast(id)));
            accesses += 1;
        }
        try std.testing.expect(plan.visits <= limits.visits);
        if (prepared) {
            try std.testing.expectEqual(1, accesses);
            try std.testing.expect(plan.visits != 0);
        } else {
            try std.testing.expectEqual(0, accesses);
            try std.testing.expectEqual(0, plan.visits);
            try std.testing.expectEqual(0, tracked.counts.allocations);
        }
        visits = plan.visits;
    }
    try std.testing.expectEqual(0, tracked.counts.live_bytes);
    std.debug.print("BLOT_NUMERIC_FINITE {{\"case\":\"{s}\",\"visits\":{d},\"requested_bytes\":{d},\"peak_bytes\":{d},\"allocations\":{d},\"live_bytes\":{d}}}\n", .{ label, visits, tracked.counts.allocated_bytes, tracked.counts.peak_bytes, tracked.counts.allocations, tracked.counts.live_bytes });
}
test "numeric finite work stays bounded and inactive no feature bodies allocate no proof storage" {
    const allocator = std.testing.allocator;
    try finitePlanMeasurement(allocator, "no_feature", "entry const run = func (index: U32) => return @u32.add index 1", .{}, false, false);
    try finitePlanMeasurement(allocator, "nested_selected", nested_finite_selected, .{}, true, true);
    const joined = try std.mem.replaceOwned(u8, allocator, nested_finite_selected, "advance (copy value) 0", "if @u32.lt value 3 then advance (copy value) 0 else advance (copy value) 0");
    defer allocator.free(joined);
    try finitePlanMeasurement(allocator, "joined_selected", joined, .{}, true, true);
    try finitePlanMeasurement(allocator, "optional_budget_2", nested_finite_selected, .{ .visits = 2 }, false, true);
    {
        var module = try lowerSource(allocator, guarded);
        defer module.deinit(allocator);
        var plan = try @import("numeric_proof_core.zig").analyze(allocator, &module, &.{}, .{ .visits = 2 });
        defer plan.deinit(allocator);
        try std.testing.expect(plan.visits != 0 and plan.visits <= 2);
        for (module.nodes, 0..) |node, id| if (node.tag == .array_op and module.arrayOperation(@intCast(id)) == .get) {
            try std.testing.expect(!plan.admits(@intCast(id)));
        };
        std.debug.print("BLOT_NUMERIC_FINITE {{\"case\":\"optional_module_budget_2\",\"visits\":{d}}}\n", .{plan.visits});
    }
    const kinds: [257]terms.Kind = @splat(.u32);
    var operands: [257]terms.Term = undefined;
    var requirements: [256]@import("numeric_proof_contracts.zig").Requirement = undefined;
    for (&operands, 0..) |*operand, index| operand.* = .{ .tag = .formal, .a = @intCast(index) };
    for (&requirements, 0..) |*requirement, index| requirement.* = .{ .before = @intCast(index + 2), .proposition = .{ .relation = .le, .left = @intCast(index + 1), .right = @intCast(index + 2) } };
    const contract: @import("numeric_proof_contracts.zig").Contract = .{ .values = &kinds, .operands = &operands, .requirements = &requirements };
    var tracked: @import("../memory.zig").TrackedAllocator = .{ .backing = allocator };
    const stats = try contract.validateMeasured(tracked.allocator(), .{});
    try std.testing.expect(stats.visits < 5000);
    try std.testing.expectEqual(0, tracked.counts.live_bytes);
    std.debug.print("BLOT_NUMERIC_FINITE {{\"case\":\"requirements_256\",\"visits\":{d},\"requested_bytes\":{d},\"peak_bytes\":{d},\"allocations\":{d},\"live_bytes\":{d}}}\n", .{ stats.visits, tracked.counts.allocated_bytes, tracked.counts.peak_bytes, tracked.counts.allocations, tracked.counts.live_bytes });
    var source_terms: terms.Store = .{};
    defer source_terms.deinit(allocator);
    const formal = try source_terms.intern(allocator, .{ .tag = .formal, .a = 0 });
    for (0..2048) |number| _ = try source_terms.intern(allocator, .{ .tag = .literal, .a = @intCast(number) });
    tracked.counts = .{};
    const measured = tracked.allocator();
    var target: terms.Store = .{};
    const actual = try target.intern(measured, .{ .tag = .version, .a = 7, .b = 2 });
    const proofs: [256]terms.Proposition = @splat(.{ .relation = .eq, .left = formal, .right = formal });
    const before = target.visits;
    const imported = try target.importMany(measured, source_terms.view(), &proofs, .{ .formals = &.{.u32} }, .{ .formals = &.{actual} });
    try std.testing.expectEqual(source_terms.terms.items.len + proofs.len * 3, target.visits - before);
    const visits = target.visits - before;
    measured.free(imported);
    target.deinit(measured);
    try std.testing.expectEqual(0, tracked.counts.live_bytes);
    std.debug.print("BLOT_NUMERIC_FINITE {{\"case\":\"shared_graph_256\",\"visits\":{d},\"requested_bytes\":{d},\"peak_bytes\":{d},\"allocations\":{d},\"live_bytes\":{d}}}\n", .{ visits, tracked.counts.allocated_bytes, tracked.counts.peak_bytes, tracked.counts.allocations, tracked.counts.live_bytes });
}

fn iteratorCarryOwners(allocator: std.mem.Allocator) !void {
    var module = try lowerSource(allocator,
        \\type Maybe a is data = $Some a | $Nothing
        \\type Counter is data = $Counter U32
        \\const Counter.iter = func (cursor: Counter) => return cursor
        \\const Counter.next = func ($Counter value) => return if @u32.lt value 4 then $Some (value, $Counter (@u32.add value 1)) else $Nothing
        \\const iterate = func (first: U32) => return do:
        \\  let result = 1
        \\  for value in $Counter first:
        \\    result := @u32.add self value
        \\  break result
        \\const bounded = func (value: U32) => return do:
        \\  let checked = @proof.lt value 10
        \\  break iterate value
    );
    defer module.deinit(allocator);
    try std.testing.expect(module.has_numeric_proofs);
    const validator = @import("numeric_proof_core.zig");
    var remaining: usize = 65_536;
    try validator.validate(allocator, &module, &.{}, &remaining);
    var mutations: usize = 0;
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .suite) continue;
        var carries = false;
        for (module.children(@intCast(id))) |child| {
            if (module.node(child).tag == .loop and module.loopCarries(child).len != 0) carries = true;
        }
        if (!carries) continue;
        // A lexical block retires its locals; a statement suite publishes its
        // actual loop outputs to the following statements in the same scope.
        module.nodes[id].tag = .block;
        defer module.nodes[id] = node;
        remaining = 65_536;
        validator.validate(allocator, &module, &.{}, &remaining) catch |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expectEqual(error.InvalidArtifact, err);
            mutations += 1;
            continue;
        };
        return error.TestUnexpectedResult;
    }
    try std.testing.expectEqual(@as(usize, 1), mutations);
}
test "numeric proof statement suites publish actual iterator carries while blocks retire them through OOM" {
    try iteratorCarryOwners(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, iteratorCarryOwners, .{});
}

fn patternFallbackOwners(allocator: std.mem.Allocator) !void {
    var module = try lowerSource(allocator,
        \\type Maybe a is data = $Some a | $Nothing
        \\const pick = func (input: Maybe U32) => return do:
        \\  let $Some value = input else:
        \\    break 3
        \\  let bounded = @proof.lt value 10
        \\  break value
    );
    defer module.deinit(allocator);
    const validator = @import("numeric_proof_core.zig");
    var remaining: usize = 65_536;
    try validator.validate(allocator, &module, &.{}, &remaining);
    var tested: usize = 0;
    for (module.nodes) |node| {
        if (node.tag != .pattern_bind or node.c == 0) continue;
        const pattern = module.pattern(node.a);
        try std.testing.expectEqual(core.PatternTag.constructor, pattern.tag);
        const success = module.pattern(pattern.b);
        try std.testing.expectEqual(core.PatternTag.bind, success.tag);
        var selected: core.Id = 0;
        for (module.nodes, 0..) |candidate, index| {
            if (candidate.tag == .reference and module.reference(@intCast(index)).binding == success.a) {
                selected = @intCast(index);
                break;
            }
        }
        try std.testing.expect(selected != 0);
        try std.testing.expectEqual(core.Tag.suite, module.node(node.c).tag);
        const fallback_return = module.children(node.c)[0];
        try std.testing.expectEqual(core.Tag.return_, module.node(fallback_return).tag);
        const original = module.node(fallback_return);
        const fallback = module.node(node.c);
        defer module.nodes[fallback_return] = original;
        defer module.nodes[node.c] = fallback;
        for (0..2) |mutation| {
            module.nodes[fallback_return] = original;
            module.nodes[node.c] = fallback;
            if (mutation == 0) {
                module.nodes[fallback_return].a = selected;
            } else {
                module.nodes[node.c] = .{ .tag = .constant, .ty = @import("types.zig").unit };
            }
            remaining = 65_536;
            if (validator.validate(allocator, &module, &.{}, &remaining)) |_| {
                return error.TestUnexpectedResult;
            } else |err| {
                if (err == error.OutOfMemory) return err;
                try std.testing.expectEqual(error.InvalidArtifact, err);
            }
        }
        tested += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), tested);
}
test "numeric proof pattern fallback owns only outer bindings and must exit through OOM" {
    try patternFallbackOwners(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, patternFallbackOwners, .{});
}

fn foreverFallbackOwners(allocator: std.mem.Allocator) !void {
    var module = try lowerSource(allocator,
        \\type Maybe a is data = $Some a | $Nothing
        \\const pick = func (input: Maybe U32) => return do:
        \\  let $Some value = input else:
        \\    for ever:
        \\      break 3
        \\  let bounded = @proof.lt value 10
        \\  break value
    );
    defer module.deinit(allocator);
    const validator = @import("numeric_proof_core.zig");
    var remaining: usize = 65_536;
    try validator.validate(allocator, &module, &.{}, &remaining);
    var tested: usize = 0;
    for (module.nodes, 0..) |node, index| {
        if (node.tag != .loop) continue;
        try std.testing.expectEqual(core.LoopKind.forever, module.loopInfo(@intCast(index)).kind);
        try std.testing.expect(!module.loopInfo(@intCast(index)).can_exit);
        const exit = module.children(module.loopInfo(@intCast(index)).body)[0];
        const original = module.node(exit);
        try std.testing.expectEqual(core.Tag.return_, original.tag);
        defer module.nodes[exit] = original;
        // A forged no-break flag cannot hide an actual break to this loop.
        module.nodes[exit] = .{ .tag = .break_, .ty = @import("types.zig").never, .a = @intCast(index) };
        remaining = 65_536;
        if (validator.validate(allocator, &module, &.{}, &remaining)) |_| {
            return error.TestUnexpectedResult;
        } else |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expectEqual(error.InvalidArtifact, err);
        }
        tested += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), tested);
}
test "numeric proof forever fallbacks reconstruct actual break owners through OOM" {
    try foreverFallbackOwners(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, foreverFallbackOwners, .{});
}
