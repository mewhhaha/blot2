import affine_parse;
import affine_verify;
import affine_check;
fn test(source:u8[:], mode:i64, want:i64) {
    var parsed=affine_parse::parse(source);
    assert(parsed.status==0);
    assert(affine_verify::verify(parsed.tree));
    assert(affine_check::check(parsed.tree,source,mode)==want);
}
fn main() {
    test("do:\n  owned.close(h)\n  return ()\n",0,0);
    test("do:\n  let m = h\n  return m\n",1,0);
    test("do:\n  if flag:\n    owned.close(h)\n    return ()\n  else:\n    owned.close(h)\n    return ()\n",0,0);
    test("do:\n  if flag:\n    owned.close(h)\n    return ()\n  owned.close(h)\n  return ()\n",0,0);
    test("do:\n  if flag:\n    let m = h\n    owned.close(m)\n  else:\n    owned.close(h)\n  return ()\n",0,0);
    test("do:\n  if flag:\n    let m = h\n    return m\n  else:\n    return h\n",1,0);
    test("do:\n  let value = owned.open(h) as r payload in do:\n    if flag:\n      break payload\n    else:\n      break payload\n  owned.close(h)\n  return ()\n",0,0);
    test("do:\n  return ()\n",0,2);
    test("do:\n  return m\n",1,2);
    test("do:\n  let m = h\n  return h\n",1,2);
    test("do:\n  owned.close(h)\n  owned.close(h)\n  return ()\n",0,2);
    test("do:\n  let m = h\n  let m = h\n  return m\n",1,2);
    test("do:\n  let value = owned.open(h) as r payload in do:\n    owned.close(h)\n    break payload\n  return ()\n",0,3);
    test("do:\n  let value = owned.open(h) as r payload in do:\n    let m = h\n    break payload\n  owned.close(h)\n  return ()\n",0,3);
    test("do:\n  let value = owned.open(h) as r payload in do:\n    return h\n  owned.close(h)\n  return ()\n",1,3);
    test("do:\n  if flag:\n    owned.close(h)\n  else:\n    let m = h\n  return ()\n",0,4);
    test("do:\n  if flag:\n    owned.close(h)\n  return ()\n",0,4);
    test("do:\n  if flag:\n    owned.close(h)\n    return ()\n",0,5);
    test("do:\n  let value = owned.open(h) as r payload in do:\n    if flag:\n      break payload\n  owned.close(h)\n  return ()\n",0,5);
    test("do:\n  owned.close(h)\n  return ()\n  owned.close(h)\n",0,6);
    test("do:\n  break payload\n",0,7);
    let source="do:\n  owned.close(h)\n  return ()\n";
    var valid=affine_parse::parse(source); assert(valid.status==0 && affine_verify::verify(valid.tree));
    assert(affine_check::check(valid.tree,"do:\n  owned.close(h)\n  return h\n",0)==1);
    assert(affine_check::check(valid.tree,source,9)==1);
    for i in valid.tree.nodes.len {
        let save=valid.tree.nodes[i]; valid.tree.nodes[i].tag=99;
        assert(!affine_verify::verify(valid.tree));
        assert(affine_check::check(valid.tree,source,0)==1);
        valid.tree.nodes[i]=save;
    }
    print("source-checked affine branches and lexical loans passed");
}
