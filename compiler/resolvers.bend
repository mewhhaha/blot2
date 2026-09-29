import Base
import ./model.bend as M
import ./closures.bend as Closures
import ./index.bend as Index
import ./core_rebuild.bend as Rebuild
import ./resolver_loops.bend as Loops

# Resolver values and type-constructor witnesses have ordinary nominal data
# representations. Their inaccessible names keep the protocol independent of
# prelude names, aliases, and user constructor spellings.
def monad_identity() -> M.TypeId:
  M.TypeId{"blot:resolver", "Monad"}

def monad_constructor() -> String:
  "$resolver.monad"

def monad_data() -> M.DataType:
  M.DataType{monad_identity(), 1n, [M.Constructor{monad_constructor(), Some{M.ParameterTy{0n}}, Nil{}}]}

def token_identity(identity: M.TypeId) -> M.TypeId:
  M.TypeId{module_name, declaration} = identity
  M.TypeId{module_name, "$type$" ++ declaration}

def token_constructor(identity: M.TypeId) -> String:
  M.TypeId{+module_name, declaration} = identity
  "$type[" ++ Nat.show(String.length(module_name)) ++ ":" ++ module_name ++ "]" ++ declaration

def token_value(identity: M.TypeId) -> M.Expr:
  M.ConstructExpr{token_constructor(identity), None{}}

def token_data(identity: M.TypeId) -> M.DataType:
  +original = identity
  M.DataType{token_identity(original), 0n, [M.Constructor{token_constructor(original), None{}, Nil{}}]}

def token_owner(ty: M.Ty) -> Maybe<&2, M.TypeId>:
  match ty:
    case M.AppliedTy{M.TypeId{module_name, +declaration}, Nil{}}:
      Bool.pick(Maybe<&2, M.TypeId>, String.starts_with(declaration, "$type$"), Some{M.TypeId{module_name, String.drop(declaration, 6n)}}, None{})
    case _:
      None{}

def monad_owner(ty: M.Ty) -> Maybe<&2, M.TypeId>:
  match ty:
    case M.AppliedTy{identity, token <> Nil{}}:
      Bool.pick(Maybe<&2, M.TypeId>, M.type_id_equal(identity, monad_identity()), token_owner(token), None{})
    case _:
      None{}

def requested(fuel: Nat, pending: List<&2, M.Expr>, names: Set()) -> Set():
  match fuel pending:
    case _ Nil{}:
      names
    case 0n _:
      names
    case 1n+rest M.ConstructExpr{+constructor, None{}} <> tail:
      requested(rest, tail, Set.add(names, constructor))
    case 1n+rest M.AssociatedExpr{site, dispatch, "@do.monad", templates, left, right} <> tail:
      requested(rest, left <> right <> tail, Set.add(names, monad_constructor()))
    case 1n+rest M.AssociatedExpr{site, dispatch, "@do.run", templates, left, right} <> tail:
      requested(rest, left <> right <> tail, Set.add(names, "$resolver$blocks"))
    case 1n+rest value <> tail:
      requested(rest, List.append(&2, M.Expr, Closures.children(value), tail), names)

def function_requests(functions: List<&2, M.Function>, names: Set()) -> Set():
  match functions:
    case Nil{}:
      names
    case M.Function{name, exported, param, p, r, body} <> tail:
      function_requests(tail, requested(1048576n, [body], names))

def constant_requests(constants: List<&2, M.Constant>, names: Set()) -> Set():
  match constants:
    case Nil{}:
      names
    case M.Constant{name, exported, annotation, value} <> tail:
      constant_requests(tail, requested(1048576n, [value], names))

def type_names(types: List<&2, M.DataType>, names: Set()) -> Set():
  match types:
    case Nil{}:
      names
    case M.DataType{identity, parameters, constructors} <> tail:
      type_names(tail, Set.add(names, M.type_id_show(identity)))

