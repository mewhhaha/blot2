// Conditionals, blocks, matches and loops of the direct backend's function
// emitter (compiler/src/direct/function.zig).
namespace blot_direct_function;
import .function;

// `count` empty result slots; the first one's index.
fn newSlots(g: Generator&, count: i64) -> u32 {
    let first = g.s.slots.len as u32;
    for at in 0..count { g.s.slots.push(blot_direct_emit::Slot {}); }
    return first;
}
recursive fn ifNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let result = g.newSlot();
    let merges = m.branchMerges(id);
    let merged = newSlots(g, merges.len);
    let condition, error = expr(g, f, n.a);
    if error != blot_direct_types::Error.none { return condition, error; }
    push(g, condition);
    let opened = open(g, f, OP_if_);
    let then, error = stmt(g, f, n.b);
    if error != blot_direct_types::Error.none { return then, error; }
    var falls = then.ty != blot_direct_types::never;
    if falls {
        if n.tag == blot_check_core::Tag.if_value {
            let delivered = deliver(g, f, then, result, id);
            if delivered != blot_direct_types::Error.none { return neverVal(), delivered; }
        }
        for merge, at in merges {
            let value, present = bindGet(g, f, merge.then_binding);
            if present {
                let delivered = deliver(g, f, value, merged + (at as u32), id);
                if delivered != blot_direct_types::Error.none { return neverVal(), delivered; }
            }
        }
    }
    op(g, OP_else_);
    if n.c != 0 {
        let otherwise, error = stmt(g, f, n.c);
        if error != blot_direct_types::Error.none { return otherwise, error; }
        if otherwise.ty != blot_direct_types::never {
            falls = true;
            if n.tag == blot_check_core::Tag.if_value {
                let delivered = deliver(g, f, otherwise, result, id);
                if delivered != blot_direct_types::Error.none { return neverVal(), delivered; }
            }
            for merge, at in merges {
                let value, present = bindGet(g, f, merge.else_binding);
                if present {
                    let delivered = deliver(g, f, value, merged + (at as u32), id);
                    if delivered != blot_direct_types::Error.none { return neverVal(), delivered; }
                }
            }
        }
    } else {
        falls = true;
        for merge, at in merges {
            let value, present = bindGet(g, f, merge.else_binding);
            if present {
                let delivered = deliver(g, f, value, merged + (at as u32), id);
                if delivered != blot_direct_types::Error.none { return neverVal(), delivered; }
            }
        }
    }
    close(g, f);
    for merge, at in merges {
        let slot = g.s.slots[merged + at];
        if slot.present { bindPut(g, f, merge.result, slot.value); }
    }
    if !falls { return neverVal(), blot_direct_types::Error.none; }
    if n.tag == blot_check_core::Tag.if_stmt { return unitVal(), blot_direct_types::Error.none; }
    if g.s.slots[result].present { return g.s.slots[result].value, blot_direct_types::Error.none; }
    return neverVal(), blot_direct_types::Error.none;
}

recursive fn block_(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let result = g.newSlot();
    let depth = open(g, f, OP_block);
    let s .= g.s;
    let mark = s.labels.len;
    s.labels.push(blot_direct_emit::Label { target: id, depth: depth, result: result });
    var last = unitVal();
    let children = m.children(id);
    for child in children {
        // Statements after one that always diverges are unreachable.
        if last.ty == blot_direct_types::never { break; }
        let value, error = stmt(g, f, child);
        if error != blot_direct_types::Error.none { s.labels.resize(mark); return value, error; }
        last = value;
    }
    s.labels.resize(mark);
    close(g, f);
    if g.s.slots[result].present { return g.s.slots[result].value, blot_direct_types::Error.none; }
    // A Unit block may fall through its end.
    if last.ty != blot_direct_types::never && m.typeOf(id) == blot_check_types::unit { return unitVal(), blot_direct_types::Error.none; }
    return neverVal(), blot_direct_types::Error.none;
}
// Copies `value` into a lazily allocated result slot.
fn deliver(g: Generator&, f: const Fn&, value: Val, slot: u32, id: u32) -> Error {
    if value.ty == blot_direct_types::never { return blot_direct_types::Error.none; }
    if !g.s.slots[slot].present {
        let made, error = fresh(g, f, value.ty, id);
        if error != blot_direct_types::Error.none { return error; }
        g.s.slots[slot] = blot_direct_emit::Slot { true, made };
    }
    return copy(g, f, value, g.s.slots[slot].value, id);
}

