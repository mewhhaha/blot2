import std;
import static_call_eval;
fn chain(count:i64)->u8[>..] {
    var s:u8[>..]=[];for i in count {
        if i+1==count {format(s,"let f",i,": U32 -> U32 = fn x => return x\n");}
        else {format(s,"let f",i,": U32 -> U32 = fn x => return f",i+1,"(x)\n");}
    }s.append("static let answer: U32 = f0(7)\n");return s;
}
fn main() {
    let s="let f: U32 -> U32 = fn x => return g(x)\nlet g: U32 -> U32 = fn y => return y & 3\nstatic let answer: U32 = f(7)\n";
    let r=static_call_eval::evaluate(s);assert(r.status==0 && r.bits==3 && r.depth==2 && r.bytes==4);
    for n in [1,127,128] {let src=chain(n);let out=static_call_eval::evaluate(src);assert(out.status==0 && out.depth==n && out.bits==7 && out.steps==1+2*n);}
    let deep=chain(129);let denied=static_call_eval::evaluate(deep);assert(denied.status!=0 && denied.bytes==0);
    for bad in ["let f: U32 -> U32 = fn x => return f(x)\nstatic let a: U32 = f(1)",
        "let f: U32 -> U32 = fn x => return host(x)\nstatic let a: U32 = f(1)",
        "let f: U32 -> U32 = fn x => return x\nstatic let a: U32 = f(1+2)",
        "let f: U32 -> U32 = fn x => return x\nstatic let f: U32 = f(1)",
        "let f: U32 -> U32 = fn x => return x\nstatic let a: U32 = g(1)"] {
        assert(static_call_eval::evaluate(bad).status!=0);
    }
    print("private required-static pure scalar call fixture passed");
}
