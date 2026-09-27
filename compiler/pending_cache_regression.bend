import Base
import ./model.bend as M
import ./types.bend as Types
import ./infer.bend as Infer
import ./constraints.bend as Constraints
import ./globals.bend as Globals
import ./monomorph.bend as Mono

def need(identity: Nat, argument: M.Ty) -> Infer.Coverage:
  Infer.OperationNeed{identity, M.TypeId{"cache", "operation"}, [argument], M.FunctionTy{M.UnitTy{}, M.UnitTy{}, M.EffectRow{Nil{}, M.ClosedRow{}}}, "cache probe"}

def definition(name: String, needs: List<&2, Infer.Coverage>) -> Infer.Definition:
  Infer.Definition{name, Infer.Inference{M.UnitTy{}, needs, Nil{}, Nil{}, Nil{}, Nil{}}}

def environment(definitions: List<&2, Infer.Definition>, substitutions: Types.Substitutions) -> Globals.Environment:
  Globals.Environment{Nil{}, definitions, Infer.State{substitutions, 1n, MTip{}}}

def specialization(definitions: List<&2, Infer.Definition>, substitutions: Types.Substitutions, choices: Map<&2, Mono.Choice>) -> Mono.Specialization:
  Mono.Specialization{M.Module{Nil{}, Nil{}, Nil{}, Nil{}}, environment(definitions, substitutions), choices, 0n, Nil{}}

# This finalization probe has no module roots. Its synthetic definition tests
# that already selected qualified evidence is still resolved after a late type
# substitution, independently of the reached-use row closing pass.
def empty_configuration() -> Mono.Configuration:
  Mono.Configuration{Nil{}, Nil{}, "", Nil{}, Nil{}, 1n, Nil{}, Nil{}, 1n, Nil{}}

def chosen() -> Map<&2, Mono.Choice>:
  Map.set(&2, Mono.Choice, Map.new(&2, Mono.Choice), "1", Mono.OperationChoice{M.TypeId{"cache", "operation"}, M.FunctionTy{M.UnitTy{}, M.UnitTy{}, M.EffectRow{Nil{}, M.ClosedRow{}}}})

def identities(needs: List<&2, Infer.Coverage>) -> List<&2, Nat>:
  match needs:
    case Nil{}:
      Nil{}
    case Infer.OperationNeed{identity, template, arguments, function_type, subject} <> tail:
      identity <> identities(tail)
    case Infer.AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, subject} <> tail:
      identity <> identities(tail)
    case other <> tail:
      identities(tail)

def ordered(ids: List<&2, Nat>) -> Bool:
  match ids:
    case 3n <> 4n <> 2n <> Nil{}:
      True{}
    case _:
      False{}

def only_second(ids: List<&2, Nat>) -> Bool:
  match ids:
    case 2n <> Nil{}:
      True{}
    case _:
      False{}

def resolved_u32(result: Result<&2, &2, M.Diagnostic, M.Ty>) -> Bool:
  match result:
    case Done{M.U32Ty{}}:
      True{}
    case _:
      False{}

def resolve_second(needs: List<&2, Infer.Coverage>, substitutions: Types.Substitutions) -> Bool:
  match needs:
    case Infer.OperationNeed{2n, template, M.VariableTy{0n} <> Nil{}, function_type, subject} <> Nil{}:
      resolved_u32(Types.resolve(substitutions, M.VariableTy{0n}))
    case _:
      False{}

def changed_substitutions(old: Infer.Definition) -> Bool:
  +old_definitions : List<&2, Infer.Definition> = [old]
  +prior : Mono.Specialization = specialization(old_definitions, Types.empty(), Map.new(&2, Mono.Choice))
  +cache : Mono.PendingCache = Mono.PendingCache{1n, Mono.specialization_pending(prior)}
  +updated_substitutions : Types.Substitutions = Types.from_list([Types.Substitution{0n, M.U32Ty{}}])
  +selected : Mono.Specialization = specialization(old_definitions, updated_substitutions, chosen())
  +next : List<&2, Infer.Coverage> = Mono.cached_needs(Mono.refresh_pending(selected, cache))
  Bool.and(only_second(identities(next)), resolve_second(next, updated_substitutions))

def qualified_slots_result(needs: List<&2, Infer.Coverage>) -> Bool:
  match needs:
    case Infer.QualifiedNeed{1n, M.EffectRepPredicate{M.EffectRow{Nil{}, M.ClosedRow{}}}, subject} <> Nil{}:
      True{}
    case _:
      False{}

