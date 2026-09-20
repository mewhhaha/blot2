import Base
import ./model.bend as M
import ./effects.bend as Effects
import ./index.bend as Index

type ConstructorSlot is Data:
  ConstructorSlot{name: String, tag: Nat, payload: Bool}

type StorageBinding is Data:
  StorageBinding{identity: M.TypeId, storage: M.Storage, constructor: String, tag: Nat}

type NominalIndex<-V: Data> is Data:
  NominalIndex{modules: Map<&2, Map<&2, Maybe<&2, V>>>}

type TypeCatalog is Data:
  TypeCatalog{variants: List<&2, ConstructorSlot>, constructors: Map<&2, Maybe<&2, ConstructorSlot>>, types: NominalIndex<M.DataType>}

def nominal_module(-V: Data, indexed: NominalIndex<V>, module_name: String) -> Map<&2, Maybe<&2, V>>:
  NominalIndex{modules} = indexed
  Index.get(Map<&2, Maybe<&2, V>>, modules, module_name, Map.new(&2, Maybe<&2, V>))

def nominal_get(-V: Data, indexed: NominalIndex<V>, identity: M.TypeId) -> Maybe<&2, V>:
  M.TypeId{module_name, declaration} = identity
  Index.get(Maybe<&2, V>, nominal_module(V, indexed, module_name), declaration, None{})

def nominal_set(-V: Data, indexed: NominalIndex<V>, identity: M.TypeId, value: V) -> NominalIndex<V>:
  NominalIndex{+modules} = indexed
  M.TypeId{+module_name, declaration} = identity
  declarations = Map.set(&2, Maybe<&2, V>, nominal_module(V, NominalIndex{modules}, module_name), declaration, Some{value})
  NominalIndex{Map.set(&2, Map<&2, Maybe<&2, V>>, modules, module_name, declarations)}

def nominal_new(-V: Data) -> NominalIndex<V>:
  NominalIndex{Map.new(&2, Map<&2, Maybe<&2, V>>)}

def datatype_slots(variants: List<&2, M.Constructor>, index: Nat) -> List<&2, ConstructorSlot>:
  match variants:
    case Nil{}:
      Nil{}
    case M.Constructor{name, None{}} <> tail:
      +tag = index
      ConstructorSlot{name, tag, False{}} <> datatype_slots(tail, 1n+tag)
    case M.Constructor{name, Some{payload}} <> tail:
      +tag = index
      ConstructorSlot{name, tag, True{}} <> datatype_slots(tail, 1n+tag)

# Runtime values and host storage use this one constructor-tag assignment.
def constructor_slots(types: List<&2, M.DataType>, index: Nat) -> List<&2, ConstructorSlot>:
  match types:
    case Nil{}:
      Nil{}
    case M.DataType{identity, parameters, +variants} <> tail:
      +start = index
      List.append(&2, ConstructorSlot, datatype_slots(variants, start), constructor_slots(tail, Nat.add(start, List.length(&2, M.Constructor, variants))))

def constructor_index_go(slots: List<&2, ConstructorSlot>, indexed: Map<&2, Maybe<&2, ConstructorSlot>>) -> Map<&2, Maybe<&2, ConstructorSlot>>:
  match slots:
    case Nil{}:
      indexed
    case ConstructorSlot{+name, tag, payload} <> tail:
      constructor_index_go(tail, Map.set(&2, Maybe<&2, ConstructorSlot>, indexed, name, Some{ConstructorSlot{name, tag, payload}}))

def type_index_go(types: List<&2, M.DataType>, indexed: NominalIndex<M.DataType>) -> NominalIndex<M.DataType>:
  match types:
    case Nil{}:
      indexed
    case M.DataType{+identity, parameters, variants} <> tail:
      type_index_go(tail, nominal_set(M.DataType, indexed, identity, M.DataType{identity, parameters, variants}))

