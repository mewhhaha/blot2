import Base
import ./model.bend as M
import ./const_eval.bend as C
import ./closures.bend as F
import ./wasm_catalog.bend as E
import ./codegen_ir.bend as I
import ./array_reuse.bend as Reuse
import ./codegen_layout.bend as Layout
import ./index.bend as Index
import ./runtime_reachable.bend as Reachable
import ./runtime_initialization.bend as Init
import ./public_exports.bend as Public
import ./loop_memory.bend as LoopMemory
import ./arena_runtime.bend as Arena
import ./inference_batch.bend as B

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

type RuntimeGlobal is Data:
  RuntimeGlobal{index: Nat, value_type: M.Ty}

type Catalog is Data:
  Catalog{
    entries: Map<&2, Maybe<&2, Nat>>,
    constructors: Map<&2, Maybe<&2, E.ConstructorSlot>>,
    constants: Map<&2, Maybe<&2, Nat>>,
    operations: Map<&2, Maybe<&2, Nat>>,
    runtime: Map<&2, RuntimeGlobal>
  }

type StaticCatalog is Data:
  StaticCatalog{entries: Map<&2, Maybe<&2, Nat>>, projection: I.Metadata, operations: Map<&2, Maybe<&2, Nat>>}

type Context is Data:
  Context{locals: List<&2, Local>, next_local: Nat, labels: List<&2, Maybe<&2, Nat>>, provider: Nat, layouts: Map<&2, Layout.Shape>}

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
  Collect{}
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
  Heap{next: Nat, chunks: List<&2, List<&2, U32>>, memos: Map<&2, Maybe<&2, U32>>}

type Serialized is Data:
  Serialized{words: List<&2, U32>, heap: Heap}

type Serialization is Data:
  ValueWork{value: C.Value}
  MemoWork{found: Maybe<&2, U32>, slot: Nat, computed: Bool, value: C.Value}
  ValuesWork{values: List<&2, C.Value>}

type StaticConstants is Data:
  StaticConstants{slots: List<&2, Slot>, heap: Heap}

type ExportedConstant is Data:
  ExportedConstant{name: String, scalar: M.Ty}

type Prepared is Data:
  Prepared{jobs: List<&2, CodegenJob>, catalog: Catalog, functions: List<&2, M.CheckedFunction>, names: List<&2, ExportedConstant>, heap: Heap, initializers: List<&2, Init.Initializer>}

type Emission is Data:
  ExpressionWork{expression: I.Expr}
  ArmsWork{arms: List<&2, M.MatchArm<I.Expr>>, first: Nat, shapes: List<&2, Layout.Shape>}
  ScrutineesWork{values: List<&2, I.Expr>, first: Nat, reversed: List<&2, Fragment>, locals: Nat}

type AbiScalar is Data:
  UnitScalar{}
  U32Scalar{}
  BoolScalar{}
  F32Scalar{}

type AbiValue is Data:
  ScalarValue{scalar: AbiScalar}
  U32ArrayValue{}
  F32ArrayValue{}

type Callback is Data:
  Callback{parameter: AbiValue, result: AbiValue}

type AbiParameter is Data:
  ValueParameter{value: AbiValue}
  CallbackParameter{signature: Callback}

type AbiFunction is Data:
  AbiFunction{name: String, parameter: AbiParameter, result: AbiValue}

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

# Bool.pick evaluates both arguments; carry a hit into the next match so the
# remaining lexical scope is not scanned after finding the nearest binding.
def lookup_local_work(locals: List<&2, Local>, +name: String, found: Maybe<&2, Location>) -> Result<&2, &2, M.Diagnostic, Location>:
  match locals found:
    case _ Some{location}:
      Done{location}
    case Nil{} None{}:
      Fail{M.Diagnostic{"internal_error", name, "Wasm lowering lost a lexical local"}}
    case Local{declared, location} <> tail None{}:
      lookup_local_work(tail, name, Bool.pick(Maybe<&2, Location>, M.name_equal(declared, name), Some{location}, None{}))

def lookup_local(locals: List<&2, Local>, name: String) -> Result<&2, &2, M.Diagnostic, Location>:
  lookup_local_work(locals, name, None{})

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

def constructor_entries(constructors: List<&2, E.ConstructorSlot>, +used: Set()) -> List<&2, Entry>:
  match constructors:
    case Nil{}:
      Nil{}
    case E.ConstructorSlot{+name, tag, payload} <> tail:
      +rest = constructor_entries(tail, used)
      Bool.pick(List<&2, Entry>, Bool.and(payload, Maybe.is_some(&2, Unit, Index.find(Unit, used, name))), Entry{"constructor:" ++ name, "$payload", M.ConstructExpr{name, Some{M.LocalExpr{"$payload"}}}, Nil{}} <> rest, rest)

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
      slot_index_go(tail, Index.set(Maybe<&2, Nat>, indexed, name, Some{position}))

def slot_index(slots: List<&2, Slot>) -> Map<&2, Maybe<&2, Nat>>:
  slot_index_go(List.reverse(&2, Slot, slots), Map.new(&2, Maybe<&2, Nat>))

def operation_slots(operations: List<&2, M.Operation>, index: Nat) -> List<&2, Slot>:
  match operations:
    case Nil{}:
      Nil{}
    case M.Operation{identity, parameter, result} <> tail:
      +position = index
      Slot{I.operation_key(identity), position} <> operation_slots(tail, 1n+position)
    case head <> tail:
      operation_slots(tail, index)

def required_symbol(found: Maybe<&2, Nat>, name: String) -> Result<&2, &2, M.Diagnostic, Nat>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"backend_link", name, "Wasm relocation has no matching prepared symbol"}}
    case Some{position}:
      Done{position}

def lookup_symbol(indexed: Map<&2, Maybe<&2, Nat>>, +name: String) -> Result<&2, &2, M.Diagnostic, Nat>:
  required_symbol(Index.get(Maybe<&2, Nat>, indexed, name, None{}), name)

def symbol_entries(symbols: Catalog) -> Map<&2, Maybe<&2, Nat>>:
  Catalog{entries, constructors, constants, operations, runtime} = symbols
  entries

def symbol_constructors(symbols: Catalog) -> Map<&2, Maybe<&2, E.ConstructorSlot>>:
  Catalog{entries, constructors, constants, operations, runtime} = symbols
  constructors

def symbol_constants(symbols: Catalog) -> Map<&2, Maybe<&2, Nat>>:
  Catalog{entries, constructors, constants, operations, runtime} = symbols
  constants

def symbol_operations(symbols: Catalog) -> Map<&2, Maybe<&2, Nat>>:
  Catalog{entries, constructors, constants, operations, runtime} = symbols
  operations

def runtime_global(symbols: Catalog, name: String) -> Maybe<&2, RuntimeGlobal>:
  Catalog{entries, constructors, constants, operations, runtime} = symbols
  Index.find(RuntimeGlobal, runtime, name)

def global_index(index: Nat, imports: Nat) -> Nat:
  Nat.add(index, Bool.pick(Nat, Nat.is_eq(imports, 0n), 0n, 1n))

def runtime_from_word(ty: M.Ty) -> List<&2, U32>:
  match ty:
    case M.F32Ty{}:
      [190]
    case _:
      Nil{}

def runtime_to_word(ty: M.Ty) -> List<&2, U32>:
  match ty:
    case M.F32Ty{}:
      [188]
    case _:
      Nil{}

