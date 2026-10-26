import unified_frontend;
import unified_wasm;
import compiler_frontend;
import compiler_validate;
import compiler_wasm;
fn compare(source:u8[:]) {
    var old=unified_frontend::parse(source);var tagged=compiler_frontend::parse(source);
    assert(old.status==0 && tagged.status==0 && tagged.program.variant==1 && compiler_validate::verify(source,tagged.program));
    let a=unified_wasm::emit(source,old.program);let b=compiler_wasm::emit(source,tagged.program);
    assert(a.len>0 && a[..]==b[..]);
}
fn main() {
    var medium:u8[>..]=[];medium.append("let f: U32 -> U32 = fn x => do:\n  return x\n//");
    for i in 65536 {medium.push('a');}assert(medium.len>65536);compare(medium);
    var missing:u8[>..]=[];missing.append("let f: U32 -> U32 = fn x => do:\n  return absent\n//");
    var unproved:u8[>..]=[];unproved.append("let f: U32 -> U32 = fn x => do:\n  return x + 1\n//");
    for i in 65536 {missing.push('a');unproved.push('a');}
    assert(unified_frontend::parse(missing).status==3 && compiler_frontend::parse(missing).status==3);
    assert(unified_frontend::parse(unproved).status==5 && compiler_frontend::parse(unproved).status==5);
    let prefix="let f: U32 -> U32 = fn x => do:\n  return x\n";
    var limit:u8[>..]=[32;16777216];for c,i in prefix {limit[i]=c;}
    compare(limit);limit.push(' ');
    let too_large=compiler_frontend::parse(limit);assert(too_large.status==2 && too_large.program.source.len==0);
    print("tagged scalar source-size parity passed at 64 KiB and 16 MiB boundaries");
}
