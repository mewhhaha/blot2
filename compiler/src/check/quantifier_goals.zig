//! Immutable predicate ownership. Ordered owner IDs are exact graph handles.
const T = @import("types.zig");
pub fn get(records: []const T.QuantifierGoals, obligations: []const T.Obligation, owner: T.Id) []const T.Obligation {
    var low: usize = 0;
    var high = records.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const record = records[middle];
        if (record.owner < owner) {
            low = middle + 1;
        } else if (record.owner > owner) {
            high = middle;
        } else {
            return obligations[record.goals.start..][0..record.goals.len];
        }
    }
    return &.{};
}
pub fn sameHead(a: T.Obligation, b: T.Obligation) bool {
    return a.kind == b.kind and a.name == b.name and a.operator == b.operator and a.identity.unit == b.identity.unit and a.identity.decl == b.identity.decl;
}
pub fn sort(records: []T.QuantifierGoals) void {
    @import("std").mem.sort(T.QuantifierGoals, records, {}, struct {
        fn less(_: void, a: T.QuantifierGoals, b: T.QuantifierGoals) bool {
            return a.owner < b.owner;
        }
    }.less);
}
pub fn validate(nodes: []const T.Node, records: []const T.QuantifierGoals, obligations: []const T.Obligation) error{InvalidArtifact}!void {
    var remaining: usize = 65_536;
    return validateWithBudget(nodes, records, obligations, &remaining);
}
pub fn validateWithBudget(nodes: []const T.Node, records: []const T.QuantifierGoals, obligations: []const T.Obligation, remaining: *usize) error{InvalidArtifact}!void {
    var previous: T.Id = 0;
    var claimed: usize = 0;
    for (records) |record| {
        if (remaining.* == 0) return error.InvalidArtifact;
        remaining.* -= 1;
        if (record.owner == 0 or record.owner <= previous or record.owner >= nodes.len) return error.InvalidArtifact;
        previous = record.owner;
        const node = nodes[record.owner];
        if (node.tag != .forall and node.tag != .existential) return error.InvalidArtifact;
        if (record.goals.len == 0 or record.goals.len > 4096 or record.goals.start > obligations.len or record.goals.len > obligations.len - record.goals.start) return error.InvalidArtifact;
        if (record.goals.start != claimed) return error.InvalidArtifact;
        claimed = @import("std").math.add(usize, claimed, record.goals.len) catch return error.InvalidArtifact;
        for (obligations[record.goals.start..][0..record.goals.len]) |goal| {
            if (remaining.* == 0) return error.InvalidArtifact;
            remaining.* -= 1;
            inline for (.{ "ty", "other", "result", "signature" }) |field| if (@field(goal, field) >= nodes.len) return error.InvalidArtifact;
        }
    }
    if (claimed != obligations.len) return error.InvalidArtifact;
}
