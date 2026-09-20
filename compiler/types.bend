import Base
import ./model.bend as M

type Equation is Data:
  Equation{left: M.Ty, right: M.Ty, subject: String}

type Substitution is Data:
  Substitution{variable: Nat, replacement: M.Ty}

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

def rewrite(+fuel: Nat, work: TypeWork, +replacement: Replacement) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match fuel work:
    case 0n _:
      Fail{complexity()}
    case 1n+rest OneType{M.FunctionTy{parameter, result}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        ps : List<&2, M.Ty> <- rewrite(rest, OneType{parameter}, replacement)
        rs : List<&2, M.Ty> <- rewrite(rest, OneType{result}, replacement)
        p : M.Ty <- first_type(ps)
        r : M.Ty <- first_type(rs)
        return [M.FunctionTy{p, r}]
    case 1n+rest OneType{M.AppliedTy{identity, arguments}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        xs : List<&2, M.Ty> <- rewrite(rest, ManyTypes{arguments}, replacement)
        return [M.AppliedTy{identity, xs}]
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
def resolve_work(+substitutions: List<&2, Substitution>, +fuel: Nat, work: TypeWork) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match substitutions fuel work:
    case Nil{} _ OneType{ty}:
      Done{[ty]}
    case Nil{} _ ManyTypes{types}:
      Done{types}
    case _ 0n _:
      Fail{complexity()}
    case Substitution{variable, replacement} <> tail _ OneType{M.VariableTy{index}}:
      resolve_work(tail, fuel, OneType{replace_leaf(M.VariableTy{index}, ReplaceVariable{variable, replacement})})
    case _ 1n+rest OneType{M.FunctionTy{parameter, result}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        ps : List<&2, M.Ty> <- resolve_work(substitutions, rest, OneType{parameter})
        rs : List<&2, M.Ty> <- resolve_work(substitutions, rest, OneType{result})
        p : M.Ty <- first_type(ps)
        r : M.Ty <- first_type(rs)
        return [M.FunctionTy{p, r}]
    case _ 1n+rest OneType{M.AppliedTy{identity, arguments}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        xs : List<&2, M.Ty> <- resolve_work(substitutions, rest, ManyTypes{arguments})
        return [M.AppliedTy{identity, xs}]
    case _ 1n+rest OneType{other}:
      Done{[other]}
    case _ 1n+rest ManyTypes{Nil{}}:
      Done{Nil{}}
    case _ 1n+rest ManyTypes{head <> tail}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        hs : List<&2, M.Ty> <- resolve_work(substitutions, rest, OneType{head})
        h : M.Ty <- first_type(hs)
        ts : List<&2, M.Ty> <- resolve_work(substitutions, rest, ManyTypes{tail})
        return h <> ts

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

def free_work(+fuel: Nat, work: TypeWork) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match fuel work:
    case 0n _:
      Fail{complexity()}
    case 1n+rest OneType{M.VariableTy{index}}:
      Done{[index]}
    case 1n+rest OneType{M.FunctionTy{parameter, result}}:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        p : List<&2, Nat> <- free_work(rest, OneType{parameter})
        r : List<&2, Nat> <- free_work(rest, OneType{result})
        return union(p, r)
    case 1n+rest OneType{M.AppliedTy{identity, arguments}}:
      free_work(rest, ManyTypes{arguments})
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

def pair_arguments(left: List<&2, M.Ty>, right: List<&2, M.Ty>, +subject: String) -> Result<&2, &2, M.Diagnostic, List<&2, Equation>>:
  match left right:
    case Nil{} Nil{}:
      Done{Nil{}}
    case a <> aa b <> bb:
      do Result<&2, &2, M.Diagnostic, List<&2, Equation>>:
        tail : List<&2, Equation> <- pair_arguments(aa, bb, subject)
        return Equation{a, b, subject} <> tail
    case _ _:
      Fail{M.Diagnostic{"type_arity", subject, "type constructor argument counts differ"}}

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
    case M.BoolTy{} M.BoolTy{}:
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
    case M.FunctionTy{ap, ar} M.FunctionTy{bp, br}:
      Done{Unification{[Equation{ap, bp, subject}, Equation{ar, br, subject}], substitutions}}
    case M.NominalTy{+a} M.NominalTy{+b}:
      nominal(M.type_id_equal(a, b), a, b, Nil{}, Nil{}, substitutions, subject)
    case M.AppliedTy{+a, aa} M.AppliedTy{+b, bb}:
      nominal(M.type_id_equal(a, b), a, b, aa, bb, substitutions, subject)
    case a b:
      Fail{mismatch(a, b, subject)}

def solve_work(fuel: Nat, equations: List<&2, Equation>, +substitutions: List<&2, Substitution>) -> Result<&2, &2, M.Diagnostic, List<&2, Substitution>>:
  match fuel equations:
    case _ Nil{}:
      Done{substitutions}
    case 0n _:
      Fail{complexity()}
    case 1n+rest Equation{left, right, subject} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Substitution>>:
        a : M.Ty <- resolve(substitutions, left)
        b : M.Ty <- resolve(substitutions, right)
        +result : Unification <- unify_one(a, b, substitutions, subject)
        solve_work(rest, List.append(&2, Equation, pending_equations(result), tail), substitutions_of(result))

def solve(equations: List<&2, Equation>, substitutions: List<&2, Substitution>) -> Result<&2, &2, M.Diagnostic, List<&2, Substitution>>:
  solve_work(Nat.mul(256n, 256n), equations, substitutions)

def unify(left: M.Ty, right: M.Ty, substitutions: List<&2, Substitution>, subject: String) -> Result<&2, &2, M.Diagnostic, List<&2, Substitution>>:
  solve([Equation{left, right, subject}], substitutions)

def scalar(ty: M.Ty) -> Bool:
  match ty:
    case M.UnitTy{}:
      True{}
    case M.U32Ty{}:
      True{}
    case M.BoolTy{}:
      True{}
    case _:
      False{}
