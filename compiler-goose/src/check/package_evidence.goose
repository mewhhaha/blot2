// Canonical binders and lexical-depth references own their exact scope.
namespace blot_check_package_evidence;
import eval.type_evidence;
import support.error;

fn validate(source: blot_eval_type_evidence::View) -> blot_error::Error {
    if source.nodes.len > 4096 { return blot_error::Error.invalid_artifact; }
    var remaining: i64 = 65536;
    let tables = source.validateGoalTablesWithBudget(remaining);
    if tables != blot_error::Error.none { return blot_error::Error.invalid_artifact; }
    var seen: bool[4096] = [false; 4096];
    for node, id in source.nodes {
        if node.tag != blot_eval_type_evidence::Tag.forall && node.tag != blot_eval_type_evidence::Tag.existential { continue; }
        if node.a == 0 || node.a >= id || node.b == 0 || node.b > 128 || node.c > source.extra.len || node.b > source.extra.len - node.c {
            return blot_error::Error.invalid_artifact;
        }
        if node.tag == blot_eval_type_evidence::Tag.existential {
            for binder in source.children(id as u32) {
                if source.node(binder).b != 0 { return blot_error::Error.invalid_artifact; }
            }
        }
        let opened = source.openQuantifierValidated(id as u32, remaining, seen);
        if opened != blot_error::Error.none { return blot_error::Error.invalid_artifact; }
    }
    for node, id in source.nodes {
        if (node.tag == blot_eval_type_evidence::Tag.bound || node.tag == blot_eval_type_evidence::Tag.projection) && !seen[id] {
            return blot_error::Error.invalid_artifact;
        }
    }
    return blot_error::Error.none;
}
