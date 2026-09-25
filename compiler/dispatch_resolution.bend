import Base
import ./model.bend as M
import ./types.bend as T
import ./infer.bend as I
import ./globals.bend as G
import ./groups.bend as Groups
import ./check_scheduler.bend as Scheduler
import ./checked_core.bend as Core
import ./closures.bend as F
import ./index.bend as Index
import ./members.bend as Members
import ./type_data.bend as TD
import ./state_specialize.bend as State
import ./schema_stage.bend as Schema
import ./monomorph.bend as Mono
import ./inference_batch.bend as Batch
import ./public_exports.bend as Public
import ./dependency.bend as D
import ./core_compare.bend as Compare

# Concrete dispatch resolution runs after the initial shape check and before
# templating. A dispatch site whose operands (binary dispatch) are closed, or
# whose receiver's nominal head is known (member and field access), once its
# declaration group is inferred selects the same implementation or field
# accessor in every specialization of that declaration. Such a site is
# rewritten into a direct call with exactly the shape specialization would
# produce, so the declaration stops being a template. A per-group solver keeps
# the unifications of its selections, so a result one selection fixes closes
# the sites that consume it in the same round. A rewrite that refines an
# interface is checked again, retaining every group whose declarations and
# imported interfaces are unchanged, and sites the refined interfaces close are
# resolved in the next round. Resolution never reports a diagnostic: any failure
# returns None and the caller specializes the original module.

# ---------------------------------------------------------------------------
# Operator calls
# ---------------------------------------------------------------------------

# Operators call forwarders such as `add = fn left => fn right => @type.call
# "add" left right`. A saturated call is the forwarder's dispatch site at the
# caller, which is also how specialization expands it. Inlining it before the
# check exposes the caller's operand types to resolution. The site keeps the
# operator's source offset as its identity.
def forwarder_entry(found: Maybe<&2, Mono.BinaryMember>, name: String, index: Map<&2, Mono.BinaryMember>) -> Map<&2, Mono.BinaryMember>:
  match found:
    case None{}:
      index
    case Some{member}:
      Map.set(&2, Mono.BinaryMember, index, name, member)

def forwarder_index(functions: List<&2, M.Function>, index: Map<&2, Mono.BinaryMember>) -> Map<&2, Mono.BinaryMember>:
  match functions:
    case Nil{}:
      index
    case +function <> tail:
      M.Function{+name, exported, parameter, p, r, body} = function
      forwarder_index(tail, forwarder_entry(Mono.binary_function(Done{function}), name, index))

def forwarder_target(target: M.Expr, left: M.Expr, right: M.Expr, +forwarders: Map<&2, Mono.BinaryMember>) -> Maybe<&2, Mono.BinaryCall>:
  match target:
    case M.FunctionExpr{name}:
      Mono.binary_result(Index.find(Mono.BinaryMember, forwarders, name), left, right)
    case _:
      None{}

def forwarder_call(callee: M.Expr, right: M.Expr, +forwarders: Map<&2, Mono.BinaryMember>) -> Maybe<&2, Mono.BinaryCall>:
  match callee:
    case M.ApplyExpr{target, left}:
      forwarder_target(Mono.unlocated(65536n, target), left, right, forwarders)
    case M.CallExpr{name, left}:
      forwarder_target(M.FunctionExpr{name}, left, right, forwarders)
    case _:
      None{}

type InlineWork is Data:
  Inline{value: M.Expr}
  InlineMany{values: List<&2, M.Expr>, reversed: List<&2, M.Expr>}
  InlineApply{offset: Nat, callee: M.Expr, argument: M.Expr, call: Maybe<&2, Mono.BinaryCall>}

