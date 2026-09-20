import Base
import ./model.bend as M
import ./const_eval.bend as C
import ./closures.bend as F
import ./wasm_catalog.bend as E
import ./codegen_ir.bend as I
import ./index.bend as Index
import ./runtime_reachable.bend as Reachable

type Slot is Data:
  Slot{name: String, index: Nat}

type Entry is Data:
  Entry{key: String, parameter: String, body: M.Expr, captures: List<&2, String>}

type CodegenJob is Data:
  CodegenJob{key: String, parameter: String, body: I.Expr, captures: List<&2, String>}

type Location is Data:
  Location{local: Nat, offsets: List<&2, Nat>}

type Local is Data:
  Local{name: String, location: Location}

type Catalog is Data:
  Catalog{
    entries: Map<&2, Maybe<&2, Nat>>,
    constructors: Map<&2, Maybe<&2, E.ConstructorSlot>>,
    constants: Map<&2, Maybe<&2, Nat>>,
    operations: Map<&2, Maybe<&2, Nat>>
  }

type StaticCatalog is Data:
  StaticCatalog{entries: Map<&2, Maybe<&2, Nat>>, projection: I.Metadata, operations: Map<&2, Maybe<&2, Nat>>}

type Context is Data:
  Context{locals: List<&2, Local>, next_local: Nat, labels: List<&2, Maybe<&2, Nat>>, provider: Nat}

type PatternWork is Data:
  OnePattern{pattern: M.Pattern, location: Location}
  ProductFields{patterns: List<&2, M.Pattern>, location: Location, offset: Nat}
  RowPatterns{patterns: List<&2, M.Pattern>, first: Nat}

# Only the linker knows module-wide positions. Each relocation carries its
# encoding and opcode, so instruction bytes cannot conceal a stale index.
type Fragment is Data:
  Bytes{bytes: List<&2, U32>}
  NamedCall{key: String}
  Allocate{}
  EntryIndex{key: String}
  ConstantReference{name: String}
  ConstructorIndex{name: String}
  OperationIndex{identity: M.TypeId}

type PatternTestWork is Data:
  PatternTest{pattern: M.Pattern, location: Location}
  ProductTests{patterns: List<&2, M.Pattern>, location: Location, offset: Nat, reversed: List<&2, Fragment>}
  RowTests{patterns: List<&2, M.Pattern>, first: Nat}

type Code is Data:
  Code{fragments: List<&2, Fragment>, locals: Nat}

type EntryCode is Data:
  EntryCode{key: String, code: Code}

type CodegenWeightWork is Data:
  WeightExpression{expression: I.Expr}
  WeightExpressions{expressions: List<&2, I.Expr>}
  WeightPattern{pattern: M.Pattern}
  WeightPatterns{patterns: List<&2, M.Pattern>}
  WeightArms{arms: List<&2, M.MatchArm<I.Expr>>}
  WeightCaptures{names: List<&2, String>}

type WeightedEntry<-A: Data> is Data:
  WeightedEntry{job: A, weight: Nat}

type EntryWorkload<-A: Data> is Data:
  EntryWorkload{entries: List<&2, WeightedEntry<A>>, weight: Nat}

type EntryPartition<-A: Data> is Data:
  EntryLeaf{entries: List<&2, WeightedEntry<A>>}
  EntryFork{left: EntryWorkload<A>, right: EntryWorkload<A>}

type EntryBatch<-A: Data> is Data:
  SequentialEntries{entries: List<&2, WeightedEntry<A>>}
  ParallelEntries{left: EntryBatch<A>, right: EntryBatch<A>}

type BytePlan is Data:
  BytePlan{length: Nat, chunks: List<&2, List<&2, U32>>}

type Heap is Data:
  Heap{next: Nat, chunks: List<&2, List<&2, U32>>}

type Serialized is Data:
  Serialized{words: List<&2, U32>, heap: Heap}

type Serialization is Data:
  ValueWork{value: C.Value}
  ValuesWork{values: List<&2, C.Value>}

type StaticConstants is Data:
  StaticConstants{slots: List<&2, Slot>, heap: Heap}

type ExportedConstant is Data:
  ExportedConstant{name: String, scalar: M.Ty}

type Prepared is Data:
  Prepared{jobs: List<&2, CodegenJob>, catalog: Catalog, functions: List<&2, M.CheckedFunction>, names: List<&2, ExportedConstant>, heap: Heap}

type Emission is Data:
  ExpressionWork{expression: I.Expr}
  ArmsWork{arms: List<&2, M.MatchArm<I.Expr>>, first: Nat}
  ScrutineesWork{values: List<&2, I.Expr>, first: Nat, reversed: List<&2, Fragment>, locals: Nat}

type AbiScalar is Data:
  UnitScalar{}
  U32Scalar{}
  BoolScalar{}
  F32Scalar{}

type Callback is Data:
  Callback{parameter: AbiScalar, result: AbiScalar}

type AbiParameter is Data:
  ScalarParameter{scalar: AbiScalar}
  CallbackParameter{signature: Callback}

type AbiFunction is Data:
  AbiFunction{name: String, parameter: AbiParameter, result: AbiScalar}

type AbiConstant is Data:
  AbiConstant{name: String, scalar: AbiScalar}

type Abi is Data:
  Abi{functions: List<&2, AbiFunction>, constants: List<&2, AbiConstant>, callbacks: List<&2, Callback>}

# Bend 2.0.5's List.length/append use the host stack for every element.
# Byte sections grow much faster than syntax trees, so their traversals are tail calls.
def byte_length(bytes: List<&2, U32>, total: Nat) -> Nat:
  match bytes:
    case Nil{}:
      total
    case head <> tail:
      byte_length(tail, 1n+total)

def concat(left: List<&2, U32>, right: List<&2, U32>) -> List<&2, U32>:
  List.reverse.go(&2, U32, List.reverse(&2, U32, left), right)

def join_reversed(chunks: List<&2, List<&2, U32>>, reversed: List<&2, U32>) -> List<&2, U32>:
  match chunks:
    case Nil{}:
      List.reverse(&2, U32, reversed)
    case head <> tail:
      join_reversed(tail, List.reverse.go(&2, U32, head, reversed))

def join(chunks: List<&2, List<&2, U32>>) -> List<&2, U32>:
  join_reversed(chunks, Nil{})

def byte_plan(+bytes: List<&2, U32>) -> BytePlan:
  BytePlan{byte_length(bytes, 0n), [bytes]}

def plan_sequence_go(plans: List<&2, BytePlan>, total: Nat, reversed: List<&2, List<&2, U32>>) -> BytePlan:
  match plans:
    case Nil{}:
      BytePlan{total, List.reverse(&2, List<&2, U32>, reversed)}
    case BytePlan{length, chunks} <> tail:
      plan_sequence_go(tail, Nat.add(total, length), List.reverse.go(&2, List<&2, U32>, chunks, reversed))

def plan_sequence(plans: List<&2, BytePlan>) -> BytePlan:
  plan_sequence_go(plans, 0n, Nil{})

def plan_prefix(+bytes: List<&2, U32>, plan: BytePlan) -> BytePlan:
  BytePlan{length, chunks} = plan
  BytePlan{Nat.add(byte_length(bytes, 0n), length), bytes <> chunks}

def plan_finish(plan: BytePlan) -> List<&2, U32>:
  BytePlan{length, chunks} = plan
  join(chunks)

def fragments_reversed(chunks: List<&2, List<&2, Fragment>>, reversed: List<&2, Fragment>) -> List<&2, Fragment>:
  match chunks:
    case Nil{}:
      List.reverse(&2, Fragment, reversed)
    case head <> tail:
      fragments_reversed(tail, List.reverse.go(&2, Fragment, head, reversed))

def fragments_join(chunks: List<&2, List<&2, Fragment>>) -> List<&2, Fragment>:
  fragments_reversed(chunks, Nil{})

def byte_code(bytes: List<&2, U32>, locals: Nat) -> Code:
  Code{[Bytes{bytes}], locals}

def unsigned_leb_go(fuel: Nat, +value: U32) -> List<&2, U32>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+rest:
      Bool.pick(List<&2, U32>, U32.is_lt(value, 128), [value], U32.or(U32.and(value, 127), 128) <> unsigned_leb_go(rest, U32.shrn(value, 7n)))

def unsigned_leb(value: Nat) -> List<&2, U32>:
  unsigned_leb_go(5n, U32.from_nat(value))

def plan_sized(plan: BytePlan) -> BytePlan:
  BytePlan{+length, chunks} = plan
  plan_prefix(unsigned_leb(length), BytePlan{length, chunks})

def plan_section(id: U32, plan: BytePlan) -> BytePlan:
  plan_prefix([id], plan_sized(plan))

def plan_vector(+plans: List<&2, BytePlan>) -> BytePlan:
  plan_prefix(unsigned_leb(List.length(&2, BytePlan, plans)), plan_sequence(plans))

# The last byte sign-extends bit 31, including for unsigned source literals.
# https://webassembly.github.io/spec/core/binary/values.html#integers
def i32_constant(+value: U32) -> List<&2, U32>:
  [65, U32.or(U32.and(value, 127), 128),
   U32.or(U32.and(U32.shrn(value, 7n), 127), 128),
   U32.or(U32.and(U32.shrn(value, 14n), 127), 128),
   U32.or(U32.and(U32.shrn(value, 21n), 127), 128),
   U32.or(U32.shrn(value, 28n), Bool.pick(U32, U32.is_lt(value, 2147483648), 0, 112))]

def utf8_char(+code: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_lt(code, 128), [code],
    Bool.pick(List<&2, U32>, U32.is_lt(code, 2048),
      [U32.or(192, U32.shrn(code, 6n)), U32.or(128, U32.and(code, 63))],
      Bool.pick(List<&2, U32>, U32.is_lt(code, 65536),
        [U32.or(224, U32.shrn(code, 12n)), U32.or(128, U32.and(U32.shrn(code, 6n), 63)), U32.or(128, U32.and(code, 63))],
        [U32.or(240, U32.shrn(code, 18n)), U32.or(128, U32.and(U32.shrn(code, 12n), 63)), U32.or(128, U32.and(U32.shrn(code, 6n), 63)), U32.or(128, U32.and(code, 63))])))

def utf8(text: String) -> List<&2, U32>:
  match text:
    case SNil{}:
      Nil{}
    case SCon{Chr{code}, tail}:
      concat(utf8_char(code), utf8(tail))

def sized(+bytes: List<&2, U32>) -> List<&2, U32>:
  concat(unsigned_leb(byte_length(bytes, 0n)), bytes)

def section(id: U32, bytes: List<&2, U32>) -> List<&2, U32>:
  id <> sized(bytes)

def vector(+entries: List<&2, List<&2, U32>>) -> List<&2, U32>:
  concat(unsigned_leb(List.length(&2, List<&2, U32>, entries)), join(entries))

def required_slot(found: Maybe<&2, Nat>, name: String) -> Result<&2, &2, M.Diagnostic, Nat>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"internal_error", name, "Wasm lowering lost a checked name"}}
    case Some{index}:
      Done{index}

def lookup_slot(slots: Map<&2, Maybe<&2, Nat>>, +name: String) -> Result<&2, &2, M.Diagnostic, Nat>:
  required_slot(Index.get(Maybe<&2, Nat>, slots, name, None{}), name)

def lookup_constructor(found: Maybe<&2, E.ConstructorSlot>, name: String) -> Result<&2, &2, M.Diagnostic, E.ConstructorSlot>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"internal_error", name, "Wasm lowering lost a checked constructor"}}
    case Some{variant}:
      Done{variant}

def lookup_lambda(found: Maybe<&2, F.Lambda>, identity: Nat) -> Result<&2, &2, M.Diagnostic, F.Lambda>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"internal_error", Nat.show(identity), "Wasm lowering lost a checked lambda"}}
    case Some{lambda}:
      Done{lambda}

def lookup_local(locals: List<&2, Local>, +name: String) -> Result<&2, &2, M.Diagnostic, Location>:
  match locals:
    case Nil{}:
      Fail{M.Diagnostic{"internal_error", name, "Wasm lowering lost a lexical local"}}
    case Local{found, location} <> tail:
      Bool.pick(Result<&2, &2, M.Diagnostic, Location>, M.name_equal(found, name), Done{location}, lookup_local(tail, name))

def function_entries(functions: List<&2, M.CheckedFunction>) -> List<&2, Entry>:
  match functions:
    case Nil{}:
      Nil{}
    case M.CheckedFunction{M.Function{name, exported, parameter, parameter_type, result_type, body}, signature, effects} <> tail:
      Entry{"fn:" ++ name, parameter, body, Nil{}} <> function_entries(tail)

def lambda_entries(lambdas: List<&2, F.Lambda>) -> List<&2, Entry>:
  match lambdas:
    case Nil{}:
      Nil{}
    case F.Lambda{identity, parameter, body, captures} <> tail:
      Entry{"lambda:" ++ Nat.show(identity), parameter, body, captures} <> lambda_entries(tail)

