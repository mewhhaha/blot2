// K1-MEM revision 1. Pure checked geometry and executable reference runtime.
// These functions model trusted Wasm helpers; they grant no source authority.
namespace runtime;
import std;

const MAX_U32: u32 = 0xffffffff;
const WORD: u32 = 4;
const PAGE: u32 = 65536;
const GRANULE: u32 = 4096;
const MEMORY_LIMIT: u32 = 0x40000000;
const OWNER_BYTES: u32 = 32;
const CAPSULE_BYTES: u32 = 256;
const ABI_TAG: u32 = 0x4b310001;
const FREE: u32 = 0;
const OPEN: u32 = 1;
const SEALED: u32 = 2;
const RETIRED: u32 = 3;
const BUILDING: u32 = 4;
const SIZE_OVERFLOW: u32 = 0;
const NO_OWNER_SLOTS: u32 = 1;
const NO_CONTIGUOUS_SPACE: u32 = 2;
const NO_SPACE: u32 = 1;
const STATUS_OK: u32 = 0;
const INVALID_INPUT: u32 = 1;
const OUTPUT_TOO_SMALL: u32 = 2;
const RESERVATION_FAILED: u32 = 3;
const BUSY: u32 = 4;
const FRAME_LIMIT: u32 = 5;
const LANGUAGE_ERROR: u32 = 6;

// Diagnostic-only counters. Each is a little-endian pair of U32 words.
// Cumulative counts are U64; byte high-water/current counts are bounded U32.
const TELEMETRY_COUNT: u32 = 13;
const T_RESERVE_ATTEMPTS: u32 = 0;
const T_RESERVE_SUCCESS: u32 = 1;
const T_RESERVE_FAILURE: u32 = 2;
const T_RESETS: u32 = 3;
const T_RELEASES: u32 = 4;
const T_BACKING_LIVE: u32 = 5;
const T_BACKING_HIGH: u32 = 6;
const T_RESULT_HIGH: u32 = 7;
const T_SCRATCH_HIGH: u32 = 8;
const T_INITIALIZED: u32 = 9;
const T_COPIED: u32 = 10;
const T_CALLS: u32 = 11;
const T_LOOPS: u32 = 12;
fn telemetry_name(id:u32)->const u8[:] {
  if id==T_RESERVE_ATTEMPTS { return "backing_reservations"; }
  if id==T_RESERVE_SUCCESS { return "backing_successes"; }
  if id==T_RESERVE_FAILURE { return "backing_failures"; }
  if id==T_RESETS { return "region_resets"; }
  if id==T_RELEASES { return "region_releases"; }
  if id==T_BACKING_LIVE { return "backing_live_bytes"; }
  if id==T_BACKING_HIGH { return "backing_high_water_bytes"; }
  if id==T_RESULT_HIGH { return "result_high_water_bytes"; }
  if id==T_SCRATCH_HIGH { return "scratch_high_water_bytes"; }
  if id==T_INITIALIZED { return "initialized_bytes"; }
  if id==T_COPIED { return "copied_bytes"; }
  if id==T_CALLS { return "source_calls"; }
  if id==T_LOOPS { return "loop_iterations"; }
  return "";
}

struct Config {
  static_bytes: u32 = 0,
  pool_bytes: u32 = 16 * 1024 * 1024,
  owner_slots: u32 = 256,
  frame_bytes: u32 = 1024 * 1024,
  ingress_bytes: u32 = 65536,
  egress_bytes: u32 = 65536,
  telemetry: bool = false,
}

struct MemoryMap {
  static_base: u32 = 0,
  static_bytes: u32 = 0,
  control: u32 = 0,
  owners: u32 = 0,
  owner_slots: u32 = 0,
  bitmap: u32 = 0,
  bitmap_bytes: u32 = 0,
  frame: u32 = 0,
  frame_bytes: u32 = 0,
  ingress: u32 = 0,
  ingress_bytes: u32 = 0,
  egress: u32 = 0,
  egress_bytes: u32 = 0,
  pool: u32 = 0,
  pool_bytes: u32 = 0,
  granules: u32 = 0,
  end: u32 = 0,
  pages: u32 = 0,
}

fn align_checked(value: u32, alignment: u32) -> u32, bool {
  if alignment == 0 || (alignment & (alignment - 1)) != 0 { return 0, false; }
  if value > MAX_U32 - (alignment - 1) { return 0, false; }
  return (value + alignment - 1) & ~(alignment - 1), true;
}

