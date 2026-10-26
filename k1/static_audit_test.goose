import std;
import static_product_parse;
import static_product_verify;
import static_product_eval;
import static_call_eval;
fn main() {
 var src:u8[>..]=[];src.append("static let data = #[");
 for i in 100 {if i>0 {src.append(",");}format(src,"(",i," & 31, 0.0 / 0.0)");}src.append("]\n");
 var parsed=static_product_parse::parse(src);assert(parsed.status==0 && static_product_verify::verify(src,parsed.tree));
 let value=static_product_eval::evaluate(src,parsed.tree);assert(value.status==0 && value.steps==701 && value.bytes==800 && value.data.len==800);
 for i in 100 {let at=i*8;assert(value.data[at]==(i&31) as u8 && value.data[at+1]==0 && value.data[at+2]==0 && value.data[at+3]==0);
  assert(value.data[at+4]==0 && value.data[at+5]==0 && value.data[at+6]==192 && value.data[at+7]==127);}
 var swapped=copy(parsed.tree);let item=swapped.parts[0];swapped.parts[0]=swapped.parts[1];swapped.parts[1]=item;
 assert(!static_product_verify::verify(src,swapped) && static_product_eval::evaluate(src,swapped).data.len==0);
 var over=copy(parsed.tree);over.parts[1].end=9223372036854775807;assert(!static_product_verify::verify(src,over));
 let call="let f: U32 -> U32 = fn x => return g(170)\nlet g: U32 -> U32 = fn y => return y & 15\nstatic let a: U32 = f(3)\n";
 let r=static_call_eval::evaluate(call);assert(r.status==0 && r.bits==10 && r.depth==2 && r.bytes==4 && r.steps==7);
 for bad in ["let f: U32 -> U32 = fn x => return x\nstatic let a: U32 = f(1)\nstatic let b: U32 = f(2)",
 "let f: U32 -> U32 = fn x => return x\nstatic let a: U32 = f(1) + 0",
 "let f: U32 -> U32 = fn x => return x\nstatic let a: U32 = f(1)\nlet g: U32 -> U32 = fn x => return x"] {assert(static_call_eval::evaluate(bad).status!=0);}
 print("independent static source/order/value audit passed");
}