def requested_types(types: List<&2, M.DataType>, +names: Set(), +known: Set()) -> List<&2, M.DataType>:
  match types:
    case Nil{}:
      Nil{}
    case M.DataType{+identity, parameters, constructors} <> tail:
      +rest = requested_types(tail, names, known)
      needed = Bool.and(Maybe.is_some(&2, Unit, Index.find(Unit, names, token_constructor(identity))), Bool.not(Maybe.is_some(&2, Unit, Index.find(Unit, known, M.type_id_show(token_identity(identity))))))
      Bool.pick(List<&2, M.DataType>, needed, token_data(identity) <> rest, rest)

def add_types(+module: M.Module) -> M.Module:
  M.Module{+constants, +functions, +types, operations} = module
  +names = constant_requests(constants, function_requests(functions, Set.new()))
  +known = type_names(types, Set.new())
  +tokens = requested_types(types, names, known)
  needed = Bool.and(Maybe.is_some(&2, Unit, Index.find(Unit, names, monad_constructor())), Bool.not(Maybe.is_some(&2, Unit, Index.find(Unit, known, M.type_id_show(monad_identity())))))
  +extra = Bool.pick(List<&2, M.DataType>, needed, monad_data() <> tokens, tokens)
  M.Module{constants, functions, List.append(&2, M.DataType, types, extra), operations}

def one(expressions: List<&2, M.Expr>) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match expressions:
    case expression <> Nil{}:
      Done{expression}
    case _:
      Fail{M.Diagnostic{"internal_cst", "resolver", "expected one lowered resolver expression"}}

type Identified is Data:
  Identified{values: List<&2, M.Expr>, next: Nat}

def identified_values(result: Identified) -> List<&2, M.Expr>:
  Identified{values, next} = result
  values

def identified_next(result: Identified) -> Nat:
  Identified{values, next} = result
  next

def identify_node(value: M.Expr, +next: Nat) -> Identified:
  match value:
    case M.AssociatedExpr{old, dispatch, member, templates, left, right}:
      Identified{[M.AssociatedExpr{next, dispatch, member, templates, left, right}], 1n+next}
    case M.GenericOperationExpr{old, template, arguments}:
      Identified{[M.GenericOperationExpr{next, template, arguments}], 1n+next}
    case M.InstantiationExpr{old, value}:
      Identified{[M.InstantiationExpr{next, value}], 1n+next}
    case M.LambdaExpr{old, parameter, p, r, body}:
      Identified{[M.LambdaExpr{next, parameter, p, r, body}], 1n+next}
    case other:
      Identified{[other], next}

type IdentifyWork is Data:
  Identify{value: M.Expr}
  IdentifyMany{values: List<&2, M.Expr>, reversed: List<&2, M.Expr>}

# Desugaring can introduce several operations at one source offset and share
# source continuations between branches. Occurrence identities are distinct
# from diagnostic offsets and are freshly assigned before source inference.
def identify(+fuel: Nat, work: IdentifyWork, next: Nat) -> Result<&2, &2, M.Diagnostic, Identified>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"resolver_complexity", "resolver", "resolver identities exceeded their structural limit"}}
    case 1n+rest Identify{+value}:
      do Result<&2, &2, M.Diagnostic, Identified>:
        +children : Identified <- identify(rest, IdentifyMany{Closures.children(value), Nil{}}, next)
        rebuilt : M.Expr <- Rebuild.rebuild(value, identified_values(children), 0n)
        return identify_node(rebuilt, identified_next(children))
    case 1n+rest IdentifyMany{Nil{}, reversed}:
      Done{Identified{List.reverse(&2, M.Expr, reversed), next}}
    case 1n+rest IdentifyMany{head <> tail, reversed}:
      do Result<&2, &2, M.Diagnostic, Identified>:
        +first : Identified <- identify(rest, Identify{head}, next)
        identify(rest, IdentifyMany{tail, List.reverse.go(&2, M.Expr, identified_values(first), reversed)}, identified_next(first))

def prepare(module: M.Module) -> Result<&2, &2, M.Diagnostic, M.Module>:
  Done{add_types(module)}


def request(+member: String) -> Bool:
  String.starts_with(member, "@do.")

type Plan is Data:
  Plan{owner: Maybe<&2, M.TypeId>, member: String, body: M.Expr}