fn make_map(c: Config) -> MemoryMap, bool {
  var m = MemoryMap {};
  if c.owner_slots == 0 || c.owner_slots > 4096 || c.pool_bytes % GRANULE != 0 ||
     c.frame_bytes > 16 * 1024 * 1024 || c.frame_bytes % 4 != 0 ||
     c.ingress_bytes < 32 || c.egress_bytes < 32 ||
     c.ingress_bytes % 4 != 0 || c.egress_bytes % 4 != 0 { return m, false; }
  // Widening here validates configuration; generated runtime arithmetic uses u32.
  var at: u64 = 16; // Address zero and its first words never hold a live object.
  m.static_base = 16;
  m.static_bytes = c.static_bytes;
  at += c.static_bytes;
  at = (at + 3) & ~(3 as u64);
  if at > MEMORY_LIMIT { return m, false; }
  m.control = at as u32;
  at += 16; // busy, frame_top, poison, reserved
  if c.telemetry { at += TELEMETRY_COUNT * 8; }
  m.owners = at as u32;
  m.owner_slots = c.owner_slots;
  at += c.owner_slots as u64 * OWNER_BYTES;
  if at > MEMORY_LIMIT { return m, false; }
  m.bitmap = at as u32;
  m.granules = c.pool_bytes / GRANULE;
  m.bitmap_bytes = ((m.granules + 7) / 8 + 3) & ~(3 as u32);
  at += m.bitmap_bytes;
  if at > MEMORY_LIMIT { return m, false; }
  m.frame = at as u32;
  m.frame_bytes = c.frame_bytes;
  at += c.frame_bytes;
  if at > MEMORY_LIMIT { return m, false; }
  m.ingress = at as u32;
  m.ingress_bytes = c.ingress_bytes;
  at += c.ingress_bytes;
  if at > MEMORY_LIMIT { return m, false; }
  m.egress = at as u32;
  m.egress_bytes = c.egress_bytes;
  at += c.egress_bytes;
  at = (at + GRANULE - 1) & ~(GRANULE as u64 - 1);
  if at > MEMORY_LIMIT { return m, false; }
  m.pool = at as u32;
  m.pool_bytes = c.pool_bytes;
  at += c.pool_bytes;
  if at > MEMORY_LIMIT { return m, false; }
  m.end = at as u32;
  m.pages = ((at + PAGE - 1) / PAGE) as u32;
  return m, true;
}

struct Pool { map: MemoryMap = MemoryMap {}, bytes: u8[>..] = [] }
struct Handle { slot: u32 = 0, generation: u32 = 0 }
struct Reservation { success: bool = false, error: u32 = 0, handle: Handle = Handle {} }
struct Placement { success: bool = false, error: u32 = 0, data: u32 = 0, capacity: u32 = 0 }

fn initialize(p: Pool&, m: MemoryMap) {
  assert(p.bytes.len == 0);
  p.map = m;
  for i in m.pages as i64 * PAGE { p.bytes.push(0); }
}
fn load(p: Pool&, address: u32) -> u32 {
  assert(address % 4 == 0 && address as u64 + 4 <= p.bytes.len as u64);
  let i = address as i64;
  return p.bytes[i] as u32 | (p.bytes[i + 1] as u32 << 8) |
    (p.bytes[i + 2] as u32 << 16) | (p.bytes[i + 3] as u32 << 24);
}
fn store(p: Pool&, address: u32, value: u32) {
  assert(address % 4 == 0 && address as u64 + 4 <= p.bytes.len as u64);
  for i in 4 { p.bytes[address as i64 + i] = (value >> (i * 8)) as! u8; }
}
fn entry(p: Pool&, slot: u32) -> u32 { p.map.owners + (slot - 1) * OWNER_BYTES }
fn valid(p: Pool&, h: Handle, state: u32) -> bool {
  if h.slot == 0 || h.slot > p.map.owner_slots { return false; }
  let e = entry(p, h.slot);
  return load(p, e + 16) == h.generation && load(p, e + 20) == state;
}
fn occupied(p: Pool&, granule: u32) -> bool {
  let byte = p.bytes[(p.map.bitmap + granule / 8) as i64];
  return (byte & ((1 as u8) << (granule % 8))) != 0;
}
fn mark_run(p: Pool&, first: u32, count: u32, used: bool) {
  // At most two partial words; complete words are touched once.
  var position = first;
  var remaining = count;
  while remaining > 0 {
    let bit = position % 32;
    let take = min(remaining, 32 - bit);
    let mask = if take == 32 { MAX_U32 } else { (((1 as u32) << take) - 1) << bit };
    let address = p.map.bitmap + (position / 32) * 4;
    let old = load(p, address);
    store(p, address, if used { old | mask } else { old & ~mask });
    position += take;
    remaining -= take;
  }
}

