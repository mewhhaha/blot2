import Base
import ./model.bend as M
import ./index.bend as Index

def requires_entity(access: M.Access, storage: M.Storage) -> Bool:
  match access storage:
    case M.Read{} M.Component{}:
      True{}
    case M.Write{} M.Component{}:
      True{}
    case _ _:
      False{}

def is_write(access: M.Access) -> Bool:
  match access:
    case M.Read{}:
      False{}
    case M.Write{}:
      True{}
    case M.Insert{}:
      True{}

def access_equal(a: M.Access, b: M.Access) -> Bool:
  match a b:
    case M.Read{} M.Read{}:
      True{}
    case M.Write{} M.Write{}:
      True{}
    case M.Insert{} M.Insert{}:
      True{}
    case _ _:
      False{}

def effect_identity_equal(same_access: Bool, left: M.TypeId, right: M.TypeId) -> Bool:
  match same_access:
    case False{}:
      False{}
    case True{}:
      M.type_id_equal(left, right)

def effect_equal(a: M.Effect, b: M.Effect) -> Bool:
  M.Effect{aa, M.Descriptor{ai, ast}} = a
  M.Effect{ba, M.Descriptor{bi, bst}} = b
  effect_identity_equal(access_equal(aa, ba), ai, bi)

def conflicts(a: M.Effect, b: M.Effect) -> Bool:
  M.Effect{aa, M.Descriptor{ai, ast}} = a
  M.Effect{ba, M.Descriptor{bi, bst}} = b
  same_identity writes = M.type_id_equal(ai, bi) Bool.or(is_write(aa), is_write(ba))
  Bool.and(same_identity, writes)

def or_else(found: Bool, next: Unit -> Bool) -> Bool:
  match found:
    case True{}:
      True{}
    case False{}:
      next(Unit{})

def contains(effects: List<&2, M.Effect>, +effect: M.Effect) -> Bool:
  match effects:
    case Nil{}:
      False{}
    case head <> tail:
      or_else(effect_equal(head, effect), _ => contains(tail, effect))

def put_if(present: Bool, effects: List<&2, M.Effect>, effect: M.Effect) -> List<&2, M.Effect>:
  match present:
    case True{}:
      effects
    case False{}:
      effect <> effects

def put(+effects: List<&2, M.Effect>, +effect: M.Effect) -> List<&2, M.Effect>:
  put_if(contains(effects, effect), effects, effect)

def IdentityIndex() -> Data:
  Map<&2, Map<&2, U32>>

def empty_index() -> IdentityIndex():
  Map.new(&2, Map<&2, U32>)

def access_mask(access: M.Access) -> U32:
  match access:
    case M.Read{}:
      1
    case M.Write{}:
      2
    case M.Insert{}:
      4

def module_index(index: IdentityIndex(), module_name: String) -> Map<&2, U32>:
  Index.get(Map<&2, U32>, index, module_name, Map.new(&2, U32))

def index_mask(index: IdentityIndex(), identity: M.TypeId) -> U32:
  M.TypeId{module_name, declaration} = identity
  Index.get(U32, module_index(index, module_name), declaration, 0)

def index_marked(present: Bool, index: IdentityIndex(), module_name: String, declarations: Map<&2, U32>, declaration: String, mask: U32) -> IdentityIndex() & Bool:
  match present:
    case True{}:
      (index, True{})
    case False{}:
      (Map.set(&2, Map<&2, U32>, index, module_name, Map.set(&2, U32, declarations, declaration, mask)), False{})

# Modules and declarations are separate map levels, never delimiter-joined keys.
def index_mark(+index: IdentityIndex(), identity: M.TypeId, +mask: U32) -> IdentityIndex() & Bool:
  M.TypeId{+module_name, +declaration} = identity
  +declarations = module_index(index, module_name)
  +previous = Index.get(U32, declarations, declaration, 0)
  index_marked(U32.is_eq(U32.and(previous, mask), mask), index, module_name, declarations, declaration, U32.or(previous, mask))

