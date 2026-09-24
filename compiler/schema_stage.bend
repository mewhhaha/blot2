import Base
import ./model.bend as M
import ./core_compare.bend as Compare
import ./type_data.bend as TD
import ./state_specialize.bend as State
import ./groups.bend as Groups
import ./members.bend as Members

# A source-checked, closed, pure linked-schema reduction. Capture is called only
# after Scheduler.check_module_evidenced succeeds. Every syntactic dependency is
# retained so a changed source or nominal declaration makes selection fall back.
type Evidence is Data:
  Evidence{node_method: M.Function, terminal_method: M.Function, equality: M.Function, type_equality: M.Function, node_type: M.DataType, terminal_type: M.DataType, witness_type: M.DataType, node_constructor: String, terminal_identity: M.TypeId, node_identity: M.TypeId, member: String}

type NodeShape is Data:
  NodeShape{constructor: String, member: String, equality: String, witness_constructor: String}

type EqualCall is Data:
  EqualCall{function: String, constructor: String}

type Terminal is Data:
  Terminal{function: M.Function, data_type: M.DataType}

def node_constructor(shape: NodeShape) -> String:
  NodeShape{constructor, member, equality, witness_constructor} = shape
  constructor

def node_member(shape: NodeShape) -> String:
  NodeShape{constructor, member, equality, witness_constructor} = shape
  member

def node_equality(shape: NodeShape) -> String:
  NodeShape{constructor, member, equality, witness_constructor} = shape
  equality

def witness_constructor(shape: NodeShape) -> String:
  NodeShape{constructor, member, equality, witness_constructor} = shape
  witness_constructor

def distinct2(a: String, b: String) -> Bool:
  Bool.not(M.name_equal(a, b))

def distinct4(+a: String, +b: String, +c: String, +d: String) -> Bool:
  Bool.and(distinct2(a, b), Bool.and(distinct2(a, c), Bool.and(distinct2(a, d), Bool.and(distinct2(b, c), Bool.and(distinct2(b, d), distinct2(c, d))))))

def distinct5(+a: String, +b: String, +c: String, +d: String, +e: String) -> Bool:
  Bool.and(distinct4(a, b, c, d), Bool.and(distinct2(a, e), Bool.and(distinct2(b, e), Bool.and(distinct2(c, e), distinct2(d, e)))))

def bare(value: M.Expr) -> Maybe<&2, M.Expr>:
  match value:
    case M.SourceExpr{offset, None{}, inner}:
      bare(inner)
    case M.SourceExpr{offset, Some{annotation}, inner}:
      None{}
    case other:
      Some{other}

def local_bare(value: Maybe<&2, M.Expr>, wanted: String) -> Bool:
  match value:
    case Some{M.LocalExpr{name}}:
      M.name_equal(name, wanted)
    case _:
      False{}

def local(value: M.Expr, wanted: String) -> Bool:
  local_bare(bare(value), wanted)

def unit_bare(value: Maybe<&2, M.Expr>) -> Bool:
  match value:
    case Some{M.UnitExpr{}}:
      True{}
    case _:
      False{}

def unit(value: M.Expr) -> Bool:
  unit_bare(bare(value))

def boolean_bare(value: Maybe<&2, M.Expr>, wanted: Bool) -> Bool:
  match value wanted:
    case Some{M.BoolExpr{True{}}} True{}:
      True{}
    case Some{M.BoolExpr{False{}}} False{}:
      True{}
    case _ _:
      False{}

def boolean(value: M.Expr, wanted: Bool) -> Bool:
  boolean_bare(bare(value), wanted)

def type_argument_callee(value: Maybe<&2, M.Expr>, argument: M.Expr, variable: String) -> Maybe<&2, String>:
  match value:
    case Some{M.ConstructorRefExpr{constructor}}:
      Bool.pick(Maybe<&2, String>, local(argument, variable), Some{constructor}, None{})
    case _:
      None{}

def type_argument_bare(value: Maybe<&2, M.Expr>, variable: String) -> Maybe<&2, String>:
  match value:
    case Some{M.ApplyExpr{callee, argument}}:
      type_argument_callee(bare(callee), argument, variable)
    case _:
      None{}

def type_argument(value: M.Expr, variable: String) -> Maybe<&2, String>:
  type_argument_bare(bare(value), variable)

def equal_arguments(left: Maybe<&2, String>, right: Maybe<&2, String>, function: String) -> Maybe<&2, EqualCall>:
  match left right:
    case Some{+a} Some{b}:
      Bool.pick(Maybe<&2, EqualCall>, M.name_equal(a, b), Some{EqualCall{function, a}}, None{})
    case _ _:
      None{}

