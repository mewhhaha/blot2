// Standalone scalar initialized-prefix state model, not a source authority or
// an emitted runtime. The caller must establish a unique exclusive destination,
// one consistent memory identity, correct region lifetime, no live conflicting
// loans, and affine consumption. Raw data pointers or these model records do
// not prove those obligations. Callers use a single Clock for an entire model
// lifetime; independent clocks cannot establish distinct identities. Handles
// here are model-local version stamps; malformed/forged records are internal
// faults, never storage authority.
namespace builder;
import layout;

// Kinds: 0 Unit, 1 U32, 2 F32, 3 Bool. Modes: 1 Append, 2 Resize.
// Cell states: 0 unused, 1 live Append, 2 live Resize, 3 frozen, 4 discarded.
struct Clock { next: u64 = 0 }
struct Handle { identity: u64 = 0, version: u64 = 0 }
struct Cell {
    identity: u64 = 0, version: u64 = 0, state: u32 = 0,
    data: u32 = 0, length: u32 = 0, capacity: u32 = 0, kind: u32 = 0
}
struct Outcome {
    // 0 success, 1 full, 2 invalid/stale model handle,
    // 3 bad index/mode, 4 invalid scalar, 5 model stamp exhaustion,
    // 6 malformed physical range or descriptor.
    status: i64 = 0, handle: Handle = Handle {}
}
struct Reading { status: i64 = 0, bytes: u8[4] = [0; 4], size: u32 = 0 }
struct Frozen { status: i64 = 0, data: u32 = 0, length: u32 = 0, domain: u64 = 0 }

