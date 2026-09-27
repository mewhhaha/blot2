import Base
import ./model.bend as M
import ./types.bend as T
import ./type_data.bend as D
import ./infer.bend as I

def wildcard_row(patterns: List<&2, M.Pattern>) -> Bool:
  match patterns:
    case Nil{}:
      True{}
    case M.WildcardPattern{} <> tail:
      wildcard_row(tail)
    case M.BindingPattern{name} <> tail:
      wildcard_row(tail)
    case other <> tail:
      False{}

def has_wildcard_row_work(rows: List<&2, List<&2, M.Pattern>>, found: Bool) -> Bool:
  match rows found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case row <> tail False{}:
      has_wildcard_row_work(tail, wildcard_row(row))

def has_wildcard_row(rows: List<&2, List<&2, M.Pattern>>) -> Bool:
  has_wildcard_row_work(rows, False{})

def has_never_column(types: List<&2, M.Ty>) -> Bool:
  match types:
    case Nil{}:
      False{}
    case M.NeverTy{} <> tail:
      True{}
    case other <> tail:
      has_never_column(tail)

type Head is Data:
  UnitHead{}
  BoolHead{value: Bool}
  ConstructorHead{name: String, payload: Bool}
  ProductHead{arity: Nat}
  DefaultHead{}

def wildcard_fields(count: Nat, tail: List<&2, M.Pattern>) -> List<&2, M.Pattern>:
  match count:
    case 0n:
      tail
    case 1n+rest:
      wildcard_fields(rest, M.WildcardPattern{} <> tail)

def select_head(head: Head, pattern: M.Pattern, remaining: List<&2, M.Pattern>) -> Maybe<&2, List<&2, M.Pattern>>:
  match head pattern:
    case ConstructorHead{name, True{}} M.WildcardPattern{}:
      Some{M.WildcardPattern{} <> remaining}
    case ConstructorHead{name, True{}} M.BindingPattern{binding}:
      Some{M.WildcardPattern{} <> remaining}
    case ProductHead{arity} M.WildcardPattern{}:
      Some{wildcard_fields(arity, remaining)}
    case ProductHead{arity} M.BindingPattern{binding}:
      Some{wildcard_fields(arity, remaining)}
    case _ M.WildcardPattern{}:
      Some{remaining}
    case _ M.BindingPattern{name}:
      Some{remaining}
    case UnitHead{} M.UnitPattern{}:
      Some{remaining}
    case BoolHead{a} M.BoolPattern{b}:
      Bool.pick(Maybe<&2, List<&2, M.Pattern>>, Bool.not(Bool.xor(a, b)), Some{remaining}, None{})
    case ConstructorHead{name, False{}} M.ConstructorPattern{found, None{}}:
      Bool.pick(Maybe<&2, List<&2, M.Pattern>>, M.name_equal(name, found), Some{remaining}, None{})
    case ConstructorHead{name, True{}} M.ConstructorPattern{found, Some{payload}}:
      Bool.pick(Maybe<&2, List<&2, M.Pattern>>, M.name_equal(name, found), Some{payload <> remaining}, None{})
    case ProductHead{arity} M.ProductPattern{+elements}:
      Bool.pick(Maybe<&2, List<&2, M.Pattern>>, Nat.is_eq(arity, List.length(&2, M.Pattern, elements)), Some{List.reverse.go(&2, M.Pattern, List.reverse(&2, M.Pattern, elements), remaining)}, None{})
    case _ _:
      None{}

def add_selected(selected: Maybe<&2, List<&2, M.Pattern>>, rows: List<&2, List<&2, M.Pattern>>) -> List<&2, List<&2, M.Pattern>>:
  match selected:
    case None{}:
      rows
    case Some{row}:
      row <> rows

def specialize(rows: List<&2, List<&2, M.Pattern>>, +head: Head) -> List<&2, List<&2, M.Pattern>>:
  match rows:
    case Nil{}:
      Nil{}
    case Nil{} <> tail:
      specialize(tail, head)
    case (pattern <> remaining) <> tail:
      add_selected(select_head(head, pattern, remaining), specialize(tail, head))

type Work is Data:
  Cover{inferred_types: List<&2, M.Ty>, rows: List<&2, List<&2, M.Pattern>>}
  Check{complete: Bool, inferred_types: List<&2, M.Ty>, rows: List<&2, List<&2, M.Pattern>>}
  DataCases{definition: Maybe<&2, M.DataType>, arguments: List<&2, M.Ty>, remaining: List<&2, M.Ty>, rows: List<&2, List<&2, M.Pattern>>}
  Constructors{constructors: List<&2, M.Constructor>, arguments: List<&2, M.Ty>, remaining: List<&2, M.Ty>, rows: List<&2, List<&2, M.Pattern>>}

