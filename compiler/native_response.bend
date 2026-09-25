import Base
import ./model.bend as M
import ./const_eval.bend as Const
import ./main.bend as Main

def version() -> U32:
  12

# This is the version-12 word protocol paired with native_protocol.ts. Fields
# follow public Analysis order; compiler-only checked declarations stay native.
type Work is Data:
  Word{value: U32}
  Natural{value: Nat}
  Length{value: Nat}
  CheckedLength{valid: Bool, value: Nat}
  Text{value: String}
  Characters{value: String}
  Identity{value: M.TypeId}
  Identities{values: List<&2, M.TypeId>}
  IdentityEntries{values: List<&2, M.TypeId>}
  Row{value: M.EffectRow}
  RowTail{value: M.RowTail}
  Operation{value: M.Operation}
  Operations{values: List<&2, M.Operation>}
  OperationEntries{values: List<&2, M.Operation>}
  Effect{value: M.Effect}
  Effects{values: List<&2, M.Effect>}
  EffectEntries{values: List<&2, M.Effect>}
  TypeValue{value: M.Ty}
  Types{values: List<&2, M.Ty>}
  TypeEntries{values: List<&2, M.Ty>}
  OptionalType{value: Maybe<&2, M.Ty>}
  Pattern{value: M.Pattern}
  Patterns{values: List<&2, M.Pattern>}
  PatternEntries{values: List<&2, M.Pattern>}
  OptionalPattern{value: Maybe<&2, M.Pattern>}
  Operator{value: M.ScalarOp}
  UnaryOperator{value: M.UnaryOp}
  Expression{value: M.Expr}
  Expressions{values: List<&2, M.Expr>}
  ExpressionEntries{values: List<&2, M.Expr>}
  OptionalExpression{value: Maybe<&2, M.Expr>}
  Arms{values: List<&2, M.MatchArm<M.Expr>>}
  ArmEntries{values: List<&2, M.MatchArm<M.Expr>>}
  Value{value: Const.Value}
  Values{values: List<&2, Const.Value>}
  ValueEntries{values: List<&2, Const.Value>}
  OptionalValue{value: Maybe<&2, Const.Value>}
  Bindings{values: List<&2, Const.Binding<Const.Value>>}
  BindingEntries{values: List<&2, Const.Binding<Const.Value>>}
  Naturals{values: List<&2, Nat>}
  NaturalEntries{values: List<&2, Nat>}
  Strings{values: List<&2, String>}
  StringEntries{values: List<&2, String>}
  Functions{values: List<&2, M.CheckedFunction>}
  FunctionEntries{values: List<&2, M.CheckedFunction>}
  Analysis{value: Main.Analysis}
  Bytes{values: List<&2, U32>}
  ByteLength{value: Nat}
  ByteWords{values: List<&2, U32>}
  CheckedBytes{valid: Bool, word: U32, rest: List<&2, U32>}
  Diagnostic{value: M.Diagnostic}

def protocol_error(message: String) -> M.Diagnostic:
  M.Diagnostic{"native_protocol", "native_response", message}

def bool_word(value: Bool) -> U32:
  match value:
    case False{}:
      0
    case True{}:
      1

def pack(a: U32, b: U32, c: U32, d: U32) -> U32:
  U32.or(U32.or(a, U32.shln(b, 8n)), U32.or(U32.shln(c, 16n), U32.shln(d, 24n)))

def valid_bytes(a: U32, b: U32, c: U32, d: U32) -> Bool:
  Bool.and(Bool.and(U32.is_le(a, 255), U32.is_le(b, 255)), Bool.and(U32.is_le(c, 255), U32.is_le(d, 255)))