def marked_index(result: IdentityIndex() & Bool) -> IdentityIndex():
  (index, present) = result
  index

def index_effects(effects: List<&2, M.Effect>, index: IdentityIndex()) -> IdentityIndex():
  match effects:
    case Nil{}:
      index
    case M.Effect{access, M.Descriptor{identity, storage}} <> tail:
      index_effects(tail, marked_index(index_mark(index, identity, access_mask(access))))

type IndexedEffects is Data:
  IndexedEffects{index: IdentityIndex(), values: List<&2, M.Effect>}

def union_insert(marked: IdentityIndex() & Bool, effect: M.Effect, values: List<&2, M.Effect>) -> IndexedEffects:
  (index, present) = marked
  IndexedEffects{index, put_if(present, values, effect)}

def union_indexed(reversed: List<&2, M.Effect>, state: IndexedEffects) -> List<&2, M.Effect>:
  match reversed state:
    case Nil{} IndexedEffects{index, values}:
      values
    case M.Effect{+access, M.Descriptor{+identity, storage}} <> tail IndexedEffects{index, values}:
      union_indexed(tail, union_insert(index_mark(index, identity, access_mask(access)), M.Effect{access, M.Descriptor{identity, storage}}, values))

# Tiny rows avoid constructing an index; larger rows deduplicate in one pass.
# The right row is retained verbatim, and last occurrences from the left win.
def union(left: List<&2, M.Effect>, +right: List<&2, M.Effect>) -> List<&2, M.Effect>:
  match left:
    case Nil{}:
      right
    case a <> Nil{}:
      put(right, a)
    case a <> b <> Nil{}:
      put(put(right, b), a)
    case a <> b <> c <> Nil{}:
      put(put(put(right, c), b), a)
    case a <> b <> c <> d <> Nil{}:
      put(put(put(put(right, d), c), b), a)
    case other:
      union_indexed(List.reverse(&2, M.Effect, other), IndexedEffects{index_effects(right, empty_index()), right})

def descriptor_contains(descriptors: List<&2, M.Descriptor>, +identity: M.TypeId) -> Bool:
  match descriptors:
    case Nil{}:
      False{}
    case M.Descriptor{found, storage} <> tail:
      or_else(M.type_id_equal(found, identity), _ => descriptor_contains(tail, identity))

def descriptor_put_if(present: Bool, descriptors: List<&2, M.Descriptor>, descriptor: M.Descriptor) -> List<&2, M.Descriptor>:
  match present:
    case True{}:
      descriptors
    case False{}:
      descriptor <> descriptors

def descriptor_put(+descriptors: List<&2, M.Descriptor>, descriptor: M.Descriptor) -> List<&2, M.Descriptor>:
  M.Descriptor{+identity, +storage} = descriptor
  descriptor_put_if(descriptor_contains(descriptors, identity), descriptors, M.Descriptor{identity, storage})

type Descriptors is Data:
  Descriptors{index: IdentityIndex(), values: List<&2, M.Descriptor>}

def register_marked(marked: IdentityIndex() & Bool, descriptor: M.Descriptor, values: List<&2, M.Descriptor>) -> Descriptors:
  (index, present) = marked
  Descriptors{index, descriptor_put_if(present, values, descriptor)}

def register(descriptor: M.Descriptor, state: Descriptors) -> Descriptors:
  M.Descriptor{+identity, storage} = descriptor
  Descriptors{index, values} = state
  register_marked(index_mark(index, identity, 1), M.Descriptor{identity, storage}, values)

def registrations_reversed(reversed: List<&2, M.Effect>, state: Descriptors) -> Descriptors:
  match reversed:
    case Nil{}:
      state
    case M.Effect{access, descriptor} <> tail:
      registrations_reversed(tail, register(descriptor, state))

def descriptor_values(state: Descriptors) -> List<&2, M.Descriptor>:
  Descriptors{index, values} = state
  values

