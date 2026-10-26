// Optional entry points over the existing private static-product pipeline.
// This does not change default evaluation, public admission, C09 receipts or
// K1 Domain identity. Every call begins from the exact supplied source.
namespace static_fast_entry;
import static_product_parse;
import static_product_eval;
import static_fast_eval;
import static_publish_core;
import static_publish_verify;
fn evaluate(source:u8[:])->static_product_eval::Result,static_fast_eval::Stats {
    var parsed=static_product_parse::parse(source);
    if parsed.status!=0{return static_product_eval::Result {status:parsed.status},static_fast_eval::Stats {};}
    return static_fast_eval::evaluate(source,parsed.tree);
}
// This optional constructor retains the existing publication checker as an
// independent admission gate. Its full build cost is not the isolated-phase
// measurement reported for the cache.
fn build_image(source:u8[:])->static_publish_core::Result,static_fast_eval::Stats {
    var parsed=static_product_parse::parse(source);
    if parsed.status!=0{return static_publish_core::Result {status:parsed.status},static_fast_eval::Stats {};}
    if !parsed.tree.is_array{return static_publish_core::Result {},static_fast_eval::Stats {};}
    let value,stats=static_fast_eval::evaluate(source,parsed.tree);
    if value.status!=0{return static_publish_core::Result {status:value.status},stats;}
    var image=static_publish_core::Image {source:source,width:parsed.tree.width as u32,rows:parsed.tree.rows as u32,
        steps:value.steps,bytes:value.bytes,data:copy(value.data)};
    if !static_publish_verify::verify(source,image){return static_publish_core::Result {},stats;}
    return static_publish_core::Result {status:0,image:image},stats;
}
