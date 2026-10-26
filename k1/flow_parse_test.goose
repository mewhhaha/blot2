import flow_parse;
import flow_verify;
import flow_completion;
fn result(source: u8[:], expected: i64) {
    var tree, status = flow_parse::parse(source);
    if status != 0 { print("parse status ", status, " for ", source); }
    assert(status == 0); assert(flow_verify::verify(tree));
    let actual = flow_completion::check(tree);
    if actual != expected { print("completion ", actual, " expected ", expected, " for ", source); }
    assert(actual == expected);
}
fn main() {
    result("do:\n  if x:\n    return 1\n  return 2\n",0);
    result("do:\n  if x:\n    return 1\n",4);
    result("do:\n  if x:\n    return 1\n  else:\n    return 2\n",0);
    result("do:\n  if x:\n    return 1\n  else:\n    return 2\n  return 3\n",8);
    result("do:\n  if #True:\n    return 1\n",0);
    result("do:\n  if #False:\n    return 1\n",4);
    result("do:\n  if #True:\n    return 1\n  return 2\n",8);
    result("do:\n  if #False:\n    return 1\n  return 2\n",0);
    result("do:\n  if x && (#False || f(x)):\n    return 1\n  else:\n    if y:\n      return 2\n  return 3\n",0);
    result("do:\n  if #True || f(x):\n    return g(1)\n",4);
    result("do:\n  if #False && f(x):\n    return 1\n  else:\n    return 2\n",0);
    result("do:\n  if #False:\n    return 1\n    return 2\n  return 3\n",8);
    result("do:\n  return ()\n",0);
    result("do:\n  return f()\n",0);
    result("do:\n  return f(1,2,3)\n",0);
    result("do:\n  return f((1,2), (), g(), h(x))\n",0);
    result("do:\n  return f()(1,2)\n",0);
    result("do:\n  return (x)\n",0);
    result("do:\n  return (f\n    (1))\n",0);
    result("do:\n  return (x\n    && y\n    || f\n      (1))\n",0);
    result("do:\n  return do:\n    break 42\n",0);
    result("do:\n  return do:\n    return 1\n",0);
    result("do:\n  return do:\n    if x:\n      return 1\n    else:\n      break 2\n",0);
    result("do:\n  return do:\n    if x:\n      break 1\n",9);
    // Literal pruning prevents a missing-break error in a branch that cannot
    // execute; unknown conditions and the reachable branch still require it.
    result("do:\n  if #False:\n    return do:\n      if x:\n        break 1\n  return 2\n",0);
    result("do:\n  if #True:\n    return do:\n      if x:\n        break 1\n",9);
    result("do:\n  if x:\n    return do:\n      if y:\n        break 1\n",9);
    result("do:\n  if #True:\n    return 1\n  else:\n    return do:\n      if x:\n        break 2\n",0);
    result("do:\n  if #False:\n    return 1\n  else:\n    return do:\n      if x:\n        break 2\n",9);
    result("do:\n  return #False && do:\n    if x:\n      break #True\n",0);
    result("do:\n  return #True && do:\n    if x:\n      break #True\n",9);
    result("do:\n  return #True || do:\n    if x:\n      break #True\n",0);
    result("do:\n  return #False || do:\n    if x:\n      break #True\n",9);
    result("do:\n  return x && do:\n    if y:\n      break #True\n",9);
    // Syntactic code-after-transfer remains rejected in a pruned branch.
    result("do:\n  if #False:\n    return 1\n    return do:\n      if x:\n        break 2\n  return 3\n",8);
    result("do:\n  return do:\n    break 1\n    break 2\n",8);
    result("do:\n  return do:\n    break do:\n      break 1\n",0);
    result("do:\n  if x:\n    return do:\n      break 1\n  return 2\n",0);
    let source = "do:\n  if x:\n    return f((1, 2), (), g())\n  else:\n    return 2\n";
    var tree, status = flow_parse::parse(source); assert(status == 0 && flow_verify::verify(tree));
    for i in 0..tree.nodes.len {
        let old = tree.nodes[i]; tree.nodes[i].tag = 999; assert(!flow_verify::verify(tree)); tree.nodes[i] = old;
        tree.nodes[i].start = -1; assert(!flow_verify::verify(tree)); tree.nodes[i] = old;
        tree.nodes[i].end = 999999; assert(!flow_verify::verify(tree)); tree.nodes[i] = old;
        tree.nodes[i].a = 999999; assert(!flow_verify::verify(tree)); tree.nodes[i] = old;
        tree.nodes[i].b = -1; assert(!flow_verify::verify(tree)); tree.nodes[i] = old;
        tree.nodes[i].c = 999999; assert(!flow_verify::verify(tree)); tree.nodes[i] = old;
    }
    tree.root = -1; assert(!flow_verify::verify(tree)); assert(flow_completion::check(tree) == 1);
    let bad, b = flow_parse::parse("do:\n  return 4294967296\n"); assert(b != 0 && bad.nodes.len == 0);
    let invalid, e = flow_parse::parse("do:\n  if # True:\n    return 1\n"); assert(e != 0 && invalid.nodes.len == 0);
    // Verify independent source ownership and operator precedence.
    var input: u8[>..] = []; input.append("do:\n  return a || b && c\n");
    var owned, own_status = flow_parse::parse(input); assert(own_status == 0);
    input[0] = 'x'; assert(flow_verify::verify(owned));
    let ret = owned.nodes[owned.root-1]; let expression = owned.nodes[ret.a-1];
    assert(expression.tag == 8 && owned.nodes[expression.b-1].tag == 7);
    owned.source[0] = 'x'; assert(!flow_verify::verify(owned));
    let tuple_source = "do:\n  return f(1,2,3)\n";
    var tuple, ts = flow_parse::parse(tuple_source); assert(ts == 0 && flow_verify::verify(tuple));
    let call = tuple.nodes[tuple.nodes[tuple.root-1].a-1]; assert(call.tag == 6);
    let value = tuple.nodes[call.b-1]; assert(value.tag == 14);
    assert(tuple.source[call.start..call.end] == "f(1,2,3)");
    let pair = tuple.nodes[value.a-1]; assert(pair.tag == 13);
    let prefix = tuple.nodes[pair.a-1]; assert(prefix.tag == 13);
    assert(tuple.source[prefix.start..prefix.end] == "1,2");
    assert(tuple.source[tuple.nodes[pair.b-1].start..tuple.nodes[pair.b-1].end] == "3");
    let bad_call, bc = flow_parse::parse("do:\n  return f(1,)\n"); assert(bc != 0 && bad_call.nodes.len == 0);
    let bad_tuple, btuple = flow_parse::parse("do:\n  return (,1)\n"); assert(btuple != 0 && bad_tuple.nodes.len == 0);
    let wrong_target, bt = flow_parse::parse("do:\n  break 1\n"); assert(bt == 6 && wrong_target.nodes.len == 0);
    let bare_break, bb = flow_parse::parse("do:\n  return do:\n    break\n"); assert(bb == 6 && bare_break.nodes.len == 0);
    let nested_source = "do:\n  return do:\n    break do:\n      break 1\n";
    var nested, ns = flow_parse::parse(nested_source); assert(ns == 0 && flow_verify::verify(nested));
    var first_target: i64 = 0; var second_target: i64 = 0;
    for node in nested.nodes { if node.tag == 16 { if first_target == 0 { first_target = node.b; } else { second_target = node.b; } } }
    assert(first_target != second_target && first_target > second_target && second_target > 0);
    assert(nested.source[first_target-1..first_target+1] == "do");
    assert(nested.source[second_target-1..second_target+1] == "do");
    for i in 0..nested.nodes.len {
        if nested.nodes[i].tag == 16 {
            let old = nested.nodes[i].b;
            nested.nodes[i].b = if old == first_target { second_target } else { first_target };
            assert(!flow_verify::verify(nested));
            nested.nodes[i].b = old;
        }
    }
    let next_call, nc = flow_parse::parse("do:\n  return do:\n    break f\n  (42)\n"); assert(nc != 0 && next_call.nodes.len == 0);
    let next_and, na = flow_parse::parse("do:\n  return do:\n    break x\n  && #False\n"); assert(na != 0 && next_and.nodes.len == 0);
    let next_or, no = flow_parse::parse("do:\n  return do:\n    break x\n  || #True\n"); assert(no != 0 && next_or.nodes.len == 0);
    let missing_line, ml = flow_parse::parse("do:\n  return x return y\n"); assert(ml != 0 && missing_line.nodes.len == 0);
    let crlf, cr = flow_parse::parse("// comment\r\ndo:\r\n  if #True: // comment\r\n    return 1\r\n"); assert(cr == 0 && flow_verify::verify(crlf));
    print("flow syntax and completion laws passed");
}
