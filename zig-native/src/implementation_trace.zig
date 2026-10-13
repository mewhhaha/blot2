//! Bounded selection facts. Rendering consumes this record without matching
//! again; identities and type IDs stay in the owning frontend/evaluator graph.
const T = @import("types.zig");
const D = @import("dispatch_explanation.zig");
pub const Record = struct {
    pub const Candidate = struct { identity: T.NominalIdentity, outcome: D.Outcome };
    pub const Step = struct { ty: u32, member: u32 = 0, outcome: D.Outcome };
    context: u32 = 0,
    request: u32 = 0,
    contract: T.NominalIdentity = .{ .unit = 0, .decl = 0 },
    candidates: [D.max_candidates]Candidate = undefined,
    len: usize = 0,
    steps: [D.max_steps]Step = undefined,
    step_len: usize = 0,
    truncated: bool = false,
    pub fn candidate(self: *Record, identity: T.NominalIdentity, outcome: D.Outcome) void {
        for (self.candidates[0..self.len]) |*known| if (known.identity.unit == identity.unit and known.identity.decl == identity.decl) {
            known.outcome = outcome;
            return;
        };
        if (self.len == self.candidates.len) {
            self.truncated = true;
            return;
        }
        self.candidates[self.len] = .{ .identity = identity, .outcome = outcome };
        self.len += 1;
    }
    pub fn step(self: *Record, ty: u32, member: u32, outcome: D.Outcome) ?usize {
        if (self.step_len == self.steps.len) {
            self.truncated = true;
            return null;
        }
        const index = self.step_len;
        self.steps[index] = .{ .ty = ty, .member = member, .outcome = outcome };
        self.step_len += 1;
        return index;
    }
    pub fn setOutcome(self: *Record, index: ?usize, value: D.Outcome) void {
        if (index) |ordinal| self.steps[ordinal].outcome = value;
    }
};
