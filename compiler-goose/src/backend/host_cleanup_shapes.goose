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
fn copyChildren(source: const u32[:]) -> const u32[:] { if source.len == 0 { return []; } let out = owned_children.alloc_slice(source.len); for child,index in source { out[index] = child; } return out; }
fn copyFields(source: const Field[:]) -> const Field[:] { if source.len == 0 { return []; } let out = owned_fields.alloc_slice(source.len); for field,index in source { out[index] = field; } return out; }
fn copyVariants(source: const Variant[:]) -> const Variant[:] { if source.len == 0 { return []; } let out = owned_variants.alloc_slice(source.len); for variant,index in source { out[index] = variant; } return out; }
fn deinit(node: Node) {
    if node.children.len != 0 { let first: const u32& = node.children[0]; let start = owned_children.index_of(first); owned_children.free_slice(owned_children[start..start + node.children.len]); }
    if node.fields.len != 0 { let first: const Field& = node.fields[0]; let start = owned_fields.index_of(first); owned_fields.free_slice(owned_fields[start..start + node.fields.len]); }
    if node.variants.len != 0 { let first: const Variant& = node.variants[0]; let start = owned_variants.index_of(first); owned_variants.free_slice(owned_variants[start..start + node.variants.len]); }
}
struct Builder<C> { context: C, nodes: Node[>..<]&, seen: dictionary<u32,bool>&, remaining: i64 = 65536 }
fn charge<C>(builder: Builder<C>&) -> Error { if builder.remaining == 0 { return blot_error::Error.layout_limit; } builder.remaining--; return blot_error::Error.none; }
fn deinit<C>(builder: Builder<C>&) { for node in builder.nodes { deinit(node); } builder.nodes.clear(); builder.seen.clear(); }
recursive fn add<C>(builder: Builder<C>&, id: u32, depth: i64) -> Error {
    let charged = charge(builder); if charged != blot_error::Error.none { return charged; }
    if depth >= 128 || id == 0 || id >= builder.context.layouts.nodes.len { return blot_error::Error.layout_limit; }
    if builder.seen.contains(id) { return blot_error::Error.none; } if builder.nodes.len == 4096 { return blot_error::Error.layout_limit; } builder.seen.insert(id,true);
    let layout = builder.context.layouts.node(id); var node = Node { id, Tag.unit , ..}; var published = false;
    recursive fn cleanup_continuation_2() -> Error {

    match layout.tag {
        unit => { node.tag = Tag.unit; }, boolean => { node.tag = Tag.boolean; }, unsigned32 => { node.tag = Tag.unsigned32; }, floating32 => { node.tag = Tag.floating32; },
        array,list => {
            node.tag = Tag.array; if layout.tag == blot_backend_layout::Tag.list { node.tag = Tag.list; } node.child = layout.a;
            let words,error = builder.context.rowWords(layout.a,builder.remaining,depth); if error != blot_error::Error.none { return error; } node.row_words = words;
            if layout.tag == blot_backend_layout::Tag.list { node.leaf_words = blot_runtime_list_runtime::capacity; }
        },
        product => { node.tag = Tag.product; node.children = copyChildren(builder.context.layouts.children(id)); },
        record => {
            node.tag = Tag.record; var fields: Field[>..<] = []; let children = builder.context.layouts.children(id);
            for index in 0..layout.b {
                let error = charge(builder); if error != blot_error::Error.none { return error; }
                let name = builder.context.layouts.record_names.map.get(children[index * 2]); if name == null { return blot_error::Error.layout_limit; }
                fields.push(Field { name, children[index * 2 + 1] , ..});
            }
            node.fields = copyFields(fields);
        },
        nominal => {
            let facts,error = builder.context.nominal(id,builder.remaining); if error != blot_error::Error.none { return error; }
            node.name = facts.name; node.tag = Tag.nominal; if facts.hidden { node.tag = Tag.opaque_; } node.variants = facts.variants; node.children = copyChildren(builder.context.layouts.children(id));
        },
        _ => { return blot_error::Error.layout_limit; },
    }
    let physical,error = builder.context.physical(id,builder.remaining,depth); if error != blot_error::Error.none { return error; }
    node.floating = physical.floating; node.reference = physical.reference; builder.nodes.push(node); published = true;
    if node.child != 0 { let child = add(builder,node.child,depth + 1); if child != blot_error::Error.none { return child; } }
    for child in node.children { let error = add(builder,child,depth + 1); if error != blot_error::Error.none { return error; } }
    for field in node.fields { let error = add(builder,field.child,depth + 1); if error != blot_error::Error.none { return error; } }
    for variant in node.variants { let error = add(builder,variant.child,depth + 1); if error != blot_error::Error.none { return error; } }
    return blot_error::Error.none;

    }
    let cleanup_result_2_0 = cleanup_continuation_2();
     if !published { deinit(node); }
    return cleanup_result_2_0;
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
    var nodes: Node[>..<] = []; var seen: dictionary<u32,bool>; var builder = Builder<C> { context,nodes,seen , ..};
    recursive fn cleanup_continuation_1() -> Error {

    for root in roots { let error = add(builder,root,0); if error != blot_error::Error.none { return error; } }
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
    out.append("{\"version\":1,\"nodes\":["); for node,index in nodes { if index != 0 { out.push(','); } jsonNode(node,out); } out.append("]}"); return blot_error::Error.none;

    }
    let cleanup_result_1_0 = cleanup_continuation_1();
     deinit(builder);
    return cleanup_result_1_0;
}
