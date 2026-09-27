import Base
import ./model.bend as M
import ./groups.bend as Groups
import ./checked_core.bend as Core
import ./core_compare.bend as Compare
import ./frontier_alpha_compare.bend as Alpha
import ./check_scheduler.bend as Scheduler
import ./constraints.bend as C

def all(values: List<&2, Bool>) -> Bool:
  match values:
    case Nil{}:
      True{}
    case head <> tail:
      Bool.and(head, all(tail))

def function(label: Nat, target: Nat, source: Nat, annotation: M.Ty) -> M.Function:
  M.Function{"$self", False{}, "x", Some{M.UnitTy{}}, Some{M.UnitTy{}}, M.SourceExpr{source, Some{annotation}, M.BlockExpr{label, M.ReturnExpr{target, M.UnitExpr{}}}}}

def body_function(body: M.Expr) -> M.Function:
  M.Function{"$self", False{}, "x", Some{M.UnitTy{}}, None{}, body}

def module(value: M.Function, types: List<&2, M.DataType>) -> M.Module:
  M.Module{Nil{}, [value], types, Nil{}}

def nominal(name: String) -> M.DataType:
  M.DataType{M.TypeId{"frontier", name}, 0n, [M.Constructor{"Make", None{}, Nil{}}]}

def imported(parameters: Nat, +effect: M.TypeId) -> Groups.Interface:
  Groups.Interface{"dependency", Groups.FunctionInterface{}, M.FunctionTy{M.UnitTy{}, M.UnitTy{}, M.EffectRow{[effect, effect], M.ClosedRow{}}}, parameters, [M.OperationEffect{effect}], Nil{}}

def candidate(value: M.Function, imports: List<&2, Groups.Interface>, types: List<&2, M.DataType>) -> Scheduler.FrontierCandidate:
  Scheduler.FrontierCandidate{0n, "origin", value, types, imports}

def alpha_and_input_check() -> Bool:
  +base : M.Function = function(10n, 10n, 7n, M.UnitTy{})
  +shifted : M.Function = function(110n, 110n, 7n, M.UnitTy{})
  +effect : M.TypeId = M.TypeId{"frontier", "read"}
  +imports : List<&2, Groups.Interface> = [imported(1n, effect)]
  +types : List<&2, M.DataType> = [nominal("Box")]
  all([
    Alpha.same_alpha_module(module(base, types), module(shifted, types)),
    Bool.not(Alpha.same_alpha_module(module(base, types), module(function(110n, 111n, 7n, M.UnitTy{}), types))),
    Bool.not(Alpha.same_alpha_module(module(base, types), module(function(110n, 110n, 8n, M.UnitTy{}), types))),
    Bool.not(Alpha.same_alpha_module(module(base, types), module(function(110n, 110n, 7n, M.BoolTy{}), types))),
    Bool.not(Alpha.same_alpha_module(module(base, types), module(shifted, [nominal("Other")]))),
    Bool.not(Alpha.same_alpha_module(module(body_function(M.FunctionExpr{"selected_A"}), types), module(body_function(M.FunctionExpr{"selected_B"}), types))),
    Bool.not(Alpha.same_alpha_module(module(body_function(M.ConstantExpr{"capture_A"}), types), module(body_function(M.ConstantExpr{"capture_B"}), types))),
    Bool.not(Alpha.same_alpha_module(module(body_function(M.AssociatedExpr{1n, M.BinaryDispatch{}, "add", [M.TypeId{"impl", "A"}], M.UnitExpr{}, M.UnitExpr{}}), types), module(body_function(M.AssociatedExpr{1n, M.BinaryDispatch{}, "add", [M.TypeId{"impl", "B"}], M.UnitExpr{}, M.UnitExpr{}}), types))),
    Bool.not(Alpha.compare_work(0n, True{}, [Alpha.ModulePair{module(base, types), module(shifted, types)}], None{})),
    Scheduler.same_candidate(candidate(base, imports, types), candidate(shifted, imports, types)),
    Bool.not(Scheduler.same_candidate(candidate(base, imports, types), candidate(shifted, [imported(2n, effect)], types))),
    Bool.not(Scheduler.same_candidate(candidate(base, imports, types), candidate(shifted, [imported(1n, M.TypeId{"frontier", "write"})], types))),
    Bool.not(Scheduler.same_candidate(candidate(base, imports, types), candidate(shifted, imports, [nominal("Other")]))),
    Bool.not(Scheduler.same_candidate(candidate(base, imports, types), Scheduler.FrontierCandidate{1n, "other_origin", shifted, types, imports}))
  ])

