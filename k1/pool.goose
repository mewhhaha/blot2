// Experimental deterministic pool-state model, not a K1 runtime or a
// certificate of linear ownership. Callers must prove the affine Space/Owner,
// lexical loans, disjointness and descendant-cleanup preconditions before
// invoking these helpers. Slot data and bitmap are trusted runtime state; they
// are not an external artifact or a way to mint source authority.
namespace pool;
import layout;

// Exactly the eight M03 control words, in order.
struct Slot {
    base: u32 = 0, requested: u32 = 0, rounded: u32 = 0, top: u32 = 0,
    generation: u32 = 0, state: u32 = 0, root_schema: u32 = 0, root_words: u32 = 0
}
struct Reservation {
    // 0 success, 1 SizeOverflow, 2 NoOwnerSlots, 3 NoContiguousSpace,
    // 4 internal model/configuration fault.
    status: i64 = 0, slot: u32 = 0, generation: u32 = 0
}
struct Placement {
    // 0 success, 1 SizeOverflow, 2 NoSpace, 3 invalid handle/state/config.
    status: i64 = 0, data: u32 = 0
}

fn configuration(slots: Slot[:], bitmap: u32[:], base: u32, granules: u32) -> bool {
    if slots.len > 4096 || granules > 262144 { return false; }
    if base % 4096 != 0 || (granules != 0 && base == 0) { return false; }
    let pool_bytes, ok = layout::checked_mul(granules, 4096);
    if !ok || base > 1073741824 || pool_bytes > 1073741824 - base { return false; }
    return bitmap.len == (granules + 31) / 32;
}
fn occupied(bitmap: u32[:], granule: u32) -> bool {
    return (bitmap[granule / 32] & (1 as u32 << (granule % 32))) != 0;
}
fn set_granule(bitmap: u32[:], granule: u32, value: bool) {
    let word = granule / 32;
    let mask = 1 as u32 << (granule % 32);
    if value { bitmap[word] |= mask; } else { bitmap[word] &= ~mask; }
}

// First-fit, lowest slot and then lowest contiguous bitmap run. Searches and
// all checks finish before bitmap or entry are changed. Zero-byte reservation
// still takes an owner slot but neither consumes a granule nor names an address.
fn reserve(slots: Slot[:], bitmap: u32[:], base: u32, granules: u32, bytes: u32) -> Reservation {
    if !configuration(slots, bitmap, base, granules) { return Reservation { status: 4 }; }
    let rounded, ok = layout::checked_align(bytes, 4096);
    if !ok { return Reservation { status: 1 }; }
    var chosen: i64 = -1;
    for slot, i in slots {
        if slot.state > 4 { return Reservation { status: 4 }; }
        if slot.state == 0 {
            if slot.generation == 4294967295 { return Reservation { status: 4 }; }
            chosen = i;
            break;
        }
    }
    if chosen < 0 { return Reservation { status: 2 }; }
    let needed = rounded / 4096;
    var begin: u32 = 0;
    var run: u32 = 0;
    var found = needed == 0;
    if !found {
        for g in granules {
            if occupied(bitmap, g) { run = 0; }
            else {
                if run == 0 { begin = g; }
                run += 1;
                if run == needed { found = true; break; }
            }
        }
    }
    if !found { return Reservation { status: 3 }; }
    var address: u32 = 0;
    if needed != 0 { address = base + begin * 4096; }
    let next_generation = slots[chosen].generation + 1;
    for offset in needed { set_granule(bitmap, begin + offset, true); }
    slots[chosen] = Slot { base: address, requested: bytes, rounded: rounded,
                           generation: next_generation, state: 1 };
    return Reservation { slot: (chosen + 1) as u32, generation: next_generation };
}
fn valid_open(slots: Slot[:], slot: u32, generation: u32) -> bool {
    if slot == 0 || slot > slots.len || generation == 0 { return false; }
    let entry = slots[slot - 1];
    return entry.state == 1 && entry.generation == generation;
}
fn valid_state(slots: Slot[:], slot: u32, generation: u32, state: u32) -> bool {
    if slot == 0 || slot > slots.len || generation == 0 { return false; }
    let entry = slots[slot - 1];
    return entry.state == state && entry.generation == generation;
}
fn valid_placement(slots: Slot[:], slot: u32, generation: u32) -> bool {
    if slot == 0 || slot > slots.len || generation == 0 { return false; }
    let entry = slots[slot - 1];
    return (entry.state == 1 || entry.state == 4) && entry.generation == generation;
}
// Internal invariant check before using a slot's stored backing extent.
// This is constant time; the bitmap/slot consistency is a trusted invariant.
fn valid_extent(entry: Slot, base: u32, granules: u32) -> bool {
    if entry.top > entry.requested || entry.requested > entry.rounded || entry.rounded % 4096 != 0 { return false; }
    if (entry.state == 2 || entry.state == 4) && (entry.requested < 256 || entry.top < 256) { return false; }
    let expected, ok = layout::checked_align(entry.requested, 4096);
    if !ok || expected != entry.rounded { return false; }
    if entry.rounded == 0 { return entry.base == 0; }
    if entry.base < base || (entry.base - base) % 4096 != 0 { return false; }
    let first = (entry.base - base) / 4096;
    let count = entry.rounded / 4096;
    if first > granules || count > granules - first { return false; }
    return true;
}

