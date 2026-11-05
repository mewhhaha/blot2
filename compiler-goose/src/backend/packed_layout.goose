namespace blot_backend_packed_layout;
import .layout;
import support.option;

struct Leaf { path: u32[8] = [0; 8], depth: u8 = 0, floating: bool = false }
struct Plan { leaves: Leaf[32] = [Leaf {..}; 32], count: i64 = 0 }
fn stride(plan: Plan) -> u32 { var count = plan.count; if count < 1 { count = 1; } return (count * 4) as u32; }
recursive fn visit(plan: Plan&, layouts: blot_backend_layout::Store&, id: blot_backend_layout::Id, path: u32[8], depth: u8) -> bool {
    let node = layouts.node(id);
    if node.tag == blot_backend_layout::Tag.unit || node.tag == blot_backend_layout::Tag.boolean || node.tag == blot_backend_layout::Tag.unsigned32 || node.tag == blot_backend_layout::Tag.floating32 {
        if plan.count == 32 { return false; } plan.leaves[plan.count] = Leaf { path: path, depth: depth, floating: node.tag == blot_backend_layout::Tag.floating32 , ..}; plan.count++; return true;
    }
    if node.tag == blot_backend_layout::Tag.record || node.tag == blot_backend_layout::Tag.product {
        if depth == 8 { return false; }
        let fields = layouts.children(id); var step = 1; if node.tag == blot_backend_layout::Tag.record { step = 2; }
        for index in 0..fields.len / step { var next = path; next[depth] = (index * 4) as u32; if !visit(plan, layouts, fields[index * step + step - 1], next, depth + 1) { return false; } }
        return true;
    }
    return false;
}
fn analyze(layouts: blot_backend_layout::Store&, id: blot_backend_layout::Id) -> blot_support::Option<Plan> {
    var plan = Plan {..}; if visit(plan, layouts, id, [0; 8], 0) { return blot_support::some(plan); } return blot_support::none<Plan>();
}
fn rowWords(layouts: blot_backend_layout::Store&, id: blot_backend_layout::Id) -> u32 {
    let tag = layouts.node(id).tag; if tag != blot_backend_layout::Tag.product && tag != blot_backend_layout::Tag.record { return 0; }
    let fields = layouts.children(id); var step = 1; if tag == blot_backend_layout::Tag.record { step = 2; }
    let count = fields.len / step; if count == 0 || count > 16 { return 0; }
    for index in 0..count { if !layouts.scalar(fields[index * step + step - 1]).present { return 0; } } return count as u32;
}
fn arrayRowWords(layouts: blot_backend_layout::Store&, collection: blot_backend_layout::Id) -> u32 { let node = layouts.node(collection); if node.tag == blot_backend_layout::Tag.array { return rowWords(layouts, node.a); } return 0; }
fn collectionRowWords(layouts: blot_backend_layout::Store&, collection: blot_backend_layout::Id) -> u32 { let node = layouts.node(collection); if node.tag == blot_backend_layout::Tag.array || node.tag == blot_backend_layout::Tag.list { return rowWords(layouts, node.a); } return 0; }
fn stride(words: u32) -> u32 { if words == 0 { return 4; } return words * 4; }