def constructor_entries(constructors: List<&2, E.ConstructorSlot>) -> List<&2, Entry>:
  match constructors:
    case Nil{}:
      Nil{}
    case E.ConstructorSlot{+name, tag, payload} <> tail:
      +rest = constructor_entries(tail)
      Bool.pick(List<&2, Entry>, payload, Entry{"constructor:" ++ name, "$payload", M.ConstructExpr{name, Some{M.LocalExpr{"$payload"}}}, Nil{}} <> rest, rest)

def static_entries(catalog: StaticCatalog) -> Map<&2, Maybe<&2, Nat>>:
  StaticCatalog{entries, projection, operations} = catalog
  entries

def static_projection(catalog: StaticCatalog) -> I.Metadata:
  StaticCatalog{entries, projection, operations} = catalog
  projection

def static_operations(catalog: StaticCatalog) -> Map<&2, Maybe<&2, Nat>>:
  StaticCatalog{entries, projection, operations} = catalog
  operations

def slot_index_go(slots: List<&2, Slot>, indexed: Map<&2, Maybe<&2, Nat>>) -> Map<&2, Maybe<&2, Nat>>:
  match slots:
    case Nil{}:
      indexed
    case Slot{name, position} <> tail:
      slot_index_go(tail, Map.set(&2, Maybe<&2, Nat>, indexed, name, Some{position}))

def slot_index(slots: List<&2, Slot>) -> Map<&2, Maybe<&2, Nat>>:
  slot_index_go(List.reverse(&2, Slot, slots), Map.new(&2, Maybe<&2, Nat>))

def operation_slots(operations: List<&2, M.Operation>, index: Nat) -> List<&2, Slot>:
  match operations:
    case Nil{}:
      Nil{}
    case M.Operation{identity, parameter, result} <> tail:
      +position = index
      Slot{I.operation_key(identity), position} <> operation_slots(tail, 1n+position)

def required_symbol(found: Maybe<&2, Nat>, name: String) -> Result<&2, &2, M.Diagnostic, Nat>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"backend_link", name, "Wasm relocation has no matching prepared symbol"}}
    case Some{position}:
      Done{position}

def lookup_symbol(indexed: Map<&2, Maybe<&2, Nat>>, +name: String) -> Result<&2, &2, M.Diagnostic, Nat>:
  required_symbol(Index.get(Maybe<&2, Nat>, indexed, name, None{}), name)

def symbol_entries(symbols: Catalog) -> Map<&2, Maybe<&2, Nat>>:
  Catalog{entries, constructors, constants, operations} = symbols
  entries

def symbol_constructors(symbols: Catalog) -> Map<&2, Maybe<&2, E.ConstructorSlot>>:
  Catalog{entries, constructors, constants, operations} = symbols
  constructors

def symbol_constants(symbols: Catalog) -> Map<&2, Maybe<&2, Nat>>:
  Catalog{entries, constructors, constants, operations} = symbols
  constants

def symbol_operations(symbols: Catalog) -> Map<&2, Maybe<&2, Nat>>:
  Catalog{entries, constructors, constants, operations} = symbols
  operations

def context_locals(context: Context) -> List<&2, Local>:
  Context{locals, next_local, labels, provider} = context
  locals

def context_next(context: Context) -> Nat:
  Context{locals, next_local, labels, provider} = context
  next_local

def reserve(context: Context, count: Nat) -> Context:
  Context{locals, next_local, labels, provider} = context
  Context{locals, Nat.add(next_local, count), labels, provider}

def bind(context: Context, name: String, location: Location) -> Context:
  Context{locals, next_local, labels, provider} = context
  Context{Local{name, location} <> locals, next_local, labels, provider}

def control(context: Context, label: Maybe<&2, Nat>) -> Context:
  Context{locals, next_local, labels, provider} = context
  Context{locals, next_local, label <> labels, provider}

def with_provider(context: Context, provider: Nat) -> Context:
  Context{locals, next_local, labels, previous} = context
  Context{locals, next_local, labels, provider}

def context_provider(context: Context) -> Nat:
  Context{locals, next_local, labels, provider} = context
  provider

def label_depth(labels: List<&2, Maybe<&2, Nat>>, +wanted: Nat, depth: Nat) -> Result<&2, &2, M.Diagnostic, Nat>:
  match labels:
    case Nil{}:
      Fail{M.Diagnostic{"internal_error", Nat.show(wanted), "Wasm return has no enclosing block"}}
    case None{} <> tail:
      label_depth(tail, wanted, 1n+depth)
    case Some{label} <> tail:
      +index = depth
      Bool.pick(Result<&2, &2, M.Diagnostic, Nat>, Nat.is_eq(label, wanted), Done{index}, label_depth(tail, wanted, 1n+index))

def return_depth(context: Context, label: Nat) -> Result<&2, &2, M.Diagnostic, Nat>:
  Context{locals, next_local, labels, provider} = context
  label_depth(labels, label, 0n)

def loads(offsets: List<&2, Nat>) -> List<&2, U32>:
  match offsets:
    case Nil{}:
      Nil{}
    case offset <> tail:
      concat([40, 2], concat(unsigned_leb(offset), loads(tail)))

def read_location(location: Location) -> List<&2, U32>:
  Location{local, offsets} = location
  concat(32 <> unsigned_leb(local), loads(offsets))

def field_location(location: Location, offset: Nat) -> Location:
  Location{local, offsets} = location
  Location{local, List.append(&2, Nat, offsets, [offset])}

def pattern_bindings_work(+fuel: Nat, work: PatternWork, context: Context) -> Result<&2, &2, M.Diagnostic, Context>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"backend_limit", "pattern", "pattern binding emission exceeded its structural depth limit"}}
    case 1n+rest OnePattern{M.BindingPattern{name}, location}:
      Done{bind(context, name, location)}
    case 1n+rest OnePattern{M.ConstructorPattern{constructor, Some{payload}}, location}:
      pattern_bindings_work(rest, OnePattern{payload, field_location(location, 4n)}, context)
    case 1n+rest OnePattern{M.ProductPattern{elements}, location}:
      pattern_bindings_work(rest, ProductFields{elements, location, 0n}, context)
    case 1n+rest OnePattern{pattern, location}:
      Done{context}
    case 1n+rest ProductFields{Nil{}, location, offset}:
      Done{context}
    case 1n+rest ProductFields{head <> tail, +location, +offset}:
      do Result<&2, &2, M.Diagnostic, Context>:
        bound : Context <- pattern_bindings_work(rest, OnePattern{head, field_location(location, offset)}, context)
        pattern_bindings_work(rest, ProductFields{tail, location, 4n+offset}, bound)
    case 1n+rest RowPatterns{Nil{}, first}:
      Done{context}
    case 1n+rest RowPatterns{head <> tail, +first}:
      do Result<&2, &2, M.Diagnostic, Context>:
        bound : Context <- pattern_bindings_work(rest, OnePattern{head, Location{first, Nil{}}}, context)
        pattern_bindings_work(rest, RowPatterns{tail, 1n+first}, bound)

def opcode(operator: M.ScalarOp) -> U32:
  match operator:
    case M.Add{}:
      106
    case M.Subtract{}:
      107
    case M.Multiply{}:
      108
    case M.Equal{}:
      70
    case M.LessThan{}:
      73
    case M.F32Add{}:
      146
    case M.F32Subtract{}:
      147
    case M.F32Multiply{}:
      148
    case M.F32Divide{}:
      149
    case M.F32Equal{}:
      91
    case M.F32NotEqual{}:
      92
    case M.F32LessThan{}:
      93
    case M.F32LessEqual{}:
      95
    case M.F32GreaterThan{}:
      94
    case M.F32GreaterEqual{}:
      96

def unary_opcode(operator: M.UnaryOp) -> List<&2, U32>:
  match operator:
    case M.F32Negate{}:
      [140]
    case M.F32Absolute{}:
      [139]
    case M.F32SquareRoot{}:
      [145]
    case M.F32Floor{}:
      [142]
    case M.F32Ceiling{}:
      [141]
    case M.F32Truncate{}:
      [143]
    case M.U32ToF32{}:
      [179]
    case M.F32ToU32{}:
      [252, 1]

# Private calls, closures, and constructor payloads share the i32 word ABI.
# Reinterpretations bracket real f32 arithmetic; no numeric cast loses bits.
def scalar_from_word(ty: M.Ty) -> List<&2, U32>:
  match ty:
    case M.F32Ty{}:
      [190]
    case _:
      Nil{}

def scalar_to_word(ty: M.Ty) -> List<&2, U32>:
  match ty:
    case M.F32Ty{}:
      [188]
    case _:
      Nil{}

def append_code(left: Code, right: Code, middle: List<&2, U32>, end: List<&2, U32>) -> Code:
  Code{lb, ll} = left
  Code{rb, rl} = right
  Code{fragments_join([lb, [Bytes{middle}], rb, [Bytes{end}]]), Nat.max(ll, rl)}

def require_locals(code: Code, count: Nat) -> Code:
  Code{bytes, locals} = code
  Code{bytes, Nat.max(locals, count)}

def scalar_code(left: Result<&2, &2, M.Diagnostic, Code>, right: Result<&2, &2, M.Diagnostic, Code>, +operator: M.ScalarOp) -> Result<&2, &2, M.Diagnostic, Code>:
  match left right:
    case Fail{error} _:
      Fail{error}
    case Done{code} Fail{error}:
      Fail{error}
    case Done{a} Done{b}:
      +convert = scalar_from_word(M.scalar_parameter(operator))
      Done{append_code(a, b, convert, join([convert, [opcode(operator)], scalar_to_word(M.scalar_result(operator))]))}

