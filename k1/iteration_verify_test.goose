// Producer/independent-recognizer differential and forged-tree controls for
// the private bounded iteration syntax subset. This is not K1 type/proof/loan
// admission or executable-loop qualification.
import iteration_core;
import iteration_parse;
import iteration_verify;
fn accepted(source: u8[:]) {
    var tree,status=iteration_parse::parse(source);
    assert(status==0 && iteration_verify::verify(tree,source));
    for i in tree.nodes.len { for field in 11 {
        var bad=copy(tree);
        if field==0 {bad.nodes[i].tag+=1;} else if field==1 {bad.nodes[i].start+=1;}
        else if field==2 {bad.nodes[i].end+=1;} else if field==3 {bad.nodes[i].a+=1;}
        else if field==4 {bad.nodes[i].b+=1;} else if field==5 {bad.nodes[i].c+=1;}
        else if field==6 {bad.nodes[i].d+=1;} else if field==7 {bad.nodes[i].e+=1;}
        else if field==8 {bad.nodes[i].f+=1;} else if field==9 {bad.nodes[i].g+=1;}
        else {bad.nodes[i].target+=1;}
        assert(!iteration_verify::verify(bad,source));
    } }
    for i in tree.bindings.len { for field in 4 {
        var bad=copy(tree);
        if field==0 {bad.bindings[i].start+=1;} else if field==1 {bad.bindings[i].end+=1;}
        else if field==2 {bad.bindings[i].kind+=1;} else {bad.bindings[i].scope+=1;}
        assert(!iteration_verify::verify(bad,source));
    } }
    var bad=copy(tree); bad.root=-1; assert(!iteration_verify::verify(bad,source));
    assert(!iteration_verify::verify(tree,"different source"));
}
fn rejected(source: u8[:]) { var tree,status=iteration_parse::parse(source); assert(status!=0 && !iteration_verify::verify(tree,source)); }
fn main() {
    accepted("fn (n,z) => do:\n  let result = for i in 0..n carry (b = z)\n    invariant [Eq(Init(b),i)] do:\n      next(b)\n  return result\n");
    accepted("fn (n) => do:\n  for i in 0..n do:\n    if #True:\n      continue\n    else:\n      break\n  return n\n");
    accepted("fn (n,z) => do:\n  let result = for i in 0..n carry (b = z) do:\n    let inner = for j in 0..n carry (c = b) do:\n      stop(c)\n    next(b)\n  return result\n");
    accepted("fn (n,z,d) => do:\n  let result = for i in 0..n carry (b = z) invariant [Le(i,n), Eq(Init(b),i), Index(d,n,i)] do:\n    next(b)\n  return result\n");
    // Coordinate a forged source and node so exact-byte equality alone cannot
    // reject the illegal Index literal. The recognizer checks the source rule.
    let index_source="fn (n,z,d) => do:\n  let r = for i in 0..n carry (b = z) invariant [Index(d,n,i)] do:\n    next(b)\n  return r\n";
    var forged,forge_status=iteration_parse::parse(index_source); assert(forge_status==0);
    var changed:u8[>..]=[];changed.append(index_source); var changed_count:i64=0;
    for i in forged.nodes.len {
        let node=forged.nodes[i];
        if node.tag==1 && node.start>=6 && changed[node.start-6..node.start]=="Index(" {
            changed[node.start]='1'; forged.source[node.start]='1';
            forged.nodes[i].tag=2; forged.nodes[i].a=0; changed_count+=1;
        }
    }
    assert(changed_count==1 && !iteration_verify::verify(forged,changed));
    accepted("fn () => do:\n  return 42\n");
    rejected("fn (n) => do:\n  next(n)\n");
    rejected("fn (n) => do:\n  for i in 0..n do:\n    next(i)\n  return n\n");
    rejected("fn (n,z) => do:\n  let r = for i in 0..n carry (b = z) do:\n    break\n  return r\n");
    rejected("fn (n,z) => do:\n  let r = for i in 0..n carry (b = b) do:\n    next(b)\n  return r\n");
    rejected("fn (n,z) => do:\n  let r = for i in 0..n carry (b = z) do:\n    next(b,z)\n  return r\n");
    rejected("fn (n,z) => do:\n  let r = for i in 0..n carry (b = z, b = z) do:\n    next(b,b)\n  return r\n");
    rejected("fn (n,z) => do:\n  let r = for i in 0..n carry (b = z) invariant [Index(1,n,i)] do:\n    next(b)\n  return r\n");
    rejected("fn (n,z) => do:\n  let r = for i in 0..n carry (b = z) invariant [Index(Len(n),n,i)] do:\n    next(b)\n  return r\n");
    print("independent finite-loop syntax verifier passed");
}
