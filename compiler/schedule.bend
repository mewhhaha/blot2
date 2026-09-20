import Base
import ./model.bend as M
import ./effects.bend as E

# Until the engine specifies deferred structural commands, insertion is a
# barrier: adding one component can move an entity's other component columns.
def structural(access: M.Access) -> Bool:
  match access:
    case M.Insert{}:
      True{}
    case _:
      False{}

def has_structural(effects: List<&2, M.Effect>) -> Bool:
  match effects:
    case Nil{}:
      False{}
    case M.Effect{access, descriptor} <> tail:
      E.or_else(structural(access), _ => has_structural(tail))

def conflicts_with(+effect: M.Effect, effects: List<&2, M.Effect>) -> Bool:
  match effects:
    case Nil{}:
      False{}
    case head <> tail:
      E.or_else(E.conflicts(effect, head), _ => conflicts_with(effect, tail))

def mask_conflicts(access: M.Access, previous: U32) -> Bool:
  match access:
    case M.Read{}:
      U32.is_ne(U32.and(previous, 6), 0)
    case _:
      U32.is_ne(previous, 0)

def row_index_conflicts(effects: List<&2, M.Effect>, +index: E.IdentityIndex()) -> Bool:
  match effects:
    case Nil{}:
      False{}
    case M.Effect{access, M.Descriptor{identity, storage}} <> tail:
      E.or_else(mask_conflicts(access, E.index_mask(index, identity)), _ => row_index_conflicts(tail, index))

def row_conflicts(left: List<&2, M.Effect>, right: List<&2, M.Effect>) -> Bool:
  row_index_conflicts(left, E.index_effects(right, E.empty_index()))

def separates(+left: List<&2, M.Effect>, +right: List<&2, M.Effect>) -> Bool:
  E.or_else(Bool.or(has_structural(left), has_structural(right)), _ => row_conflicts(left, right))

type Batches is Data:
  Batches{current: List<&2, String>, effects: List<&2, M.Effect>, completed: List<&2, List<&2, String>>}

def add(separate: Bool, name: String, effects: List<&2, M.Effect>, state: Batches) -> Batches:
  match separate state:
    case True{} Batches{Nil{}, previous, completed}:
      Batches{[name], effects, completed}
    case True{} Batches{head <> tail, previous, completed}:
      Batches{[name], effects, List.reverse(&2, String, head <> tail) <> completed}
    case False{} Batches{current, previous, completed}:
      Batches{name <> current, E.union(effects, previous), completed}

def current_effects(state: Batches) -> List<&2, M.Effect>:
  Batches{current, effects, completed} = state
  effects

def finish(state: Batches) -> List<&2, List<&2, String>>:
  match state:
    case Batches{Nil{}, effects, completed}:
      List.reverse(&2, List<&2, String>, completed)
    case Batches{current, effects, completed}:
      List.reverse(&2, List<&2, String>, List.reverse(&2, String, current) <> completed)

type IndexedBatches is Data:
  IndexedBatches{current: List<&2, String>, index: E.IdentityIndex(), barrier: Bool, completed: List<&2, List<&2, String>>}

def batch_index(barrier: Bool, effects: List<&2, M.Effect>) -> E.IdentityIndex():
  match barrier:
    case True{}:
      E.empty_index()
    case False{}:
      E.index_effects(effects, E.empty_index())

def add_indexed(separate: Bool, name: String, effects: List<&2, M.Effect>, +barrier: Bool, state: IndexedBatches) -> IndexedBatches:
  match separate state:
    case True{} IndexedBatches{Nil{}, previous, previous_barrier, completed}:
      IndexedBatches{[name], batch_index(barrier, effects), barrier, completed}
    case True{} IndexedBatches{head <> tail, previous, previous_barrier, completed}:
      IndexedBatches{[name], batch_index(barrier, effects), barrier, List.reverse(&2, String, head <> tail) <> completed}
    case False{} IndexedBatches{current, previous, previous_barrier, completed}:
      IndexedBatches{name <> current, E.index_effects(effects, previous), barrier, completed}

def add_system(name: String, +effects: List<&2, M.Effect>, state: IndexedBatches) -> IndexedBatches:
  IndexedBatches{current, +index, +barrier, completed} = state
  +next_barrier = has_structural(effects)
  add_indexed(E.or_else(Bool.or(barrier, next_barrier), _ => row_index_conflicts(effects, index)), name, effects, next_barrier, IndexedBatches{current, index, barrier, completed})

def collect_indexed(systems: List<&2, M.SystemPlan>, state: IndexedBatches) -> List<&2, List<&2, String>>:
  match systems state:
    case Nil{} IndexedBatches{current, index, barrier, completed}:
      finish(Batches{current, Nil{}, completed})
    case M.SystemPlan{name, effects, query} <> tail state:
      collect_indexed(tail, add_system(name, effects, state))

# Contiguous batches preserve the supplied order across every conflict.
# This is conservative, deterministic metadata, not an execution runtime.
def collect(systems: List<&2, M.SystemPlan>, state: Batches) -> List<&2, List<&2, String>>:
  Batches{current, +effects, completed} = state
  +barrier = has_structural(effects)
  collect_indexed(systems, IndexedBatches{current, batch_index(barrier, effects), barrier, completed})

def batches(systems: List<&2, M.SystemPlan>) -> List<&2, List<&2, String>>:
  collect(systems, Batches{Nil{}, Nil{}, Nil{}})
