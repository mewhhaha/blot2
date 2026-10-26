import std;
import static_compound_core;
import static_compound_build;
import static_compound_verify;
import static_compound_eval;
fn chain(n:i64)->u8[>..] {
 var out:u8[>..]=[];for i in n {
  if i+1==n {format(out,"let f",i,": U32 -> U32 = fn x => return x\n");}
  else {format(out,"let f",i,": U32 -> U32 = fn x => return f",i+1,"(x)\n");}
 }
 out.append("static let answer = #[(f0(7), 0.0 / 0.0)]\n");return out;
}
fn main() {
 let source="let f: U32 -> U32 = fn x => return g(x)\nlet g: U32 -> U32 = fn x => return x & 3\nstatic let a = #[(f(7), -0.0), (f(10), 0.0 / 0.0)]\n";
 var built=static_compound_build::build(source);assert(built.status==0 && static_compound_verify::verify(source,built.program));
 let result=static_compound_eval::evaluate(source,built.program);
 let expected:u8[16]=[3,0,0,0,0,0,0,128,2,0,0,0,0,0,192,127];
 assert(result.status==0 && result.depth==2 && result.bytes==16 && result.data[..]==expected[..]);
 for i in built.program.calls.len {for field in 5 {
  var bad=copy(built.program);
  if field==0 {bad.calls[i].start+=1;}else if field==1 {bad.calls[i].end+=1;}else if field==2 {bad.calls[i].name_end+=1;}
  else if field==3 {bad.calls[i].argument+=1;}else {bad.calls[i].target+=1;}
  assert(!static_compound_verify::verify(source,bad) && static_compound_eval::evaluate(source,bad).data.len==0);
 }}
 var forged=copy(built.program);forged.projection[forged.calls[0].start]='9';assert(!static_compound_verify::verify(source,forged));
 var swapped=copy(built.program);let a=swapped.calls[0];swapped.calls[0]=swapped.calls[1];swapped.calls[1]=a;assert(!static_compound_verify::verify(source,swapped));
 for n in [1,127,128] {let src=chain(n);var p=static_compound_build::build(src);assert(p.status==0 && static_compound_verify::verify(src,p.program));
  let v=static_compound_eval::evaluate(src,p.program);assert(v.status==0 && v.depth==n && v.data[0]==7);}
 let deep=chain(129);assert(static_compound_build::build(deep).status!=0);
 for bad in ["let f: U32 -> U32 = fn x => return f(x)\nstatic let a = (f(1), 0)",
  "let f: U32 -> U32 = fn x => return host(x)\nstatic let a = (f(1), 0)",
  "let f: U32 -> U32 = fn x => return x\nstatic let a = (f(1)+2, 0)",
  "let f: U32 -> U32 = fn x => return x\nstatic let a = (f(1), g(2))",
  "let f: U32 -> U32 = fn x => return x\nstatic let f = (f(1), 0)"] {assert(static_compound_build::build(bad).status!=0);}
 let fail="let f: U32 -> U32 = fn x => return x\nstatic let a = #[(f(1), 4294967295+1), (f(2), 0)]";
 var failed=static_compound_build::build(fail);assert(failed.status==0);let err=static_compound_eval::evaluate(fail,failed.program);
 assert(err.status==3 && err.steps==6 && err.data.len==0);
 for extra in [4,5] {
  var src:u8[>..]=[];src.append("let f: U32 -> U32 = fn x => return x\nstatic let a = #[(f(1),");
  for _ in extra {src.push('(');}src.push('0');for _ in extra {src.push(')');}src.push(')');
  for _ in 19998 {src.append(",(f(1),0)");}src.append("]\n");
  var p=static_compound_build::build(src);assert(p.status==0 && static_compound_verify::verify(src,p.program));
  let v=static_compound_eval::evaluate(src,p.program);assert(v.steps==100000);
  if extra==4 {assert(v.status==0 && v.bytes==159992);}else {assert(v.status==2 && v.data.len==0);}
 }
 print("private source-bound aggregate and pure scalar calls passed");
}
