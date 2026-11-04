// Ordinary schemes own assumptions; all endpoint roots are traversed.
namespace blot_check_scheme_predicates;
import support.error;
fn scope(context: blot_check_package_contracts::Context&, goals: const blot_check_types::Obligation[:]) -> blot_error::Error {
    for goal in goals {
        if context.remaining == 0 { return blot_error::Error.invalid_artifact; }
        context.remaining -= 1;
        for endpoint in [goal.ty, goal.other, goal.result, goal.signature] {
            if endpoint == 0 { continue; }
            let error = context.visit(endpoint);
            if error != blot_error::Error.none { return error; }
        }
        if goal.identity.unit == 0 && goal.identity.decl != 0 && goal.kind != blot_check_types::ObligationKind.contract {
            let error = context.visit(goal.identity.decl);
            if error != blot_error::Error.none { return error; }
        }
    }
    return blot_error::Error.none;
}