# Specialize complete rows, never each column independently: correlations between
# scrutinees remain in the matrix throughout constructor/default expansion.
def coverage(+fuel: Nat, work: Work, +types: List<&2, M.DataType>) -> Result<&2, &2, M.Diagnostic, Bool>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"pattern_complexity", "inference", "pattern coverage exceeds compiler traversal limit"}}
    case 1n+rest Cover{+inferred, +rows}:
      # Every scrutinee runs before matching, including later divergent columns.
      coverage(rest, Check{Bool.or(has_never_column(inferred), has_wildcard_row(rows)), inferred, rows}, types)
    case 1n+rest Check{True{}, inferred, rows}:
      Done{True{}}
    case 1n+rest Check{False{}, M.NeverTy{} <> remaining, rows}:
      Done{True{}}
    case 1n+rest Check{False{}, inferred, Nil{}}:
      Done{False{}}
    case 1n+rest Check{False{}, Nil{}, rows}:
      Done{False{}}
    case 1n+rest Check{False{}, M.BoolTy{} <> +remaining, +rows}:
      do Result<&2, &2, M.Diagnostic, Bool>:
        yes : Bool <- coverage(rest, Cover{remaining, specialize(rows, BoolHead{True{}})}, types)
        no : Bool <- coverage(rest, Cover{remaining, specialize(rows, BoolHead{False{}})}, types)
        return Bool.and(yes, no)
    case 1n+rest Check{False{}, M.UnitTy{} <> remaining, rows}:
      coverage(rest, Cover{remaining, specialize(rows, UnitHead{})}, types)
    case 1n+rest Check{False{}, M.AppliedTy{identity, arguments} <> remaining, rows}:
      coverage(rest, DataCases{D.lookup(types, identity), arguments, remaining, rows}, types)
    case 1n+rest Check{False{}, M.ProductTy{+elements} <> remaining, rows}:
      coverage(rest, Cover{List.reverse.go(&2, M.Ty, List.reverse(&2, M.Ty, elements), remaining), specialize(rows, ProductHead{List.length(&2, M.Ty, elements)})}, types)
    case 1n+rest Check{False{}, other <> remaining, rows}:
      coverage(rest, Cover{remaining, specialize(rows, DefaultHead{})}, types)
    case 1n+rest DataCases{None{}, arguments, remaining, rows}:
      Fail{M.Diagnostic{"internal_error", "inference", "coverage references an unknown data type"}}
    case 1n+rest DataCases{Some{M.DataType{identity, count, constructors}}, arguments, remaining, rows}:
      coverage(rest, Constructors{constructors, arguments, remaining, rows}, types)
    case 1n+rest Constructors{Nil{}, arguments, remaining, rows}:
      Done{True{}}
    case 1n+rest Constructors{M.Constructor{name, None{}, fields} <> tail, +arguments, +remaining, +rows}:
      do Result<&2, &2, M.Diagnostic, Bool>:
        current : Bool <- coverage(rest, Cover{remaining, specialize(rows, ConstructorHead{name, False{}})}, types)
        following : Bool <- coverage(rest, Constructors{tail, arguments, remaining, rows}, types)
        return Bool.and(current, following)
    case 1n+rest Constructors{M.Constructor{name, Some{payload}, fields} <> tail, +arguments, +remaining, +rows}:
      do Result<&2, &2, M.Diagnostic, Bool>:
        ty : M.Ty <- T.parameters(arguments, 0n, payload)
        current : Bool <- coverage(rest, Cover{ty <> remaining, specialize(rows, ConstructorHead{name, True{}})}, types)
        following : Bool <- coverage(rest, Constructors{tail, arguments, remaining, rows}, types)
        return Bool.and(current, following)

def types_show(types: List<&2, M.Ty>) -> String:
  match types:
    case Nil{}:
      ""
    case head <> Nil{}:
      M.type_show(head)
    case head <> next <> tail:
      M.type_show(head) ++ ", " ++ types_show(next <> tail)

def require(complete: Bool, types: List<&2, M.Ty>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match complete:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{M.Diagnostic{"non_exhaustive_match", subject, "pattern rows do not cover every value of (" ++ types_show(types) ++ ")"}}

def value_pattern_type(ty: M.Ty, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match ty:
    case M.U32Ty{}:
      Done{Unit{}}
    case M.BoolTy{}:
      Done{Unit{}}
    case _:
      Fail{M.Diagnostic{"value_pattern_type", subject, "value patterns require U32 or Bool; annotate an otherwise unconstrained parameter"}}

def check(constraints: List<&2, I.Coverage>, +substitutions: T.Substitutions, +types: List<&2, M.DataType>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match constraints:
    case Nil{}:
      Done{Unit{}}
    case I.OperationNeed{identity, template, arguments, function_type, subject} <> tail:
      check(tail, substitutions, types)
    case I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, subject} <> tail:
      # Monomorphization discharges these; this pass checks pattern coverage.
      check(tail, substitutions, types)
    case I.LetGeneralized{witness} <> tail:
      check(tail, substitutions, types)
    case I.QualifiedBoundary{offset, declared, subject} <> tail:
      check(tail, substitutions, types)
    # QualifiedNeed is produced only for release execution sites, after this
    # source pattern pass. Keep this visitor total if a caller supplies one.
    case I.QualifiedNeed{site, predicate, subject} <> tail:
      check(tail, substitutions, types)
    case I.ValuePatternType{inferred, subject} <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        resolved : M.Ty <- T.resolve(substitutions, inferred)
        valid : Unit <- value_pattern_type(resolved, subject)
        check(tail, substitutions, types)
    case I.Coverage{inferred, patterns, subject} <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        +resolved : List<&2, M.Ty> <- T.resolve_work(substitutions, U32.to_nat(65536), T.ManyTypes{inferred})
        complete : Bool <- coverage(U32.to_nat(65536), Cover{resolved, patterns}, types)
        valid : Unit <- require(complete, resolved, subject)
        check(tail, substitutions, types)