# The native Nat ceiling is 2^48-1. Cross-summing two valid labels can exceed
# that ceiling even when the uniform offset itself is only one.
def large_label_check() -> Bool:
  +near_max : Nat = Nat.mul(65536n, 4294967295n)
  +base_label : Nat = Nat.sub(near_max, 1n)
  +lower_label : Nat = Nat.sub(near_max, 2n)
  +base : M.Function = function(base_label, base_label, 7n, M.UnitTy{})
  all([
    Alpha.same_alpha_module(module(base, Nil{}), module(function(near_max, near_max, 7n, M.UnitTy{}), Nil{})),
    Alpha.same_alpha_module(module(base, Nil{}), module(function(lower_label, lower_label, 7n, M.UnitTy{}), Nil{})),
    Bool.not(Alpha.same_alpha_module(module(base, Nil{}), module(function(near_max, base_label, 7n, M.UnitTy{}), Nil{})))
  ])

def mixed_function(name: String) -> M.Function:
  M.Function{name, False{}, "x", Some{M.UnitTy{}}, None{}, M.OperationExpr{M.TypeId{"frontier", "operation"}}}

def mixed_task(position: Nat, name: String, result: M.Ty) -> Scheduler.Task:
  Scheduler.Task{position, M.Module{Nil{}, [mixed_function(name)], Nil{}, [M.Operation{M.TypeId{"frontier", "operation"}, M.UnitTy{}, result}]}, Nil{}, 64n}

def outcome_type(outcome: Scheduler.Outcome) -> Maybe<&2, M.Ty>:
  match outcome:
    case Scheduler.Outcome{position, Done{Groups.CheckedGroup{M.CheckedModule{constants, M.CheckedFunction{function, M.Signature{name, parameter, result, variables, effects}, inferred} <> Nil{}, types, operations}, interfaces, uses}}}:
      Some{result}
    case _:
      None{}

def mixed_types(first: Maybe<&2, M.Ty>, second: Maybe<&2, M.Ty>) -> Bool:
  match first second:
    case Some{left} Some{right}:
      Bool.not(Compare.same_ty(left, right))
    case _ _:
      False{}

def mixed_catalog_check(outcomes: List<&2, Scheduler.Outcome>) -> Bool:
  match outcomes:
    case first <> second <> Nil{}:
      mixed_types(outcome_type(first), outcome_type(second))
    case _:
      False{}

def bad_function(name: String) -> M.Function:
  M.Function{name, False{}, "x", Some{M.UnitTy{}}, None{}, M.CallExpr{"absent", M.UnitExpr{}}}

def bad_task(position: Nat, name: String) -> Scheduler.Task:
  Scheduler.Task{position, M.Module{Nil{}, [bad_function(name)], Nil{}, Nil{}}, Nil{}, 64n}

def same_failure(left: Scheduler.Outcome, right: Scheduler.Outcome) -> Bool:
  match left right:
    case Scheduler.Outcome{left_position, Fail{M.Diagnostic{left_code, left_subject, left_message}}} Scheduler.Outcome{right_position, Fail{M.Diagnostic{right_code, right_subject, right_message}}}:
      Bool.and(Nat.is_eq(left_position, right_position), Bool.and(M.name_equal(left_code, right_code), Bool.and(M.name_equal(left_subject, right_subject), M.name_equal(left_message, right_message))))
    case _ _:
      False{}

def same_failures(left: List<&2, Scheduler.Outcome>, right: List<&2, Scheduler.Outcome>) -> Bool:
  match left right:
    case first <> second <> Nil{} other_first <> other_second <> Nil{}:
      Bool.and(same_failure(first, other_first), same_failure(second, other_second))
    case _ _:
      False{}

def failure_fallback_check() -> Bool:
  +tasks : List<&2, Scheduler.Task> = [bad_task(0n, "$mono[1].bad"), bad_task(1n, "$mono[2].bad")]
  same_failures(Scheduler.check_batch_same_catalog(tasks), Scheduler.check_batch_planned(tasks))

def evidence_function(name: String) -> M.Function:
  M.Function{name, False{}, "x", Some{M.UnitTy{}}, None{}, M.UnitExpr{}}

def evidence_task(position: Nat, name: String) -> Scheduler.Task:
  Scheduler.EvidenceTask{position, M.Module{Nil{}, [evidence_function(name)], Nil{}, Nil{}}, Nil{}, 64n}

def certificate_name(certificate: Core.Certificate) -> Maybe<&2, String>:
  match certificate:
    case Core.Certificate{M.Module{constants, M.Function{name, exported, argument, parameter, result, body} <> Nil{}, types, operations}, checked, imports}:
      Some{name}
    case _:
      None{}