def equality_callee(value: Maybe<&2, M.Expr>, argument: M.Expr, witness: String, head: String) -> Maybe<&2, EqualCall>:
  match value:
    case Some{M.CallExpr{function, left}}:
      equal_arguments(type_argument(left, head), type_argument(argument, witness), function)
    case _:
      None{}

def equality_bare(value: Maybe<&2, M.Expr>, witness: String, head: String) -> Maybe<&2, EqualCall>:
  match value:
    case Some{M.ApplyExpr{callee, argument}}:
      equality_callee(bare(callee), argument, witness, head)
    case _:
      None{}

def equality(value: M.Expr, witness: String, head: String) -> Maybe<&2, EqualCall>:
  equality_bare(bare(value), witness, head)

def returned_bool_bare(value: Maybe<&2, M.Expr>, label: Nat, wanted: Bool) -> Bool:
  match value:
    case Some{M.ReturnExpr{found, body}}:
      Bool.and(Nat.is_eq(found, label), boolean(body, wanted))
    case _:
      False{}

def returned_bool(value: M.Expr, label: Nat, wanted: Bool) -> Bool:
  returned_bool_bare(bare(value), label, wanted)

def tail_member_bare(value: Maybe<&2, M.Expr>, tail: String) -> Maybe<&2, String>:
  match value:
    case Some{M.AssociatedExpr{identity, M.MemberDispatch{}, member, Nil{}, receiver, right}}:
      Bool.pick(Maybe<&2, String>, Bool.and(local(receiver, tail), unit(right)), Some{member}, None{})
    case _:
      None{}

def tail_call_callee(value: Maybe<&2, M.Expr>, argument: M.Expr, witness: String, tail: String) -> Maybe<&2, String>:
  match value:
    case Some{M.AssociatedExpr{identity, M.MemberDispatch{}, member, Nil{}, receiver, right}}:
      Bool.pick(Maybe<&2, String>, Bool.and(local(receiver, tail), Bool.and(unit(right), local(argument, witness))), Some{member}, None{})
    case _:
      None{}

def tail_call_bare(value: Maybe<&2, M.Expr>, witness: String, tail: String) -> Maybe<&2, String>:
  match value:
    case Some{M.ApplyExpr{callee, argument}}:
      tail_call_callee(bare(callee), argument, witness, tail)
    case _:
      None{}

def returned_tail_bare(value: Maybe<&2, M.Expr>, label: Nat, witness: String, tail: String) -> Maybe<&2, String>:
  match value:
    case Some{M.ReturnExpr{found, body}}:
      Bool.pick(Maybe<&2, String>, Nat.is_eq(found, label), tail_call_bare(bare(body), witness, tail), None{})
    case _:
      None{}

def returned_tail(value: M.Expr, label: Nat, witness: String, tail: String) -> Maybe<&2, String>:
  returned_tail_bare(bare(value), label, witness, tail)

def branch_bare(value: Maybe<&2, M.Expr>, label: Nat, witness: String, head: String) -> Maybe<&2, EqualCall>:
  match value:
    case Some{M.IfExpr{condition, consequent, alternative}}:
      Bool.pick(Maybe<&2, EqualCall>, Bool.and(returned_bool(consequent, label, True{}), unit(alternative)), equality(condition, witness, head), None{})
    case _:
      None{}

def joined_parts(equal: Maybe<&2, EqualCall>, member: Maybe<&2, String>, constructor: String) -> Maybe<&2, NodeShape>:
  match equal member:
    case Some{EqualCall{function, witness_constructor}} Some{name}:
      Some{NodeShape{constructor, name, function, witness_constructor}}
    case _ _:
      None{}

def node_sequence_bare(value: Maybe<&2, M.Expr>, constructor: String, +label: Nat, +witness: String, head: String, tail: String) -> Maybe<&2, NodeShape>:
  match value:
    case Some{M.SequenceExpr{first, next}}:
      joined_parts(branch_bare(bare(first), label, witness, head), returned_tail(next, label, witness, tail), constructor)
    case _:
      None{}

def node_arm(value: M.MatchArm<M.Expr>, label: Nat, +receiver: String, +temporary: String, +witness: String) -> Maybe<&2, NodeShape>:
  match value:
    case M.MatchArm{M.ConstructorPattern{constructor, Some{M.ProductPattern{M.BindingPattern{+head} <> M.BindingPattern{+tail} <> Nil{}}}} <> Nil{}, body}:
      Bool.pick(Maybe<&2, NodeShape>, distinct5(receiver, temporary, witness, head, tail), node_sequence_bare(bare(body), constructor, label, witness, head, tail), None{})
    case _:
      None{}

