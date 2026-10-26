import std;
import os;
import source_resolver;

fn fail(label: u8[:], status: i64) {
    var message: u8[>..] = [];
    format(message, label, status, "\n"); write_stderr(message); exit(1);
}
fn main() {
    let argv = args();
    if argv.len != 5 { write_stderr("expected ROOT PACKAGE MODULE DECLARATION\n"); exit(2); }
    var opened = source_resolver::open_root(argv[1], argv[2]);
    if opened.status != 0 { fail("root error ", opened.status); }
    var source = source_resolver::read(opened.root, argv[3], argv[4]);
    let closed = source_resolver::close_root(opened.root);
    if !closed || source.status != 0 { fail("source error ", source.status); }
    write_stdout(source.source.bytes);
}
