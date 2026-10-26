// Closed, source-verified direct-call tuple/array evaluator. All actual scalar
// operations, call steps and aggregate construction share a per-declaration
// meter. Calls only appear as entire U32 tuple components and take one U32
// literal; no runtime identities/effects, captured calls or general evaluator.
// Output bytes counted once; fixture steps are not full C09 accounting.
namespace static_compound_eval;
import static_compound_core;
import static_compound_verify;
import static_product_eval;
import static_parse;
import static_verify;
import static_budget;
import module_frontend;
import module_core;
struct CallResult {status:i64=1,bits:u32=0,depth:u32=0}
struct Result {status:i64=1,steps:u32=0,bytes:u32=0,depth:u32=0,data:u8[]=[]}
fn call(core:module_core::ModuleCore&,which:i64,arg:u32,budget:static_budget::Budget&)->CallResult {
    if !static_budget::step(budget){return CallResult {status:2};}
    var value=arg;var depth:u32=0;var current=which;
    loop {
        if current<0 || current>=core.functions.len{return CallResult {};}
        if depth>=128{return CallResult {status:2,depth:depth};}depth+=1;
        if !static_budget::step(budget) || !static_budget::step(budget){return CallResult {status:2,depth:depth};}
        let f=core.functions[current];let result=f.values[f.result_id];
        if result.producer==1 {break;}
        if result.producer==2 {if !static_budget::step(budget){return CallResult {status:2,depth:depth};}value=result.literal;break;}
        let left=f.values[result.left_id];var a=value;
        if left.producer==2 {if !static_budget::step(budget){return CallResult {status:2,depth:depth};}a=left.literal;}
        if result.producer==3 {
            let right=f.values[result.right_id];var b=value;
            if right.producer==2 {if !static_budget::step(budget){return CallResult {status:2,depth:depth};}b=right.literal;}
            value=a&b;break;
        }
        if result.producer!=4{return CallResult {};}
        value=a;current=result.callee_id;
    }
    return CallResult {status:0,bits:value,depth:depth};
}
fn evaluate(source:u8[:],p:static_compound_core::Program&)->Result {
    if !static_compound_verify::verify(source,p){return Result {};}
    var mod,status=module_frontend::parse(source[..p.split]);if status!=0{return Result {};}
    var core=module_frontend::to_core(mod);if module_frontend::verify_core(mod,core)!=0{return Result {};}
    var budget=static_budget::Budget {};var bytes:u8[>..]=[];var ci:i64=0;var max_depth:u32=0;
    for part,i in p.product.parts {
        var bits:u32=0;
        if ci<p.calls.len && p.calls[ci].start==part.start {
            let entry=p.calls[ci];let value=call(core,entry.target,entry.argument,budget);
            if value.status!=0{return Result {status:value.status,steps:budget.steps,depth:value.depth};}
            bits=value.bits;if value.depth>max_depth {max_depth=value.depth;}ci+=1;
        } else {
            var synthetic:u8[>..]=[];if part.ty==1 {synthetic.append("static let v: U32 = ");}else {synthetic.append("static let v: F32 = ");}
            synthetic.append(p.projection[part.start..part.end]);synthetic.push('\n');var scalar=static_parse::parse(synthetic);
            if scalar.status!=0 || !static_verify::verify(synthetic,scalar.tree){return Result {};}
            let value=static_product_eval::scalar(scalar.tree,budget);
            if value.status!=0{return Result {status:value.status,steps:budget.steps,depth:max_depth};}bits=value.bits;
        }
        if !static_budget::produce(budget,4){return Result {status:2,steps:budget.steps,depth:max_depth};}
        for k in 4 {bytes.push(((bits>>(k*8))&255) as u8);}
        if (i+1)%p.product.width==0 && !static_budget::step(budget){return Result {status:2,steps:budget.steps,depth:max_depth};}
    }
    if p.product.is_array && !static_budget::step(budget){return Result {status:2,steps:budget.steps,depth:max_depth};}
    return Result {status:0,steps:budget.steps,bytes:budget.bytes,depth:max_depth,data:copy(bytes)};
}