def node_match_bare(value: Maybe<&2, M.Expr>, +temporary: String, label: Nat, receiver: String, witness: String) -> Maybe<&2, NodeShape>:
  match value:
    case Some{M.MatchExpr{M.LocalExpr{found} <> Nil{}, arm <> Nil{}}}:
      Bool.pick(Maybe<&2, NodeShape>, M.name_equal(found, temporary), node_arm(arm, label, receiver, temporary, witness), None{})
    case _:
      None{}

def node_let_bare(value: Maybe<&2, M.Expr>, +receiver: String, label: Nat, witness: String) -> Maybe<&2, NodeShape>:
  match value:
    case Some{M.LetExpr{temporary, subject, body}}:
      Bool.pick(Maybe<&2, NodeShape>, local(subject, receiver), node_match_bare(bare(body), temporary, label, receiver, witness), None{})
    case _:
      None{}

def node_block_bare(value: Maybe<&2, M.Expr>, receiver: String, witness: String) -> Maybe<&2, NodeShape>:
  match value:
    case Some{M.BlockExpr{label, body}}:
      node_let_bare(bare(body), receiver, label, witness)
    case _:
      None{}

def node_lambda_bare(value: Maybe<&2, M.Expr>, receiver: String) -> Maybe<&2, NodeShape>:
  match value:
    case Some{M.LambdaExpr{identity, witness, None{}, None{}, body}}:
      node_block_bare(bare(body), receiver, witness)
    case _:
      None{}

def node(function: M.Function) -> Maybe<&2, NodeShape>:
  match function:
    case M.Function{name, exported, receiver, None{}, None{}, body}:
      node_lambda_bare(bare(body), receiver)
    case _:
      None{}

def terminal_lambda_bare(value: Maybe<&2, M.Expr>) -> Bool:
  match value:
    case Some{M.LambdaExpr{identity, witness, None{}, None{}, body}}:
      boolean(body, False{})
    case _:
      False{}

def terminal(function: M.Function) -> Bool:
  match function:
    case M.Function{name, exported, receiver, parameter_type, None{}, body}:
      terminal_lambda_bare(bare(body))
    case _:
      False{}

def forwarded_call_bare(value: Maybe<&2, M.Expr>, left: String, right: String) -> Bool:
  match value:
    case Some{M.AssociatedExpr{identity, M.BinaryDispatch{}, member, Nil{}, a, b}}:
      Bool.and(M.name_equal(member, "eq"), Bool.and(local(a, left), local(b, right)))
    case _:
      False{}

def forwarding_lambda_bare(value: Maybe<&2, M.Expr>, +left: String) -> Bool:
  match value:
    case Some{M.LambdaExpr{identity, +right, None{}, None{}, body}}:
      Bool.and(distinct2(left, right), forwarded_call_bare(bare(body), left, right))
    case _:
      False{}

def equality_forwarder(function: M.Function) -> Bool:
  match function:
    case M.Function{name, exported, left, None{}, None{}, body}:
      forwarding_lambda_bare(bare(body), left)
    case _:
      False{}

def type_same_bare(value: Maybe<&2, M.Expr>, left: String, right: String) -> Bool:
  match value:
    case Some{M.AssociatedExpr{identity, M.BinaryDispatch{}, member, Nil{}, a, b}}:
      Bool.and(M.name_equal(member, "@type.same"), Bool.and(local(a, left), local(b, right)))
    case _:
      False{}

def type_eq_arm(value: M.MatchArm<M.Expr>, +outer_left: String, +outer_right: String) -> Maybe<&2, String>:
  match value:
    case M.MatchArm{M.ConstructorPattern{+left_constructor, Some{M.BindingPattern{+left}}} <> M.ConstructorPattern{right_constructor, Some{M.BindingPattern{+right}}} <> Nil{}, body}:
      Bool.pick(Maybe<&2, String>, Bool.and(distinct4(outer_left, outer_right, left, right), Bool.and(M.name_equal(left_constructor, right_constructor), type_same_bare(bare(body), left, right))), Some{left_constructor}, None{})
    case _:
      None{}

def type_eq_match_bare(value: Maybe<&2, M.Expr>, +left: String, +right: String) -> Maybe<&2, String>:
  match value:
    case Some{M.MatchExpr{a <> b <> Nil{}, arm <> Nil{}}}:
      Bool.pick(Maybe<&2, String>, Bool.and(local(a, left), local(b, right)), type_eq_arm(arm, left, right), None{})
    case _:
      None{}

def type_eq_lambda_bare(value: Maybe<&2, M.Expr>, left: String) -> Maybe<&2, String>:
  match value:
    case Some{M.LambdaExpr{identity, right, None{}, None{}, body}}:
      type_eq_match_bare(bare(body), left, right)
    case _:
      None{}

