// Construct only after source-only static evaluation succeeds. A product alone
// is not an array and does not acquire a static array Domain in this fixture.
namespace static_publish_build;
import static_product_parse;
import static_product_verify;
import static_product_eval;
import static_publish_core;
fn build(source:u8[:])->static_publish_core::Result {
    var p=static_product_parse::parse(source);
    if p.status!=0 {return static_publish_core::Result {status:p.status};}
    if !p.tree.is_array || !static_product_verify::verify(source,p.tree){return static_publish_core::Result {};}
    let value=static_product_eval::evaluate(source,p.tree);if value.status!=0{return static_publish_core::Result {status:value.status};}
    return static_publish_core::Result {status:0,image:static_publish_core::Image {source:source,width:p.tree.width as u32,
        rows:p.tree.rows as u32,steps:value.steps,bytes:value.bytes,data:copy(value.data)}};
}
