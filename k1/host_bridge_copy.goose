// Executable, bounded M12 lifecycle experiment for one concrete U32 array
// export. It is not a generated bridge, a source authority, or a complete
// K1 ABI. State, the callable and fault injection belong to this test model.
// The host must treat these buffers as private during a call. The semantic
// compiler must establish the effects, brands, callable and loan contracts.
namespace host_bridge_copy;
import host_bridge;
import pool;
import builder;

struct State {
    ingress: u8[128] = [0; 128],
    egress: u8[128] = [0; 128],
    memory: u8[8192] = [0; 8192],
    slots: pool::Slot[1] = [pool::Slot {}; 1],
    bitmap: u32[1] = [0; 1],
    busy: bool = false,
    frames: u32 = 0,
    calls: u32 = 0
}
fn put_word(bytes: u8[:], pos: i64, value: u32) {
    for i in 4 { bytes[pos + i] = (value >> (8 * i) & 255) as u8; }
}
fn publish(state: State&, status: u32, payload: u32, required: u32, items: u32, detail: u32) {
    put_word(state.egress, 0, 0x4b310001);
    put_word(state.egress, 4, 17);
    put_word(state.egress, 8, status);
    put_word(state.egress, 12, payload);
    put_word(state.egress, 16, required);
    put_word(state.egress, 20, items);
    put_word(state.egress, 24, detail);
    put_word(state.egress, 28, 0);
}
fn finish(state: State&, status: u32, payload: u32, required: u32, items: u32, detail: u32,
          slot: u32, generation: u32, old_frames: u32) -> u32 {
    if slot != 0 {
        // This concrete model has no outstanding nested loans at this point.
        assert(pool::close(state.slots, state.bitmap, 4096, 1, slot, generation));
    }
    state.frames = old_frames;
    publish(state, status, payload, required, items, detail);
    state.busy = false;
    return status;
}
// The fixture callable consumes one immutable copied U32 view and an output
// destination. It returns the result view obtained by xor with the fixed U32
// mask. fault=1 injects reservation failure, 2 frame failure, 3 a language
// error after the sole invocation. These injections are fixture controls.
fn invoke(state: State&, export_id: u32, input_bytes: u32, output_capacity: u32, fault: u32) -> u32 {
    if state.busy { return 4; } // no state/window writes
    state.busy = true;
    let old_frames = state.frames;
    let m = host_bridge::Manifest { export_id: 17, ingress_bytes: 128, egress_bytes: 128,
        output_kind: 1, output_capacity: 4, result_max_count: 4, required_domain_mask: 1,
        work_bytes: 32, output_items_are_count: true };
    let fields: host_bridge::Field[] = [host_bridge::Field { kind: 1 },
        host_bridge::Field { role: 1, kind: 1, max_count: 4, domain_binder: 1 }];
    let predicates: host_bridge::Predicate[] = [];
    let checked = host_bridge::inspect(m, fields, predicates, state.ingress, export_id, input_bytes, output_capacity, false);
    if checked.status != 0 { return finish(state, 1, 0, 0, 0, 0, 0, 0, old_frames); }
    if fault == 2 || state.frames == 4294967295 { return finish(state, 5, 0, 0, 0, 0, 0, 0, old_frames); }
    state.frames += 1;
    if fault == 1 { return finish(state, 3, 0, 0, 0, 1, 0, 0, old_frames); }
    let reservation = pool::reserve(state.slots, state.bitmap, 4096, 1, m.work_bytes);
    if reservation.status != 0 { return finish(state, 3, 0, 0, 0, reservation.status as u32, 0, 0, old_frames); }
    let slot = reservation.slot;
    let generation = reservation.generation;
    let input = pool::try_alloc(state.slots, state.bitmap, 4096, 1, slot, generation, 4, 4);
    let output = pool::try_alloc(state.slots, state.bitmap, 4096, 1, slot, generation, 4, 4);
    assert(input.status == 0 && output.status == 0 && input.data != output.data);
    let mask = host_bridge::word(state.ingress, 32);
    let count = host_bridge::word(state.ingress, 36);
    let offset = host_bridge::word(state.ingress, 40);
    var clock = builder::Clock {};
    var in_builder = builder::Cell {};
    var out_builder = builder::Cell {};
    let started = builder::begin(in_builder, clock, state.memory, input.data, count, 1, 1);
    assert(started.status == 0);
    var handle = started.handle;
    for i in count {
        let begin = 32 + offset as i64 + i as i64 * 4;
        let next = builder::try_append(in_builder, handle, state.memory, state.ingress[begin..begin + 4]);
        assert(next.status == 0); handle = next.handle;
    }
    let frozen = builder::freeze(in_builder, handle, clock, state.memory);
    assert(frozen.status == 0 && frozen.length == count);
    let dest = builder::begin(out_builder, clock, state.memory, output.data, 4, 1, 1);
    assert(dest.status == 0);
    var out_handle = dest.handle;
    // Test telemetry saturates; it must never make a valid invocation trap.
    if state.calls != 4294967295 { state.calls += 1; }
    if fault == 3 {
        assert(builder::discard(out_builder, out_handle).status == 0);
        return finish(state, 6, 0, 0, 0, 1, slot, generation, old_frames);
    }
    for i in count {
        let word = host_bridge::word(state.memory, frozen.data as i64 + i as i64 * 4) ^ mask;
        var bytes: u8[4] = [0; 4];
        put_word(bytes, 0, word);
        let appended = builder::try_append(out_builder, out_handle, state.memory, bytes);
        assert(appended.status == 0); out_handle = appended.handle;
    }
    let result = builder::freeze(out_builder, out_handle, clock, state.memory);
    assert(result.status == 0 && result.length == count);
    let plan = host_bridge::output(m, fields, predicates, count, output_capacity);
    if plan.status == 2 { return finish(state, 2, 0, plan.required_bytes, plan.item_count, 0, slot, generation, old_frames); }
    assert(plan.status == 0);
    // Construct all payload bytes before publishing Ok. Prior payload bytes
    // remain physically present on failures but no failure advertises them.
    put_word(state.egress, 32, count);
    put_word(state.egress, 36, 8);
    for i in count as i64 * 4 { state.egress[40 + i] = state.memory[result.data + i]; }
    return finish(state, 0, plan.payload_bytes, plan.required_bytes, plan.item_count, 0, slot, generation, old_frames);
}
