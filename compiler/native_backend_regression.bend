import Base
import ./model.bend as M
import ./type_data.bend as D
import ./residual_scheme_regression.bend as ResidualScheme
import ./frontier_reuse_regression.bend as FrontierReuse
import ./pending_cache_regression.bend as PendingCache
import ./global_bindings_regression.bend as GlobalBindings
import ./parallel_infer_regression.bend as ParallelInferRegression
import ./staging_boundary_regression.bend as StagingBoundary
import ./types.bend as Types

def maybe_declaration() -> M.DataType:
  M.DataType{M.TypeId{"regression", "Maybe"}, 1n, [M.Constructor{"Some", Some{M.ParameterTy{0n}}, Nil{}}, M.Constructor{"Nothing", None{}, Nil{}}]}

def payload_text(payload: Maybe<&2, M.Ty>) -> String:
  match payload:
    case None{}:
      "none"
    case Some{ty}:
      M.type_show(ty)

def definition_text(found: Maybe<&2, D.ConstructorDefinition>) -> String:
  match found:
    case None{}:
      "missing"
    case Some{D.ConstructorDefinition{identity, parameters, payload}}:
      M.type_id_show(identity) ++ " params=" ++ Nat.show(parameters) ++ " payload=" ++ payload_text(payload)

def instance_valid(found: Result<&2, &2, M.Diagnostic, D.ConstructorType>) -> Bool:
  match found:
    case Done{D.ConstructorType{M.AppliedTy{identity, M.VariableTy{index} <> Nil{}}, None{}, next}}:
      Bool.and(M.type_id_equal(identity, M.TypeId{"regression", "Maybe"}), Bool.and(Nat.is_eq(index, 7n), Nat.is_eq(next, 8n)))
    case _:
      False{}

type NestedRecord is Data:
  NestedRecord{primary: M.TypeId, optional: Maybe<&2, M.TypeId>}

def repeat(-A: Data, count: Nat, +value: A) -> List<&2, A>:
  match count:
    case 0n:
      Nil{}
    case 1n+remaining:
      value <> repeat(A, remaining, value)

def nested_text(value: Maybe<&2, NestedRecord>) -> String:
  match value:
    case Some{NestedRecord{primary, Some{optional}}}:
      M.type_id_show(primary) ++ "," ++ M.type_id_show(optional)
    case _:
      "missing"

def nested_list_valid(values: List<&2, Maybe<&2, NestedRecord>>) -> Bool:
  match values:
    case Nil{}:
      True{}
    case value <> rest:
      Bool.and(String.eq(nested_text(value), "shared::Nested,shared::Nested"), nested_list_valid(rest))

# The generic recursive boundary retains boxed aliases. Both the outer list
# and its nested record payloads are consumed while another owner remains.
def shared_records_valid() -> Bool:
  +identity = {M.TypeId{"shared", "Nested"} : M.TypeId}
  +copies = repeat(Maybe<&2, NestedRecord>, 3n, Some{NestedRecord{identity, Some{identity}}})
  Bool.and(nested_list_valid(copies), nested_list_valid(copies))

# Exercise nested continuation frames and ordered duplicate effect labels in
# the native backend. The final result consumes both saved siblings and rows.
def flat_resolver_result(result: Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>, +get: M.TypeId, put: M.TypeId) -> Bool:
  match result:
    case Done{M.FunctionTy{M.U32Ty{}, M.ProductTy{M.ArrayTy{M.BoolTy{}} <> M.AppliedTy{M.TypeId{"regression", "Box"}, M.U32Ty{} <> Nil{}} <> Nil{}}, M.EffectRow{first <> second <> third <> Nil{}, M.ClosedRow{}}} <> Nil{}}:
      Bool.and(M.type_id_equal(first, get), Bool.and(M.type_id_equal(second, get), M.type_id_equal(third, put)))
    case _:
      False{}

def flat_resolver_valid() -> Bool:
  +get = {M.TypeId{"regression", "get"} : M.TypeId}
  +put = {M.TypeId{"regression", "put"} : M.TypeId}
  +substitutions = Types.from_list([Types.Substitution{0n, M.U32Ty{}}, Types.Substitution{1n, M.BoolTy{}}, Types.RowSubstitution{7n, M.EffectRow{[put], M.ClosedRow{}}}])
  +source = {M.FunctionTy{M.VariableTy{0n}, M.ProductTy{[M.ArrayTy{M.VariableTy{1n}}, M.AppliedTy{M.TypeId{"regression", "Box"}, [M.VariableTy{0n}]}]}, M.EffectRow{[get, get], M.RowVariable{7n}}} : M.Ty}
  flat_resolver_result(Types.resolve_work(substitutions, 64n, Types.OneType{source}), get, put)

# Bend 2.0.5 sealed this polymorphic Some payload, then unboxed its record with
# term_loc instead of ctr_take. Keep the actual constructor lookup as a guard.
def check_existing() -> Bool:
  Bool.and(GlobalBindings.valid(), Bool.and(FrontierReuse.valid(), Bool.and(PendingCache.valid(), Bool.and(flat_resolver_valid(), Bool.and(ResidualScheme.valid(), Bool.and(shared_records_valid(), Bool.and(String.eq(definition_text(D.constructor([maybe_declaration()], "Nothing")), "regression::Maybe params=1 payload=none"), Bool.and(String.eq(definition_text(D.constructor([maybe_declaration()], "Some")), "regression::Maybe params=1 payload='0"), instance_valid(D.instantiate(Some{D.ConstructorDefinition{M.TypeId{"regression", "Maybe"}, 1n, None{}}}, "Nothing", 7n, "native backend regression"))))))))))

def check() -> Bool:
  Bool.and(StagingBoundary.valid(), Bool.and(ParallelInferRegression.valid(), check_existing()))

def finish(valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "native backend regression: ownership, resolver, frontier reuse, or pending cache check failed")

def main() -> IO(Unit):
  finish(check())
