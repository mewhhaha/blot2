import src.evaluate;
import src.frontend;
fn test_required_static_core() {
    let source = "let offset: U32 -> U32 ! {} = fn x => return U32.wrapping_add(x,7)\nlet count: Unit -> U32 ! {} = fn () => do:\n  let answer = for i in 0..10 carry (n = 0) invariant [Eq(n,i)] do:\n    next (n+1)\n  return offset(answer)\n";
    with_core() { b =>
        var work = Work { .. }; var diagnostics: Diagnostic[>..] = [];
        let completed = frontend_complete(source, "static-core", b, work, diagnostics); if !completed { print(diagnostics); } assert(completed);
        var stats = StaticStats { .. }; let value, ok = static_evaluate(core_view(b), b.definitions[2].function, StaticValue { .. }, stats, diagnostics);
        if !ok { print(diagnostics); } assert(ok && value.count == 1 && value.words[0] == 17 && stats.steps > 10 && stats.max_depth == 2);
        var exhausted = StaticStats { steps: 99999, .. }; let unused, limit_ok = static_evaluate(core_view(b), b.definitions[2].function, StaticValue { .. }, exhausted, diagnostics); assert(!limit_ok && diagnostics[diagnostics.len - 1].code == 4021 && exhausted.steps == 100000);
        var output_limit = StaticStats { produced_bytes: 4194304, .. }; let before = b.static_objects.len;
        let object, published = static_publish(b, STATIC_VALUE, b.values[b.functions[1].param].type_id, 0, 1, 0, [static_scalar(42)], 1, output_limit, diagnostics);
        assert(!published && b.static_objects.len == before && diagnostics[diagnostics.len - 1].code == 4023);
    };
    print("STATIC required pure calls and finite loop, independent step/output limits passed");
}
fn test_required_static_f32() {
    assert(static_bits(static_nearest(-0.5)) == 0x80000000);
    assert(static_bits(static_nearest(0.5)) == 0);
    assert(static_nearest(1.5) == 2.0 && static_nearest(2.5) == 2.0 && static_nearest(-1.5) == -2.0);
    assert(static_bits(static_f32(0x7fa00001)) == 0x7fa00001);
    let source = "let calc: F32 -> F32 ! {} = fn x => return (x * 0.1) + 0.2\nlet nan: Unit -> F32 ! {} = fn () => return 0.0 / 0.0\n";
    with_core() { b =>
        var work = Work { .. }; var diagnostics: Diagnostic[>..] = [];
        assert(frontend_complete(source, "static-f32", b, work, diagnostics));
        var stats = StaticStats { .. }; let value, ok = static_evaluate(core_view(b), b.definitions[1].function, static_scalar(0x40400000), stats, diagnostics);
        if !ok { print(diagnostics); } assert(ok && value.words[0] == 0x3f000000);
        let nan, nan_ok = static_evaluate(core_view(b), b.definitions[2].function, StaticValue { .. }, stats, diagnostics);
        assert(nan_ok && nan.words[0] == 0x7fc00000);
    };
    print("STATIC F32 ties, signed zero, separate rounding and canonical NaN passed");
}

fn test_required_static_f32_integer_conversion() {
    with_core() { b =>
        var work = Work { .. }; var diags: Diagnostic[>..] = [];
        assert(frontend_complete("let convert: F32 -> Result[U32,Unit] ! {} = fn x => return U32.from_f32(x)\n", "static-convert", b, work, diags));
        let inputs: u32[7] = [0x80000000, 0x3ff33333, 0x4f7fffff, 0x4f800000, 0xbf800000, 0x7fc00000, 0x7f800000];
        let tags: u32[7] = [0, 0, 0, 1, 1, 1, 1];
        let payloads: u32[7] = [0, 1, 4294967040, 0, 0, 0, 0];
        for input, i in inputs {
            var stats = StaticStats { .. }; let value, ok = static_evaluate(core_view(b), b.definitions[1].function, static_scalar(input), stats, diags);
            assert(ok && value.count == 2 && value.words[0] == tags[i] && value.words[1] == payloads[i]);
        }
    };
    print("STATIC F32 fractional truncation, signed zero and conversion failures passed");
}

fn test_required_static_boundaries() {
    var source: u8[>..] = [];
    source.append("let f0: Unit -> U32 ! {} = fn () => return 7\n");
    for i in 1..129 { format(source, "let f", i, ": Unit -> U32 ! {} = fn () => return f", i - 1, "(())\n"); }
    with_core() { b =>
        var work = Work { .. }; var diags: Diagnostic[>..] = [];
        assert(frontend_complete(source, "static-depth", b, work, diags));
        var stats = StaticStats { .. }; let value, ok = static_evaluate_initializer(core_view(b), b.definitions[129].function, StaticValue { .. }, stats, diags);
        assert(ok && value.words[0] == 7 && stats.max_depth == 128);
        var too_deep = StaticStats { .. }; let unused, deep_ok = static_evaluate(core_view(b), b.definitions[129].function, StaticValue { .. }, too_deep, diags);
        assert(!deep_ok && diags[diags.len - 1].code == 4022 && too_deep.max_depth == 129);
        var exact = StaticStats { steps: 100000 - stats.steps, .. }; let last, last_ok = static_evaluate_initializer(core_view(b), b.definitions[129].function, StaticValue { .. }, exact, diags);
        assert(last_ok && exact.steps == 100000);
        var overflow = StaticStats { steps: 100001 - stats.steps, .. }; let none, overflow_ok = static_evaluate_initializer(core_view(b), b.definitions[129].function, StaticValue { .. }, overflow, diags);
        assert(!overflow_ok && overflow.steps == 100000 && diags[diags.len - 1].code == 4021);
        let unsigned = b.contracts[b.functions[1].contract].result;
        var bytes = StaticStats { produced_bytes: 4194300, .. }; let object, published = static_publish(b, STATIC_VALUE, unsigned, 0, 1, 0, [static_scalar(7)], 1, bytes, diags);
        assert(published && bytes.produced_bytes == 4194304);
        let before = b.static_objects.len; let rejected, extra_ok = static_publish(b, STATIC_VALUE, unsigned, 0, 1, 0, [static_scalar(8)], 1, bytes, diags);
        assert(!extra_ok && b.static_objects.len == before && diags[diags.len - 1].code == 4023);
    };
    print("STA exact128 source calls,100000 primitive steps and4MiB output boundaries passed");
}
