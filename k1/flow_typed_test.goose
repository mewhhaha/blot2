import std;
import os;
import flow_typed;
import flow_typed_check;
import flow_typed_wasm;

fn positive(source: u8[:], index: i64) {
    var result = flow_typed::build(source,"f","x");
    assert(result.status == 0 && flow_typed_check::verify(result.program));
    let bytes = flow_typed_wasm::emit(result.program);
    assert(bytes.len > 0 && write_file(str("flow_typed_",index,".wasm"),bytes));
    for i in result.program.tree.nodes.len {
        let old_type = result.program.types[i]; result.program.types[i] = 99;
        assert(!flow_typed_check::verify(result.program) && flow_typed_wasm::emit(result.program).len == 0);
        result.program.types[i] = old_type;
        let old_literal = result.program.literals[i]; result.program.literals[i] = old_literal ^ 1;
        assert(!flow_typed_check::verify(result.program)); result.program.literals[i] = old_literal;
        let old_node = result.program.tree.nodes[i]; result.program.tree.nodes[i].a = -1;
        assert(!flow_typed_check::verify(result.program)); result.program.tree.nodes[i] = old_node;
    }
    assert(flow_typed_check::verify(result.program));
    let old = result.program.tree.source[0]; result.program.tree.source[0] = 'x';
    assert(!flow_typed_check::verify(result.program)); result.program.tree.source[0] = old;
    result.program.parameter[0] = '1'; assert(!flow_typed_check::verify(result.program));
}
fn negative(source: u8[:], status: i64) { let r = flow_typed::build(source,"f","x"); assert(r.status == status && r.program.tree.nodes.len == 0); }
fn probe(source: u8[:], path: u8[:]) {
    var r = flow_typed::build(source,"f","x"); assert(r.status == 0);
    var operand: i64 = 0;
    for n in r.program.tree.nodes { if n.tag == 7 || n.tag == 8 { operand = n.b; } }
    assert(operand > 0);
    let bytes = flow_typed_wasm::probe(r.program,operand);
    assert(bytes.len > 0 && write_file(path,bytes));
    assert(flow_typed_wasm::probe(r.program,0).len == 0);
    assert(flow_typed_wasm::probe(r.program,r.program.tree.root).len == 0);
}
fn main() {
    positive("do:\n  return 42\n",0);
    positive("do:\n  if x:\n    return 4294967295\n  else:\n    return 7\n",1);
    positive("do:\n  if x:\n    return 1\n  return 2\n",2);
    positive("do:\n  if x && (#True || #False):\n    if #False:\n      return 3\n    else:\n      return 4\n  else:\n    return 5\n",3);
    positive("do:\n  if x || #False:\n    if x && #True:\n      return 6\n  return 7\n",4);
    positive("do:\n  if #False && x:\n    return 8\n  else:\n    return 9\n",5);
    negative("do:\n  if y:\n    return 1\n  else:\n    return 2\n",3);
    negative("do:\n  if #False:\n    if y:\n      return 1\n    else:\n      return 2\n  return 3\n",3);
    negative("do:\n  if 1:\n    return 1\n  else:\n    return 2\n",4);
    negative("do:\n  return x\n",4);
    negative("do:\n  return ()\n",2);
    negative("do:\n  if x:\n    return 1\n",5);
    negative("do:\n  return 1\n  return 2\n",6);
    assert(flow_typed::build("do:\n  return 1\n","f","do").status == 7);
    probe("do:\n  if x && #True:\n    return 1\n  else:\n    return 2\n","flow_typed_and_probe.wasm");
    probe("do:\n  if x || #False:\n    return 1\n  else:\n    return 2\n","flow_typed_or_probe.wasm");
    print("private typed flow lowering passed");
}
