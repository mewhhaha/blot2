import std;
import os;
import typed_dispatch;
import short_frontend;
import short_check;
import short_emit;
import short_legacy_wasm;
fn main(){var matched:i64=0;
 for form in 2 {for multiline in 2 {for l in ["x","0","7","4294967295"] {for r in ["x","0","7","4294967295"] {
  let sig=if form==0 {"U32 -> Bool"} else {"Fn[static,Many,U32,Bool]"};let body=if multiline==0 {str("return ",l," < ",r,"\n")} else {str("do:\n  return ",l," < ",r,"\n")};
  let source=str("pub let pred: ",sig," ! {} resources {depth: 1, frame: 0} = fn x => ",body);let old=typed_dispatch::compile(source);var p=short_frontend::parse(source);assert(p.status==0 && short_check::verify(source,p.program));let candidate=short_legacy_wasm::emit(source,p.program);
  if old.status==0 {assert(candidate.len>0 && old.wasm[..]==candidate[..]);matched+=1;}
  if form==0 && multiline==0 {assert(candidate.len>0 && write_file(str("single-",l,"-",r,".wasm"),candidate));}
  var bad=copy(p.program);bad.tree.nodes[bad.tree.root-1].a=bad.tree.root;assert(!short_check::verify(source,bad) && short_legacy_wasm::emit(source,bad).len==0);
  var alter=copy(source);alter[0]^=1;assert(!short_check::verify(alter,p.program) && short_legacy_wasm::emit(alter,p.program).len==0);
 }}}}assert(matched>0);
 for s in ["pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return missing < x\n", "pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x + 1 < 5\n", "pub let f: U32 -> Bool ! {host} resources {depth: 1, frame: 0} = fn x => return x < 5\n", "pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => let y = x\n", "pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x < 5\nreturn #False\n"] {let p=short_frontend::parse(s);assert(p.status!=0);}
 print("source-bound single-line predicate and exact legacy target compatibility passed ",matched);
}