# The worklist avoids recursive host stacks for nested closures and core terms.
# Only emitted words spend the 16M-word output allowance; traversal fuel is an
# independent Nat bound and never truncates a successful response.
def encode_work(fuel: Nat, pending: List<&2, Work>, remaining: Nat, reversed: List<&2, U32>) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  match fuel pending remaining:
    case _ Nil{} _:
      Done{List.reverse(&2, U32, reversed)}
    case 0n _ _:
      Fail{protocol_error("response traversal exceeded its bound")}
    case 1n+rest Word{value} <> tail 0n:
      Fail{protocol_error("response exceeds 16M words")}
    case 1n+rest Word{value} <> tail 1n+room:
      encode_work(rest, tail, room, value <> reversed)
    case 1n+rest Natural{+value} <> tail room:
      encode_work(rest, Word{U32.from_nat(value)} <> Word{U32.from_nat(Nat.div(value, Nat.mul(U32.to_nat(65536), U32.to_nat(65536))))} <> tail, room, reversed)
    case 1n+rest Length{+value} <> tail room:
      encode_work(rest, CheckedLength{Nat.is_le(value, U32.to_nat(16777216)), value} <> tail, room, reversed)
    case 1n+rest CheckedLength{False{}, value} <> tail room:
      Fail{protocol_error("response collection exceeds 16M words")}
    case 1n+rest CheckedLength{True{}, value} <> tail room:
      encode_work(rest, Word{U32.from_nat(value)} <> tail, room, reversed)
    case 1n+rest Text{+value} <> tail room:
      encode_work(rest, Length{String.length(value)} <> Characters{value} <> tail, room, reversed)
    case 1n+rest Characters{SNil{}} <> tail room:
      encode_work(rest, tail, room, reversed)
    case 1n+rest Characters{SCon{character, following}} <> tail room:
      encode_work(rest, Word{Char.to_u32(character)} <> Characters{following} <> tail, room, reversed)
    case 1n+rest Identity{M.TypeId{module_name, declaration}} <> tail room:
      encode_work(rest, Text{module_name} <> Text{declaration} <> tail, room, reversed)
    case 1n+rest Identities{+values} <> tail room:
      encode_work(rest, Length{List.length(&2, M.TypeId, values)} <> IdentityEntries{values} <> tail, room, reversed)
    case 1n+rest IdentityEntries{Nil{}} <> tail room:
      encode_work(rest, tail, room, reversed)
    case 1n+rest IdentityEntries{head <> following} <> tail room:
      encode_work(rest, Identity{head} <> IdentityEntries{following} <> tail, room, reversed)
    case 1n+rest Row{M.EffectRow{operations, tail_value}} <> tail room:
      encode_work(rest, Identities{operations} <> RowTail{tail_value} <> tail, room, reversed)
    case 1n+rest RowTail{M.ClosedRow{}} <> tail room:
      encode_work(rest, Word{0} <> tail, room, reversed)
    case 1n+rest RowTail{M.RowVariable{index}} <> tail room:
      encode_work(rest, Word{1} <> Natural{index} <> tail, room, reversed)
    case 1n+rest RowTail{M.RowParameter{index}} <> tail room:
      encode_work(rest, Word{2} <> Natural{index} <> tail, room, reversed)
    case 1n+rest Operation{M.Operation{identity, parameter, result}} <> tail room:
      encode_work(rest, Identity{identity} <> TypeValue{parameter} <> TypeValue{result} <> tail, room, reversed)
    case 1n+rest Operation{other} <> tail room:
      Fail{protocol_error("unspecialized effect operation reached response encoding")}
    case 1n+rest Operations{+values} <> tail room:
      encode_work(rest, Length{List.length(&2, M.Operation, values)} <> OperationEntries{values} <> tail, room, reversed)
    case 1n+rest OperationEntries{Nil{}} <> tail room:
      encode_work(rest, tail, room, reversed)
    case 1n+rest OperationEntries{head <> following} <> tail room:
      encode_work(rest, Operation{head} <> OperationEntries{following} <> tail, room, reversed)
    case 1n+rest Effect{M.OperationEffect{identity}} <> tail room:
      encode_work(rest, Identity{identity} <> tail, room, reversed)
    case 1n+rest Effects{+values} <> tail room:
      encode_work(rest, Length{List.length(&2, M.Effect, values)} <> EffectEntries{values} <> tail, room, reversed)
    case 1n+rest EffectEntries{Nil{}} <> tail room:
      encode_work(rest, tail, room, reversed)
    case 1n+rest EffectEntries{head <> following} <> tail room:
      encode_work(rest, Effect{head} <> EffectEntries{following} <> tail, room, reversed)
    case 1n+rest TypeValue{M.UnitTy{}} <> tail room:
      encode_work(rest, Word{0} <> tail, room, reversed)
    case 1n+rest TypeValue{M.U32Ty{}} <> tail room:
      encode_work(rest, Word{1} <> tail, room, reversed)
    case 1n+rest TypeValue{M.BoolTy{}} <> tail room:
      encode_work(rest, Word{2} <> tail, room, reversed)
    case 1n+rest TypeValue{M.AppliedTy{identity, arguments}} <> tail room:
      encode_work(rest, Word{3} <> Identity{identity} <> Types{arguments} <> tail, room, reversed)
    case 1n+rest TypeValue{M.FunctionTy{parameter, result, effects}} <> tail room:
      encode_work(rest, Word{4} <> TypeValue{parameter} <> TypeValue{result} <> Row{effects} <> tail, room, reversed)
    case 1n+rest TypeValue{M.FreeTy{scope, name}} <> tail room:
      encode_work(rest, Word{15} <> Text{scope} <> Text{name} <> tail, room, reversed)
    case 1n+rest TypeValue{M.ParameterTy{index}} <> tail room:
      encode_work(rest, Word{5} <> Natural{index} <> tail, room, reversed)
    case 1n+rest TypeValue{M.VariableTy{index}} <> tail room:
      encode_work(rest, Word{6} <> Natural{index} <> tail, room, reversed)
    case 1n+rest TypeValue{M.NeverTy{}} <> tail room:
      encode_work(rest, Word{7} <> tail, room, reversed)
    case 1n+rest TypeValue{M.F32Ty{}} <> tail room:
      encode_work(rest, Word{8} <> tail, room, reversed)
    case 1n+rest TypeValue{M.StateProviderTy{read, write, state}} <> tail room:
      encode_work(rest, Word{14} <> Identity{read} <> Identity{write} <> TypeValue{state} <> tail, room, reversed)
    case 1n+rest TypeValue{M.ProviderTy{identity, effects}} <> tail room:
      encode_work(rest, Word{9} <> Identity{identity} <> Row{effects} <> tail, room, reversed)
    case 1n+rest TypeValue{M.EffectDescriptorTy{}} <> tail room:
      encode_work(rest, Word{10} <> tail, room, reversed)
    case 1n+rest TypeValue{M.EffectSetTy{}} <> tail room:
      encode_work(rest, Word{11} <> tail, room, reversed)
    case 1n+rest TypeValue{M.ProductTy{elements}} <> tail room:
      encode_work(rest, Word{12} <> Types{elements} <> tail, room, reversed)
    case 1n+rest TypeValue{M.ArrayTy{element}} <> tail room:
      encode_work(rest, Word{13} <> TypeValue{element} <> tail, room, reversed)
    case 1n+rest Types{+values} <> tail room:
      encode_work(rest, Length{List.length(&2, M.Ty, values)} <> TypeEntries{values} <> tail, room, reversed)
    case 1n+rest TypeEntries{Nil{}} <> tail room:
      encode_work(rest, tail, room, reversed)
    case 1n+rest TypeEntries{head <> following} <> tail room:
      encode_work(rest, TypeValue{head} <> TypeEntries{following} <> tail, room, reversed)
    case 1n+rest OptionalType{None{}} <> tail room:
      encode_work(rest, Word{0} <> tail, room, reversed)
    case 1n+rest OptionalType{Some{value}} <> tail room:
      encode_work(rest, Word{1} <> TypeValue{value} <> tail, room, reversed)
    case 1n+rest Patterns{+values} <> tail room:
      encode_work(rest, Length{List.length(&2, M.Pattern, values)} <> PatternEntries{values} <> tail, room, reversed)
    case 1n+rest PatternEntries{head <> following} <> tail room:
      encode_work(rest, Pattern{head} <> PatternEntries{following} <> tail, room, reversed)
    case 1n+rest PatternEntries{Nil{}} <> tail room:
      encode_work(rest, tail, room, reversed)
    case 1n+rest Pattern{M.WildcardPattern{}} <> tail room:
      encode_work(rest, Word{0} <> tail, room, reversed)
    case 1n+rest Pattern{M.BindingPattern{name}} <> tail room:
      encode_work(rest, Word{1} <> Text{name} <> tail, room, reversed)
    case 1n+rest Pattern{M.UnitPattern{}} <> tail room:
      encode_work(rest, Word{2} <> tail, room, reversed)
    case 1n+rest Pattern{M.U32Pattern{value}} <> tail room:
      encode_work(rest, Word{3} <> Word{value} <> tail, room, reversed)
    case 1n+rest Pattern{M.BoolPattern{value}} <> tail room:
      encode_work(rest, Word{4} <> Word{bool_word(value)} <> tail, room, reversed)
    case 1n+rest Pattern{M.ConstructorPattern{constructor, payload}} <> tail room:
      encode_work(rest, Word{5} <> Text{constructor} <> OptionalPattern{payload} <> tail, room, reversed)
    case 1n+rest Pattern{M.ProductPattern{elements}} <> tail room:
      encode_work(rest, Word{6} <> Patterns{elements} <> tail, room, reversed)
    case 1n+rest Pattern{M.ValuePattern{M.LocalReference{name}}} <> tail room:
      encode_work(rest, Word{7} <> Word{0} <> Text{name} <> tail, room, reversed)
    case 1n+rest Pattern{M.ValuePattern{M.ConstantReference{name}}} <> tail room:
      encode_work(rest, Word{7} <> Word{1} <> Text{name} <> tail, room, reversed)
    case 1n+rest OptionalPattern{None{}} <> tail room:
      encode_work(rest, Word{0} <> tail, room, reversed)
    case 1n+rest OptionalPattern{Some{value}} <> tail room:
      encode_work(rest, Word{1} <> Pattern{value} <> tail, room, reversed)
    case 1n+rest Operator{M.Add{}} <> tail room:
      encode_work(rest, Word{0} <> tail, room, reversed)
    case 1n+rest Operator{M.Subtract{}} <> tail room:
      encode_work(rest, Word{1} <> tail, room, reversed)
    case 1n+rest Operator{M.Multiply{}} <> tail room:
      encode_work(rest, Word{2} <> tail, room, reversed)
    case 1n+rest Operator{M.Equal{}} <> tail room:
      encode_work(rest, Word{3} <> tail, room, reversed)
    case 1n+rest Operator{M.LessThan{}} <> tail room:
      encode_work(rest, Word{4} <> tail, room, reversed)
    case 1n+rest Operator{M.F32Add{}} <> tail room:
      encode_work(rest, Word{5} <> tail, room, reversed)
    case 1n+rest Operator{M.F32Subtract{}} <> tail room:
      encode_work(rest, Word{6} <> tail, room, reversed)
    case 1n+rest Operator{M.F32Multiply{}} <> tail room:
      encode_work(rest, Word{7} <> tail, room, reversed)
    case 1n+rest Operator{M.F32Divide{}} <> tail room:
      encode_work(rest, Word{8} <> tail, room, reversed)
    case 1n+rest Operator{M.F32Equal{}} <> tail room:
      encode_work(rest, Word{9} <> tail, room, reversed)
    case 1n+rest Operator{M.F32NotEqual{}} <> tail room:
      encode_work(rest, Word{10} <> tail, room, reversed)
    case 1n+rest Operator{M.F32LessThan{}} <> tail room:
      encode_work(rest, Word{11} <> tail, room, reversed)
    case 1n+rest Operator{M.F32LessEqual{}} <> tail room:
      encode_work(rest, Word{12} <> tail, room, reversed)
    case 1n+rest Operator{M.F32GreaterThan{}} <> tail room:
      encode_work(rest, Word{13} <> tail, room, reversed)
    case 1n+rest Operator{M.F32GreaterEqual{}} <> tail room:
      encode_work(rest, Word{14} <> tail, room, reversed)
    case 1n+rest UnaryOperator{M.F32Negate{}} <> tail room:
      encode_work(rest, Word{0} <> tail, room, reversed)
    case 1n+rest UnaryOperator{M.F32Absolute{}} <> tail room:
      encode_work(rest, Word{1} <> tail, room, reversed)
    case 1n+rest UnaryOperator{M.F32SquareRoot{}} <> tail room:
      encode_work(rest, Word{2} <> tail, room, reversed)
    case 1n+rest UnaryOperator{M.F32Floor{}} <> tail room:
      encode_work(rest, Word{3} <> tail, room, reversed)
    case 1n+rest UnaryOperator{M.F32Ceiling{}} <> tail room:
      encode_work(rest, Word{4} <> tail, room, reversed)
    case 1n+rest UnaryOperator{M.F32Truncate{}} <> tail room:
      encode_work(rest, Word{5} <> tail, room, reversed)
    case 1n+rest UnaryOperator{M.U32ToF32{}} <> tail room:
      encode_work(rest, Word{6} <> tail, room, reversed)
    case 1n+rest UnaryOperator{M.F32ToU32{}} <> tail room:
      encode_work(rest, Word{7} <> tail, room, reversed)
    case 1n+rest Expression{M.UnitExpr{}} <> tail room:
      encode_work(rest, Word{0} <> tail, room, reversed)
    case 1n+rest Expression{M.U32Expr{value}} <> tail room:
      encode_work(rest, Word{1} <> Word{value} <> tail, room, reversed)
    case 1n+rest Expression{M.BoolExpr{value}} <> tail room:
      encode_work(rest, Word{2} <> Word{bool_word(value)} <> tail, room, reversed)
    case 1n+rest Expression{M.LocalExpr{name}} <> tail room:
      encode_work(rest, Word{3} <> Text{name} <> tail, room, reversed)
    case 1n+rest Expression{M.ConstantExpr{name}} <> tail room:
      encode_work(rest, Word{4} <> Text{name} <> tail, room, reversed)
    case 1n+rest Expression{M.FunctionExpr{name}} <> tail room:
      encode_work(rest, Word{5} <> Text{name} <> tail, room, reversed)
    case 1n+rest Expression{M.ConstructorRefExpr{constructor}} <> tail room:
      encode_work(rest, Word{6} <> Text{constructor} <> tail, room, reversed)
    case 1n+rest Expression{M.ConstructExpr{constructor, payload}} <> tail room:
      encode_work(rest, Word{7} <> Text{constructor} <> OptionalExpression{payload} <> tail, room, reversed)
    case 1n+rest Expression{M.LambdaExpr{identity, parameter, parameter_type, result_type, body}} <> tail room:
      encode_work(rest, Word{8} <> Natural{identity} <> Text{parameter} <> OptionalType{parameter_type} <> OptionalType{result_type} <> Expression{body} <> tail, room, reversed)
    case 1n+rest Expression{M.ApplyExpr{callee, argument}} <> tail room:
      encode_work(rest, Word{9} <> Expression{callee} <> Expression{argument} <> tail, room, reversed)
    case 1n+rest Expression{M.CallExpr{callee, argument}} <> tail room:
      encode_work(rest, Word{10} <> Text{callee} <> Expression{argument} <> tail, room, reversed)
    case 1n+rest Expression{M.ScalarExpr{operator, left, right}} <> tail room:
      encode_work(rest, Word{11} <> Operator{operator} <> Expression{left} <> Expression{right} <> tail, room, reversed)
    case 1n+rest Expression{M.LetExpr{name, value, body}} <> tail room:
      encode_work(rest, Word{12} <> Text{name} <> Expression{value} <> Expression{body} <> tail, room, reversed)
    case 1n+rest Expression{M.UseExpr{name, value, body}} <> tail room:
      encode_work(rest, Word{13} <> Text{name} <> Expression{value} <> Expression{body} <> tail, room, reversed)
    case 1n+rest Expression{M.IfExpr{condition, consequent, alternative}} <> tail room:
      encode_work(rest, Word{14} <> Expression{condition} <> Expression{consequent} <> Expression{alternative} <> tail, room, reversed)
    case 1n+rest Expression{M.SequenceExpr{first, next}} <> tail room:
      encode_work(rest, Word{15} <> Expression{first} <> Expression{next} <> tail, room, reversed)
    case 1n+rest Expression{M.MatchExpr{values, arms}} <> tail room:
      encode_work(rest, Word{16} <> Expressions{values} <> Arms{arms} <> tail, room, reversed)
    case 1n+rest Expression{M.GuardExpr{pattern, value, alternative, body}} <> tail room:
      encode_work(rest, Word{17} <> Pattern{pattern} <> Expression{value} <> Expression{alternative} <> Expression{body} <> tail, room, reversed)
    case 1n+rest Expression{M.BlockExpr{label, body}} <> tail room:
      encode_work(rest, Word{18} <> Natural{label} <> Expression{body} <> tail, room, reversed)
    case 1n+rest Expression{M.ReturnExpr{label, value}} <> tail room:
      encode_work(rest, Word{19} <> Natural{label} <> Expression{value} <> tail, room, reversed)
    case 1n+rest Expression{M.RuntimeInitExpr{value}} <> tail room:
      encode_work(rest, Word{44} <> Expression{value} <> tail, room, reversed)
    case 1n+rest Expression{M.SourceExpr{offset, annotation, value}} <> tail room:
      encode_work(rest, Word{20} <> Natural{offset} <> OptionalType{annotation} <> Expression{value} <> tail, room, reversed)
    case 1n+rest Expression{M.F32Expr{value}} <> tail room:
      encode_work(rest, Word{21} <> Word{F32.bits(value)} <> tail, room, reversed)
    case 1n+rest Expression{M.UnaryExpr{operator, value}} <> tail room:
      encode_work(rest, Word{22} <> UnaryOperator{operator} <> Expression{value} <> tail, room, reversed)
    case 1n+rest Expression{M.PanicExpr{message}} <> tail room:
      encode_work(rest, Word{23} <> Text{message} <> tail, room, reversed)
    case 1n+rest Expression{M.OperationExpr{identity}} <> tail room:
      encode_work(rest, Word{24} <> Identity{identity} <> tail, room, reversed)
    case 1n+rest Expression{M.SpecializeOperationExpr{template, arguments, body}} <> tail room:
      Fail{protocol_error("unspecialized effect expression reached response encoding")}
    case 1n+rest Expression{M.StateProviderExpr{read, write, initial}} <> tail room:
      encode_work(rest, Word{42} <> Identity{read} <> Identity{write} <> Expression{initial} <> tail, room, reversed)
    case 1n+rest Expression{M.ProviderExpr{identity, implementation}} <> tail room:
      encode_work(rest, Word{25} <> Identity{identity} <> Expression{implementation} <> tail, room, reversed)
    case 1n+rest Expression{M.HandleExpr{provider, body}} <> tail room:
      encode_work(rest, Word{26} <> Expression{provider} <> Expression{body} <> tail, room, reversed)
    case 1n+rest Expression{M.OperationDescriptorExpr{identity}} <> tail room:
      encode_work(rest, Word{27} <> Identity{identity} <> tail, room, reversed)
    case 1n+rest Expression{M.FunctionEffectsExpr{callee}} <> tail room:
      encode_work(rest, Word{28} <> Text{callee} <> tail, room, reversed)
    case 1n+rest Expression{M.EffectHasExpr{set, operation}} <> tail room:
      encode_work(rest, Word{29} <> Expression{set} <> Expression{operation} <> tail, room, reversed)
    case 1n+rest Expression{M.EffectCountExpr{set}} <> tail room:
      encode_work(rest, Word{30} <> Expression{set} <> tail, room, reversed)
    case 1n+rest Expression{M.EffectSameExpr{left, right}} <> tail room:
      encode_work(rest, Word{31} <> Expression{left} <> Expression{right} <> tail, room, reversed)
    case 1n+rest Expression{M.ProductExpr{elements}} <> tail room:
      encode_work(rest, Word{32} <> Expressions{elements} <> tail, room, reversed)
    case 1n+rest Expression{M.ProjectExpr{value, index}} <> tail room:
      encode_work(rest, Word{33} <> Expression{value} <> Natural{index} <> tail, room, reversed)
    case 1n+rest Expression{M.ArrayExpr{elements}} <> tail room:
      encode_work(rest, Word{34} <> Expressions{elements} <> tail, room, reversed)
    case 1n+rest Expression{M.ForExpr{index, start, end, state, initial, body}} <> tail room:
      encode_work(rest, Word{41} <> Text{index} <> Expression{start} <> Expression{end} <> Text{state} <> Expression{initial} <> Expression{body} <> tail, room, reversed)
    case 1n+rest Expression{M.ArrayGenerateExpr{count, generator}} <> tail room:
      encode_work(rest, Word{39} <> Expression{count} <> Expression{generator} <> tail, room, reversed)
    case 1n+rest Expression{M.ArrayFillExpr{count, value}} <> tail room:
      encode_work(rest, Word{38} <> Expression{count} <> Expression{value} <> tail, room, reversed)
    case 1n+rest Expression{M.ArrayGetExpr{array, index}} <> tail room:
      encode_work(rest, Word{35} <> Expression{array} <> Expression{index} <> tail, room, reversed)
    case 1n+rest Expression{M.ArraySetExpr{array, index, value}} <> tail room:
      encode_work(rest, Word{36} <> Expression{array} <> Expression{index} <> Expression{value} <> tail, room, reversed)
    case 1n+rest Expression{M.AssociatedExpr{identity, dispatch, member, templates, left, right}} <> tail room:
      encode_work(rest, Word{40} <> Natural{identity} <> Text{member} <> Expression{left} <> Expression{right} <> tail, room, reversed)
    case 1n+rest Expression{M.GenericOperationExpr{identity, template, arguments}} <> tail room:
      encode_work(rest, Word{43} <> Natural{identity} <> Identity{template} <> Types{arguments} <> tail, room, reversed)
    case 1n+rest Expression{M.ArrayLengthExpr{array}} <> tail room:
      encode_work(rest, Word{37} <> Expression{array} <> tail, room, reversed)
    case 1n+rest Expressions{+values} <> tail room:
      encode_work(rest, Length{List.length(&2, M.Expr, values)} <> ExpressionEntries{values} <> tail, room, reversed)
    case 1n+rest ExpressionEntries{Nil{}} <> tail room:
      encode_work(rest, tail, room, reversed)
    case 1n+rest ExpressionEntries{head <> following} <> tail room:
      encode_work(rest, Expression{head} <> ExpressionEntries{following} <> tail, room, reversed)
    case 1n+rest OptionalExpression{None{}} <> tail room:
      encode_work(rest, Word{0} <> tail, room, reversed)
    case 1n+rest OptionalExpression{Some{value}} <> tail room:
      encode_work(rest, Word{1} <> Expression{value} <> tail, room, reversed)
    case 1n+rest Arms{+values} <> tail room:
      encode_work(rest, Length{List.length(&2, M.MatchArm<M.Expr>, values)} <> ArmEntries{values} <> tail, room, reversed)
    case 1n+rest ArmEntries{Nil{}} <> tail room:
      encode_work(rest, tail, room, reversed)
    case 1n+rest ArmEntries{M.MatchArm{patterns, body} <> following} <> tail room:
      encode_work(rest, Patterns{patterns} <> Expression{body} <> ArmEntries{following} <> tail, room, reversed)
    case 1n+rest Value{Const.UnitValue{}} <> tail room:
      encode_work(rest, Word{0} <> tail, room, reversed)
    case 1n+rest Value{Const.U32Value{value}} <> tail room:
      encode_work(rest, Word{1} <> Word{value} <> tail, room, reversed)
    case 1n+rest Value{Const.BoolValue{value}} <> tail room:
      encode_work(rest, Word{2} <> Word{bool_word(value)} <> tail, room, reversed)
    case 1n+rest Value{Const.FunctionValue{name}} <> tail room:
      encode_work(rest, Word{3} <> Text{name} <> tail, room, reversed)
    case 1n+rest Value{Const.ConstructorFunctionValue{constructor}} <> tail room:
      encode_work(rest, Word{4} <> Text{constructor} <> tail, room, reversed)
    case 1n+rest Value{Const.DataValue{constructor, payload}} <> tail room:
      encode_work(rest, Word{5} <> Text{constructor} <> OptionalValue{payload} <> tail, room, reversed)
    case 1n+rest Value{Const.ClosureValue{identity, parameter, body, environment}} <> tail room:
      encode_work(rest, Word{6} <> Natural{identity} <> Text{parameter} <> Expression{body} <> Bindings{environment} <> tail, room, reversed)
    case 1n+rest Value{Const.ReturnValue{label, value}} <> tail room:
      Fail{M.Diagnostic{"internal_error", "const", "A checked constant leaked a block return"}}
    case 1n+rest Value{Const.F32Value{value}} <> tail room:
      encode_work(rest, Word{7} <> Word{F32.bits(value)} <> tail, room, reversed)
    case 1n+rest Value{Const.OperationValue{identity}} <> tail room:
      encode_work(rest, Word{8} <> Identity{identity} <> tail, room, reversed)
    case 1n+rest Value{Const.StateProviderValue{read, write, initial}} <> tail room:
      encode_work(rest, Word{14} <> Identity{read} <> Identity{write} <> Value{initial} <> tail, room, reversed)
    case 1n+rest Value{Const.StateReadValue{slot}} <> tail room:
      Fail{M.Diagnostic{"internal_error", "state", "a state reader escaped its resolver"}}
    case 1n+rest Value{Const.StateWriteValue{slot}} <> tail room:
      Fail{M.Diagnostic{"internal_error", "state", "a state writer escaped its resolver"}}
    case 1n+rest Value{Const.ProviderValue{identity, implementation}} <> tail room:
      encode_work(rest, Word{9} <> Identity{identity} <> Value{implementation} <> tail, room, reversed)
    case 1n+rest Value{Const.EffectDescriptorValue{identity}} <> tail room:
      encode_work(rest, Word{10} <> Identity{identity} <> tail, room, reversed)
    case 1n+rest Value{Const.EffectSetValue{identities}} <> tail room:
      encode_work(rest, Word{11} <> Identities{identities} <> tail, room, reversed)
    case 1n+rest Value{Const.ProductValue{elements}} <> tail room:
      encode_work(rest, Word{12} <> Values{elements} <> tail, room, reversed)
    case 1n+rest Value{Const.ArrayValue{elements}} <> tail room:
      encode_work(rest, Word{13} <> Values{elements} <> tail, room, reversed)
    case 1n+rest Values{+values} <> tail room:
      encode_work(rest, Length{List.length(&2, Const.Value, values)} <> ValueEntries{values} <> tail, room, reversed)
    case 1n+rest ValueEntries{Nil{}} <> tail room:
      encode_work(rest, tail, room, reversed)
    case 1n+rest ValueEntries{head <> following} <> tail room:
      encode_work(rest, Value{head} <> ValueEntries{following} <> tail, room, reversed)
    case 1n+rest Value{Const.PatternBindingsValue{bindings}} <> tail room:
      Fail{M.Diagnostic{"internal_error", "const", "A checked constant leaked internal pattern bindings"}}
    case 1n+rest Value{Const.MatchValuesValue{values}} <> tail room:
      Fail{M.Diagnostic{"internal_error", "const", "A checked constant leaked internal match values"}}
    case 1n+rest OptionalValue{None{}} <> tail room:
      encode_work(rest, Word{0} <> tail, room, reversed)
    case 1n+rest OptionalValue{Some{value}} <> tail room:
      encode_work(rest, Word{1} <> Value{value} <> tail, room, reversed)
    case 1n+rest Bindings{+values} <> tail room:
      encode_work(rest, Length{List.length(&2, Const.Binding<Const.Value>, values)} <> BindingEntries{values} <> tail, room, reversed)
    case 1n+rest BindingEntries{Nil{}} <> tail room:
      encode_work(rest, tail, room, reversed)
    case 1n+rest BindingEntries{Const.Binding{name, value} <> following} <> tail room:
      encode_work(rest, Text{name} <> Value{value} <> BindingEntries{following} <> tail, room, reversed)
    case 1n+rest Naturals{+values} <> tail room:
      encode_work(rest, Length{List.length(&2, Nat, values)} <> NaturalEntries{values} <> tail, room, reversed)
    case 1n+rest NaturalEntries{Nil{}} <> tail room:
      encode_work(rest, tail, room, reversed)
    case 1n+rest NaturalEntries{head <> following} <> tail room:
      encode_work(rest, Natural{head} <> NaturalEntries{following} <> tail, room, reversed)
    case 1n+rest Strings{+values} <> tail room:
      encode_work(rest, Length{List.length(&2, String, values)} <> StringEntries{values} <> tail, room, reversed)
    case 1n+rest StringEntries{Nil{}} <> tail room:
      encode_work(rest, tail, room, reversed)
    case 1n+rest StringEntries{head <> following} <> tail room:
      encode_work(rest, Text{head} <> StringEntries{following} <> tail, room, reversed)
    case 1n+rest Functions{+values} <> tail room:
      encode_work(rest, Length{List.length(&2, M.CheckedFunction, values)} <> FunctionEntries{values} <> tail, room, reversed)
    case 1n+rest FunctionEntries{Nil{}} <> tail room:
      encode_work(rest, tail, room, reversed)
    case 1n+rest FunctionEntries{M.CheckedFunction{function, M.Signature{name, parameter, result, variables, row}, effects} <> following} <> tail room:
      encode_work(rest, Text{name} <> TypeValue{parameter} <> TypeValue{result} <> Naturals{variables} <> Effects{effects} <> Row{row} <> FunctionEntries{following} <> tail, room, reversed)
    case 1n+rest Analysis{Main.Analysis{M.CheckedModule{checked_constants, functions, types, operations}, constants, remaining_steps}} <> tail room:
      encode_work(rest, Functions{functions} <> Bindings{constants} <> Natural{remaining_steps} <> tail, room, reversed)
    case 1n+rest Bytes{+values} <> tail room:
      encode_work(rest, ByteLength{List.length(&2, U32, values)} <> ByteWords{values} <> tail, room, reversed)
    case 1n+rest ByteLength{+value} <> tail room:
      encode_work(rest, CheckedLength{Nat.is_le(value, U32.to_nat(67108864)), value} <> tail, room, reversed)
    case 1n+rest ByteWords{Nil{}} <> tail room:
      encode_work(rest, tail, room, reversed)
    case 1n+rest ByteWords{+a <> Nil{}} <> tail room:
      encode_work(rest, CheckedBytes{valid_bytes(a, 0, 0, 0), a, Nil{}} <> tail, room, reversed)
    case 1n+rest ByteWords{+a <> +b <> Nil{}} <> tail room:
      encode_work(rest, CheckedBytes{valid_bytes(a, b, 0, 0), pack(a, b, 0, 0), Nil{}} <> tail, room, reversed)
    case 1n+rest ByteWords{+a <> +b <> +c <> Nil{}} <> tail room:
      encode_work(rest, CheckedBytes{valid_bytes(a, b, c, 0), pack(a, b, c, 0), Nil{}} <> tail, room, reversed)
    case 1n+rest ByteWords{+a <> +b <> +c <> +d <> following} <> tail room:
      encode_work(rest, CheckedBytes{valid_bytes(a, b, c, d), pack(a, b, c, d), following} <> tail, room, reversed)
    case 1n+rest CheckedBytes{False{}, word, following} <> tail room:
      Fail{M.Diagnostic{"internal_error", "wasm", "Wasm emitter produced a value outside byte range"}}
    case 1n+rest CheckedBytes{True{}, word, following} <> tail room:
      encode_work(rest, Word{word} <> ByteWords{following} <> tail, room, reversed)
    case 1n+rest Diagnostic{M.Diagnostic{code, subject, message}} <> tail room:
      encode_work(rest, Text{code} <> Text{subject} <> Text{message} <> tail, room, reversed)