def constant_reference(found: Maybe<&2, RuntimeGlobal>, name: String, symbols: Catalog, imports: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  match found:
    case Some{RuntimeGlobal{index, ty}}:
      Done{concat(35 <> unsigned_leb(global_index(index, imports)), runtime_to_word(ty))}
    case None{}:
      do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
        word : Nat <- lookup_symbol(symbol_constants(symbols), name)
        return i32_constant(U32.from_nat(word))

def context_locals(context: Context) -> List<&2, Local>:
  Context{locals, next_local, labels, provider, layouts} = context
  locals

def context_next(context: Context) -> Nat:
  Context{locals, next_local, labels, provider, layouts} = context
  next_local

def reserve(context: Context, count: Nat) -> Context:
  Context{locals, next_local, labels, provider, layouts} = context
  Context{locals, Nat.add(next_local, count), labels, provider, layouts}

def bind(context: Context, +name: String, location: Location) -> Context:
  Context{locals, next_local, labels, provider, layouts} = context
  Context{Local{name, location} <> locals, next_local, labels, provider, Layout.bind(layouts, name, Layout.Unknown{})}

def context_layouts(context: Context) -> Map<&2, Layout.Shape>:
  Context{locals, next_local, labels, provider, layouts} = context
  layouts

def with_layouts(context: Context, layouts: Map<&2, Layout.Shape>) -> Context:
  Context{locals, next_local, labels, provider, previous} = context
  Context{locals, next_local, labels, provider, layouts}

def bind_known(context: Context, +name: String, location: Location, shape: Layout.Shape) -> Context:
  Context{locals, next_local, labels, provider, layouts} = context
  Context{Local{name, location} <> locals, next_local, labels, provider, Layout.bind(layouts, name, shape)}

def expression_shape(expression: I.Expr, context: Context) -> Layout.Shape:
  Layout.expression(32n, expression, context_layouts(context))

def scalar_word_in(expression: I.Expr, context: Context) -> Bool:
  Layout.scalar(expression_shape(expression, context))

# Sibling width must not consume the host stack. Short-circuiting this pure
# classification does not skip evaluation of any emitted array operand.
def scalar_words_in_go(elements: List<&2, I.Expr>, +context: Context, scalars: Bool) -> Bool:
  match elements scalars:
    case _ False{}:
      False{}
    case Nil{} True{}:
      True{}
    case head <> tail True{}:
      scalar_words_in_go(tail, context, scalar_word_in(head, context))

def scalar_words_in(elements: List<&2, I.Expr>, context: Context) -> Bool:
  scalar_words_in_go(elements, context, True{})

def control(context: Context, label: Maybe<&2, Nat>) -> Context:
  Context{locals, next_local, labels, provider, layouts} = context
  Context{locals, next_local, label <> labels, provider, layouts}

def with_provider(context: Context, provider: Nat) -> Context:
  Context{locals, next_local, labels, previous, layouts} = context
  Context{locals, next_local, labels, provider, layouts}

def context_provider(context: Context) -> Nat:
  Context{locals, next_local, labels, provider, layouts} = context
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
  Context{locals, next_local, labels, provider, layouts} = context
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
        +bound : Context <- pattern_bindings_work(rest, OnePattern{head, field_location(location, offset)}, context)
        pattern_bindings_work(rest, ProductFields{tail, location, 4n+offset}, bound)
    case 1n+rest RowPatterns{Nil{}, first}:
      Done{context}
    case 1n+rest RowPatterns{head <> tail, +first}:
      do Result<&2, &2, M.Diagnostic, Context>:
        +bound : Context <- pattern_bindings_work(rest, OnePattern{head, Location{first, Nil{}}}, context)
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
    case M.U32Divide{}:
      110
    case M.U32Remainder{}:
      112
    case M.U32BitAnd{}:
      113
    case M.U32BitOr{}:
      114
    case M.U32BitXor{}:
      115
    case M.U32ShiftLeft{}:
      116
    case M.U32ShiftRight{}:
      118

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

# Memo cells are ordinary traced arena blocks: state, callback, cached word.
def memo_code(computation: Code, +slot: Nat) -> Code:
  Code{fragments, locals} = computation
  +pointer = Nat.add(slot, 1n)
  Code{fragments_join([fragments, [Bytes{join([33 <> unsigned_leb(slot), i32_constant(12)])}, Allocate{}, Bytes{join([34 <> unsigned_leb(pointer), [65, 0, 54, 2, 0], local_get(pointer), local_get(slot), [54, 2, 4], local_get(pointer), [65, 0, 54, 2, 8], local_get(pointer)])}]]), Nat.max(locals, 2n+slot)}

def force_code(value: Code, +slot: Nat, provider: Nat) -> Code:
  +closure = Nat.add(slot, 1n)
  +result = Nat.add(slot, 2n)
  bytes = join([
    33 <> unsigned_leb(slot),
    # Forcing a memo below the startup floor may install persistent heap edges.
    local_get(slot), [65, 0, 40, 2, 0, 73, 4, 64, 65, 20, 65, 1, 54, 2, 0, 11],
    local_get(slot), [40, 2, 0, 65, 2, 70, 4, 127],
    local_get(slot), [40, 2, 8, 5],
    # Re-entering a running demand is a black hole, just as in const evaluation.
    local_get(slot), [40, 2, 0, 4, 64, 0, 11],
    local_get(slot), [65, 1, 54, 2, 0],
    local_get(slot), [40, 2, 4], 34 <> unsigned_leb(closure), [65, 0],
    local_get(provider), local_get(closure), [40, 2, 0, 17, 0, 0],
    33 <> unsigned_leb(result), local_get(slot), local_get(result), [54, 2, 8],
    local_get(slot), [65, 2, 54, 2, 0], local_get(slot), [65, 0, 54, 2, 4],
    local_get(result), [11]])
  require_locals(append_code(value, byte_code(bytes, 3n+slot), Nil{}, Nil{}), 3n+slot)

def element_stores(count: Nat, +pointer: Nat, first: Nat, offset: Nat, reversed: List<&2, List<&2, U32>>) -> List<&2, U32>:
  match count:
    case 0n:
      join(List.reverse(&2, List<&2, U32>, local_get(pointer) <> reversed))
    case 1n+rest:
      +slot = first
      +at = offset
      bytes = join([local_get(pointer), local_get(slot), [54, 2], unsigned_leb(at)])
      element_stores(rest, pointer, 1n+slot, 4n+at, bytes <> reversed)

# Only use this immediately after allocating a fresh dynamic object. Constants
# and host-provided pointers need not have this private arena header.
def scalar_array_header(leaf: Bool, pointer: Nat) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, leaf, join([local_get(pointer), [65, 8, 107, 65, 2, 54, 2, 0]]), Nil{})

# Tiny products often die before tracing; avoid an extra header store for
# less than eight words. Representation evidence still flows through them.
def product_code(elements: Code, +count: Nat, +first: Nat, leaf: Bool) -> Code:
  Code{fragments, locals} = elements
  +pointer = Nat.add(first, count)
  Code{fragments_join([fragments, [Bytes{i32_constant(U32.from_nat(Nat.mul(4n, count)))}, Allocate{}, Bytes{join([33 <> unsigned_leb(pointer), scalar_array_header(Bool.and(leaf, Nat.is_ge(count, 8n)), pointer), element_stores(count, pointer, first, 0n, Nil{})])}]]), Nat.max(locals, 1n+pointer)}

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

# This is a sufficient, not exhaustive, proof of a non-pointer result. Never
# guess from the bits of a Local, Constant, projection, call or array element.
# The checked array element type is homogeneous, so later valid updates cannot
# put a reference into an array created from one of these scalar expressions.
def scalar_word(expression: I.Expr) -> Bool:
  match expression:
    case I.UnitExpr{}:
      True{}
    case I.U32Expr{value}:
      True{}
    case I.F32Expr{value}:
      True{}
    case I.BoolExpr{value}:
      True{}
    case I.ScalarExpr{operator, left, right}:
      True{}
    case I.UnaryExpr{operator, value}:
      True{}
    case I.ArrayLengthExpr{array}:
      True{}
    case _:
      False{}

# Checking every element also keeps the low-level instruction API conservative:
# it does not need to assume that a hand-built ArrayExpr was type checked.
def scalar_words(elements: List<&2, I.Expr>) -> Bool:
  match elements:
    case Nil{}:
      True{}
    case head <> tail:
      Bool.and(scalar_word(head), scalar_words(tail))

def array_code(elements: Code, +count: Nat, size: U32, +first: Nat, leaf: Bool) -> Code:
  Code{fragments, locals} = elements
  +pointer = Nat.add(first, count)
  Code{fragments_join([fragments, [Bytes{i32_constant(size)}, Allocate{}, Bytes{join([
    34 <> unsigned_leb(pointer), i32_constant(U32.from_nat(count)), [54, 2, 0],
    scalar_array_header(leaf, pointer),
    element_stores(count, pointer, first, 4n, Nil{})
  ])}]]), Nat.max(locals, 1n+pointer)}

# The length header and payload byte count must fit one Wasm32 word before
# allocation checks the end pointer. Static bootstrap constants keep their own
# smaller compilation budget.
def runtime_array_max_count() -> U32:
  1073741822

def runtime_memory_max_pages() -> Nat:
  65536n

# Seed at most 32 words, then double the initialized prefix with memory.copy.
# memory.fill repeats bytes, not words; copying the seed preserves every U32,
# F32 and reference bit pattern. Each copy is bounded by the remaining count.
# Tiny fills retain a short store loop without the bulk-copy setup cost.
def array_fill_code(+first: Nat, leaf: Bool) -> Code:
  +value = {1n+first : Nat}
  +pointer = {2n+first : Nat}
  +index = {3n+first : Nat}
  +chunk = {4n+first : Nat}
  Code{[
    Bytes{join([
      local_get(first), i32_constant(runtime_array_max_count()), [75, 4, 64, 0, 11],
      local_get(first), [65, 1, 106, 65, 4, 108]
    ])},
    Allocate{},
    Bytes{join([
      34 <> unsigned_leb(pointer), local_get(first), [54, 2, 0],
      scalar_array_header(leaf, pointer),
      [65, 0], 33 <> unsigned_leb(index), [2, 64, 3, 64],
      local_get(index), local_get(first), [79, 13, 1],
      local_get(index), [65, 32, 79, 13, 1],
      local_get(pointer), local_get(index), [65, 4, 108, 106], local_get(value), [54, 2, 4],
      local_get(index), [65, 1, 106], 33 <> unsigned_leb(index), [12, 0, 11, 11],
      [2, 64, 3, 64],
      local_get(index), local_get(first), [79, 13, 1],
      local_get(first), local_get(index), [107], 33 <> unsigned_leb(chunk),
      local_get(chunk), local_get(index), [75, 4, 64],
      local_get(index), 33 <> unsigned_leb(chunk), [11],
      local_get(pointer), [65, 4, 106], local_get(index), [65, 4, 108, 106],
      local_get(pointer), [65, 4, 106], local_get(chunk), [65, 4, 108, 252, 10, 0, 0],
      local_get(index), local_get(chunk), [106], 33 <> unsigned_leb(index),
      [12, 0, 11, 11], local_get(pointer)
    ])}
  ], 5n+first}

