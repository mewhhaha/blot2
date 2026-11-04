//! Numeric domains stay compact while representation/proof conversions cannot
//! silently exchange a layout, semantic type, effect row or source expression.
//! Handles identify an index within the store bound to the receiving service;
//! they are never portable across compilation owners.
pub const Layout = enum(u32) { _ };
pub const Evidence = enum(u32) { _ };
pub const LayoutRow = enum(u32) { _ };
pub const EvidenceRow = enum(u32) { _ };
pub const Expectation = enum(u32) { _ };
pub const Expression = enum(u32) { _ };
