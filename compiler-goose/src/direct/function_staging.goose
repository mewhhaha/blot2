// Evaluate closed Core values before writing the caller's Wasm body.
namespace blot_direct_function;
import .function;
import check.scalar_ops;
import backend.native_assets;
import backend.collection_ops;
import support.pooled_buffer;
reusable[] var part_runs:StagePart[>..]=[];
reusable[] var aggregate_runs:StageAggregate[>..]=[];
reusable[] var binding_runs:StageBinding[>..]=[];
import check.typed_staging;
import support.native;

struct StageValue { bits: u32 = 0, ty: u32 = blot_check_types::unit, returning_to: u32 = 0 }
struct StageBinding { binding: u32, value: StageValue }
// Scalar values keep their original bits. Aggregates refer to immutable member
// ranges so that bindings and calls can share values during evaluation.

struct StagePart { name: u32 = 0, value: StageValue = StageValue {} }
struct StageAggregate { kind: blot_check_core::Tag, start: u32, len: u32, tag: u32 }
let stage_aggregate: u32 = 0xffffffff;
struct Stage {
    parts: blot_support_pooled_buffer::Buffer<StagePart> = blot_support_pooled_buffer::Buffer<StagePart>{..},
    aggregates: blot_support_pooled_buffer::Buffer<StageAggregate> = blot_support_pooled_buffer::Buffer<StageAggregate>{..},
    bindings: blot_support_pooled_buffer::Buffer<StageBinding> = blot_support_pooled_buffer::Buffer<StageBinding>{..},
    remaining: i64 = 65536,
    failure: Chars = "",
}

fn stopStage(s: Stage&, message: Chars) -> StageValue {
    if s.failure.len == 0 { s.failure = message; }
    return StageValue {};
}

fn stagedConstant(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    if m.node(id).c == blot_check_typed_staging::opCode(blot_check_typed_staging::Op.read_input) { return neverVal(), g.fail(m, id, "@build.read needs a surrounding #run"); }
    var s = Stage {..};
    let value = evaluateStage(g, s, m, id, 0, 0);
    var result = neverVal();
    var error = blot_direct_types::Error.none;
    if s.failure.len != 0 { error = g.fail(m, id, s.failure); }
    else if value.ty != stage_aggregate { result, error = constant(g, f, id, value.bits); }
    else {
        let ty, lowered = typeOf(g, f, id);
        error = lowered;
        if error == blot_direct_types::Error.none {
            var remaining: i64 = 65536;
            result, error = emitStageValue(g, f, s, value, ty, id, remaining, 0);
        }
    }
    blot_support_pooled_buffer::deinit(s.parts, part_runs);
    blot_support_pooled_buffer::deinit(s.aggregates, aggregate_runs);
    blot_support_pooled_buffer::deinit(s.bindings, binding_runs);
    return result, error;
}

fn stageBinding(s: const Stage&, frame: i64, binding: u32) -> StageValue, bool {
    var at = s.bindings.items.len;
    while at > frame {
        at--;
        if s.bindings.items[at].binding == binding { return s.bindings.items[at].value, true; }
    }
    return StageValue {}, false;
}

fn stageBool(value: bool) -> StageValue {
    if value { return StageValue {1, blot_check_types::boolean, 0}; }
    return StageValue {0, blot_check_types::boolean, 0};
}

fn compareStage<T>(op: blot_check_core::Op, a: T, b: T) -> StageValue, bool {
    match op {
        equal => { return stageBool(a == b), true; }, not_equal => { return stageBool(a != b), true; },
        less => { return stageBool(a < b), true; }, less_equal => { return stageBool(a <= b), true; },
        greater => { return stageBool(a > b), true; }, greater_equal => { return stageBool(a >= b), true; },
        _ => { return StageValue {}, false; },
    }
}