def type_equality(function: M.Function) -> Maybe<&2, String>:
  match function:
    case M.Function{name, exported, left, None{}, None{}, body}:
      type_eq_lambda_bare(bare(body), left)
    case _:
      None{}

def name(function: M.Function) -> String:
  M.Function{name, exported, parameter, p, r, body} = function
  name

def find_function_work(functions: List<&2, M.Function>, +wanted: String, found: Maybe<&2, M.Function>) -> Maybe<&2, M.Function>:
  match functions found:
    case _ Some{value}:
      Some{value}
    case Nil{} None{}:
      None{}
    case +head <> tail None{}:
      find_function_work(tail, wanted, Bool.pick(Maybe<&2, M.Function>, M.name_equal(name(head), wanted), Some{head}, None{}))

def find_function(functions: List<&2, M.Function>, wanted: String) -> Maybe<&2, M.Function>:
  find_function_work(functions, wanted, None{})

def certified_if_named(same: Bool, function: M.Function, source: M.Function) -> Bool:
  match same:
    case False{}:
      False{}
    case True{}:
      Compare.compare(1048576n, [Compare.FunctionPair{function, source}], True{})

def certified_function_work(checked: List<&2, M.CheckedFunction>, +source: M.Function, found: Bool) -> Bool:
  match checked found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case M.CheckedFunction{+function, signature, effects} <> tail False{}:
      certified_function_work(tail, source, certified_if_named(M.name_equal(name(function), name(source)), function, source))

def certified_function(checked: List<&2, M.CheckedFunction>, source: M.Function) -> Bool:
  certified_function_work(checked, source, False{})

def node_catalog(found: Maybe<&2, M.DataType>, constructor: String) -> Maybe<&2, M.DataType>:
  match found:
    case Some{+value}:
      match value:
        case M.DataType{identity, 2n, M.Constructor{name, Some{M.ProductTy{M.ParameterTy{0n} <> M.ParameterTy{1n} <> Nil{}}}, fields} <> Nil{}}:
          Bool.pick(Maybe<&2, M.DataType>, M.name_equal(name, constructor), Some{value}, None{})
        case _:
          None{}
    case None{}:
      None{}

def terminal_catalog(found: Maybe<&2, M.DataType>) -> Maybe<&2, M.DataType>:
  match found:
    case Some{+value}:
      match value:
        case M.DataType{identity, 0n, M.Constructor{name, None{}, fields} <> Nil{}}:
          Some{value}
        case _:
          None{}
    case None{}:
      None{}

def witness_catalog(found: Maybe<&2, M.DataType>, constructor: String) -> Maybe<&2, M.DataType>:
  match found:
    case Some{+value}:
      match value:
        case M.DataType{identity, 1n, M.Constructor{name, Some{M.ParameterTy{0n}}, Nil{}} <> Nil{}}:
          Bool.pick(Maybe<&2, M.DataType>, M.name_equal(name, constructor), Some{value}, None{})
        case _:
          None{}
    case None{}:
      None{}

def type_identity(value: M.DataType) -> M.TypeId:
  M.DataType{identity, parameters, constructors} = value
  identity

def constructor_identity(value: TD.ConstructorDefinition) -> M.TypeId:
  TD.ConstructorDefinition{identity, parameters, payload} = value
  identity

def nominal_prefix(identity: M.TypeId, +entry: String) -> String:
  M.TypeId{+module_name, declaration} = identity
  Bool.pick(String, M.name_equal(module_name, "std/prelude"), "$prelude.", Bool.pick(String, M.name_equal(module_name, entry), "", "$module[" ++ module_name ++ "].")) ++ declaration

def method_name(identity: M.TypeId, entry: String, member: String) -> String:
  nominal_prefix(identity, entry) ++ "." ++ member

def same_name(left: M.Function, right: String) -> Bool:
  M.name_equal(name(left), right)

def found_function(found: Maybe<&2, M.Function>, checked: List<&2, M.CheckedFunction>) -> Maybe<&2, M.Function>:
  match found:
    case None{}:
      None{}
    case Some{+function}:
      Bool.pick(Maybe<&2, M.Function>, certified_function(checked, function), Some{function}, None{})

def terminal_from_catalog(found: Maybe<&2, M.DataType>, +source: M.Function, +identity: M.TypeId, +member: String, +entry: String, +checked: List<&2, M.CheckedFunction>) -> Maybe<&2, Terminal>:
  match found:
    case Some{ty}:
      Bool.pick(Maybe<&2, Terminal>, Bool.and(terminal(source), Bool.and(M.name_equal(name(source), method_name(identity, entry, member)), certified_function(checked, source))), Some{Terminal{source, ty}}, None{})
    case None{}:
      None{}