fn reserve(p: Pool&, bytes: u32, owned: bool) -> Reservation {
  var result = Reservation {};
  if owned && bytes > MAX_U32 - CAPSULE_BYTES { return result; }
  let requested = if owned { bytes + CAPSULE_BYTES } else { bytes };
  let rounded, fits = align_checked(requested, GRANULE);
  if !fits { return result; }
  var slot: u32 = 0;
  for i in p.map.owner_slots as i64 {
    let s = i as u32 + 1;
    let e = entry(p, s);
    if load(p, e + 20) == FREE && load(p, e + 16) != MAX_U32 { slot = s; break; }
  }
  if slot == 0 { result.error = NO_OWNER_SLOTS; return result; }
  let needed = rounded / GRANULE;
  var run: u32 = 0;
  var first: u32 = 0;
  if needed > 0 {
    for i in p.map.granules as i64 {
      if occupied(p, i as u32) { run = 0; }
      else {
        if run == 0 { first = i as u32; }
        run++;
        if run == needed { break; }
      }
    }
    if run != needed { result.error = NO_CONTIGUOUS_SPACE; return result; }
  }
  let e = entry(p, slot);
  let generation = load(p, e + 16) + 1;
  mark_run(p, first, needed, true);
  store(p, e, if needed == 0 { 0 } else { p.map.pool + first * GRANULE });
  store(p, e + 4, requested);
  store(p, e + 8, rounded);
  store(p, e + 12, if owned { CAPSULE_BYTES } else { 0 });
  store(p, e + 16, generation);
  store(p, e + 20, if owned { BUILDING } else { OPEN });
  store(p, e + 24, 0);
  store(p, e + 28, 0);
  result.success = true;
  result.handle = Handle { slot, generation };
  return result;
}

fn place(p: Pool&, h: Handle, count: u32, size: u32, alignment: u32) -> Placement, bool {
  var out = Placement { capacity: count };
  if !valid(p, h, OPEN) && !valid(p, h, BUILDING) { return out, false; }
  if (size == 0 && alignment != 1) || (size != 0 && alignment != 4) || (size != 1 && size % 4 != 0) {
    return out, false;
  }
  let e = entry(p, h.slot);
  if size == 0 || count == 0 { out.success = true; return out, true; }
  if count > MAX_U32 / size { return out, true; }
  let top, fits = align_checked(load(p, e + 12), alignment);
  if !fits { return out, true; }
  let requested = load(p, e + 4);
  if top > requested || count > (requested - top) / size {
    out.error = NO_SPACE;
    return out, true;
  }
  let bytes = count * size;
  out.success = true;
  out.data = if bytes == 0 { 0 } else { load(p, e) + top };
  store(p, e + 12, top + bytes);
  return out, true;
}

fn release(p: Pool&, h: Handle, state: u32) -> bool {
  if !valid(p, h, state) || (state != OPEN && state != SEALED && state != BUILDING) { return false; }
  let e = entry(p, h.slot);
  let rounded = load(p, e + 8);
  if rounded != 0 { mark_run(p, (load(p, e) - p.map.pool) / GRANULE, rounded / GRANULE, false); }
  let generation = load(p, e + 16);
  for i in 8 { store(p, e + i as u32 * 4, 0); }
  store(p, e + 16, generation);
  store(p, e + 20, if generation == MAX_U32 { RETIRED } else { FREE });
  return true;
}
fn reset(p: Pool&, h: Handle) -> bool {
  if !valid(p, h, OPEN) { return false; }
  store(p, entry(p, h.slot) + 12, 0);
  return true;
}
fn seal(p: Pool&, h: Handle, schema: u32, payload: const u32[:]) -> bool {
  if !valid(p, h, BUILDING) || payload.len > 64 { return false; }
  let e = entry(p, h.slot);
  let base = load(p, e);
  // Copy all payload words and clear the unused capsule before state publication.
  for i in 64 { store(p, base + i as u32 * 4, if i < payload.len { payload[i] } else { 0 }); }
  store(p, e + 24, schema);
  store(p, e + 28, payload.len as u32);
  store(p, e + 20, SEALED);
  return true;
}
fn open_owned(p: Pool&, h: Handle, schema: u32, words: u32) -> u32, bool {
  if !valid(p, h, SEALED) { return 0, false; }
  let e = entry(p, h.slot);
  if load(p, e + 24) != schema || load(p, e + 28) != words || words > 64 { return 0, false; }
  return load(p, e), true;
}