fn stageScalar(s: Stage&, op: blot_check_core::Op, left: StageValue, right: StageValue) -> StageValue {
    if left.ty == stage_aggregate || right.ty == stage_aggregate { return stopStage(s, "#run requires scalar operands"); }
    let a = left.bits;
    let b = right.bits;
    if left.ty == blot_check_types::f32_type {
        let x = blot_native::f32_from_bits(a);
        let y = blot_native::f32_from_bits(b);
        let cmp, compared = compareStage(op, x, y);
        if compared { return cmp; }
        var result: f32 = 0.0;
        match op {
            add => { result = x + y; }, sub => { result = x - y; },
            mul => { result = x * y; }, div => { result = x / y; },
            neg => { return StageValue {a ^ 0x80000000, left.ty, 0}; },
            abs => { return StageValue {a & 0x7fffffff, left.ty, 0}; },
            ceil => { result = ceil(x); }, floor => { result = floor(x); },
            trunc => { result = trunc(x); }, sqrt => { result = sqrt(x); },
            bits => { return StageValue {a, blot_check_types::u32_type, 0}; },
            convert_f32_u32 => { return StageValue {blot_check_scalar_ops::truncate(x), blot_check_types::u32_type, 0}; },
            _ => { return stopStage(s, "#run does not support this floating-point operation"); },
        }
        return StageValue {blot_native::f32_bits(result), left.ty, 0};
    }
    let cmp, compared = compareStage(op, a, b);
    if compared { return cmp; }
    if op == blot_check_core::Op.from_bits { return StageValue {a, blot_check_types::f32_type, 0}; }
    if op == blot_check_core::Op.convert_u32_f32 { return StageValue {blot_native::f32_bits(a as f32), blot_check_types::f32_type, 0}; }
    if op == blot_check_core::Op.neg { let _, bits = blot_check_scalar_ops::foldU32(blot_check_core::Op.sub, 0, a); return StageValue {bits, left.ty, 0}; }
    if op == blot_check_core::Op.abs { return left; }
    if (op == blot_check_core::Op.div || op == blot_check_core::Op.rem) && b == 0 { return stopStage(s, "#run trapped on integer division by zero"); }
    let folded, bits = blot_check_scalar_ops::foldU32(op, a, b);
    if folded == blot_check_scalar_ops::Fold.value { return StageValue {bits, blot_check_types::u32_type, 0}; }
    return stopStage(s, "#run does not support this scalar operation");
}

recursive fn evaluateStageCall(g: Generator&, s: Stage&, m: const Module&, id: u32, frame: i64, depth: i64) -> StageValue {
    let call = m.call(id);
    let target = g.resolve(m, call.target);
    if !g.hasUnit(target.unit) { return stopStage(s, "#run has no body for this call"); }
    blot_backend_native_assets::stageDefinition(g.build_inputs, target.unit, target.binding);
    let owner .= g.units[target.unit - 1];
    let alias, primitive = primitiveAlias(owner, target.binding);
    if primitive {
        let info = owner.primitive(alias);
        if info.kind != blot_check_core::PrimitiveKind.scalar || info.arity != call.arguments.len || call.arguments.len < 1 || call.arguments.len > 2 { return stopStage(s, "#run requires a saturated scalar primitive"); }
        let a = evaluateStage(g, s, m, call.arguments[0], frame, depth + 1);
        if s.failure.len != 0 || a.returning_to != 0 { return a; }
        var b = StageValue {};
        if call.arguments.len == 2 { b = evaluateStage(g, s, m, call.arguments[1], frame, depth + 1); }
        if s.failure.len != 0 || b.returning_to != 0 { return b; }
        return stageScalar(s, info.op, a, b);
    }
    let body .= owner.body(target.binding);
    if !body { return stopStage(s, "#run has no body for this call"); }
    if !body.is_function || body.runtime || body.parameters.len != call.arguments.len { return stopStage(s, "#run requires a fully applied compile-time function"); }
    // Evaluate arguments in the caller before exposing *any* callee bindings.
    let base = s.bindings.items.len;
    for argument in call.arguments { blot_support_pooled_buffer::push(s.bindings, StageBinding {0, StageValue {}}, binding_runs); }
    for argument, at in call.arguments {
        let value = evaluateStage(g, s, m, argument, frame, depth + 1);
        if s.failure.len != 0 || value.returning_to != 0 { blot_support_pooled_buffer::resize(s.bindings, base); return value; }
        s.bindings.items[base + at].value = value;
    }
    blot_support_pooled_buffer::resize(s.bindings, base + call.arguments.len);
    for parameter, at in owner.bodyParameters(body) { s.bindings.items[base + at].binding = parameter.binding; }
    let value = evaluateStage(g, s, owner, body.root, base, depth + 1);
    blot_support_pooled_buffer::resize(s.bindings, base);
    return value;
}

