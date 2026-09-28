import Base
import ./model.bend as M
import ./closures.bend as F
import ./dependency.bend as D
import ./infer.bend as I
import ./globals.bend as G
import ./types.bend as T
import ./constraints.bend as C
import ./effect_rows.bend as Rows
import ./check.bend as Check
import ./check_scheduler.bend as Scheduler
import ./index.bend as Index
import ./state_specialize.bend as State
import ./inference_batch.bend as Batch
import ./public_exports.bend as Public
import ./members.bend as Members
import ./checked_core.bend as Core
import ./groups.bend as Groups
import ./type_data.bend as TD
import ./staging_scheme.bend as Staging
import ./schema_stage.bend as Schema
import ./state_run_evidence.bend as StateEvidence
import ./state_scoped_evidence.bend as ScopedStateEvidence
import ./type_eq_evidence.bend as TypeEq
import ./selected_binding_evidence.bend as SelectedBindingEvidence
import ./core_compare.bend as Compare
import ./global_bindings.bend as Bindings
import ./parallel_infer.bend as ParallelInfer
import ./entry_points.bend as Entries

type Rename is Data:
  Rename{original: String, specialized: String}

type LocalTemplate is Data:
  LocalTemplate{name: String, value: M.Expr}

# This value is created only by a successful same-choice, full-module body
# recheck. It is not a property of a generalized binding or of a selected name.
type MemberEvidenceCertificate is Data:
  MemberEvidenceCertificate{name: String, signature: M.Ty}

type MemberRowProof is Data:
  MemberRowProof{state: I.State, certified: List<&2, MemberEvidenceCertificate>}

type Configuration is Data:
  Configuration{functions: List<&2, M.Function>, templates: List<&2, String>, entry: String, locals: List<&2, LocalTemplate>, affected: List<&2, String>, stride: Nat, constants: List<&2, M.Constant>, family_templates: List<&2, M.Operation>, step: Nat, schema: List<&2, Schema.Evidence>}

type Expansion is Data:
  Expansion{expressions: List<&2, M.Expr>, functions: List<&2, M.Function>, constants: List<&2, M.Constant>, next: Nat}

type BinaryCall is Data:
  BinaryCall{member: String, templates: List<&2, M.TypeId>, left: M.Expr, right: M.Expr}

type BinaryMember is Data:
  BinaryMember{member: String, templates: List<&2, M.TypeId>}

type ExpandWork is Data:
  Expression{value: M.Expr}
  Expressions{values: List<&2, M.Expr>}
  Reference{name: String, needed: Bool, active: Maybe<&2, String>}
  Clone{function: M.Function}
  LocalValue{name: String, template: Maybe<&2, M.Expr>}
  ConstantValue{name: String, template: Maybe<&2, M.Expr>}
  ConstantReference{name: String, original: Maybe<&2, M.Constant>, active: Maybe<&2, String>}
  LetValue{name: String, value: M.Expr, body: M.Expr, inline: Bool}
  Application{callee: M.Expr, argument: M.Expr, direct: Maybe<&2, BinaryCall>}

def expressions(value: Expansion) -> List<&2, M.Expr>:
  Expansion{expressions, functions, constants, next} = value
  expressions

def functions(value: Expansion) -> List<&2, M.Function>:
  Expansion{expressions, functions, constants, next} = value
  functions

def next(value: Expansion) -> Nat:
  Expansion{expressions, functions, constants, next} = value
  next

def emitted_constants(value: Expansion) -> List<&2, M.Constant>:
  Expansion{expressions, functions, constants, next} = value
  constants

def one(values: List<&2, M.Expr>) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match values:
    case head <> Nil{}:
      Done{head}
    case _:
      Fail{M.Diagnostic{"internal_error", "monomorphization", "lost an expression during specialization"}}

def renamed_work(names: List<&2, Rename>, +wanted: String, found: Maybe<&2, String>) -> Maybe<&2, String>:
  match names found:
    case _ Some{specialized}:
      Some{specialized}
    case Nil{} None{}:
      None{}
    case Rename{original, specialized} <> tail None{}:
      renamed_work(tail, wanted, Bool.pick(Maybe<&2, String>, M.name_equal(original, wanted), Some{specialized}, None{}))

def renamed(names: List<&2, Rename>, wanted: String) -> Maybe<&2, String>:
  renamed_work(names, wanted, None{})

def lookup_work(functions: List<&2, M.Function>, +wanted: String, found: Maybe<&2, M.Function>) -> Result<&2, &2, M.Diagnostic, M.Function>:
  match functions found:
    case _ Some{function}:
      Done{function}
    case Nil{} None{}:
      Fail{M.Diagnostic{"unknown_function", wanted, "missing function during specialization"}}
    case M.Function{+name, exported, parameter, p, r, body} <> tail None{}:
      lookup_work(tail, wanted, Bool.pick(Maybe<&2, M.Function>, M.name_equal(name, wanted), Some{M.Function{name, exported, parameter, p, r, body}}, None{}))

def lookup(functions: List<&2, M.Function>, wanted: String) -> Result<&2, &2, M.Diagnostic, M.Function>:
  lookup_work(functions, wanted, None{})

def lookup_constant_work(constants: List<&2, M.Constant>, +wanted: String, found: Maybe<&2, M.Constant>) -> Maybe<&2, M.Constant>:
  match constants found:
    case _ Some{constant}:
      Some{constant}
    case Nil{} None{}:
      None{}
    case M.Constant{+name, exported, annotation, value} <> tail None{}:
      lookup_constant_work(tail, wanted, Bool.pick(Maybe<&2, M.Constant>, M.name_equal(name, wanted), Some{M.Constant{name, exported, annotation, value}}, None{}))

def lookup_constant(constants: List<&2, M.Constant>, wanted: String) -> Maybe<&2, M.Constant>:
  lookup_constant_work(constants, wanted, None{})

def has_deferred(fuel: Nat, pending: List<&2, M.Expr>) -> Bool:
  match fuel pending:
    case _ Nil{}:
      False{}
    case 0n _:
      True{}
    case 1n+rest M.AssociatedExpr{identity, dispatch, member, templates, left, right} <> tail:
      True{}
    case 1n+rest M.GenericOperationExpr{identity, template, arguments} <> tail:
      True{}
    case 1n+rest M.QualifiedExpr{offset, annotation, predicates, value} <> tail:
      True{}
    case 1n+rest head <> tail:
      has_deferred(rest, List.reverse.go(&2, M.Expr, List.reverse(&2, M.Expr, F.children(head)), tail))

def seeds(functions: List<&2, M.Function>) -> List<&2, String>:
  match functions:
    case Nil{}:
      Nil{}
    case M.Function{name, exported, parameter, p, r, body} <> tail:
      +rest = seeds(tail)
      Bool.pick(List<&2, String>, has_deferred(65536n, [body]), name <> rest, rest)

def constant_seeds(constants: List<&2, M.Constant>) -> List<&2, String>:
  match constants:
    case Nil{}:
      Nil{}
    case M.Constant{name, exported, annotation, value} <> tail:
      +rest = constant_seeds(tail)
      Bool.pick(List<&2, String>, has_deferred(65536n, [value]), name <> rest, rest)

# Every transitive caller of a template seed is a template too: the closure is
# reverse reachability from the seeds. A traversal failure keeps every
# declaration a template, which only costs specialization time.
def closure_found(found: Result<&2, &2, M.Diagnostic, D.Reachability>, names: List<&2, String>) -> List<&2, String>:
  match found:
    case Done{reached}:
      List.reverse(&2, String, D.reached_members(reached))
    case Fail{diagnostic}:
      names

def template_closure(+nodes: List<&2, D.Node>, seeds: List<&2, String>) -> List<&2, String>:
  +names = D.node_names(nodes)
  closure_found(D.reachable(1n+Nat.add(List.length(&2, String, names), D.edge_count(nodes)), seeds, D.transpose(nodes, Map.new(&2, List<&2, String>)), Set.from_list(names), Set.new(), Nil{}), names)

def rebuild_arms(arms: List<&2, M.MatchArm<M.Expr>>, bodies: List<&2, M.Expr>) -> List<&2, M.MatchArm<M.Expr>>:
  match arms bodies:
    case M.MatchArm{patterns, old} <> tail body <> remaining:
      M.MatchArm{patterns, body} <> rebuild_arms(tail, remaining)
    case _ _:
      Nil{}

# A clone owns a disjoint range of lambda, return-label and dispatch identities.
def identity(base: Nat, original: Nat) -> Nat:
  Nat.add(base, original)

def relocate_annotation(annotation: Maybe<&2, M.Ty>, +base: Nat) -> Result<&2, &2, M.Diagnostic, Maybe<&2, M.Ty>>:
  match annotation base:
    case annotation 0n:
      Done{annotation}
    case None{} _:
      Done{None{}}
    case Some{ty} _:
      do Result<&2, &2, M.Diagnostic, Maybe<&2, M.Ty>>:
        types : List<&2, M.Ty> <- T.rewrite(65536n, T.OneType{ty}, T.RelocateFree{"$mono[" ++ Nat.show(base) ++ "]"})
        relocated : M.Ty <- T.first_type(types)
        return Some{relocated}

def relocate_arguments(arguments: List<&2, M.Ty>, base: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match base:
    case 0n:
      Done{arguments}
    case base:
      T.rewrite(65536n, T.ManyTypes{arguments}, T.RelocateFree{"$mono[" ++ Nat.show(base) ++ "]"})

def relocate_predicates(predicates: List<&2, M.Predicate>, base: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  match base:
    case 0n:
      Done{predicates}
    case base:
      C.relocate_free(predicates, "$mono[" ++ Nat.show(base) ++ "]")

def rebuild(original: M.Expr, children: List<&2, M.Expr>, +base: Nat) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match original children:
    case M.ConstructExpr{constructor, Some{payload}} a <> Nil{}:
      Done{M.ConstructExpr{constructor, Some{a}}}
    case M.ProductExpr{elements} children:
      Done{M.ProductExpr{children}}
    case M.ArrayExpr{elements} children:
      Done{M.ArrayExpr{children}}
    case M.ProjectExpr{value, index} a <> Nil{}:
      Done{M.ProjectExpr{a, index}}
    case M.LambdaExpr{old, parameter, p, r, body} a <> Nil{}:
      do Result<&2, &2, M.Diagnostic, M.Expr>:
        parameter_type : Maybe<&2, M.Ty> <- relocate_annotation(p, base)
        result_type : Maybe<&2, M.Ty> <- relocate_annotation(r, base)
        return M.LambdaExpr{identity(base, old), parameter, parameter_type, result_type, a}
    case M.ApplyExpr{callee, argument} a <> b <> Nil{}:
      Done{M.ApplyExpr{a, b}}
    case M.TagExpr{offset, callee, argument} a <> b <> Nil{}:
      Done{M.TagExpr{offset, a, b}}
    case M.CallExpr{callee, argument} a <> Nil{}:
      Done{M.CallExpr{callee, a}}
    case M.ScalarExpr{operator, left, right} a <> b <> Nil{}:
      Done{M.ScalarExpr{operator, a, b}}
    case M.GenericOperationExpr{old, template, arguments} Nil{}:
      do Result<&2, &2, M.Diagnostic, M.Expr>:
        relocated : List<&2, M.Ty> <- relocate_arguments(arguments, base)
        return M.GenericOperationExpr{identity(base, old), template, relocated}
    case M.AssociatedExpr{old, dispatch, member, templates, left, right} a <> b <> Nil{}:
      Done{M.AssociatedExpr{identity(base, old), dispatch, member, templates, a, b}}
    case M.UnaryExpr{operator, value} a <> Nil{}:
      Done{M.UnaryExpr{operator, a}}
    case M.LetExpr{name, value, body} a <> b <> Nil{}:
      Done{M.LetExpr{name, a, b}}
    case M.UseExpr{name, value, body} a <> b <> Nil{}:
      Done{M.UseExpr{name, a, b}}
    case M.IfExpr{condition, consequent, alternative} a <> b <> c <> Nil{}:
      Done{M.IfExpr{a, b, c}}
    case M.SequenceExpr{first, next} a <> b <> Nil{}:
      Done{M.SequenceExpr{a, b}}
    case M.GuardExpr{pattern, value, alternative, body} a <> b <> c <> Nil{}:
      Done{M.GuardExpr{pattern, a, b, c}}
    case M.BlockExpr{label, body} a <> Nil{}:
      Done{M.BlockExpr{identity(base, label), a}}
    case M.ReturnExpr{label, value} a <> Nil{}:
      Done{M.ReturnExpr{identity(base, label), a}}
    case M.RuntimeInitExpr{value} a <> Nil{}:
      Done{M.RuntimeInitExpr{a}}
    case M.SourceExpr{offset, annotation, value} a <> Nil{}:
      do Result<&2, &2, M.Diagnostic, M.Expr>:
        relocated : Maybe<&2, M.Ty> <- relocate_annotation(annotation, base)
        return M.SourceExpr{offset, relocated, a}
    case M.QualifiedExpr{offset, annotation, predicates, value} a <> Nil{}:
      do Result<&2, &2, M.Diagnostic, M.Expr>:
        types : List<&2, M.Ty> <- relocate_arguments([annotation], base)
        relocated : M.Ty <- T.first_type(types)
        requirements : List<&2, M.Predicate> <- relocate_predicates(predicates, base)
        return M.QualifiedExpr{offset, relocated, requirements, a}
    case M.InstantiationExpr{site, value} a <> Nil{}:
      Done{M.InstantiationExpr{identity(base, site), a}}
    case M.StateProviderExpr{read, write, initial} a <> Nil{}:
      Done{M.StateProviderExpr{read, write, a}}
    case M.ProviderExpr{operation, implementation} a <> Nil{}:
      Done{M.ProviderExpr{operation, a}}
    case M.HandleExpr{provider, body} a <> b <> Nil{}:
      Done{M.HandleExpr{a, b}}
    case M.EffectHasExpr{set, operation} a <> b <> Nil{}:
      Done{M.EffectHasExpr{a, b}}
    case M.EffectCountExpr{set} a <> Nil{}:
      Done{M.EffectCountExpr{a}}
    case M.EffectSameExpr{left, right} a <> b <> Nil{}:
      Done{M.EffectSameExpr{a, b}}
    case M.ForExpr{index, start, end, state, initial, body} a <> b <> c <> d <> Nil{}:
      Done{M.ForExpr{index, a, b, state, c, d}}
    case M.ForeverExpr{state, initial, body} a <> b <> Nil{}:
      Done{M.ForeverExpr{state, a, b}}
    case M.ArrayGenerateExpr{count, generator} a <> b <> Nil{}:
      Done{M.ArrayGenerateExpr{a, b}}
    case M.ArrayFillExpr{count, value} a <> b <> Nil{}:
      Done{M.ArrayFillExpr{a, b}}
    case M.ArrayGetExpr{array, index} a <> b <> Nil{}:
      Done{M.ArrayGetExpr{a, b}}
    case M.ArraySetExpr{array, index, value} a <> b <> c <> Nil{}:
      Done{M.ArraySetExpr{a, b, c}}
    case M.ArrayLengthExpr{array} a <> Nil{}:
      Done{M.ArrayLengthExpr{a}}
    case M.MatchExpr{+values, arms} +children:
      Done{M.MatchExpr{List.take(&2, M.Expr, children, List.length(&2, M.Expr, values)), rebuild_arms(arms, List.drop(&2, M.Expr, children, List.length(&2, M.Expr, values)))}}
    case original Nil{}:
      Done{original}
    case _ _:
      Fail{M.Diagnostic{"internal_error", "monomorphization", "expression children differ from their parent"}}

def local_template_work(locals: List<&2, LocalTemplate>, +wanted: String, found: Maybe<&2, M.Expr>) -> Maybe<&2, M.Expr>:
  match locals found:
    case _ Some{value}:
      Some{value}
    case Nil{} None{}:
      None{}
    case LocalTemplate{name, value} <> tail None{}:
      local_template_work(tail, wanted, Bool.pick(Maybe<&2, M.Expr>, M.name_equal(name, wanted), Some{value}, None{}))

def local_template(locals: List<&2, LocalTemplate>, wanted: String) -> Maybe<&2, M.Expr>:
  local_template_work(locals, wanted, None{})

def template_value(fuel: Nat, expression: M.Expr) -> Bool:
  match fuel expression:
    case 0n _:
      False{}
    case 1n+rest M.SourceExpr{offset, annotation, value}:
      template_value(rest, value)
    case 1n+rest M.QualifiedExpr{offset, annotation, predicates, value}:
      template_value(rest, value)
    case 1n+rest M.InstantiationExpr{site, value}:
      template_value(rest, value)
    case _ M.FunctionExpr{name}:
      True{}
    case _ M.ConstantExpr{name}:
      True{}
    case _ M.GenericOperationExpr{identity, template, arguments}:
      True{}
    case _ M.ConstructorRefExpr{constructor}:
      True{}
    case _ M.LambdaExpr{identity, parameter, p, r, body}:
      True{}
    case _ _:
      False{}

def bind_template(configuration: Configuration, name: String, value: M.Expr) -> Configuration:
  Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
  Configuration{originals, templates, entry, LocalTemplate{name, value} <> locals, affected, stride, constant_values, family_templates, step, schema}

def unlocated(fuel: Nat, expression: M.Expr) -> M.Expr:
  match fuel expression:
    case 1n+rest M.SourceExpr{offset, None{}, value}:
      unlocated(rest, value)
    case 1n+rest M.InstantiationExpr{site, value}:
      unlocated(rest, value)
    case _ other:
      other

def binary_operands(l: M.Expr, r: M.Expr, left: String, right: String, member: String, templates: List<&2, M.TypeId>) -> Maybe<&2, BinaryMember>:
  match l r:
    case M.LocalExpr{a} M.LocalExpr{b}:
      Bool.pick(Maybe<&2, BinaryMember>, Bool.and(M.name_equal(a, left), M.name_equal(b, right)), Some{BinaryMember{member, templates}}, None{})
    case _ _:
      None{}

def binary_member(body: M.Expr, +left: String, +right: String) -> Maybe<&2, BinaryMember>:
  match body:
    case M.AssociatedExpr{identity, M.BinaryDispatch{}, member, templates, l, r}:
      binary_operands(unlocated(65536n, l), unlocated(65536n, r), left, right, member, templates)
    case _:
      None{}

def binary_lambda(body: M.Expr, left: String) -> Maybe<&2, BinaryMember>:
  match body:
    case M.LambdaExpr{identity, right, None{}, None{}, body}:
      binary_member(unlocated(65536n, body), left, right)
    case _:
      None{}

def binary_function(found: Result<&2, &2, M.Diagnostic, M.Function>) -> Maybe<&2, BinaryMember>:
  match found:
    case Done{M.Function{name, exported, left, None{}, None{}, body}}:
      binary_lambda(unlocated(65536n, body), left)
    case _:
      None{}

def binary_result(member: Maybe<&2, BinaryMember>, left: M.Expr, right: M.Expr) -> Maybe<&2, BinaryCall>:
  match member:
    case Some{BinaryMember{name, templates}}:
      Some{BinaryCall{name, templates, left, right}}
    case None{}:
      None{}

def binary_target(target: M.Expr, left: M.Expr, right: M.Expr, originals: List<&2, M.Function>) -> Maybe<&2, BinaryCall>:
  match target:
    case M.FunctionExpr{name}:
      binary_result(binary_function(lookup(originals, name)), left, right)
    case _:
      None{}

def binary_call(callee: M.Expr, right: M.Expr, originals: List<&2, M.Function>) -> Maybe<&2, BinaryCall>:
  match callee:
    case M.ApplyExpr{target, left}:
      binary_target(unlocated(65536n, target), left, right, originals)
    case M.CallExpr{name, left}:
      binary_target(M.FunctionExpr{name}, left, right, originals)
    case _:
      None{}

def expand(+fuel: Nat, work: ExpandWork, +configuration: Configuration, +stack: List<&2, Rename>, +base: Nat, +counter: Nat) -> Result<&2, &2, M.Diagnostic, Expansion>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"specialization_limit", "monomorphization", "specialization exceeded its structural limit"}}
    case 1n+rest Expression{M.ConstantExpr{+name}}:
      Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      expand(rest, ConstantValue{name, local_template(locals, name)}, configuration, stack, base, counter)
    case 1n+rest ConstantValue{+name, None{}}:
      Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      expand(rest, ConstantReference{name, lookup_constant(constant_values, name), renamed(stack, name)}, configuration, stack, base, counter)
    case 1n+rest ConstantReference{name, None{}, active}:
      Done{Expansion{[M.ConstantExpr{name}], Nil{}, Nil{}, counter}}
    case 1n+rest ConstantReference{name, Some{original}, Some{specialized}}:
      Done{Expansion{[M.ConstantExpr{specialized}], Nil{}, Nil{}, counter}}
    case 1n+rest ConstantReference{+name, Some{M.Constant{declared, exported, annotation, value}}, None{}}:
      Configuration{originals, templates, entry, locals, affected, +stride, constant_values, family_templates, step, schema} = configuration
      +specialized = "$mono[" ++ Nat.show(counter) ++ "]." ++ name
      do Result<&2, &2, M.Diagnostic, Expansion>:
        +expanded : Expansion <- expand(rest, Expression{value}, configuration, Rename{name, specialized} <> stack, Nat.mul(counter, stride), Nat.add(counter, step))
        expression : M.Expr <- one(expressions(expanded))
        relocated : Maybe<&2, M.Ty> <- relocate_annotation(annotation, Nat.mul(counter, stride))
        return Expansion{[M.ConstantExpr{specialized}], functions(expanded), M.Constant{specialized, False{}, relocated, expression} <> emitted_constants(expanded), next(expanded)}
    case 1n+rest ConstantValue{name, Some{value}}:
      Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      expand(rest, Expression{value}, configuration, stack, Nat.mul(counter, stride), Nat.add(counter, step))
    case 1n+rest Expression{M.LocalExpr{+name}}:
      Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      expand(rest, LocalValue{name, local_template(locals, name)}, configuration, stack, base, counter)
    case 1n+rest LocalValue{name, None{}}:
      Done{Expansion{[M.LocalExpr{name}], Nil{}, Nil{}, counter}}
    case 1n+rest LocalValue{name, Some{value}}:
      Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      expand(rest, Expression{value}, configuration, stack, Nat.mul(counter, stride), Nat.add(counter, step))
    case 1n+rest Expression{M.LetExpr{name, +value, body}}:
      expand(rest, LetValue{name, value, body, template_value(65536n, value)}, configuration, stack, base, counter)
    case 1n+rest LetValue{name, value, body, True{}}:
      expand(rest, Expression{body}, bind_template(configuration, name, value), stack, base, counter)
    case 1n+rest LetValue{+name, +value, +body, False{}}:
      do Result<&2, &2, M.Diagnostic, Expansion>:
        +expanded : Expansion <- expand(rest, Expressions{[value, body]}, configuration, stack, base, counter)
        expression : M.Expr <- rebuild(M.LetExpr{name, value, body}, expressions(expanded), base)
        return Expansion{[expression], functions(expanded), emitted_constants(expanded), next(expanded)}
    case 1n+rest Expression{M.FunctionExpr{+name}}:
      Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      expand(rest, Reference{name, D.contains(templates, name), renamed(stack, name)}, configuration, stack, base, counter)
    case 1n+rest Reference{name, False{}, active}:
      Done{Expansion{[M.FunctionExpr{name}], Nil{}, Nil{}, counter}}
    case 1n+rest Reference{name, True{}, Some{specialized}}:
      Done{Expansion{[M.FunctionExpr{specialized}], Nil{}, Nil{}, counter}}
    case 1n+rest Reference{name, True{}, None{}}:
      Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      do Result<&2, &2, M.Diagnostic, Expansion>:
        original : M.Function <- lookup(originals, name)
        expand(rest, Clone{original}, configuration, stack, base, counter)
    case 1n+rest Clone{M.Function{+name, exported, parameter, p, r, body}}:
      Configuration{originals, templates, entry, locals, affected, +stride, constant_values, family_templates, step, schema} = configuration
      +specialized = "$mono[" ++ Nat.show(counter) ++ "]." ++ name
      do Result<&2, &2, M.Diagnostic, Expansion>:
        +expanded : Expansion <- expand(rest, Expression{body}, configuration, Rename{name, specialized} <> stack, Nat.mul(counter, stride), Nat.add(counter, step))
        expression : M.Expr <- one(expressions(expanded))
        parameter_type : Maybe<&2, M.Ty> <- relocate_annotation(p, Nat.mul(counter, stride))
        result_type : Maybe<&2, M.Ty> <- relocate_annotation(r, Nat.mul(counter, stride))
        return Expansion{[M.FunctionExpr{specialized}], M.Function{specialized, False{}, parameter, parameter_type, result_type, expression} <> functions(expanded), emitted_constants(expanded), next(expanded)}
    case 1n+rest Expression{M.ApplyExpr{+callee, +argument}}:
      Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      expand(rest, Application{callee, argument, binary_call(unlocated(65536n, callee), argument, originals)}, configuration, stack, base, counter)
    case 1n+rest Application{callee, argument, Some{BinaryCall{member, effect_templates, left, right}}}:
      Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      do Result<&2, &2, M.Diagnostic, Expansion>:
        +expanded : Expansion <- expand(rest, Expressions{[left, right]}, configuration, stack, base, Nat.add(counter, step))
        expression : M.Expr <- rebuild(M.AssociatedExpr{Nat.mul(counter, stride), M.BinaryDispatch{}, member, effect_templates, M.UnitExpr{}, M.UnitExpr{}}, expressions(expanded), 0n)
        return Expansion{[expression], functions(expanded), emitted_constants(expanded), next(expanded)}
    case 1n+rest Application{+callee, +argument, None{}}:
      do Result<&2, &2, M.Diagnostic, Expansion>:
        +expanded : Expansion <- expand(rest, Expressions{[callee, argument]}, configuration, stack, base, counter)
        expression : M.Expr <- rebuild(M.ApplyExpr{callee, argument}, expressions(expanded), base)
        return Expansion{[expression], functions(expanded), emitted_constants(expanded), next(expanded)}
    case 1n+rest Expression{M.CallExpr{callee, argument}}:
      expand(rest, Expression{M.ApplyExpr{M.FunctionExpr{callee}, argument}}, configuration, stack, base, counter)
    case 1n+rest Expression{+expression}:
      do Result<&2, &2, M.Diagnostic, Expansion>:
        +expanded : Expansion <- expand(rest, Expressions{F.children(expression)}, configuration, stack, base, counter)
        rebuilt : M.Expr <- rebuild(expression, expressions(expanded), base)
        return Expansion{[rebuilt], functions(expanded), emitted_constants(expanded), next(expanded)}
    case 1n+rest Expressions{Nil{}}:
      Done{Expansion{Nil{}, Nil{}, Nil{}, counter}}
    case 1n+rest Expressions{head <> tail}:
      do Result<&2, &2, M.Diagnostic, Expansion>:
        +first : Expansion <- expand(rest, Expression{head}, configuration, stack, base, counter)
        +following : Expansion <- expand(rest, Expressions{tail}, configuration, stack, base, next(first))
        return Expansion{List.append(&2, M.Expr, expressions(first), expressions(following)), List.append(&2, M.Function, functions(first), functions(following)), List.append(&2, M.Constant, emitted_constants(first), emitted_constants(following)), next(following)}

type ExpandedModule is Data:
  ExpandedModule{module: M.Module, next: Nat, bindings: List<&2, I.Binding>, certificates: List<&2, Core.Certificate>}

def expand_root(root: Bool, template: Bool, function: M.Function, configuration: Configuration, counter: Nat) -> Result<&2, &2, M.Diagnostic, Expansion>:
  match root template function:
    case False{} True{} function:
      Done{Expansion{Nil{}, Nil{}, Nil{}, counter}}
    case False{} False{} function:
      Done{Expansion{Nil{}, [function], Nil{}, counter}}
    case True{} _ M.Function{+name, exported, parameter, p, r, body}:
      do Result<&2, &2, M.Diagnostic, Expansion>:
        +expanded : Expansion <- expand(65536n, Expression{body}, configuration, [Rename{name, name}], 0n, counter)
        expression : M.Expr <- one(expressions(expanded))
        return Expansion{Nil{}, M.Function{name, exported, parameter, p, r, expression} <> functions(expanded), emitted_constants(expanded), next(expanded)}

