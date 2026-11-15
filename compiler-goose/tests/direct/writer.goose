// The direct backend's Wasm writer lays out the same bytes as
// compiler/src/direct/writer.zig for one module that uses every section.
// tools/test_direct.py compares the printed bytes with writer_reference.zig.
import std;
import direct.writer;

fn hex(value: u8) -> u8 { if value < 10 { return 48 + value; } return 87 + value; }

fn main() {
    var m = blot_direct_writer::Module { .. };
    let i32t = blot_direct_writer::VT_i32;
    let f32t = blot_direct_writer::VT_f32;
    let unit = blot_direct_writer::signature(m, [], []);
    let binary = blot_direct_writer::signature(m, [i32t, i32t], [i32t]);
    let again = blot_direct_writer::signature(m, [i32t, i32t], [i32t]);
    let mixed = blot_direct_writer::signature(m, [f32t, i32t, blot_direct_writer::VT_externref], [f32t, i32t]);
    assert(again == binary);
    blot_direct_writer::importFunction(m, "host", "log", unit);
    blot_direct_writer::importFunction(m, "host", "pick", mixed);
    let first = blot_direct_writer::addFunction(m, binary);
    let second = blot_direct_writer::addFunction(m, unit);
    let third = blot_direct_writer::addFunction(m, mixed);
    blot_direct_writer::setBody(m, first, [0 as u8, 0x20, 0, 0x20, 1, 0x6a, 0x0b]);
    blot_direct_writer::setBody(m, second, [0 as u8, 0x0b]);
    blot_direct_writer::setBody(m, third, [1 as u8, 2, 0x7f, 0x20, 0, 0x41, 0xc0, 0xbb, 0x78, 0x0b]);
    blot_direct_writer::addGlobal(m, i32t, true, 65536);
    blot_direct_writer::addGlobal(m, f32t, false, 0x3fc00000);
    blot_direct_writer::addGlobal(m, i32t, false, 0xffffff80);
    blot_direct_writer::exportItem(m, "add", blot_direct_writer::EXPORT_function, first);
    blot_direct_writer::exportItem(m, "memory", blot_direct_writer::EXPORT_memory, 0);
    blot_direct_writer::exportItem(m, "limit", blot_direct_writer::EXPORT_global, 0);
    blot_direct_writer::tableSlot(m, first);
    blot_direct_writer::tableSlot(m, third);
    m.host_slots = 3;
    m.has_memory = true;
    m.memory_pages = 300;
    m.has_start = true;
    m.start = second;
    m.data_offset = 1024;
    m.data.append("blot data ");
    m.data.push(0);
    m.data.push(255);
    blot_direct_writer::custom(m, "blot:abi", [8 as u8, 0, 0, 0]);
    blot_direct_writer::setName(m, first, "add");
    blot_direct_writer::setName(m, third, "a much longer name that needs more than one hundred and twenty-seven bytes to spell so that its length takes two bytes in the map");
    var out: u8[>..<] = [];
    blot_direct_writer::assemble(m, out);
    var text: u8[>..<] = [];
    for value in out { text.push(hex(value >> 4)); text.push(hex(value & 15)); }
    print(text[..]);
}