# The destination is allocated once. Callback allocations share the arena but
# cannot change existing addresses or the immutable values they return.
def array_generate_code(+first: Nat, +provider: Nat) -> Code:
  +generator = {1n+first : Nat}
  +pointer = {2n+first : Nat}
  +index = {3n+first : Nat}
  Code{[
    Bytes{join([
      local_get(first), i32_constant(runtime_array_max_count()), [75, 4, 64, 0, 11],
      local_get(first), [65, 1, 106, 65, 4, 108]
    ])},
    Allocate{},
    Bytes{join([
      34 <> unsigned_leb(pointer), local_get(first), [54, 2, 0],
      [65, 0], 33 <> unsigned_leb(index), [2, 64, 3, 64],
      local_get(index), local_get(first), [79, 13, 1],
      local_get(pointer), local_get(index), [65, 4, 108, 106],
      local_get(generator), local_get(index), local_get(provider), local_get(generator), [40, 2, 0, 17, 0, 0, 54, 2, 4],
      local_get(index), [65, 1, 106], 33 <> unsigned_leb(index), [12, 0, 11, 11],
      local_get(pointer)
    ])}
  ], 4n+first}

def array_get_code(+first: Nat) -> Code:
  +index = {1n+first : Nat}
  byte_code(join([
    local_get(index), local_get(first), [40, 2, 0, 79, 4, 64, 0, 11],
    local_get(first), local_get(index), [65, 4, 108, 106, 40, 2, 4]
  ]), 2n+first)

# Bounds precede address arithmetic. The copied length is checked before the
# byte count is formed, independently of the allocator's end-address checks.
def array_set_code(+first: Nat, leaf: Bool) -> Code:
  +index = {1n+first : Nat}
  +value = {2n+first : Nat}
  +length = {3n+first : Nat}
  +pointer = {4n+first : Nat}
  Code{[
    Bytes{join([
      local_get(first), [40, 2, 0], 33 <> unsigned_leb(length),
      local_get(index), local_get(length), [79, 4, 64, 0, 11],
      local_get(length), i32_constant(runtime_array_max_count()), [75, 4, 64, 0, 11],
      local_get(length), [65, 1, 106, 65, 4, 108]
    ])},
    Allocate{},
    Bytes{join([
      33 <> unsigned_leb(pointer),
      scalar_array_header(leaf, pointer),
      local_get(pointer), local_get(first), local_get(length), [65, 1, 106, 65, 4, 108, 252, 10, 0, 0],
      local_get(pointer), local_get(index), [65, 4, 108, 106], local_get(value), [54, 2, 4],
      local_get(pointer)
    ])}
  ], 5n+first}

def array_reuse_code(+first: Nat) -> Code:
  +index = {1n+first : Nat}
  value = {2n+first : Nat}
  byte_code(join([
    local_get(index), local_get(first), [40, 2, 0, 79, 4, 64, 0, 11],
    local_get(first), local_get(index), [65, 4, 108, 106], local_get(value), [54, 2, 4],
    local_get(first)
  ]), 3n+first)

# Provider values contain no dynamic scope. Installing one creates a fresh frame;
# the lexical context selects that frame only for the handled body.
def state_provider_code(read: M.TypeId, write: M.TypeId, value: Code, +slot: Nat) -> Code:
  Code{fragments, locals} = value
  +pointer = {1n+slot : Nat}
  Code{fragments_join([fragments, [Bytes{join([33 <> unsigned_leb(slot), i32_constant(16)])}, Allocate{},
    Bytes{join([34 <> unsigned_leb(pointer), i32_constant(4294967295), [54, 2, 0], local_get(pointer)])},
    OperationIndex{read}, Bytes{join([[54, 2, 4], local_get(pointer)])},
    OperationIndex{write}, Bytes{join([[54, 2, 8], local_get(pointer), local_get(slot), [54, 2, 12], local_get(pointer)])}
  ]]), Nat.max(locals, 2n+slot)}

def install_provider(+slot: Nat, +outer: Nat) -> Code:
  +frame = {1n+slot : Nat}
  +cell = {2n+slot : Nat}
  Code{[
    Bytes{join([33 <> unsigned_leb(slot), local_get(slot), [40, 2, 0], i32_constant(4294967295), [70, 4, 64], i32_constant(36)])}, Allocate{},
    Bytes{join([
      34 <> unsigned_leb(frame), [65, 32, 106], 33 <> unsigned_leb(cell),
      local_get(cell), local_get(slot), [40, 2, 12, 54, 2, 0],
      local_get(frame), local_get(slot), [40, 2, 4, 54, 2, 0],
      local_get(frame), local_get(cell), [54, 2, 4],
      local_get(frame), local_get(frame), [65, 16, 106, 54, 2, 8],
      local_get(frame), [65, 1, 54, 2, 12],
      local_get(frame), local_get(slot), [40, 2, 8, 54, 2, 16],
      local_get(frame), local_get(cell), [54, 2, 20],
      local_get(frame), local_get(outer), [54, 2, 24],
      local_get(frame), [65, 2, 54, 2, 28, 5], i32_constant(16)
    ])}, Allocate{}, Bytes{join([
      34 <> unsigned_leb(frame), local_get(slot), [40, 2, 0, 54, 2, 0],
      local_get(frame), local_get(slot), [40, 2, 4, 54, 2, 4],
      local_get(frame), local_get(outer), [54, 2, 8],
      local_get(frame), [65, 0, 54, 2, 12, 11]
    ])}
  ], 3n+slot}

def complete_provider(+slot: Nat) -> Code:
  +frame = {1n+slot : Nat}
  +result = {2n+slot : Nat}
  +tuple = {3n+slot : Nat}
  Code{[
    Bytes{join([33 <> unsigned_leb(result), local_get(slot), [40, 2, 0], i32_constant(4294967295), [70, 4, 127], i32_constant(8)])}, Allocate{},
    Bytes{join([
      34 <> unsigned_leb(tuple), local_get(frame), [40, 2, 4, 40, 2, 0, 54, 2, 0],
      local_get(tuple), local_get(result), [54, 2, 4], local_get(tuple),
      [5], local_get(result), [11]
    ])}
  ], 4n+slot}

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
    local_get(slot), [40, 2, 12, 69, 4, 127],
    local_get(slot), [40, 2, 4], 34 <> unsigned_leb(handler),
    local_get(value), local_get(slot), [40, 2, 8], local_get(handler), [40, 2, 0, 17, 0, 0, 5],
    local_get(slot), [40, 2, 12, 65, 1, 70, 4, 127],
    local_get(slot), [40, 2, 4, 40, 2, 0, 5],
    local_get(slot), [40, 2, 4], local_get(value), [54, 2, 0, 65, 0, 11, 11]
  ])}]]), Nat.max(locals, 3n+slot)}

def constructor_tag(variant: E.ConstructorSlot) -> Nat:
  E.ConstructorSlot{name, tag, payload} = variant
  tag

def lambda_captures(lambda: F.Lambda) -> List<&2, String>:
  F.Lambda{identity, parameter, body, captures} = lambda
  captures

def pattern_test_work(+fuel: Nat, work: PatternTestWork, +locals: List<&2, Local>) -> Result<&2, &2, M.Diagnostic, List<&2, Fragment>>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"backend_limit", "pattern", "pattern tests exceeded their structural depth limit"}}
    case 1n+rest PatternTest{M.WildcardPattern{}, location}:
      Done{[Bytes{[65, 1]}]}
    case 1n+rest PatternTest{M.BindingPattern{name}, location}:
      Done{[Bytes{[65, 1]}]}
    case 1n+rest PatternTest{M.ValuePattern{M.LocalReference{name}}, location}:
      do Result<&2, &2, M.Diagnostic, List<&2, Fragment>>:
        expected : Location <- lookup_local(locals, name)
        return [Bytes{join([read_location(location), read_location(expected), [70]])}]
    case 1n+rest PatternTest{M.ValuePattern{M.ConstantReference{name}}, location}:
      Done{[Bytes{read_location(location)}, ConstantReference{name}, Bytes{[70]}]}
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
        nested : List<&2, Fragment> <- pattern_test_work(rest, PatternTest{payload, field_location(location, 4n)}, locals)
        return fragments_join([[Bytes{concat(read_location(location), [40, 2, 0])}, ConstructorIndex{constructor}, Bytes{[70, 4, 127]}], nested, [Bytes{[5, 65, 0, 11]}]])
    case 1n+rest PatternTest{M.ProductPattern{+elements}, location}:
      do Result<&2, &2, M.Diagnostic, List<&2, Fragment>>:
        valid : Unit <- product_arity(List.length(&2, M.Pattern, elements))
        pattern_test_work(rest, ProductTests{elements, location, 0n, [Bytes{[2, 127]}]}, locals)
    case 1n+rest ProductTests{Nil{}, location, offset, reversed}:
      Done{List.reverse.go(&2, Fragment, reversed, [Bytes{[65, 1, 11]}])}
    case 1n+rest ProductTests{head <> tail, +location, +offset, reversed}:
      do Result<&2, &2, M.Diagnostic, List<&2, Fragment>>:
        test : List<&2, Fragment> <- pattern_test_work(rest, PatternTest{head, field_location(location, offset)}, locals)
        # One shared result block keeps flat products flat in Wasm too. Each
        # failed field branches with 0; successful fields discard that value.
        pattern_test_work(rest, ProductTests{tail, location, 4n+offset, Bytes{[69, 13, 0, 26]} <> List.reverse.go(&2, Fragment, test, Bytes{[65, 0]} <> reversed)}, locals)
    case 1n+rest RowTests{Nil{}, first}:
      Done{[Bytes{[65, 1]}]}
    case 1n+rest RowTests{head <> tail, +first}:
      do Result<&2, &2, M.Diagnostic, List<&2, Fragment>>:
        test : List<&2, Fragment> <- pattern_test_work(rest, PatternTest{head, Location{first, Nil{}}}, locals)
        remaining : List<&2, Fragment> <- pattern_test_work(rest, RowTests{tail, 1n+first}, locals)
        return fragments_join([test, [Bytes{[4, 127]}], remaining, [Bytes{[5, 65, 0, 11]}]])

