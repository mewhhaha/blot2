// The direct backend's storage runtime emits the same globals, helpers and
// names as compiler/src/direct/runtime.zig, for the default budgets and for
// small budgets in a module that already has an import and a global.
// tools/test_direct.py compares the printed text with runtime_reference.zig.
import std;
import direct.writer;
import direct.runtime;

fn hex(value: u8) -> u8 { if value < 10 { return 48 + value; } return 87 + value; }
fn number(text: u8[>..<]&, value: u32) {
    var digits: u8[10] = [0; 10];
    var count = 0;
    var rest = value;
    loop {
        digits[count] = 48 + (rest % 10) as! u8;
        count += 1;
        rest /= 10;
        if rest == 0 { break; }
    }
    while count > 0 { count -= 1; text.push(digits[count]); }
    text.push(' ');
}
fn show(text: u8[>..<]&, budgets: squid_direct_runtime::Budgets, shifted: bool) {
    var m = squid_direct_writer::Module { .. };
    if shifted {
        let unit = squid_direct_writer::signature(m, [], []);
        squid_direct_writer::importFunction(m, "host", "log", unit);
        squid_direct_writer::addGlobal(m, squid_direct_writer::VT_f32, false, 0x3fc00000);
    }
    let r = squid_direct_runtime::emit(m, budgets);
    let l = r.layout;
    text.append("layout ");
    for value in [l.free_lists, l.owner_table, l.owner_capacity, l.persistent_base, l.persistent_end, l.stack_base, l.stack_end, l.heap_base, l.heap_end, l.transport_base, l.transport_end, l.total] { number(text, value); }
    text.push('\n');
    text.append("runtime ");
    for value in [r.owner_top, r.persistent_bottom, r.stack_pointer, r.heap_top, r.persistent_top, r.transport_top, r.effect_context, r.open, r.open_persistent, r.release, r.check, r.stack, r.heap_alloc, r.heap_free, r.address, r.length, r.push, r.pop, r.truncate, r.create, r.copy, r.persist, r.allocate, r.reset, r.packet_length] { number(text, value); }
    text.push('\n');
    var out: u8[>..<] = [];
    squid_direct_writer::assemble(m, out);
    for value in out { text.push(hex(value >> 4)); text.push(hex(value & 15)); }
    text.push('\n');
}

fn main() {
    var text: u8[>..<] = [];
    show(text, squid_direct_runtime::Budgets { .. }, false);
    show(text, squid_direct_runtime::Budgets { owners: 1024, persistent: 65536, stack: 131072, heap: 262144, transport: 4096 }, true);
    print(text[..]);
}
