import std;
import os;
import public_frontend;
import public_artifact;
import public_function;
import public_plan;
import public_fixture;
fn main() {
    let abi: u8[32] = [7; 32]; let wrong_abi: u8[32] = [8; 32];
    let cases = [
      "pub let answer: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x",
      "pub let answer: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 4294967295",
      "pub let answer: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x & 255",
      "pub let answer: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x < 2"
    ];
    for source, i in cases {
        let candidate = public_frontend::parse(source); assert(candidate.status == 0);
        let interface = public_artifact::encode(source,candidate,"pkg","main.blot","answer",abi);
        let function = public_function::encode(source,candidate,interface,"pkg","main.blot","answer",abi);
        let plan = public_plan::encode(source,candidate,interface,function,"pkg","main.blot","answer",abi,275);
        let bytes = public_fixture::emit(source,interface,function,plan,"pkg","main.blot","answer",abi);
        assert(bytes.len > 0 && write_file(str("public_fixture_",i,".wasm"),bytes));
        assert(public_fixture::emit(source,interface,function,plan,"wrong","main.blot","answer",abi).len == 0);
        assert(public_fixture::emit(source,interface,function,plan,"pkg","main.blot","answer",wrong_abi).len == 0);
        var changed: u8[>..] = []; changed.append(plan); changed[changed.len - 1] ^= 1;
        assert(public_fixture::emit(source,interface,function,changed,"pkg","main.blot","answer",abi).len == 0);
        var bad_function: u8[>..] = []; bad_function.append(function); bad_function[bad_function.len - 1] ^= 1;
        assert(public_fixture::emit(source,interface,bad_function,plan,"pkg","main.blot","answer",abi).len == 0);
        // Origins are intentionally outside the semantic digest. A different
        // but structurally valid origin must still fail fresh source binding.
        var bad_origin: u8[>..] = []; bad_origin.append(function); bad_origin[bad_origin.len - 40] ^= 1;
        assert(public_function::decode(bad_origin,interface,"pkg","main.blot","answer",abi).status == 0);
        assert(public_fixture::emit(source,interface,bad_origin,plan,"pkg","main.blot","answer",abi).len == 0);
        var bad_interface: u8[>..] = []; bad_interface.append(interface); bad_interface[bad_interface.len - 1] ^= 1;
        assert(public_fixture::emit(source,bad_interface,function,plan,"pkg","main.blot","answer",abi).len == 0);
    }
    // Source-only changes cannot reuse an artifact chain for another body.
    let a = cases[0]; let c = public_frontend::parse(a);
    let ai = public_artifact::encode(a,c,"pkg","main.blot","answer",abi);
    let af = public_function::encode(a,c,ai,"pkg","main.blot","answer",abi);
    let ap = public_plan::encode(a,c,ai,af,"pkg","main.blot","answer",abi,275);
    assert(public_fixture::emit(cases[1],ai,af,ap,"pkg","main.blot","answer",abi).len == 0);
    print("public artifact fixture emission passed");
}
