import module_core;

// Build test records in declaration order with real, non-overlapping spans.
// This is not a parser and is not evidence of source completion.
fn append(source: u8[>..]&, functions: module_core::Function[>..]&, number: i64, callee: i64, depth: i64) {
    var f = module_core::Function { depth: depth, result_type: 1, terminator: 1 };
    f.declaration_start = source.len;
    source.append("let ");
    f.name_start = source.len; source.append(str("f", number)); f.name_end = source.len;
    source.append(": U32 -> U32 = ");
    f.function_start = source.len; source.append("fn ");
    f.parameter_start = source.len; source.append("x"); f.parameter_end = source.len;
    source.append(" => "); f.return_start = source.len; source.append("return ");
    f.expression_start = source.len;
    f.values[0] = module_core::Value { producer: 1, type_id: 1 };
    if callee >= 0 {
        f.callee_start = source.len; source.append(str("f", callee)); f.callee_end = source.len;
        source.append("("); f.left_start = source.len; source.append("x"); f.left_end = source.len;
        source.append(")");
        f.values[1] = module_core::Value { producer: 4, type_id: 1, callee_id: callee };
        f.value_count = 2; f.result_id = 1;
    } else if callee == -2 {
        f.left_start = source.len; source.append("x"); f.left_end = source.len;
        source.append(" "); f.operator_start = source.len; source.append("&"); f.operator_end = source.len;
        source.append(" "); f.right_start = source.len; source.append("x"); f.right_end = source.len;
        f.values[1] = module_core::Value { producer: 3, type_id: 1, op_id: 1 };
        f.value_count = 2; f.result_id = 1;
    } else if callee == -3 {
        f.left_start = source.len; source.append("4294967295"); f.left_end = source.len;
        f.values[1] = module_core::Value { producer: 2, type_id: 1, literal: 4294967295 };
        f.value_count = 2; f.result_id = 1;
    } else {
        f.left_start = source.len; source.append("x"); f.left_end = source.len;
        f.value_count = 1;
    }
    f.expression_end = source.len; f.declaration_end = source.len;
    source.append("\n"); functions.push(f);
}

fn chain(size: i64, cycle: bool) -> module_core::ModuleCore {
    var source: u8[>..] = [];
    var functions: module_core::Function[>..] = [];
    for i in size {
        let callee = if i + 1 < size { i + 1 } else if cycle { 0 } else { -1 };
        append(source, functions, i, callee, size - i);
    }
    return module_core::ModuleCore { source: source, functions: functions };
}
fn main() {
    var m = chain(2, false);
    assert(module_core::validate(m) == 0);
    let original = m.functions[0];
    m.functions[0].depth = 3; assert(module_core::validate(m) == 1); m.functions[0] = original;
    m.functions[0].frame = 1; assert(module_core::validate(m) == 1); m.functions[0] = original;
    m.functions[0].result_type = 2; assert(module_core::validate(m) == 1); m.functions[0] = original;
    m.functions[0].value_count = 5; assert(module_core::validate(m) == 1); m.functions[0] = original;
    m.functions[0].result_id = 7; assert(module_core::validate(m) == 1); m.functions[0] = original;
    m.functions[0].terminator = 2; assert(module_core::validate(m) == 1); m.functions[0] = original;
    m.functions[0].name_end = 999999; assert(module_core::validate(m) == 1); m.functions[0] = original;
    m.functions[0].left_end = m.functions[0].left_start; assert(module_core::validate(m) == 1); m.functions[0] = original;
    m.functions[0].values[1].callee_id = 999; assert(module_core::validate(m) == 1); m.functions[0] = original;
    m.functions[0].values[1].callee_id = 0; assert(module_core::validate(m) == 1); m.functions[0] = original;
    m.functions[0].values[1].op_id = 1; assert(module_core::validate(m) == 1); m.functions[0] = original;
    m.functions[0].values[1].left_id = 1; assert(module_core::validate(m) == 1); m.functions[0] = original;
    m.functions[0].values[3].literal = 1; assert(module_core::validate(m) == 1); m.functions[0] = original;
    m.functions[0].operator_start = 1; assert(module_core::validate(m) == 1); m.functions[0] = original;
    m.functions[1].name_start = original.name_start; assert(module_core::validate(m) == 1);
    var mutual = chain(2, true); assert(module_core::validate(mutual) == 8);
    var self_loop = chain(1, true); assert(module_core::validate(self_loop) == 8);
    var depth128 = chain(128, false); assert(module_core::validate(depth128) == 0);
    var depth129 = chain(129, false); assert(module_core::validate(depth129) == 9);
    var long_cycle = chain(129, true); assert(module_core::validate(long_cycle) == 8);
    var wide_source: u8[>..] = [];
    var wide_functions: module_core::Function[>..] = [];
    for i in 256 { append(wide_source, wide_functions, i, -1, 1); }
    var wide = module_core::ModuleCore { source: copy(wide_source), functions: copy(wide_functions) };
    assert(module_core::validate(wide) == 0);
    append(wide_source, wide_functions, 256, -1, 1);
    var wide_extra = module_core::ModuleCore { source: copy(wide_source), functions: copy(wide_functions) };
    assert(module_core::validate(wide_extra) == 1);
    var shape_source: u8[>..] = [];
    var shape_functions: module_core::Function[>..] = [];
    append(shape_source, shape_functions, 0, -2, 1);
    append(shape_source, shape_functions, 1, -3, 1);
    var shape = module_core::ModuleCore { source: copy(shape_source), functions: copy(shape_functions) };
    assert(module_core::validate(shape) == 0);
    shape.functions[0].values[1].op_id = 2; assert(module_core::validate(shape) == 1);
    shape.functions[0].values[1].op_id = 1;
    shape.functions[1].values[1].callee_id = 1; assert(module_core::validate(shape) == 1);
    var dup_source: u8[>..] = [];
    var dup_functions: module_core::Function[>..] = [];
    append(dup_source, dup_functions, 0, -1, 1);
    append(dup_source, dup_functions, 0, -1, 1);
    var duplicate = module_core::ModuleCore { source: copy(dup_source), functions: copy(dup_functions) };
    assert(module_core::validate(duplicate) == 1);
    var empty = module_core::ModuleCore {};
    assert(module_core::validate(empty) == 1);
    print("module Core structural validation: passed");
}