def terminal_source(function: M.Function, member: String, entry: String, types: List<&2, M.DataType>, checked: List<&2, M.CheckedFunction>) -> Maybe<&2, Terminal>:
  match function:
    case +source:
      match source:
        case M.Function{name, exported, receiver, Some{M.AppliedTy{identity, Nil{}}}, result, body}:
          terminal_from_catalog(terminal_catalog(TD.lookup(types, identity)), source, identity, member, entry, checked)
        case _:
          None{}

def find_terminal_work(functions: List<&2, M.Function>, found: Maybe<&2, Terminal>, +member: String, +entry: String, +types: List<&2, M.DataType>, +checked: List<&2, M.CheckedFunction>) -> Maybe<&2, Terminal>:
  match functions found:
    case _ Some{pair}:
      Some{pair}
    case Nil{} None{}:
      None{}
    case head <> tail None{}:
      find_terminal_work(tail, terminal_source(head, member, entry, types, checked), member, entry, types, checked)

def find_terminal(functions: List<&2, M.Function>, member: String, entry: String, types: List<&2, M.DataType>, checked: List<&2, M.CheckedFunction>) -> Maybe<&2, Terminal>:
  find_terminal_work(functions, None{}, member, entry, types, checked)

def matched_type_equality_found(found: Maybe<&2, String>, +function: M.Function, constructor: String, checked: List<&2, M.CheckedFunction>) -> Maybe<&2, M.Function>:
  match found:
    case None{}:
      None{}
    case Some{name}:
      Bool.pick(Maybe<&2, M.Function>, Bool.and(M.name_equal(name, constructor), certified_function(checked, function)), Some{function}, None{})

def matched_type_equality(found: Maybe<&2, M.Function>, constructor: String, checked: List<&2, M.CheckedFunction>) -> Maybe<&2, M.Function>:
  match found:
    case None{}:
      None{}
    case Some{+function}:
      matched_type_equality_found(type_equality(function), function, constructor, checked)

def matched_forwarder(found: Maybe<&2, M.Function>, checked: List<&2, M.CheckedFunction>) -> Maybe<&2, M.Function>:
  match found:
    case None{}:
      None{}
    case Some{+function}:
      Bool.pick(Maybe<&2, M.Function>, Bool.and(equality_forwarder(function), certified_function(checked, function)), Some{function}, None{})

def data_has_field(data: M.DataType, member: String) -> Bool:
  M.DataType{identity, parameters, constructors} = data
  Members.has_field(constructors, member)

def capture_valid(+node_source: M.Function, shape: NodeShape, +node_data: M.DataType, witness_data: M.DataType, +terminal_source: M.Function, +terminal_data: M.DataType, +equality: M.Function, +type_equality: M.Function, +entry: String, +checked: List<&2, M.CheckedFunction>) -> Maybe<&2, Evidence>:
  NodeShape{constructor, +member, equality_name, witness_constructor} = shape
  +node_identity = type_identity(node_data)
  +terminal_identity = type_identity(terminal_data)
  +valid = Bool.and(Bool.not(data_has_field(node_data, member)), Bool.and(Bool.not(data_has_field(terminal_data, member)), Bool.and(M.name_equal(name(node_source), method_name(node_identity, entry, member)), Bool.and(M.name_equal(name(terminal_source), method_name(terminal_identity, entry, member)), Bool.and(certified_function(checked, node_source), Bool.and(certified_function(checked, equality), certified_function(checked, type_equality)))))))
  Bool.pick(Maybe<&2, Evidence>, valid, Some{Evidence{node_source, terminal_source, equality, type_equality, node_data, terminal_data, witness_data, constructor, terminal_identity, node_identity, member}}, None{})

def capture_dependencies(node_source: M.Function, shape: NodeShape, node_data: M.DataType, witness_data: M.DataType, terminal: Maybe<&2, Terminal>, equality: Maybe<&2, M.Function>, type_equality: Maybe<&2, M.Function>, entry: String, checked: List<&2, M.CheckedFunction>) -> Maybe<&2, Evidence>:
  match terminal equality type_equality:
    case Some{Terminal{end_source, end_data}} Some{equal_source} Some{type_source}:
      capture_valid(node_source, shape, node_data, witness_data, end_source, end_data, equal_source, type_source, entry, checked)
    case _ _ _:
      None{}

