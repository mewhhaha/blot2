import Base
import ./cst.bend as C
import ./model.bend as M

type Parts is Data:
  Parts{head: C.Cst, arguments: List<&2, C.Cst>}

def labelled(node: C.Cst, field: String) -> C.Cst:
  C.Cst{kind, previous, text, offset, children} = node
  C.Cst{kind, field, text, offset, children}

def atom(+node: C.Cst) -> C.Cst:
  C.Cst{"atom", "", "", C.offset_of(node), [node]}

def ordinary(node: C.Cst) -> C.Cst:
  match node:
    case C.Cst{"postfix_argument", field, text, offset, children}:
      C.Cst{"atom", field, text, offset, children}
    case node:
      node

def unwrapped(node: C.Cst) -> C.Cst:
  match node:
    case C.Cst{"atom", field, text, offset, child <> Nil{}}:
      child
    case node:
      node

def call(current: C.Cst, argument: C.Cst) -> C.Cst:
  match current:
    case C.Cst{"atom", field, text, offset, C.Cst{"call_expression", f, t, o, children} <> Nil{}}:
      atom(C.Cst{"call_expression", "", "", offset, List.append(&2, C.Cst, children, [labelled(argument, "arguments")])})
    case +current:
      atom(C.Cst{"call_expression", "", "", C.offset_of(current), [labelled(current, "head"), labelled(argument, "arguments") ]})

def index_argument(elements: List<&2, C.Cst>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, C.Cst>:
  match elements:
    case index <> Nil{}:
      Done{index}
    case _:
      Fail{C.diagnostic(node, "index_arity", "indexing requires exactly one index; separate an array argument with a space")}

def finished(nodes: List<&2, C.Cst>) -> Result<&2, &2, M.Diagnostic, Parts>:
  match nodes:
    case head <> tail:
      Done{Parts{head, tail}}
    case Nil{}:
      Fail{M.Diagnostic{"internal_cst", "application", "application lost its head"}}

type Work is Data:
  Next{nodes: List<&2, C.Cst>, current: C.Cst, reversed: List<&2, C.Cst>}
  Step{kind: String, adjacent: Bool, next: C.Cst, tail: List<&2, C.Cst>, current: C.Cst, reversed: List<&2, C.Cst>}

def collect(fuel: Nat, work: Work) -> Result<&2, &2, M.Diagnostic, Parts>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"lower_limit", "postfix", "postfix chain exceeded its structural limit"}}
    case 1n+rest Next{Nil{}, current, reversed}:
      finished(List.reverse(&2, C.Cst, current <> reversed))
    case 1n+rest Next{+next <> tail, +current, reversed}:
      collect(rest, Step{C.kind_of(unwrapped(ordinary(next))), M.name_equal(C.kind_of(next), "postfix_argument"), ordinary(next), tail, current, reversed})
    case 1n+rest Step{"member_access", adjacent, next, tail, +current, reversed}:
      do Result<&2, &2, M.Diagnostic, Parts>:
        name : C.Cst <- C.one(C.field_values(next, "name"))
        collect(rest, Next{tail, atom(C.Cst{"member_expression", "", "", C.offset_of(current), [labelled(current, "receiver"), labelled(name, "name")]}), reversed})
    case 1n+rest Step{"array", True{}, +next, tail, +current, reversed}:
      do Result<&2, &2, M.Diagnostic, Parts>:
        index : C.Cst <- index_argument(C.field_values(unwrapped(next), "elements"), next)
        collect(rest, Next{tail, atom(C.Cst{"index_expression", "", "", C.offset_of(current), [labelled(current, "receiver"), labelled(index, "index")]}), reversed})
    case 1n+rest Step{"group", True{}, next, tail, current, reversed}:
      collect(rest, Next{tail, call(current, next), reversed})
    case 1n+rest Step{kind, adjacent, next, tail, current, reversed}:
      collect(rest, Next{tail, next, current <> reversed})

def application(+node: C.Cst) -> Result<&2, &2, M.Diagnostic, Parts>:
  match node:
    case C.Cst{"call_expression", field, text, offset, children}:
      do Result<&2, &2, M.Diagnostic, Parts>:
        head : C.Cst <- C.one(C.field_values(node, "head"))
        return Parts{head, C.field_values(node, "arguments")}
    case +node:
      do Result<&2, &2, M.Diagnostic, Parts>:
        head : C.Cst <- C.one(C.field_values(node, "head"))
        collect(65536n, Next{C.field_values(node, "arguments"), head, Nil{}})

def head(parts: Parts) -> C.Cst:
  Parts{head, arguments} = parts
  head

def arguments(parts: Parts) -> List<&2, C.Cst>:
  Parts{head, arguments} = parts
  arguments