struct Destination { data: u32 = 0, capacity: u32 = 0 }
struct Builder { data: u32 = 0, length: u32 = 0, capacity: u32 = 0 }
struct View { data: u32 = 0, length: u32 = 0 }

fn split(d: Destination, at: u32, stride: u32) -> Destination, Destination, bool {
  if at > d.capacity || (stride != 0 && d.capacity > MAX_U32 / stride) { return Destination {}, Destination {}, false; }
  let delta = at * stride;
  if d.data > MAX_U32 - delta { return Destination {}, Destination {}, false; }
  return Destination { if stride == 0 { 0 } else { d.data }, at },
    Destination { if stride == 0 { 0 } else { d.data + delta }, d.capacity - at }, true;
}
fn begin(d: Destination) -> Builder { Builder { d.data, 0, d.capacity } }
fn append(p: Pool&, b: Builder&, words: const u32[:]) -> bool {
  if b.length >= b.capacity { return false; }
  let bytes = words.len as u32 * 4;
  // Validated Core supplies an admitted Plain layout and writable provenance.
  assert(words.len <= 16);
  assert(bytes == 0 || b.capacity <= MAX_U32 / bytes);
  let at = b.data + b.length * bytes;
  for i in words.len { store(p, at + i as u32 * 4, words[i]); }
  b.length++;
  return true;
}
fn freeze(b: Builder, stride: u32) -> View {
  View { if b.length == 0 || stride == 0 { 0 } else { b.data }, b.length }
}
fn slice(v: View, start: u32, count: u32, stride: u32) -> View, bool {
  if start > v.length || count > v.length - start || (stride != 0 && v.length > MAX_U32 / stride) { return View {}, false; }
  let delta = start * stride;
  if v.data > MAX_U32 - delta { return View {}, false; }
  return View { if count == 0 || stride == 0 { 0 } else { v.data + delta }, count }, true;
}

// Header-only admission precedes reservation or source execution. Structural
// Plain validation and per-field limits are supplied by the manifest schema.
fn bridge_header(p: Pool&, export_id: u32, input_bytes: u32, output_capacity: u32) -> bool {
  if input_bytes < 32 || input_bytes > p.map.ingress_bytes || output_capacity > p.map.egress_bytes - 32 { return false; }
  let a = p.map.ingress;
  return load(p, a) == ABI_TAG && load(p, a + 4) == export_id &&
    load(p, a + 8) == 0 && load(p, a + 12) == input_bytes - 32 &&
    load(p, a + 16) == 0 && load(p, a + 24) == 0 && load(p, a + 28) == 0;
}
fn wire_array(payload_bytes: u32, fixed_bytes: u32, count: u32, offset: u32,
              stride: u32, maximum: u32) -> bool {
  if count > maximum || offset % 4 != 0 || offset < fixed_bytes || offset > payload_bytes { return false; }
  if stride == 0 { return true; }
  if count > MAX_U32 / stride { return false; }
  return count <= (payload_bytes - offset) / stride;
}
fn publish_header(p: Pool&, export_id: u32, status: u32, payload: u32,
                  required: u32, items: u32, detail: u32) {
  assert(status <= LANGUAGE_ERROR && status != BUSY);
  assert((status == STATUS_OK || payload == 0) &&
    (status == STATUS_OK || status == OUTPUT_TOO_SMALL || required == 0));
  let a = p.map.egress;
  store(p, a, ABI_TAG); store(p, a + 4, export_id);
  store(p, a + 12, payload); store(p, a + 16, required);
  store(p, a + 20, items); store(p, a + 24, detail); store(p, a + 28, 0);
  store(p, a + 8, status); // Last publication write.
}