def expand_roots(pending: List<&2, M.Function>, +configuration: Configuration, counter: Nat) -> Result<&2, &2, M.Diagnostic, Expansion>:
  match pending:
    case Nil{}:
      Done{Expansion{Nil{}, Nil{}, Nil{}, counter}}
    case +function <> tail:
      M.Function{+name, +exported, parameter, p, r, body} = function
      Configuration{originals, +templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      do Result<&2, &2, M.Diagnostic, Expansion>:
        +current : Expansion <- expand_root(Bool.or(Bool.and(exported, D.contains(templates, name)), Bool.and(Bool.not(D.contains(templates, name)), D.contains(affected, name))), D.contains(templates, name), function, configuration, counter)
        +rest : Expansion <- expand_roots(tail, configuration, next(current))
        return Expansion{Nil{}, List.append(&2, M.Function, functions(current), functions(rest)), List.append(&2, M.Constant, emitted_constants(current), emitted_constants(rest)), next(rest)}

def prepend_constant(constant: M.Constant, expanded: ExpandedModule) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  ExpandedModule{M.Module{constants, functions, types, operations}, next, bindings, certificates} = expanded
  Done{ExpandedModule{M.Module{constant <> constants, functions, types, operations}, next, bindings, certificates}}

def expand_constants(constants: List<&2, M.Constant>, +configuration: Configuration, emitted: List<&2, M.Function>, captured: List<&2, M.Constant>, +types: List<&2, M.DataType>, +operations: List<&2, M.Operation>, counter: Nat) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  match constants:
    case Nil{}:
      Done{ExpandedModule{M.Module{captured, emitted, types, operations}, counter, Nil{}, Nil{}}}
    case M.Constant{name, exported, annotation, value} <> tail:
      do Result<&2, &2, M.Diagnostic, ExpandedModule>:
        +expanded : Expansion <- expand(65536n, Expression{value}, configuration, Nil{}, 0n, counter)
        expression : M.Expr <- one(expressions(expanded))
        rest : ExpandedModule <- expand_constants(tail, configuration, List.append(&2, M.Function, emitted, functions(expanded)), List.append(&2, M.Constant, captured, emitted_constants(expanded)), types, operations, next(expanded))
        prepend_constant(M.Constant{name, exported, annotation, expression}, rest)

def function_bindings(functions: List<&2, M.CheckedFunction>) -> List<&2, I.Binding>:
  match functions:
    case Nil{}:
      Nil{}
    case M.CheckedFunction{function, M.Signature{name, parameter, result, variables, row}, effects} <> tail:
      I.Binding{name, M.FunctionTy{parameter, result, row}, variables, Nil{}} <> function_bindings(tail)

def constant_bindings(constants: List<&2, M.CheckedConstant>) -> List<&2, I.Binding>:
  match constants:
    case Nil{}:
      Nil{}
    case M.CheckedConstant{M.Constant{name, exported, annotation, value}, ty, variables} <> tail:
      I.Binding{name, ty, variables, Nil{}} <> constant_bindings(tail)

def shape_bindings(checked: M.CheckedModule) -> G.Environment:
  M.CheckedModule{constants, functions, types, operations} = checked
  G.Environment{List.append(&2, I.Binding, function_bindings(functions), constant_bindings(constants)), Nil{}, I.State{T.empty(), 0n, MTip{}}}

def certificate_interfaces(certificates: List<&2, Core.Certificate>) -> List<&2, Groups.Interface>:
  match certificates:
    case Nil{}:
      Nil{}
    case Core.Certificate{module, checked, imports} <> tail:
      List.append(&2, Groups.Interface, Groups.checked_interfaces(checked), certificate_interfaces(tail))

def has_planned_predicates(plans: List<&2, C.UsePlan>) -> Bool:
  match plans:
    case Nil{}:
      False{}
    case C.UsePlan{site, subject, ty, Nil{}} <> tail:
      has_planned_predicates(tail)
    case C.UsePlan{site, subject, ty, predicates} <> tail:
      True{}

def certificate_plan_roots(certificates: List<&2, Core.Certificate>) -> List<&2, String>:
  match certificates:
    case Nil{}:
      Nil{}
    case Core.Certificate{module, checked, imports} <> tail:
      +rest = certificate_plan_roots(tail)
      Bool.pick(List<&2, String>, has_planned_predicates(Groups.checked_uses(checked)), List.append(&2, String, Core.names(module), rest), rest)

def without_interface_bindings(bindings: List<&2, I.Binding>, +names: List<&2, String>) -> List<&2, I.Binding>:
  match bindings:
    case Nil{}:
      Nil{}
    case I.Binding{+name, ty, variables, predicates} <> tail:
      +rest = without_interface_bindings(tail, names)
      Bool.pick(List<&2, I.Binding>, D.contains(names, name), rest, I.Binding{name, ty, variables, predicates} <> rest)

def shape_initial(initial: Scheduler.Initial, module: M.Module) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  Scheduler.Initial{checked, certificates, needs} = initial
  M.Module{constants, functions, types, operations} = module
  +interfaces = certificate_interfaces(certificates)
  +bare = G.env_bindings(shape_bindings(checked))
  do Result<&2, &2, M.Diagnostic, G.Environment>:
    +imported : G.Environment <- Groups.import_interfaces(interfaces, operations, types, 0n)
    return G.Environment{List.append(&2, I.Binding, G.env_bindings(imported), without_interface_bindings(bare, Groups.interface_names(interfaces))), G.env_definitions(imported), G.env_state(imported)}

def resolved_bindings(bindings: List<&2, I.Binding>, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
  match bindings:
    case Nil{}:
      Done{Nil{}}
    case I.Binding{name, ty, variables, predicates} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
        resolved : M.Ty <- T.resolve(substitutions, ty)
        requirements : List<&2, M.Predicate> <- C.resolve_list(substitutions, predicates)
        rest : List<&2, I.Binding> <- resolved_bindings(tail, substitutions)
        return I.Binding{name, resolved, variables, requirements} <> rest

def ordinary_bindings_indexed(bindings: List<&2, I.Binding>, +templates: Set()) -> List<&2, I.Binding>:
  match bindings:
    case Nil{}:
      Nil{}
    case I.Binding{+name, ty, variables, predicates} <> tail:
      +rest = ordinary_bindings_indexed(tail, templates)
      Bool.pick(List<&2, I.Binding>, Bool.not(D.member(templates, name)), I.Binding{name, ty, variables, predicates} <> rest, rest)

def ordinary_bindings(bindings: List<&2, I.Binding>, templates: List<&2, String>) -> List<&2, I.Binding>:
  ordinary_bindings_indexed(bindings, G.reference_set(templates, Set.new()))

def pending_functions(functions: List<&2, M.Function>, +ordinary: List<&2, I.Binding>) -> List<&2, M.Function>:
  match functions:
    case Nil{}:
      Nil{}
    case M.Function{+name, exported, parameter, p, r, body} <> tail:
      +rest = pending_functions(tail, ordinary)
      Bool.pick(List<&2, M.Function>, Maybe.is_some(&2, I.Binding, I.lookup_binding(ordinary, name)), rest, M.Function{name, exported, parameter, p, r, body} <> rest)

def pending_constants(constants: List<&2, M.Constant>, +ordinary: List<&2, I.Binding>) -> List<&2, M.Constant>:
  match constants:
    case Nil{}:
      Nil{}
    case M.Constant{+name, exported, annotation, value} <> tail:
      +rest = pending_constants(tail, ordinary)
      Bool.pick(List<&2, M.Constant>, Maybe.is_some(&2, I.Binding, I.lookup_binding(ordinary, name)), rest, M.Constant{name, exported, annotation, value} <> rest)

def clone_origin(name: String) -> String:
  match name:
    case SCon{Chr{93}, SCon{Chr{46}, tail}}:
      tail
    case SCon{character, tail}:
      clone_origin(tail)
    case SNil{}:
      SNil{}

def original_name(+name: String) -> String:
  Bool.pick(String, String.starts_with(name, "$mono["), clone_origin(name), name)

def shape_limit(bindings: List<&2, I.Binding>, next: Nat) -> Result<&2, &2, M.Diagnostic, Nat>:
  match bindings:
    case Nil{}:
      Done{next}
    case I.Binding{name, ty, variables, predicates} <> tail:
      do Result<&2, &2, M.Diagnostic, Nat>:
        free : List<&2, Nat> <- T.free(ty)
        requirement_free : List<&2, Nat> <- C.free_list(predicates)
        shape_limit(tail, T.above(T.union(free, requirement_free), next))

def seed_bindings(bindings: List<&2, I.Binding>, +shapes: List<&2, I.Binding>, state: I.State) -> Result<&2, &2, M.Diagnostic, I.State>:
  match bindings:
    case Nil{}:
      Done{state}
    case I.Binding{+name, ty, variables, predicates} <> tail:
      do Result<&2, &2, M.Diagnostic, I.State>:
        +shape : I.Typing <- I.instantiate_binding(I.lookup_binding(shapes, original_name(name)), state, name, name)
        next : I.State <- I.unify(ty, I.type_of(shape), I.state_of(shape), name)
        seed_bindings(tail, shapes, next)

def infer_pending(+declarations: List<&2, G.Declaration>, shapes: List<&2, I.Binding>, environment: G.Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, +names: List<&2, String>) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  G.Environment{bindings, definitions, +state} = environment
  +start = I.next_of(state)
  +created = G.initial_bindings(declarations, start)
  do Result<&2, &2, M.Diagnostic, G.Environment>:
    seeded : I.State <- seed_bindings(created, shapes, I.with_next(state, G.initial_next(declarations, start)))
    ParallelInfer.infer_component(declarations, G.Environment{List.append(&2, I.Binding, created, bindings), definitions, seeded}, operations, types, names)

# Compare the entire emitted clone against the expansion of the independently
# checked source. A body edit, annotation, source offset, or nominal identity
# mismatch leaves the ordinary inference path in charge of diagnostics.
def staged_clone(expanded: Result<&2, &2, M.Diagnostic, Expansion>, clone: M.Function) -> Bool:
  match expanded:
    case Done{Expansion{expressions, expected <> Nil{}, Nil{}, next}}:
      Compare.compare(1048576n, [Compare.FunctionPair{expected, clone}], True{})
    case _:
      False{}

def exact_staged_clone(+candidate: Staging.Candidate, clone: M.Function, stride: Nat) -> Bool:
  +source = Staging.candidate_source(candidate)
  +name = Staging.source_name(source)
  +configuration = {Configuration{[source], [name], "", Nil{}, Nil{}, stride, Nil{}, Nil{}, 1n, Nil{}} : Configuration}
  staged_clone(expand(65536n, Clone{source}, configuration, Nil{}, 0n, Staging.candidate_counter(candidate)), clone)

def staged_candidate(found: Maybe<&2, Staging.Candidate>, +function: M.Function, +stride: Nat, environment: G.Environment, types: List<&2, M.DataType>) -> Maybe<&2, G.Environment>:
  match found:
    case None{}:
      None{}
    case Some{+candidate}:
      Staging.replay(candidate, function, stride, environment, types, exact_staged_clone(candidate, function, stride))

def staged_or_infer(found: Maybe<&2, G.Environment>, declaration: G.Declaration, environment: G.Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, functions: List<&2, String>, index: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match found:
    case Some{value}:
      Done{value}
    case None{}:
      G.infer_declaration_prepared(declaration, environment, operations, types, functions, index)

# A potential replay is a source-order barrier. Ordinary contiguous runs can
# use the parallel inference guard; a failed replay falls back at its original
# position. Duplicate pending names use Globals' first-match lookup semantics.
type StagedSplit is Data:
  StagedSplit{ordinary: List<&2, G.Declaration>, barrier: Maybe<&2, G.Declaration>, remaining: List<&2, G.Declaration>}

def has_staged_candidate(declaration: G.Declaration, schemes: List<&2, Staging.Scheme>) -> Bool:
  match declaration:
    case G.FunctionDeclaration{function}:
      Maybe.is_some(&2, Staging.Candidate, Staging.candidate(function, schemes))
    case G.ConstantDeclaration{constant}:
      False{}

def split_staged_if(remaining: List<&2, G.Declaration>, candidate: Bool, +head: G.Declaration, +reversed: List<&2, G.Declaration>, +schemes: List<&2, Staging.Scheme>) -> StagedSplit:
  match remaining candidate:
    case rest True{}:
      StagedSplit{List.reverse(&2, G.Declaration, reversed), Some{head}, rest}
    case Nil{} False{}:
      StagedSplit{List.reverse(&2, G.Declaration, head <> reversed), None{}, Nil{}}
    case +next <> rest False{}:
      split_staged_if(rest, has_staged_candidate(next, schemes), next, head <> reversed, schemes)

def split_staged(remaining: List<&2, G.Declaration>, +reversed: List<&2, G.Declaration>, +schemes: List<&2, Staging.Scheme>) -> StagedSplit:
  match remaining:
    case Nil{}:
      StagedSplit{List.reverse(&2, G.Declaration, reversed), None{}, Nil{}}
    case +head <> tail:
      split_staged_if(tail, has_staged_candidate(head, schemes), head, reversed, schemes)

def infer_staged_barrier(+declaration: G.Declaration, +environment: G.Environment, operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, functions: List<&2, String>, schemes: List<&2, Staging.Scheme>, stride: Nat, index: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match declaration:
    case G.FunctionDeclaration{+function}:
      staged_or_infer(staged_candidate(Staging.candidate(function, schemes), function, stride, environment, types), declaration, environment, operations, types, functions, index)
    case G.ConstantDeclaration{constant}:
      G.infer_declaration_prepared(declaration, environment, operations, types, functions, index)

type StagedWork is Data:
  StageDeclarations{declarations: List<&2, G.Declaration>, environment: G.Environment}
  StageSplit{split: StagedSplit, environment: G.Environment}
  StageBarrier{barrier: Maybe<&2, G.Declaration>, remaining: List<&2, G.Declaration>, environment: G.Environment}

def infer_staged_work(fuel: Nat, work: StagedWork, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, +functions: List<&2, String>, +schemes: List<&2, Staging.Scheme>, +stride: Nat, +all_pending: List<&2, String>, +index: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>, +catalog_closed: Bool) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"internal_error", "staging", "staged inference traversal limit"}}
    case 1n+rest StageDeclarations{declarations, environment}:
      infer_staged_work(rest, StageSplit{split_staged(declarations, Nil{}, schemes), environment}, operations, types, functions, schemes, stride, all_pending, index, catalog_closed)
    case 1n+rest StageSplit{StagedSplit{ordinary, barrier, remaining}, environment}:
      do Result<&2, &2, M.Diagnostic, G.Environment>:
        next : G.Environment <- ParallelInfer.infer_segment_prechecked(ordinary, all_pending, environment, operations, types, functions, index, catalog_closed)
        infer_staged_work(rest, StageBarrier{barrier, remaining, next}, operations, types, functions, schemes, stride, all_pending, index, catalog_closed)
    case 1n+rest StageBarrier{None{}, remaining, environment}:
      Done{environment}
    case 1n+rest StageBarrier{Some{declaration}, remaining, environment}:
      do Result<&2, &2, M.Diagnostic, G.Environment>:
        next : G.Environment <- infer_staged_barrier(declaration, environment, operations, types, functions, schemes, stride, index)
        infer_staged_work(rest, StageDeclarations{remaining, next}, operations, types, functions, schemes, stride, all_pending, index, catalog_closed)

def staged_catalog_closed(declarations: List<&2, G.Declaration>, operations: List<&2, M.Operation>, types: List<&2, M.DataType>) -> Bool:
  match declarations:
    case Nil{}: False{}
    case [single]: False{}
    case a <> b <> rest: ParallelInfer.catalog_closed(operations, types)

def infer_staged_unique(unique: Bool, +declarations: List<&2, G.Declaration>, +pending: List<&2, String>, +environment: G.Environment, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, +functions: List<&2, String>, schemes: List<&2, Staging.Scheme>, stride: Nat, index: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match unique:
    case False{}:
      G.infer_component(pending, declarations, environment, operations, types, functions)
    case True{}:
      infer_staged_work(3n+Nat.mul(3n, List.length(&2, G.Declaration, declarations)), StageDeclarations{declarations, environment}, operations, types, functions, schemes, stride, pending, index, staged_catalog_closed(declarations, operations, types))

def infer_pending_staged(+declarations: List<&2, G.Declaration>, shapes: List<&2, I.Binding>, environment: G.Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, names: List<&2, String>, schemes: List<&2, Staging.Scheme>, stride: Nat) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  G.Environment{bindings, definitions, +state} = environment
  +start = I.next_of(state)
  +created = G.initial_bindings(declarations, start)
  do Result<&2, &2, M.Diagnostic, G.Environment>:
    seeded : I.State <- seed_bindings(created, shapes, I.with_next(state, G.initial_next(declarations, start)))
    +prepared_environment : G.Environment = G.Environment{List.append(&2, I.Binding, created, bindings), definitions, seeded}
    +pending : List<&2, String> = G.names(declarations)
    infer_staged_unique(ParallelInfer.unique_names(pending, Set.new()), declarations, pending, prepared_environment, operations, types, names, schemes, stride, G.component_bindings(pending, G.env_bindings(prepared_environment)))

def infer_pending_optional(+declarations: List<&2, G.Declaration>, shapes: List<&2, I.Binding>, environment: G.Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, names: List<&2, String>, schemes: List<&2, Staging.Scheme>, stride: Nat) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match schemes:
    case Nil{}:
      infer_pending(declarations, shapes, environment, operations, types, names)
    case head <> tail:
      infer_pending_staged(declarations, shapes, environment, operations, types, names, head <> tail, stride)

def nominal_prefix(identity: M.TypeId, +entry: String) -> String:
  M.TypeId{+module_name, declaration} = identity
  Bool.pick(String, M.name_equal(module_name, "std/prelude"), "$prelude.", Bool.pick(String, M.name_equal(module_name, entry), "", "$module[" ++ module_name ++ "].")) ++ declaration

def owner(ty: M.Ty, entry: String) -> Maybe<&2, String>:
  match ty:
    case M.U32Ty{}:
      Some{"$prelude.U32"}
    case M.F32Ty{}:
      Some{"$prelude.F32"}
    case M.BoolTy{}:
      Some{"$prelude.Bool"}
    case M.UnitTy{}:
      Some{"$prelude.Unit"}
    case M.AppliedTy{identity, arguments}:
      Some{nominal_prefix(identity, entry)}
    case M.ArrayTy{element}:
      Some{"$prelude.Array"}
    case M.VariableTy{index}:
      None{}
    case M.ParameterTy{index}:
      None{}
    case _:
      Some{""}

def member_name(owner: Maybe<&2, String>, member: String) -> Maybe<&2, String>:
  match owner:
    case None{}:
      None{}
    case Some{prefix}:
      Some{prefix ++ "." ++ member}

# An implementation is a candidate when it accepts both operands in order.
def candidate_binding(found: Maybe<&2, I.Binding>, name: String, left: M.Ty, right: M.Ty, state: I.State, +subject: String) -> Result<&2, &2, M.Diagnostic, I.Typing>:
  do Result<&2, &2, M.Diagnostic, I.Typing>:
    +fn : I.Typing <- I.instantiate_binding(found, state, name, subject)
    +next : Nat = I.next_of(I.state_of(fn))
    s1 : I.State <- I.unify(I.type_of(fn), M.FunctionTy{left, M.FunctionTy{right, M.VariableTy{next}, M.EffectRow{Nil{}, M.RowVariable{1n+next}}}, M.EffectRow{Nil{}, M.RowVariable{2n+next}}}, I.with_next(I.state_of(fn), 3n+next), subject)
    return I.Typing{I.pure(M.VariableTy{next}), s1}

def candidate(name: Maybe<&2, String>, +bindings: List<&2, I.Binding>, left: M.Ty, right: M.Ty, state: I.State, +subject: String) -> Result<&2, &2, M.Diagnostic, I.Typing>:
  match name:
    case None{}:
      Fail{M.Diagnostic{"unknown_associated_type", subject, "operand type is not yet known"}}
    case Some{+name}:
      candidate_binding(I.lookup_binding(bindings, name), name, left, right, state, subject)

def candidate_error(candidate: Result<&2, &2, M.Diagnostic, I.Typing>) -> String:
  match candidate:
    case Done{value}:
      "no named implementation"
    case Fail{M.Diagnostic{code, subject, message}}:
      message

def choose_right(right: Result<&2, &2, M.Diagnostic, I.Typing>, name: Maybe<&2, String>, subject: String, description: String) -> Result<&2, &2, M.Diagnostic, String>:
  match right name:
    case Done{value} Some{name}:
      Done{name}
    case other _:
      Fail{M.Diagnostic{"missing_associated", subject, description ++ "; right: " ++ candidate_error(other)}}

def chosen(left: Result<&2, &2, M.Diagnostic, I.Typing>, left_name: Maybe<&2, String>, right: Result<&2, &2, M.Diagnostic, I.Typing>, right_name: Maybe<&2, String>, subject: String, description: String) -> Result<&2, &2, M.Diagnostic, String>:
  match left left_name:
    case Done{value} Some{name}:
      Done{name}
    case other _:
      choose_right(right, right_name, subject, description ++ "; left: " ++ candidate_error(other))

type Choice is Data:
  FunctionChoice{name: String, signature: M.Ty}
  ReceiverChoice{name: String, signature: M.Ty}
  OperationChoice{identity: M.TypeId, signature: M.Ty}
  QualifiedChoice{solved: List<&2, M.Predicate>, answers: List<&2, C.EvidenceAnswer>}

type Specialization is Data:
  Specialization{module: M.Module, environment: G.Environment, choices: Map<&2, Choice>, next: Nat, certificates: List<&2, Core.Certificate>}

def choice(choices: Map<&2, Choice>, wanted: Nat) -> Maybe<&2, Choice>:
  Index.find(Choice, choices, Nat.show(wanted))

def qualified_key(site: Nat) -> String:
  "q" ++ Nat.show(site)

def qualified_choice(choices: Map<&2, Choice>, site: Nat) -> Maybe<&2, Choice>:
  Index.find(Choice, choices, qualified_key(site))

def solved_predicates(found: Maybe<&2, Choice>) -> List<&2, M.Predicate>:
  match found:
    case Some{QualifiedChoice{solved, answers}}:
      solved
    case _:
      Nil{}

def qualified_solved_work(solved: List<&2, M.Predicate>, +wanted: M.Predicate) -> Bool:
  match solved:
    case Nil{}:
      False{}
    case head <> tail:
      Bool.or(C.same_predicate(head, wanted), qualified_solved_work(tail, wanted))

def qualified_solved(choices: Map<&2, Choice>, site: Nat, predicate: M.Predicate) -> Bool:
  qualified_solved_work(solved_predicates(qualified_choice(choices, site)), predicate)

def qualified_answers(found: Maybe<&2, Choice>) -> List<&2, C.EvidenceAnswer>:
  match found:
    case Some{QualifiedChoice{solved, answers}}:
      answers
    case _:
      Nil{}

def remember_answer(previous: Specialization, selected: Specialization, +site: Nat, original: M.Predicate, answer: C.EvidenceAnswer) -> Specialization:
  Specialization{original_module, original_environment, +choices, original_next, original_certificates} = previous
  Specialization{module, environment, selected_choices, next, certificates} = selected
  +solved = solved_predicates(qualified_choice(choices, site))
  +answers = qualified_answers(qualified_choice(choices, site))
  # Every selector records exactly one temporary numeric choice. Expansion and
  # generated-body inference add definitions, not further choices. Start from
  # the previous map so a numeric site collision cannot overwrite an ordinary
  # dispatch choice; keep the qualified answer in its own key namespace.
  Specialization{module, environment, Map.set(&2, Choice, choices, qualified_key(site), QualifiedChoice{original <> solved, answer <> answers}), next, certificates}

def field_owner(receiver: M.Ty, member: String, accessor: String, signature: M.Ty) -> Result<&2, &2, M.Diagnostic, C.Evidence>:
  match receiver:
    case M.AppliedTy{identity, arguments}:
      Done{C.SelectedField{identity, member, accessor, signature}}
    case _:
      Fail{M.Diagnostic{"internal_error", member, "selected field has no nominal owner"}}

def receiver_evidence(field: Bool, receiver: M.Ty, member: String, name: String, signature: M.Ty) -> Result<&2, &2, M.Diagnostic, C.Evidence>:
  match field:
    case True{}:
      field_owner(receiver, member, name, signature)
    case False{}:
      Done{C.SelectedFunction{name, signature}}

def qualified_evidence(predicate: M.Predicate, found: Maybe<&2, Choice>, types: List<&2, M.DataType>) -> Result<&2, &2, M.Diagnostic, C.Evidence>:
  match predicate found:
    case M.FieldPredicate{member, receiver, result} Some{ReceiverChoice{name, signature}}:
      field_owner(receiver, member, name, signature)
    case M.UpdatePredicate{member, receiver, assigned, result, invocation} Some{FunctionChoice{name, signature}}:
      field_owner(receiver, member, name, signature)
    case M.OperationPredicate{template, arguments, function_type} Some{OperationChoice{identity, signature}}:
      Done{C.SelectedOperation{identity, signature}}
    case M.AssociatedPredicate{member, templates, left, right, result, invocation} Some{FunctionChoice{name, signature}}:
      Done{C.SelectedFunction{name, signature}}
    case M.ReceiverPredicate{+member, templates, +receiver, argument, result, invocation} Some{ReceiverChoice{name, signature}}:
      receiver_evidence(Members.has_field(Members.constructors(receiver, types), member), receiver, member, name, signature)
    case _ _:
      Fail{M.Diagnostic{"internal_error", "monomorphization", "qualified selection did not produce matching evidence"}}

def evidence_signature(evidence: C.Evidence) -> Maybe<&2, M.Ty>:
  match evidence:
    case C.SelectedFunction{name, signature}:
      Some{signature}
    case C.SelectedField{owner, member, accessor, signature}:
      Some{signature}
    case C.SelectedOperation{identity, signature}:
      Some{signature}
    case _:
      None{}

def require_closed_evidence(free: List<&2, Nat>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match free:
    case Nil{}:
      Done{Unit{}}
    case head <> tail:
      Fail{M.Diagnostic{"ambiguous_qualified", subject, "selected evidence still has unconstrained type or effect variables"}}

def validate_evidence_found(found: Maybe<&2, M.Ty>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match found:
    case None{}:
      Done{Unit{}}
    case Some{signature}:
      do Result<&2, &2, M.Diagnostic, Unit>:
        free : List<&2, Nat> <- T.free(signature)
        require_closed_evidence(free, subject)

def validate_evidence(evidence: C.Evidence, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  validate_evidence_found(evidence_signature(evidence), subject)

def selected_qualified_answer(selected: Specialization, site: Nat, predicate: M.Predicate) -> Result<&2, &2, M.Diagnostic, C.EvidenceAnswer>:
  Specialization{M.Module{constants, functions, types, operations}, environment, choices, next, certificates} = selected
  do Result<&2, &2, M.Diagnostic, C.EvidenceAnswer>:
    +resolved : M.Predicate <- C.resolve(I.substitutions_of(G.env_state(environment)), predicate)
    evidence : C.Evidence <- qualified_evidence(resolved, choice(choices, site), types)
    return C.EvidenceAnswer{resolved, evidence}

def identity_at_subject(found: Result<&2, &2, M.Diagnostic, String>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match found:
    case Done{key}:
      Done{Unit{}}
    case Fail{M.Diagnostic{code, old_subject, message}}:
      Fail{M.Diagnostic{code, subject, message}}

def direct_qualified_answer(+predicate: M.Predicate, subject: String) -> Result<&2, &2, M.Diagnostic, C.EvidenceAnswer>:
  match predicate:
    case M.TypeRepPredicate{+represented}:
      do Result<&2, &2, M.Diagnostic, C.EvidenceAnswer>:
        valid : Unit <- identity_at_subject(State.type_key(65536n, State.TypeKey{represented}), subject)
        return C.EvidenceAnswer{predicate, C.RepresentedType{represented}}
    case M.EffectRepPredicate{+row}:
      do Result<&2, &2, M.Diagnostic, C.EvidenceAnswer>:
        valid : Unit <- identity_at_subject(State.row_key(row), subject)
        return C.EvidenceAnswer{predicate, C.RepresentedEffect{Rows.canonical(row)}}
    case _:
      Fail{M.Diagnostic{"internal_error", "monomorphization", "expected a representation predicate"}}

def selected_qualified(previous: Specialization, +selected: Specialization, +site: Nat, +original: M.Predicate) -> Result<&2, &2, M.Diagnostic, Specialization>:
  do Result<&2, &2, M.Diagnostic, Specialization>:
    answer : C.EvidenceAnswer <- selected_qualified_answer(selected, site, original)
    return remember_answer(previous, selected, site, original, answer)

def requirements_reversed(constraints: List<&2, I.Coverage>, reversed: List<&2, I.Coverage>) -> List<&2, I.Coverage>:
  match constraints:
    case Nil{}:
      List.reverse(&2, I.Coverage, reversed)
    case I.OperationNeed{identity, template, arguments, function_type, subject} <> tail:
      requirements_reversed(tail, I.OperationNeed{identity, template, arguments, function_type, subject} <> reversed)
    case I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, subject} <> tail:
      requirements_reversed(tail, I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, subject} <> reversed)
    case I.QualifiedNeed{site, predicate, subject} <> tail:
      requirements_reversed(tail, I.QualifiedNeed{site, predicate, subject} <> reversed)
    case head <> tail:
      requirements_reversed(tail, reversed)

def requirements(constraints: List<&2, I.Coverage>) -> List<&2, I.Coverage>:
  requirements_reversed(constraints, Nil{})

def definition_uses(definitions: List<&2, I.Definition>) -> List<&2, C.UsePlan>:
  match definitions:
    case Nil{}:
      Nil{}
    case I.Definition{name, inference} <> tail:
      List.append(&2, C.UsePlan, I.inference_uses(inference), definition_uses(tail))

def pending(+environment: G.Environment) -> List<&2, I.Coverage>:
  requirements(List.append(&2, I.Coverage, Check.coverage_constraints(G.env_definitions(environment)), I.execution_needs(definition_uses(G.env_definitions(environment)))))

def reference_name(expression: M.Expr) -> Result<&2, &2, M.Diagnostic, String>:
  match expression:
    case M.FunctionExpr{name}:
      Done{name}
    case _:
      Fail{M.Diagnostic{"internal_error", "monomorphization", "specialized reference is not a function"}}

def select_associated(need: I.Coverage, +left: M.Ty, +right: M.Ty, specialization: Specialization, +configuration: Configuration, +shapes: List<&2, I.Binding>, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match need specialization:
    case I.AssociatedNeed{+identity, +dispatch, +member, +effect_templates, old_left, old_right, result, invocation, +ambient, +subject} Specialization{M.Module{+constants, +original_functions, +types, +operations}, +environment, choices, counter, certificates}:
      Configuration{+originals, templates, +entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      +state = G.env_state(environment)
      +left_name = member_name(owner(left, entry), member)
      +right_name = member_name(owner(right, entry), member)
      do Result<&2, &2, M.Diagnostic, Specialization>:
        selected : String <- chosen(candidate(left_name, shapes, left, right, state, subject), left_name, candidate(right_name, shapes, left, right, state, subject), right_name, subject, "no compatible " ++ member ++ " for " ++ M.type_show(left) ++ " and " ++ M.type_show(right))
        +expanded : Expansion <- expand(65536n, Expression{M.FunctionExpr{selected}}, configuration, Nil{}, 0n, counter)
        reference : M.Expr <- one(expressions(expanded))
        +name : String <- reference_name(reference)
        +all_functions : List<&2, M.Function> = List.append(&2, M.Function, original_functions, functions(expanded))
        +inferred : G.Environment <- infer_pending_optional(List.append(&2, G.Declaration, G.function_declarations(functions(expanded)), G.constant_declarations(emitted_constants(expanded))), shapes, environment, operations, types, G.function_names(G.function_declarations(List.append(&2, M.Function, originals, all_functions))), schemes, stride)
        +selected_instance : I.SelectedInstantiation <- I.instantiate_binding_selected(I.lookup_binding(G.env_bindings(inferred), name), G.env_state(inferred), name, subject)
        +target : I.Typing = I.selected_typing(selected_instance)
        +unified : I.State <- I.unify(I.type_of(target), M.FunctionTy{left, M.FunctionTy{right, result, ambient}, ambient}, I.state_of(target), subject)
        signature : M.Ty <- T.resolve(I.substitutions_of(unified), I.selected_exact(selected_instance))
        return Specialization{M.Module{List.append(&2, M.Constant, constants, emitted_constants(expanded)), all_functions, types, operations}, G.Environment{G.env_bindings(inferred), G.env_definitions(inferred), unified}, Map.set(&2, Choice, choices, Nat.show(identity), FunctionChoice{name, signature}), next(expanded), certificates}
    case _ _:
      Fail{M.Diagnostic{"internal_error", "monomorphization", "selection expected an associated requirement"}}

def required_method(found: Maybe<&2, I.Binding>, name: String, subject: String) -> Result<&2, &2, M.Diagnostic, String>:
  match found:
    case Some{binding}:
      Done{name}
    case None{}:
      Fail{M.Diagnostic{"missing_member", subject, "no associated member " ++ name}}

def receiver_method_name(name: Maybe<&2, String>, bindings: List<&2, I.Binding>, subject: String) -> Result<&2, &2, M.Diagnostic, String>:
  match name:
    case None{}:
      Fail{M.Diagnostic{"ambiguous_associated", subject, "member access requires an inferred receiver type"}}
    case Some{+name}:
      required_method(I.lookup_binding(bindings, name), name, subject)

def receiver_method(owner: Maybe<&2, String>, member: String, bindings: List<&2, I.Binding>, subject: String) -> Result<&2, &2, M.Diagnostic, String>:
  receiver_method_name(member_name(owner, member), bindings, subject)

def receiver_signature(dispatch: M.Dispatch, left: M.Ty, right: M.Ty, result: M.Ty, +ambient: M.EffectRow) -> M.Ty:
  match dispatch:
    case M.MemberDispatch{}:
      M.FunctionTy{left, result, ambient}
    case _:
      M.FunctionTy{left, M.FunctionTy{right, result, ambient}, ambient}

def receiver_choice(dispatch: M.Dispatch, name: String, signature: M.Ty) -> Choice:
  match dispatch:
    case M.MemberDispatch{}:
      ReceiverChoice{name, signature}
    case _:
      FunctionChoice{name, signature}

def infer_generated(+function: M.Function, environment: G.Environment, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, +names: List<&2, String>) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  G.Environment{bindings, definitions, +state} = environment
  +declarations = G.function_declarations([function])
  +start = I.next_of(state)
  +created = G.initial_bindings(declarations, start)
  do Result<&2, &2, M.Diagnostic, G.Environment>:
    inferred : G.Environment <- G.infer_component(G.names(declarations), declarations, G.Environment{List.append(&2, I.Binding, created, bindings), definitions, I.with_next(state, G.initial_next(declarations, start))}, operations, types, names)
    nodes : List<&2, D.Node> <- D.function_nodes([function])
    G.generalize_component(inferred, G.names(declarations), operations, types, nodes)

def select_method_original(need: I.Coverage, +left: M.Ty, right: M.Ty, specialization: Specialization, +configuration: Configuration, +shapes: List<&2, I.Binding>, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match need specialization:
    case I.AssociatedNeed{identity, +dispatch, member, templates, old_left, old_right, result, invocation, ambient, +subject} Specialization{M.Module{constants, +original_functions, +types, +operations}, environment, choices, counter, certificates}:
      Configuration{+originals, templates, +entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      do Result<&2, &2, M.Diagnostic, Specialization>:
        selected : String <- receiver_method(owner(left, entry), member, shapes, subject)
        +expanded : Expansion <- expand(65536n, Expression{M.FunctionExpr{selected}}, configuration, Nil{}, 0n, counter)
        reference : M.Expr <- one(expressions(expanded))
        +name : String <- reference_name(reference)
        +all_functions : List<&2, M.Function> = List.append(&2, M.Function, original_functions, functions(expanded))
        +inferred : G.Environment <- infer_pending_optional(List.append(&2, G.Declaration, G.function_declarations(functions(expanded)), G.constant_declarations(emitted_constants(expanded))), shapes, environment, operations, types, G.function_names(G.function_declarations(List.append(&2, M.Function, originals, all_functions))), schemes, stride)
        +selected_instance : I.SelectedInstantiation <- I.instantiate_binding_selected(I.lookup_binding(G.env_bindings(inferred), name), G.env_state(inferred), name, subject)
        +target : I.Typing = I.selected_typing(selected_instance)
        +unified : I.State <- I.unify(I.type_of(target), receiver_signature(dispatch, left, right, result, ambient), I.state_of(target), subject)
        signature : M.Ty <- T.resolve(I.substitutions_of(unified), I.selected_exact(selected_instance))
        return Specialization{M.Module{List.append(&2, M.Constant, constants, emitted_constants(expanded)), all_functions, types, operations}, G.Environment{G.env_bindings(inferred), G.env_definitions(inferred), unified}, Map.set(&2, Choice, choices, Nat.show(identity), receiver_choice(dispatch, name, signature)), next(expanded), certificates}
    case _ _:
      Fail{M.Diagnostic{"internal_error", "member", "selection expected a receiver requirement"}}

# Source evidence is captured after the independent source check. This
# shortcut is entered only from select_receiver_found, after its ordinary
# field/method ambiguity check. Any uncertain condition returns None before
# changing the specialization; select_method_original then owns diagnostics.
def schema_proofs(configuration: Configuration) -> List<&2, Schema.Evidence>:
  Configuration{functions, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
  schema

def schema_answer_type(found: Result<&2, &2, M.Diagnostic, M.Ty>, proofs: List<&2, Schema.Evidence>, selected: String, member: String, left: M.Ty, functions: List<&2, M.Function>, types: List<&2, M.DataType>) -> Maybe<&2, Bool>:
  match found:
    case Fail{diagnostic}:
      None{}
    case Done{resolved}:
      Schema.decide(proofs, selected, member, left, resolved, functions, types)

def schema_answer_method(found: Result<&2, &2, M.Diagnostic, String>, proofs: List<&2, Schema.Evidence>, member: String, left: M.Ty, result: M.Ty, environment: G.Environment, functions: List<&2, M.Function>, types: List<&2, M.DataType>) -> Maybe<&2, Bool>:
  match found:
    case Fail{diagnostic}:
      None{}
    case Done{selected}:
      schema_answer_type(T.resolve(I.substitutions_of(G.env_state(environment)), result), proofs, selected, member, left, functions, types)

def schema_answer_ready(eligible: Bool, proofs: List<&2, Schema.Evidence>, +member: String, +left: M.Ty, result: M.Ty, specialization: Specialization, configuration: Configuration, shapes: List<&2, I.Binding>, subject: String) -> Maybe<&2, Bool>:
  match eligible:
    case False{}:
      None{}
    case True{}:
      Specialization{M.Module{constants, functions, +types, operations}, environment, choices, counter, certificates} = specialization
      Configuration{+originals, templates, +entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      schema_answer_method(receiver_method(owner(left, entry), member, shapes, subject), proofs, member, left, result, environment, originals, types)

def schema_answer(+proofs: List<&2, Schema.Evidence>, +member: String, +left: M.Ty, result: M.Ty, specialization: Specialization, configuration: Configuration, shapes: List<&2, I.Binding>, subject: String) -> Maybe<&2, Bool>:
  schema_answer_ready(Schema.eligible(proofs, member, left), proofs, member, left, result, specialization, configuration, shapes, subject)

def schema_space_counter(within: Bool, +counter: Nat, stride: Nat, step: Nat) -> Bool:
  match within:
    case False{}:
      False{}
    case True{}:
      Bool.and(Nat.is_le(counter, Nat.div(Staging.max_nat48(), stride)), Nat.is_le(step, Nat.sub(Staging.max_nat48(), counter)))

def schema_space(+counter: Nat, +stride: Nat, step: Nat) -> Bool:
  match stride:
    case 0n:
      False{}
    case 1n+remaining:
      schema_space_counter(Nat.is_le(counter, Staging.max_nat48()), counter, stride, step)

def schema_fresh_space(environment: G.Environment) -> Bool:
  # The one-body helper allocates only a few fresh inference IDs. Reserve a
  # full block so optional inference cannot overflow before old-path fallback.
  Nat.is_le(I.next_of(G.env_state(environment)), Nat.sub(Staging.max_nat48(), 65536n))

def schema_outcome(value: Result<&2, &2, M.Diagnostic, Specialization>) -> Maybe<&2, Specialization>:
  match value:
    case Done{selected}:
      Some{selected}
    case Fail{diagnostic}:
      None{}

def schema_name_free(found: Result<&2, &2, M.Diagnostic, M.Function>) -> Bool:
  match found:
    case Fail{diagnostic}:
      True{}
    case Done{function}:
      False{}

def schema_generated(+name: String, answer: Bool, identity: Nat, +dispatch: M.Dispatch, member: String, left: M.Ty, right: M.Ty, result: M.Ty, ambient: M.EffectRow, +subject: String, specialization: Specialization, configuration: Configuration) -> Result<&2, &2, M.Diagnostic, Specialization>:
  Specialization{M.Module{constants, +functions, +types, +operations}, environment, +choices, +counter, certificates} = specialization
  Configuration{+originals, templates, entry, locals, affected, +stride, constant_values, family_templates, +step, schema} = configuration
  +generated : M.Function = M.Function{name, False{}, "$schema.receiver", None{}, None{}, M.LambdaExpr{Nat.mul(counter, stride), "$schema.witness", None{}, None{}, M.BoolExpr{answer}}}
  +all_functions : List<&2, M.Function> = List.append(&2, M.Function, functions, [generated])
  do Result<&2, &2, M.Diagnostic, Specialization>:
    +inferred : G.Environment <- infer_generated(generated, environment, operations, types, G.function_names(G.function_declarations(List.append(&2, M.Function, originals, all_functions))))
    +selected_instance : I.SelectedInstantiation <- I.instantiate_binding_selected(I.lookup_binding(G.env_bindings(inferred), name), G.env_state(inferred), name, subject)
    +target : I.Typing = I.selected_typing(selected_instance)
    +unified : I.State <- I.unify(I.type_of(target), receiver_signature(dispatch, left, right, result, ambient), I.state_of(target), subject)
    signature : M.Ty <- T.resolve(I.substitutions_of(unified), I.selected_exact(selected_instance))
    return Specialization{M.Module{constants, all_functions, types, operations}, G.Environment{G.env_bindings(inferred), G.env_definitions(inferred), unified}, Map.set(&2, Choice, choices, Nat.show(identity), receiver_choice(dispatch, name, signature)), Nat.add(counter, step), certificates}

def schema_choice_space(fits: Bool, +name: String, answer: Bool, identity: Nat, dispatch: M.Dispatch, member: String, left: M.Ty, right: M.Ty, result: M.Ty, ambient: M.EffectRow, subject: String, specialization: Specialization, configuration: Configuration) -> Maybe<&2, Specialization>:
  match fits:
    case False{}:
      None{}
    case True{}:
      schema_outcome(schema_generated(name, answer, identity, dispatch, member, left, right, result, ambient, subject, specialization, configuration))

def schema_choice(found: Maybe<&2, Bool>, identity: Nat, dispatch: M.Dispatch, +member: String, left: M.Ty, right: M.Ty, result: M.Ty, ambient: M.EffectRow, subject: String, specialization: Specialization, configuration: Configuration) -> Maybe<&2, Specialization>:
  match found specialization configuration:
    case None{} _ _:
      None{}
    case Some{answer} +specialization +configuration:
      Specialization{M.Module{+constants, +functions, types, operations}, environment, choices, +counter, certificates} = specialization
      Configuration{+originals, templates, entry, locals, affected, +stride, +constant_values, family_templates, +step, schema} = configuration
      +name = "$schema[" ++ Nat.show(counter) ++ "]." ++ member
      schema_choice_space(Bool.and(schema_space(counter, stride, step), Bool.and(schema_fresh_space(environment), Bool.and(schema_name_free(lookup(functions, name)), Bool.and(schema_name_free(lookup(originals, name)), Bool.and(Bool.not(Maybe.is_some(&2, M.Constant, lookup_constant(constants, name))), Bool.not(Maybe.is_some(&2, M.Constant, lookup_constant(constant_values, name)))))))), name, answer, identity, dispatch, member, left, right, result, ambient, subject, specialization, configuration)

def schema_method(need: I.Coverage, +left: M.Ty, right: M.Ty, +specialization: Specialization, +configuration: Configuration, shapes: List<&2, I.Binding>) -> Maybe<&2, Specialization>:
  match need:
    case I.AssociatedNeed{identity, M.MemberDispatch{}, +member, Nil{}, old_left, old_right, +result, invocation, +ambient, +subject}:
      schema_choice(schema_answer(schema_proofs(configuration), member, left, result, specialization, configuration, shapes, subject), identity, M.MemberDispatch{}, member, left, right, result, ambient, subject, specialization, configuration)
    case _:
      None{}

def select_method_staged(found: Maybe<&2, Specialization>, need: I.Coverage, left: M.Ty, right: M.Ty, specialization: Specialization, configuration: Configuration, shapes: List<&2, I.Binding>, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match found:
    case Some{selected}:
      Done{selected}
    case None{}:
      select_method_original(need, left, right, specialization, configuration, shapes, schemes)

def select_method(+need: I.Coverage, +left: M.Ty, +right: M.Ty, +specialization: Specialization, +configuration: Configuration, +shapes: List<&2, I.Binding>, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, Specialization>:
  select_method_staged(schema_method(need, left, right, specialization, configuration, shapes), need, left, right, specialization, configuration, shapes, schemes)

# Field bodies contain only constructor cases and local variables. Check one
# independently against the already validated catalog, then import its closed
# principal interface at IDs fresh to the caller's inference state. The exact
# checked body is retained for the final scheduler; caller substitutions cannot
# change that certificate. Any independent-check failure takes the old path so
# the caller keeps its established diagnostic ordering.
type FieldEvidence is Data:
  FieldEvidence{environment: G.Environment, certificates: List<&2, Core.Certificate>}

def field_environment(value: FieldEvidence) -> G.Environment:
  FieldEvidence{environment, certificates} = value
  environment

def field_certificates(value: FieldEvidence) -> List<&2, Core.Certificate>:
  FieldEvidence{environment, certificates} = value
  certificates

def field_fallback(function: M.Function, environment: G.Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, names: List<&2, String>) -> Result<&2, &2, M.Diagnostic, FieldEvidence>:
  do Result<&2, &2, M.Diagnostic, FieldEvidence>:
    inferred : G.Environment <- infer_generated(function, environment, operations, types, names)
    return FieldEvidence{inferred, Nil{}}

def field_import(imported: Result<&2, &2, M.Diagnostic, G.Environment>, +function: M.Function, +module: M.Module, +checked: Groups.CheckedGroup, environment: G.Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, names: List<&2, String>) -> Result<&2, &2, M.Diagnostic, FieldEvidence>:
  match imported:
    case Fail{diagnostic}:
      field_fallback(function, environment, operations, types, names)
    case Done{G.Environment{new_bindings, new_definitions, imported_state}}:
      G.Environment{bindings, definitions, state} = environment
      Done{FieldEvidence{G.Environment{List.append(&2, I.Binding, new_bindings, bindings), List.append(&2, I.Definition, new_definitions, definitions), I.with_next(state, I.next_of(imported_state))}, [Core.Certificate{module, checked, Nil{}}]}}

def field_checked(result: Result<&2, &2, M.Diagnostic, Groups.CheckedGroup>, +function: M.Function, +module: M.Module, +environment: G.Environment, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, +names: List<&2, String>) -> Result<&2, &2, M.Diagnostic, FieldEvidence>:
  match result:
    case Fail{diagnostic}:
      field_fallback(function, environment, operations, types, names)
    case Done{Groups.CheckedGroup{checked_module, +interfaces, uses}}:
      field_import(Groups.import_interfaces(interfaces, operations, types, I.next_of(G.env_state(environment))), function, module, Groups.CheckedGroup{checked_module, interfaces, uses}, environment, operations, types, names)

def infer_field_owner(found: Maybe<&2, M.DataType>, +function: M.Function, environment: G.Environment, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, +names: List<&2, String>) -> Result<&2, &2, M.Diagnostic, FieldEvidence>:
  match found:
    case None{}:
      field_fallback(function, environment, operations, types, names)
    case Some{owner}:
      +module : M.Module = M.Module{Nil{}, [function], [owner], Nil{}}
      field_checked(Groups.check_group_planned(module, Nil{}), function, module, environment, operations, types, names)

def infer_field(+function: M.Function, +receiver: M.Ty, environment: G.Environment, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, +names: List<&2, String>) -> Result<&2, &2, M.Diagnostic, FieldEvidence>:
  match receiver:
    case M.AppliedTy{identity, arguments}:
      infer_field_owner(TD.lookup(types, identity), function, environment, operations, types, names)
    case other:
      field_fallback(function, environment, operations, types, names)

def select_field_site(need: I.Coverage, +left: M.Ty, right: M.Ty, specialization: Specialization, configuration: Configuration) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match need specialization:
    case I.AssociatedNeed{identity, +dispatch, member, templates, old_left, old_right, result, invocation, ambient, +subject} Specialization{M.Module{constants, +functions, +types, +operations}, environment, choices, +counter, certificates}:
      Configuration{+originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      +name = "$member[" ++ Nat.show(counter) ++ "]"
      do Result<&2, &2, M.Diagnostic, Specialization>:
        +generated : M.Function <- Members.function(Members.constructors(left, types), dispatch, member, name, Nat.mul(counter, stride))
        +all_functions : List<&2, M.Function> = List.append(&2, M.Function, functions, [generated])
        +field : FieldEvidence <- infer_field(generated, left, environment, operations, types, G.function_names(G.function_declarations(List.append(&2, M.Function, originals, all_functions))))
        +inferred : G.Environment = field_environment(field)
        +new_certificates : List<&2, Core.Certificate> = field_certificates(field)
        +selected_instance : I.SelectedInstantiation <- I.instantiate_binding_selected(I.lookup_binding(G.env_bindings(inferred), name), G.env_state(inferred), name, subject)
        +target : I.Typing = I.selected_typing(selected_instance)
        +unified : I.State <- I.unify(I.type_of(target), receiver_signature(dispatch, left, right, result, ambient), I.state_of(target), subject)
        signature : M.Ty <- T.resolve(I.substitutions_of(unified), I.selected_exact(selected_instance))
        return Specialization{M.Module{constants, all_functions, types, operations}, G.Environment{G.env_bindings(inferred), G.env_definitions(inferred), unified}, Map.set(&2, Choice, choices, Nat.show(identity), receiver_choice(dispatch, name, signature)), Nat.add(counter, step), List.append(&2, Core.Certificate, new_certificates, certificates)}
    case _ _:
      Fail{M.Diagnostic{"internal_error", "field", "selection expected a field requirement"}}

# One accessor serves every access to a field through the same nominal
# receiver type: its body depends only on that type's constructors, and its
# independently checked interface is generic in the type's arguments.
def accessor_name(owner: String, member: String, dispatch: M.Dispatch) -> String:
  match dispatch:
    case M.FieldUpdateDispatch{}:
      "$member.set[" ++ owner ++ "]." ++ member
    case _:
      "$member[" ++ owner ++ "]." ++ member

def accessor_owner(found: Maybe<&2, String>) -> String:
  match found:
    case Some{prefix}:
      prefix
    case None{}:
      ""

def function_name(function: M.Function) -> String:
  M.Function{name, exported, parameter, p, r, body} = function
  name

def function_exists(found: Result<&2, &2, M.Diagnostic, M.Function>) -> Bool:
  match found:
    case Done{function}:
      True{}
    case Fail{diagnostic}:
      False{}

def reuse_field(+name: String, need: I.Coverage, +left: M.Ty, right: M.Ty, specialization: Specialization, configuration: Configuration) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match need specialization:
    case I.AssociatedNeed{identity, +dispatch, member, templates, old_left, old_right, result, invocation, ambient, +subject} Specialization{module, +environment, choices, +counter, certificates}:
      Configuration{originals, configured, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      do Result<&2, &2, M.Diagnostic, Specialization>:
        +selected_instance : I.SelectedInstantiation <- I.instantiate_binding_selected(I.lookup_binding(G.env_bindings(environment), name), G.env_state(environment), name, subject)
        +target : I.Typing = I.selected_typing(selected_instance)
        +unified : I.State <- I.unify(I.type_of(target), receiver_signature(dispatch, left, right, result, ambient), I.state_of(target), subject)
        signature : M.Ty <- T.resolve(I.substitutions_of(unified), I.selected_exact(selected_instance))
        return Specialization{module, G.Environment{G.env_bindings(environment), G.env_definitions(environment), unified}, Map.set(&2, Choice, choices, Nat.show(identity), receiver_choice(dispatch, name, signature)), Nat.add(counter, step), certificates}
    case _ _:
      Fail{M.Diagnostic{"internal_error", "field", "selection expected a field requirement"}}

# Independent evidence for a shared accessor, or None when the owner is not in
# the catalog or the accessor alone does not check. The per-site path then owns
# the diagnostic exactly as before sharing existed.
def shared_field_import(imported: Result<&2, &2, M.Diagnostic, G.Environment>, +module: M.Module, +checked: Groups.CheckedGroup, environment: G.Environment) -> Maybe<&2, FieldEvidence>:
  match imported:
    case Fail{diagnostic}:
      None{}
    case Done{G.Environment{new_bindings, new_definitions, imported_state}}:
      G.Environment{bindings, definitions, state} = environment
      Some{FieldEvidence{G.Environment{List.append(&2, I.Binding, new_bindings, bindings), List.append(&2, I.Definition, new_definitions, definitions), I.with_next(state, I.next_of(imported_state))}, [Core.Certificate{module, checked, Nil{}}]}}

def shared_field_checked(result: Result<&2, &2, M.Diagnostic, Groups.CheckedGroup>, +module: M.Module, +environment: G.Environment, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>) -> Maybe<&2, FieldEvidence>:
  match result:
    case Fail{diagnostic}:
      None{}
    case Done{Groups.CheckedGroup{checked_module, +interfaces, uses}}:
      shared_field_import(Groups.import_interfaces(interfaces, operations, types, I.next_of(G.env_state(environment))), module, Groups.CheckedGroup{checked_module, interfaces, uses}, environment)

def shared_field_owner(found: Maybe<&2, M.DataType>, function: M.Function, environment: G.Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>) -> Maybe<&2, FieldEvidence>:
  match found:
    case None{}:
      None{}
    case Some{owner}:
      +module : M.Module = M.Module{Nil{}, [function], [owner], Nil{}}
      shared_field_checked(Groups.check_group_planned(module, Nil{}), module, environment, operations, types)

def shared_field_evidence(function: M.Function, receiver: M.Ty, environment: G.Environment, operations: List<&2, M.Operation>, +types: List<&2, M.DataType>) -> Maybe<&2, FieldEvidence>:
  match receiver:
    case M.AppliedTy{identity, arguments}:
      shared_field_owner(TD.lookup(types, identity), function, environment, operations, types)
    case other:
      None{}

def create_field(found: Maybe<&2, FieldEvidence>, +generated: M.Function, need: I.Coverage, +left: M.Ty, right: M.Ty, specialization: Specialization, configuration: Configuration) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match found need specialization:
    case None{} need specialization:
      select_field_site(need, left, right, specialization, configuration)
    case Some{+field} I.AssociatedNeed{identity, +dispatch, member, templates, old_left, old_right, result, invocation, ambient, +subject} Specialization{M.Module{constants, functions, types, operations}, environment, choices, +counter, certificates}:
      Configuration{originals, configured, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      +name = function_name(generated)
      +inferred : G.Environment = field_environment(field)
      do Result<&2, &2, M.Diagnostic, Specialization>:
        +selected_instance : I.SelectedInstantiation <- I.instantiate_binding_selected(I.lookup_binding(G.env_bindings(inferred), name), G.env_state(inferred), name, subject)
        +target : I.Typing = I.selected_typing(selected_instance)
        +unified : I.State <- I.unify(I.type_of(target), receiver_signature(dispatch, left, right, result, ambient), I.state_of(target), subject)
        signature : M.Ty <- T.resolve(I.substitutions_of(unified), I.selected_exact(selected_instance))
        return Specialization{M.Module{constants, List.append(&2, M.Function, functions, [generated]), types, operations}, G.Environment{G.env_bindings(inferred), G.env_definitions(inferred), unified}, Map.set(&2, Choice, choices, Nat.show(identity), receiver_choice(dispatch, name, signature)), Nat.add(counter, step), List.append(&2, Core.Certificate, field_certificates(field), certificates)}
    case _ _ _:
      Fail{M.Diagnostic{"internal_error", "field", "selection expected a field requirement"}}

def generate_field(+name: String, +need: I.Coverage, +left: M.Ty, right: M.Ty, +specialization: Specialization, +configuration: Configuration) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match need specialization:
    case I.AssociatedNeed{identity, +dispatch, +member, templates, old_left, old_right, result, invocation, ambient, subject} Specialization{M.Module{constants, functions, +types, +operations}, +environment, choices, +counter, certificates}:
      Configuration{originals, configured, entry, locals, affected, +stride, constant_values, family_templates, step, schema} = configuration
      do Result<&2, &2, M.Diagnostic, Specialization>:
        +generated : M.Function <- Members.function(Members.constructors(left, types), dispatch, member, name, Nat.mul(counter, stride))
        create_field(shared_field_evidence(generated, left, environment, operations, types), generated, need, left, right, specialization, configuration)
    case _ _:
      Fail{M.Diagnostic{"internal_error", "field", "selection expected a field requirement"}}

def select_field_shared(exists: Bool, +name: String, need: I.Coverage, left: M.Ty, right: M.Ty, specialization: Specialization, configuration: Configuration) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match exists:
    case True{}:
      reuse_field(name, need, left, right, specialization, configuration)
    case False{}:
      generate_field(name, need, left, right, specialization, configuration)

def select_field(+need: I.Coverage, +left: M.Ty, right: M.Ty, +specialization: Specialization, +configuration: Configuration) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match need specialization configuration:
    case I.AssociatedNeed{identity, +dispatch, +member, templates, old_left, old_right, result, invocation, ambient, subject} Specialization{M.Module{constants, functions, types, operations}, environment, choices, counter, certificates} Configuration{originals, configured, +entry, locals, affected, stride, constant_values, family_templates, step, schema}:
      +name = accessor_name(accessor_owner(owner(left, entry)), member, dispatch)
      select_field_shared(Bool.or(function_exists(lookup(originals, name)), function_exists(lookup(functions, name))), name, need, left, right, specialization, configuration)
    case _ _ _:
      Fail{M.Diagnostic{"internal_error", "field", "selection expected a field requirement"}}

def select_receiver_found(field: Bool, method: Result<&2, &2, M.Diagnostic, String>, dispatch: M.Dispatch, member: String, subject: String, need: I.Coverage, left: M.Ty, right: M.Ty, specialization: Specialization, configuration: Configuration, shapes: List<&2, I.Binding>, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match field method dispatch:
    case True{} Done{name} M.MemberDispatch{}:
      Fail{M.Diagnostic{"ambiguous_member", subject, "field and associated function share the name " ++ member}}
    case True{} _ _:
      select_field(need, left, right, specialization, configuration)
    case False{} _ M.FieldUpdateDispatch{}:
      Fail{M.Diagnostic{"missing_field", subject, "no writable field " ++ member ++ " on " ++ M.type_show(left)}}
    case False{} _ _:
      select_method(need, left, right, specialization, configuration, shapes, schemes)

def select_receiver(+need: I.Coverage, +left: M.Ty, right: M.Ty, +specialization: Specialization, +configuration: Configuration, +shapes: List<&2, I.Binding>, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match need specialization configuration:
    case I.AssociatedNeed{identity, +dispatch, +member, templates, old_left, old_right, result, invocation, ambient, +subject} Specialization{M.Module{constants, functions, types, operations}, environment, choices, counter, certificates} Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema}:
      select_receiver_found(Members.has_field(Members.constructors(left, types), member), receiver_method(owner(left, entry), member, shapes, subject), dispatch, member, subject, need, left, right, specialization, configuration, shapes, schemes)
    case _ _ _:
      Fail{M.Diagnostic{"internal_error", "member", "selection expected a member requirement"}}

def polymorphic(fuel: Nat, pending: List<&2, M.Ty>) -> Bool:
  match fuel pending:
    case _ Nil{}:
      False{}
    case 0n _:
      True{}
    case 1n+rest M.VariableTy{index} <> tail:
      True{}
    case 1n+rest M.ParameterTy{index} <> tail:
      True{}
    case 1n+rest M.FunctionTy{parameter, result, row} <> tail:
      polymorphic(rest, parameter <> result <> tail)
    case 1n+rest M.AppliedTy{identity, arguments} <> tail:
      polymorphic(rest, List.append(&2, M.Ty, arguments, tail))
    case 1n+rest M.ProductTy{elements} <> tail:
      polymorphic(rest, List.append(&2, M.Ty, elements, tail))
    case 1n+rest M.ArrayTy{element} <> tail:
      polymorphic(rest, element <> tail)
    case 1n+rest head <> tail:
      polymorphic(rest, tail)

type StateSource is Data:
  StateSource{read: M.TypeId, write: M.TypeId, operations: List<&2, M.Operation>}

def state_source_read(source: StateSource) -> M.TypeId:
  StateSource{read, write, operations} = source
  read

def state_source_write(source: StateSource) -> M.TypeId:
  StateSource{read, write, operations} = source
  write

def state_source_operations(source: StateSource) -> List<&2, M.Operation>:
  StateSource{read, write, operations} = source
  operations

def family_declaration_work(declarations: List<&2, M.Operation>, +wanted: M.TypeId, found: Maybe<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, M.Operation>:
  match declarations found:
    case _ Some{declaration}:
      Done{declaration}
    case Nil{} None{}:
      Fail{M.Diagnostic{"unknown_effect", M.type_id_show(wanted), "no declared effect operation matches this family member"}}
    case M.OperationTemplate{+identity, parameters, parameter, result} <> tail None{}:
      family_declaration_work(tail, wanted, Bool.pick(Maybe<&2, M.Operation>, M.type_id_equal(identity, wanted), Some{M.OperationTemplate{identity, parameters, parameter, result}}, None{}))
    case head <> tail None{}:
      family_declaration_work(tail, wanted, None{})

def family_declaration(declarations: List<&2, M.Operation>, wanted: M.TypeId) -> Result<&2, &2, M.Diagnostic, M.Operation>:
  family_declaration_work(declarations, wanted, None{})

def family_arguments_declared(declared: M.Operation, wanted: M.TypeId, +arguments: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, M.Operation>:
  match declared:
    case M.OperationTemplate{M.TypeId{module_name, declaration}, parameters, parameter, result}:
      do Result<&2, &2, M.Diagnostic, M.Operation>:
        valid : Unit <- Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, Nat.is_eq(parameters, List.length(&2, M.Ty, arguments)), Done{Unit{}}, Fail{M.Diagnostic{"type_arity", M.type_id_show(wanted), "effect operation has the wrong number of type arguments"}})
        key : String <- State.type_key(65536n, State.TypesKey{arguments})
        specialized_parameter : M.Ty <- T.parameters(arguments, 0n, parameter)
        specialized_result : M.Ty <- T.parameters(arguments, 0n, result)
        return M.Operation{M.TypeId{module_name, declaration ++ "<" ++ key ++ ">"}, specialized_parameter, specialized_result}
    case _:
      Fail{M.Diagnostic{"internal_error", M.type_id_show(wanted), "generic effect requires a template declaration"}}

def family_instance(+wanted: M.TypeId, +ty: M.Ty, declarations: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, M.Operation>:
  do Result<&2, &2, M.Diagnostic, M.Operation>:
    declared : M.Operation <- family_declaration(declarations, wanted)
    family_arguments_declared(declared, wanted, [ty])

def family_identity(operation: M.Operation) -> Result<&2, &2, M.Diagnostic, M.TypeId>:
  match operation:
    case M.Operation{identity, parameter, result}:
      Done{identity}
    case _:
      Fail{M.Diagnostic{"internal_error", "effect", "generic effect bridge expected a concrete operation"}}

def single_family_source(template: M.TypeId, +ty: M.Ty, declarations: List<&2, M.Operation>, existing: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, StateSource>:
  do Result<&2, &2, M.Diagnostic, StateSource>:
    +operation : M.Operation <- family_instance(template, ty, declarations)
    +identity : M.TypeId <- family_identity(operation)
    return StateSource{identity, identity, State.merge([operation], existing)}

def family_source(request: State.Request, requested: List<&2, M.TypeId>, +ty: M.Ty, +declarations: List<&2, M.Operation>, +existing: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, StateSource>:
  match request requested:
    case State.Read{} read <> Nil{}:
      single_family_source(read, ty, declarations, existing)
    case State.Reader{} read <> Nil{}:
      single_family_source(read, ty, declarations, existing)
    case State.Write{} write <> Nil{}:
      single_family_source(write, ty, declarations, existing)
    case State.Writer{} write <> Nil{}:
      single_family_source(write, ty, declarations, existing)
    case State.Run{} read <> write <> Nil{}:
      do Result<&2, &2, M.Diagnostic, StateSource>:
        +reader : M.Operation <- family_instance(read, ty, declarations)
        +writer : M.Operation <- family_instance(write, ty, declarations)
        read_identity : M.TypeId <- family_identity(reader)
        write_identity : M.TypeId <- family_identity(writer)
        return StateSource{read_identity, write_identity, State.merge([reader, writer], existing)}
    case _ _:
      Fail{M.Diagnostic{"effect_arity", "effect", "generic effect bridge received the wrong number of operation members"}}

def state_source(request: State.Request, requested: List<&2, M.TypeId>, +ty: M.Ty, declarations: List<&2, M.Operation>, existing: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, StateSource>:
  match requested:
    case Nil{}:
      do Result<&2, &2, M.Diagnostic, StateSource>:
        +key : String <- State.type_key(65536n, State.TypeKey{ty})
        return StateSource{State.read_identity(key), State.write_identity(key), State.operations(key, ty, existing)}
    case templates:
      family_source(request, templates, ty, declarations, existing)

def select_state(+request: State.Request, need: I.Coverage, +left: M.Ty, +right: M.Ty, specialization: Specialization, configuration: Configuration) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match need specialization:
    case I.AssociatedNeed{identity, dispatch, member, +effect_templates, old_left, old_right, result, invocation, +ambient, +subject} Specialization{M.Module{constants, +functions, +types, operations}, environment, choices, +counter, certificates}:
      Configuration{originals, templates, entry, locals, affected, stride, constant_values, +family_templates, step, schema} = configuration
      +ty = State.state_type(request, left)
      +name = "$state[" ++ Nat.show(counter) ++ "]"
      do Result<&2, &2, M.Diagnostic, Specialization>:
        +source : StateSource <- state_source(request, effect_templates, ty, family_templates, operations)
        +catalog : List<&2, M.Operation> = state_source_operations(source)
        +generated : M.Function = State.function_for(request, state_source_read(source), state_source_write(source), name, Nat.mul(counter, stride))
        +all_functions : List<&2, M.Function> = List.append(&2, M.Function, functions, [generated])
        +inferred : G.Environment <- infer_generated(generated, environment, catalog, types, G.function_names(G.function_declarations(List.append(&2, M.Function, originals, all_functions))))
        +selected_instance : I.SelectedInstantiation <- I.instantiate_binding_selected(I.lookup_binding(G.env_bindings(inferred), name), G.env_state(inferred), name, subject)
        +target : I.Typing = I.selected_typing(selected_instance)
        +unified : I.State <- I.unify(I.type_of(target), M.FunctionTy{left, M.FunctionTy{right, result, ambient}, ambient}, I.state_of(target), subject)
        signature : M.Ty <- T.resolve(I.substitutions_of(unified), I.selected_exact(selected_instance))
        return Specialization{M.Module{constants, all_functions, types, catalog}, G.Environment{G.env_bindings(inferred), G.env_definitions(inferred), unified}, Map.set(&2, Choice, choices, Nat.show(identity), FunctionChoice{name, signature}), Nat.add(counter, step), certificates}
    case _ _:
      Fail{M.Diagnostic{"internal_error", "state", "selection expected a typed state requirement"}}

# Invocation typing admits the operation in a wider ambient row. Evidence
# records the concrete operation itself, whose invocation has one effect.
def exact_operation_type(operation: M.Operation) -> M.Ty:
  match operation:
    case M.Operation{identity, parameter, result}:
      M.FunctionTy{parameter, result, Rows.singleton(identity, M.ClosedRow{})}
    case _:
      M.NeverTy{}

def select_operation(need: I.Coverage, arguments: List<&2, M.Ty>, specialization: Specialization, configuration: Configuration) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match need specialization:
    case I.OperationNeed{identity, +template, old_arguments, function_type, +subject} Specialization{M.Module{constants, functions, types, operations}, +environment, choices, counter, certificates}:
      Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      +state = G.env_state(environment)
      do Result<&2, &2, M.Diagnostic, Specialization>:
        declaration : M.Operation <- family_declaration(family_templates, template)
        +operation : M.Operation <- family_arguments_declared(declaration, template, arguments)
        concrete : M.TypeId <- family_identity(operation)
        +selected_type : M.Ty = I.operation_type(operation, I.next_of(state))
        +unified : I.State <- I.unify(function_type, selected_type, I.with_next(state, 1n+I.next_of(state)), subject)
        signature : M.Ty <- T.resolve(I.substitutions_of(unified), exact_operation_type(operation))
        return Specialization{M.Module{constants, functions, types, State.merge([operation], operations)}, G.Environment{G.env_bindings(environment), G.env_definitions(environment), unified}, Map.set(&2, Choice, choices, Nat.show(identity), OperationChoice{concrete, signature}), counter, certificates}
    case _ _:
      Fail{M.Diagnostic{"internal_error", "effect", "selection expected a generic operation requirement"}}

def select_request(request: Maybe<&2, State.Request>, need: I.Coverage, left: M.Ty, right: M.Ty, specialization: Specialization, configuration: Configuration, shapes: List<&2, I.Binding>, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match request:
    case Some{request}:
      select_state(request, need, left, right, specialization, configuration)
    case None{}:
      select_associated(need, left, right, specialization, configuration, shapes, schemes)

def select_type_same(need: I.Coverage, +left: M.Ty, +right: M.Ty, specialization: Specialization, configuration: Configuration) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match need specialization:
    case I.AssociatedNeed{identity, dispatch, member, +effect_templates, old_left, old_right, result, invocation, +ambient, +subject} Specialization{M.Module{constants, +functions, +types, +operations}, environment, choices, +counter, certificates}:
      Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      +name = "$type[" ++ Nat.show(counter) ++ "].same"
      do Result<&2, &2, M.Diagnostic, Specialization>:
        a : String <- State.type_key(65536n, State.TypeKey{State.witness(65536n, left)})
        b : String <- State.type_key(65536n, State.TypeKey{State.witness(65536n, right)})
        +generated : M.Function = M.Function{name, False{}, "$type.left", None{}, None{}, M.LambdaExpr{Nat.mul(counter, stride), "$type.right", None{}, None{}, M.BoolExpr{M.name_equal(a, b)}}}
        +all_functions : List<&2, M.Function> = List.append(&2, M.Function, functions, [generated])
        +inferred : G.Environment <- infer_generated(generated, environment, operations, types, G.function_names(G.function_declarations(List.append(&2, M.Function, originals, all_functions))))
        +selected_instance : I.SelectedInstantiation <- I.instantiate_binding_selected(I.lookup_binding(G.env_bindings(inferred), name), G.env_state(inferred), name, subject)
        +target : I.Typing = I.selected_typing(selected_instance)
        +unified : I.State <- I.unify(I.type_of(target), M.FunctionTy{left, M.FunctionTy{right, result, ambient}, ambient}, I.state_of(target), subject)
        signature : M.Ty <- T.resolve(I.substitutions_of(unified), I.selected_exact(selected_instance))
        return Specialization{M.Module{constants, all_functions, types, operations}, G.Environment{G.env_bindings(inferred), G.env_definitions(inferred), unified}, Map.set(&2, Choice, choices, Nat.show(identity), FunctionChoice{name, signature}), Nat.add(counter, step), certificates}
    case _ _:
      Fail{M.Diagnostic{"internal_error", "@type.same", "selection expected a type comparison requirement"}}

def select_type_request(same: Bool, request: Maybe<&2, State.Request>, need: I.Coverage, left: M.Ty, right: M.Ty, specialization: Specialization, configuration: Configuration, shapes: List<&2, I.Binding>, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match same:
    case True{}:
      select_type_same(need, left, right, specialization, configuration)
    case False{}:
      select_request(request, need, left, right, specialization, configuration, shapes, schemes)

def select(+need: I.Coverage, left: M.Ty, right: M.Ty, specialization: Specialization, configuration: Configuration, shapes: List<&2, I.Binding>, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match need:
    case I.AssociatedNeed{identity, M.BinaryDispatch{}, +member, +effect_templates, old_left, old_right, result, invocation, ambient, subject}:
      select_type_request(M.name_equal(member, "@type.same"), State.request(member), need, left, right, specialization, configuration, shapes, schemes)
    case I.AssociatedNeed{identity, dispatch, member, templates, old_left, old_right, result, invocation, ambient, subject}:
      select_receiver(need, left, right, specialization, configuration, shapes, schemes)
    case _:
      Fail{M.Diagnostic{"internal_error", "monomorphization", "selection expected a deferred requirement"}}

# The selector checks an implementation in the caller's permissible row. A
# qualified predicate instead states the effects of invoking that selected
# implementation. Compare with the exact pre-covariance signature.
def remaining_row_labels(selected: Rows.Selection) -> List<&2, M.TypeId>:
  Rows.Selection{found, remaining} = selected
  remaining

def max_row_labels(outer: List<&2, M.TypeId>, inner: List<&2, M.TypeId>) -> List<&2, M.TypeId>:
  match outer:
    case Nil{}:
      inner
    case +head <> tail:
      head <> max_row_labels(tail, remaining_row_labels(Rows.select(inner, head)))

def exact_binary_invocation(signature: M.Ty) -> Result<&2, &2, M.Diagnostic, Maybe<&2, M.EffectRow>>:
  match signature:
    case M.FunctionTy{first, M.FunctionTy{second, result, M.EffectRow{inner, M.ClosedRow{}}}, M.EffectRow{outer, M.ClosedRow{}}}:
      Done{Some{Rows.canonical(M.EffectRow{max_row_labels(outer, inner), M.ClosedRow{}})}}
    case M.FunctionTy{first, M.FunctionTy{second, result, inner}, outer}:
      Done{None{}}
    case other:
      Fail{M.Diagnostic{"internal_error", "qualified", "selected binary implementation has no curried signature"}}

def exact_receiver_invocation(signature: M.Ty) -> Result<&2, &2, M.Diagnostic, Maybe<&2, M.EffectRow>>:
  match signature:
    case M.FunctionTy{receiver, result, M.EffectRow{operations, M.ClosedRow{}}}:
      Done{Some{Rows.canonical(M.EffectRow{operations, M.ClosedRow{}})}}
    case M.FunctionTy{receiver, result, row}:
      Done{None{}}
    case other:
      Fail{M.Diagnostic{"internal_error", "qualified", "selected receiver implementation has no function signature"}}

# An ordinary invocation may be effect-polymorphic. An empty closed arrow
# contributes nothing, so the other row is exact even when its tail is open.
# Combining nonempty rows still requires the closed multiset calculation above.
def selected_binary_invocation(signature: M.Ty) -> Result<&2, &2, M.Diagnostic, Maybe<&2, M.EffectRow>>:
  match signature:
    case M.FunctionTy{first, M.FunctionTy{second, result, inner}, M.EffectRow{Nil{}, M.ClosedRow{}}}:
      Done{Some{Rows.canonical(inner)}}
    case M.FunctionTy{first, M.FunctionTy{second, result, M.EffectRow{Nil{}, M.ClosedRow{}}}, outer}:
      Done{Some{Rows.canonical(outer)}}
    case other:
      exact_binary_invocation(other)

def selected_receiver_invocation(signature: M.Ty) -> Result<&2, &2, M.Diagnostic, Maybe<&2, M.EffectRow>>:
  match signature:
    case M.FunctionTy{receiver, result, row}:
      Done{Some{Rows.canonical(row)}}
    case other:
      exact_receiver_invocation(other)

def selected_exact_invocation(found: Maybe<&2, Choice>, binary: Bool) -> Result<&2, &2, M.Diagnostic, Maybe<&2, M.EffectRow>>:
  match found binary:
    case Some{FunctionChoice{name, signature}} True{}:
      selected_binary_invocation(signature)
    case Some{ReceiverChoice{name, signature}} True{}:
      selected_binary_invocation(signature)
    case Some{ReceiverChoice{name, signature}} False{}:
      selected_receiver_invocation(signature)
    case _ _:
      Fail{M.Diagnostic{"internal_error", "qualified", "qualified selector has no matching exact implementation"}}

def unify_selected_invocation(found: Maybe<&2, M.EffectRow>, invocation: M.EffectRow, state: I.State, subject: String) -> Result<&2, &2, M.Diagnostic, I.State>:
  match found:
    case Some{exact}:
      I.unify_rows(invocation, exact, state, subject)
    case None{}:
      Done{state}

def constrain_selected_invocation(selected: Specialization, site: Nat, invocation: M.EffectRow, binary: Bool, subject: String) -> Result<&2, &2, M.Diagnostic, Specialization>:
  Specialization{module, +environment, +choices, next, certificates} = selected
  do Result<&2, &2, M.Diagnostic, Specialization>:
    exact : Maybe<&2, M.EffectRow> <- selected_exact_invocation(choice(choices, site), binary)
    state : I.State <- unify_selected_invocation(exact, invocation, G.env_state(environment), subject)
    return Specialization{module, G.Environment{G.env_bindings(environment), G.env_definitions(environment), state}, choices, next, certificates}

def associated_binary(dispatch: M.Dispatch) -> Bool:
  match dispatch:
    case M.MemberDispatch{}:
      False{}
    case M.BinaryDispatch{}:
      True{}
    case M.FieldUpdateDispatch{}:
      True{}

def constrain_ordinary_invocation(found: Maybe<&2, Specialization>, need: I.Coverage) -> Result<&2, &2, M.Diagnostic, Maybe<&2, Specialization>>:
  match found need:
    case Some{selected} I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, Some{invocation}, ambient, subject}:
      do Result<&2, &2, M.Diagnostic, Maybe<&2, Specialization>>:
        constrained : Specialization <- constrain_selected_invocation(selected, identity, invocation, associated_binary(dispatch), subject)
        return Some{constrained}
    case selected other:
      Done{selected}

def require_field(exists: Bool, need: I.Coverage, receiver: M.Ty, argument: M.Ty, member: String, subject: String, specialization: Specialization, configuration: Configuration, shapes: List<&2, I.Binding>, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match exists:
    case True{}:
      select_receiver(need, receiver, argument, specialization, configuration, shapes, schemes)
    case False{}:
      Fail{M.Diagnostic{"missing_field", subject, "no field " ++ member ++ " on " ++ M.type_show(receiver)}}

def select_qualified(original: M.Predicate, +resolved: M.Predicate, +site: Nat, +subject: String, +specialization: Specialization, configuration: Configuration, shapes: List<&2, I.Binding>, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match resolved:
    case M.AssociatedPredicate{member, templates, +left, +right, result, +invocation}:
      do Result<&2, &2, M.Diagnostic, Specialization>:
        selected : Specialization <- select(I.AssociatedNeed{site, M.BinaryDispatch{}, member, templates, left, right, result, None{}, invocation, subject}, left, right, specialization, configuration, shapes, schemes)
        constrained : Specialization <- constrain_selected_invocation(selected, site, invocation, True{}, subject)
        selected_qualified(specialization, constrained, site, original)
    case M.ReceiverPredicate{member, templates, +receiver, +argument, result, +invocation}:
      do Result<&2, &2, M.Diagnostic, Specialization>:
        selected : Specialization <- select(I.AssociatedNeed{site, M.MemberDispatch{}, member, templates, receiver, argument, result, None{}, invocation, subject}, receiver, argument, specialization, configuration, shapes, schemes)
        constrained : Specialization <- constrain_selected_invocation(selected, site, invocation, False{}, subject)
        selected_qualified(specialization, constrained, site, original)
    case M.FieldPredicate{+member, +receiver, result}:
      Specialization{M.Module{constants, functions, types, operations}, environment, choices, counter, certificates} = specialization
      do Result<&2, &2, M.Diagnostic, Specialization>:
        # The field clause requires a field, but ordinary member lookup still
        # rejects a same-name method; the clause does not suppress ambiguity.
        selected : Specialization <- require_field(Members.has_field(Members.constructors(receiver, types), member), I.AssociatedNeed{site, M.MemberDispatch{}, member, Nil{}, receiver, M.UnitTy{}, result, None{}, M.EffectRow{Nil{}, M.ClosedRow{}}, subject}, receiver, M.UnitTy{}, member, subject, specialization, configuration, shapes, schemes)
        selected_qualified(specialization, selected, site, original)
    case M.UpdatePredicate{member, +receiver, +assigned, result, +invocation}:
      do Result<&2, &2, M.Diagnostic, Specialization>:
        selected : Specialization <- select_receiver(I.AssociatedNeed{site, M.FieldUpdateDispatch{}, member, Nil{}, receiver, assigned, result, None{}, invocation, subject}, receiver, assigned, specialization, configuration, shapes, schemes)
        constrained : Specialization <- constrain_selected_invocation(selected, site, invocation, True{}, subject)
        selected_qualified(specialization, constrained, site, original)
    case M.OperationPredicate{template, +arguments, function_type}:
      do Result<&2, &2, M.Diagnostic, Specialization>:
        selected : Specialization <- select_operation(I.OperationNeed{site, template, arguments, function_type, subject}, arguments, specialization, configuration)
        selected_qualified(specialization, selected, site, original)
    case M.TypeRepPredicate{represented}:
      do Result<&2, &2, M.Diagnostic, Specialization>:
        answer : C.EvidenceAnswer <- direct_qualified_answer(resolved, subject)
        return remember_answer(specialization, specialization, site, original, answer)
    case M.EffectRepPredicate{row}:
      do Result<&2, &2, M.Diagnostic, Specialization>:
        answer : C.EvidenceAnswer <- direct_qualified_answer(resolved, subject)
        return remember_answer(specialization, specialization, site, original, answer)

def state_request_ready(request: Maybe<&2, State.Request>, left: M.Ty, right: M.Ty, +entry: String) -> Bool:
  match request:
    case Some{request}:
      Bool.not(polymorphic(65536n, [State.state_type(request, left)]))
    case None{}:
      Bool.or(Maybe.is_some(&2, String, owner(left, entry)), Maybe.is_some(&2, String, owner(right, entry)))

def request_ready(dispatch: M.Dispatch, +member: String, +left: M.Ty, +right: M.Ty, entry: String) -> Bool:
  match dispatch:
    case M.BinaryDispatch{}:
      Bool.pick(Bool, M.name_equal(member, "@type.same"), Bool.not(polymorphic(65536n, [State.witness(65536n, left), State.witness(65536n, right)])), state_request_ready(State.request(member), left, right, entry))
    case _:
      Maybe.is_some(&2, String, owner(left, entry))

# A selected implementation determines the predicate's result and latent row.
# Waiting for those outputs to close would prevent the selection itself.
def qualified_ready(predicate: M.Predicate, entry: String) -> Result<&2, &2, M.Diagnostic, Bool>:
  match predicate:
    case M.AssociatedPredicate{member, templates, left, right, result, invocation}:
      Done{request_ready(M.BinaryDispatch{}, member, left, right, entry)}
    case M.ReceiverPredicate{member, templates, receiver, argument, result, invocation}:
      Done{request_ready(M.MemberDispatch{}, member, receiver, argument, entry)}
    case M.FieldPredicate{member, receiver, result}:
      Done{request_ready(M.MemberDispatch{}, member, receiver, M.UnitTy{}, entry)}
    case M.UpdatePredicate{member, receiver, assigned, result, invocation}:
      Done{request_ready(M.FieldUpdateDispatch{}, member, receiver, assigned, entry)}
    case M.OperationPredicate{template, arguments, function_type}:
      Done{Bool.not(polymorphic(65536n, arguments))}
    case M.TypeRepPredicate{represented}:
      do Result<&2, &2, M.Diagnostic, Bool>:
        free : List<&2, Nat> <- C.free(M.TypeRepPredicate{represented})
        return List.is_empty(&2, Nat, free)
    case M.EffectRepPredicate{row}:
      do Result<&2, &2, M.Diagnostic, Bool>:
        free : List<&2, Nat> <- C.free(M.EffectRepPredicate{row})
        return List.is_empty(&2, Nat, free)

type ChoiceChange is Data:
  OrdinaryChoiceChanged{site: Nat}
  QualifiedChoiceChanged{site: Nat, predicate: M.Predicate}
  UnknownChoiceChange{}

def ordinary_choice_change(need: I.Coverage) -> ChoiceChange:
  match need:
    case I.OperationNeed{identity, template, arguments, function_type, subject}:
      OrdinaryChoiceChanged{identity}
    case I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, subject}:
      OrdinaryChoiceChanged{identity}
    case _:
      UnknownChoiceChange{}

type SolveWork is Data:
  Needs{values: List<&2, I.Coverage>}
  Operation{value: I.Coverage, arguments: List<&2, M.Ty>, ready: Bool, done: Bool, remaining: List<&2, I.Coverage>}
  Need{value: I.Coverage, left: M.Ty, right: M.Ty, ready: Bool, done: Bool, remaining: List<&2, I.Coverage>}
  Qualified{original: M.Predicate, resolved: M.Predicate, site: Nat, subject: String, ready: Bool, done: Bool, remaining: List<&2, I.Coverage>}
  Selected{value: Maybe<&2, Specialization>, change: ChoiceChange, remaining: List<&2, I.Coverage>}

def available_selection(attempt: Result<&2, &2, M.Diagnostic, Specialization>, unresolved: Bool) -> Result<&2, &2, M.Diagnostic, Maybe<&2, Specialization>>:
  match attempt:
    case Done{selected}:
      Done{Some{selected}}
    case Fail{M.Diagnostic{+code, subject, message}}:
      Bool.pick(Result<&2, &2, M.Diagnostic, Maybe<&2, Specialization>>, Bool.and(unresolved, M.name_equal(code, "missing_associated")), Done{None{}}, Fail{M.Diagnostic{code, subject, message}})

def unfinished(need: I.Coverage) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match need:
    case I.OperationNeed{identity, template, arguments, function_type, subject}:
      Fail{M.Diagnostic{"ambiguous_effect", subject, "cannot infer type arguments for " ++ M.type_id_show(template) ++ "; constrain its argument or result, or supply explicit type arguments"}}
    case I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, subject}:
      Fail{M.Diagnostic{"ambiguous_associated", subject, "cannot select " ++ member ++ " until operand types can be inferred; annotate the exported parameter or call the generic function with concrete types"}}
    case I.QualifiedNeed{site, predicate, subject}:
      Fail{M.Diagnostic{"ambiguous_qualified", subject, "cannot select this qualified requirement until its type and effect arguments are concrete"}}
    case _:
      Fail{M.Diagnostic{"internal_error", "monomorphization", "invalid deferred constraint"}}

def unresolved_need(need: I.Coverage, +choices: Map<&2, Choice>, +rest: List<&2, I.Coverage>) -> List<&2, I.Coverage>:
  match need:
    case I.OperationNeed{+identity, template, arguments, function_type, subject}:
      Bool.pick(List<&2, I.Coverage>, Maybe.is_some(&2, Choice, choice(choices, identity)), rest, I.OperationNeed{identity, template, arguments, function_type, subject} <> rest)
    case I.AssociatedNeed{+identity, +dispatch, member, templates, left, right, result, invocation, ambient, subject}:
      Bool.pick(List<&2, I.Coverage>, Maybe.is_some(&2, Choice, choice(choices, identity)), rest, I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, subject} <> rest)
    case I.QualifiedNeed{+site, +predicate, subject}:
      Bool.pick(List<&2, I.Coverage>, qualified_solved(choices, site, predicate), rest, I.QualifiedNeed{site, predicate, subject} <> rest)
    case _:
      rest

def unresolved(needs: List<&2, I.Coverage>, +choices: Map<&2, Choice>) -> List<&2, I.Coverage>:
  match needs:
    case Nil{}:
      Nil{}
    case +need <> +tail:
      unresolved_need(need, choices, unresolved(tail, choices))

# The solver revisits outstanding needs after each selected specialization.
# Walk each definition's coverage once, retaining the original order, instead
# of first flattening every coverage list and then copying its requirements.
def unresolved_coverage_with_tail(needs: List<&2, I.Coverage>, +choices: Map<&2, Choice>, rest: List<&2, I.Coverage>) -> List<&2, I.Coverage>:
  match needs:
    case Nil{}:
      rest
    case +need <> +tail:
      unresolved_need(need, choices, unresolved_coverage_with_tail(tail, choices, rest))

def unresolved_definitions(definitions: List<&2, I.Definition>, +choices: Map<&2, Choice>) -> List<&2, I.Coverage>:
  match definitions:
    case Nil{}:
      Nil{}
    case I.Definition{name, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail:
      unresolved_coverage_with_tail(List.append(&2, I.Coverage, coverage, I.execution_needs(uses)), choices, unresolved_definitions(tail, choices))

def specialization_pending(specialization: Specialization) -> List<&2, I.Coverage>:
  Specialization{module, environment, choices, next, certificates} = specialization
  unresolved_definitions(G.env_definitions(environment), choices)

type PendingCache is Data:
  PendingCache{definition_count: Nat, needs: List<&2, I.Coverage>}

def cached_needs(cache: PendingCache) -> List<&2, I.Coverage>:
  PendingCache{definition_count, needs} = cache
  needs

# Every successful selection leaves prior definitions as an unchanged suffix.
# G.infer_declaration prepends one immutable definition per new declaration;
# field_import prepends checked definitions, and operation selection adds none.
type FreshWork is Data:
  FreshWork{remaining: Nat, definitions: List<&2, I.Definition>}

def append_fresh(found: Maybe<&2, List<&2, I.Coverage>>, coverage: List<&2, I.Coverage>, +choices: Map<&2, Choice>) -> Maybe<&2, List<&2, I.Coverage>>:
  match found:
    case Some{next}:
      Some{unresolved_coverage_with_tail(coverage, choices, next)}
    case None{}:
      None{}

def fresh_unresolved(work: FreshWork, +choices: Map<&2, Choice>, rest: List<&2, I.Coverage>) -> Maybe<&2, List<&2, I.Coverage>>:
  match work:
    case FreshWork{0n, definitions}:
      Some{rest}
    case FreshWork{1n+remaining, I.Definition{name, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail}:
      append_fresh(fresh_unresolved(FreshWork{remaining, tail}, choices, rest), List.append(&2, I.Coverage, coverage, I.execution_needs(uses)), choices)
    case FreshWork{1n+remaining, Nil{}}:
      None{}

def refresh_from_fresh(found: Maybe<&2, List<&2, I.Coverage>>, selected: Specialization, count: Nat) -> PendingCache:
  match found:
    case Some{next}:
      PendingCache{count, next}
    case None{}:
      PendingCache{count, specialization_pending(selected)}

def refresh_with_count(valid: Bool, +selected: Specialization, +count: Nat, prior_count: Nat, definitions: List<&2, I.Definition>, prior_needs: List<&2, I.Coverage>, +choices: Map<&2, Choice>) -> PendingCache:
  match valid:
    case False{}:
      PendingCache{count, specialization_pending(selected)}
    case True{}:
      refresh_from_fresh(fresh_unresolved(FreshWork{Nat.sub(count, prior_count), definitions}, choices, unresolved(prior_needs, choices)), selected, count)

def refresh_pending(+selected: Specialization, cache: PendingCache) -> PendingCache:
  Specialization{module, environment, +choices, next, certificates} = selected
  PendingCache{+prior_count, +prior_needs} = cache
  +definitions = G.env_definitions(environment)
  +current_count = List.length(&2, I.Definition, definitions)
  refresh_with_count(Nat.is_ge(current_count, prior_count), selected, current_count, prior_count, definitions, prior_needs, choices)

# A selector changes one ordinary choice or adds one qualified predicate. The
# cached needs were already unresolved against the previous choices, so only
# that site can have become solved. New definitions still use the full map.
def qualified_pending_after_change(same_site: Bool, predicate: M.Predicate, selected: M.Predicate) -> Bool:
  match same_site:
    case False{}:
      True{}
    case True{}:
      Bool.not(C.same_predicate(predicate, selected))

def pending_after_change(need: I.Coverage, change: ChoiceChange) -> Bool:
  match need change:
    case I.OperationNeed{identity, template, arguments, function_type, subject} OrdinaryChoiceChanged{site}:
      Bool.not(Nat.is_eq(identity, site))
    case I.OperationNeed{identity, template, arguments, function_type, subject} _:
      True{}
    case I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, subject} OrdinaryChoiceChanged{site}:
      Bool.not(Nat.is_eq(identity, site))
    case I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, subject} _:
      True{}
    case I.QualifiedNeed{site, predicate, subject} QualifiedChoiceChanged{selected_site, selected}:
      qualified_pending_after_change(Nat.is_eq(site, selected_site), predicate, selected)
    case I.QualifiedNeed{site, predicate, subject} _:
      True{}
    case _ _:
      False{}

def remaining_after_change(needs: List<&2, I.Coverage>, +change: ChoiceChange) -> List<&2, I.Coverage>:
  match needs:
    case Nil{}:
      Nil{}
    case +head <> tail:
      +rest = remaining_after_change(tail, change)
      Bool.pick(List<&2, I.Coverage>, pending_after_change(head, change), head <> rest, rest)

def refresh_changed_with_count(valid: Bool, +selected: Specialization, +count: Nat, prior_count: Nat, definitions: List<&2, I.Definition>, prior_needs: List<&2, I.Coverage>, +choices: Map<&2, Choice>, change: ChoiceChange) -> PendingCache:
  match valid:
    case False{}:
      PendingCache{count, specialization_pending(selected)}
    case True{}:
      refresh_from_fresh(fresh_unresolved(FreshWork{Nat.sub(count, prior_count), definitions}, choices, remaining_after_change(prior_needs, change)), selected, count)

def refresh_known_change(+selected: Specialization, cache: PendingCache, change: ChoiceChange) -> PendingCache:
  Specialization{module, environment, +choices, next, certificates} = selected
  PendingCache{+prior_count, prior_needs} = cache
  +definitions = G.env_definitions(environment)
  +count = List.length(&2, I.Definition, definitions)
  refresh_changed_with_count(Nat.is_ge(count, prior_count), selected, count, prior_count, definitions, prior_needs, choices, change)

def refresh_after_change(selected: Specialization, cache: PendingCache, change: ChoiceChange) -> PendingCache:
  match change:
    case UnknownChoiceChange{}:
      refresh_pending(selected, cache)
    case changed:
      refresh_known_change(selected, cache, changed)

def solve_staged(fuel: Nat, work: SolveWork, +specialization: Specialization, +configuration: Configuration, +shapes: List<&2, I.Binding>, +cache: PendingCache, +schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"specialization_limit", "monomorphization", "too many associated specializations"}}
    case 1n+rest Needs{Nil{}}:
      Done{specialization}
    case 1n+rest Needs{I.OperationNeed{+identity, template, arguments, function_type, subject} <> tail}:
      Specialization{module, environment, choices, counter, certificates} = specialization
      do Result<&2, &2, M.Diagnostic, Specialization>:
        +resolved : List<&2, M.Ty> <- T.resolve_work(I.substitutions_of(G.env_state(environment)), 65536n, T.ManyTypes{arguments})
        solve_staged(rest, Operation{I.OperationNeed{identity, template, resolved, function_type, subject}, resolved, Bool.not(polymorphic(65536n, resolved)), Maybe.is_some(&2, Choice, choice(choices, identity)), tail}, specialization, configuration, shapes, cache, schemes)
    case 1n+rest Operation{need, arguments, ready, True{}, tail}:
      solve_staged(rest, Needs{tail}, specialization, configuration, shapes, cache, schemes)
    case 1n+rest Operation{need, arguments, False{}, False{}, tail}:
      solve_staged(rest, Needs{tail}, specialization, configuration, shapes, cache, schemes)
    case 1n+rest Operation{+need, arguments, True{}, False{}, tail}:
      do Result<&2, &2, M.Diagnostic, Specialization>:
        +selected : Specialization <- select_operation(need, arguments, specialization, configuration)
        +updated : PendingCache = refresh_after_change(selected, cache, ordinary_choice_change(need))
        solve_staged(rest, Needs{cached_needs(updated)}, selected, configuration, shapes, updated, schemes)
    case 1n+rest Needs{I.AssociatedNeed{+identity, +dispatch, +member, +effect_templates, +left, +right, result, invocation, ambient, subject} <> tail}:
      Specialization{module, environment, choices, counter, certificates} = specialization
      Configuration{originals, templates, +entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      do Result<&2, &2, M.Diagnostic, Specialization>:
        +l : M.Ty <- T.resolve(I.substitutions_of(G.env_state(environment)), left)
        +r : M.Ty <- T.resolve(I.substitutions_of(G.env_state(environment)), right)
        solve_staged(rest, Need{I.AssociatedNeed{identity, dispatch, member, effect_templates, left, right, result, invocation, ambient, subject}, l, r, request_ready(dispatch, member, l, r, entry), Maybe.is_some(&2, Choice, choice(choices, identity)), tail}, specialization, configuration, shapes, cache, schemes)
    case 1n+rest Needs{I.QualifiedNeed{+site, +predicate, subject} <> tail}:
      Specialization{module, environment, choices, counter, certificates} = specialization
      Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      do Result<&2, &2, M.Diagnostic, Specialization>:
        +resolved : M.Predicate <- C.resolve(I.substitutions_of(G.env_state(environment)), predicate)
        ready : Bool <- qualified_ready(resolved, entry)
        solve_staged(rest, Qualified{predicate, resolved, site, subject, ready, qualified_solved(choices, site, predicate), tail}, specialization, configuration, shapes, cache, schemes)
    case 1n+rest Needs{head <> tail}:
      solve_staged(rest, Needs{tail}, specialization, configuration, shapes, cache, schemes)
    case 1n+rest Qualified{original, resolved, site, subject, ready, True{}, tail}:
      solve_staged(rest, Needs{tail}, specialization, configuration, shapes, cache, schemes)
    case 1n+rest Qualified{original, resolved, site, subject, False{}, False{}, tail}:
      solve_staged(rest, Needs{tail}, specialization, configuration, shapes, cache, schemes)
    case 1n+rest Qualified{+original, resolved, +site, subject, True{}, False{}, tail}:
      do Result<&2, &2, M.Diagnostic, Specialization>:
        +selected : Specialization <- select_qualified(original, resolved, site, subject, specialization, configuration, shapes, schemes)
        +updated : PendingCache = refresh_after_change(selected, cache, QualifiedChoiceChanged{site, original})
        solve_staged(rest, Needs{cached_needs(updated)}, selected, configuration, shapes, updated, schemes)
    case 1n+rest Need{need, left, right, ready, True{}, tail}:
      solve_staged(rest, Needs{tail}, specialization, configuration, shapes, cache, schemes)
    case 1n+rest Need{need, left, right, False{}, False{}, tail}:
      solve_staged(rest, Needs{tail}, specialization, configuration, shapes, cache, schemes)
    case 1n+rest Need{+need, +left, +right, True{}, False{}, tail}:
      do Result<&2, &2, M.Diagnostic, Specialization>:
        selected : Maybe<&2, Specialization> <- available_selection(select(need, left, right, specialization, configuration, shapes, schemes), polymorphic(65536n, [left, right]))
        constrained : Maybe<&2, Specialization> <- constrain_ordinary_invocation(selected, need)
        solve_staged(rest, Selected{constrained, ordinary_choice_change(need), tail}, specialization, configuration, shapes, cache, schemes)
    case 1n+rest Selected{None{}, change, tail}:
      solve_staged(rest, Needs{tail}, specialization, configuration, shapes, cache, schemes)
    case 1n+rest Selected{Some{+selected}, change, tail}:
      +updated = refresh_after_change(selected, cache, change)
      solve_staged(rest, Needs{cached_needs(updated)}, selected, configuration, shapes, updated, schemes)
def solve(fuel: Nat, work: SolveWork, specialization: Specialization, configuration: Configuration, shapes: List<&2, I.Binding>, cache: PendingCache) -> Result<&2, &2, M.Diagnostic, Specialization>:
  solve_staged(fuel, work, specialization, configuration, shapes, cache, Nil{})

def selected_call(found: Maybe<&2, Choice>, member: String, left: M.Expr, right: M.Expr) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match found:
    case Some{ReceiverChoice{name, signature}}:
      Done{M.ApplyExpr{M.FunctionExpr{name}, left}}
    case Some{FunctionChoice{name, signature}}:
      Done{M.UseExpr{"$associated.left", left, M.UseExpr{"$associated.right", right, M.ApplyExpr{M.ApplyExpr{M.FunctionExpr{name}, M.LocalExpr{"$associated.left"}}, M.LocalExpr{"$associated.right"}}}}}
    case _:
      Fail{M.Diagnostic{"internal_error", member, "unresolved associated call after specialization"}}

def selected_operation(found: Maybe<&2, Choice>, template: M.TypeId) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match found:
    case Some{OperationChoice{identity, signature}}:
      Done{M.OperationExpr{identity}}
    case _:
      Fail{M.Diagnostic{"internal_error", M.type_id_show(template), "unresolved generic operation after specialization"}}

def replace_node(original: M.Expr, children: List<&2, M.Expr>, choices: Map<&2, Choice>) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match original children:
    case M.QualifiedExpr{offset, annotation, predicates, value} a <> Nil{}:
      Done{a}
    case M.InstantiationExpr{site, value} a <> Nil{}:
      Done{a}
    case M.GenericOperationExpr{identity, template, arguments} Nil{}:
      selected_operation(choice(choices, identity), template)
    case M.AssociatedExpr{identity, dispatch, member, templates, left, right} l <> r <> Nil{}:
      selected_call(choice(choices, identity), member, l, r)
    case original children:
      rebuild(original, children, 0n)

def replace(+fuel: Nat, work: ExpandWork, +choices: Map<&2, Choice>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"specialization_limit", "monomorphization", "replacement exceeded its structural limit"}}
    case 1n+rest Expression{+expression}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        children : List<&2, M.Expr> <- replace(rest, Expressions{F.children(expression)}, choices)
        rebuilt : M.Expr <- replace_node(expression, children, choices)
        return [rebuilt]
    case 1n+rest Expressions{Nil{}}:
      Done{Nil{}}
    case 1n+rest Expressions{head <> tail}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        value : List<&2, M.Expr> <- replace(rest, Expression{head}, choices)
        following : List<&2, M.Expr> <- replace(rest, Expressions{tail}, choices)
        return List.append(&2, M.Expr, value, following)
    case _ _:
      Fail{M.Diagnostic{"internal_error", "monomorphization", "unexpected replacement work"}}

def replace_functions(pending: List<&2, M.Function>, +choices: Map<&2, Choice>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Function>>:
  match pending:
    case Nil{}:
      Done{Nil{}}
    case M.Function{name, exported, parameter, p, r, body} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Function>>:
        expressions : List<&2, M.Expr> <- replace(65536n, Expression{body}, choices)
        value : M.Expr <- one(expressions)
        rest : List<&2, M.Function> <- replace_functions(tail, choices)
        return M.Function{name, exported, parameter, p, r, value} <> rest

def replace_constants(pending: List<&2, M.Constant>, +choices: Map<&2, Choice>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Constant>>:
  match pending:
    case Nil{}:
      Done{Nil{}}
    case M.Constant{name, exported, annotation, value} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Constant>>:
        expressions : List<&2, M.Expr> <- replace(65536n, Expression{value}, choices)
        result : M.Expr <- one(expressions)
        rest : List<&2, M.Constant> <- replace_constants(tail, choices)
        return M.Constant{name, exported, annotation, result} <> rest

def finish(specialized: Specialization) -> Result<&2, &2, M.Diagnostic, M.Module>:
  Specialization{M.Module{constants, functions, types, operations}, environment, +choices, next, certificates} = specialized
  do Result<&2, &2, M.Diagnostic, M.Module>:
    cs : List<&2, M.Constant> <- replace_constants(constants, choices)
    fs : List<&2, M.Function> <- replace_functions(functions, choices)
    return M.Module{cs, fs, types, operations}

def required(module: M.Module) -> Bool:
  M.Module{constants, functions, types, operations} = module
  Bool.or(Bool.not(List.is_empty(&2, String, seeds(functions))), Bool.not(List.is_empty(&2, String, constant_seeds(constants))))

def finish_expansion(+specialized: Specialization) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  Specialization{module, environment, choices, counter, certificates} = specialized
  M.Module{+constants, +functions, +types, +operations} = module
  +members = G.names(List.append(&2, G.Declaration, G.function_declarations(functions), G.constant_declarations(constants)))
  do Result<&2, &2, M.Diagnostic, ExpandedModule>:
    prepared : M.Module <- finish(specialized)
    function_nodes : List<&2, D.Node> <- D.function_nodes(functions)
    constant_nodes : List<&2, D.Node> <- D.constant_nodes(constants)
    +generalized : G.Environment <- G.generalize_component(environment, members, operations, types, List.append(&2, D.Node, function_nodes, constant_nodes))
    +bindings : List<&2, I.Binding> <- resolved_bindings(G.referenced_bindings(G.env_bindings(generalized), members), I.substitutions_of(G.env_state(generalized)))
    +selected : M.Module <- Public.select(prepared, bindings, Public.Resolved{})
    interfaces : List<&2, I.Binding> <- Public.generated_bindings(selected, bindings)
    return ExpandedModule{selected, counter, interfaces, certificates}

def selected_reference(found: Maybe<&2, Choice>, tail: List<&2, String>) -> List<&2, String>:
  match found:
    case Some{FunctionChoice{name, signature}}:
      name <> tail
    case Some{ReceiverChoice{name, signature}}:
      name <> tail
    case _:
      tail

def answer_reference(answer: C.EvidenceAnswer, tail: List<&2, String>) -> List<&2, String>:
  match answer:
    case C.EvidenceAnswer{predicate, C.SelectedFunction{name, signature}}:
      name <> tail
    case C.EvidenceAnswer{predicate, C.SelectedField{owner, member, accessor, signature}}:
      accessor <> tail
    case _:
      tail

def qualified_reference_match(solved: List<&2, M.Predicate>, answers: List<&2, C.EvidenceAnswer>, +wanted: M.Predicate, +tail: List<&2, String>) -> List<&2, String>:
  match solved answers:
    case head <> rest answer <> remaining:
      Bool.pick(List<&2, String>, C.same_predicate(head, wanted), answer_reference(answer, tail), qualified_reference_match(rest, remaining, wanted, tail))
    case _ _:
      tail

def qualified_reference(found: Maybe<&2, Choice>, wanted: M.Predicate, tail: List<&2, String>) -> List<&2, String>:
  match found:
    case Some{QualifiedChoice{solved, answers}}:
      qualified_reference_match(solved, answers, wanted, tail)
    case _:
      tail

def selected_references(constraints: List<&2, I.Coverage>, +choices: Map<&2, Choice>) -> List<&2, String>:
  match constraints:
    case Nil{}:
      Nil{}
    case I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, subject} <> tail:
      selected_reference(choice(choices, identity), selected_references(tail, choices))
    case I.QualifiedNeed{site, predicate, subject} <> tail:
      qualified_reference(qualified_choice(choices, site), predicate, selected_references(tail, choices))
    case head <> tail:
      selected_references(tail, choices)

def selected_edges(definitions: List<&2, I.Definition>, +choices: Map<&2, Choice>, +edges: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match definitions:
    case Nil{}:
      edges
    case I.Definition{+name, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail:
      selected_edges(tail, choices, Map.set(&2, List<&2, String>, edges, name, List.append(&2, String, selected_references(List.append(&2, I.Coverage, coverage, I.execution_needs(uses)), choices), D.neighbors(edges, name))))

def required_function_roots(functions: List<&2, M.Function>, +originals: List<&2, String>, +bindings: List<&2, I.Binding>, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, String>>:
  match functions:
    case Nil{}:
      Done{Nil{}}
    case M.Function{+name, exported, parameter, p, r, body} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, String>>:
        ty : M.Ty <- G.binding_type(I.lookup_binding(bindings, name), name)
        resolved : M.Ty <- T.resolve(substitutions, ty)
        +rest : List<&2, String> <- required_function_roots(tail, originals, bindings, substitutions)
        return Bool.pick(List<&2, String>, Bool.and(D.contains(originals, name), Bool.not(Bool.and(exported, polymorphic(65536n, [resolved])))), name <> rest, rest)

def required_constant_roots(constants: List<&2, M.Constant>, +bindings: List<&2, I.Binding>, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, String>>:
  match constants:
    case Nil{}:
      Done{Nil{}}
    case M.Constant{+name, exported, annotation, value} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, String>>:
        ty : M.Ty <- G.binding_type(I.lookup_binding(bindings, name), name)
        resolved : M.Ty <- T.resolve(substitutions, ty)
        +rest : List<&2, String> <- required_constant_roots(tail, bindings, substitutions)
        generic_alias : Bool = Bool.and(exported, Bool.and(template_value(65536n, value), polymorphic(65536n, [resolved])))
        return Bool.pick(List<&2, String>, Bool.or(String.starts_with(name, "$mono["), generic_alias), rest, name <> rest)

def reached_functions(functions: List<&2, M.Function>, +needed: Set()) -> List<&2, M.Function>:
  match functions:
    case Nil{}:
      Nil{}
    case +function <> tail:
      M.Function{name, exported, parameter, p, r, body} = function
      +rest = reached_functions(tail, needed)
      Bool.pick(List<&2, M.Function>, D.member(needed, name), function <> rest, rest)

def reached_constants(constants: List<&2, M.Constant>, +needed: Set()) -> List<&2, M.Constant>:
  match constants:
    case Nil{}:
      Nil{}
    case +constant <> tail:
      M.Constant{name, exported, annotation, value} = constant
      +rest = reached_constants(tail, needed)
      Bool.pick(List<&2, M.Constant>, D.member(needed, name), constant <> rest, rest)

def reached_definitions(definitions: List<&2, I.Definition>, +needed: Set()) -> List<&2, I.Definition>:
  match definitions:
    case Nil{}:
      Nil{}
    case I.Definition{+name, inference} <> tail:
      +rest = reached_definitions(tail, needed)
      Bool.pick(List<&2, I.Definition>, D.member(needed, name), I.Definition{name, inference} <> rest, rest)

def require_solved(needs: List<&2, I.Coverage>, specialization: Specialization) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match needs:
    case Nil{}:
      Done{specialization}
    case head <> tail:
      unfinished(head)

# Selection can infer the result immediately while a later requirement still
# refines its signature. Resolve and validate retained answers only after the
# solver has discharged every requirement in the reached module.
def resolve_evidence(evidence: C.Evidence, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, C.Evidence>:
  match evidence:
    case C.SelectedFunction{name, signature}:
      do Result<&2, &2, M.Diagnostic, C.Evidence>:
        resolved : M.Ty <- T.resolve(substitutions, signature)
        return C.SelectedFunction{name, resolved}
    case C.SelectedField{owner, member, accessor, signature}:
      do Result<&2, &2, M.Diagnostic, C.Evidence>:
        resolved : M.Ty <- T.resolve(substitutions, signature)
        return C.SelectedField{owner, member, accessor, resolved}
    case C.SelectedOperation{identity, signature}:
      do Result<&2, &2, M.Diagnostic, C.Evidence>:
        resolved : M.Ty <- T.resolve(substitutions, signature)
        return C.SelectedOperation{identity, resolved}
    case C.RepresentedType{represented}:
      do Result<&2, &2, M.Diagnostic, C.Evidence>:
        resolved : M.Ty <- T.resolve(substitutions, represented)
        return C.RepresentedType{resolved}
    case C.RepresentedEffect{row}:
      Done{C.RepresentedEffect{Rows.canonical(T.resolve_row(substitutions, row))}}

def compare_exact_invocation(invocation: M.EffectRow, exact: M.EffectRow, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match invocation:
    case M.EffectRow{operations, M.ClosedRow{}}:
      Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, C.same_type_ids(Rows.row_operations(Rows.canonical(M.EffectRow{operations, M.ClosedRow{}})), Rows.row_operations(Rows.canonical(exact))), Done{Unit{}}, Fail{M.Diagnostic{"effect_mismatch", subject, "qualified invocation effects differ from selected implementation"}})
    case other:
      Fail{M.Diagnostic{"ambiguous_qualified", subject, "qualified invocation effects remain open after selection"}}

def compare_found_exact_invocation(invocation: M.EffectRow, exact: Maybe<&2, M.EffectRow>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match exact:
    case Some{row}:
      compare_exact_invocation(invocation, row, subject)
    case None{}:
      Fail{M.Diagnostic{"ambiguous_qualified", subject, "selected implementation effects remain open"}}

def validate_exact_invocation(invocation: M.EffectRow, found: Result<&2, &2, M.Diagnostic, Maybe<&2, M.EffectRow>>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  do Result<&2, &2, M.Diagnostic, Unit>:
    exact : Maybe<&2, M.EffectRow> <- found
    compare_found_exact_invocation(invocation, exact, subject)

def resolved_selected_invocation(found: Maybe<&2, Choice>, +substitutions: T.Substitutions, binary: Bool) -> Result<&2, &2, M.Diagnostic, Maybe<&2, M.EffectRow>>:
  match found binary:
    case Some{FunctionChoice{name, signature}} True{}:
      do Result<&2, &2, M.Diagnostic, Maybe<&2, M.EffectRow>>:
        ty : M.Ty <- T.resolve(substitutions, signature)
        selected_binary_invocation(ty)
    case Some{ReceiverChoice{name, signature}} True{}:
      do Result<&2, &2, M.Diagnostic, Maybe<&2, M.EffectRow>>:
        ty : M.Ty <- T.resolve(substitutions, signature)
        selected_binary_invocation(ty)
    case Some{ReceiverChoice{name, signature}} False{}:
      do Result<&2, &2, M.Diagnostic, Maybe<&2, M.EffectRow>>:
        ty : M.Ty <- T.resolve(substitutions, signature)
        selected_receiver_invocation(ty)
    case _ _:
      Fail{M.Diagnostic{"internal_error", "associated", "ordinary call has no matching selected implementation"}}

def validate_qualified_invocation(predicate: M.Predicate, evidence: C.Evidence, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match predicate evidence:
    case M.AssociatedPredicate{member, templates, left, right, result, invocation} C.SelectedFunction{name, signature}:
      validate_exact_invocation(invocation, exact_binary_invocation(signature), subject)
    case M.UpdatePredicate{member, receiver, assigned, result, invocation} C.SelectedField{owner, field, accessor, signature}:
      validate_exact_invocation(invocation, exact_binary_invocation(signature), subject)
    case M.ReceiverPredicate{member, templates, receiver, argument, result, invocation} C.SelectedFunction{name, signature}:
      validate_exact_invocation(invocation, exact_receiver_invocation(signature), subject)
    case M.ReceiverPredicate{member, templates, receiver, argument, result, invocation} C.SelectedField{owner, field, accessor, signature}:
      validate_exact_invocation(invocation, exact_receiver_invocation(signature), subject)
    case M.AssociatedPredicate{member, templates, left, right, result, invocation} other:
      Fail{M.Diagnostic{"internal_error", subject, "associated qualifier has no selected function evidence"}}
    case M.UpdatePredicate{member, receiver, assigned, result, invocation} other:
      Fail{M.Diagnostic{"internal_error", subject, "update qualifier has no selected field evidence"}}
    case M.ReceiverPredicate{member, templates, receiver, argument, result, invocation} other:
      Fail{M.Diagnostic{"internal_error", subject, "receiver qualifier has no selected member evidence"}}
    case _ _:
      Done{Unit{}}

def finalize_answer(answer: C.EvidenceAnswer, +substitutions: T.Substitutions, +subject: String) -> Result<&2, &2, M.Diagnostic, C.EvidenceAnswer>:
  C.EvidenceAnswer{predicate, evidence} = answer
  do Result<&2, &2, M.Diagnostic, C.EvidenceAnswer>:
    +resolved_predicate : M.Predicate <- C.resolve(substitutions, predicate)
    +resolved_evidence : C.Evidence <- resolve_evidence(evidence, substitutions)
    valid : Unit <- validate_evidence(resolved_evidence, subject)
    row_valid : Unit <- validate_qualified_invocation(resolved_predicate, resolved_evidence, subject)
    return C.EvidenceAnswer{resolved_predicate, resolved_evidence}

def finalize_answers(answers: List<&2, C.EvidenceAnswer>, +substitutions: T.Substitutions, +subject: String) -> Result<&2, &2, M.Diagnostic, List<&2, C.EvidenceAnswer>>:
  match answers:
    case Nil{}:
      Done{Nil{}}
    case answer <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, C.EvidenceAnswer>>:
        first : C.EvidenceAnswer <- finalize_answer(answer, substitutions, subject)
        rest : List<&2, C.EvidenceAnswer> <- finalize_answers(tail, substitutions, subject)
        return first <> rest

def finalize_qualified_choice(found: Maybe<&2, Choice>, substitutions: T.Substitutions, subject: String) -> Result<&2, &2, M.Diagnostic, Choice>:
  match found:
    case Some{QualifiedChoice{solved, answers}}:
      do Result<&2, &2, M.Diagnostic, Choice>:
        resolved : List<&2, C.EvidenceAnswer> <- finalize_answers(answers, substitutions, subject)
        return QualifiedChoice{solved, resolved}
    case _:
      Fail{M.Diagnostic{"internal_error", subject, "qualified requirement has no selected evidence"}}

# Equality of the same resolved open tail holds for every later instantiation.
# This does not publish closed evidence: qualified choices use the stricter
# finalizer above. Source row names must never survive to this comparison.
def compare_ordinary_invocation(+invocation: M.EffectRow, found: Maybe<&2, M.EffectRow>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match invocation found:
    case M.EffectRow{operations, M.FreeRow{scope, name}} _:
      Fail{M.Diagnostic{"ambiguous_qualified", subject, "ordinary invocation retains an unresolved source effect row"}}
    case _ Some{M.EffectRow{operations, M.FreeRow{scope, name}}}:
      Fail{M.Diagnostic{"ambiguous_qualified", subject, "selected implementation retains an unresolved source effect row"}}
    case _ Some{exact}:
      Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, C.same_predicate(M.EffectRepPredicate{Rows.canonical(invocation)}, M.EffectRepPredicate{Rows.canonical(exact)}), Done{Unit{}}, Fail{M.Diagnostic{"effect_mismatch", subject, "invocation effects differ from selected implementation"}})
    case _ None{}:
      Fail{M.Diagnostic{"ambiguous_qualified", subject, "selected implementation effects remain open"}}

def validate_ordinary_invocation(invocation: M.EffectRow, found: Result<&2, &2, M.Diagnostic, Maybe<&2, M.EffectRow>>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  do Result<&2, &2, M.Diagnostic, Unit>:
    row : Maybe<&2, M.EffectRow> <- found
    compare_ordinary_invocation(invocation, row, subject)

def finalize_coverage(needs: List<&2, I.Coverage>, +substitutions: T.Substitutions, +choices: Map<&2, Choice>) -> Result<&2, &2, M.Diagnostic, Map<&2, Choice>>:
  match needs:
    case Nil{}:
      Done{choices}
    case I.AssociatedNeed{+identity, dispatch, member, templates, left, right, result, Some{invocation}, ambient, subject} <> tail:
      do Result<&2, &2, M.Diagnostic, Map<&2, Choice>>:
        valid : Unit <- validate_ordinary_invocation(T.resolve_row(substitutions, invocation), resolved_selected_invocation(choice(choices, identity), substitutions, associated_binary(dispatch)), subject)
        finalize_coverage(tail, substitutions, choices)
    case I.QualifiedNeed{+site, predicate, subject} <> tail:
      do Result<&2, &2, M.Diagnostic, Map<&2, Choice>>:
        selected : Choice <- finalize_qualified_choice(qualified_choice(choices, site), substitutions, subject)
        finalize_coverage(tail, substitutions, Map.set(&2, Choice, choices, qualified_key(site), selected))
    case head <> tail:
      finalize_coverage(tail, substitutions, choices)

def finalize_definitions(definitions: List<&2, I.Definition>, +substitutions: T.Substitutions, choices: Map<&2, Choice>) -> Result<&2, &2, M.Diagnostic, Map<&2, Choice>>:
  match definitions:
    case Nil{}:
      Done{choices}
    case I.Definition{name, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail:
      do Result<&2, &2, M.Diagnostic, Map<&2, Choice>>:
        selected : Map<&2, Choice> <- finalize_coverage(List.append(&2, I.Coverage, coverage, I.execution_needs(uses)), substitutions, choices)
        finalize_definitions(tail, substitutions, selected)

# The canonical Type.eq body erases callable witness arrows. Its proof may
# refine the exact selected invocation rows, but never those witness inputs or
# the caller's ambient row. The inner selection is read at its exact AST site.
def type_eq_selected_same(found: Maybe<&2, Choice>) -> Maybe<&2, C.Evidence>:
  match found:
    case Some{FunctionChoice{name, signature}}:
      Some{C.SelectedFunction{name, signature}}
    case _:
      None{}

def type_eq_same_resolved(found: Result<&2, &2, M.Diagnostic, C.Evidence>, predicate: M.Predicate, outer: C.Evidence, site: Nat, module: M.Module) -> Maybe<&2, M.Ty>:
  match found:
    case Done{same}:
      TypeEq.certified_signature(predicate, outer, site, same, module)
    case Fail{diagnostic}:
      None{}

def type_eq_same_found(found: Maybe<&2, C.Evidence>, predicate: M.Predicate, outer: C.Evidence, site: Nat, module: M.Module, substitutions: T.Substitutions) -> Maybe<&2, M.Ty>:
  match found:
    case Some{same}:
      type_eq_same_resolved(resolve_evidence(same, substitutions), predicate, outer, site, module)
    case None{}:
      None{}

def type_eq_site_found(found: Maybe<&2, Nat>, predicate: M.Predicate, outer: C.Evidence, choices: Map<&2, Choice>, module: M.Module, substitutions: T.Substitutions) -> Maybe<&2, M.Ty>:
  match found:
    case Some{+site}:
      type_eq_same_found(type_eq_selected_same(choice(choices, site)), predicate, outer, site, module, substitutions)
    case None{}:
      None{}

def type_eq_input_type(ty: M.Ty) -> Bool:
  match ty:
    case M.AppliedTy{identity, argument <> Nil{}}:
      M.type_id_equal(identity, M.TypeId{"std/prelude", "Type"})
    case _:
      False{}

def type_eq_input_signature(evidence: C.Evidence) -> Bool:
  match evidence:
    case C.SelectedFunction{name, M.FunctionTy{left, M.FunctionTy{right, M.BoolTy{}, inner}, outer}}:
      Bool.and(type_eq_input_type(left), type_eq_input_type(right))
    case _:
      False{}

def type_eq_input_ready(valid: Bool, predicate: M.Predicate, +outer: C.Evidence, choices: Map<&2, Choice>, +module: M.Module, substitutions: T.Substitutions) -> Maybe<&2, M.Ty>:
  match valid:
    case True{}:
      type_eq_site_found(TypeEq.clone_site(outer, module), predicate, outer, choices, module, substitutions)
    case False{}:
      None{}

def type_eq_resolved(predicate: Result<&2, &2, M.Diagnostic, M.Predicate>, evidence: Result<&2, &2, M.Diagnostic, C.Evidence>, choices: Map<&2, Choice>, module: M.Module, substitutions: T.Substitutions) -> Maybe<&2, M.Ty>:
  match predicate evidence:
    case Done{resolved} Done{+outer}:
      type_eq_input_ready(type_eq_input_signature(outer), resolved, outer, choices, module, substitutions)
    case _ _:
      None{}

def type_eq_request(predicate: M.Predicate) -> Bool:
  match predicate:
    case M.AssociatedPredicate{member, Nil{}, left, right, result, invocation}:
      M.name_equal(member, "eq")
    case _:
      False{}

def certify_type_eq_request(valid: Bool, predicate: M.Predicate, evidence: C.Evidence, +substitutions: T.Substitutions, choices: Map<&2, Choice>, module: M.Module) -> Maybe<&2, M.Ty>:
  match valid:
    case True{}:
      type_eq_resolved(C.resolve(substitutions, predicate), resolve_evidence(evidence, substitutions), choices, module, substitutions)
    case False{}:
      None{}

def type_eq_choice_name(evidence: C.Evidence) -> Bool:
  match evidence:
    case C.SelectedFunction{name, signature}:
      TypeEq.source_clone(name)
    case _:
      False{}

def certify_type_eq(+predicate: M.Predicate, +evidence: C.Evidence, substitutions: T.Substitutions, choices: Map<&2, Choice>, module: M.Module) -> Maybe<&2, M.Ty>:
  certify_type_eq_request(Bool.and(type_eq_request(predicate), type_eq_choice_name(evidence)), predicate, evidence, substitutions, choices, module)

def with_type_eq_signature(found: Maybe<&2, M.Ty>, evidence: C.Evidence) -> C.Evidence:
  match found evidence:
    case Some{signature} C.SelectedFunction{name, old}:
      C.SelectedFunction{name, signature}
    case _ other:
      other

def refresh_type_eq_answer(answer: C.EvidenceAnswer, substitutions: T.Substitutions, choices: Map<&2, Choice>, module: M.Module) -> C.EvidenceAnswer:
  C.EvidenceAnswer{+predicate, +evidence} = answer
  C.EvidenceAnswer{predicate, with_type_eq_signature(certify_type_eq(predicate, evidence, substitutions, choices, module), evidence)}

def refresh_type_eq_answers(answers: List<&2, C.EvidenceAnswer>, +substitutions: T.Substitutions, +choices: Map<&2, Choice>, +module: M.Module) -> List<&2, C.EvidenceAnswer>:
  match answers:
    case Nil{}:
      Nil{}
    case head <> tail:
      refresh_type_eq_answer(head, substitutions, choices, module) <> refresh_type_eq_answers(tail, substitutions, choices, module)

def refreshed_type_eq_function(found: Maybe<&2, M.Ty>, +name: String, signature: M.Ty) -> Choice:
  match found:
    case Some{exact}:
      FunctionChoice{name, exact}
    case None{}:
      FunctionChoice{name, signature}

def refresh_type_eq_function(found: Maybe<&2, Choice>, predicate: M.Predicate, substitutions: T.Substitutions, choices: Map<&2, Choice>, module: M.Module) -> Maybe<&2, Choice>:
  match found:
    case Some{FunctionChoice{+name, +signature}}:
      Some{refreshed_type_eq_function(certify_type_eq(predicate, C.SelectedFunction{name, signature}, substitutions, choices, module), name, signature)}
    case other:
      other

def refresh_type_eq_qualified(found: Maybe<&2, Choice>, substitutions: T.Substitutions, choices: Map<&2, Choice>, module: M.Module) -> Maybe<&2, Choice>:
  match found:
    case Some{QualifiedChoice{solved, answers}}:
      Some{QualifiedChoice{solved, refresh_type_eq_answers(answers, substitutions, choices, module)}}
    case other:
      other

def store_type_eq_choice(found: Maybe<&2, Choice>, key: String, choices: Map<&2, Choice>) -> Map<&2, Choice>:
  match found:
    case Some{selected}:
      Map.set(&2, Choice, choices, key, selected)
    case None{}:
      choices

def refresh_type_eq_need(need: I.Coverage, substitutions: T.Substitutions, +choices: Map<&2, Choice>, module: M.Module) -> Map<&2, Choice>:
  match need:
    case I.AssociatedNeed{+site, M.BinaryDispatch{}, member, templates, left, right, result, Some{invocation}, ambient, subject}:
      store_type_eq_choice(refresh_type_eq_function(choice(choices, site), M.AssociatedPredicate{member, templates, left, right, result, invocation}, substitutions, choices, module), Nat.show(site), choices)
    case I.QualifiedNeed{+site, predicate, subject}:
      store_type_eq_choice(refresh_type_eq_qualified(qualified_choice(choices, site), substitutions, choices, module), qualified_key(site), choices)
    case _:
      choices

def refresh_type_eq_needs(needs: List<&2, I.Coverage>, +substitutions: T.Substitutions, choices: Map<&2, Choice>, +module: M.Module) -> Map<&2, Choice>:
  match needs:
    case Nil{}:
      choices
    case head <> tail:
      refresh_type_eq_needs(tail, substitutions, refresh_type_eq_need(head, substitutions, choices, module), module)

def refresh_type_eq_definitions(definitions: List<&2, I.Definition>, +substitutions: T.Substitutions, choices: Map<&2, Choice>, +module: M.Module) -> Map<&2, Choice>:
  match definitions:
    case Nil{}:
      choices
    case I.Definition{name, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail:
      refresh_type_eq_definitions(tail, substitutions, refresh_type_eq_needs(List.append(&2, I.Coverage, coverage, I.execution_needs(uses)), substitutions, choices, module), module)

# Refresh can prove an open invocation before relinking. Final evidence may
# use that proof only after its actual qualified invocation is closed and pure.
def type_eq_closed_invocation(predicate: M.Predicate) -> Bool:
  match predicate:
    case M.AssociatedPredicate{member, templates, left, right, result, M.EffectRow{Nil{}, M.ClosedRow{}}}:
      True{}
    case _:
      False{}

def exact_type_eq_certificate(found: Maybe<&2, M.Ty>, evidence: C.Evidence) -> Bool:
  match found evidence:
    case Some{expected} C.SelectedFunction{name, actual}:
      Compare.same_ty(expected, actual)
    case _ _:
      False{}

# Ordinary selected evidence must be closed. A generated state runner also
# has a checked universal interpretation: callback results and residual effects
# can be quantified by the enclosing declaration. This fallback keeps that
# proof separate and never treats unrelated free variables as evidence.
def scoped_variables(found: Maybe<&2, I.Binding>) -> List<&2, Nat>:
  match found:
    case Some{I.Binding{name, ty, variables, predicates}}:
      variables
    case None{}:
      Nil{}

def restore_scoped_diagnostic(found: Result<&2, &2, M.Diagnostic, C.EvidenceAnswer>, original: M.Diagnostic) -> Result<&2, &2, M.Diagnostic, C.EvidenceAnswer>:
  match found:
    case Done{answer}:
      Done{answer}
    case Fail{diagnostic}:
      Fail{original}

# The contextual fallback may retain a current checked source scheme whose
# quantified arguments contain phantom rows. It must still be the same named
# selected instance, and its qualified invocation must pass the strict check.
def scoped_binding_count(bindings: List<&2, I.Binding>, +wanted: String) -> Nat:
  match bindings:
    case Nil{}:
      0n
    case I.Binding{name, ty, variables, predicates} <> tail:
      Nat.add(Bool.pick(Nat, M.name_equal(name, wanted), 1n, 0n), scoped_binding_count(tail, wanted))

def scoped_binding_resolved(found: Result<&2, &2, M.Diagnostic, M.Ty>, name: String, variables: List<&2, Nat>, evidence: C.Evidence, bound: List<&2, Nat>) -> Bool:
  match found:
    case Done{ty}:
      SelectedBindingEvidence.certify(I.Binding{name, ty, variables, Nil{}}, evidence, bound)
    case Fail{diagnostic}:
      False{}

def scoped_binding_found(found: Maybe<&2, I.Binding>, evidence: C.Evidence, bound: List<&2, Nat>, substitutions: T.Substitutions) -> Bool:
  match found:
    case Some{I.Binding{name, ty, variables, Nil{}}}:
      scoped_binding_resolved(T.resolve(substitutions, ty), name, variables, evidence, bound)
    case _:
      False{}

def scoped_binding_unique(unique: Bool, bindings: List<&2, I.Binding>, name: String, evidence: C.Evidence, bound: List<&2, Nat>, substitutions: T.Substitutions) -> Bool:
  match unique:
    case True{}:
      scoped_binding_found(I.lookup_binding(bindings, name), evidence, bound, substitutions)
    case False{}:
      False{}

def scoped_binding_certificate(+evidence: C.Evidence, +bindings: List<&2, I.Binding>, bound: List<&2, Nat>, substitutions: T.Substitutions) -> Bool:
  match evidence:
    case C.SelectedFunction{+name, signature}:
      scoped_binding_unique(Nat.is_eq(scoped_binding_count(bindings, name), 1n), bindings, name, evidence, bound, substitutions)
    case _:
      False{}

def member_certificate_count(certified: List<&2, MemberEvidenceCertificate>, +wanted: String) -> Nat:
  match certified:
    case Nil{}:
      0n
    case MemberEvidenceCertificate{name, signature} <> tail:
      Nat.add(Bool.pick(Nat, M.name_equal(name, wanted), 1n, 0n), member_certificate_count(tail, wanted))

def member_certificate_signature(certified: List<&2, MemberEvidenceCertificate>, +name: String, +signature: M.Ty) -> Bool:
  match certified:
    case Nil{}:
      False{}
    case MemberEvidenceCertificate{found, exact} <> tail:
      Bool.or(Bool.and(M.name_equal(found, name), Compare.same_ty(exact, signature)), member_certificate_signature(tail, name, signature))

def member_binding_resolved(found: Result<&2, &2, M.Diagnostic, M.Ty>, signature: M.Ty) -> Bool:
  match found:
    case Done{current}:
      Compare.same_ty(current, signature)
    case Fail{diagnostic}:
      False{}

def member_binding_found(found: Maybe<&2, I.Binding>, signature: M.Ty, substitutions: T.Substitutions) -> Bool:
  match found:
    case Some{I.Binding{name, ty, variables, predicates}}:
      member_binding_resolved(T.resolve(substitutions, ty), signature)
    case None{}:
      False{}

def member_signature_free(found: Result<&2, &2, M.Diagnostic, List<&2, Nat>>, bound: List<&2, Nat>) -> Bool:
  match found:
    case Done{free}:
      List.is_empty(&2, Nat, T.difference(free, bound))
    case Fail{diagnostic}:
      False{}

# The owning definition's generalized IDs delimit the certificate. The
# selected current binding must be unique and its full resolved type must be
# the checked body signature; a name match alone is never enough.
def member_certificate_condition_present(evidence: C.Evidence, +bound: List<&2, Nat>, +bindings: List<&2, I.Binding>, substitutions: T.Substitutions, +certified: List<&2, MemberEvidenceCertificate>) -> Bool:
  match evidence:
    case C.SelectedFunction{+name, +signature}:
      Bool.and(
        Bool.and(Nat.is_eq(member_certificate_count(certified, name), 1n), member_certificate_signature(certified, name, signature)),
        Bool.and(
          Bool.and(Nat.is_eq(scoped_binding_count(bindings, name), 1n), member_binding_found(I.lookup_binding(bindings, name), signature, substitutions)),
          Bool.and(SelectedBindingEvidence.admissible_types(65536n, [signature]), member_signature_free(T.free(signature), bound))
        )
      )
    case _:
      False{}

# Most requests never ran a member body proof. A constructor match avoids
# scanning current bindings or walking the selected type on that common path.
def member_certificate_condition(evidence: C.Evidence, bound: List<&2, Nat>, bindings: List<&2, I.Binding>, substitutions: T.Substitutions, certified: List<&2, MemberEvidenceCertificate>) -> Bool:
  match certified:
    case Nil{}:
      False{}
    case head <> tail:
      member_certificate_condition_present(evidence, bound, bindings, substitutions, head <> tail)

def scoped_binding_invocation(valid: Bool, predicate: M.Predicate, evidence: C.Evidence) -> Result<&2, &2, M.Diagnostic, Unit>:
  match valid:
    case True{}:
      validate_qualified_invocation(predicate, evidence, "selected source binding")
    case False{}:
      Fail{M.Diagnostic{"ambiguous_qualified", "selected source binding", "no scoped source scheme certificate"}}

def member_certificate_accept(predicate: M.Predicate, +evidence: C.Evidence, bound: List<&2, Nat>, bindings: List<&2, I.Binding>, substitutions: T.Substitutions, certified: List<&2, MemberEvidenceCertificate>) -> Result<&2, &2, M.Diagnostic, Unit>:
  scoped_binding_invocation(member_certificate_condition(evidence, bound, bindings, substitutions, certified), predicate, evidence)

def scoped_selected_certificate(canonical: Bool, predicate: M.Predicate, +evidence: C.Evidence, +bindings: List<&2, I.Binding>, +bound: List<&2, Nat>, +substitutions: T.Substitutions, certified: List<&2, MemberEvidenceCertificate>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match canonical:
    case True{}:
      Done{Unit{}}
    case False{}:
      scoped_binding_invocation(Bool.or(scoped_binding_certificate(evidence, bindings, bound, substitutions), member_certificate_condition(evidence, bound, bindings, substitutions, certified)), predicate, evidence)

def prove_scoped_answer(answer: C.EvidenceAnswer, +substitutions: T.Substitutions, +bound: List<&2, Nat>, +module: M.Module, choices: Map<&2, Choice>, bindings: List<&2, I.Binding>, certified: List<&2, MemberEvidenceCertificate>) -> Result<&2, &2, M.Diagnostic, C.EvidenceAnswer>:
  C.EvidenceAnswer{predicate, evidence} = answer
  do Result<&2, &2, M.Diagnostic, C.EvidenceAnswer>:
    +resolved_predicate : M.Predicate <- C.resolve(substitutions, predicate)
    +resolved_evidence : C.Evidence <- resolve_evidence(evidence, substitutions)
    accepted : Unit <- scoped_selected_certificate(Bool.or(Bool.or(StateEvidence.certify_run(resolved_predicate, resolved_evidence, bound, module), ScopedStateEvidence.certify_scoped(resolved_predicate, resolved_evidence, bound, module)), Bool.and(type_eq_closed_invocation(resolved_predicate), exact_type_eq_certificate(certify_type_eq(resolved_predicate, resolved_evidence, substitutions, choices, module), resolved_evidence))), resolved_predicate, resolved_evidence, bindings, bound, substitutions, certified)
    return C.EvidenceAnswer{resolved_predicate, resolved_evidence}

def accept_scoped_answer(found: Result<&2, &2, M.Diagnostic, C.EvidenceAnswer>, answer: C.EvidenceAnswer, substitutions: T.Substitutions, bound: List<&2, Nat>, module: M.Module, choices: Map<&2, Choice>, bindings: List<&2, I.Binding>, certified: List<&2, MemberEvidenceCertificate>) -> Result<&2, &2, M.Diagnostic, C.EvidenceAnswer>:
  match found:
    case Done{resolved}:
      Done{resolved}
    case Fail{diagnostic}:
      restore_scoped_diagnostic(prove_scoped_answer(answer, substitutions, bound, module, choices, bindings, certified), diagnostic)

def finalize_answers_scoped(answers: List<&2, C.EvidenceAnswer>, +substitutions: T.Substitutions, +subject: String, +bound: List<&2, Nat>, +module: M.Module, +choices: Map<&2, Choice>, +bindings: List<&2, I.Binding>, +certified: List<&2, MemberEvidenceCertificate>) -> Result<&2, &2, M.Diagnostic, List<&2, C.EvidenceAnswer>>:
  match answers:
    case Nil{}:
      Done{Nil{}}
    case +answer <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, C.EvidenceAnswer>>:
        first : C.EvidenceAnswer <- accept_scoped_answer(finalize_answer(answer, substitutions, subject), answer, substitutions, bound, module, choices, bindings, certified)
        rest : List<&2, C.EvidenceAnswer> <- finalize_answers_scoped(tail, substitutions, subject, bound, module, choices, bindings, certified)
        return first <> rest

def finalize_choice_scoped_certified(found: Maybe<&2, Choice>, substitutions: T.Substitutions, subject: String, bound: List<&2, Nat>, module: M.Module, choices: Map<&2, Choice>, bindings: List<&2, I.Binding>, certified: List<&2, MemberEvidenceCertificate>) -> Result<&2, &2, M.Diagnostic, Choice>:
  match found:
    case Some{QualifiedChoice{solved, answers}}:
      do Result<&2, &2, M.Diagnostic, Choice>:
        resolved : List<&2, C.EvidenceAnswer> <- finalize_answers_scoped(answers, substitutions, subject, bound, module, choices, bindings, certified)
        return QualifiedChoice{solved, resolved}
    case _:
      Fail{M.Diagnostic{"internal_error", subject, "qualified requirement has no selected evidence"}}

# Keep the existing focused-test and public helper arity. Production carries
# proof certificates only through the private certified continuation.
def finalize_choice_scoped(found: Maybe<&2, Choice>, substitutions: T.Substitutions, subject: String, bound: List<&2, Nat>, module: M.Module, choices: Map<&2, Choice>, bindings: List<&2, I.Binding>) -> Result<&2, &2, M.Diagnostic, Choice>:
  finalize_choice_scoped_certified(found, substitutions, subject, bound, module, choices, bindings, Nil{})

def finalize_coverage_scoped(needs: List<&2, I.Coverage>, +substitutions: T.Substitutions, +choices: Map<&2, Choice>, +bound: List<&2, Nat>, +module: M.Module, +bindings: List<&2, I.Binding>, +certified: List<&2, MemberEvidenceCertificate>) -> Result<&2, &2, M.Diagnostic, Map<&2, Choice>>:
  match needs:
    case Nil{}:
      Done{choices}
    case I.QualifiedNeed{+site, predicate, subject} <> tail:
      do Result<&2, &2, M.Diagnostic, Map<&2, Choice>>:
        selected : Choice <- finalize_choice_scoped_certified(qualified_choice(choices, site), substitutions, subject, bound, module, choices, bindings, certified)
        finalize_coverage_scoped(tail, substitutions, Map.set(&2, Choice, choices, qualified_key(site), selected), bound, module, bindings, certified)
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, Map<&2, Choice>>:
        selected : Map<&2, Choice> <- finalize_coverage([head], substitutions, choices)
        finalize_coverage_scoped(tail, substitutions, selected, bound, module, bindings, certified)

def finalize_definitions_scoped(definitions: List<&2, I.Definition>, +substitutions: T.Substitutions, choices: Map<&2, Choice>, +bindings: List<&2, I.Binding>, +module: M.Module, +certified: List<&2, MemberEvidenceCertificate>) -> Result<&2, &2, M.Diagnostic, Map<&2, Choice>>:
  match definitions:
    case Nil{}:
      Done{choices}
    case I.Definition{name, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail:
      do Result<&2, &2, M.Diagnostic, Map<&2, Choice>>:
        selected : Map<&2, Choice> <- finalize_coverage_scoped(List.append(&2, I.Coverage, coverage, I.execution_needs(uses)), substitutions, choices, scoped_variables(I.lookup_binding(bindings, name)), module, bindings, certified)
        finalize_definitions_scoped(tail, substitutions, selected, bindings, module, certified)

def scoped_finalization(found: Result<&2, &2, M.Diagnostic, G.Environment>, +module: M.Module, choices: Map<&2, Choice>, original: M.Diagnostic, certified: List<&2, MemberEvidenceCertificate>) -> Result<&2, &2, M.Diagnostic, Map<&2, Choice>>:
  match found:
    case Fail{diagnostic}:
      Fail{original}
    case Done{environment}:
      G.Environment{bindings, definitions, state} = environment
      finalize_definitions_scoped(definitions, I.substitutions_of(state), choices, bindings, module, certified)

def finalize_with_scope(found: Result<&2, &2, M.Diagnostic, Map<&2, Choice>>, +module: M.Module, environment: G.Environment, choices: Map<&2, Choice>, certified: List<&2, MemberEvidenceCertificate>) -> Result<&2, &2, M.Diagnostic, Map<&2, Choice>>:
  match found:
    case Done{answers}:
      Done{answers}
    case Fail{diagnostic}:
      M.Module{+constants, +functions, types, operations} = module
      +members = G.names(List.append(&2, G.Declaration, G.function_declarations(functions), G.constant_declarations(constants)))
      do Result<&2, &2, M.Diagnostic, Map<&2, Choice>>:
        function_nodes : List<&2, D.Node> <- D.function_nodes(functions)
        constant_nodes : List<&2, D.Node> <- D.constant_nodes(constants)
        scoped_finalization(G.generalize_component(environment, members, operations, types, List.append(&2, D.Node, function_nodes, constant_nodes)), module, choices, diagnostic, certified)

def finalize_evidence_certified(+module: M.Module, +environment: G.Environment, +choices: Map<&2, Choice>, certified: List<&2, MemberEvidenceCertificate>) -> Result<&2, &2, M.Diagnostic, Map<&2, Choice>>:
  finalize_with_scope(finalize_definitions(G.env_definitions(environment), I.substitutions_of(G.env_state(environment)), choices), module, environment, choices, certified)

def finalize_evidence(+module: M.Module, +environment: G.Environment, +choices: Map<&2, Choice>) -> Result<&2, &2, M.Diagnostic, Map<&2, Choice>>:
  finalize_evidence_certified(module, environment, choices, Nil{})

# Selected associated and qualified choices contribute edges before replacement
# materializes them. Boundary scheduling and pruning use the same graph.
def reached_names(specialized: Specialization, configuration: Configuration) -> Result<&2, &2, M.Diagnostic, Set()>:
  Specialization{M.Module{+constants, +functions, types, operations}, +environment, +choices, counter, certificates} = specialized
  Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
  +definitions = G.env_definitions(environment)
  do Result<&2, &2, M.Diagnostic, Set()>:
    function_roots : List<&2, String> <- required_function_roots(functions, G.function_names(G.function_declarations(originals)), G.env_bindings(environment), I.substitutions_of(G.env_state(environment)))
    constant_roots : List<&2, String> <- required_constant_roots(constants, G.env_bindings(environment), I.substitutions_of(G.env_state(environment)))
    fs : List<&2, D.Node> <- D.function_nodes(functions)
    cs : List<&2, D.Node> <- D.constant_nodes(constants)
    +nodes : List<&2, D.Node> = List.append(&2, D.Node, fs, cs)
    +roots : List<&2, String> = List.append(&2, String, function_roots, constant_roots)
    edges : Map<&2, List<&2, String>> = selected_edges(definitions, choices, D.adjacency(nodes, MTip{}))
    fuel : Nat = 1n+Nat.add(List.length(&2, String, roots), Nat.add(D.edge_count(nodes), List.length(&2, I.Coverage, pending(environment))))
    reached : D.Reachability <- D.reachable(fuel, roots, edges, Set.from_list(D.node_names(nodes)), Set.new(), Nil{})
    return D.reached_seen(reached)

# Public generic functions remain source templates until a caller fixes their
# types. Remove only speculative roots and clones unreachable from real roots.
def prune_generic_roots(+specialized: Specialization, configuration: Configuration) -> Result<&2, &2, M.Diagnostic, Specialization>:
  Specialization{M.Module{+constants, +functions, types, operations}, +environment, choices, counter, certificates} = specialized
  do Result<&2, &2, M.Diagnostic, Specialization>:
    +seen : Set() <- reached_names(specialized, configuration)
    +definitions : List<&2, I.Definition> = G.env_definitions(environment)
    +retained : Specialization = Specialization{M.Module{reached_constants(constants, seen), reached_functions(functions, seen), types, operations}, G.Environment{G.env_bindings(environment), reached_definitions(definitions, seen), G.env_state(environment)}, choices, counter, certificates}
    require_solved(specialization_pending(retained), retained)

type BoundaryCoverage is Data:
  BoundaryCoverage{values: List<&2, I.Coverage>, next: Nat, changed: Bool}

type BoundaryDefinitions is Data:
  BoundaryDefinitions{values: List<&2, I.Definition>, next: Nat, changed: Bool}

type BoundaryProgress is Data:
  BoundaryProgress{specialization: Specialization, changed: Bool}

def boundary_coverage_values(value: BoundaryCoverage) -> List<&2, I.Coverage>:
  BoundaryCoverage{values, next, changed} = value
  values

def boundary_coverage_next(value: BoundaryCoverage) -> Nat:
  BoundaryCoverage{values, next, changed} = value
  next

def boundary_coverage_changed(value: BoundaryCoverage) -> Bool:
  BoundaryCoverage{values, next, changed} = value
  changed

def boundary_definition_values(value: BoundaryDefinitions) -> List<&2, I.Definition>:
  BoundaryDefinitions{values, next, changed} = value
  values

def boundary_definition_next(value: BoundaryDefinitions) -> Nat:
  BoundaryDefinitions{values, next, changed} = value
  next

def boundary_definition_changed(value: BoundaryDefinitions) -> Bool:
  BoundaryDefinitions{values, next, changed} = value
  changed

def boundary_needs(predicates: List<&2, M.Predicate>, +site: Nat, +subject: String) -> List<&2, I.Coverage>:
  match predicates:
    case Nil{}:
      Nil{}
    case predicate <> tail:
      I.QualifiedNeed{site, predicate, subject} <> boundary_needs(tail, site, subject)

def checked_boundary_site(allowed: Bool, counter: Nat, stride: Nat, subject: String) -> Result<&2, &2, M.Diagnostic, Nat>:
  match allowed:
    case True{}:
      Done{Nat.mul(counter, stride)}
    case False{}:
      Fail{M.Diagnostic{"specialization_limit", subject, "qualified boundary identity space exhausted"}}

def boundary_site(+counter: Nat, +stride: Nat, +step: Nat, subject: String) -> Result<&2, &2, M.Diagnostic, Nat>:
  checked_boundary_site(Bool.and(Nat.is_ge(counter, 1n), Bool.and(Nat.is_ge(step, 1n), schema_space(counter, stride, step))), counter, stride, subject)

def schedule_boundary_coverage(values: List<&2, I.Coverage>, +counter: Nat, +stride: Nat, +step: Nat) -> Result<&2, &2, M.Diagnostic, BoundaryCoverage>:
  match values:
    case Nil{}:
      Done{BoundaryCoverage{Nil{}, counter, False{}}}
    case I.QualifiedBoundary{offset, declared, +subject} <> tail:
      do Result<&2, &2, M.Diagnostic, BoundaryCoverage>:
        site : Nat <- boundary_site(counter, stride, step, subject)
        needs : List<&2, I.Coverage> = boundary_needs(declared, site, subject)
        +rest : BoundaryCoverage <- schedule_boundary_coverage(tail, Nat.add(counter, step), stride, step)
        return BoundaryCoverage{List.append(&2, I.Coverage, needs, boundary_coverage_values(rest)), boundary_coverage_next(rest), True{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, BoundaryCoverage>:
        +rest : BoundaryCoverage <- schedule_boundary_coverage(tail, counter, stride, step)
        return BoundaryCoverage{head <> boundary_coverage_values(rest), boundary_coverage_next(rest), boundary_coverage_changed(rest)}

def schedule_if_reached(reached: Bool, coverage: List<&2, I.Coverage>, counter: Nat, stride: Nat, step: Nat) -> Result<&2, &2, M.Diagnostic, BoundaryCoverage>:
  match reached:
    case False{}:
      Done{BoundaryCoverage{coverage, counter, False{}}}
    case True{}:
      schedule_boundary_coverage(coverage, counter, stride, step)

def schedule_boundary_definitions(definitions: List<&2, I.Definition>, +reached: Set(), counter: Nat, +stride: Nat, +step: Nat) -> Result<&2, &2, M.Diagnostic, BoundaryDefinitions>:
  match definitions:
    case Nil{}:
      Done{BoundaryDefinitions{Nil{}, counter, False{}}}
    case I.Definition{+name, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail:
      do Result<&2, &2, M.Diagnostic, BoundaryDefinitions>:
        +updated : BoundaryCoverage <- schedule_if_reached(D.member(reached, name), coverage, counter, stride, step)
        +rest : BoundaryDefinitions <- schedule_boundary_definitions(tail, reached, boundary_coverage_next(updated), stride, step)
        return BoundaryDefinitions{I.Definition{name, I.Inference{ty, boundary_coverage_values(updated), exits, reflections, predicates, uses}} <> boundary_definition_values(rest), boundary_definition_next(rest), Bool.or(boundary_coverage_changed(updated), boundary_definition_changed(rest))}

def has_boundary(coverage: List<&2, I.Coverage>) -> Bool:
  match coverage:
    case Nil{}:
      False{}
    case I.QualifiedBoundary{offset, declared, subject} <> tail:
      True{}
    case head <> tail:
      has_boundary(tail)

def has_boundary_definition(definitions: List<&2, I.Definition>) -> Bool:
  match definitions:
    case Nil{}:
      False{}
    case I.Definition{name, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail:
      Bool.or(has_boundary(coverage), has_boundary_definition(tail))

def solve_scheduled_boundaries(changed: Bool, +specialized: Specialization, configuration: Configuration, shapes: List<&2, I.Binding>, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, BoundaryProgress>:
  match changed:
    case False{}:
      Done{BoundaryProgress{specialized, False{}}}
    case True{}:
      Specialization{module, +environment, choices, counter, certificates} = specialized
      +initial = specialization_pending(specialized)
      +count = List.length(&2, I.Definition, G.env_definitions(environment))
      do Result<&2, &2, M.Diagnostic, BoundaryProgress>:
        solved : Specialization <- solve_staged(65536n, Needs{initial}, specialized, configuration, shapes, PendingCache{count, initial}, schemes)
        return BoundaryProgress{solved, True{}}

def schedule_present_boundaries_work(+specialized: Specialization, +configuration: Configuration, shapes: List<&2, I.Binding>, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, BoundaryProgress>:
  Specialization{module, +environment, choices, counter, certificates} = specialized
  Configuration{originals, templates, entry, locals, affected, +stride, constant_values, family_templates, +step, schema} = configuration
  do Result<&2, &2, M.Diagnostic, BoundaryProgress>:
    reached : Set() <- reached_names(specialized, configuration)
    +scheduled : BoundaryDefinitions <- schedule_boundary_definitions(G.env_definitions(environment), reached, counter, stride, step)
    updated : BoundaryProgress <- solve_scheduled_boundaries(boundary_definition_changed(scheduled), Specialization{module, G.Environment{G.env_bindings(environment), boundary_definition_values(scheduled), G.env_state(environment)}, choices, boundary_definition_next(scheduled), certificates}, configuration, shapes, schemes)
    return updated

def schedule_if_present(present: Bool, specialized: Specialization, configuration: Configuration, shapes: List<&2, I.Binding>, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, BoundaryProgress>:
  match present:
    case False{}:
      Done{BoundaryProgress{specialized, False{}}}
    case True{}:
      schedule_present_boundaries_work(specialized, configuration, shapes, schemes)

def schedule_reached_boundaries(+specialized: Specialization, configuration: Configuration, shapes: List<&2, I.Binding>, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, BoundaryProgress>:
  Specialization{module, environment, choices, counter, certificates} = specialized
  schedule_if_present(has_boundary_definition(G.env_definitions(environment)), specialized, configuration, shapes, schemes)

type BoundaryLoop is Data:
  CheckBoundaries{specialization: Specialization, changed: Bool}
  ContinueBoundaries{progress: BoundaryProgress, changed: Bool}

def schedule_boundaries(fuel: Nat, work: BoundaryLoop, +configuration: Configuration, +shapes: List<&2, I.Binding>, +schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, BoundaryProgress>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"specialization_limit", "qualified boundary", "qualified boundary fixed point exceeded its limit"}}
    case 1n+rest CheckBoundaries{specialized, changed}:
      do Result<&2, &2, M.Diagnostic, BoundaryProgress>:
        progress : BoundaryProgress <- schedule_reached_boundaries(specialized, configuration, shapes, schemes)
        schedule_boundaries(rest, ContinueBoundaries{progress, changed}, configuration, shapes, schemes)
    case 1n+rest ContinueBoundaries{BoundaryProgress{next, False{}}, changed}:
      Done{BoundaryProgress{next, changed}}
    case 1n+rest ContinueBoundaries{BoundaryProgress{next, True{}}, changed}:
      schedule_boundaries(rest, CheckBoundaries{next, True{}}, configuration, shapes, schemes)

# A selected signature may retain a flexible effect tail after all dispatches
# have been chosen. Close only tails belonging to reached, concrete uses;
# interface inputs, returned values, quantified schemes, and explicit
# boundaries retain their own row variables.
def signature_rows_work(fuel: Nat, pending: List<&2, M.Ty>, +found: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match fuel pending:
    case 0n _:
      Fail{M.Diagnostic{"type_complexity", "effects", "selected signature is too complex"}}
    case 1n+rest Nil{}:
      Done{found}
    case 1n+rest M.FunctionTy{parameter, result, effects} <> tail:
      signature_rows_work(rest, parameter <> result <> tail, T.union(T.row_free(effects), found))
    case 1n+rest M.ProviderTy{identity, effects} <> tail:
      signature_rows_work(rest, tail, T.union(T.row_free(effects), found))
    case 1n+rest M.StateProviderTy{read, write, state} <> tail:
      signature_rows_work(rest, state <> tail, found)
    case 1n+rest M.AppliedTy{identity, arguments} <> tail:
      signature_rows_work(rest, List.append(&2, M.Ty, arguments, tail), found)
    case 1n+rest M.ProductTy{elements} <> tail:
      signature_rows_work(rest, List.append(&2, M.Ty, elements, tail), found)
    case 1n+rest M.ArrayTy{element} <> tail:
      signature_rows_work(rest, element <> tail, found)
    case 1n+rest head <> tail:
      signature_rows_work(rest, tail, found)

def signature_rows(ty: M.Ty) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  signature_rows_work(65536n, [ty], Nil{})

def selected_evidence_types(answers: List<&2, C.EvidenceAnswer>) -> List<&2, M.Ty>:
  match answers:
    case Nil{}:
      Nil{}
    case C.EvidenceAnswer{predicate, C.SelectedFunction{name, signature}} <> tail:
      signature <> selected_evidence_types(tail)
    case C.EvidenceAnswer{predicate, C.SelectedField{owner, member, accessor, signature}} <> tail:
      signature <> selected_evidence_types(tail)
    case C.EvidenceAnswer{predicate, C.SelectedOperation{identity, signature}} <> tail:
      signature <> selected_evidence_types(tail)
    case head <> tail:
      selected_evidence_types(tail)

def selected_choice_types(found: Maybe<&2, Choice>) -> List<&2, M.Ty>:
  match found:
    case Some{FunctionChoice{name, signature}}:
      [signature]
    case Some{ReceiverChoice{name, signature}}:
      [signature]
    case Some{OperationChoice{identity, signature}}:
      [signature]
    case Some{QualifiedChoice{solved, answers}}:
      selected_evidence_types(answers)
    case None{}:
      Nil{}

def selected_need_types(needs: List<&2, I.Coverage>, +choices: Map<&2, Choice>) -> List<&2, M.Ty>:
  match needs:
    case Nil{}:
      Nil{}
    case I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, subject} <> tail:
      List.append(&2, M.Ty, selected_choice_types(choice(choices, identity)), selected_need_types(tail, choices))
    case I.QualifiedNeed{site, predicate, subject} <> tail:
      List.append(&2, M.Ty, selected_choice_types(qualified_choice(choices, site)), selected_need_types(tail, choices))
    case head <> tail:
      selected_need_types(tail, choices)

def reached_selected_one(reached: Bool, coverage: List<&2, I.Coverage>, uses: List<&2, C.UsePlan>, choices: Map<&2, Choice>) -> List<&2, M.Ty>:
  match reached:
    case False{}:
      Nil{}
    case True{}:
      selected_need_types(List.append(&2, I.Coverage, coverage, I.execution_needs(uses)), choices)

def reached_selected_types(definitions: List<&2, I.Definition>, +reached: Set(), +choices: Map<&2, Choice>) -> List<&2, M.Ty>:
  match definitions:
    case Nil{}:
      Nil{}
    case I.Definition{+name, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail:
      +rest = reached_selected_types(tail, reached, choices)
      List.append(&2, M.Ty, reached_selected_one(D.member(reached, name), coverage, uses, choices), rest)

def resolved_signature_row_groups(types: List<&2, M.Ty>, +substitutions: T.Substitutions, reversed: List<&2, List<&2, Nat>>) -> Result<&2, &2, M.Diagnostic, List<&2, List<&2, Nat>>>:
  match types:
    case Nil{}:
      Done{reversed}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, List<&2, Nat>>>:
        resolved : M.Ty <- T.resolve(substitutions, head)
        first : List<&2, Nat> <- signature_rows(resolved)
        resolved_signature_row_groups(tail, substitutions, first <> reversed)

def resolved_signature_row_union(reversed: List<&2, List<&2, Nat>>, accumulated: List<&2, Nat>) -> List<&2, Nat>:
  match reversed:
    case Nil{}:
      accumulated
    case first <> tail:
      resolved_signature_row_union(tail, T.union(first, accumulated))

def resolved_signature_rows(types: List<&2, M.Ty>, substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
    groups : List<&2, List<&2, Nat>> <- resolved_signature_row_groups(types, substitutions, Nil{})
    return resolved_signature_row_union(groups, Nil{})

def reached_definition_names(definitions: List<&2, I.Definition>, +reached: Set()) -> List<&2, String>:
  match definitions:
    case Nil{}:
      Nil{}
    case I.Definition{+name, inference} <> tail:
      +rest = reached_definition_names(tail, reached)
      Bool.pick(List<&2, String>, D.member(reached, name), name <> rest, rest)

def scheme_quantifiers(bindings: List<&2, I.Binding>) -> List<&2, Nat>:
  match bindings:
    case Nil{}:
      Nil{}
    case I.Binding{name, ty, variables, predicates} <> tail:
      T.union(variables, scheme_quantifiers(tail))

def external_fixed_one(owned: Bool, binding: I.Binding, substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match owned:
    case True{}:
      Done{Nil{}}
    case False{}:
      I.binding_free([binding], substitutions)

def external_fixed_rows(bindings: List<&2, I.Binding>, +owned: List<&2, String>, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match bindings:
    case Nil{}:
      Done{Nil{}}
    case +binding <> tail:
      I.Binding{+name, ty, variables, predicates} = binding
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        first : List<&2, Nat> <- external_fixed_one(D.contains(owned, name), binding, substitutions)
        rest : List<&2, Nat> <- external_fixed_rows(tail, owned, substitutions)
        return T.union(first, rest)

def boundary_fixed_rows(needs: List<&2, I.Coverage>, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match needs:
    case Nil{}:
      Done{Nil{}}
    case I.QualifiedNeed{site, predicate, subject} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        resolved : M.Predicate <- C.resolve(substitutions, predicate)
        first : List<&2, Nat> <- C.free(resolved)
        rest : List<&2, Nat> <- boundary_fixed_rows(tail, substitutions)
        return T.union(first, rest)
    case I.QualifiedBoundary{offset, declared, subject} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        resolved : List<&2, M.Predicate> <- C.resolve_list(substitutions, declared)
        first : List<&2, Nat> <- C.free_list(resolved)
        rest : List<&2, Nat> <- boundary_fixed_rows(tail, substitutions)
        return T.union(first, rest)
    case I.LetGeneralized{witness} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        resolved : M.Ty <- T.resolve(substitutions, witness)
        first : List<&2, Nat> <- T.free(resolved)
        rest : List<&2, Nat> <- boundary_fixed_rows(tail, substitutions)
        return T.union(first, rest)
    case head <> tail:
      boundary_fixed_rows(tail, substitutions)

def visible_interface_type(ty: M.Ty) -> M.Ty:
  match ty:
    case M.FunctionTy{parameter, result, effects}:
      M.ProductTy{[parameter, result]}
    case other:
      other

def reached_interface_one(reached: Bool, ty: M.Ty, coverage: List<&2, I.Coverage>, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match reached:
    case False{}:
      Done{Nil{}}
    case True{}:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        resolved : M.Ty <- T.resolve(substitutions, ty)
        inputs : List<&2, Nat> <- signature_rows(visible_interface_type(resolved))
        boundary : List<&2, Nat> <- boundary_fixed_rows(coverage, substitutions)
        return T.union(inputs, boundary)

def reached_interface_rows(definitions: List<&2, I.Definition>, +reached: Set(), +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match definitions:
    case Nil{}:
      Done{Nil{}}
    case I.Definition{+name, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        first : List<&2, Nat> <- reached_interface_one(D.member(reached, name), ty, coverage, substitutions)
        rest : List<&2, Nat> <- reached_interface_rows(tail, reached, substitutions)
        return T.union(first, rest)

def close_selected_one(protected: Bool, index: Nat, state: I.State) -> Result<&2, &2, M.Diagnostic, I.State>:
  match protected:
    case True{}:
      Done{state}
    case False{}:
      I.unify_rows(Rows.variable_row(index), M.empty_row(), state, "selected invocation")

def close_selected_rows(candidates: List<&2, Nat>, +fixed: List<&2, Nat>, state: I.State) -> Result<&2, &2, M.Diagnostic, I.State>:
  match candidates:
    case Nil{}:
      Done{state}
    case +index <> tail:
      do Result<&2, &2, M.Diagnostic, I.State>:
        next : I.State <- close_selected_one(T.contains(fixed, index), index, state)
        close_selected_rows(tail, fixed, next)

def relink_qualified_evidence(predicate: M.Predicate, evidence: C.Evidence, +state: I.State, subject: String) -> Result<&2, &2, M.Diagnostic, I.State>:
  match predicate evidence:
    case M.AssociatedPredicate{member, templates, left, right, result, invocation} C.SelectedFunction{name, signature}:
      do Result<&2, &2, M.Diagnostic, I.State>:
        ty : M.Ty <- T.resolve(I.substitutions_of(state), signature)
        row : Maybe<&2, M.EffectRow> <- selected_binary_invocation(ty)
        unify_selected_invocation(row, invocation, state, subject)
    case M.UpdatePredicate{member, receiver, assigned, result, invocation} C.SelectedField{owner, field, accessor, signature}:
      do Result<&2, &2, M.Diagnostic, I.State>:
        ty : M.Ty <- T.resolve(I.substitutions_of(state), signature)
        row : Maybe<&2, M.EffectRow> <- selected_binary_invocation(ty)
        unify_selected_invocation(row, invocation, state, subject)
    case M.ReceiverPredicate{member, templates, receiver, argument, result, invocation} C.SelectedFunction{name, signature}:
      do Result<&2, &2, M.Diagnostic, I.State>:
        ty : M.Ty <- T.resolve(I.substitutions_of(state), signature)
        row : Maybe<&2, M.EffectRow> <- selected_receiver_invocation(ty)
        unify_selected_invocation(row, invocation, state, subject)
    case M.ReceiverPredicate{member, templates, receiver, argument, result, invocation} C.SelectedField{owner, field, accessor, signature}:
      do Result<&2, &2, M.Diagnostic, I.State>:
        ty : M.Ty <- T.resolve(I.substitutions_of(state), signature)
        row : Maybe<&2, M.EffectRow> <- selected_receiver_invocation(ty)
        unify_selected_invocation(row, invocation, state, subject)
    case _ _:
      Done{state}

def relink_qualified_answers(answers: List<&2, C.EvidenceAnswer>, state: I.State, +subject: String) -> Result<&2, &2, M.Diagnostic, I.State>:
  match answers:
    case Nil{}:
      Done{state}
    case C.EvidenceAnswer{predicate, evidence} <> tail:
      do Result<&2, &2, M.Diagnostic, I.State>:
        next : I.State <- relink_qualified_evidence(predicate, evidence, state, subject)
        relink_qualified_answers(tail, next, subject)

def relink_selected_needs(needs: List<&2, I.Coverage>, +choices: Map<&2, Choice>, +state: I.State) -> Result<&2, &2, M.Diagnostic, I.State>:
  match needs:
    case Nil{}:
      Done{state}
    case I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, Some{invocation}, ambient, subject} <> tail:
      do Result<&2, &2, M.Diagnostic, I.State>:
        row : Maybe<&2, M.EffectRow> <- resolved_selected_invocation(choice(choices, identity), I.substitutions_of(state), associated_binary(dispatch))
        next : I.State <- unify_selected_invocation(row, invocation, state, subject)
        relink_selected_needs(tail, choices, next)
    case I.QualifiedNeed{site, predicate, subject} <> tail:
      do Result<&2, &2, M.Diagnostic, I.State>:
        next : I.State <- relink_qualified_answers(qualified_answers(qualified_choice(choices, site)), state, subject)
        relink_selected_needs(tail, choices, next)
    case head <> tail:
      relink_selected_needs(tail, choices, state)

def relink_if_reached(reached: Bool, needs: List<&2, I.Coverage>, choices: Map<&2, Choice>, state: I.State) -> Result<&2, &2, M.Diagnostic, I.State>:
  match reached:
    case False{}:
      Done{state}
    case True{}:
      relink_selected_needs(needs, choices, state)

def relink_reached_definitions(definitions: List<&2, I.Definition>, +reached: Set(), +choices: Map<&2, Choice>, state: I.State) -> Result<&2, &2, M.Diagnostic, I.State>:
  match definitions:
    case Nil{}:
      Done{state}
    case I.Definition{+name, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail:
      do Result<&2, &2, M.Diagnostic, I.State>:
        next : I.State <- relink_if_reached(D.member(reached, name), List.append(&2, I.Coverage, coverage, I.execution_needs(uses)), choices, state)
        relink_reached_definitions(tail, reached, choices, next)

# A source-checked member can return a closure whose row is shared with its
# outer arrow. Generalization correctly leaves that row open. This proof
# narrows only that exact empty-prefix row, never a row within the receiver,
# argument, or result. Other free IDs in those types must survive unchanged.
def recheckable_member_ground(found: Result<&2, &2, M.Diagnostic, List<&2, Nat>>, inner: Nat, outer: Nat, +index: Nat) -> Bool:
  match found:
    case Done{free}:
      Bool.and(Bool.not(T.contains(free, index)), Bool.and(Nat.is_eq(inner, index), Nat.is_eq(outer, index)))
    case _:
      False{}

def recheckable_member_signature(ty: M.Ty, +index: Nat) -> Bool:
  match ty:
    case M.FunctionTy{parameter, M.FunctionTy{argument, result, M.EffectRow{Nil{}, M.RowVariable{inner}}}, M.EffectRow{Nil{}, M.RowVariable{outer}}}:
      recheckable_member_ground(T.free(M.ProductTy{[parameter, argument, result]}), inner, outer, index)
    case _:
      False{}

# Keep the previous candidate as an argument so the match is decided before
# visiting the next definition. Bool.pick evaluates both alternatives in JS.
def member_target_definition_work(definitions: List<&2, I.Definition>, matched: Bool, found: Maybe<&2, M.Ty>, +name: String) -> Maybe<&2, M.Ty>:
  match definitions matched:
    case _ True{}:
      found
    case Nil{} False{}:
      None{}
    case I.Definition{candidate, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail False{}:
      member_target_definition_work(tail, M.name_equal(candidate, name), Some{ty}, name)

def member_target_definition(definitions: List<&2, I.Definition>, name: String) -> Maybe<&2, M.Ty>:
  member_target_definition_work(definitions, False{}, None{}, name)

def member_target_free(found: Result<&2, &2, M.Diagnostic, List<&2, Nat>>, index: Nat) -> Bool:
  match found:
    case Done{free}:
      T.contains(free, index)
    case Fail{diagnostic}:
      False{}

def member_target_resolved(found: Result<&2, &2, M.Diagnostic, M.Ty>, index: Nat) -> Bool:
  match found:
    case Done{resolved}:
      member_target_free(T.free(resolved), index)
    case Fail{diagnostic}:
      False{}

def member_target_found(found: Maybe<&2, M.Ty>, substitutions: T.Substitutions, index: Nat) -> Bool:
  match found:
    case Some{ty}:
      member_target_resolved(T.resolve(substitutions, ty), index)
    case None{}:
      False{}

def member_target_affected(definitions: List<&2, I.Definition>, name: String, index: Nat, substitutions: T.Substitutions) -> Bool:
  member_target_found(member_target_definition(definitions, name), substitutions, index)

def binding_row_free(found: Result<&2, &2, M.Diagnostic, List<&2, Nat>>, name: String, +index: Nat, definitions: List<&2, I.Definition>, substitutions: T.Substitutions) -> Bool:
  match found:
    case Fail{diagnostic}:
      False{}
    case Done{free}:
      Bool.or(Bool.not(T.contains(free, index)), member_target_affected(definitions, name, index, substitutions))

def binding_row_accounted(found: Result<&2, &2, M.Diagnostic, M.Ty>, name: String, +index: Nat, definitions: List<&2, I.Definition>, substitutions: T.Substitutions) -> Bool:
  match found:
    case Fail{diagnostic}:
      False{}
    case Done{ty}:
      binding_row_free(T.free(ty), name, index, definitions, substitutions)

def member_binding_accounted(owned: Bool, ty: M.Ty, name: String, index: Nat, definitions: List<&2, I.Definition>, +substitutions: T.Substitutions, rest: Bool) -> Bool:
  match owned:
    case False{}:
      rest
    case True{}:
      Bool.and(binding_row_accounted(T.resolve(substitutions, ty), name, index, definitions, substitutions), rest)

def all_member_bindings_accounted(bindings: List<&2, I.Binding>, +owned: List<&2, String>, +index: Nat, +definitions: List<&2, I.Definition>, +substitutions: T.Substitutions) -> Bool:
  match bindings:
    case Nil{}:
      True{}
    case I.Binding{+name, ty, variables, predicates} <> tail:
      +rest = all_member_bindings_accounted(tail, owned, index, definitions, substitutions)
      member_binding_accounted(D.contains(owned, name), ty, name, index, definitions, substitutions, rest)

def resolved_recheckable_member(found: Result<&2, &2, M.Diagnostic, M.Ty>, +name: String, +index: Nat, owned: List<&2, String>, definitions: List<&2, I.Definition>, substitutions: T.Substitutions) -> Bool:
  match found:
    case Done{ty}:
      Bool.and(Bool.and(D.contains(owned, name), member_target_affected(definitions, name, index, substitutions)), recheckable_member_signature(ty, index))
    case Fail{diagnostic}:
      False{}

def recheckable_member_answers_work(answers: List<&2, C.EvidenceAnswer>, matched: Bool, +substitutions: T.Substitutions, +index: Nat, +owned: List<&2, String>, +definitions: List<&2, I.Definition>) -> Bool:
  match answers matched:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case C.EvidenceAnswer{M.ReceiverPredicate{member, templates, receiver, argument, result, invocation}, C.SelectedFunction{name, signature}} <> tail False{}:
      +matching = resolved_recheckable_member(T.resolve(substitutions, signature), name, index, owned, definitions, substitutions)
      recheckable_member_answers_work(tail, matching, substitutions, index, owned, definitions)
    case head <> tail False{}:
      recheckable_member_answers_work(tail, False{}, substitutions, index, owned, definitions)

def recheckable_member_answers(answers: List<&2, C.EvidenceAnswer>, substitutions: T.Substitutions, index: Nat, owned: List<&2, String>, definitions: List<&2, I.Definition>) -> Bool:
  recheckable_member_answers_work(answers, False{}, substitutions, index, owned, definitions)

def recheckable_member_choices(pending: List<&2, Choice>, +substitutions: T.Substitutions, +index: Nat, +owned: List<&2, String>, +definitions: List<&2, I.Definition>) -> Bool:
  match pending:
    case Nil{}:
      False{}
    case QualifiedChoice{solved, answers} <> tail:
      Bool.or(recheckable_member_answers(answers, substitutions, index, owned, definitions), recheckable_member_choices(tail, substitutions, index, owned, definitions))
    case FunctionChoice{name, signature} <> tail:
      +matching = resolved_recheckable_member(T.resolve(substitutions, signature), name, index, owned, definitions, substitutions)
      Bool.or(matching, recheckable_member_choices(tail, substitutions, index, owned, definitions))
    case head <> tail:
      recheckable_member_choices(tail, substitutions, index, owned, definitions)

def reached_input_one(reached: Bool, ty: M.Ty, coverage: List<&2, I.Coverage>, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match reached:
    case False{}:
      Done{Nil{}}
    case True{}:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        resolved : M.Ty <- T.resolve(substitutions, ty)
        inputs : List<&2, Nat> <- T.covariant_inputs(65536n, T.OneType{resolved})
        boundary : List<&2, Nat> <- boundary_fixed_rows(coverage, substitutions)
        return T.union(inputs, boundary)

def reached_input_rows(definitions: List<&2, I.Definition>, +reached: Set(), +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match definitions:
    case Nil{}:
      Done{Nil{}}
    case I.Definition{+name, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        first : List<&2, Nat> <- reached_input_one(D.member(reached, name), ty, coverage, substitutions)
        rest : List<&2, Nat> <- reached_input_rows(tail, reached, substitutions)
        return T.union(first, rest)

def rechecked_member_binding(original: Maybe<&2, I.Binding>, fresh: Maybe<&2, I.Binding>, +expected: M.Ty, +after: T.Substitutions, state: I.State, +subject: String) -> Result<&2, &2, M.Diagnostic, I.State>:
  match original fresh:
    case Some{I.Binding{name, ty, Nil{}, Nil{}}} Some{I.Binding{fresh_name, +inferred, variables, predicates}}:
      do Result<&2, &2, M.Diagnostic, I.State>:
        +signature : M.Ty <- T.resolve(after, ty)
        checked : I.State <- I.unify(inferred, signature, state, subject)
        I.unify(inferred, expected, checked, subject)
    case _ _:
      Fail{M.Diagnostic{"ambiguous_qualified", subject, "selected member has no unqualified body signature for recheck"}}

def recheck_affected_one(affected: Bool, ty: M.Ty, +name: String, original: List<&2, I.Binding>, +after: T.Substitutions, fresh: List<&2, I.Binding>, state: I.State) -> Result<&2, &2, M.Diagnostic, I.State>:
  match affected:
    case False{}:
      Done{state}
    case True{}:
      do Result<&2, &2, M.Diagnostic, I.State>:
        expected : M.Ty <- T.resolve(after, ty)
        rechecked_member_binding(I.lookup_binding(original, name), I.lookup_binding(fresh, name), expected, after, state, name)

# The trial must account for every generated declaration linked to the row,
# including other clones of the same method and its caller. One checked target
# alone would not justify closing a row shared across the inference component.
def recheck_affected_member(definitions: List<&2, I.Definition>, +owned: List<&2, String>, +index: Nat, +original: List<&2, I.Binding>, +before: T.Substitutions, +after: T.Substitutions, +fresh: List<&2, I.Binding>, state: I.State, seen: Bool) -> Result<&2, &2, M.Diagnostic, I.State>:
  match definitions:
    case Nil{}:
      match seen:
        case True{}:
          Done{state}
        case False{}:
          Fail{M.Diagnostic{"ambiguous_qualified", "selected member", "no generated body owns the selected effect row"}}
    case I.Definition{+name, I.Inference{+ty, coverage, exits, reflections, predicates, uses}} <> tail:
      do Result<&2, &2, M.Diagnostic, I.State>:
        resolved : M.Ty <- T.resolve(before, ty)
        free : List<&2, Nat> <- T.free(resolved)
        +affected : Bool = Bool.and(D.contains(owned, name), T.contains(free, index))
        next : I.State <- recheck_affected_one(affected, ty, name, original, after, fresh, state)
        recheck_affected_member(tail, owned, index, original, before, after, fresh, next, Bool.or(seen, affected))

def member_definition_count_work(definitions: List<&2, I.Definition>, +wanted: String, count: Nat) -> Nat:
  match definitions:
    case Nil{}:
      count
    case I.Definition{name, inference} <> tail:
      member_definition_count_work(tail, wanted, Nat.add(Bool.pick(Nat, M.name_equal(name, wanted), 1n, 0n), count))

def member_definition_count(definitions: List<&2, I.Definition>, wanted: String) -> Nat:
  member_definition_count_work(definitions, wanted, 0n)

def member_preserved(found: Result<&2, &2, M.Diagnostic, M.Ty>, +snapshot: M.Ty, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match found:
    case Fail{diagnostic}:
      Fail{diagnostic}
    case Done{resolved}:
      Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, Compare.same_ty(snapshot, resolved), Done{Unit{}}, Fail{M.Diagnostic{"ambiguous_qualified", subject, "body recheck constrained a retained full signature"}})

def checked_member_certificate(found: Maybe<&2, I.Binding>, +name: String, +definition: M.Ty, +after: T.Substitutions, +narrowed: T.Substitutions) -> Result<&2, &2, M.Diagnostic, MemberEvidenceCertificate>:
  match found:
    case Some{I.Binding{found_name, binding, Nil{}, Nil{}}}:
      do Result<&2, &2, M.Diagnostic, MemberEvidenceCertificate>:
        +signature : M.Ty <- T.resolve(after, binding)
        +expected : M.Ty <- T.resolve(after, definition)
        binding_preserved : Unit <- member_preserved(T.resolve(narrowed, signature), signature, name)
        definition_preserved : Unit <- member_preserved(T.resolve(narrowed, expected), expected, name)
        +exact : Bool = Bool.and(M.name_equal(found_name, name), Compare.same_ty(signature, expected))
        valid : Unit <- Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, exact, Done{Unit{}}, Fail{M.Diagnostic{"ambiguous_qualified", name, "checked binding and definition have different full signatures"}})
        return MemberEvidenceCertificate{name, signature}
    case _:
      Fail{M.Diagnostic{"ambiguous_qualified", name, "checked member lacks a unique unqualified original binding"}}

def member_affected_free(found: Result<&2, &2, M.Diagnostic, List<&2, Nat>>, owned: Bool, index: Nat) -> Bool:
  match found:
    case Done{free}:
      Bool.and(owned, T.contains(free, index))
    case Fail{diagnostic}:
      False{}

def member_affected_type(found: Result<&2, &2, M.Diagnostic, M.Ty>, owned: Bool, index: Nat) -> Bool:
  match found:
    case Done{resolved}:
      member_affected_free(T.free(resolved), owned, index)
    case Fail{diagnostic}:
      False{}

def maybe_member_certificate(affected: Bool, +name: String, +ty: M.Ty, +definitions: List<&2, I.Definition>, +original: List<&2, I.Binding>, +after: T.Substitutions, +narrowed: T.Substitutions, rest: List<&2, MemberEvidenceCertificate>) -> Result<&2, &2, M.Diagnostic, List<&2, MemberEvidenceCertificate>>:
  match affected:
    case False{}:
      Done{rest}
    case True{}:
      do Result<&2, &2, M.Diagnostic, List<&2, MemberEvidenceCertificate>>:
        unique : Unit <- Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, Bool.and(Nat.is_eq(member_definition_count(definitions, name), 1n), Nat.is_eq(scoped_binding_count(original, name), 1n)), Done{Unit{}}, Fail{M.Diagnostic{"ambiguous_qualified", name, "checked member identity is not unique"}})
        first : MemberEvidenceCertificate <- checked_member_certificate(I.lookup_binding(original, name), name, ty, after, narrowed)
        return first <> rest

def member_certificates_work(pending: List<&2, I.Definition>, +all: List<&2, I.Definition>, +owned: List<&2, String>, +index: Nat, +original: List<&2, I.Binding>, +before: T.Substitutions, +after: T.Substitutions, +narrowed: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, MemberEvidenceCertificate>>:
  match pending:
    case Nil{}:
      Done{Nil{}}
    case I.Definition{+name, I.Inference{+ty, coverage, exits, reflections, predicates, uses}} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, MemberEvidenceCertificate>>:
        rest : List<&2, MemberEvidenceCertificate> <- member_certificates_work(tail, all, owned, index, original, before, after, narrowed)
        +affected : Bool = member_affected_type(T.resolve(before, ty), D.contains(owned, name), index)
        maybe_member_certificate(affected, name, ty, all, original, after, narrowed, rest)

# Project generated declarations before entering the Result block; Bend does
# not destructure an already computed do-block binding.
def member_trial_declarations(prepared: M.Module) -> List<&2, G.Declaration>:
  match prepared:
    case M.Module{constants, functions, types, operations}:
      List.append(&2, G.Declaration, G.function_declarations(functions), G.constant_declarations(constants))

def member_trial_types(prepared: M.Module) -> List<&2, M.DataType>:
  match prepared:
    case M.Module{constants, functions, types, operations}:
      types

# The normal finalizer has already resolved every choice. Materialize those
# exact choices, infer the complete emitted core afresh, and check all affected
# full signatures under a single narrowed row. This is a bounded proof probe:
# its failure leaves the original state and strict evidence diagnostic intact.
def prove_member_row(+index: Nat, +module: M.Module, +environment: G.Environment, +choices: Map<&2, Choice>, +counter: Nat, +certificates: List<&2, Core.Certificate>, +external_functions: List<&2, String>) -> Result<&2, &2, M.Diagnostic, MemberRowProof>:
  M.Module{constants, functions, types, operations} = module
  +owned = G.names(List.append(&2, G.Declaration, G.function_declarations(functions), G.constant_declarations(constants)))
  +before = I.substitutions_of(G.env_state(environment))
  +outside = without_interface_bindings(G.env_bindings(environment), owned)
  +imported : G.Environment = G.Environment{outside, Nil{}, G.env_state(environment)}
  do Result<&2, &2, M.Diagnostic, MemberRowProof>:
    accounted : Unit <- Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, all_member_bindings_accounted(G.env_bindings(environment), owned, index, G.env_definitions(environment), before), Done{Unit{}}, Fail{M.Diagnostic{"ambiguous_qualified", "selected member", "selected row has an unverified generated binding"}})
    +trial : I.State <- I.unify_rows(Rows.variable_row(index), M.empty_row(), G.env_state(environment), "selected member")
    +prepared : M.Module <- finish(Specialization{module, environment, choices, counter, certificates})
    declarations : List<&2, G.Declaration> = member_trial_declarations(prepared)
    graph : List<&2, D.Node> <- Check.module_graph(prepared)
    +fresh : G.Environment <- G.infer_with(declarations, graph, M.module_operations(prepared), member_trial_types(prepared), imported, external_functions)
    +narrowed : I.State <- recheck_affected_member(G.env_definitions(environment), owned, index, G.env_bindings(environment), before, I.substitutions_of(trial), G.env_bindings(fresh), G.env_state(fresh), False{})
    checked : M.CheckedModule <- Check.finish(prepared, G.Environment{G.env_bindings(fresh), G.env_definitions(fresh), narrowed})
    +certified : List<&2, MemberEvidenceCertificate> <- member_certificates_work(G.env_definitions(environment), G.env_definitions(environment), owned, index, G.env_bindings(environment), before, I.substitutions_of(trial), I.substitutions_of(narrowed))
    return MemberRowProof{trial, certified}

def first_recheckable_member_work(candidates: List<&2, Nat>, matched: Bool, found: Maybe<&2, Nat>, +fixed: List<&2, Nat>, +hard_fixed: List<&2, Nat>, +owned: List<&2, String>, +pending: List<&2, Choice>, +substitutions: T.Substitutions, +definitions: List<&2, I.Definition>) -> Maybe<&2, Nat>:
  match candidates matched:
    case _ True{}:
      found
    case Nil{} False{}:
      None{}
    case +index <> tail False{}:
      eligible : Bool = Bool.and(Bool.and(T.contains(fixed, index), Bool.not(T.contains(hard_fixed, index))), recheckable_member_choices(pending, substitutions, index, owned, definitions))
      first_recheckable_member_work(tail, eligible, Some{index}, fixed, hard_fixed, owned, pending, substitutions, definitions)

def first_recheckable_member(candidates: List<&2, Nat>, fixed: List<&2, Nat>, hard_fixed: List<&2, Nat>, owned: List<&2, String>, pending: List<&2, Choice>, substitutions: T.Substitutions, definitions: List<&2, I.Definition>) -> Maybe<&2, Nat>:
  first_recheckable_member_work(candidates, False{}, None{}, fixed, hard_fixed, owned, pending, substitutions, definitions)

def member_row_trial(found: Result<&2, &2, M.Diagnostic, MemberRowProof>, fallback: I.State) -> MemberRowProof:
  match found:
    case Done{proven}:
      proven
    case Fail{diagnostic}:
      MemberRowProof{fallback, Nil{}}

def member_row_selected(found: Maybe<&2, Nat>, +module: M.Module, +environment: G.Environment, +choices: Map<&2, Choice>, counter: Nat, +certificates: List<&2, Core.Certificate>, +external_functions: List<&2, String>, +state: I.State) -> MemberRowProof:
  match found:
    case None{}:
      MemberRowProof{state, Nil{}}
    case Some{index}:
      member_row_trial(prove_member_row(index, module, G.Environment{G.env_bindings(environment), G.env_definitions(environment), state}, choices, counter, certificates, external_functions), state)

def prove_one_member_row(candidates: List<&2, Nat>, +fixed: List<&2, Nat>, +hard_fixed: List<&2, Nat>, +module: M.Module, +environment: G.Environment, +choices: Map<&2, Choice>, +counter: Nat, +certificates: List<&2, Core.Certificate>, +external_functions: List<&2, String>, +state: I.State) -> MemberRowProof:
  +owned : List<&2, String> = G.names(member_trial_declarations(module))
  +definitions : List<&2, I.Definition> = G.env_definitions(environment)
  +pending : List<&2, Choice> = Map.values(&2, Choice, choices)
  +substitutions : T.Substitutions = I.substitutions_of(state)
  member_row_selected(first_recheckable_member(candidates, fixed, hard_fixed, owned, pending, substitutions, definitions), module, environment, choices, counter, certificates, external_functions, state)

def protected_selected_rows(candidates: List<&2, Nat>, +fixed: List<&2, Nat>) -> List<&2, Nat>:
  match candidates:
    case Nil{}:
      Nil{}
    case +index <> tail:
      +rest = protected_selected_rows(tail, fixed)
      Bool.pick(List<&2, Nat>, T.contains(fixed, index), index <> rest, rest)

def prove_protected_member_rows_pending(pending: List<&2, Nat>, +fixed: List<&2, Nat>, +reached: Set(), +module: M.Module, +environment: G.Environment, +choices: Map<&2, Choice>, +counter: Nat, +certificates: List<&2, Core.Certificate>, +external_functions: List<&2, String>, +state: I.State) -> Result<&2, &2, M.Diagnostic, MemberRowProof>:
  match pending:
    case Nil{}:
      Done{MemberRowProof{state, Nil{}}}
    case pending:
      +definitions = G.env_definitions(environment)
      +bindings = G.env_bindings(environment)
      +substitutions = I.substitutions_of(state)
      +owned = G.names(member_trial_declarations(module))
      do Result<&2, &2, M.Diagnostic, MemberRowProof>:
        inputs : List<&2, Nat> <- reached_input_rows(definitions, reached, substitutions)
        external : List<&2, Nat> <- external_fixed_rows(bindings, owned, substitutions)
        +hard_fixed : List<&2, Nat> = T.union(scheme_quantifiers(bindings), T.union(inputs, external))
        return prove_one_member_row(pending, fixed, hard_fixed, module, environment, choices, counter, certificates, external_functions, state)

def prove_protected_member_rows(candidates: List<&2, Nat>, +fixed: List<&2, Nat>, +reached: Set(), +module: M.Module, +environment: G.Environment, +choices: Map<&2, Choice>, +counter: Nat, +certificates: List<&2, Core.Certificate>, +external_functions: List<&2, String>, +state: I.State) -> Result<&2, &2, M.Diagnostic, MemberRowProof>:
  prove_protected_member_rows_pending(protected_selected_rows(candidates, fixed), fixed, reached, module, environment, choices, counter, certificates, external_functions, state)

def member_proof_state(proof: MemberRowProof) -> I.State:
  match proof:
    case MemberRowProof{state, certified}:
      state

def member_proof_certified(proof: MemberRowProof) -> List<&2, MemberEvidenceCertificate>:
  match proof:
    case MemberRowProof{state, certified}:
      certified

def finalize_with_selected_rows(candidates: List<&2, Nat>, +reached: Set(), +module: M.Module, +environment: G.Environment, +choices: Map<&2, Choice>, +counter: Nat, +certificates: List<&2, Core.Certificate>, +external_functions: List<&2, String>) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match candidates:
    case Nil{}:
      +definitions = G.env_definitions(environment)
      +bindings = G.env_bindings(environment)
      +substitutions = I.substitutions_of(G.env_state(environment))
      do Result<&2, &2, M.Diagnostic, Specialization>:
        +linked : I.State <- relink_reached_definitions(definitions, reached, choices, G.env_state(environment))
        answers : Map<&2, Choice> <- finalize_evidence_certified(module, G.Environment{bindings, definitions, linked}, choices, Nil{})
        return Specialization{module, G.Environment{bindings, definitions, linked}, answers, counter, certificates}
    case +pending_rows:
      +definitions = G.env_definitions(environment)
      +bindings = G.env_bindings(environment)
      +substitutions = I.substitutions_of(G.env_state(environment))
      do Result<&2, &2, M.Diagnostic, Specialization>:
        interfaces : List<&2, Nat> <- reached_interface_rows(definitions, reached, substitutions)
        external : List<&2, Nat> <- external_fixed_rows(bindings, reached_definition_names(definitions, reached), substitutions)
        +fixed : List<&2, Nat> = T.union(scheme_quantifiers(bindings), T.union(interfaces, external))
        closed : I.State <- close_selected_rows(pending_rows, fixed, G.env_state(environment))
        +proof : MemberRowProof <- prove_protected_member_rows(pending_rows, fixed, reached, module, environment, choices, counter, certificates, external_functions, closed)
        +linked : I.State <- relink_reached_definitions(definitions, reached, choices, member_proof_state(proof))
        answers : Map<&2, Choice> <- finalize_evidence_certified(module, G.Environment{bindings, definitions, linked}, choices, member_proof_certified(proof))
        return Specialization{module, G.Environment{bindings, definitions, linked}, answers, counter, certificates}

def finalize_specialization(specialized: Specialization, +configuration: Configuration) -> Result<&2, &2, M.Diagnostic, Specialization>:
  Specialization{+module, +environment, +choices, +counter, +certificates} = specialized
  Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
  +external_functions = G.function_names(G.function_declarations(originals))
  +refreshed = refresh_type_eq_definitions(G.env_definitions(environment), I.substitutions_of(G.env_state(environment)), choices, module)
  do Result<&2, &2, M.Diagnostic, Specialization>:
    +reached : Set() <- reached_names(Specialization{module, environment, refreshed, counter, certificates}, configuration)
    candidates : List<&2, Nat> <- resolved_signature_rows(reached_selected_types(G.env_definitions(environment), reached, refreshed), I.substitutions_of(G.env_state(environment)))
    finalize_with_selected_rows(candidates, reached, module, environment, refreshed, counter, certificates, external_functions)

def finish_boundary_progress(needs: List<&2, I.Coverage>, progress: BoundaryProgress, +configuration: Configuration) -> Result<&2, &2, M.Diagnostic, Specialization>:
  match needs progress:
    case Nil{} BoundaryProgress{updated, False{}}:
      finalize_specialization(updated, configuration)
    case _ BoundaryProgress{updated, changed}:
      do Result<&2, &2, M.Diagnostic, Specialization>:
        retained : Specialization <- prune_generic_roots(updated, configuration)
        finalize_specialization(retained, configuration)

def finish_requirements(needs: List<&2, I.Coverage>, specialized: Specialization, +configuration: Configuration, shapes: List<&2, I.Binding>, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, Specialization>:
  do Result<&2, &2, M.Diagnostic, Specialization>:
    progress : BoundaryProgress <- schedule_boundaries(65536n, CheckBoundaries{specialized, False{}}, configuration, shapes, schemes)
    finish_boundary_progress(needs, progress, configuration)

def infer_required_at(expanded: ExpandedModule, +configuration: Configuration, +shapes: List<&2, I.Binding>, isolated: Bool, limit: Result<&2, &2, M.Diagnostic, Nat>) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  ExpandedModule{M.Module{+constants, +functions, +types, +operations}, counter, bindings, certificates} = expanded
  Configuration{+originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
  +owned = List.append(&2, G.Declaration, G.function_declarations(functions), G.constant_declarations(constants))
  +ordinary = ordinary_bindings(shapes, Bool.pick(List<&2, String>, isolated, G.names(owned), affected))
  +declarations = List.append(&2, G.Declaration, G.function_declarations(pending_functions(functions, ordinary)), G.constant_declarations(pending_constants(constants, ordinary)))
  do Result<&2, &2, M.Diagnostic, ExpandedModule>:
    start : Nat <- limit
    +inferred : G.Environment <- infer_pending(declarations, shapes, G.Environment{ordinary, Nil{}, I.State{T.empty(), start, MTip{}}}, operations, types, G.function_names(G.function_declarations(List.append(&2, M.Function, originals, functions))))
    +initial_needs : List<&2, I.Coverage> = pending(inferred)
    +initial_count : Nat = List.length(&2, I.Definition, G.env_definitions(inferred))
    +solved : Specialization <- solve(65536n, Needs{initial_needs}, Specialization{M.Module{constants, functions, types, operations}, inferred, Map.new(&2, Choice), counter, certificates}, configuration, shapes, PendingCache{initial_count, initial_needs})
    specialized : Specialization <- finish_requirements(specialization_pending(solved), solved, configuration, shapes, Nil{})
    finish_expansion(specialized)

def infer_required(expanded: ExpandedModule, configuration: Configuration, +shapes: List<&2, I.Binding>, isolated: Bool) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  infer_required_at(expanded, configuration, shapes, isolated, shape_limit(shapes, 0n))

def infer_present(present: Bool, expanded: ExpandedModule, configuration: Configuration, shapes: List<&2, I.Binding>, isolated: Bool) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  match present:
    case False{}:
      Done{expanded}
    case True{}:
      infer_required(expanded, configuration, shapes, isolated)

def infer_expansion(+expanded: ExpandedModule, configuration: Configuration, shapes: List<&2, I.Binding>, isolated: Bool) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  ExpandedModule{module, counter, bindings, certificates} = expanded
  infer_present(required(module), expanded, configuration, shapes, isolated)

def infer_required_staged_at(expanded: ExpandedModule, +configuration: Configuration, +shapes: List<&2, I.Binding>, isolated: Bool, +schemes: List<&2, Staging.Scheme>, limit: Result<&2, &2, M.Diagnostic, Nat>) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  ExpandedModule{M.Module{+constants, +functions, +types, +operations}, counter, bindings, certificates} = expanded
  Configuration{+originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
  +owned = List.append(&2, G.Declaration, G.function_declarations(functions), G.constant_declarations(constants))
  +ordinary = ordinary_bindings(shapes, Bool.pick(List<&2, String>, isolated, G.names(owned), affected))
  +declarations = List.append(&2, G.Declaration, G.function_declarations(pending_functions(functions, ordinary)), G.constant_declarations(pending_constants(constants, ordinary)))
  do Result<&2, &2, M.Diagnostic, ExpandedModule>:
    start : Nat <- limit
    +inferred : G.Environment <- infer_pending_staged(declarations, shapes, G.Environment{ordinary, Nil{}, I.State{T.empty(), start, MTip{}}}, operations, types, G.function_names(G.function_declarations(List.append(&2, M.Function, originals, functions))), schemes, stride)
    +initial_needs : List<&2, I.Coverage> = pending(inferred)
    +initial_count : Nat = List.length(&2, I.Definition, G.env_definitions(inferred))
    +solved : Specialization <- solve_staged(65536n, Needs{initial_needs}, Specialization{M.Module{constants, functions, types, operations}, inferred, Map.new(&2, Choice), counter, certificates}, configuration, shapes, PendingCache{initial_count, initial_needs}, schemes)
    specialized : Specialization <- finish_requirements(specialization_pending(solved), solved, configuration, shapes, schemes)
    finish_expansion(specialized)

def infer_required_staged(expanded: ExpandedModule, configuration: Configuration, +shapes: List<&2, I.Binding>, isolated: Bool, +schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  infer_required_staged_at(expanded, configuration, shapes, isolated, schemes, shape_limit(shapes, 0n))

def infer_required_optional(+expanded: ExpandedModule, +configuration: Configuration, +shapes: List<&2, I.Binding>, +isolated: Bool, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  match schemes:
    case Nil{}:
      infer_required(expanded, configuration, shapes, isolated)
    case head <> tail:
      infer_required_staged(expanded, configuration, shapes, isolated, head <> tail)

def infer_present_staged(present: Bool, expanded: ExpandedModule, configuration: Configuration, shapes: List<&2, I.Binding>, isolated: Bool, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  match present:
    case False{}:
      Done{expanded}
    case True{}:
      infer_required_staged(expanded, configuration, shapes, isolated, schemes)

def infer_expansion_staged(+expanded: ExpandedModule, +configuration: Configuration, +shapes: List<&2, I.Binding>, +isolated: Bool, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  ExpandedModule{module, counter, bindings, certificates} = expanded
  match schemes:
    case Nil{}:
      infer_expansion(expanded, configuration, shapes, isolated)
    case head <> tail:
      infer_present_staged(required(module), expanded, configuration, shapes, isolated, head <> tail)


def has_predicates(predicates: List<&2, M.Predicate>) -> Bool:
  match predicates:
    case Nil{}:
      False{}
    case head <> tail:
      True{}

def infer_present_at(present: Bool, expanded: ExpandedModule, configuration: Configuration, shapes: List<&2, I.Binding>, isolated: Bool, schemes: List<&2, Staging.Scheme>, limit: Result<&2, &2, M.Diagnostic, Nat>) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  match present schemes:
    case False{} _:
      Done{expanded}
    case True{} Nil{}:
      infer_required_at(expanded, configuration, shapes, isolated, limit)
    case True{} head <> tail:
      infer_required_staged_at(expanded, configuration, shapes, isolated, head <> tail, limit)

def infer_expansion_at(+expanded: ExpandedModule, configuration: Configuration, shapes: List<&2, I.Binding>, isolated: Bool, schemes: List<&2, Staging.Scheme>, limit: Result<&2, &2, M.Diagnostic, Nat>) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  ExpandedModule{module, counter, bindings, certificates} = expanded
  infer_present_at(required(module), expanded, configuration, shapes, isolated, schemes, limit)

def generic_template_selected(selected: Bool, +name: String, ty: M.Ty, predicates: List<&2, M.Predicate>, +rest: List<&2, String>) -> List<&2, String>:
  match selected:
    case False{}:
      rest
    case True{}:
      Bool.pick(List<&2, String>, Bool.or(polymorphic(65536n, [ty]), has_predicates(predicates)), name <> rest, rest)

def generic_templates_in(bindings: List<&2, I.Binding>, +affected: Set()) -> List<&2, String>:
  match bindings:
    case Nil{}:
      Nil{}
    case I.Binding{+name, ty, variables, predicates} <> tail:
      generic_template_selected(D.member(affected, name), name, ty, predicates, generic_templates_in(tail, affected))

def generic_templates(bindings: List<&2, I.Binding>, affected: List<&2, String>) -> List<&2, String>:
  generic_templates_in(bindings, Set.from_list(affected))

def constant_annotation(annotation: Maybe<&2, M.Ty>, value: M.Expr) -> M.Expr:
  match annotation value:
    case None{} value:
      value
    case Some{ty} M.SourceExpr{offset, previous, value}:
      M.SourceExpr{offset, Some{ty}, value}
    case Some{ty} value:
      M.SourceExpr{0n, Some{ty}, value}

def constant_template_selected(selected: Bool, name: String, annotation: Maybe<&2, M.Ty>, +value: M.Expr, +rest: List<&2, LocalTemplate>) -> List<&2, LocalTemplate>:
  match selected:
    case False{}:
      rest
    case True{}:
      Bool.pick(List<&2, LocalTemplate>, template_value(65536n, value), LocalTemplate{name, constant_annotation(annotation, value)} <> rest, rest)

def constant_templates_in(constants: List<&2, M.Constant>, +affected: Set()) -> List<&2, LocalTemplate>:
  match constants:
    case Nil{}:
      Nil{}
    case M.Constant{+name, exported, annotation, value} <> tail:
      constant_template_selected(D.member(affected, name), name, annotation, value, constant_templates_in(tail, affected))

def constant_templates(constants: List<&2, M.Constant>, affected: List<&2, String>) -> List<&2, LocalTemplate>:
  constant_templates_in(constants, Set.from_list(affected))

def retained_constants(constants: List<&2, M.Constant>, +templates: List<&2, LocalTemplate>) -> List<&2, M.Constant>:
  match constants:
    case Nil{}:
      Nil{}
    case M.Constant{+name, +exported, annotation, value} <> tail:
      +rest = retained_constants(tail, templates)
      Bool.pick(List<&2, M.Constant>, Bool.and(Bool.not(exported), Maybe.is_some(&2, M.Expr, local_template(templates, name))), rest, M.Constant{name, exported, annotation, value} <> rest)

def polymorphic_callable(fuel: Nat, pending: List<&2, M.Ty>) -> Bool:
  match fuel pending:
    case _ Nil{}:
      False{}
    case 0n _:
      False{}
    case 1n+rest M.FunctionTy{parameter, result, row} <> tail:
      Bool.or(polymorphic(65536n, [parameter, result]), polymorphic_callable(rest, tail))
    case 1n+rest M.AppliedTy{identity, arguments} <> tail:
      polymorphic_callable(rest, List.append(&2, M.Ty, arguments, tail))
    case 1n+rest M.ProductTy{elements} <> tail:
      polymorphic_callable(rest, List.append(&2, M.Ty, elements, tail))
    case 1n+rest M.ArrayTy{element} <> tail:
      polymorphic_callable(rest, element <> tail)
    case 1n+rest head <> tail:
      polymorphic_callable(rest, tail)

def constant_callable(found: Maybe<&2, I.Binding>) -> Bool:
  match found:
    case Some{I.Binding{name, ty, variables, predicates}}:
      Bool.or(polymorphic_callable(65536n, [ty]), has_predicates(predicates))
    case None{}:
      False{}

def specialized_constant_callable(callable: Bool, +constant: M.Constant, +rest: List<&2, M.Constant>) -> List<&2, M.Constant>:
  match callable:
    case False{}:
      rest
    case True{}:
      M.Constant{name, exported, annotation, value} = constant
      Bool.pick(List<&2, M.Constant>, template_value(65536n, value), rest, constant <> rest)

def specialized_constant_selected(selected: Bool, +constant: M.Constant, shapes: List<&2, I.Binding>, rest: List<&2, M.Constant>) -> List<&2, M.Constant>:
  match selected:
    case False{}:
      rest
    case True{}:
      M.Constant{name, exported, annotation, value} = constant
      specialized_constant_callable(constant_callable(I.lookup_binding(shapes, name)), constant, rest)

def specialized_constants_in(constants: List<&2, M.Constant>, +templates: Set(), +shapes: List<&2, I.Binding>) -> List<&2, M.Constant>:
  match constants:
    case Nil{}:
      Nil{}
    case M.Constant{name, exported, annotation, M.RuntimeInitExpr{value}} <> tail:
      specialized_constants_in(tail, templates, shapes)
    case M.Constant{+name, exported, annotation, value} <> tail:
      constant : M.Constant = M.Constant{name, exported, annotation, value}
      specialized_constant_selected(D.member(templates, name), constant, shapes, specialized_constants_in(tail, templates, shapes))

def specialized_constants(constants: List<&2, M.Constant>, templates: List<&2, String>, shapes: List<&2, I.Binding>) -> List<&2, M.Constant>:
  specialized_constants_in(constants, Set.from_list(templates), shapes)

def retained_specializations(constants: List<&2, M.Constant>, +templates: List<&2, M.Constant>) -> List<&2, M.Constant>:
  match constants:
    case Nil{}:
      Nil{}
    case +constant <> tail:
      M.Constant{name, exported, annotation, value} = constant
      +rest = retained_specializations(tail, templates)
      Bool.pick(List<&2, M.Constant>, Bool.and(Bool.not(exported), Maybe.is_some(&2, M.Constant, lookup_constant(templates, name))), rest, constant <> rest)

def expression_identity(expression: M.Expr) -> Nat:
  match expression:
    case M.TagExpr{offset, callee, argument}:
      offset
    case M.SourceExpr{offset, annotation, value}:
      offset
    case M.LambdaExpr{identity, parameter, p, r, body}:
      identity
    case M.BlockExpr{label, body}:
      label
    case M.ReturnExpr{label, value}:
      label
    case M.AssociatedExpr{identity, dispatch, member, templates, left, right}:
      identity
    case M.GenericOperationExpr{identity, template, arguments}:
      identity
    case M.InstantiationExpr{site, value}:
      site
    case _:
      0n

def identity_limit(fuel: Nat, pending: List<&2, M.Expr>, +maximum: Nat) -> Result<&2, &2, M.Diagnostic, Nat>:
  match fuel pending:
    case _ Nil{}:
      Done{1n+maximum}
    case 0n _:
      Fail{M.Diagnostic{"specialization_limit", "monomorphization", "module identity scan exceeded its limit"}}
    case 1n+rest +head <> tail:
      +found = expression_identity(head)
      identity_limit(rest, List.reverse.go(&2, M.Expr, List.reverse(&2, M.Expr, F.children(head)), tail), Bool.pick(Nat, Nat.is_gt(found, maximum), found, maximum))

def module_expressions(functions: List<&2, M.Function>, constants: List<&2, M.Constant>) -> List<&2, M.Expr>:
  match functions constants:
    case M.Function{name, exported, parameter, p, r, body} <> tail constants:
      body <> module_expressions(tail, constants)
    case Nil{} M.Constant{name, exported, annotation, value} <> tail:
      value <> module_expressions(Nil{}, tail)
    case Nil{} Nil{}:
      Nil{}

def known_constant(binding: Maybe<&2, I.Binding>) -> Bool:
  match binding:
    case Some{I.Binding{name, ty, variables, predicates}}:
      Bool.and(Bool.not(polymorphic(65536n, [ty])), Bool.not(has_predicates(predicates)))
    case None{}:
      False{}

# Concrete shared signatures separate specialization units. A constant whose
# dispatch result is still unknown keeps its consumers in one inference scope.
def independent_constants(constants: List<&2, M.Constant>, +affected: List<&2, String>, +shapes: List<&2, I.Binding>) -> Bool:
  match constants:
    case Nil{}:
      True{}
    case M.Constant{+name, exported, annotation, value} <> tail:
      Bool.and(Bool.or(Bool.not(D.contains(affected, name)), known_constant(I.lookup_binding(shapes, name))), independent_constants(tail, affected, shapes))

def expanded_module(expanded: ExpandedModule) -> M.Module:
  ExpandedModule{module, counter, bindings, certificates} = expanded
  module

def expanded_next(expanded: ExpandedModule) -> Nat:
  ExpandedModule{module, counter, bindings, certificates} = expanded
  counter

def expanded_certificates(expanded: ExpandedModule) -> List<&2, Core.Certificate>:
  ExpandedModule{module, counter, bindings, certificates} = expanded
  certificates

def combine_expansions(first: ExpandedModule, rest: ExpandedModule) -> ExpandedModule:
  ExpandedModule{M.Module{a_constants, a_functions, types, operations}, +counter, first_bindings, first_certificates} = first
  ExpandedModule{M.Module{b_constants, b_functions, b_types, b_operations}, +next, next_bindings, next_certificates} = rest
  ExpandedModule{M.Module{List.append(&2, M.Constant, a_constants, b_constants), List.append(&2, M.Function, a_functions, b_functions), types, State.merge(b_operations, operations)}, Bool.pick(Nat, Nat.is_ge(counter, next), counter, next), List.append(&2, I.Binding, first_bindings, next_bindings), List.append(&2, Core.Certificate, first_certificates, next_certificates)}

def expand_declaration(declaration: G.Declaration, +configuration: Configuration, types: List<&2, M.DataType>, operations: List<&2, M.Operation>, counter: Nat) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  match declaration:
    case G.FunctionDeclaration{+function}:
      M.Function{+name, +exported, parameter, p, r, body} = function
      Configuration{originals, +templates, entry, locals, +affected, stride, constant_values, family_templates, step, schema} = configuration
      do Result<&2, &2, M.Diagnostic, ExpandedModule>:
        +expanded : Expansion <- expand_root(Bool.or(Bool.and(exported, D.contains(templates, name)), Bool.and(Bool.not(D.contains(templates, name)), D.contains(affected, name))), D.contains(templates, name), function, configuration, counter)
        return ExpandedModule{M.Module{emitted_constants(expanded), functions(expanded), types, operations}, next(expanded), Nil{}, Nil{}}
    case G.ConstantDeclaration{M.Constant{name, exported, annotation, value}}:
      do Result<&2, &2, M.Diagnostic, ExpandedModule>:
        +expanded : Expansion <- expand(65536n, Expression{value}, configuration, Nil{}, 0n, counter)
        expression : M.Expr <- one(expressions(expanded))
        return ExpandedModule{M.Module{M.Constant{name, exported, annotation, expression} <> emitted_constants(expanded), functions(expanded), types, operations}, next(expanded), Nil{}, Nil{}}

type SpecializationTask is Data:
  SpecializationTask{declaration: G.Declaration, first: Nat}

type SpecializationContext is Data:
  SpecializationContext{configuration: Configuration, shapes: List<&2, I.Binding>, types: List<&2, M.DataType>, operations: List<&2, M.Operation>, schemes: List<&2, Staging.Scheme>, limit: Result<&2, &2, M.Diagnostic, Nat>}

# A task result is reusable only with the same inferred shapes and nominal
# context. Source declarations are encoded once per revision, then each task
# compares only the declarations whose bodies it used.
type CachedTask is Data:
  CachedTask{position: Nat, name: String, dependencies: List<&2, String>, result: ExpandedModule}

type Cache is Data:
  Cache{context: List<&2, U32>, tasks: List<&2, CachedTask>, sources: Map<&2, List<&2, U32>>, source_certificates: List<&2, Core.Certificate>}

type Reusable is Data:
  Reusable{tasks: List<&2, CachedTask>, sources: Map<&2, List<&2, U32>>}

def empty_cache() -> Cache:
  Cache{Nil{}, Nil{}, Map.new(&2, List<&2, U32>), Nil{}}

type Prepared is Data:
  Prepared{module: M.Module, cache: Cache, certificates: List<&2, Core.Certificate>}

type CachedExpansion is Data:
  CachedExpansion{value: ExpandedModule, tasks: List<&2, CachedTask>}

type TaskRun is Data:
  ReusedTask{value: CachedTask}
  NewTask{task: SpecializationTask, dependencies: List<&2, String>}

def prepared_module(prepared: Prepared) -> M.Module:
  Prepared{module, cache, certificates} = prepared
  module

def prepared_cache(prepared: Prepared) -> Cache:
  Prepared{module, cache, certificates} = prepared
  cache

def source_certificates(previous: Maybe<&2, Cache>) -> List<&2, Core.Certificate>:
  match previous:
    case None{}:
      Nil{}
    case Some{Cache{context, tasks, sources, certificates}}:
      certificates

# Source evidence is published only with a successful prepared module. The
# native session leaves its previous cache in place when compilation fails.
def with_source_certificates(prepared: Prepared, certificates: List<&2, Core.Certificate>) -> Prepared:
  Prepared{module, Cache{context, tasks, sources, old}, final_certificates} = prepared
  Prepared{module, Cache{context, tasks, sources, Core.ready_certificates(certificates)}, final_certificates}

def prepared_certificates(prepared: Prepared) -> List<&2, Core.Certificate>:
  Prepared{module, cache, certificates} = prepared
  certificates

def same_words_go(left: List<&2, U32>, right: List<&2, U32>, equal: Bool) -> Bool:
  match left right equal:
    case _ _ False{}:
      False{}
    case Nil{} Nil{} True{}:
      True{}
    case a <> rest_a b <> rest_b True{}:
      same_words_go(rest_a, rest_b, U32.is_eq(a, b))
    case _ _ _:
      False{}

def same_words(left: List<&2, U32>, right: List<&2, U32>) -> Bool:
  same_words_go(left, right, True{})

def task_index(tasks: List<&2, CachedTask>, index: Map<&2, CachedTask>) -> Map<&2, CachedTask>:
  match tasks:
    case Nil{}:
      index
    case CachedTask{+at, name, dependencies, result} <> tail:
      task_index(tail, Map.set(&2, CachedTask, index, Nat.show(at), CachedTask{at, name, dependencies, result}))

def reusable_match(equal: Bool, tasks: List<&2, CachedTask>, sources: Map<&2, List<&2, U32>>) -> Reusable:
  match equal:
    case True{}:
      Reusable{tasks, sources}
    case False{}:
      Reusable{Nil{}, Map.new(&2, List<&2, U32>)}

def cache_for_context(previous: Maybe<&2, Cache>, +context: List<&2, U32>) -> Reusable:
  match previous:
    case None{}:
      Reusable{Nil{}, Map.new(&2, List<&2, U32>)}
    case Some{Cache{prior, tasks, sources, certificates}}:
      reusable_match(same_words(prior, context), tasks, sources)

def shape_variables(variables: List<&2, Nat>) -> List<&2, M.Function>:
  match variables:
    case Nil{}:
      Nil{}
    case head <> tail:
      M.Function{Nat.show(head), False{}, "", None{}, None{}, M.UnitExpr{}} <> shape_variables(tail)

def shape_key_body(ty: M.Ty, predicates: List<&2, M.Predicate>) -> M.Expr:
  match predicates:
    case Nil{}:
      M.UnitExpr{}
    case predicates:
      M.QualifiedExpr{0n, ty, predicates, M.UnitExpr{}}

def shape_functions(shapes: List<&2, I.Binding>) -> List<&2, M.Function>:
  match shapes:
    case Nil{}:
      Nil{}
    case I.Binding{name, +ty, +variables, predicates} <> tail:
      M.Function{name, False{}, Nat.show(List.length(&2, Nat, variables)), Some{ty}, None{}, shape_key_body(ty, predicates)} <> List.append(&2, M.Function, shape_variables(variables), shape_functions(tail))

def marker_functions(names: List<&2, String>) -> List<&2, M.Function>:
  match names:
    case Nil{}:
      Nil{}
    case name <> tail:
      M.Function{name, False{}, "", None{}, None{}, M.UnitExpr{}} <> marker_functions(tail)

def local_constants(locals: List<&2, LocalTemplate>) -> List<&2, M.Constant>:
  match locals:
    case Nil{}:
      Nil{}
    case LocalTemplate{name, value} <> tail:
      M.Constant{name, False{}, None{}, value} <> local_constants(tail)

def unplanned_functions(functions: List<&2, M.Function>, +planned: List<&2, String>) -> List<&2, M.Function>:
  match functions:
    case Nil{}:
      Nil{}
    case +function <> tail:
      M.Function{+name, exported, parameter, input, output, body} = function
      +rest = unplanned_functions(tail, planned)
      Bool.pick(List<&2, M.Function>, D.contains(planned, name), rest, function <> rest)

# A schema reduction can erase the call that made one of these functions
# reachable from a specialization task. Keep their exact source bodies in the
# global context key so a session edit cannot reuse a reduced old task.
def schema_source_functions(proofs: List<&2, Schema.Evidence>) -> List<&2, M.Function>:
  match proofs:
    case Nil{}:
      Nil{}
    case Schema.Evidence{node_method, terminal_method, equality, type_equality, node_type, terminal_type, witness_type, node_constructor, terminal_identity, node_identity, member} <> tail:
      node_method <> terminal_method <> equality <> type_equality <> schema_source_functions(tail)

def context_module(context: SpecializationContext, +nodes: List<&2, D.Node>) -> M.Module:
  SpecializationContext{Configuration{originals, +templates, entry, +locals, +affected, stride, constants, family_templates, step, +schema}, +shapes, types, +operations, schemes, limit} = context
  metadata : List<&2, M.Function> = [M.Function{entry, False{}, Nat.show(stride), None{}, None{}, M.UnitExpr{}}, M.Function{Nat.show(step), False{}, Nat.show(List.length(&2, String, templates)), None{}, None{}, M.UnitExpr{}}, M.Function{Nat.show(List.length(&2, LocalTemplate, locals)), False{}, Nat.show(List.length(&2, M.Operation, operations)), None{}, None{}, M.UnitExpr{}}, M.Function{Nat.show(List.length(&2, I.Binding, shapes)), False{}, "", None{}, None{}, M.UnitExpr{}}, M.Function{"@schema.evidence", False{}, Nat.show(List.length(&2, Schema.Evidence, schema)), None{}, None{}, M.UnitExpr{}}]
  marked = List.append(&2, M.Function, metadata, List.append(&2, M.Function, marker_functions(templates), M.Function{"@affected", False{}, Nat.show(List.length(&2, String, affected)), None{}, None{}, M.UnitExpr{}} <> List.append(&2, M.Function, marker_functions(affected), shape_functions(shapes))))
  # Shared-constant specialization can add source-independent helper bodies.
  # Include all helpers absent from the original graph in the global key.
  M.Module{List.append(&2, M.Constant, local_constants(locals), constants), List.append(&2, M.Function, marked, List.append(&2, M.Function, unplanned_functions(originals, D.node_names(nodes)), schema_source_functions(schema))), types, List.append(&2, M.Operation, operations, family_templates)}

def function_source_keys(~key: M.Module -> Result<&2, &2, M.Diagnostic, List<&2, U32>>, functions: List<&2, M.Function>, +acc: Map<&2, List<&2, U32>>) -> Result<&2, &2, M.Diagnostic, Map<&2, List<&2, U32>>>:
  match functions:
    case Nil{}:
      Done{acc}
    case +function <> rest:
      M.Function{+name, exported, parameter, input, output, body} = function
      do Result<&2, &2, M.Diagnostic, Map<&2, List<&2, U32>>>:
        words : List<&2, U32> <- key(M.Module{Nil{}, [function], Nil{}, Nil{}})
        function_source_keys(~key, rest, Map.set(&2, List<&2, U32>, acc, name, words))

def constant_source_keys(~key: M.Module -> Result<&2, &2, M.Diagnostic, List<&2, U32>>, constants: List<&2, M.Constant>, +acc: Map<&2, List<&2, U32>>) -> Result<&2, &2, M.Diagnostic, Map<&2, List<&2, U32>>>:
  match constants:
    case Nil{}:
      Done{acc}
    case +constant <> rest:
      M.Constant{+name, exported, annotation, value} = constant
      do Result<&2, &2, M.Diagnostic, Map<&2, List<&2, U32>>>:
        words : List<&2, U32> <- key(M.Module{[constant], Nil{}, Nil{}, Nil{}})
        constant_source_keys(~key, rest, Map.set(&2, List<&2, U32>, acc, name, words))

def source_keys(~key: M.Module -> Result<&2, &2, M.Diagnostic, List<&2, U32>>, functions: List<&2, M.Function>, constants: List<&2, M.Constant>) -> Result<&2, &2, M.Diagnostic, Map<&2, List<&2, U32>>>:
  do Result<&2, &2, M.Diagnostic, Map<&2, List<&2, U32>>>:
    functions_keyed : Map<&2, List<&2, U32>> <- function_source_keys(~key, functions, Map.new(&2, List<&2, U32>))
    constant_source_keys(~key, constants, functions_keyed)

def with_step(configuration: Configuration, step: Nat) -> Configuration:
  Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, previous, schema} = configuration
  Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema}

def declaration_cost(declaration: G.Declaration) -> Nat:
  match declaration:
    case G.FunctionDeclaration{M.Function{name, exported, parameter, p, r, body}}:
      Scheduler.expression_cost(4096n, [Scheduler.ExpressionCost{body}], 1n)
    case G.ConstantDeclaration{M.Constant{name, exported, annotation, value}}:
      Scheduler.expression_cost(4096n, [Scheduler.ExpressionCost{value}], 1n)

def specialization_tasks(declarations: List<&2, G.Declaration>, +first: Nat) -> List<&2, Batch.Weighted<SpecializationTask>>:
  match declarations:
    case Nil{}:
      Nil{}
    case +head <> tail:
      Batch.Weighted{SpecializationTask{head, first}, declaration_cost(head)} <> specialization_tasks(tail, 1n+first)

def specialize_task(task: SpecializationTask, context: SpecializationContext) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  SpecializationTask{declaration, first} = task
  SpecializationContext{+configuration, shapes, types, operations, schemes, limit} = context
  do Result<&2, &2, M.Diagnostic, ExpandedModule>:
    expanded : ExpandedModule <- expand_declaration(declaration, configuration, types, operations, first)
    infer_expansion_at(expanded, configuration, shapes, True{}, schemes, limit)

def run_task(task: TaskRun, context: SpecializationContext) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  match task:
    case ReusedTask{CachedTask{position, name, dependencies, result}}:
      Done{result}
    case NewTask{pending, dependencies}:
      specialize_task(pending, context)

def reuse_match(equal: Bool, entry: CachedTask, task: SpecializationTask) -> TaskRun:
  match equal:
    case True{}:
      ReusedTask{entry}
    case False{}:
      NewTask{task, Nil{}}

def same_source(old: Maybe<&2, List<&2, U32>>, current: Maybe<&2, List<&2, U32>>) -> Bool:
  match old current:
    case Some{prior} Some{now}:
      same_words(prior, now)
    case _ _:
      False{}

def same_dependencies(names: List<&2, String>, +old: Map<&2, List<&2, U32>>, +current: Map<&2, List<&2, U32>>, equal: Bool) -> Bool:
  match names equal:
    case _ False{}:
      False{}
    case Nil{} True{}:
      True{}
    case +name <> rest True{}:
      same_dependencies(rest, old, current, same_source(Index.find(List<&2, U32>, old, name), Index.find(List<&2, U32>, current, name)))

def reuse_task(candidate: Maybe<&2, CachedTask>, +declaration: G.Declaration, position: Nat, +old: Map<&2, List<&2, U32>>, +current: Map<&2, List<&2, U32>>) -> TaskRun:
  match candidate:
    case None{}:
      NewTask{SpecializationTask{declaration, position}, Nil{}}
    case Some{+entry}:
      CachedTask{at, name, +dependencies, result} = entry
      +root = G.declaration_name(declaration)
      reuse_match(Bool.and(M.name_equal(name, root), same_dependencies(root <> dependencies, old, current, True{})), entry, SpecializationTask{declaration, position})

def cached_tasks(declarations: List<&2, G.Declaration>, +previous: Map<&2, CachedTask>, +old: Map<&2, List<&2, U32>>, +current: Map<&2, List<&2, U32>>, +position: Nat) -> List<&2, Batch.Weighted<TaskRun>>:
  match declarations:
    case Nil{}:
      Nil{}
    case +declaration <> tail:
      +run = reuse_task(Index.find(CachedTask, previous, Nat.show(position)), declaration, position, old, current)
      +cost = declaration_cost(declaration)
      Batch.Weighted{run, cost} <> cached_tasks(tail, previous, old, current, 1n+position)

def expanded_function_roots(functions: List<&2, M.Function>) -> List<&2, String>:
  match functions:
    case Nil{}:
      Nil{}
    case M.Function{+name, exported, parameter, p, r, body} <> tail:
      original_name(name) <> expanded_function_roots(tail)

def task_dependencies(declaration: G.Declaration, expanded: ExpandedModule, +nodes: List<&2, D.Node>) -> Result<&2, &2, M.Diagnostic, List<&2, String>>:
  ExpandedModule{M.Module{constants, functions, types, operations}, next, bindings, certificates} = expanded
  +roots : List<&2, String> = G.declaration_name(declaration) <> expanded_function_roots(functions)
  do Result<&2, &2, M.Diagnostic, List<&2, String>>:
    +reached : D.Reachability <- D.reachable(Nat.add(List.length(&2, String, roots), Nat.add(D.edge_count(nodes), 1n)), roots, D.adjacency(nodes, MTip{}), Set.from_list(D.node_names(nodes)), Set.new(), Nil{})
    return D.reached_members(reached)

def dependent_entry(dependencies: Result<&2, &2, M.Diagnostic, List<&2, String>>, +declaration: G.Declaration, position: Nat, expanded: ExpandedModule) -> Maybe<&2, CachedTask>:
  match dependencies:
    case Fail{diagnostic}:
      None{}
    case Done{+names}:
      Some{CachedTask{position, G.declaration_name(declaration), names, expanded}}

def task_entry(run: TaskRun, +expanded: ExpandedModule, +nodes: List<&2, D.Node>) -> Maybe<&2, CachedTask>:
  match run:
    case ReusedTask{entry}:
      Some{entry}
    case NewTask{SpecializationTask{+declaration, position}, unused}:
      dependent_entry(task_dependencies(declaration, expanded, nodes), declaration, position, expanded)

def append_entry(entry: Maybe<&2, CachedTask>, rest: List<&2, CachedTask>) -> List<&2, CachedTask>:
  match entry:
    case None{}:
      rest
    case Some{value}:
      value <> rest

def combine_cached(+first: ExpandedModule, next: CachedExpansion, run: TaskRun, +nodes: List<&2, D.Node>) -> CachedExpansion:
  CachedExpansion{remaining, entries} = next
  CachedExpansion{combine_expansions(first, remaining), append_entry(task_entry(run, first, nodes), entries)}

def collect_cached(runs: List<&2, Batch.Weighted<TaskRun>>, outcomes: List<&2, Result<&2, &2, M.Diagnostic, ExpandedModule>>, +nodes: List<&2, D.Node>, +types: List<&2, M.DataType>, +operations: List<&2, M.Operation>, +counter: Nat) -> Result<&2, &2, M.Diagnostic, CachedExpansion>:
  match runs outcomes:
    case Nil{} Nil{}:
      Done{CachedExpansion{ExpandedModule{M.Module{Nil{}, Nil{}, types, operations}, counter, Nil{}, Nil{}}, Nil{}}}
    case Batch.Weighted{run, cost} <> following outcome <> tail:
      do Result<&2, &2, M.Diagnostic, CachedExpansion>:
        first : ExpandedModule <- outcome
        next : CachedExpansion <- collect_cached(following, tail, nodes, types, operations, counter)
        return combine_cached(first, next, run, nodes)
    case _ _:
      Fail{M.Diagnostic{"internal_error", "monomorphization", "specialization task outcome count mismatch"}}

# Parallel units can each create the same shared accessor. Every copy has the
# same body up to its unit-local lambda identity, so keep the first in source
# order; references name the accessor, never a particular copy.
def kept_accessor(duplicate: Bool, function: M.Function, reversed: List<&2, M.Function>) -> List<&2, M.Function>:
  match duplicate:
    case True{}:
      reversed
    case False{}:
      function <> reversed

def distinct_accessors_work(functions: List<&2, M.Function>, +seen: Set(), reversed: List<&2, M.Function>) -> List<&2, M.Function>:
  match functions:
    case Nil{}:
      List.reverse(&2, M.Function, reversed)
    case +function <> tail:
      M.Function{+name, exported, parameter, p, r, body} = function
      distinct_accessors_work(tail, Set.add(seen, name), kept_accessor(Bool.and(String.starts_with(name, "$member"), D.member(seen, name)), function, reversed))

def distinct_accessors(functions: List<&2, M.Function>) -> List<&2, M.Function>:
  distinct_accessors_work(functions, Set.new(), Nil{})

def distinct_expansion(expanded: ExpandedModule) -> ExpandedModule:
  ExpandedModule{M.Module{constants, functions, types, operations}, next, bindings, certificates} = expanded
  ExpandedModule{M.Module{constants, distinct_accessors(functions), types, operations}, next, bindings, certificates}

def distinct_cached(compiled: CachedExpansion) -> CachedExpansion:
  CachedExpansion{value, tasks} = compiled
  CachedExpansion{distinct_expansion(value), tasks}

def specialize_declarations_cached(+declarations: List<&2, G.Declaration>, configuration: Configuration, +shapes: List<&2, I.Binding>, +types: List<&2, M.DataType>, +operations: List<&2, M.Operation>, +counter: Nat, +nodes: List<&2, D.Node>, +previous: List<&2, CachedTask>, +old: Map<&2, List<&2, U32>>, +current: Map<&2, List<&2, U32>>) -> Result<&2, &2, M.Diagnostic, CachedExpansion>:
  +width = Nat.max(1n, List.length(&2, G.Declaration, declarations))
  +stepped = with_step(configuration, width)
  +runs = cached_tasks(declarations, task_index(previous, Map.new(&2, CachedTask)), old, current, counter)
  context : SpecializationContext = SpecializationContext{stepped, shapes, types, operations, Nil{}, shape_limit(shapes, 0n)}
  outcomes = Batch.execute(~TaskRun, ~SpecializationContext, ~Result<&2, &2, M.Diagnostic, ExpandedModule>, ~run_task, Batch.plan(TaskRun, runs, 2048n), context)
  do Result<&2, &2, M.Diagnostic, CachedExpansion>:
    collected : CachedExpansion <- collect_cached(runs, outcomes, nodes, types, operations, counter)
    return distinct_cached(collected)

def collect_specializations(outcomes: List<&2, Result<&2, &2, M.Diagnostic, ExpandedModule>>, types: List<&2, M.DataType>, operations: List<&2, M.Operation>, counter: Nat) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  match outcomes:
    case Nil{}:
      Done{ExpandedModule{M.Module{Nil{}, Nil{}, types, operations}, counter, Nil{}, Nil{}}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, ExpandedModule>:
        first : ExpandedModule <- head
        rest : ExpandedModule <- collect_specializations(tail, types, operations, counter)
        return combine_expansions(first, rest)

# Lane n uses n, n+width, n+2*width, ... . No worker shares a counter, and
# source-ordered collection keeps diagnostics independent of completion order.
def specialize_declarations(+declarations: List<&2, G.Declaration>, configuration: Configuration, +shapes: List<&2, I.Binding>, +types: List<&2, M.DataType>, +operations: List<&2, M.Operation>, +counter: Nat, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  +width = Nat.max(1n, List.length(&2, G.Declaration, declarations))
  tasks = specialization_tasks(declarations, counter)
  context : SpecializationContext = SpecializationContext{with_step(configuration, width), shapes, types, operations, schemes, shape_limit(shapes, 0n)}
  outcomes = Batch.execute(~SpecializationTask, ~SpecializationContext, ~Result<&2, &2, M.Diagnostic, ExpandedModule>, ~specialize_task, Batch.plan(SpecializationTask, tasks, 2048n), context)
  do Result<&2, &2, M.Diagnostic, ExpandedModule>:
    collected : ExpandedModule <- collect_specializations(outcomes, types, operations, counter)
    return distinct_expansion(collected)

def stale_interfaces(functions: List<&2, M.Function>, +affected: List<&2, String>, +computed: Map<&2, I.Binding>, +shapes: Map<&2, I.Binding>) -> List<&2, M.Function>:
  match functions:
    case Nil{}:
      Nil{}
    case +function <> tail:
      M.Function{+name, exported, parameter, input, output, body} = function
      +rest = stale_interfaces(tail, affected, computed, shapes)
      Bool.pick(List<&2, M.Function>, Bool.or(D.contains(affected, name), Bool.and(Bool.not(Maybe.is_some(&2, I.Binding, Index.find(I.Binding, shapes, name))), Bool.not(Maybe.is_some(&2, I.Binding, Index.find(I.Binding, computed, name))))), function <> rest, rest)

def stale_constants(constants: List<&2, M.Constant>, +affected: List<&2, String>, +computed: Map<&2, I.Binding>, +shapes: Map<&2, I.Binding>) -> List<&2, M.Constant>:
  match constants:
    case Nil{}:
      Nil{}
    case +constant <> tail:
      M.Constant{+name, exported, annotation, value} = constant
      +rest = stale_constants(tail, affected, computed, shapes)
      Bool.pick(List<&2, M.Constant>, Bool.or(D.contains(affected, name), Bool.and(Bool.not(Maybe.is_some(&2, I.Binding, Index.find(I.Binding, shapes, name))), Bool.not(Maybe.is_some(&2, I.Binding, Index.find(I.Binding, computed, name))))), constant <> rest, rest)

def uncomputed_bindings(shapes: List<&2, I.Binding>, +computed: Map<&2, I.Binding>) -> List<&2, I.Binding>:
  match shapes:
    case Nil{}:
      Nil{}
    case I.Binding{+name, ty, variables, predicates} <> tail:
      +rest = uncomputed_bindings(tail, computed)
      Bool.pick(List<&2, I.Binding>, Maybe.is_some(&2, I.Binding, Index.find(I.Binding, computed, name)), rest, I.Binding{name, ty, variables, predicates} <> rest)

def refreshed_exports(refreshed: ExpandedModule, module: M.Module, bindings: List<&2, I.Binding>) -> Result<&2, &2, M.Diagnostic, M.Module>:
  ExpandedModule{refreshed_module, next, interfaces, certificates} = refreshed
  Public.select(module, List.append(&2, I.Binding, bindings, interfaces), Public.Resolved{})

# Independent roots can use a dependency's earlier shape even when their own
# specialization computed an interface. Refresh affected declarations together
# against completed clones so newly inferred effects also reach their callers.
def refresh_interfaces(pending_functions: List<&2, M.Function>, pending_constants: List<&2, M.Constant>, module: M.Module, +bindings: List<&2, I.Binding>, configuration: Configuration, +shapes: List<&2, I.Binding>, counter: Nat) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match pending_functions pending_constants:
    case Nil{} Nil{}:
      Public.select(module, List.append(&2, I.Binding, shapes, bindings), Public.Resolved{})
    case +fs +cs:
      M.Module{constants, +functions, +types, +operations} = module
      Configuration{originals, templates, entry, locals, affected, stride, constant_values, family_templates, step, schema} = configuration
      scope : Configuration = Configuration{List.append(&2, M.Function, originals, functions), templates, entry, locals, affected, stride, constant_values, family_templates, step, schema}
      +completed = ordinary_bindings(bindings, G.names(List.append(&2, G.Declaration, G.function_declarations(fs), G.constant_declarations(cs))))
      known = List.append(&2, I.Binding, completed, uncomputed_bindings(shapes, Public.binding_index(completed, MTip{})))
      do Result<&2, &2, M.Diagnostic, M.Module>:
        checked : ExpandedModule <- infer_required(ExpandedModule{M.Module{cs, fs, types, operations}, counter, Nil{}, Nil{}}, scope, known, True{})
        refreshed_exports(checked, M.Module{constants, functions, types, operations}, List.append(&2, I.Binding, shapes, bindings))

def public_expansion(expanded: ExpandedModule, +shapes: List<&2, I.Binding>, +configuration: Configuration) -> Result<&2, &2, M.Diagnostic, M.Module>:
  ExpandedModule{+module, counter, +bindings, certificates} = expanded
  M.Module{constants, functions, types, operations} = module
  Configuration{originals, templates, entry, locals, +affected, stride, constant_values, family_templates, step, schema} = configuration
  +computed = Public.binding_index(bindings, MTip{})
  +known = Public.binding_index(shapes, MTip{})
  refresh_interfaces(stale_interfaces(functions, affected, computed, known), stale_constants(constants, affected, computed, known), module, bindings, configuration, shapes, counter)

def specialize(independent: Bool, originals: List<&2, M.Function>, constants: List<&2, M.Constant>, types: List<&2, M.DataType>, operations: List<&2, M.Operation>, +configuration: Configuration, +shapes: List<&2, I.Binding>, counter: Nat) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match independent:
    case True{}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        compiled : ExpandedModule <- specialize_declarations(List.append(&2, G.Declaration, G.function_declarations(originals), G.constant_declarations(constants)), configuration, shapes, types, operations, counter, Nil{})
        public_expansion(compiled, shapes, configuration)
    case False{}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        +roots : Expansion <- expand_roots(originals, configuration, counter)
        expanded : ExpandedModule <- expand_constants(constants, configuration, functions(roots), emitted_constants(roots), types, operations, next(roots))
        compiled : ExpandedModule <- infer_expansion(expanded, configuration, shapes, False{})
        public_expansion(compiled, shapes, configuration)

type SharedConstants is Data:
  SharedConstants{module: M.Module, shapes: List<&2, I.Binding>, names: List<&2, String>, next: Nat, certificates: List<&2, Core.Certificate>}

def unshared_names(pending: List<&2, String>, +shared: List<&2, String>) -> List<&2, String>:
  match pending:
    case Nil{}:
      Nil{}
    case +head <> tail:
      +rest = unshared_names(tail, shared)
      Bool.pick(List<&2, String>, D.contains(shared, head), rest, head <> rest)

def append_constant(found: Maybe<&2, M.Constant>, rest: List<&2, M.Constant>) -> List<&2, M.Constant>:
  match found:
    case None{}:
      rest
    case Some{constant}:
      constant <> rest

def named_constants(names: List<&2, String>, +constants: List<&2, M.Constant>) -> List<&2, M.Constant>:
  match names:
    case Nil{}:
      Nil{}
    case head <> tail:
      append_constant(lookup_constant(constants, head), named_constants(tail, constants))

def ordered_constants(groups: List<&2, List<&2, String>>, +constants: List<&2, M.Constant>) -> List<&2, M.Constant>:
  match groups:
    case Nil{}:
      Nil{}
    case head <> tail:
      List.append(&2, M.Constant, named_constants(head, constants), ordered_constants(tail, constants))

def unreplaced_constants(constants: List<&2, M.Constant>, +replacements: List<&2, M.Constant>) -> List<&2, M.Constant>:
  match constants:
    case Nil{}:
      Nil{}
    case +constant <> tail:
      M.Constant{name, exported, annotation, value} = constant
      +rest = unreplaced_constants(tail, replacements)
      Bool.pick(List<&2, M.Constant>, Maybe.is_some(&2, M.Constant, lookup_constant(replacements, name)), rest, constant <> rest)

def deferred_constant(ambiguous: Bool, error: M.Diagnostic, previous: SharedConstants) -> Result<&2, &2, M.Diagnostic, SharedConstants>:
  match ambiguous:
    case True{}:
      Done{previous}
    case False{}:
      Fail{error}

def accept_constant(compiled: Result<&2, &2, M.Diagnostic, ExpandedModule>, name: String, previous: SharedConstants) -> Result<&2, &2, M.Diagnostic, SharedConstants>:
  match compiled previous:
    case Fail{+error} previous:
      M.Diagnostic{code, subject, message} = error
      deferred_constant(Bool.or(M.name_equal(code, "ambiguous_associated"), M.name_equal(code, "ambiguous_effect")), error, previous)
    case Done{ExpandedModule{M.Module{+compiled_constants, +compiled_functions, compiled_types, compiled_operations}, counter, bindings, certificates}} SharedConstants{M.Module{constants, functions, types, operations}, shapes, shared, next, prior_certificates}:
      +module = {M.Module{List.append(&2, M.Constant, unreplaced_constants(constants, compiled_constants), compiled_constants), List.append(&2, M.Function, functions, compiled_functions), types, State.merge(compiled_operations, operations)} : M.Module}
      +members = G.names(List.append(&2, G.Declaration, G.function_declarations(compiled_functions), G.constant_declarations(compiled_constants)))
      Done{SharedConstants{module, List.append(&2, I.Binding, bindings, ordinary_bindings(shapes, members)), name <> shared, counter, List.append(&2, Core.Certificate, prior_certificates, certificates)}}

# Resolve constants before their consumers when identities are already known.
# Their callback variables remain generalized, so one const value can be shared.
# Dispatch that genuinely needs a caller's type keeps the per-use clone path.
def share_constant(+constant: M.Constant, +previous: SharedConstants, templates: List<&2, String>, entry: String, +stride: Nat, +family_templates: List<&2, M.Operation>, schemes: List<&2, Staging.Scheme>, schema: List<&2, Schema.Evidence>) -> Result<&2, &2, M.Diagnostic, SharedConstants>:
  M.Constant{name, exported, annotation, value} = constant
  SharedConstants{M.Module{+constants, +functions, +types, +operations}, +shapes, shared, counter, certificates} = previous
  +affected = unshared_names(templates, shared)
  +aliases = constant_templates(constants, affected)
  +generic = generic_templates(shapes, affected)
  +configuration = {Configuration{functions, generic, entry, aliases, affected, stride, specialized_constants(constants, generic, shapes), family_templates, 1n, schema} : Configuration}
  do Result<&2, &2, M.Diagnostic, SharedConstants>:
    expanded : ExpandedModule <- expand_declaration(G.ConstantDeclaration{constant}, configuration, types, operations, counter)
    accept_constant(infer_required_optional(expanded, configuration, shapes, True{}, schemes), name, previous)

def share_constants(constants: List<&2, M.Constant>, previous: SharedConstants, +templates: List<&2, String>, +entry: String, +stride: Nat, +family_templates: List<&2, M.Operation>, +schemes: List<&2, Staging.Scheme>, +schema: List<&2, Schema.Evidence>) -> Result<&2, &2, M.Diagnostic, SharedConstants>:
  match constants:
    case Nil{}:
      Done{previous}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, SharedConstants>:
        next : SharedConstants <- share_constant(head, previous, templates, entry, stride, family_templates, schemes, schema)
        share_constants(tail, next, templates, entry, stride, family_templates, schemes, schema)

def prepare_shared(templates: List<&2, String>, prepared: SharedConstants, entry: String, stride: Nat, family_templates: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, M.Module>:
  SharedConstants{M.Module{+constants, +functions, types, operations}, +shapes, shared, counter, certificates} = prepared
  +affected = unshared_names(templates, shared)
  +aliases = constant_templates(constants, affected)
  +generic = generic_templates(shapes, affected)
  +constant_values = specialized_constants(constants, generic, shapes)
  +configuration = {Configuration{functions, generic, entry, aliases, affected, stride, constant_values, family_templates, 1n, Nil{}} : Configuration}
  +retained = retained_specializations(retained_constants(constants, aliases), constant_values)
  specialize(independent_constants(retained, affected, shapes), functions, retained, types, operations, configuration, shapes, counter)

def prepare_templates(templates: List<&2, String>, +module: M.Module, +shapes: List<&2, I.Binding>, +entry: String, +family_templates: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match templates:
    case Nil{}:
      Public.select(module, shapes, Public.Resolved{})
    case +head <> +tail:
      M.Module{+constants, original_functions, types, operations} = module
      do Result<&2, &2, M.Diagnostic, M.Module>:
        +stride : Nat <- identity_limit(U32.to_nat(1048576), module_expressions(original_functions, constants), 0n)
        generic : List<&2, String> = generic_templates(shapes, head <> tail)
        candidates : List<&2, M.Constant> = specialized_constants(constants, generic, shapes)
        nodes : List<&2, D.Node> <- Check.module_graph(module)
        groups : List<&2, List<&2, String>> <- D.components(nodes)
        shared : SharedConstants <- share_constants(ordered_constants(groups, candidates), SharedConstants{module, shapes, Nil{}, 1n, Nil{}}, head <> tail, entry, stride, family_templates, Nil{}, Nil{})
        prepare_shared(head <> tail, shared, entry, stride, family_templates)

def concrete_module(module: M.Module) -> M.Module:
  M.Module{constants, functions, types, operations} = module
  M.Module{constants, functions, types, State.concrete(operations)}

def module_templates(module: M.Module, +nodes: List<&2, D.Node>, initial: Scheduler.Initial) -> List<&2, String>:
  M.Module{constants, functions, types, operations} = module
  template_closure(nodes, List.append(&2, String, certificate_plan_roots(Scheduler.initial_certificates(initial)), List.append(&2, String, seeds(functions), constant_seeds(constants))))

def prepare_shaped(+module: M.Module, entry: String, +family_templates: List<&2, M.Operation>, +nodes: List<&2, D.Node>, +initial: Scheduler.Initial) -> Result<&2, &2, M.Diagnostic, M.Module>:
  do Result<&2, &2, M.Diagnostic, M.Module>:
    +shape : G.Environment <- shape_initial(initial, module)
    +shapes : List<&2, I.Binding> <- resolved_bindings(G.env_bindings(shape), I.substitutions_of(G.env_state(shape)))
    selected : M.Module <- Public.select(module, shapes, Public.Candidates{})
    prepared : M.Module <- prepare_templates(module_templates(module, nodes, initial), selected, shapes, entry, family_templates)
    return concrete_module(prepared)

# Every declaration passes this initial check; only what the entry
# declarations reach is specialized.
def prepare(+module: M.Module, +entry: String, family_templates: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, M.Module>:
  do Result<&2, &2, M.Diagnostic, M.Module>:
    initial : Scheduler.Initial <- Scheduler.check_module_evidenced(module)
    +pruned : Entries.Pruned <- Entries.prune_initial(module, initial, entry)
    +nodes : List<&2, D.Node> <- Check.module_graph(Entries.pruned_module(pruned))
    prepare_shaped(Entries.pruned_module(pruned), entry, family_templates, nodes, Entries.pruned_initial(pruned))

# Dispatch resolution has already checked this exact module.
def prepare_checked(+module: M.Module, entry: String, family_templates: List<&2, M.Operation>, initial: Scheduler.Initial) -> Result<&2, &2, M.Diagnostic, M.Module>:
  do Result<&2, &2, M.Diagnostic, M.Module>:
    +nodes : List<&2, D.Node> <- Check.module_graph(module)
    prepare_shaped(module, entry, family_templates, nodes, initial)

# Cold compilation checks the expanded module after specialization. Defer the
# final export/effect refresh to that check instead of inferring all affected
# declarations here and then inferring the same bodies again.
def specialize_deferred(independent: Bool, originals: List<&2, M.Function>, constants: List<&2, M.Constant>, types: List<&2, M.DataType>, operations: List<&2, M.Operation>, +configuration: Configuration, +shapes: List<&2, I.Binding>, counter: Nat, schemes: List<&2, Staging.Scheme>) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  match independent:
    case True{}:
      do Result<&2, &2, M.Diagnostic, ExpandedModule>:
        compiled : ExpandedModule <- specialize_declarations(List.append(&2, G.Declaration, G.function_declarations(originals), G.constant_declarations(constants)), configuration, shapes, types, operations, counter, schemes)
        return compiled

    case False{}:
      do Result<&2, &2, M.Diagnostic, ExpandedModule>:
        +roots : Expansion <- expand_roots(originals, configuration, counter)
        expanded : ExpandedModule <- expand_constants(constants, configuration, functions(roots), emitted_constants(roots), types, operations, next(roots))
        compiled : ExpandedModule <- infer_expansion_staged(expanded, configuration, shapes, False{}, schemes)
        return compiled

def with_expanded_certificates(expanded: ExpandedModule, prior: List<&2, Core.Certificate>) -> ExpandedModule:
  ExpandedModule{module, counter, bindings, certificates} = expanded
  ExpandedModule{module, counter, bindings, List.append(&2, Core.Certificate, prior, certificates)}

def prepare_shared_deferred(templates: List<&2, String>, prepared: SharedConstants, entry: String, stride: Nat, family_templates: List<&2, M.Operation>, schemes: List<&2, Staging.Scheme>, schema: List<&2, Schema.Evidence>) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  SharedConstants{M.Module{+constants, +functions, types, operations}, +shapes, shared, counter, certificates} = prepared
  +affected = unshared_names(templates, shared)
  +aliases = constant_templates(constants, affected)
  +generic = generic_templates(shapes, affected)
  +constant_values = specialized_constants(constants, generic, shapes)
  +configuration = {Configuration{functions, generic, entry, aliases, affected, stride, constant_values, family_templates, 1n, schema} : Configuration}
  +retained = retained_specializations(retained_constants(constants, aliases), constant_values)
  do Result<&2, &2, M.Diagnostic, ExpandedModule>:
    expanded : ExpandedModule <- specialize_deferred(independent_constants(retained, affected, shapes), functions, retained, types, operations, configuration, shapes, counter, schemes)
    return with_expanded_certificates(expanded, certificates)

def prepare_templates_deferred(templates: List<&2, String>, +module: M.Module, +shapes: List<&2, I.Binding>, +entry: String, +family_templates: List<&2, M.Operation>, checked: M.CheckedModule) -> Result<&2, &2, M.Diagnostic, ExpandedModule>:
  match templates:
    case Nil{}:
      Done{ExpandedModule{module, 0n, Nil{}, Nil{}}}
    case +head <> +tail:
      M.Module{+constants, +original_functions, +types, +operations} = module
      +schemes = Staging.capture_closed(ParallelInfer.data_types_closed(types), original_functions, operations, types)
      +schema = Schema.capture(original_functions, types, checked, entry)
      do Result<&2, &2, M.Diagnostic, ExpandedModule>:
        +stride : Nat <- identity_limit(U32.to_nat(1048576), module_expressions(original_functions, constants), 0n)
        generic : List<&2, String> = generic_templates(shapes, head <> tail)
        candidates : List<&2, M.Constant> = specialized_constants(constants, generic, shapes)
        nodes : List<&2, D.Node> <- Check.module_graph(module)
        groups : List<&2, List<&2, String>> <- D.components(nodes)
        shared : SharedConstants <- share_constants(ordered_constants(groups, candidates), SharedConstants{module, shapes, Nil{}, 1n, Nil{}}, head <> tail, entry, stride, family_templates, schemes, schema)
        prepare_shared_deferred(head <> tail, shared, entry, stride, family_templates, schemes, schema)

# Only groups without deferred dispatch can certify a final-check group.
def prepare_initial_templates(templates: List<&2, String>, +module: M.Module, entry: String, family_templates: List<&2, M.Operation>, +initial: Scheduler.Initial) -> Result<&2, &2, M.Diagnostic, Core.Prepared>:
  match templates:
    case Nil{}:
      Done{Core.Prepared{concrete_module(module), Core.ready_certificates(Scheduler.initial_certificates(initial))}}
    case head <> tail:
      Scheduler.Initial{+checked, certificates, needs} = initial
      do Result<&2, &2, M.Diagnostic, Core.Prepared>:
        +shape : G.Environment <- shape_initial(initial, module)
        +shapes : List<&2, I.Binding> <- resolved_bindings(G.env_bindings(shape), I.substitutions_of(G.env_state(shape)))
        selected : M.Module <- Public.select(module, shapes, Public.Candidates{})
        +prepared : ExpandedModule <- prepare_templates_deferred(head <> tail, selected, shapes, entry, family_templates, checked)
        return Core.Prepared{concrete_module(expanded_module(prepared)), List.append(&2, Core.Certificate, Core.ready_certificates(certificates), expanded_certificates(prepared))}

# Dispatch resolution has already checked this exact module; its certificates
# cover every group, so the final check also reuses the ready ones when no
# template is left.
def prepare_deferred_initial(+module: M.Module, entry: String, family_templates: List<&2, M.Operation>, +initial: Scheduler.Initial) -> Result<&2, &2, M.Diagnostic, Core.Prepared>:
  do Result<&2, &2, M.Diagnostic, Core.Prepared>:
    +nodes : List<&2, D.Node> <- Check.module_graph(module)
    prepare_initial_templates(module_templates(module, nodes, initial), module, entry, family_templates, initial)

# The initial check covers every declaration, even when nothing needs
# specialization; its certificates let the final check retain the groups that
# need none. Dead-code elimination follows it.
def prepare_deferred_core(+module: M.Module, +entry: String, family_templates: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, Core.Prepared>:
  do Result<&2, &2, M.Diagnostic, Core.Prepared>:
    initial : Scheduler.Initial <- Scheduler.check_module_evidenced(module)
    +pruned : Entries.Pruned <- Entries.prune_initial(module, initial, entry)
    prepare_deferred_initial(Entries.pruned_module(pruned), entry, family_templates, Entries.pruned_initial(pruned))

def finish_cached(compiled: CachedExpansion, +context_key: List<&2, U32>, +sources: Map<&2, List<&2, U32>>, +shapes: List<&2, I.Binding>, +configuration: Configuration) -> Result<&2, &2, M.Diagnostic, Prepared>:
  CachedExpansion{expansion, tasks} = compiled
  ExpandedModule{expanded, next, bindings, +certificates} = expansion
  do Result<&2, &2, M.Diagnostic, Prepared>:
    module : M.Module <- public_expansion(expansion, shapes, configuration)
    return Prepared{module, Cache{context_key, tasks, sources, Nil{}}, certificates}

def cached_sources(probe: Result<&2, &2, M.Diagnostic, Map<&2, List<&2, U32>>>, +context_key: List<&2, U32>, originals: List<&2, M.Function>, retained: List<&2, M.Constant>, types: List<&2, M.DataType>, operations: List<&2, M.Operation>, +configuration: Configuration, +shapes: List<&2, I.Binding>, counter: Nat, +nodes: List<&2, D.Node>, +reusable: Reusable) -> Result<&2, &2, M.Diagnostic, Prepared>:
  match probe:
    case Fail{diagnostic}:
      do Result<&2, &2, M.Diagnostic, Prepared>:
        module : M.Module <- specialize(True{}, originals, retained, types, operations, configuration, shapes, counter)
        return Prepared{module, empty_cache(), Nil{}}
    case Done{+current}:
      Reusable{old_tasks, old_sources} = reusable
      +declarations = List.append(&2, G.Declaration, G.function_declarations(originals), G.constant_declarations(retained))
      do Result<&2, &2, M.Diagnostic, Prepared>:
        +compiled : CachedExpansion <- specialize_declarations_cached(declarations, configuration, shapes, types, operations, counter, nodes, old_tasks, old_sources, current)
        finish_cached(compiled, context_key, current, shapes, configuration)

def cached_context(~key: M.Module -> Result<&2, &2, M.Diagnostic, List<&2, U32>>, probe: Result<&2, &2, M.Diagnostic, List<&2, U32>>, +originals: List<&2, M.Function>, source_constants: List<&2, M.Constant>, retained: List<&2, M.Constant>, types: List<&2, M.DataType>, operations: List<&2, M.Operation>, +configuration: Configuration, +shapes: List<&2, I.Binding>, counter: Nat, +nodes: List<&2, D.Node>, previous: Maybe<&2, Cache>) -> Result<&2, &2, M.Diagnostic, Prepared>:
  match probe:
    case Fail{diagnostic}:
      do Result<&2, &2, M.Diagnostic, Prepared>:
        module : M.Module <- specialize(True{}, originals, retained, types, operations, configuration, shapes, counter)
        return Prepared{module, empty_cache(), Nil{}}
    case Done{+context_key}:
      cached_sources(source_keys(~key, originals, source_constants), context_key, originals, retained, types, operations, configuration, shapes, counter, nodes, cache_for_context(previous, context_key))

def cached_specialize(~key: M.Module -> Result<&2, &2, M.Diagnostic, List<&2, U32>>, independent: Bool, +originals: List<&2, M.Function>, +source_constants: List<&2, M.Constant>, +retained: List<&2, M.Constant>, +types: List<&2, M.DataType>, +operations: List<&2, M.Operation>, +configuration: Configuration, +shapes: List<&2, I.Binding>, counter: Nat, +nodes: List<&2, D.Node>, previous: Maybe<&2, Cache>) -> Result<&2, &2, M.Diagnostic, Prepared>:
  match independent:
    case False{}:
      do Result<&2, &2, M.Diagnostic, Prepared>:
        module : M.Module <- specialize(False{}, originals, retained, types, operations, configuration, shapes, counter)
        return Prepared{module, empty_cache(), Nil{}}
    case True{}:
      +declarations = List.append(&2, G.Declaration, G.function_declarations(originals), G.constant_declarations(retained))
      +context : SpecializationContext = SpecializationContext{with_step(configuration, Nat.max(1n, List.length(&2, G.Declaration, declarations))), shapes, types, operations, Nil{}, Done{0n}}
      cached_context(~key, key(context_module(context, nodes)), originals, source_constants, retained, types, operations, configuration, shapes, counter, nodes, previous)

def with_prepared_certificates(prepared: Prepared, prior: List<&2, Core.Certificate>) -> Prepared:
  Prepared{module, cache, certificates} = prepared
  Prepared{module, cache, List.append(&2, Core.Certificate, prior, certificates)}

def prepare_shared_cached(~key: M.Module -> Result<&2, &2, M.Diagnostic, List<&2, U32>>, templates: List<&2, String>, prepared: SharedConstants, entry: String, stride: Nat, family_templates: List<&2, M.Operation>, schema: List<&2, Schema.Evidence>, +nodes: List<&2, D.Node>, previous: Maybe<&2, Cache>) -> Result<&2, &2, M.Diagnostic, Prepared>:
  SharedConstants{M.Module{+constants, +functions, types, operations}, +shapes, shared, counter, certificates} = prepared
  +affected = unshared_names(templates, shared)
  +aliases = constant_templates(constants, affected)
  +generic = generic_templates(shapes, affected)
  +constant_values = specialized_constants(constants, generic, shapes)
  +configuration = {Configuration{functions, generic, entry, aliases, affected, stride, constant_values, family_templates, 1n, schema} : Configuration}
  +retained = retained_specializations(retained_constants(constants, aliases), constant_values)
  do Result<&2, &2, M.Diagnostic, Prepared>:
    result : Prepared <- cached_specialize(~key, independent_constants(retained, affected, shapes), functions, constants, retained, types, operations, configuration, shapes, counter, nodes, previous)
    return with_prepared_certificates(result, certificates)

def prepare_templates_cached(~key: M.Module -> Result<&2, &2, M.Diagnostic, List<&2, U32>>, templates: List<&2, String>, +module: M.Module, +shapes: List<&2, I.Binding>, +entry: String, +family_templates: List<&2, M.Operation>, +nodes: List<&2, D.Node>, previous: Maybe<&2, Cache>, checked: M.CheckedModule) -> Result<&2, &2, M.Diagnostic, Prepared>:
  match templates:
    case Nil{}:
      do Result<&2, &2, M.Diagnostic, Prepared>:
        selected : M.Module <- Public.select(module, shapes, Public.Resolved{})
        return Prepared{selected, empty_cache(), Nil{}}
    case +head <> +tail:
      M.Module{+constants, +original_functions, types, operations} = module
      +schema = Schema.capture(original_functions, types, checked, entry)
      do Result<&2, &2, M.Diagnostic, Prepared>:
        +stride : Nat <- identity_limit(U32.to_nat(1048576), module_expressions(original_functions, constants), 0n)
        generic : List<&2, String> = generic_templates(shapes, head <> tail)
        candidates : List<&2, M.Constant> = specialized_constants(constants, generic, shapes)
        groups : List<&2, List<&2, String>> <- D.components(nodes)
        shared : SharedConstants <- share_constants(ordered_constants(groups, candidates), SharedConstants{module, shapes, Nil{}, 1n, Nil{}}, head <> tail, entry, stride, family_templates, Nil{}, schema)
        prepare_shared_cached(~key, head <> tail, shared, entry, stride, family_templates, schema, nodes, previous)

# The caller supplies the same exact module encoder used by project-session
# cache keys. A key encoding failure falls back to ordinary specialization.
def concrete_prepared(prepared: Prepared) -> Prepared:
  Prepared{expanded, cache, certificates} = prepared
  Prepared{concrete_module(expanded), cache, certificates}

def prepare_cached_nodes(~key: M.Module -> Result<&2, &2, M.Diagnostic, List<&2, U32>>, +module: M.Module, entry: String, +family_templates: List<&2, M.Operation>, +nodes: List<&2, D.Node>, previous: Maybe<&2, Cache>, +initial: Scheduler.Initial) -> Result<&2, &2, M.Diagnostic, Prepared>:
  Scheduler.Initial{+checked, certificates, needs} = initial
  do Result<&2, &2, M.Diagnostic, Prepared>:
    +shape : G.Environment <- shape_initial(initial, module)
    +shapes : List<&2, I.Binding> <- resolved_bindings(G.env_bindings(shape), I.substitutions_of(G.env_state(shape)))
    selected : M.Module <- Public.select(module, shapes, Public.Candidates{})
    prepared : Prepared <- prepare_templates_cached(~key, module_templates(module, nodes, initial), selected, shapes, entry, family_templates, nodes, previous, checked)
    return with_prepared_certificates(concrete_prepared(prepared), Core.ready_certificates(certificates))

def prepare_cached_evidenced(~key: M.Module -> Result<&2, &2, M.Diagnostic, List<&2, U32>>, +module: M.Module, +entry: String, family_templates: List<&2, M.Operation>, +previous: Maybe<&2, Cache>) -> Result<&2, &2, M.Diagnostic, Prepared>:
  do Result<&2, &2, M.Diagnostic, Prepared>:
    # Even a revision with no dispatch must publish source-ready certificates:
    # its next edit may introduce dispatch or fail while other groups remain.
    +initial : Scheduler.Initial <- Scheduler.check_module_resolving(module, source_certificates(previous))
    +pruned : Entries.Pruned <- Entries.prune_initial(module, initial, entry)
    +nodes : List<&2, D.Node> <- Check.module_graph(Entries.pruned_module(pruned))
    prepared : Prepared <- prepare_cached_nodes(~key, Entries.pruned_module(pruned), entry, family_templates, nodes, previous, Entries.pruned_initial(pruned))
    return with_source_certificates(prepared, Scheduler.initial_certificates(initial))

# Dispatch resolution has already checked this exact module.
def prepare_cached_initial(~key: M.Module -> Result<&2, &2, M.Diagnostic, List<&2, U32>>, +module: M.Module, entry: String, family_templates: List<&2, M.Operation>, previous: Maybe<&2, Cache>, initial: Scheduler.Initial) -> Result<&2, &2, M.Diagnostic, Prepared>:
  do Result<&2, &2, M.Diagnostic, Prepared>:
    +nodes : List<&2, D.Node> <- Check.module_graph(module)
    prepare_cached_nodes(~key, module, entry, family_templates, nodes, previous, initial)