def plan_owner(plan: Plan) -> Maybe<&2, M.TypeId>:
  Plan{owner, member, body} = plan
  owner

def plan_member(plan: Plan) -> String:
  Plan{owner, member, body} = plan
  member

def ordinary_plan_body(plan: Plan, reference: M.Expr) -> M.Expr:
  Plan{owner, member, body} = plan
  M.LetExpr{"$resolver$member", reference, body}

def plan_body(plan: Plan, reference: M.Expr, name: String, member: String, identity: Nat) -> M.Expr:
  match member:
    case "@do.for":
      Loops.body(name, identity, False{})
    case "@do.forever":
      Loops.body(name, identity, True{})
    case _:
      ordinary_plan_body(plan, reference)

def bind_body(monadic: Bool) -> M.Expr:
  +value = {M.LocalExpr{"$resolver$value"} : M.Expr}
  +next = {M.LocalExpr{"$resolver$next"} : M.Expr}
  M.MatchExpr{[M.LocalExpr{"$resolver$right"}], [M.MatchArm{[M.ProductPattern{[M.BindingPattern{"$resolver$value"}, M.BindingPattern{"$resolver$next"}]}], Bool.pick(M.Expr, monadic, M.ApplyExpr{M.ApplyExpr{M.LocalExpr{"$resolver$member"}, value}, next}, M.ApplyExpr{next, value})}]}

def monadic_plan(member: String, +owner: M.TypeId, subject: String) -> Result<&2, &2, M.Diagnostic, Plan>:
  match member:
    case "@do.pure":
      Done{Plan{Some{owner}, "pure", M.ApplyExpr{M.LocalExpr{"$resolver$member"}, M.LocalExpr{"$resolver$right"}}}}
    case "@do.bind":
      Done{Plan{Some{owner}, "bind", bind_body(True{})}}
    case "@do.forward":
      Done{Plan{None{}, "", M.LocalExpr{"$resolver$right"}}}
    case "@do.run":
      Done{Plan{None{}, "", M.ApplyExpr{M.LocalExpr{"$resolver$right"}, M.UnitExpr{}}}}
    case _:
      Fail{M.Diagnostic{"invalid_resolver", subject, "unknown monad resolver operation"}}

def direct_plan(member: String, subject: String) -> Result<&2, &2, M.Diagnostic, Plan>:
  match member:
    case "@do.pure":
      Done{Plan{None{}, "", M.LocalExpr{"$resolver$right"}}}
    case "@do.bind":
      Done{Plan{None{}, "", bind_body(False{})}}
    case "@do.run":
      Done{Plan{None{}, "", M.HandleExpr{M.LocalExpr{"$resolver$left"}, M.ApplyExpr{M.LocalExpr{"$resolver$right"}, M.UnitExpr{}}}}}
    case "@do.forward":
      Fail{M.Diagnostic{"resolver_required", subject, "return $ requires a monad resolver; provider blocks return plain values"}}
    case _:
      Fail{M.Diagnostic{"invalid_resolver", subject, "unknown provider resolver operation"}}

def selected_plan(owner: Maybe<&2, M.TypeId>, ty: M.Ty, member: String, subject: String) -> Result<&2, &2, M.Diagnostic, Plan>:
  match owner ty:
    case Some{identity} _:
      monadic_plan(member, identity, subject)
    case None{} M.ProviderTy{identity, effects}:
      direct_plan(member, subject)
    case None{} M.StateProviderTy{read, write, state}:
      direct_plan(member, subject)
    case _ _:
      Fail{M.Diagnostic{"invalid_provider", subject, "do requires an effect provider or a monad resolver"}}

def create_plan(owner: Maybe<&2, M.TypeId>, subject: String) -> Result<&2, &2, M.Diagnostic, Plan>:
  match owner:
    case Some{identity}:
      Done{Plan{None{}, "", M.ConstructExpr{monad_constructor(), Some{M.LocalExpr{"$resolver$left"}}}}}
    case None{}:
      Fail{M.Diagnostic{"type_constructor_required", subject, "monad requires a type constructor value"}}

