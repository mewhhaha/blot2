//! Run all native tests with the retained server's production cache policies.
test "native compiler with production artifact policies" {
    _ = @import("tests.zig");
}
