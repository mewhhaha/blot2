import static_product_core;
import static_product_parse;
import static_product_verify;
import static_product_eval;
recursive fn balanced(n:i64,out:u8[>..]&) {
    if n==1 {out.push('0');return;}out.push('(');balanced(n/2,out);out.push('+');balanced(n-n/2,out);out.push(')');
}
fn main() {
    for source in ["static let x = (1 + 2, -0.0)\n", "static let a = #[(1, 0.0 / 0.0), (2, 3.5)]\n"] {
        var parsed=static_product_parse::parse(source);assert(parsed.status==0 && static_product_verify::verify(source,parsed.tree));
        let value=static_product_eval::evaluate(source,parsed.tree);assert(value.status==0 && value.bytes==parsed.tree.parts.len*4 && value.data.len==value.bytes);
        if parsed.tree.is_array {let expected:u8[16]=[1,0,0,0,0,0,192,127,2,0,0,0,0,0,96,64];assert(value.data[..]==expected[..]);}
        else {let expected:u8[8]=[3,0,0,0,0,0,0,128];assert(value.data[..]==expected[..]);}
        for i in parsed.tree.parts.len {
            let old=parsed.tree.parts[i].start;parsed.tree.parts[i].start+=1;assert(!static_product_verify::verify(source,parsed.tree));parsed.tree.parts[i].start=old;
            let prev=parsed.tree.parts[i].ty;parsed.tree.parts[i].ty=3;
            assert(!static_product_verify::verify(source,parsed.tree) && static_product_eval::evaluate(source,parsed.tree).status==1);parsed.tree.parts[i].ty=prev;
        }
    }
    for source in ["let a = #[(1,2)]", "static let a = #[]", "static let a = #[1,2]", "static let a = #[(1,2),(3,4.0)]",
        "static let a = #[(1,2),(3,4,5)]", "static let a = (1,)", "static let a = (1,host())",
        "static let a = (1, region.reserve(4))"] {assert(static_product_parse::parse(source).status!=0);}
    let order="static let a = #[(4294967295 + 1, 0 - 1)]";var fail=static_product_parse::parse(order);
    assert(fail.status==0);let result=static_product_eval::evaluate(order,fail.tree);assert(result.status==3 && result.steps==3 && result.data.len==0);
    for n in [33333,33334] {
        var src:u8[>..]=[];src.append("static let a = #[(");balanced(n,src);src.append(",0)]\n");
        var x=static_product_parse::parse(src);assert(x.status==0 && static_product_verify::verify(src,x.tree));
        let out=static_product_eval::evaluate(src,x.tree);assert(out.steps==100000);
        if n==33333 {assert(out.status==0 && out.data.len==8);}else {assert(out.status==2 && out.data.len==0);}
    }
    for n in [16,17] {
        var src:u8[>..]=[];src.append("static let a = #[(");
        for i in n {if i>0 {src.push(',');}src.push('1');}src.append(")]\n");
        var p=static_product_parse::parse(src);
        if n==16 {assert(p.status==0 && static_product_verify::verify(src,p.tree) && static_product_eval::evaluate(src,p.tree).bytes==64);}
        else {assert(p.status!=0);}
    }
    var oversized:u8[>..]=[32;16777217];assert(static_product_parse::parse(oversized).status!=0);
    print("private required-static product/array fixture passed");
}