def capture_stores(names: List<&2, String>, +locals: List<&2, Local>, +pointer: Nat, offset: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  match names:
    case Nil{}:
      Done{Nil{}}
    case name <> tail:
      +at = offset
      do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
        location : Location <- lookup_local(locals, name)
        rest : List<&2, U32> <- capture_stores(tail, locals, pointer, 4n+at)
        return join([32 <> unsigned_leb(pointer), read_location(location), [54, 2], unsigned_leb(at), rest])

def closure_code(key: String, +captures: List<&2, String>, +context: Context) -> Result<&2, &2, M.Diagnostic, Code>:
  +pointer = context_next(context)
  do Result<&2, &2, M.Diagnostic, Code>:
    stores : List<&2, U32> <- capture_stores(captures, context_locals(context), pointer, 4n)
    return Code{[Bytes{i32_constant(U32.from_nat(Nat.mul(4n, 1n+List.length(&2, String, captures))))}, Allocate{}, Bytes{34 <> unsigned_leb(pointer)}, EntryIndex{key}, Bytes{join([[54, 2, 0], stores, 32 <> unsigned_leb(pointer)])}], 1n+pointer}

def construct_code(tag: Fragment, payload: Code, +slot: Nat) -> Code:
  Code{fragments, locals} = payload
  Code{fragments_join([fragments, [Bytes{concat(33 <> unsigned_leb(slot), i32_constant(8))}, Allocate{}, Bytes{34 <> unsigned_leb(1n+slot)}, tag, Bytes{join([[54, 2, 0], 32 <> unsigned_leb(1n+slot), 32 <> unsigned_leb(slot), [54, 2, 4], 32 <> unsigned_leb(1n+slot)])}]]), Nat.max(locals, 2n+slot)}

def local_get(slot: Nat) -> List<&2, U32>:
  32 <> unsigned_leb(slot)

def element_stores(count: Nat, +pointer: Nat, first: Nat, offset: Nat, reversed: List<&2, List<&2, U32>>) -> List<&2, U32>:
  match count:
    case 0n:
      join(List.reverse(&2, List<&2, U32>, local_get(pointer) <> reversed))
    case 1n+rest:
      +slot = first
      +at = offset
      bytes = join([local_get(pointer), local_get(slot), [54, 2], unsigned_leb(at)])
      element_stores(rest, pointer, 1n+slot, 4n+at, bytes <> reversed)

def product_code(elements: Code, +count: Nat, +first: Nat) -> Code:
  Code{fragments, locals} = elements
  +pointer = Nat.add(first, count)
  Code{fragments_join([fragments, [Bytes{i32_constant(U32.from_nat(Nat.mul(4n, count)))}, Allocate{}, Bytes{concat(33 <> unsigned_leb(pointer), element_stores(count, pointer, first, 0n, Nil{}))}]]), Nat.max(locals, 1n+pointer)}

def product_arity(count: Nat) -> Result<&2, &2, M.Diagnostic, Unit>:
  match count:
    case 0n:
      Fail{M.Diagnostic{"internal_error", "product", "checked products require at least two elements"}}
    case 1n+0n:
      Fail{M.Diagnostic{"internal_error", "product", "checked products require at least two elements"}}
    case 1n+1n+rest:
      Done{Unit{}}

def projection_code(allowed: Bool, index: Nat) -> Result<&2, &2, M.Diagnostic, Code>:
  match allowed:
    case True{}:
      Done{byte_code(concat([40, 2], unsigned_leb(Nat.mul(4n, index))), 0n)}
    case False{}:
      Fail{M.Diagnostic{"backend_limit", "projection", "product projection exceeds the private arena address range"}}

def checked_array_size(allowed: Bool, count: Nat) -> Result<&2, &2, M.Diagnostic, U32>:
  match allowed:
    case True{}:
      Done{U32.from_nat(Nat.mul(4n, 1n+count))}
    case False{}:
      Fail{M.Diagnostic{"backend_limit", "array", "array length exceeds the 16 MiB bootstrap arena"}}

def array_size(+count: Nat) -> Result<&2, &2, M.Diagnostic, U32>:
  checked_array_size(Nat.is_lt(count, U32.to_nat(4194304)), count)

def array_code(elements: Code, +count: Nat, size: U32, +first: Nat) -> Code:
  Code{fragments, locals} = elements
  +pointer = Nat.add(first, count)
  Code{fragments_join([fragments, [Bytes{i32_constant(size)}, Allocate{}, Bytes{join([
    34 <> unsigned_leb(pointer), i32_constant(U32.from_nat(count)), [54, 2, 0],
    element_stores(count, pointer, first, 4n, Nil{})
  ])}]]), Nat.max(locals, 1n+pointer)}

def array_get_code(+first: Nat) -> Code:
  +index = {1n+first : Nat}
  byte_code(join([
    local_get(index), local_get(first), [40, 2, 0, 79, 4, 64, 0, 11],
    local_get(first), local_get(index), [65, 4, 108, 106, 40, 2, 4]
  ]), 2n+first)

# Bounds precede address arithmetic. The copied length is checked before the
# byte count is formed, independently of the allocator's end-address checks.
def array_set_code(+first: Nat) -> Code:
  +index = {1n+first : Nat}
  +value = {2n+first : Nat}
  +length = {3n+first : Nat}
  +pointer = {4n+first : Nat}
  Code{[
    Bytes{join([
      local_get(first), [40, 2, 0], 33 <> unsigned_leb(length),
      local_get(index), local_get(length), [79, 4, 64, 0, 11],
      local_get(length), i32_constant(4194303), [75, 4, 64, 0, 11],
      local_get(length), [65, 1, 106, 65, 4, 108]
    ])},
    Allocate{},
    Bytes{join([
      33 <> unsigned_leb(pointer),
      local_get(pointer), local_get(first), local_get(length), [65, 1, 106, 65, 4, 108, 252, 10, 0, 0],
      local_get(pointer), local_get(index), [65, 4, 108, 106], local_get(value), [54, 2, 4],
      local_get(pointer)
    ])}
  ], 5n+first}

# Provider values contain no dynamic scope. Installing one creates a fresh frame;
# the lexical context selects that frame only for the handled body.
def install_provider(+slot: Nat, outer: Nat) -> Code:
  +frame = {1n+slot : Nat}
  Code{[Bytes{join([33 <> unsigned_leb(slot), i32_constant(12)])}, Allocate{}, Bytes{join([
    34 <> unsigned_leb(frame), local_get(slot), [40, 2, 0, 54, 2, 0],
    local_get(frame), local_get(slot), [40, 2, 4, 54, 2, 4],
    local_get(frame), local_get(outer), [54, 2, 8]
  ])}], 2n+slot}

def invoke_operation(identity: M.TypeId, argument: Code, +slot: Nat, provider: Nat) -> Code:
  Code{fragments, locals} = argument
  +handler = {1n+slot : Nat}
  +value = {2n+slot : Nat}
  Code{fragments_join([fragments, [Bytes{join([
    33 <> unsigned_leb(value), local_get(provider), 33 <> unsigned_leb(slot),
    [2, 64, 3, 64], local_get(slot), [69, 4, 64, 0, 11],
    local_get(slot), [40, 2, 0]
  ])}, OperationIndex{identity}, Bytes{join([
    [70, 13, 1], local_get(slot), [40, 2, 8], 33 <> unsigned_leb(slot), [12, 0, 11, 11],
    local_get(slot), [40, 2, 4], 34 <> unsigned_leb(handler),
    local_get(value), local_get(slot), [40, 2, 8], local_get(handler), [40, 2, 0, 17, 0, 0]
  ])}]]), Nat.max(locals, 3n+slot)}

def constructor_tag(variant: E.ConstructorSlot) -> Nat:
  E.ConstructorSlot{name, tag, payload} = variant
  tag

def lambda_captures(lambda: F.Lambda) -> List<&2, String>:
  F.Lambda{identity, parameter, body, captures} = lambda
  captures

def pattern_test_work(+fuel: Nat, work: PatternTestWork) -> Result<&2, &2, M.Diagnostic, List<&2, Fragment>>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"backend_limit", "pattern", "pattern tests exceeded their structural depth limit"}}
    case 1n+rest PatternTest{M.WildcardPattern{}, location}:
      Done{[Bytes{[65, 1]}]}
    case 1n+rest PatternTest{M.BindingPattern{name}, location}:
      Done{[Bytes{[65, 1]}]}
    case 1n+rest PatternTest{M.UnitPattern{}, location}:
      Done{[Bytes{[65, 1]}]}
    case 1n+rest PatternTest{M.U32Pattern{value}, location}:
      Done{[Bytes{join([read_location(location), i32_constant(value), [70]])}]}
    case 1n+rest PatternTest{M.BoolPattern{value}, location}:
      Done{[Bytes{join([read_location(location), [65, Bool.pick(U32, value, 1, 0), 70]])}]}
    case 1n+rest PatternTest{M.ConstructorPattern{constructor, None{}}, location}:
      Done{[Bytes{concat(read_location(location), [40, 2, 0])}, ConstructorIndex{constructor}, Bytes{[70]}]}
    case 1n+rest PatternTest{M.ConstructorPattern{constructor, Some{payload}}, +location}:
      do Result<&2, &2, M.Diagnostic, List<&2, Fragment>>:
        nested : List<&2, Fragment> <- pattern_test_work(rest, PatternTest{payload, field_location(location, 4n)})
        return fragments_join([[Bytes{concat(read_location(location), [40, 2, 0])}, ConstructorIndex{constructor}, Bytes{[70, 4, 127]}], nested, [Bytes{[5, 65, 0, 11]}]])
    case 1n+rest PatternTest{M.ProductPattern{+elements}, location}:
      do Result<&2, &2, M.Diagnostic, List<&2, Fragment>>:
        valid : Unit <- product_arity(List.length(&2, M.Pattern, elements))
        pattern_test_work(rest, ProductTests{elements, location, 0n, [Bytes{[2, 127]}]})
    case 1n+rest ProductTests{Nil{}, location, offset, reversed}:
      Done{List.reverse.go(&2, Fragment, reversed, [Bytes{[65, 1, 11]}])}
    case 1n+rest ProductTests{head <> tail, +location, +offset, reversed}:
      do Result<&2, &2, M.Diagnostic, List<&2, Fragment>>:
        test : List<&2, Fragment> <- pattern_test_work(rest, PatternTest{head, field_location(location, offset)})
        # One shared result block keeps flat products flat in Wasm too. Each
        # failed field branches with 0; successful fields discard that value.
        pattern_test_work(rest, ProductTests{tail, location, 4n+offset, Bytes{[69, 13, 0, 26]} <> List.reverse.go(&2, Fragment, test, Bytes{[65, 0]} <> reversed)})
    case 1n+rest RowTests{Nil{}, first}:
      Done{[Bytes{[65, 1]}]}
    case 1n+rest RowTests{head <> tail, +first}:
      do Result<&2, &2, M.Diagnostic, List<&2, Fragment>>:
        test : List<&2, Fragment> <- pattern_test_work(rest, PatternTest{head, Location{first, Nil{}}})
        remaining : List<&2, Fragment> <- pattern_test_work(rest, RowTests{tail, 1n+first})
        return fragments_join([test, [Bytes{[4, 127]}], remaining, [Bytes{[5, 65, 0, 11]}]])

def next_scrutinee(values: List<&2, I.Expr>, +first: Nat, compiled: Code, reversed: List<&2, Fragment>, locals: Nat) -> Emission:
  Code{fragments, used} = compiled
  ScrutineesWork{values, 1n+first, Bytes{33 <> unsigned_leb(first)} <> List.reverse.go(&2, Fragment, fragments, reversed), Nat.max(Nat.max(locals, used), 1n+first)}

