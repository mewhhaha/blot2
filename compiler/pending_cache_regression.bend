import Base
import ./model.bend as M
import ./types.bend as Types
import ./infer.bend as Infer
import ./globals.bend as Globals
import ./monomorph.bend as Mono

def need(identity: Nat, argument: M.Ty) -> Infer.Coverage:
  Infer.OperationNeed{identity, M.TypeId{"cache", "operation"}, [argument], M.FunctionTy{M.UnitTy{}, M.UnitTy{}, M.EffectRow{Nil{}, M.ClosedRow{}}}, "cache probe"}

def definition(name: String, needs: List<&2, Infer.Coverage>) -> Infer.Definition:
  Infer.Definition{name, Infer.Inference{M.UnitTy{}, needs, Nil{}, Nil{}}}

def environment(definitions: List<&2, Infer.Definition>, substitutions: Types.Substitutions) -> Globals.Environment:
  Globals.Environment{Nil{}, definitions, Infer.State{substitutions, 1n, MTip{}}}

def specialization(definitions: List<&2, Infer.Definition>, substitutions: Types.Substitutions, choices: Map<&2, Mono.Choice>) -> Mono.Specialization:
  Mono.Specialization{M.Module{Nil{}, Nil{}, Nil{}, Nil{}}, environment(definitions, substitutions), choices, 0n, Nil{}}

def chosen() -> Map<&2, Mono.Choice>:
  Map.set(&2, Mono.Choice, Map.new(&2, Mono.Choice), "1", Mono.OperationChoice{M.TypeId{"cache", "operation"}})

def identities(needs: List<&2, Infer.Coverage>) -> List<&2, Nat>:
  match needs:
    case Nil{}:
      Nil{}
    case Infer.OperationNeed{identity, template, arguments, function_type, subject} <> tail:
      identity <> identities(tail)
    case Infer.AssociatedNeed{identity, dispatch, member, templates, left, right, result, ambient, subject} <> tail:
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

def check() -> Bool:
  +old : Infer.Definition = definition("old", [need(1n, M.UnitTy{}), need(2n, M.VariableTy{0n})])
  +new : Infer.Definition = definition("new", [need(3n, M.BoolTy{}), Infer.ValuePatternType{M.UnitTy{}, "ignored"}, need(4n, M.UnitTy{})])
  +initial : Mono.Specialization = specialization([old], Types.empty(), Map.new(&2, Mono.Choice))
  +cache : Mono.PendingCache = Mono.PendingCache{1n, Mono.specialization_pending(initial)}
  +expanded : Mono.Specialization = specialization([new, old], Types.empty(), chosen())
  +refreshed : List<&2, Infer.Coverage> = Mono.cached_needs(Mono.refresh_pending(expanded, cache))
  +shrunk : Mono.Specialization = specialization([old], Types.empty(), chosen())
  +invalid_count : List<&2, Infer.Coverage> = Mono.cached_needs(Mono.refresh_pending(shrunk, Mono.PendingCache{2n, refreshed}))
  Bool.and(ordered(identities(refreshed)), Bool.and(only_second(identities(invalid_count)), changed_substitutions(old)))

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