def plan(member: String, +ty: M.Ty, subject: String) -> Result<&2, &2, M.Diagnostic, Plan>:
  match member:
    case "@do.for":
      Done{Plan{None{}, "", M.UnitExpr{}}}
    case "@do.forever":
      Done{Plan{None{}, "", M.UnitExpr{}}}
    case "@do.monad":
      create_plan(token_owner(ty), subject)
    case other:
      selected_plan(monad_owner(ty), ty, other, subject)

def ready(ty: M.Ty) -> Bool:
  match ty:
    case M.VariableTy{index}:
      False{}
    case M.ParameterTy{index}:
      False{}
    case _:
      True{}

def validate(+ty: M.Ty, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, Bool.or(Bool.not(ready(ty)), Maybe.is_some(&2, M.TypeId, monad_owner(ty))), Done{Unit{}}, Fail{M.Diagnostic{"invalid_provider", subject, "do requires an effect provider or monad resolver"}})

# A generated provider runner needs the operation identity before checking its
# body. Use fresh source-style annotation variables, never inference-owned IDs.
def parameter_annotation(member: String, ty: M.Ty, name: String) -> Maybe<&2, M.Ty>:
  match member ty:
    case "@do.run" M.ProviderTy{identity, effects}:
      Some{M.ProviderTy{identity, M.EffectRow{Nil{}, M.FreeRow{name, "effects"}}}}
    case "@do.run" M.StateProviderTy{read, write, state}:
      Some{M.StateProviderTy{read, write, M.FreeTy{name, "state"}}}
    case _ _:
      None{}

def shape_arguments(count: Nat, +scope: String) -> List<&2, M.Ty>:
  match count:
    case 0n:
      Nil{}
    case 1n+ +rest:
      M.FreeTy{scope, Nat.show(rest)} <> shape_arguments(rest, scope)

def result_shape(types: List<&2, M.DataType>, +wanted: M.TypeId, +scope: String) -> Maybe<&2, M.Ty>:
  match types:
    case Nil{}:
      None{}
    case M.DataType{identity, parameters, constructors} <> tail:
      Bool.pick(Maybe<&2, M.Ty>, M.type_id_equal(identity, wanted), Some{M.AppliedTy{wanted, shape_arguments(parameters, scope)}}, result_shape(tail, wanted, scope))

def checked_body(owner: Maybe<&2, M.TypeId>, member: String, body: M.Expr, types: List<&2, M.DataType>, name: String) -> M.Expr:
  match owner member:
    case Some{identity} "@do.pure":
      M.SourceExpr{0n, result_shape(types, identity, name), body}
    case Some{identity} "@do.bind":
      M.SourceExpr{0n, result_shape(types, identity, name), body}
    case Some{identity} "@do.forward":
      M.SourceExpr{0n, result_shape(types, identity, name), body}
    case Some{identity} "@do.run":
      M.SourceExpr{0n, result_shape(types, identity, name), body}
    case _ _:
      body

def scope(label: Nat) -> String:
  "$resolver$" ++ Nat.show(label)

def call(label: Nat, offset: Nat, member: String, value: M.Expr) -> M.Expr:
  M.AssociatedExpr{offset, M.BinaryDispatch{}, "@do." ++ member, Nil{}, M.LocalExpr{scope(label)}, value}

type Continuation is Data:
  Discard{next: M.Expr}
  BindValue{name: String, next: M.Expr}

def continue_with(next: Continuation, value: M.Expr) -> M.Expr:
  match next:
    case Discard{body}:
      M.SequenceExpr{value, body}
    case BindValue{name, body}:
      M.UseExpr{name, value, body}

def join_name(offset: Nat) -> String:
  "$resolver$join$" ++ Nat.show(offset)

def shared_continuation(+offset: Nat) -> Continuation:
  +parameter = join_name(offset) ++ "$value"
  BindValue{parameter, M.ApplyExpr{M.InstantiationExpr{0n, M.LocalExpr{join_name(offset)}}, M.LocalExpr{parameter}}}

