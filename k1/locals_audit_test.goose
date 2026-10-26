import locals_core;
import locals_check;
fn main() {
    var empty = locals_core::Program {};
    assert(!locals_check::verify("",empty));
    let source = "let f: U32 -> U32 = fn x => do:\n  return 1 + 2\n";
    var literal = locals_core::Program { source: source, name_start: 4, name_end: 5, param_start: 23, param_end: 24,
        values: [locals_core::Value { kind: 2, start: 41, end: 42, literal: 1 },
                 locals_core::Value { kind: 2, start: 45, end: 46, literal: 2 },
                 locals_core::Value { kind: 3, start: 41, end: 46, a: 1, b: 2 }], yes: 3 };
    assert(locals_check::verify(source,literal));
    literal.values[2].kind = 4; assert(!locals_check::verify(source,literal)); literal.values[2].kind = 3;
    literal.values[2].a = 2; assert(!locals_check::verify(source,literal)); literal.values[2].a = 1;
    literal.values[0].literal = 0; assert(!locals_check::verify(source,literal)); literal.values[0].literal = 1;
    literal.yes = 1; assert(!locals_check::verify(source,literal)); literal.yes = 3;
    assert(!locals_check::verify("different source",literal));
    let unproved_source = "let f: U32 -> U32 = fn x => do:\n  return x + 1\n";
    var unproved = locals_core::Program { source: unproved_source, name_start: 4, name_end: 5, param_start: 23, param_end: 24,
        values: [locals_core::Value { kind: 1, start: 41, end: 42 },
                 locals_core::Value { kind: 2, start: 45, end: 46, literal: 1 },
                 locals_core::Value { kind: 3, start: 41, end: 46, a: 1, b: 2 }], yes: 3 };
    assert(!locals_check::verify(unproved_source,unproved));
    print("private local source check smoke passed");
}