def inline_work(+fuel: Nat, work: InlineWork, +forwarders: Map<&2, Mono.BinaryMember>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"specialization_limit", "dispatch", "operator inlining exceeded its structural limit"}}
    case 1n+rest Inline{M.SourceExpr{offset, None{}, M.ApplyExpr{+callee, +argument}}}:
      inline_work(rest, InlineApply{offset, callee, argument, forwarder_call(Mono.unlocated(65536n, callee), argument, forwarders)}, forwarders)
    case 1n+rest InlineApply{+offset, callee, argument, Some{Mono.BinaryCall{member, templates, left, right}}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        operands : List<&2, M.Expr> <- inline_work(rest, InlineMany{[left, right], Nil{}}, forwarders)
        call : M.Expr <- Mono.rebuild(M.AssociatedExpr{offset, M.BinaryDispatch{}, member, templates, M.UnitExpr{}, M.UnitExpr{}}, operands, 0n)
        return [M.SourceExpr{offset, None{}, call}]
    case 1n+rest InlineApply{offset, callee, argument, None{}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        parts : List<&2, M.Expr> <- inline_work(rest, InlineMany{[callee, argument], Nil{}}, forwarders)
        apply : M.Expr <- Mono.rebuild(M.ApplyExpr{M.UnitExpr{}, M.UnitExpr{}}, parts, 0n)
        return [M.SourceExpr{offset, None{}, apply}]
    case 1n+rest Inline{+expression}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        children : List<&2, M.Expr> <- inline_work(rest, InlineMany{F.children(expression), Nil{}}, forwarders)
        rebuilt : M.Expr <- Mono.rebuild(expression, children, 0n)
        return [rebuilt]
    case 1n+rest InlineMany{Nil{}, reversed}:
      Done{List.reverse(&2, M.Expr, reversed)}
    # Siblings accumulate: a wide array must not nest one frame per element.
    case 1n+rest InlineMany{head <> tail, reversed}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        first : List<&2, M.Expr> <- inline_work(rest, Inline{head}, forwarders)
        inline_work(rest, InlineMany{tail, List.reverse.go(&2, M.Expr, first, reversed)}, forwarders)

def inlined_body(result: Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>, original: M.Expr) -> M.Expr:
  match result:
    case Done{expression <> Nil{}}:
      expression
    case _:
      original

def inline_body(+body: M.Expr, forwarders: Map<&2, Mono.BinaryMember>) -> M.Expr:
  inlined_body(inline_work(65536n, Inline{body}, forwarders), body)

# A linked-schema node method keeps its equality call: schema staging proves
# that exact source shape before it answers the method at compile time.
def inline_function_if(node: Bool, function: M.Function, forwarders: Map<&2, Mono.BinaryMember>) -> M.Function:
  match node:
    case True{}:
      function
    case False{}:
      M.Function{name, exported, parameter, p, r, body} = function
      M.Function{name, exported, parameter, p, r, inline_body(body, forwarders)}

def inline_declaration(declaration: G.Declaration, forwarders: Map<&2, Mono.BinaryMember>) -> G.Declaration:
  match declaration:
    case G.FunctionDeclaration{+function}:
      G.FunctionDeclaration{inline_function_if(Maybe.is_some(&2, Schema.NodeShape, Schema.node(function)), function, forwarders)}
    case G.ConstantDeclaration{M.Constant{name, exported, annotation, value}}:
      G.ConstantDeclaration{M.Constant{name, exported, annotation, inline_body(value, forwarders)}}

def weighted_declarations(declarations: List<&2, G.Declaration>) -> List<&2, Batch.Weighted<G.Declaration>>:
  match declarations:
    case Nil{}:
      Nil{}
    case +declaration <> tail:
      Batch.Weighted{declaration, Mono.declaration_cost(declaration)} <> weighted_declarations(tail)

def declaration_functions(declarations: List<&2, G.Declaration>) -> List<&2, M.Function>:
  match declarations:
    case Nil{}:
      Nil{}
    case G.FunctionDeclaration{function} <> tail:
      function <> declaration_functions(tail)
    case G.ConstantDeclaration{constant} <> tail:
      declaration_functions(tail)

def declaration_constants(declarations: List<&2, G.Declaration>) -> List<&2, M.Constant>:
  match declarations:
    case Nil{}:
      Nil{}
    case G.FunctionDeclaration{function} <> tail:
      declaration_constants(tail)
    case G.ConstantDeclaration{constant} <> tail:
      constant <> declaration_constants(tail)

def inline_module(module: M.Module) -> M.Module:
  M.Module{constants, +functions, types, operations} = module
  +known = forwarder_index(functions, Map.new(&2, Mono.BinaryMember))
  +declarations = List.append(&2, G.Declaration, G.function_declarations(functions), G.constant_declarations(constants))
  +inlined = Batch.execute(~G.Declaration, ~Map<&2, Mono.BinaryMember>, ~G.Declaration, ~inline_declaration, Batch.plan(G.Declaration, weighted_declarations(declarations), 2048n), known)
  M.Module{declaration_constants(inlined), declaration_functions(inlined), types, operations}

# ---------------------------------------------------------------------------
# Dispatch identities
# ---------------------------------------------------------------------------

# Resolution and specialization key their choices by site identity, so every
# associated and generic-operation site must own a distinct one.
type DispatchScan is Data:
  DispatchScan{count: Nat, seen: Set(), unique: Bool}

def scan_identity(scan: DispatchScan, identity: Nat, associated: Nat) -> DispatchScan:
  DispatchScan{count, +seen, unique} = scan
  +key = Nat.show(identity)
  DispatchScan{Nat.add(count, associated), Set.add(seen, key), Bool.and(unique, Bool.not(D.member(seen, key)))}

def scan_limit(scan: DispatchScan) -> DispatchScan:
  DispatchScan{count, seen, unique} = scan
  DispatchScan{count, seen, False{}}

def dispatch_scan(fuel: Nat, pending: List<&2, M.Expr>, scan: DispatchScan) -> DispatchScan:
  match fuel pending:
    case _ Nil{}:
      scan
    case 0n _:
      scan_limit(scan)
    case 1n+rest M.AssociatedExpr{identity, dispatch, member, templates, left, right} <> tail:
      dispatch_scan(rest, left <> right <> tail, scan_identity(scan, identity, 1n))
    case 1n+rest M.GenericOperationExpr{identity, template, arguments} <> tail:
      dispatch_scan(rest, tail, scan_identity(scan, identity, 0n))
    case 1n+rest head <> tail:
      dispatch_scan(rest, List.reverse.go(&2, M.Expr, List.reverse(&2, M.Expr, F.children(head)), tail), scan)

def scan_bodies(bodies: List<&2, M.Expr>, scan: DispatchScan) -> DispatchScan:
  match bodies:
    case Nil{}:
      scan
    case body <> tail:
      scan_bodies(tail, dispatch_scan(1048576n, [body], scan))

def scan_module(module: M.Module) -> DispatchScan:
  M.Module{constants, functions, types, operations} = module
  scan_bodies(Mono.module_expressions(functions, constants), DispatchScan{0n, Set.new(), True{}})

# ---------------------------------------------------------------------------
# Shared field accessors
# ---------------------------------------------------------------------------

# Every field a receiver requirement could name gets its shared accessor built
# (and independently checked) once; resolution then types field sites from it.
# Unused accessors stay in the round cache and never enter the module.
type Accessor is Data:
  Accessor{name: String, function: M.Function, certificate: Core.Certificate, binding: I.Binding}

type AccessorRequest is Data:
  AccessorRequest{name: String, owner: M.DataType, dispatch: M.Dispatch, member: String, identity: Nat}

type Requests is Data:
  Requests{seen: Set(), reversed: List<&2, AccessorRequest>, next: Nat}

def dispatch_tag(dispatch: M.Dispatch) -> String:
  match dispatch:
    case M.BinaryDispatch{}:
      "b"
    case M.MemberDispatch{}:
      "m"
    case M.FieldUpdateDispatch{}:
      "u"

def choice_key(identity: Nat, dispatch: M.Dispatch) -> String:
  Nat.show(identity) ++ dispatch_tag(dispatch)

def data_identity(data: M.DataType) -> M.TypeId:
  M.DataType{identity, parameters, constructors} = data
  identity

def data_constructors(data: M.DataType) -> List<&2, M.Constructor>:
  M.DataType{identity, parameters, constructors} = data
  constructors

def request_if(fresh: Bool, +name: String, owner: M.DataType, dispatch: M.Dispatch, member: String, requests: Requests) -> Requests:
  match fresh:
    case False{}:
      requests
    case True{}:
      Requests{+seen, reversed, +next} = requests
      Requests{Set.add(seen, name), AccessorRequest{name, owner, dispatch, member, next} <> reversed, 1n+next}

def seen_request(requests: Requests, name: String) -> Bool:
  Requests{seen, reversed, next} = requests
  D.member(seen, name)

def owner_request(has: Bool, +owner: M.DataType, +dispatch: M.Dispatch, +member: String, +known: Set(), +cache: Map<&2, Accessor>, +entry: String, +requests: Requests) -> Requests:
  match has:
    case False{}:
      requests
    case True{}:
      +name = Mono.accessor_name(Mono.nominal_prefix(data_identity(owner), entry), member, dispatch)
      request_if(Bool.and(Bool.not(D.member(known, name)), Bool.and(Bool.not(Maybe.is_some(&2, Accessor, Index.find(Accessor, cache, name))), Bool.not(seen_request(requests, name)))), name, owner, dispatch, member, requests)

def type_requests(types: List<&2, M.DataType>, +dispatch: M.Dispatch, +member: String, +known: Set(), +cache: Map<&2, Accessor>, +entry: String, requests: Requests) -> Requests:
  match types:
    case Nil{}:
      requests
    case +owner <> tail:
      type_requests(tail, dispatch, member, known, cache, entry, owner_request(Members.has_field(data_constructors(owner), member), owner, dispatch, member, known, cache, entry, requests))

# Distinct (access kind, member) pairs named by receiver requirements.
type MemberUse is Data:
  MemberUse{dispatch: M.Dispatch, member: String}

type Uses is Data:
  Uses{seen: Set(), reversed: List<&2, MemberUse>}

def use_if(fresh: Bool, key: String, dispatch: M.Dispatch, member: String, uses: Uses) -> Uses:
  match fresh:
    case False{}:
      uses
    case True{}:
      Uses{seen, reversed} = uses
      Uses{Set.add(seen, key), MemberUse{dispatch, member} <> reversed}

def need_uses(needs: List<&2, Groups.Resolution>, +uses: Uses) -> Uses:
  match needs:
    case Nil{}:
      uses
    case Groups.Resolution{declaration, identity, M.BinaryDispatch{}, member, templates, left, right, result, ambient} <> tail:
      need_uses(tail, uses)
    case Groups.Resolution{declaration, identity, +dispatch, +member, templates, left, right, result, ambient} <> tail:
      Uses{seen, reversed} = uses
      +key = dispatch_tag(dispatch) ++ member
      need_uses(tail, use_if(Bool.not(D.member(seen, key)), key, dispatch, member, uses))

def group_uses(groups: List<&2, Groups.GroupNeeds>, uses: Uses) -> Uses:
  match groups:
    case Nil{}:
      uses
    case Groups.GroupNeeds{next, needs, members, generalized} <> tail:
      group_uses(tail, need_uses(needs, uses))

def use_requests(uses: List<&2, MemberUse>, +types: List<&2, M.DataType>, +known: Set(), +cache: Map<&2, Accessor>, +entry: String, requests: Requests) -> Requests:
  match uses:
    case Nil{}:
      requests
    case MemberUse{dispatch, member} <> tail:
      use_requests(tail, types, known, cache, entry, type_requests(types, dispatch, member, known, cache, entry, requests))

def uses_list(uses: Uses) -> List<&2, MemberUse>:
  Uses{seen, reversed} = uses
  List.reverse(&2, MemberUse, reversed)

def group_requests(groups: List<&2, Groups.GroupNeeds>, +types: List<&2, M.DataType>, +known: Set(), +cache: Map<&2, Accessor>, +entry: String, requests: Requests) -> Requests:
  use_requests(uses_list(group_uses(groups, Uses{Set.new(), Nil{}})), types, known, cache, entry, requests)

def request_list(requests: Requests) -> List<&2, AccessorRequest>:
  Requests{seen, reversed, next} = requests
  List.reverse(&2, AccessorRequest, reversed)

def request_next(requests: Requests) -> Nat:
  Requests{seen, reversed, next} = requests
  next

def accessor_binding(checked: Groups.CheckedGroup, name: String) -> Maybe<&2, I.Binding>:
  Groups.CheckedGroup{M.CheckedModule{constants, functions, types, operations}, interfaces} = checked
  I.lookup_binding(Mono.function_bindings(functions), name)

def accessor_found(binding: Maybe<&2, I.Binding>, name: String, function: M.Function, module: M.Module, checked: Groups.CheckedGroup) -> Maybe<&2, Accessor>:
  match binding:
    case None{}:
      None{}
    case Some{value}:
      Some{Accessor{name, function, Core.Certificate{module, checked, Nil{}}, value}}

def accessor_checked(result: Result<&2, &2, M.Diagnostic, Groups.CheckedGroup>, +name: String, function: M.Function, module: M.Module) -> Maybe<&2, Accessor>:
  match result:
    case Fail{diagnostic}:
      None{}
    case Done{+checked}:
      accessor_found(accessor_binding(checked, name), name, function, module, checked)

def accessor_generated(generated: Result<&2, &2, M.Diagnostic, M.Function>, name: String, owner: M.DataType) -> Maybe<&2, Accessor>:
  match generated:
    case Fail{diagnostic}:
      None{}
    case Done{+function}:
      +module : M.Module = M.Module{Nil{}, [function], [owner], Nil{}}
      accessor_checked(Groups.check_group_planned(module, Nil{}), name, function, module)

# An accessor is shared only when it checks independently against its owner
# type, exactly as specialization's field evidence requires.
def build_accessor_in(request: AccessorRequest) -> Maybe<&2, Accessor>:
  AccessorRequest{+name, +owner, dispatch, member, identity} = request
  accessor_generated(Members.function(data_constructors(owner), dispatch, member, name, identity), name, owner)

def build_accessor(request: AccessorRequest, context: Unit) -> Maybe<&2, Accessor>:
  build_accessor_in(request)

def weighted_requests(requests: List<&2, AccessorRequest>) -> List<&2, Batch.Weighted<AccessorRequest>>:
  match requests:
    case Nil{}:
      Nil{}
    case request <> tail:
      Batch.Weighted{request, 64n} <> weighted_requests(tail)

def cache_accessors(accessors: List<&2, Maybe<&2, Accessor>>, cache: Map<&2, Accessor>) -> Map<&2, Accessor>:
  match accessors:
    case Nil{}:
      cache
    case None{} <> tail:
      cache_accessors(tail, cache)
    case Some{Accessor{+name, function, certificate, binding}} <> tail:
      cache_accessors(tail, Map.set(&2, Accessor, cache, name, Accessor{name, function, certificate, binding}))

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

type SolveContext is Data:
  SolveContext{bindings: Map<&2, I.Binding>, accessors: Map<&2, Accessor>, types: List<&2, M.DataType>, entry: String, proofs: List<&2, Schema.Evidence>}

# A resolved site and the direct call specialization would substitute for it.
type Plan is Data:
  Planned{declaration: String, key: String, choice: Mono.Choice}

type Attempt is Data:
  Selected{plan: Plan, state: I.State}
  Waiting{}
  Dropped{}

# Plain associated members; type identity and typed-state requests keep their
# own specialization.
def plain_member(+member: String) -> Bool:
  Bool.and(Bool.not(M.name_equal(member, "@type.same")), Bool.not(Maybe.is_some(&2, State.Request, State.request(member))))

# Receiver selection depends only on the receiver's nominal head (its owner,
# its constructors' fields and its linked-schema evidence), never on arguments.
def receiver_known(ty: M.Ty) -> Bool:
  match ty:
    case M.VariableTy{index}:
      False{}
    case M.ParameterTy{index}:
      False{}
    case M.FreeTy{scope, name}:
      False{}
    case _:
      True{}

def scratch(next: Nat) -> I.State:
  I.State{T.empty(), next, MTip{}}

def candidate_indexed(name: Maybe<&2, String>, +bindings: Map<&2, I.Binding>, left: M.Ty, right: M.Ty, state: I.State) -> Result<&2, &2, M.Diagnostic, I.Typing>:
  match name:
    case None{}:
      Fail{M.Diagnostic{"unknown_associated_type", "dispatch", "operand type is not yet known"}}
    case Some{+name}:
      Mono.candidate_binding(Index.find(I.Binding, bindings, name), name, left, right, state, "dispatch")

# The unification specialization performs once it has selected `name`.
def unified(found: Maybe<&2, I.Binding>, name: String, signature: M.Ty, state: I.State) -> Result<&2, &2, M.Diagnostic, I.State>:
  do Result<&2, &2, M.Diagnostic, I.State>:
    +target : I.Typing <- I.instantiate_binding(found, state, name, "dispatch")
    I.unify(I.type_of(target), signature, I.state_of(target), "dispatch")

def selected_attempt(result: Result<&2, &2, M.Diagnostic, I.State>, plan: Plan) -> Attempt:
  match result:
    case Done{state}:
      Selected{plan, state}
    case Fail{diagnostic}:
      Dropped{}

def binary_chosen(selected: Result<&2, &2, M.Diagnostic, String>, declaration: String, identity: Nat, left: M.Ty, right: M.Ty, result: M.Ty, +ambient: M.EffectRow, state: I.State, +bindings: Map<&2, I.Binding>) -> Attempt:
  match selected:
    case Fail{diagnostic}:
      Dropped{}
    case Done{+name}:
      selected_attempt(unified(Index.find(I.Binding, bindings, name), name, M.FunctionTy{left, M.FunctionTy{right, result, ambient}, ambient}, state), Planned{declaration, choice_key(identity, M.BinaryDispatch{}), Mono.FunctionChoice{name}})

def attempt_binary(plain: Bool, closed: Bool, declaration: String, identity: Nat, +member: String, +left: M.Ty, +right: M.Ty, result: M.Ty, ambient: M.EffectRow, +state: I.State, context: SolveContext) -> Attempt:
  match plain closed:
    case False{} _:
      Dropped{}
    case True{} False{}:
      Waiting{}
    case True{} True{}:
      SolveContext{+bindings, accessors, types, +entry, proofs} = context
      +left_name = Mono.member_name(Mono.owner(left, entry), member)
      +right_name = Mono.member_name(Mono.owner(right, entry), member)
      binary_chosen(Mono.chosen(candidate_indexed(left_name, bindings, left, right, state), left_name, candidate_indexed(right_name, bindings, left, right, state), right_name, "dispatch", member), declaration, identity, left, right, result, ambient, state, bindings)

def method_found(name: Maybe<&2, String>, bindings: Map<&2, I.Binding>) -> Maybe<&2, String>:
  match name:
    case None{}:
      None{}
    case Some{+name}:
      Bool.pick(Maybe<&2, String>, Maybe.is_some(&2, I.Binding, Index.find(I.Binding, bindings, name)), Some{name}, None{})

def cached_binding(found: Maybe<&2, Accessor>, bindings: Map<&2, I.Binding>, name: String) -> Maybe<&2, I.Binding>:
  match found:
    case Some{Accessor{accessor, function, certificate, binding}}:
      Some{binding}
    case None{}:
      Index.find(I.Binding, bindings, name)

# The same order as Mono.select_receiver_found: a field and a same-named method
# are ambiguous, a missing writable field and a missing member are errors, and a
# method with linked-schema evidence keeps the schema reduction. Those sites
# stay deferred so specialization reports or reduces them as before.
def receiver_attempt(field: Bool, method: Maybe<&2, String>, schema: Bool, dispatch: M.Dispatch, declaration: String, +identity: Nat, +member: String, +left: M.Ty, right: M.Ty, result: M.Ty, ambient: M.EffectRow, state: I.State, +bindings: Map<&2, I.Binding>, accessors: Map<&2, Accessor>, entry: String) -> Attempt:
  match field method schema dispatch:
    case True{} Some{name} _ M.MemberDispatch{}:
      Dropped{}
    case True{} _ _ +dispatch:
      +name = Mono.accessor_name(Mono.accessor_owner(Mono.owner(left, entry)), member, dispatch)
      selected_attempt(unified(cached_binding(Index.find(Accessor, accessors, name), bindings, name), name, Mono.receiver_signature(dispatch, left, right, result, ambient), state), Planned{declaration, choice_key(identity, dispatch), Mono.receiver_choice(dispatch, name)})
    case False{} Some{+name} False{} M.MemberDispatch{}:
      selected_attempt(unified(Index.find(I.Binding, bindings, name), name, Mono.receiver_signature(M.MemberDispatch{}, left, right, result, ambient), state), Planned{declaration, choice_key(identity, M.MemberDispatch{}), Mono.ReceiverChoice{name}})
    case _ _ _ _:
      Dropped{}

def attempt_receiver(known: Bool, dispatch: M.Dispatch, declaration: String, identity: Nat, +member: String, +left: M.Ty, right: M.Ty, result: M.Ty, ambient: M.EffectRow, state: I.State, context: SolveContext) -> Attempt:
  match known:
    case False{}:
      Waiting{}
    case True{}:
      SolveContext{+bindings, accessors, types, +entry, proofs} = context
      receiver_attempt(Members.has_field(Members.constructors(left, types), member), method_found(Mono.member_name(Mono.owner(left, entry), member), bindings), Schema.eligible(proofs, member, left), dispatch, declaration, identity, member, left, right, result, ambient, state, bindings, accessors, entry)

def attempt_dispatch(dispatch: M.Dispatch, templates: List<&2, M.TypeId>, declaration: String, identity: Nat, +member: String, +left: M.Ty, +right: M.Ty, result: M.Ty, ambient: M.EffectRow, state: I.State, context: SolveContext) -> Attempt:
  match dispatch templates:
    case M.BinaryDispatch{} Nil{}:
      attempt_binary(plain_member(member), Groups.closed_types(65536n, [left, right]), declaration, identity, member, left, right, result, ambient, state, context)
    case M.BinaryDispatch{} _:
      Dropped{}
    case receiver _:
      attempt_receiver(receiver_known(left), receiver, declaration, identity, member, left, right, result, ambient, state, context)

def attempt_resolved(left: Result<&2, &2, M.Diagnostic, M.Ty>, right: Result<&2, &2, M.Diagnostic, M.Ty>, result: Result<&2, &2, M.Diagnostic, M.Ty>, ambient: M.EffectRow, dispatch: M.Dispatch, templates: List<&2, M.TypeId>, declaration: String, identity: Nat, member: String, state: I.State, context: SolveContext) -> Attempt:
  match left right result:
    case Done{l} Done{r} Done{value}:
      attempt_dispatch(dispatch, templates, declaration, identity, member, l, r, value, ambient, state, context)
    case _ _ _:
      Dropped{}

type Solving is Data:
  Solving{state: I.State, plans: List<&2, Plan>, waiting: List<&2, Groups.Resolution>, progress: Bool}

def solving_state(solving: Solving) -> I.State:
  Solving{state, plans, waiting, progress} = solving
  state

def settle(attempt: Attempt, need: Groups.Resolution, solving: Solving) -> Solving:
  match attempt:
    case Selected{plan, state}:
      Solving{previous, plans, waiting, progress} = solving
      Solving{state, plan <> plans, waiting, True{}}
    case Waiting{}:
      Solving{state, plans, waiting, progress} = solving
      Solving{state, plans, need <> waiting, progress}
    case Dropped{}:
      solving

# Requirement types are re-read through the substitutions earlier selections
# made: a result that a closed selection fixed closes the requirements that
# consume it, exactly as it would in every specialization of the group.
def solve_need(need: Groups.Resolution, +solving: Solving, context: SolveContext) -> Solving:
  match need:
    case Groups.Resolution{+declaration, +identity, +dispatch, +member, +templates, +left, +right, +result, +ambient}:
      +state = solving_state(solving)
      +substitutions = I.substitutions_of(state)
      settle(attempt_resolved(T.resolve(substitutions, left), T.resolve(substitutions, right), T.resolve(substitutions, result), T.resolve_row(substitutions, ambient), dispatch, templates, declaration, identity, member, state, context), Groups.Resolution{declaration, identity, dispatch, member, templates, left, right, result, ambient}, solving)

def solve_pass(needs: List<&2, Groups.Resolution>, solving: Solving, +context: SolveContext) -> Solving:
  match needs:
    case Nil{}:
      solving
    case need <> tail:
      solve_pass(tail, solve_need(need, solving, context), context)

# Passes repeat while one selects something; each pass selects at least one
# requirement, so a group needs at most one pass per requirement plus one.
def solve_work(fuel: Nat, solving: Solving, +context: SolveContext) -> Solving:
  match fuel solving:
    case 0n _:
      solving
    case 1n+rest Solving{state, plans, waiting, False{}}:
      Solving{state, plans, waiting, False{}}
    case 1n+rest Solving{state, plans, waiting, True{}}:
      solve_work(rest, solve_pass(List.reverse(&2, Groups.Resolution, waiting), Solving{state, plans, Nil{}, False{}}, context), context)

# A group's resolution is stable when its unifications leave every member's
# (ungeneralized) type and every local let's scheme unchanged: the rewritten
# declarations then check exactly as before and keep their interfaces, so no
# dependent can change and no new requirement can close. Anything else is
# checked again, and a failing check abandons resolution.
type Solved is Data:
  Solved{plans: List<&2, Plan>, stable: Bool}

def member_unchanged(resolved: Result<&2, &2, M.Diagnostic, M.Ty>, original: M.Ty) -> Bool:
  match resolved:
    case Fail{diagnostic}:
      False{}
    case Done{ty}:
      Compare.same_ty(ty, original)

def unchanged_members(members: List<&2, I.Binding>, +substitutions: T.Substitutions) -> Bool:
  match members:
    case Nil{}:
      True{}
    case I.Binding{name, +ty, variables} <> tail:
      Bool.and(member_unchanged(T.resolve(substitutions, ty), ty), unchanged_members(tail, substitutions))

def disjoint(variables: List<&2, Nat>, +generalized: List<&2, Nat>) -> Bool:
  match variables:
    case Nil{}:
      True{}
    case head <> tail:
      Bool.and(Bool.not(T.contains(generalized, head)), disjoint(tail, generalized))

def free_untouched(free: Result<&2, &2, M.Diagnostic, List<&2, Nat>>, generalized: List<&2, Nat>) -> Bool:
  match free:
    case Fail{diagnostic}:
      False{}
    case Done{variables}:
      disjoint(variables, generalized)

def type_untouched(resolved: Result<&2, &2, M.Diagnostic, M.Ty>, generalized: List<&2, Nat>) -> Bool:
  match resolved:
    case Fail{diagnostic}:
      False{}
    case Done{ty}:
      free_untouched(T.free(ty), generalized)

# One solver binding. Binding a let-generalized variable changes that let's
# scheme; binding a group variable (numbered below the group's `next`) to a
# type that mentions one moves it out of its let. Only a fresh variable of a
# selected implementation's instance may name one: that is exactly how the
# direct call instantiates inside the let. `replacement` is the resolved
# replacement's free-variable check, consulted only for group variables.
def binding_untouched(generalized_variable: Bool, group_variable: Bool, replacement: Bool) -> Bool:
  match generalized_variable group_variable:
    case True{} _:
      False{}
    case False{} True{}:
      replacement
    case False{} False{}:
      True{}

def history_untouched(history: List<&2, T.Substitution>, +substitutions: T.Substitutions, +generalized: List<&2, Nat>, +next: Nat) -> Bool:
  match history:
    case Nil{}:
      True{}
    case T.Substitution{+variable, replacement} <> tail:
      Bool.and(binding_untouched(T.contains(generalized, variable), Nat.is_lt(variable, next), type_untouched(T.resolve(substitutions, replacement), generalized)), history_untouched(tail, substitutions, generalized, next))
    case T.RowSubstitution{+variable, replacement} <> tail:
      Bool.and(binding_untouched(T.contains(generalized, variable), Nat.is_lt(variable, next), disjoint(T.row_free(T.resolve_row(substitutions, replacement)), generalized)), history_untouched(tail, substitutions, generalized, next))

def schemes_untouched(+substitutions: T.Substitutions, generalized: List<&2, Nat>, next: Nat) -> Bool:
  match generalized:
    case Nil{}:
      True{}
    case head <> tail:
      history_untouched(T.substitution_history(substitutions), substitutions, head <> tail, next)

# A group with no plan is stable; otherwise its local schemes and its members'
# interfaces must both be unchanged.
def stable_group(unplanned: Bool, untouched: Bool, unchanged: Bool) -> Bool:
  match unplanned untouched:
    case True{} _:
      True{}
    case False{} False{}:
      False{}
    case False{} True{}:
      unchanged

def solved_group(solving: Solving, members: List<&2, I.Binding>, generalized: List<&2, Nat>, next: Nat) -> Solved:
  Solving{state, +plans, waiting, progress} = solving
  +substitutions = I.substitutions_of(state)
  Solved{List.reverse(&2, Plan, plans), stable_group(List.is_empty(&2, Plan, plans), schemes_untouched(substitutions, generalized, next), unchanged_members(members, substitutions))}

def solve_group_in(group: Groups.GroupNeeds, +context: SolveContext) -> Solved:
  Groups.GroupNeeds{+next, +needs, members, generalized} = group
  solved_group(solve_work(2n+List.length(&2, Groups.Resolution, needs), Solving{scratch(next), Nil{}, List.reverse(&2, Groups.Resolution, needs), True{}}, context), members, generalized, next)

def solve_group(group: Groups.GroupNeeds, context: SolveContext) -> Solved:
  solve_group_in(group, context)

def weighted_groups(groups: List<&2, Groups.GroupNeeds>) -> List<&2, Batch.Weighted<Groups.GroupNeeds>>:
  match groups:
    case Nil{}:
      Nil{}
    case Groups.GroupNeeds{next, +needs, members, generalized} <> tail:
      Batch.Weighted{Groups.GroupNeeds{next, needs, members, generalized}, List.length(&2, Groups.Resolution, needs)} <> weighted_groups(tail)

def flatten_plans(groups: List<&2, Solved>) -> List<&2, Plan>:
  match groups:
    case Nil{}:
      Nil{}
    case Solved{plans, stable} <> tail:
      List.append(&2, Plan, plans, flatten_plans(tail))

def all_stable(groups: List<&2, Solved>) -> Bool:
  match groups:
    case Nil{}:
      True{}
    case Solved{plans, stable} <> tail:
      Bool.and(stable, all_stable(tail))

def chosen_name(choice: Mono.Choice) -> String:
  match choice:
    case Mono.FunctionChoice{name}:
      name
    case Mono.ReceiverChoice{name}:
      name
    case Mono.OperationChoice{identity}:
      ""

type Generated is Data:
  Generated{seen: Set(), functions: List<&2, M.Function>, certificates: List<&2, Core.Certificate>}

def generated_accessor(found: Maybe<&2, Accessor>, generated: Generated) -> Generated:
  match found:
    case None{}:
      generated
    case Some{Accessor{+name, function, certificate, binding}}:
      Generated{seen, functions, certificates} = generated
      Generated{Set.add(seen, name), function <> functions, certificate <> certificates}

def generated_name(+name: String, +known: Set(), +cache: Map<&2, Accessor>, generated: Generated) -> Generated:
  Generated{+seen, functions, certificates} = generated
  +fresh = Bool.and(Bool.not(D.member(known, name)), Bool.not(D.member(seen, name)))
  generated_accessor(Bool.pick(Maybe<&2, Accessor>, fresh, Index.find(Accessor, cache, name), None{}), Generated{seen, functions, certificates})

# New accessors enter the module in the order their first site was planned.
def generated_accessors(plans: List<&2, Plan>, +known: Set(), +cache: Map<&2, Accessor>, generated: Generated) -> Generated:
  match plans:
    case Nil{}:
      generated
    case Planned{declaration, key, choice} <> tail:
      generated_accessors(tail, known, cache, generated_name(chosen_name(choice), known, cache, generated))

# ---------------------------------------------------------------------------
# Rewriting
# ---------------------------------------------------------------------------

def choice_entry(present: Bool, choice: Mono.Choice) -> Maybe<&2, Mono.Choice>:
  match present:
    case True{}:
      None{}
    case False{}:
      Some{choice}

# A key that two requirements claim is a conflict: neither site is rewritten.
def add_choice(+choices: Map<&2, Map<&2, Maybe<&2, Mono.Choice>>>, +declaration: String, +key: String, choice: Mono.Choice) -> Map<&2, Map<&2, Maybe<&2, Mono.Choice>>>:
  +current = Index.get(Map<&2, Maybe<&2, Mono.Choice>>, choices, declaration, Map.new(&2, Maybe<&2, Mono.Choice>))
  Map.set(&2, Map<&2, Maybe<&2, Mono.Choice>>, choices, declaration, Map.set(&2, Maybe<&2, Mono.Choice>, current, key, choice_entry(Maybe.is_some(&2, Maybe<&2, Mono.Choice>, Index.find(Maybe<&2, Mono.Choice>, current, key)), choice)))

def declaration_choices(plans: List<&2, Plan>, choices: Map<&2, Map<&2, Maybe<&2, Mono.Choice>>>) -> Map<&2, Map<&2, Maybe<&2, Mono.Choice>>>:
  match plans:
    case Nil{}:
      choices
    case Planned{declaration, key, choice} <> tail:
      declaration_choices(tail, add_choice(choices, declaration, key, choice))
    case head <> tail:
      declaration_choices(tail, choices)

def resolved_call(found: Maybe<&2, Maybe<&2, Mono.Choice>>, identity: Nat, dispatch: M.Dispatch, member: String, templates: List<&2, M.TypeId>, left: M.Expr, right: M.Expr) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match found:
    case Some{Some{choice}}:
      Mono.selected_call(Some{choice}, member, left, right)
    case _:
      Done{M.AssociatedExpr{identity, dispatch, member, templates, left, right}}

def rewrite_node(original: M.Expr, children: List<&2, M.Expr>, +choices: Map<&2, Maybe<&2, Mono.Choice>>) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match original children:
    case M.AssociatedExpr{+identity, +dispatch, member, templates, left, right} l <> r <> Nil{}:
      resolved_call(Index.find(Maybe<&2, Mono.Choice>, choices, choice_key(identity, dispatch)), identity, dispatch, member, templates, l, r)
    case original children:
      Mono.rebuild(original, children, 0n)

type RewriteWork is Data:
  RewriteOne{value: M.Expr}
  RewriteMany{values: List<&2, M.Expr>, reversed: List<&2, M.Expr>}

def rewrite_work(+fuel: Nat, work: RewriteWork, +choices: Map<&2, Maybe<&2, Mono.Choice>>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"specialization_limit", "dispatch", "dispatch rewriting exceeded its structural limit"}}
    case 1n+rest RewriteOne{+expression}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        children : List<&2, M.Expr> <- rewrite_work(rest, RewriteMany{F.children(expression), Nil{}}, choices)
        rebuilt : M.Expr <- rewrite_node(expression, children, choices)
        return [rebuilt]
    case 1n+rest RewriteMany{Nil{}, reversed}:
      Done{List.reverse(&2, M.Expr, reversed)}
    case 1n+rest RewriteMany{head <> tail, reversed}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        first : List<&2, M.Expr> <- rewrite_work(rest, RewriteOne{head}, choices)
        rewrite_work(rest, RewriteMany{tail, List.reverse.go(&2, M.Expr, first, reversed)}, choices)

def rewritten_body(result: Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>, original: M.Expr) -> M.Expr:
  match result:
    case Done{expression <> Nil{}}:
      expression
    case _:
      original

def rewrite_body(+body: M.Expr, choices: Map<&2, Maybe<&2, Mono.Choice>>) -> M.Expr:
  rewritten_body(rewrite_work(65536n, RewriteOne{body}, choices), body)

type RewriteTask is Data:
  RewriteTask{declaration: G.Declaration, choices: Maybe<&2, Map<&2, Maybe<&2, Mono.Choice>>>}

def rewrite_declaration(task: RewriteTask, context: Unit) -> G.Declaration:
  match task:
    case RewriteTask{declaration, None{}}:
      declaration
    case RewriteTask{G.FunctionDeclaration{M.Function{name, exported, parameter, p, r, body}}, Some{choices}}:
      G.FunctionDeclaration{M.Function{name, exported, parameter, p, r, rewrite_body(body, choices)}}
    case RewriteTask{G.ConstantDeclaration{M.Constant{name, exported, annotation, value}}, Some{choices}}:
      G.ConstantDeclaration{M.Constant{name, exported, annotation, rewrite_body(value, choices)}}

def rewrite_cost(found: Maybe<&2, Map<&2, Maybe<&2, Mono.Choice>>>, declaration: G.Declaration) -> Nat:
  match found:
    case None{}:
      1n
    case Some{choices}:
      Mono.declaration_cost(declaration)

def rewrite_tasks(declarations: List<&2, G.Declaration>, +choices: Map<&2, Map<&2, Maybe<&2, Mono.Choice>>>) -> List<&2, Batch.Weighted<RewriteTask>>:
  match declarations:
    case Nil{}:
      Nil{}
    case +declaration <> tail:
      +found = Index.find(Map<&2, Maybe<&2, Mono.Choice>>, choices, G.declaration_name(declaration))
      Batch.Weighted{RewriteTask{declaration, found}, rewrite_cost(found, declaration)} <> rewrite_tasks(tail, choices)

def function_names(functions: List<&2, M.Function>, names: Set()) -> Set():
  match functions:
    case Nil{}:
      names
    case M.Function{name, exported, parameter, p, r, body} <> tail:
      function_names(tail, Set.add(names, name))

def planned_count(plans: List<&2, Plan>, count: Nat) -> Nat:
  match plans:
    case Nil{}:
      count
    case Planned{declaration, key, choice} <> tail:
      planned_count(tail, 1n+count)

type Rewrite is Data:
  Rewrite{module: M.Module, certificates: List<&2, Core.Certificate>, next: Nat, cache: Map<&2, Accessor>, changed: Bool, stable: Bool}

def rewritten_module(+rewritten: List<&2, G.Declaration>, generated: Generated, types: List<&2, M.DataType>, operations: List<&2, M.Operation>, next: Nat, cache: Map<&2, Accessor>, changed: Bool, stable: Bool) -> Rewrite:
  Generated{seen, added, certificates} = generated
  Rewrite{M.Module{declaration_constants(rewritten), List.append(&2, M.Function, declaration_functions(rewritten), List.reverse(&2, M.Function, added)), types, operations}, List.reverse(&2, Core.Certificate, certificates), next, cache, changed, stable}

def rewrite_planned(+plans: List<&2, Plan>, module: M.Module, +known: Set(), +cache: Map<&2, Accessor>, next: Nat, stable: Bool) -> Rewrite:
  M.Module{constants, functions, types, operations} = module
  +declarations = List.append(&2, G.Declaration, G.function_declarations(functions), G.constant_declarations(constants))
  rewritten = Batch.execute(~RewriteTask, ~Unit, ~G.Declaration, ~rewrite_declaration, Batch.plan(RewriteTask, rewrite_tasks(declarations, declaration_choices(plans, Map.new(&2, Map<&2, Maybe<&2, Mono.Choice>>))), 2048n), Unit{})
  rewritten_module(rewritten, generated_accessors(plans, known, cache, Generated{Set.new(), Nil{}, Nil{}}), types, operations, next, cache, Nat.is_gt(planned_count(plans, 0n), 0n), stable)

def rewrite_round(+module: M.Module, initial: Scheduler.Initial, +entry: String, next: Nat, proofs: List<&2, Schema.Evidence>, +cache: Map<&2, Accessor>) -> Rewrite:
  M.Module{constants, +functions, +types, operations} = module
  Scheduler.Initial{checked, certificates, +needs} = initial
  +known = function_names(functions, Set.new())
  +requests = group_requests(needs, types, known, cache, entry, Requests{Set.new(), Nil{}, next})
  built = Batch.execute(~AccessorRequest, ~Unit, ~Maybe<&2, Accessor>, ~build_accessor, Batch.plan(AccessorRequest, weighted_requests(request_list(requests)), 128n), Unit{})
  +accessors = cache_accessors(built, cache)
  +bindings = Public.binding_index(G.env_bindings(Mono.shape_bindings(checked)), MTip{})
  +solved = Batch.execute(~Groups.GroupNeeds, ~SolveContext, ~Solved, ~solve_group, Batch.plan(Groups.GroupNeeds, weighted_groups(needs), 256n), SolveContext{bindings, accessors, types, entry, proofs})
  rewrite_planned(flatten_plans(solved), module, known, accessors, request_next(requests), all_stable(solved))

# ---------------------------------------------------------------------------
# Rounds
# ---------------------------------------------------------------------------

type Resolved is Data:
  Resolved{module: M.Module, initial: Scheduler.Initial}

type RoundWork is Data:
  CheckRound{module: M.Module, certificates: List<&2, Core.Certificate>, next: Nat, proofs: Maybe<&2, List<&2, Schema.Evidence>>, cache: Map<&2, Accessor>, budget: Nat}
  CheckedRound{module: M.Module, checked: Result<&2, &2, M.Diagnostic, Scheduler.Initial>, next: Nat, proofs: Maybe<&2, List<&2, Schema.Evidence>>, cache: Map<&2, Accessor>, budget: Nat}
  RewrittenRound{initial: Scheduler.Initial, rewrite: Rewrite, proofs: List<&2, Schema.Evidence>, budget: Nat}

# Linked-schema evidence comes from the first round's source check; resolution
# never rewrites the functions it certifies.
def captured_proofs(found: Maybe<&2, List<&2, Schema.Evidence>>, module: M.Module, initial: Scheduler.Initial, entry: String) -> List<&2, Schema.Evidence>:
  match found:
    case Some{proofs}:
      proofs
    case None{}:
      M.Module{constants, functions, types, operations} = module
      Schema.capture(functions, types, Scheduler.initial_checked(initial), entry)

def certificate_functions(certificates: List<&2, Core.Certificate>) -> List<&2, M.CheckedFunction>:
  match certificates:
    case Nil{}:
      Nil{}
    case Core.Certificate{module, Groups.CheckedGroup{M.CheckedModule{constants, functions, types, operations}, interfaces}, imports} <> tail:
      List.append(&2, M.CheckedFunction, functions, certificate_functions(tail))

# A stable rewrite needs no further check: every interface is unchanged, so the
# last check still describes the module apart from the added accessors, whose
# independent checks are appended. The final check re-infers the rewritten
# groups, whose certificates no longer match their bodies.
def extended_initial(initial: Scheduler.Initial, +certificates: List<&2, Core.Certificate>) -> Scheduler.Initial:
  Scheduler.Initial{M.CheckedModule{constants, functions, types, operations}, existing, needs} = initial
  Scheduler.Initial{M.CheckedModule{constants, List.append(&2, M.CheckedFunction, functions, certificate_functions(certificates)), types, operations}, List.append(&2, Core.Certificate, certificates, existing), needs}

def round_budget() -> Nat:
  32n

def rounds(fuel: Nat, work: RoundWork, +entry: String) -> Maybe<&2, Resolved>:
  match fuel work:
    case 0n _:
      None{}
    case 1n+rest CheckRound{+module, certificates, next, proofs, cache, budget}:
      rounds(rest, CheckedRound{module, Scheduler.check_module_resolving(module, certificates), next, proofs, cache, budget}, entry)
    case 1n+rest CheckedRound{module, Fail{diagnostic}, next, proofs, cache, budget}:
      None{}
    case 1n+rest CheckedRound{module, Done{initial}, next, proofs, cache, 0n}:
      Some{Resolved{module, initial}}
    case 1n+rest CheckedRound{+module, Done{+initial}, next, proofs, cache, 1n+budget}:
      +evidence = captured_proofs(proofs, module, initial, entry)
      rounds(rest, RewrittenRound{initial, rewrite_round(module, initial, entry, next, evidence, cache), evidence, budget}, entry)
    case 1n+rest RewrittenRound{initial, Rewrite{module, certificates, next, cache, False{}, stable}, proofs, budget}:
      Some{Resolved{module, initial}}
    case 1n+rest RewrittenRound{initial, Rewrite{module, certificates, next, cache, True{}, True{}}, proofs, budget}:
      Some{Resolved{module, extended_initial(initial, certificates)}}
    case 1n+rest RewrittenRound{initial, Rewrite{module, certificates, next, cache, True{}, False{}}, proofs, budget}:
      rounds(rest, CheckRound{module, List.append(&2, Core.Certificate, certificates, Scheduler.initial_certificates(initial)), next, Some{proofs}, cache, budget}, entry)

def resolve_scanned(scan: DispatchScan, limit: Result<&2, &2, M.Diagnostic, Nat>, module: M.Module, entry: String) -> Maybe<&2, Resolved>:
  match scan limit:
    case DispatchScan{0n, seen, unique} _:
      None{}
    case DispatchScan{count, seen, False{}} _:
      None{}
    case DispatchScan{count, seen, True{}} Done{next}:
      rounds(Nat.mul(3n, 2n+round_budget()), CheckRound{module, Nil{}, next, None{}, Map.new(&2, Accessor), round_budget()}, entry)
    case _ Fail{diagnostic}:
      None{}

def module_identity_limit(module: M.Module) -> Result<&2, &2, M.Diagnostic, Nat>:
  M.Module{constants, functions, types, operations} = module
  Mono.identity_limit(1048576n, Mono.module_expressions(functions, constants), 0n)

def resolve(module: M.Module, entry: String) -> Maybe<&2, Resolved>:
  +inlined = inline_module(module)
  resolve_scanned(scan_module(inlined), module_identity_limit(inlined), inlined, entry)

# ---------------------------------------------------------------------------
# Entry points
# ---------------------------------------------------------------------------

def prepare_resolved(found: Maybe<&2, Resolved>, module: M.Module, entry: String, family_templates: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match found:
    case None{}:
      Mono.prepare(module, entry, family_templates)
    case Some{Resolved{resolved, initial}}:
      Mono.prepare_checked(resolved, entry, family_templates, Scheduler.initial_checked(initial))

def prepare(+module: M.Module, +entry: String, family_templates: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, M.Module>:
  prepare_resolved(resolve(module, entry), module, entry, family_templates)

def prepare_deferred_resolved(found: Maybe<&2, Resolved>, module: M.Module, entry: String, family_templates: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, Core.Prepared>:
  match found:
    case None{}:
      Mono.prepare_deferred_core(module, entry, family_templates)
    case Some{Resolved{resolved, initial}}:
      Mono.prepare_deferred_initial(resolved, entry, family_templates, initial)

def prepare_deferred_core(+module: M.Module, +entry: String, family_templates: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, Core.Prepared>:
  prepare_deferred_resolved(resolve(module, entry), module, entry, family_templates)

def prepare_deferred(module: M.Module, entry: String, family_templates: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, M.Module>:
  do Result<&2, &2, M.Diagnostic, M.Module>:
    prepared : Core.Prepared <- prepare_deferred_core(module, entry, family_templates)
    return Core.prepared_module(prepared)

def prepare_cached_resolved(~key: M.Module -> Result<&2, &2, M.Diagnostic, List<&2, U32>>, found: Maybe<&2, Resolved>, module: M.Module, entry: String, family_templates: List<&2, M.Operation>, previous: Maybe<&2, Mono.Cache>, retain: Bool) -> Result<&2, &2, M.Diagnostic, Mono.Prepared>:
  match found:
    case None{}:
      Mono.prepare_cached_evidenced(~key, module, entry, family_templates, previous, retain)
    case Some{Resolved{resolved, initial}}:
      Mono.prepare_cached_initial(~key, resolved, entry, family_templates, previous, initial)

def prepare_cached_evidenced(~key: M.Module -> Result<&2, &2, M.Diagnostic, List<&2, U32>>, +module: M.Module, +entry: String, family_templates: List<&2, M.Operation>, previous: Maybe<&2, Mono.Cache>, retain: Bool) -> Result<&2, &2, M.Diagnostic, Mono.Prepared>:
  prepare_cached_resolved(~key, resolve(module, entry), module, entry, family_templates, previous, retain)
