// Reconstruct disjointness from one moved binding and literal half-open ranges.
namespace blot_check_task_regions;
import std;
import support.error;
struct Range { first: u32, end: u32 }
struct Plan { owner: blot_check_core::BindingRef, payload: blot_check_types::Id, ranges: Range[16] = [default<Range>(); 16], len: i64, limit: u32 = 0 }
fn partition(module: const blot_check_core::Module&, id: blot_check_core::Id) -> Plan, blot_error::Error {
    let node = module.node(id);
    if node.tag != blot_check_core::Tag.task || node.c != blot_check_task_types::opCode(blot_check_task_types::Op.split) || node.b != 3 { return default<Plan>(), blot_error::Error.invalid_artifact; }
    let operands = module.children(id);
    if module.node(operands[0]).tag != blot_check_core::Tag.reference { return default<Plan>(), blot_error::Error.invalid_artifact; }
    let owner = module.reference(operands[0]);
    if owner.unit != 0 && owner.unit != module.unit { return default<Plan>(), blot_error::Error.invalid_artifact; }
    let wrapper = module.types.node(module.typeOf(operands[0]));
    if wrapper.tag != blot_check_types::Tag.usage || wrapper.b != blot_parse_ast::usagekind_unique || wrapper.c != 0 || module.types.node(wrapper.a).tag != blot_check_types::Tag.array { return default<Plan>(), blot_error::Error.invalid_artifact; }
    let ranges = module.node(operands[1]);
    if ranges.tag != blot_check_core::Tag.product || ranges.b == 0 || ranges.b > 16 { return default<Plan>(), blot_error::Error.invalid_artifact; }
    var result = Plan { owner, wrapper.a, len: ranges.b };
    for range_id, index in module.children(operands[1]) {
        let range = module.node(range_id); if range.tag != blot_check_core::Tag.product || range.b != 2 { return default<Plan>(), blot_error::Error.invalid_artifact; }
        let endpoints = module.children(range_id); let first = module.node(endpoints[0]); let end = module.node(endpoints[1]);
        if first.tag != blot_check_core::Tag.constant || end.tag != blot_check_core::Tag.constant || first.ty != blot_check_types::u32_type || end.ty != blot_check_types::u32_type || first.a > end.a { return default<Plan>(), blot_error::Error.invalid_artifact; }
        result.ranges[index] = Range { first.a, end.a }; result.limit = max(result.limit, end.a);
        for prior in result.ranges[..index] { if prior.first != prior.end && first.a != end.a && prior.end > first.a && end.a > prior.first { return default<Plan>(), blot_error::Error.invalid_artifact; } }
    }
    if module.node(operands[2]).tag != blot_check_core::Tag.closure { return default<Plan>(), blot_error::Error.invalid_artifact; }
    let callback = module.closure(operands[2]); let parameters = module.types.node(callback.parameter.ty);
    if parameters.tag != blot_check_types::Tag.product || parameters.b != result.len { return default<Plan>(), blot_error::Error.invalid_artifact; }
    var remaining: i64 = 4096; var scope = blot_check_types::Node { blot_check_types::Tag.absent };
    for input, ordinal in module.types.list(blot_check_types::List { parameters.a, parameters.b }) {
        let view = blot_check_task_types::viewInfo(module.types, input); if !view.present { return default<Plan>(), blot_error::Error.invalid_artifact; }
        let same, error = blot_check_rank_equal::equalWithBudget(module.types, view.value.payload, result.payload, true, remaining);
        if error != blot_error::Error.none || !same { return default<Plan>(), blot_error::Error.invalid_artifact; }
        let version = module.types.node(view.value.version);
        if version.a != module.unit || version.b != owner.binding || version.c != ordinal { return default<Plan>(), blot_error::Error.invalid_artifact; }
        let region = module.types.node(view.value.scope);
        if ordinal == 0 { scope = region; } else if region.b != scope.b || region.c != scope.c { return default<Plan>(), blot_error::Error.invalid_artifact; }
    }
    return result, blot_error::Error.none;
}
