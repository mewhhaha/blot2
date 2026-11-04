//! Live dependency-validation capabilities. Only closure freezing can mint
//! these receipts; they are never decoded, serialized or retained separately
//! from the immutable dependency snapshot that pins their Core slices.
const closure = @import("dependency_closure.zig");
pub const Receipt = closure.CoreValidationReceipt;
pub const Borrow = closure.CoreValidationBorrow;
