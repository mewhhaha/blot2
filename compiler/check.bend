import Base
import ./model.bend as M
import ./types.bend as T
import ./infer.bend as I
import ./effects.bend as E
import ./globals.bend as G
import ./dependency.bend as D
import ./type_data.bend as TD
import ./patterns.bend as P
import ./index.bend as Index

def descriptor_match(found: Bool, descriptor: M.Descriptor, next: Unit -> Result<&2, &2, M.Diagnostic, M.Descriptor>) -> Result<&2, &2, M.Diagnostic, M.Descriptor>:
  match found:
    case True{}:
      Done{descriptor}
    case False{}:
      next(Unit{})

def lookup_descriptor(descriptors: List<&2, M.Descriptor>, +identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, M.Descriptor>:
  match descriptors:
    case Nil{}:
      Fail{M.Diagnostic{"unknown_storage", M.type_id_show(identity), "no component or resource descriptor for this type"}}
    case M.Descriptor{+found, +storage} <> tail:
      descriptor_match(M.type_id_equal(found, identity), M.Descriptor{found, storage}, _ => lookup_descriptor(tail, identity))

def DescriptorIndex() -> Data:
  Map<&2, Map<&2, M.Descriptor>>

def descriptor_modules(index: DescriptorIndex(), module_name: String) -> Map<&2, M.Descriptor>:
  Index.get(Map<&2, M.Descriptor>, index, module_name, Map.new(&2, M.Descriptor))

def descriptor_index(reversed: List<&2, M.Descriptor>, +index: DescriptorIndex()) -> DescriptorIndex():
  match reversed:
    case Nil{}:
      index
    case M.Descriptor{M.TypeId{+module_name, +declaration}, storage} <> tail:
      declarations = descriptor_modules(index, module_name)
      descriptor = {M.Descriptor{M.TypeId{module_name, declaration}, storage} : M.Descriptor}
      descriptor_index(tail, Map.set(&2, Map<&2, M.Descriptor>, index, module_name, Map.set(&2, M.Descriptor, declarations, declaration, descriptor)))

def descriptor_found(found: Maybe<&2, M.Descriptor>, identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, M.Descriptor>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"unknown_storage", M.type_id_show(identity), "no component or resource descriptor for this type"}}
    case Some{descriptor}:
      Done{descriptor}

