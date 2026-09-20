import Base
import ./model.bend as M

type Binding is Data:
  Binding{variable: Nat, replacement: M.EffectRow}

type Solution is Data:
  Solution{bindings: List<&2, Binding>, next: Nat}

type Selection is Data:
  Selection{found: Bool, remaining: List<&2, M.TypeId>}

type Extraction is Data:
  Extraction{remaining: M.EffectRow, solution: Solution, expanded: Maybe<&2, Nat>}

def extraction_row(extracted: Extraction) -> M.EffectRow:
  Extraction{remaining, solution, expanded} = extracted
  remaining

def extraction_solution(extracted: Extraction) -> Solution:
  Extraction{remaining, solution, expanded} = extracted
  solution

def extraction_expanded(extracted: Extraction) -> Maybe<&2, Nat>:
  Extraction{remaining, solution, expanded} = extracted
  expanded

def solution_bindings(solution: Solution) -> List<&2, Binding>:
  Solution{bindings, next} = solution
  bindings

def variable_row(index: Nat) -> M.EffectRow:
  M.EffectRow{Nil{}, M.RowVariable{index}}

def singleton(identity: M.TypeId, tail: M.RowTail) -> M.EffectRow:
  M.EffectRow{[identity], tail}

def row_tail(row: M.EffectRow) -> M.RowTail:
  M.EffectRow{operations, rest} = row
  rest

def row_operations(row: M.EffectRow) -> List<&2, M.TypeId>:
  M.EffectRow{labels, rest} = row
  labels

def prepend(labels: List<&2, M.TypeId>, row: M.EffectRow) -> M.EffectRow:
  M.EffectRow{remaining, rest} = row
  M.EffectRow{List.append(&2, M.TypeId, labels, remaining), rest}

def same_variable(rest: M.RowTail, index: Nat) -> Bool:
  match rest:
    case M.RowVariable{found}:
      Nat.is_eq(found, index)
    case _:
      False{}

def replaced(found: Bool, row: M.EffectRow, labels: List<&2, M.TypeId>, replacement: M.EffectRow) -> M.EffectRow:
  match found:
    case False{}:
      row
    case True{}:
      prepend(labels, replacement)

def replace(+row: M.EffectRow, index: Nat, replacement: M.EffectRow) -> M.EffectRow:
  M.EffectRow{labels, rest} = row
  replaced(same_variable(rest, index), row, labels, replacement)

def resolve(bindings: List<&2, Binding>, row: M.EffectRow) -> M.EffectRow:
  match bindings:
    case Nil{}:
      row
    case Binding{variable, replacement} <> rest:
      resolve(rest, replace(row, variable, replacement))

def infinite(subject: String) -> M.Diagnostic:
  M.Diagnostic{"infinite_effect", subject, "effect row occurs check failed"}

def mismatch(left: M.EffectRow, right: M.EffectRow, subject: String) -> M.Diagnostic:
  M.Diagnostic{"effect_mismatch", subject, "cannot unify effect rows" ++ M.row_show(left) ++ " and" ++ M.row_show(right)}

def bind_checked(recursive: Bool, index: Nat, row: M.EffectRow, solution: Solution, subject: String) -> Result<&2, &2, M.Diagnostic, Solution>:
  match recursive:
    case True{}:
      Fail{infinite(subject)}
    case False{}:
      Solution{bindings, next} = solution
      Done{Solution{List.append(&2, Binding, bindings, [Binding{index, row}]), next}}

def bind(+index: Nat, +row: M.EffectRow, solution: Solution, subject: String) -> Result<&2, &2, M.Diagnostic, Solution>:
  bind_checked(same_variable(row_tail(row), index), index, row, solution, subject)

def selected(found: Bool, head: M.TypeId, remaining: List<&2, M.TypeId>, result: Selection) -> Selection:
  match found:
    case True{}:
      Selection{True{}, remaining}
    case False{}:
      Selection{present, tail} = result
      Selection{present, head <> tail}

def select(labels: List<&2, M.TypeId>, +identity: M.TypeId) -> Selection:
  match labels:
    case Nil{}:
      Selection{False{}, Nil{}}
    case +head <> +rest:
      selected(M.type_id_equal(head, identity), head, rest, select(rest, identity))

def extract_tail(rest: M.RowTail, labels: List<&2, M.TypeId>, identity: M.TypeId, solution: Solution, subject: String) -> Result<&2, &2, M.Diagnostic, Extraction>:
  match rest:
    case M.RowVariable{+index}:
      Solution{bindings, +next} = solution
      +row = singleton(identity, M.RowVariable{next})
      Done{Extraction{M.EffectRow{labels, M.RowVariable{next}}, Solution{List.append(&2, Binding, bindings, [Binding{index, row}]), 1n+next}, Some{index}}}
    case other:
      Fail{mismatch(M.EffectRow{labels, other}, singleton(identity, M.ClosedRow{}), subject)}

