import Base
import ./model.bend as M
import ./types.bend as T
import ./type_data.bend as TD
import ./infer.bend as I
import ./globals.bend as G
import ./check.bend as Check
import ./dependency.bend as D
import ./effects.bend as E
import ./index.bend as Index

type Job is Data:
  Job{members: List<&2, String>, dependencies: List<&2, String>, type_dependencies: List<&2, M.TypeId>}

type InterfaceKind is Data:
  FunctionInterface{}
  ConstantInterface{}

# ParameterTy indices bind within this interface, never within another job's
# inference state. An interface contains no unresolved monomorphic variables.
type Interface is Data:
  Interface{name: String, kind: InterfaceKind, template: M.Ty, parameters: Nat, effects: List<&2, M.Effect>}

type CheckedGroup is Data:
  CheckedGroup{checked: M.CheckedModule, interfaces: List<&2, Interface>}

def interface_names(interfaces: List<&2, Interface>) -> List<&2, String>:
  match interfaces:
    case Nil{}:
      Nil{}
    case Interface{name, kind, template, parameters, effects} <> tail:
      name <> interface_names(tail)

def interface_functions(interfaces: List<&2, Interface>) -> List<&2, String>:
  match interfaces:
    case Nil{}:
      Nil{}
    case Interface{name, FunctionInterface{}, template, parameters, effects} <> tail:
      name <> interface_functions(tail)
    case head <> tail:
      interface_functions(tail)

def indices(count: Nat, +start: Nat) -> List<&2, Nat>:
  match count:
    case 0n:
      Nil{}
    case 1n+rest:
      start <> indices(rest, 1n+start)

def same_storage(left: M.Storage, right: M.Storage) -> Bool:
  match left right:
    case M.Component{} M.Component{}:
      True{}
    case M.Resource{} M.Resource{}:
      True{}
    case _ _:
      False{}

def interface_requirement(consistent: Bool, access: M.Access, identity: M.TypeId, types: List<&2, M.DataType>, subject: String) -> Result<&2, &2, M.Diagnostic, I.Requirement>:
  match consistent:
    case False{}:
      Fail{M.Diagnostic{"invalid_interface", subject, "dependency storage classification differs from the current module"}}
    case True{}:
      +target = identity
      do Result<&2, &2, M.Diagnostic, I.Requirement>:
        ty : M.Ty <- TD.storage_type(TD.lookup(types, target), target)
        return I.AccessRequirement{access, ty}

def descriptor_storage(descriptor: M.Descriptor) -> M.Storage:
  M.Descriptor{identity, storage} = descriptor
  storage

def effect_requirements(effects: List<&2, M.Effect>, +descriptors: List<&2, M.Descriptor>, +types: List<&2, M.DataType>, +subject: String) -> Result<&2, &2, M.Diagnostic, List<&2, I.Requirement>>:
  match effects:
    case Nil{}:
      Done{Nil{}}
    case M.Effect{+access, M.Descriptor{+identity, storage}} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, I.Requirement>>:
        +registered : M.Descriptor <- Check.lookup_descriptor(descriptors, identity)
        valid : M.Effect <- Check.valid_access(access, registered)
        requirement : I.Requirement <- interface_requirement(same_storage(storage, descriptor_storage(registered)), access, identity, types, subject)
        rest : List<&2, I.Requirement> <- effect_requirements(tail, descriptors, types, subject)
        return requirement <> rest

