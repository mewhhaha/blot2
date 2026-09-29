import Base
import ./infer.bend as I
import ./index.bend as Index

# A component's binding list is immutable until generalization. Index it once
# for a multi-declaration component, retaining every duplicate and its original
# position: local generalization observes the complete ordered environment.
type Entry is Data:
  Entry{position: Nat, binding: I.Binding}

type Selection is Data:
  Selection{entries: List<&2, Entry>, seen: Set()}

def build(bindings: List<&2, I.Binding>, +position: Nat, index: Map<&2, List<&2, Entry>>) -> Map<&2, List<&2, Entry>>:
  match bindings:
    case Nil{}:
      index
    case +binding <> tail:
      I.Binding{+name, ty, variables, predicates} = binding
      +known = index
      prior = Index.get(List<&2, Entry>, known, name, Nil{})
      build(tail, 1n+position, Index.set(List<&2, Entry>, known, name, Entry{position, binding} <> prior))

def choose(before: Bool, first: Unit -> List<&2, Entry>, later: Unit -> List<&2, Entry>) -> List<&2, Entry>:
  match before:
    case True{}:
      first(Unit{})
    case False{}:
      later(Unit{})

def insert(entries: List<&2, Entry>, +item: Entry) -> List<&2, Entry>:
  match entries:
    case Nil{}:
      item <> Nil{}
    case +head <> +tail:
      Entry{position, binding} = head
      Entry{target, item_binding} = item
      choose(Nat.is_lt(target, position), unit => item <> head <> tail, unit => head <> insert(tail, item))

def add(entries: List<&2, Entry>, selected: List<&2, Entry>) -> List<&2, Entry>:
  match entries:
    case Nil{}:
      selected
    case head <> tail:
      add(tail, insert(selected, head))

def present(found: Maybe<&2, Unit>) -> Bool:
  match found:
    case None{}:
      False{}
    case Some{value}:
      True{}

def select_name(found: Bool, name: String, index: Map<&2, List<&2, Entry>>, selection: Selection) -> Selection:
  match found:
    case True{}:
      selection
    case False{}:
      Selection{entries, seen} = selection
      +key = name
      Selection{add(Index.get(List<&2, Entry>, index, key, Nil{}), entries), Set.add(seen, key)}

def select(names: List<&2, String>, +index: Map<&2, List<&2, Entry>>, selection: Selection) -> Selection:
  match names:
    case Nil{}:
      selection
    case +name <> tail:
      Selection{entries, +seen} = selection
      select(tail, index, select_name(present(Index.find(Unit, seen, name)), name, index, Selection{entries, seen}))

def bindings(entries: List<&2, Entry>) -> List<&2, I.Binding>:
  match entries:
    case Nil{}:
      Nil{}
    case Entry{position, binding} <> tail:
      binding <> bindings(tail)

def selected(selection: Selection) -> List<&2, I.Binding>:
  Selection{entries, seen} = selection
  bindings(entries)

def referenced(index: Map<&2, List<&2, Entry>>, names: List<&2, String>) -> List<&2, I.Binding>:
  selected(select(names, index, Selection{Nil{}, Set.new()}))
