import Base
import ./model.bend as M
import ./infer.bend as I
import ./globals.bend as G
import ./types.bend as T
import ./staging_residual.bend as R
import ./closures.bend as F
import ./nat_index.bend as NatIndex
import ./core_compare.bend as Compare

# A principal source inference for the built-in type-witness equality function.
# Its body contains no global or captured references; the source is checked
# independently, and the caller must also prove an exact expanded clone match.
type Scheme is Data:
  Scheme{source: M.Function, inference: I.Inference, variables: List<&2, Nat>, allocated: Nat, types: List<&2, M.DataType>}

# Reject every global, closure capture, operation or arbitrary call. The only
# unresolved choice permitted by this slice is the exact @type.same request.
def safe_work(+fuel: Nat, pending: List<&2, M.Expr>) -> Bool:
  match fuel pending:
    case _ Nil{}:
      True{}
    case 0n _:
      False{}
    case 1n+rest M.SourceExpr{offset, None{}, value} <> tail:
      safe_work(rest, value <> tail)
    case 1n+rest M.LambdaExpr{identity, parameter, None{}, None{}, body} <> tail:
      safe_work(rest, body <> tail)
    case 1n+rest M.MatchExpr{values, arms} <> tail:
      safe_work(rest, List.append(&2, M.Expr, F.children(M.MatchExpr{values, arms}), tail))
    case 1n+rest M.AssociatedExpr{identity, M.BinaryDispatch{}, member, Nil{}, left, right} <> tail:
      Bool.and(M.name_equal(member, "@type.same"), safe_work(rest, left <> right <> tail))
    case 1n+rest M.LocalExpr{name} <> tail:
      safe_work(rest, tail)
    case _ _:
      False{}

def eligible(function: M.Function) -> Bool:
  match function:
    case M.Function{name, exported, parameter, None{}, None{}, body}:
      Bool.and(M.name_equal(name, "$prelude.Type.eq"), safe_work(65536n, [body]))
    case _:
      False{}

def type_equality_inference(value: I.Inference) -> Bool:
  # Match children omit pattern expressions. The exact coverage shape below
  # also rejects ValuePatternType, so no hidden pattern reference is replayed.
  match value:
    case I.Inference{M.FunctionTy{parameter, result, effects}, I.Coverage{inferred, patterns, coverage_subject} <> I.AssociatedNeed{identity, M.BinaryDispatch{}, member, Nil{}, left, right, selected, ambient, subject} <> Nil{}, Nil{}, Nil{}}:
      Bool.and(M.name_equal(member, "@type.same"), M.name_equal(subject, "offset:" ++ Nat.show(identity)))
    case _:
      False{}

def captured_free(free: Result<&2, &2, M.Diagnostic, List<&2, Nat>>, source: M.Function, +inference: I.Inference, +allocated: Nat, types: List<&2, M.DataType>) -> Maybe<&2, Scheme>:
  match free:
    case Fail{diagnostic}:
      None{}
    case Done{+variables}:
      Bool.pick(Maybe<&2, Scheme>, Bool.and(Nat.is_ge(allocated, 3n), Bool.and(Nat.is_le(T.above(variables, 0n), allocated), type_equality_inference(inference))), Some{Scheme{source, inference, variables, allocated, types}}, None{})

def captured_resolved(resolved: Result<&2, &2, M.Diagnostic, I.Inference>, +source: M.Function, allocated: Nat, types: List<&2, M.DataType>) -> Maybe<&2, Scheme>:
  match resolved:
    case Fail{diagnostic}:
      None{}
    case Done{+inference}:
      captured_free(R.free(inference), source, inference, allocated, types)

def captured(result: Result<&2, &2, M.Diagnostic, G.Environment>, +source: M.Function, types: List<&2, M.DataType>) -> Maybe<&2, Scheme>:
  match result:
    case Fail{diagnostic}:
      None{}
    case Done{G.Environment{bindings, definitions, +state}}:
      match definitions:
        case I.Definition{name, inference} <> Nil{}:
          captured_resolved(R.resolve(inference, I.substitutions_of(state)), source, I.next_of(state), types)
        case _:
          None{}

def capture_one(function: M.Function, operations: List<&2, M.Operation>, +types: List<&2, M.DataType>) -> Maybe<&2, Scheme>:
  match function:
    case +source:
      M.Function{+name, exported, parameter, annotation, result, body} = source
      +declarations = G.function_declarations([source])
      +initial = G.initial_bindings(declarations, 0n)
      captured(G.infer_component([name], declarations, G.Environment{initial, Nil{}, I.State{T.empty(), G.initial_next(declarations, 0n), MTip{}}}, operations, types, [name]), source, types)

def capture_if(allowed: Bool, function: M.Function, operations: List<&2, M.Operation>, types: List<&2, M.DataType>) -> Maybe<&2, Scheme>:
  match allowed:
    case False{}:
      None{}
    case True{}:
      capture_one(function, operations, types)