def short_row(effects: List<&2, M.Effect>) -> Bool:
  match effects:
    case Nil{}:
      True{}
    case _ <> Nil{}:
      True{}
    case _ <> _ <> Nil{}:
      True{}
    case _ <> _ <> _ <> Nil{}:
      True{}
    case _ <> _ <> _ <> _ <> Nil{}:
      True{}
    case _:
      False{}

def registrations_scan(effects: List<&2, M.Effect>) -> List<&2, M.Descriptor>:
  match effects:
    case Nil{}:
      Nil{}
    case M.Effect{access, descriptor} <> tail:
      descriptor_put(registrations_scan(tail), descriptor)

def registrations_choose(short: Bool, effects: List<&2, M.Effect>) -> List<&2, M.Descriptor>:
  match short:
    case True{}:
      registrations_scan(effects)
    case False{}:
      descriptor_values(registrations_reversed(List.reverse(&2, M.Effect, effects), Descriptors{empty_index(), Nil{}}))

# Registration includes inserts and resources; entity filtering does not.
def registrations(+effects: List<&2, M.Effect>) -> List<&2, M.Descriptor>:
  registrations_choose(short_row(effects), effects)

def system_registrations_reversed(reversed: List<&2, M.SystemPlan>, state: Descriptors) -> Descriptors:
  match reversed:
    case Nil{}:
      state
    case M.SystemPlan{name, effects, query} <> tail:
      system_registrations_reversed(tail, registrations_reversed(List.reverse(&2, M.Effect, effects), state))

# Equivalent to registrations of the union of all rows, without rebuilding a
# growing flat effect row for each system.
def system_registrations(systems: List<&2, M.SystemPlan>) -> List<&2, M.Descriptor>:
  descriptor_values(system_registrations_reversed(List.reverse(&2, M.SystemPlan, systems), Descriptors{empty_index(), Nil{}}))

def query_put(required: Bool, descriptors: List<&2, M.Descriptor>, descriptor: M.Descriptor) -> List<&2, M.Descriptor>:
  match required:
    case False{}:
      descriptors
    case True{}:
      descriptor_put(descriptors, descriptor)

def register_required(required: Bool, descriptor: M.Descriptor, state: Descriptors) -> Descriptors:
  match required:
    case False{}:
      state
    case True{}:
      register(descriptor, state)

def query_reversed(reversed: List<&2, M.Effect>, state: Descriptors) -> Descriptors:
  match reversed:
    case Nil{}:
      state
    case M.Effect{access, M.Descriptor{identity, +storage}} <> tail:
      query_reversed(tail, register_required(requires_entity(access, storage), M.Descriptor{identity, storage}, state))

def query_scan(effects: List<&2, M.Effect>) -> List<&2, M.Descriptor>:
  match effects:
    case Nil{}:
      Nil{}
    case M.Effect{access, M.Descriptor{identity, +storage}} <> tail:
      query_put(requires_entity(access, storage), query_scan(tail), M.Descriptor{identity, storage})

def query_choose(short: Bool, effects: List<&2, M.Effect>) -> List<&2, M.Descriptor>:
  match short:
    case True{}:
      query_scan(effects)
    case False{}:
      descriptor_values(query_reversed(List.reverse(&2, M.Effect, effects), Descriptors{empty_index(), Nil{}}))

def query(+effects: List<&2, M.Effect>) -> List<&2, M.Descriptor>:
  query_choose(short_row(effects), effects)

def descriptor_le(left: M.Descriptor, right: M.Descriptor) -> Bool:
  M.Descriptor{M.TypeId{+lm, ln}, ls} = left
  M.Descriptor{M.TypeId{+rm, rn}, rs} = right
  Bool.or(String.is_lt(lm, rm), Bool.and(M.name_equal(lm, rm), String.is_le(ln, rn)))

def canonical(descriptors: List<&2, M.Descriptor>) -> List<&2, M.Descriptor>:
  List.sort(~M.Descriptor, ~descriptor_le, descriptors)
