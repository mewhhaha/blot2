// Canonical semantic interface graphs. Structural nodes are hash-consed by
// exact bytes; BLAKE3 accelerates lookup but never substitutes for equality.
import .model;
import .hash;

struct CanonRow { words: Span }
struct CanonMemo { type_id: u32, context: Span, canonical: u32 }
fn canonical_interface(c: Core, type_id: u32, out: u8[>..]&) -> bool {
    var rows: CanonRow[>..] = [CanonRow { .. }]; var words: u32[>..] = [];
    var pending: u32[>..<] = []; var bound: u32[>..<] = []; var free: u32[>..] = [];
    var slots: u32[131072] = [0; 131072];
    var memo: CanonMemo[>..] = []; var contexts: u32[>..] = []; var memo_slots: u32[131072] = [0; 131072];
    var free_values: u32[>..] = [];
    var visits: u32 = 0;
    fn tick() { visits++; if visits > LIMIT_VISITS { return false from canonical_interface; } }
    fn put(n: u32) { tick(); pending.push(n); }
    fn text(bytes: const u8[:]) {
        put(bytes.len as u32);
        var at: i64 = 0;
        while at < bytes.len {
            var word: u32 = 0;
            for i in 4 { if at + i < bytes.len { word |= (bytes[at + i] as u32) << (8 * i); } }
            put(word); at += 4;
        }
    }
    fn intern(mark: i64) -> u32 {
        let candidate = pending[mark..];
        var hash: u32 = 2166136261;
        for word in candidate { tick(); hash = (hash ^ word) * 16777619; }
        var slot = hash & 131071;
        var probes: u32 = 0;
        while slots[slot] != 0 {
            tick(); probes++; if probes == 131072 { return false from canonical_interface; }
            let i = slots[slot]; let row = rows[i];
            if row.words.count == candidate.len {
                var equal = true;
                for word, j in candidate { tick(); if words[row.words.start + j] != word { equal = false; break; } }
                if equal { pending.resize(mark); return i; }
            }
            slot = (slot + 1) & 131071;
        }
        if words.len + candidate.len > LIMIT_ARTIFACT / 4 { return false from canonical_interface; }
        let id = rows.len as u32;
        slots[slot] = id;
        rows.push(CanonRow { words: Span { start: words.len as u32, count: candidate.len as u32 } });
        words.append(candidate); pending.resize(mark); return id;
    }
    fn binder(id: u32) {
        if id == 0 { put(0); return; }
        var at = bound.len;
        while at > 0 { at--; if bound[at] == id { put(1); put((bound.len - at) as u32); return; } }
        // Ambient compiler-captured binders retain kind/constraint/name identity;
        // lexical source positions and allocation addresses never enter a key.
        var index: u32 = 0;
        for value, i in free { if value == id { index = i as u32 + 1; break; } }
        if index == 0 { free.push(id); index = free.len as u32; }
        put(2); put(index); let b = c.binders[id]; put(b.kind); put(b.constraints);
    }
    recursive fn term(id: u32, depth: u32) -> u32 {
        if id == 0 { return 0; }
        if depth > 64 || !id_ok(id, c.terms.len) { return false from canonical_interface; }
        let t = c.terms[id]; let mark = pending.len;
        put(2); put(t.tag); put(t.literal);
        if t.tag == EXPR_BINDER { binder(t.binder); }
        else if t.tag == EXPR_ARG || t.tag == EXPR_RESULT { put(0); }
        else if t.value != 0 {
            // Internal schemas may carry dependent lengths obtained from an SSA
            // value. Alpha-normalize their equality relationships, never their
            // allocation index or source position.
            var index: u32 = 0;
            for value, i in free_values { if value == t.value { index = i as u32 + 1; break; } }
            if index == 0 { free_values.push(t.value); index = free_values.len as u32; }
            put(index);
        }
        put(t.args.count); for i in t.args.count { put(term(c.refs[t.args.start + i], depth + 1)); }
        return intern(mark);
    }
    fn fact(id: u32) -> u32 {
        if !id_ok(id, c.facts.len) { return false from canonical_interface; }
        let f = c.facts[id]; let mark = pending.len;
        put(3); put(f.tag); put(term(f.left, 0)); put(term(f.right, 0)); put(term(f.third, 0)); binder(f.domain);
        return intern(mark);
    }
    fn facts(span: Span) {
        put(span.count); for i in span.count { put(fact(c.refs[span.start + i])); }
    }
    recursive fn layout_shape(id: u32, depth: u32) -> u32 {
        if !id_ok(id, c.types.len) || depth > 64 { return false from canonical_interface; }
        let key = id | 0x80000000; var hash = key * 16777619;
        for bid in bound { hash = (hash ^ bid) * 16777619; }
        var slot = hash & 131071;
        while memo_slots[slot] != 0 {
            tick(); let old = memo[memo_slots[slot] - 1]; var same = old.type_id == key && old.context.count == bound.len;
            if same { for bid, i in bound { tick(); if contexts[old.context.start + i] != bid { same = false; break; } } }
            if same { return old.canonical; } slot = (slot + 1) & 131071;
        }
        let t = c.types[id];
        if t.tag == TY_ALIAS || t.tag == TY_FORALL { return layout_shape(c.refs[t.children.start], depth + 1); }
        let mark = pending.len; put(5); put(t.tag);
        if t.tag == TY_PARAM { binder(t.binder); }
        else if t.tag == TY_TUPLE || t.tag == TY_RECORD || t.tag == TY_SUM || t.tag == TY_RESULT || t.tag == TY_EXISTS {
            var prefix: u32 = 0;
            if t.tag == TY_EXISTS { for i in t.binders.count { if c.binders[c.refs[t.binders.start + i]].kind == KIND_NAT { prefix++; } } }
            put(prefix); let count = if t.fields.count != 0 { t.fields.count } else { t.children.count }; put(count);
            for i in count { let child = if t.fields.count != 0 { c.fields[c.refs[t.fields.start + i]].type_id } else { c.refs[t.children.start + i] }; put(layout_shape(child, depth + 1)); }
        }
        let result = intern(mark); let context = Span { start: contexts.len as u32, count: bound.len as u32 }; contexts.append(bound);
        slot = hash & 131071; while memo_slots[slot] != 0 { tick(); slot = (slot + 1) & 131071; }
        memo.push(CanonMemo { type_id: key, context: context, canonical: result }); memo_slots[slot] = memo.len as u32; return result;
    }
    recursive fn contract(id: u32, depth: u32) -> u32 {
        if !id_ok(id, c.contracts.len) || depth > 64 { return false from canonical_interface; }
        let ct = c.contracts[id]; let mark = pending.len;
        put(4); put(shape(ct.arg, depth + 1)); put(shape(ct.result, depth + 1));
        put(ct.depth); put(ct.frame);
        put(ct.effects.count);
        for i in ct.effects.count { let e = c.effects[c.refs[ct.effects.start + i]]; put(e.kind); binder(e.region); }
        facts(ct.requires); facts(ct.ensures); facts(ct.on_true); facts(ct.on_false);
        put(ct.layout_premises.count);
        for i in ct.layout_premises.count {
            let premise = c.layout_premises[c.refs[ct.layout_premises.start + i]];
            put(premise.kind); put(layout_shape(premise.type_id, depth + 1));
        }
        return intern(mark);
    }
    recursive fn shape(id: u32, depth: u32) -> u32 {
        if !id_ok(id, c.types.len) || depth > 64 { return false from canonical_interface; }
        var memo_hash = id * 16777619;
        for bid in bound { memo_hash = (memo_hash ^ bid) * 16777619; }
        var memo_slot = memo_hash & 131071; var memo_probes: u32 = 0;
        while memo_slots[memo_slot] != 0 {
            tick(); memo_probes++; if memo_probes == 131072 { return false from canonical_interface; }
            let previous = memo[memo_slots[memo_slot] - 1];
            if previous.type_id == id && previous.context.count == bound.len {
                var equal = true;
                for bid, i in bound { tick(); if contexts[previous.context.start + i] != bid { equal = false; break; } }
                if equal { return previous.canonical; }
            }
            memo_slot = (memo_slot + 1) & 131071;
        }
        let context = Span { start: contexts.len as u32, count: bound.len as u32 }; contexts.append(bound);
        let t = c.types[id];
        if t.tag == TY_ALIAS { return shape(c.refs[t.children.start], depth + 1); }
        let mark = pending.len; let binder_mark = bound.len;
        put(1); put(t.tag); put(t.mode);
        put(t.binders.count);
        for i in t.binders.count {
            let bid = c.refs[t.binders.start + i]; let b = c.binders[bid];
            put(b.kind); put(b.constraints); bound.push(bid);
        }
        binder(t.region); binder(t.domain); binder(t.binder);
        put(term(t.nat, 0)); put(term(t.capacity, 0));
        let count = if t.fields.count != 0 { t.fields.count } else { t.children.count };
        put(count);
        for i in count {
            if t.fields.count != 0 {
                let field = c.fields[c.refs[t.fields.start + i]];
                if t.tag == TY_RECORD || t.tag == TY_SUM || t.tag == TY_RESULT { text(name_bytes(c, field.name)); }
                put(shape(field.type_id, depth + 1));
            } else { put(shape(c.refs[t.children.start + i], depth + 1)); }
        }
        put(if t.contract != 0 { contract(t.contract, depth + 1) } else { 0 });
        let result = intern(mark); bound.resize(binder_mark);
        memo_slot = memo_hash & 131071;
        while memo_slots[memo_slot] != 0 { tick(); memo_slot = (memo_slot + 1) & 131071; }
        memo.push(CanonMemo { type_id: id, context: context, canonical: result }); memo_slots[memo_slot] = memo.len as u32;
        return result;
    }
    let root = shape(type_id, 0);
    out.append(ABI_HASH);
    for word in [SEM_POLICY, root, rows.len as u32] { for i in 4 { out.push((word >> (8 * i)) as! u8); } }
    for row, i in rows {
        if i == 0 { continue; }
        for j in 4 { out.push((row.words.count >> (8 * j)) as! u8); }
        for word in words[row.words.start..row.words.start + row.words.count] { for j in 4 { out.push((word >> (8 * j)) as! u8); } }
    }
    return true;
}