def next_scrutinee(values: List<&2, I.Expr>, +first: Nat, compiled: Code, reversed: List<&2, Fragment>, locals: Nat) -> Emission:
  Code{fragments, used} = compiled
  ScrutineesWork{values, 1n+first, Bytes{33 <> unsigned_leb(first)} <> List.reverse.go(&2, Fragment, fragments, reversed), Nat.max(Nat.max(locals, used), 1n+first)}

# Collection preserves addresses and graph sharing. The watermark pins all
# allocations that preceded the loop; the runtime traces their outgoing edges.
# A counter belongs to this loop activation. A global cadence can starve
# outer-loop collection when an inner loop repeatedly consumes its GC turn.
def forever_compaction(enabled: Bool, +state_slot: Nat, floor_slot: Nat, +scratch_slot: Nat) -> Code:
  Bool.pick(Code, enabled, Code{[
    Bytes{join([local_get(scratch_slot), [65, 1, 106], 34 <> unsigned_leb(scratch_slot), [65, 3, 113, 69, 4, 64], local_get(state_slot), local_get(floor_slot), [65, 0]])},
    Collect{},
    Bytes{join([33 <> unsigned_leb(state_slot), [11]])}
  ], 1n+scratch_slot}, byte_code(Nil{}, 0n))

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
            return product_code(values, count, first, scalar_words_in(elements, context))
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
            return array_code(values, count, size, first, scalar_words_in(elements, context))
        case ExpressionWork{I.ForExpr{index, start, end, state, initial, body}}:
          +first = context_next(context)
          +nested = control(control(bind(bind_known(reserve(context, 3n), index, Location{first, Nil{}}, Layout.Scalar{}), state, Location{2n+first, Nil{}}), None{}), None{})
          do Result<&2, &2, M.Diagnostic, Code>:
            operands : Code <- emit_expr(rest, ScrutineesWork{[start, end, initial], first, Nil{}, 0n}, reserve(context, 3n))
            iteration : Code <- emit_expr(rest, ExpressionWork{body}, nested)
            return require_locals(append_code(operands, iteration, join([[2, 64, 3, 64], local_get(first), local_get(1n+first), [79, 13, 1]]), join([33 <> unsigned_leb(2n+first), local_get(first), [65, 1, 106], 33 <> unsigned_leb(first), [12, 0, 11, 11], local_get(2n+first)])), 3n+first)
        case ExpressionWork{I.ForeverExpr{state, initial, body, compact}}:
          +first = context_next(context)
          +nested = control(control(bind(reserve(context, 3n), state, Location{first, Nil{}}), None{}), None{})
          do Result<&2, &2, M.Diagnostic, Code>:
            prepared : Code <- emit_expr(rest, ScrutineesWork{[initial], first, Nil{}, 0n}, reserve(context, 3n))
            iteration : Code <- emit_expr(rest, ExpressionWork{body}, nested)
            return require_locals(append_code(append_code(prepared, iteration, join([[35, 0], 33 <> unsigned_leb(1n+first), [65, 0], 33 <> unsigned_leb(2n+first), [2, 64, 3, 64]]), 33 <> unsigned_leb(first)), forever_compaction(compact, first, 1n+first, 2n+first), Nil{}, join([[12, 0, 11, 11], local_get(first)])), 3n+first)
        case ExpressionWork{I.ArrayGenerateExpr{count, generator}}:
          +first = context_next(context)
          do Result<&2, &2, M.Diagnostic, Code>:
            operands : Code <- emit_expr(rest, ScrutineesWork{[count, generator], first, Nil{}, 0n}, reserve(context, 4n))
            return append_code(operands, array_generate_code(first, context_provider(context)), Nil{}, Nil{})
        case ExpressionWork{I.ArrayFillExpr{count, +value}}:
          +first = context_next(context)
          do Result<&2, &2, M.Diagnostic, Code>:
            operands : Code <- emit_expr(rest, ScrutineesWork{[count, value], first, Nil{}, 0n}, reserve(context, 5n))
            return append_code(operands, array_fill_code(first, scalar_word_in(value, context)), Nil{}, Nil{})
        case ExpressionWork{I.ArrayGetExpr{array, index}}:
          +first = context_next(context)
          do Result<&2, &2, M.Diagnostic, Code>:
            operands : Code <- emit_expr(rest, ScrutineesWork{[array, index], first, Nil{}, 0n}, reserve(context, 2n))
            return append_code(operands, array_get_code(first), Nil{}, Nil{})
        case ExpressionWork{I.ArraySetExpr{array, index, +value}}:
          +first = context_next(context)
          do Result<&2, &2, M.Diagnostic, Code>:
            operands : Code <- emit_expr(rest, ScrutineesWork{[array, index, value], first, Nil{}, 0n}, reserve(context, 5n))
            return append_code(operands, array_set_code(first, scalar_word_in(value, context)), Nil{}, Nil{})
        case ExpressionWork{I.ArrayReuseExpr{array, index, value}}:
          +first = context_next(context)
          do Result<&2, &2, M.Diagnostic, Code>:
            operands : Code <- emit_expr(rest, ScrutineesWork{[array, index, value], first, Nil{}, 0n}, reserve(context, 3n))
            return append_code(operands, array_reuse_code(first), Nil{}, Nil{})
        case ExpressionWork{I.ArrayLengthExpr{array}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            value : Code <- emit_expr(rest, ExpressionWork{array}, context)
            return append_code(value, byte_code([40, 2, 0], 0n), Nil{}, Nil{})
        case ExpressionWork{I.StateProviderExpr{read, write, initial}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            value : Code <- emit_expr(rest, ExpressionWork{initial}, reserve(context, 2n))
            return state_provider_code(read, write, value, context_next(context))
        case ExpressionWork{I.ProviderExpr{identity, implementation}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            value : Code <- emit_expr(rest, ExpressionWork{implementation}, reserve(context, 2n))
            return construct_code(OperationIndex{identity}, value, context_next(context))
        case ExpressionWork{I.HandleExpr{provider, body}}:
          +slot = context_next(context)
          do Result<&2, &2, M.Diagnostic, Code>:
            value : Code <- emit_expr(rest, ExpressionWork{provider}, reserve(context, 4n))
            scoped : Code <- emit_expr(rest, ExpressionWork{body}, with_provider(reserve(context, 4n), 1n+slot))
            return append_code(append_code(append_code(value, install_provider(slot, context_provider(context)), Nil{}, Nil{}), scoped, Nil{}, Nil{}), complete_provider(slot), Nil{}, Nil{})
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
        case ExpressionWork{I.MemoExpr{computation}}:
          +slot = context_next(context)
          do Result<&2, &2, M.Diagnostic, Code>:
            value : Code <- emit_expr(rest, ExpressionWork{computation}, reserve(context, 2n))
            return memo_code(value, slot)
        case ExpressionWork{I.ForceExpr{value}}:
          +slot = context_next(context)
          do Result<&2, &2, M.Diagnostic, Code>:
            suspended : Code <- emit_expr(rest, ExpressionWork{value}, reserve(context, 3n))
            return force_code(suspended, slot, context_provider(context))
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
        case ExpressionWork{I.LetExpr{name, +value, body}}:
          +slot = context_next(context)
          do Result<&2, &2, M.Diagnostic, Code>:
            v : Code <- emit_expr(rest, ExpressionWork{value}, context)
            b : Code <- emit_expr(rest, ExpressionWork{body}, bind_known(reserve(context, 1n), name, Location{slot, Nil{}}, expression_shape(value, context)))
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
            b : Code <- emit_expr(rest, ArmsWork{arms, slot, Layout.expressions(32n, values, context_layouts(context))}, reserve(context, count))
            return require_locals(append_code(v, b, Nil{}, Nil{}), Nat.add(slot, count))
        case ExpressionWork{I.GuardExpr{+pattern, +value, alternative, body}}:
          +slot = context_next(context)
          +nested = control(reserve(context, 1n), None{})
          do Result<&2, &2, M.Diagnostic, Code>:
            v : Code <- emit_expr(rest, ExpressionWork{value}, reserve(context, 1n))
            test : List<&2, Fragment> <- pattern_test_work(rest, PatternTest{pattern, Location{slot, Nil{}}}, context_locals(context))
            +bound : Context <- pattern_bindings_work(rest, OnePattern{pattern, Location{slot, Nil{}}}, nested)
            yes : Code <- emit_expr(rest, ExpressionWork{body}, with_layouts(bound, Layout.pattern(32n, pattern, expression_shape(value, context), context_layouts(bound))))
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
        case ArmsWork{Nil{}, first, shapes}:
          Done{byte_code([0], 0n)}
        case ArmsWork{M.MatchArm{+patterns, body} <> tail, +first, +shapes}:
          +nested = control(context, None{})
          do Result<&2, &2, M.Diagnostic, Code>:
            test : List<&2, Fragment> <- pattern_test_work(rest, RowTests{patterns, first}, context_locals(context))
            +bound : Context <- pattern_bindings_work(rest, RowPatterns{patterns, first}, nested)
            yes : Code <- emit_expr(rest, ExpressionWork{body}, with_layouts(bound, Layout.patterns(32n, patterns, shapes, context_layouts(bound))))
            no : Code <- emit_expr(rest, ArmsWork{tail, first, shapes}, nested)
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
  Heap{+next, chunks, memos} = heap
  +end = Nat.add(next, Nat.mul(4n, List.length(&2, U32, words)))
  Bool.pick(Result<&2, &2, M.Diagnostic, Serialized>, Nat.is_le(end, U32.to_nat(16777216)), Done{Serialized{[U32.from_nat(next)], Heap{end, words_bytes(words) <> chunks, memos}}}, Fail{M.Diagnostic{"backend_limit", "constant", "static constants exceed the 16 MiB bootstrap arena"}})

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

def heap_memo(heap: Heap, slot: Nat) -> Maybe<&2, U32>:
  Heap{next, chunks, memos} = heap
  Index.get(Maybe<&2, U32>, memos, Nat.show(slot), None{})

def remember_memo(heap: Heap, slot: Nat, +word: U32) -> Heap:
  Heap{next, chunks, memos} = heap
  Heap{next, chunks, Map.set(&2, Maybe<&2, U32>, Map.set(&2, Maybe<&2, U32>, memos, Nat.show(slot), Some{word}), "head", Some{word})}

def memo_pointer(found: Maybe<&2, U32>) -> U32:
  match found:
    case None{}:
      0
    case Some{value}:
      value

def memo_head(memos: Map<&2, Maybe<&2, U32>>) -> U32:
  memo_pointer(Index.get(Maybe<&2, U32>, memos, "head", None{}))

def heap_memo_head(heap: Heap) -> U32:
  Heap{next, chunks, memos} = heap
  memo_head(memos)

def heap_end(heap: Heap) -> Nat:
  Heap{next, chunks, memos} = heap
  next

def serialize(+fuel: Nat, work: Serialization, +catalog: StaticCatalog, +heap: Heap) -> Result<&2, &2, M.Diagnostic, Serialized>:
  match fuel:
    case 0n:
      Fail{M.Diagnostic{"backend_limit", "constant", "constant serialization exceeded its structural depth limit"}}
    case 1n+rest:
      match work:
        case ValueWork{C.DemandValue{slot, computation}}:
          Fail{M.Diagnostic{"internal_error", "demand", "an unsnapshotted memo escaped constant evaluation"}}
        case ValueWork{C.MemoValue{+slot, computed, value}}:
          serialize(rest, MemoWork{heap_memo(heap, slot), slot, computed, value}, catalog, heap)
        case MemoWork{Some{word}, slot, computed, value}:
          Done{Serialized{[word], heap}}
        case MemoWork{None{}, +slot, +computed, value}:
          do Result<&2, &2, M.Diagnostic, Serialized>:
            +child : Serialized <- serialize(rest, ValueWork{value}, catalog, heap)
            +word : U32 <- only_word(serialized_words(child))
            +cell : Serialized <- heap_allocate([Bool.pick(U32, computed, 2, 0), Bool.pick(U32, computed, 0, word), Bool.pick(U32, computed, word, 0), heap_memo_head(serialized_heap(child))], serialized_heap(child))
            +pointer : U32 <- only_word(serialized_words(cell))
            return Serialized{[pointer], remember_memo(serialized_heap(cell), slot, pointer)}
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
        case ValueWork{C.StateProviderValue{read, write, initial}}:
          do Result<&2, &2, M.Diagnostic, Serialized>:
            reader : Nat <- lookup_slot(static_operations(catalog), I.operation_key(read))
            writer : Nat <- lookup_slot(static_operations(catalog), I.operation_key(write))
            +value : Serialized <- serialize(rest, ValueWork{initial}, catalog, heap)
            word : U32 <- only_word(serialized_words(value))
            heap_allocate([4294967295, U32.from_nat(reader), U32.from_nat(writer), word], serialized_heap(value))
        case ValueWork{C.StateReadValue{slot}}:
          Fail{M.Diagnostic{"internal_error", "state", "a state reader escaped its resolver"}}
        case ValueWork{C.StateWriteValue{slot}}:
          Fail{M.Diagnostic{"internal_error", "state", "a state writer escaped its resolver"}}
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
        case ValueWork{C.PatternBindingsValue{bindings}}:
          Fail{M.Diagnostic{"internal_error", "constant", "internal pattern bindings escaped constant evaluation"}}
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
      Fail{M.Diagnostic{"backend_type", name, "Wasm export constants require Unit, U32, F32, or Bool; function boundaries accept scalar or numeric-array values and callbacks with the closed Foreign effect"}}
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

def abi_value(ty: M.Ty, name: String) -> Result<&2, &2, M.Diagnostic, AbiValue>:
  match ty:
    case M.ArrayTy{M.U32Ty{}}:
      Done{U32ArrayValue{}}
    case M.ArrayTy{M.F32Ty{}}:
      Done{F32ArrayValue{}}
    case scalar:
      do Result<&2, &2, M.Diagnostic, AbiValue>:
        value : AbiScalar <- abi_scalar(scalar, name)
        return ScalarValue{value}

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
        input : AbiValue <- abi_value(parameter, name)
        output : AbiValue <- abi_value(result, name)
        return CallbackParameter{Callback{input, output}}
    case scalar:
      do Result<&2, &2, M.Diagnostic, AbiParameter>:
        value : AbiValue <- abi_value(scalar, name)
        return ValueParameter{value}

def function_abi(signature: M.Signature) -> Result<&2, &2, M.Diagnostic, AbiFunction>:
  M.Signature{+name, parameter, result, variables, effects} = signature
  do Result<&2, &2, M.Diagnostic, AbiFunction>:
    input : AbiParameter <- abi_parameter(parameter, name)
    output : AbiValue <- abi_value(result, name)
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
    compiled : Code <- emit_expr(U32.to_nat(16384), ExpressionWork{body}, Context{Local{parameter, Location{1n, Nil{}}} <> capture_locals(captures, 4n), 3n, Nil{}, 2n, Layout.empty()})
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
    case 1n+rest WeightExpression{I.StateProviderExpr{read, write, initial}} <> tail:
      codegen_weight_work(rest, WeightExpression{initial} <> tail, 1n+weight)
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
    case 1n+rest WeightExpression{I.ForExpr{index, start, end, state, initial, body}} <> tail:
      codegen_weight_work(rest, WeightExpressions{[start, end, initial, body]} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.ForeverExpr{state, initial, body, compact}} <> tail:
      codegen_weight_work(rest, WeightExpressions{[initial, body]} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.ArrayGenerateExpr{count, generator}} <> tail:
      codegen_weight_work(rest, WeightExpression{count} <> WeightExpression{generator} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.ArrayFillExpr{count, value}} <> tail:
      codegen_weight_work(rest, WeightExpression{count} <> WeightExpression{value} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.ArrayGetExpr{array, index}} <> tail:
      codegen_weight_work(rest, WeightExpression{array} <> WeightExpression{index} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.ArraySetExpr{array, index, value}} <> tail:
      codegen_weight_work(rest, WeightExpression{array} <> WeightExpression{index} <> WeightExpression{value} <> tail, 1n+weight)
    case 1n+rest WeightExpression{I.ArrayReuseExpr{array, index, value}} <> tail:
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
        return 16 <> unsigned_leb(3n+Nat.add(imports, index))
    case Allocate{}:
      Done{16 <> unsigned_leb(imports)}
    case Collect{}:
      Done{16 <> unsigned_leb(2n+imports)}
    case EntryIndex{key}:
      do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
        index : Nat <- lookup_symbol(symbol_entries(symbols), key)
        return i32_constant(U32.from_nat(index))
    case ConstantReference{+name}:
      constant_reference(runtime_global(symbols, name), name, symbols, imports)
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

type LinkTask is Data:
  LinkBody{key: String, entry: EntryCode}
  LinkCountMismatch{}

type LinkContext is Data:
  LinkContext{symbols: Catalog, imports: Nat}

def relocation_cost(fragments: List<&2, Fragment>, cost: Nat) -> Nat:
  match fragments:
    case Nil{}:
      cost
    case Bytes{bytes} <> tail:
      relocation_cost(tail, Nat.add(cost, 1n))
    case head <> tail:
      relocation_cost(tail, Nat.add(cost, 8n))

def link_tasks(jobs: List<&2, CodegenJob>, entries: List<&2, EntryCode>) -> List<&2, B.Weighted<LinkTask>>:
  match jobs entries:
    case Nil{} Nil{}:
      Nil{}
    case CodegenJob{key, parameter, body, captures} <> tail EntryCode{found, Code{+fragments, locals}} <> rest:
      B.Weighted{LinkBody{key, EntryCode{found, Code{fragments, locals}}}, relocation_cost(fragments, 8n)} <> link_tasks(tail, rest)
    case _ _:
      [B.Weighted{LinkCountMismatch{}, 1n}]

def link_body(task: LinkTask, context: LinkContext) -> Result<&2, &2, M.Diagnostic, BytePlan>:
  match task context:
    case LinkBody{+key, EntryCode{found, Code{fragments, locals}}} LinkContext{symbols, imports}:
      do Result<&2, &2, M.Diagnostic, BytePlan>:
        matched : Unit <- matching_entry(M.name_equal(key, found), key)
        instructions : BytePlan <- resolve_fragments(fragments, symbols, imports, Done{BytePlan{0n, Nil{}}})
        return body_plan(instructions, locals, 3n)
    case LinkCountMismatch{} _:
      Fail{M.Diagnostic{"backend_link", "codegen", "cached codegen entry count differs from the prepared jobs"}}

def collect_bodies(results: List<&2, Result<&2, &2, M.Diagnostic, BytePlan>>) -> Result<&2, &2, M.Diagnostic, List<&2, BytePlan>>:
  match results:
    case Nil{}:
      Done{Nil{}}
    case Fail{error} <> tail:
      Fail{error}
    case Done{body} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, BytePlan>>:
        rest : List<&2, BytePlan> <- collect_bodies(tail)
        return body <> rest

def link_bodies_with_grain(grain: Nat, jobs: List<&2, CodegenJob>, entries: List<&2, EntryCode>, symbols: Catalog, imports: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, BytePlan>>:
  collect_bodies(B.execute(~LinkTask, ~LinkContext, ~Result<&2, &2, M.Diagnostic, BytePlan>, ~link_body, B.plan(LinkTask, link_tasks(jobs, entries), grain), LinkContext{symbols, imports}))

def link_bodies(jobs: List<&2, CodegenJob>, entries: List<&2, EntryCode>, symbols: Catalog, imports: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, BytePlan>>:
  link_bodies_with_grain(256n, jobs, entries, symbols, imports)

# Three private runtime entries precede generated jobs: allocator, marker,
# and collector. Their internal calls are relocated by the callback import count.
def allocator() -> List<&2, U32>:
  sized(Arena.allocate(0n))

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

def value_tag(value: AbiValue) -> U32:
  match value:
    case ScalarValue{scalar}:
      scalar_tag(scalar)
    case U32ArrayValue{}:
      5
    case F32ArrayValue{}:
      6

def value_from_word(value: AbiValue) -> List<&2, U32>:
  match value:
    case ScalarValue{scalar}:
      abi_from_word(scalar)
    case _:
      Nil{}

def value_to_word(value: AbiValue) -> List<&2, U32>:
  match value:
    case ScalarValue{scalar}:
      abi_to_word(scalar)
    case _:
      Nil{}

def value_name(value: AbiValue) -> String:
  match value:
    case ScalarValue{scalar}:
      scalar_name(scalar)
    case U32ArrayValue{}:
      "array_u32"
    case F32ArrayValue{}:
      "array_f32"

def value_wasm(value: AbiValue) -> U32:
  match value:
    case ScalarValue{scalar}:
      scalar_wasm(scalar)
    case _:
      127

def callback_equal(left: Callback, right: Callback) -> Bool:
  Callback{lp, lr} = left
  Callback{rp, rr} = right
  Bool.and(U32.is_eq(value_tag(lp), value_tag(rp)), U32.is_eq(value_tag(lr), value_tag(rr)))

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
    case AbiFunction{name, ValueParameter{value}, result} <> tail:
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

def value_is_array(value: AbiValue) -> Bool:
  match value:
    case ScalarValue{scalar}:
      False{}
    case _:
      True{}

def array_parameter(parameter: AbiParameter) -> Bool:
  match parameter:
    case ValueParameter{value}:
      value_is_array(value)
    case CallbackParameter{signature}:
      False{}

def callback_arrays(parameter: AbiParameter) -> Bool:
  match parameter:
    case CallbackParameter{Callback{input, output}}:
      Bool.or(value_is_array(input), value_is_array(output))
    case _:
      False{}

def array_exports(functions: List<&2, AbiFunction>) -> Bool:
  match functions:
    case Nil{}:
      False{}
    case AbiFunction{name, +parameter, result} <> tail:
      Bool.or(Bool.or(Bool.or(array_parameter(parameter), callback_arrays(parameter)), value_is_array(result)), array_exports(tail))

# Array arguments are allocated by the host before entering the wrapper.
def arena_floor(initialized: Bool, heap_start: Nat) -> List<&2, U32>:
  match initialized:
    case False{}:
      i32_constant(U32.from_nat(heap_start))
    case True{}:
      [65, 0, 40, 2, 0]


# Reset invalidates free-list links into discarded allocations. Runtime
# initializers remain before the restored cursor and keep their block headers.
def clear_free_bins() -> List<&2, U32>:
  join([i32_constant(32), [65, 0], i32_constant(132), [252, 11, 0]])

# Ephemeral calls keep the cheap arena rewind. Once a persistent memo has been
# forced, collect instead so its cached graph survives subsequent guest calls.
def reset_arena(+heap_start: Nat, +initialized: Bool, imports: Nat) -> List<&2, U32>:
  join([[65, 20, 40, 2, 0, 4, 64, 65, 0], arena_floor(initialized, heap_start), [65, 0, 16], unsigned_leb(2n+imports), [26, 5], arena_floor(initialized, heap_start), [36, 0], clear_free_bins(), [11]])

def wrapper_reset(parameter: AbiParameter, heap_start: Nat, initialized: Bool, imports: Nat) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, array_parameter(parameter), Nil{}, reset_arena(heap_start, initialized, imports))

def abi_parameter_bytes(parameter: AbiParameter) -> List<&2, U32>:
  match parameter:
    case ValueParameter{value}:
      [value_tag(value)]
    case CallbackParameter{Callback{input, output}}:
      [4, value_tag(input), value_tag(output)]

def abi_function_bytes(functions: List<&2, AbiFunction>) -> List<&2, List<&2, U32>>:
  match functions:
    case Nil{}:
      Nil{}
    case AbiFunction{name, parameter, result} <> tail:
      join([sized(utf8(Public.export_name(name))), abi_parameter_bytes(parameter), [value_tag(result)]]) <> abi_function_bytes(tail)

def abi_constant_bytes(constants: List<&2, AbiConstant>) -> List<&2, List<&2, U32>>:
  match constants:
    case Nil{}:
      Nil{}
    case AbiConstant{name, scalar} <> tail:
      concat(sized(utf8(name)), [scalar_tag(scalar)]) <> abi_constant_bytes(tail)

def abi_section(abi: Abi) -> BytePlan:
  Abi{functions, constants, callbacks} = abi
  byte_plan(section(0, join([sized(utf8("blot:abi")), [2], vector(abi_function_bytes(functions)), vector(abi_constant_bytes(constants))])))

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
    case AbiFunction{name, CallbackParameter{signature}, ScalarValue{F32Scalar{}}}:
      6
    case AbiFunction{name, CallbackParameter{signature}, result}:
      5
    case AbiFunction{name, ValueParameter{ScalarValue{F32Scalar{}}}, ScalarValue{F32Scalar{}}}:
      4
    case AbiFunction{name, ValueParameter{ScalarValue{F32Scalar{}}}, result}:
      2
    case AbiFunction{name, parameter, ScalarValue{F32Scalar{}}}:
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
    case ValueParameter{value}:
      return_bytes = join([[65, 0, 32, 0], value_to_word(value)])
      Done{concat(Bool.pick(List<&2, U32>, List.is_empty(&2, Callback, callbacks), Nil{}, [208, 111, 36, 1]), return_bytes)}
    case CallbackParameter{signature}:
      +imports = List.length(&2, Callback, callbacks)
      do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
        slot : Nat <- callback_index(callbacks, signature, entries)
        return join([[32, 0, 36, 1, 65, 0, 65, 4, 16], unsigned_leb(imports), [34, 1], i32_constant(U32.from_nat(slot)), [54, 2, 0, 32, 1]])

def wrapper_return(callbacks: List<&2, Callback>, result: AbiValue) -> List<&2, U32>:
  match callbacks:
    case Nil{}:
      value_from_word(result)
    case head <> tail:
      concat([33, 1, 208, 111, 36, 1, 32, 1], value_from_word(result))

def wrapper_bodies(functions: List<&2, AbiFunction>, +slots: Map<&2, Maybe<&2, Nat>>, +heap_start: Nat, +callbacks: List<&2, Callback>, +entries: Nat, +initialized: Bool) -> Result<&2, &2, M.Diagnostic, List<&2, BytePlan>>:
  match functions:
    case Nil{}:
      Done{Nil{}}
    case AbiFunction{name, +parameter, result} <> tail:
      +imports = List.length(&2, Callback, callbacks)
      do Result<&2, &2, M.Diagnostic, List<&2, BytePlan>>:
        index : Nat <- lookup_symbol(slots, "fn:" ++ name)
        argument : List<&2, U32> <- wrapper_argument(parameter, callbacks, entries)
        rest : List<&2, BytePlan> <- wrapper_bodies(tail, slots, heap_start, callbacks, entries, initialized)
        return byte_plan(body_bytes(join([wrapper_reset(parameter, heap_start, initialized, imports), argument, [65, 0, 16], unsigned_leb(3n+Nat.add(imports, index)), wrapper_return(callbacks, result)]), Bool.pick(Nat, Nat.is_eq(imports, 0n), 1n, 2n), 1n)) <> rest

def function_exports(functions: List<&2, AbiFunction>, index: Nat) -> List<&2, List<&2, U32>>:
  match functions:
    case Nil{}:
      Nil{}
    case AbiFunction{name, parameter, result} <> tail:
      +slot = index
      concat(sized(utf8(Public.export_name(name))), 0 <> unsigned_leb(slot)) <> function_exports(tail, 1n+slot)

def global_exports(names: List<&2, ExportedConstant>, index: Nat) -> List<&2, List<&2, U32>>:
  match names:
    case Nil{}:
      Nil{}
    case ExportedConstant{name, value_type} <> tail:
      +slot = index
      concat(sized(utf8(name)), 3 <> unsigned_leb(slot)) <> global_exports(tail, 1n+slot)

def global_initializer(ty: M.Ty, word: U32, mutable: Bool) -> List<&2, U32>:
  match ty:
    case M.F32Ty{}:
      join([[125, Bool.pick(U32, mutable, 1, 0), 67], word_bytes(word), [11]])
    case _:
      join([[127, Bool.pick(U32, mutable, 1, 0)], i32_constant(word), [11]])

def exported_initializer(runtime: Maybe<&2, RuntimeGlobal>, name: String, ty: M.Ty, symbols: Catalog) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  match runtime:
    case Some{slot}:
      Done{global_initializer(ty, 0, True{})}
    case None{}:
      do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
        value : Nat <- lookup_symbol(symbol_constants(symbols), name)
        return global_initializer(ty, U32.from_nat(value), False{})

def globals(names: List<&2, ExportedConstant>, +symbols: Catalog) -> Result<&2, &2, M.Diagnostic, List<&2, List<&2, U32>>>:
  match names:
    case Nil{}:
      Done{Nil{}}
    case ExportedConstant{+name, value_type} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, List<&2, U32>>>:
        value : List<&2, U32> <- exported_initializer(runtime_global(symbols, name), name, value_type, symbols)
        rest : List<&2, List<&2, U32>> <- globals(tail, symbols)
        return value <> rest


def table_indices(count: Nat, start: Nat) -> List<&2, U32>:
  match count:
    case 0n:
      Nil{}
    case 1n+rest:
      +index = start
      concat(unsigned_leb(index), table_indices(rest, 1n+index))

def data_section(heap: Heap) -> BytePlan:
  Heap{+heap_start, chunks, memos} = heap
  plan_section(11, plan_vector([
    plan_prefix([0, 65, 0, 11], plan_sized(BytePlan{heap_start, List.reverse(&2, List<&2, U32>, chunks)})),
    byte_plan(join([[0, 65, 0, 11], sized(words_bytes([U32.from_nat(heap_start), 0, 0, 0, memo_head(memos), 0]))]))]))

def callback_types(callbacks: List<&2, Callback>) -> List<&2, List<&2, U32>>:
  match callbacks:
    case Nil{}:
      Nil{}
    case Callback{parameter, result} <> tail:
      [96, 2, 111, value_wasm(parameter), 1, value_wasm(result)] <> callback_types(tail)

def extra_types(callbacks: List<&2, Callback>) -> List<&2, List<&2, U32>>:
  match callbacks:
    case Nil{}:
      Nil{}
    case head <> tail:
      [96, 1, 111, 1, 127] <> [96, 1, 111, 1, 125] <> callback_types(head <> tail)

def type_section(callbacks: List<&2, Callback>, initialized: Bool) -> BytePlan:
  byte_plan(section(1, vector(List.append(&2, List<&2, U32>, [
    [96, 3, 127, 127, 127, 1, 127],
    [96, 1, 127, 1, 127],
    [96, 1, 125, 1, 127],
    [96, 1, 127, 1, 125],
    [96, 1, 125, 1, 125]
  ], List.append(&2, List<&2, U32>, extra_types(callbacks), Bool.pick(List<&2, List<&2, U32>>, initialized, [[96, 0, 0]], Nil{}))))))

def callback_imports(callbacks: List<&2, Callback>, index: Nat) -> List<&2, List<&2, U32>>:
  match callbacks:
    case Nil{}:
      Nil{}
    case Callback{parameter, result} <> tail:
      +slot = index
      join([sized(utf8("blot:host/1")), sized(utf8("call_" ++ value_name(parameter) ++ "_" ++ value_name(result))), [0], unsigned_leb(7n+slot)]) <> callback_imports(tail, 1n+slot)

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
      byte_plan(body_bytes(join([[35, 1, 32, 1], value_from_word(parameter), [16], unsigned_leb(slot), value_to_word(result)]), 3n, 3n)) <> callback_bodies(tail, 1n+slot)

def callback_globals(callbacks: List<&2, Callback>, values: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match callbacks:
    case Nil{}:
      values
    case head <> tail:
      [111, 1, 208, 111, 11] <> values

def arena_exports(enabled: Bool, allocator_index: Nat, reset_index: Nat) -> List<&2, List<&2, U32>>:
  match enabled:
    case False{}:
      Nil{}
    case True{}:
      [
        concat(sized(utf8("blot:memory")), [2, 0]),
        concat(sized(utf8("blot:allocate")), 0 <> unsigned_leb(allocator_index)),
        concat(sized(utf8("blot:reset")), 0 <> unsigned_leb(reset_index))
      ]


def arena_reset_body(enabled: Bool, heap_start: Nat, initialized: Bool, imports: Nat) -> List<&2, BytePlan>:
  match enabled:
    case False{}:
      Nil{}
    case True{}:
      [byte_plan(body_bytes(join([reset_arena(heap_start, initialized, imports), [35, 0]]), 1n, 1n))]

def assemble(+abi: Abi, +bodies: List<&2, BytePlan>, +wrappers: List<&2, BytePlan>, names: List<&2, ExportedConstant>, values: List<&2, List<&2, U32>>, heap: Heap, +startup: List<&2, BytePlan>) -> BytePlan:
  Abi{+functions, constants, +callbacks} = abi
  Heap{+heap_start, chunks, +memos} = heap
  +count = List.length(&2, BytePlan, bodies)
  +imports = List.length(&2, Callback, callbacks)
  +wrapper_count = List.length(&2, BytePlan, wrappers)
  +arrays = array_exports(functions)
  +reset_count = Bool.pick(Nat, arrays, 1n, 0n)
  +initialized = Bool.not(List.is_empty(&2, BytePlan, startup))
  +start_count = List.length(&2, BytePlan, startup)
  +start_type = Bool.pick(Nat, Nat.is_eq(imports, 0n), 5n, 7n+imports)
  +start_index = {3n+Nat.add(imports, Nat.add(count, Nat.add(wrapper_count, reset_count))) : Nat}
  +pages = Nat.max(1n, U32.to_nat(U32.shrn(U32.add(U32.from_nat(heap_start), 65535), 16n)))
  plan_sequence([
    byte_plan([0, 97, 115, 109, 1, 0, 0, 0]),
    type_section(callbacks, initialized),
    import_section(callbacks),
    byte_plan(section(3, join([unsigned_leb(3n+Nat.add(count, Nat.add(wrapper_count, Nat.add(reset_count, start_count)))), [1, 0, 0], List.replicate(U32, count, 0), wrapper_types(functions), List.replicate(U32, reset_count, 1), Bool.pick(List<&2, U32>, initialized, unsigned_leb(start_type), Nil{})]))),
    byte_plan(section(4, join([[1, 112, 0], unsigned_leb(count)]))),
    byte_plan(section(5, join([[1, 1], unsigned_leb(pages), unsigned_leb(runtime_memory_max_pages())]))),
    byte_plan(section(6, vector(join([[127, 1], i32_constant(U32.from_nat(heap_start)), [11]]) <> callback_globals(callbacks, values)))),
    byte_plan(section(7, vector(List.append(&2, List<&2, U32>, function_exports(functions, 3n+Nat.add(imports, count)), List.append(&2, List<&2, U32>, global_exports(names, Bool.pick(Nat, Nat.is_eq(imports, 0n), 1n, 2n)), arena_exports(arrays, imports, 3n+Nat.add(imports, Nat.add(count, wrapper_count)))))))),
    byte_plan(Bool.pick(List<&2, U32>, initialized, section(8, unsigned_leb(start_index)), Nil{})),
    byte_plan(section(9, join([[1, 0, 65, 0, 11], unsigned_leb(count), table_indices(count, 3n+imports)]))),
    plan_section(10, plan_vector(byte_plan(allocator()) <> byte_plan(sized(Arena.mark(imports))) <> byte_plan(sized(Arena.collect(imports))) <> List.append(&2, BytePlan, bodies, List.append(&2, BytePlan, wrappers, List.append(&2, BytePlan, arena_reset_body(arrays, heap_start, initialized, imports), startup))))),
    data_section(Heap{heap_start, chunks, memos}),
    abi_section(abi)
  ])

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
    case 1n+rest PreparationExpression{M.QualifiedExpr{offset, annotation, predicates, value}} <> tail:
      preparation_weight(rest, PreparationExpression{value} <> tail, weight)
    case 1n+rest PreparationExpression{M.InstantiationExpr{site, value}} <> tail:
      preparation_weight(rest, PreparationExpression{value} <> tail, weight)
    case 1n+rest PreparationExpression{M.TagExpr{offset, callee, argument}} <> tail:
      preparation_weight(rest, PreparationExpression{callee} <> PreparationExpression{argument} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.StateProviderExpr{read, write, initial}} <> tail:
      preparation_weight(rest, PreparationExpression{initial} <> tail, 1n+weight)
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
    case 1n+rest PreparationExpression{M.ForExpr{index, start, end, state, initial, body}} <> tail:
      preparation_weight(rest, PreparationExpressions{[start, end, initial, body]} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.ForeverExpr{state, initial, body}} <> tail:
      preparation_weight(rest, PreparationExpressions{[initial, body]} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.ArrayGenerateExpr{count, generator}} <> tail:
      preparation_weight(rest, PreparationExpression{count} <> PreparationExpression{generator} <> tail, 1n+weight)
    case 1n+rest PreparationExpression{M.ArrayFillExpr{count, value}} <> tail:
      preparation_weight(rest, PreparationExpression{count} <> PreparationExpression{value} <> tail, 1n+weight)
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
    case WeightedEntry{Entry{+key, parameter, body, captures}, weight} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, CodegenJob>>:
        projected : I.Expr <- I.prepare_scoped(body, projection, I.safe_loop_entry(projection, key))
        prepared : I.Expr <- Reuse.prepare(projected)
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
    case head <> tail:
      operation_jobs(tail)

def used_operations(operations: List<&2, M.Operation>, +used: Set()) -> List<&2, M.Operation>:
  match operations:
    case Nil{}:
      Nil{}
    case M.Operation{+identity, +parameter, +result} <> tail:
      +rest = used_operations(tail, used)
      Bool.pick(List<&2, M.Operation>, Maybe.is_some(&2, Unit, Index.find(Unit, used, I.operation_key(identity))), M.Operation{identity, parameter, result} <> rest, rest)
    case head <> tail:
      used_operations(tail, used)

def job_slots(jobs: List<&2, CodegenJob>, index: Nat) -> List<&2, Slot>:
  match jobs:
    case Nil{}:
      Nil{}
    case CodegenJob{key, parameter, body, captures} <> tail:
      +position = index
      Slot{key, position} <> job_slots(tail, 1n+position)

def initializer_entries(initializers: List<&2, Init.Initializer>) -> List<&2, Entry>:
  match initializers:
    case Nil{}:
      Nil{}
    case Init.Initializer{name, value} <> tail:
      Entry{"init:" ++ name, "$unit", value, Nil{}} <> initializer_entries(tail)

def exported_global(names: List<&2, ExportedConstant>, +wanted: String, index: Nat) -> Maybe<&2, RuntimeGlobal>:
  match names:
    case Nil{}:
      None{}
    case ExportedConstant{name, ty} <> tail:
      +slot = index
      Bool.pick(Maybe<&2, RuntimeGlobal>, M.name_equal(name, wanted), Some{RuntimeGlobal{slot, ty}}, exported_global(tail, wanted, 1n+slot))

def runtime_position(found: Maybe<&2, RuntimeGlobal>, fallback: Nat) -> RuntimeGlobal:
  match found:
    case Some{slot}:
      slot
    case None{}:
      RuntimeGlobal{fallback, M.U32Ty{}}

def runtime_global_index(global: RuntimeGlobal) -> Nat:
  RuntimeGlobal{index, ty} = global
  index

def runtime_globals(initializers: List<&2, Init.Initializer>, +names: List<&2, ExportedConstant>, +next: Nat, indexed: Map<&2, RuntimeGlobal>) -> Map<&2, RuntimeGlobal>:
  match initializers:
    case Nil{}:
      indexed
    case Init.Initializer{+name, value} <> tail:
      +global = runtime_position(exported_global(names, name, 1n), next)
      runtime_globals(tail, names, Nat.add(next, Bool.pick(Nat, Nat.is_eq(runtime_global_index(global), next), 1n, 0n)), Index.set(RuntimeGlobal, indexed, name, global))

def required_runtime(found: Maybe<&2, RuntimeGlobal>, name: String) -> Result<&2, &2, M.Diagnostic, RuntimeGlobal>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"backend_link", name, "runtime initializer has no prepared global"}}
    case Some{global}:
      Done{global}

def private_global(global: RuntimeGlobal, first: Nat, +rest: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  RuntimeGlobal{index, ty} = global
  Bool.pick(List<&2, List<&2, U32>>, Nat.is_ge(index, first), global_initializer(ty, 0, True{}) <> rest, rest)

def private_globals(initializers: List<&2, Init.Initializer>, +symbols: Catalog, +first: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, List<&2, U32>>>:
  match initializers:
    case Nil{}:
      Done{Nil{}}
    case Init.Initializer{+name, value} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, List<&2, U32>>>:
        global : RuntimeGlobal <- required_runtime(runtime_global(symbols, name), name)
        rest : List<&2, List<&2, U32>> <- private_globals(tail, symbols, first)
        return private_global(global, first, rest)

def initializer_call(global: RuntimeGlobal, entry: Nat, +imports: Nat) -> List<&2, U32>:
  RuntimeGlobal{index, ty} = global
  join([[65, 0, 65, 0, 65, 0, 16], unsigned_leb(3n+Nat.add(imports, entry)), runtime_from_word(ty), [36], unsigned_leb(global_index(index, imports))])

def initializer_calls(initializers: List<&2, Init.Initializer>, +symbols: Catalog, +imports: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, List<&2, U32>>>:
  match initializers:
    case Nil{}:
      Done{[[65, 0, 35, 0, 54, 2, 0]]}
    case Init.Initializer{+name, value} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, List<&2, U32>>>:
        global : RuntimeGlobal <- required_runtime(runtime_global(symbols, name), name)
        entry : Nat <- lookup_symbol(symbol_entries(symbols), "init:" ++ name)
        rest : List<&2, List<&2, U32>> <- initializer_calls(tail, symbols, imports)
        return initializer_call(global, entry, imports) <> rest

def initializer_body(initializers: List<&2, Init.Initializer>, symbols: Catalog, imports: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, BytePlan>>:
  match initializers:
    case Nil{}:
      Done{Nil{}}
    case initializers:
      do Result<&2, &2, M.Diagnostic, List<&2, BytePlan>>:
        calls : List<&2, List<&2, U32>> <- initializer_calls(initializers, symbols, imports)
        return [byte_plan(body_bytes(join(calls), 0n, 0n))]

def prepare_catalog(runtime: Reachable.Runtime, safe_loops: Set()) -> Result<&2, &2, M.Diagnostic, Prepared>:
  Reachable.Runtime{M.CheckedModule{+checked_constants, +functions, types, operations}, constants, +lambdas, +constructors, +used} = runtime
  +needed_operations = used_operations(operations, used)
  +declarations = E.type_catalog(types)
  entries = List.append(&2, Entry, function_entries(functions), List.append(&2, Entry, lambda_entries(lambdas), constructor_entries(E.catalog_variants(declarations), constructors)))
  +projection = I.with_safe_loops(I.with_functions(I.metadata(lambdas, E.catalog_constructors(declarations)), functions), safe_loops)
  do Result<&2, &2, M.Diagnostic, Prepared>:
    supported : Unit <- check_functions(functions)
    +names : List<&2, ExportedConstant> <- exported_constants(checked_constants)
    +initializers : List<&2, Init.Initializer> <- Init.plan(Init.bindings(checked_constants), checked_constants, functions)
    normal : List<&2, CodegenJob> <- prepare_jobs(List.append(&2, Entry, entries, initializer_entries(initializers)), projection)
    +jobs : List<&2, CodegenJob> = List.append(&2, CodegenJob, normal, operation_jobs(needed_operations))
    +slots : Map<&2, Maybe<&2, Nat>> = slot_index(job_slots(jobs, 0n))
    +operation_ids : Map<&2, Maybe<&2, Nat>> = slot_index(operation_slots(needed_operations, 0n))
    +serialized : StaticConstants <- serialize_constants(constants, StaticCatalog{slots, projection, operation_ids}, Heap{256n, [List.replicate(U32, 256n, 0)], Map.new(&2, Maybe<&2, U32>)})
    return Prepared{jobs, Catalog{slots, E.catalog_constructors(declarations), slot_index(static_slots(serialized)), operation_ids, runtime_globals(initializers, names, 1n+List.length(&2, ExportedConstant, names), MTip{})}, functions, names, static_heap(serialized), initializers}

def prepare(+checked: M.CheckedModule, constants: List<&2, C.Binding<C.Value>>) -> Result<&2, &2, M.Diagnostic, Prepared>:
  M.CheckedModule{checked_constants, functions, types, operations} = checked
  +safe_loops = LoopMemory.eligible(checked_constants, functions)
  do Result<&2, &2, M.Diagnostic, Prepared>:
    runtime : Reachable.Runtime <- Reachable.prepare(checked, constants)
    prepare_catalog(runtime, safe_loops)

def prepared_jobs(prepared: Prepared) -> List<&2, CodegenJob>:
  Prepared{jobs, catalog, functions, names, heap, initializers} = prepared
  jobs

def link_plan(prepared: Prepared, entries: List<&2, EntryCode>) -> Result<&2, &2, M.Diagnostic, BytePlan>:
  Prepared{jobs, +symbols, +functions, +names, +heap, +initializers} = prepared
  do Result<&2, &2, M.Diagnostic, BytePlan>:
    +abi : Abi <- module_abi(functions, names)
    +callbacks : List<&2, Callback> = abi_callbacks(abi)
    +bodies : List<&2, BytePlan> <- link_bodies(jobs, entries, symbols, List.length(&2, Callback, callbacks))
    wrappers : List<&2, BytePlan> <- wrapper_bodies(abi_exports(abi), symbol_entries(symbols), heap_end(heap), callbacks, List.length(&2, BytePlan, bodies), Bool.not(List.is_empty(&2, Init.Initializer, initializers)))
    values : List<&2, List<&2, U32>> <- globals(names, symbols)
    hidden : List<&2, List<&2, U32>> <- private_globals(initializers, symbols, 1n+List.length(&2, ExportedConstant, names))
    startup : List<&2, BytePlan> <- initializer_body(initializers, symbols, List.length(&2, Callback, callbacks))
    return assemble(abi, List.append(&2, BytePlan, bodies, callback_bodies(callbacks, 0n)), wrappers, names, List.append(&2, List<&2, U32>, values, hidden), heap, startup)

def link(prepared: Prepared, entries: List<&2, EntryCode>) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
    plan : BytePlan <- link_plan(prepared, entries)
    return plan_finish(plan)

def emit_plan(checked: M.CheckedModule, constants: List<&2, C.Binding<C.Value>>) -> Result<&2, &2, M.Diagnostic, BytePlan>:
  do Result<&2, &2, M.Diagnostic, BytePlan>:
    +prepared : Prepared <- prepare(checked, constants)
    entries : List<&2, EntryCode> <- compile_entries(prepared_jobs(prepared))
    link_plan(prepared, entries)

def emit(checked: M.CheckedModule, constants: List<&2, C.Binding<C.Value>>) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
    plan : BytePlan <- emit_plan(checked, constants)
    return plan_finish(plan)
