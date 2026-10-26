// Experimental per-evaluation two-entry cache for previously independently
// verified exact scalar source/type. The original element order, every scalar
// evaluation and the fixture step/byte charges are unchanged. This does not
// implement or waive the shared C09 semantic-visit meter.
namespace static_fast_eval;
import static_product_core;
import static_product_eval;
import static_eval;
import static_fast_verify;
import static_core;
import static_parse;
import static_verify;
import static_budget;
struct Stats {verify_parses:i64=0,eval_parses:i64=0,eval_hits:i64=0}
fn evaluate(source:u8[:],p:static_product_core::Tree&)->static_product_eval::Result,Stats {
    let ok,count=static_fast_verify::verify_stats(source,p);var stats=Stats {verify_parses:count};
    if !ok{return static_product_eval::Result {},stats;}
    var budget=static_budget::Budget {};var output:u8[>..]=[];
    let first=p.parts[0];let second=p.parts[1];
    var one:u8[>..]=[];if first.ty==1 {one.append("static let v: U32 = ");}else {one.append("static let v: F32 = ");}
    one.append(source[first.start..first.end]);one.push('\n');var tree_a=static_parse::parse(one);
    var two:u8[>..]=[];if second.ty==1 {two.append("static let v: U32 = ");}else {two.append("static let v: F32 = ");}
    two.append(source[second.start..second.end]);two.push('\n');var tree_b=static_parse::parse(two);stats.eval_parses=2;
    if tree_a.status!=0 || tree_b.status!=0 || !static_verify::verify(one,tree_a.tree) || !static_verify::verify(two,tree_b.tree){return static_product_eval::Result {},stats;}
    for item,i in p.parts {
        let hit_a=first.ty==item.ty && source[first.start..first.end]==source[item.start..item.end];
        let hit_b=second.ty==item.ty && source[second.start..second.end]==source[item.start..item.end];
        var value=static_eval::Result {};
        if hit_a {value=static_product_eval::scalar(tree_a.tree,budget);stats.eval_hits+=1;}
        else if hit_b {value=static_product_eval::scalar(tree_b.tree,budget);stats.eval_hits+=1;}
        else {
            var own:u8[>..]=[];if item.ty==1 {own.append("static let v: U32 = ");}else {own.append("static let v: F32 = ");}
            own.append(source[item.start..item.end]);own.push('\n');stats.eval_parses+=1;
            var parsed=static_parse::parse(own);if parsed.status!=0 || !static_verify::verify(own,parsed.tree){return static_product_eval::Result {},stats;}
            value=static_product_eval::scalar(parsed.tree,budget);
        }
        if value.status!=0{return static_product_eval::Result {status:value.status,steps:budget.steps},stats;}
        if !static_budget::produce(budget,4){return static_product_eval::Result {status:2,steps:budget.steps},stats;}
        let bits=value.bits;for k in 4 {output.push(((bits>>(k*8))&255) as u8);}
        if (i+1)%p.width==0 && !static_budget::step(budget){return static_product_eval::Result {status:2,steps:budget.steps},stats;}
    }
    if p.is_array && !static_budget::step(budget){return static_product_eval::Result {status:2,steps:budget.steps},stats;}
    return static_product_eval::Result {status:0,steps:budget.steps,bytes:budget.bytes,data:copy(output)},stats;
}
