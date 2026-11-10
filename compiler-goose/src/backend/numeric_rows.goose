namespace blot_backend_numeric_rows;
import dictionary;
import .layout;
import support.error;
import support.option;

struct Storage {
    layout: blot_backend_layout::Id = 0, bytes: u32 = 0, parent: blot_support::Option<u8>, offset: u32 = 0,
    word: u8 = 0, references: u16 = 0, tag: blot_support::Option<u32>, guard_: blot_support::Option<u8>, unit_payload: bool = false,
}
struct Guard { parent: blot_support::Option<u8>, owner: u8 = 0, word: u8 = 0, tag: u32 = 0 }
struct Leaf { owner: u8 = 0, offset: u32 = 0, floating: bool = false, word: u8 = 0, guard_: blot_support::Option<u8>, discriminant: bool = false }
struct Plan {
    storage: Storage[32] = [Storage {..}; 32], storage_count: u8 = 0, leaves: Leaf[64] = [Leaf {..}; 64], leaf_count: u8 = 0,
    word_count: u8 = 0, guards: Guard[32] = [Guard {..}; 32], guard_count: u8 = 0,
}
fn stride(plan: Plan&) -> u32 { plan.word_count as u32 * 4 }
fn addStorage(plan: Plan&, ty: blot_backend_layout::Id, bytes: u32, parent: blot_support::Option<u8>, offset: u32, tag: blot_support::Option<u32>, guard_: blot_support::Option<u8>) -> blot_support::Option<u8> {
    if plan.storage_count == 32 { return blot_support::none<u8>(); }
    let index = plan.storage_count; plan.storage_count++;
    plan.storage[index] = Storage { layout: ty, bytes: bytes, parent: parent, offset: offset, tag: tag, guard_: guard_ , ..};
    if parent.present { plan.storage[parent.value].references |= 1 as u16 << (offset / 4); }
    return blot_support::some(index);
}
recursive fn visit<G>(plan: Plan&, generator: G&, ty: blot_backend_layout::Id, parent: blot_support::Option<u8>, offset: u32, remaining: i64&, depth: i64, guard_: blot_support::Option<u8>, word: u8&) -> bool, blot_error::Error {
    if remaining == 0 || depth >= 16 { return false, blot_error::Error.none; } remaining--;
    let node = generator.representations.store.node(ty);
    if node.tag == blot_backend_layout::Tag.unit || node.tag == blot_backend_layout::Tag.boolean || node.tag == blot_backend_layout::Tag.unsigned32 || node.tag == blot_backend_layout::Tag.floating32 {
        if plan.leaf_count == 64 || !parent.present || word >= 16 { return false, blot_error::Error.none; }
        plan.leaves[plan.leaf_count] = Leaf { owner: parent.value, offset: offset, floating: node.tag == blot_backend_layout::Tag.floating32, word: word, guard_: guard_ , ..};
        plan.leaf_count++; word++; return true, blot_error::Error.none;
    }
    if node.tag == blot_backend_layout::Tag.record || node.tag == blot_backend_layout::Tag.product {
        var step = 1; if node.tag == blot_backend_layout::Tag.record { step = 2; }
        let count = generator.representations.store.children(ty).len / step; if count == 0 || count > 16 { return false, blot_error::Error.none; }
        let owner = addStorage(plan, ty, (count * 4) as u32, parent, offset, blot_support::none<u32>(), guard_); if !owner.present { return false, blot_error::Error.none; }
        plan.storage[owner.value].word = word;
        for index in 0..count {
            let child = generator.representations.store.children(ty)[index * step + step - 1];
            let valid, error = visit(plan, generator, child, owner, (index * 4) as u32, remaining, depth + 1, guard_, word); if error != blot_error::Error.none || !valid { return false, error; }
        }
        return true, blot_error::Error.none;
    }
    if node.tag == blot_backend_layout::Tag.nominal {
        if node.a == 0 || node.a > generator.units.len { return false, blot_error::Error.none; }
        let source .= generator.unit(node.a); var tags: u32[4] = [0; 4]; var count = 0;
        for constructor in source.constructors {
            if remaining == 0 { return false, blot_error::Error.none; } remaining--;
            let nominal = source.nominal(constructor.nominal);
            if nominal.identity.unit != node.a || nominal.identity.decl != node.b { continue; }
            if count == 4 || nominal.is_opaque || nominal.private || nominal.has_usage || !nominal.closed_storage { return false, blot_error::Error.none; }
            tags[count] = constructor.tag; count++;
        }
        if count == 0 { return false, blot_error::Error.none; }
        let first_owner = plan.storage_count; let tag_word = word;
        if count > 1 {
            if word >= 16 || plan.leaf_count == 64 { return false, blot_error::Error.none; }
            plan.leaves[plan.leaf_count] = Leaf { owner: first_owner, word: tag_word, guard_: guard_, discriminant: true , ..}; plan.leaf_count++; word++;
        }
        let payload_start = word; var end = payload_start;
        for tag in tags[..count] {
            var active = guard_;
            if count > 1 {
                if plan.guard_count == 32 { return false, blot_error::Error.none; }
                active = blot_support::some(plan.guard_count); plan.guards[plan.guard_count] = Guard { parent: guard_, owner: first_owner, word: tag_word, tag: tag , ..}; plan.guard_count++;
            }
            let payload, payload_error = generator.nominalPayload((node.a as u64 << 32) | node.b, tag, ty);
            if payload_error != blot_error::Error.none { if payload_error == blot_error::Error.out_of_memory { return false, payload_error; } return false, blot_error::Error.none; }
            let owner = addStorage(plan, ty, 8, parent, offset, blot_support::some(tag), active); if !owner.present { return false, blot_error::Error.none; }
            plan.storage[owner.value].word = tag_word; plan.storage[owner.value].unit_payload = generator.representations.store.node(payload).tag == blot_backend_layout::Tag.unit;
            var arm_word = payload_start; let valid, error = visit(plan, generator, payload, owner, 4, remaining, depth + 1, active, arm_word);
            if error != blot_error::Error.none || !valid { return false, error; } if arm_word > end { end = arm_word; }
        }
        word = end; return true, blot_error::Error.none;
    }
    return false, blot_error::Error.none;
}
fn analyze<G>(generator: G&, ty: blot_backend_layout::Id) -> blot_support::Option<Plan>, blot_error::Error {
    var plan = Plan {..}; var remaining: i64 = 256; var words: u8 = 0;
    let valid, error = visit(plan, generator, ty, blot_support::none<u8>(), 0, remaining, 0, blot_support::none<u8>(), words);
    if error != blot_error::Error.none { return blot_support::none<Plan>(), error; } plan.word_count = words;
    if !valid || words == 0 { return blot_support::none<Plan>(), blot_error::Error.none; }
    return blot_support::some(plan), blot_error::Error.none;
}
struct Cache { rows: dictionary<blot_backend_layout::Id, Plan>& }
fn get<G>(cache: Cache&, generator: G&, ty: blot_backend_layout::Id) -> blot_support::Option<Plan>, blot_error::Error {
    let known = ::get(cache.rows,ty); if known { if known.word_count == 0 { return blot_support::none<Plan>(), blot_error::Error.none; } return blot_support::some(copy(known)), blot_error::Error.none; }
    let plan, error = analyze(generator, ty); if error != blot_error::Error.none { return plan, error; }
    var value = Plan {..}; if plan.present { value = plan.value; } ::insert(cache.rows,ty, value); return plan, blot_error::Error.none;
}
fn deinit(cache: Cache&) { ::clear(cache.rows); }
