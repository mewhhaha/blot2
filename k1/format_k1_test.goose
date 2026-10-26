import compiler_frontend;
import format_k1_formatter;
import format_k1_check;
fn stable(source:u8[:],expected:u8[:]) {
    var input:u8[>..]=[];input.append(source);let formatted=format_k1_formatter::format(input);
    assert(formatted.status==0 && formatted.source[..]==expected && input[..]==source);
    let twice=format_k1_formatter::format(formatted.source);assert(twice.status==0 && twice.source[..]==formatted.source[..]);
}
fn main() {
    let scalar="let f: U32 -> U32 = fn x => do:  \r\n  let y = x + 0 \t\r\n   \r\n  // retain all comment spaces   \r\n  if y < 4294967295: \r\n    return y + 1 // keep tail   \r\n  return x   \r\n";
    let expected="let f: U32 -> U32 = fn x => do:\n  let y = x + 0\n   \n  // retain all comment spaces   \n  if y < 4294967295:\n    return y + 1 // keep tail   \n  return x\n";
    stable(scalar,expected);
    stable("let f: U32 -> U32 = fn x => do:\n  return x", "let f: U32 -> U32 = fn x => do:\n  return x");
    let loops="let f: U32 -> U32 = fn x => do:  \r\n  let outer = for i in 0..x carry (a=7) do:  \r\n    let inner = for j in 0..2 carry (b=a) do: \r\n      if #True: \r\n        next (j)  \r\n      else: \r\n        stop (b)\r\n    next (inner) \r\n  return outer \r\n";
    let normal="let f: U32 -> U32 = fn x => do:\n  let outer = for i in 0..x carry (a=7) do:\n    let inner = for j in 0..2 carry (b=a) do:\n      if #True:\n        next (j)\n      else:\n        stop (b)\n    next (inner)\n  return outer\n";
    stable(loops,normal);
    var before=compiler_frontend::parse(loops);var after=compiler_frontend::parse(normal);
    assert(before.status==0 && after.status==0 && before.program.variant==2 && after.program.variant==2);
    assert(format_k1_check::equivalent(before.program,after.program));
    var shifted=false;
    for n,i in before.program.body.nodes {if n.target!=0 && n.target!=after.program.body.nodes[i].target {shifted=true;}}
    assert(shifted); // targets remain structurally equal despite moved bytes
    for i in after.program.body.nodes.len {
        if after.program.body.nodes[i].tag==9 || after.program.body.nodes[i].tag==10 {
            let saved=after.program.body.nodes[i].target;after.program.body.nodes[i].target=1;
            assert(!format_k1_check::equivalent(before.program,after.program));after.program.body.nodes[i].target=saved;
        }
    }
    for invalid in [
      "let f: U32 -> U32 = fn x => do:\n  return x + 1\n",
      "let f: U32 -> U32 = fn x => do:\n  for i in x..x do:\n    continue\n  return x\n",
      "let f: U32 -> U32 = fn x => do:\n  for i in 0..x do:\n    next (i)\n  return x\n",
      "let f: F32 -> F32 = fn x => do:\n  return x\n"
    ] {let result=format_k1_formatter::format(invalid);assert(result.status!=0 && result.source.len==0);}
    print("private K1 formatter round-trip and lexical targets passed");
}
