import os;
import bounds_core;
import bounds_parse;
import bounds_validate;
import bounds_wasm;
fn copy_program(p: bounds_core::Program&) -> bounds_core::Program {
    return bounds_core::Program { source: copy(p.source), context: p.context, evidence: p.evidence,
        branch: p.branch, guard_index: p.guard_index, guard_view: p.guard_view, guard_length: p.guard_length,
        read_view: p.read_view, read_index: p.read_index, fallback_span: p.fallback_span, fallback: p.fallback };
}
fn main() {
    let context = bounds_core::Context { owner: 1, view: 2, view_version: 3, index: 4, index_version: 5, length: 6, domain: 7 };
    let source = "if i < v.length:\n  return v[i]\nelse:\n  return 3735928559\n";
    var p, status = bounds_parse::parse(source,context);
    assert(status == 0 && bounds_validate::verify(p,source,context));
    let values: u32[4] = [42, 0xffffffff, 0, 123456789];
    let bytes = bounds_wasm::emit(p,source,context,values);
    assert(bytes.len > 0 && write_file("bounds-fixture.wasm",bytes));
    let empty: u32[0] = [];
    let zero = bounds_wasm::emit(p,source,context,empty);
    assert(zero.len > 0 && write_file("bounds-empty.wasm",zero));
    var maximum: u32[256] = [0;256];
    for i in 256 { maximum[i] = (i as u32 * 65537) ^ 0xa5a5a5a5; }
    let max_bytes = bounds_wasm::emit(p,source,context,maximum);
    assert(max_bytes.len > 0 && write_file("bounds-maximum.wasm",max_bytes));
    for text in [
        "if i <= v.length:\n  return v[i]\nelse:\n  return 0\n",
        "if i < v.capacity:\n  return v[i]\nelse:\n  return 0\n",
        "if i < v.length:\n  return v[j]\nelse:\n  return 0\n",
        "if i < v.length:\n  return w[i]\nelse:\n  return 0\n",
        "if i < w.length:\n  return v[i]\nelse:\n  return 0\n",
        "if i < v.length:\n  return v[i+1]\nelse:\n  return 0\n",
        "if i < v.length:\n  return 0\nelse:\n  return v[i]\n",
        "if i < v.length:\n  return v[i]\n",
        "if i < v.length:\n  return v[i]\nelse:\n  return 4294967296\n",
        "if i < v.length:\n  return v[i]\nelse:\n  return -1\n",
        "if i < v.length:\n  return v[i]\nelse:\n  return 0\nreturn 1\n"
    ] {
        var invalid, error = bounds_parse::parse(text,context); assert(error != 0);
        assert(!bounds_validate::verify(invalid,text,context));
    }
    // Forgery of any proof identity, scope location, token span or fallback
    // rejects before Wasm emission. This assumes trusted expected source and
    // context; the caller cannot authenticate their own raw numeric IDs.
    for field in 20 {
        var f = copy_program(p);
        if field == 0 { f.evidence.rule += 1; }
        else if field == 1 { f.evidence.owner += 1; }
        else if field == 2 { f.evidence.view += 1; }
        else if field == 3 { f.evidence.view_version += 1; }
        else if field == 4 { f.evidence.index += 1; }
        else if field == 5 { f.evidence.index_version += 1; }
        else if field == 6 { f.evidence.length += 1; }
        else if field == 7 { f.evidence.domain += 1; }
        else if field == 8 { f.evidence.guard_start += 1; }
        else if field == 9 { f.evidence.true_read_start += 1; }
        else if field == 10 { f.branch.start += 1; }
        else if field == 11 { f.guard_index.start += 1; }
        else if field == 12 { f.guard_view.start += 1; }
        else if field == 13 { f.guard_length.start += 1; }
        else if field == 14 { f.read_view.start += 1; }
        else if field == 15 { f.read_index.start += 1; }
        else if field == 16 { f.fallback_span.start += 1; }
        else if field == 17 { f.fallback += 1; }
        else if field == 18 { f.context.view_version += 1; }
        else { f.context.index_version += 1; }
        assert(!bounds_validate::verify(f,source,context));
        assert(bounds_wasm::emit(f,source,context,values).len == 0);
    }
    var different = context; different.view_version += 1;
    assert(!bounds_validate::verify(p,source,different));
    different = context; different.index_version += 1;
    assert(!bounds_validate::verify(p,source,different));
    different = context; different.domain += 1;
    assert(!bounds_validate::verify(p,source,different));
    different = context; different.length += 1;
    assert(!bounds_validate::verify(p,source,different));
    for i in source.len {
        var altered = copy_program(p); altered.source[i] = '?';
        assert(!bounds_validate::verify(altered,source,context));
    }
    let bad_context = bounds_core::Context {};
    let _, rejected = bounds_parse::parse(source,bad_context); assert(rejected == 1);
    var large: u32[257] = [0;257]; assert(bounds_wasm::emit(p,source,context,large).len == 0);
    print("private guarded-view source/evidence laws passed");
}