// Plain destination placement. The caller must supply the validated exact
// Plain stride (0 for Unit, otherwise a multiple of four at most 64) and must
// own the unique frontier; the returned address alone grants no authority.
fn try_alloc(slots: Slot[:], bitmap: u32[:], base: u32, granules: u32,
             slot: u32, generation: u32, stride: u32, count: u32) -> Placement {
    if !configuration(slots, bitmap, base, granules) || !valid_placement(slots, slot, generation) { return Placement { status: 3 }; }
    let entry = slots[slot - 1];
    if !valid_extent(entry, base, granules) || stride > 64 || stride % 4 != 0 { return Placement { status: 3 }; }
    let bytes, ok = layout::checked_mul(count, stride);
    if !ok { return Placement { status: 1 }; }
    if stride == 0 { return Placement {}; }
    let aligned, align_ok = layout::checked_align(entry.top, 4);
    if !align_ok { return Placement { status: 1 }; }
    if aligned > entry.requested || bytes > entry.requested - aligned { return Placement { status: 2 }; }
    let address, address_ok = layout::checked_add(entry.base, aligned);
    if !address_ok { return Placement { status: 3 }; }
    // aligned + bytes is bounded above by requested, already checked.
    slots[slot - 1].top = aligned + bytes;
    return Placement { data: address };
}

// The caller must have ended the frontier and every descendant loan. The
// model cannot establish that precondition from a physical handle.
fn reset(slots: Slot[:], bitmap: u32[:], base: u32, granules: u32, slot: u32, generation: u32) -> bool {
    if !configuration(slots, bitmap, base, granules) || !valid_open(slots, slot, generation) { return false; }
    if !valid_extent(slots[slot - 1], base, granules) { return false; }
    slots[slot - 1].top = 0;
    return true;
}
fn release_state(slots: Slot[:], bitmap: u32[:], base: u32, granules: u32,
                 slot: u32, generation: u32, state: u32) -> bool {
    if !configuration(slots, bitmap, base, granules) || !valid_state(slots, slot, generation, state) { return false; }
    let entry = slots[slot - 1];
    if !valid_extent(entry, base, granules) { return false; }
    if entry.rounded != 0 {
        let first = (entry.base - base) / 4096;
        let count = entry.rounded / 4096;
        // Validate the complete run before clearing any part of it.
        for i in count { if !occupied(bitmap, first + i) { return false; } }
        for i in count { set_granule(bitmap, first + i, false); }
    }
    slots[slot - 1].state = if generation == 4294967295 { 3 } else { 0 };
    return true;
}
fn close(slots: Slot[:], bitmap: u32[:], base: u32, granules: u32, slot: u32, generation: u32) -> bool {
    return release_state(slots, bitmap, base, granules, slot, generation, 1);
}

// Initial construction is transactional: overflow, lack of a reusable slot,
// or lack of backing cannot publish a partial owner or alter prior state.
// The caller retains the affine construction token, rather than a RegionOwner.
fn owned_begin(slots: Slot[:], bitmap: u32[:], base: u32, granules: u32, work_bytes: u32) -> Reservation {
    if !configuration(slots, bitmap, base, granules) { return Reservation { status: 4 }; }
    let requested, ok = layout::checked_add(256, work_bytes);
    if !ok { return Reservation { status: 1 }; }
    let result = reserve(slots, bitmap, base, granules, requested);
    if result.status != 0 { return result; }
    slots[result.slot - 1].top = 256;
    slots[result.slot - 1].state = 4;
    return result;
}

// Prepare a value, not the actual capsule or owner state. Before
// a future seal may publish it, independently checked evidence must establish
// root type/validity, schema, closedness, loans, and affine cleanup. This
// routine does not produce that evidence and cannot transition to SealedOwned.
struct Capsule { valid: bool = false, bytes: u8[256] = [0; 256] }
fn prepare_capsule(root_words: u32, root_bytes: u8[:]) -> Capsule {
    var result = Capsule {};
    if root_words > 64 || root_bytes.len != root_words * 4 { return result; }
    for byte, i in root_bytes { result.bytes[i] = byte; }
    result.valid = true;
    return result;
}

// The caller must have ended all local descendants and the frontier. Sealed
// close similarly requires all owned.open loans to have ended; the raw handle
// alone cannot establish either precondition.
fn owned_abort(slots: Slot[:], bitmap: u32[:], base: u32, granules: u32, slot: u32, generation: u32) -> bool {
    return release_state(slots, bitmap, base, granules, slot, generation, 4);
}
fn owned_close(slots: Slot[:], bitmap: u32[:], base: u32, granules: u32, slot: u32, generation: u32) -> bool {
    return release_state(slots, bitmap, base, granules, slot, generation, 2);
}