def with_continuation(+offset: Nat, next: Continuation, body: M.Expr) -> M.Expr:
  +parameter = join_name(offset) ++ "$argument"
  M.LetExpr{join_name(offset), M.LambdaExpr{0n, parameter, None{}, None{}, continue_with(next, M.LocalExpr{parameter})}, body}

def exits(fuel: Nat, value: M.Expr, +label: Nat) -> Bool:
  match fuel value:
    case 1n+rest M.SourceExpr{offset, annotation, body}:
      exits(rest, body, label)
    case 1n+rest M.ReturnExpr{target, value}:
      Nat.is_eq(target, label)
    case 1n+rest M.PanicExpr{message}:
      True{}
    case 1n+ +rest M.SequenceExpr{first, next}:
      Bool.or(exits(rest, first, label), exits(rest, next, label))
    case 1n+ +rest M.LetExpr{name, value, body}:
      Bool.or(exits(rest, value, label), exits(rest, body, label))
    case 1n+ +rest M.UseExpr{name, value, body}:
      Bool.or(exits(rest, value, label), exits(rest, body, label))
    case 1n+ +rest M.IfExpr{condition, yes, no}:
      Bool.and(exits(rest, yes, label), exits(rest, no, label))
    case _ _:
      False{}

def require_exit(valid: Bool, offset: Nat) -> Result<&2, &2, M.Diagnostic, Unit>:
  match valid:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{M.Diagnostic{"guard_fallthrough", "offset:" ++ Nat.show(offset), "let-else fallback must exit its enclosing do block"}}

def annotation(value: M.Expr) -> Maybe<&2, M.Ty>:
  match value:
    case M.SourceExpr{offset, annotation, value}:
      annotation
    case _:
      None{}

def unannotated(value: M.Expr) -> M.Expr:
  match value:
    case M.SourceExpr{offset, annotation, value}:
      M.SourceExpr{offset, None{}, value}
    case other:
      other

def is_panic(value: M.Expr) -> Bool:
  match value:
    case M.PanicExpr{message}:
      True{}
    case M.SourceExpr{offset, annotation, value}:
      is_panic(value)
    case M.InstantiationExpr{site, value}:
      is_panic(value)
    case _:
      False{}

def returned(label: Nat, offset: Nat, value: M.Expr) -> M.Expr:
  match value:
    case M.AssociatedExpr{site, dispatch, "@do.forward", templates, left, right}:
      call(label, site, "forward", right)
    case +other:
      Bool.pick(M.Expr, is_panic(other), other, call(label, offset, "pure", other))

type Work is Data:
  Expression{value: M.Expr, next: Continuation, offset: Nat}
  Arms{arms: List<&2, M.MatchArm<M.Expr>>, next: Continuation, offset: Nat}
  Binding{monadic: Bool, name: String, value: M.Expr, body: M.Expr, offset: Nat}
  Loop{forever: Bool, index: String, start: M.Expr, end: M.Expr, state: String, initial: M.Expr, body: M.Expr, next: Continuation, offset: Nat}


def arms(values: List<&2, M.MatchArm<M.Expr>>, bodies: List<&2, M.Expr>) -> List<&2, M.MatchArm<M.Expr>>:
  match values bodies:
    case M.MatchArm{patterns, old} <> tail body <> rest:
      M.MatchArm{patterns, body} <> arms(tail, rest)
    case _ _:
      Nil{}

