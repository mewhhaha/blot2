import static_parse;
import static_verify;
import static_eval;
import static_budget;
recursive fn balanced(n:i64,out:u8[>..]&) {
    if n==1 {out.push('0');return;}
    out.push('(');balanced(n/2,out);out.push('+');balanced(n-n/2,out);out.push(')');
}
fn accepted(s:u8[:],ty:i64,bits:u32) {
    var p=static_parse::parse(s);if p.status!=0 {print("parse ",p.status," ",s);}assert(p.status==0 && static_verify::verify(s,p.tree));
    let value=static_eval::evaluate(s,p.tree);if value.status!=0 {print("eval ",value.status," ",s);}
    assert(value.status==0 && value.ty==ty && value.bits==bits && value.steps==p.tree.nodes.len && value.bytes==4);
}
fn main() {
 accepted("static let x: U32 = 1 + 2 * 3\n",1,7);
 accepted("static let x: U32 = (1 + 2) * 3 & 7\n",1,1);
 accepted("static let x: U32 = U32.wrapping_add(4294967295,1)\n",1,0);
 accepted("static let x: U32 = U32.wrapping_sub(0,1)\n",1,4294967295);
 accepted("static let x: U32 = U32.wrapping_mul(4294967295,2)\n",1,4294967294);
 accepted("static let f: F32 = 3.0 + 4.0\n",2,0x40e00000);
 accepted("static let f: F32 = -0.0\n",2,0x80000000);
 accepted("static let f: F32 = 0.0 / 0.0\n",2,0x7fc00000);
 accepted("static let f: F32 = 1.0 / 0.0\n",2,0x7f800000);
 accepted("static let f: F32 = (16777216.0 + 1.0) - 16777216.0\n",2,0);
 accepted("static let f: F32 = 0.5 * 3.0\n",2,0x3fc00000);
 for s in ["static let x: U32 = 4294967295 + 1\n","static let x: U32 = 0 - 1\n","static let x: U32 = 65536 * 65536\n"] {
   var p=static_parse::parse(s);assert(p.status==0 && static_verify::verify(s,p.tree));let r=static_eval::evaluate(s,p.tree);assert(r.status==3 && r.bytes==0);
 }
 for s in ["let x: U32 = 1\n","static let x: U32 = -1\n","static let x: U32 = 1 / 2\n",
            "static let x: F32 = 16777217.0\n","static let x: F32 = 1.25\n","static let x: F32 = 1e2\n",
            "static let x: U32 = runtime_identity()\n","static let x: U32 = 1.0 + 2\n"] {
   assert(static_parse::parse(s).status!=0);
 }
 assert(static_parse::parse("static let x: U32 = 1 + \r").status==1);
 var budget=static_budget::Budget {};
 for _ in 100000 {assert(static_budget::step(budget));}
 assert(!static_budget::step(budget) && budget.steps==100000 && budget.failed);
 var storage=static_budget::Budget {};assert(static_budget::produce(storage,4194304));assert(!static_budget::produce(storage,1));
 assert(static_budget::enter(128) && !static_budget::enter(129));
 var forged_budget=static_budget::Budget {bytes:4294967295};assert(!static_budget::produce(forged_budget,1));
 // Source/Core mismatches reject before any evaluation/publication.
 let s="static let x: U32 = 1 + 2\n";var p=static_parse::parse(s);assert(p.status==0);
 assert(!static_verify::verify("static let x: U32 = 1 + 3\n",p.tree));
 for i in p.tree.nodes.len {let old=p.tree.nodes[i];p.tree.nodes[i].literal ^= 1;assert(!static_verify::verify(s,p.tree));assert(static_eval::evaluate(s,p.tree).status==1);p.tree.nodes[i]=old;}
 // The fixture's expression-tree cap is distinct from K1 static call depth;
 // the source parser's own parenthesis depth remains small here.
 var deep:u8[>..]=[];deep.append("static let x: U32 = 0");for _ in 127 {deep.append(" + 0");}deep.push('\n');
 var d=static_parse::parse(deep);assert(d.status==0 && static_verify::verify(deep,d.tree));
 assert(static_eval::evaluate(deep,d.tree).status==0);
 deep.pop();deep.append(" + 0\n");
 var d2=static_parse::parse(deep);assert(d2.status==0 && static_verify::verify(deep,d2.tree));
 let limited=static_eval::evaluate(deep,d2.tree);assert(limited.status==2 && limited.bytes==0);
 var ordered:u8[>..]=[];ordered.append("static let x: U32 = 4294967295");for _ in 127 {ordered.append(" + 0");}ordered.append(" + 1\n");
 var ordered_tree=static_parse::parse(ordered);assert(ordered_tree.status==0);
 let ordered_result=static_eval::evaluate(ordered,ordered_tree.tree);assert(ordered_result.status==2 && ordered_result.bytes==0);
 // Balanced expressions reach the exact primitive ceiling without exceeding
 // depth 128. The first rejected operation cannot publish a partial value.
 for leaves in [33334,33335] {
   var program:u8[>..]=[];program.append("static let x: U32 = ");balanced(leaves,program);program.push('\n');
   var tree=static_parse::parse(program);assert(tree.status==0 && static_verify::verify(program,tree.tree));
   let result=static_eval::evaluate(program,tree.tree);assert(result.steps==100000);
   if leaves==33334 {assert(result.status==0 && result.bits==0 && result.bytes==4);}
   else {assert(result.status==2 && result.bytes==0);}
 }
 print("required static scalar fixture passed");
}