def valid_interface_kind(kind: InterfaceKind, template: M.Ty, parameters: Nat, effects: List<&2, M.Effect>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match kind template parameters effects:
    case FunctionInterface{} M.FunctionTy{parameter, result} _ Nil{}:
      Done{Unit{}}
    case FunctionInterface{} M.FunctionTy{parameter, result} 0n _:
      Done{Unit{}}
    case ConstantInterface{} _ _ Nil{}:
      Done{Unit{}}
    case _ _ _ _:
      Fail{M.Diagnostic{"invalid_interface", subject, "dependencies require pure constants and functions with closed monomorphic effects"}}

def import_interfaces(interfaces: List<&2, Interface>, +descriptors: List<&2, M.Descriptor>, +types: List<&2, M.DataType>, +start: Nat) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match interfaces:
    case Nil{}:
      Done{G.Environment{Nil{}, Nil{}, I.State{Nil{}, start}}}
    case Interface{+name, +kind, +template, +parameters, +effects} <> tail:
      do Result<&2, &2, M.Diagnostic, G.Environment>:
        valid : Unit <- TD.validate_work(Nat.mul(256n, 256n), T.OneType{template}, Some{parameters}, descriptors, types, name)
        compatible : Unit <- valid_interface_kind(kind, template, parameters, effects, name)
        +ty : M.Ty <- T.parameters(TD.fresh_arguments(parameters, start), 0n, template)
        requirements : List<&2, I.Requirement> <- effect_requirements(effects, descriptors, types, name)
        +rest : G.Environment <- import_interfaces(tail, descriptors, types, Nat.add(start, parameters))
        return G.Environment{I.Binding{name, ty, indices(parameters, start)} <> G.env_bindings(rest), I.Definition{name, I.Inference{ty, requirements, Nil{}, Nil{}, Nil{}}} <> G.env_definitions(rest), G.env_state(rest)}

def template_type(variables: List<&2, Nat>, +index: Nat, ty: M.Ty) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match variables:
    case Nil{}:
      Done{ty}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, M.Ty>:
        replaced : M.Ty <- T.replace(ty, head, M.ParameterTy{index})
        template_type(tail, 1n+index, replaced)

def access_rank(access: M.Access) -> Nat:
  match access:
    case M.Read{}:
      0n
    case M.Write{}:
      1n
    case M.Insert{}:
      2n

def effect_le(left: M.Effect, right: M.Effect) -> Bool:
  M.Effect{la, +ld} = left
  M.Effect{ra, +rd} = right
  Bool.and(E.descriptor_le(ld, rd), Bool.or(Bool.not(E.descriptor_le(rd, ld)), Nat.is_le(access_rank(la), access_rank(ra))))

def closed_interface(open: List<&2, Nat>, +variables: List<&2, Nat>, name: String, kind: InterfaceKind, ty: M.Ty, effects: List<&2, M.Effect>) -> Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
  match open:
    case Nil{}:
      do Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
        template : M.Ty <- template_type(variables, 0n, ty)
        return [Interface{name, kind, template, List.length(&2, Nat, variables), List.sort(~M.Effect, ~effect_le, effects)}]
    case head <> tail:
      # All callers of effectful monomorphic members are in this same job.
      # Keep their checked types, but never export an open inference variable.
      Done{Nil{}}

def export_interface(name: String, kind: InterfaceKind, +ty: M.Ty, variables: List<&2, Nat>, effects: List<&2, M.Effect>) -> Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
  do Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
    +free : List<&2, Nat> <- T.free(ty)
    closed_interface(T.difference(free, variables), free, name, kind, ty, effects)

def function_interfaces(functions: List<&2, M.CheckedFunction>) -> Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
  match functions:
    case Nil{}:
      Done{Nil{}}
    case M.CheckedFunction{function, M.Signature{name, parameter, result, variables}, effects} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
        head : List<&2, Interface> <- export_interface(name, FunctionInterface{}, M.FunctionTy{parameter, result}, variables, effects)
        rest : List<&2, Interface> <- function_interfaces(tail)
        return List.append(&2, Interface, head, rest)

def constant_interfaces(constants: List<&2, M.CheckedConstant>) -> Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
  match constants:
    case Nil{}:
      Done{Nil{}}
    case M.CheckedConstant{M.Constant{name, exported, annotation, value}, ty, variables} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
        head : List<&2, Interface> <- export_interface(name, ConstantInterface{}, ty, variables, Nil{})
        rest : List<&2, Interface> <- constant_interfaces(tail)
        return List.append(&2, Interface, head, rest)

def checked_group(+checked: M.CheckedModule) -> Result<&2, &2, M.Diagnostic, CheckedGroup>:
  M.CheckedModule{constants, functions, types} = checked
  do Result<&2, &2, M.Diagnostic, CheckedGroup>:
    fns : List<&2, Interface> <- function_interfaces(functions)
    consts : List<&2, Interface> <- constant_interfaces(constants)
    return CheckedGroup{checked, List.append(&2, Interface, fns, consts)}

def check_group(+module: M.Module, +dependencies: List<&2, Interface>) -> Result<&2, &2, M.Diagnostic, CheckedGroup>:
  M.Module{+descriptors, constants, functions, +types} = module
  +declarations = List.append(&2, G.Declaration, G.function_declarations(functions), G.constant_declarations(constants))
  do Result<&2, &2, M.Diagnostic, CheckedGroup>:
    graph : List<&2, D.Node> <- Check.module_graph(module)
    unique : Unit <- Check.unique_names(List.append(&2, String, interface_names(dependencies), List.append(&2, String, G.names(declarations), Check.all_constructor_names(types))))
    imported : G.Environment <- import_interfaces(dependencies, descriptors, types, 0n)
    environment : G.Environment <- G.infer_with(declarations, graph, descriptors, types, imported, interface_functions(dependencies))
    checked : M.CheckedModule <- Check.finish(module, environment)
    checked_group(checked)

type Usage is Data:
  Usage{effectful: Bool, nominals: List<&2, M.TypeId>}

type UsageWork is Data:
  ExpressionUsage{value: M.Expr}
  ArmsUsage{values: List<&2, M.MatchArm<M.Expr>>}
  PatternUsage{value: M.Pattern}
  TypeUsage{value: M.Ty}
  TypesUsage{values: List<&2, M.Ty>}

def contains_type(identities: List<&2, M.TypeId>, +identity: M.TypeId) -> Bool:
  match identities:
    case Nil{}:
      False{}
    case head <> tail:
      Bool.or(M.type_id_equal(head, identity), contains_type(tail, identity))

def put_type_if(present: Bool, identities: List<&2, M.TypeId>, identity: M.TypeId) -> List<&2, M.TypeId>:
  match present:
    case True{}:
      identities
    case False{}:
      identity <> identities

def union_types(left: List<&2, M.TypeId>, +right: List<&2, M.TypeId>) -> List<&2, M.TypeId>:
  match left:
    case Nil{}:
      right
    case +head <> tail:
      union_types(tail, put_type_if(contains_type(right, head), right, head))

def combine_usage(left: Usage, right: Usage) -> Usage:
  Usage{le, lt} = left
  Usage{re, rt} = right
  Usage{Bool.or(le, re), union_types(lt, rt)}

def mark_effect(usage: Usage) -> Usage:
  Usage{effectful, nominals} = usage
  Usage{True{}, nominals}

def constructor_usage(found: Maybe<&2, M.TypeId>) -> Usage:
  match found:
    case None{}:
      Usage{False{}, Nil{}}
    case Some{identity}:
      Usage{False{}, [identity]}

def constructor_index_entries(constructors: List<&2, M.Constructor>, +identity: M.TypeId, index: Map<&2, M.TypeId>) -> Map<&2, M.TypeId>:
  match constructors:
    case Nil{}:
      index
    case M.Constructor{name, payload} <> tail:
      constructor_index_entries(tail, identity, Map.set(&2, M.TypeId, index, name, identity))

def constructor_index(types: List<&2, M.DataType>, index: Map<&2, M.TypeId>) -> Map<&2, M.TypeId>:
  match types:
    case Nil{}:
      index
    case M.DataType{identity, parameters, constructors} <> tail:
      constructor_index(tail, constructor_index_entries(constructors, identity, index))

def optional_type(ty: Maybe<&2, M.Ty>) -> M.Ty:
  match ty:
    case None{}:
      M.UnitTy{}
    case Some{value}:
      value

def optional_pattern(pattern: Maybe<&2, M.Pattern>) -> M.Pattern:
  match pattern:
    case None{}:
      M.WildcardPattern{}
    case Some{value}:
      value

def usage(+fuel: Nat, work: UsageWork, +types: Map<&2, M.TypeId>) -> Result<&2, &2, M.Diagnostic, Usage>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"expression_complexity", "inference", "dependency metadata exceeded compiler traversal limit"}}
    case 1n+rest ExpressionUsage{M.ReadExpr{identity}}:
      Done{Usage{True{}, [identity]}}
    case 1n+rest ExpressionUsage{M.WriteExpr{value}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        found : Usage <- usage(rest, ExpressionUsage{value}, types)
        return mark_effect(found)
    case 1n+rest ExpressionUsage{M.InsertExpr{value}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        found : Usage <- usage(rest, ExpressionUsage{value}, types)
        return mark_effect(found)
    case 1n+rest ExpressionUsage{M.ConstructorRefExpr{constructor}}:
      Done{constructor_usage(Index.find(M.TypeId, types, constructor))}
    case 1n+rest ExpressionUsage{M.ConstructExpr{constructor, payload}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        nested : Usage <- usage(rest, ExpressionUsage{D.payload_expression(payload)}, types)
        return combine_usage(constructor_usage(Index.find(M.TypeId, types, constructor)), nested)
    case 1n+rest ExpressionUsage{M.LambdaExpr{identity, parameter, p, r, body}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        annotations : Usage <- usage(rest, TypesUsage{[optional_type(p), optional_type(r)]}, types)
        nested : Usage <- usage(rest, ExpressionUsage{body}, types)
        return combine_usage(annotations, nested)
    case 1n+rest ExpressionUsage{M.ApplyExpr{callee, argument}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, ExpressionUsage{callee}, types)
        b : Usage <- usage(rest, ExpressionUsage{argument}, types)
        return combine_usage(a, b)
    case 1n+rest ExpressionUsage{M.CallExpr{callee, argument}}:
      usage(rest, ExpressionUsage{argument}, types)
    case 1n+rest ExpressionUsage{M.ScalarExpr{operator, left, right}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, ExpressionUsage{left}, types)
        b : Usage <- usage(rest, ExpressionUsage{right}, types)
        return combine_usage(a, b)
    case 1n+rest ExpressionUsage{M.LetExpr{name, value, body}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, ExpressionUsage{value}, types)
        b : Usage <- usage(rest, ExpressionUsage{body}, types)
        return combine_usage(a, b)
    case 1n+rest ExpressionUsage{M.UseExpr{name, value, body}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, ExpressionUsage{value}, types)
        b : Usage <- usage(rest, ExpressionUsage{body}, types)
        return combine_usage(a, b)
    case 1n+rest ExpressionUsage{M.SequenceExpr{first, next}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, ExpressionUsage{first}, types)
        b : Usage <- usage(rest, ExpressionUsage{next}, types)
        return combine_usage(a, b)
    case 1n+rest ExpressionUsage{M.IfExpr{condition, consequent, alternative}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, ExpressionUsage{condition}, types)
        b : Usage <- usage(rest, ExpressionUsage{consequent}, types)
        c : Usage <- usage(rest, ExpressionUsage{alternative}, types)
        return combine_usage(a, combine_usage(b, c))
    case 1n+rest ExpressionUsage{M.MatchExpr{value, arms}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, ExpressionUsage{value}, types)
        b : Usage <- usage(rest, ArmsUsage{arms}, types)
        return combine_usage(a, b)
    case 1n+rest ExpressionUsage{M.GuardExpr{pattern, value, alternative, body}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        p : Usage <- usage(rest, PatternUsage{pattern}, types)
        a : Usage <- usage(rest, ExpressionUsage{value}, types)
        b : Usage <- usage(rest, ExpressionUsage{alternative}, types)
        c : Usage <- usage(rest, ExpressionUsage{body}, types)
        return combine_usage(p, combine_usage(a, combine_usage(b, c)))
    case 1n+rest ExpressionUsage{M.BlockExpr{label, body}}:
      usage(rest, ExpressionUsage{body}, types)
    case 1n+rest ExpressionUsage{M.ReturnExpr{label, value}}:
      usage(rest, ExpressionUsage{value}, types)
    case 1n+rest ExpressionUsage{M.SourceExpr{offset, annotation, value}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, TypeUsage{optional_type(annotation)}, types)
        b : Usage <- usage(rest, ExpressionUsage{value}, types)
        return combine_usage(a, b)
    case 1n+rest ArmsUsage{M.MatchArm{pattern, body} <> tail}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        p : Usage <- usage(rest, PatternUsage{pattern}, types)
        b : Usage <- usage(rest, ExpressionUsage{body}, types)
        r : Usage <- usage(rest, ArmsUsage{tail}, types)
        return combine_usage(p, combine_usage(b, r))
    case 1n+rest PatternUsage{M.ConstructorPattern{constructor, payload}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        nested : Usage <- usage(rest, PatternUsage{optional_pattern(payload)}, types)
        return combine_usage(constructor_usage(Index.find(M.TypeId, types, constructor)), nested)
    case 1n+rest TypeUsage{M.NominalTy{identity}}:
      Done{Usage{False{}, [identity]}}
    case 1n+rest TypeUsage{M.AppliedTy{identity, arguments}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        nested : Usage <- usage(rest, TypesUsage{arguments}, types)
        return combine_usage(Usage{False{}, [identity]}, nested)
    case 1n+rest TypeUsage{M.FunctionTy{parameter, result}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, TypeUsage{parameter}, types)
        b : Usage <- usage(rest, TypeUsage{result}, types)
        return combine_usage(a, b)
    case 1n+rest TypesUsage{head <> tail}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, TypeUsage{head}, types)
        b : Usage <- usage(rest, TypesUsage{tail}, types)
        return combine_usage(a, b)
    case 1n+rest _:
      Done{Usage{False{}, Nil{}}}

type DeclarationUsage is Data:
  DeclarationUsage{name: String, usage: Usage}

def declaration_usage(declaration: G.Declaration, +types: Map<&2, M.TypeId>) -> Result<&2, &2, M.Diagnostic, DeclarationUsage>:
  match declaration:
    case G.FunctionDeclaration{M.Function{name, exported, parameter, p, r, body}}:
      do Result<&2, &2, M.Diagnostic, DeclarationUsage>:
        annotations : Usage <- usage(Nat.mul(256n, 256n), TypesUsage{[optional_type(p), optional_type(r)]}, types)
        nested : Usage <- usage(Nat.mul(256n, 256n), ExpressionUsage{body}, types)
        return DeclarationUsage{name, combine_usage(annotations, nested)}
    case G.ConstantDeclaration{M.Constant{name, exported, annotation, value}}:
      do Result<&2, &2, M.Diagnostic, DeclarationUsage>:
        annotations : Usage <- usage(Nat.mul(256n, 256n), TypeUsage{optional_type(annotation)}, types)
        nested : Usage <- usage(Nat.mul(256n, 256n), ExpressionUsage{value}, types)
        return DeclarationUsage{name, combine_usage(annotations, nested)}

def declaration_usages(declarations: List<&2, G.Declaration>, +types: Map<&2, M.TypeId>) -> Result<&2, &2, M.Diagnostic, List<&2, DeclarationUsage>>:
  match declarations:
    case Nil{}:
      Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, DeclarationUsage>>:
        found : DeclarationUsage <- declaration_usage(head, types)
        rest : List<&2, DeclarationUsage> <- declaration_usages(tail, types)
        return found <> rest

def effect_seeds(usages: List<&2, DeclarationUsage>) -> List<&2, String>:
  match usages:
    case Nil{}:
      Nil{}
    case DeclarationUsage{name, Usage{True{}, nominals}} <> tail:
      name <> effect_seeds(tail)
    case head <> tail:
      effect_seeds(tail)

type TypeDependencies is Data:
  TypeDependencies{identity: M.TypeId, references: List<&2, M.TypeId>}

def usage_types(found: Usage) -> List<&2, M.TypeId>:
  Usage{effectful, nominals} = found
  nominals

def constructor_types(constructors: List<&2, M.Constructor>, +types: Map<&2, M.TypeId>) -> Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
  match constructors:
    case Nil{}:
      Done{Nil{}}
    case M.Constructor{name, payload} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
        found : Usage <- usage(Nat.mul(256n, 256n), TypeUsage{optional_type(payload)}, types)
        rest : List<&2, M.TypeId> <- constructor_types(tail, types)
        return union_types(usage_types(found), rest)

def type_dependencies(pending: List<&2, M.DataType>, +types: Map<&2, M.TypeId>) -> Result<&2, &2, M.Diagnostic, List<&2, TypeDependencies>>:
  match pending:
    case Nil{}:
      Done{Nil{}}
    case M.DataType{identity, parameters, constructors} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, TypeDependencies>>:
        refs : List<&2, M.TypeId> <- constructor_types(constructors, types)
        rest : List<&2, TypeDependencies> <- type_dependencies(tail, types)
        return TypeDependencies{identity, refs} <> rest

def coupled_references(effectful: Bool, references: List<&2, String>, callers: List<&2, String>) -> List<&2, String>:
  match effectful:
    case False{}:
      references
    case True{}:
      List.append(&2, String, references, callers)

def coupled_nodes(nodes: List<&2, D.Node>, +effectful: Set(), +callers: Map<&2, List<&2, String>>) -> List<&2, D.Node>:
  match nodes:
    case Nil{}:
      Nil{}
    case D.Node{+name, references, lambdas} <> tail:
      D.Node{name, coupled_references(D.member(effectful, name), references, D.neighbors(callers, name)), lambdas} <> coupled_nodes(tail, effectful, callers)

def external_references(references: List<&2, String>, +known: Set(), +members: Set(), +found: Set()) -> Set():
  match references:
    case Nil{}:
      found
    case +head <> tail:
      external_references(tail, known, members, D.mark(Bool.and(D.member(known, head), Bool.not(D.member(members, head))), found, head))

def job_dependencies(members: List<&2, String>, +edges: Map<&2, List<&2, String>>, +known: Set(), +owned: Set(), found: Set()) -> List<&2, String>:
  match members:
    case Nil{}:
      Set.to_list(found)
    case head <> tail:
      job_dependencies(tail, edges, known, owned, external_references(D.neighbors(edges, head), known, owned, found))

# A display name is not a key: modules and declarations may contain separators.
# Prefixing the module's character length makes the two-part identity injective.
def type_key(identity: M.TypeId) -> String:
  M.TypeId{+module_name, declaration} = identity
  Nat.show(String.length(module_name)) ++ ":" ++ module_name ++ declaration

def TypeSet() -> Data:
  Map<&2, M.TypeId>

def type_set(identities: List<&2, M.TypeId>, found: TypeSet()) -> TypeSet():
  match identities:
    case Nil{}:
      found
    case +head <> tail:
      type_set(tail, Map.set(&2, M.TypeId, found, type_key(head), head))

def type_keys(identities: List<&2, M.TypeId>) -> List<&2, String>:
  match identities:
    case Nil{}:
      Nil{}
    case head <> tail:
      type_key(head) <> type_keys(tail)

def type_identity_le(left: M.TypeId, right: M.TypeId) -> Bool:
  E.descriptor_le(M.Descriptor{left, M.Component{}}, M.Descriptor{right, M.Component{}})

def type_seed(seeds: Map<&2, TypeSet()>, name: String) -> TypeSet():
  Index.get(TypeSet(), seeds, name, Map.new(&2, M.TypeId))

def combine_seeds(names: List<&2, String>, +seeds: Map<&2, TypeSet()>, found: TypeSet()) -> TypeSet():
  match names:
    case Nil{}:
      found
    case head <> tail:
      combine_seeds(tail, seeds, Map.union(&2, M.TypeId, found, type_seed(seeds, head)))

def publish_summary(names: List<&2, String>, +summary: TypeSet(), summaries: Map<&2, TypeSet()>) -> Map<&2, TypeSet()>:
  match names:
    case Nil{}:
      summaries
    case head <> tail:
      publish_summary(tail, summary, Map.set(&2, TypeSet(), summaries, head, summary))

def usage_seeds(usages: List<&2, DeclarationUsage>, seeds: Map<&2, TypeSet()>) -> Map<&2, TypeSet()>:
  match usages:
    case Nil{}:
      seeds
    case DeclarationUsage{name, Usage{effectful, nominals}} <> tail:
      usage_seeds(tail, Map.set(&2, TypeSet(), seeds, name, type_set(nominals, Map.new(&2, M.TypeId))))

def nominal_nodes(types: List<&2, TypeDependencies>) -> List<&2, D.Node>:
  match types:
    case Nil{}:
      Nil{}
    case TypeDependencies{identity, Nil{}} <> tail:
      # Leaf closures are already represented by every user's direct seed.
      nominal_nodes(tail)
    case TypeDependencies{identity, references} <> tail:
      D.Node{type_key(identity), type_keys(references), Nil{}} <> nominal_nodes(tail)

def nominal_seeds(types: List<&2, TypeDependencies>, seeds: Map<&2, TypeSet()>) -> Map<&2, TypeSet()>:
  match types:
    case Nil{}:
      seeds
    case TypeDependencies{identity, Nil{}} <> tail:
      nominal_seeds(tail, seeds)
    case TypeDependencies{+identity, references} <> tail:
      # Leaves and opaque storage have no graph node but remain in closures.
      nominal_seeds(tail, Map.set(&2, TypeSet(), seeds, type_key(identity), type_set(identity <> references, Map.new(&2, M.TypeId))))

def nominal_summaries(components: List<&2, List<&2, String>>, +edges: Map<&2, List<&2, String>>, +seeds: Map<&2, TypeSet()>, +known: Set(), +summaries: Map<&2, TypeSet()>) -> Map<&2, TypeSet()>:
  match components:
    case Nil{}:
      summaries
    case +members <> tail:
      dependencies = job_dependencies(members, edges, known, Set.from_list(members), Set.new())
      own = combine_seeds(members, seeds, Map.new(&2, M.TypeId))
      summary = combine_seeds(dependencies, summaries, own)
      nominal_summaries(tail, edges, seeds, known, publish_summary(members, summary, summaries))

def close_nominals(identities: List<&2, M.TypeId>, +summaries: Map<&2, TypeSet()>, found: TypeSet()) -> TypeSet():
  match identities:
    case Nil{}:
      found
    case head <> tail:
      close_nominals(tail, summaries, Map.union(&2, M.TypeId, found, type_seed(summaries, type_key(head))))

# A caller of an effectful job would have been coupled into that same job.
# Cross-job dependencies therefore target pure SCCs, whose members are mutually
# reachable. Sharing their complete nominal summaries adds no unrelated types.
def make_jobs(components: List<&2, List<&2, String>>, +edges: Map<&2, List<&2, String>>, +known: Set(), +seeds: Map<&2, TypeSet()>, +nominals: Map<&2, TypeSet()>, +summaries: Map<&2, TypeSet()>) -> List<&2, Job>:
  match components:
    case Nil{}:
      Nil{}
    case +members <> tail:
      +dependencies = job_dependencies(members, edges, known, Set.from_list(members), Set.new())
      +own = combine_seeds(members, seeds, Map.new(&2, M.TypeId))
      closed = close_nominals(Map.values(&2, M.TypeId, own), nominals, own)
      +summary = combine_seeds(dependencies, summaries, closed)
      required = List.sort(~M.TypeId, ~type_identity_le, Map.values(&2, M.TypeId, summary))
      Job{members, dependencies, required} <> make_jobs(tail, edges, known, seeds, nominals, publish_summary(members, summary, summaries))

type Planning is Data:
  Planning{nodes: List<&2, D.Node>, usages: List<&2, DeclarationUsage>, type_dependencies: List<&2, TypeDependencies>}

def planning_nodes(nodes: List<&2, D.Node>) -> List<&2, D.Node>:
  match nodes:
    case Nil{}:
      Nil{}
    case D.Node{name, references, lambdas} <> tail:
      # Lambda identities have already been validated and do not affect jobs.
      D.Node{name, Set.to_list(Set.from_list(references)), Nil{}} <> planning_nodes(tail)

def planning_usages(usages: List<&2, DeclarationUsage>) -> List<&2, DeclarationUsage>:
  match usages:
    case Nil{}:
      Nil{}
    case DeclarationUsage{name, Usage{effectful, nominals}} <> tail:
      DeclarationUsage{name, Usage{effectful, List.sort(~M.TypeId, ~type_identity_le, nominals)}} <> planning_usages(tail)

def planning_types(types: List<&2, TypeDependencies>) -> List<&2, TypeDependencies>:
  match types:
    case Nil{}:
      Nil{}
    case TypeDependencies{identity, references} <> tail:
      TypeDependencies{identity, List.sort(~M.TypeId, ~type_identity_le, references)} <> planning_types(tail)

# Global validation still runs for every revision, including unused declarations.
# The result retains semantic dependencies but no expression bodies, allowing a
# body-only edit to reuse SCC planning and transitive catalog selection.
def prepare_plan(+module: M.Module) -> Result<&2, &2, M.Diagnostic, Planning>:
  M.Module{descriptors, constants, functions, +types} = module
  declarations = List.append(&2, G.Declaration, G.function_declarations(functions), G.constant_declarations(constants))
  do Result<&2, &2, M.Diagnostic, Planning>:
    nodes : List<&2, D.Node> <- Check.module_graph(module)
    +constructors : Map<&2, M.TypeId> = constructor_index(types, Map.new(&2, M.TypeId))
    usages : List<&2, DeclarationUsage> <- declaration_usages(declarations, constructors)
    nominal_graph : List<&2, TypeDependencies> <- type_dependencies(types, constructors)
    return Planning{planning_nodes(nodes), planning_usages(usages), planning_types(nominal_graph)}

# Reverse only edges into possibly effectful definitions. Every caller that can
# constrain a monomorphic helper shares its job; pure dependencies stay reusable.
def finish_plan(planning: Planning) -> Result<&2, &2, M.Diagnostic, List<&2, Job>>:
  Planning{+nodes, +usages, +nominal_graph} = planning
  do Result<&2, &2, M.Diagnostic, List<&2, Job>>:
    +known : Set() = Set.from_list(D.node_names(nodes))
    +callers : Map<&2, List<&2, String>> = D.transpose(nodes, Map.new(&2, List<&2, String>))
    +seeds : List<&2, String> = effect_seeds(usages)
    +fuel : Nat = 1n+Nat.add(List.length(&2, D.Node, nodes), D.edge_count(nodes))
    effectful : D.Reachability <- D.reachable(Nat.add(fuel, List.length(&2, String, seeds)), seeds, callers, known, Set.new(), Nil{})
    components : List<&2, List<&2, String>> <- D.components(coupled_nodes(nodes, D.reached_seen(effectful), callers))
    +nominal_graph_nodes : List<&2, D.Node> = nominal_nodes(nominal_graph)
    nominal_components : List<&2, List<&2, String>> <- D.components(nominal_graph_nodes)
    closures : Map<&2, TypeSet()> = nominal_summaries(nominal_components, D.adjacency(nominal_graph_nodes, Map.new(&2, List<&2, String>)), nominal_seeds(nominal_graph, Map.new(&2, TypeSet())), Set.from_list(D.node_names(nominal_graph_nodes)), Map.new(&2, TypeSet()))
    return make_jobs(components, D.adjacency(nodes, Map.new(&2, List<&2, String>)), known, usage_seeds(usages, Map.new(&2, TypeSet())), closures, Map.new(&2, TypeSet()))

def plan(module: M.Module) -> Result<&2, &2, M.Diagnostic, List<&2, Job>>:
  do Result<&2, &2, M.Diagnostic, List<&2, Job>>:
    prepared : Planning <- prepare_plan(module)
    finish_plan(prepared)

def select_functions(functions: List<&2, M.Function>, +members: List<&2, String>) -> List<&2, M.Function>:
  match functions:
    case Nil{}:
      Nil{}
    case M.Function{+name, exported, parameter, p, r, body} <> tail:
      +rest = select_functions(tail, members)
      Bool.pick(List<&2, M.Function>, D.contains(members, name), M.Function{name, exported, parameter, p, r, body} <> rest, rest)

def select_constants(constants: List<&2, M.Constant>, +members: List<&2, String>) -> List<&2, M.Constant>:
  match constants:
    case Nil{}:
      Nil{}
    case M.Constant{+name, exported, annotation, value} <> tail:
      +rest = select_constants(tail, members)
      Bool.pick(List<&2, M.Constant>, D.contains(members, name), M.Constant{name, exported, annotation, value} <> rest, rest)

def select_types(types: List<&2, M.DataType>, +required: List<&2, M.TypeId>) -> List<&2, M.DataType>:
  match types:
    case Nil{}:
      Nil{}
    case M.DataType{+identity, parameters, constructors} <> tail:
      +rest = select_types(tail, required)
      Bool.pick(List<&2, M.DataType>, contains_type(required, identity), M.DataType{identity, parameters, constructors} <> rest, rest)

def select_descriptors(descriptors: List<&2, M.Descriptor>, +required: List<&2, M.TypeId>) -> List<&2, M.Descriptor>:
  match descriptors:
    case Nil{}:
      Nil{}
    case M.Descriptor{+identity, storage} <> tail:
      +rest = select_descriptors(tail, required)
      Bool.pick(List<&2, M.Descriptor>, contains_type(required, identity), M.Descriptor{identity, storage} <> rest, rest)

def job_module(module: M.Module, job: Job) -> Result<&2, &2, M.Diagnostic, M.Module>:
  M.Module{descriptors, constants, functions, types} = module
  Job{+members, dependencies, +required} = job
  Done{M.Module{select_descriptors(descriptors, required), select_constants(constants, members), select_functions(functions, members), select_types(types, required)}}
