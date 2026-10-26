import compiler_core;
import compiler_validate;
import iteration_parse;
fn candidate(s:u8[:]) -> compiler_core::Program {
    let prefix="let f: U32 -> U32 = ";assert(s.len>=prefix.len && s[..prefix.len]==prefix);
    var body,status=iteration_parse::parse(s[prefix.len..]);assert(status==0);
    return compiler_core::Program {source:s,variant:2,name_start:4,name_end:5,fn_start:prefix.len,body:copy(body)};
}
fn valid(s:u8[:]) {var p=candidate(s);assert(compiler_validate::verify(s,p));}
fn invalid(s:u8[:]) {var p=candidate(s);assert(!compiler_validate::verify(s,p));}
fn main() {
    let good="let f: U32 -> U32 = fn x => do:\n  let y = for i in 0..x carry (b=x) do:\n    next (b)\n  return y\n";
    valid(good);
    invalid("let f: U32 -> U32 = fn (x) => do:\n  return x\n");
    valid("let f: U32 -> U32 = fn x => do:\n  for i in 0..x do:\n    continue\n  return x\n");
    valid("let f: U32 -> U32 = fn x => do:\n  let y = for i in 3..3 carry (b=x) do:\n    stop (b)\n  return y\n");
    valid("let f: U32 -> U32 = fn x => do:\n  if #True:\n    return x\n  else:\n    return 1\n");
    invalid("let f: U32 -> U32 = fn x => do:\n  let y = for i in 3..2 carry (b=x) do:\n    next (b)\n  return y\n");
    invalid("let f: U32 -> U32 = fn x => do:\n  for i in x..x do:\n    continue\n  return x\n");
    invalid("let f: U32 -> U32 = fn x => do:\n  if x:\n    return x\n  else:\n    return 1\n");
    invalid("let f: U32 -> U32 = fn x => do:\n  return #True\n");
    invalid("let f: U32 -> U32 = fn x => do:\n  let y = for i in 0..x carry (b=#True) do:\n    next (b)\n  return y\n");
    invalid("let f: U32 -> U32 = fn x => do:\n  let y = for i in 0..x carry (b=x) do:\n    next (#True)\n  return y\n");
    invalid("let f: U32 -> U32 = fn x => do:\n  let y = for i in 0..x do:\n    break\n  return y\n");
    invalid("let f: U32 -> U32 = fn x => do:\n  let y = for i in 0..x carry (b=x) invariant [Eq(i,0)] do:\n    next (b)\n  return y\n");
    var p=candidate(good);assert(compiler_validate::verify(good,p));
    let old_fn=p.fn_start;p.fn_start=-1;assert(!compiler_validate::verify(good,p));p.fn_start=old_fn;
    let old_name=p.name_start;p.name_start=0;assert(!compiler_validate::verify(good,p));p.name_start=old_name;
    p.variant=1;assert(!compiler_validate::verify(good,p));p.variant=2;
    p.scalar.root=1;assert(!compiler_validate::verify(good,p));p.scalar.root=0;
    let original=p.body.nodes[0];p.body.nodes[0].a=999999;assert(!compiler_validate::verify(good,p));p.body.nodes[0]=original;
    let changed="let f: U32 -> U32 = fn x => do:\n  let y = for i in 0..x carry (b=x) do:\n    stop (b)\n  return y\n";
    assert(good.len==changed.len && !compiler_validate::verify(changed,p));
    print("independent whole-source loop type and bounds controls passed");
}
