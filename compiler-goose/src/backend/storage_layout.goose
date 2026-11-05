// Inline products sum payloads; variants reserve one word plus the largest arm.
namespace blot_backend_storage_layout;
import support.option;
import support.error;
let alignment: u32 = 4;
type Error = blot_error::Error;
fn productBytes(fields: const u32[:]) -> u32,Error { var size: u32 = 0; for field in fields { if field == 0 || (field & 3) != 0 || field > 4294967295 - size { return 0,Error.invalid_layout; } size += field; } return max(alignment,size),Error.none; }
fn variantBytes(payloads: const u32[:]) -> u32,Error { if payloads.len == 0 { return 0,Error.invalid_layout; } var payload: u32 = 0; for size in payloads { if size == 0 || (size & 3) != 0 { return 0,Error.invalid_layout; } payload = max(payload,size); } if payload > 4294967295 - alignment { return 0,Error.invalid_layout; } return alignment + payload,Error.none; }
struct InlineFields {}
fn children<V>(context: InlineFields,value: V) -> const V[:] { value.fields }
recursive fn bytes<V>(value: V) -> u32,Error { bytes(InlineFields {},value) }
recursive fn bytes<C,V>(context: const C&,value: V) -> u32,Error {
    match value.tag {
        scalar=>{ return alignment,Error.none; },ref,link=>{ return 5 * alignment,Error.none; },view=>{ return 6 * alignment,Error.none; },
        aggregate=>{ var size: u32 = 0; let fields = context.children(value); for field in fields { let width,error = bytes(context,field); if error != Error.none { return 0,error; } if value.variant_tags.len != 0 { size = max(size,width); } else { if width > 4294967295 - size { return 0,Error.invalid_layout; } size += width; } } if value.variant_tags.len != 0 { if value.variant_tags.len != fields.len || size > 4294967295 - alignment { return 0,Error.invalid_layout; } return alignment + size,Error.none; } return max(alignment,size),Error.none; },
        array,callable=>{ return 0,Error.invalid_layout; },
    }
}
fn variantIndex(tags: const u32[:],tag: u32) -> blot_support::Option<i64> { for candidate,index in tags { if candidate == tag { return blot_support::some(index); } } return blot_support::none<i64>(); }
