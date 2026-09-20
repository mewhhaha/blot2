import Base
import ./model.bend as M
import ./cst.bend as C

type Associativity is Data:
  Left{}
  Right{}
  NonAssociative{}

type Fixity is Data:
  Fixity{name: String, named: Bool, precedence: U32, associativity: Associativity, target: M.Expr}

type Operator is Data:
  Operator{precedence: U32, associativity: Associativity, target: M.Expr, offset: Nat}

type Tail is Data:
  Tail{operator: Operator, right: M.Expr}

type Decision is Data:
  Push{}
  Reduce{}
  Conflict{}

type Work is Data:
  Read{tails: List<&2, Tail>}
  Insert{decision: Decision, operator: Operator, right: M.Expr, tails: List<&2, Tail>}
  Finish{}

def parse_associativity(+name: String) -> Associativity:
  Bool.pick(Associativity, M.name_equal(name, "infixl"), Left{},
    Bool.pick(Associativity, M.name_equal(name, "infixr"), Right{}, NonAssociative{}))

def same_direction(left: Associativity, right: Associativity) -> Bool:
  match left right:
    case Left{} Left{}:
      True{}
    case Right{} Right{}:
      True{}
    case _ _:
      False{}

def equal_decision(association: Associativity, compatible: Bool) -> Decision:
  match association compatible:
    case Left{} True{}:
      Reduce{}
    case Right{} True{}:
      Push{}
    case _ _:
      Conflict{}

def decision(operator: Operator, stack: List<&2, Operator>) -> Decision:
  match operator stack:
    case _ Nil{}:
      Push{}
    case Operator{+precedence, +association, target, offset} Operator{+top_precedence, top_association, top_target, top_offset} <> rest:
      Bool.pick(Decision, U32.is_lt(top_precedence, precedence), Push{},
        Bool.pick(Decision, U32.is_lt(precedence, top_precedence), Reduce{}, equal_decision(association, same_direction(association, top_association))))

def invoke(callee: M.Expr, argument: M.Expr) -> M.Expr:
  match callee:
    case M.FunctionExpr{name}:
      M.CallExpr{name, argument}
    case value:
      M.ApplyExpr{value, argument}

def reduce(operator: Operator, left: M.Expr, right: M.Expr) -> M.Expr:
  Operator{precedence, associativity, target, offset} = operator
  M.SourceExpr{offset, None{}, M.ApplyExpr{invoke(target, left), right}}

def resolve(fuel: Nat, work: Work, values: List<&2, M.Expr>, operators: List<&2, Operator>) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match fuel:
    case 0n:
      Fail{M.Diagnostic{"internal_cst", "parser", "operator chain exhausted its work bound"}}
    case 1n+remaining:
      match work values operators:
        case Read{Nil{}} values operators:
          resolve(remaining, Finish{}, values, operators)
        case Read{Tail{+operator, right} <> rest} values +operators:
          resolve(remaining, Insert{decision(operator, operators), operator, right, rest}, values, operators)
        case Insert{Push{}, operator, right, rest} values operators:
          resolve(remaining, Read{rest}, right <> values, operator <> operators)
        case Insert{Conflict{}, Operator{precedence, association, target, offset}, right, rest} values operators:
          Fail{M.Diagnostic{"operator_associativity", "offset:" ++ Nat.show(offset), "operators at equal precedence need compatible associativity or explicit parentheses"}}
        case Insert{Reduce{}, +operator, right, rest} previous_right <> previous_left <> values top <> +operators:
          resolve(remaining, Insert{decision(operator, operators), operator, right, rest}, reduce(top, previous_left, previous_right) <> values, operators)
        case Finish{} value <> Nil{} Nil{}:
          Done{value}
        case Finish{} right <> left <> values top <> operators:
          resolve(remaining, Finish{}, reduce(top, left, right) <> values, operators)
        case _ _ _:
          Fail{M.Diagnostic{"internal_cst", "parser", "invalid operator stack"}}

def same_bool(left: Bool, right: Bool) -> Bool:
  match left right:
    case True{} True{}:
      True{}
    case False{} False{}:
      True{}
    case _ _:
      False{}

def lookup(fixities: List<&2, Fixity>, +name: String, +named: Bool) -> Maybe<&2, Fixity>:
  match fixities:
    case Nil{}:
      None{}
    case Fixity{+spelling, +is_named, +precedence, +association, +target} <> rest:
      Bool.pick(Maybe<&2, Fixity>, Bool.and(M.name_equal(spelling, name), same_bool(is_named, named)), Some{Fixity{spelling, is_named, precedence, association, target}}, lookup(rest, name, named))

def from_fixity(fixity: Fixity, offset: Nat) -> Operator:
  Fixity{name, named, precedence, associativity, target} = fixity
  Operator{precedence, associativity, target, offset}
