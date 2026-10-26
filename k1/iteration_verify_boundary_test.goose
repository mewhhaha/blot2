// Boundary and source-mutation differential for private iteration syntax.
import std;
import iteration_parse;
import iteration_verify;
fn good(s:u8[:]) {var t,st=iteration_parse::parse(s);assert(st==0 && iteration_verify::verify(t,s));}
fn bad(s:u8[:]) {var t,st=iteration_parse::parse(s);assert(st!=0 && !iteration_verify::verify(t,s));}
fn mutations(source:u8[:]) {
 var bytes:u8[>..]=[];bytes.append(source);
 for i in bytes.len {let old=bytes[i];for replacement in [0 as u8,' ','\n','x','0',')',255] {
  bytes[i]=replacement;var t,st=iteration_parse::parse(bytes);
  if st==0 {assert(iteration_verify::verify(t,bytes));} else {assert(t.nodes.len==0 && !iteration_verify::verify(t,bytes));}
 } bytes[i]=old;}
}
fn main() {
 mutations("fn (n,z) => do:\n  let r = for i in 0..n carry (b = z)\n    invariant [Eq(Init(b),i)] do:\n      next(b)\n  return r\n");
 mutations("fn (n) => do:\n  for i in 0..n do:\n    if #True:\n      continue\n    else:\n      break\n  return n\n");
 var statements:u8[>..]=[];statements.append("fn () => do:\n");for i in 32 {statements.append("  return 0\n");} good(statements);
 statements.append("  return 0\n");bad(statements);
 var params:u8[>..]=[];params.append("fn (");for i in 16 {if i>0 {params.append(",");} format(params,"p",i);} params.append(") => do:\n  return p0\n");good(params);
 var too_many:u8[>..]=[];too_many.append("fn (");for i in 17 {if i>0 {too_many.append(",");} format(too_many,"p",i);} too_many.append(") => do:\n  return p0\n");bad(too_many);
 var carries:u8[>..]=[];carries.append("fn (n,z) => do:\n  let r = for i in 0..n carry (");
 for i in 16 {if i>0 {carries.append(",");}format(carries,"b",i,"=z");} carries.append(") do:\n    next(");
 for i in 16 {if i>0 {carries.append(",");}format(carries,"b",i);}carries.append(")\n  return r\n");good(carries);
 var too_carries:u8[>..]=[];too_carries.append("fn (n,z) => do:\n  let r = for i in 0..n carry (");
 for i in 17 {if i>0 {too_carries.append(",");}format(too_carries,"b",i,"=z");} too_carries.append(") do:\n    next(");
 for i in 17 {if i>0 {too_carries.append(",");}format(too_carries,"b",i);}too_carries.append(")\n  return r\n");bad(too_carries);
 var many_facts:u8[>..]=[];many_facts.append("fn (n,z) => do:\n  let r = for i in 0..n carry (b = z) invariant [");for i in 32 {if i>0 {many_facts.append(",");} many_facts.append("Eq(i,n)");}many_facts.append("] do:\n    next(b)\n  return r\n");good(many_facts);
 var too_facts:u8[>..]=[];too_facts.append("fn (n,z) => do:\n  let r = for i in 0..n carry (b = z) invariant [");for i in 33 {if i>0 {too_facts.append(",");} too_facts.append("Eq(i,n)");}too_facts.append("] do:\n    next(b)\n  return r\n");bad(too_facts);
 var nested:u8[>..]=[];nested.append("fn (n) => do:\n");for i in 32 {for j in 2*(i+1) {nested.push(' ');}format(nested,"for i",i," in 0..n do:\n");}for j in 66 {nested.push(' ');}nested.append("continue\n  return n\n");good(nested);
 var too_nested:u8[>..]=[];too_nested.append("fn (n) => do:\n");for i in 33 {for j in 2*(i+1) {too_nested.push(' ');}format(too_nested,"for i",i," in 0..n do:\n");}for j in 68 {too_nested.push(' ');}too_nested.append("continue\n  return n\n");bad(too_nested);
 print("independent finite-loop syntax limits and source mutations passed");
}