recursive fn returnNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let value, error = stmt(g, f, n.a);
    if error != blot_direct_types::Error.none { return value, error; }
    if value.ty == blot_direct_types::never { return neverVal(), blot_direct_types::Error.none; }
    var at = g.s.labels.len;
    while at != f.labels_base {
        at -= 1;
        let label = g.s.labels[at];
        if (label.target != n.b && label.kind != blot_direct_emit::LabelKind.function) || label.kind == blot_direct_emit::LabelKind.loop_ { continue; }
        let delivered = deliver(g, f, value, label.result, id);
        if delivered != blot_direct_types::Error.none { return neverVal(), delivered; }
        leaveHandles(g, f, label.depth);
        br(g, f, OP_br, label.depth);
        return neverVal(), blot_direct_types::Error.none;
    }
    return neverVal(), g.fail(m, id, "return outside its block");
}

fn sameWords(g: const Generator&, left: Val, right: Val) -> bool {
    if left.len != right.len { return false; }
    for at in 0..(left.len as i64) { if g.s.words[left.start + at] != g.s.words[right.start + at] { return false; } }
    return true;
}
recursive fn match_(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let info = m.matchInfo(id);
    let inputs = m.matchInputs(id);
    let values = g.reserveVals(inputs.len);
    for input, at in inputs {
        let value, error = expr(g, f, input);
        if error != blot_direct_types::Error.none { return value, error; }
        g.s.vals[values.start + at] = value;
    }
    let result = g.newSlot();
    let merges = m.branchMerges(id);
    let merged = newSlots(g, merges.len);
    var falls = false;
    let done = open(g, f, OP_block);
    let arms = m.matchArms(id);
    for arm, arm_index in arms {
        let rows = m.armRows(arm);
        let next = open(g, f, OP_block);
        if rows.len == 1 {
            let patterns = m.rowPatterns(rows[0]);
            for pattern, at in patterns {
                let tested = test_(g, f, pattern, g.s.vals[values.start + at], true, next, id);
                if tested != blot_direct_types::Error.none { return neverVal(), tested; }
            }
        } else {
            // Alternatives bind the same names; later rows copy into the first row's locals.
            let matched = open(g, f, OP_block);
            var first = blot_direct_zigmap::Map {};
            for row, row_index in rows {
                let row_fail = open(g, f, OP_block);
                let before = blot_direct_zigmap::clone(g.s.map_pool, f.bindings);
                let patterns = m.rowPatterns(row);
                for pattern, at in patterns {
                    let tested = test_(g, f, pattern, g.s.vals[values.start + at], true, row_fail, id);
                    if tested != blot_direct_types::Error.none { return neverVal(), tested; }
                }
                if row_index == 0 {
                    // Zig walks its hash map here; the table keeps its order.
                    let table = f.bindings;
                    for slot in 0..(table.capacity as i64) {
                        if !blot_direct_zigmap::used(g.s.map_pool, table, slot as u32) { continue; }
                        let key = blot_direct_zigmap::keyAt(g.s.map_pool, table, slot as u32);
                        let entry = g.s.vals[blot_direct_zigmap::valueAt(g.s.map_pool, table, slot as u32)];
                        let prior_at, has_prior = blot_direct_zigmap::get(g.s.map_pool, before, key);
                        if has_prior && sameWords(g, g.s.vals[prior_at], entry) { continue; }
                        let owned, error = fresh(g, f, entry.ty, id);
                        if error != blot_direct_types::Error.none { return neverVal(), error; }
                        let copied = copy(g, f, entry, owned, id);
                        if copied != blot_direct_types::Error.none { return neverVal(), copied; }
                        g.s.vals.push(owned);
                        blot_direct_zigmap::put(g.s.map_pool, first, key, (g.s.vals.len - 1) as u32);
                    }
                } else {
                    // Every name the first row binds: a later row's payload
                    // may sit in the same locals as the first row's.
                    for slot in 0..(first.capacity as i64) {
                        if !blot_direct_zigmap::used(g.s.map_pool, first, slot as u32) { continue; }
                        let key = blot_direct_zigmap::keyAt(g.s.map_pool, first, slot as u32);
                        let target = g.s.vals[blot_direct_zigmap::valueAt(g.s.map_pool, first, slot as u32)];
                        let value, present = bindGet(g, f, key);
                        if present {
                            let copied = copy(g, f, value, target, id);
                            if copied != blot_direct_types::Error.none { return neverVal(), copied; }
                        }
                    }
                }
                br(g, f, OP_br, matched);
                close(g, f);
            }
            br(g, f, OP_br, next);
            close(g, f);
            for slot in 0..(first.capacity as i64) {
                if !blot_direct_zigmap::used(g.s.map_pool, first, slot as u32) { continue; }
                let key = blot_direct_zigmap::keyAt(g.s.map_pool, first, slot as u32);
                bindPut(g, f, key, g.s.vals[blot_direct_zigmap::valueAt(g.s.map_pool, first, slot as u32)]);
            }
        }
        if arm.guard_ != 0 {
            let guard_value, error = expr(g, f, arm.guard_);
            if error != blot_direct_types::Error.none { return guard_value, error; }
            push(g, guard_value);
            op(g, OP_i32_eqz);
            br(g, f, OP_br_if, next);
        }
        let body, error = stmt(g, f, arm.body);
        if error != blot_direct_types::Error.none { return body, error; }
        if body.ty != blot_direct_types::never {
            falls = true;
            if !info.statement {
                let delivered = deliver(g, f, body, result, id);
                if delivered != blot_direct_types::Error.none { return neverVal(), delivered; }
            }
            // A two-arm statement match carries rebindings like an if.
            if merges.len != 0 && arm_index < 2 {
                for merge, at in merges {
                    var binding = merge.else_binding;
                    if arm_index == 0 { binding = merge.then_binding; }
                    let value, present = bindGet(g, f, binding);
                    if present {
                        let delivered = deliver(g, f, value, merged + (at as u32), id);
                        if delivered != blot_direct_types::Error.none { return neverVal(), delivered; }
                    }
                }
            }
        }
        br(g, f, OP_br, done);
        close(g, f);
    }
    op(g, OP_unreachable_);
    close(g, f);
    for merge, at in merges {
        let slot = g.s.slots[merged + at];
        if slot.present { bindPut(g, f, merge.result, slot.value); }
    }
    if !falls { return neverVal(), blot_direct_types::Error.none; }
    if info.statement { return unitVal(), blot_direct_types::Error.none; }
    if g.s.slots[result].present { return g.s.slots[result].value, blot_direct_types::Error.none; }
    return neverVal(), blot_direct_types::Error.none;
}

