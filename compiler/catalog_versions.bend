import Base
import ./model.bend as M
import ./native_cache_keys.bend as K
import ./native_response.bend as R
import ./index.bend as Index

# Exact catalog comparison happens once per revision. A token is only retained
# when the same nominal identity has byte-for-byte equal encoded declaration
# words. Tokens are monotonic across committed revisions, so no ABA reuse is
# possible after a deletion or replacement.
type TypeVersion is Data:
  TypeVersion{words: List<&2, U32>, token: Nat}

type TypeVersions is Data:
  TypeVersions{entries: Map<&2, Map<&2, TypeVersion>>, next: Nat}

type Revision is Data:
  Revision{
    operations: List<&2, U32>,
    ordered_types: List<&2, Nat>,
    types: Map<&2, Map<&2, TypeVersion>>,
    next: Nat
  }

type Prepared is Data:
  Prepared{revision: Revision, same_operations: Bool}

def entry(index: Map<&2, Map<&2, TypeVersion>>, identity: M.TypeId) -> Maybe<&2, TypeVersion>:
  M.TypeId{module_name, declaration} = identity
  nested = Index.get(Map<&2, TypeVersion>, index, module_name, Map.new(&2, TypeVersion))
  Index.find(TypeVersion, nested, declaration)

def put(+index: Map<&2, Map<&2, TypeVersion>>, identity: M.TypeId, value: TypeVersion) -> Map<&2, Map<&2, TypeVersion>>:
  M.TypeId{+module_name, declaration} = identity
  nested = Index.get(Map<&2, TypeVersion>, index, module_name, Map.new(&2, TypeVersion))
  Map.set(&2, Map<&2, TypeVersion>, index, module_name, Map.set(&2, TypeVersion, nested, declaration, value))

def select_same(same: Bool, words: List<&2, U32>, token: Nat, +next: Nat) -> TypeVersion & Nat:
  match same:
    case True{}:
      (TypeVersion{words, token}, next)
    case False{}:
      (TypeVersion{words, next}, 1n+next)

def select(found: Maybe<&2, TypeVersion>, +words: List<&2, U32>, +next: Nat) -> TypeVersion & Nat:
  match found:
    case Some{TypeVersion{prior, token}}:
      select_same(K.same(prior, words), words, token, next)
    case None{}:
      (TypeVersion{words, next}, 1n+next)

def previous_types(previous: Maybe<&2, Revision>) -> Map<&2, Map<&2, TypeVersion>>:
  match previous:
    case None{}:
      Map.new(&2, Map<&2, TypeVersion>)
    case Some{Revision{operations, ordered_types, types, next}}:
      types

def previous_next(previous: Maybe<&2, Revision>) -> Nat:
  match previous:
    case None{}:
      1n
    case Some{Revision{operations, ordered_types, types, next}}:
      next

def insert_selected(selection: TypeVersion & Nat, entries: Map<&2, Map<&2, TypeVersion>>, identity: M.TypeId) -> TypeVersions:
  (selected, following) = selection
  TypeVersions{put(entries, identity, selected), following}

def types_go(pending: List<&2, M.DataType>, +previous: Map<&2, Map<&2, TypeVersion>>, result: TypeVersions) -> Result<&2, &2, M.Diagnostic, TypeVersions>:
  match pending:
    case Nil{}:
      Done{result}
    case +declaration <> tail:
      M.DataType{+identity, parameters, constructors} = declaration
      TypeVersions{entries, next} = result
      do Result<&2, &2, M.Diagnostic, TypeVersions>:
        words : List<&2, U32> <- K.encode([K.DataTypes{[declaration]}])
        types_go(tail, previous, insert_selected(select(entry(previous, identity), words, next), entries, identity))

def operations_match(previous: Maybe<&2, Revision>, current: List<&2, U32>) -> Bool:
  match previous:
    case None{}:
      False{}
    case Some{Revision{operations, ordered_types, types, next}}:
      K.same(operations, current)

def make_prepared(versions: TypeVersions, previous: Maybe<&2, Revision>, +operation_words: List<&2, U32>, ordered_types: List<&2, Nat>) -> Prepared:
  TypeVersions{entries, next} = versions
  Prepared{Revision{operation_words, ordered_types, entries, next}, operations_match(previous, operation_words)}

