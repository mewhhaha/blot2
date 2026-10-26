import flow_parse;
import flow_verify;
import flow_completion;
fn result(source: u8[:], expected: i64) {
    var tree, status = flow_parse::parse(source);
    assert(status == 0); assert(flow_verify::verify(tree)); assert(flow_completion::check(tree) == expected);
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
    let source = "do:\n  if x:\n    return f(1)\n  else:\n    return 2\n";
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
    let bad_call, bc = flow_parse::parse("do:\n  return f(1,2)\n"); assert(bc != 0 && bad_call.nodes.len == 0);
    let wrong_target, bt = flow_parse::parse("do:\n  break 1\n"); assert(bt != 0 && wrong_target.nodes.len == 0);
    let missing_line, ml = flow_parse::parse("do:\n  return x return y\n"); assert(ml != 0 && missing_line.nodes.len == 0);
    let crlf, cr = flow_parse::parse("// comment\r\ndo:\r\n  if #True: // comment\r\n    return 1\r\n"); assert(cr == 0 && flow_verify::verify(crlf));
    print("flow syntax and completion laws passed");
}