def extract_selected(selected: Selection, rest: M.RowTail, identity: M.TypeId, solution: Solution, subject: String) -> Result<&2, &2, M.Diagnostic, Extraction>:
  match selected:
    case Selection{True{}, remaining}:
      Done{Extraction{M.EffectRow{remaining, rest}, solution, None{}}}
    case Selection{False{}, remaining}:
      extract_tail(rest, remaining, identity, solution, subject)

def extract(row: M.EffectRow, +identity: M.TypeId, solution: Solution, subject: String) -> Result<&2, &2, M.Diagnostic, Extraction>:
  M.EffectRow{labels, rest} = row
  extract_selected(select(labels, identity), rest, identity, solution, subject)

def safe_expansion(rest: M.RowTail, expanded: Maybe<&2, Nat>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match rest expanded:
    case M.RowVariable{left} Some{right}:
      Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, Nat.is_eq(left, right), Fail{infinite(subject)}, Done{Unit{}})
    case _ _:
      Done{Unit{}}

def unify_tails(left: M.RowTail, right: M.RowTail, +solution: Solution, subject: String) -> Result<&2, &2, M.Diagnostic, Solution>:
  match left right:
    case M.ClosedRow{} M.ClosedRow{}:
      Done{solution}
    case M.RowVariable{+a} M.RowVariable{+b}:
      Bool.pick(Result<&2, &2, M.Diagnostic, Solution>, Nat.is_eq(a, b), Done{solution}, bind(a, variable_row(b), solution, subject))
    case M.RowVariable{index} other:
      bind(index, M.EffectRow{Nil{}, other}, solution, subject)
    case other M.RowVariable{index}:
      bind(index, M.EffectRow{Nil{}, other}, solution, subject)
    case M.RowParameter{+a} M.RowParameter{+b}:
      Bool.pick(Result<&2, &2, M.Diagnostic, Solution>, Nat.is_eq(a, b), Done{solution}, Fail{mismatch(M.EffectRow{Nil{}, M.RowParameter{a}}, M.EffectRow{Nil{}, M.RowParameter{b}}, subject)})
    case a b:
      Fail{mismatch(M.EffectRow{Nil{}, a}, M.EffectRow{Nil{}, b}, subject)}

def unify_work(fuel: Nat, left: M.EffectRow, right: M.EffectRow, +solution: Solution, +subject: String) -> Result<&2, &2, M.Diagnostic, Solution>:
  match fuel left right:
    case 0n _ _:
      Fail{M.Diagnostic{"type_complexity", subject, "effect row unification exceeded its structural limit"}}
    case 1n+rest M.EffectRow{Nil{}, a} M.EffectRow{Nil{}, b}:
      unify_tails(a, b, solution, subject)
    case 1n+rest M.EffectRow{Nil{}, M.RowVariable{index}} other:
      bind(index, other, solution, subject)
    case 1n+rest other M.EffectRow{Nil{}, M.RowVariable{index}}:
      bind(index, other, solution, subject)
    case 1n+rest M.EffectRow{identity <> labels, +a} other:
      do Result<&2, &2, M.Diagnostic, Solution>:
        +extracted : Extraction <- extract(other, identity, solution, subject)
        +next : Solution = extraction_solution(extracted)
        +bindings : List<&2, Binding> = solution_bindings(next)
        valid : Unit <- safe_expansion(a, extraction_expanded(extracted), subject)
        unify_work(rest, resolve(bindings, M.EffectRow{labels, a}), resolve(bindings, extraction_row(extracted)), next, subject)
    case 1n+rest a b:
      Fail{mismatch(a, b, subject)}

def unify(left: M.EffectRow, right: M.EffectRow, +bindings: List<&2, Binding>, next: Nat, subject: String) -> Result<&2, &2, M.Diagnostic, Solution>:
  unify_work(U32.to_nat(65536), resolve(bindings, left), resolve(bindings, right), Solution{bindings, next}, subject)

def operation_le(left: M.TypeId, right: M.TypeId) -> Bool:
  M.TypeId{+lm, ln} = left
  M.TypeId{+rm, rn} = right
  Bool.or(String.is_lt(lm, rm), Bool.and(M.name_equal(lm, rm), String.is_le(ln, rn)))

def canonical(row: M.EffectRow) -> M.EffectRow:
  M.EffectRow{labels, rest} = row
  M.EffectRow{List.sort(~M.TypeId, ~operation_le, labels), rest}

def distinct_sorted(labels: List<&2, M.TypeId>, previous: Maybe<&2, M.TypeId>) -> List<&2, M.TypeId>:
  match labels previous:
    case Nil{} _:
      Nil{}
    case +head <> rest None{}:
      head <> distinct_sorted(rest, Some{head})
    case +head <> rest Some{last}:
      +remaining = distinct_sorted(rest, Some{head})
      Bool.pick(List<&2, M.TypeId>, M.type_id_equal(head, last), remaining, head <> remaining)

def operation_set(row: M.EffectRow) -> List<&2, M.TypeId>:
  distinct_sorted(row_operations(canonical(row)), None{})

def metadata(operations: List<&2, M.TypeId>) -> List<&2, M.Effect>:
  match operations:
    case Nil{}:
      Nil{}
    case identity <> rest:
      M.OperationEffect{identity} <> metadata(rest)