def certificate_names(first: Maybe<&2, String>, second: Maybe<&2, String>) -> Bool:
  match first second:
    case Some{first_name} Some{second_name}:
      Bool.and(M.name_equal(first_name, "$mono[1].evidence"), M.name_equal(second_name, "$mono[2].evidence"))
    case _ _:
      False{}

def evidence_certificates(certificates: List<&2, Core.Certificate>) -> Bool:
  match certificates:
    case second <> first <> Nil{}:
      certificate_names(certificate_name(first), certificate_name(second))
    case _:
      False{}

def evidence_completed(completed: Scheduler.Completed) -> Bool:
  Scheduler.Completed{interfaces, functions, constants, published, failure, certificates, needs} = completed
  evidence_certificates(certificates)

def evidence_check(outcomes: List<&2, Scheduler.Outcome>) -> Bool:
  +empty : Scheduler.Completed = Scheduler.empty_completed()
  evidence_completed(Scheduler.publish_outcomes(outcomes, empty))

def retained_result(found: Maybe<&2, Scheduler.FrontierCandidate>) -> Bool:
  match found:
    case None{}:
      True{}
    case _:
      False{}

def retained_not_candidate() -> Bool:
  +retained : Groups.CheckedGroup = Groups.CheckedGroup{M.CheckedModule{Nil{}, Nil{}, Nil{}, Nil{}}, Nil{}, Nil{}}
  retained_result(Scheduler.task_candidate(Scheduler.RetainedTask{0n, retained}))

def prior_group(predicates: List<&2, M.Predicate>, uses: List<&2, C.UsePlan>) -> Groups.CheckedGroup:
  Groups.CheckedGroup{M.CheckedModule{Nil{}, [M.CheckedFunction{evidence_function("$mono[1].evidence"), M.Signature{"$mono[1].evidence", M.UnitTy{}, M.UnitTy{}, Nil{}, M.EffectRow{Nil{}, M.ClosedRow{}}}, Nil{}}], Nil{}, Nil{}},
    [Groups.Interface{"$mono[1].evidence", Groups.FunctionInterface{}, M.FunctionTy{M.UnitTy{}, M.UnitTy{}, M.EffectRow{Nil{}, M.ClosedRow{}}}, 0n, Nil{}, predicates}], uses}

def no_group(found: Maybe<&2, Groups.CheckedGroup>) -> Bool:
  match found:
    case None{}:
      True{}
    case _:
      False{}

def qualified_retained(found: Maybe<&2, Groups.CheckedGroup>) -> Bool:
  match found:
    case Some{Groups.CheckedGroup{checked, Groups.Interface{name, kind, ty, parameters, effects, M.TypeRepPredicate{M.UnitTy{}} <> Nil{}} <> Nil{}, C.UsePlan{9n, "qualified source", M.VariableTy{7n}, M.TypeRepPredicate{M.VariableTy{7n}} <> Nil{}} <> Nil{}}}:
      True{}
    case _:
      False{}

def qualified_reuse_check() -> Bool:
  +plan = {C.UsePlan{9n, "qualified source", M.VariableTy{7n}, [M.TypeRepPredicate{M.VariableTy{7n}}]} : C.UsePlan}
  +source = module(evidence_function("$mono[1].evidence"), Nil{})
  all([
    no_group(Scheduler.replay_for_task(prior_group([M.TypeRepPredicate{M.UnitTy{}}], Nil{}), evidence_task(1n, "$mono[2].evidence"))),
    no_group(Scheduler.replay_for_task(prior_group(Nil{}, [plan]), evidence_task(1n, "$mono[2].evidence"))),
    qualified_retained(Core.matching_certificate(Core.Certificate{source, prior_group([M.TypeRepPredicate{M.UnitTy{}}], [plan]), Nil{}}, source, Nil{}))
  ])

def check() -> Bool:
  all([
    qualified_reuse_check(),
    alpha_and_input_check(),
    large_label_check(),
    mixed_catalog_check(Scheduler.check_batch_planned([mixed_task(0n, "$mono[1].mixed", M.UnitTy{}), mixed_task(1n, "$mono[2].mixed", M.BoolTy{})])),
    failure_fallback_check(),
    evidence_check(Scheduler.check_batch_same_catalog([evidence_task(0n, "$mono[1].evidence"), evidence_task(1n, "$mono[2].evidence")])),
    retained_not_candidate()
  ])

def valid() -> Bool:
  check()

def finish(valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "frontier reuse regression failed")

def main() -> IO(Unit):
  finish(valid())