def emit_expr(+fuel: Nat, work: Emission, +context: Context) -> Result<&2, &2, M.Diagnostic, Code>:
  match fuel:
    case 0n:
      Fail{M.Diagnostic{"backend_limit", "expression", "Wasm lowering exceeded its structural depth limit"}}
    case 1n+rest:
      match work:
        case ExpressionWork{I.UnitExpr{}}:
          Done{byte_code([65, 0], 0n)}
        case ExpressionWork{I.U32Expr{value}}:
          Done{byte_code(i32_constant(value), 0n)}
        case ExpressionWork{I.F32Expr{value}}:
          Done{byte_code(i32_constant(F32.bits(value)), 0n)}
        case ExpressionWork{I.BoolExpr{value}}:
          Done{byte_code([65, Bool.pick(U32, value, 1, 0)], 0n)}
        case ExpressionWork{I.LocalExpr{name}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            location : Location <- lookup_local(context_locals(context), name)
            return byte_code(read_location(location), 0n)
        case ExpressionWork{I.ConstantExpr{name}}:
          Done{Code{[ConstantReference{name}], 0n}}
        case ExpressionWork{I.ClosureExpr{key, captures}}:
          closure_code(key, captures, context)
        case ExpressionWork{I.PanicExpr{message}}:
          Done{byte_code([0], 0n)}
        case ExpressionWork{I.ProductExpr{+elements}}:
          +first = context_next(context)
          +count = List.length(&2, I.Expr, elements)
          do Result<&2, &2, M.Diagnostic, Code>:
            valid : Unit <- product_arity(count)
            values : Code <- emit_expr(rest, ScrutineesWork{elements, first, Nil{}, 0n}, reserve(context, 1n+count))
            return product_code(values, count, first)
        case ExpressionWork{I.ProjectExpr{value, +index}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            compiled : Code <- emit_expr(rest, ExpressionWork{value}, context)
            access : Code <- projection_code(Nat.is_lt(index, U32.to_nat(4194304)), index)
            return append_code(compiled, access, Nil{}, Nil{})
        case ExpressionWork{I.ArrayExpr{+elements}}:
          +first = context_next(context)
          +count = List.length(&2, I.Expr, elements)
          do Result<&2, &2, M.Diagnostic, Code>:
            size : U32 <- array_size(count)
            values : Code <- emit_expr(rest, ScrutineesWork{elements, first, Nil{}, 0n}, reserve(context, 1n+count))
            return array_code(values, count, size, first)
        case ExpressionWork{I.ArrayGetExpr{array, index}}:
          +first = context_next(context)
          do Result<&2, &2, M.Diagnostic, Code>:
            operands : Code <- emit_expr(rest, ScrutineesWork{[array, index], first, Nil{}, 0n}, reserve(context, 2n))
            return append_code(operands, array_get_code(first), Nil{}, Nil{})
        case ExpressionWork{I.ArraySetExpr{array, index, value}}:
          +first = context_next(context)
          do Result<&2, &2, M.Diagnostic, Code>:
            operands : Code <- emit_expr(rest, ScrutineesWork{[array, index, value], first, Nil{}, 0n}, reserve(context, 5n))
            return append_code(operands, array_set_code(first), Nil{}, Nil{})
        case ExpressionWork{I.ArrayLengthExpr{array}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            value : Code <- emit_expr(rest, ExpressionWork{array}, context)
            return append_code(value, byte_code([40, 2, 0], 0n), Nil{}, Nil{})
        case ExpressionWork{I.ProviderExpr{identity, implementation}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            value : Code <- emit_expr(rest, ExpressionWork{implementation}, reserve(context, 2n))
            return construct_code(OperationIndex{identity}, value, context_next(context))
        case ExpressionWork{I.HandleExpr{provider, body}}:
          +slot = context_next(context)
          do Result<&2, &2, M.Diagnostic, Code>:
            value : Code <- emit_expr(rest, ExpressionWork{provider}, reserve(context, 2n))
            scoped : Code <- emit_expr(rest, ExpressionWork{body}, with_provider(reserve(context, 2n), 1n+slot))
            return append_code(append_code(value, install_provider(slot, context_provider(context)), Nil{}, Nil{}), scoped, Nil{}, Nil{})
        case ExpressionWork{I.InvokeOperationExpr{identity, argument}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            value : Code <- emit_expr(rest, ExpressionWork{argument}, reserve(context, 3n))
            return invoke_operation(identity, value, context_next(context), context_provider(context))
        case ExpressionWork{I.ConstructExpr{constructor, None{}}}:
          Done{construct_code(ConstructorIndex{constructor}, byte_code([65, 0], 0n), context_next(context))}
        case ExpressionWork{I.ConstructExpr{constructor, Some{payload}}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            value : Code <- emit_expr(rest, ExpressionWork{payload}, reserve(context, 2n))
            return construct_code(ConstructorIndex{constructor}, value, context_next(context))
        case ExpressionWork{I.ApplyExpr{callee, argument}}:
          +slot = context_next(context)
          do Result<&2, &2, M.Diagnostic, Code>:
            function : Code <- emit_expr(rest, ExpressionWork{callee}, reserve(context, 1n))
            value : Code <- emit_expr(rest, ExpressionWork{argument}, reserve(context, 1n))
            return require_locals(append_code(function, value, join([33 <> unsigned_leb(slot), local_get(slot)]), join([local_get(context_provider(context)), local_get(slot), [40, 2, 0, 17, 0, 0]])), 1n+slot)
        case ExpressionWork{I.CallExpr{key, argument}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            value : Code <- emit_expr(rest, ExpressionWork{argument}, context)
            return append_code(append_code(byte_code([65, 0], 0n), value, Nil{}, Nil{}), Code{[NamedCall{key}], 0n}, local_get(context_provider(context)), Nil{})
        case ExpressionWork{I.ScalarExpr{operator, left, right}}:
          a = emit_expr(rest, ExpressionWork{left}, context)
          b = emit_expr(rest, ExpressionWork{right}, context)
          scalar_code(a, b, operator)
        case ExpressionWork{I.UnaryExpr{+operator, value}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            compiled : Code <- emit_expr(rest, ExpressionWork{value}, context)
            return append_code(compiled, byte_code(join([scalar_from_word(M.unary_parameter(operator)), unary_opcode(operator), scalar_to_word(M.unary_result(operator))]), 0n), Nil{}, Nil{})
        case ExpressionWork{I.LetExpr{name, value, body}}:
          +slot = context_next(context)
          do Result<&2, &2, M.Diagnostic, Code>:
            v : Code <- emit_expr(rest, ExpressionWork{value}, context)
            b : Code <- emit_expr(rest, ExpressionWork{body}, bind(reserve(context, 1n), name, Location{slot, Nil{}}))
            return require_locals(append_code(v, b, 33 <> unsigned_leb(slot), Nil{}), 1n+slot)
        case ExpressionWork{I.IfExpr{condition, consequent, alternative}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            c : Code <- emit_expr(rest, ExpressionWork{condition}, context)
            y : Code <- emit_expr(rest, ExpressionWork{consequent}, control(context, None{}))
            n : Code <- emit_expr(rest, ExpressionWork{alternative}, control(context, None{}))
            return append_code(c, append_code(y, n, [5], [11]), [4, 127], Nil{})
        case ExpressionWork{I.SequenceExpr{first, next}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            a : Code <- emit_expr(rest, ExpressionWork{first}, context)
            b : Code <- emit_expr(rest, ExpressionWork{next}, context)
            return append_code(a, b, [26], Nil{})
        case ExpressionWork{I.MatchExpr{+values, arms}}:
          +slot = context_next(context)
          +count = List.length(&2, I.Expr, values)
          do Result<&2, &2, M.Diagnostic, Code>:
            v : Code <- emit_expr(rest, ScrutineesWork{values, slot, Nil{}, 0n}, reserve(context, count))
            b : Code <- emit_expr(rest, ArmsWork{arms, slot}, reserve(context, count))
            return require_locals(append_code(v, b, Nil{}, Nil{}), Nat.add(slot, count))
        case ExpressionWork{I.GuardExpr{+pattern, value, alternative, body}}:
          +slot = context_next(context)
          +nested = control(reserve(context, 1n), None{})
          do Result<&2, &2, M.Diagnostic, Code>:
            v : Code <- emit_expr(rest, ExpressionWork{value}, reserve(context, 1n))
            test : List<&2, Fragment> <- pattern_test_work(rest, PatternTest{pattern, Location{slot, Nil{}}})
            bound : Context <- pattern_bindings_work(rest, OnePattern{pattern, Location{slot, Nil{}}}, nested)
            yes : Code <- emit_expr(rest, ExpressionWork{body}, bound)
            no : Code <- emit_expr(rest, ExpressionWork{alternative}, nested)
            return require_locals(append_code(append_code(v, Code{test, 0n}, 33 <> unsigned_leb(slot), Nil{}), append_code(yes, no, [5], [11]), [4, 127], Nil{}), 1n+slot)
        case ExpressionWork{I.BlockExpr{label, body}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            value : Code <- emit_expr(rest, ExpressionWork{body}, control(context, Some{label}))
            return append_code(byte_code([2, 127], 0n), value, Nil{}, [11])
        case ExpressionWork{I.ReturnExpr{label, value}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            depth : Nat <- return_depth(context, label)
            v : Code <- emit_expr(rest, ExpressionWork{value}, context)
            return append_code(v, byte_code(12 <> unsigned_leb(depth), 0n), Nil{}, Nil{})
        case ScrutineesWork{Nil{}, first, reversed, locals}:
          Done{Code{List.reverse(&2, Fragment, reversed), locals}}
        case ScrutineesWork{head <> tail, first, reversed, locals}:
          do Result<&2, &2, M.Diagnostic, Code>:
            value : Code <- emit_expr(rest, ExpressionWork{head}, context)
            emit_expr(rest, next_scrutinee(tail, first, value, reversed, locals), context)
        case ArmsWork{Nil{}, first}:
          Done{byte_code([0], 0n)}
        case ArmsWork{M.MatchArm{+patterns, body} <> tail, +first}:
          +nested = control(context, None{})
          do Result<&2, &2, M.Diagnostic, Code>:
            test : List<&2, Fragment> <- pattern_test_work(rest, RowTests{patterns, first})
            bound : Context <- pattern_bindings_work(rest, RowPatterns{patterns, first}, nested)
            yes : Code <- emit_expr(rest, ExpressionWork{body}, bound)
            no : Code <- emit_expr(rest, ArmsWork{tail, first}, nested)
            return append_code(Code{test, 0n}, append_code(yes, no, [5], [11]), [4, 127], Nil{})

def word_bytes(+word: U32) -> List<&2, U32>:
  [U32.and(word, 255), U32.and(U32.shrn(word, 8n), 255), U32.and(U32.shrn(word, 16n), 255), U32.shrn(word, 24n)]

def words_bytes(words: List<&2, U32>) -> List<&2, U32>:
  match words:
    case Nil{}:
      Nil{}
    case head <> tail:
      concat(word_bytes(head), words_bytes(tail))

def heap_allocate(+words: List<&2, U32>, heap: Heap) -> Result<&2, &2, M.Diagnostic, Serialized>:
  Heap{+next, chunks} = heap
  +end = Nat.add(next, Nat.mul(4n, List.length(&2, U32, words)))
  Bool.pick(Result<&2, &2, M.Diagnostic, Serialized>, Nat.is_le(end, U32.to_nat(16777216)), Done{Serialized{[U32.from_nat(next)], Heap{end, words_bytes(words) <> chunks}}}, Fail{M.Diagnostic{"backend_limit", "constant", "static constants exceed the 16 MiB bootstrap arena"}})

def capture_values(names: List<&2, String>, +environment: List<&2, C.Binding<C.Value>>) -> Result<&2, &2, M.Diagnostic, List<&2, C.Value>>:
  match names:
    case Nil{}:
      Done{Nil{}}
    case name <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, C.Value>>:
        value : C.Value <- C.lookup_local(environment, name)
        rest : List<&2, C.Value> <- capture_values(tail, environment)
        return value <> rest

def only_word(words: List<&2, U32>) -> Result<&2, &2, M.Diagnostic, U32>:
  match words:
    case word <> Nil{}:
      Done{word}
    case _:
      Fail{M.Diagnostic{"internal_error", "constant", "Wasm serialization expected one machine word"}}

def serialized_words(encoded: Serialized) -> List<&2, U32>:
  Serialized{words, heap} = encoded
  words

def serialized_heap(encoded: Serialized) -> Heap:
  Serialized{words, heap} = encoded
  heap

def static_slots(encoded: StaticConstants) -> List<&2, Slot>:
  StaticConstants{slots, heap} = encoded
  slots

def static_heap(encoded: StaticConstants) -> Heap:
  StaticConstants{slots, heap} = encoded
  heap

def heap_end(heap: Heap) -> Nat:
  Heap{next, chunks} = heap
  next

def serialize(+fuel: Nat, work: Serialization, +catalog: StaticCatalog, heap: Heap) -> Result<&2, &2, M.Diagnostic, Serialized>:
  match fuel:
    case 0n:
      Fail{M.Diagnostic{"backend_limit", "constant", "constant serialization exceeded its structural depth limit"}}
    case 1n+rest:
      match work:
        case ValueWork{C.UnitValue{}}:
          Done{Serialized{[0], heap}}
        case ValueWork{C.U32Value{value}}:
          Done{Serialized{[value], heap}}
        case ValueWork{C.F32Value{value}}:
          Done{Serialized{[F32.bits(value)], heap}}
        case ValueWork{C.ProductValue{+elements}}:
          do Result<&2, &2, M.Diagnostic, Serialized>:
            valid : Unit <- product_arity(List.length(&2, C.Value, elements))
            +encoded : Serialized <- serialize(rest, ValuesWork{elements}, catalog, heap)
            heap_allocate(serialized_words(encoded), serialized_heap(encoded))
        case ValueWork{C.ArrayValue{+elements}}:
          +count = List.length(&2, C.Value, elements)
          do Result<&2, &2, M.Diagnostic, Serialized>:
            size : U32 <- array_size(count)
            +encoded : Serialized <- serialize(rest, ValuesWork{elements}, catalog, heap)
            heap_allocate(U32.from_nat(count) <> serialized_words(encoded), serialized_heap(encoded))
        case ValueWork{C.OperationValue{identity}}:
          do Result<&2, &2, M.Diagnostic, Serialized>:
            index : Nat <- lookup_slot(static_entries(catalog), I.operation_key(identity))
            heap_allocate([U32.from_nat(index)], heap)
        case ValueWork{C.ProviderValue{identity, implementation}}:
          do Result<&2, &2, M.Diagnostic, Serialized>:
            operation : Nat <- lookup_slot(static_operations(catalog), I.operation_key(identity))
            +handler : Serialized <- serialize(rest, ValueWork{implementation}, catalog, heap)
            word : U32 <- only_word(serialized_words(handler))
            heap_allocate([U32.from_nat(operation), word], serialized_heap(handler))
        case ValueWork{C.EffectDescriptorValue{identity}}:
          Fail{I.const_only()}
        case ValueWork{C.EffectSetValue{operations}}:
          Fail{I.const_only()}
        case ValueWork{C.BoolValue{value}}:
          Done{Serialized{[Bool.pick(U32, value, 1, 0)], heap}}
        case ValueWork{C.FunctionValue{name}}:
          do Result<&2, &2, M.Diagnostic, Serialized>:
            index : Nat <- lookup_slot(static_entries(catalog), "fn:" ++ name)
            result : Serialized <- heap_allocate([U32.from_nat(index)], heap)
            return result
        case ValueWork{C.ConstructorFunctionValue{constructor}}:
          do Result<&2, &2, M.Diagnostic, Serialized>:
            index : Nat <- lookup_slot(static_entries(catalog), "constructor:" ++ constructor)
            result : Serialized <- heap_allocate([U32.from_nat(index)], heap)
            return result
        case ValueWork{C.DataValue{+constructor, None{}}}:
          do Result<&2, &2, M.Diagnostic, Serialized>:
            variant : E.ConstructorSlot <- lookup_constructor(E.constructor_get(I.metadata_constructors(static_projection(catalog)), constructor), constructor)
            result : Serialized <- heap_allocate([U32.from_nat(constructor_tag(variant)), 0], heap)
            return result
        case ValueWork{C.DataValue{+constructor, Some{payload}}}:
          do Result<&2, &2, M.Diagnostic, Serialized>:
            variant : E.ConstructorSlot <- lookup_constructor(E.constructor_get(I.metadata_constructors(static_projection(catalog)), constructor), constructor)
            +child : Serialized <- serialize(rest, ValueWork{payload}, catalog, heap)
            word : U32 <- only_word(serialized_words(child))
            result : Serialized <- heap_allocate([U32.from_nat(constructor_tag(variant)), word], serialized_heap(child))
            return result
        case ValueWork{C.ClosureValue{+identity, parameter, body, environment}}:
          do Result<&2, &2, M.Diagnostic, Serialized>:
            index : Nat <- lookup_slot(static_entries(catalog), "lambda:" ++ Nat.show(identity))
            lambda : F.Lambda <- lookup_lambda(I.lambda_get(I.metadata_lambdas(static_projection(catalog)), identity), identity)
            values : List<&2, C.Value> <- capture_values(lambda_captures(lambda), environment)
            +captured : Serialized <- serialize(rest, ValuesWork{values}, catalog, heap)
            result : Serialized <- heap_allocate(U32.from_nat(index) <> serialized_words(captured), serialized_heap(captured))
            return result
        case ValueWork{C.ReturnValue{label, value}}:
          Fail{M.Diagnostic{"internal_error", "constant", "an unhandled return escaped constant evaluation"}}
        case ValueWork{C.MatchValuesValue{values}}:
          Fail{M.Diagnostic{"internal_error", "constant", "a match scrutinee collection escaped constant evaluation"}}
        case ValuesWork{Nil{}}:
          Done{Serialized{Nil{}, heap}}
        case ValuesWork{head <> tail}:
          do Result<&2, &2, M.Diagnostic, Serialized>:
            +first : Serialized <- serialize(rest, ValueWork{head}, catalog, heap)
            +remaining : Serialized <- serialize(rest, ValuesWork{tail}, catalog, serialized_heap(first))
            return Serialized{concat(serialized_words(first), serialized_words(remaining)), serialized_heap(remaining)}

def serialize_constants(constants: List<&2, C.Binding<C.Value>>, +catalog: StaticCatalog, heap: Heap) -> Result<&2, &2, M.Diagnostic, StaticConstants>:
  match constants:
    case Nil{}:
      Done{StaticConstants{Nil{}, heap}}
    case C.Binding{name, value} <> tail:
      do Result<&2, &2, M.Diagnostic, StaticConstants>:
        +encoded : Serialized <- serialize(U32.to_nat(4096), ValueWork{value}, catalog, heap)
        word : U32 <- only_word(serialized_words(encoded))
        +remaining : StaticConstants <- serialize_constants(tail, catalog, serialized_heap(encoded))
        return StaticConstants{Slot{name, U32.to_nat(word)} <> static_slots(remaining), static_heap(remaining)}

def scalar_type(ty: M.Ty) -> Bool:
  match ty:
    case M.UnitTy{}:
      True{}
    case M.U32Ty{}:
      True{}
    case M.F32Ty{}:
      True{}
    case M.BoolTy{}:
      True{}
    case _:
      False{}

def export_type(exported: Bool, supported: Bool, name: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match exported supported:
    case True{} False{}:
      Fail{M.Diagnostic{"backend_type", name, "Wasm export results and constants require Unit, U32, F32, or Bool; parameters may also be scalar callbacks with the closed Foreign effect"}}
    case _ _:
      Done{Unit{}}

def foreign_labels(labels: List<&2, M.TypeId>) -> Bool:
  match labels:
    case Nil{}:
      True{}
    case identity <> tail:
      Bool.and(M.is_foreign(identity), foreign_labels(tail))

def export_effects(row: M.EffectRow, parameter: M.Ty, name: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match row parameter:
    case M.EffectRow{Nil{}, M.ClosedRow{}} _:
      Done{Unit{}}
    case M.EffectRow{labels, M.ClosedRow{}} M.FunctionTy{input, output, effects}:
      Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, foreign_labels(labels), Done{Unit{}}, Fail{M.Diagnostic{"backend_effect", name, "Wasm exports must handle ordinary operations; only explicit callback Foreign effects may cross the host boundary"}})
    case M.EffectRow{labels, M.ClosedRow{}} _:
      Fail{M.Diagnostic{"backend_effect", name, "an exported effect requires an explicit host callback parameter"}}
    case _ _:
      Fail{M.Diagnostic{"backend_effect", name, "Wasm exports require a closed effect row"}}

def abi_scalar(ty: M.Ty, name: String) -> Result<&2, &2, M.Diagnostic, AbiScalar>:
  match ty:
    case M.UnitTy{}:
      Done{UnitScalar{}}
    case M.U32Ty{}:
      Done{U32Scalar{}}
    case M.BoolTy{}:
      Done{BoolScalar{}}
    case M.F32Ty{}:
      Done{F32Scalar{}}
    case _:
      Fail{M.Diagnostic{"backend_type", name, "the host ABI accepts only Unit, U32, Bool, and F32 scalar values"}}

def callback_effects(row: M.EffectRow, name: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match row:
    case M.EffectRow{identity <> Nil{}, M.ClosedRow{}}:
      Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, M.is_foreign(identity), Done{Unit{}}, Fail{M.Diagnostic{"backend_type", name, "host callback parameters require exactly the closed Foreign effect"}})
    case _:
      Fail{M.Diagnostic{"backend_type", name, "host callback parameters require exactly the closed Foreign effect"}}

def abi_parameter(ty: M.Ty, +name: String) -> Result<&2, &2, M.Diagnostic, AbiParameter>:
  match ty:
    case M.FunctionTy{parameter, result, effects}:
      do Result<&2, &2, M.Diagnostic, AbiParameter>:
        valid : Unit <- callback_effects(effects, name)
        input : AbiScalar <- abi_scalar(parameter, name)
        output : AbiScalar <- abi_scalar(result, name)
        return CallbackParameter{Callback{input, output}}
    case scalar:
      do Result<&2, &2, M.Diagnostic, AbiParameter>:
        value : AbiScalar <- abi_scalar(scalar, name)
        return ScalarParameter{value}

def function_abi(signature: M.Signature) -> Result<&2, &2, M.Diagnostic, AbiFunction>:
  M.Signature{+name, parameter, result, variables, effects} = signature
  do Result<&2, &2, M.Diagnostic, AbiFunction>:
    input : AbiParameter <- abi_parameter(parameter, name)
    output : AbiScalar <- abi_scalar(result, name)
    return AbiFunction{name, input, output}

def check_signature(exported: Bool, signature: M.Signature) -> Result<&2, &2, M.Diagnostic, Unit>:
  match exported:
    case False{}:
      Done{Unit{}}
    case True{}:
      M.Signature{+name, +parameter, result, variables, row} = signature
      do Result<&2, &2, M.Diagnostic, Unit>:
        effects : Unit <- export_effects(row, parameter, name)
        supported : AbiFunction <- function_abi(M.Signature{name, parameter, result, variables, M.empty_row()})
        return Unit{}

def check_functions(functions: List<&2, M.CheckedFunction>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match functions:
    case Nil{}:
      Done{Unit{}}
    case M.CheckedFunction{M.Function{name, exported, parameter, param_ann, result_ann, body}, signature, effects} <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        supported : Unit <- check_signature(exported, signature)
        check_functions(tail)

def exported_constants(constants: List<&2, M.CheckedConstant>) -> Result<&2, &2, M.Diagnostic, List<&2, ExportedConstant>>:
  match constants:
    case Nil{}:
      Done{Nil{}}
    case M.CheckedConstant{M.Constant{+name, +exported, annotation, value}, +ty, variables} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, ExportedConstant>>:
        supported : Unit <- export_type(exported, scalar_type(ty), name)
        +rest : List<&2, ExportedConstant> <- exported_constants(tail)
        return Bool.pick(List<&2, ExportedConstant>, exported, ExportedConstant{name, ty} <> rest, rest)

def capture_locals(names: List<&2, String>, offset: Nat) -> List<&2, Local>:
  match names:
    case Nil{}:
      Nil{}
    case name <> tail:
      +at = offset
      Local{name, Location{0n, [at]}} <> capture_locals(tail, 4n+at)

def body_bytes(bytes: List<&2, U32>, locals: Nat, parameters: Nat) -> List<&2, U32>:
  +count = Nat.sub(locals, parameters)
  sized(join([Bool.pick(List<&2, U32>, Nat.is_eq(count, 0n), [0], 1 <> concat(unsigned_leb(count), [127])), bytes, [11]]))

def body_plan(instructions: BytePlan, locals: Nat, parameters: Nat) -> BytePlan:
  +count = Nat.sub(locals, parameters)
  declarations = Bool.pick(List<&2, U32>, Nat.is_eq(count, 0n), [0], 1 <> concat(unsigned_leb(count), [127]))
  plan_sized(plan_sequence([byte_plan(declarations), instructions, byte_plan([11])]))

def compile_entry(job: CodegenJob) -> Result<&2, &2, M.Diagnostic, EntryCode>:
  CodegenJob{key, parameter, body, captures} = job
  do Result<&2, &2, M.Diagnostic, EntryCode>:
    compiled : Code <- emit_expr(U32.to_nat(16384), ExpressionWork{body}, Context{Local{parameter, Location{1n, Nil{}}} <> capture_locals(captures, 4n), 3n, Nil{}, 2n})
    return EntryCode{key, compiled}

def merge_entries(left: Result<&2, &2, M.Diagnostic, List<&2, EntryCode>>, right: Result<&2, &2, M.Diagnostic, List<&2, EntryCode>>) -> Result<&2, &2, M.Diagnostic, List<&2, EntryCode>>:
  match left right:
    case Fail{error} _:
      Fail{error}
    case Done{first} Fail{error}:
      Fail{error}
    case Done{first} Done{second}:
      Done{List.reverse.go(&2, EntryCode, List.reverse(&2, EntryCode, first), second)}

# Work units count IR nodes, pattern nodes, and capture lanes. This is a
# scheduler estimate, not a compiler limit or a function of the thread count.
def codegen_grain() -> Nat:
  512n

def codegen_weight_work(fuel: Nat, pending: List<&2, CodegenWeightWork>, weight: Nat) -> Nat:
  match fuel pending:
    case _ Nil{}:
      weight
    case 0n _:
      weight
    case 1n+rest WeightExpression{I.ClosureExpr{key, captures}} <> tail:
      codegen_weight_work(rest, WeightCaptures{captures} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.ConstructExpr{constructor, Some{payload}}} <> tail:
      codegen_weight_work(rest, WeightExpression{payload} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.ApplyExpr{callee, argument}} <> tail:
      codegen_weight_work(rest, WeightExpression{callee} <> WeightExpression{argument} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.CallExpr{key, argument}} <> tail:
      codegen_weight_work(rest, WeightExpression{argument} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.ScalarExpr{operator, left, right}} <> tail:
      codegen_weight_work(rest, WeightExpression{left} <> WeightExpression{right} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.UnaryExpr{operator, value}} <> tail:
      codegen_weight_work(rest, WeightExpression{value} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.LetExpr{name, value, body}} <> tail:
      codegen_weight_work(rest, WeightExpression{value} <> WeightExpression{body} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.IfExpr{condition, consequent, alternative}} <> tail:
      codegen_weight_work(rest, WeightExpression{condition} <> WeightExpression{consequent} <> WeightExpression{alternative} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.SequenceExpr{first, next}} <> tail:
      codegen_weight_work(rest, WeightExpression{first} <> WeightExpression{next} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.MatchExpr{values, arms}} <> tail:
      codegen_weight_work(rest, WeightExpressions{values} <> WeightArms{arms} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.GuardExpr{pattern, value, alternative, body}} <> tail:
      codegen_weight_work(rest, WeightPattern{pattern} <> WeightExpression{value} <> WeightExpression{alternative} <> WeightExpression{body} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.BlockExpr{label, body}} <> tail:
      codegen_weight_work(rest, WeightExpression{body} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.ReturnExpr{label, value}} <> tail:
      codegen_weight_work(rest, WeightExpression{value} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.ProviderExpr{identity, implementation}} <> tail:
      codegen_weight_work(rest, WeightExpression{implementation} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.HandleExpr{provider, body}} <> tail:
      codegen_weight_work(rest, WeightExpression{provider} <> WeightExpression{body} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.InvokeOperationExpr{identity, argument}} <> tail:
      codegen_weight_work(rest, WeightExpression{argument} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.ProductExpr{elements}} <> tail:
      codegen_weight_work(rest, WeightExpressions{elements} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.ProjectExpr{value, index}} <> tail:
      codegen_weight_work(rest, WeightExpression{value} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.ArrayExpr{elements}} <> tail:
      codegen_weight_work(rest, WeightExpressions{elements} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.ArrayGetExpr{array, index}} <> tail:
      codegen_weight_work(rest, WeightExpression{array} <> WeightExpression{index} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.ArraySetExpr{array, index, value}} <> tail:
      codegen_weight_work(rest, WeightExpression{array} <> WeightExpression{index} <> WeightExpression{value} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.ArrayLengthExpr{array}} <> tail:
      codegen_weight_work(rest, WeightExpression{array} <> tail, 1n+weight)
    case 1n+rest WeightExpression{expression} <> tail:
      codegen_weight_work(rest, tail, 1n+weight)
    case 1n+rest WeightExpressions{Nil{}} <> tail:
      codegen_weight_work(rest, tail, weight)
    case 1n+rest WeightExpressions{head <> following} <> tail:
      codegen_weight_work(rest, WeightExpression{head} <> WeightExpressions{following} <> tail, weight)
    case 1n+rest WeightPattern{M.ConstructorPattern{constructor, Some{payload}}} <> tail:
      codegen_weight_work(rest, WeightPattern{payload} <> tail, 1n+weight)
    case 1n+rest WeightPattern{M.ProductPattern{elements}} <> tail:
      codegen_weight_work(rest, WeightPatterns{elements} <> tail, 1n+weight)
    case 1n+rest WeightPattern{pattern} <> tail:
      codegen_weight_work(rest, tail, 1n+weight)
    case 1n+rest WeightPatterns{Nil{}} <> tail:
      codegen_weight_work(rest, tail, weight)
    case 1n+rest WeightPatterns{head <> following} <> tail:
      codegen_weight_work(rest, WeightPattern{head} <> WeightPatterns{following} <> tail, weight)
    case 1n+rest WeightArms{Nil{}} <> tail:
      codegen_weight_work(rest, tail, weight)
    case 1n+rest WeightArms{M.MatchArm{patterns, body} <> following} <> tail:
      codegen_weight_work(rest, WeightPatterns{patterns} <> WeightExpression{body} <> WeightArms{following} <> tail, 1n+weight)
    case 1n+rest WeightCaptures{Nil{}} <> tail:
      codegen_weight_work(rest, tail, weight)
    case 1n+rest WeightCaptures{name <> following} <> tail:
      codegen_weight_work(rest, WeightCaptures{following} <> tail, 1n+weight)

def codegen_weight(job: CodegenJob) -> Nat:
  CodegenJob{key, parameter, body, captures} = job
  # Saturating this estimate bounds planning overhead without rejecting work.
  codegen_weight_work(65536n, [WeightExpression{body}, WeightCaptures{captures}], 8n)

def weigh_entries(jobs: List<&2, CodegenJob>, reversed: List<&2, WeightedEntry<CodegenJob>>, weight: Nat) -> EntryWorkload<CodegenJob>:
  match jobs:
    case Nil{}:
      EntryWorkload{List.reverse(&2, WeightedEntry<CodegenJob>, reversed), weight}
    case +job <> tail:
      +estimated = codegen_weight(job)
      weigh_entries(tail, WeightedEntry{job, estimated} <> reversed, Nat.add(weight, estimated))

def entry_partition_valid(-A: Data, large: Bool, left: List<&2, WeightedEntry<A>>, right: List<&2, WeightedEntry<A>>, left_weight: Nat, right_weight: Nat) -> EntryPartition<A>:
  match large left right:
    case True{} first <> xs second <> ys:
      EntryFork{EntryWorkload{first <> xs, left_weight}, EntryWorkload{second <> ys, right_weight}}
    case _ _ _:
      EntryLeaf{List.reverse.go(&2, WeightedEntry<A>, List.reverse(&2, WeightedEntry<A>, left), right)}

def entry_split_boundary(-A: Data, previous: Bool, latest: WeightedEntry<A>, reversed: List<&2, WeightedEntry<A>>, following: List<&2, WeightedEntry<A>>, +previous_weight: Nat, +weight: Nat, +total: Nat, +grain: Nat) -> EntryPartition<A>:
  match previous:
    case True{}:
      EntryFork{EntryWorkload{List.reverse(&2, WeightedEntry<A>, reversed), previous_weight}, EntryWorkload{latest <> following, Nat.sub(total, previous_weight)}}
    case False{}:
      +right_weight = Nat.sub(total, weight)
      entry_partition_valid(A, Bool.and(Nat.is_le(grain, weight), Nat.is_le(grain, right_weight)), List.reverse(&2, WeightedEntry<A>, latest <> reversed), following, weight, right_weight)

def split_entries(-A: Data, entries: List<&2, WeightedEntry<A>>, +target: Nat, +total: Nat, +grain: Nat, +weight: Nat, reversed: List<&2, WeightedEntry<A>>, ready: Bool) -> EntryPartition<A>:
  match entries reversed ready:
    case _ WeightedEntry{job, +estimated} <> previous True{}:
      +before = Nat.sub(weight, estimated)
      +earlier = Bool.and(Nat.is_le(Nat.max(1n, grain), before), Nat.is_le(grain, Nat.sub(total, before)))
      nearer = Nat.is_le(Nat.sub(target, before), Nat.sub(weight, target))
      entry_split_boundary(A, Bool.and(earlier, nearer), WeightedEntry{job, estimated}, previous, entries, before, weight, total, grain)
    case _ Nil{} True{}:
      EntryLeaf{entries}
    case Nil{} _ False{}:
      EntryLeaf{List.reverse(&2, WeightedEntry<A>, reversed)}
    case WeightedEntry{job, +estimated} <> tail _ False{}:
      +next = Nat.add(weight, estimated)
      split_entries(A, tail, target, total, grain, next, WeightedEntry{job, estimated} <> reversed, Nat.is_le(target, next))

def partition_entries(-A: Data, large: Bool, workload: EntryWorkload<A>, grain: Nat) -> EntryPartition<A>:
  match large workload:
    case False{} EntryWorkload{entries, weight}:
      EntryLeaf{entries}
    case True{} EntryWorkload{entries, +weight}:
      split_entries(A, entries, Nat.div(weight, 2n), weight, grain, 0n, Nil{}, False{})

def entry_partition(-A: Data, +workload: EntryWorkload<A>, +grain: Nat) -> EntryPartition<A>:
  EntryWorkload{entries, weight} = workload
  partition_entries(A, Nat.is_le(grain, Nat.div(weight, 2n)), workload, grain)

def entry_batches(-A: Data, +fuel: Nat, partition: EntryPartition<A>, +grain: Nat) -> EntryBatch<A>:
  match fuel partition:
    case _ EntryLeaf{entries}:
      SequentialEntries{entries}
    case 0n EntryFork{EntryWorkload{left, lw}, EntryWorkload{right, rw}}:
      SequentialEntries{List.reverse.go(&2, WeightedEntry<A>, List.reverse(&2, WeightedEntry<A>, left), right)}
    case 1n+rest EntryFork{left, right}:
      ParallelEntries{entry_batches(A, rest, entry_partition(A, left, grain), grain), entry_batches(A, rest, entry_partition(A, right, grain), grain)}

def plan_entries(jobs: List<&2, CodegenJob>, +grain: Nat) -> EntryBatch<CodegenJob>:
  entry_batches(CodegenJob, 64n, entry_partition(CodegenJob, weigh_entries(jobs, Nil{}, 0n), grain), grain)

def compile_entry_leaf(entries: List<&2, WeightedEntry<CodegenJob>>, reversed: List<&2, EntryCode>) -> Result<&2, &2, M.Diagnostic, List<&2, EntryCode>>:
  match entries:
    case Nil{}:
      Done{List.reverse(&2, EntryCode, reversed)}
    case WeightedEntry{job, weight} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, EntryCode>>:
        compiled : EntryCode <- compile_entry(job)
        compile_entry_leaf(tail, compiled <> reversed)

def compile_entry_batch(batch: EntryBatch<CodegenJob>) -> Result<&2, &2, M.Diagnostic, List<&2, EntryCode>>:
  match batch:
    case SequentialEntries{entries}:
      compile_entry_leaf(entries, Nil{})
    # Wider forks spread balanced subtrees across Bend's 16-lane CPU chunks.
    case ParallelEntries{ParallelEntries{ParallelEntries{a, b}, ParallelEntries{c, d}}, ParallelEntries{ParallelEntries{e, f}, ParallelEntries{g, h}}}:
      ra rb rc rd re rf rg rh = compile_entry_batch(a) compile_entry_batch(b) compile_entry_batch(c) compile_entry_batch(d) compile_entry_batch(e) compile_entry_batch(f) compile_entry_batch(g) compile_entry_batch(h)
      merge_entries(merge_entries(merge_entries(ra, rb), merge_entries(rc, rd)), merge_entries(merge_entries(re, rf), merge_entries(rg, rh)))
    case ParallelEntries{ParallelEntries{a, b}, ParallelEntries{c, d}}:
      ra rb rc rd = compile_entry_batch(a) compile_entry_batch(b) compile_entry_batch(c) compile_entry_batch(d)
      merge_entries(merge_entries(ra, rb), merge_entries(rc, rd))
    case ParallelEntries{left, right}:
      a b = compile_entry_batch(left) compile_entry_batch(right)
      merge_entries(a, b)

def compile_entries_with_grain(grain: Nat, jobs: List<&2, CodegenJob>) -> Result<&2, &2, M.Diagnostic, List<&2, EntryCode>>:
  compile_entry_batch(plan_entries(jobs, grain))

def compile_entries(jobs: List<&2, CodegenJob>) -> Result<&2, &2, M.Diagnostic, List<&2, EntryCode>>:
  compile_entries_with_grain(codegen_grain(), jobs)

def constructor_word(found: Maybe<&2, E.ConstructorSlot>) -> Maybe<&2, Nat>:
  match found:
    case None{}:
      None{}
    case Some{E.ConstructorSlot{name, tag, payload}}:
      Some{tag}

def resolve_fragment(fragment: Fragment, +symbols: Catalog, imports: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  match fragment:
    case Bytes{bytes}:
      Done{bytes}
    case NamedCall{key}:
      do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
        index : Nat <- lookup_symbol(symbol_entries(symbols), key)
        return 16 <> unsigned_leb(1n+Nat.add(imports, index))
    case Allocate{}:
      Done{16 <> unsigned_leb(imports)}
    case EntryIndex{key}:
      do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
        index : Nat <- lookup_symbol(symbol_entries(symbols), key)
        return i32_constant(U32.from_nat(index))
    case ConstantReference{name}:
      do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
        word : Nat <- lookup_symbol(symbol_constants(symbols), name)
        return i32_constant(U32.from_nat(word))
    case ConstructorIndex{+name}:
      do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
        tag : Nat <- required_symbol(constructor_word(E.constructor_get(symbol_constructors(symbols), name)), name)
        return i32_constant(U32.from_nat(tag))
    case OperationIndex{identity}:
      do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
        index : Nat <- lookup_symbol(symbol_operations(symbols), I.operation_key(identity))
        return i32_constant(U32.from_nat(index))

def relocation_chunk(result: Result<&2, &2, M.Diagnostic, List<&2, U32>>, accumulated: BytePlan) -> Result<&2, &2, M.Diagnostic, BytePlan>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{+bytes}:
      BytePlan{length, reversed} = accumulated
      Done{BytePlan{Nat.add(length, byte_length(bytes, 0n)), bytes <> reversed}}

# Accumulating chunks makes the number of relocations independent of the host
# stack. Lengths are measured after relocation; bytes are flattened only once.
def resolve_fragments(fragments: List<&2, Fragment>, +symbols: Catalog, +imports: Nat, accumulated: Result<&2, &2, M.Diagnostic, BytePlan>) -> Result<&2, &2, M.Diagnostic, BytePlan>:
  match fragments accumulated:
    case _ Fail{error}:
      Fail{error}
    case Nil{} Done{BytePlan{length, reversed}}:
      Done{BytePlan{length, List.reverse(&2, List<&2, U32>, reversed)}}
    case Bytes{Nil{}} <> tail Done{plan}:
      resolve_fragments(tail, symbols, imports, Done{plan})
    case head <> tail Done{plan}:
      resolve_fragments(tail, symbols, imports, relocation_chunk(resolve_fragment(head, symbols, imports), plan))

def matching_entry(same: Bool, key: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match same:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{M.Diagnostic{"backend_link", key, "cached codegen entry does not match the prepared job order"}}

def link_bodies(jobs: List<&2, CodegenJob>, entries: List<&2, EntryCode>, +symbols: Catalog, +imports: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, BytePlan>>:
  match jobs entries:
    case Nil{} Nil{}:
      Done{Nil{}}
    case CodegenJob{+key, parameter, body, captures} <> tail EntryCode{found, Code{fragments, locals}} <> rest:
      do Result<&2, &2, M.Diagnostic, List<&2, BytePlan>>:
        matched : Unit <- matching_entry(M.name_equal(key, found), key)
        instructions : BytePlan <- resolve_fragments(fragments, symbols, imports, Done{BytePlan{0n, Nil{}}})
        remaining : List<&2, BytePlan> <- link_bodies(tail, rest, symbols, imports)
        return body_plan(instructions, locals, 3n) <> remaining
    case _ _:
      Fail{M.Diagnostic{"backend_link", "codegen", "cached codegen entry count differs from the prepared jobs"}}

# The first defined function is (byte_count:i32) -> pointer:i32. Memory is bounded
# at 256 pages (16 MiB); every addition and memory.grow failure is checked.
def allocator() -> List<&2, U32>:
  body_bytes(join([
    [35, 0, 34, 1, 32, 0, 106, 34, 2, 32, 1, 73, 4, 64, 0, 11],
    [32, 2], i32_constant(16777216), [75, 4, 64, 0, 11],
    [32, 2], i32_constant(65535), [106], i32_constant(16), [118, 34, 3, 63, 0, 75, 4, 64],
    [32, 3, 63, 0, 107, 64, 0], i32_constant(4294967295), [70, 4, 64, 0, 11, 11],
    [32, 2, 36, 0, 32, 1]
  ]), 4n, 1n)

def scalar_tag(scalar: AbiScalar) -> U32:
  match scalar:
    case UnitScalar{}:
      0
    case U32Scalar{}:
      1
    case BoolScalar{}:
      2
    case F32Scalar{}:
      3

def scalar_name(scalar: AbiScalar) -> String:
  match scalar:
    case UnitScalar{}:
      "unit"
    case U32Scalar{}:
      "u32"
    case BoolScalar{}:
      "bool"
    case F32Scalar{}:
      "f32"

def scalar_wasm(scalar: AbiScalar) -> U32:
  match scalar:
    case F32Scalar{}:
      125
    case _:
      127

def abi_from_word(scalar: AbiScalar) -> List<&2, U32>:
  match scalar:
    case UnitScalar{}:
      [26, 65, 0]
    case BoolScalar{}:
      [69, 69]
    case F32Scalar{}:
      [190]
    case U32Scalar{}:
      Nil{}

def abi_to_word(scalar: AbiScalar) -> List<&2, U32>:
  match scalar:
    case UnitScalar{}:
      [26, 65, 0]
    case BoolScalar{}:
      [69, 69]
    case F32Scalar{}:
      [188]
    case U32Scalar{}:
      Nil{}

def callback_equal(left: Callback, right: Callback) -> Bool:
  Callback{lp, lr} = left
  Callback{rp, rr} = right
  Bool.and(U32.is_eq(scalar_tag(lp), scalar_tag(rp)), U32.is_eq(scalar_tag(lr), scalar_tag(rr)))

def callback_contains(callbacks: List<&2, Callback>, +wanted: Callback) -> Bool:
  match callbacks:
    case Nil{}:
      False{}
    case first <> tail:
      Bool.or(callback_equal(first, wanted), callback_contains(tail, wanted))

def callback_catalog(functions: List<&2, AbiFunction>, +reversed: List<&2, Callback>) -> List<&2, Callback>:
  match functions:
    case Nil{}:
      List.reverse(&2, Callback, reversed)
    case AbiFunction{name, ScalarParameter{scalar}, result} <> tail:
      callback_catalog(tail, reversed)
    case AbiFunction{name, CallbackParameter{+signature}, result} <> tail:
      +found = callback_contains(reversed, signature)
      callback_catalog(tail, Bool.pick(List<&2, Callback>, found, reversed, signature <> reversed))

def abi_functions(functions: List<&2, M.CheckedFunction>) -> Result<&2, &2, M.Diagnostic, List<&2, AbiFunction>>:
  match functions:
    case Nil{}:
      Done{Nil{}}
    case M.CheckedFunction{M.Function{name, False{}, parameter, param_ann, result_ann, body}, signature, effects} <> tail:
      abi_functions(tail)
    case M.CheckedFunction{M.Function{name, True{}, parameter, param_ann, result_ann, body}, signature, effects} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, AbiFunction>>:
        head : AbiFunction <- function_abi(signature)
        rest : List<&2, AbiFunction> <- abi_functions(tail)
        return head <> rest

def abi_constants(constants: List<&2, ExportedConstant>) -> Result<&2, &2, M.Diagnostic, List<&2, AbiConstant>>:
  match constants:
    case Nil{}:
      Done{Nil{}}
    case ExportedConstant{+name, ty} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, AbiConstant>>:
        scalar : AbiScalar <- abi_scalar(ty, name)
        rest : List<&2, AbiConstant> <- abi_constants(tail)
        return AbiConstant{name, scalar} <> rest

def module_abi(functions: List<&2, M.CheckedFunction>, constants: List<&2, ExportedConstant>) -> Result<&2, &2, M.Diagnostic, Abi>:
  do Result<&2, &2, M.Diagnostic, Abi>:
    +exports : List<&2, AbiFunction> <- abi_functions(functions)
    names : List<&2, AbiConstant> <- abi_constants(constants)
    return Abi{exports, names, callback_catalog(exports, Nil{})}

def abi_exports(abi: Abi) -> List<&2, AbiFunction>:
  Abi{functions, constants, callbacks} = abi
  functions

def abi_callbacks(abi: Abi) -> List<&2, Callback>:
  Abi{functions, constants, callbacks} = abi
  callbacks

def abi_parameter_bytes(parameter: AbiParameter) -> List<&2, U32>:
  match parameter:
    case ScalarParameter{scalar}:
      [scalar_tag(scalar)]
    case CallbackParameter{Callback{input, output}}:
      [4, scalar_tag(input), scalar_tag(output)]

def abi_function_bytes(functions: List<&2, AbiFunction>) -> List<&2, List<&2, U32>>:
  match functions:
    case Nil{}:
      Nil{}
    case AbiFunction{name, parameter, result} <> tail:
      join([sized(utf8(name)), abi_parameter_bytes(parameter), [scalar_tag(result)]]) <> abi_function_bytes(tail)

def abi_constant_bytes(constants: List<&2, AbiConstant>) -> List<&2, List<&2, U32>>:
  match constants:
    case Nil{}:
      Nil{}
    case AbiConstant{name, scalar} <> tail:
      concat(sized(utf8(name)), [scalar_tag(scalar)]) <> abi_constant_bytes(tail)

def abi_section(abi: Abi) -> BytePlan:
  Abi{functions, constants, callbacks} = abi
  byte_plan(section(0, join([sized(utf8("blot:abi")), [1], vector(abi_function_bytes(functions)), vector(abi_constant_bytes(constants))])))

def callback_slot(found: Bool, index: Nat, fallback: Unit -> Result<&2, &2, M.Diagnostic, Nat>) -> Result<&2, &2, M.Diagnostic, Nat>:
  match found:
    case True{}:
      Done{index}
    case False{}:
      fallback(Unit{})

def callback_index(callbacks: List<&2, Callback>, +wanted: Callback, +index: Nat) -> Result<&2, &2, M.Diagnostic, Nat>:
  match callbacks:
    case Nil{}:
      Fail{M.Diagnostic{"internal_error", "callback", "host wrapper lost its callback signature"}}
    case first <> tail:
      callback_slot(callback_equal(first, wanted), index, ignored => callback_index(tail, wanted, 1n+index))

def wrapper_type(function: AbiFunction) -> U32:
  match function:
    case AbiFunction{name, CallbackParameter{signature}, F32Scalar{}}:
      6
    case AbiFunction{name, CallbackParameter{signature}, result}:
      5
    case AbiFunction{name, ScalarParameter{F32Scalar{}}, F32Scalar{}}:
      4
    case AbiFunction{name, ScalarParameter{F32Scalar{}}, result}:
      2
    case AbiFunction{name, parameter, F32Scalar{}}:
      3
    case _:
      1

def wrapper_types(functions: List<&2, AbiFunction>) -> List<&2, U32>:
  match functions:
    case Nil{}:
      Nil{}
    case head <> tail:
      wrapper_type(head) <> wrapper_types(tail)

def wrapper_argument(parameter: AbiParameter, +callbacks: List<&2, Callback>, entries: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  match parameter:
    case ScalarParameter{scalar}:
      return_bytes = join([[65, 0, 32, 0], abi_to_word(scalar)])
      Done{concat(Bool.pick(List<&2, U32>, List.is_empty(&2, Callback, callbacks), Nil{}, [208, 111, 36, 1]), return_bytes)}
    case CallbackParameter{signature}:
      +imports = List.length(&2, Callback, callbacks)
      do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
        slot : Nat <- callback_index(callbacks, signature, entries)
        return join([[32, 0, 36, 1, 65, 0, 65, 4, 16], unsigned_leb(imports), [34, 1], i32_constant(U32.from_nat(slot)), [54, 2, 0, 32, 1]])

def wrapper_return(callbacks: List<&2, Callback>, result: AbiScalar) -> List<&2, U32>:
  match callbacks:
    case Nil{}:
      abi_from_word(result)
    case head <> tail:
      concat([33, 1, 208, 111, 36, 1, 32, 1], abi_from_word(result))

def wrapper_bodies(functions: List<&2, AbiFunction>, +slots: Map<&2, Maybe<&2, Nat>>, +heap_start: Nat, +callbacks: List<&2, Callback>, +entries: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, BytePlan>>:
  match functions:
    case Nil{}:
      Done{Nil{}}
    case AbiFunction{name, parameter, result} <> tail:
      +imports = List.length(&2, Callback, callbacks)
      do Result<&2, &2, M.Diagnostic, List<&2, BytePlan>>:
        index : Nat <- lookup_symbol(slots, "fn:" ++ name)
        argument : List<&2, U32> <- wrapper_argument(parameter, callbacks, entries)
        rest : List<&2, BytePlan> <- wrapper_bodies(tail, slots, heap_start, callbacks, entries)
        return byte_plan(body_bytes(join([i32_constant(U32.from_nat(heap_start)), [36, 0], argument, [65, 0, 16], unsigned_leb(1n+Nat.add(imports, index)), wrapper_return(callbacks, result)]), Bool.pick(Nat, Nat.is_eq(imports, 0n), 1n, 2n), 1n)) <> rest

def function_exports(functions: List<&2, AbiFunction>, index: Nat) -> List<&2, List<&2, U32>>:
  match functions:
    case Nil{}:
      Nil{}
    case AbiFunction{name, parameter, result} <> tail:
      +slot = index
      concat(sized(utf8(name)), 0 <> unsigned_leb(slot)) <> function_exports(tail, 1n+slot)

def global_exports(names: List<&2, ExportedConstant>, index: Nat) -> List<&2, List<&2, U32>>:
  match names:
    case Nil{}:
      Nil{}
    case ExportedConstant{name, value_type} <> tail:
      +slot = index
      concat(sized(utf8(name)), 3 <> unsigned_leb(slot)) <> global_exports(tail, 1n+slot)

def global_initializer(ty: M.Ty, word: U32) -> List<&2, U32>:
  match ty:
    case M.F32Ty{}:
      join([[125, 0, 67], word_bytes(word), [11]])
    case _:
      join([[127, 0], i32_constant(word), [11]])

def globals(names: List<&2, ExportedConstant>, +constants: Map<&2, Maybe<&2, Nat>>) -> Result<&2, &2, M.Diagnostic, List<&2, List<&2, U32>>>:
  match names:
    case Nil{}:
      Done{Nil{}}
    case ExportedConstant{name, value_type} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, List<&2, U32>>>:
        value : Nat <- lookup_symbol(constants, name)
        rest : List<&2, List<&2, U32>> <- globals(tail, constants)
        return global_initializer(value_type, U32.from_nat(value)) <> rest

def table_indices(count: Nat, start: Nat) -> List<&2, U32>:
  match count:
    case 0n:
      Nil{}
    case 1n+rest:
      +index = start
      concat(unsigned_leb(index), table_indices(rest, 1n+index))

def data_section(heap: Heap) -> BytePlan:
  Heap{heap_start, chunks} = heap
  plan_section(11, plan_prefix([1, 0, 65, 0, 11], plan_sized(BytePlan{heap_start, List.reverse(&2, List<&2, U32>, chunks)})))

def callback_types(callbacks: List<&2, Callback>) -> List<&2, List<&2, U32>>:
  match callbacks:
    case Nil{}:
      Nil{}
    case Callback{parameter, result} <> tail:
      [96, 2, 111, scalar_wasm(parameter), 1, scalar_wasm(result)] <> callback_types(tail)

def extra_types(callbacks: List<&2, Callback>) -> List<&2, List<&2, U32>>:
  match callbacks:
    case Nil{}:
      Nil{}
    case head <> tail:
      [96, 1, 111, 1, 127] <> [96, 1, 111, 1, 125] <> callback_types(head <> tail)

def type_section(callbacks: List<&2, Callback>) -> BytePlan:
  byte_plan(section(1, vector(List.append(&2, List<&2, U32>, [
    [96, 3, 127, 127, 127, 1, 127],
    [96, 1, 127, 1, 127],
    [96, 1, 125, 1, 127],
    [96, 1, 127, 1, 125],
    [96, 1, 125, 1, 125]
  ], extra_types(callbacks)))))

def callback_imports(callbacks: List<&2, Callback>, index: Nat) -> List<&2, List<&2, U32>>:
  match callbacks:
    case Nil{}:
      Nil{}
    case Callback{parameter, result} <> tail:
      +slot = index
      join([sized(utf8("blot:host/1")), sized(utf8("call_" ++ scalar_name(parameter) ++ "_" ++ scalar_name(result))), [0], unsigned_leb(7n+slot)]) <> callback_imports(tail, 1n+slot)

def import_section(callbacks: List<&2, Callback>) -> BytePlan:
  match callbacks:
    case Nil{}:
      byte_plan(Nil{})
    case head <> tail:
      byte_plan(section(2, vector(callback_imports(head <> tail, 0n))))

# Stubs read the current opaque capability, never an integer handle or captured
# provider frame. The adapter rejects reentry and expires the token on traps.
def callback_bodies(callbacks: List<&2, Callback>, index: Nat) -> List<&2, BytePlan>:
  match callbacks:
    case Nil{}:
      Nil{}
    case Callback{parameter, result} <> tail:
      +slot = index
      byte_plan(body_bytes(join([[35, 1, 32, 1], abi_from_word(parameter), [16], unsigned_leb(slot), abi_to_word(result)]), 3n, 3n)) <> callback_bodies(tail, 1n+slot)

def callback_globals(callbacks: List<&2, Callback>, values: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match callbacks:
    case Nil{}:
      values
    case head <> tail:
      [111, 1, 208, 111, 11] <> values

def assemble(+abi: Abi, +bodies: List<&2, BytePlan>, +wrappers: List<&2, BytePlan>, names: List<&2, ExportedConstant>, values: List<&2, List<&2, U32>>, heap: Heap) -> List<&2, U32>:
  Abi{+functions, constants, +callbacks} = abi
  Heap{+heap_start, chunks} = heap
  +count = List.length(&2, BytePlan, bodies)
  +imports = List.length(&2, Callback, callbacks)
  +wrapper_count = List.length(&2, BytePlan, wrappers)
  +pages = Nat.max(1n, U32.to_nat(U32.shrn(U32.add(U32.from_nat(heap_start), 65535), 16n)))
  plan_finish(plan_sequence([
    byte_plan([0, 97, 115, 109, 1, 0, 0, 0]),
    type_section(callbacks),
    import_section(callbacks),
    byte_plan(section(3, join([unsigned_leb(1n+Nat.add(count, wrapper_count)), [1], List.replicate(U32, count, 0), wrapper_types(functions)]))),
    byte_plan(section(4, join([[1, 112, 0], unsigned_leb(count)]))),
    byte_plan(section(5, join([[1, 1], unsigned_leb(pages), unsigned_leb(256n)]))),
    byte_plan(section(6, vector(join([[127, 1], i32_constant(U32.from_nat(heap_start)), [11]]) <> callback_globals(callbacks, values)))),
    byte_plan(section(7, vector(List.append(&2, List<&2, U32>, function_exports(functions, 1n+Nat.add(imports, count)), global_exports(names, Bool.pick(Nat, Nat.is_eq(imports, 0n), 1n, 2n)))))),
    byte_plan(section(9, join([[1, 0, 65, 0, 11], unsigned_leb(count), table_indices(count, 1n+imports)]))),
    plan_section(10, plan_vector(byte_plan(allocator()) <> List.append(&2, BytePlan, bodies, wrappers))),
    data_section(Heap{heap_start, chunks}),
    abi_section(abi)
  ]))

# Projection does not descend into nested lambda bodies: each has its own entry.
# Bound the estimate, not compilation, just as for instruction generation.
type PreparationWeightWork is Data:
  PreparationExpression{expression: M.Expr}
  PreparationExpressions{expressions: List<&2, M.Expr>}
  PreparationArms{arms: List<&2, M.MatchArm<M.Expr>>}

# F.children builds child lists through non-tail calls for match arms. Keeping
# this traversal explicit lets Bend compile the estimator into one flat loop.
def preparation_weight(fuel: Nat, pending: List<&2, PreparationWeightWork>, weight: Nat) -> Nat:
  match fuel pending:
    case _ Nil{}:
      weight
    case 0n _:
      weight
    case 1n+rest PreparationExpressions{Nil{}} <> tail:
      preparation_weight(rest, tail, weight)
    case 1n+rest PreparationExpressions{head <> following} <> tail:
      preparation_weight(rest, PreparationExpression{head} <> PreparationExpressions{following} <> tail, weight)
    case 1n+rest PreparationArms{Nil{}} <> tail:
      preparation_weight(rest, tail, weight)
    case 1n+rest PreparationArms{M.MatchArm{patterns, body} <> following} <> tail:
      preparation_weight(rest, PreparationExpression{body} <> PreparationArms{following} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.ConstructExpr{constructor, Some{payload}}} <> tail:
      preparation_weight(rest, PreparationExpression{payload} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.ApplyExpr{callee, argument}} <> tail:
      preparation_weight(rest, PreparationExpression{callee} <> PreparationExpression{argument} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.CallExpr{callee, argument}} <> tail:
      preparation_weight(rest, PreparationExpression{argument} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.ScalarExpr{operator, left, right}} <> tail:
      preparation_weight(rest, PreparationExpression{left} <> PreparationExpression{right} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.UnaryExpr{operator, value}} <> tail:
      preparation_weight(rest, PreparationExpression{value} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.LetExpr{name, value, body}} <> tail:
      preparation_weight(rest, PreparationExpression{value} <> PreparationExpression{body} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.UseExpr{name, value, body}} <> tail:
      preparation_weight(rest, PreparationExpression{value} <> PreparationExpression{body} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.IfExpr{condition, consequent, alternative}} <> tail:
      preparation_weight(rest, PreparationExpression{condition} <> PreparationExpression{consequent} <> PreparationExpression{alternative} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.SequenceExpr{first, next}} <> tail:
      preparation_weight(rest, PreparationExpression{first} <> PreparationExpression{next} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.MatchExpr{values, arms}} <> tail:
      preparation_weight(rest, PreparationExpressions{values} <> PreparationArms{arms} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.GuardExpr{pattern, value, alternative, body}} <> tail:
      preparation_weight(rest, PreparationExpression{value} <> PreparationExpression{alternative} <> PreparationExpression{body} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.BlockExpr{label, body}} <> tail:
      preparation_weight(rest, PreparationExpression{body} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.ReturnExpr{label, value}} <> tail:
      preparation_weight(rest, PreparationExpression{value} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.SourceExpr{offset, annotation, value}} <> tail:
      preparation_weight(rest, PreparationExpression{value} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.ProviderExpr{identity, implementation}} <> tail:
      preparation_weight(rest, PreparationExpression{implementation} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.HandleExpr{provider, body}} <> tail:
      preparation_weight(rest, PreparationExpression{provider} <> PreparationExpression{body} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.EffectHasExpr{set, operation}} <> tail:
      preparation_weight(rest, PreparationExpression{set} <> PreparationExpression{operation} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.EffectCountExpr{set}} <> tail:
      preparation_weight(rest, PreparationExpression{set} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.EffectSameExpr{left, right}} <> tail:
      preparation_weight(rest, PreparationExpression{left} <> PreparationExpression{right} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.ProductExpr{elements}} <> tail:
      preparation_weight(rest, PreparationExpressions{elements} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.ProjectExpr{value, index}} <> tail:
      preparation_weight(rest, PreparationExpression{value} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.ArrayExpr{elements}} <> tail:
      preparation_weight(rest, PreparationExpressions{elements} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.ArrayGetExpr{array, index}} <> tail:
      preparation_weight(rest, PreparationExpression{array} <> PreparationExpression{index} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.ArraySetExpr{array, index, value}} <> tail:
      preparation_weight(rest, PreparationExpression{array} <> PreparationExpression{index} <> PreparationExpression{value} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.ArrayLengthExpr{array}} <> tail:
      preparation_weight(rest, PreparationExpression{array} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{expression} <> tail:
      preparation_weight(rest, tail, 1n+weight)

def weigh_preparations(entries: List<&2, Entry>, reversed: List<&2, WeightedEntry<Entry>>, weight: Nat) -> EntryWorkload<Entry>:
  match entries:
    case Nil{}:
      EntryWorkload{List.reverse(&2, WeightedEntry<Entry>, reversed), weight}
    case Entry{key, parameter, +body, captures} <> tail:
      +estimated = preparation_weight(65536n, [PreparationExpression{body}], 8n)
      weigh_preparations(tail, WeightedEntry{Entry{key, parameter, body, captures}, estimated} <> reversed, Nat.add(weight, estimated))

def prepare_job_leaf(entries: List<&2, WeightedEntry<Entry>>, +projection: I.Metadata, reversed: List<&2, CodegenJob>) -> Result<&2, &2, M.Diagnostic, List<&2, CodegenJob>>:
  match entries:
    case Nil{}:
      Done{List.reverse(&2, CodegenJob, reversed)}
    case WeightedEntry{Entry{key, parameter, body, captures}, weight} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, CodegenJob>>:
        prepared : I.Expr <- I.prepare(body, projection)
        prepare_job_leaf(tail, projection, CodegenJob{key, parameter, prepared, captures} <> reversed)

def merge_prepared(left: Result<&2, &2, M.Diagnostic, List<&2, CodegenJob>>, right: Result<&2, &2, M.Diagnostic, List<&2, CodegenJob>>) -> Result<&2, &2, M.Diagnostic, List<&2, CodegenJob>>:
  match left right:
    case Fail{error} _:
      Fail{error}
    case Done{first} Fail{error}:
      Fail{error}
    case Done{first} Done{second}:
      Done{List.reverse.go(&2, CodegenJob, List.reverse(&2, CodegenJob, first), second)}

def prepare_job_batch(batch: EntryBatch<Entry>, +projection: I.Metadata) -> Result<&2, &2, M.Diagnostic, List<&2, CodegenJob>>:
  match batch:
    case SequentialEntries{entries}:
      prepare_job_leaf(entries, projection, Nil{})
    case ParallelEntries{ParallelEntries{ParallelEntries{a, b}, ParallelEntries{c, d}}, ParallelEntries{ParallelEntries{e, f}, ParallelEntries{g, h}}}:
      ra rb rc rd re rf rg rh = prepare_job_batch(a, projection) prepare_job_batch(b, projection) prepare_job_batch(c, projection) prepare_job_batch(d, projection) prepare_job_batch(e, projection) prepare_job_batch(f, projection) prepare_job_batch(g, projection) prepare_job_batch(h, projection)
      merge_prepared(merge_prepared(merge_prepared(ra, rb), merge_prepared(rc, rd)), merge_prepared(merge_prepared(re, rf), merge_prepared(rg, rh)))
    case ParallelEntries{ParallelEntries{a, b}, ParallelEntries{c, d}}:
      ra rb rc rd = prepare_job_batch(a, projection) prepare_job_batch(b, projection) prepare_job_batch(c, projection) prepare_job_batch(d, projection)
      merge_prepared(merge_prepared(ra, rb), merge_prepared(rc, rd))
    case ParallelEntries{left, right}:
      a b = prepare_job_batch(left, projection) prepare_job_batch(right, projection)
      merge_prepared(a, b)

def preparation_grain() -> Nat:
  512n

def plan_preparations(entries: List<&2, Entry>, +grain: Nat) -> EntryBatch<Entry>:
  entry_batches(Entry, 64n, entry_partition(Entry, weigh_preparations(entries, Nil{}, 0n), grain), grain)

def prepare_jobs_with_grain(grain: Nat, entries: List<&2, Entry>, projection: I.Metadata) -> Result<&2, &2, M.Diagnostic, List<&2, CodegenJob>>:
  prepare_job_batch(plan_preparations(entries, grain), projection)

def prepare_jobs(entries: List<&2, Entry>, projection: I.Metadata) -> Result<&2, &2, M.Diagnostic, List<&2, CodegenJob>>:
  prepare_jobs_with_grain(preparation_grain(), entries, projection)

def operation_jobs(operations: List<&2, M.Operation>) -> List<&2, CodegenJob>:
  match operations:
    case Nil{}:
      Nil{}
    case M.Operation{+identity, parameter, result} <> tail:
      CodegenJob{I.operation_key(identity), "$argument", I.InvokeOperationExpr{identity, I.LocalExpr{"$argument"}}, Nil{}} <> operation_jobs(tail)

def job_slots(jobs: List<&2, CodegenJob>, index: Nat) -> List<&2, Slot>:
  match jobs:
    case Nil{}:
      Nil{}
    case CodegenJob{key, parameter, body, captures} <> tail:
      +position = index
      Slot{key, position} <> job_slots(tail, 1n+position)

def prepare_catalog(runtime: Reachable.Runtime) -> Result<&2, &2, M.Diagnostic, Prepared>:
  Reachable.Runtime{M.CheckedModule{checked_constants, +functions, types, +operations}, constants, +lambdas} = runtime
  +declarations = E.type_catalog(types)
  entries = List.append(&2, Entry, function_entries(functions), List.append(&2, Entry, lambda_entries(lambdas), constructor_entries(E.catalog_variants(declarations))))
  +projection = I.metadata(lambdas, E.catalog_constructors(declarations))
  do Result<&2, &2, M.Diagnostic, Prepared>:
    supported : Unit <- check_functions(functions)
    names : List<&2, ExportedConstant> <- exported_constants(checked_constants)
    normal : List<&2, CodegenJob> <- prepare_jobs(entries, projection)
    +jobs : List<&2, CodegenJob> = List.append(&2, CodegenJob, normal, operation_jobs(operations))
    +slots : Map<&2, Maybe<&2, Nat>> = slot_index(job_slots(jobs, 0n))
    +operation_ids : Map<&2, Maybe<&2, Nat>> = slot_index(operation_slots(operations, 0n))
    +serialized : StaticConstants <- serialize_constants(constants, StaticCatalog{slots, projection, operation_ids}, Heap{4n, [[0, 0, 0, 0]]})
    return Prepared{jobs, Catalog{slots, E.catalog_constructors(declarations), slot_index(static_slots(serialized)), operation_ids}, functions, names, static_heap(serialized)}

def prepare(checked: M.CheckedModule, constants: List<&2, C.Binding<C.Value>>) -> Result<&2, &2, M.Diagnostic, Prepared>:
  do Result<&2, &2, M.Diagnostic, Prepared>:
    runtime : Reachable.Runtime <- Reachable.prepare(checked, constants)
    prepare_catalog(runtime)

def prepared_jobs(prepared: Prepared) -> List<&2, CodegenJob>:
  Prepared{jobs, catalog, functions, names, heap} = prepared
  jobs

def link(prepared: Prepared, entries: List<&2, EntryCode>) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  Prepared{jobs, +symbols, +functions, +names, +heap} = prepared
  do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
    +abi : Abi <- module_abi(functions, names)
    +callbacks : List<&2, Callback> = abi_callbacks(abi)
    +bodies : List<&2, BytePlan> <- link_bodies(jobs, entries, symbols, List.length(&2, Callback, callbacks))
    wrappers : List<&2, BytePlan> <- wrapper_bodies(abi_exports(abi), symbol_entries(symbols), heap_end(heap), callbacks, List.length(&2, BytePlan, bodies))
    values : List<&2, List<&2, U32>> <- globals(names, symbol_constants(symbols))
    return assemble(abi, List.append(&2, BytePlan, bodies, callback_bodies(callbacks, 0n)), wrappers, names, values, heap)

def emit(checked: M.CheckedModule, constants: List<&2, C.Binding<C.Value>>) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
    +prepared : Prepared <- prepare(checked, constants)
    entries : List<&2, EntryCode> <- compile_entries(prepared_jobs(prepared))
    link(prepared, entries)
