import std;
import os;
import flow_decl;
import flow_decl_check;
import flow_decl_wasm;

fn positive(source: u8[:], index: i64) {
    var result = flow_decl::build(source);
    assert(result.status == 0 && flow_decl_check::verify(result.decl));
    let bytes = flow_decl_wasm::emit(source,result.decl);
    assert(bytes.len > 0 && write_file(str("flow_decl_",index,".wasm"),bytes));
    assert(flow_decl_wasm::emit("not this source",result.decl).len == 0);
    let ns = result.decl.name_start; result.decl.name_start = -1; assert(!flow_decl_check::verify(result.decl)); result.decl.name_start = ns;
    let ne = result.decl.name_end; result.decl.name_end = 99999999; assert(!flow_decl_check::verify(result.decl)); result.decl.name_end = ne;
    let ps = result.decl.param_start; result.decl.param_start = -1; assert(!flow_decl_check::verify(result.decl)); result.decl.param_start = ps;
    let pe = result.decl.param_end; result.decl.param_end = 0; assert(!flow_decl_check::verify(result.decl)); result.decl.param_end = pe;
    let bs = result.decl.body_start; result.decl.body_start = -1; assert(!flow_decl_check::verify(result.decl)); result.decl.body_start = bs;
    let old_name = result.decl.body.name[0]; result.decl.body.name[0] = 'q';
    assert(!flow_decl_check::verify(result.decl) && flow_decl_wasm::emit(source,result.decl).len == 0); result.decl.body.name[0] = old_name;
    let old_parameter = result.decl.body.parameter[0]; result.decl.body.parameter[0] = 'q';
    assert(!flow_decl_check::verify(result.decl)); result.decl.body.parameter[0] = old_parameter;
    let old_source = result.decl.source[0]; result.decl.source[0] = 0;
    assert(!flow_decl_check::verify(result.decl)); result.decl.source[0] = old_source;
    let old_body = result.decl.body.tree.source[0]; result.decl.body.tree.source[0] = 'x';
    assert(!flow_decl_check::verify(result.decl)); result.decl.body.tree.source[0] = old_body;
    assert(flow_decl_check::verify(result.decl));
}
fn reject(source: u8[:]) { let r = flow_decl::build(source); assert(r.status != 0 && r.decl.source.len == 0); }
fn main() {
    positive("let f: Bool -> U32 = fn x => do:\n  if x:\n    return 4294967295\n  else:\n    return 7\n",0);
    positive("let choose: Bool -> U32 = fn flag => do:\n  if flag && #True:\n    if #False:\n      return 1\n    else:\n      return 42\n  return 17\n",1);
    positive("// source\r\nlet value: Bool -> U32 = fn b => do:\r\n  return 9\r\n",2);
    reject("let f: U32 -> U32 = fn x => do:\n  return 1\n");
    reject("let f: Bool -> Bool = fn x => do:\n  return 1\n");
    reject("pub let f: Bool -> U32 = fn x => do:\n  return 1\n");
    reject("let do: Bool -> U32 = fn x => do:\n  return 1\n");
    reject("let f: Bool -> U32 = fn do => do:\n  return 1\n");
    reject("let f: Bool -> U32 = fn x => do:\n  return y\n");
    reject("let f: Bool -> U32 = fn x => do:\n  if x:\n    return 1\n");
    reject("let f: Bool -> U32 = fn x => do:\n  return 1\nlet other: Bool -> U32 = fn y => do:\n  return 2\n");
    var input: u8[>..] = []; input.append("let f: Bool -> U32 = fn x => do:\n  return 1\n");
    var owned = flow_decl::build(input); assert(owned.status == 0);
    input[0] = 'x'; assert(flow_decl_check::verify(owned.decl)); assert(flow_decl_wasm::emit(input,owned.decl).len == 0);
    let original = "let f: Bool -> U32 = fn x => do:\n  return 1\n";
    var replacement = flow_decl::build("let f: Bool -> U32 = fn x => do:\n  return 2\n");
    assert(replacement.status == 0 && flow_decl_check::verify(replacement.decl));
    assert(flow_decl_wasm::emit(original,replacement.decl).len == 0);
    print("private whole-source flow declaration passed");
}
