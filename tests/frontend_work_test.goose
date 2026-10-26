import src.frontend;
fn frontend_receipt_visits(source: const u8[:], name: const u8[:]) -> u64 {
    var visits: u64 = 0;
    with_core() { b => var work = Work { .. }; var diags: Diagnostic[>..] = []; let ok = frontend_complete(source, "work", b, work, diags); if !ok { for d in diags { print(d.code, " ", name_bytes(core_view(b), d.detail)); } } assert(ok); var definition: u32 = 0; for d, id in b.definitions { if id != 0 && name_bytes(core_view(b), d.name) == name { definition = id as u32; } } assert(definition != 0); for r in b.receipts { if r.producer == definition { visits = r.completed_visits; } } assert(visits != 0); }; return visits;
}
fn test_frontend_work_independence() {
    let annotation = "pub let dependency: U32 -> U32 ! {} resources {depth:1,frame:0} = fn value => do:\n";
    let caller = "pub let caller: U32 -> U32 ! {} resources {depth:2,frame:0} = fn x => do:\n  let y = dependency(x)\n  if y<100:\n    return y+1\n  return 0\n";
    var small: u8[>..] = []; small.append(annotation); small.append("  return value\n"); small.append(caller);
    var large: u8[>..] = []; large.append(annotation); for i in 100 { large.append(str("  let item", i, " = ", i, "+1\n")); } large.append("  return value\n"); large.append(caller);
    let before = frontend_receipt_visits(small, "caller"); let after = frontend_receipt_visits(large, "caller"); print("WORK stable caller receipt ", before, " / ", after); assert(before == after);
}
fn test_frontend_static_dependency_observations() {
    let source = "static let seed: U32 = 1\nlet helper: U32 -> U32 ! {} resources {depth:1,frame:0} = fn value => return U32.wrapping_add(value,seed)\nlet via: Unit -> U32 ! {} resources {depth:3,frame:128} = fn () => do:\n  let callback = fn (u:Unit) => return helper(41)\n  return callback(())\nstatic let answer: U32 = via(())\n";
    with_core() { b => var work = Work { .. }; var diags: Diagnostic[>..] = []; let ok = frontend_complete(source, "static-dependencies", b, work, diags); if !ok { for d in diags { print(d.code, " ", name_bytes(core_view(b), d.detail)); } } assert(ok); var answer: u32 = 0; for d, id in b.definitions { if id != 0 && name_bytes(core_view(b), d.name) == "answer" { answer = id as u32; } } var helper = false; var via = false; var seed = false; for receipt in b.receipts { if receipt.producer != answer { continue; } for i in receipt.dependencies.count { let query = b.dependencies[b.refs[receipt.dependencies.start + i]]; if query.producer == 0 { continue; } let name = name_bytes(core_view(b), b.definitions[query.producer].name); if query.kind == DEP_BODY && name == "helper" { helper = true; } if query.kind == DEP_BODY && name == "via" { via = true; } if query.kind == DEP_STATIC && name == "seed" { seed = true; } } } assert(helper && via && seed); }
}

fn test_frontend_operation_limit_includes_terminators() {
    for excessive in 2 {
        var source: u8[>..] = []; source.append("let f: Unit -> Unit = fn () => do:\n");
        for i in LIMIT_OPS - 2 + excessive { source.append("  ()\n"); }
        source.append("  return ()\n");
        with_core() { b =>
            var work = Work { .. }; var diags: Diagnostic[>..] = [];
            let ok = frontend_complete(source, "operation-boundary", b, work, diags);
            if excessive == 0 { if !ok { for d in diags { print(d.code, " ", name_bytes(core_view(b), d.detail)); } } assert(ok); assert(b.ops.len + b.terminators.len - 2 == LIMIT_OPS); }
            else { assert(!ok); assert(diags.len != 0 && diags[diags.len - 1].code == FE_CORE_LIMIT); }
        }
    }
}