def append(found: Maybe<&2, Scheme>, rest: List<&2, Scheme>) -> List<&2, Scheme>:
  match found:
    case None{}:
      rest
    case Some{value}:
      value <> rest

def capture(functions: List<&2, M.Function>, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>) -> List<&2, Scheme>:
  match functions:
    case Nil{}:
      Nil{}
    case +head <> tail:
      append(capture_if(eligible(head), head, operations, types), capture(tail, operations, types))

def capture_closed(closed: Bool, functions: List<&2, M.Function>, operations: List<&2, M.Operation>, types: List<&2, M.DataType>) -> List<&2, Scheme>:
  match closed:
    case False{}:
      Nil{}
    case True{}:
      capture(functions, operations, types)

type CloneName is Data:
  CloneName{counter: Nat, source: String}

def parsed_number(value: Maybe<&2, Nat>, source: String) -> Maybe<&2, CloneName>:
  match value:
    case None{}:
      None{}
    case Some{counter}:
      Some{CloneName{counter, source}}

def parse_digits(value: String, reversed: String) -> Maybe<&2, CloneName>:
  match value:
    case SCon{Chr{93}, SCon{Chr{46}, source}}:
      parsed_number(Nat.read(String.reverse(reversed)), source)
    case SCon{character, tail}:
      parse_digits(tail, SCon{character, reversed})
    case SNil{}:
      None{}

def parse_prefix(found: Bool, name: String) -> Maybe<&2, CloneName>:
  match found:
    case False{}:
      None{}
    case True{}:
      parse_digits(String.drop(name, 6n), SNil{})

def clone_name(+name: String) -> Maybe<&2, CloneName>:
  parse_prefix(String.starts_with(name, "$mono["), name)

def source_name(source: M.Function) -> String:
  M.Function{name, exported, parameter, annotation, result, body} = source
  name

def scheme_source(scheme: Scheme) -> M.Function:
  Scheme{source, inference, variables, allocated, types} = scheme
  source

def matches_source(scheme: Scheme, parsed: CloneName) -> Bool:
  Scheme{source, inference, variables, allocated, types} = scheme
  CloneName{counter, original} = parsed
  M.name_equal(source_name(source), original)

type Placeholder is Data:
  Placeholder{parameter: Nat, result: Nat, row: Nat, ty: M.Ty}

def placeholder(found: Maybe<&2, I.Binding>, +wanted: String) -> Maybe<&2, Placeholder>:
  match found:
    case Some{I.Binding{name, M.FunctionTy{M.VariableTy{+p}, M.VariableTy{+r}, M.EffectRow{Nil{}, M.RowVariable{+e}}}, Nil{}}}:
      Bool.pick(Maybe<&2, Placeholder>, M.name_equal(name, wanted), Some{Placeholder{p, r, e, M.FunctionTy{M.VariableTy{p}, M.VariableTy{r}, M.EffectRow{Nil{}, M.RowVariable{e}}}}}, None{})
    case _:
      None{}

def map_body(remaining: Nat, +old: Nat, +fresh: Nat, mapping: NatIndex.Index<Nat>) -> NatIndex.Index<Nat>:
  match remaining:
    case 0n:
      mapping
    case 1n+rest:
      map_body(rest, 1n+old, 1n+fresh, NatIndex.set(Nat, mapping, old, fresh))

def mapping(placeholder: Placeholder, allocated: Nat, next: Nat) -> NatIndex.Index<Nat>:
  Placeholder{p, r, e, ty} = placeholder
  +head = NatIndex.set(Nat, NatIndex.set(Nat, NatIndex.set(Nat, NatIndex.new(Nat), 0n, p), 1n, r), 2n, e)
  map_body(Nat.sub(allocated, 3n), 3n, next, head)

def replay_unified(result: Result<&2, &2, M.Diagnostic, I.State>, +name: String, inference: I.Inference, bindings: List<&2, I.Binding>, definitions: List<&2, I.Definition>) -> Maybe<&2, G.Environment>:
  match result:
    case Fail{diagnostic}:
      None{}
    case Done{state}:
      Some{G.Environment{bindings, I.Definition{name, inference} <> definitions, I.clear_annotations(state)}}

def replay_offset(result: Result<&2, &2, M.Diagnostic, I.Inference>, +name: String, placeholder: Placeholder, +state: I.State, bindings: List<&2, I.Binding>, definitions: List<&2, I.Definition>, next: Nat) -> Maybe<&2, G.Environment>:
  match result:
    case Fail{diagnostic}:
      None{}
    case Done{+inference}:
      Placeholder{p, r, e, expected} = placeholder
      replay_unified(I.unify(I.inferred_type(inference), expected, I.with_next(state, next), name), name, inference, bindings, definitions)

def replay_renamed(result: Result<&2, &2, M.Diagnostic, I.Inference>, name: String, base: Nat, placeholder: Placeholder, state: I.State, bindings: List<&2, I.Binding>, definitions: List<&2, I.Definition>, next: Nat) -> Maybe<&2, G.Environment>:
  match result:
    case Fail{diagnostic}:
      None{}
    case Done{inference}:
      replay_offset(R.offset_identities(inference, base), name, placeholder, state, bindings, definitions, next)

