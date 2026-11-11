// Closed host cleanup schemas retain exact physical fields and producer names.
namespace blot_backend_host_cleanup_shapes;
import dictionary;
import .layout;
import .backend_timing;
import runtime.list_runtime;
import support.error;
type Error = blot_error::Error;
enum Tag { unit, boolean, unsigned32, floating32, product, record, array, list, nominal, opaque_ }
fn spelling(tag: Tag) -> const u8[:] { match tag { unit=>"unit",boolean=>"boolean",unsigned32=>"u32",floating32=>"f32",product=>"product",record=>"record",array=>"array",list=>"list",nominal=>"nominal",opaque_=>"opaque" } }
struct Field { name: const u8[:], child: u32 }
struct Variant { tag: u32, child: u32 }
struct Node {
    id: u32, tag: Tag, floating: bool = false, reference: bool = false, child: u32 = 0, row_words: u32 = 0, leaf_words: u32 = 0,
    children: const u32[:] = default<const u32[:]>(), fields: const Field[:] = default<const Field[:]>(), variants: const Variant[:] = default<const Variant[:]>(), name: const u8[:] = "",
}
struct Facts { name: const u8[:], hidden: bool, variants: const Variant[:] }
reusable[] var owned_children: u32[>..] = [];
reusable[] var owned_fields: Field[>..] = [];
reusable[] var owned_variants: Variant[>..] = [];
fn copyChildren(source: const u32[:]) -> const u32[:] { if source.len == 0 { return default<const u32[:]>(); } let out = owned_children.alloc_slice(source.len); for child,index in source { out[index] = child; } return out; }
// Published field names are owned bytes; borrowed record names never reach the pool.
reusable[] var owned_field_names: u8[>..] = [];
fn pooledVariants(values: const Variant[:]) -> const Variant[:] { if values.len == 0 { return default<const Variant[:]>(); } let owned = owned_variants.realloc_slice(values,values.len); assert(blot_support::same_slice_identity(owned,values)); let start = owned_variants.index_of(owned[0]); assert(start >= 0 && values.len <= owned_variants.len - start); return owned_variants[start..start + values.len]; }
fn copyVariants(source: const Variant[:]) -> const Variant[:] { if source.len == 0 { return default<const Variant[:]>(); } let out = owned_variants.alloc_slice(source.len); for variant,index in source { out[index] = variant; } return out; }
fn deinit(node: Node) {
    if node.name.len != 0 { owned_field_names.free_slice(node.name); }
    if node.children.len != 0 { let owned=owned_children.realloc_slice(node.children,node.children.len);assert(blot_support::same_slice_identity(owned,node.children));owned_children.free_slice(owned); }
    if node.fields.len != 0 { for field in node.fields { if field.name.len != 0 { owned_field_names.free_slice(field.name); } } let owned=owned_fields.realloc_slice(node.fields,node.fields.len);assert(blot_support::same_slice_identity(owned,node.fields));owned_fields.free_slice(owned); }
    if node.variants.len != 0 { let owned=owned_variants.realloc_slice(node.variants,node.variants.len);assert(blot_support::same_slice_identity(owned,node.variants));owned_variants.free_slice(owned); }
}
// Visited layout ids grow in a plain run (at most 4096), so recording a visit never shrinks storage.
// The context travels beside the builder, so context calls never reach builder storage.
struct Builder { nodes: Node[>..<]&, seen: u32[>..]&, remaining: i64 = 65536 }
fn visited(seen: const u32[>..]&, id: u32) -> bool { for value in seen { if value == id { return true; } } return false; }
fn charge(builder: Builder&) -> Error { if builder.remaining == 0 { return blot_error::Error.layout_limit; } builder.remaining--; return blot_error::Error.none; }
fn deinit(builder: Builder&) { let nodes .= builder.nodes; for node in nodes { deinit(node); } nodes.clear(); }
recursive fn add<C>(context: C, builder: Builder&, id: u32, depth: i64) -> Error {
    let charged = charge(builder); if charged != blot_error::Error.none { return charged; }
    if depth >= 128 || id == 0 || id >= context.layouts.nodes.len { return blot_error::Error.layout_limit; }
    if visited(builder.seen,id) { return blot_error::Error.none; } if builder.nodes.len == 4096 { return blot_error::Error.layout_limit; } builder.seen.push(id);
    let layout = context.layouts.node(id); var node = Node { id, Tag.unit , ..}; var published = false;
    block {

    match layout.tag {
        unit => { node.tag = Tag.unit; }, boolean => { node.tag = Tag.boolean; }, unsigned32 => { node.tag = Tag.unsigned32; }, floating32 => { node.tag = Tag.floating32; },
        array,list => {
            node.tag = Tag.array; if layout.tag == blot_backend_layout::Tag.list { node.tag = Tag.list; } node.child = layout.a;
            let words,error = context.rowWords(layout.a,builder.remaining,depth); if error != blot_error::Error.none { let __flat_cleanup_1_0_0: Error = error; block {
if !published { deinit(node); }
} return __flat_cleanup_1_0_0; } node.row_words = words;
            if layout.tag == blot_backend_layout::Tag.list { node.leaf_words = blot_runtime_list_runtime::capacity; }
        },
        product => { node.tag = Tag.product; node.children = copyChildren(context.layouts.children(id)); },
        record => {
            node.tag = Tag.record; let count = layout.b as i64; var out: Field[:] = default<Field[:]>();
            if count != 0 { out = owned_fields.alloc_slice(count); for index in 0..count { out[index] = Field { name: "", child: 0 }; } node.fields = out; }
            for index in 0..count {
                let error = charge(builder); if error != blot_error::Error.none { let __flat_cleanup_1_1_0: Error = error; block {
if !published { deinit(node); }
} return __flat_cleanup_1_1_0; }
                let name = context.layouts.record_names.get(blot_backend_layout::sourceUnits(context.layouts.closed),context.layouts.children(id)[index * 2]); if !name.present { let __flat_cleanup_1_2_0: Error = blot_error::Error.layout_limit; block {
if !published { deinit(node); }
} return __flat_cleanup_1_2_0; }
                var owned_name: const u8[:] = ""; if name.value.len != 0 { let bytes = owned_field_names.alloc_slice(name.value.len); for byte,at in name.value { bytes[at] = byte; } owned_name = bytes; }
                out[index] = Field { name: owned_name, child: context.layouts.children(id)[index * 2 + 1] };
            }
        },
        nominal => {
            let facts,error = context.nominal(id,builder.remaining); if error != blot_error::Error.none { let __flat_cleanup_1_3_0: Error = error; block {
if !published { deinit(node); }
} return __flat_cleanup_1_3_0; }
            var owned_name: const u8[:] = ""; if facts.name.len != 0 { let bytes = owned_field_names.alloc_slice(facts.name.len); for byte,at in facts.name { bytes[at] = byte; } owned_name = bytes; } node.name = owned_name; node.tag = Tag.nominal; if facts.hidden { node.tag = Tag.opaque_; } node.variants = pooledVariants(facts.variants); node.children = copyChildren(context.layouts.children(id));
        },
        _ => { let __flat_cleanup_1_4_0: Error = blot_error::Error.layout_limit; block {
if !published { deinit(node); }
} return __flat_cleanup_1_4_0; },
    }
    let physical,error = context.physical(id,builder.remaining,depth); if error != blot_error::Error.none { let __flat_cleanup_1_5_0: Error = error; block {
if !published { deinit(node); }
} return __flat_cleanup_1_5_0; }
    node.floating = physical.floating; node.reference = physical.reference; builder.nodes.push(node); published = true;
    if node.child != 0 { let child = add(context,builder,node.child,depth + 1); if child != blot_error::Error.none { let __flat_cleanup_1_6_0: Error = child; block {
if !published { deinit(node); }
} return __flat_cleanup_1_6_0; } }
    for child in node.children { let error = add(context,builder,child,depth + 1); if error != blot_error::Error.none { let __flat_cleanup_1_7_0: Error = error; block {
if !published { deinit(node); }
} return __flat_cleanup_1_7_0; } }
    for field in node.fields { let error = add(context,builder,field.child,depth + 1); if error != blot_error::Error.none { let __flat_cleanup_1_8_0: Error = error; block {
if !published { deinit(node); }
} return __flat_cleanup_1_8_0; } }
    for variant in node.variants { let error = add(context,builder,variant.child,depth + 1); if error != blot_error::Error.none { let __flat_cleanup_1_9_0: Error = error; block {
if !published { deinit(node); }
} return __flat_cleanup_1_9_0; } }
    let __flat_cleanup_1_10_0: Error = blot_error::Error.none; block {
if !published { deinit(node); }
} return __flat_cleanup_1_10_0;


    }
}
fn jsonNumber(out: u8[>..<]&,value: u32) { var digits: u8[10]; var count: i64 = 0; var remaining = value; while true { digits[count] = '0' + (remaining % 10) as u8; count++; remaining /= 10; if remaining == 0 { break; } } while count > 0 { count--; out.push(digits[count]); } }
fn jsonNode(node: Node,out: u8[>..<]&) {
    out.push('{'); blot_backend_backend_timing::jsonField(out,"id",node.id,false); out.append(",\"tag\":"); blot_backend_backend_timing::jsonString(out,spelling(node.tag));
    blot_backend_backend_timing::jsonField(out,"floating",node.floating); blot_backend_backend_timing::jsonField(out,"reference",node.reference); blot_backend_backend_timing::jsonField(out,"child",node.child); blot_backend_backend_timing::jsonField(out,"row_words",node.row_words); blot_backend_backend_timing::jsonField(out,"leaf_words",node.leaf_words);
    out.append(",\"children\":["); for child,index in node.children { if index != 0 { out.push(','); } jsonNumber(out,child); } out.append("],\"fields\":[");
    for field,index in node.fields { if index != 0 { out.push(','); } out.append("{\"name\":"); blot_backend_backend_timing::jsonString(out,field.name); blot_backend_backend_timing::jsonField(out,"child",field.child); out.push('}'); }
    out.append("],\"variants\":["); for variant,index in node.variants { if index != 0 { out.push(','); } out.push('{'); blot_backend_backend_timing::jsonField(out,"tag",variant.tag,false); blot_backend_backend_timing::jsonField(out,"child",variant.child); out.push('}'); }
    out.append("],\"name\":"); blot_backend_backend_timing::jsonString(out,node.name); out.push('}');
}
fn build<C>(context: C,roots: const u32[:],out: u8[>..<]&) -> Error {
    var nodes: Node[>..<] = []; var seen: u32[>..] = []; var builder = Builder { nodes,seen , ..};
    block {

    for root in roots { let error = add(context,builder,root,0); if error != blot_error::Error.none { let __flat_cleanup_0_0_0: Error = error; block {
deinit(builder);
} return __flat_cleanup_0_0_0; } }
    // IDs are unique; bounded merge sorting gives the source O(n log n) work.
    var scratch: Node[>..<] = []; for node in nodes { scratch.push(node); } var width: i64 = 1;
    while width < nodes.len {
        var start: i64 = 0;
        while start < nodes.len {
            var middle = start + width; if middle > nodes.len { middle = nodes.len; } var end = middle + width; if end > nodes.len { end = nodes.len; }
            var left = start; var right = middle; var destination = start;
            while destination < end { if right == end || (left < middle && nodes[left].id < nodes[right].id) { scratch[destination] = nodes[left]; left++; } else { scratch[destination] = nodes[right]; right++; } destination++; }
            start = end;
        }
        for node,index in scratch { nodes[index] = node; } width *= 2;
    }
    out.append("{\"version\":1,\"nodes\":["); for node,index in nodes { if index != 0 { out.push(','); } jsonNode(node,out); } out.append("]}"); let __flat_cleanup_0_1_0: Error = blot_error::Error.none; block {
deinit(builder);
} return __flat_cleanup_0_1_0;


    }
}
