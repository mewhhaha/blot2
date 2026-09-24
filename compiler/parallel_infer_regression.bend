import Base
import ./model.bend as M
import ./infer.bend as I
import ./types.bend as T
import ./globals.bend as G
import ./parallel_infer.bend as ParallelInfer

def same_substitutions(left: List<&2, T.Substitution>, right: List<&2, T.Substitution>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case T.Substitution{a, x} <> xs T.Substitution{b, y} <> ys:
      Bool.and(Nat.is_eq(a, b), Bool.and(String.eq(M.type_show(x), M.type_show(y)), same_substitutions(xs, ys)))
    case T.RowSubstitution{a, x} <> xs T.RowSubstitution{b, y} <> ys:
      Bool.and(Nat.is_eq(a, b), Bool.and(String.eq(M.row_show(x), M.row_show(y)), same_substitutions(xs, ys)))
    case _ _: False{}

def same_definitions(left: List<&2, I.Definition>, right: List<&2, I.Definition>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case I.Definition{a, I.Inference{x, coverage_a, exits_a, reflections_a}} <> xs I.Definition{b, I.Inference{y, coverage_b, exits_b, reflections_b}} <> ys:
      Bool.and(M.name_equal(a, b), Bool.and(String.eq(M.type_show(x), M.type_show(y)), same_definitions(xs, ys)))
    case _ _: False{}

def same_result(serial: Result<&2, &2, M.Diagnostic, G.Environment>, parallel: Result<&2, &2, M.Diagnostic, G.Environment>) -> Bool:
  match serial parallel:
    case Done{G.Environment{serial_bindings, serial_definitions, I.State{+serial_substitutions, serial_next, serial_annotations}}} Done{G.Environment{parallel_bindings, parallel_definitions, I.State{+parallel_substitutions, parallel_next, parallel_annotations}}}:
      Bool.and(Nat.is_eq(serial_next, parallel_next), Bool.and(Nat.is_eq(T.substitution_count(serial_substitutions), T.substitution_count(parallel_substitutions)), Bool.and(same_substitutions(T.substitution_history(serial_substitutions), T.substitution_history(parallel_substitutions)), same_definitions(serial_definitions, parallel_definitions))))
    case Fail{M.Diagnostic{a, b, c}} Fail{M.Diagnostic{x, y, z}}:
      Bool.and(String.eq(a, x), Bool.and(String.eq(b, y), String.eq(c, z)))
    case _ _: False{}

def independent() -> Bool:
  +declarations = {[G.ConstantDeclaration{M.Constant{"first", False{}, None{}, M.U32Expr{1}}}, G.ConstantDeclaration{M.Constant{"second", False{}, None{}, M.BoolExpr{True{}}}}] : List<&2, G.Declaration>}
  +state = {I.State{T.empty(), G.initial_next(declarations, 0n), MTip{}} : I.State}
  +environment = {G.Environment{G.initial_bindings(declarations, 0n), Nil{}, state} : G.Environment}
  same_result(G.infer_component(G.names(declarations), declarations, environment, Nil{}, Nil{}, Nil{}), ParallelInfer.infer_component(declarations, environment, Nil{}, Nil{}, Nil{}))

def shared_case(imported: I.Binding, first: Maybe<&2, M.Ty>, second: Maybe<&2, M.Ty>, +operations: List<&2, M.Operation>) -> Bool:
  +declarations = {[G.ConstantDeclaration{M.Constant{"first", False{}, first, M.ConstantExpr{"shared"}}}, G.ConstantDeclaration{M.Constant{"second", False{}, second, M.ConstantExpr{"shared"}}}] : List<&2, G.Declaration>}
  +state = {I.State{T.empty(), G.initial_next(declarations, 101n), MTip{}} : I.State}
  +environment = {G.Environment{List.append(&2, I.Binding, G.initial_bindings(declarations, 101n), [imported]), Nil{}, state} : G.Environment}
  same_result(G.infer_component(G.names(declarations), declarations, environment, operations, Nil{}, Nil{}), ParallelInfer.infer_component(declarations, environment, operations, Nil{}, Nil{}))

def read_only() -> Bool:
  shared_case(I.Binding{"shared", M.ProductTy{[M.VariableTy{100n}]}, Nil{}}, None{}, None{}, Nil{})

def writable_type() -> Bool:
  shared_case(I.Binding{"shared", M.VariableTy{100n}, Nil{}}, Some{M.U32Ty{}}, Some{M.BoolTy{}}, Nil{})

def writable_row() -> Bool:
  +read = {M.TypeId{"ops", "read"} : M.TypeId}
  +write = {M.TypeId{"ops", "write"} : M.TypeId}
  +operations = {[M.Operation{read, M.UnitTy{}, M.UnitTy{}}, M.Operation{write, M.UnitTy{}, M.UnitTy{}}] : List<&2, M.Operation>}
  shared_case(I.Binding{"shared", M.ProviderTy{read, M.EffectRow{Nil{}, M.RowVariable{100n}}}, Nil{}}, Some{M.ProviderTy{read, M.EffectRow{Nil{}, M.ClosedRow{}}}}, Some{M.ProviderTy{read, M.EffectRow{[write], M.ClosedRow{}}}}, operations)

def indexed_version_order(found: Result<&2, &2, M.Diagnostic, List<&2, Nat>>) -> Bool:
  match found:
    case Done{1n <> 2n <> 3n <> 4n <> Nil{}}: True{}
    case _: False{}

def indexed_versions() -> Bool:
  +substitutions = T.from_list([T.Substitution{0n, M.VariableTy{1n}}, T.RowSubstitution{0n, M.EffectRow{Nil{}, M.RowVariable{2n}}}, T.Substitution{0n, M.VariableTy{3n}}, T.RowSubstitution{0n, M.EffectRow{Nil{}, M.RowVariable{4n}}}])
  indexed_version_order(ParallelInfer.indexed_neighbors(substitutions, 0n))

def closure_cycle_result(found: Result<&2, &2, M.Diagnostic, List<&2, Nat>>) -> Bool:
  match found:
    case Done{+visited}:
      Bool.and(Nat.is_eq(List.length(&2, Nat, visited), 4n), Bool.and(T.contains(visited, 0n), Bool.and(T.contains(visited, 1n), Bool.and(T.contains(visited, 2n), T.contains(visited, 3n)))))
    case _: False{}

def indexed_cycle() -> Bool:
  +substitutions = T.from_list([T.Substitution{0n, M.ProductTy{[M.VariableTy{1n}, M.VariableTy{2n}]}}, T.Substitution{1n, M.VariableTy{3n}}, T.Substitution{2n, M.VariableTy{3n}}, T.Substitution{3n, M.VariableTy{0n}}])
  closure_cycle_result(ParallelInfer.read_closure(12n, ParallelInfer.ClosureStep{[0n], Nil{}}, substitutions))

def valid() -> Bool:
  Bool.and(independent(), Bool.and(read_only(), Bool.and(writable_type(), Bool.and(writable_row(), Bool.and(indexed_versions(), indexed_cycle())))))

def finish(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "parallel inference regression failed")

def main() -> IO(Unit):
  finish(valid())
