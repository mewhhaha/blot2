import Base
import ./model.bend as M
import ./infer.bend as I
import ./closures.bend as F
import ./core_rebuild.bend as Core
import ./index.bend as Index

# Inference records demand mode at each source call. The checked tree owns the
# suspension, so specialization, aliases, and both backends see the same code.
def sites(coverage: List<&2, I.Coverage>, found: Set()) -> Set():
  match coverage:
    case Nil{}:
      found
    case I.DemandCall{site} <> tail:
      sites(tail, Set.add(found, Nat.show(site)))
    case head <> tail:
      sites(tail, found)

def suspend(expression: M.Expr, +site: Nat) -> M.Expr:
  match expression:
    case M.ApplyExpr{callee, argument}:
      M.ApplyExpr{callee, M.suspend_argument(site, argument)}
    case M.CallExpr{callee, argument}:
      M.CallExpr{callee, M.suspend_argument(site, argument)}
    case value:
      value

def replace(expression: M.Expr, +calls: Set()) -> M.Expr:
  match expression:
    case M.InstantiationExpr{+site, +value}:
      M.InstantiationExpr{site, Bool.pick(M.Expr, Maybe.is_some(&2, Unit, Index.find(Unit, calls, Nat.show(site))), suspend(value, site), value)}
    case value:
      value

type Work is Data:
  Expression{value: M.Expr}
  Expressions{values: List<&2, M.Expr>}

def elaborate(+fuel: Nat, work: Work, +calls: Set()) -> Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"backend_limit", "demand", "demand elaboration exceeded its structural limit"}}
    case 1n+rest Expression{+value}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        children : List<&2, M.Expr> <- elaborate(rest, Expressions{F.children(value)}, calls)
        rebuilt : M.Expr <- Core.rebuild(value, children, 0n)
        return [replace(rebuilt, calls)]
    case 1n+rest Expressions{Nil{}}:
      Done{Nil{}}
    case 1n+rest Expressions{head <> tail}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        value : List<&2, M.Expr> <- elaborate(rest, Expression{head}, calls)
        remaining : List<&2, M.Expr> <- elaborate(rest, Expressions{tail}, calls)
        return List.append(&2, M.Expr, value, remaining)

def first(values: List<&2, M.Expr>) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match values:
    case value <> Nil{}:
      Done{value}
    case _:
      Fail{M.Diagnostic{"internal_error", "demand", "expected one elaborated expression"}}

def expression_work(value: M.Expr, calls: Set()) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  do Result<&2, &2, M.Diagnostic, M.Expr>:
    values : List<&2, M.Expr> <- elaborate(65536n, Expression{value}, calls)
    first(values)


def expression(value: M.Expr, calls: Set()) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match calls:
    case MTip{}:
      Done{value}
    case remaining:
      expression_work(value, remaining)
