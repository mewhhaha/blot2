// Deterministic native evaluation after independent full source/operation
// checking. This is a scalar fixture: no static arrays, calls, dependencies,
// portable artifact, general decimal conversion or compiler-wide C09 meter.
namespace static_eval;
import static_core;
import static_verify;
import static_budget;
import static_float;
struct Value {bits:u32=0,depth:u32=0}
// 0 success; 1 malformed/source mismatch; 2 fixture traversal/step limit;
// 3 unproved/overflowing ordinary U32 arithmetic. No runtime fallback.
struct Result {status:i64=1,ty:i64=0,bits:u32=0,steps:u32=0,bytes:u32=0}
fn evaluate(source:u8[:],tree:static_core::Tree&) -> Result {
    if !static_verify::verify(source,tree) {return Result {};}
    var budget=static_budget::Budget {};var values:Value[>..]=[];
    for n,i in tree.nodes {
        if !static_budget::step(budget) {return Result {status:2,steps:budget.steps,bytes:budget.bytes};}
        var v=Value {depth:1};
        if n.tag==1 {v.bits=n.literal;}
        else if n.tag==2 {v.bits=static_float::literal(n.literal,n.half);}
        else if n.tag==3 || n.tag==4 {
            if n.a<1 || n.a>i {return Result {};}
            let a=values[n.a-1];v.depth=a.depth+1;
            if !static_budget::enter(v.depth) {return Result {status:2,steps:budget.steps};}
            v.bits=if n.tag==3 {a.bits} else {a.bits ^ 0x80000000};
        } else {
            if n.a<1 || n.a>i || n.b<1 || n.b>i {return Result {};}
            let a=values[n.a-1];let b=values[n.b-1];v.depth=(if a.depth>b.depth {a.depth} else {b.depth})+1;
            if !static_budget::enter(v.depth) {return Result {status:2,steps:budget.steps};}
            if n.ty==2 {v.bits=static_float::arithmetic(n.tag,a.bits,b.bits);}
            else if n.tag==5 {
                if (a.bits as u64)+(b.bits as u64)>4294967295 {return Result {status:3,steps:budget.steps};}
                v.bits=a.bits+b.bits;
            } else if n.tag==6 {
                if a.bits<b.bits {return Result {status:3,steps:budget.steps};}v.bits=a.bits-b.bits;
            } else if n.tag==7 {
                if (a.bits as u64)*(b.bits as u64)>4294967295 {return Result {status:3,steps:budget.steps};}v.bits=(a.bits as u64*b.bits as u64) as u32;
            } else if n.tag==9 {v.bits=a.bits & b.bits;}
            else if n.tag==10 {v.bits=((a.bits as u64+b.bits as u64)&4294967295) as u32;}
            else if n.tag==11 {v.bits=((a.bits as u64+4294967296-b.bits as u64)&4294967295) as u32;}
            else if n.tag==12 {v.bits=((a.bits as u64*b.bits as u64)&4294967295) as u32;}
            else {return Result {};}
        }
        if !static_budget::enter(v.depth) {return Result {status:2,steps:budget.steps};}
        values.push(v);
    }
    if tree.root<1 || tree.root>values.len || !static_budget::produce(budget,4) {return Result {status:2,steps:budget.steps};}
    return Result {status:0,ty:tree.ty,bits:values[tree.root-1].bits,steps:budget.steps,bytes:budget.bytes};
}