# Only the source `use` bindings have the $use$ prefix. Compiler temporaries
# remain ordinary sequencing; notably, an if's successor tuple is not a bind.
# Nested blocks and function bodies are opaque: each owns its resolver rules.
def lower(+fuel: Nat, work: Work, +label: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"resolver_complexity", "resolver", "resolver block exceeded its structural limit"}}
    case 1n+rest Expression{M.SourceExpr{+at, None{}, value}, next, offset}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        body : M.Expr <- Result.bind(&2, &2, M.Diagnostic, List<&2, M.Expr>, M.Expr, lower(rest, Expression{value, next, at}, label), one)
        return [M.SourceExpr{at, None{}, body}]
    case 1n+rest Expression{M.ReturnExpr{target, value}, next, offset}:
      Done{[returned(label, offset, value)]}
    case 1n+rest Expression{M.LetExpr{name, value, body}, next, offset}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        body : M.Expr <- Result.bind(&2, &2, M.Diagnostic, List<&2, M.Expr>, M.Expr, lower(rest, Expression{body, next, offset}, label), one)
        return [M.LetExpr{name, value, body}]
    case 1n+rest Expression{M.UseExpr{+name, +value, body}, next, +offset}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        body : M.Expr <- Result.bind(&2, &2, M.Diagnostic, List<&2, M.Expr>, M.Expr, lower(rest, Expression{body, next, offset}, label), one)
        lower(rest, Binding{String.starts_with(name, "$use$"), name, value, body, offset}, label)
    case 1n+rest Binding{True{}, name, +value, body, +offset}:
      Done{[call(label, offset, "bind", M.ProductExpr{[unannotated(value), M.LambdaExpr{Nat.add(Nat.mul(offset, 16n), 7n), name, annotation(value), None{}, body}]})]}
    case 1n+rest Binding{False{}, name, value, body, offset}:
      lower(rest, Expression{value, BindValue{name, body}, offset}, label)
    case 1n+rest Expression{M.SequenceExpr{first, next}, continuation, +offset}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        next : M.Expr <- Result.bind(&2, &2, M.Diagnostic, List<&2, M.Expr>, M.Expr, lower(rest, Expression{next, continuation, offset}, label), one)
        lower(rest, Expression{first, Discard{next}, offset}, label)
    case 1n+rest Expression{M.IfExpr{condition, yes, no}, next, +offset}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        yes : M.Expr <- Result.bind(&2, &2, M.Diagnostic, List<&2, M.Expr>, M.Expr, lower(rest, Expression{yes, shared_continuation(offset), offset}, label), one)
        no : M.Expr <- Result.bind(&2, &2, M.Diagnostic, List<&2, M.Expr>, M.Expr, lower(rest, Expression{no, shared_continuation(offset), offset}, label), one)
        return [with_continuation(offset, next, M.IfExpr{condition, yes, no})]
    case 1n+rest Expression{M.MatchExpr{values, +original}, next, +offset}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        bodies : List<&2, M.Expr> <- lower(rest, Arms{original, shared_continuation(offset), offset}, label)
        return [with_continuation(offset, next, M.MatchExpr{values, arms(original, bodies)})]
    case 1n+rest Expression{M.ForExpr{index, start, end, state, initial, body}, next, offset}:
      lower(rest, Loop{False{}, index, start, end, state, initial, body, next, offset}, label)
    case 1n+rest Expression{M.ForeverExpr{state, initial, body}, next, offset}:
      lower(rest, Loop{True{}, "$resolver$index", M.U32Expr{0}, M.U32Expr{0}, state, initial, body, next, offset}, label)
    case 1n+rest Loop{forever, index, start, end, +state, initial, body, next, +offset}:
      +again = "$resolver$again$" ++ Nat.show(offset)
      +successor = "$resolver$state$" ++ Nat.show(offset)
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        body : M.Expr <- Result.bind(&2, &2, M.Diagnostic, List<&2, M.Expr>, M.Expr, lower(rest, Expression{body, BindValue{successor, M.ApplyExpr{M.LocalExpr{again}, M.LocalExpr{successor}}}, offset}, label), one)
        step : M.Expr = M.LambdaExpr{0n, index, Some{M.U32Ty{}}, None{}, M.LambdaExpr{1n, state, None{}, None{}, M.LambdaExpr{2n, again, None{}, None{}, body}}}
        finish : M.Expr = M.LambdaExpr{3n, state, None{}, None{}, continue_with(next, M.LocalExpr{state})}
        return [call(label, offset, Bool.pick(String, forever, "forever", "for"), M.ProductExpr{[start, end, initial, step, finish]})]
    case 1n+rest Expression{M.GuardExpr{pattern, value, +alternative, body}, +next, +offset}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        valid : Unit <- require_exit(exits(65536n, alternative, label), offset)
        yes : M.Expr <- Result.bind(&2, &2, M.Diagnostic, List<&2, M.Expr>, M.Expr, lower(rest, Expression{body, next, offset}, label), one)
        no : M.Expr <- Result.bind(&2, &2, M.Diagnostic, List<&2, M.Expr>, M.Expr, lower(rest, Expression{alternative, next, offset}, label), one)
        +name : String = "$resolver$match$" ++ Nat.show(offset)
        return [M.LetExpr{name, value, M.MatchExpr{[M.LocalExpr{name}], [M.MatchArm{[pattern], yes}, M.MatchArm{[M.WildcardPattern{}], no}]}}]
    case 1n+rest Arms{Nil{}, next, offset}:
      Done{Nil{}}
    case 1n+rest Arms{M.MatchArm{patterns, body} <> tail, +next, +offset}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        head : M.Expr <- Result.bind(&2, &2, M.Diagnostic, List<&2, M.Expr>, M.Expr, lower(rest, Expression{body, next, offset}, label), one)
        tail : List<&2, M.Expr> <- lower(rest, Arms{tail, next, offset}, label)
        return head <> tail
    case 1n+rest Expression{value, next, offset}:
      Done{[continue_with(next, value)]}

