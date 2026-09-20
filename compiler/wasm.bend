import Base
import ./model.bend as M
import ./const_eval.bend as C
import ./closures.bend as F
import ./ecs_abi.bend as E
import ./codegen_ir.bend as I
import ./index.bend as Index

type Slot is Data:
  Slot{name: String, index: Nat}

type Linkage is Data:
  PureLink{}
  EcsLink{storage: List<&2, E.StorageBinding>}

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
    storage: E.NominalIndex<Nat>,
    linkage: Linkage
  }

type StaticCatalog is Data:
  StaticCatalog{entries: Map<&2, Maybe<&2, Nat>>, projection: I.Metadata}

type Context is Data:
  Context{locals: List<&2, Local>, next_local: Nat, labels: List<&2, Maybe<&2, Nat>>}

# Only the linker knows module-wide positions. Each relocation carries its
# encoding and opcode, so instruction bytes cannot conceal a stale index.
type Fragment is Data:
  Bytes{bytes: List<&2, U32>}
  NamedCall{key: String}
  Allocate{}
  EntryIndex{key: String}
  ConstantReference{name: String}
  ConstructorIndex{name: String}
  StorageIndex{identity: M.TypeId}
  StorageCall{access: M.Access}

type Code is Data:
  Code{fragments: List<&2, Fragment>, locals: Nat}

type EntryCode is Data:
  EntryCode{key: String, code: Code}

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

type Prepared is Data:
  Prepared{jobs: List<&2, CodegenJob>, catalog: Catalog, functions: List<&2, M.CheckedFunction>, names: List<&2, String>, heap: Heap}

type Emission is Data:
  ExpressionWork{expression: I.Expr}
  ArmsWork{arms: List<&2, M.MatchArm<I.Expr>>, subject: Location}

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

def entry_slots(entries: List<&2, Entry>, index: Nat) -> List<&2, Slot>:
  match entries:
    case Nil{}:
      Nil{}
    case Entry{key, parameter, body, captures} <> tail:
      +slot = index
      Slot{key, slot} <> entry_slots(tail, 1n+slot)

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
  StaticCatalog{entries, projection} = catalog
  entries

def static_projection(catalog: StaticCatalog) -> I.Metadata:
  StaticCatalog{entries, projection} = catalog
  projection

def import_count(linkage: Linkage) -> Nat:
  match linkage:
    case EcsLink{head <> tail}:
      3n
    case _:
      0n

def slot_index_go(slots: List<&2, Slot>, indexed: Map<&2, Maybe<&2, Nat>>) -> Map<&2, Maybe<&2, Nat>>:
  match slots:
    case Nil{}:
      indexed
    case Slot{name, position} <> tail:
      slot_index_go(tail, Map.set(&2, Maybe<&2, Nat>, indexed, name, Some{position}))

def slot_index(slots: List<&2, Slot>) -> Map<&2, Maybe<&2, Nat>>:
  slot_index_go(List.reverse(&2, Slot, slots), Map.new(&2, Maybe<&2, Nat>))

def storage_index_go(bindings: List<&2, E.StorageBinding>, indexed: E.NominalIndex<Nat>) -> E.NominalIndex<Nat>:
  match bindings:
    case Nil{}:
      indexed
    case E.StorageBinding{identity, storage, constructor, tag} <> tail:
      storage_index_go(tail, E.nominal_set(Nat, indexed, identity, tag))

def storage_symbols(linkage: Linkage) -> E.NominalIndex<Nat>:
  match linkage:
    case PureLink{}:
      E.nominal_new(Nat)
    case EcsLink{bindings}:
      storage_index_go(List.reverse(&2, E.StorageBinding, bindings), E.nominal_new(Nat))

def required_symbol(found: Maybe<&2, Nat>, name: String) -> Result<&2, &2, M.Diagnostic, Nat>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"backend_link", name, "Wasm relocation has no matching prepared symbol"}}
    case Some{position}:
      Done{position}

