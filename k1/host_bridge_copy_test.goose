import pool;
import host_bridge_copy;

fn read32(bytes: u8[:], pos: i64) -> u32 {
    return bytes[pos] as u32 | (bytes[pos + 1] as u32 << 8) | (bytes[pos + 2] as u32 << 16) | (bytes[pos + 3] as u32 << 24);
}
fn write32(bytes: u8[:], pos: i64, value: u32) {
    for i in 4 { bytes[pos + i] = (value >> (8 * i) & 255) as u8; }
}
fn init(state: host_bridge_copy::State&, count: u32) {
    for i in 128 { state.ingress[i] = 0; state.egress[i] = 0xa5; }
    write32(state.ingress, 0, 0x4b310001); write32(state.ingress, 4, 17);
    write32(state.ingress, 12, 12 + count * 4);
    write32(state.ingress, 32, 0x80000001);
    write32(state.ingress, 36, count); write32(state.ingress, 40, 12);
    for i in count { write32(state.ingress, 44 + i as i64 * 4, 11 + i as u32); }
}
fn header(state: host_bridge_copy::State&, status: u32, payload: u32, required: u32, count: u32, detail: u32) {
    assert(read32(state.egress, 0) == 0x4b310001);
    assert(read32(state.egress, 4) == 17);
    assert(read32(state.egress, 8) == status);
    assert(read32(state.egress, 12) == payload);
    assert(read32(state.egress, 16) == required);
    assert(read32(state.egress, 20) == count);
    assert(read32(state.egress, 24) == detail);
    assert(read32(state.egress, 28) == 0);
}
fn clean(state: host_bridge_copy::State&) {
    assert(!state.busy && state.frames == 7 && state.slots[0].state == 0 && state.bitmap[0] == 0);
}
fn main() {
    var state = host_bridge_copy::State {};
    state.frames = 7;
    init(state, 4);
    let original = copy(state.ingress);
    assert(host_bridge_copy::invoke(state, 17, 60, 24, 0) == 0);
    clean(state); header(state, 0, 24, 24, 4, 0);
    assert(state.ingress[..] == original[..]);
    assert(read32(state.egress, 32) == 4 && read32(state.egress, 36) == 8);
    for i in 4 { assert(read32(state.egress, 40 + i * 4) == ((11 + i as u32) ^ 0x80000001)); }
    assert(state.calls == 1);
    // Successful host copies can outlive later reuse of the guest output.
    let host_copy = copy(state.egress);
    init(state, 1);
    assert(host_bridge_copy::invoke(state, 17, 48, 12, 0) == 0);
    clean(state); header(state, 0, 12, 12, 1, 0);
    assert(read32(host_copy, 32) == 4 && read32(host_copy, 52) == (14 ^ 0x80000001));
    assert(state.calls == 2);
    // No error status publishes or overwrites any payload byte.
    for fault in 1..4 {
        init(state, 4);
        let before = copy(state.egress);
        let calls = state.calls;
        let expected = if fault == 1 { 3 } else if fault == 2 { 5 } else { 6 };
        let detail = if fault == 2 { 0 } else { 1 };
        assert(host_bridge_copy::invoke(state, 17, 60, 24, fault as u32) == expected);
        clean(state); header(state, expected as u32, 0, 0, 0, detail as u32);
        assert(state.egress[32..] == before[32..]);
        assert(state.calls == calls + (if fault == 3 { 1 } else { 0 }));
    }
    init(state, 4);
    let old_payload = copy(state.egress);
    let calls = state.calls;
    assert(host_bridge_copy::invoke(state, 17, 60, 23, 0) == 2);
    clean(state); header(state, 2, 0, 24, 4, 0);
    assert(state.egress[32..] == old_payload[32..] && state.calls == calls + 1);
    // Reentry returns Busy without touching any state or window.
    state.busy = true;
    let before_ingress = copy(state.ingress);
    let before_egress = copy(state.egress);
    let before_calls = state.calls;
    assert(host_bridge_copy::invoke(state, 0, 0, 500, 0) == 4);
    assert(state.busy && state.frames == 7 && state.calls == before_calls);
    assert(state.ingress[..] == before_ingress[..] && state.egress[..] == before_egress[..]);
    state.busy = false;
    // Validated descriptors gate all memory operations and invocation.
    for pos in [0, 4, 8, 12, 16, 20, 24, 28, 36, 40] {
        init(state, 4); state.ingress[pos] ^= 0xff;
        let payload = copy(state.egress); let seen = state.calls;
        assert(host_bridge_copy::invoke(state, 17, 60, 24, 0) == 1);
        clean(state); header(state, 1, 0, 0, 0, 0);
        assert(state.egress[32..] == payload[32..] && state.calls == seen);
    }
    init(state, 0);
    assert(host_bridge_copy::invoke(state, 17, 44, 8, 0) == 0);
    clean(state); header(state, 0, 8, 8, 0, 0);
    assert(read32(state.egress, 32) == 0 && read32(state.egress, 36) == 8);
    init(state, 4);
    let previous = state.calls;
    assert(host_bridge_copy::invoke(state, 18, 60, 24, 0) == 1);
    assert(host_bridge_copy::invoke(state, 17, 59, 24, 0) == 1);
    assert(host_bridge_copy::invoke(state, 17, 60, 97, 0) == 1);
    clean(state); assert(state.calls == previous);
    // A real exhausted slot rejects reservation without modifying the other
    // live reservation; frame and busy state are restored.
    let occupied = pool::reserve(state.slots, state.bitmap, 4096, 1, 4);
    assert(occupied.status == 0);
    init(state, 1);
    let kept_slot = state.slots[0]; let kept_bitmap = state.bitmap[0]; let old_calls = state.calls;
    assert(host_bridge_copy::invoke(state, 17, 48, 12, 0) == 3);
    assert(!state.busy && state.frames == 7 && state.calls == old_calls && state.bitmap[0] == kept_bitmap);
    assert(state.slots[0].state == kept_slot.state && state.slots[0].generation == kept_slot.generation && state.slots[0].requested == kept_slot.requested);
    header(state, 3, 0, 0, 0, 2);
    assert(pool::close(state.slots, state.bitmap, 4096, 1, occupied.slot, occupied.generation));
    clean(state);
    // Cross-check a range of data and capacities using a decoder independent
    // of the bridge's own parser. Retries are separate callable executions.
    for n in 5 {
        for available in 25 {
            init(state, n as u32);
            let mask = 0x31415926 as u32 ^ (n as u32 * 17);
            write32(state.ingress, 32, mask);
            let was_called = state.calls;
            let got = host_bridge_copy::invoke(state, 17, 44 + n as u32 * 4, available as u32, 0);
            let needed = 8 + n as u32 * 4;
            if available < needed {
                assert(got == 2); header(state, 2, 0, needed, n as u32, 0);
                for i in 32..128 { assert(state.egress[i] == 0xa5); }
            } else {
                assert(got == 0); header(state, 0, needed, needed, n as u32, 0);
                assert(read32(state.egress, 32) == n && read32(state.egress, 36) == 8);
                for i in n { assert(read32(state.egress, 40 + i * 4) == ((11 + i as u32) ^ mask)); }
            }
            assert(state.calls == was_called + 1); clean(state);
        }
    }
    state.calls = 4294967295;
    init(state, 1);
    assert(host_bridge_copy::invoke(state, 17, 48, 12, 0) == 0);
    assert(state.calls == 4294967295); clean(state);
    print("private copied host bridge lifecycle passed");
}