def type_catalog(+types: List<&2, M.DataType>) -> TypeCatalog:
  +variants = constructor_slots(types, 0n)
  TypeCatalog{variants, constructor_index_go(List.reverse(&2, ConstructorSlot, variants), Map.new(&2, Maybe<&2, ConstructorSlot>)), type_index_go(List.reverse(&2, M.DataType, types), nominal_new(M.DataType))}

def catalog_variants(catalog: TypeCatalog) -> List<&2, ConstructorSlot>:
  TypeCatalog{variants, constructors, types} = catalog
  variants

def catalog_constructors(catalog: TypeCatalog) -> Map<&2, Maybe<&2, ConstructorSlot>>:
  TypeCatalog{variants, constructors, types} = catalog
  constructors

def catalog_types(catalog: TypeCatalog) -> NominalIndex<M.DataType>:
  TypeCatalog{variants, constructors, types} = catalog
  types

def constructor_get(indexed: Map<&2, Maybe<&2, ConstructorSlot>>, name: String) -> Maybe<&2, ConstructorSlot>:
  Index.get(Maybe<&2, ConstructorSlot>, indexed, name, None{})

def lookup_tag(found: Maybe<&2, ConstructorSlot>, name: String) -> Result<&2, &2, M.Diagnostic, Nat>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"internal_error", name, "ECS storage constructor has no runtime tag"}}
    case Some{ConstructorSlot{constructor, tag, payload}}:
      Done{tag}

def lookup_type(found: Maybe<&2, M.DataType>, identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, M.DataType>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"backend_ecs_layout", M.type_id_show(identity), "ECS linking requires a declared data type; opaque nominal storage has no runtime layout"}}
    case Some{declaration}:
      Done{declaration}

def storage_layout(declaration: M.DataType, storage: M.Storage, constructors: Map<&2, Maybe<&2, ConstructorSlot>>) -> Result<&2, &2, M.Diagnostic, StorageBinding>:
  match declaration:
    case M.DataType{identity, 0n, M.Constructor{+name, Some{M.U32Ty{}}} <> Nil{}}:
      do Result<&2, &2, M.Diagnostic, StorageBinding>:
        tag : Nat <- lookup_tag(constructor_get(constructors, name), name)
        return StorageBinding{identity, storage, name, tag}
    case M.DataType{identity, parameters, variants}:
      Fail{M.Diagnostic{"backend_ecs_layout", M.type_id_show(identity), "ECS linking currently supports only zero-parameter data with exactly one constructor carrying U32"}}

def storage_bindings(descriptors: List<&2, M.Descriptor>, +catalog: TypeCatalog) -> Result<&2, &2, M.Diagnostic, List<&2, StorageBinding>>:
  match descriptors:
    case Nil{}:
      Done{Nil{}}
    case M.Descriptor{+identity, storage} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, StorageBinding>>:
        declaration : M.DataType <- lookup_type(nominal_get(M.DataType, catalog_types(catalog), identity), identity)
        binding : StorageBinding <- storage_layout(declaration, storage, catalog_constructors(catalog))
        rest : List<&2, StorageBinding> <- storage_bindings(tail, catalog)
        return binding <> rest

def register_functions(reversed: List<&2, M.CheckedFunction>, state: Effects.Descriptors) -> Effects.Descriptors:
  match reversed:
    case Nil{}:
      state
    case M.CheckedFunction{function, signature, effects} <> tail:
      register_functions(tail, Effects.registrations_reversed(List.reverse(&2, M.Effect, effects), state))

def bindings_with_catalog(functions: List<&2, M.CheckedFunction>, catalog: TypeCatalog) -> Result<&2, &2, M.Diagnostic, List<&2, StorageBinding>>:
  storage_bindings(Effects.canonical(Effects.descriptor_values(register_functions(List.reverse(&2, M.CheckedFunction, functions), Effects.Descriptors{Effects.empty_index(), Nil{}}))), catalog)

def bindings(checked: M.CheckedModule) -> Result<&2, &2, M.Diagnostic, List<&2, StorageBinding>>:
  M.CheckedModule{constants, functions, types} = checked
  bindings_with_catalog(functions, type_catalog(types))
