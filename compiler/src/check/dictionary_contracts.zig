//! Reconstruct stored package dictionaries from admitted selected proofs and
//! exact lexical openings. Call after immutable bounds and proof admission.
const core = @import("core.zig");
const T = @import("types.zig");
const PI = @import("../reuse/principal_interface.zig");
const contracts = @import("package_contracts.zig");
const Error = error{InvalidArtifact};

fn require(ok: bool) Error!void {
    if (!ok) return error.InvalidArtifact;
}
fn step(scopes: *contracts.Context) Error!void {
    try require(scopes.remaining.* != 0);
    scopes.remaining.* -= 1;
}
fn contract(module: *const core.Module, goal: T.Obligation) Error!core.Contract {
    try require(goal.kind == .contract);
    for (module.contracts) |candidate| {
        if (candidate.identity.unit == goal.identity.unit and candidate.identity.decl == goal.identity.decl) return candidate;
    }
    return error.InvalidArtifact;
}
fn sameTarget(module: *const core.Module, reference: core.BindingRef, target: PI.ExternalTarget) bool {
    var left = reference.unit;
    if (left == 0) left = module.unit;
    var right = target.unit;
    if (right == 0) right = module.unit;
    return left == right and reference.binding == target.binding;
}
/// A declaration may assume only its own already admitted implementation
/// head. Caller evidence and unrelated declarations confer no such authority.
fn implementationGiven(module: *const core.Module, body: core.BindingId, goal: core.Obligation, scopes: *contracts.Context) Error!bool {
    if (body == 0) return false;
    const arguments = module.types.node(goal.ty);
    if (arguments.tag != .product) return false;
    for (module.implementations) |implementation| {
        try step(scopes);
        if (implementation.contract.unit != goal.identity.unit or implementation.contract.decl != goal.identity.decl or implementation.head.len != arguments.b) continue;
        var owns = false;
        for (module.implementation_members[implementation.members.start..][0..implementation.members.len]) |member| {
            try step(scopes);
            if (member.kind == .value and sameTarget(module, .{ .unit = 0, .binding = body }, member.target)) owns = true;
        }
        if (!owns) continue;
        var matches = true;
        for (module.types.list(implementation.head), module.types.list(.{ .start = arguments.a, .len = arguments.b })) |expected, actual| {
            var comparison: contracts.Principal = .{ .left = &module.types, .right = &module.types, .remaining = scopes.remaining, .views = scopes };
            comparison.validate(expected, actual) catch {
                matches = false;
                break;
            };
        }
        if (matches) return true;
    }
    return false;
}
pub fn requirements(module: *const core.Module, predicates: T.List, scopes: *contracts.Context, body: core.BindingId) Error!void {
    for (module.obligations[predicates.start..][0..predicates.len]) |goal| {
        try step(scopes);
        try require(goal.kind == .contract);
        const arguments = module.types.node(goal.ty);
        try require(arguments.tag == .product);
        var found = try implementationGiven(module, body, goal, scopes);
        if (found) continue;
        for (module.selected_proofs) |proof| {
            try step(scopes);
            if (proof.kind != .implementation or proof.contract.unit != goal.identity.unit or proof.contract.decl != goal.identity.decl or proof.arguments.len != arguments.b) continue;
            // Residual implementation requirements must be closed. Candidate
            // mismatch cannot publish covariant row authority into the scope.
            var same: contracts.Principal = .{ .left = &module.types, .right = &module.types, .remaining = scopes.remaining };
            var matches = true;
            for (module.types.list(.{ .start = arguments.a, .len = arguments.b }), module.types.list(proof.arguments)) |expected, actual| {
                same.validate(expected, actual) catch {
                    matches = false;
                    break;
                };
            }
            if (!matches) continue;
            found = true;
            break;
        }
        try require(found);
    }
}
fn givenBinders(module: *const core.Module, given: core.DictionaryGiven, scopes: *contracts.Context) Error!T.List {
    const owner = module.types.node(given.quantifier);
    if (given.introduction != 0) {
        try require(given.opening == 0 and owner.tag == .forall);
        for (scopes.formals[0..scopes.formal_count], scopes.introductions[0..scopes.formal_count]) |quantifier, introduction| {
            try step(scopes);
            if (quantifier == given.quantifier and introduction == given.introduction) return .{ .start = owner.b, .len = owner.c };
        }
    } else {
        try require(owner.tag == .existential);
        for (scopes.openings[0..scopes.opening_count]) |opening| {
            try step(scopes);
            if (opening.binding == given.opening and opening.quantifier == given.quantifier) return opening.binders;
        }
    }
    return error.InvalidArtifact;
}
fn givenArguments(module: *const core.Module, given: core.DictionaryGiven, wanted: T.Obligation, scopes: *contracts.Context) Error!void {
    const opened = try givenBinders(module, given, scopes);
    const owner = module.types.node(given.quantifier);
    const goals = module.types.quantifierGoals(given.quantifier);
    try require(given.goal < goals.len);
    const goal = goals[given.goal];
    try require(goal.kind == .contract and goal.identity.unit == wanted.identity.unit and goal.identity.decl == wanted.identity.decl);
    const arguments = module.types.node(goal.ty);
    try require(arguments.tag == .product and arguments.b == given.arguments.len);
    var comparison: contracts.Principal = .{ .left = &module.types, .right = &module.types, .remaining = scopes.remaining, .views = scopes };
    for (module.types.list(.{ .start = arguments.a, .len = arguments.b }), module.types.list(given.arguments)) |expected, actual| {
        try comparison.substituted(.{ .start = owner.b, .len = owner.c }, module.types.list(opened), expected, actual);
    }
}
pub fn pack(module: *const core.Module, id: core.Id, scopes: *contracts.Context) Error!void {
    const node = module.node(id);
    const owner = module.types.node(node.ty);
    const goals = module.types.quantifierGoals(node.ty);
    var count: usize = 0;
    var content_slot: usize = 1;
    const contents = module.children(id);
    for (goals, 0..) |goal, ordinal| {
        try step(scopes);
        const declaration = try contract(module, goal);
        var selected: ?core.DictionarySelection = null;
        for (module.dictionary_selections) |candidate| {
            try step(scopes);
            if (candidate.owner != id or candidate.goal != ordinal) continue;
            try require(selected == null);
            selected = candidate;
        }
        const selection = selected orelse return error.InvalidArtifact;
        const arguments = module.types.node(goal.ty);
        try require(arguments.tag == .product);
        const formals: T.List = .{ .start = owner.b, .len = owner.c };
        const witnesses = module.types.list(.{ .start = node.b, .len = node.c });
        const nodes = module.extra[selection.members.start..][0..selection.members.len];
        switch (selection.proof) {
            .selected => |selected_proof| {
                const proof = module.selected_proofs[selected_proof];
                try require(proof.kind == .implementation and proof.contract.unit == goal.identity.unit and proof.contract.decl == goal.identity.decl);
                try require(arguments.b == proof.arguments.len);
                var substitution: contracts.Principal = .{ .left = &module.types, .right = &module.types, .remaining = scopes.remaining, .views = scopes };
                for (module.types.list(.{ .start = arguments.a, .len = arguments.b }), module.types.list(proof.arguments)) |expected, actual| try substitution.substituted(formals, witnesses, expected, actual);
                try require(proof.members.len == declaration.members.len and selection.members.len == proof.members.len);
                for (module.selected_members[proof.members.start..][0..proof.members.len], nodes) |member, value| {
                    try step(scopes);
                    if (member.kind == .type_) {
                        try require(value == 0);
                        continue;
                    }
                    try require(value != 0 and module.node(value).tag == .reference and module.typeOf(value) == member.root);
                    try require(sameTarget(module, module.reference(value), member.target));
                    try require(content_slot < contents.len and contents[content_slot] == value);
                    content_slot += 1;
                }
            },
            .given => |given| {
                try givenArguments(module, given, goal, scopes);
                try require(arguments.b == given.arguments.len and selection.members.len == declaration.members.len);
                var substitution: contracts.Principal = .{ .left = &module.types, .right = &module.types, .remaining = scopes.remaining, .views = scopes };
                for (module.types.list(.{ .start = arguments.a, .len = arguments.b }), module.types.list(given.arguments)) |expected, actual| try substitution.substituted(formals, witnesses, expected, actual);
                for (module.contract_members[declaration.members.start..][0..declaration.members.len], nodes, 0..) |member, value, ordinal_| {
                    try step(scopes);
                    if (member.kind != .value) {
                        try require(value == 0);
                        continue;
                    }
                    try require(value != 0 and module.node(value).tag == .reference);
                    var matching = false;
                    for (module.dictionary_uses) |method| {
                        try step(scopes);
                        if (method.node != value) continue;
                        try require(!matching);
                        try require(method.opening == given.opening and method.introduction == given.introduction and method.quantifier == given.quantifier and method.goal == given.goal and method.member == ordinal_);
                        matching = true;
                    }
                    try require(matching);
                    try use(module, value, scopes);
                    try require(content_slot < contents.len and contents[content_slot] == value);
                    content_slot += 1;
                }
            },
        }
        count += 1;
    }
    for (module.dictionary_selections) |selection| {
        try step(scopes);
        if (selection.owner == id) {
            try require(selection.quantifier == node.ty);
            try require(selection.goal < goals.len);
            try require(selection.contents.len == contents.len);
            for (module.extra[selection.contents.start..][0..selection.contents.len], contents) |left, right| try require(left == right);
            try require(count != 0);
            count -= 1;
        }
    }
    try require(count == 0 and content_slot == contents.len);
}

