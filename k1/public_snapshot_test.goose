import std;
import os;
import public_snapshot;

// Construct from mutable, caller-owned scratch, mutate every input after the
// return, and then drop that scratch when this function exits.
fn make_scope() -> public_snapshot::Result {
    var source: u8[>..] = []; source.append("pub let answer: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n");
    var package: u8[>..] = []; package.append("pkg");
    var module: u8[>..] = []; module.append("main.blot");
    var declaration: u8[>..] = []; declaration.append("answer");
    var abi: u8[32] = [7; 32];
    let result = public_snapshot::make(source, package, module, declaration, abi);
    source[0] = 'X'; package[0] = 'X'; module[0] = 'X'; declaration[0] = 'X'; abi[0] = 9;
    return result;
}
fn alternate(abi: u8[:]) -> public_snapshot::Result {
    return public_snapshot::make("pub let answer: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 7\n",
        "pkg", "main.blot", "answer", abi);
}
fn no_output(s: public_snapshot::Snapshot&, abi: u8[:]) {
    assert(!public_snapshot::validate(s,"pkg","main.blot","answer",abi));
    assert(public_snapshot::emit(s,"pkg","main.blot","answer",abi).len == 0);
}
fn main() {
    let abi: u8[32] = [7; 32]; let other_abi: u8[32] = [8; 32];
    var empty = public_snapshot::Snapshot {};
    no_output(empty,abi);
    var good = make_scope();
    assert(good.status == 0);
    assert(good.snapshot.source[..] == "pub let answer: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n");
    assert(good.snapshot.package[..] == "pkg" && good.snapshot.module[..] == "main.blot" &&
           good.snapshot.declaration[..] == "answer" && good.snapshot.abi[..] == abi[..]);
    assert(public_snapshot::validate(good.snapshot,"pkg","main.blot","answer",abi));
    assert(!public_snapshot::validate(good.snapshot,"bad","main.blot","answer",abi));
    assert(!public_snapshot::validate(good.snapshot,"pkg","other.blot","answer",abi));
    assert(!public_snapshot::validate(good.snapshot,"pkg","main.blot","other",abi));
    assert(!public_snapshot::validate(good.snapshot,"pkg","main.blot","answer",other_abi));
    let short_abi: u8[2] = [7, 7];
    assert(!public_snapshot::validate(good.snapshot,"pkg","main.blot","answer",short_abi));
    let bad_request = public_snapshot::make(good.snapshot.source,"pkg","main.blot","answer",short_abi);
    assert(bad_request.status != 0 && bad_request.snapshot.source.len == 0 && bad_request.snapshot.plan.len == 0);
    assert(public_snapshot::emit(good.snapshot,"bad","main.blot","answer",abi).len == 0);
    let baseline = public_snapshot::emit(good.snapshot,"pkg","main.blot","answer",abi);
    assert(baseline.len > 0 && write_file("public_snapshot.wasm",baseline));
    // Independent repeated admission has identical output and does not consume
    // or mutate the prior successful snapshot.
    assert(public_snapshot::emit(good.snapshot,"pkg","main.blot","answer",abi)[..] == baseline[..]);
    let rejected = public_snapshot::make("invalid source", "pkg", "main.blot", "answer", abi);
    assert(rejected.status != 0 && rejected.snapshot.source.len == 0 && rejected.snapshot.plan.len == 0);
    assert(public_snapshot::validate(good.snapshot,"pkg","main.blot","answer",abi));
    var oversized: u8[>..] = [];
    for i in 16777217 { oversized.push('a'); }
    let too_large = public_snapshot::make(oversized, "pkg", "main.blot", "answer", abi);
    assert(too_large.status != 0 && too_large.snapshot.source.len == 0 && too_large.snapshot.plan.len == 0);
    assert(oversized.len == 16777217 && oversized[0] == 'a' && oversized[oversized.len - 1] == 'a');
    // The same O(1) size guard used by snapshot validation handles an
    // oversized artifact without allocating a second 16 MiB array.
    assert(public_snapshot::sizes_fit(0, 16777216, 0, 0));
    assert(!public_snapshot::sizes_fit(0, oversized.len, 0, 0));
    assert(!public_snapshot::sizes_fit(0, 0, oversized.len, 0));
    assert(!public_snapshot::sizes_fit(0, 0, 0, oversized.len));
    assert(!public_snapshot::sizes_fit(0, -1, 0, 0));
    assert(!public_snapshot::sizes_fit(0, 9223372036854775807, 0, 0));
    assert(public_snapshot::validate(good.snapshot,"pkg","main.blot","answer",abi));
    var source_edit = make_scope(); source_edit.snapshot.source[source_edit.snapshot.source.len - 2] = '7'; no_output(source_edit.snapshot,abi);
    var producer_edit = make_scope(); producer_edit.snapshot.package[0] = 'x'; no_output(producer_edit.snapshot,abi);
    var abi_edit = make_scope(); abi_edit.snapshot.abi[0] ^= 1; no_output(abi_edit.snapshot,abi);
    var interface_edit = make_scope(); interface_edit.snapshot.interface[0] ^= 1; no_output(interface_edit.snapshot,abi);
    var function_edit = make_scope(); function_edit.snapshot.function[function_edit.snapshot.function.len - 40] ^= 1; no_output(function_edit.snapshot,abi);
    var plan_edit = make_scope(); plan_edit.snapshot.plan[plan_edit.snapshot.plan.len - 1] ^= 1; no_output(plan_edit.snapshot,abi);
    let base = make_scope();
    var truncated = public_snapshot::Snapshot { source: copy(base.snapshot.source), package: copy(base.snapshot.package),
        module: copy(base.snapshot.module), declaration: copy(base.snapshot.declaration), abi: base.snapshot.abi,
        interface: public_snapshot::owned(base.snapshot.interface[..base.snapshot.interface.len - 1]),
        function: copy(base.snapshot.function), plan: copy(base.snapshot.plan) };
    no_output(truncated,abi);
    let other = alternate(abi); assert(other.status == 0);
    var mixed = public_snapshot::Snapshot { source: copy(base.snapshot.source), package: copy(base.snapshot.package),
        module: copy(base.snapshot.module), declaration: copy(base.snapshot.declaration), abi: base.snapshot.abi,
        interface: copy(base.snapshot.interface), function: copy(other.snapshot.function), plan: copy(other.snapshot.plan) };
    no_output(mixed,abi);
    assert(public_snapshot::validate(good.snapshot,"pkg","main.blot","answer",abi));
    print("owned public snapshot laws passed");
}
