import Base
import ./model.bend as M
import ./dependency.bend as D
import ./index.bend as Index

type Initializer is Data:
  Initializer{name: String, value: M.Expr}

def bindings(constants: List<&2, M.CheckedConstant>) -> List<&2, Initializer>:
  match constants:
    case Nil{}:
      Nil{}
    case M.CheckedConstant{M.Constant{name, exported, annotation, M.RuntimeInitExpr{value}}, ty, variables} <> tail:
      Initializer{name, value} <> bindings(tail)
    case head <> tail:
      bindings(tail)

def index(initializers: List<&2, Initializer>, indexed: Map<&2, Initializer>) -> Map<&2, Initializer>:
  match initializers:
    case Nil{}:
      indexed
    case +initializer <> tail:
      Initializer{name, value} = initializer
      index(tail, Map.set(&2, Initializer, indexed, name, initializer))

def function_nodes(functions: List<&2, M.CheckedFunction>) -> Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
  match functions:
    case Nil{}:
      Done{Nil{}}
    case M.CheckedFunction{function, signature, effects} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
        nodes : List<&2, D.Node> <- D.function_nodes([function])
        rest : List<&2, D.Node> <- function_nodes(tail)
        return List.append(&2, D.Node, nodes, rest)

def constant_nodes(constants: List<&2, M.CheckedConstant>) -> Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
  match constants:
    case Nil{}:
      Done{Nil{}}
    case M.CheckedConstant{constant, ty, variables} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
        nodes : List<&2, D.Node> <- D.constant_nodes([constant])
        rest : List<&2, D.Node> <- constant_nodes(tail)
        return List.append(&2, D.Node, nodes, rest)

def prepend(found: Maybe<&2, Initializer>, rest: List<&2, Initializer>) -> List<&2, Initializer>:
  match found:
    case None{}:
      rest
    case Some{initializer}:
      initializer <> rest

def members(names: List<&2, String>, +indexed: Map<&2, Initializer>) -> List<&2, Initializer>:
  match names:
    case Nil{}:
      Nil{}
    case name <> tail:
      prepend(Index.find(Initializer, indexed, name), members(tail, indexed))

def ordered_component(initializers: List<&2, Initializer>, cyclic: Bool) -> Result<&2, &2, M.Diagnostic, List<&2, Initializer>>:
  match initializers cyclic:
    case Nil{} _:
      Done{Nil{}}
    case initializers False{}:
      Done{initializers}
    case Initializer{name, value} <> tail True{}:
      Fail{M.Diagnostic{"initialization_cycle", name, "top-level let initializers form a dependency cycle"}}

def ordered(components: List<&2, List<&2, String>>, +indexed: Map<&2, Initializer>, +edges: Map<&2, List<&2, String>>) -> Result<&2, &2, M.Diagnostic, List<&2, Initializer>>:
  match components:
    case Nil{}:
      Done{Nil{}}
    case Nil{} <> tail:
      ordered(tail, indexed, edges)
    case (+name <> +following) <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Initializer>>:
        head : List<&2, Initializer> <- ordered_component(members(name <> following, indexed), Bool.or(Bool.not(List.is_empty(&2, String, following)), D.contains(D.neighbors(edges, name), name)))
        rest : List<&2, Initializer> <- ordered(tail, indexed, edges)
        return List.append(&2, Initializer, head, rest)

def plan(initializers: List<&2, Initializer>, constants: List<&2, M.CheckedConstant>, functions: List<&2, M.CheckedFunction>) -> Result<&2, &2, M.Diagnostic, List<&2, Initializer>>:
  match initializers:
    case Nil{}:
      Done{Nil{}}
    case initializers:
      do Result<&2, &2, M.Diagnostic, List<&2, Initializer>>:
        fn_nodes : List<&2, D.Node> <- function_nodes(functions)
        const_nodes : List<&2, D.Node> <- constant_nodes(constants)
        +graph : List<&2, D.Node> = List.append(&2, D.Node, fn_nodes, const_nodes)
        components : List<&2, List<&2, String>> <- D.components(graph)
        ordered(components, index(initializers, MTip{}), D.adjacency(graph, MTip{}))
