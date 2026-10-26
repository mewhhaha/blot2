// Re-evaluate retained expected source, independently replaying aggregate and
// scalar recognition. The private meter is not a complete C09 receipt.
namespace static_publish_verify;
import static_product_parse;
import static_product_verify;
import static_product_eval;
import static_publish_core;
fn verify(source:u8[:],image:static_publish_core::Image&)->bool {
    if source!=image.source[..] || source.len>16777216 || image.width<2 || image.width>16 || image.rows<1 ||
       image.bytes>4194304 || image.data.len!=image.bytes || image.rows as u64*image.width as u64*4!=image.bytes as u64 {return false;}
    var parsed=static_product_parse::parse(source);
    if parsed.status!=0 || !parsed.tree.is_array || !static_product_verify::verify(source,parsed.tree) ||
       parsed.tree.width!=image.width || parsed.tree.rows!=image.rows {return false;}
    let actual=static_product_eval::evaluate(source,parsed.tree);
    return actual.status==0 && actual.steps==image.steps && actual.bytes==image.bytes && actual.data[..]==image.data[..];
}
