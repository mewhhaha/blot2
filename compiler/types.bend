import Base
import ./model.bend as M
import ./effect_rows.bend as R

type Equation is Data:
  Equation{left: M.Ty, right: M.Ty, subject: String}
  RowEquation{left: M.EffectRow, right: M.EffectRow, subject: String}

type Substitution is Data:
  Substitution{variable: Nat, replacement: M.Ty}
  RowSubstitution{variable: Nat, replacement: M.EffectRow}

type TypeWork is Data:
  OneType{value: M.Ty}
  ManyTypes{values: List<&2, M.Ty>}

type Replacement is Data:
  ReplaceVariable{index: Nat, value: M.Ty}
  ReplaceParameter{index: Nat, value: M.Ty}

def complexity() -> M.Diagnostic:
  M.Diagnostic{"type_complexity", "inference", "type traversal exceeded the 65536-node nesting/width limit"}

def first_type(types: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match types:
    case head <> Nil{}:
      Done{head}
    case _:
      Fail{M.Diagnostic{"internal_error", "inference", "type rewrite did not produce exactly one type"}}

def replace_leaf(ty: M.Ty, replacement: Replacement) -> M.Ty:
  match ty replacement:
    case M.VariableTy{+found} ReplaceVariable{index, value}:
      Bool.pick(M.Ty, Nat.is_eq(found, index), value, M.VariableTy{found})
    case M.ParameterTy{+found} ReplaceParameter{index, value}:
      Bool.pick(M.Ty, Nat.is_eq(found, index), value, M.ParameterTy{found})
    case other _:
      other

def replacement_tail(value: M.Ty) -> Result<&2, &2, M.Diagnostic, M.RowTail>:
  match value:
    case M.VariableTy{index}:
      Done{M.RowVariable{index}}
    case M.ParameterTy{index}:
      Done{M.RowParameter{index}}
    case _:
      Fail{M.Diagnostic{"kind_mismatch", "inference", "an effect row variable cannot be replaced by a value type"}}

def rewrite_tail_match(same: Bool, original: M.RowTail, value: M.Ty) -> Result<&2, &2, M.Diagnostic, M.RowTail>:
  match same:
    case False{}:
      Done{original}
    case True{}:
      replacement_tail(value)

def rewrite_tail(tail: M.RowTail, replacement: Replacement) -> Result<&2, &2, M.Diagnostic, M.RowTail>:
  match tail replacement:
    case M.RowVariable{+found} ReplaceVariable{index, value}:
      rewrite_tail_match(Nat.is_eq(found, index), M.RowVariable{found}, value)
    case M.RowParameter{+found} ReplaceParameter{index, value}:
      rewrite_tail_match(Nat.is_eq(found, index), M.RowParameter{found}, value)
    case original _:
      Done{original}

def rewrite_row(row: M.EffectRow, replacement: Replacement) -> Result<&2, &2, M.Diagnostic, M.EffectRow>:
  M.EffectRow{operations, tail} = row
  do Result<&2, &2, M.Diagnostic, M.EffectRow>:
    rewritten : M.RowTail <- rewrite_tail(tail, replacement)
    return M.EffectRow{operations, rewritten}

def rewrite(+fuel: Nat, work: TypeWork, +replacement: Replacement) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match fuel work:
    case 0n _:
      Fail{complexity()}
    case 1n+rest OneType{M.FunctionTy{parameter, result, effects}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        ps : List<&2, M.Ty> <- rewrite(rest, OneType{parameter}, replacement)
        rs : List<&2, M.Ty> <- rewrite(rest, OneType{result}, replacement)
        p : M.Ty <- first_type(ps)
        r : M.Ty <- first_type(rs)
        row : M.EffectRow <- rewrite_row(effects, replacement)
        return [M.FunctionTy{p, r, row}]
    case 1n+rest OneType{M.ProviderTy{identity, effects}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        row : M.EffectRow <- rewrite_row(effects, replacement)
        return [M.ProviderTy{identity, row}]
    case 1n+rest OneType{M.AppliedTy{identity, arguments}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        xs : List<&2, M.Ty> <- rewrite(rest, ManyTypes{arguments}, replacement)
        return [M.AppliedTy{identity, xs}]
    case 1n+rest OneType{M.ProductTy{elements}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        xs : List<&2, M.Ty> <- rewrite(rest, ManyTypes{elements}, replacement)
        return [M.ProductTy{xs}]
    case 1n+rest OneType{M.ArrayTy{element}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        xs : List<&2, M.Ty> <- rewrite(rest, OneType{element}, replacement)
        value : M.Ty <- first_type(xs)
        return [M.ArrayTy{value}]
    case 1n+rest OneType{other}:
      Done{[replace_leaf(other, replacement)]}
    case 1n+rest ManyTypes{Nil{}}:
      Done{Nil{}}
    case 1n+rest ManyTypes{head <> tail}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        hs : List<&2, M.Ty> <- rewrite(rest, OneType{head}, replacement)
        h : M.Ty <- first_type(hs)
        ts : List<&2, M.Ty> <- rewrite(rest, ManyTypes{tail}, replacement)
        return h <> ts

def replace(ty: M.Ty, variable: Nat, replacement: M.Ty) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  do Result<&2, &2, M.Diagnostic, M.Ty>:
    xs : List<&2, M.Ty> <- rewrite(Nat.mul(256n, 256n), OneType{ty}, ReplaceVariable{variable, replacement})
    first_type(xs)

def parameters(arguments: List<&2, M.Ty>, +index: Nat, ty: M.Ty) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match arguments:
    case Nil{}:
      Done{ty}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, M.Ty>:
        xs : List<&2, M.Ty> <- rewrite(Nat.mul(256n, 256n), OneType{ty}, ReplaceParameter{index, head})
        next : M.Ty <- first_type(xs)
        parameters(tail, 1n+index, next)

# Substitutions act only on variable leaves. A replacement sees the remaining
# suffix, never earlier entries or its own entry, preserving sequential order.
# Fuel counts the same structural depth/width as rewrite, not substitution links.
def resolve_row(substitutions: List<&2, Substitution>, row: M.EffectRow) -> M.EffectRow:
  match substitutions:
    case Nil{}:
      row
    case RowSubstitution{variable, replacement} <> tail:
      resolve_row(tail, R.replace(row, variable, replacement))
    case Substitution{variable, replacement} <> tail:
      resolve_row(tail, row)

def resolve_accumulated(+substitutions: List<&2, Substitution>, +fuel: Nat, work: TypeWork, reversed: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match substitutions fuel work:
    case Nil{} _ OneType{ty}:
      Done{[ty]}
    case Nil{} _ ManyTypes{types}:
      Done{List.append(&2, M.Ty, List.reverse(&2, M.Ty, reversed), types)}
    case _ 0n _:
      Fail{complexity()}
    case Substitution{variable, replacement} <> tail _ OneType{M.VariableTy{index}}:
      resolve_accumulated(tail, fuel, OneType{replace_leaf(M.VariableTy{index}, ReplaceVariable{variable, replacement})}, Nil{})
    case RowSubstitution{variable, replacement} <> tail _ OneType{M.VariableTy{index}}:
      resolve_accumulated(tail, fuel, OneType{M.VariableTy{index}}, Nil{})
    case _ 1n+rest OneType{M.FunctionTy{parameter, result, effects}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        ps : List<&2, M.Ty> <- resolve_accumulated(substitutions, rest, OneType{parameter}, Nil{})
        rs : List<&2, M.Ty> <- resolve_accumulated(substitutions, rest, OneType{result}, Nil{})
        p : M.Ty <- first_type(ps)
        r : M.Ty <- first_type(rs)
        return [M.FunctionTy{p, r, resolve_row(substitutions, effects)}]
    case _ 1n+rest OneType{M.ProviderTy{identity, effects}}:
      Done{[M.ProviderTy{identity, resolve_row(substitutions, effects)}]}
    case _ 1n+rest OneType{M.AppliedTy{identity, arguments}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        xs : List<&2, M.Ty> <- resolve_accumulated(substitutions, rest, ManyTypes{arguments}, Nil{})
        return [M.AppliedTy{identity, xs}]
    case _ 1n+rest OneType{M.ProductTy{elements}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        xs : List<&2, M.Ty> <- resolve_accumulated(substitutions, rest, ManyTypes{elements}, Nil{})
        return [M.ProductTy{xs}]
    case _ 1n+rest OneType{M.ArrayTy{element}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        xs : List<&2, M.Ty> <- resolve_accumulated(substitutions, rest, OneType{element}, Nil{})
        value : M.Ty <- first_type(xs)
        return [M.ArrayTy{value}]
    case _ 1n+rest OneType{other}:
      Done{[other]}
    case _ 1n+rest ManyTypes{Nil{}}:
      Done{List.reverse(&2, M.Ty, reversed)}
    case _ 1n+rest ManyTypes{head <> tail}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        hs : List<&2, M.Ty> <- resolve_accumulated(substitutions, rest, OneType{head}, Nil{})
        h : M.Ty <- first_type(hs)
        resolve_accumulated(substitutions, rest, ManyTypes{tail}, h <> reversed)

def resolve_work(substitutions: List<&2, Substitution>, fuel: Nat, work: TypeWork) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  resolve_accumulated(substitutions, fuel, work, Nil{})

def resolve(substitutions: List<&2, Substitution>, ty: M.Ty) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  do Result<&2, &2, M.Diagnostic, M.Ty>:
    xs : List<&2, M.Ty> <- resolve_work(substitutions, Nat.mul(256n, 256n), OneType{ty})
    first_type(xs)

def contains(variables: List<&2, Nat>, +variable: Nat) -> Bool:
  match variables:
    case Nil{}:
      False{}
    case head <> tail:
      Bool.or(Nat.is_eq(head, variable), contains(tail, variable))

def put(+variables: List<&2, Nat>, +variable: Nat) -> List<&2, Nat>:
  Bool.pick(List<&2, Nat>, contains(variables, variable), variables, variable <> variables)

def union(left: List<&2, Nat>, right: List<&2, Nat>) -> List<&2, Nat>:
  match left:
    case Nil{}:
      right
    case head <> tail:
      union(tail, put(right, head))

def difference(variables: List<&2, Nat>, +excluded: List<&2, Nat>) -> List<&2, Nat>:
  match variables:
    case Nil{}:
      Nil{}
    case +head <> tail:
      +rest = difference(tail, excluded)
      Bool.pick(List<&2, Nat>, contains(excluded, head), rest, head <> rest)

def row_free(row: M.EffectRow) -> List<&2, Nat>:
  match row:
    case M.EffectRow{operations, M.RowVariable{index}}:
      [index]
    case _:
      Nil{}

def free_work(+fuel: Nat, work: TypeWork) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match fuel work:
    case 0n _:
      Fail{complexity()}
    case 1n+rest OneType{M.VariableTy{index}}:
      Done{[index]}
    case 1n+rest OneType{M.FunctionTy{parameter, result, effects}}:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        p : List<&2, Nat> <- free_work(rest, OneType{parameter})
        r : List<&2, Nat> <- free_work(rest, OneType{result})
        return union(row_free(effects), union(p, r))
    case 1n+rest OneType{M.ProviderTy{identity, effects}}:
      Done{row_free(effects)}
    case 1n+rest OneType{M.AppliedTy{identity, arguments}}:
      free_work(rest, ManyTypes{arguments})
    case 1n+rest OneType{M.ProductTy{elements}}:
      free_work(rest, ManyTypes{elements})
    case 1n+rest OneType{M.ArrayTy{element}}:
      free_work(rest, OneType{element})
    case 1n+rest OneType{other}:
      Done{Nil{}}
    case 1n+rest ManyTypes{Nil{}}:
      Done{Nil{}}
    case 1n+rest ManyTypes{head <> tail}:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        h : List<&2, Nat> <- free_work(rest, OneType{head})
        t : List<&2, Nat> <- free_work(rest, ManyTypes{tail})
        return union(h, t)

def free(ty: M.Ty) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  free_work(Nat.mul(256n, 256n), OneType{ty})

def close_tail(generalized: List<&2, Nat>, connected: List<&2, Nat>, row: M.EffectRow) -> M.EffectRow:
  match row:
    case M.EffectRow{labels, M.RowVariable{+index}}:
      +tail = {M.RowVariable{index} : M.RowTail}
      M.EffectRow{labels, Bool.pick(M.RowTail, Bool.and(contains(generalized, index), Bool.not(contains(connected, index))), M.ClosedRow{}, tail)}
    case other:
      other

# A product's siblings can share a callback's input row. Closing one sibling
# must not erase that constraint in another; nominal type arguments are invariant.
def covariant_inputs(+fuel: Nat, work: TypeWork) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match fuel work:
    case 0n _:
      Fail{complexity()}
    case 1n+rest OneType{M.FunctionTy{parameter, result, effects}}:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        inputs : List<&2, Nat> <- free(parameter)
        nested : List<&2, Nat> <- covariant_inputs(rest, OneType{result})
        return union(inputs, nested)
    case 1n+rest OneType{M.AppliedTy{identity, arguments}}:
      free_work(rest, ManyTypes{arguments})
    case 1n+rest OneType{M.ProductTy{elements}}:
      covariant_inputs(rest, ManyTypes{elements})
    case 1n+rest OneType{M.ArrayTy{element}}:
      covariant_inputs(rest, OneType{element})
    case 1n+rest ManyTypes{head <> tail}:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        h : List<&2, Nat> <- covariant_inputs(rest, OneType{head})
        t : List<&2, Nat> <- covariant_inputs(rest, ManyTypes{tail})
        return union(h, t)
    case 1n+rest _:
      Done{Nil{}}

# Returned closures preserve rows shared with outer parameters or still-open
# invocation rows. Providers and products obey the same covariance rule.
def close_covariant_work(+fuel: Nat, work: TypeWork, +generalized: List<&2, Nat>, +protected: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match fuel work:
    case 0n _:
      Fail{complexity()}
    case 1n+rest OneType{M.FunctionTy{+parameter, +result, effects}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        +parameter_free : List<&2, Nat> <- free(parameter)
        result_free : List<&2, Nat> <- free(result)
        +row : M.EffectRow = close_tail(generalized, union(protected, union(parameter_free, result_free)), effects)
        closed : List<&2, M.Ty> <- close_covariant_work(rest, OneType{result}, generalized, union(protected, union(parameter_free, row_free(row))))
        result : M.Ty <- first_type(closed)
        return [M.FunctionTy{parameter, result, row}]
    case 1n+rest OneType{M.ProviderTy{identity, effects}}:
      Done{[M.ProviderTy{identity, close_tail(generalized, protected, effects)}]}
    case 1n+rest OneType{M.ProductTy{+elements}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        connected : List<&2, Nat> <- covariant_inputs(rest, ManyTypes{elements})
        closed : List<&2, M.Ty> <- close_covariant_work(rest, ManyTypes{elements}, generalized, union(protected, connected))
        return [M.ProductTy{closed}]
    case 1n+rest OneType{M.ArrayTy{element}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        closed : List<&2, M.Ty> <- close_covariant_work(rest, OneType{element}, generalized, protected)
        value : M.Ty <- first_type(closed)
        return [M.ArrayTy{value}]
    case 1n+rest OneType{other}:
      Done{[other]}
    case 1n+rest ManyTypes{Nil{}}:
      Done{Nil{}}
    case 1n+rest ManyTypes{head <> tail}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        hs : List<&2, M.Ty> <- close_covariant_work(rest, OneType{head}, generalized, protected)
        h : M.Ty <- first_type(hs)
        ts : List<&2, M.Ty> <- close_covariant_work(rest, ManyTypes{tail}, generalized, protected)
        return h <> ts

def close_covariant(ty: M.Ty, generalized: List<&2, Nat>, protected: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  do Result<&2, &2, M.Diagnostic, M.Ty>:
    closed : List<&2, M.Ty> <- close_covariant_work(U32.to_nat(65536), OneType{ty}, generalized, protected)
    first_type(closed)

def close_generalized(ty: M.Ty, generalized: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  close_covariant(ty, generalized, Nil{})

type Opened is Data:
  Opened{inferred_type: M.Ty, next: Nat}

def opened_type(opened: Opened) -> M.Ty:
  Opened{ty, next} = opened
  ty

def opened_next(opened: Opened) -> Nat:
  Opened{ty, next} = opened
  next

def open_function(row: M.EffectRow, parameter: M.Ty, opened: Opened) -> Opened:
  match row:
    case M.EffectRow{labels, M.ClosedRow{}}:
      Opened{result, +next} = opened
      Opened{M.FunctionTy{parameter, result, M.EffectRow{labels, M.RowVariable{next}}}, 1n+next}
    case effects:
      Opened{result, next} = opened
      Opened{M.FunctionTy{parameter, result, effects}, next}

type OpenedTypes is Data:
  OpenedTypes{types: List<&2, M.Ty>, next: Nat}

def opened_types(value: OpenedTypes) -> List<&2, M.Ty>:
  OpenedTypes{types, next} = value
  types

def opened_types_next(value: OpenedTypes) -> Nat:
  OpenedTypes{types, next} = value
  next

def open_covariant_work(+fuel: Nat, work: TypeWork, +next: Nat) -> Result<&2, &2, M.Diagnostic, OpenedTypes>:
  match fuel work:
    case 0n _:
      Fail{complexity()}
    case 1n+rest OneType{M.FunctionTy{parameter, result, effects}}:
      do Result<&2, &2, M.Diagnostic, OpenedTypes>:
        +nested : OpenedTypes <- open_covariant_work(rest, OneType{result}, next)
        result : M.Ty <- first_type(opened_types(nested))
        +opened : Opened = open_function(effects, parameter, Opened{result, opened_types_next(nested)})
        return OpenedTypes{[opened_type(opened)], opened_next(opened)}
    case 1n+rest OneType{M.ProviderTy{identity, M.EffectRow{labels, M.ClosedRow{}}}}:
      Done{OpenedTypes{[M.ProviderTy{identity, M.EffectRow{labels, M.RowVariable{next}}}], 1n+next}}
    case 1n+rest OneType{M.ProductTy{elements}}:
      do Result<&2, &2, M.Diagnostic, OpenedTypes>:
        +nested : OpenedTypes <- open_covariant_work(rest, ManyTypes{elements}, next)
        return OpenedTypes{[M.ProductTy{opened_types(nested)}], opened_types_next(nested)}
    case 1n+rest OneType{M.ArrayTy{element}}:
      do Result<&2, &2, M.Diagnostic, OpenedTypes>:
        +nested : OpenedTypes <- open_covariant_work(rest, OneType{element}, next)
        value : M.Ty <- first_type(opened_types(nested))
        return OpenedTypes{[M.ArrayTy{value}], opened_types_next(nested)}
    case 1n+rest OneType{other}:
      Done{OpenedTypes{[other], next}}
    case 1n+rest ManyTypes{Nil{}}:
      Done{OpenedTypes{Nil{}, next}}
    case 1n+rest ManyTypes{head <> tail}:
      do Result<&2, &2, M.Diagnostic, OpenedTypes>:
        +hs : OpenedTypes <- open_covariant_work(rest, OneType{head}, next)
        h : M.Ty <- first_type(opened_types(hs))
        +ts : OpenedTypes <- open_covariant_work(rest, ManyTypes{tail}, opened_types_next(hs))
        return OpenedTypes{h <> opened_types(ts), opened_types_next(ts)}

def open_covariant(ty: M.Ty, next: Nat) -> Result<&2, &2, M.Diagnostic, Opened>:
  do Result<&2, &2, M.Diagnostic, Opened>:
    +opened : OpenedTypes <- open_covariant_work(U32.to_nat(65536), OneType{ty}, next)
    value : M.Ty <- first_type(opened_types(opened))
    return Opened{value, opened_types_next(opened)}

type ParameterKinds is Data:
  ParameterKinds{types: List<&2, Nat>, rows: List<&2, Nat>}

def merge_kinds(left: ParameterKinds, right: ParameterKinds) -> ParameterKinds:
  ParameterKinds{lt, lr} = left
  ParameterKinds{rt, rr} = right
  ParameterKinds{union(lt, rt), union(lr, rr)}

def row_parameter_kinds(row: M.EffectRow) -> ParameterKinds:
  match row:
    case M.EffectRow{labels, M.RowParameter{index}}:
      ParameterKinds{Nil{}, [index]}
    case _:
      ParameterKinds{Nil{}, Nil{}}

def parameter_kinds(+fuel: Nat, work: TypeWork) -> Result<&2, &2, M.Diagnostic, ParameterKinds>:
  match fuel work:
    case 0n _:
      Fail{complexity()}
    case 1n+rest OneType{M.ParameterTy{index}}:
      Done{ParameterKinds{[index], Nil{}}}
    case 1n+rest OneType{M.FunctionTy{parameter, result, effects}}:
      do Result<&2, &2, M.Diagnostic, ParameterKinds>:
        nested : ParameterKinds <- parameter_kinds(rest, ManyTypes{[parameter, result]})
        return merge_kinds(row_parameter_kinds(effects), nested)
    case 1n+rest OneType{M.ProviderTy{identity, effects}}:
      Done{row_parameter_kinds(effects)}
    case 1n+rest OneType{M.AppliedTy{identity, arguments}}:
      parameter_kinds(rest, ManyTypes{arguments})
    case 1n+rest OneType{M.ProductTy{elements}}:
      parameter_kinds(rest, ManyTypes{elements})
    case 1n+rest OneType{M.ArrayTy{element}}:
      parameter_kinds(rest, OneType{element})
    case 1n+rest ManyTypes{head <> tail}:
      do Result<&2, &2, M.Diagnostic, ParameterKinds>:
        first : ParameterKinds <- parameter_kinds(rest, OneType{head})
        remaining : ParameterKinds <- parameter_kinds(rest, ManyTypes{tail})
        return merge_kinds(first, remaining)
    case 1n+rest _:
      Done{ParameterKinds{Nil{}, Nil{}}}

def disjoint(variables: List<&2, Nat>, +excluded: List<&2, Nat>) -> Bool:
  match variables:
    case Nil{}:
      True{}
    case head <> tail:
      Bool.and(Bool.not(contains(excluded, head)), disjoint(tail, excluded))

def kind_check(kinds: ParameterKinds, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  ParameterKinds{types, rows} = kinds
  Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, disjoint(types, rows), Done{Unit{}}, Fail{M.Diagnostic{"kind_mismatch", subject, "a quantified index is used as both a value type and an effect row"}})

def variable_binding(recursive: Bool, variable: Nat, replacement: M.Ty, substitutions: List<&2, Substitution>, subject: String) -> Result<&2, &2, M.Diagnostic, List<&2, Substitution>>:
  match recursive:
    case True{}:
      Fail{M.Diagnostic{"infinite_type", subject, "occurs check failed: ?" ++ Nat.show(variable) ++ " occurs in " ++ M.type_show(replacement)}}
    case False{}:
      Done{List.append(&2, Substitution, substitutions, [Substitution{variable, replacement}])}

def bind(+variable: Nat, +replacement: M.Ty, substitutions: List<&2, Substitution>, subject: String) -> Result<&2, &2, M.Diagnostic, List<&2, Substitution>>:
  do Result<&2, &2, M.Diagnostic, List<&2, Substitution>>:
    variables : List<&2, Nat> <- free(replacement)
    variable_binding(contains(variables, variable), variable, replacement, substitutions, subject)

def pair_arguments_accumulated(left: List<&2, M.Ty>, right: List<&2, M.Ty>, +subject: String, reversed: List<&2, Equation>) -> Result<&2, &2, M.Diagnostic, List<&2, Equation>>:
  match left right:
    case Nil{} Nil{}:
      Done{List.reverse(&2, Equation, reversed)}
    case a <> aa b <> bb:
      pair_arguments_accumulated(aa, bb, subject, Equation{a, b, subject} <> reversed)
    case _ _:
      Fail{M.Diagnostic{"type_arity", subject, "type constructor argument counts differ"}}

def pair_arguments(left: List<&2, M.Ty>, right: List<&2, M.Ty>, subject: String) -> Result<&2, &2, M.Diagnostic, List<&2, Equation>>:
  pair_arguments_accumulated(left, right, subject, Nil{})

type Unification is Data:
  Unification{equations: List<&2, Equation>, substitutions: List<&2, Substitution>}

def pending_equations(result: Unification) -> List<&2, Equation>:
  Unification{equations, substitutions} = result
  equations

def substitutions_of(result: Unification) -> List<&2, Substitution>:
  Unification{equations, substitutions} = result
  substitutions

def mismatch(left: M.Ty, right: M.Ty, subject: String) -> M.Diagnostic:
  M.Diagnostic{"type_mismatch", subject, "cannot unify " ++ M.type_show(left) ++ " with " ++ M.type_show(right)}

def same_variable(same: Bool, left: Nat, right: Nat, substitutions: List<&2, Substitution>, subject: String) -> Result<&2, &2, M.Diagnostic, Unification>:
  match same:
    case True{}:
      Done{Unification{Nil{}, substitutions}}
    case False{}:
      do Result<&2, &2, M.Diagnostic, Unification>:
        next : List<&2, Substitution> <- bind(left, M.VariableTy{right}, substitutions, subject)
        return Unification{Nil{}, next}

def nominal(same: Bool, left: M.TypeId, right: M.TypeId, a: List<&2, M.Ty>, b: List<&2, M.Ty>, substitutions: List<&2, Substitution>, subject: String) -> Result<&2, &2, M.Diagnostic, Unification>:
  match same:
    case False{}:
      Fail{mismatch(M.AppliedTy{left, a}, M.AppliedTy{right, b}, subject)}
    case True{}:
      do Result<&2, &2, M.Diagnostic, Unification>:
        equations : List<&2, Equation> <- pair_arguments(a, b, subject)
        return Unification{equations, substitutions}

def providers(same: Bool, left: M.TypeId, right: M.TypeId, a: M.EffectRow, b: M.EffectRow, substitutions: List<&2, Substitution>, subject: String) -> Result<&2, &2, M.Diagnostic, Unification>:
  match same:
    case False{}:
      Fail{mismatch(M.ProviderTy{left, a}, M.ProviderTy{right, b}, subject)}
    case True{}:
      Done{Unification{[RowEquation{a, b, subject}], substitutions}}

def products(same_arity: Bool, left: List<&2, M.Ty>, right: List<&2, M.Ty>, substitutions: List<&2, Substitution>, subject: String) -> Result<&2, &2, M.Diagnostic, Unification>:
  match same_arity:
    case False{}:
      Fail{M.Diagnostic{"product_arity", subject, "cannot unify products with different element counts"}}
    case True{}:
      do Result<&2, &2, M.Diagnostic, Unification>:
        equations : List<&2, Equation> <- pair_arguments(left, right, subject)
        return Unification{equations, substitutions}

def unify_one(left: M.Ty, right: M.Ty, substitutions: List<&2, Substitution>, +subject: String) -> Result<&2, &2, M.Diagnostic, Unification>:
  match left right:
    case M.NeverTy{} _:
      Done{Unification{Nil{}, substitutions}}
    case _ M.NeverTy{}:
      Done{Unification{Nil{}, substitutions}}
    case M.UnitTy{} M.UnitTy{}:
      Done{Unification{Nil{}, substitutions}}
    case M.U32Ty{} M.U32Ty{}:
      Done{Unification{Nil{}, substitutions}}
    case M.F32Ty{} M.F32Ty{}:
      Done{Unification{Nil{}, substitutions}}
    case M.BoolTy{} M.BoolTy{}:
      Done{Unification{Nil{}, substitutions}}
    case M.EffectDescriptorTy{} M.EffectDescriptorTy{}:
      Done{Unification{Nil{}, substitutions}}
    case M.EffectSetTy{} M.EffectSetTy{}:
      Done{Unification{Nil{}, substitutions}}
    case M.VariableTy{+a} M.VariableTy{+b}:
      same_variable(Nat.is_eq(a, b), a, b, substitutions, subject)
    case M.VariableTy{index} other:
      do Result<&2, &2, M.Diagnostic, Unification>:
        next : List<&2, Substitution> <- bind(index, other, substitutions, subject)
        return Unification{Nil{}, next}
    case other M.VariableTy{index}:
      do Result<&2, &2, M.Diagnostic, Unification>:
        next : List<&2, Substitution> <- bind(index, other, substitutions, subject)
        return Unification{Nil{}, next}
    case M.FunctionTy{ap, ar, ae} M.FunctionTy{bp, br, be}:
      Done{Unification{[Equation{ap, bp, subject}, Equation{ar, br, subject}, RowEquation{ae, be, subject}], substitutions}}
    case M.ProviderTy{+a, ae} M.ProviderTy{+b, be}:
      providers(M.type_id_equal(a, b), a, b, ae, be, substitutions, subject)
    case M.AppliedTy{+a, aa} M.AppliedTy{+b, bb}:
      nominal(M.type_id_equal(a, b), a, b, aa, bb, substitutions, subject)
    case M.ProductTy{+a} M.ProductTy{+b}:
      products(Nat.is_eq(List.length(&2, M.Ty, a), List.length(&2, M.Ty, b)), a, b, substitutions, subject)
    case M.ArrayTy{a} M.ArrayTy{b}:
      Done{Unification{[Equation{a, b, subject}], substitutions}}
    case a b:
      Fail{mismatch(a, b, subject)}

type Solution is Data:
  Solution{substitutions: List<&2, Substitution>, next: Nat}

def solution_substitutions(solution: Solution) -> List<&2, Substitution>:
  Solution{substitutions, next} = solution
  substitutions

def solution_next(solution: Solution) -> Nat:
  Solution{substitutions, next} = solution
  next

def row_substitutions(bindings: List<&2, R.Binding>) -> List<&2, Substitution>:
  match bindings:
    case Nil{}:
      Nil{}
    case R.Binding{variable, replacement} <> tail:
      RowSubstitution{variable, replacement} <> row_substitutions(tail)

def row_solution(solution: R.Solution, previous: List<&2, Substitution>) -> Solution:
  R.Solution{bindings, next} = solution
  Solution{List.append(&2, Substitution, previous, row_substitutions(bindings)), next}

def solve_work(fuel: Nat, equations: List<&2, Equation>, +substitutions: List<&2, Substitution>, next: Nat) -> Result<&2, &2, M.Diagnostic, Solution>:
  match fuel equations:
    case _ Nil{}:
      Done{Solution{substitutions, next}}
    case 0n _:
      Fail{complexity()}
    case 1n+rest Equation{left, right, subject} <> tail:
      do Result<&2, &2, M.Diagnostic, Solution>:
        a : M.Ty <- resolve(substitutions, left)
        b : M.Ty <- resolve(substitutions, right)
        +result : Unification <- unify_one(a, b, substitutions, subject)
        solve_work(rest, List.reverse.go(&2, Equation, List.reverse(&2, Equation, pending_equations(result)), tail), substitutions_of(result), next)
    case 1n+rest RowEquation{left, right, subject} <> tail:
      do Result<&2, &2, M.Diagnostic, Solution>:
        rows : R.Solution <- R.unify(resolve_row(substitutions, left), resolve_row(substitutions, right), Nil{}, next, subject)
        +solved : Solution = row_solution(rows, substitutions)
        solve_work(rest, tail, solution_substitutions(solved), solution_next(solved))

def equations_free(equations: List<&2, Equation>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match equations:
    case Nil{}:
      Done{Nil{}}
    case Equation{left, right, subject} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        first : List<&2, Nat> <- free_work(U32.to_nat(65536), ManyTypes{[left, right]})
        remaining : List<&2, Nat> <- equations_free(tail)
        return union(first, remaining)
    case RowEquation{left, right, subject} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        remaining : List<&2, Nat> <- equations_free(tail)
        return union(row_free(left), union(row_free(right), remaining))

def substitutions_free(substitutions: List<&2, Substitution>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match substitutions:
    case Nil{}:
      Done{Nil{}}
    case Substitution{variable, replacement} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        first : List<&2, Nat> <- free(replacement)
        remaining : List<&2, Nat> <- substitutions_free(tail)
        return variable <> union(first, remaining)
    case RowSubstitution{variable, replacement} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        remaining : List<&2, Nat> <- substitutions_free(tail)
        return variable <> union(row_free(replacement), remaining)

def above(variables: List<&2, Nat>, +next: Nat) -> Nat:
  match variables:
    case Nil{}:
      next
    case head <> tail:
      +candidate = {1n+head : Nat}
      above(tail, Bool.pick(Nat, Nat.is_lt(next, candidate), candidate, next))

def solve(equations: List<&2, Equation>, substitutions: List<&2, Substitution>) -> Result<&2, &2, M.Diagnostic, List<&2, Substitution>>:
  +pending = equations
  +previous = substitutions
  do Result<&2, &2, M.Diagnostic, List<&2, Substitution>>:
    first : List<&2, Nat> <- equations_free(pending)
    second : List<&2, Nat> <- substitutions_free(previous)
    solved : Solution <- solve_work(U32.to_nat(65536), pending, previous, above(first, above(second, 0n)))
    return solution_substitutions(solved)

def unify_at(left: M.Ty, right: M.Ty, substitutions: List<&2, Substitution>, next: Nat, subject: String) -> Result<&2, &2, M.Diagnostic, Solution>:
  solve_work(U32.to_nat(65536), [Equation{left, right, subject}], substitutions, next)

def unify_rows_at(left: M.EffectRow, right: M.EffectRow, substitutions: List<&2, Substitution>, next: Nat, subject: String) -> Result<&2, &2, M.Diagnostic, Solution>:
  solve_work(U32.to_nat(65536), [RowEquation{left, right, subject}], substitutions, next)

def unify(left: M.Ty, right: M.Ty, substitutions: List<&2, Substitution>, subject: String) -> Result<&2, &2, M.Diagnostic, List<&2, Substitution>>:
  solve([Equation{left, right, subject}], substitutions)

def scalar(ty: M.Ty) -> Bool:
  match ty:
    case M.UnitTy{}:
      True{}
    case M.U32Ty{}:
      True{}
    case M.F32Ty{}:
      True{}
    case M.BoolTy{}:
      True{}
    case _:
      False{}
