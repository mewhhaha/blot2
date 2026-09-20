import Base
import ./model.bend as M
import ./index.bend as Index

type ConstructorSlot is Data:
  ConstructorSlot{name: String, tag: Nat, payload: Bool}

type TypeCatalog is Data:
  TypeCatalog{variants: List<&2, ConstructorSlot>, constructors: Map<&2, Maybe<&2, ConstructorSlot>>}

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

def type_catalog(types: List<&2, M.DataType>) -> TypeCatalog:
  +variants = constructor_slots(types, 0n)
  TypeCatalog{variants, constructor_index_go(List.reverse(&2, ConstructorSlot, variants), Map.new(&2, Maybe<&2, ConstructorSlot>))}

def catalog_variants(catalog: TypeCatalog) -> List<&2, ConstructorSlot>:
  TypeCatalog{variants, constructors} = catalog
  variants

def catalog_constructors(catalog: TypeCatalog) -> Map<&2, Maybe<&2, ConstructorSlot>>:
  TypeCatalog{variants, constructors} = catalog
  constructors

def constructor_get(indexed: Map<&2, Maybe<&2, ConstructorSlot>>, name: String) -> Maybe<&2, ConstructorSlot>:
  Index.get(Maybe<&2, ConstructorSlot>, indexed, name, None{})
