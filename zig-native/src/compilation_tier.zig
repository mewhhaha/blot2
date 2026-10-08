//! Output policy, separate from the optimization mode used to build blotc.
//! Both tiers perform the same semantic checks and required runtime cleanup.
pub const Tier = enum { optimized, development };
