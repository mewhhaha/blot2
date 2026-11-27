// The direct backend's Wasm writer lays out the same bytes as
// compiler/src/direct/writer.zig for one module that uses every section.
// tools/test_direct.py compares the printed bytes with writer_reference.zig.
import std;
import direct.writer;

fn hex(value: u8) -> u8 { if value < 10 { return 48 + value; } return 87 + value; }

fn main() {
    var m = squid_direct_writer::Module { .. };
    let i32t = squid_direct_writer::VT_i32;
    let f32t = squid_direct_writer::VT_f32;
    let unit = squid_direct_writer::signature(m, [], []);
    let binary = squid_direct_writer::signature(m, [i32t, i32t], [i32t]);
    let again = squid_direct_writer::signature(m, [i32t, i32t], [i32t]);
    let mixed = squid_direct_writer::signature(m, [f32t, i32t, squid_direct_writer::VT_externref], [f32t, i32t]);
    assert(again == binary);
    squid_direct_writer::importFunction(m, "host", "log", unit);
    squid_direct_writer::importFunction(m, "host", "pick", mixed);
    let first = squid_direct_writer::addFunction(m, binary);
    let second = squid_direct_writer::addFunction(m, unit);
    let third = squid_direct_writer::addFunction(m, mixed);
    squid_direct_writer::setBody(m, first, [0 as u8, 0x20, 0, 0x20, 1, 0x6a, 0x0b]);
    squid_direct_writer::setBody(m, second, [0 as u8, 0x0b]);
    squid_direct_writer::setBody(m, third, [1 as u8, 2, 0x7f, 0x20, 0, 0x41, 0xc0, 0xbb, 0x78, 0x0b]);
    squid_direct_writer::addGlobal(m, i32t, true, 65536);
    squid_direct_writer::addGlobal(m, f32t, false, 0x3fc00000);
    squid_direct_writer::addGlobal(m, i32t, false, 0xffffff80);
    squid_direct_writer::exportItem(m, "add", squid_direct_writer::EXPORT_function, first);
    squid_direct_writer::exportItem(m, "memory", squid_direct_writer::EXPORT_memory, 0);
    squid_direct_writer::exportItem(m, "limit", squid_direct_writer::EXPORT_global, 0);
    squid_direct_writer::tableSlot(m, first);
    squid_direct_writer::tableSlot(m, third);
    m.host_slots = 3;
    m.has_memory = true;
    m.memory_pages = 300;
    m.has_start = true;
    m.start = second;
    m.data_offset = 1024;
    m.data.append("squid data ");
    m.data.push(0);
    m.data.push(255);
    squid_direct_writer::custom(m, "squid:abi", [8 as u8, 0, 0, 0]);
    squid_direct_writer::setName(m, first, "add");
    squid_direct_writer::setName(m, third, "a much longer name that needs more than one hundred and twenty-seven bytes to spell so that its length takes two bytes in the map");
    var out: u8[>..<] = [];
    squid_direct_writer::assemble(m, out);
    var text: u8[>..<] = [];
    for value in out { text.push(hex(value >> 4)); text.push(hex(value & 15)); }
    print(text[..]);
}
