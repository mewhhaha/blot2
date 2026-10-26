import compiler_frontend;
import compiler_validate;
import compiler_wasm;
import format_k1_formatter;
fn main() {
 let scalar="let f: U32 -> U32 = fn x => do:\n  return x\n";
 let loop_source="let f: U32 -> U32 = fn x => do:\n  let r = for i in 0..x carry (a=0) do:\n    next (a)\n  return r\n";
 let mixed="let f: U32 -> U32 = fn x => do:\n  let r = for i in 0..x carry (a=0) do:\n    next (U32.wrapping_add(a,i))\n  return r\n";
 for s,i in [scalar,loop_source,mixed] {
   var p=compiler_frontend::parse(s);assert(p.status==0 && p.program.variant==i+1 && compiler_validate::verify(s,p.program) && compiler_wasm::emit(s,p.program).len>0);
   assert(!compiler_validate::verify("wrong source",p.program) && compiler_wasm::emit("wrong source",p.program).len==0);
   let old=p.program.variant;p.program.variant=8;assert(!compiler_validate::verify(s,p.program));p.program.variant=old;
   if i<2 {p.program.mixed.variant=2;assert(!compiler_validate::verify(s,p.program));p.program.mixed.variant=0;
      p.program.mixed.scalar.param_start=1;assert(!compiler_validate::verify(s,p.program));p.program.mixed.scalar.param_start=0;
      p.program.mixed.body.root=1;assert(!compiler_validate::verify(s,p.program));p.program.mixed.body.root=0;}
   else {p.program.name_start=1;assert(!compiler_validate::verify(s,p.program));p.program.name_start=0;
      p.program.scalar.param_start=1;assert(!compiler_validate::verify(s,p.program));p.program.scalar.param_start=0;
      p.program.body.root=1;assert(!compiler_validate::verify(s,p.program));p.program.body.root=0;
      p.program.mixed.variant=1;assert(!compiler_validate::verify(s,p.program));p.program.mixed.variant=2;
      let oldnode=p.program.mixed.body.nodes[0];p.program.mixed.body.nodes[0].a=999999;assert(!compiler_validate::verify(s,p.program));p.program.mixed.body.nodes[0]=oldnode;
      let result=format_k1_formatter::format(s);assert(result.status!=0 && result.source.len==0);}
   assert(compiler_validate::verify(s,p.program));
 }
 for s in ["let f: U32 -> U32 = fn x => do:\n  return missing\n", "let f: U32 -> U32 = fn x => do:\n  return x + 1\n", "not a K1 program", "let f: U32 -> U32 = fn x => do:\n  return x\n  return x\n"] {
  let a=compiler_frontend::legacy_parse(s);let b=compiler_frontend::parse(s);assert(a.status!=0 && a.status==b.status);
 }
 print("independent adapter source/variant/status audit passed");
}
