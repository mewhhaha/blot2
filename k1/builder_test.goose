import builder;

fn main() {
    var clock = builder::Clock {};
    var cell = builder::Cell {};
    var mem: u8[32] = [99; 32];
    let a: u8[] = [1, 2, 3, 4];
    let b: u8[] = [5, 6, 7, 8];
    let c: u8[] = [9, 10, 11, 12];
    let start = builder::begin(cell, clock, mem, 4, 2, 1, 1);
    assert(start.status == 0 && start.handle.identity == 1 && start.handle.version == 1);
    assert(cell.length == 0 && cell.capacity == 2 && cell.state == 1);
    assert(builder::begin(cell, clock, mem, 4, 2, 1, 1).status == 2);
    assert(builder::read(cell, start.handle, mem, 0).status == 3);
    let one = builder::try_append(cell, start.handle, mem, a);
    assert(one.status == 0 && one.handle.version == 2 && cell.length == 1);
    assert(mem[4] == 1 && mem[5] == 2 && mem[6] == 3 && mem[7] == 4);
    assert(builder::try_append(cell, start.handle, mem, b).status == 2);
    assert(builder::read(cell, start.handle, mem, 0).status == 2);
    let read_one = builder::read(cell, one.handle, mem, 0);
    assert(read_one.status == 0 && read_one.size == 4 && read_one.bytes[0] == 1 && read_one.bytes[3] == 4);
    let two = builder::try_append(cell, one.handle, mem, b);
    assert(two.status == 0 && cell.length == 2);
    let full = builder::try_append(cell, two.handle, mem, c);
    assert(full.status == 1 && full.handle.identity == two.handle.identity && full.handle.version == two.handle.version);
    assert(cell.length == 2 && cell.version == two.handle.version && mem[8] == 5 && mem[11] == 8);
    // No read of the uninitialized prefix or out-of-range index is permitted.
    assert(builder::read(cell, two.handle, mem, 2).status == 3);
    assert(builder::set(cell, two.handle, mem, 2, c).status == 3);
    assert(builder::truncate(cell, two.handle, mem, 1).status == 3); // Append mode
    let changed = builder::set(cell, two.handle, mem, 0, c);
    assert(changed.status == 0 && cell.length == 2 && changed.handle.version == 4);
    assert(mem[4] == 9 && mem[7] == 12 && builder::read(cell, two.handle, mem, 0).status == 2);
    let frozen = builder::freeze(cell, changed.handle, clock, mem);
    assert(frozen.status == 0 && frozen.data == 4 && frozen.length == 2 && frozen.domain == 2);
    assert(cell.state == 3 && builder::try_append(cell, changed.handle, mem, a).status == 2);
    assert(builder::freeze(cell, changed.handle, clock, mem).status == 2);
    assert(builder::discard(cell, changed.handle).status == 2);

    // Resize loses access to the truncated suffix. Re-extending must write it.
    let resizable = builder::begin(cell, clock, mem, 4, 2, 1, 2);
    assert(resizable.status == 0 && resizable.handle.identity == 3);
    let r1 = builder::try_append(cell, resizable.handle, mem, a);
    let r2 = builder::try_append(cell, r1.handle, mem, b);
    // The input overlaps the destination's first byte. A complete snapshot
    // must be made before the first store, preserving its original last byte.
    let overlap = builder::set(cell, r2.handle, mem, 1, mem[5..9]);
    assert(overlap.status == 0 && mem[8] == 2 && mem[9] == 3 && mem[10] == 4 && mem[11] == 5);
    let truncated = builder::truncate(cell, overlap.handle, mem, 1);
    assert(truncated.status == 0 && cell.length == 1 && builder::read(cell, truncated.handle, mem, 1).status == 3);
    let r3 = builder::try_append(cell, truncated.handle, mem, c);
    assert(r3.status == 0 && cell.length == 2 && mem[8] == 9 && mem[11] == 12);
    let rfreeze = builder::freeze(cell, r3.handle, clock, mem);
    assert(rfreeze.status == 0 && rfreeze.domain == 4 && rfreeze.domain != frozen.domain);

    // Invalid scalar values and bad input size never publish a partial Bool.
    let bool_start = builder::begin(cell, clock, mem, 4, 1, 3, 1);
    let invalid_bool: u8[] = [2, 0, 0, 0];
    let padded_bool: u8[] = [1, 1, 0, 0];
    let yes: u8[] = [1, 0, 0, 0];
    let short: u8[] = [1, 0, 0];
    assert(builder::try_append(cell, bool_start.handle, mem, invalid_bool).status == 4);
    assert(builder::try_append(cell, bool_start.handle, mem, padded_bool).status == 4);
    assert(builder::try_append(cell, bool_start.handle, mem, short).status == 4);
    assert(cell.length == 0 && cell.version == bool_start.handle.version && mem[4] == 1);
    let valid_bool = builder::try_append(cell, bool_start.handle, mem, yes);
    assert(valid_bool.status == 0 && cell.length == 1);
    mem[4] = 2; // deliberate model-boundary corruption
    assert(builder::read(cell, valid_bool.handle, mem, 0).status == 4);
    assert(builder::discard(cell, valid_bool.handle).status == 0);
    assert(builder::read(cell, valid_bool.handle, mem, 0).status == 2);

    // Unit retains logical capacity and bounds while never accessing bytes.
    let empty_bytes: u8[] = [];
    let unit = builder::begin(cell, clock, mem, 0, 2, 0, 1);
    assert(unit.status == 0);
    let u1 = builder::try_append(cell, unit.handle, mem, empty_bytes);
    let u2 = builder::try_append(cell, u1.handle, mem, empty_bytes);
    assert(u2.status == 0 && cell.length == 2);
    let unit_read = builder::read(cell, u2.handle, mem, 1);
    assert(unit_read.status == 0 && unit_read.size == 0);
    assert(builder::try_append(cell, u2.handle, mem, empty_bytes).status == 1);
    let unit_view = builder::freeze(cell, u2.handle, clock, mem);
    assert(unit_view.status == 0 && unit_view.data == 0 && unit_view.length == 2);
    // A Unit prefix can reach U32.MAX without allocating an impossible host
    // array. The seeded prefix models already initialized zero-sized values.
    let huge_unit = builder::begin(cell, clock, mem, 0, 4294967295, 0, 1);
    assert(huge_unit.status == 0);
    cell.length = 4294967294;
    let last_unit = builder::try_append(cell, huge_unit.handle, mem, empty_bytes);
    assert(last_unit.status == 0 && cell.length == 4294967295);
    assert(builder::try_append(cell, last_unit.handle, mem, empty_bytes).status == 1);
    let huge_view = builder::freeze(cell, last_unit.handle, clock, mem);
    assert(huge_view.status == 0 && huge_view.data == 0 && huge_view.length == 4294967295);
    let empty = builder::begin(cell, clock, mem, 4, 0, 1, 1);
    let empty_view = builder::freeze(cell, empty.handle, clock, mem);
    assert(empty_view.status == 0 && empty_view.data == 0 && empty_view.length == 0);

    // Invalid ranges, invalid versions, and exhausted model counters leave
    // the live state and memory unchanged.
    let old_clock = clock.next;
    assert(builder::begin(cell, clock, mem, 4, 4294967295, 1, 1).status == 6);
    assert(clock.next == old_clock && cell.state == 3);
    assert(builder::begin(cell, clock, mem, 1, 1, 1, 1).status == 6);
    assert(builder::begin(cell, clock, mem, 0, 1, 1, 1).status == 6);
    assert(builder::begin(cell, clock, mem, 4, 1, 7, 1).status == 6);
    assert(clock.next == old_clock);
    let again = builder::begin(cell, clock, mem, 4, 1, 1, 1);
    assert(again.status == 0 && again.handle.identity != start.handle.identity);
    assert(builder::try_append(cell, start.handle, mem, a).status == 2);
    let old_byte = mem[4];
    let too_small: u8[] = [0; 4];
    assert(builder::try_append(cell, again.handle, too_small, a).status == 6);
    assert(cell.length == 0 && cell.version == again.handle.version && mem[4] == old_byte);
    let original_kind = cell.kind;
    cell.kind = 5;
    assert(builder::try_append(cell, again.handle, mem, a).status == 6 && cell.length == 0);
    cell.kind = original_kind;
    cell.length = 2;
    assert(builder::try_append(cell, again.handle, mem, a).status == 6);
    cell.length = 0;
    cell.version = 18446744073709551615;
    let last_version = builder::Handle { identity: cell.identity, version: cell.version };
    assert(builder::try_append(cell, last_version, mem, a).status == 5 && cell.length == 0);
    clock.next = 18446744073709551615;
    assert(builder::freeze(cell, last_version, clock, mem).status == 5 && cell.state == 1 && cell.length == 0);
    assert(builder::discard(cell, last_version).status == 0);
    assert(builder::begin(cell, clock, mem, 4, 1, 1, 1).status == 5 && cell.state == 4);
    cell.state = 5;
    assert(builder::begin(cell, clock, mem, 4, 1, 1, 1).status == 6 && cell.state == 5);
    print("builder state laws passed");
}
