import pool;

fn main() {
    var slots: pool::Slot[4] = [pool::Slot {}; 4];
    var bits: u32[1] = [0];
    let a = pool::reserve(slots, bits, 4096, 6, 4096);
    let b = pool::reserve(slots, bits, 4096, 6, 8192);
    let c = pool::reserve(slots, bits, 4096, 6, 4096);
    assert(a.status == 0 && a.slot == 1 && a.generation == 1 && slots[0].base == 4096);
    assert(b.status == 0 && b.slot == 2 && slots[1].base == 8192);
    assert(c.status == 0 && c.slot == 3 && slots[2].base == 16384);
    assert(bits[0] == 15);
    assert(pool::close(slots, bits, 4096, 6, b.slot, b.generation));
    assert(bits[0] == 9 && slots[1].state == 0);
    // Two free runs of two granules cannot satisfy a request for three.
    let bitmap_before = bits[0];
    let generation_before = slots[1].generation;
    let fragmented = pool::reserve(slots, bits, 4096, 6, 12288);
    assert(fragmented.status == 3 && bits[0] == bitmap_before);
    assert(slots[1].state == 0 && slots[1].generation == generation_before);
    // Lowest slot and first run are reused; old handle becomes stale.
    let reused = pool::reserve(slots, bits, 4096, 6, 4097);
    assert(reused.status == 0 && reused.slot == 2 && reused.generation == 2);
    assert(slots[1].base == 8192 && slots[1].requested == 4097 && slots[1].rounded == 8192);
    assert(!pool::close(slots, bits, 4096, 6, b.slot, b.generation));
    assert(bits[0] == 15);

    var short_slots: pool::Slot[1] = [pool::Slot {}];
    var short_bits: u32[1] = [0];
    let s = pool::reserve(short_slots, short_bits, 4096, 2, 13);
    assert(s.status == 0 && short_slots[0].requested == 13);
    let first = pool::try_alloc(short_slots, short_bits, 4096, 2, s.slot, s.generation, 4, 2);
    assert(first.status == 0 && first.data == 4096 && short_slots[0].top == 8);
    let second = pool::try_alloc(short_slots, short_bits, 4096, 2, s.slot, s.generation, 4, 1);
    assert(second.status == 0 && second.data == 4104 && short_slots[0].top == 12);
    let full = pool::try_alloc(short_slots, short_bits, 4096, 2, s.slot, s.generation, 4, 1);
    assert(full.status == 2 && short_slots[0].top == 12 && short_bits[0] == 1);
    let overflow = pool::try_alloc(short_slots, short_bits, 4096, 2, s.slot, s.generation, 64, 4294967295);
    assert(overflow.status == 1 && short_slots[0].top == 12);
    let zero = pool::try_alloc(short_slots, short_bits, 4096, 2, s.slot, s.generation, 0, 4294967295);
    assert(zero.status == 0 && zero.data == 0 && short_slots[0].top == 12);
    let invalid_stride = pool::try_alloc(short_slots, short_bits, 4096, 2, s.slot, s.generation, 3, 1);
    assert(invalid_stride.status == 3 && short_slots[0].top == 12);
    assert(!pool::reset(short_slots, short_bits, 4096, 2, 0, s.generation));
    assert(pool::reset(short_slots, short_bits, 4096, 2, s.slot, s.generation));
    assert(short_slots[0].top == 0 && short_slots[0].generation == s.generation && short_bits[0] == 1);
    assert(pool::close(short_slots, short_bits, 4096, 2, s.slot, s.generation));
    assert(short_bits[0] == 0 && short_slots[0].state == 0);
    assert(!pool::reset(short_slots, short_bits, 4096, 2, s.slot, s.generation));

    // Zero-byte reservations take a slot without consuming a granule.
    let empty = pool::reserve(short_slots, short_bits, 4096, 2, 0);
    assert(empty.status == 0 && empty.generation == 2 && short_slots[0].base == 0 && short_bits[0] == 0);
    let empty_unit = pool::try_alloc(short_slots, short_bits, 4096, 2, empty.slot, empty.generation, 0, 7);
    assert(empty_unit.status == 0 && empty_unit.data == 0 && short_slots[0].top == 0);
    let no_capacity = pool::try_alloc(short_slots, short_bits, 4096, 2, empty.slot, empty.generation, 4, 1);
    assert(no_capacity.status == 2 && short_slots[0].top == 0);
    // SizeOverflow wins over NoOwnerSlots; failure cannot mutate state.
    let too_large = pool::reserve(short_slots, short_bits, 4096, 2, 4294967295);
    assert(too_large.status == 1 && short_slots[0].state == 1 && short_slots[0].generation == 2);
    let no_slots = pool::reserve(short_slots, short_bits, 4096, 2, 0);
    assert(no_slots.status == 2 && short_bits[0] == 0);
    assert(pool::close(short_slots, short_bits, 4096, 2, empty.slot, empty.generation));

    // A max-generation close retires permanently, without wrapping.
    short_slots[0].generation = 4294967294;
    let last = pool::reserve(short_slots, short_bits, 4096, 2, 1);
    assert(last.status == 0 && last.generation == 4294967295);
    assert(pool::close(short_slots, short_bits, 4096, 2, last.slot, last.generation));
    assert(short_slots[0].state == 3 && short_slots[0].generation == 4294967295 && short_bits[0] == 0);
    assert(pool::reserve(short_slots, short_bits, 4096, 2, 1).status == 2);

    // Malformed configuration and damaged bitmaps are implementation faults;
    // close verifies the whole run before clearing any occupied bit.
    var fault_slots: pool::Slot[1] = [pool::Slot {}];
    var fault_bits: u32[1] = [0];
    assert(pool::reserve(fault_slots, fault_bits, 1, 2, 1).status == 4);
    let fault = pool::reserve(fault_slots, fault_bits, 4096, 2, 8192);
    assert(fault.status == 0 && fault_bits[0] == 3);
    fault_bits[0] = 1;
    assert(!pool::close(fault_slots, fault_bits, 4096, 2, fault.slot, fault.generation));
    assert(fault_bits[0] == 1 && fault_slots[0].state == 1);
    // Impossible extent/top and a forged state must fail before mutation.
    fault_slots[0].top = 8193;
    assert(pool::try_alloc(fault_slots, fault_bits, 4096, 2, fault.slot, fault.generation, 4, 1).status == 3);
    assert(!pool::reset(fault_slots, fault_bits, 4096, 2, fault.slot, fault.generation));
    assert(fault_slots[0].top == 8193 && fault_bits[0] == 1);
    fault_slots[0].state = 5;
    assert(pool::reserve(fault_slots, fault_bits, 4096, 2, 1).status == 4);
    assert(fault_slots[0].state == 5 && fault_bits[0] == 1);
    var exhausted_slots: pool::Slot[1] = [pool::Slot { generation: 4294967295 }];
    var exhausted_bits: u32[1] = [0];
    assert(pool::reserve(exhausted_slots, exhausted_bits, 4096, 2, 0).status == 4);
    assert(exhausted_slots[0].generation == 4294967295 && exhausted_slots[0].state == 0 && exhausted_bits[0] == 0);

    // BuildingOwned can place in its working tail, but ordinary reset/close
    // cannot consume the construction token. This model cannot certify
    // payload validity, lifetime, loan, or authority preconditions.
    var owned_slots: pool::Slot[1] = [pool::Slot {}];
    var owned_bits: u32[1] = [0];
    let owned = pool::owned_begin(owned_slots, owned_bits, 4096, 2, 4);
    assert(owned.status == 0 && owned_slots[0].requested == 260 &&
           owned_slots[0].rounded == 4096 && owned_slots[0].top == 256);
    let owned_place = pool::try_alloc(owned_slots, owned_bits, 4096, 2, owned.slot, owned.generation, 4, 1);
    assert(owned_place.status == 0 && owned_place.data == 4352 && owned_slots[0].top == 260);
    assert(!pool::reset(owned_slots, owned_bits, 4096, 2, owned.slot, owned.generation));
    assert(!pool::close(owned_slots, owned_bits, 4096, 2, owned.slot, owned.generation));
    assert(owned_slots[0].state == 4 && owned_bits[0] == 1);
    assert(pool::owned_begin(owned_slots, owned_bits, 4096, 2, 4294967295).status == 1);
    assert(pool::owned_begin(owned_slots, owned_bits, 4096, 2, 4294963200).status == 1); // rounding overflow
    assert(pool::owned_begin(owned_slots, owned_bits, 4096, 2, 0).status == 2);
    assert(owned_slots[0].state == 4 && owned_slots[0].top == 260 && owned_bits[0] == 1);
    assert(!pool::owned_abort(owned_slots, owned_bits, 4096, 2, owned.slot, owned.generation + 1));
    assert(owned_slots[0].state == 4 && owned_bits[0] == 1);
    assert(pool::owned_abort(owned_slots, owned_bits, 4096, 2, owned.slot, owned.generation));
    assert(owned_slots[0].state == 0 && owned_bits[0] == 0);
    // Zero working bytes still reserve a full root capsule and one granule.
    let zero_owned = pool::owned_begin(owned_slots, owned_bits, 4096, 2, 0);
    assert(zero_owned.status == 0 && owned_slots[0].requested == 256 &&
           owned_slots[0].top == 256 && owned_bits[0] == 1);
    assert(!pool::owned_close(owned_slots, owned_bits, 4096, 2, zero_owned.slot, zero_owned.generation));
    assert(pool::owned_abort(owned_slots, owned_bits, 4096, 2, zero_owned.slot, zero_owned.generation));

    let root: u8[] = [7, 11, 12, 13, 14, 15, 16, 17];
    let capsule = pool::prepare_capsule(2, root);
    assert(capsule.valid && capsule.bytes[0] == 7 && capsule.bytes[7] == 17);
    for j in 8..256 { assert(capsule.bytes[j] == 0); }
    assert(!pool::prepare_capsule(1, root).valid);
    assert(!pool::prepare_capsule(65, root).valid);
    let no_root: u8[] = [];
    let empty_capsule = pool::prepare_capsule(0, no_root);
    assert(empty_capsule.valid);
    for byte in empty_capsule.bytes { assert(byte == 0); }
    // This is only a release-helper fault fixture: directly forging the state
    // does not stand in for the required checked seal implementation.
    let release_fixture = pool::owned_begin(owned_slots, owned_bits, 4096, 2, 0);
    owned_slots[0].state = 2;
    assert(!pool::owned_abort(owned_slots, owned_bits, 4096, 2, release_fixture.slot, release_fixture.generation));
    assert(!pool::owned_close(owned_slots, owned_bits, 4096, 2, release_fixture.slot, release_fixture.generation + 1));
    assert(pool::owned_close(owned_slots, owned_bits, 4096, 2, release_fixture.slot, release_fixture.generation));
    assert(owned_slots[0].state == 0 && owned_bits[0] == 0);

    // First-fit and cleanup cross 32-granule bitmap-word boundaries.
    var cross_slots: pool::Slot[2] = [pool::Slot {}; 2];
    var cross_bits: u32[3] = [0; 3];
    let before_boundary = pool::reserve(cross_slots, cross_bits, 4096, 65, 31 * 4096);
    let cross = pool::reserve(cross_slots, cross_bits, 4096, 65, 3 * 4096);
    assert(before_boundary.status == 0 && cross.status == 0 && cross_slots[1].base == 32 * 4096);
    assert(cross_bits[0] == 4294967295 && cross_bits[1] == 3 && cross_bits[2] == 0);
    assert(pool::close(cross_slots, cross_bits, 4096, 65, cross.slot, cross.generation));
    assert(cross_bits[0] == 2147483647 && cross_bits[1] == 0 && cross_bits[2] == 0);
    print("pool state laws passed");
}