def scheme_inference(scheme: Scheme) -> I.Inference:
  Scheme{source, inference, variables, allocated, types} = scheme
  inference

def scheme_allocated(scheme: Scheme) -> Nat:
  Scheme{source, inference, variables, allocated, types} = scheme
  allocated

def clone_counter(parsed: CloneName) -> Nat:
  CloneName{counter, source} = parsed
  counter

def replay_with_space(fits: Bool, +placeholder: Placeholder, +scheme: Scheme, clone: M.Function, parsed: CloneName, stride: Nat, +environment: G.Environment) -> Maybe<&2, G.Environment>:
  match fits:
    case False{}:
      None{}
    case True{}:
      +name = source_name(clone)
      +allocated = scheme_allocated(scheme)
      +next = I.next_of(G.env_state(environment))
      +advanced = Nat.add(next, Nat.sub(allocated, 3n))
      replay_renamed(R.rewrite_inference(scheme_inference(scheme), R.Alpha{mapping(placeholder, allocated, next), NatIndex.new(Nat)}), name, Nat.mul(clone_counter(parsed), stride), placeholder, G.env_state(environment), G.env_bindings(environment), G.env_definitions(environment), advanced)

def max_nat48() -> Nat:
  Nat.add(Nat.mul(U32.to_nat(4294967295), 65536n), 65535n)

def replay_placeholder(found: Maybe<&2, Placeholder>, +scheme: Scheme, clone: M.Function, parsed: CloneName, stride: Nat, +environment: G.Environment) -> Maybe<&2, G.Environment>:
  match found:
    case None{}:
      None{}
    case Some{+placeholder}:
      +allocated = scheme_allocated(scheme)
      +next = I.next_of(G.env_state(environment))
      replay_with_space(Nat.is_le(Nat.sub(allocated, 3n), Nat.sub(max_nat48(), next)), placeholder, scheme, clone, parsed, stride, environment)

def clean_state(state: I.State) -> Bool:
  match state:
    case I.State{substitutions, next, MTip{}}:
      True{}
    case _:
      False{}

def replay_if_clean(clean: Bool, found: Maybe<&2, Placeholder>, scheme: Scheme, clone: M.Function, parsed: CloneName, stride: Nat, environment: G.Environment) -> Maybe<&2, G.Environment>:
  match clean:
    case False{}:
      None{}
    case True{}:
      replay_placeholder(found, scheme, clone, parsed, stride, environment)

def replay_scheme(allowed: Bool, scheme: Scheme, +clone: M.Function, parsed: CloneName, stride: Nat, +environment: G.Environment) -> Maybe<&2, G.Environment>:
  match allowed:
    case False{}:
      None{}
    case True{}:
      +name = source_name(clone)
      replay_if_clean(clean_state(G.env_state(environment)), placeholder(I.lookup_binding(G.env_bindings(environment), name), name), scheme, clone, parsed, stride, environment)

def lookup(schemes: List<&2, Scheme>, +wanted: String) -> Maybe<&2, Scheme>:
  match schemes:
    case Nil{}:
      None{}
    case +head <> tail:
      Scheme{source, inference, variables, allocated, types} = head
      Bool.pick(Maybe<&2, Scheme>, M.name_equal(source_name(source), wanted), Some{head}, lookup(tail, wanted))

type Candidate is Data:
  Candidate{scheme: Scheme, parsed: CloneName}

def candidate_found(found: Maybe<&2, Scheme>, +parsed: CloneName) -> Maybe<&2, Candidate>:
  match found:
    case None{}:
      None{}
    case Some{+scheme}:
      Bool.pick(Maybe<&2, Candidate>, matches_source(scheme, parsed), Some{Candidate{scheme, parsed}}, None{})

def candidate_parsed(found: Maybe<&2, CloneName>, schemes: List<&2, Scheme>) -> Maybe<&2, Candidate>:
  match found:
    case None{}:
      None{}
    case Some{+parsed}:
      CloneName{counter, original} = parsed
      candidate_found(lookup(schemes, original), parsed)

def candidate(clone: M.Function, schemes: List<&2, Scheme>) -> Maybe<&2, Candidate>:
  candidate_parsed(clone_name(source_name(clone)), schemes)

def candidate_source(value: Candidate) -> M.Function:
  Candidate{scheme, parsed} = value
  scheme_source(scheme)

def candidate_counter(value: Candidate) -> Nat:
  Candidate{scheme, parsed} = value
  clone_counter(parsed)

def replay(value: Candidate, clone: M.Function, stride: Nat, environment: G.Environment, current_types: List<&2, M.DataType>, exact: Bool) -> Maybe<&2, G.Environment>:
  Candidate{+scheme, parsed} = value
  Scheme{source, inference, variables, allocated, +types} = scheme
  replay_scheme(Bool.and(exact, Compare.compare(1048576n, [Compare.DataTypeListPair{types, current_types}], True{})), scheme, clone, parsed, stride, environment)
