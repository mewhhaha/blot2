//! Exact immutable collection contracts shared by executable Core readers.
const core = @import("core.zig");
const T = @import("types.zig");
const Error = error{InvalidArtifact};
fn require(ok: bool) Error!void {
    if (!ok) return error.InvalidArtifact;
}
pub fn validate(types: *const core.Types, operation: core.ArrayOp, inputs: []const T.Id, output_: T.Id, proof: anytype) Error!void {
    if (inputs.len == 0) return error.InvalidArtifact;
    try require(inputs.len == @import("../backend/collection_ops.zig").arity(operation));
    const first = types.node(inputs[0]);
    const result = types.node(output_);
    switch (operation) {
        .length, .get, .set, .append, .prepend, .identity, .concat, .slice => {
            try require(first.tag == .array or first.tag == .list);
            switch (operation) {
                .length => try proof.same(T.u32_type, output_),
                .get => {
                    try require(first.tag == .array);
                    try proof.same(T.u32_type, inputs[1]);
                    try proof.same(first.a, output_);
                },
                .set => {
                    try require(first.tag == .array);
                    try proof.same(T.u32_type, inputs[1]);
                    try proof.same(first.a, inputs[2]);
                    try proof.same(inputs[0], output_);
                },
                .append, .prepend => {
                    try proof.same(first.a, inputs[1]);
                    try proof.same(inputs[0], output_);
                },
                .concat => {
                    try proof.same(inputs[0], inputs[1]);
                    try proof.same(inputs[0], output_);
                },
                .slice => {
                    try proof.same(T.u32_type, inputs[1]);
                    try proof.same(T.u32_type, inputs[2]);
                    try proof.same(inputs[0], output_);
                },
                .identity => try proof.same(inputs[0], output_),
                else => unreachable,
            }
        },
        .fill, .generate => {
            try proof.same(T.u32_type, inputs[0]);
            try require(result.tag == .array or result.tag == .list);
            if (operation == .fill) {
                try proof.same(result.a, inputs[1]);
            } else {
                const generator = types.node(inputs[1]);
                try require(generator.tag == .function);
                try proof.callback(generator.c);
                try proof.same(T.u32_type, generator.a);
                try proof.same(result.a, generator.b);
            }
        },
        .convert => {
            try require((first.tag == .array and result.tag == .list) or (first.tag == .list and result.tag == .array));
            try proof.same(first.a, result.a);
        },
        .cursor => {
            try require((first.tag == .array or first.tag == .list) and result.tag == .cursor);
            try proof.same(inputs[0], result.a);
        },
        .cursor_has, .cursor_value, .cursor_advance => {
            try require(first.tag == .cursor);
            const sequence = types.node(first.a);
            if (sequence.tag != .array and sequence.tag != .list) {
                if (comptime @hasDecl(@TypeOf(proof), "collection")) {
                    var element: T.Id = 0;
                    if (operation == .cursor_value) element = output_;
                    try proof.collection(first.a, element);
                } else return error.InvalidArtifact;
            }
            switch (operation) {
                .cursor_has => try proof.same(T.boolean, output_),
                .cursor_value => if (sequence.tag == .array or sequence.tag == .list) try proof.same(sequence.a, output_),
                .cursor_advance => try proof.same(inputs[0], output_),
                else => unreachable,
            }
        },
    }
}