// This resolver is installed only while checking this exact pack's payload.
// Its evidence was reconstructed by pack(); a matching ambient implementation
// or another pack's selection never grants associated representation authority.
pub const PackProjection = struct {
    module: *const core.Module,
    owner: core.Id,
    pub fn resolver(self: *PackProjection) contracts.ProjectionResolver {
        return .{ .context = self, .validate = validate };
    }
    fn validate(raw: *anyopaque, substitution: *const contracts.Substitution, expected: T.Id, actual: T.Id) Error!void {
        const self: *PackProjection = @ptrCast(@alignCast(raw));
        const module = self.module;
        const node = module.node(self.owner);
        try require(node.tag == .package_pack and substitution.types == &module.types);
        const owner = module.types.node(node.ty);
        try require(substitution.formal.start == owner.b and substitution.formal.len == owner.c);
        const witnesses = module.types.list(.{ .start = node.b, .len = node.c });
        try require(witnesses.len == substitution.witnesses.len);
        for (witnesses, substitution.witnesses) |owned, supplied| try require(owned == supplied);
        const projection = module.types.node(expected);
        try require(projection.tag == .projection);
        const arguments = module.types.nominalArguments(projection);
        const goals = module.types.quantifierGoals(node.ty);
        for (module.dictionary_selections) |selection| {
            try require(substitution.remaining.* != 0);
            substitution.remaining.* -= 1;
            if (selection.owner != self.owner or selection.quantifier != node.ty) continue;
            try require(selection.goal < goals.len);
            const goal = goals[selection.goal];
            if (goal.kind != .contract or goal.identity.unit != projection.a or goal.identity.decl != projection.b) continue;
            const proof = switch (selection.proof) {
                .selected => |selected| module.selected_proofs[selected],
                .given => continue,
            };
            const goal_arguments = module.types.node(goal.ty);
            try require(goal_arguments.tag == .product and goal_arguments.b == proof.arguments.len);
            if (arguments.len != proof.arguments.len) continue;
            var comparison: contracts.Principal = .{ .left = &module.types, .right = &module.types, .remaining = substitution.remaining, .views = substitution.views };
            var matches = true;
            for (arguments, module.types.list(.{ .start = goal_arguments.a, .len = goal_arguments.b }), module.types.list(proof.arguments)) |argument, goal_argument, selected_argument| {
                comparison.substituted(substitution.formal, substitution.witnesses, goal_argument, selected_argument) catch {
                    matches = false;
                    break;
                };
                comparison.substituted(substitution.formal, substitution.witnesses, argument, selected_argument) catch {
                    matches = false;
                    break;
                };
            }
            if (!matches) {
                try require(substitution.remaining.* != 0);
                continue;
            }
            const member_name = module.types.projectionMember(projection);
            const declaration = try contract(module, goal);
            try require(declaration.members.len == proof.members.len);
            for (module.contract_members[declaration.members.start..][0..declaration.members.len], module.selected_members[proof.members.start..][0..proof.members.len]) |member, selected| {
                try require(substitution.remaining.* != 0);
                substitution.remaining.* -= 1;
                if (member.name != member_name) continue;
                try require(member.kind != .value and selected.kind == .type_ and selected.name == member_name);
                return comparison.validate(selected.root, actual);
            }
            return error.InvalidArtifact;
        }
        return error.InvalidArtifact;
    }
};