def capture_witness_data(found: Maybe<&2, M.DataType>, node_source: M.Function, +shape: NodeShape, node_data: M.DataType, +functions: List<&2, M.Function>, +types: List<&2, M.DataType>, +checked: List<&2, M.CheckedFunction>, +entry: String) -> Maybe<&2, Evidence>:
  match found:
    case None{}:
      None{}
    case Some{+witness_data}:
      +type_eq_name = method_name(type_identity(witness_data), entry, "eq")
      capture_dependencies(node_source, shape, node_data, witness_data, find_terminal(functions, node_member(shape), entry, types, checked), matched_forwarder(find_function(functions, node_equality(shape)), checked), matched_type_equality(find_function(functions, type_eq_name), witness_constructor(shape), checked), entry, checked)

def capture_witness(node_source: M.Function, +shape: NodeShape, node_data: M.DataType, found: Maybe<&2, TD.ConstructorDefinition>, +functions: List<&2, M.Function>, +types: List<&2, M.DataType>, +checked: List<&2, M.CheckedFunction>, +entry: String) -> Maybe<&2, Evidence>:
  match found:
    case None{}:
      None{}
    case Some{definition}:
      capture_witness_data(witness_catalog(TD.lookup(types, constructor_identity(definition)), witness_constructor(shape)), node_source, shape, node_data, functions, types, checked, entry)

def capture_node_data(found: Maybe<&2, M.DataType>, node_source: M.Function, +shape: NodeShape, +functions: List<&2, M.Function>, +types: List<&2, M.DataType>, +checked: List<&2, M.CheckedFunction>, +entry: String) -> Maybe<&2, Evidence>:
  match found:
    case None{}:
      None{}
    case Some{node_data}:
      capture_witness(node_source, shape, node_data, TD.constructor(types, witness_constructor(shape)), functions, types, checked, entry)

def capture_node(node_source: M.Function, +shape: NodeShape, found: Maybe<&2, TD.ConstructorDefinition>, +functions: List<&2, M.Function>, +types: List<&2, M.DataType>, +checked: List<&2, M.CheckedFunction>, +entry: String) -> Maybe<&2, Evidence>:
  match found:
    case None{}:
      None{}
    case Some{definition}:
      capture_node_data(node_catalog(TD.lookup(types, constructor_identity(definition)), node_constructor(shape)), node_source, shape, functions, types, checked, entry)

def capture_shape(found: Maybe<&2, NodeShape>, source: M.Function, +functions: List<&2, M.Function>, +types: List<&2, M.DataType>, +checked: List<&2, M.CheckedFunction>, +entry: String) -> Maybe<&2, Evidence>:
  match found:
    case None{}:
      None{}
    case Some{+shape}:
      capture_node(source, shape, TD.constructor(types, node_constructor(shape)), functions, types, checked, entry)

def capture_one(+source: M.Function, +functions: List<&2, M.Function>, +types: List<&2, M.DataType>, +checked: List<&2, M.CheckedFunction>, +entry: String) -> Maybe<&2, Evidence>:
  capture_shape(node(source), source, functions, types, checked, entry)

def captured(found: Maybe<&2, Evidence>, rest: List<&2, Evidence>) -> List<&2, Evidence>:
  match found:
    case None{}:
      rest
    case Some{proof}:
      proof <> rest

def capture_functions(pending: List<&2, M.Function>, +functions: List<&2, M.Function>, +types: List<&2, M.DataType>, +checked: List<&2, M.CheckedFunction>, +entry: String) -> List<&2, Evidence>:
  match pending:
    case Nil{}:
      Nil{}
    case +source <> tail:
      captured(capture_one(source, functions, types, checked, entry), capture_functions(tail, functions, types, checked, entry))

def capture_checked_catalog(valid: Bool, +functions: List<&2, M.Function>, +types: List<&2, M.DataType>, +checked_functions: List<&2, M.CheckedFunction>, entry: String) -> List<&2, Evidence>:
  match valid:
    case False{}:
      Nil{}
    case True{}:
      capture_functions(functions, functions, types, checked_functions, entry)

def capture(+functions: List<&2, M.Function>, +types: List<&2, M.DataType>, checked: M.CheckedModule, entry: String) -> List<&2, Evidence>:
  M.CheckedModule{constants, checked_functions, checked_types, operations} = checked
  capture_checked_catalog(Compare.compare(1048576n, [Compare.DataTypeListPair{types, checked_types}], True{}), functions, types, checked_functions, entry)

def node_id(proof: Evidence) -> M.TypeId:
  Evidence{node_method, terminal_method, equality, type_equality, node_type, terminal_type, witness_type, node_constructor, terminal_identity, node_identity, member} = proof
  node_identity

def terminal_id(proof: Evidence) -> M.TypeId:
  Evidence{node_method, terminal_method, equality, type_equality, node_type, terminal_type, witness_type, node_constructor, terminal_identity, node_identity, member} = proof
  terminal_identity