def qualified_slots() -> Bool:
  +represented = {M.TypeRepPredicate{M.U32Ty{}} : M.Predicate}
  +other = {M.EffectRepPredicate{M.EffectRow{Nil{}, M.ClosedRow{}}} : M.Predicate}
  +answer = {Constraints.EvidenceAnswer{represented, Constraints.RepresentedType{M.U32Ty{}}} : Constraints.EvidenceAnswer}
  +choices = Map.set(&2, Mono.Choice, chosen(), "q1", Mono.QualifiedChoice{[represented], [answer]})
  +needs : List<&2, Infer.Coverage> = [Infer.OperationNeed{1n, M.TypeId{"cache", "operation"}, [M.U32Ty{}], M.UnitTy{}, "old site"}, Infer.QualifiedNeed{1n, represented, "first predicate"}, Infer.QualifiedNeed{1n, other, "second predicate"}]
  qualified_slots_result(Mono.unresolved(needs, choices))

def closed_qualified_answer(found: Maybe<&2, Mono.Choice>) -> Bool:
  match found:
    case Some{Mono.QualifiedChoice{solved, Constraints.EvidenceAnswer{predicate, Constraints.SelectedFunction{name, M.FunctionTy{M.U32Ty{}, M.FunctionTy{M.U32Ty{}, M.U32Ty{}, row}, outer}}} <> Nil{}}}:
      True{}
    case _:
      False{}

def finalized_qualified(result: Result<&2, &2, M.Diagnostic, Mono.Specialization>) -> Bool:
  match result:
    case Done{Mono.Specialization{module, environment, choices, next, certificates}}:
      closed_qualified_answer(Mono.qualified_choice(choices, 7n))
    case _:
      False{}

def late_evidence() -> Bool:
  +row = {M.EffectRow{Nil{}, M.ClosedRow{}} : M.EffectRow}
  +predicate = {M.AssociatedPredicate{"add", Nil{}, M.U32Ty{}, M.U32Ty{}, M.VariableTy{0n}, row} : M.Predicate}
  +signature = {M.FunctionTy{M.U32Ty{}, M.FunctionTy{M.U32Ty{}, M.VariableTy{0n}, row}, row} : M.Ty}
  +answer = {Constraints.EvidenceAnswer{predicate, Constraints.SelectedFunction{"@u32.add", signature}} : Constraints.EvidenceAnswer}
  +choices = Map.set(&2, Mono.Choice, Map.new(&2, Mono.Choice), "q7", Mono.QualifiedChoice{[predicate], [answer]})
  +definitions : List<&2, Infer.Definition> = [definition("caller", [Infer.QualifiedNeed{7n, predicate, "caller"}])]
  +closed = Types.from_list([Types.Substitution{0n, M.U32Ty{}}])
  finalized_qualified(Mono.finalize_specialization(specialization(definitions, closed, choices), empty_configuration()))

def check() -> Bool:
  +old : Infer.Definition = definition("old", [need(1n, M.UnitTy{}), need(2n, M.VariableTy{0n})])
  +new : Infer.Definition = definition("new", [need(3n, M.BoolTy{}), Infer.ValuePatternType{M.UnitTy{}, "ignored"}, need(4n, M.UnitTy{})])
  +initial : Mono.Specialization = specialization([old], Types.empty(), Map.new(&2, Mono.Choice))
  +cache : Mono.PendingCache = Mono.PendingCache{1n, Mono.specialization_pending(initial)}
  +expanded : Mono.Specialization = specialization([new, old], Types.empty(), chosen())
  +refreshed : List<&2, Infer.Coverage> = Mono.cached_needs(Mono.refresh_pending(expanded, cache))
  +shrunk : Mono.Specialization = specialization([old], Types.empty(), chosen())
  +invalid_count : List<&2, Infer.Coverage> = Mono.cached_needs(Mono.refresh_pending(shrunk, Mono.PendingCache{2n, refreshed}))
  Bool.and(ordered(identities(refreshed)), Bool.and(only_second(identities(invalid_count)), Bool.and(changed_substitutions(old), Bool.and(qualified_slots(), late_evidence()))))

def valid() -> Bool:
  check()

def finish(valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "pending constraint cache regression failed")

def main() -> IO(Unit):
  finish(valid())
