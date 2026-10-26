import iteration_core;
import iteration_parse;
import iteration_verify;
import iteration_completion;
fn copied(tree: iteration_core::Tree&) -> iteration_core::Tree {
    return iteration_core::Tree { source:copy(tree.source),bindings:copy(tree.bindings),nodes:copy(tree.nodes),root:tree.root };
}
fn accepted(source: u8[:], completion: i64) {
    var tree,status=iteration_parse::parse(source); assert(status==0);
    assert(iteration_verify::verify(tree,source)); assert(iteration_completion::check(tree,source)==completion);
}
fn rejected(source: u8[:], expected: i64) {
    var tree,status=iteration_parse::parse(source); assert(status==expected);
    assert(!iteration_verify::verify(tree,source));
}
fn main() {
    let source="fn (n, initial, flag) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i), Le(i,n)] do:\n      if flag:\n        next (b)\n      else:\n        stop (b)\n  return built\n";
    var tree,status=iteration_parse::parse(source); assert(status==0 && iteration_verify::verify(tree,source));
    assert(iteration_completion::check(tree,source)==0 && tree.bindings.len==6);
    var target: i64=0; var seen=0;
    for node in tree.nodes { if node.tag==15 { target=node.target; } }
    for node in tree.nodes { if node.tag==9 || node.tag==10 { assert(node.target==target && node.b==1); seen+=1; } }
    assert(seen==2);
    // A loop nested in a carrying loop cannot steal or skip the innermost
    // transfer target; loop-local names disappear when that scope ends.
    accepted("fn (n, initial, flag) => do:\n  let result = for i in 0..n carry (a = initial)\n    invariant [Eq(Init(a),i)] do:\n      for j in 0..n do:\n        if flag:\n          break\n        else:\n          continue\n      next (a)\n  return result\n",0);
    accepted("fn (n, initial) => do:\n  let result = for i in 0..n carry (a = initial)\n    invariant [Eq(Init(a),i)] do:\n      let inner = for j in 0..n carry (b = a)\n        invariant [Eq(Init(b),j)] do:\n          next (b)\n      next (inner)\n  return result\n",0);
    accepted("fn (n, x, y, d) => do:\n  let result = for i in 0..n carry (a = x, b = y) invariant [Index(d,n,i), Eq(Init(a),i), Le(Init(b),n)] do:\n    next (a, b)\n  return result\n",0);
    accepted("fn (n) => do:\n  for i in 0..n do:\n    continue\n  return n\n",0);
    accepted("fn (n) => do:\n  for i in 0..n do:\n    break\n",4); // function fallthrough
    accepted("fn (n, initial, flag) => do:\n  let x = for i in 0..n carry (a = initial) do:\n    if flag:\n      next (a)\n  return x\n",9); // missing transfer on false arm
    accepted("fn (n, initial) => do:\n  let x = for i in 0..n carry (a = initial) do:\n    next (a)\n    next (a)\n  return x\n",8); // unreachable
    accepted("fn () => do:\n  if #True:\n    return 1\n  else:\n    return 0\n",0);
    accepted("fn () => do:\n  if #False:\n    return 1\n",4);
    // Literal pruning suppresses a missing-transfer obligation in the dead
    // outer arm; true or unknown conditions retain that obligation.
    accepted("fn (flag) => do:\n  if #False:\n    for i in 0..3 do:\n      if flag:\n        continue\n  return 0\n",0);
    accepted("fn (flag) => do:\n  if #True:\n    for i in 0..3 do:\n      if flag:\n        continue\n  return 0\n",9);
    accepted("fn (flag) => do:\n  if flag:\n    for i in 0..3 do:\n      if flag:\n        continue\n  return 0\n",9);
    accepted("fn (flag) => do:\n  if #True:\n    for i in 0..1 do:\n      continue\n  else:\n    for j in 0..1 do:\n      if flag:\n        continue\n  return 0\n",0);
    accepted("fn (flag) => do:\n  if #False:\n    for i in 0..1 do:\n      continue\n  else:\n    for j in 0..1 do:\n      if flag:\n        continue\n  return 0\n",9);
    accepted("fn (flag) => do:\n  if flag:\n    for i in 0..1 do:\n      continue\n  else:\n    for j in 0..1 do:\n      if flag:\n        continue\n  return 0\n",9);
    accepted("fn (flag) => do:\n  for i in 0..1 do:\n    if #False:\n      for j in 0..1 do:\n        if flag:\n          continue\n    continue\n  return 0\n",0);
    accepted("fn (flag) => do:\n  for i in 0..1 do:\n    if #True:\n      for j in 0..1 do:\n        if flag:\n          continue\n    continue\n  return 0\n",9);
    accepted("fn (flag) => do:\n  for i in 0..1 do:\n    if flag:\n      for j in 0..1 do:\n        if flag:\n          continue\n    continue\n  return 0\n",9);
    // Unreachable-statement diagnostics deliberately remain conservative in
    // a pruned arm, as stated in iteration_completion.goose.
    accepted("fn () => do:\n  if #False:\n    return 0\n    return 1\n  return 2\n",8);
    // These syntax cases are not semantically typed: U32 if tests or Bool
    // values may be rejected by a later type checker.
    accepted("fn () => do:\n  if 1:\n    return #True\n  else:\n    return 0\n",0);
    rejected("fn () => do:\n  next (1)\n",5);
    rejected("fn (n) => do:\n  for i in 0..n do:\n    stop (i)\n  return n\n",5);
    rejected("fn (n,x) => do:\n  let r = for i in 0..n carry (b=x) do:\n    break\n  return r\n",5);
    rejected("fn (n,x) => do:\n  let r = for i in 0..n carry (b=x) do:\n    next (b,b)\n  return r\n",6);
    rejected("fn (n,x) => do:\n  let r = for i in i..n carry (b=x) do:\n    next (b)\n  return r\n",3);
    rejected("fn (n) => do:\n  let r = for i in 0..n carry (b=b) do:\n    next (b)\n  return r\n",3);
    rejected("fn (n,x) => do:\n  let r = for i in 0..n carry (b=x) do:\n    next (b)\n  return b\n",3);
    rejected("fn (n,x) => do:\n  let r = for i in 0..n carry (b=x) do:\n    next (r)\n  return r\n",3);
    rejected("fn (n,n) => do:\n  return n\n",4);
    rejected("fn (n,x) => do:\n  let r = for i in 0..n carry (i=x) do:\n    next (i)\n  return r\n",4);
    rejected("fn (n,x) => do:\n  let r = for i in 0..n carry (b=x, b=x) do:\n    next (b,b)\n  return r\n",4);
    rejected("fn (n,x) => do:\n  let r = for i in 0..n carry (a=x) do:\n    for j in 0..n do:\n      next (a)\n    next (a)\n  return r\n",5);
    rejected("fn (n,x) => do:\n  let r = for i in 0..n carry (a=x) do:\n    next (builder.append(a,x))\n  return r\n",1); // calls excluded
    rejected("fn (n,x) => do:\n  let r = for i in 0..n carry (a=x) invariant [Index(0,n,i)] do:\n    next (a)\n  return r\n",1);
    rejected("fn (n,x) => do:\n  let r = for i in 0..n carry (a=x) invariant [Index(Init(a),n,i)] do:\n    next (a)\n  return r\n",1);
    // Every material record must be reconstructed from source. Forge each
    // field, including zeros, targets and bindings, before completion.
    for index in tree.nodes.len { for field in 11 {
        var bad=copied(tree);
        if field==0 { bad.nodes[index].tag+=1; } else if field==1 { bad.nodes[index].start+=1; }
        else if field==2 { bad.nodes[index].end+=1; } else if field==3 { bad.nodes[index].a+=1; }
        else if field==4 { bad.nodes[index].b+=1; } else if field==5 { bad.nodes[index].c+=1; }
        else if field==6 { bad.nodes[index].d+=1; } else if field==7 { bad.nodes[index].e+=1; }
        else if field==8 { bad.nodes[index].f+=1; } else if field==9 { bad.nodes[index].g+=1; }
        else { bad.nodes[index].target+=1; }
        assert(!iteration_verify::verify(bad,source)); assert(iteration_completion::check(bad,source)==1);
    } }
    for index in tree.bindings.len { for field in 4 {
        var bad=copied(tree);
        if field==0 { bad.bindings[index].start+=1; } else if field==1 { bad.bindings[index].end+=1; }
        else if field==2 { bad.bindings[index].kind+=1; } else { bad.bindings[index].scope+=1; }
        assert(!iteration_verify::verify(bad,source));
    } }
    for index in source.len { var bad=copied(tree); bad.source[index]='?'; assert(!iteration_verify::verify(bad,source)); }
    var wrongroot=copied(tree); wrongroot.root-=1; assert(!iteration_verify::verify(wrongroot,source));
    var owned: u8[>..]=[]; owned.append(source); var own, own_status=iteration_parse::parse(owned);
    assert(own_status==0); owned[0]='?'; assert(iteration_verify::verify(own,source));
    var oversized: u8[>..]=[32;65537]; let _,limit=iteration_parse::parse(oversized); assert(limit==2);
    print("private finite iteration syntax, targets and completion passed");
}