def proof_member(proof: Evidence) -> String:
  Evidence{node_method, terminal_method, equality, type_equality, node_type, terminal_type, witness_type, node_constructor, terminal_identity, node_identity, member} = proof
  member

def proof_type_id(proof: Evidence) -> M.TypeId:
  Evidence{node_method, terminal_method, equality, type_equality, node_type, terminal_type, witness_type, node_constructor, terminal_identity, node_identity, member} = proof
  type_identity(witness_type)

def node_method(proof: Evidence) -> String:
  Evidence{node_method, terminal_method, equality, type_equality, node_type, terminal_type, witness_type, node_constructor, terminal_identity, node_identity, member} = proof
  name(node_method)

def terminal_method(proof: Evidence) -> String:
  Evidence{node_method, terminal_method, equality, type_equality, node_type, terminal_type, witness_type, node_constructor, terminal_identity, node_identity, member} = proof
  name(terminal_method)

def type_method(proof: Evidence) -> String:
  Evidence{node_method, terminal_method, equality, type_equality, node_type, terminal_type, witness_type, node_constructor, terminal_identity, node_identity, member} = proof
  name(type_equality)

def method_matches(left: M.Ty, +selected: String, +proof: Evidence) -> Bool:
  match left:
    case M.AppliedTy{+identity, arguments}:
      Bool.or(Bool.and(M.type_id_equal(identity, node_id(proof)), M.name_equal(selected, node_method(proof))), Bool.and(M.type_id_equal(identity, terminal_id(proof)), M.name_equal(selected, terminal_method(proof))))
    case _:
      False{}

def exact_function(found: Maybe<&2, M.Function>, source: M.Function) -> Bool:
  match found:
    case None{}:
      False{}
    case Some{current}:
      Compare.compare(1048576n, [Compare.FunctionPair{current, source}], True{})

def exact_type(found: Maybe<&2, M.DataType>, source: M.DataType) -> Bool:
  match found:
    case None{}:
      False{}
    case Some{current}:
      Compare.same_type(current, source)

def exact_sources(+proof: Evidence, +functions: List<&2, M.Function>, +types: List<&2, M.DataType>) -> Bool:
  Evidence{+node_method, +terminal_method, +equality, +type_equality, +node_type, +terminal_type, +witness_type, node_constructor, terminal_identity, node_identity, member} = proof
  Bool.and(exact_function(find_function(functions, name(node_method)), node_method),
    Bool.and(exact_function(find_function(functions, name(terminal_method)), terminal_method),
    Bool.and(exact_function(find_function(functions, name(equality)), equality),
    Bool.and(exact_function(find_function(functions, name(type_equality)), type_equality),
    Bool.and(exact_type(TD.lookup(types, type_identity(node_type)), node_type),
    Bool.and(exact_type(TD.lookup(types, type_identity(terminal_type)), terminal_type),
      exact_type(TD.lookup(types, type_identity(witness_type)), witness_type)))))))

def type_key(found: Result<&2, &2, M.Diagnostic, String>) -> Maybe<&2, String>:
  match found:
    case Done{key}:
      Some{key}
    case Fail{diagnostic}:
      None{}

def key(ty: M.Ty) -> Maybe<&2, String>:
  type_key(State.type_key(65536n, State.TypeKey{State.witness(65536n, ty)}))

type ChainWork is Data:
  Walk{ty: M.Ty, wanted: String, proof: Evidence, answer: Bool}
  OnNode{head: M.Ty, tail: M.Ty, wanted: String, proof: Evidence, matched: Bool, answer: Bool}
  ComparedHead{found: Maybe<&2, String>, wanted: String, tail: M.Ty, proof: Evidence, answer: Bool}
  Choose{same: Bool, tail: M.Ty, wanted: String, proof: Evidence, answer: Bool}

def decide_chain(fuel: Nat, work: ChainWork) -> Maybe<&2, Bool>:
  match fuel work:
    case 0n _:
      None{}
    case 1n+rest Walk{M.AppliedTy{identity, Nil{}}, wanted, proof, answer}:
      Bool.pick(Maybe<&2, Bool>, M.type_id_equal(identity, terminal_id(proof)), Some{answer}, None{})
    case 1n+rest Walk{M.AppliedTy{identity, head <> tail <> Nil{}}, wanted, +proof, answer}:
      decide_chain(rest, OnNode{head, tail, wanted, proof, M.type_id_equal(identity, node_id(proof)), answer})
    case 1n+rest OnNode{head, tail, wanted, proof, False{}, answer}:
      None{}
    case 1n+rest OnNode{head, tail, wanted, proof, True{}, answer}:
      decide_chain(rest, ComparedHead{key(head), wanted, tail, proof, answer})
    case 1n+rest ComparedHead{None{}, wanted, tail, proof, answer}:
      None{}
    case 1n+rest ComparedHead{Some{head}, +wanted, tail, proof, answer}:
      decide_chain(rest, Choose{M.name_equal(head, wanted), tail, wanted, proof, answer})
    case 1n+rest Choose{same, tail, wanted, proof, answer}:
      # Source checking validates both branches of each node. Keep validating
      # the whole concrete tail even after a matching head has been found.
      decide_chain(rest, Walk{tail, wanted, proof, Bool.or(same, answer)})
    case _ _:
      None{}