def character_words(value: String, tail: List<&2, U32>) -> List<&2, U32>:
  match value:
    case SNil{}:
      tail
    case SCon{character, following}:
      Char.to_u32(character) <> character_words(following, tail)

def text_words(+value: String, tail: List<&2, U32>) -> List<&2, U32>:
  U32.from_nat(String.length(value)) <> character_words(value, tail)

# Encoder failures contain only bounded compiler-authored diagnostic strings.
# A fresh diagnostic replaces the partial response, never a truncated artifact.
def finish(result: Result<&2, &2, M.Diagnostic, List<&2, U32>>) -> List<&2, U32>:
  match result:
    case Done{words}:
      words
    case Fail{M.Diagnostic{code, subject, message}}:
      1112297300 <> version() <> 0 <> text_words(code, text_words(subject, text_words(message, Nil{})))

def encode(kind: U32, fields: List<&2, Work>) -> List<&2, U32>:
  finish(encode_work(Nat.read.max(), Word{1112297300} <> Word{version()} <> Word{kind} <> fields, U32.to_nat(16777216), Nil{}))

def encode_diagnostic(diagnostic: M.Diagnostic) -> List<&2, U32>:
  encode(0, [Diagnostic{diagnostic}])

def encode_analysis(result: Result<&2, &2, M.Diagnostic, Main.Analysis>) -> List<&2, U32>:
  match result:
    case Fail{diagnostic}:
      encode_diagnostic(diagnostic)
    case Done{analysis}:
      encode(1, [Analysis{analysis}])

def encode_artifact(result: Result<&2, &2, M.Diagnostic, Main.Artifact>) -> List<&2, U32>:
  match result:
    case Fail{diagnostic}:
      encode_diagnostic(diagnostic)
    case Done{Main.Artifact{analysis, bytes}}:
      encode(2, [Analysis{analysis}, Bytes{bytes}])