# Source offsets and ordinary cloned sites occupy the low identity space.
# Each block owns 65536 identities in the upper half of Bend's 48-bit Nat range.
def run_id(label: Nat) -> Nat:
  Nat.add(Nat.mul(2147483648n, 65536n), Nat.mul(label, 65536n))

def require_space(valid: Bool) -> Result<&2, &2, M.Diagnostic, Unit>:
  match valid:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{M.Diagnostic{"resolver_complexity", "resolver", "resolver identities exceed their structural limit"}}

def action(body: M.Expr, +label: Nat) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  do Result<&2, &2, M.Diagnostic, M.Expr>:
    valid : Unit <- require_space(Nat.is_lt(label, 2147483648n))
    lowered : M.Expr <- Result.bind(&2, &2, M.Diagnostic, List<&2, M.Expr>, M.Expr, lower(1048576n, Expression{body, Discard{call(label, 0n, "pure", M.UnitExpr{})}, label}, label), one)
    +fresh : Identified <- identify(1048576n, Identify{lowered}, 1n+run_id(label))
    valid : Unit <- require_space(Nat.is_lt(Nat.sub(identified_next(fresh), run_id(label)), 65536n))
    body : M.Expr <- one(identified_values(fresh))
    return call(label, run_id(label), "run", M.LambdaExpr{identified_next(fresh), "$resolver$unit", Some{M.UnitTy{}}, None{}, body})

def block(provider: M.Expr, body: M.Expr, +label: Nat) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  do Result<&2, &2, M.Diagnostic, M.Expr>:
    body : M.Expr <- action(body, label)
    return M.UseExpr{scope(label), provider, body}

def direct(ty: M.Ty) -> Bool:
  match ty:
    case M.ProviderTy{identity, effects}:
      True{}
    case M.StateProviderTy{read, write, state}:
      True{}
    case _:
      False{}

def check_direct(fuel: Nat, pending: List<&2, M.Expr>, +wanted: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match fuel pending:
    case _ Nil{}:
      Done{Unit{}}
    case 0n _:
      Fail{M.Diagnostic{"resolver_complexity", "resolver", "provider block exceeds its structural limit"}}
    case 1n+rest M.AssociatedExpr{offset, dispatch, "@do.forward", templates, M.LocalExpr{+name}, right} <> tail:
      Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, M.name_equal(name, wanted), Fail{M.Diagnostic{"resolver_required", "offset:" ++ Nat.show(offset), "return $ requires a monad resolver; provider blocks return plain values"}}, check_direct(rest, right <> tail, wanted))
    case 1n+rest value <> tail:
      check_direct(rest, List.append(&2, M.Expr, Closures.children(value), tail), wanted)

def validate_direct(body: M.Expr) -> Result<&2, &2, M.Diagnostic, Unit>:
  match body:
    case M.BlockExpr{label, body}:
      check_direct(1048576n, [body], scope(label))
    case _:
      Done{Unit{}}
