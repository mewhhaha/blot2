//! Loop carries retain inline data or descriptors for the same named owners.
//! A backedge cannot replace an owner or widen a borrow's possible roots: the
//! body was checked using the incoming root set, not a later iteration's set.
pub fn fixedCarry(value: anytype) bool {
    if (value.demand != null) return false;
    switch (value.tag) {
        .callable => return false,
        .array => if (value.root == null) return false,
        else => {},
    }
    for (value.fields) |field| if (!fixedCarry(field)) return false;
    return true;
}

fn contains(value: anytype, root: usize) bool {
    if (value.root == root) return true;
    for (value.other_roots) |other| if (other == root) return true;
    return false;
}
fn includes(left: anytype, right: @TypeOf(left)) bool {
    if (right.root) |root| if (!contains(left, root)) return false;
    for (right.other_roots) |root| if (!contains(left, root)) return false;
    return true;
}
pub fn stableCarry(before: anytype, after: @TypeOf(before)) bool {
    if (before.tag != after.tag or before.fields.len != after.fields.len) return false;
    if (!includes(before, after) or !includes(after, before)) return false;
    for (before.fields, after.fields) |old, next| if (!stableCarry(old, next)) return false;
    return true;
}