fn scalar_size(kind: u32) -> u32 { if kind == 0 { return 0; } return 4; }
fn valid_scalar(kind: u32, value: u8[:]) -> bool {
    if kind > 3 || value.len != scalar_size(kind) { return false; }
    if kind == 3 {
        return (value[0] == 0 || value[0] == 1) && value[1] == 0 && value[2] == 0 && value[3] == 0;
    }
    return true;
}
fn live(cell: Cell&, handle: Handle) -> bool {
    return (cell.state == 1 || cell.state == 2) && cell.identity != 0 &&
        cell.version != 0 && cell.identity == handle.identity && cell.version == handle.version;
}
fn range_ok(data: u32, count: u32, size: u32, memory: u8[:]) -> bool {
    if size == 0 { return data == 0; }
    if data % 4 != 0 || (count != 0 && data == 0) { return false; }
    let extent, ok = layout::checked_mul(count, size);
    if !ok { return false; }
    let end, add_ok = layout::checked_add(data, extent);
    return add_ok && end <= 1073741824 && end <= memory.len;
}
// Fresh identity is for deterministic model tests only. The semantic checker
// must introduce actual distinct regions/domains; a number is not a domain proof.
fn fresh(clock: Clock&) -> u64, bool {
    if clock.next == 18446744073709551615 { return 0, false; }
    clock.next += 1;
    return clock.next, true;
}
fn begin(cell: Cell&, clock: Clock&, memory: u8[:], data: u32, capacity: u32,
         kind: u32, mode: u32) -> Outcome {
    if cell.state == 1 || cell.state == 2 { return Outcome { status: 2 }; }
    if cell.state > 4 || (cell.state == 0 && (cell.identity != 0 || cell.version != 0)) ||
       ((cell.state == 3 || cell.state == 4) && (cell.identity == 0 || cell.version == 0)) { return Outcome { status: 6 }; }
    if kind > 3 || (mode != 1 && mode != 2) { return Outcome { status: 6 }; }
    if !range_ok(data, capacity, scalar_size(kind), memory) { return Outcome { status: 6 }; }
    let id, ok = fresh(clock);
    if !ok { return Outcome { status: 5 }; }
    cell = Cell { identity: id, version: 1, state: mode, data: data, capacity: capacity, kind: kind };
    return Outcome { handle: Handle { identity: id, version: 1 } };
}
// Validate the whole source scalar before touching memory. Successful append
// writes every byte, then publishes n+1; full/invalid outcomes leave n, bytes,
// and handle unchanged. `value` can overlap the destination: snapshot first.
fn try_append(cell: Cell&, handle: Handle, memory: u8[:], value: u8[:]) -> Outcome {
    if !live(cell, handle) { return Outcome { status: 2, handle: handle }; }
    if cell.kind > 3 || cell.length > cell.capacity || !range_ok(cell.data, cell.capacity, scalar_size(cell.kind), memory) { return Outcome { status: 6, handle: handle }; }
    if !valid_scalar(cell.kind, value) { return Outcome { status: 4, handle: handle }; }
    if cell.length == cell.capacity { return Outcome { status: 1, handle: handle }; }
    if cell.version == 18446744073709551615 { return Outcome { status: 5, handle: handle }; }
    var snapshot: u8[4] = [0; 4];
    for byte, i in value { snapshot[i] = byte; }
    if cell.kind != 0 {
        let offset = cell.data + cell.length * 4; // range_ok proved this is in bounds
        for i in 4 { memory[offset + i] = snapshot[i]; }
    }
    cell.length += 1;
    cell.version += 1;
    return Outcome { handle: Handle { identity: cell.identity, version: cell.version } };
}
fn set(cell: Cell&, handle: Handle, memory: u8[:], index: u32, value: u8[:]) -> Outcome {
    if !live(cell, handle) { return Outcome { status: 2, handle: handle }; }
    if cell.kind > 3 || cell.length > cell.capacity || !range_ok(cell.data, cell.capacity, scalar_size(cell.kind), memory) { return Outcome { status: 6, handle: handle }; }
    if index >= cell.length { return Outcome { status: 3, handle: handle }; }
    if !valid_scalar(cell.kind, value) { return Outcome { status: 4, handle: handle }; }
    if cell.version == 18446744073709551615 { return Outcome { status: 5, handle: handle }; }
    var snapshot: u8[4] = [0; 4];
    for byte, i in value { snapshot[i] = byte; }
    if cell.kind != 0 {
        let offset = cell.data + index * 4;
        for i in 4 { memory[offset + i] = snapshot[i]; }
    }
    cell.version += 1;
    return Outcome { handle: Handle { identity: cell.identity, version: cell.version } };
}
fn read(cell: Cell&, handle: Handle, memory: u8[:], index: u32) -> Reading {
    if !live(cell, handle) { return Reading { status: 2 }; }
    if cell.kind > 3 || cell.length > cell.capacity || !range_ok(cell.data, cell.capacity, scalar_size(cell.kind), memory) { return Reading { status: 6 }; }
    if index >= cell.length { return Reading { status: 3 }; }
    var result = Reading { size: scalar_size(cell.kind) };
    if cell.kind != 0 {
        let offset = cell.data + index * 4;
        for i in 4 { result.bytes[i] = memory[offset + i]; }
    }
    // Memory is assumed not to be corrupted outside the checked model; reject
    // invalid Bool bits if an untrusted test tampers with it nevertheless.
    if !valid_scalar(cell.kind, result.bytes[0..result.size]) { return Reading { status: 4 }; }
    return result;
}
fn truncate(cell: Cell&, handle: Handle, memory: u8[:], length: u32) -> Outcome {
    if !live(cell, handle) { return Outcome { status: 2, handle: handle }; }
    if cell.kind > 3 || cell.length > cell.capacity || !range_ok(cell.data, cell.capacity, scalar_size(cell.kind), memory) { return Outcome { status: 6, handle: handle }; }
    if cell.state != 2 || length > cell.length { return Outcome { status: 3, handle: handle }; }
    if cell.version == 18446744073709551615 { return Outcome { status: 5, handle: handle }; }
    cell.length = length;
    cell.version += 1;
    return Outcome { handle: Handle { identity: cell.identity, version: cell.version } };
}
// A distinct clock value models fresh-domain introduction; the value must not
// be treated as a runtime tag or as externally forgeable domain authority.
fn freeze(cell: Cell&, handle: Handle, clock: Clock&, memory: u8[:]) -> Frozen {
    if !live(cell, handle) { return Frozen { status: 2 }; }
    if cell.kind > 3 || cell.length > cell.capacity || !range_ok(cell.data, cell.capacity, scalar_size(cell.kind), memory) { return Frozen { status: 6 }; }
    let domain, ok = fresh(clock);
    if !ok { return Frozen { status: 5 }; }
    let data = if cell.length == 0 || cell.kind == 0 { 0 } else { cell.data };
    let length = cell.length;
    cell.state = 3;
    return Frozen { data: data, length: length, domain: domain };
}
fn discard(cell: Cell&, handle: Handle) -> Outcome {
    if !live(cell, handle) { return Outcome { status: 2, handle: handle }; }
    cell.state = 4;
    return Outcome {};
}