pub fn use(module: *const core.Module, id: core.Id, scopes: *contracts.Context) Error!void {
    if (module.dictionary_uses.len == 0) return;
    const reference = module.reference(id);
    if (reference.unit != 0 and reference.unit != module.unit) return;
    var synthetic = false;
    var found = false;
    for (module.dictionary_uses) |value| {
        try step(scopes);
        if (value.binding == reference.binding) synthetic = true;
        if (value.node != id) continue;
        try require(!found);
        found = true;
        const owner = module.types.node(value.quantifier);
        var opened: T.List = undefined;
        if (value.introduction != 0) {
            try require(value.opening == 0 and owner.tag == .forall);
            var active = false;
            for (scopes.formals[0..scopes.formal_count], scopes.introductions[0..scopes.formal_count]) |quantifier, introduction| {
                if (quantifier == value.quantifier and introduction == value.introduction) active = true;
            }
            try require(active);
            opened = .{ .start = owner.b, .len = owner.c };
        } else {
            var active: ?T.List = null;
            for (scopes.openings[0..scopes.opening_count]) |opening| {
                try step(scopes);
                if (opening.binding == value.opening) active = opening.binders;
            }
            opened = active orelse return error.InvalidArtifact;
            var source: core.Id = 0;
            for (module.nodes, 0..) |node, ordinal| {
                try step(scopes);
                if (node.tag != .package_unpack or node.b != value.opening) continue;
                try require(source == 0);
                source = @intCast(ordinal);
            }
            try require(source != 0 and module.typeOf(module.node(source).a) == value.quantifier);
        }
        const goals = module.types.quantifierGoals(value.quantifier);
        try require(value.goal < goals.len);
        const goal = goals[value.goal];
        const declaration = try contract(module, goal);
        try require(value.member < declaration.members.len and declaration.variables.len <= 128);
        const member = module.contract_members[declaration.members.start + value.member];
        try require(member.kind == .value);
        const arguments = module.types.node(goal.ty);
        try require(arguments.tag == .product and arguments.b == declaration.parameters.len);
        var replacements: [128]T.Id = @splat(0);
        var selector: contracts.Principal = .{ .left = &module.types, .right = &module.types, .remaining = scopes.remaining, .views = scopes };
        for (module.types.list(declaration.parameters), module.types.list(.{ .start = arguments.a, .len = arguments.b })) |parameter, argument| {
            try selector.substituted(declaration.variables, replacements[0..declaration.variables.len], parameter, argument);
            for (selector.witnesses[0..declaration.variables.len], 0..) |replacement, ordinal| replacements[ordinal] = replacement;
        }
        for (replacements[0..declaration.variables.len]) |replacement| try require(replacement != 0);
        const formals: T.List = .{ .start = owner.b, .len = owner.c };
        var proof: contracts.Principal = .{ .left = &module.types, .right = &module.types, .remaining = scopes.remaining, .views = scopes };
        try proof.composed(declaration.variables, replacements[0..declaration.variables.len], formals, module.types.list(opened), member.root, module.typeOf(id));
    }
    try require(!synthetic or found);
}