def lookup_symbol(indexed: Map<&2, Maybe<&2, Nat>>, +name: String) -> Result<&2, &2, M.Diagnostic, Nat>:
  required_symbol(Index.get(Maybe<&2, Nat>, indexed, name, None{}), name)

def symbol_entries(symbols: Catalog) -> Map<&2, Maybe<&2, Nat>>:
  Catalog{entries, constructors, constants, storage, linkage} = symbols
  entries

def symbol_constructors(symbols: Catalog) -> Map<&2, Maybe<&2, E.ConstructorSlot>>:
  Catalog{entries, constructors, constants, storage, linkage} = symbols
  constructors

def symbol_constants(symbols: Catalog) -> Map<&2, Maybe<&2, Nat>>:
  Catalog{entries, constructors, constants, storage, linkage} = symbols
  constants

def symbol_storage(symbols: Catalog) -> E.NominalIndex<Nat>:
  Catalog{entries, constructors, constants, storage, linkage} = symbols
  storage

def symbol_linkage(symbols: Catalog) -> Linkage:
  Catalog{entries, constructors, constants, storage, linkage} = symbols
  linkage

def context_locals(context: Context) -> List<&2, Local>:
  Context{locals, next_local, labels} = context
  locals

def context_next(context: Context) -> Nat:
  Context{locals, next_local, labels} = context
  next_local

def reserve(context: Context, count: Nat) -> Context:
  Context{locals, next_local, labels} = context
  Context{locals, Nat.add(next_local, count), labels}

def bind(context: Context, name: String, location: Location) -> Context:
  Context{locals, next_local, labels} = context
  Context{Local{name, location} <> locals, next_local, labels}

def control(context: Context, label: Maybe<&2, Nat>) -> Context:
  Context{locals, next_local, labels} = context
  Context{locals, next_local, label <> labels}

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
  Context{locals, next_local, labels} = context
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

def payload_location(location: Location) -> Location:
  Location{local, offsets} = location
  Location{local, List.append(&2, Nat, offsets, [4n])}

def pattern_bindings(pattern: M.Pattern, location: Location, context: Context) -> Context:
  match pattern:
    case M.BindingPattern{name}:
      bind(context, name, location)
    case M.ConstructorPattern{constructor, Some{payload}}:
      pattern_bindings(payload, payload_location(location), context)
    case _:
      context

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

def append_code(left: Code, right: Code, middle: List<&2, U32>, end: List<&2, U32>) -> Code:
  Code{lb, ll} = left
  Code{rb, rl} = right
  Code{fragments_join([lb, [Bytes{middle}], rb, [Bytes{end}]]), Nat.max(ll, rl)}

def require_locals(code: Code, count: Nat) -> Code:
  Code{bytes, locals} = code
  Code{bytes, Nat.max(locals, count)}

def scalar_code(left: Result<&2, &2, M.Diagnostic, Code>, right: Result<&2, &2, M.Diagnostic, Code>, operator: M.ScalarOp) -> Result<&2, &2, M.Diagnostic, Code>:
  match left right:
    case Fail{error} _:
      Fail{error}
    case Done{code} Fail{error}:
      Fail{error}
    case Done{a} Done{b}:
      Done{append_code(a, b, Nil{}, [opcode(operator)])}

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

def read_code(+identity: M.TypeId, context: Context) -> Code:
  construct_code(StorageIndex{identity}, Code{[StorageIndex{identity}, StorageCall{M.Read{}}], 0n}, context_next(context))

def effect_import(linkage: Linkage, access: M.Access) -> Result<&2, &2, M.Diagnostic, Nat>:
  match linkage access:
    case PureLink{} _:
      Fail{M.Diagnostic{"backend_effect", "ecs", "ECS effects require the explicit ECS compiler and storage runtime"}}
    case EcsLink{Nil{}} _:
      Fail{M.Diagnostic{"internal_error", "ecs", "checked ECS operation has no linked storage"}}
    case EcsLink{head <> tail} M.Read{}:
      Done{0n}
    case EcsLink{head <> tail} M.Write{}:
      Done{1n}
    case EcsLink{head <> tail} M.Insert{}:
      Done{2n}