def indexed_descriptor(index: DescriptorIndex(), +identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, M.Descriptor>:
  M.TypeId{module_name, declaration} = identity
  descriptor_found(Index.find(M.Descriptor, descriptor_modules(index, module_name), declaration), identity)

def IdentitySet() -> Data:
  Map<&2, Set()>

def identity_members(index: IdentitySet(), module_name: String) -> Set():
  Index.get(Set(), index, module_name, Set.new())

def identity_present(index: IdentitySet(), identity: M.TypeId) -> Bool:
  M.TypeId{module_name, declaration} = identity
  D.member(identity_members(index, module_name), declaration)

def identity_add(+index: IdentitySet(), identity: M.TypeId) -> IdentitySet():
  M.TypeId{+module_name, declaration} = identity
  Map.set(&2, Set(), index, module_name, Set.add(identity_members(index, module_name), declaration))

def identity_mark(present: Bool, index: IdentitySet(), identity: M.TypeId) -> IdentitySet():
  match present:
    case False{}:
      index
    case True{}:
      identity_add(index, identity)

def repeated_identities(identities: List<&2, M.TypeId>, +seen: IdentitySet(), repeated: IdentitySet()) -> IdentitySet():
  match identities:
    case Nil{}:
      repeated
    case +head <> tail:
      repeated_identities(tail, identity_add(seen, head), identity_mark(identity_present(seen, head), repeated, head))

def descriptor_identities(descriptors: List<&2, M.Descriptor>) -> List<&2, M.TypeId>:
  match descriptors:
    case Nil{}:
      Nil{}
    case M.Descriptor{identity, storage} <> tail:
      identity <> descriptor_identities(tail)

def require_unique_identity(repeated: Bool, identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, Unit>:
  match repeated:
    case False{}:
      Done{Unit{}}
    case True{}:
      Fail{M.Diagnostic{"duplicate_type", M.type_id_show(identity), "duplicate nominal identity"}}

def unique_identities(identities: List<&2, M.TypeId>, +repeated: IdentitySet()) -> Result<&2, &2, M.Diagnostic, Unit>:
  match identities:
    case Nil{}:
      Done{Unit{}}
    case +head <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        unique : Unit <- require_unique_identity(identity_present(repeated, head), head)
        unique_identities(tail, repeated)

def valid_descriptors(descriptors: List<&2, M.Descriptor>) -> Result<&2, &2, M.Diagnostic, Unit>:
  +identities = descriptor_identities(descriptors)
  unique_identities(identities, repeated_identities(identities, Map.new(&2, Set()), Map.new(&2, Set())))

def name_present(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}:
      False{}
    case head <> tail:
      E.or_else(M.name_equal(head, name), _ => name_present(tail, name))

def definition_names(definitions: List<&2, I.Definition>) -> List<&2, String>:
  match definitions:
    case Nil{}:
      Nil{}
    case I.Definition{name, inference} <> tail:
      name <> definition_names(tail)

def repeated_names(names: List<&2, String>, +seen: Set(), repeated: Set()) -> Set():
  match names:
    case Nil{}:
      repeated
    case +head <> tail:
      repeated_names(tail, Set.add(seen, head), D.mark(D.member(seen, head), repeated, head))

def require_unique_name(repeated: Bool, name: String, code: String, message: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match repeated:
    case False{}:
      Done{Unit{}}
    case True{}:
      Fail{M.Diagnostic{code, name, message}}

# Diagnose the earliest first occurrence with a duplicate, not the earliest
# second occurrence: [a, b, b, a] must still identify a.
def unique_names_indexed(names: List<&2, String>, +repeated: Set(), +code: String, +message: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match names:
    case Nil{}:
      Done{Unit{}}
    case +head <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        unique : Unit <- require_unique_name(D.member(repeated, head), head, code, message)
        unique_names_indexed(tail, repeated, code, message)

def unique_names(+names: List<&2, String>) -> Result<&2, &2, M.Diagnostic, Unit>:
  unique_names_indexed(names, repeated_names(names, Set.new(), Set.new()), "duplicate_name", "duplicate top-level definition")

def valid_access(access: M.Access, descriptor: M.Descriptor) -> Result<&2, &2, M.Diagnostic, M.Effect>:
  match access descriptor:
    case M.Insert{} M.Descriptor{identity, M.Resource{}}:
      Fail{M.Diagnostic{"invalid_insert", M.type_id_show(identity), "insertion is an entity-component operation, not a resource write"}}
    case a d:
      Done{M.Effect{a, d}}

def access_effect(ty: M.Ty, access: M.Access, descriptors: List<&2, M.Descriptor>, subject: String) -> Result<&2, &2, M.Diagnostic, M.Effect>:
  match ty:
    case M.NominalTy{identity}:
      do Result<&2, &2, M.Diagnostic, M.Effect>:
        registered : M.Descriptor <- lookup_descriptor(descriptors, identity)
        valid_access(access, registered)
    case M.AppliedTy{identity, Nil{}}:
      do Result<&2, &2, M.Diagnostic, M.Effect>:
        registered : M.Descriptor <- lookup_descriptor(descriptors, identity)
        valid_access(access, registered)
    case other:
      Fail{M.Diagnostic{"invalid_storage_access", subject, "expected a known component/resource type, got " ++ M.type_show(other)}}

def access_effect_indexed(ty: M.Ty, access: M.Access, descriptors: DescriptorIndex(), subject: String) -> Result<&2, &2, M.Diagnostic, M.Effect>:
  match ty:
    case M.NominalTy{identity}:
      do Result<&2, &2, M.Diagnostic, M.Effect>:
        registered : M.Descriptor <- indexed_descriptor(descriptors, identity)
        valid_access(access, registered)
    case M.AppliedTy{identity, Nil{}}:
      do Result<&2, &2, M.Diagnostic, M.Effect>:
        registered : M.Descriptor <- indexed_descriptor(descriptors, identity)
        valid_access(access, registered)
    case other:
      Fail{M.Diagnostic{"invalid_storage_access", subject, "expected a known component/resource type, got " ++ M.type_show(other)}}

type EffectNode is Data:
  EffectNode{name: String, direct: List<&2, M.Effect>, callees: List<&2, String>}

def direct_requirements(requirements: List<&2, I.Requirement>, +substitutions: List<&2, T.Substitution>, +descriptors: DescriptorIndex(), +subject: String, effects: List<&2, M.Effect>, callees: List<&2, String>) -> Result<&2, &2, M.Diagnostic, EffectNode>:
  match requirements:
    case Nil{}:
      Done{EffectNode{subject, effects, callees}}
    case I.CallRequirement{callee} <> tail:
      direct_requirements(tail, substitutions, descriptors, subject, effects, callee <> callees)
    case I.ConstantRequirement{name} <> tail:
      direct_requirements(tail, substitutions, descriptors, subject, effects, name <> callees)
    case I.AccessRequirement{access, target} <> tail:
      do Result<&2, &2, M.Diagnostic, EffectNode>:
        resolved : M.Ty <- T.resolve(substitutions, target)
        effect : M.Effect <- access_effect_indexed(resolved, access, descriptors, subject)
        direct_requirements(tail, substitutions, descriptors, subject, E.put(effects, effect), callees)

def effect_nodes(definitions: List<&2, I.Definition>, +substitutions: List<&2, T.Substitution>, +descriptors: DescriptorIndex()) -> Result<&2, &2, M.Diagnostic, List<&2, EffectNode>>:
  match definitions:
    case Nil{}:
      Done{Nil{}}
    case I.Definition{name, I.Inference{ty, requirements, purity, coverage, exits}} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, EffectNode>>:
        head : EffectNode <- direct_requirements(requirements, substitutions, descriptors, name, Nil{}, Nil{})
        rest : List<&2, EffectNode> <- effect_nodes(tail, substitutions, descriptors)
        return head <> rest

def effect_node_match(found: Bool, node: EffectNode, next: Unit -> Result<&2, &2, M.Diagnostic, EffectNode>) -> Result<&2, &2, M.Diagnostic, EffectNode>:
  match found:
    case True{}:
      Done{node}
    case False{}:
      next(Unit{})

def lookup_effect_node(nodes: List<&2, EffectNode>, +name: String) -> Result<&2, &2, M.Diagnostic, EffectNode>:
  match nodes:
    case Nil{}:
      Fail{M.Diagnostic{"internal_error", name, "missing effect-graph node"}}
    case EffectNode{+found, +direct, +callees} <> tail:
      effect_node_match(M.name_equal(found, name), EffectNode{found, direct, callees}, _ => lookup_effect_node(tail, name))

def effect_node_index(reversed: List<&2, EffectNode>, index: Map<&2, EffectNode>) -> Map<&2, EffectNode>:
  match reversed:
    case Nil{}:
      index
    case EffectNode{+name, direct, callees} <> tail:
      effect_node_index(tail, Map.set(&2, EffectNode, index, name, EffectNode{name, direct, callees}))

def effect_node_found(found: Maybe<&2, EffectNode>, name: String) -> Result<&2, &2, M.Diagnostic, EffectNode>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"internal_error", name, "missing effect-graph node"}}
    case Some{node}:
      Done{node}

def indexed_effect_node(nodes: Map<&2, EffectNode>, +name: String) -> Result<&2, &2, M.Diagnostic, EffectNode>:
  effect_node_found(Index.find(EffectNode, nodes, name), name)

def node_callees(node: EffectNode) -> List<&2, String>:
  EffectNode{name, direct, callees} = node
  callees

def node_direct(node: EffectNode) -> List<&2, M.Effect>:
  EffectNode{name, direct, callees} = node
  direct

def next_pending(visited: Bool, callees: List<&2, String>, pending: List<&2, String>) -> List<&2, String>:
  match visited:
    case True{}:
      pending
    case False{}:
      List.append(&2, String, callees, pending)

# Each definition's outgoing edges are queued once, including recursive cycles.
# Fuel bounds the initial worklist plus graph edges, not semantic recursion.
def reachable_indexed_work(fuel: Nat, pending: List<&2, String>, +nodes: Map<&2, EffectNode>, +visited: Set(), +effects: List<&2, M.Effect>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Effect>>:
  match fuel pending:
    case _ Nil{}:
      Done{effects}
    case 0n head <> tail:
      Fail{M.Diagnostic{"internal_error", head, "effect worklist exceeded its graph bound"}}
    case 1n+rest +head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Effect>>:
        +node : EffectNode <- indexed_effect_node(nodes, head)
        reachable_indexed_work(rest, next_pending(D.member(visited, head), node_callees(node), tail), nodes, Set.add(visited, head), E.union(node_direct(node), effects))

def reachable_work(fuel: Nat, pending: List<&2, String>, nodes: List<&2, EffectNode>, visited: List<&2, String>, effects: List<&2, M.Effect>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Effect>>:
  reachable_indexed_work(fuel, pending, effect_node_index(List.reverse(&2, EffectNode, nodes), Map.new(&2, EffectNode)), Set.from_list(visited), effects)

def any_direct_effect(nodes: List<&2, EffectNode>) -> Bool:
  match nodes:
    case Nil{}:
      False{}
    case EffectNode{name, direct, callees} <> tail:
      E.or_else(Bool.not(List.is_empty(&2, M.Effect, direct)), _ => any_direct_effect(tail))

type EffectGraph is Data:
  EffectGraph{nodes: Map<&2, EffectNode>, has_effects: Bool}

def effect_graph(+nodes: List<&2, EffectNode>) -> EffectGraph:
  EffectGraph{effect_node_index(List.reverse(&2, EffectNode, nodes), Map.new(&2, EffectNode)), any_direct_effect(nodes)}

def reachable_indexed(fuel: Nat, pending: List<&2, String>, graph: EffectGraph, effects: List<&2, M.Effect>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Effect>>:
  match graph:
    case EffectGraph{nodes, False{}}:
      Done{effects}
    case EffectGraph{nodes, True{}}:
      reachable_indexed_work(fuel, pending, nodes, Set.new(), effects)

def reachable_graph(has_effects: Bool, fuel: Nat, pending: List<&2, String>, nodes: List<&2, EffectNode>, visited: List<&2, String>, effects: List<&2, M.Effect>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Effect>>:
  match has_effects:
    case False{}:
      Done{effects}
    case True{}:
      reachable_work(fuel, pending, nodes, visited, effects)

def reachable(fuel: Nat, pending: List<&2, String>, +nodes: List<&2, EffectNode>, visited: List<&2, String>, effects: List<&2, M.Effect>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Effect>>:
  # Keep the constraint's own effects, even when every named definition is pure:
  # a latent lambda may perform storage access without adding it to its creator.
  reachable_graph(any_direct_effect(nodes), fuel, pending, nodes, visited, effects)

def edge_count(nodes: List<&2, EffectNode>) -> Nat:
  match nodes:
    case Nil{}:
      0n
    case EffectNode{name, direct, callees} <> tail:
      Nat.add(List.length(&2, String, callees), edge_count(tail))

def checked_signature(ty: M.Ty, name: String, variables: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, M.Signature>:
  match ty:
    case M.FunctionTy{parameter, result}:
      Done{M.Signature{name, parameter, result, variables}}
    case other:
      Fail{M.Diagnostic{"internal_error", name, "function does not have an arrow type"}}

def resolve_binding(found: Maybe<&2, I.Binding>, substitutions: List<&2, T.Substitution>, subject: String) -> Result<&2, &2, M.Diagnostic, I.Binding>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"internal_error", subject, "missing inferred binding"}}
    case Some{I.Binding{name, ty, variables}}:
      do Result<&2, &2, M.Diagnostic, I.Binding>:
        resolved : M.Ty <- T.resolve(substitutions, ty)
        return I.Binding{name, resolved, variables}

def binding_signature(binding: I.Binding) -> Result<&2, &2, M.Diagnostic, M.Signature>:
  I.Binding{name, ty, variables} = binding
  checked_signature(ty, name, variables)

def function_results(functions: List<&2, M.Function>, +bindings: List<&2, I.Binding>, +substitutions: List<&2, T.Substitution>, +nodes: EffectGraph, +fuel: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, M.CheckedFunction>>:
  match functions:
    case Nil{}:
      Done{Nil{}}
    case M.Function{+name, exported, parameter, p, r, body} <> fs:
      do Result<&2, &2, M.Diagnostic, List<&2, M.CheckedFunction>>:
        binding : I.Binding <- resolve_binding(I.lookup_binding(bindings, name), substitutions, name)
        signature : M.Signature <- binding_signature(binding)
        effects : List<&2, M.Effect> <- reachable_indexed(fuel, [name], nodes, Nil{})
        rest : List<&2, M.CheckedFunction> <- function_results(fs, bindings, substitutions, nodes, fuel)
        return M.CheckedFunction{M.Function{name, exported, parameter, p, r, body}, signature, effects} <> rest

def require_let_pure(effects: List<&2, M.Effect>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match effects:
    case Nil{}:
      Done{Unit{}}
    case head <> tail:
      Fail{M.Diagnostic{"let_effect", subject, "let requires a pure RHS; bind effectful computations with use name <- expression"}}

def require_function_pure(effects: List<&2, M.Effect>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match effects:
    case Nil{}:
      Done{Unit{}}
    case head <> tail:
      Fail{M.Diagnostic{"effectful_function_value", subject, "higher-order function values must be pure until function types carry effect rows; call named effectful functions directly"}}

def check_purity(constraints: List<&2, I.PurityConstraint>, +substitutions: List<&2, T.Substitution>, +descriptors: DescriptorIndex(), +nodes: EffectGraph, +fuel: Nat) -> Result<&2, &2, M.Diagnostic, Unit>:
  match constraints:
    case Nil{}:
      Done{Unit{}}
    case I.PurityConstraint{+subject, requirements} <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        +node : EffectNode <- direct_requirements(requirements, substitutions, descriptors, subject, Nil{}, Nil{})
        +callees : List<&2, String> = node_callees(node)
        effects : List<&2, M.Effect> <- reachable_indexed(Nat.add(fuel, List.length(&2, String, callees)), callees, nodes, node_direct(node))
        pure : Unit <- require_let_pure(effects, subject)
        check_purity(tail, substitutions, descriptors, nodes, fuel)
    case I.FunctionPurityConstraint{+subject, requirements} <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        +node : EffectNode <- direct_requirements(requirements, substitutions, descriptors, subject, Nil{}, Nil{})
        +callees : List<&2, String> = node_callees(node)
        effects : List<&2, M.Effect> <- reachable_indexed(Nat.add(fuel, List.length(&2, String, callees)), callees, nodes, node_direct(node))
        pure : Unit <- require_function_pure(effects, subject)
        check_purity(tail, substitutions, descriptors, nodes, fuel)

def require_const_pure(effects: List<&2, M.Effect>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match effects:
    case Nil{}:
      Done{Unit{}}
    case head <> tail:
      Fail{M.Diagnostic{"const_effect", subject, "const evaluation cannot access runtime ECS storage"}}

def checked_constant(constant: M.Constant, binding: I.Binding) -> M.CheckedConstant:
  I.Binding{name, ty, variables} = binding
  M.CheckedConstant{constant, ty, variables}

def constant_results(constants: List<&2, M.Constant>, +bindings: List<&2, I.Binding>, +substitutions: List<&2, T.Substitution>, +nodes: EffectGraph, +fuel: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, M.CheckedConstant>>:
  match constants:
    case Nil{}:
      Done{Nil{}}
    case M.Constant{+name, exported, annotation, value} <> cs:
      do Result<&2, &2, M.Diagnostic, List<&2, M.CheckedConstant>>:
        binding : I.Binding <- resolve_binding(I.lookup_binding(bindings, name), substitutions, name)
        effects : List<&2, M.Effect> <- reachable_indexed(fuel, [name], nodes, Nil{})
        pure : Unit <- require_const_pure(effects, name)
        rest : List<&2, M.CheckedConstant> <- constant_results(cs, bindings, substitutions, nodes, fuel)
        return checked_constant(M.Constant{name, exported, annotation, value}, binding) <> rest

def purity_constraints(definitions: List<&2, I.Definition>) -> List<&2, I.PurityConstraint>:
  match definitions:
    case Nil{}:
      Nil{}
    case I.Definition{name, I.Inference{ty, requirements, purity, coverage, exits}} <> tail:
      List.append(&2, I.PurityConstraint, purity, purity_constraints(tail))

def coverage_constraints(definitions: List<&2, I.Definition>) -> List<&2, I.Coverage>:
  match definitions:
    case Nil{}:
      Nil{}
    case I.Definition{name, I.Inference{ty, requirements, purity, coverage, exits}} <> tail:
      List.append(&2, I.Coverage, coverage, coverage_constraints(tail))

def constructor_names(constructors: List<&2, M.Constructor>) -> List<&2, String>:
  match constructors:
    case Nil{}:
      Nil{}
    case M.Constructor{name, payload} <> tail:
      name <> constructor_names(tail)

def all_constructor_names(types: List<&2, M.DataType>) -> List<&2, String>:
  match types:
    case Nil{}:
      Nil{}
    case M.DataType{identity, parameters, constructors} <> tail:
      List.append(&2, String, constructor_names(constructors), all_constructor_names(tail))

def storage_parameters(registered: Bool, parameters: Nat, identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, Unit>:
  match registered parameters:
    case False{} _:
      Done{Unit{}}
    case True{} 0n:
      Done{Unit{}}
    case True{} 1n+rest:
      Fail{M.Diagnostic{"generic_storage_type", M.type_id_show(identity), "component and resource registrations require a data type with no type parameters"}}

def type_identities(types: List<&2, M.DataType>) -> List<&2, M.TypeId>:
  match types:
    case Nil{}:
      Nil{}
    case M.DataType{identity, parameters, constructors} <> tail:
      identity <> type_identities(tail)

def validate_types_indexed(pending: List<&2, M.DataType>, +types: List<&2, M.DataType>, +descriptors: List<&2, M.Descriptor>, +repeated: IdentitySet(), +registered: IdentitySet()) -> Result<&2, &2, M.Diagnostic, Unit>:
  match pending:
    case Nil{}:
      Done{Unit{}}
    case M.DataType{+identity, +parameters, +constructors} <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        unique : Unit <- require_unique_identity(identity_present(repeated, identity), identity)
        storage : Unit <- storage_parameters(identity_present(registered, identity), parameters, identity)
        inhabited : Unit <- TD.require(Bool.not(List.is_empty(&2, M.Constructor, constructors)), M.type_id_show(identity), "data declarations need at least one constructor")
        valid : Unit <- TD.validate_constructors(constructors, parameters, descriptors, types)
        validate_types_indexed(tail, types, descriptors, repeated, registered)

def identity_set(identities: List<&2, M.TypeId>, index: IdentitySet()) -> IdentitySet():
  match identities:
    case Nil{}:
      index
    case head <> tail:
      identity_set(tail, identity_add(index, head))

def validate_types(+pending: List<&2, M.DataType>, types: List<&2, M.DataType>, +descriptors: List<&2, M.Descriptor>) -> Result<&2, &2, M.Diagnostic, Unit>:
  repeated = repeated_identities(type_identities(pending), Map.new(&2, Set()), Map.new(&2, Set()))
  registered = identity_set(descriptor_identities(descriptors), Map.new(&2, Set()))
  validate_types_indexed(pending, types, descriptors, repeated, registered)

def lambda_ids(nodes: List<&2, D.Node>) -> List<&2, Nat>:
  match nodes:
    case Nil{}:
      Nil{}
    case D.Node{name, references, lambdas} <> tail:
      List.append(&2, Nat, lambdas, lambda_ids(tail))

def lambda_names(identities: List<&2, Nat>) -> List<&2, String>:
  match identities:
    case Nil{}:
      Nil{}
    case head <> tail:
      Nat.show(head) <> lambda_names(tail)

def unique_lambdas(identities: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, Unit>:
  +names = lambda_names(identities)
  unique_names_indexed(names, repeated_names(names, Set.new(), Set.new()), "duplicate_lambda", "lambda identity must be unique within its module")

def module_graph(module: M.Module) -> Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
  M.Module{+descriptors, +constants, +functions, +types} = module
  +declarations = List.append(&2, G.Declaration, G.function_declarations(functions), G.constant_declarations(constants))
  do Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
    registered : Unit <- valid_descriptors(descriptors)
    valid_types : Unit <- validate_types(types, types, descriptors)
    unique : Unit <- unique_names(List.append(&2, String, G.names(declarations), all_constructor_names(types)))
    fns : List<&2, D.Node> <- D.function_nodes(functions)
    consts : List<&2, D.Node> <- D.constant_nodes(constants)
    +graph : List<&2, D.Node> = List.append(&2, D.Node, fns, consts)
    lambdas : Unit <- unique_lambdas(lambda_ids(graph))
    return graph

def finish(module: M.Module, +environment: G.Environment) -> Result<&2, &2, M.Diagnostic, M.CheckedModule>:
  M.Module{+descriptors, constants, functions, +types} = module
  do Result<&2, &2, M.Diagnostic, M.CheckedModule>:
    +definitions : List<&2, I.Definition> = G.env_definitions(environment)
    +bindings : List<&2, I.Binding> = G.env_bindings(environment)
    +substitutions : List<&2, T.Substitution> = I.substitutions_of(G.env_state(environment))
    +registered : DescriptorIndex() = descriptor_index(List.reverse(&2, M.Descriptor, descriptors), Map.new(&2, Map<&2, M.Descriptor>))
    +nodes : List<&2, EffectNode> <- effect_nodes(definitions, substitutions, registered)
    +fuel : Nat = 1n+edge_count(nodes)
    +graph : EffectGraph = effect_graph(nodes)
    pure_bindings : Unit <- check_purity(purity_constraints(definitions), substitutions, registered, graph, fuel)
    coverage : Unit <- P.check(coverage_constraints(definitions), substitutions, types)
    checked_fns : List<&2, M.CheckedFunction> <- function_results(functions, bindings, substitutions, graph, fuel)
    checked_consts : List<&2, M.CheckedConstant> <- constant_results(constants, bindings, substitutions, graph, fuel)
    return M.CheckedModule{checked_consts, checked_fns, types}

def check_module(+module: M.Module) -> Result<&2, &2, M.Diagnostic, M.CheckedModule>:
  M.Module{descriptors, constants, functions, types} = module
  declarations = List.append(&2, G.Declaration, G.function_declarations(functions), G.constant_declarations(constants))
  do Result<&2, &2, M.Diagnostic, M.CheckedModule>:
    graph : List<&2, D.Node> <- module_graph(module)
    environment : G.Environment <- G.infer(declarations, graph, descriptors, types)
    finish(module, environment)
