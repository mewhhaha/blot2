import std;
import os;
import control_frontend;
import control_validate;
import control_wasm;
fn write_case(expression: u8[:], i: i64) {
    let source = str("let f: Bool -> U32 = fn x => do:\n  if ",expression,":\n    return 4294967295\n  else:\n    return 7\n");
    let p = control_frontend::parse(source);
    assert(p.status == 0 && control_validate::verify(source,p.program));
    let data = control_wasm::emit(source,p.program);
    assert(data.len > 0 && write_file(str("control_",i,".wasm"),data));
    var forged = p.program; forged.yes = 6;
    assert(control_wasm::emit(source,forged).len == 0);
}
fn main() {
    let atoms = ["x", "#True", "#False"];
    var index = 0;
    for a in atoms { write_case(a,index); index += 1; }
    for a in atoms {
        for b in atoms {
            for op in ["&&", "||"] {
                write_case(str(a," ",op," ",b),index); index += 1;
            }
        }
    }
    assert(write_file("control_and_probe.wasm",control_wasm::probe(1)));
    assert(write_file("control_or_probe.wasm",control_wasm::probe(2)));
    assert(control_wasm::probe(0).len == 0);
}