def store_code(value: Code, +slot: Nat, access: M.Access) -> Code:
  Code{fragments, locals} = value
  Code{fragments_join([fragments, [Bytes{join([33 <> unsigned_leb(slot), 32 <> unsigned_leb(slot), [40, 2, 0], 32 <> unsigned_leb(slot), [40, 2, 4]])}, StorageCall{access}, Bytes{[26, 65, 0]}]]), Nat.max(locals, 1n+slot)}

def constructor_tag(variant: E.ConstructorSlot) -> Nat:
  E.ConstructorSlot{name, tag, payload} = variant
  tag

def lambda_captures(lambda: F.Lambda) -> List<&2, String>:
  F.Lambda{identity, parameter, body, captures} = lambda
  captures

def pattern_test(pattern: M.Pattern, +location: Location) -> Result<&2, &2, M.Diagnostic, List<&2, Fragment>>:
  match pattern:
    case M.WildcardPattern{}:
      Done{[Bytes{[65, 1]}]}
    case M.BindingPattern{name}:
      Done{[Bytes{[65, 1]}]}
    case M.UnitPattern{}:
      Done{[Bytes{[65, 1]}]}
    case M.U32Pattern{value}:
      Done{[Bytes{join([read_location(location), i32_constant(value), [70]])}]}
    case M.BoolPattern{value}:
      Done{[Bytes{join([read_location(location), [65, Bool.pick(U32, value, 1, 0), 70]])}]}
    case M.ConstructorPattern{constructor, None{}}:
      Done{[Bytes{concat(read_location(location), [40, 2, 0])}, ConstructorIndex{constructor}, Bytes{[70]}]}
    case M.ConstructorPattern{constructor, Some{payload}}:
      do Result<&2, &2, M.Diagnostic, List<&2, Fragment>>:
        nested : List<&2, Fragment> <- pattern_test(payload, payload_location(location))
        return fragments_join([[Bytes{concat(read_location(location), [40, 2, 0])}, ConstructorIndex{constructor}, Bytes{[70, 4, 127]}], nested, [Bytes{[5, 65, 0, 11]}]])

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
            return require_locals(append_code(function, value, join([33 <> unsigned_leb(slot), 32 <> unsigned_leb(slot)]), join([32 <> unsigned_leb(slot), [40, 2, 0, 17, 0, 0]])), 1n+slot)
        case ExpressionWork{I.CallExpr{key, argument}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            value : Code <- emit_expr(rest, ExpressionWork{argument}, context)
            return append_code(append_code(byte_code([65, 0], 0n), value, Nil{}, Nil{}), Code{[NamedCall{key}], 0n}, Nil{}, Nil{})
        case ExpressionWork{I.ScalarExpr{operator, left, right}}:
          a b = emit_expr(rest, ExpressionWork{left}, context) emit_expr(rest, ExpressionWork{right}, context)
          scalar_code(a, b, operator)
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
        case ExpressionWork{I.MatchExpr{value, arms}}:
          +slot = context_next(context)
          do Result<&2, &2, M.Diagnostic, Code>:
            v : Code <- emit_expr(rest, ExpressionWork{value}, reserve(context, 1n))
            b : Code <- emit_expr(rest, ArmsWork{arms, Location{slot, Nil{}}}, reserve(context, 1n))
            return require_locals(append_code(v, b, 33 <> unsigned_leb(slot), Nil{}), 1n+slot)
        case ExpressionWork{I.GuardExpr{+pattern, value, alternative, body}}:
          +slot = context_next(context)
          +nested = control(reserve(context, 1n), None{})
          do Result<&2, &2, M.Diagnostic, Code>:
            v : Code <- emit_expr(rest, ExpressionWork{value}, reserve(context, 1n))
            test : List<&2, Fragment> <- pattern_test(pattern, Location{slot, Nil{}})
            yes : Code <- emit_expr(rest, ExpressionWork{body}, pattern_bindings(pattern, Location{slot, Nil{}}, nested))
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
        case ExpressionWork{I.ReadExpr{identity}}:
          Done{read_code(identity, context)}
        case ExpressionWork{I.WriteExpr{value}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            compiled : Code <- emit_expr(rest, ExpressionWork{value}, reserve(context, 1n))
            return store_code(compiled, context_next(context), M.Write{})
        case ExpressionWork{I.InsertExpr{value}}:
          do Result<&2, &2, M.Diagnostic, Code>:
            compiled : Code <- emit_expr(rest, ExpressionWork{value}, reserve(context, 1n))
            return store_code(compiled, context_next(context), M.Insert{})
        case ArmsWork{Nil{}, subject}:
          Done{byte_code([0], 0n)}
        case ArmsWork{M.MatchArm{+pattern, body} <> tail, +subject}:
          +nested = control(context, None{})
          do Result<&2, &2, M.Diagnostic, Code>:
            test : List<&2, Fragment> <- pattern_test(pattern, subject)
            yes : Code <- emit_expr(rest, ExpressionWork{body}, pattern_bindings(pattern, subject, nested))
            no : Code <- emit_expr(rest, ArmsWork{tail, subject}, nested)
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

def scalar(ty: M.Ty) -> Bool:
  match ty:
    case M.UnitTy{}:
      True{}
    case M.U32Ty{}:
      True{}
    case M.BoolTy{}:
      True{}
    case _:
      False{}

def export_type(exported: Bool, supported: Bool, name: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match exported supported:
    case True{} False{}:
      Fail{M.Diagnostic{"backend_type", name, "Wasm exports require resolved Unit, U32, or Bool types; closures and algebraic values remain private to an exported call"}}
    case _ _:
      Done{Unit{}}

def pure_function(effects: List<&2, M.Effect>, name: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match effects:
    case Nil{}:
      Done{Unit{}}
    case head <> tail:
      Fail{M.Diagnostic{"backend_effect", name, "ECS effects require the explicit ECS compiler and storage runtime"}}

def ecs_export_signature(exported: Bool, signature: M.Signature) -> Result<&2, &2, M.Diagnostic, Unit>:
  match exported signature:
    case False{} _:
      Done{Unit{}}
    case True{} M.Signature{name, M.UnitTy{}, M.UnitTy{}, variables}:
      Done{Unit{}}
    case True{} M.Signature{name, parameter, result, variables}:
      Fail{M.Diagnostic{"backend_ecs_signature", name, "ECS system exports must have type Unit -> Unit; entity and world are selected by the runtime"}}

def check_signature(linkage: Linkage, exported: Bool, signature: M.Signature, effects: List<&2, M.Effect>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match linkage:
    case PureLink{}:
      M.Signature{+name, parameter, result, variables} = signature
      do Result<&2, &2, M.Diagnostic, Unit>:
        pure : Unit <- pure_function(effects, name)
        export_type(exported, Bool.and(scalar(parameter), scalar(result)), name)
    case EcsLink{storage}:
      ecs_export_signature(exported, signature)

def check_functions(functions: List<&2, M.CheckedFunction>, +linkage: Linkage) -> Result<&2, &2, M.Diagnostic, Unit>:
  match functions:
    case Nil{}:
      Done{Unit{}}
    case M.CheckedFunction{M.Function{name, exported, parameter, param_ann, result_ann, body}, signature, effects} <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        supported : Unit <- check_signature(linkage, exported, signature, effects)
        rest : Unit <- check_functions(tail, linkage)
        return rest

def exported_constants(constants: List<&2, M.CheckedConstant>) -> Result<&2, &2, M.Diagnostic, List<&2, String>>:
  match constants:
    case Nil{}:
      Done{Nil{}}
    case M.CheckedConstant{M.Constant{+name, +exported, annotation, value}, ty, variables} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, String>>:
        supported : Unit <- export_type(exported, scalar(ty), name)
        +rest : List<&2, String> <- exported_constants(tail)
        return Bool.pick(List<&2, String>, exported, name <> rest, rest)

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
    compiled : Code <- emit_expr(U32.to_nat(4096), ExpressionWork{body}, Context{Local{parameter, Location{1n, Nil{}}} <> capture_locals(captures, 4n), 2n, Nil{}})
    return EntryCode{key, compiled}

def merge_entries(left: Result<&2, &2, M.Diagnostic, List<&2, EntryCode>>, right: Result<&2, &2, M.Diagnostic, List<&2, EntryCode>>) -> Result<&2, &2, M.Diagnostic, List<&2, EntryCode>>:
  match left right:
    case Fail{error} _:
      Fail{error}
    case Done{first} Fail{error}:
      Fail{error}
    case Done{first} Done{second}:
      Done{List.append(&2, EntryCode, first, second)}

def compile_entries_tree(+fuel: Nat, jobs: List<&2, CodegenJob>) -> Result<&2, &2, M.Diagnostic, List<&2, EntryCode>>:
  match fuel jobs:
    case _ Nil{}:
      Done{Nil{}}
    case _ job <> Nil{}:
      do Result<&2, &2, M.Diagnostic, List<&2, EntryCode>>:
        compiled : EntryCode <- compile_entry(job)
        return [compiled]
    case 0n _:
      Fail{M.Diagnostic{"backend_limit", "codegen", "parallel codegen tree exceeded its structural depth limit"}}
    case 1n+rest first <> second <> tail:
      +remaining = {first <> second <> tail : List<&2, CodegenJob>}
      +middle = Nat.div(List.length(&2, CodegenJob, remaining), 2n)
      left right = compile_entries_tree(rest, List.take(&2, CodegenJob, remaining, middle)) compile_entries_tree(rest, List.drop(&2, CodegenJob, remaining, middle))
      merge_entries(left, right)

def compile_entries(jobs: List<&2, CodegenJob>) -> Result<&2, &2, M.Diagnostic, List<&2, EntryCode>>:
  compile_entries_tree(64n, jobs)

def storage_index(linkage: Linkage, indexed: E.NominalIndex<Nat>, +identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, Nat>:
  match linkage:
    case PureLink{}:
      Fail{M.Diagnostic{"backend_effect", M.type_id_show(identity), "ECS effects require the explicit ECS compiler and storage runtime"}}
    case EcsLink{storage}:
      required_symbol(E.nominal_get(Nat, indexed, identity), M.type_id_show(identity))

def constructor_word(found: Maybe<&2, E.ConstructorSlot>) -> Maybe<&2, Nat>:
  match found:
    case None{}:
      None{}
    case Some{E.ConstructorSlot{name, tag, payload}}:
      Some{tag}

def resolve_fragment(fragment: Fragment, +symbols: Catalog) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  match fragment:
    case Bytes{bytes}:
      Done{bytes}
    case NamedCall{key}:
      do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
        index : Nat <- lookup_symbol(symbol_entries(symbols), key)
        return 16 <> unsigned_leb(1n+Nat.add(index, import_count(symbol_linkage(symbols))))
    case Allocate{}:
      Done{16 <> unsigned_leb(import_count(symbol_linkage(symbols)))}
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
    case StorageIndex{identity}:
      do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
        tag : Nat <- storage_index(symbol_linkage(symbols), symbol_storage(symbols), identity)
        return i32_constant(U32.from_nat(tag))
    case StorageCall{access}:
      do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
        index : Nat <- effect_import(symbol_linkage(symbols), access)
        return 16 <> unsigned_leb(index)

def relocation_chunk(result: Result<&2, &2, M.Diagnostic, List<&2, U32>>, accumulated: BytePlan) -> Result<&2, &2, M.Diagnostic, BytePlan>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{+bytes}:
      BytePlan{length, reversed} = accumulated
      Done{BytePlan{Nat.add(length, byte_length(bytes, 0n)), bytes <> reversed}}

# Accumulating chunks makes the number of relocations independent of the host
# stack. Lengths are measured after relocation; bytes are flattened only once.
def resolve_fragments(fragments: List<&2, Fragment>, +symbols: Catalog, accumulated: Result<&2, &2, M.Diagnostic, BytePlan>) -> Result<&2, &2, M.Diagnostic, BytePlan>:
  match fragments accumulated:
    case _ Fail{error}:
      Fail{error}
    case Nil{} Done{BytePlan{length, reversed}}:
      Done{BytePlan{length, List.reverse(&2, List<&2, U32>, reversed)}}
    case Bytes{Nil{}} <> tail Done{plan}:
      resolve_fragments(tail, symbols, Done{plan})
    case head <> tail Done{plan}:
      resolve_fragments(tail, symbols, relocation_chunk(resolve_fragment(head, symbols), plan))

def matching_entry(same: Bool, key: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match same:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{M.Diagnostic{"backend_link", key, "cached codegen entry does not match the prepared job order"}}

def link_bodies(jobs: List<&2, CodegenJob>, entries: List<&2, EntryCode>, +symbols: Catalog) -> Result<&2, &2, M.Diagnostic, List<&2, BytePlan>>:
  match jobs entries:
    case Nil{} Nil{}:
      Done{Nil{}}
    case CodegenJob{+key, parameter, body, captures} <> tail EntryCode{found, Code{fragments, locals}} <> rest:
      do Result<&2, &2, M.Diagnostic, List<&2, BytePlan>>:
        matched : Unit <- matching_entry(M.name_equal(key, found), key)
        instructions : BytePlan <- resolve_fragments(fragments, symbols, Done{BytePlan{0n, Nil{}}})
        remaining : List<&2, BytePlan> <- link_bodies(tail, rest, symbols)
        return body_plan(instructions, locals, 2n) <> remaining
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

def scalar_argument(signature: M.Signature) -> List<&2, U32>:
  match signature:
    case M.Signature{name, M.UnitTy{}, result, variables}:
      [65, 0]
    case M.Signature{name, M.BoolTy{}, result, variables}:
      [32, 0, 69, 69]
    case _:
      [32, 0]

def wrapper_bodies(functions: List<&2, M.CheckedFunction>, +slots: Map<&2, Maybe<&2, Nat>>, +heap_start: Nat, +imports: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, BytePlan>>:
  match functions:
    case Nil{}:
      Done{Nil{}}
    case M.CheckedFunction{M.Function{name, False{}, parameter, param_ann, result_ann, body}, signature, effects} <> tail:
      wrapper_bodies(tail, slots, heap_start, imports)
    case M.CheckedFunction{M.Function{name, True{}, parameter, param_ann, result_ann, body}, signature, effects} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, BytePlan>>:
        index : Nat <- lookup_symbol(slots, "fn:" ++ name)
        rest : List<&2, BytePlan> <- wrapper_bodies(tail, slots, heap_start, imports)
        return byte_plan(body_bytes(join([i32_constant(U32.from_nat(heap_start)), [36, 0, 65, 0], scalar_argument(signature), [16], unsigned_leb(1n+Nat.add(index, imports))]), 1n, 1n)) <> rest

def function_exports(functions: List<&2, M.CheckedFunction>, index: Nat) -> List<&2, List<&2, U32>>:
  match functions:
    case Nil{}:
      Nil{}
    case M.CheckedFunction{M.Function{name, False{}, parameter, param_ann, result_ann, body}, signature, effects} <> tail:
      function_exports(tail, index)
    case M.CheckedFunction{M.Function{name, True{}, parameter, param_ann, result_ann, body}, signature, effects} <> tail:
      +slot = index
      concat(sized(utf8(name)), 0 <> unsigned_leb(slot)) <> function_exports(tail, 1n+slot)

def global_exports(names: List<&2, String>, index: Nat) -> List<&2, List<&2, U32>>:
  match names:
    case Nil{}:
      Nil{}
    case name <> tail:
      +slot = index
      concat(sized(utf8(name)), 3 <> unsigned_leb(slot)) <> global_exports(tail, 1n+slot)

def globals(names: List<&2, String>, +constants: Map<&2, Maybe<&2, Nat>>) -> Result<&2, &2, M.Diagnostic, List<&2, List<&2, U32>>>:
  match names:
    case Nil{}:
      Done{Nil{}}
    case name <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, List<&2, U32>>>:
        value : Nat <- lookup_symbol(constants, name)
        rest : List<&2, List<&2, U32>> <- globals(tail, constants)
        return join([[127, 0], i32_constant(U32.from_nat(value)), [11]]) <> rest

def table_indices(count: Nat, start: Nat) -> List<&2, U32>:
  match count:
    case 0n:
      Nil{}
    case 1n+rest:
      +index = start
      concat(unsigned_leb(index), table_indices(rest, 1n+index))

def storage_import(name: String, signature_index: Nat) -> List<&2, U32>:
  join([sized(utf8("blot:ecs")), sized(utf8(name)), [0], unsigned_leb(signature_index)])

def import_section(linkage: Linkage) -> List<&2, U32>:
  match linkage:
    case EcsLink{head <> tail}:
      section(2, vector([storage_import("read", 1n), storage_import("write", 0n), storage_import("insert", 0n)]))
    case _:
      Nil{}

def assemble(functions: List<&2, M.CheckedFunction>, +bodies: List<&2, BytePlan>, +wrappers: List<&2, BytePlan>, names: List<&2, String>, values: List<&2, List<&2, U32>>, heap: Heap, +linkage: Linkage) -> List<&2, U32>:
  Heap{+heap_start, chunks} = heap
  +count = List.length(&2, BytePlan, bodies)
  +wrapper_count = List.length(&2, BytePlan, wrappers)
  +pages = Nat.max(1n, U32.to_nat(U32.shrn(U32.add(U32.from_nat(heap_start), 65535), 16n)))
  +first_entry = Nat.add(1n, import_count(linkage))
  plan_finish(plan_sequence([
    byte_plan([0, 97, 115, 109, 1, 0, 0, 0]),
    byte_plan(section(1, [2, 96, 2, 127, 127, 1, 127, 96, 1, 127, 1, 127])),
    byte_plan(import_section(linkage)),
    byte_plan(section(3, join([unsigned_leb(1n+Nat.add(count, wrapper_count)), [1], List.replicate(U32, count, 0), List.replicate(U32, wrapper_count, 1)]))),
    byte_plan(section(4, join([[1, 112, 0], unsigned_leb(count)]))),
    byte_plan(section(5, join([[1, 1], unsigned_leb(pages), unsigned_leb(256n)]))),
    byte_plan(section(6, vector(join([[127, 1], i32_constant(U32.from_nat(heap_start)), [11]]) <> values))),
    byte_plan(section(7, vector(List.append(&2, List<&2, U32>, function_exports(functions, Nat.add(first_entry, count)), global_exports(names, 1n))))),
    byte_plan(section(9, join([[1, 0, 65, 0, 11], unsigned_leb(count), table_indices(count, first_entry)]))),
    plan_section(10, plan_vector(byte_plan(allocator()) <> List.append(&2, BytePlan, bodies, wrappers))),
    plan_section(11, plan_prefix([1, 0, 65, 0, 11], plan_sized(BytePlan{heap_start, List.reverse(&2, List<&2, U32>, chunks)})))
  ]))

def prepare_jobs(entries: List<&2, Entry>, +projection: I.Metadata) -> Result<&2, &2, M.Diagnostic, List<&2, CodegenJob>>:
  match entries:
    case Nil{}:
      Done{Nil{}}
    case Entry{key, parameter, body, captures} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, CodegenJob>>:
        prepared : I.Expr <- I.prepare(body, projection)
        rest : List<&2, CodegenJob> <- prepare_jobs(tail, projection)
        return CodegenJob{key, parameter, prepared, captures} <> rest

def prepare_catalog(checked: M.CheckedModule, constants: List<&2, C.Binding<C.Value>>, +linkage: Linkage, +declarations: E.TypeCatalog) -> Result<&2, &2, M.Diagnostic, Prepared>:
  M.CheckedModule{+checked_constants, +functions, types} = checked
  variants = E.catalog_variants(declarations)
  do Result<&2, &2, M.Diagnostic, Prepared>:
    supported : Unit <- check_functions(functions, linkage)
    +names : List<&2, String> <- exported_constants(checked_constants)
    +lambdas : List<&2, F.Lambda> <- F.collect(U32.to_nat(4096), List.append(&2, M.Expr, F.function_expressions(functions), F.constant_expressions(checked_constants)))
    +entries : List<&2, Entry> = List.append(&2, Entry, function_entries(functions), List.append(&2, Entry, lambda_entries(lambdas), constructor_entries(variants)))
    +slots : Map<&2, Maybe<&2, Nat>> = slot_index(entry_slots(entries, 0n))
    +projection : I.Metadata = I.metadata(lambdas, E.catalog_constructors(declarations))
    +serialized : StaticConstants <- serialize_constants(constants, StaticCatalog{slots, projection}, Heap{4n, [[0, 0, 0, 0]]})
    jobs : List<&2, CodegenJob> <- prepare_jobs(entries, projection)
    return Prepared{jobs, Catalog{slots, E.catalog_constructors(declarations), slot_index(static_slots(serialized)), storage_symbols(linkage), linkage}, functions, names, static_heap(serialized)}

def prepare(+checked: M.CheckedModule, constants: List<&2, C.Binding<C.Value>>, linkage: Linkage) -> Result<&2, &2, M.Diagnostic, Prepared>:
  M.CheckedModule{checked_constants, functions, types} = checked
  prepare_catalog(checked, constants, linkage, E.type_catalog(types))

def prepare_ecs(+checked: M.CheckedModule, constants: List<&2, C.Binding<C.Value>>) -> Result<&2, &2, M.Diagnostic, Prepared>:
  M.CheckedModule{checked_constants, functions, types} = checked
  +declarations = E.type_catalog(types)
  do Result<&2, &2, M.Diagnostic, Prepared>:
    storage : List<&2, E.StorageBinding> <- E.bindings_with_catalog(functions, declarations)
    prepare_catalog(checked, constants, EcsLink{storage}, declarations)

def prepared_jobs(prepared: Prepared) -> List<&2, CodegenJob>:
  Prepared{jobs, catalog, functions, names, heap} = prepared
  jobs

def linkage_storage(linkage: Linkage) -> List<&2, E.StorageBinding>:
  match linkage:
    case PureLink{}:
      Nil{}
    case EcsLink{storage}:
      storage

def prepared_storage(prepared: Prepared) -> List<&2, E.StorageBinding>:
  Prepared{jobs, catalog, functions, names, heap} = prepared
  linkage_storage(symbol_linkage(catalog))

def link(prepared: Prepared, entries: List<&2, EntryCode>) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  Prepared{jobs, +symbols, +functions, +names, +heap} = prepared
  do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
    bodies : List<&2, BytePlan> <- link_bodies(jobs, entries, symbols)
    wrappers : List<&2, BytePlan> <- wrapper_bodies(functions, symbol_entries(symbols), heap_end(heap), import_count(symbol_linkage(symbols)))
    values : List<&2, List<&2, U32>> <- globals(names, symbol_constants(symbols))
    return assemble(functions, bodies, wrappers, names, values, heap, symbol_linkage(symbols))

def emit_linked(checked: M.CheckedModule, constants: List<&2, C.Binding<C.Value>>, linkage: Linkage) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
    +prepared : Prepared <- prepare(checked, constants, linkage)
    entries : List<&2, EntryCode> <- compile_entries(prepared_jobs(prepared))
    link(prepared, entries)

def emit(checked: M.CheckedModule, constants: List<&2, C.Binding<C.Value>>) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  emit_linked(checked, constants, PureLink{})

def emit_ecs(checked: M.CheckedModule, constants: List<&2, C.Binding<C.Value>>) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
    +prepared : Prepared <- prepare_ecs(checked, constants)
    entries : List<&2, EntryCode> <- compile_entries(prepared_jobs(prepared))
    link(prepared, entries)
