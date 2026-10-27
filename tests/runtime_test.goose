import std;
import src.runtime;

fn test_runtime() {
  let defaults, defaults_ok = runtime::make_map(runtime::Config {});
  assert(defaults_ok && defaults.bitmap_bytes == 512 && defaults.owner_slots == 256);
  assert(defaults.pool % 4096 == 0 && defaults.pages * 65536 >= defaults.end);
  let rejected, rejects_limit = runtime::make_map(runtime::Config { pool_bytes: 0x40000000 });
  assert(!rejects_limit);
  let rejected2, rejects_slots = runtime::make_map(runtime::Config { owner_slots: 4097 });
  assert(!rejects_slots);
  let m, ok = runtime::make_map(runtime::Config {
    pool_bytes: 4 * 4096, owner_slots: 4, frame_bytes: 256, ingress_bytes: 256, egress_bytes: 256,
  });
  assert(ok);
  var p = runtime::Pool {};
  runtime::initialize(p, m);
  let a = runtime::reserve(p, 1, false);
  let b = runtime::reserve(p, 4096, false);
  let c = runtime::reserve(p, 4096, false);
  let d = runtime::reserve(p, 4096, false);
  assert(a.success && b.success && c.success && d.success);
  assert(a.handle.slot == 1 && a.handle.generation == 1);
  let overflow = runtime::reserve(p, 0xffffffff, false);
  assert(!overflow.success && overflow.error == runtime::SIZE_OVERFLOW);
  let no_slot = runtime::reserve(p, 0, false);
  assert(!no_slot.success && no_slot.error == runtime::NO_OWNER_SLOTS);
  let slack, slack_valid = runtime::place(p, a.handle, 1, 4, 4);
  assert(slack_valid && !slack.success && slack.error == runtime::NO_SPACE);
  assert(runtime::load(p, runtime::entry(p, a.handle.slot) + 12) == 0);
  let huge, huge_valid = runtime::place(p, a.handle, 0xffffffff, 4, 4);
  assert(huge_valid && !huge.success && huge.error == runtime::SIZE_OVERFLOW);
  let zst, zst_valid = runtime::place(p, a.handle, 0xffffffff, 0, 1);
  assert(zst_valid && zst.success && zst.data == 0 && zst.capacity == 0xffffffff);
  assert(runtime::release(p, b.handle, runtime::OPEN));
  assert(runtime::release(p, d.handle, runtime::OPEN));
  let fragmented = runtime::reserve(p, 8192, false);
  assert(!fragmented.success && fragmented.error == runtime::NO_CONTIGUOUS_SPACE);
  assert(runtime::load(p, runtime::entry(p, 2) + 16) == 1);
  assert(runtime::release(p, c.handle, runtime::OPEN));
  let joined = runtime::reserve(p, 8192, false);
  assert(joined.success && joined.handle.slot == 2 && joined.handle.generation == 2);
  assert(runtime::load(p, runtime::entry(p, 2)) == m.pool + 4096);
  assert(!runtime::release(p, b.handle, runtime::OPEN));
  assert(!runtime::reset(p, runtime::Handle {0, 1}));
  assert(!runtime::reset(p, runtime::Handle {5, 1}));
  assert(runtime::release(p, joined.handle, runtime::OPEN));
  assert(runtime::release(p, a.handle, runtime::OPEN));
  let zero = runtime::reserve(p, 0, false);
  assert(zero.success && runtime::load(p, runtime::entry(p, zero.handle.slot)) == 0);
  assert(runtime::release(p, zero.handle, runtime::OPEN));

  // Retirement is permanent, but failed reservations never retire or increment.
  runtime::store(p, runtime::entry(p, 1) + 16, 0xfffffffe);
  let last = runtime::reserve(p, 0, false);
  assert(last.handle.slot == 1 && last.handle.generation == 0xffffffff);
  assert(runtime::release(p, last.handle, runtime::OPEN));
  assert(runtime::load(p, runtime::entry(p, 1) + 20) == runtime::RETIRED);
  let next = runtime::reserve(p, 16, false);
  assert(next.handle.slot == 2);
  let dest, dest_ok = runtime::place(p, next.handle, 4, 4, 4);
  assert(dest_ok && dest.success && dest.data == m.pool);
  var builder = runtime::begin(runtime::Destination {dest.data, dest.capacity});
  assert(runtime::append(p, builder, [10 as u32]));
  assert(runtime::append(p, builder, [20 as u32]));
  assert(runtime::append(p, builder, [30 as u32]));
  assert(runtime::append(p, builder, [40 as u32]));
  assert(!runtime::append(p, builder, [50 as u32]) && builder.length == 4);
  let view = runtime::freeze(builder, 4);
  let sliced, sliced_ok = runtime::slice(view, 1, 2, 4);
  assert(sliced_ok && sliced.length == 2 && runtime::load(p, sliced.data) == 20);
  let empty, empty_ok = runtime::slice(view, 4, 0, 4);
  assert(empty_ok && empty.data == 0 && empty.length == 0);
  let out, out_ok = runtime::slice(view, 0xffffffff, 2, 4);
  assert(!out_ok);
  assert(runtime::reset(p, next.handle));
  assert(runtime::load(p, runtime::entry(p, next.handle.slot) + 12) == 0);
  assert(runtime::release(p, next.handle, runtime::OPEN));

  let padding = runtime::reserve(p, 7, false);
  let seven, seven_ok = runtime::place(p, padding.handle, 7, 1, 4);
  assert(seven_ok && seven.success);
  let empty_aligned, empty_aligned_ok = runtime::place(p, padding.handle, 0, 4, 4);
  assert(empty_aligned_ok && empty_aligned.success && empty_aligned.data == 0);
  assert(runtime::load(p, runtime::entry(p, padding.handle.slot) + 12) == 7);
  assert(runtime::release(p, padding.handle, runtime::OPEN));

  let own = runtime::reserve(p, 0, true);
  assert(own.success && runtime::load(p, runtime::entry(p, own.handle.slot) + 4) == 256);
  assert(runtime::load(p, runtime::entry(p, own.handle.slot) + 12) == 256);
  assert(!runtime::reset(p, own.handle));
  assert(!runtime::release(p, own.handle, runtime::OPEN));
  let no_work, no_work_ok = runtime::place(p, own.handle, 1, 4, 4);
  assert(no_work_ok && !no_work.success && no_work.error == runtime::NO_SPACE);
  assert(runtime::seal(p, own.handle, 77, [42 as u32, 9 as u32]));
  let root, root_ok = runtime::open_owned(p, own.handle, 77, 2);
  assert(root_ok && runtime::load(p, root) == 42 && runtime::load(p, root + 4) == 9);
  for i in 62 { assert(runtime::load(p, root + 8 + i as u32 * 4) == 0); }
  let mismatch, mismatch_ok = runtime::open_owned(p, own.handle, 78, 2);
  assert(!mismatch_ok);
  assert(!runtime::seal(p, own.handle, 77, []));
  assert(runtime::release(p, own.handle, runtime::SEALED));

  assert(runtime::wire_array(24, 8, 4, 8, 4, 4));
  assert(!runtime::wire_array(24, 8, 5, 8, 4, 8));
  assert(!runtime::wire_array(24, 8, 4, 4, 4, 8));
  assert(!runtime::wire_array(24, 8, 0xffffffff, 8, 4, 0xffffffff));
  assert(runtime::wire_array(8, 8, 100, 8, 0, 100));
  runtime::store(p, m.ingress, runtime::ABI_TAG);
  runtime::store(p, m.ingress + 4, 7);
  runtime::store(p, m.ingress + 12, 8);
  assert(runtime::bridge_header(p, 7, 40, 224));
  assert(!runtime::bridge_header(p, 7, 40, 225));
  runtime::store(p, m.ingress + 28, 1);
  assert(!runtime::bridge_header(p, 7, 40, 224));
  print("K1_RUNTIME_TEST geometry pool fragmentation failures retirement placement owned builders wire: PASS");
}
