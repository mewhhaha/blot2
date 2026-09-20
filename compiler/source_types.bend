import Base
import ./model.bend as M
import ./cst.bend as C
import ./index.bend as Index
import ./effect_rows.bend as Rows

type Header is Data:
  Header{source: String, identity: M.TypeId, arity: Nat}

type Variable is Data:
  Variable{source: String, index: Nat}

type NodeKind is Data:
  Expression{}
  Application{}
  Atom{}
  Group{}
  Name{}

type Work is Data:
  Node{kind: NodeKind, node: C.Cst}
  Nodes{nodes: List<&2, C.Cst>}
  Target{kind: NodeKind, node: C.Cst, arguments: List<&2, M.Ty>}

def classify(+kind: String) -> NodeKind:
  Bool.pick(NodeKind, M.name_equal(kind, "type_expression"), Expression{},
    Bool.pick(NodeKind, M.name_equal(kind, "type_application"), Application{},
    Bool.pick(NodeKind, M.name_equal(kind, "type_atom"), Atom{},
    Bool.pick(NodeKind, M.name_equal(kind, "type_group"), Group{}, Name{}))))

def visit(+node: C.Cst) -> Work:
  Node{classify(C.kind_of(node)), node}

def one(types: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match types:
    case ty <> Nil{}:
      Done{ty}
    case _:
      Fail{M.Diagnostic{"internal_cst", "parser", "expected one type"}}

def grouped(types: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match types:
    case ty <> Nil{}:
      Done{ty}
    case first <> second <> tail:
      Done{M.ProductTy{first <> second <> tail}}
    case Nil{}:
      Fail{M.Diagnostic{"internal_cst", "parser", "empty type group"}}

def lookup_variable(variables: List<&2, Variable>, +name: String) -> Maybe<&2, M.Ty>:
  match variables:
    case Nil{}:
      None{}
    case Variable{source, index} <> rest:
      Bool.pick(Maybe<&2, M.Ty>, M.name_equal(source, name), Some{M.ParameterTy{index}}, lookup_variable(rest, name))

def lookup_header(headers: Map<&2, Header>, name: String) -> Maybe<&2, Header>:
  Index.find(Header, headers, name)

def require_arity(valid: Bool, result: M.Ty, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match valid:
    case True{}:
      Done{result}
    case False{}:
      Fail{C.diagnostic(node, "type_arity", "wrong number of type arguments")}

def builtin_name(array: Bool, +arguments: List<&2, M.Ty>, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match array arguments:
    case True{} element <> Nil{}:
      Done{M.ArrayTy{element}}
    case True{} _:
      Fail{C.diagnostic(node, "type_arity", "Array requires one element type")}
    case False{} _:
      do Result<&2, &2, M.Diagnostic, M.Ty>:
        scalar : M.Ty <- C.scalar_type(node)
        require_arity(List.is_empty(&2, M.Ty, arguments), scalar, node)

def named(found: Maybe<&2, Header>, variable: Maybe<&2, M.Ty>, +arguments: List<&2, M.Ty>, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match found variable:
    case _ Some{ty}:
      require_arity(List.is_empty(&2, M.Ty, arguments), ty, node)
    case Some{Header{source, identity, arity}} None{}:
      require_arity(Nat.is_eq(arity, List.length(&2, M.Ty, arguments)), M.AppliedTy{identity, arguments}, node)
    case None{} None{}:
      builtin_name(M.name_equal(C.type_name(node), "Array"), arguments, node)

def arrow(types: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match types:
    case Nil{}:
      Fail{M.Diagnostic{"internal_cst", "parser", "empty function type"}}
    case head <> Nil{}:
      Done{head}
    case head <> next <> tail:
      do Result<&2, &2, M.Diagnostic, M.Ty>:
        result : M.Ty <- arrow(next <> tail)
        return M.FunctionTy{head, result, M.empty_row()}

def effect_identity(sealed: Bool, found: Maybe<&2, M.TypeId>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.TypeId>:
  match sealed found:
    case True{} _:
      Done{M.foreign_identity()}
    case False{} Some{identity}:
      Done{identity}
    case False{} None{}:
      Fail{C.diagnostic(node, "unknown_effect", "effect rows require Foreign or a declared nominal operation")}

def row_labels(~Scope: Data, ~resolve_effect: Scope -> String -> Maybe<&2, M.TypeId>, nodes: List<&2, C.Cst>, +scope: Scope) -> Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case +node <> tail:
      +name = C.name_of(node)
      do Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
        identity : M.TypeId <- effect_identity(M.name_equal(name, "Foreign"), resolve_effect(scope, name), node)
        remaining : List<&2, M.TypeId> <- row_labels(~Scope, ~resolve_effect, tail, scope)
        return identity <> remaining

def annotated_row(~Scope: Data, ~resolve_effect: Scope -> String -> Maybe<&2, M.TypeId>, nodes: List<&2, C.Cst>, scope: Scope) -> Result<&2, &2, M.Diagnostic, Maybe<&2, M.EffectRow>>:
  match nodes:
    case Nil{}:
      Done{None{}}
    case node <> Nil{}:
      do Result<&2, &2, M.Diagnostic, Maybe<&2, M.EffectRow>>:
        labels : List<&2, M.TypeId> <- row_labels(~Scope, ~resolve_effect, C.field_values(node, "labels"), scope)
        return Some{M.EffectRow{Rows.operation_set(M.EffectRow{labels, M.ClosedRow{}}), M.ClosedRow{}}}
    case node <> tail:
      Fail{C.diagnostic(node, "internal_cst", "expected one closed effect row")}

def with_annotated_row(ty: M.Ty, row: Maybe<&2, M.EffectRow>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match ty row:
    case ty None{}:
      Done{ty}
    case M.FunctionTy{parameter, result, old_row} Some{effects}:
      Done{M.FunctionTy{parameter, result, effects}}
    case _ Some{effects}:
      Fail{C.diagnostic(node, "invalid_effect_annotation", "a closed effect row annotates a function arrow, not a value type")}

def without_arrows(nodes: List<&2, C.Cst>) -> List<&2, C.Cst>:
  match nodes:
    case Nil{}:
      Nil{}
    case +head <> tail:
      +rest = without_arrows(tail)
      Bool.pick(List<&2, C.Cst>, M.name_equal(C.kind_of(head), "->"), rest, head <> rest)

def lower(~Scope: Data, ~resolve_effect: Scope -> String -> Maybe<&2, M.TypeId>, +fuel: Nat, work: Work, +headers: Map<&2, Header>, +variables: List<&2, Variable>, +scope: Scope) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match fuel:
    case 0n:
      Fail{M.Diagnostic{"internal_cst", "parser", "type source tree exhausted its node-count bound"}}
    case 1n+remaining:
      match work:
        case Target{kind, +node, +arguments}:
          match kind:
            case Name{}:
              do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
                ty : M.Ty <- named(lookup_header(headers, C.type_name(node)), lookup_variable(variables, C.type_name(node)), arguments, node)
                return [ty]
            case _:
              do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
                nested : List<&2, M.Ty> <- lower(~Scope, ~resolve_effect, remaining, visit(node), headers, variables, scope)
                inner : M.Ty <- one(nested)
                ty : M.Ty <- require_arity(List.is_empty(&2, M.Ty, arguments), inner, node)
                return [ty]
        case Nodes{Nil{}}:
          Done{Nil{}}
        case Nodes{head <> tail}:
          do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
            ty : List<&2, M.Ty> <- lower(~Scope, ~resolve_effect, remaining, visit(head), headers, variables, scope)
            rest : List<&2, M.Ty> <- lower(~Scope, ~resolve_effect, remaining, Nodes{tail}, headers, variables, scope)
            return List.append(&2, M.Ty, ty, rest)
        case Node{kind, +node}:
          match kind:
            case Expression{}:
              do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
                types : List<&2, M.Ty> <- lower(~Scope, ~resolve_effect, remaining, Nodes{List.append(&2, C.Cst, C.field_values(node, "head"), without_arrows(C.field_values(node, "results")))}, headers, variables, scope)
                ty : M.Ty <- arrow(types)
                row : Maybe<&2, M.EffectRow> <- annotated_row(~Scope, ~resolve_effect, C.field_values(node, "effects"), scope)
                annotated : M.Ty <- with_annotated_row(ty, row, node)
                return [annotated]
            case Application{}:
              do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
                +head : C.Cst <- C.one(C.field_values(node, "head"))
                +target : C.Cst <- C.one(C.children_of(head))
                arguments : List<&2, M.Ty> <- lower(~Scope, ~resolve_effect, remaining, Nodes{C.field_values(node, "arguments")}, headers, variables, scope)
                lower(~Scope, ~resolve_effect, remaining, Target{classify(C.kind_of(target)), target, arguments}, headers, variables, scope)
            case Atom{}:
              do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
                child : C.Cst <- C.one(C.children_of(node))
                lower(~Scope, ~resolve_effect, remaining, visit(child), headers, variables, scope)
            case Group{}:
              do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
                elements : List<&2, M.Ty> <- lower(~Scope, ~resolve_effect, remaining, Nodes{C.field_values(node, "value")}, headers, variables, scope)
                ty : M.Ty <- grouped(elements)
                return [ty]
            case Name{}:
              do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
                ty : M.Ty <- named(lookup_header(headers, C.type_name(node)), lookup_variable(variables, C.type_name(node)), Nil{}, node)
                return [ty]

def annotation(~Scope: Data, ~resolve_effect: Scope -> String -> Maybe<&2, M.TypeId>, nodes: List<&2, C.Cst>, fuel: Nat, headers: Map<&2, Header>, variables: List<&2, Variable>, scope: Scope) -> Result<&2, &2, M.Diagnostic, Maybe<&2, M.Ty>>:
  match nodes:
    case Nil{}:
      Done{None{}}
    case node <> Nil{}:
      do Result<&2, &2, M.Diagnostic, Maybe<&2, M.Ty>>:
        types : List<&2, M.Ty> <- lower(~Scope, ~resolve_effect, fuel, visit(node), headers, variables, scope)
        ty : M.Ty <- one(types)
        return Some{ty}
    case marker <> node <> Nil{}:
      do Result<&2, &2, M.Diagnostic, Maybe<&2, M.Ty>>:
        types : List<&2, M.Ty> <- lower(~Scope, ~resolve_effect, fuel, visit(node), headers, variables, scope)
        ty : M.Ty <- one(types)
        return Some{ty}
    case _:
      Fail{M.Diagnostic{"internal_cst", "parser", "invalid type annotation field"}}