// Tests `pattern` against `value`, branching to `fail` (a Wasm depth) on
// mismatch, and binds its names. Without `has_fail` a mismatch traps.
recursive fn test_(g: Generator&, f: Fn&, pattern_id: u32, value: Val, has_fail: bool, fail: u32, id: u32) -> Error {
    let m .= g.units[f.unit - 1];
    let pattern = m.pattern(pattern_id);
    if value.ty == blot_direct_types::never { return blot_direct_types::Error.none; }
    match pattern.tag {
        wildcard => {},
        bind => {
            refine(g, f, m.binding(pattern.a).ty, value.ty);
            bindPut(g, f, pattern.a, value);
        },
        constant, value => {
            let tag = g.types.node(value.ty).tag;
            // Unit has one value: its pattern always matches.
            if tag == blot_direct_types::Tag.unit {
                if pattern.tag == blot_check_core::PatternTag.value {
                    let ignored, error = expr(g, f, pattern.a);
                    if error != blot_direct_types::Error.none { return error; }
                }
                return blot_direct_types::Error.none;
            }
            push(g, value);
            if pattern.tag == blot_check_core::PatternTag.constant {
                if tag == blot_direct_types::Tag.f32_ { f32Const(g, pattern.a); } else { i32Const(g, pattern.a); }
            } else {
                let expected, error = expr(g, f, pattern.a);
                if error != blot_direct_types::Error.none { return error; }
                push(g, expected);
            }
            if tag == blot_direct_types::Tag.f32_ { op(g, OP_f32_ne); } else { op(g, OP_i32_ne); }
            failIf(g, f, has_fail, fail);
        },
        product => {
            let children = m.patternChildren(pattern_id);
            let shape = g.types.node(value.ty);
            match shape.tag {
                tuple => {
                    for child, index in children {
                        let item, error = tupleItem(g, f, value, index, id);
                        if error != blot_direct_types::Error.none { return error; }
                        let tested = test_(g, f, child, item, has_fail, fail, id);
                        if tested != blot_direct_types::Error.none { return tested; }
                    }
                },
                unit => {},
                // Children follow the pattern's Core record type order.
                record => { return recordPattern(g, f, pattern_id, false, m.types.node(pattern.ty), value, has_fail, fail, id); },
                _ => {
                    g.failOpen(m, id);
                    g.put("product pattern on a ");
                    g.put(blot_direct_types::tagName(shape.tag));
                    return g.failClose();
                },
            }
        },
        constructor => {
            let constructor = m.constructor(pattern.a);
            let cases, error = g.types.variants(value.ty);
            if error != blot_direct_types::Error.none { return g.typeFailure(m, id); }
            if cases.len > 1 {
                lget(g, w(g, value, 0));
                // A boxed value's tag is the first word of its block.
                let boxed, error = isBoxed(g, f, value.ty, id);
                if error != blot_direct_types::Error.none { return error; }
                if boxed {
                    op(g, OP_i32_load);
                    uleb(g, 2);
                    uleb(g, 0);
                }
                i32Const(g, constructor.tag);
                op(g, OP_i32_ne);
                failIf(g, f, has_fail, fail);
            }
            if pattern.b != 0 {
                let payload, error = unwrapVariant(g, f, value, constructor.tag, id);
                if error != blot_direct_types::Error.none { return error; }
                return test_(g, f, pattern.b, payload, has_fail, fail, id);
            }
        },
        record_payload => {
            if g.types.node(value.ty).tag != blot_direct_types::Tag.record { return g.fail(m, id, "record pattern on a non-record"); }
            // One pattern for a wider record binds the whole payload as a
            // tuple in declared field order.
            let storage = m.types.node(pattern.ty);
            if m.pattern(pattern.b).tag != blot_check_core::PatternTag.product && storage.tag == blot_check_types::Tag.record && storage.b > 1 {
                let declared, error = declaredTuple(g, f, storage, value, id);
                if error != blot_direct_types::Error.none { return error; }
                return test_(g, f, pattern.b, declared, has_fail, fail, id);
            }
            // A one-field record's child is that field's own pattern.
            if m.pattern(pattern.b).tag == blot_check_core::PatternTag.product { return recordPattern(g, f, pattern.b, false, storage, value, has_fail, fail, id); }
            return recordPattern(g, f, pattern.b, true, storage, value, has_fail, fail, id);
        },
        invalid => { return g.fail(m, id, "invalid pattern"); },
    }
    return blot_direct_types::Error.none;
}
// The fields of record `value` as a tuple in the declared order of the Core
// record type `storage`.
fn declaredTuple(g: Generator&, f: Fn&, storage: blot_check_types::Node, value: Val, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    var items: Ty[>..<] = [];
    var collected: u32[>..<] = [];
    for index in 0..(storage.b as i64) {
        let field = m.types.recordField(storage, index);
        let spelling = m.fieldSpelling(field.name);
        if !spelling.present { return neverVal(), g.fail(m, id, "record pattern field without a spelling"); }
        let position = g.types.findField(value.ty, g.types.fieldName(spelling.value));
        if position < 0 { return neverVal(), g.fail(m, id, "record pattern field missing"); }
        let part, error = recordField(g, f, value, position, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        items.push(part.ty);
        for at in 0..(part.len as i64) { collected.push(g.s.words[part.start + at]); }
    }
    let ty, error = g.types.tuple(items[..]);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let words = g.saveWords(collected[..]);
    return Val { ty, words.start, words.len }, blot_direct_types::Error.none;
}
// Child `i` matches field `i` of the Core record type `storage`. The children
// are those of product pattern `pattern_id`, or that pattern alone (`single`).
recursive fn recordPattern(g: Generator&, f: Fn&, pattern_id: u32, single: bool, storage: blot_check_types::Node, value: Val, has_fail: bool, fail: u32, id: u32) -> Error {
    let m .= g.units[f.unit - 1];
    var count: i64 = 1;
    if !single { count = m.patternChildren(pattern_id).len; }
    if storage.tag != blot_check_types::Tag.record || storage.b < count { return g.fail(m, id, "record pattern without a record type"); }
    for index in 0..count {
        var child = pattern_id;
        if !single { child = m.patternChildren(pattern_id)[index]; }
        let field = m.types.recordField(storage, index);
        let spelling = m.fieldSpelling(field.name);
        if !spelling.present { return g.fail(m, id, "record pattern field without a spelling"); }
        let position = g.types.findField(value.ty, g.types.fieldName(spelling.value));
        if position < 0 { return g.fail(m, id, "record pattern field missing"); }
        let part, error = recordField(g, f, value, position, id);
        if error != blot_direct_types::Error.none { return error; }
        let tested = test_(g, f, child, part, has_fail, fail, id);
        if tested != blot_direct_types::Error.none { return tested; }
    }
    return blot_direct_types::Error.none;
}
fn failIf(g: Generator&, f: Fn&, has_fail: bool, fail: u32) {
    if has_fail { br(g, f, OP_br_if, fail); return; }
    let opened = open(g, f, OP_if_);
    op(g, OP_unreachable_);
    close(g, f);
}

fn hasWord(g: const Generator&, value: Val, wanted: u32) -> bool {
    for at in 0..(value.len as i64) { if g.s.words[value.start + at] == wanted { return true; } }
    return false;
}
// Copies `values` into `targets` through temporaries, so a value may read a
// target that an earlier assignment already overwrote.
fn assign(g: Generator&, f: const Fn&, values: Vals, targets: Vals, id: u32) -> Error {
    let staged = g.reserveVals(values.len);
    for at in 0..(values.len as i64) {
        let value = g.s.vals[values.start + at];
        let target = g.s.vals[targets.start + at];
        g.s.vals[staged.start + at] = value;
        if value.ty == blot_direct_types::never || sameWords(g, value, target) { continue; }
        for other_at in 0..(targets.len as i64) {
            let other = g.s.vals[targets.start + other_at];
            // Zig's `break` leaves only the scan of this target's words.
            for word_at in 0..(other.len as i64) {
                if hasWord(g, value, g.s.words[other.start + word_at]) {
                    let made, error = fresh(g, f, target.ty, id);
                    if error != blot_direct_types::Error.none { return error; }
                    g.s.vals[staged.start + at] = made;
                    let copied = copy(g, f, value, made, id);
                    if copied != blot_direct_types::Error.none { return copied; }
                    break;
                }
            }
        }
    }
    for at in 0..(values.len as i64) {
        let copied = copy(g, f, g.s.vals[staged.start + at], g.s.vals[targets.start + at], id);
        if copied != blot_direct_types::Error.none { return copied; }
    }
    return blot_direct_types::Error.none;
}
// assign, but a boxed carry's new value is copied into its slot.
fn assignCarries(g: Generator&, f: const Fn&, values: Vals, targets: Vals, slots: Words, id: u32) -> Error {
    let plain_values = g.reserveVals(values.len);
    let plain_targets = g.reserveVals(values.len);
    var plain: u32 = 0;
    for at in 0..(values.len as i64) {
        let value = g.s.vals[values.start + at];
        let target = g.s.vals[targets.start + at];
        if g.s.words[slots.start + at] == 0 {
            g.s.vals[plain_values.start + plain] = value;
            g.s.vals[plain_targets.start + plain] = target;
            plain += 1;
            continue;
        }
        if value.ty == blot_direct_types::never || w(g, value, 0) == w(g, target, 0) { continue; }
        let bytes, error = blockBytes(g, f, value.ty, id);
        if error != blot_direct_types::Error.none { return error; }
        memoryCopy(g, w(g, target, 0), 0, w(g, value, 0), bytes);
    }
    return assign(g, f, Vals { plain_values.start, plain }, Vals { plain_targets.start, plain }, id);
}
recursive fn loop_(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let info = m.loopInfo(id);
    let carries = m.loopCarries(id);
    let incoming = g.reserveVals(carries.len);
    for carry, at in carries {
        let value, present = bindGet(g, f, carry.incoming);
        if !present { return neverVal(), g.fail(m, id, "loop carry without an incoming value"); }
        g.s.vals[incoming.start + at] = value;
    }
    let iteration = g.reserveVals(carries.len);
    let outgoing = g.reserveVals(carries.len);
    // A boxed carry lives in a slot reserved before the loop, so each
    // iteration can release what it allocated.
    let slots = Words { g.s.words.len as u32, carries.len as u32 };
    for carry in carries { g.s.words.push(0); }
    for at in 0..carries.len {
        let value = g.s.vals[incoming.start + at];
        let held, error = copiedBox(g, f, value.ty, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        if held {
            g.s.words[slots.start + at] = 1;
            let reserved, error = newBlock(g, f, value.ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            g.s.vals[iteration.start + at] = valOf1(g, value.ty, reserved);
        } else {
            let current, error = fresh(g, f, value.ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            g.s.vals[iteration.start + at] = current;
        }
        let after, error = fresh(g, f, value.ty, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        g.s.vals[outgoing.start + at] = after;
    }
    let assigned = assignCarries(g, f, incoming, iteration, slots, id);
    if assigned != blot_direct_types::Error.none { return neverVal(), assigned; }
    for carry, at in carries { bindPut(g, f, carry.iteration, g.s.vals[iteration.start + at]); }
    var has_index = false;
    var index: u32 = 0;
    var end = neverVal();
    var has_source = false;
    var source = neverVal();
    match info.kind {
        forever => {},
        range => {
            has_index = true;
            index = local32(g, f);
            let first, error = expr(g, f, info.first);
            if error != blot_direct_types::Error.none { return first, error; }
            let copied = copy(g, f, first, valOf1(g, blot_direct_types::u32_, index), id);
            if copied != blot_direct_types::Error.none { return neverVal(), copied; }
            let limit, error = fresh(g, f, blot_direct_types::u32_, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            end = limit;
            let last, error = expr(g, f, info.end);
            if error != blot_direct_types::Error.none { return last, error; }
            let copied = copy(g, f, last, end, id);
            if copied != blot_direct_types::Error.none { return neverVal(), copied; }
        },
        array => {
            let container, error = expr(g, f, info.first);
            if error != blot_direct_types::Error.none { return container, error; }
            has_source = true;
            source = container;
            has_index = true;
            index = constLocal(g, f, 0);
            let length, error = lengthOf(g, f, source, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            end = valOf1(g, blot_direct_types::u32_, length);
        },
    }
    let exit = open(g, f, OP_block);
    let top = open(g, f, OP_loop);
    if has_index {
        lget(g, index);
        lget(g, w(g, end, 0));
        op(g, OP_i32_ge_u);
        let opened = open(g, f, OP_if_);
        let assigned = assign(g, f, iteration, outgoing, id);
        if assigned != blot_direct_types::Error.none { return neverVal(), assigned; }
        br(g, f, OP_br, exit);
        close(g, f);
        let current = local32(g, f);
        lget(g, index);
        lset(g, current);
        lget(g, index);
        i32Const(g, 1);
        op(g, OP_i32_add);
        lset(g, index);
        var item = neverVal();
        if has_source {
            let element, error = readElement(g, f, source, current, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            item = element;
        } else { item = valOf1(g, blot_direct_types::u32_, current); }
        if info.pattern != 0 {
            let tested = test_(g, f, info.pattern, item, false, 0, id);
            if tested != blot_direct_types::Error.none { return neverVal(), tested; }
        }
    }
    // An iteration may release what it allocated when no carry can refer to
    // it: carries are plain values or owners of plain elements, each carried
    // owner predates the iteration (checked at run time), and the body stored
    // no memory-holding value into older storage.
    var release = true;
    let s .= g.s;
    let scratch_mark = s.scratch.len;
    for at in 0..carries.len {
        let value = g.s.vals[iteration.start + at];
        let safe, error = ownerSlots(g, value.ty, value.start);
        if error != blot_direct_types::Error.none { s.scratch.resize(scratch_mark); return neverVal(), error; }
        if !safe { release = false; }
    }
    let guards = Words { g.s.words.len as u32, (s.scratch.len - scratch_mark) as u32 };
    for at in scratch_mark..s.scratch.len { let slot = s.scratch[at]; g.s.words.push(slot); }
    s.scratch.resize(scratch_mark);
    let owner_mark = local32(g, f);
    let stack_mark = local32(g, f);
    let allow = local32(g, f);
    let mark_at = s.code.len;
    let allocations = f.allocations;
    let stores = f.memory_stores;
    let unused = g.newSlot();
    let labels_mark = s.labels.len;
    s.labels.push(blot_direct_emit::Label { target: id, depth: exit, result: unused, kind: blot_direct_emit::LabelKind.loop_, top: top, iteration: iteration, outgoing: outgoing, has_release: release, release_owner: owner_mark, release_stack: stack_mark, slots: slots, allow: allow, guards: guards });
    let body, error = stmt(g, f, info.body);
    let label = s.labels[labels_mark];
    s.labels.resize(labels_mark);
    if error != blot_direct_types::Error.none { return body, error; }
    if body.ty != blot_direct_types::never {
        let backedge = g.reserveVals(carries.len);
        for carry, at in carries {
            let value, present = bindGet(g, f, carry.backedge);
            if !present { return neverVal(), g.fail(m, id, "loop carry without a backedge value"); }
            g.s.vals[backedge.start + at] = value;
        }
        let assigned = assignCarries(g, f, backedge, iteration, slots, id);
        if assigned != blot_direct_types::Error.none { return neverVal(), assigned; }
        if label.has_release && f.allocations != allocations { releaseIteration(g, f, label); }
        br(g, f, OP_br, top);
    }
    if release && (f.allocations != allocations || label.used) {
        // Insert the iteration's marks at its start, now that the body is
        // known to allocate.
        var prefix: u8[>..<] = [];
        markInto(g, prefix, owner_mark, stack_mark);
        prefix.push(OP_i32_const);
        blot_direct_writer::sleb(prefix, boolWord(f.memory_stores == stores));
        prefix.push(OP_local_set);
        blot_direct_writer::uleb(prefix, allow);
        let old_len = s.code.len;
        for byte in prefix { s.code.push(byte); }
        var at = old_len;
        while at > mark_at {
            at -= 1;
            s.code[at + prefix.len] = s.code[at];
        }
        for byte, offset in prefix { s.code[mark_at + offset] = byte; }
    }
    close(g, f);
    close(g, f);
    for carry, at in carries { bindPut(g, f, carry.outgoing, g.s.vals[outgoing.start + at]); }
    if info.kind == blot_check_core::LoopKind.forever && !info.can_exit { return neverVal(), blot_direct_types::Error.none; }
    return unitVal(), blot_direct_types::Error.none;
}
// Records a store into an existing owner, which may predate this scope.
fn noteStore(g: Generator&, f: Fn&, value: Val) -> Error {
    if value.ty == blot_direct_types::never { return blot_direct_types::Error.none; }
    let holds, error = g.contentsHoldMemory(value.ty);
    if error != blot_direct_types::Error.none { return error; }
    if holds { f.memory_stores += 1; }
    return blot_direct_types::Error.none;
}
// Releases an iteration's allocations when its loop allows it and every
// carried owner predates the iteration.
fn releaseIteration(g: Generator&, f: Fn&, label: blot_direct_emit::Label) {
    lget(g, label.allow);
    for at in 0..(label.guards.len as i64) {
        lget(g, g.s.words[label.guards.start + at]);
        lget(g, label.release_owner);
        op(g, OP_i32_lt_u);
        op(g, OP_i32_and);
    }
    op(g, OP_if_);
    op(g, 0x40);
    f.depth += 1;
    releaseTo(g, label.release_owner, label.release_stack);
    close(g, f);
}
// Pushes on the scratch stack the owner-slot locals of a carried value of
// `ty` whose words start at `words` in the word pool, and returns whether
// releasing around it can be made safe: plain values and owners of plain
// elements qualify; closures and memory-holding sums do not.
recursive fn ownerSlots(g: Generator&, ty: Ty, words: u32) -> bool, Error {
    let holds, error = g.contentsHoldMemory(ty);
    if error != blot_direct_types::Error.none { return false, error; }
    if !holds { return true, blot_direct_types::Error.none; }
    // A boxed carry is copied into its reserved slot; owners inside it are
    // not checked word by word.
    let boxed, error = g.types.boxed(ty);
    if error != blot_direct_types::Error.none { return false, error; }
    if boxed { return false, blot_direct_types::Error.none; }
    let n = g.types.node(ty);
    match n.tag {
        array, list, grow, resize, view, ref, link, cursor => {
            let element_holds, error = g.contentsHoldMemory(n.a);
            if error != blot_direct_types::Error.none { return false, error; }
            if element_holds { return false, blot_direct_types::Error.none; }
            let slot = g.s.words[words];
            g.s.scratch.push(slot);
            return true, blot_direct_types::Error.none;
        },
        tuple => {
            var at: u32 = 0;
            for index in 0..(n.b as i64) {
                let item = g.types.tupleItems(ty)[index];
                let layout, error = g.types.layout(item);
                if error != blot_direct_types::Error.none { return false, error; }
                let width = layout.len as u32;
                let safe, error = ownerSlots(g, item, words + at);
                if error != blot_direct_types::Error.none { return false, error; }
                if !safe { return false, blot_direct_types::Error.none; }
                at += width;
            }
            return true, blot_direct_types::Error.none;
        },
        record => {
            var at: u32 = 0;
            for index in 0..(n.b as i64) {
                let field = g.types.recordField(ty, index).ty;
                let layout, error = g.types.layout(field);
                if error != blot_direct_types::Error.none { return false, error; }
                let width = layout.len as u32;
                let safe, error = ownerSlots(g, field, words + at);
                if error != blot_direct_types::Error.none { return false, error; }
                if !safe { return false, blot_direct_types::Error.none; }
                at += width;
            }
            return true, blot_direct_types::Error.none;
        },
        _ => { return false, blot_direct_types::Error.none; },
    }
}
recursive fn breakNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let children = m.breakValues(id);
    let values = g.reserveVals(children.len);
    for child, at in children {
        let value, error = expr(g, f, child);
        if error != blot_direct_types::Error.none { return value, error; }
        g.s.vals[values.start + at] = value;
    }
    var at = g.s.labels.len;
    while at != f.labels_base {
        at -= 1;
        let label = g.s.labels[at];
        if label.target != n.a || label.kind != blot_direct_emit::LabelKind.loop_ { continue; }
        if values.len != label.iteration.len { return neverVal(), g.fail(m, id, "break carries the wrong number of values"); }
        leaveHandles(g, f, label.depth);
        if n.op == blot_check_core::Op.continue_ {
            let assigned = assignCarries(g, f, values, label.iteration, label.slots, id);
            if assigned != blot_direct_types::Error.none { return neverVal(), assigned; }
            if label.has_release {
                releaseIteration(g, f, label);
                g.s.labels[at].used = true;
            }
            br(g, f, OP_br, label.top);
        } else {
            let assigned = assign(g, f, values, label.outgoing, id);
            if assigned != blot_direct_types::Error.none { return neverVal(), assigned; }
            br(g, f, OP_br, label.depth);
        }
        return neverVal(), blot_direct_types::Error.none;
    }
    return neverVal(), g.fail(m, id, "break outside its loop");
}

recursive fn patternBind(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let n = g.units[f.unit - 1].node(id);
    let value, error = expr(g, f, n.b);
    if error != blot_direct_types::Error.none { return value, error; }
    if n.c == 0 {
        let tested = test_(g, f, n.a, value, false, 0, id);
        if tested != blot_direct_types::Error.none { return neverVal(), tested; }
        return unitVal(), blot_direct_types::Error.none;
    }
    let ok = open(g, f, OP_block);
    let failed = open(g, f, OP_block);
    let tested = test_(g, f, n.a, value, true, failed, id);
    if tested != blot_direct_types::Error.none { return neverVal(), tested; }
    br(g, f, OP_br, ok);
    close(g, f);
    let otherwise, error = stmt(g, f, n.c);
    if error != blot_direct_types::Error.none { return otherwise, error; }
    op(g, OP_unreachable_);
    close(g, f);
    return unitVal(), blot_direct_types::Error.none;
}