def version_entries(value: TypeVersions) -> Map<&2, Map<&2, TypeVersion>>:
  TypeVersions{entries, next} = value
  entries

def token(found: Maybe<&2, TypeVersion>, identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, Nat>:
  match found:
    case Some{TypeVersion{words, value}}:
      Done{value}
    case None{}:
      Fail{M.Diagnostic{"internal_error", M.type_id_show(identity), "planned group type is absent from validated catalog"}}

def tokens(pending: List<&2, M.DataType>, +versions: Map<&2, Map<&2, TypeVersion>>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match pending:
    case Nil{}:
      Done{Nil{}}
    case M.DataType{+identity, parameters, constructors} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        head : Nat <- token(entry(versions, identity), identity)
        rest : List<&2, Nat> <- tokens(tail, versions)
        return head <> rest

def prepare(+types: List<&2, M.DataType>, operations: List<&2, M.Operation>, +previous: Maybe<&2, Revision>) -> Result<&2, &2, M.Diagnostic, Prepared>:
  do Result<&2, &2, M.Diagnostic, Prepared>:
    +operation_words : List<&2, U32> <- K.operations(operations)
    +versions : TypeVersions <- types_go(types, previous_types(previous), TypeVersions{Map.new(&2, Map<&2, TypeVersion>), previous_next(previous)})
    ordered : List<&2, Nat> <- tokens(types, version_entries(versions))
    return make_prepared(versions, previous, operation_words, ordered)

def prepared_revision(prepared: Prepared) -> Revision:
  Prepared{revision, same_operations} = prepared
  revision

def prepared_same_operations(prepared: Prepared) -> Bool:
  Prepared{revision, same_operations} = prepared
  same_operations

def group_key(module: M.Module, revision: Revision) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  M.Module{constants, functions, types, operations} = module
  Revision{operation_words, ordered_types, versions, next} = revision
  do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
    selected : List<&2, Nat> <- tokens(types, versions)
    K.encode([K.Constants{constants}, K.Functions{functions}, K.Field{R.Naturals{selected}}])

# Shape seeds were checked against the original module. A changed specialized
# catalog cannot reuse that proof merely because a particular body is equal.
def encoded_same(result: Result<&2, &2, M.Diagnostic, List<&2, U32>>, expected: List<&2, U32>) -> Bool:
  match result:
    case Fail{diagnostic}:
      False{}
    case Done{words}:
      K.same(words, expected)

def original_type_words_if(same: Bool, declaration: M.DataType, words: List<&2, U32>) -> Bool:
  match same:
    case False{}:
      False{}
    case True{}:
      encoded_same(K.encode([K.DataTypes{[declaration]}]), words)

def original_type_matches(found: Maybe<&2, TypeVersion>, declaration: M.DataType, expected: Nat) -> Bool:
  match found:
    case None{}:
      False{}
    case Some{TypeVersion{words, token}}:
      original_type_words_if(Nat.is_eq(token, expected), declaration, words)

def original_types_match(pending: List<&2, M.DataType>, ordered: List<&2, Nat>, +versions: Map<&2, Map<&2, TypeVersion>>, matching: Bool) -> Bool:
  match pending ordered matching:
    case _ _ False{}:
      False{}
    case Nil{} Nil{} True{}:
      True{}
    case M.DataType{+identity, parameters, constructors} <> tail expected <> rest True{}:
      +declaration : M.DataType = M.DataType{identity, parameters, constructors}
      original_types_match(tail, rest, versions, original_type_matches(entry(versions, identity), declaration, expected))
    case _ _ _:
      False{}

def original_operations_match(result: Result<&2, &2, M.Diagnostic, List<&2, U32>>, current: List<&2, U32>, types: List<&2, M.DataType>, ordered: List<&2, Nat>, versions: Map<&2, Map<&2, TypeVersion>>) -> Bool:
  original_types_match(types, ordered, versions, encoded_same(result, current))

def original_matches(module: M.Module, revision: Revision) -> Bool:
  M.Module{constants, functions, types, operations} = module
  Revision{operation_words, ordered_types, versions, next} = revision
  original_operations_match(K.operations(operations), operation_words, types, ordered_types, versions)