recursive fn evaluateStage(g: Generator&, s: Stage&, m: const Module&, id: u32, frame: i64, depth: i64) -> StageValue {
    if s.failure.len != 0 || id == 0 { return StageValue {}; }
    if s.remaining == 0 || depth >= 256 { return stopStage(s, "#run exceeded its evaluation budget"); }
    s.remaining--;
    let n = m.node(id);
    match n.tag {
        staging => {
            if n.c == blot_check_typed_staging::opCode(blot_check_typed_staging::Op.read_input) {
                let key = evaluateStage(g, s, m, n.a, frame, depth + 1);
                if s.failure.len != 0 || key.returning_to != 0 { return key; }
                let bytes, found = blot_backend_native_assets::readBuildInput(g.build_inputs, key.bits);
                if !found { return stopStage(s, "#run cannot read the declared build input"); }
                // A captured input already owns immutable bytes. Keep a handle
                // so reading one header does not expand an entire file.
                let index = s.aggregates.items.len as u32;
                blot_support_pooled_buffer::push(s.aggregates, StageAggregate {blot_check_core::Tag.array, 0, bytes.len as u32, key.bits}, aggregate_runs);
                return StageValue {index, stage_aggregate, 0};
            }
            if n.c != blot_check_typed_staging::opCode(blot_check_typed_staging::Op.evaluate) { return stopStage(s, "typed code staging is not supported by the direct backend"); }
            return evaluateStage(g, s, m, n.a, s.bindings.items.len, depth + 1);
        },
        constant => {
            blot_direct_relocations::stagedRead(m.unit,id);
            let ty = m.types.node(n.ty).tag;
            if ty == blot_check_types::Tag.unit { return StageValue {}; }
            if ty == blot_check_types::Tag.unsigned32 { return StageValue {n.a, blot_check_types::u32_type, 0}; }
            if ty == blot_check_types::Tag.boolean { return StageValue {n.a, blot_check_types::boolean, 0}; }
            if ty == blot_check_types::Tag.floating32 { return StageValue {n.a, blot_check_types::f32_type, 0}; }
            return stopStage(s, "#run requires a scalar constant");
        },
        reference => {
            let target = g.resolve(m, m.reference(id));
            if !g.hasUnit(target.unit) { return stopStage(s, "#run has no definition for this value"); }
            let owner .= g.units[target.unit - 1];
            let binding = owner.binding(target.binding);
            if binding.kind == blot_reuse_principal_interface::Kind.local || binding.kind == blot_reuse_principal_interface::Kind.parameter {
                if target.unit == m.unit {
                    let value, found = stageBinding(s, frame, target.binding);
                    if found { return value; }
                }
                return stopStage(s, "#run depends on a runtime binding");
            }
            blot_backend_native_assets::stageDefinition(g.build_inputs, target.unit, target.binding);
            let body .= owner.body(target.binding);
            var root = binding.initializer;
            if body {
                if body.runtime || body.is_function { return stopStage(s, "#run requires a compile-time scalar value"); }
                root = body.root;
            }
            if root == 0 { return stopStage(s, "#run has no compile-time initializer"); }
            let base = s.bindings.items.len;
            let value = evaluateStage(g, s, owner, root, base, depth + 1);
            blot_support_pooled_buffer::resize(s.bindings, base);
            return value;
        },
        product, record, array, construct => {
            let children = m.children(id);
            var count = children.len;
            if n.tag == blot_check_core::Tag.construct && n.b != 0 { count = 1; }
            if count > s.remaining { return stopStage(s, "#run exceeded its evaluation budget"); }
            let start = s.parts.items.len as u32;
            for at in 0..count { blot_support_pooled_buffer::push(s.parts, StagePart {}, part_runs); }
            var tag: u32 = 0;
            if n.tag == blot_check_core::Tag.construct { tag = m.constructor(n.a).tag; }
            for at in 0..count {
                var child = n.b;
                if n.tag != blot_check_core::Tag.construct { child = children[at]; }
                let value = evaluateStage(g, s, m, child, frame, depth + 1);
                if s.failure.len != 0 || value.returning_to != 0 { return value; }
                var name: u32 = 0;
                if n.tag == blot_check_core::Tag.record {
                    let field = m.types.recordField(m.types.node(n.ty), m.recordDestinations(id)[at]);
                    let spelling = m.fieldSpelling(field.name);
                    if !spelling.present { return stopStage(s, "#run record field has no name"); }
                    name = g.types.fieldName(spelling.value);
                }
                s.parts.items[start + at] = StagePart {name, value};
            }
            let index = s.aggregates.items.len as u32;
            blot_support_pooled_buffer::push(s.aggregates, StageAggregate {n.tag, start, count as u32, tag}, aggregate_runs);
            return StageValue {index, stage_aggregate, 0};
        },
        project => {
            let value = evaluateStage(g, s, m, n.a, frame, depth + 1);
            if s.failure.len != 0 || value.returning_to != 0 { return value; }
            if value.ty != stage_aggregate { return stopStage(s, "#run requires an aggregate for projection"); }
            var a = s.aggregates.items[value.bits];
            if a.kind == blot_check_core::Tag.construct && a.len == 1 {
                let payload = s.parts.items[a.start].value;
                if payload.ty != stage_aggregate { return stopStage(s, "#run projected a scalar payload"); }
                a = s.aggregates.items[payload.bits];
            }
            let variants = m.projectionVariants(n.b);
            if a.kind == blot_check_core::Tag.product && variants.len == 1 && variants[0].field < a.len {
                return s.parts.items[a.start + variants[0].field].value;
            }
            let spelling = m.fieldSpelling(m.projection(n.b).field);
            if spelling.present && a.kind == blot_check_core::Tag.record {
                let name = g.types.fieldName(spelling.value);
                for at in 0..(a.len as i64) { if s.parts.items[a.start + at].name == name { return s.parts.items[a.start + at].value; } }
            }
            return stopStage(s, "#run field missing from the selected value");
        },
        array_op, storage => {
            var operation = blot_backend_collection_ops::Op.get;
            if n.tag == blot_check_core::Tag.array_op { operation = m.arrayOperation(id); }
            else {
                let storage, error = blot_check_storage_ops::opFromCode(n.c);
                if error != blot_error::Error.none || (storage != blot_check_storage_ops::Op.read && storage != blot_check_storage_ops::Op.length) { return stopStage(s, "#run requires a read-only collection operation"); }
                if storage == blot_check_storage_ops::Op.length { operation = blot_backend_collection_ops::Op.length; }
            }
            let children = m.children(id);
            let value = evaluateStage(g, s, m, children[0], frame, depth + 1);
            if s.failure.len != 0 || value.returning_to != 0 { return value; }
            if value.ty != stage_aggregate || s.aggregates.items[value.bits].kind != blot_check_core::Tag.array { return stopStage(s, "#run requires an array"); }
            let a = s.aggregates.items[value.bits];
            if operation == blot_backend_collection_ops::Op.length { return StageValue {a.len, blot_check_types::u32_type, 0}; }
            if operation != blot_backend_collection_ops::Op.get { return stopStage(s, "#run does not support this collection operation"); }
            let index = evaluateStage(g, s, m, children[1], frame, depth + 1);
            if s.failure.len != 0 || index.returning_to != 0 { return index; }
            if index.bits >= a.len { return stopStage(s, "#run array index out of bounds"); }
            if a.tag != 0 {
                let bytes, found = blot_backend_native_assets::readBuildInput(g.build_inputs, a.tag);
                if !found { return stopStage(s, "#run input snapshot missing"); }
                return StageValue {bytes[index.bits] as u32, blot_check_types::u32_type, 0};
            }
            return s.parts.items[a.start + index.bits].value;
        },
        scalar, logical => {
            let a = evaluateStage(g, s, m, n.a, frame, depth + 1);
            if s.failure.len != 0 || a.returning_to != 0 { return a; }
            if n.tag == blot_check_core::Tag.logical {
                if (n.op == blot_check_core::Op.and_ && a.bits == 0) || (n.op == blot_check_core::Op.or_ && a.bits != 0) { return a; }
                return evaluateStage(g, s, m, n.b, frame, depth + 1);
            }
            let b = evaluateStage(g, s, m, n.b, frame, depth + 1);
            if s.failure.len != 0 || b.returning_to != 0 { return b; }
            return stageScalar(s, n.op, a, b);
        },
        call => { return evaluateStageCall(g, s, m, id, frame, depth); },
        bind => {
            let value = evaluateStage(g, s, m, n.b, frame, depth + 1);
            if s.failure.len != 0 || value.returning_to != 0 { return value; }
            blot_support_pooled_buffer::push(s.bindings, StageBinding {n.a, value}, binding_runs);
            return StageValue {};
        },
        block_, suite => {
            for child in m.children(id) {
                var value = evaluateStage(g, s, m, child, frame, depth + 1);
                if s.failure.len != 0 || value.returning_to != 0 {
                    if n.tag == blot_check_core::Tag.block_ && value.returning_to == id { value.returning_to = 0; }
                    return value;
                }
            }
            return StageValue {};
        },
        return_ => {
            var value = evaluateStage(g, s, m, n.a, frame, depth + 1);
            if value.returning_to == 0 { value.returning_to = n.b; }
            return value;
        },
        if_value, if_stmt => {
            let condition = evaluateStage(g, s, m, n.a, frame, depth + 1);
            if s.failure.len != 0 || condition.returning_to != 0 { return condition; }
            var branch = n.c;
            if condition.bits != 0 { branch = n.b; }
            let result = evaluateStage(g, s, m, branch, frame, depth + 1);
            if s.failure.len != 0 || result.returning_to != 0 { return result; }
            for merge in m.branchMerges(id) {
                var from = merge.else_binding;
                if condition.bits != 0 { from = merge.then_binding; }
                let value, found = stageBinding(s, frame, from);
                if found { blot_support_pooled_buffer::push(s.bindings, StageBinding {merge.result, value}, binding_runs); }
            }
            return result;
        },
        panic => { return stopStage(s, "#run trapped"); },
        _ => { return stopStage(s, "#run requires a supported closed expression"); },
    }
}

