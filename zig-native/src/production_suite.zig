//! Run all native tests with the retained server's production cache policies.
test "native compiler with production artifact policies" {
    const artifacts = @import("code_artifacts.zig");
    artifacts.buffered_stamps_enabled = true;
    artifacts.scoped_stamps_enabled = true;
    artifacts.exact_stamps_enabled = true;
    _ = @import("tests.zig");
}