def decide_witness(found: Maybe<&2, String>, left: M.Ty, proof: Evidence) -> Maybe<&2, Bool>:
  match found:
    case None{}:
      None{}
    case Some{wanted}:
      decide_chain(65536n, Walk{left, wanted, proof, False{}})

def decide_checked(valid: Bool, left: M.Ty, witness: M.Ty, proof: Evidence) -> Maybe<&2, Bool>:
  match valid:
    case False{}:
      None{}
    case True{}:
      decide_witness(key(witness), left, proof)

def decide_ready(ready: Bool, left: M.Ty, witness: M.Ty, +proof: Evidence, functions: List<&2, M.Function>, types: List<&2, M.DataType>) -> Maybe<&2, Bool>:
  match ready:
    case False{}:
      None{}
    case True{}:
      decide_checked(exact_sources(proof, functions, types), left, witness, proof)

def decide_one(+proof: Evidence, selected: String, member: String, +left: M.Ty, result: M.Ty, functions: List<&2, M.Function>, types: List<&2, M.DataType>) -> Maybe<&2, Bool>:
  match result:
    case M.FunctionTy{witness, M.BoolTy{}, M.EffectRow{Nil{}, M.ClosedRow{}}}:
      decide_ready(Bool.and(M.name_equal(member, proof_member(proof)), method_matches(left, selected, proof)), left, witness, proof, functions, types)
    case _:
      None{}

# Reject unrelated member selections before Mono repeats method lookup and
# resolves the result type. This only inspects immutable nominal identities.
def eligible_one(proof: Evidence, member: String, left: M.Ty) -> Bool:
  Evidence{node_method, terminal_method, equality, type_equality, node_type, terminal_type, witness_type, node_constructor, +terminal_identity, +node_identity, expected} = proof
  match left:
    case M.AppliedTy{identity, head <> tail <> Nil{}}:
      Bool.and(M.name_equal(member, expected), M.type_id_equal(identity, node_identity))
    case M.AppliedTy{identity, Nil{}}:
      Bool.and(M.name_equal(member, expected), M.type_id_equal(identity, terminal_identity))
    case _:
      False{}

def eligible_work(proofs: List<&2, Evidence>, +member: String, +left: M.Ty, found: Bool) -> Bool:
  match proofs found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case head <> tail False{}:
      eligible_work(tail, member, left, eligible_one(head, member, left))

def eligible(proofs: List<&2, Evidence>, member: String, left: M.Ty) -> Bool:
  eligible_work(proofs, member, left, False{})

type Search is Data:
  Scan{proofs: List<&2, Evidence>, selected: String, member: String, left: M.Ty, result: M.Ty, functions: List<&2, M.Function>, types: List<&2, M.DataType>}
  Chosen{found: Maybe<&2, Bool>, remaining: List<&2, Evidence>, selected: String, member: String, left: M.Ty, result: M.Ty, functions: List<&2, M.Function>, types: List<&2, M.DataType>}

def decide_search(fuel: Nat, work: Search) -> Maybe<&2, Bool>:
  match fuel work:
    case 0n _:
      None{}
    case 1n+rest Scan{Nil{}, selected, member, left, result, functions, types}:
      None{}
    case 1n+rest Scan{head <> tail, +selected, +member, +left, +result, +functions, +types}:
      decide_search(rest, Chosen{decide_one(head, selected, member, left, result, functions, types), tail, selected, member, left, result, functions, types})
    case 1n+rest Chosen{Some{answer}, remaining, selected, member, left, result, functions, types}:
      Some{answer}
    case 1n+rest Chosen{None{}, remaining, selected, member, left, result, functions, types}:
      decide_search(rest, Scan{remaining, selected, member, left, result, functions, types})

def decide(proofs: List<&2, Evidence>, selected: String, member: String, left: M.Ty, result: M.Ty, functions: List<&2, M.Function>, types: List<&2, M.DataType>) -> Maybe<&2, Bool>:
  decide_search(65536n, Scan{proofs, selected, member, left, result, functions, types})
