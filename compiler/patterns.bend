import Base
import ./model.bend as M
import ./types.bend as T
import ./type_data.bend as D
import ./infer.bend as I

def wildcard(patterns: List<&2, M.Pattern>) -> Bool:
  match patterns:
    case Nil{}:
      False{}
    case M.WildcardPattern{} <> tail:
      True{}
    case M.BindingPattern{name} <> tail:
      True{}
    case head <> tail:
      wildcard(tail)

def bool_case(patterns: List<&2, M.Pattern>, +value: Bool) -> Bool:
  match patterns:
    case Nil{}:
      False{}
    case M.BoolPattern{found} <> tail:
      Bool.or(Bool.not(Bool.xor(found, value)), bool_case(tail, value))
    case head <> tail:
      bool_case(tail, value)

def unit_case(patterns: List<&2, M.Pattern>) -> Bool:
  match patterns:
    case Nil{}:
      False{}
    case M.UnitPattern{} <> tail:
      True{}
    case head <> tail:
      unit_case(tail)

def constructor_payloads(patterns: List<&2, M.Pattern>, +name: String) -> List<&2, M.Pattern>:
  match patterns:
    case Nil{}:
      Nil{}
    case M.ConstructorPattern{found, None{}} <> tail:
      +rest = constructor_payloads(tail, name)
      Bool.pick(List<&2, M.Pattern>, M.name_equal(found, name), M.UnitPattern{} <> rest, rest)
    case M.ConstructorPattern{found, Some{payload}} <> tail:
      +rest = constructor_payloads(tail, name)
      Bool.pick(List<&2, M.Pattern>, M.name_equal(found, name), payload <> rest, rest)
    case head <> tail:
      constructor_payloads(tail, name)

type Work is Data:
  Cover{inferred_type: M.Ty, patterns: List<&2, M.Pattern>}
  Check{complete: Bool, inferred_type: M.Ty, patterns: List<&2, M.Pattern>}
  DataCases{definition: Maybe<&2, M.DataType>, arguments: List<&2, M.Ty>, patterns: List<&2, M.Pattern>}
  Constructors{constructors: List<&2, M.Constructor>, arguments: List<&2, M.Ty>, patterns: List<&2, M.Pattern>}

def coverage(+fuel: Nat, work: Work, +types: List<&2, M.DataType>) -> Result<&2, &2, M.Diagnostic, Bool>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"pattern_complexity", "inference", "pattern coverage exceeds compiler traversal limit"}}
    case 1n+rest Cover{ty, +patterns}:
      coverage(rest, Check{wildcard(patterns), ty, patterns}, types)
    case 1n+rest Check{True{}, ty, patterns}:
      Done{True{}}
    case 1n+rest Check{False{}, M.NeverTy{}, patterns}:
      Done{True{}}
    case 1n+rest Check{False{}, ty, Nil{}}:
      Done{False{}}
    case 1n+rest Check{False{}, M.BoolTy{}, +patterns}:
      Done{Bool.and(bool_case(patterns, True{}), bool_case(patterns, False{}))}
    case 1n+rest Check{False{}, M.UnitTy{}, patterns}:
      Done{unit_case(patterns)}
    case 1n+rest Check{False{}, M.AppliedTy{identity, arguments}, patterns}:
      coverage(rest, DataCases{D.lookup(types, identity), arguments, patterns}, types)
    case 1n+rest Check{False{}, other, patterns}:
      Done{False{}}
    case 1n+rest DataCases{None{}, arguments, patterns}:
      Fail{M.Diagnostic{"internal_error", "inference", "coverage references an unknown data type"}}
    case 1n+rest DataCases{Some{M.DataType{identity, count, constructors}}, arguments, patterns}:
      coverage(rest, Constructors{constructors, arguments, patterns}, types)
    case 1n+rest Constructors{Nil{}, arguments, patterns}:
      Done{True{}}
    case 1n+rest Constructors{M.Constructor{name, None{}} <> tail, +arguments, +patterns}:
      do Result<&2, &2, M.Diagnostic, Bool>:
        following : Bool <- coverage(rest, Constructors{tail, arguments, patterns}, types)
        return Bool.and(unit_case(constructor_payloads(patterns, name)), following)
    case 1n+rest Constructors{M.Constructor{name, Some{payload}} <> tail, +arguments, +patterns}:
      do Result<&2, &2, M.Diagnostic, Bool>:
        ty : M.Ty <- T.parameters(arguments, 0n, payload)
        current : Bool <- coverage(rest, Cover{ty, constructor_payloads(patterns, name)}, types)
        following : Bool <- coverage(rest, Constructors{tail, arguments, patterns}, types)
        return Bool.and(current, following)

def require(complete: Bool, ty: M.Ty, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match complete:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{M.Diagnostic{"non_exhaustive_match", subject, "patterns do not cover every value of " ++ M.type_show(ty)}}

def check(constraints: List<&2, I.Coverage>, +substitutions: List<&2, T.Substitution>, +types: List<&2, M.DataType>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match constraints:
    case Nil{}:
      Done{Unit{}}
    case I.Coverage{ty, patterns, subject} <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        +resolved : M.Ty <- T.resolve(substitutions, ty)
        complete : Bool <- coverage(Nat.mul(256n, 256n), Cover{resolved, patterns}, types)
        valid : Unit <- require(complete, resolved, subject)
        check(tail, substitutions, types)
