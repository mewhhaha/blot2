// Evaluate closed scalar Core before writing the caller's Wasm body.
namespace blot_direct_function;
import .function;
import check.scalar_ops;
import check.typed_staging;
import support.native;

struct StageValue { bits: u32 = 0, ty: u32 = blot_check_types::unit, returning_to: u32 = 0 }
struct StageBinding { binding: u32, value: StageValue }
struct Stage {
    remaining: i64 = 65536,
    failure: Chars = "",
    bindings: StageBinding[>..] = [],
}

fn stopStage(s: Stage&, message: Chars) -> StageValue {
    if s.failure.len == 0 { s.failure = message; }
    return StageValue {};
}

fn stagedConstant(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    var bits: u32 = 0;
    {
        var s = Stage {};
        let value = evaluateStage(g, s, m, id, 0, 0);
        if s.failure.len != 0 { return neverVal(), g.fail(m, id, s.failure); }
        bits = value.bits;
    }
    return constant(g, f, id, bits);
}

fn stageBinding(s: const Stage&, frame: i64, binding: u32) -> StageValue, bool {
    var at = s.bindings.len;
    while at > frame {
        at--;
        if s.bindings[at].binding == binding { return s.bindings[at].value, true; }
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

recursive fn evaluateStageCall(g: const Generator&, s: Stage&, m: const Module&, id: u32, frame: i64, depth: i64) -> StageValue {
    let call = m.call(id);
    let target = g.resolve(m, call.target);
    if !g.hasUnit(target.unit) { return stopStage(s, "#run has no body for this call"); }
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
    let base = s.bindings.len;
    s.bindings.resize(base + call.arguments.len, StageBinding {0, StageValue {}});
    for argument, at in call.arguments {
        let value = evaluateStage(g, s, m, argument, frame, depth + 1);
        if s.failure.len != 0 || value.returning_to != 0 { s.bindings.resize(base); return value; }
        s.bindings[base + at].value = value;
    }
    s.bindings.resize(base + call.arguments.len);
    for parameter, at in owner.bodyParameters(body) { s.bindings[base + at].binding = parameter.binding; }
    let value = evaluateStage(g, s, owner, body.root, base, depth + 1);
    s.bindings.resize(base);
    return value;
}

recursive fn evaluateStage(g: const Generator&, s: Stage&, m: const Module&, id: u32, frame: i64, depth: i64) -> StageValue {
    if s.failure.len != 0 || id == 0 { return StageValue {}; }
    if s.remaining == 0 || depth >= 256 { return stopStage(s, "#run exceeded its evaluation budget"); }
    s.remaining--;
    let n = m.node(id);
    match n.tag {
        staging => {
            if n.c != blot_check_typed_staging::opCode(blot_check_typed_staging::Op.evaluate) { return stopStage(s, "typed code staging is not supported by the direct backend"); }
            return evaluateStage(g, s, m, n.a, s.bindings.len, depth + 1);
        },
        constant => {
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
            let body .= owner.body(target.binding);
            var root = binding.initializer;
            if body {
                if body.runtime || body.is_function { return stopStage(s, "#run requires a compile-time scalar value"); }
                root = body.root;
            }
            if root == 0 { return stopStage(s, "#run has no compile-time initializer"); }
            let base = s.bindings.len;
            let value = evaluateStage(g, s, owner, root, base, depth + 1);
            s.bindings.resize(base);
            return value;
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
            s.bindings.push(StageBinding {n.a, value});
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
                if found { s.bindings.push(StageBinding {merge.result, value}); }
            }
            return result;
        },
        panic => { return stopStage(s, "#run trapped"); },
        _ => { return stopStage(s, "#run requires a supported closed scalar expression"); },
    }
}