/// Independently reconstruct a universal elimination's required predicates.
/// Concrete proofs are already admitted by the enclosing immutable reader;
/// lexical universal givens remain tied to their exact owned binder endpoints.
pub fn instantiated(module: *const core.Module, producer: *const core.Module, quantifier: T.Id, witnesses: []const T.Id, scopes: *contracts.Context) Error!void {
    const owner = producer.types.node(quantifier);
    const formals: T.List = .{ .start = owner.b, .len = owner.c };
    try require(owner.tag == .forall and formals.len == witnesses.len);
    for (producer.types.quantifierGoals(quantifier)) |goal| {
        try step(scopes);
        try require(goal.kind == .contract);
        const arguments = producer.types.node(goal.ty);
        try require(arguments.tag == .product);
        const inputs = producer.types.list(.{ .start = arguments.a, .len = arguments.b });
        var found = false;
        for (module.selected_proofs) |proof| {
            try step(scopes);
            if (proof.kind != .implementation or proof.contract.unit != goal.identity.unit or proof.contract.decl != goal.identity.decl or proof.arguments.len != inputs.len) continue;
            var matches = true;
            for (inputs, module.types.list(proof.arguments)) |expected, actual| {
                var comparison: contracts.Principal = .{ .left = &producer.types, .right = &module.types, .remaining = scopes.remaining, .views = scopes };
                comparison.substituted(formals, witnesses, expected, actual) catch {
                    matches = false;
                    break;
                };
            }
            if (matches) {
                found = true;
                break;
            }
        }
        if (!found) for (scopes.formals[0..scopes.formal_count]) |given_owner| {
            for (module.types.quantifierGoals(given_owner)) |given| {
                try step(scopes);
                if (given.kind != .contract or given.identity.unit != goal.identity.unit or given.identity.decl != goal.identity.decl) continue;
                const parameters = module.types.node(given.ty);
                if (parameters.tag != .product or parameters.b != inputs.len) continue;
                var matches = true;
                for (inputs, module.types.list(.{ .start = parameters.a, .len = parameters.b })) |expected, actual| {
                    var comparison: contracts.Principal = .{ .left = &producer.types, .right = &module.types, .remaining = scopes.remaining, .views = scopes };
                    comparison.substituted(formals, witnesses, expected, actual) catch {
                        matches = false;
                        break;
                    };
                }
                if (matches) {
                    found = true;
                    break;
                }
            }
            if (found) break;
        };
        if (!found) for (scopes.schemes[0..scopes.scheme_count]) |scheme| {
            for (try scopes.schemeGoals(scheme)) |given| {
                try step(scopes);
                if (given.kind != .contract or given.identity.unit != goal.identity.unit or given.identity.decl != goal.identity.decl) continue;
                const parameters = module.types.node(given.ty);
                if (parameters.tag != .product or parameters.b != inputs.len) continue;
                var matches = true;
                for (inputs, module.types.list(.{ .start = parameters.a, .len = parameters.b })) |expected, actual| {
                    var comparison: contracts.Principal = .{ .left = &producer.types, .right = &module.types, .remaining = scopes.remaining, .views = scopes };
                    comparison.substituted(formals, witnesses, expected, actual) catch {
                        matches = false;
                        break;
                    };
                }
                if (matches) {
                    found = true;
                    break;
                }
            }
            if (found) break;
        };
        try require(found);
    }
}
