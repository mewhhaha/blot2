// Private source-bound immutable bytes. The local meter charges each scalar
// Core node plus one product and (for arrays) one array construction. Output
// charge is the final immutable data exactly once; intermediate scalar storage
// is not additionally charged by this fixture policy. There are no calls here.
// This is not a complete C09 primitive schedule, semantic visit meter, static
// Domain allocator, compiler storage publication or general static evaluator.
namespace static_product_eval;
import static_product_core;
import static_product_verify;
import static_budget;
import static_eval;
import static_core;
import static_float;
import static_parse;
import static_verify;
struct Result {status:i64=1,steps:u32=0,bytes:u32=0,data:u8[]=[]}
// Replays scalar operations with the same shared declaration budget, charging
// immediately before each operation and stopping at the first failure.
fn scalar(tree:static_core::Tree&,budget:static_budget::Budget&)->static_eval::Result {
    var values:static_eval::Value[>..]=[];
    for n,i in tree.nodes {
        if !static_budget::step(budget){return static_eval::Result {status:2};}
        var v=static_eval::Value {depth:1};
        if n.tag==1 {v.bits=n.literal;} else if n.tag==2 {v.bits=static_float::literal(n.literal,n.half);}
        else if n.tag==3 || n.tag==4 {
            if n.a<1 || n.a>i{return static_eval::Result {};}
            let a=values[n.a-1];v.depth=a.depth+1;
            if !static_budget::enter(v.depth){return static_eval::Result {status:2};}
            v.bits=if n.tag==3 {a.bits} else {a.bits ^ 0x80000000};
        } else {
            if n.a<1 || n.a>i || n.b<1 || n.b>i{return static_eval::Result {};}
            let a=values[n.a-1];let b=values[n.b-1];v.depth=(if a.depth>b.depth {a.depth} else {b.depth})+1;
            if !static_budget::enter(v.depth){return static_eval::Result {status:2};}
            if n.ty==2 {v.bits=static_float::arithmetic(n.tag,a.bits,b.bits);}
            else if n.tag==5 {if (a.bits as u64)+(b.bits as u64)>4294967295{return static_eval::Result {status:3};}v.bits=a.bits+b.bits;}
            else if n.tag==6 {if a.bits<b.bits{return static_eval::Result {status:3};}v.bits=a.bits-b.bits;}
            else if n.tag==7 {if (a.bits as u64)*(b.bits as u64)>4294967295{return static_eval::Result {status:3};}v.bits=(a.bits as u64*b.bits as u64) as u32;}
            else if n.tag==9 {v.bits=a.bits&b.bits;}
            else if n.tag==10 {v.bits=((a.bits as u64+b.bits as u64)&4294967295) as u32;}
            else if n.tag==11 {v.bits=((a.bits as u64+4294967296-b.bits as u64)&4294967295) as u32;}
            else if n.tag==12 {v.bits=((a.bits as u64*b.bits as u64)&4294967295) as u32;}
            else {return static_eval::Result {};}
        }
        if !static_budget::enter(v.depth){return static_eval::Result {status:2};}values.push(v);
    }
    if tree.root<1 || tree.root>values.len{return static_eval::Result {};}
    return static_eval::Result {status:0,ty:tree.ty,bits:values[tree.root-1].bits};
}
fn evaluate(source:u8[:],p:static_product_core::Tree&) -> Result {
    if !static_product_verify::verify(source,p){return Result {};}
    var budget=static_budget::Budget {};var output:u8[>..]=[];
    for i in p.parts.len {
        let item=p.parts[i];
        var own:u8[>..]=[];if item.ty==1 {own.append("static let v: U32 = ");}else {own.append("static let v: F32 = ");}
        own.append(source[item.start..item.end]);own.push('\n');var parsed=static_parse::parse(own);
        if parsed.status!=0 || !static_verify::verify(own,parsed.tree){return Result {}; }
        let value=scalar(parsed.tree,budget);
        if value.status!=0 {return Result {status:value.status,steps:budget.steps};}
        if !static_budget::produce(budget,4){return Result {status:2,steps:budget.steps};}
        let bits=value.bits;for k in 4 {output.push(((bits>>(k*8))&255) as u8);}
        if (i+1)%p.width==0 && !static_budget::step(budget) {return Result {status:2,steps:budget.steps};}
    }
    if p.is_array && !static_budget::step(budget){return Result {status:2,steps:budget.steps};}
    return Result {status:0,steps:budget.steps,bytes:budget.bytes,data:copy(output)};
}