// Reconstruct an ordinary Blot value using the layout selected by the caller.
// Evaluation can share subtrees. Bound expansion independently when embedding.
recursive fn emitStageValue(g: Generator&, f: Fn&, s: const Stage&, v: StageValue, ty: Ty, id: u32, remaining: i64&, depth: i64) -> Val, Error {
    let m .= g.units[f.unit - 1];
    if remaining == 0 || depth >= 256 { return neverVal(), g.fail(m, id, "#run result exceeded its materialization budget"); }
    remaining--;
    if v.ty != stage_aggregate {
        match tagOf(g, ty) {
            unit => { return unitVal(), blot_direct_types::Error.none; },
            f32_ => { f32Const(g, v.bits); },
            u32_, boolean => { i32Const(g, v.bits); },
            _ => { return neverVal(), g.fail(m, id, "#run scalar result shape mismatch"); },
        }
        return pop(g, f, ty, id);
    }
    let a = s.aggregates.items[v.bits];
    let shape = g.types.node(ty);
    if a.kind == blot_check_core::Tag.construct {
        let cases, error = g.types.variants(ty);
        if error != blot_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
        for at in 0..(cases.len as i64) {
            if g.types.variant_tags[cases.tags + at] != a.tag { continue; }
            var payload = unitVal();
            if a.len != 0 {
                let part_ty = g.types.variant_payloads[cases.payloads + at];
                let part, error = emitStageValue(g, f, s, s.parts.items[a.start].value, part_ty, id, remaining, depth + 1);
                if error != blot_direct_types::Error.none { return part, error; }
                payload = part;
            }
            return wrapVariant(g, f, ty, a.tag, payload, id);
        }
        return neverVal(), g.fail(m, id, "#run constructor result shape mismatch");
    }
    if a.len > remaining { return neverVal(), g.fail(m, id, "#run result exceeded its materialization budget"); }
    if a.kind == blot_check_core::Tag.array && a.tag != 0 {
        let bytes, found = blot_backend_native_assets::readBuildInput(g.build_inputs, a.tag);
        if !found { return neverVal(), g.fail(m, id, "#run input snapshot missing"); }
        let values = g.reserveVals(bytes.len);
        remaining -= bytes.len;
        for byte, at in bytes {
            let local = constLocal(g, f, byte as u32);
            let item = valOf1(g, blot_direct_types::u32_, local);
            g.s.vals[values.start + at] = item;
        }
        return arrayFromValues(g, f, ty, values, id);
    }
    let values = g.reserveVals(a.len);
    for at in 0..(a.len as i64) {
        let part = s.parts.items[a.start + at];
        var position = at;
        var child_ty = shape.a;
        if shape.tag == blot_direct_types::Tag.tuple {
            child_ty = g.types.tupleItems(ty)[at];
        } else if shape.tag == blot_direct_types::Tag.record {
            if a.kind != blot_check_core::Tag.record { return neverVal(), g.fail(m, id, "#run requires named record fields"); }
            position = g.types.findField(ty, part.name);
            if position < 0 { return neverVal(), g.fail(m, id, "#run record result shape mismatch"); }
            child_ty = g.types.recordField(ty, position).ty;
        } else if a.kind != blot_check_core::Tag.array {
            return neverVal(), g.fail(m, id, "#run result shape mismatch");
        }
        let item, error = emitStageValue(g, f, s, part.value, child_ty, id, remaining, depth + 1);
        if error != blot_direct_types::Error.none { return item, error; }
        g.s.vals[values.start + position] = item;
    }
    if a.kind == blot_check_core::Tag.array { return arrayFromValues(g, f, ty, values, id); }
    let boxed, error = isBoxed(g, f, ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if boxed {
        let base, error = newBlock(g, f, ty, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        var offset: u32 = 0;
        for at in 0..(values.len as i64) {
            let item = g.s.vals[values.start + at];
            let written = writeFlat(g, f, base, offset, item, id);
            if written != blot_direct_types::Error.none { return neverVal(), written; }
            let size, error = flatBytes(g, f, item.ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            offset += size;
        }
        return valOf1(g, ty, base), blot_direct_types::Error.none;
    }
    let start = g.s.words.len as u32;
    for at in 0..(values.len as i64) {
        let item = g.s.vals[values.start + at];
        for word in 0..(item.len as i64) { let local = g.s.words[item.start + word]; g.s.words.push(local); }
    }
    return Val {ty, start, (g.s.words.len as u32) - start}, blot_direct_types::Error.none;
}
