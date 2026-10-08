//! The one vocabulary for constant-evaluation and code-emission failures. The
//! evaluator and the backend each wrap a `Code` in their own diagnostic record
//! but share this enum and its wording, so a failure keeps its code and
//! message as it crosses from one to the other.
const std = @import("std");

pub const Code = enum {
    // Constant evaluation.
    cycle,
    constant_fuel,
    integer_divide_by_zero,
    array_bounds,
    backend_limit,
    const_panic,
    const_effect,
    const_runtime_dependency,
    // Typing and dispatch.
    invalid_annotation,
    ambiguous_state,
    ambiguous_operator,
    ambiguous_associated,
    missing_associated,
    ambiguous_member,
    missing_member,
    missing_field,
    ambiguous_qualified,
    type_mismatch,
    effect_mismatch,
    infinite_effect,
    type_constructor_required,
    invalid_provider,
    // Native lowering and entry validation.
    initialization_cycle,
    backend_const_only,
    unsupported,
    no_entry,
    entry_type,
    entry_let_type,
    unresolved_type,
    constant_expression,
    complexity,

    /// The public message. `detail` carries the producer's more specific text
    /// when it has one; a panic message is always the detail.
    pub fn message(self: Code, detail: []const u8) []const u8 {
        return switch (self) {
            .const_panic => detail,
            .cycle => "Compile-time constant dependencies contain a cycle",
            .constant_fuel => "Constant evaluation exceeded its operation or nesting budget",
            .integer_divide_by_zero => "Compile-time integer division or remainder has a zero divisor",
            .array_bounds => "Array index is outside the element range",
            .backend_limit => if (detail.len != 0) detail else "Array length exceeds the 16 MiB bootstrap arena",
            .const_effect => "A constant initializer requires a handled effect",
            .const_runtime_dependency => if (detail.len != 0) detail else "a const initializer cannot read a top-level let value initialized at module startup",
            .invalid_annotation => "Never is an internal control-flow type",
            .ambiguous_state => "State requires a concrete runtime value type",
            .ambiguous_operator => "This operator does not have a compatible implementation for these operand types",
            .ambiguous_associated => if (detail.len != 0) detail else "Associated result dispatch requires a known destination type",
            .missing_associated => "Neither operand has a compatible associated implementation",
            .ambiguous_member => "A field and associated function share this name",
            .missing_member => "This receiver has no associated member with this name",
            .missing_field => if (detail.len != 0) detail else "This receiver has no physical field with this name",
            .ambiguous_qualified => "An explicit predicate lacks complete concrete evidence",
            .type_mismatch => if (detail.len != 0) detail else "The expression has a different type from the required type",
            .effect_mismatch => "Effect rows do not match",
            .infinite_effect => "An effect row contains itself",
            .type_constructor_required => "A monad resolver requires a declared data type constructor",
            .invalid_provider => "This computation requires an effect resolver",
            .initialization_cycle => "top-level let initializers form a dependency cycle",
            .backend_const_only => "Effect reflection and descriptors are available only during constant evaluation",
            .unsupported => "This typed core form is not supported by constant evaluation or native Wasm lowering",
            .no_entry => "A build requires at least one entry declaration",
            .entry_type => if (detail.len != 0) detail else "An entry requires one supported guest parameter and result, or a scalar constant",
            .entry_let_type => if (detail.len != 0) detail else "A runtime-initialized entry requires a supported guest function or a scalar global",
            .unresolved_type => "Code emission requires concrete representation evidence",
            .constant_expression => "This compile-time value cannot be evaluated by the native evaluator",
            .complexity => "Typed-core lowering exceeds the native compiler limit",
        };
    }
};

test "every code has a message and details override only the codes that accept them" {
    inline for (@typeInfo(Code).@"enum".field_names) |name| {
        const code = @field(Code, name);
        try std.testing.expect(code.message("").len != 0 or code == .const_panic);
    }
    try std.testing.expectEqualStrings("panicked", Code.const_panic.message("panicked"));
    try std.testing.expectEqualStrings("specific", Code.type_mismatch.message("specific"));
    try std.testing.expect(!std.mem.eql(u8, "specific", Code.cycle.message("specific")));
}
