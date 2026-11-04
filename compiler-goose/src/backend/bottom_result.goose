namespace blot_backend_bottom_result;
import check.core;
import check.types;
import check.task_types;
import check.task_core;
import support.error;

fn proves(units: const blot_check_core::Module[:], owner: u32, id: blot_check_core::Id) -> bool {
    var budget: i64 = 1024; return visit(units, owner, id, 0, budget);
}
recursive fn visit(units: const blot_check_core::Module[:], owner: u32, id: blot_check_core::Id, depth: i64, budget: i64&) -> bool {
    if id == 0 || owner == 0 || owner > units.len || depth >= 32 || budget == 0 { return false; }
    budget--; let source = units[owner - 1]; let node = source.node(id);
    if node.tag == blot_check_core::Tag.return_ { return visit(units, owner, node.a, depth + 1, budget); }
    if node.tag == blot_check_core::Tag.break_ || node.tag == blot_check_core::Tag.request_loop || node.tag == blot_check_core::Tag.loop_ || node.tag == blot_check_core::Tag.if_stmt || node.tag == blot_check_core::Tag.match_ { return false; }
    if node.tag == blot_check_core::Tag.block_ || node.tag == blot_check_core::Tag.suite {
        for statement in source.children(id) {
            let child = source.node(statement);
            if child.tag == blot_check_core::Tag.return_ { if child.b != id { return false; } return visit(units, owner, child.a, depth + 1, budget); }
            if child.tag == blot_check_core::Tag.break_ || child.tag == blot_check_core::Tag.loop_ || child.tag == blot_check_core::Tag.if_stmt || child.tag == blot_check_core::Tag.match_ || child.tag == blot_check_core::Tag.request_loop { return false; }
            if visit(units, owner, statement, depth + 1, budget) { return true; }
        }
        return false;
    }
    if node.tag == blot_check_core::Tag.bind || node.tag == blot_check_core::Tag.pattern_bind { return visit(units, owner, node.b, depth + 1, budget); }
    if node.tag == blot_check_core::Tag.if_value { return visit(units, owner, node.b, depth + 1, budget) && visit(units, owner, node.c, depth + 1, budget); }
    if node.tag == blot_check_core::Tag.task {
        let operation, error = blot_check_task_types::opFromCode(node.c); if error != blot_error::Error.none { return false; }
        let operands = source.children(id);
        if operation == blot_check_task_types::Op.scope {
            if source.node(operands[0]).tag != blot_check_core::Tag.closure { return false; }
            return visit(units, owner, source.closure(operands[0]).body, depth + 1, budget);
        }
        if operation != blot_check_task_types::Op.join { return false; }
        var handle = operands[0];
        for index in 0..32 {
            if budget == 0 { return false; } budget--;
            let value = source.node(handle);
            if value.tag == blot_check_core::Tag.reference {
                let reference = source.reference(handle); if reference.unit != 0 && reference.unit != owner { return false; }
                let binding = source.binding(reference.binding); if binding.kind != blot_check_core::BindingKind.local || binding.initializer == 0 { return false; }
                handle = binding.initializer; continue;
            }
            if value.tag != blot_check_core::Tag.task || value.c != blot_check_task_types::opCode(blot_check_task_types::Op.spawn) { return false; }
            let thunk, error = blot_check_task_core::callable(source, source.children(handle)[1]); if error != blot_error::Error.none { return false; }
            return visit(units, owner, source.closure(thunk).body, depth + 1, budget);
        }
        return false;
    }
    if node.tag == blot_check_core::Tag.call {
        var target = source.call(id).target; if target.unit == 0 { target.unit = owner; }
        if target.unit > units.len { return false; }
        let producer = units[target.unit - 1]; let body .= producer.body(target.binding);
        if body == null || !body.is_function || body.parameters.len != source.call(id).arguments.len { return false; }
        return visit(units, target.unit, body.root, depth + 1, budget);
    }
    return source.types.node(source.typeOf(id)).tag == blot_check_types::Tag.never;
}
