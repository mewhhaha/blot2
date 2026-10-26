import os;
import std;
import wasm;

fn require(ok: bool, message: u8[:]) {
    if !ok { abort(str("wasm test: ", message)); }
}

fn main() {
    require(wasm::emit_scalar("", 1, 0).len == 0, "empty name");
    require(wasm::emit_scalar("4x", 1, 0).len == 0, "invalid name");
    require(wasm::emit_scalar("return", 1, 0).len == 0, "reserved name");
    require(wasm::emit_scalar("id", 0, 0).len == 0, "invalid operation");
    require(write_file("identity.wasm", wasm::emit_scalar("id", 1, 0)), "write identity");
    let values: i64[8] = [0, 63, 64, 127, 128, 2147483647, 2147483648, 4294967295];
    for value, i in values {
        require(write_file(str("const", i, ".wasm"), wasm::emit_scalar("value", 2, value as u32)), "write constant");
    }
    var long_name: u8[>..] = [];
    for i in 130 { long_name.push('x'); }
    require(write_file("long.wasm", wasm::emit_scalar(long_name, 1, 0)), "write long name");
}
