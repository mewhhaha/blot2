(* Native semantic port of compiler/wasm.bend.

   Source SHA-256: 5b41be50886f469f6d86eb2a5b413f190b3d0dc97a94cf4756e9c4c8905f9aa2

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module C = Ox_const_eval

module F = Ox_closures

module E = Ox_wasm_catalog

module I = Ox_codegen_ir

module Reuse = Ox_array_reuse

module Index = Ox_index

module Reachable = Ox_runtime_reachable

module Init = Ox_runtime_initialization

module Public = Ox_public_exports

module LoopMemory = Ox_loop_memory

module Arena = Ox_arena_runtime

module B = Ox_inference_batch

type t_Slot =
  | Slot of Base.text * int
and t_Entry =
  | Entry of Base.text * Base.text * M.t_Expr * (Base.text) list
and t_CodegenJob =
  | CodegenJob of Base.text * Base.text * I.t_Expr * (Base.text) list
and t_Location =
  | Location of int * (int) list
and t_Local =
  | Local of Base.text * t_Location
and t_RuntimeGlobal =
  | RuntimeGlobal of int * M.t_Ty
and t_Catalog =
  | Catalog of ((int) option) Base.map * ((E.t_ConstructorSlot) option) Base.map * ((int) option) Base.map * ((int) option) Base.map * (t_RuntimeGlobal) Base.map
and t_StaticCatalog =
  | StaticCatalog of ((int) option) Base.map * I.t_Metadata * ((int) option) Base.map
and t_Context =
  | Context of (t_Local) list * int * ((int) option) list * int
and t_PatternWork =
  | OnePattern of M.t_Pattern * t_Location
  | ProductFields of (M.t_Pattern) list * t_Location * int
  | RowPatterns of (M.t_Pattern) list * int
and t_Fragment =
  | Bytes of (Base.word32) list
  | NamedCall of Base.text
  | Allocate
  | Collect
  | EntryIndex of Base.text
  | ConstantReference of Base.text
  | ConstructorIndex of Base.text
  | OperationIndex of M.t_TypeId
and t_PatternTestWork =
  | PatternTest of M.t_Pattern * t_Location
  | ProductTests of (M.t_Pattern) list * t_Location * int * (t_Fragment) list
  | RowTests of (M.t_Pattern) list * int
and t_Code =
  | Code of (t_Fragment) list * int
and t_EntryCode =
  | EntryCode of Base.text * t_Code
and t_CodegenWeightWork =
  | WeightExpression of I.t_Expr
  | WeightExpressions of (I.t_Expr) list
  | WeightPattern of M.t_Pattern
  | WeightPatterns of (M.t_Pattern) list
  | WeightArms of ((I.t_Expr) M.t_MatchArm) list
  | WeightCaptures of (Base.text) list
and 'a t_WeightedEntry =
  | WeightedEntry of 'a * int
and 'a t_EntryWorkload =
  | EntryWorkload of (('a) t_WeightedEntry) list * int
and 'a t_EntryPartition =
  | EntryLeaf of (('a) t_WeightedEntry) list
  | EntryFork of ('a) t_EntryWorkload * ('a) t_EntryWorkload
and 'a t_EntryBatch =
  | SequentialEntries of (('a) t_WeightedEntry) list
  | ParallelEntries of ('a) t_EntryBatch * ('a) t_EntryBatch
and t_BytePlan =
  | BytePlan of int * ((Base.word32) list) list
and t_Heap =
  | Heap of int * ((Base.word32) list) list
and t_Serialized =
  | Serialized of (Base.word32) list * t_Heap
and t_Serialization =
  | ValueWork of C.t_Value
  | ValuesWork of (C.t_Value) list
and t_StaticConstants =
  | StaticConstants of (t_Slot) list * t_Heap
and t_ExportedConstant =
  | ExportedConstant of Base.text * M.t_Ty
and t_Prepared =
  | Prepared of (t_CodegenJob) list * t_Catalog * (M.t_CheckedFunction) list * (t_ExportedConstant) list * t_Heap * (Init.t_Initializer) list
and t_Emission =
  | ExpressionWork of I.t_Expr
  | ArmsWork of ((I.t_Expr) M.t_MatchArm) list * int
  | ScrutineesWork of (I.t_Expr) list * int * (t_Fragment) list * int
and t_AbiScalar =
  | UnitScalar
  | U32Scalar
  | BoolScalar
  | F32Scalar
and t_AbiValue =
  | ScalarValue of t_AbiScalar
  | U32ArrayValue
  | F32ArrayValue
and t_Callback =
  | Callback of t_AbiValue * t_AbiValue
and t_AbiParameter =
  | ValueParameter of t_AbiValue
  | CallbackParameter of t_Callback
and t_AbiFunction =
  | AbiFunction of Base.text * t_AbiParameter * t_AbiValue
and t_AbiConstant =
  | AbiConstant of Base.text * t_AbiScalar
and t_Abi =
  | Abi of (t_AbiFunction) list * (t_AbiConstant) list * (t_Callback) list
and t_LinkTask =
  | LinkBody of Base.text * t_EntryCode
  | LinkCountMismatch
and t_LinkContext =
  | LinkContext of t_Catalog * int
and t_PreparationWeightWork =
  | PreparationExpression of M.t_Expr
  | PreparationExpressions of (M.t_Expr) list
  | PreparationArms of ((M.t_Expr) M.t_MatchArm) list

let s_0 = Base.text_of_utf8 "internal_error"

let s_1 = Base.text_of_utf8 "Wasm lowering lost a checked name"

let s_2 = Base.text_of_utf8 "Wasm lowering lost a checked constructor"

let s_3 = Base.text_of_utf8 "Wasm lowering lost a checked lambda"

let s_4 = Base.text_of_utf8 "Wasm lowering lost a lexical local"

let s_5 = Base.text_of_utf8 "fn:"

let s_6 = Base.text_of_utf8 "lambda:"

let s_7 = Base.text_of_utf8 "constructor:"

let s_8 = Base.text_of_utf8 "$payload"

let s_9 = Base.text_of_utf8 "backend_link"

let s_10 = Base.text_of_utf8 "Wasm relocation has no matching prepared symbol"

let s_11 = Base.text_of_utf8 "Wasm return has no enclosing block"

let s_12 = Base.text_of_utf8 "backend_limit"

let s_13 = Base.text_of_utf8 "pattern"

let s_14 = Base.text_of_utf8 "pattern binding emission exceeded its structural depth limit"

let s_15 = Base.text_of_utf8 "product"

let s_16 = Base.text_of_utf8 "checked products require at least two elements"

let s_17 = Base.text_of_utf8 "projection"

let s_18 = Base.text_of_utf8 "product projection exceeds the private arena address range"

let s_19 = Base.text_of_utf8 "array"

let s_20 = Base.text_of_utf8 "array length exceeds the 16 MiB bootstrap arena"

let s_21 = Base.text_of_utf8 "pattern tests exceeded their structural depth limit"

let s_22 = Base.text_of_utf8 "expression"

let s_23 = Base.text_of_utf8 "Wasm lowering exceeded its structural depth limit"

let s_24 = Base.text_of_utf8 "constant"

let s_25 = Base.text_of_utf8 "static constants exceed the 16 MiB bootstrap arena"

let s_26 = Base.text_of_utf8 "Wasm serialization expected one machine word"

let s_27 = Base.text_of_utf8 "constant serialization exceeded its structural depth limit"

let s_28 = Base.text_of_utf8 "state"

let s_29 = Base.text_of_utf8 "a state reader escaped its resolver"

let s_30 = Base.text_of_utf8 "a state writer escaped its resolver"

let s_31 = Base.text_of_utf8 "an unhandled return escaped constant evaluation"

let s_32 = Base.text_of_utf8 "internal pattern bindings escaped constant evaluation"

let s_33 = Base.text_of_utf8 "a match scrutinee collection escaped constant evaluation"

let s_34 = Base.text_of_utf8 "backend_type"

let s_35 = Base.text_of_utf8 "Wasm export constants require Unit, U32, F32, or Bool; function boundaries accept scalar or numeric-array values and callbacks with the closed Foreign effect"

let s_36 = Base.text_of_utf8 "backend_effect"

let s_37 = Base.text_of_utf8 "Wasm exports must handle ordinary operations; only explicit callback Foreign effects may cross the host boundary"

let s_38 = Base.text_of_utf8 "an exported effect requires an explicit host callback parameter"

let s_39 = Base.text_of_utf8 "Wasm exports require a closed effect row"

let s_40 = Base.text_of_utf8 "the host ABI accepts only Unit, U32, Bool, and F32 scalar values"

let s_41 = Base.text_of_utf8 "host callback parameters require exactly the closed Foreign effect"

let s_42 = Base.text_of_utf8 "cached codegen entry does not match the prepared job order"

let s_43 = Base.text_of_utf8 "codegen"

let s_44 = Base.text_of_utf8 "cached codegen entry count differs from the prepared jobs"

let s_45 = Base.text_of_utf8 "unit"

let s_46 = Base.text_of_utf8 "u32"

let s_47 = Base.text_of_utf8 "bool"

let s_48 = Base.text_of_utf8 "f32"

let s_49 = Base.text_of_utf8 "array_u32"

let s_50 = Base.text_of_utf8 "array_f32"

let s_51 = Base.text_of_utf8 "blot:abi"

let s_52 = Base.text_of_utf8 "callback"

let s_53 = Base.text_of_utf8 "host wrapper lost its callback signature"

let s_54 = Base.text_of_utf8 "blot:host/1"

let s_55 = Base.text_of_utf8 "call_"

let s_56 = Base.text_of_utf8 "_"

let s_57 = Base.text_of_utf8 "blot:memory"

let s_58 = Base.text_of_utf8 "blot:allocate"

let s_59 = Base.text_of_utf8 "blot:reset"

let s_60 = Base.text_of_utf8 "$argument"

let s_61 = Base.text_of_utf8 "init:"

let s_62 = Base.text_of_utf8 "$unit"

let s_63 = Base.text_of_utf8 "runtime initializer has no prepared global"

let rec (* wasm.bend:155 *)
f_byte_length : (Base.word32) list -> int -> int =
fun v_bytes v_total ->
(match v_bytes with
| [] ->
v_total
| (v_head :: v_tail) ->
(f_byte_length (v_tail) ((Base.nat_add 1 v_total))))
and (* wasm.bend:162 *)
f_concat : (Base.word32) list -> (Base.word32) list -> (Base.word32) list =
fun v_left v_right ->
(Base.list_reverse_go ((Base.list_reverse (v_left))) (v_right))
and (* wasm.bend:165 *)
f_join_reversed : ((Base.word32) list) list -> (Base.word32) list -> (Base.word32) list =
fun v_chunks v_reversed ->
(match v_chunks with
| [] ->
(Base.list_reverse (v_reversed))
| (v_head :: v_tail) ->
(f_join_reversed (v_tail) ((Base.list_reverse_go (v_head) (v_reversed)))))
and (* wasm.bend:172 *)
f_join : ((Base.word32) list) list -> (Base.word32) list =
fun v_chunks ->
(f_join_reversed (v_chunks) ([]))
and (* wasm.bend:175 *)
f_byte_plan : (Base.word32) list -> t_BytePlan =
fun v_bytes ->
(BytePlan ((f_byte_length (v_bytes) (0)), [v_bytes]))
and (* wasm.bend:178 *)
f_plan_sequence_go : (t_BytePlan) list -> int -> ((Base.word32) list) list -> t_BytePlan =
fun v_plans v_total v_reversed ->
(match v_plans with
| [] ->
(BytePlan (v_total, (Base.list_reverse (v_reversed))))
| ((BytePlan (v_length, v_chunks)) :: v_tail) ->
(f_plan_sequence_go (v_tail) ((Base.nat_add (v_total) (v_length))) ((Base.list_reverse_go (v_chunks) (v_reversed)))))
and (* wasm.bend:185 *)
f_plan_sequence : (t_BytePlan) list -> t_BytePlan =
fun v_plans ->
(f_plan_sequence_go (v_plans) (0) ([]))
and (* wasm.bend:188 *)
f_plan_prefix : (Base.word32) list -> t_BytePlan -> t_BytePlan =
fun v_bytes v_plan ->
(let (BytePlan (v_length, v_chunks)) = v_plan in
(BytePlan ((Base.nat_add ((f_byte_length (v_bytes) (0))) (v_length)), (v_bytes :: v_chunks))))
and (* wasm.bend:192 *)
f_plan_finish : t_BytePlan -> (Base.word32) list =
fun v_plan ->
(let (BytePlan (v_length, v_chunks)) = v_plan in
(f_join (v_chunks)))
and (* wasm.bend:196 *)
f_fragments_reversed : ((t_Fragment) list) list -> (t_Fragment) list -> (t_Fragment) list =
fun v_chunks v_reversed ->
(match v_chunks with
| [] ->
(Base.list_reverse (v_reversed))
| (v_head :: v_tail) ->
(f_fragments_reversed (v_tail) ((Base.list_reverse_go (v_head) (v_reversed)))))
and (* wasm.bend:203 *)
f_fragments_join : ((t_Fragment) list) list -> (t_Fragment) list =
fun v_chunks ->
(f_fragments_reversed (v_chunks) ([]))
and (* wasm.bend:206 *)
f_byte_code : (Base.word32) list -> int -> t_Code =
fun v_bytes v_locals ->
(Code ([(Bytes (v_bytes))], v_locals))
and (* wasm.bend:209 *)
f_unsigned_leb_go : int -> Base.word32 -> (Base.word32) list =
fun v_fuel v_value ->
(match v_fuel with
| 0 ->
[]
| __nat_1 when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(Base.bool_pick ((Base.u32_is_lt (v_value) ((Base.W32 0x80)))) ([v_value]) (((Base.u32_or ((Base.u32_and (v_value) ((Base.W32 0x7f)))) ((Base.W32 0x80))) :: (f_unsigned_leb_go (v_rest) ((Base.u32_shrn (v_value) (7)))))))))
and (* wasm.bend:216 *)
f_unsigned_leb : int -> (Base.word32) list =
fun v_value ->
(f_unsigned_leb_go (5) ((Base.u32_from_nat (v_value))))
and (* wasm.bend:219 *)
f_plan_sized : t_BytePlan -> t_BytePlan =
fun v_plan ->
(let (BytePlan (v_length, v_chunks)) = v_plan in
(f_plan_prefix ((f_unsigned_leb (v_length))) ((BytePlan (v_length, v_chunks)))))
and (* wasm.bend:223 *)
f_plan_section : Base.word32 -> t_BytePlan -> t_BytePlan =
fun v_id v_plan ->
(f_plan_prefix ([v_id]) ((f_plan_sized (v_plan))))
and (* wasm.bend:226 *)
f_plan_vector : (t_BytePlan) list -> t_BytePlan =
fun v_plans ->
(f_plan_prefix ((f_unsigned_leb ((Base.list_length (v_plans))))) ((f_plan_sequence (v_plans))))
and (* wasm.bend:231 *)
f_i32_constant : Base.word32 -> (Base.word32) list =
fun v_value ->
[(Base.W32 0x41); (Base.u32_or ((Base.u32_and (v_value) ((Base.W32 0x7f)))) ((Base.W32 0x80))); (Base.u32_or ((Base.u32_and ((Base.u32_shrn (v_value) (7))) ((Base.W32 0x7f)))) ((Base.W32 0x80))); (Base.u32_or ((Base.u32_and ((Base.u32_shrn (v_value) (14))) ((Base.W32 0x7f)))) ((Base.W32 0x80))); (Base.u32_or ((Base.u32_and ((Base.u32_shrn (v_value) (21))) ((Base.W32 0x7f)))) ((Base.W32 0x80))); (Base.u32_or ((Base.u32_shrn (v_value) (28))) ((Base.bool_pick ((Base.u32_is_lt (v_value) ((Base.W32 0x80000000)))) ((Base.W32 0x0)) ((Base.W32 0x70)))))]
and (* wasm.bend:238 *)
f_utf8_char : Base.word32 -> (Base.word32) list =
fun v_code ->
(Base.bool_pick ((Base.u32_is_lt (v_code) ((Base.W32 0x80)))) ([v_code]) ((Base.bool_pick ((Base.u32_is_lt (v_code) ((Base.W32 0x800)))) ([(Base.u32_or ((Base.W32 0xc0)) ((Base.u32_shrn (v_code) (6)))); (Base.u32_or ((Base.W32 0x80)) ((Base.u32_and (v_code) ((Base.W32 0x3f)))))]) ((Base.bool_pick ((Base.u32_is_lt (v_code) ((Base.W32 0x10000)))) ([(Base.u32_or ((Base.W32 0xe0)) ((Base.u32_shrn (v_code) (12)))); (Base.u32_or ((Base.W32 0x80)) ((Base.u32_and ((Base.u32_shrn (v_code) (6))) ((Base.W32 0x3f))))); (Base.u32_or ((Base.W32 0x80)) ((Base.u32_and (v_code) ((Base.W32 0x3f)))))]) ([(Base.u32_or ((Base.W32 0xf0)) ((Base.u32_shrn (v_code) (18)))); (Base.u32_or ((Base.W32 0x80)) ((Base.u32_and ((Base.u32_shrn (v_code) (12))) ((Base.W32 0x3f))))); (Base.u32_or ((Base.W32 0x80)) ((Base.u32_and ((Base.u32_shrn (v_code) (6))) ((Base.W32 0x3f))))); (Base.u32_or ((Base.W32 0x80)) ((Base.u32_and (v_code) ((Base.W32 0x3f)))))]))))))
and (* wasm.bend:246 *)
f_utf8 : Base.text -> (Base.word32) list =
fun v_text ->
(match v_text with
| SNil ->
[]
| (SCon ((Chr (v_code)), v_tail)) ->
(f_concat ((f_utf8_char (v_code))) ((f_utf8 (v_tail)))))
and (* wasm.bend:253 *)
f_sized : (Base.word32) list -> (Base.word32) list =
fun v_bytes ->
(f_concat ((f_unsigned_leb ((f_byte_length (v_bytes) (0))))) (v_bytes))
and (* wasm.bend:256 *)
f_section : Base.word32 -> (Base.word32) list -> (Base.word32) list =
fun v_id v_bytes ->
(v_id :: (f_sized (v_bytes)))
and (* wasm.bend:259 *)
f_vector : ((Base.word32) list) list -> (Base.word32) list =
fun v_entries ->
(f_concat ((f_unsigned_leb ((Base.list_length (v_entries))))) ((f_join (v_entries))))
and (* wasm.bend:262 *)
f_required_slot : (int) option -> Base.text -> (M.t_Diagnostic, int) Base.result_ =
fun v_found v_name ->
(match v_found with
| None ->
(Fail ((M.Diagnostic (s_0, v_name, s_1))))
| (Some (v_index)) ->
(Done (v_index)))
and (* wasm.bend:269 *)
f_lookup_slot : ((int) option) Base.map -> Base.text -> (M.t_Diagnostic, int) Base.result_ =
fun v_slots v_name ->
(f_required_slot ((Index.f_get (v_slots) (v_name) (None))) (v_name))
and (* wasm.bend:272 *)
f_lookup_constructor : (E.t_ConstructorSlot) option -> Base.text -> (M.t_Diagnostic, E.t_ConstructorSlot) Base.result_ =
fun v_found v_name ->
(match v_found with
| None ->
(Fail ((M.Diagnostic (s_0, v_name, s_2))))
| (Some (v_variant)) ->
(Done (v_variant)))
and (* wasm.bend:279 *)
f_lookup_lambda : (F.t_Lambda) option -> int -> (M.t_Diagnostic, F.t_Lambda) Base.result_ =
fun v_found v_identity ->
(match v_found with
| None ->
(Fail ((M.Diagnostic (s_0, (Base.nat_show (v_identity)), s_3))))
| (Some (v_lambda)) ->
(Done (v_lambda)))
and (* wasm.bend:288 *)
f_lookup_local_work : (t_Local) list -> Base.text -> (t_Location) option -> (M.t_Diagnostic, t_Location) Base.result_ =
fun v_locals v_name v_found ->
(match (v_locals, v_found) with
| (_, (Some (v_location))) ->
(Done (v_location))
| ([], None) ->
(Fail ((M.Diagnostic (s_0, v_name, s_4))))
| (((Local (v_declared, v_location)) :: v_tail), None) ->
(f_lookup_local_work (v_tail) (v_name) ((Base.bool_pick ((M.f_name_equal (v_declared) (v_name))) ((Some (v_location))) (None)))))
and (* wasm.bend:297 *)
f_lookup_local : (t_Local) list -> Base.text -> (M.t_Diagnostic, t_Location) Base.result_ =
fun v_locals v_name ->
(f_lookup_local_work (v_locals) (v_name) (None))
and (* wasm.bend:300 *)
f_function_entries : (M.t_CheckedFunction) list -> (t_Entry) list =
fun v_functions ->
(match v_functions with
| [] ->
[]
| ((M.CheckedFunction ((M.Function (v_name, v_exported, v_parameter, v_parameter_type, v_result_type, v_body)), v_signature, v_effects)) :: v_tail) ->
((Entry ((Base.string_append s_5 v_name), v_parameter, v_body, [])) :: (f_function_entries (v_tail))))
and (* wasm.bend:307 *)
f_lambda_entries : (F.t_Lambda) list -> (t_Entry) list =
fun v_lambdas ->
(match v_lambdas with
| [] ->
[]
| ((F.Lambda (v_identity, v_parameter, v_body, v_captures)) :: v_tail) ->
((Entry ((Base.string_append s_6 (Base.nat_show (v_identity))), v_parameter, v_body, v_captures)) :: (f_lambda_entries (v_tail))))
and (* wasm.bend:314 *)
f_constructor_entries : (E.t_ConstructorSlot) list -> Base.set -> (t_Entry) list =
fun v_constructors v_used ->
(match v_constructors with
| [] ->
[]
| ((E.ConstructorSlot (v_name, v_tag, v_payload)) :: v_tail) ->
(let v_rest = (f_constructor_entries (v_tail) (v_used)) in
(Base.bool_pick ((Base.bool_and (v_payload) ((Base.maybe_is_some ((Index.f_find (v_used) (v_name))))))) (((Entry ((Base.string_append s_7 v_name), s_8, (M.ConstructExpr (v_name, (Some ((M.LocalExpr (s_8)))))), [])) :: v_rest)) (v_rest))))
and (* wasm.bend:322 *)
f_static_entries : t_StaticCatalog -> ((int) option) Base.map =
fun v_catalog ->
(let (StaticCatalog (v_entries, v_projection, v_operations)) = v_catalog in
v_entries)
and (* wasm.bend:326 *)
f_static_projection : t_StaticCatalog -> I.t_Metadata =
fun v_catalog ->
(let (StaticCatalog (v_entries, v_projection, v_operations)) = v_catalog in
v_projection)
and (* wasm.bend:330 *)
f_static_operations : t_StaticCatalog -> ((int) option) Base.map =
fun v_catalog ->
(let (StaticCatalog (v_entries, v_projection, v_operations)) = v_catalog in
v_operations)
and (* wasm.bend:334 *)
f_slot_index_go : (t_Slot) list -> ((int) option) Base.map -> ((int) option) Base.map =
fun v_slots v_indexed ->
(match v_slots with
| [] ->
v_indexed
| ((Slot (v_name, v_position)) :: v_tail) ->
(f_slot_index_go (v_tail) ((Base.map_set (v_indexed) (v_name) ((Some (v_position)))))))
and (* wasm.bend:341 *)
f_slot_index : (t_Slot) list -> ((int) option) Base.map =
fun v_slots ->
(f_slot_index_go ((Base.list_reverse (v_slots))) ((Base.map_new ())))
and (* wasm.bend:344 *)
f_operation_slots : (M.t_Operation) list -> int -> (t_Slot) list =
fun v_operations v_index ->
(match v_operations with
| [] ->
[]
| ((M.Operation (v_identity, v_parameter, v_result)) :: v_tail) ->
(let v_position = v_index in
((Slot ((I.f_operation_key (v_identity)), v_position)) :: (f_operation_slots (v_tail) ((Base.nat_add 1 v_position)))))
| (v_head :: v_tail) ->
(f_operation_slots (v_tail) (v_index)))
and (* wasm.bend:354 *)
f_required_symbol : (int) option -> Base.text -> (M.t_Diagnostic, int) Base.result_ =
fun v_found v_name ->
(match v_found with
| None ->
(Fail ((M.Diagnostic (s_9, v_name, s_10))))
| (Some (v_position)) ->
(Done (v_position)))
and (* wasm.bend:361 *)
f_lookup_symbol : ((int) option) Base.map -> Base.text -> (M.t_Diagnostic, int) Base.result_ =
fun v_indexed v_name ->
(f_required_symbol ((Index.f_get (v_indexed) (v_name) (None))) (v_name))
and (* wasm.bend:364 *)
f_symbol_entries : t_Catalog -> ((int) option) Base.map =
fun v_symbols ->
(let (Catalog (v_entries, v_constructors, v_constants, v_operations, v_runtime)) = v_symbols in
v_entries)
and (* wasm.bend:368 *)
f_symbol_constructors : t_Catalog -> ((E.t_ConstructorSlot) option) Base.map =
fun v_symbols ->
(let (Catalog (v_entries, v_constructors, v_constants, v_operations, v_runtime)) = v_symbols in
v_constructors)
and (* wasm.bend:372 *)
f_symbol_constants : t_Catalog -> ((int) option) Base.map =
fun v_symbols ->
(let (Catalog (v_entries, v_constructors, v_constants, v_operations, v_runtime)) = v_symbols in
v_constants)
and (* wasm.bend:376 *)
f_symbol_operations : t_Catalog -> ((int) option) Base.map =
fun v_symbols ->
(let (Catalog (v_entries, v_constructors, v_constants, v_operations, v_runtime)) = v_symbols in
v_operations)
and (* wasm.bend:380 *)
f_runtime_global : t_Catalog -> Base.text -> (t_RuntimeGlobal) option =
fun v_symbols v_name ->
(let (Catalog (v_entries, v_constructors, v_constants, v_operations, v_runtime)) = v_symbols in
(Index.f_find (v_runtime) (v_name)))
and (* wasm.bend:384 *)
f_global_index : int -> int -> int =
fun v_index v_imports ->
(Base.nat_add (v_index) ((Base.bool_pick ((Base.nat_is_eq (v_imports) (0))) (0) (1))))
and (* wasm.bend:387 *)
f_runtime_from_word : M.t_Ty -> (Base.word32) list =
fun v_ty ->
(match v_ty with
| M.F32Ty ->
[(Base.W32 0xbe)]
| _ ->
[])
and (* wasm.bend:394 *)
f_runtime_to_word : M.t_Ty -> (Base.word32) list =
fun v_ty ->
(match v_ty with
| M.F32Ty ->
[(Base.W32 0xbc)]
| _ ->
[])
and (* wasm.bend:401 *)
f_constant_reference : (t_RuntimeGlobal) option -> Base.text -> t_Catalog -> int -> (M.t_Diagnostic, (Base.word32) list) Base.result_ =
fun v_found v_name v_symbols v_imports ->
(match v_found with
| (Some ((RuntimeGlobal (v_index, v_ty)))) ->
(Done ((f_concat (((Base.W32 0x23) :: (f_unsigned_leb ((f_global_index (v_index) (v_imports)))))) ((f_runtime_to_word (v_ty))))))
| None ->
(match (f_lookup_symbol ((f_symbol_constants (v_symbols))) (v_name)) with
| Fail __error -> Fail __error
| Done v_word ->
(Done ((f_i32_constant ((Base.u32_from_nat (v_word))))))))
and (* wasm.bend:410 *)
f_context_locals : t_Context -> (t_Local) list =
fun v_context ->
(let (Context (v_locals, v_next_local, v_labels, v_provider)) = v_context in
v_locals)
and (* wasm.bend:414 *)
f_context_next : t_Context -> int =
fun v_context ->
(let (Context (v_locals, v_next_local, v_labels, v_provider)) = v_context in
v_next_local)
and (* wasm.bend:418 *)
f_reserve : t_Context -> int -> t_Context =
fun v_context v_count ->
(let (Context (v_locals, v_next_local, v_labels, v_provider)) = v_context in
(Context (v_locals, (Base.nat_add (v_next_local) (v_count)), v_labels, v_provider)))
and (* wasm.bend:422 *)
f_bind : t_Context -> Base.text -> t_Location -> t_Context =
fun v_context v_name v_location ->
(let (Context (v_locals, v_next_local, v_labels, v_provider)) = v_context in
(Context (((Local (v_name, v_location)) :: v_locals), v_next_local, v_labels, v_provider)))
and (* wasm.bend:426 *)
f_control : t_Context -> (int) option -> t_Context =
fun v_context v_label ->
(let (Context (v_locals, v_next_local, v_labels, v_provider)) = v_context in
(Context (v_locals, v_next_local, (v_label :: v_labels), v_provider)))
and (* wasm.bend:430 *)
f_with_provider : t_Context -> int -> t_Context =
fun v_context v_provider ->
(let (Context (v_locals, v_next_local, v_labels, v_previous)) = v_context in
(Context (v_locals, v_next_local, v_labels, v_provider)))
and (* wasm.bend:434 *)
f_context_provider : t_Context -> int =
fun v_context ->
(let (Context (v_locals, v_next_local, v_labels, v_provider)) = v_context in
v_provider)
and (* wasm.bend:438 *)
f_label_depth : ((int) option) list -> int -> int -> (M.t_Diagnostic, int) Base.result_ =
fun v_labels v_wanted v_depth ->
(match v_labels with
| [] ->
(Fail ((M.Diagnostic (s_0, (Base.nat_show (v_wanted)), s_11))))
| (None :: v_tail) ->
(f_label_depth (v_tail) (v_wanted) ((Base.nat_add 1 v_depth)))
| ((Some (v_label)) :: v_tail) ->
(let v_index = v_depth in
(Base.bool_pick ((Base.nat_is_eq (v_label) (v_wanted))) ((Done (v_index))) ((f_label_depth (v_tail) (v_wanted) ((Base.nat_add 1 v_index)))))))
and (* wasm.bend:448 *)
f_return_depth : t_Context -> int -> (M.t_Diagnostic, int) Base.result_ =
fun v_context v_label ->
(let (Context (v_locals, v_next_local, v_labels, v_provider)) = v_context in
(f_label_depth (v_labels) (v_label) (0)))
and (* wasm.bend:452 *)
f_loads : (int) list -> (Base.word32) list =
fun v_offsets ->
(match v_offsets with
| [] ->
[]
| (v_offset :: v_tail) ->
(f_concat ([(Base.W32 0x28); (Base.W32 0x2)]) ((f_concat ((f_unsigned_leb (v_offset))) ((f_loads (v_tail)))))))
and (* wasm.bend:459 *)
f_read_location : t_Location -> (Base.word32) list =
fun v_location ->
(let (Location (v_local, v_offsets)) = v_location in
(f_concat (((Base.W32 0x20) :: (f_unsigned_leb (v_local)))) ((f_loads (v_offsets)))))
and (* wasm.bend:463 *)
f_field_location : t_Location -> int -> t_Location =
fun v_location v_offset ->
(let (Location (v_local, v_offsets)) = v_location in
(Location (v_local, (Base.list_append (v_offsets) ([v_offset])))))
and (* wasm.bend:467 *)
f_pattern_bindings_work : int -> t_PatternWork -> t_Context -> (M.t_Diagnostic, t_Context) Base.result_ =
fun v_fuel v_work v_context ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_12, s_13, s_14))))
| (__nat_2, (OnePattern ((M.BindingPattern (v_name)), v_location))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(Done ((f_bind (v_context) (v_name) (v_location)))))
| (__nat_3, (OnePattern ((M.ConstructorPattern (v_constructor, (Some (v_payload)))), v_location))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_pattern_bindings_work (v_rest) ((OnePattern (v_payload, (f_field_location (v_location) (4))))) (v_context)))
| (__nat_4, (OnePattern ((M.ProductPattern (v_elements)), v_location))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_pattern_bindings_work (v_rest) ((ProductFields (v_elements, v_location, 0))) (v_context)))
| (__nat_5, (OnePattern (v_pattern, v_location))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(Done (v_context)))
| (__nat_6, (ProductFields ([], v_location, v_offset))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(Done (v_context)))
| (__nat_7, (ProductFields ((v_head :: v_tail), v_location, v_offset))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(match (f_pattern_bindings_work (v_rest) ((OnePattern (v_head, (f_field_location (v_location) (v_offset))))) (v_context)) with
| Fail __error -> Fail __error
| Done v_bound ->
(f_pattern_bindings_work (v_rest) ((ProductFields (v_tail, v_location, (Base.nat_add 4 v_offset)))) (v_bound))))
| (__nat_8, (RowPatterns ([], v_first))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(Done (v_context)))
| (__nat_9, (RowPatterns ((v_head :: v_tail), v_first))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(match (f_pattern_bindings_work (v_rest) ((OnePattern (v_head, (Location (v_first, []))))) (v_context)) with
| Fail __error -> Fail __error
| Done v_bound ->
(f_pattern_bindings_work (v_rest) ((RowPatterns (v_tail, (Base.nat_add 1 v_first)))) (v_bound)))))
and (* wasm.bend:492 *)
f_opcode : M.t_ScalarOp -> Base.word32 =
fun v_operator ->
(match v_operator with
| M.Add ->
(Base.W32 0x6a)
| M.Subtract ->
(Base.W32 0x6b)
| M.Multiply ->
(Base.W32 0x6c)
| M.Equal ->
(Base.W32 0x46)
| M.LessThan ->
(Base.W32 0x49)
| M.F32Add ->
(Base.W32 0x92)
| M.F32Subtract ->
(Base.W32 0x93)
| M.F32Multiply ->
(Base.W32 0x94)
| M.F32Divide ->
(Base.W32 0x95)
| M.F32Equal ->
(Base.W32 0x5b)
| M.F32NotEqual ->
(Base.W32 0x5c)
| M.F32LessThan ->
(Base.W32 0x5d)
| M.F32LessEqual ->
(Base.W32 0x5f)
| M.F32GreaterThan ->
(Base.W32 0x5e)
| M.F32GreaterEqual ->
(Base.W32 0x60))
and (* wasm.bend:525 *)
f_unary_opcode : M.t_UnaryOp -> (Base.word32) list =
fun v_operator ->
(match v_operator with
| M.F32Negate ->
[(Base.W32 0x8c)]
| M.F32Absolute ->
[(Base.W32 0x8b)]
| M.F32SquareRoot ->
[(Base.W32 0x91)]
| M.F32Floor ->
[(Base.W32 0x8e)]
| M.F32Ceiling ->
[(Base.W32 0x8d)]
| M.F32Truncate ->
[(Base.W32 0x8f)]
| M.U32ToF32 ->
[(Base.W32 0xb3)]
| M.F32ToU32 ->
[(Base.W32 0xfc); (Base.W32 0x1)])
and (* wasm.bend:546 *)
f_scalar_from_word : M.t_Ty -> (Base.word32) list =
fun v_ty ->
(match v_ty with
| M.F32Ty ->
[(Base.W32 0xbe)]
| _ ->
[])
and (* wasm.bend:553 *)
f_scalar_to_word : M.t_Ty -> (Base.word32) list =
fun v_ty ->
(match v_ty with
| M.F32Ty ->
[(Base.W32 0xbc)]
| _ ->
[])
and (* wasm.bend:560 *)
f_append_code : t_Code -> t_Code -> (Base.word32) list -> (Base.word32) list -> t_Code =
fun v_left v_right v_middle v_end ->
(let (Code (v_lb, v_ll)) = v_left in
(let (Code (v_rb, v_rl)) = v_right in
(Code ((f_fragments_join ([v_lb; [(Bytes (v_middle))]; v_rb; [(Bytes (v_end))]])), (Base.nat_max (v_ll) (v_rl))))))
and (* wasm.bend:565 *)
f_require_locals : t_Code -> int -> t_Code =
fun v_code v_count ->
(let (Code (v_bytes, v_locals)) = v_code in
(Code (v_bytes, (Base.nat_max (v_locals) (v_count)))))
and (* wasm.bend:569 *)
f_scalar_code : (M.t_Diagnostic, t_Code) Base.result_ -> (M.t_Diagnostic, t_Code) Base.result_ -> M.t_ScalarOp -> (M.t_Diagnostic, t_Code) Base.result_ =
fun v_left v_right v_operator ->
(match (v_left, v_right) with
| ((Fail (v_error)), _) ->
(Fail (v_error))
| ((Done (v_code)), (Fail (v_error))) ->
(Fail (v_error))
| ((Done (v_a)), (Done (v_b))) ->
(let v_convert = (f_scalar_from_word ((M.f_scalar_parameter (v_operator)))) in
(Done ((f_append_code (v_a) (v_b) (v_convert) ((f_join ([v_convert; [(f_opcode (v_operator))]; (f_scalar_to_word ((M.f_scalar_result (v_operator))))]))))))))
and (* wasm.bend:579 *)
f_capture_stores : (Base.text) list -> (t_Local) list -> int -> int -> (M.t_Diagnostic, (Base.word32) list) Base.result_ =
fun v_names v_locals v_pointer v_offset ->
(match v_names with
| [] ->
(Done ([]))
| (v_name :: v_tail) ->
(let v_at = v_offset in
(match (f_lookup_local (v_locals) (v_name)) with
| Fail __error -> Fail __error
| Done v_location ->
(match (f_capture_stores (v_tail) (v_locals) (v_pointer) ((Base.nat_add 4 v_at))) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((f_join ([((Base.W32 0x20) :: (f_unsigned_leb (v_pointer))); (f_read_location (v_location)); [(Base.W32 0x36); (Base.W32 0x2)]; (f_unsigned_leb (v_at)); v_rest]))))))))
and (* wasm.bend:590 *)
f_closure_code : Base.text -> (Base.text) list -> t_Context -> (M.t_Diagnostic, t_Code) Base.result_ =
fun v_key v_captures v_context ->
(let v_pointer = (f_context_next (v_context)) in
(match (f_capture_stores (v_captures) ((f_context_locals (v_context))) (v_pointer) (4)) with
| Fail __error -> Fail __error
| Done v_stores ->
(Done ((Code ([(Bytes ((f_i32_constant ((Base.u32_from_nat ((Base.nat_mul (4) ((Base.nat_add 1 (Base.list_length (v_captures))))))))))); Allocate; (Bytes (((Base.W32 0x22) :: (f_unsigned_leb (v_pointer))))); (EntryIndex (v_key)); (Bytes ((f_join ([[(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x0)]; v_stores; ((Base.W32 0x20) :: (f_unsigned_leb (v_pointer)))]))))], (Base.nat_add 1 v_pointer)))))))
and (* wasm.bend:596 *)
f_construct_code : t_Fragment -> t_Code -> int -> t_Code =
fun v_tag v_payload v_slot ->
(let (Code (v_fragments, v_locals)) = v_payload in
(Code ((f_fragments_join ([v_fragments; [(Bytes ((f_concat (((Base.W32 0x21) :: (f_unsigned_leb (v_slot)))) ((f_i32_constant ((Base.W32 0x8))))))); Allocate; (Bytes (((Base.W32 0x22) :: (f_unsigned_leb ((Base.nat_add 1 v_slot)))))); v_tag; (Bytes ((f_join ([[(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x0)]; ((Base.W32 0x20) :: (f_unsigned_leb ((Base.nat_add 1 v_slot)))); ((Base.W32 0x20) :: (f_unsigned_leb (v_slot))); [(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x4)]; ((Base.W32 0x20) :: (f_unsigned_leb ((Base.nat_add 1 v_slot))))]))))]])), (Base.nat_max (v_locals) ((Base.nat_add 2 v_slot))))))
and (* wasm.bend:600 *)
f_local_get : int -> (Base.word32) list =
fun v_slot ->
((Base.W32 0x20) :: (f_unsigned_leb (v_slot)))
and (* wasm.bend:603 *)
f_element_stores : int -> int -> int -> int -> ((Base.word32) list) list -> (Base.word32) list =
fun v_count v_pointer v_first v_offset v_reversed ->
(match v_count with
| 0 ->
(f_join ((Base.list_reverse (((f_local_get (v_pointer)) :: v_reversed)))))
| __nat_10 when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(let v_slot = v_first in
(let v_at = v_offset in
(let v_bytes = (f_join ([(f_local_get (v_pointer)); (f_local_get (v_slot)); [(Base.W32 0x36); (Base.W32 0x2)]; (f_unsigned_leb (v_at))])) in
(f_element_stores (v_rest) (v_pointer) ((Base.nat_add 1 v_slot)) ((Base.nat_add 4 v_at)) ((v_bytes :: v_reversed))))))))
and (* wasm.bend:613 *)
f_product_code : t_Code -> int -> int -> t_Code =
fun v_elements v_count v_first ->
(let (Code (v_fragments, v_locals)) = v_elements in
(let v_pointer = (Base.nat_add (v_first) (v_count)) in
(Code ((f_fragments_join ([v_fragments; [(Bytes ((f_i32_constant ((Base.u32_from_nat ((Base.nat_mul (4) (v_count)))))))); Allocate; (Bytes ((f_concat (((Base.W32 0x21) :: (f_unsigned_leb (v_pointer)))) ((f_element_stores (v_count) (v_pointer) (v_first) (0) ([]))))))]])), (Base.nat_max (v_locals) ((Base.nat_add 1 v_pointer)))))))
and (* wasm.bend:618 *)
f_product_arity : int -> (M.t_Diagnostic, unit) Base.result_ =
fun v_count ->
(match v_count with
| 0 ->
(Fail ((M.Diagnostic (s_0, s_15, s_16))))
| 1 ->
(Fail ((M.Diagnostic (s_0, s_15, s_16))))
| __nat_11 when __nat_11 >= 2 ->
(let v_rest = (__nat_11 - 2) in
(Done (()))))
and (* wasm.bend:627 *)
f_projection_code : bool -> int -> (M.t_Diagnostic, t_Code) Base.result_ =
fun v_allowed v_index ->
(match v_allowed with
| true ->
(Done ((f_byte_code ((f_concat ([(Base.W32 0x28); (Base.W32 0x2)]) ((f_unsigned_leb ((Base.nat_mul (4) (v_index))))))) (0))))
| false ->
(Fail ((M.Diagnostic (s_12, s_17, s_18)))))
and (* wasm.bend:634 *)
f_checked_array_size : bool -> int -> (M.t_Diagnostic, Base.word32) Base.result_ =
fun v_allowed v_count ->
(match v_allowed with
| true ->
(Done ((Base.u32_from_nat ((Base.nat_mul (4) ((Base.nat_add 1 v_count)))))))
| false ->
(Fail ((M.Diagnostic (s_12, s_19, s_20)))))
and (* wasm.bend:641 *)
f_array_size : int -> (M.t_Diagnostic, Base.word32) Base.result_ =
fun v_count ->
(f_checked_array_size ((Base.nat_is_lt (v_count) ((Base.u32_to_nat ((Base.W32 0x400000)))))) (v_count))
and (* wasm.bend:644 *)
f_array_code : t_Code -> int -> Base.word32 -> int -> t_Code =
fun v_elements v_count v_size v_first ->
(let (Code (v_fragments, v_locals)) = v_elements in
(let v_pointer = (Base.nat_add (v_first) (v_count)) in
(Code ((f_fragments_join ([v_fragments; [(Bytes ((f_i32_constant (v_size)))); Allocate; (Bytes ((f_join ([((Base.W32 0x22) :: (f_unsigned_leb (v_pointer))); (f_i32_constant ((Base.u32_from_nat (v_count)))); [(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x0)]; (f_element_stores (v_count) (v_pointer) (v_first) (4) ([]))]))))]])), (Base.nat_max (v_locals) ((Base.nat_add 1 v_pointer)))))))
and (* wasm.bend:655 *)
f_runtime_array_max_count : unit -> Base.word32 =
fun () ->
(Base.W32 0x3ffffffe)
and (* wasm.bend:658 *)
f_runtime_memory_max_pages : unit -> int =
fun () ->
65536
and (* wasm.bend:663 *)
f_array_fill_code : int -> t_Code =
fun v_first ->
(let v_value = (Base.nat_add 1 v_first) in
(let v_pointer = (Base.nat_add 2 v_first) in
(let v_index = (Base.nat_add 3 v_first) in
(Code ([(Bytes ((f_join ([(f_local_get (v_first)); (f_i32_constant ((f_runtime_array_max_count ()))); [(Base.W32 0x4b); (Base.W32 0x4); (Base.W32 0x40); (Base.W32 0x0); (Base.W32 0xb)]; (f_local_get (v_first)); [(Base.W32 0x41); (Base.W32 0x1); (Base.W32 0x6a); (Base.W32 0x41); (Base.W32 0x4); (Base.W32 0x6c)]])))); Allocate; (Bytes ((f_join ([((Base.W32 0x22) :: (f_unsigned_leb (v_pointer))); (f_local_get (v_first)); [(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x0)]; [(Base.W32 0x41); (Base.W32 0x0)]; ((Base.W32 0x21) :: (f_unsigned_leb (v_index))); [(Base.W32 0x2); (Base.W32 0x40); (Base.W32 0x3); (Base.W32 0x40)]; (f_local_get (v_index)); (f_local_get (v_first)); [(Base.W32 0x4f); (Base.W32 0xd); (Base.W32 0x1)]; (f_local_get (v_pointer)); (f_local_get (v_index)); [(Base.W32 0x41); (Base.W32 0x4); (Base.W32 0x6c); (Base.W32 0x6a)]; (f_local_get (v_value)); [(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x4)]; (f_local_get (v_index)); [(Base.W32 0x41); (Base.W32 0x1); (Base.W32 0x6a)]; ((Base.W32 0x21) :: (f_unsigned_leb (v_index))); [(Base.W32 0xc); (Base.W32 0x0); (Base.W32 0xb); (Base.W32 0xb)]; (f_local_get (v_pointer))]))))], (Base.nat_add 4 v_first))))))
and (* wasm.bend:685 *)
f_array_generate_code : int -> int -> t_Code =
fun v_first v_provider ->
(let v_generator = (Base.nat_add 1 v_first) in
(let v_pointer = (Base.nat_add 2 v_first) in
(let v_index = (Base.nat_add 3 v_first) in
(Code ([(Bytes ((f_join ([(f_local_get (v_first)); (f_i32_constant ((f_runtime_array_max_count ()))); [(Base.W32 0x4b); (Base.W32 0x4); (Base.W32 0x40); (Base.W32 0x0); (Base.W32 0xb)]; (f_local_get (v_first)); [(Base.W32 0x41); (Base.W32 0x1); (Base.W32 0x6a); (Base.W32 0x41); (Base.W32 0x4); (Base.W32 0x6c)]])))); Allocate; (Bytes ((f_join ([((Base.W32 0x22) :: (f_unsigned_leb (v_pointer))); (f_local_get (v_first)); [(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x0)]; [(Base.W32 0x41); (Base.W32 0x0)]; ((Base.W32 0x21) :: (f_unsigned_leb (v_index))); [(Base.W32 0x2); (Base.W32 0x40); (Base.W32 0x3); (Base.W32 0x40)]; (f_local_get (v_index)); (f_local_get (v_first)); [(Base.W32 0x4f); (Base.W32 0xd); (Base.W32 0x1)]; (f_local_get (v_pointer)); (f_local_get (v_index)); [(Base.W32 0x41); (Base.W32 0x4); (Base.W32 0x6c); (Base.W32 0x6a)]; (f_local_get (v_generator)); (f_local_get (v_index)); (f_local_get (v_provider)); (f_local_get (v_generator)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x0); (Base.W32 0x11); (Base.W32 0x0); (Base.W32 0x0); (Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x4)]; (f_local_get (v_index)); [(Base.W32 0x41); (Base.W32 0x1); (Base.W32 0x6a)]; ((Base.W32 0x21) :: (f_unsigned_leb (v_index))); [(Base.W32 0xc); (Base.W32 0x0); (Base.W32 0xb); (Base.W32 0xb)]; (f_local_get (v_pointer))]))))], (Base.nat_add 4 v_first))))))
and (* wasm.bend:706 *)
f_array_get_code : int -> t_Code =
fun v_first ->
(let v_index = (Base.nat_add 1 v_first) in
(f_byte_code ((f_join ([(f_local_get (v_index)); (f_local_get (v_first)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x0); (Base.W32 0x4f); (Base.W32 0x4); (Base.W32 0x40); (Base.W32 0x0); (Base.W32 0xb)]; (f_local_get (v_first)); (f_local_get (v_index)); [(Base.W32 0x41); (Base.W32 0x4); (Base.W32 0x6c); (Base.W32 0x6a); (Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x4)]]))) ((Base.nat_add 2 v_first))))
and (* wasm.bend:715 *)
f_array_set_code : int -> t_Code =
fun v_first ->
(let v_index = (Base.nat_add 1 v_first) in
(let v_value = (Base.nat_add 2 v_first) in
(let v_length = (Base.nat_add 3 v_first) in
(let v_pointer = (Base.nat_add 4 v_first) in
(Code ([(Bytes ((f_join ([(f_local_get (v_first)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x0)]; ((Base.W32 0x21) :: (f_unsigned_leb (v_length))); (f_local_get (v_index)); (f_local_get (v_length)); [(Base.W32 0x4f); (Base.W32 0x4); (Base.W32 0x40); (Base.W32 0x0); (Base.W32 0xb)]; (f_local_get (v_length)); (f_i32_constant ((f_runtime_array_max_count ()))); [(Base.W32 0x4b); (Base.W32 0x4); (Base.W32 0x40); (Base.W32 0x0); (Base.W32 0xb)]; (f_local_get (v_length)); [(Base.W32 0x41); (Base.W32 0x1); (Base.W32 0x6a); (Base.W32 0x41); (Base.W32 0x4); (Base.W32 0x6c)]])))); Allocate; (Bytes ((f_join ([((Base.W32 0x21) :: (f_unsigned_leb (v_pointer))); (f_local_get (v_pointer)); (f_local_get (v_first)); (f_local_get (v_length)); [(Base.W32 0x41); (Base.W32 0x1); (Base.W32 0x6a); (Base.W32 0x41); (Base.W32 0x4); (Base.W32 0x6c); (Base.W32 0xfc); (Base.W32 0xa); (Base.W32 0x0); (Base.W32 0x0)]; (f_local_get (v_pointer)); (f_local_get (v_index)); [(Base.W32 0x41); (Base.W32 0x4); (Base.W32 0x6c); (Base.W32 0x6a)]; (f_local_get (v_value)); [(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x4)]; (f_local_get (v_pointer))]))))], (Base.nat_add 5 v_first)))))))
and (* wasm.bend:736 *)
f_array_reuse_code : int -> t_Code =
fun v_first ->
(let v_index = (Base.nat_add 1 v_first) in
(let v_value = (Base.nat_add 2 v_first) in
(f_byte_code ((f_join ([(f_local_get (v_index)); (f_local_get (v_first)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x0); (Base.W32 0x4f); (Base.W32 0x4); (Base.W32 0x40); (Base.W32 0x0); (Base.W32 0xb)]; (f_local_get (v_first)); (f_local_get (v_index)); [(Base.W32 0x41); (Base.W32 0x4); (Base.W32 0x6c); (Base.W32 0x6a)]; (f_local_get (v_value)); [(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x4)]; (f_local_get (v_first))]))) ((Base.nat_add 3 v_first)))))
and (* wasm.bend:747 *)
f_state_provider_code : M.t_TypeId -> M.t_TypeId -> t_Code -> int -> t_Code =
fun v_read v_write v_value v_slot ->
(let (Code (v_fragments, v_locals)) = v_value in
(let v_pointer = (Base.nat_add 1 v_slot) in
(Code ((f_fragments_join ([v_fragments; [(Bytes ((f_join ([((Base.W32 0x21) :: (f_unsigned_leb (v_slot))); (f_i32_constant ((Base.W32 0x10)))])))); Allocate; (Bytes ((f_join ([((Base.W32 0x22) :: (f_unsigned_leb (v_pointer))); (f_i32_constant ((Base.W32 0xffffffff))); [(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x0)]; (f_local_get (v_pointer))])))); (OperationIndex (v_read)); (Bytes ((f_join ([[(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x4)]; (f_local_get (v_pointer))])))); (OperationIndex (v_write)); (Bytes ((f_join ([[(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x8)]; (f_local_get (v_pointer)); (f_local_get (v_slot)); [(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0xc)]; (f_local_get (v_pointer))]))))]])), (Base.nat_max (v_locals) ((Base.nat_add 2 v_slot)))))))
and (* wasm.bend:756 *)
f_install_provider : int -> int -> t_Code =
fun v_slot v_outer ->
(let v_frame = (Base.nat_add 1 v_slot) in
(let v_cell = (Base.nat_add 2 v_slot) in
(Code ([(Bytes ((f_join ([((Base.W32 0x21) :: (f_unsigned_leb (v_slot))); (f_local_get (v_slot)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x0)]; (f_i32_constant ((Base.W32 0xffffffff))); [(Base.W32 0x46); (Base.W32 0x4); (Base.W32 0x40)]; (f_i32_constant ((Base.W32 0x24)))])))); Allocate; (Bytes ((f_join ([((Base.W32 0x22) :: (f_unsigned_leb (v_frame))); [(Base.W32 0x41); (Base.W32 0x20); (Base.W32 0x6a)]; ((Base.W32 0x21) :: (f_unsigned_leb (v_cell))); (f_local_get (v_cell)); (f_local_get (v_slot)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0xc); (Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x0)]; (f_local_get (v_frame)); (f_local_get (v_slot)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x4); (Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x0)]; (f_local_get (v_frame)); (f_local_get (v_cell)); [(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x4)]; (f_local_get (v_frame)); (f_local_get (v_frame)); [(Base.W32 0x41); (Base.W32 0x10); (Base.W32 0x6a); (Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x8)]; (f_local_get (v_frame)); [(Base.W32 0x41); (Base.W32 0x1); (Base.W32 0x36); (Base.W32 0x2); (Base.W32 0xc)]; (f_local_get (v_frame)); (f_local_get (v_slot)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x8); (Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x10)]; (f_local_get (v_frame)); (f_local_get (v_cell)); [(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x14)]; (f_local_get (v_frame)); (f_local_get (v_outer)); [(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x18)]; (f_local_get (v_frame)); [(Base.W32 0x41); (Base.W32 0x2); (Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x1c); (Base.W32 0x5)]; (f_i32_constant ((Base.W32 0x10)))])))); Allocate; (Bytes ((f_join ([((Base.W32 0x22) :: (f_unsigned_leb (v_frame))); (f_local_get (v_slot)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x0); (Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x0)]; (f_local_get (v_frame)); (f_local_get (v_slot)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x4); (Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x4)]; (f_local_get (v_frame)); (f_local_get (v_outer)); [(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x8)]; (f_local_get (v_frame)); [(Base.W32 0x41); (Base.W32 0x0); (Base.W32 0x36); (Base.W32 0x2); (Base.W32 0xc); (Base.W32 0xb)]]))))], (Base.nat_add 3 v_slot)))))
and (* wasm.bend:780 *)
f_complete_provider : int -> t_Code =
fun v_slot ->
(let v_frame = (Base.nat_add 1 v_slot) in
(let v_result = (Base.nat_add 2 v_slot) in
(let v_tuple = (Base.nat_add 3 v_slot) in
(Code ([(Bytes ((f_join ([((Base.W32 0x21) :: (f_unsigned_leb (v_result))); (f_local_get (v_slot)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x0)]; (f_i32_constant ((Base.W32 0xffffffff))); [(Base.W32 0x46); (Base.W32 0x4); (Base.W32 0x7f)]; (f_i32_constant ((Base.W32 0x8)))])))); Allocate; (Bytes ((f_join ([((Base.W32 0x22) :: (f_unsigned_leb (v_tuple))); (f_local_get (v_frame)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x4); (Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x0); (Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x0)]; (f_local_get (v_tuple)); (f_local_get (v_result)); [(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x4)]; (f_local_get (v_tuple)); [(Base.W32 0x5)]; (f_local_get (v_result)); [(Base.W32 0xb)]]))))], (Base.nat_add 4 v_slot))))))
and (* wasm.bend:793 *)
f_invoke_operation : M.t_TypeId -> t_Code -> int -> int -> t_Code =
fun v_identity v_argument v_slot v_provider ->
(let (Code (v_fragments, v_locals)) = v_argument in
(let v_handler = (Base.nat_add 1 v_slot) in
(let v_value = (Base.nat_add 2 v_slot) in
(Code ((f_fragments_join ([v_fragments; [(Bytes ((f_join ([((Base.W32 0x21) :: (f_unsigned_leb (v_value))); (f_local_get (v_provider)); ((Base.W32 0x21) :: (f_unsigned_leb (v_slot))); [(Base.W32 0x2); (Base.W32 0x40); (Base.W32 0x3); (Base.W32 0x40)]; (f_local_get (v_slot)); [(Base.W32 0x45); (Base.W32 0x4); (Base.W32 0x40); (Base.W32 0x0); (Base.W32 0xb)]; (f_local_get (v_slot)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x0)]])))); (OperationIndex (v_identity)); (Bytes ((f_join ([[(Base.W32 0x46); (Base.W32 0xd); (Base.W32 0x1)]; (f_local_get (v_slot)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x8)]; ((Base.W32 0x21) :: (f_unsigned_leb (v_slot))); [(Base.W32 0xc); (Base.W32 0x0); (Base.W32 0xb); (Base.W32 0xb)]; (f_local_get (v_slot)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0xc); (Base.W32 0x45); (Base.W32 0x4); (Base.W32 0x7f)]; (f_local_get (v_slot)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x4)]; ((Base.W32 0x22) :: (f_unsigned_leb (v_handler))); (f_local_get (v_value)); (f_local_get (v_slot)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x8)]; (f_local_get (v_handler)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x0); (Base.W32 0x11); (Base.W32 0x0); (Base.W32 0x0); (Base.W32 0x5)]; (f_local_get (v_slot)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0xc); (Base.W32 0x41); (Base.W32 0x1); (Base.W32 0x46); (Base.W32 0x4); (Base.W32 0x7f)]; (f_local_get (v_slot)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x4); (Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x0); (Base.W32 0x5)]; (f_local_get (v_slot)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x4)]; (f_local_get (v_value)); [(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x0); (Base.W32 0x41); (Base.W32 0x0); (Base.W32 0xb); (Base.W32 0xb)]]))))]])), (Base.nat_max (v_locals) ((Base.nat_add 3 v_slot))))))))
and (* wasm.bend:811 *)
f_constructor_tag : E.t_ConstructorSlot -> int =
fun v_variant ->
(let (E.ConstructorSlot (v_name, v_tag, v_payload)) = v_variant in
v_tag)
and (* wasm.bend:815 *)
f_lambda_captures : F.t_Lambda -> (Base.text) list =
fun v_lambda ->
(let (F.Lambda (v_identity, v_parameter, v_body, v_captures)) = v_lambda in
v_captures)
and (* wasm.bend:819 *)
f_pattern_test_work : int -> t_PatternTestWork -> (t_Local) list -> (M.t_Diagnostic, (t_Fragment) list) Base.result_ =
fun v_fuel v_work v_locals ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_12, s_13, s_21))))
| (__nat_12, (PatternTest (M.WildcardPattern, v_location))) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(Done ([(Bytes ([(Base.W32 0x41); (Base.W32 0x1)]))])))
| (__nat_13, (PatternTest ((M.BindingPattern (v_name)), v_location))) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(Done ([(Bytes ([(Base.W32 0x41); (Base.W32 0x1)]))])))
| (__nat_14, (PatternTest ((M.ValuePattern ((M.LocalReference (v_name)))), v_location))) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(match (f_lookup_local (v_locals) (v_name)) with
| Fail __error -> Fail __error
| Done v_expected ->
(Done ([(Bytes ((f_join ([(f_read_location (v_location)); (f_read_location (v_expected)); [(Base.W32 0x46)]]))))]))))
| (__nat_15, (PatternTest ((M.ValuePattern ((M.ConstantReference (v_name)))), v_location))) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(Done ([(Bytes ((f_read_location (v_location)))); (ConstantReference (v_name)); (Bytes ([(Base.W32 0x46)]))])))
| (__nat_16, (PatternTest (M.UnitPattern, v_location))) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(Done ([(Bytes ([(Base.W32 0x41); (Base.W32 0x1)]))])))
| (__nat_17, (PatternTest ((M.U32Pattern (v_value)), v_location))) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(Done ([(Bytes ((f_join ([(f_read_location (v_location)); (f_i32_constant (v_value)); [(Base.W32 0x46)]]))))])))
| (__nat_18, (PatternTest ((M.BoolPattern (v_value)), v_location))) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
(Done ([(Bytes ((f_join ([(f_read_location (v_location)); [(Base.W32 0x41); (Base.bool_pick (v_value) ((Base.W32 0x1)) ((Base.W32 0x0))); (Base.W32 0x46)]]))))])))
| (__nat_19, (PatternTest ((M.ConstructorPattern (v_constructor, None)), v_location))) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
(Done ([(Bytes ((f_concat ((f_read_location (v_location))) ([(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x0)])))); (ConstructorIndex (v_constructor)); (Bytes ([(Base.W32 0x46)]))])))
| (__nat_20, (PatternTest ((M.ConstructorPattern (v_constructor, (Some (v_payload)))), v_location))) when __nat_20 >= 1 ->
(let v_rest = (__nat_20 - 1) in
(match (f_pattern_test_work (v_rest) ((PatternTest (v_payload, (f_field_location (v_location) (4))))) (v_locals)) with
| Fail __error -> Fail __error
| Done v_nested ->
(Done ((f_fragments_join ([[(Bytes ((f_concat ((f_read_location (v_location))) ([(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x0)])))); (ConstructorIndex (v_constructor)); (Bytes ([(Base.W32 0x46); (Base.W32 0x4); (Base.W32 0x7f)]))]; v_nested; [(Bytes ([(Base.W32 0x5); (Base.W32 0x41); (Base.W32 0x0); (Base.W32 0xb)]))]]))))))
| (__nat_21, (PatternTest ((M.ProductPattern (v_elements)), v_location))) when __nat_21 >= 1 ->
(let v_rest = (__nat_21 - 1) in
(match (f_product_arity ((Base.list_length (v_elements)))) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_pattern_test_work (v_rest) ((ProductTests (v_elements, v_location, 0, [(Bytes ([(Base.W32 0x2); (Base.W32 0x7f)]))]))) (v_locals))))
| (__nat_22, (ProductTests ([], v_location, v_offset, v_reversed))) when __nat_22 >= 1 ->
(let v_rest = (__nat_22 - 1) in
(Done ((Base.list_reverse_go (v_reversed) ([(Bytes ([(Base.W32 0x41); (Base.W32 0x1); (Base.W32 0xb)]))])))))
| (__nat_23, (ProductTests ((v_head :: v_tail), v_location, v_offset, v_reversed))) when __nat_23 >= 1 ->
(let v_rest = (__nat_23 - 1) in
(match (f_pattern_test_work (v_rest) ((PatternTest (v_head, (f_field_location (v_location) (v_offset))))) (v_locals)) with
| Fail __error -> Fail __error
| Done v_test ->
(f_pattern_test_work (v_rest) ((ProductTests (v_tail, v_location, (Base.nat_add 4 v_offset), ((Bytes ([(Base.W32 0x45); (Base.W32 0xd); (Base.W32 0x0); (Base.W32 0x1a)])) :: (Base.list_reverse_go (v_test) (((Bytes ([(Base.W32 0x41); (Base.W32 0x0)])) :: v_reversed))))))) (v_locals))))
| (__nat_24, (RowTests ([], v_first))) when __nat_24 >= 1 ->
(let v_rest = (__nat_24 - 1) in
(Done ([(Bytes ([(Base.W32 0x41); (Base.W32 0x1)]))])))
| (__nat_25, (RowTests ((v_head :: v_tail), v_first))) when __nat_25 >= 1 ->
(let v_rest = (__nat_25 - 1) in
(match (f_pattern_test_work (v_rest) ((PatternTest (v_head, (Location (v_first, []))))) (v_locals)) with
| Fail __error -> Fail __error
| Done v_test ->
(match (f_pattern_test_work (v_rest) ((RowTests (v_tail, (Base.nat_add 1 v_first)))) (v_locals)) with
| Fail __error -> Fail __error
| Done v_remaining ->
(Done ((f_fragments_join ([v_test; [(Bytes ([(Base.W32 0x4); (Base.W32 0x7f)]))]; v_remaining; [(Bytes ([(Base.W32 0x5); (Base.W32 0x41); (Base.W32 0x0); (Base.W32 0xb)]))]]))))))))
and (* wasm.bend:865 *)
f_next_scrutinee : (I.t_Expr) list -> int -> t_Code -> (t_Fragment) list -> int -> t_Emission =
fun v_values v_first v_compiled v_reversed v_locals ->
(let (Code (v_fragments, v_used)) = v_compiled in
(ScrutineesWork (v_values, (Base.nat_add 1 v_first), ((Bytes (((Base.W32 0x21) :: (f_unsigned_leb (v_first))))) :: (Base.list_reverse_go (v_fragments) (v_reversed))), (Base.nat_max ((Base.nat_max (v_locals) (v_used))) ((Base.nat_add 1 v_first))))))
and (* wasm.bend:873 *)
f_forever_compaction : bool -> int -> int -> int -> t_Code =
fun v_enabled v_state_slot v_floor_slot v_scratch_slot ->
(Base.bool_pick (v_enabled) ((Code ([(Bytes ((f_join ([(f_local_get (v_scratch_slot)); [(Base.W32 0x41); (Base.W32 0x1); (Base.W32 0x6a)]; ((Base.W32 0x22) :: (f_unsigned_leb (v_scratch_slot))); [(Base.W32 0x41); (Base.W32 0x3); (Base.W32 0x71); (Base.W32 0x45); (Base.W32 0x4); (Base.W32 0x40)]; (f_local_get (v_state_slot)); (f_local_get (v_floor_slot)); [(Base.W32 0x41); (Base.W32 0x0)]])))); Collect; (Bytes ((f_join ([((Base.W32 0x21) :: (f_unsigned_leb (v_state_slot))); [(Base.W32 0xb)]]))))], (Base.nat_add 1 v_scratch_slot)))) ((f_byte_code ([]) (0))))
and (* wasm.bend:880 *)
f_emit_expr : int -> t_Emission -> t_Context -> (M.t_Diagnostic, t_Code) Base.result_ =
fun v_fuel v_work v_context ->
(match v_fuel with
| 0 ->
(Fail ((M.Diagnostic (s_12, s_22, s_23))))
| __nat_26 when __nat_26 >= 1 ->
(let v_rest = (__nat_26 - 1) in
(match v_work with
| (ExpressionWork (I.UnitExpr)) ->
(Done ((f_byte_code ([(Base.W32 0x41); (Base.W32 0x0)]) (0))))
| (ExpressionWork ((I.U32Expr (v_value)))) ->
(Done ((f_byte_code ((f_i32_constant (v_value))) (0))))
| (ExpressionWork ((I.F32Expr (v_value)))) ->
(Done ((f_byte_code ((f_i32_constant ((Base.f32_bits (v_value))))) (0))))
| (ExpressionWork ((I.BoolExpr (v_value)))) ->
(Done ((f_byte_code ([(Base.W32 0x41); (Base.bool_pick (v_value) ((Base.W32 0x1)) ((Base.W32 0x0)))]) (0))))
| (ExpressionWork ((I.LocalExpr (v_name)))) ->
(match (f_lookup_local ((f_context_locals (v_context))) (v_name)) with
| Fail __error -> Fail __error
| Done v_location ->
(Done ((f_byte_code ((f_read_location (v_location))) (0)))))
| (ExpressionWork ((I.ConstantExpr (v_name)))) ->
(Done ((Code ([(ConstantReference (v_name))], 0))))
| (ExpressionWork ((I.ClosureExpr (v_key, v_captures)))) ->
(f_closure_code (v_key) (v_captures) (v_context))
| (ExpressionWork ((I.PanicExpr (v_message)))) ->
(Done ((f_byte_code ([(Base.W32 0x0)]) (0))))
| (ExpressionWork ((I.ProductExpr (v_elements)))) ->
(let v_first = (f_context_next (v_context)) in
(let v_count = (Base.list_length (v_elements)) in
(match (f_product_arity (v_count)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_emit_expr (v_rest) ((ScrutineesWork (v_elements, v_first, [], 0))) ((f_reserve (v_context) ((Base.nat_add 1 v_count))))) with
| Fail __error -> Fail __error
| Done v_values ->
(Done ((f_product_code (v_values) (v_count) (v_first))))))))
| (ExpressionWork ((I.ProjectExpr (v_value, v_index)))) ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_value))) (v_context)) with
| Fail __error -> Fail __error
| Done v_compiled ->
(match (f_projection_code ((Base.nat_is_lt (v_index) ((Base.u32_to_nat ((Base.W32 0x400000)))))) (v_index)) with
| Fail __error -> Fail __error
| Done v_access ->
(Done ((f_append_code (v_compiled) (v_access) ([]) ([]))))))
| (ExpressionWork ((I.ArrayExpr (v_elements)))) ->
(let v_first = (f_context_next (v_context)) in
(let v_count = (Base.list_length (v_elements)) in
(match (f_array_size (v_count)) with
| Fail __error -> Fail __error
| Done v_size ->
(match (f_emit_expr (v_rest) ((ScrutineesWork (v_elements, v_first, [], 0))) ((f_reserve (v_context) ((Base.nat_add 1 v_count))))) with
| Fail __error -> Fail __error
| Done v_values ->
(Done ((f_array_code (v_values) (v_count) (v_size) (v_first))))))))
| (ExpressionWork ((I.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body)))) ->
(let v_first = (f_context_next (v_context)) in
(let v_nested = (f_control ((f_control ((f_bind ((f_bind ((f_reserve (v_context) (3))) (v_index) ((Location (v_first, []))))) (v_state) ((Location ((Base.nat_add 2 v_first), []))))) (None))) (None)) in
(match (f_emit_expr (v_rest) ((ScrutineesWork ([v_start; v_end; v_initial], v_first, [], 0))) ((f_reserve (v_context) (3)))) with
| Fail __error -> Fail __error
| Done v_operands ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_body))) (v_nested)) with
| Fail __error -> Fail __error
| Done v_iteration ->
(Done ((f_require_locals ((f_append_code (v_operands) (v_iteration) ((f_join ([[(Base.W32 0x2); (Base.W32 0x40); (Base.W32 0x3); (Base.W32 0x40)]; (f_local_get (v_first)); (f_local_get ((Base.nat_add 1 v_first))); [(Base.W32 0x4f); (Base.W32 0xd); (Base.W32 0x1)]]))) ((f_join ([((Base.W32 0x21) :: (f_unsigned_leb ((Base.nat_add 2 v_first)))); (f_local_get (v_first)); [(Base.W32 0x41); (Base.W32 0x1); (Base.W32 0x6a)]; ((Base.W32 0x21) :: (f_unsigned_leb (v_first))); [(Base.W32 0xc); (Base.W32 0x0); (Base.W32 0xb); (Base.W32 0xb)]; (f_local_get ((Base.nat_add 2 v_first)))]))))) ((Base.nat_add 3 v_first)))))))))
| (ExpressionWork ((I.ForeverExpr (v_state, v_initial, v_body, v_compact)))) ->
(let v_first = (f_context_next (v_context)) in
(let v_nested = (f_control ((f_control ((f_bind ((f_reserve (v_context) (3))) (v_state) ((Location (v_first, []))))) (None))) (None)) in
(match (f_emit_expr (v_rest) ((ScrutineesWork ([v_initial], v_first, [], 0))) ((f_reserve (v_context) (3)))) with
| Fail __error -> Fail __error
| Done v_prepared ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_body))) (v_nested)) with
| Fail __error -> Fail __error
| Done v_iteration ->
(Done ((f_require_locals ((f_append_code ((f_append_code (v_prepared) (v_iteration) ((f_join ([[(Base.W32 0x23); (Base.W32 0x0)]; ((Base.W32 0x21) :: (f_unsigned_leb ((Base.nat_add 1 v_first)))); [(Base.W32 0x41); (Base.W32 0x0)]; ((Base.W32 0x21) :: (f_unsigned_leb ((Base.nat_add 2 v_first)))); [(Base.W32 0x2); (Base.W32 0x40); (Base.W32 0x3); (Base.W32 0x40)]]))) (((Base.W32 0x21) :: (f_unsigned_leb (v_first)))))) ((f_forever_compaction (v_compact) (v_first) ((Base.nat_add 1 v_first)) ((Base.nat_add 2 v_first)))) ([]) ((f_join ([[(Base.W32 0xc); (Base.W32 0x0); (Base.W32 0xb); (Base.W32 0xb)]; (f_local_get (v_first))]))))) ((Base.nat_add 3 v_first)))))))))
| (ExpressionWork ((I.ArrayGenerateExpr (v_count, v_generator)))) ->
(let v_first = (f_context_next (v_context)) in
(match (f_emit_expr (v_rest) ((ScrutineesWork ([v_count; v_generator], v_first, [], 0))) ((f_reserve (v_context) (4)))) with
| Fail __error -> Fail __error
| Done v_operands ->
(Done ((f_append_code (v_operands) ((f_array_generate_code (v_first) ((f_context_provider (v_context))))) ([]) ([]))))))
| (ExpressionWork ((I.ArrayFillExpr (v_count, v_value)))) ->
(let v_first = (f_context_next (v_context)) in
(match (f_emit_expr (v_rest) ((ScrutineesWork ([v_count; v_value], v_first, [], 0))) ((f_reserve (v_context) (4)))) with
| Fail __error -> Fail __error
| Done v_operands ->
(Done ((f_append_code (v_operands) ((f_array_fill_code (v_first))) ([]) ([]))))))
| (ExpressionWork ((I.ArrayGetExpr (v_array, v_index)))) ->
(let v_first = (f_context_next (v_context)) in
(match (f_emit_expr (v_rest) ((ScrutineesWork ([v_array; v_index], v_first, [], 0))) ((f_reserve (v_context) (2)))) with
| Fail __error -> Fail __error
| Done v_operands ->
(Done ((f_append_code (v_operands) ((f_array_get_code (v_first))) ([]) ([]))))))
| (ExpressionWork ((I.ArraySetExpr (v_array, v_index, v_value)))) ->
(let v_first = (f_context_next (v_context)) in
(match (f_emit_expr (v_rest) ((ScrutineesWork ([v_array; v_index; v_value], v_first, [], 0))) ((f_reserve (v_context) (5)))) with
| Fail __error -> Fail __error
| Done v_operands ->
(Done ((f_append_code (v_operands) ((f_array_set_code (v_first))) ([]) ([]))))))
| (ExpressionWork ((I.ArrayReuseExpr (v_array, v_index, v_value)))) ->
(let v_first = (f_context_next (v_context)) in
(match (f_emit_expr (v_rest) ((ScrutineesWork ([v_array; v_index; v_value], v_first, [], 0))) ((f_reserve (v_context) (3)))) with
| Fail __error -> Fail __error
| Done v_operands ->
(Done ((f_append_code (v_operands) ((f_array_reuse_code (v_first))) ([]) ([]))))))
| (ExpressionWork ((I.ArrayLengthExpr (v_array)))) ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_array))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_append_code (v_value) ((f_byte_code ([(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x0)]) (0))) ([]) ([])))))
| (ExpressionWork ((I.StateProviderExpr (v_read, v_write, v_initial)))) ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_initial))) ((f_reserve (v_context) (2)))) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_state_provider_code (v_read) (v_write) (v_value) ((f_context_next (v_context)))))))
| (ExpressionWork ((I.ProviderExpr (v_identity, v_implementation)))) ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_implementation))) ((f_reserve (v_context) (2)))) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_construct_code ((OperationIndex (v_identity))) (v_value) ((f_context_next (v_context)))))))
| (ExpressionWork ((I.HandleExpr (v_provider, v_body)))) ->
(let v_slot = (f_context_next (v_context)) in
(match (f_emit_expr (v_rest) ((ExpressionWork (v_provider))) ((f_reserve (v_context) (4)))) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_body))) ((f_with_provider ((f_reserve (v_context) (4))) ((Base.nat_add 1 v_slot))))) with
| Fail __error -> Fail __error
| Done v_scoped ->
(Done ((f_append_code ((f_append_code ((f_append_code (v_value) ((f_install_provider (v_slot) ((f_context_provider (v_context))))) ([]) ([]))) (v_scoped) ([]) ([]))) ((f_complete_provider (v_slot))) ([]) ([])))))))
| (ExpressionWork ((I.InvokeOperationExpr (v_identity, v_argument)))) ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_argument))) ((f_reserve (v_context) (3)))) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_invoke_operation (v_identity) (v_value) ((f_context_next (v_context))) ((f_context_provider (v_context)))))))
| (ExpressionWork ((I.ConstructExpr (v_constructor, None)))) ->
(Done ((f_construct_code ((ConstructorIndex (v_constructor))) ((f_byte_code ([(Base.W32 0x41); (Base.W32 0x0)]) (0))) ((f_context_next (v_context))))))
| (ExpressionWork ((I.ConstructExpr (v_constructor, (Some (v_payload)))))) ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_payload))) ((f_reserve (v_context) (2)))) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_construct_code ((ConstructorIndex (v_constructor))) (v_value) ((f_context_next (v_context)))))))
| (ExpressionWork ((I.ApplyExpr (v_callee, v_argument)))) ->
(let v_slot = (f_context_next (v_context)) in
(match (f_emit_expr (v_rest) ((ExpressionWork (v_callee))) ((f_reserve (v_context) (1)))) with
| Fail __error -> Fail __error
| Done v_function ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_argument))) ((f_reserve (v_context) (1)))) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_require_locals ((f_append_code (v_function) (v_value) ((f_join ([((Base.W32 0x21) :: (f_unsigned_leb (v_slot))); (f_local_get (v_slot))]))) ((f_join ([(f_local_get ((f_context_provider (v_context)))); (f_local_get (v_slot)); [(Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x0); (Base.W32 0x11); (Base.W32 0x0); (Base.W32 0x0)]]))))) ((Base.nat_add 1 v_slot))))))))
| (ExpressionWork ((I.CallExpr (v_key, v_argument)))) ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_argument))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_append_code ((f_append_code ((f_byte_code ([(Base.W32 0x41); (Base.W32 0x0)]) (0))) (v_value) ([]) ([]))) ((Code ([(NamedCall (v_key))], 0))) ((f_local_get ((f_context_provider (v_context))))) ([])))))
| (ExpressionWork ((I.ScalarExpr (v_operator, v_left, v_right)))) ->
(let v_a = (f_emit_expr (v_rest) ((ExpressionWork (v_left))) (v_context)) in
(let v_b = (f_emit_expr (v_rest) ((ExpressionWork (v_right))) (v_context)) in
(f_scalar_code (v_a) (v_b) (v_operator))))
| (ExpressionWork ((I.UnaryExpr (v_operator, v_value)))) ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_value))) (v_context)) with
| Fail __error -> Fail __error
| Done v_compiled ->
(Done ((f_append_code (v_compiled) ((f_byte_code ((f_join ([(f_scalar_from_word ((M.f_unary_parameter (v_operator)))); (f_unary_opcode (v_operator)); (f_scalar_to_word ((M.f_unary_result (v_operator))))]))) (0))) ([]) ([])))))
| (ExpressionWork ((I.LetExpr (v_name, v_value, v_body)))) ->
(let v_slot = (f_context_next (v_context)) in
(match (f_emit_expr (v_rest) ((ExpressionWork (v_value))) (v_context)) with
| Fail __error -> Fail __error
| Done v_v ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_body))) ((f_bind ((f_reserve (v_context) (1))) (v_name) ((Location (v_slot, [])))))) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_require_locals ((f_append_code (v_v) (v_b) (((Base.W32 0x21) :: (f_unsigned_leb (v_slot)))) ([]))) ((Base.nat_add 1 v_slot))))))))
| (ExpressionWork ((I.IfExpr (v_condition, v_consequent, v_alternative)))) ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_condition))) (v_context)) with
| Fail __error -> Fail __error
| Done v_c ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_consequent))) ((f_control (v_context) (None)))) with
| Fail __error -> Fail __error
| Done v_y ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_alternative))) ((f_control (v_context) (None)))) with
| Fail __error -> Fail __error
| Done v_n ->
(Done ((f_append_code (v_c) ((f_append_code (v_y) (v_n) ([(Base.W32 0x5)]) ([(Base.W32 0xb)]))) ([(Base.W32 0x4); (Base.W32 0x7f)]) ([])))))))
| (ExpressionWork ((I.SequenceExpr (v_first, v_next)))) ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_first))) (v_context)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_next))) (v_context)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_append_code (v_a) (v_b) ([(Base.W32 0x1a)]) ([]))))))
| (ExpressionWork ((I.MatchExpr (v_values, v_arms)))) ->
(let v_slot = (f_context_next (v_context)) in
(let v_count = (Base.list_length (v_values)) in
(match (f_emit_expr (v_rest) ((ScrutineesWork (v_values, v_slot, [], 0))) ((f_reserve (v_context) (v_count)))) with
| Fail __error -> Fail __error
| Done v_v ->
(match (f_emit_expr (v_rest) ((ArmsWork (v_arms, v_slot))) ((f_reserve (v_context) (v_count)))) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_require_locals ((f_append_code (v_v) (v_b) ([]) ([]))) ((Base.nat_add (v_slot) (v_count))))))))))
| (ExpressionWork ((I.GuardExpr (v_pattern, v_value, v_alternative, v_body)))) ->
(let v_slot = (f_context_next (v_context)) in
(let v_nested = (f_control ((f_reserve (v_context) (1))) (None)) in
(match (f_emit_expr (v_rest) ((ExpressionWork (v_value))) ((f_reserve (v_context) (1)))) with
| Fail __error -> Fail __error
| Done v_v ->
(match (f_pattern_test_work (v_rest) ((PatternTest (v_pattern, (Location (v_slot, []))))) ((f_context_locals (v_context)))) with
| Fail __error -> Fail __error
| Done v_test ->
(match (f_pattern_bindings_work (v_rest) ((OnePattern (v_pattern, (Location (v_slot, []))))) (v_nested)) with
| Fail __error -> Fail __error
| Done v_bound ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_body))) (v_bound)) with
| Fail __error -> Fail __error
| Done v_yes ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_alternative))) (v_nested)) with
| Fail __error -> Fail __error
| Done v_no ->
(Done ((f_require_locals ((f_append_code ((f_append_code (v_v) ((Code (v_test, 0))) (((Base.W32 0x21) :: (f_unsigned_leb (v_slot)))) ([]))) ((f_append_code (v_yes) (v_no) ([(Base.W32 0x5)]) ([(Base.W32 0xb)]))) ([(Base.W32 0x4); (Base.W32 0x7f)]) ([]))) ((Base.nat_add 1 v_slot))))))))))))
| (ExpressionWork ((I.BlockExpr (v_label, v_body)))) ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_body))) ((f_control (v_context) ((Some (v_label)))))) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_append_code ((f_byte_code ([(Base.W32 0x2); (Base.W32 0x7f)]) (0))) (v_value) ([]) ([(Base.W32 0xb)])))))
| (ExpressionWork ((I.ReturnExpr (v_label, v_value)))) ->
(match (f_return_depth (v_context) (v_label)) with
| Fail __error -> Fail __error
| Done v_depth ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_value))) (v_context)) with
| Fail __error -> Fail __error
| Done v_v ->
(Done ((f_append_code (v_v) ((f_byte_code (((Base.W32 0xc) :: (f_unsigned_leb (v_depth)))) (0))) ([]) ([]))))))
| (ScrutineesWork ([], v_first, v_reversed, v_locals)) ->
(Done ((Code ((Base.list_reverse (v_reversed)), v_locals))))
| (ScrutineesWork ((v_head :: v_tail), v_first, v_reversed, v_locals)) ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_head))) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(f_emit_expr (v_rest) ((f_next_scrutinee (v_tail) (v_first) (v_value) (v_reversed) (v_locals))) (v_context)))
| (ArmsWork ([], v_first)) ->
(Done ((f_byte_code ([(Base.W32 0x0)]) (0))))
| (ArmsWork (((M.MatchArm (v_patterns, v_body)) :: v_tail), v_first)) ->
(let v_nested = (f_control (v_context) (None)) in
(match (f_pattern_test_work (v_rest) ((RowTests (v_patterns, v_first))) ((f_context_locals (v_context)))) with
| Fail __error -> Fail __error
| Done v_test ->
(match (f_pattern_bindings_work (v_rest) ((RowPatterns (v_patterns, v_first))) (v_nested)) with
| Fail __error -> Fail __error
| Done v_bound ->
(match (f_emit_expr (v_rest) ((ExpressionWork (v_body))) (v_bound)) with
| Fail __error -> Fail __error
| Done v_yes ->
(match (f_emit_expr (v_rest) ((ArmsWork (v_tail, v_first))) (v_nested)) with
| Fail __error -> Fail __error
| Done v_no ->
(Done ((f_append_code ((Code (v_test, 0))) ((f_append_code (v_yes) (v_no) ([(Base.W32 0x5)]) ([(Base.W32 0xb)]))) ([(Base.W32 0x4); (Base.W32 0x7f)]) ([]))))))))))))
and (* wasm.bend:1068 *)
f_word_bytes : Base.word32 -> (Base.word32) list =
fun v_word ->
[(Base.u32_and (v_word) ((Base.W32 0xff))); (Base.u32_and ((Base.u32_shrn (v_word) (8))) ((Base.W32 0xff))); (Base.u32_and ((Base.u32_shrn (v_word) (16))) ((Base.W32 0xff))); (Base.u32_shrn (v_word) (24))]
and (* wasm.bend:1071 *)
f_words_bytes : (Base.word32) list -> (Base.word32) list =
fun v_words ->
(match v_words with
| [] ->
[]
| (v_head :: v_tail) ->
(f_concat ((f_word_bytes (v_head))) ((f_words_bytes (v_tail)))))
and (* wasm.bend:1078 *)
f_heap_allocate : (Base.word32) list -> t_Heap -> (M.t_Diagnostic, t_Serialized) Base.result_ =
fun v_words v_heap ->
(let (Heap (v_next, v_chunks)) = v_heap in
(let v_end = (Base.nat_add (v_next) ((Base.nat_mul (4) ((Base.list_length (v_words)))))) in
(Base.bool_pick ((Base.nat_is_le (v_end) ((Base.u32_to_nat ((Base.W32 0x1000000)))))) ((Done ((Serialized ([(Base.u32_from_nat (v_next))], (Heap (v_end, ((f_words_bytes (v_words)) :: v_chunks)))))))) ((Fail ((M.Diagnostic (s_12, s_24, s_25))))))))
and (* wasm.bend:1083 *)
f_capture_values : (Base.text) list -> ((C.t_Value) C.t_Binding) list -> (M.t_Diagnostic, (C.t_Value) list) Base.result_ =
fun v_names v_environment ->
(match v_names with
| [] ->
(Done ([]))
| (v_name :: v_tail) ->
(match (C.f_lookup_local (v_environment) (v_name)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_capture_values (v_tail) (v_environment)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_value :: v_rest))))))
and (* wasm.bend:1093 *)
f_only_word : (Base.word32) list -> (M.t_Diagnostic, Base.word32) Base.result_ =
fun v_words ->
(match v_words with
| (v_word :: []) ->
(Done (v_word))
| _ ->
(Fail ((M.Diagnostic (s_0, s_24, s_26)))))
and (* wasm.bend:1100 *)
f_serialized_words : t_Serialized -> (Base.word32) list =
fun v_encoded ->
(let (Serialized (v_words, v_heap)) = v_encoded in
v_words)
and (* wasm.bend:1104 *)
f_serialized_heap : t_Serialized -> t_Heap =
fun v_encoded ->
(let (Serialized (v_words, v_heap)) = v_encoded in
v_heap)
and (* wasm.bend:1108 *)
f_static_slots : t_StaticConstants -> (t_Slot) list =
fun v_encoded ->
(let (StaticConstants (v_slots, v_heap)) = v_encoded in
v_slots)
and (* wasm.bend:1112 *)
f_static_heap : t_StaticConstants -> t_Heap =
fun v_encoded ->
(let (StaticConstants (v_slots, v_heap)) = v_encoded in
v_heap)
and (* wasm.bend:1116 *)
f_heap_end : t_Heap -> int =
fun v_heap ->
(let (Heap (v_next, v_chunks)) = v_heap in
v_next)
and (* wasm.bend:1120 *)
f_serialize : int -> t_Serialization -> t_StaticCatalog -> t_Heap -> (M.t_Diagnostic, t_Serialized) Base.result_ =
fun v_fuel v_work v_catalog v_heap ->
(match v_fuel with
| 0 ->
(Fail ((M.Diagnostic (s_12, s_24, s_27))))
| __nat_27 when __nat_27 >= 1 ->
(let v_rest = (__nat_27 - 1) in
(match v_work with
| (ValueWork (C.UnitValue)) ->
(Done ((Serialized ([(Base.W32 0x0)], v_heap))))
| (ValueWork ((C.U32Value (v_value)))) ->
(Done ((Serialized ([v_value], v_heap))))
| (ValueWork ((C.F32Value (v_value)))) ->
(Done ((Serialized ([(Base.f32_bits (v_value))], v_heap))))
| (ValueWork ((C.ProductValue (v_elements)))) ->
(match (f_product_arity ((Base.list_length (v_elements)))) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_serialize (v_rest) ((ValuesWork (v_elements))) (v_catalog) (v_heap)) with
| Fail __error -> Fail __error
| Done v_encoded ->
(f_heap_allocate ((f_serialized_words (v_encoded))) ((f_serialized_heap (v_encoded))))))
| (ValueWork ((C.ArrayValue (v_elements)))) ->
(let v_count = (Base.list_length (v_elements)) in
(match (f_array_size (v_count)) with
| Fail __error -> Fail __error
| Done v_size ->
(match (f_serialize (v_rest) ((ValuesWork (v_elements))) (v_catalog) (v_heap)) with
| Fail __error -> Fail __error
| Done v_encoded ->
(f_heap_allocate (((Base.u32_from_nat (v_count)) :: (f_serialized_words (v_encoded)))) ((f_serialized_heap (v_encoded)))))))
| (ValueWork ((C.OperationValue (v_identity)))) ->
(match (f_lookup_slot ((f_static_entries (v_catalog))) ((I.f_operation_key (v_identity)))) with
| Fail __error -> Fail __error
| Done v_index ->
(f_heap_allocate ([(Base.u32_from_nat (v_index))]) (v_heap)))
| (ValueWork ((C.StateProviderValue (v_read, v_write, v_initial)))) ->
(match (f_lookup_slot ((f_static_operations (v_catalog))) ((I.f_operation_key (v_read)))) with
| Fail __error -> Fail __error
| Done v_reader ->
(match (f_lookup_slot ((f_static_operations (v_catalog))) ((I.f_operation_key (v_write)))) with
| Fail __error -> Fail __error
| Done v_writer ->
(match (f_serialize (v_rest) ((ValueWork (v_initial))) (v_catalog) (v_heap)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_only_word ((f_serialized_words (v_value)))) with
| Fail __error -> Fail __error
| Done v_word ->
(f_heap_allocate ([(Base.W32 0xffffffff); (Base.u32_from_nat (v_reader)); (Base.u32_from_nat (v_writer)); v_word]) ((f_serialized_heap (v_value))))))))
| (ValueWork ((C.StateReadValue (v_slot)))) ->
(Fail ((M.Diagnostic (s_0, s_28, s_29))))
| (ValueWork ((C.StateWriteValue (v_slot)))) ->
(Fail ((M.Diagnostic (s_0, s_28, s_30))))
| (ValueWork ((C.ProviderValue (v_identity, v_implementation)))) ->
(match (f_lookup_slot ((f_static_operations (v_catalog))) ((I.f_operation_key (v_identity)))) with
| Fail __error -> Fail __error
| Done v_operation ->
(match (f_serialize (v_rest) ((ValueWork (v_implementation))) (v_catalog) (v_heap)) with
| Fail __error -> Fail __error
| Done v_handler ->
(match (f_only_word ((f_serialized_words (v_handler)))) with
| Fail __error -> Fail __error
| Done v_word ->
(f_heap_allocate ([(Base.u32_from_nat (v_operation)); v_word]) ((f_serialized_heap (v_handler)))))))
| (ValueWork ((C.EffectDescriptorValue (v_identity)))) ->
(Fail ((I.f_const_only ())))
| (ValueWork ((C.EffectSetValue (v_operations)))) ->
(Fail ((I.f_const_only ())))
| (ValueWork ((C.BoolValue (v_value)))) ->
(Done ((Serialized ([(Base.bool_pick (v_value) ((Base.W32 0x1)) ((Base.W32 0x0)))], v_heap))))
| (ValueWork ((C.FunctionValue (v_name)))) ->
(match (f_lookup_slot ((f_static_entries (v_catalog))) ((Base.string_append s_5 v_name))) with
| Fail __error -> Fail __error
| Done v_index ->
(match (f_heap_allocate ([(Base.u32_from_nat (v_index))]) (v_heap)) with
| Fail __error -> Fail __error
| Done v_result ->
(Done (v_result))))
| (ValueWork ((C.ConstructorFunctionValue (v_constructor)))) ->
(match (f_lookup_slot ((f_static_entries (v_catalog))) ((Base.string_append s_7 v_constructor))) with
| Fail __error -> Fail __error
| Done v_index ->
(match (f_heap_allocate ([(Base.u32_from_nat (v_index))]) (v_heap)) with
| Fail __error -> Fail __error
| Done v_result ->
(Done (v_result))))
| (ValueWork ((C.DataValue (v_constructor, None)))) ->
(match (f_lookup_constructor ((E.f_constructor_get ((I.f_metadata_constructors ((f_static_projection (v_catalog))))) (v_constructor))) (v_constructor)) with
| Fail __error -> Fail __error
| Done v_variant ->
(match (f_heap_allocate ([(Base.u32_from_nat ((f_constructor_tag (v_variant)))); (Base.W32 0x0)]) (v_heap)) with
| Fail __error -> Fail __error
| Done v_result ->
(Done (v_result))))
| (ValueWork ((C.DataValue (v_constructor, (Some (v_payload)))))) ->
(match (f_lookup_constructor ((E.f_constructor_get ((I.f_metadata_constructors ((f_static_projection (v_catalog))))) (v_constructor))) (v_constructor)) with
| Fail __error -> Fail __error
| Done v_variant ->
(match (f_serialize (v_rest) ((ValueWork (v_payload))) (v_catalog) (v_heap)) with
| Fail __error -> Fail __error
| Done v_child ->
(match (f_only_word ((f_serialized_words (v_child)))) with
| Fail __error -> Fail __error
| Done v_word ->
(match (f_heap_allocate ([(Base.u32_from_nat ((f_constructor_tag (v_variant)))); v_word]) ((f_serialized_heap (v_child)))) with
| Fail __error -> Fail __error
| Done v_result ->
(Done (v_result))))))
| (ValueWork ((C.ClosureValue (v_identity, v_parameter, v_body, v_environment)))) ->
(match (f_lookup_slot ((f_static_entries (v_catalog))) ((Base.string_append s_6 (Base.nat_show (v_identity))))) with
| Fail __error -> Fail __error
| Done v_index ->
(match (f_lookup_lambda ((I.f_lambda_get ((I.f_metadata_lambdas ((f_static_projection (v_catalog))))) (v_identity))) (v_identity)) with
| Fail __error -> Fail __error
| Done v_lambda ->
(match (f_capture_values ((f_lambda_captures (v_lambda))) (v_environment)) with
| Fail __error -> Fail __error
| Done v_values ->
(match (f_serialize (v_rest) ((ValuesWork (v_values))) (v_catalog) (v_heap)) with
| Fail __error -> Fail __error
| Done v_captured ->
(match (f_heap_allocate (((Base.u32_from_nat (v_index)) :: (f_serialized_words (v_captured)))) ((f_serialized_heap (v_captured)))) with
| Fail __error -> Fail __error
| Done v_result ->
(Done (v_result)))))))
| (ValueWork ((C.ReturnValue (v_label, v_value)))) ->
(Fail ((M.Diagnostic (s_0, s_24, s_31))))
| (ValueWork ((C.PatternBindingsValue (v_bindings)))) ->
(Fail ((M.Diagnostic (s_0, s_24, s_32))))
| (ValueWork ((C.MatchValuesValue (v_values)))) ->
(Fail ((M.Diagnostic (s_0, s_24, s_33))))
| (ValuesWork ([])) ->
(Done ((Serialized ([], v_heap))))
| (ValuesWork ((v_head :: v_tail))) ->
(match (f_serialize (v_rest) ((ValueWork (v_head))) (v_catalog) (v_heap)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_serialize (v_rest) ((ValuesWork (v_tail))) (v_catalog) ((f_serialized_heap (v_first)))) with
| Fail __error -> Fail __error
| Done v_remaining ->
(Done ((Serialized ((f_concat ((f_serialized_words (v_first))) ((f_serialized_words (v_remaining)))), (f_serialized_heap (v_remaining)))))))))))
and (* wasm.bend:1214 *)
f_serialize_constants : ((C.t_Value) C.t_Binding) list -> t_StaticCatalog -> t_Heap -> (M.t_Diagnostic, t_StaticConstants) Base.result_ =
fun v_constants v_catalog v_heap ->
(match v_constants with
| [] ->
(Done ((StaticConstants ([], v_heap))))
| ((C.Binding (v_name, v_value)) :: v_tail) ->
(match (f_serialize ((Base.u32_to_nat ((Base.W32 0x1000)))) ((ValueWork (v_value))) (v_catalog) (v_heap)) with
| Fail __error -> Fail __error
| Done v_encoded ->
(match (f_only_word ((f_serialized_words (v_encoded)))) with
| Fail __error -> Fail __error
| Done v_word ->
(match (f_serialize_constants (v_tail) (v_catalog) ((f_serialized_heap (v_encoded)))) with
| Fail __error -> Fail __error
| Done v_remaining ->
(Done ((StaticConstants (((Slot (v_name, (Base.u32_to_nat (v_word)))) :: (f_static_slots (v_remaining))), (f_static_heap (v_remaining))))))))))
and (* wasm.bend:1225 *)
f_scalar_type : M.t_Ty -> bool =
fun v_ty ->
(match v_ty with
| M.UnitTy ->
true
| M.U32Ty ->
true
| M.F32Ty ->
true
| M.BoolTy ->
true
| _ ->
false)
and (* wasm.bend:1238 *)
f_export_type : bool -> bool -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_exported v_supported v_name ->
(match (v_exported, v_supported) with
| (true, false) ->
(Fail ((M.Diagnostic (s_34, v_name, s_35))))
| (_, _) ->
(Done (())))
and (* wasm.bend:1245 *)
f_foreign_labels : (M.t_TypeId) list -> bool =
fun v_labels ->
(match v_labels with
| [] ->
true
| (v_identity :: v_tail) ->
(Base.bool_and ((M.f_is_foreign (v_identity))) ((f_foreign_labels (v_tail)))))
and (* wasm.bend:1252 *)
f_export_effects : M.t_EffectRow -> M.t_Ty -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_row v_parameter v_name ->
(match (v_row, v_parameter) with
| ((M.EffectRow ([], M.ClosedRow)), _) ->
(Done (()))
| ((M.EffectRow (v_labels, M.ClosedRow)), (M.FunctionTy (v_input, v_output, v_effects))) ->
(Base.bool_pick ((f_foreign_labels (v_labels))) ((Done (()))) ((Fail ((M.Diagnostic (s_36, v_name, s_37))))))
| ((M.EffectRow (v_labels, M.ClosedRow)), _) ->
(Fail ((M.Diagnostic (s_36, v_name, s_38))))
| (_, _) ->
(Fail ((M.Diagnostic (s_36, v_name, s_39)))))
and (* wasm.bend:1263 *)
f_abi_scalar : M.t_Ty -> Base.text -> (M.t_Diagnostic, t_AbiScalar) Base.result_ =
fun v_ty v_name ->
(match v_ty with
| M.UnitTy ->
(Done (UnitScalar))
| M.U32Ty ->
(Done (U32Scalar))
| M.BoolTy ->
(Done (BoolScalar))
| M.F32Ty ->
(Done (F32Scalar))
| _ ->
(Fail ((M.Diagnostic (s_34, v_name, s_40)))))
and (* wasm.bend:1276 *)
f_abi_value : M.t_Ty -> Base.text -> (M.t_Diagnostic, t_AbiValue) Base.result_ =
fun v_ty v_name ->
(match v_ty with
| (M.ArrayTy (M.U32Ty)) ->
(Done (U32ArrayValue))
| (M.ArrayTy (M.F32Ty)) ->
(Done (F32ArrayValue))
| v_scalar ->
(match (f_abi_scalar (v_scalar) (v_name)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((ScalarValue (v_value))))))
and (* wasm.bend:1287 *)
f_callback_effects : M.t_EffectRow -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_row v_name ->
(match v_row with
| (M.EffectRow ((v_identity :: []), M.ClosedRow)) ->
(Base.bool_pick ((M.f_is_foreign (v_identity))) ((Done (()))) ((Fail ((M.Diagnostic (s_34, v_name, s_41))))))
| _ ->
(Fail ((M.Diagnostic (s_34, v_name, s_41)))))
and (* wasm.bend:1294 *)
f_abi_parameter : M.t_Ty -> Base.text -> (M.t_Diagnostic, t_AbiParameter) Base.result_ =
fun v_ty v_name ->
(match v_ty with
| (M.FunctionTy (v_parameter, v_result, v_effects)) ->
(match (f_callback_effects (v_effects) (v_name)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_abi_value (v_parameter) (v_name)) with
| Fail __error -> Fail __error
| Done v_input ->
(match (f_abi_value (v_result) (v_name)) with
| Fail __error -> Fail __error
| Done v_output ->
(Done ((CallbackParameter ((Callback (v_input, v_output)))))))))
| v_scalar ->
(match (f_abi_value (v_scalar) (v_name)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((ValueParameter (v_value))))))
and (* wasm.bend:1307 *)
f_function_abi : M.t_Signature -> (M.t_Diagnostic, t_AbiFunction) Base.result_ =
fun v_signature ->
(let (M.Signature (v_name, v_parameter, v_result, v_variables, v_effects)) = v_signature in
(match (f_abi_parameter (v_parameter) (v_name)) with
| Fail __error -> Fail __error
| Done v_input ->
(match (f_abi_value (v_result) (v_name)) with
| Fail __error -> Fail __error
| Done v_output ->
(Done ((AbiFunction (v_name, v_input, v_output)))))))
and (* wasm.bend:1314 *)
f_check_signature : bool -> M.t_Signature -> (M.t_Diagnostic, unit) Base.result_ =
fun v_exported v_signature ->
(match v_exported with
| false ->
(Done (()))
| true ->
(let (M.Signature (v_name, v_parameter, v_result, v_variables, v_row)) = v_signature in
(match (f_export_effects (v_row) (v_parameter) (v_name)) with
| Fail __error -> Fail __error
| Done v_effects ->
(match (f_function_abi ((M.Signature (v_name, v_parameter, v_result, v_variables, (M.f_empty_row ()))))) with
| Fail __error -> Fail __error
| Done v_supported ->
(Done (()))))))
and (* wasm.bend:1325 *)
f_check_functions : (M.t_CheckedFunction) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_functions ->
(match v_functions with
| [] ->
(Done (()))
| ((M.CheckedFunction ((M.Function (v_name, v_exported, v_parameter, v_param_ann, v_result_ann, v_body)), v_signature, v_effects)) :: v_tail) ->
(match (f_check_signature (v_exported) (v_signature)) with
| Fail __error -> Fail __error
| Done v_supported ->
(f_check_functions (v_tail))))
and (* wasm.bend:1334 *)
f_exported_constants : (M.t_CheckedConstant) list -> (M.t_Diagnostic, (t_ExportedConstant) list) Base.result_ =
fun v_constants ->
(match v_constants with
| [] ->
(Done ([]))
| ((M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, v_value)), v_ty, v_variables)) :: v_tail) ->
(match (f_export_type (v_exported) ((f_scalar_type (v_ty))) (v_name)) with
| Fail __error -> Fail __error
| Done v_supported ->
(match (f_exported_constants (v_tail)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((Base.bool_pick (v_exported) (((ExportedConstant (v_name, v_ty)) :: v_rest)) (v_rest)))))))
and (* wasm.bend:1344 *)
f_capture_locals : (Base.text) list -> int -> (t_Local) list =
fun v_names v_offset ->
(match v_names with
| [] ->
[]
| (v_name :: v_tail) ->
(let v_at = v_offset in
((Local (v_name, (Location (0, [v_at])))) :: (f_capture_locals (v_tail) ((Base.nat_add 4 v_at))))))
and (* wasm.bend:1352 *)
f_body_bytes : (Base.word32) list -> int -> int -> (Base.word32) list =
fun v_bytes v_locals v_parameters ->
(let v_count = (Base.nat_sub (v_locals) (v_parameters)) in
(f_sized ((f_join ([(Base.bool_pick ((Base.nat_is_eq (v_count) (0))) ([(Base.W32 0x0)]) (((Base.W32 0x1) :: (f_concat ((f_unsigned_leb (v_count))) ([(Base.W32 0x7f)]))))); v_bytes; [(Base.W32 0xb)]])))))
and (* wasm.bend:1356 *)
f_body_plan : t_BytePlan -> int -> int -> t_BytePlan =
fun v_instructions v_locals v_parameters ->
(let v_count = (Base.nat_sub (v_locals) (v_parameters)) in
(let v_declarations = (Base.bool_pick ((Base.nat_is_eq (v_count) (0))) ([(Base.W32 0x0)]) (((Base.W32 0x1) :: (f_concat ((f_unsigned_leb (v_count))) ([(Base.W32 0x7f)]))))) in
(f_plan_sized ((f_plan_sequence ([(f_byte_plan (v_declarations)); v_instructions; (f_byte_plan ([(Base.W32 0xb)]))]))))))
and (* wasm.bend:1361 *)
f_compile_entry : t_CodegenJob -> (M.t_Diagnostic, t_EntryCode) Base.result_ =
fun v_job ->
(let (CodegenJob (v_key, v_parameter, v_body, v_captures)) = v_job in
(match (f_emit_expr ((Base.u32_to_nat ((Base.W32 0x4000)))) ((ExpressionWork (v_body))) ((Context (((Local (v_parameter, (Location (1, [])))) :: (f_capture_locals (v_captures) (4))), 3, [], 2)))) with
| Fail __error -> Fail __error
| Done v_compiled ->
(Done ((EntryCode (v_key, v_compiled))))))
and (* wasm.bend:1367 *)
f_merge_entries : (M.t_Diagnostic, (t_EntryCode) list) Base.result_ -> (M.t_Diagnostic, (t_EntryCode) list) Base.result_ -> (M.t_Diagnostic, (t_EntryCode) list) Base.result_ =
fun v_left v_right ->
(match (v_left, v_right) with
| ((Fail (v_error)), _) ->
(Fail (v_error))
| ((Done (v_first)), (Fail (v_error))) ->
(Fail (v_error))
| ((Done (v_first)), (Done (v_second))) ->
(Done ((Base.list_reverse_go ((Base.list_reverse (v_first))) (v_second)))))
and (* wasm.bend:1378 *)
f_codegen_grain : unit -> int =
fun () ->
512
and (* wasm.bend:1381 *)
f_codegen_weight_work : int -> (t_CodegenWeightWork) list -> int -> int =
fun v_fuel v_pending v_weight ->
(match (v_fuel, v_pending) with
| (_, []) ->
v_weight
| (0, _) ->
v_weight
| (__nat_28, ((WeightExpression ((I.ClosureExpr (v_key, v_captures)))) :: v_tail)) when __nat_28 >= 1 ->
(let v_rest = (__nat_28 - 1) in
(f_codegen_weight_work (v_rest) (((WeightCaptures (v_captures)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_29, ((WeightExpression ((I.ConstructExpr (v_constructor, (Some (v_payload)))))) :: v_tail)) when __nat_29 >= 1 ->
(let v_rest = (__nat_29 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_payload)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_30, ((WeightExpression ((I.ApplyExpr (v_callee, v_argument)))) :: v_tail)) when __nat_30 >= 1 ->
(let v_rest = (__nat_30 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_callee)) :: ((WeightExpression (v_argument)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_31, ((WeightExpression ((I.CallExpr (v_key, v_argument)))) :: v_tail)) when __nat_31 >= 1 ->
(let v_rest = (__nat_31 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_argument)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_32, ((WeightExpression ((I.ScalarExpr (v_operator, v_left, v_right)))) :: v_tail)) when __nat_32 >= 1 ->
(let v_rest = (__nat_32 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_left)) :: ((WeightExpression (v_right)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_33, ((WeightExpression ((I.UnaryExpr (v_operator, v_value)))) :: v_tail)) when __nat_33 >= 1 ->
(let v_rest = (__nat_33 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_value)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_34, ((WeightExpression ((I.LetExpr (v_name, v_value, v_body)))) :: v_tail)) when __nat_34 >= 1 ->
(let v_rest = (__nat_34 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_value)) :: ((WeightExpression (v_body)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_35, ((WeightExpression ((I.IfExpr (v_condition, v_consequent, v_alternative)))) :: v_tail)) when __nat_35 >= 1 ->
(let v_rest = (__nat_35 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_condition)) :: ((WeightExpression (v_consequent)) :: ((WeightExpression (v_alternative)) :: v_tail)))) ((Base.nat_add 1 v_weight))))
| (__nat_36, ((WeightExpression ((I.SequenceExpr (v_first, v_next)))) :: v_tail)) when __nat_36 >= 1 ->
(let v_rest = (__nat_36 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_first)) :: ((WeightExpression (v_next)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_37, ((WeightExpression ((I.MatchExpr (v_values, v_arms)))) :: v_tail)) when __nat_37 >= 1 ->
(let v_rest = (__nat_37 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpressions (v_values)) :: ((WeightArms (v_arms)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_38, ((WeightExpression ((I.GuardExpr (v_pattern, v_value, v_alternative, v_body)))) :: v_tail)) when __nat_38 >= 1 ->
(let v_rest = (__nat_38 - 1) in
(f_codegen_weight_work (v_rest) (((WeightPattern (v_pattern)) :: ((WeightExpression (v_value)) :: ((WeightExpression (v_alternative)) :: ((WeightExpression (v_body)) :: v_tail))))) ((Base.nat_add 1 v_weight))))
| (__nat_39, ((WeightExpression ((I.BlockExpr (v_label, v_body)))) :: v_tail)) when __nat_39 >= 1 ->
(let v_rest = (__nat_39 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_body)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_40, ((WeightExpression ((I.ReturnExpr (v_label, v_value)))) :: v_tail)) when __nat_40 >= 1 ->
(let v_rest = (__nat_40 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_value)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_41, ((WeightExpression ((I.StateProviderExpr (v_read, v_write, v_initial)))) :: v_tail)) when __nat_41 >= 1 ->
(let v_rest = (__nat_41 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_initial)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_42, ((WeightExpression ((I.ProviderExpr (v_identity, v_implementation)))) :: v_tail)) when __nat_42 >= 1 ->
(let v_rest = (__nat_42 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_implementation)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_43, ((WeightExpression ((I.HandleExpr (v_provider, v_body)))) :: v_tail)) when __nat_43 >= 1 ->
(let v_rest = (__nat_43 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_provider)) :: ((WeightExpression (v_body)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_44, ((WeightExpression ((I.InvokeOperationExpr (v_identity, v_argument)))) :: v_tail)) when __nat_44 >= 1 ->
(let v_rest = (__nat_44 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_argument)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_45, ((WeightExpression ((I.ProductExpr (v_elements)))) :: v_tail)) when __nat_45 >= 1 ->
(let v_rest = (__nat_45 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpressions (v_elements)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_46, ((WeightExpression ((I.ProjectExpr (v_value, v_index)))) :: v_tail)) when __nat_46 >= 1 ->
(let v_rest = (__nat_46 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_value)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_47, ((WeightExpression ((I.ArrayExpr (v_elements)))) :: v_tail)) when __nat_47 >= 1 ->
(let v_rest = (__nat_47 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpressions (v_elements)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_48, ((WeightExpression ((I.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body)))) :: v_tail)) when __nat_48 >= 1 ->
(let v_rest = (__nat_48 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpressions ([v_start; v_end; v_initial; v_body])) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_49, ((WeightExpression ((I.ForeverExpr (v_state, v_initial, v_body, v_compact)))) :: v_tail)) when __nat_49 >= 1 ->
(let v_rest = (__nat_49 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpressions ([v_initial; v_body])) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_50, ((WeightExpression ((I.ArrayGenerateExpr (v_count, v_generator)))) :: v_tail)) when __nat_50 >= 1 ->
(let v_rest = (__nat_50 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_count)) :: ((WeightExpression (v_generator)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_51, ((WeightExpression ((I.ArrayFillExpr (v_count, v_value)))) :: v_tail)) when __nat_51 >= 1 ->
(let v_rest = (__nat_51 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_count)) :: ((WeightExpression (v_value)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_52, ((WeightExpression ((I.ArrayGetExpr (v_array, v_index)))) :: v_tail)) when __nat_52 >= 1 ->
(let v_rest = (__nat_52 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_array)) :: ((WeightExpression (v_index)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_53, ((WeightExpression ((I.ArraySetExpr (v_array, v_index, v_value)))) :: v_tail)) when __nat_53 >= 1 ->
(let v_rest = (__nat_53 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_array)) :: ((WeightExpression (v_index)) :: ((WeightExpression (v_value)) :: v_tail)))) ((Base.nat_add 1 v_weight))))
| (__nat_54, ((WeightExpression ((I.ArrayReuseExpr (v_array, v_index, v_value)))) :: v_tail)) when __nat_54 >= 1 ->
(let v_rest = (__nat_54 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_array)) :: ((WeightExpression (v_index)) :: ((WeightExpression (v_value)) :: v_tail)))) ((Base.nat_add 1 v_weight))))
| (__nat_55, ((WeightExpression ((I.ArrayLengthExpr (v_array)))) :: v_tail)) when __nat_55 >= 1 ->
(let v_rest = (__nat_55 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_array)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_56, ((WeightExpression (v_expression)) :: v_tail)) when __nat_56 >= 1 ->
(let v_rest = (__nat_56 - 1) in
(f_codegen_weight_work (v_rest) (v_tail) ((Base.nat_add 1 v_weight))))
| (__nat_57, ((WeightExpressions ([])) :: v_tail)) when __nat_57 >= 1 ->
(let v_rest = (__nat_57 - 1) in
(f_codegen_weight_work (v_rest) (v_tail) (v_weight)))
| (__nat_58, ((WeightExpressions ((v_head :: v_following))) :: v_tail)) when __nat_58 >= 1 ->
(let v_rest = (__nat_58 - 1) in
(f_codegen_weight_work (v_rest) (((WeightExpression (v_head)) :: ((WeightExpressions (v_following)) :: v_tail))) (v_weight)))
| (__nat_59, ((WeightPattern ((M.ConstructorPattern (v_constructor, (Some (v_payload)))))) :: v_tail)) when __nat_59 >= 1 ->
(let v_rest = (__nat_59 - 1) in
(f_codegen_weight_work (v_rest) (((WeightPattern (v_payload)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_60, ((WeightPattern ((M.ProductPattern (v_elements)))) :: v_tail)) when __nat_60 >= 1 ->
(let v_rest = (__nat_60 - 1) in
(f_codegen_weight_work (v_rest) (((WeightPatterns (v_elements)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_61, ((WeightPattern (v_pattern)) :: v_tail)) when __nat_61 >= 1 ->
(let v_rest = (__nat_61 - 1) in
(f_codegen_weight_work (v_rest) (v_tail) ((Base.nat_add 1 v_weight))))
| (__nat_62, ((WeightPatterns ([])) :: v_tail)) when __nat_62 >= 1 ->
(let v_rest = (__nat_62 - 1) in
(f_codegen_weight_work (v_rest) (v_tail) (v_weight)))
| (__nat_63, ((WeightPatterns ((v_head :: v_following))) :: v_tail)) when __nat_63 >= 1 ->
(let v_rest = (__nat_63 - 1) in
(f_codegen_weight_work (v_rest) (((WeightPattern (v_head)) :: ((WeightPatterns (v_following)) :: v_tail))) (v_weight)))
| (__nat_64, ((WeightArms ([])) :: v_tail)) when __nat_64 >= 1 ->
(let v_rest = (__nat_64 - 1) in
(f_codegen_weight_work (v_rest) (v_tail) (v_weight)))
| (__nat_65, ((WeightArms (((M.MatchArm (v_patterns, v_body)) :: v_following))) :: v_tail)) when __nat_65 >= 1 ->
(let v_rest = (__nat_65 - 1) in
(f_codegen_weight_work (v_rest) (((WeightPatterns (v_patterns)) :: ((WeightExpression (v_body)) :: ((WeightArms (v_following)) :: v_tail)))) ((Base.nat_add 1 v_weight))))
| (__nat_66, ((WeightCaptures ([])) :: v_tail)) when __nat_66 >= 1 ->
(let v_rest = (__nat_66 - 1) in
(f_codegen_weight_work (v_rest) (v_tail) (v_weight)))
| (__nat_67, ((WeightCaptures ((v_name :: v_following))) :: v_tail)) when __nat_67 >= 1 ->
(let v_rest = (__nat_67 - 1) in
(f_codegen_weight_work (v_rest) (((WeightCaptures (v_following)) :: v_tail)) ((Base.nat_add 1 v_weight)))))
and (* wasm.bend:1468 *)
f_codegen_weight : t_CodegenJob -> int =
fun v_job ->
(let (CodegenJob (v_key, v_parameter, v_body, v_captures)) = v_job in
(f_codegen_weight_work (65536) ([(WeightExpression (v_body)); (WeightCaptures (v_captures))]) (8)))
and (* wasm.bend:1473 *)
f_weigh_entries : (t_CodegenJob) list -> ((t_CodegenJob) t_WeightedEntry) list -> int -> (t_CodegenJob) t_EntryWorkload =
fun v_jobs v_reversed v_weight ->
(match v_jobs with
| [] ->
(EntryWorkload ((Base.list_reverse (v_reversed)), v_weight))
| (v_job :: v_tail) ->
(let v_estimated = (f_codegen_weight (v_job)) in
(f_weigh_entries (v_tail) (((WeightedEntry (v_job, v_estimated)) :: v_reversed)) ((Base.nat_add (v_weight) (v_estimated))))))
and (* wasm.bend:1481 *)
f_entry_partition_valid : 'a. bool -> (('a) t_WeightedEntry) list -> (('a) t_WeightedEntry) list -> int -> int -> ('a) t_EntryPartition =
fun v_large v_left v_right v_left_weight v_right_weight ->
(match (v_large, v_left, v_right) with
| (true, (v_first :: v_xs), (v_second :: v_ys)) ->
(EntryFork ((EntryWorkload ((v_first :: v_xs), v_left_weight)), (EntryWorkload ((v_second :: v_ys), v_right_weight))))
| (_, _, _) ->
(EntryLeaf ((Base.list_reverse_go ((Base.list_reverse (v_left))) (v_right)))))
and (* wasm.bend:1488 *)
f_entry_split_boundary : 'a. bool -> ('a) t_WeightedEntry -> (('a) t_WeightedEntry) list -> (('a) t_WeightedEntry) list -> int -> int -> int -> int -> ('a) t_EntryPartition =
fun v_previous v_latest v_reversed v_following v_previous_weight v_weight v_total v_grain ->
(match v_previous with
| true ->
(EntryFork ((EntryWorkload ((Base.list_reverse (v_reversed)), v_previous_weight)), (EntryWorkload ((v_latest :: v_following), (Base.nat_sub (v_total) (v_previous_weight))))))
| false ->
(let v_right_weight = (Base.nat_sub (v_total) (v_weight)) in
(f_entry_partition_valid ((Base.bool_and ((Base.nat_is_le (v_grain) (v_weight))) ((Base.nat_is_le (v_grain) (v_right_weight))))) ((Base.list_reverse ((v_latest :: v_reversed)))) (v_following) (v_weight) (v_right_weight))))
and (* wasm.bend:1496 *)
f_split_entries : 'a. (('a) t_WeightedEntry) list -> int -> int -> int -> int -> (('a) t_WeightedEntry) list -> bool -> ('a) t_EntryPartition =
fun v_entries v_target v_total v_grain v_weight v_reversed v_ready ->
(match (v_entries, v_reversed, v_ready) with
| (_, ((WeightedEntry (v_job, v_estimated)) :: v_previous), true) ->
(let v_before = (Base.nat_sub (v_weight) (v_estimated)) in
(let v_earlier = (Base.bool_and ((Base.nat_is_le ((Base.nat_max (1) (v_grain))) (v_before))) ((Base.nat_is_le (v_grain) ((Base.nat_sub (v_total) (v_before)))))) in
(let v_nearer = (Base.nat_is_le ((Base.nat_sub (v_target) (v_before))) ((Base.nat_sub (v_weight) (v_target)))) in
(f_entry_split_boundary ((Base.bool_and (v_earlier) (v_nearer))) ((WeightedEntry (v_job, v_estimated))) (v_previous) (v_entries) (v_before) (v_weight) (v_total) (v_grain)))))
| (_, [], true) ->
(EntryLeaf (v_entries))
| ([], _, false) ->
(EntryLeaf ((Base.list_reverse (v_reversed))))
| (((WeightedEntry (v_job, v_estimated)) :: v_tail), _, false) ->
(let v_next = (Base.nat_add (v_weight) (v_estimated)) in
(f_split_entries (v_tail) (v_target) (v_total) (v_grain) (v_next) (((WeightedEntry (v_job, v_estimated)) :: v_reversed)) ((Base.nat_is_le (v_target) (v_next))))))
and (* wasm.bend:1511 *)
f_partition_entries : 'a. bool -> ('a) t_EntryWorkload -> int -> ('a) t_EntryPartition =
fun v_large v_workload v_grain ->
(match (v_large, v_workload) with
| (false, (EntryWorkload (v_entries, v_weight))) ->
(EntryLeaf (v_entries))
| (true, (EntryWorkload (v_entries, v_weight))) ->
(f_split_entries (v_entries) ((Base.nat_div (v_weight) (2))) (v_weight) (v_grain) (0) ([]) (false)))
and (* wasm.bend:1518 *)
f_entry_partition : 'a. ('a) t_EntryWorkload -> int -> ('a) t_EntryPartition =
fun v_workload v_grain ->
(let (EntryWorkload (v_entries, v_weight)) = v_workload in
(f_partition_entries ((Base.nat_is_le (v_grain) ((Base.nat_div (v_weight) (2))))) (v_workload) (v_grain)))
and (* wasm.bend:1522 *)
f_entry_batches : 'a. int -> ('a) t_EntryPartition -> int -> ('a) t_EntryBatch =
fun v_fuel v_partition v_grain ->
(match (v_fuel, v_partition) with
| (_, (EntryLeaf (v_entries))) ->
(SequentialEntries (v_entries))
| (0, (EntryFork ((EntryWorkload (v_left, v_lw)), (EntryWorkload (v_right, v_rw))))) ->
(SequentialEntries ((Base.list_reverse_go ((Base.list_reverse (v_left))) (v_right))))
| (__nat_68, (EntryFork (v_left, v_right))) when __nat_68 >= 1 ->
(let v_rest = (__nat_68 - 1) in
(ParallelEntries ((f_entry_batches (v_rest) ((f_entry_partition (v_left) (v_grain))) (v_grain)), (f_entry_batches (v_rest) ((f_entry_partition (v_right) (v_grain))) (v_grain))))))
and (* wasm.bend:1531 *)
f_plan_entries : (t_CodegenJob) list -> int -> (t_CodegenJob) t_EntryBatch =
fun v_jobs v_grain ->
(f_entry_batches (64) ((f_entry_partition ((f_weigh_entries (v_jobs) ([]) (0))) (v_grain))) (v_grain))
and (* wasm.bend:1534 *)
f_compile_entry_leaf : ((t_CodegenJob) t_WeightedEntry) list -> (t_EntryCode) list -> (M.t_Diagnostic, (t_EntryCode) list) Base.result_ =
fun v_entries v_reversed ->
(match v_entries with
| [] ->
(Done ((Base.list_reverse (v_reversed))))
| ((WeightedEntry (v_job, v_weight)) :: v_tail) ->
(match (f_compile_entry (v_job)) with
| Fail __error -> Fail __error
| Done v_compiled ->
(f_compile_entry_leaf (v_tail) ((v_compiled :: v_reversed)))))
and (* wasm.bend:1543 *)
f_compile_entry_batch : (t_CodegenJob) t_EntryBatch -> (M.t_Diagnostic, (t_EntryCode) list) Base.result_ =
fun v_batch ->
(match v_batch with
| (SequentialEntries (v_entries)) ->
(f_compile_entry_leaf (v_entries) ([]))
| (ParallelEntries ((ParallelEntries ((ParallelEntries (v_a, v_b)), (ParallelEntries (v_c, v_d)))), (ParallelEntries ((ParallelEntries (v_e, v_f)), (ParallelEntries (v_g, v_h)))))) ->
(let (v_ra, v_rb, v_rc, v_rd, v_re, v_rf, v_rg, v_rh) = Native_parallel.eight (fun () -> (f_compile_entry_batch (v_a))) (fun () -> (f_compile_entry_batch (v_b))) (fun () -> (f_compile_entry_batch (v_c))) (fun () -> (f_compile_entry_batch (v_d))) (fun () -> (f_compile_entry_batch (v_e))) (fun () -> (f_compile_entry_batch (v_f))) (fun () -> (f_compile_entry_batch (v_g))) (fun () -> (f_compile_entry_batch (v_h))) in
(f_merge_entries ((f_merge_entries ((f_merge_entries (v_ra) (v_rb))) ((f_merge_entries (v_rc) (v_rd))))) ((f_merge_entries ((f_merge_entries (v_re) (v_rf))) ((f_merge_entries (v_rg) (v_rh)))))))
| (ParallelEntries ((ParallelEntries (v_a, v_b)), (ParallelEntries (v_c, v_d)))) ->
(let (v_ra, v_rb, v_rc, v_rd) = Native_parallel.four (fun () -> (f_compile_entry_batch (v_a))) (fun () -> (f_compile_entry_batch (v_b))) (fun () -> (f_compile_entry_batch (v_c))) (fun () -> (f_compile_entry_batch (v_d))) in
(f_merge_entries ((f_merge_entries (v_ra) (v_rb))) ((f_merge_entries (v_rc) (v_rd)))))
| (ParallelEntries (v_left, v_right)) ->
(let (v_a, v_b) = Native_parallel.two (fun () -> (f_compile_entry_batch (v_left))) (fun () -> (f_compile_entry_batch (v_right))) in
(f_merge_entries (v_a) (v_b))))
and (* wasm.bend:1558 *)
f_compile_entries_with_grain : int -> (t_CodegenJob) list -> (M.t_Diagnostic, (t_EntryCode) list) Base.result_ =
fun v_grain v_jobs ->
(f_compile_entry_batch ((f_plan_entries (v_jobs) (v_grain))))
and (* wasm.bend:1561 *)
f_compile_entries : (t_CodegenJob) list -> (M.t_Diagnostic, (t_EntryCode) list) Base.result_ =
fun v_jobs ->
(f_compile_entries_with_grain ((f_codegen_grain ())) (v_jobs))
and (* wasm.bend:1564 *)
f_constructor_word : (E.t_ConstructorSlot) option -> (int) option =
fun v_found ->
(match v_found with
| None ->
None
| (Some ((E.ConstructorSlot (v_name, v_tag, v_payload)))) ->
(Some (v_tag)))
and (* wasm.bend:1571 *)
f_resolve_fragment : t_Fragment -> t_Catalog -> int -> (M.t_Diagnostic, (Base.word32) list) Base.result_ =
fun v_fragment v_symbols v_imports ->
(match v_fragment with
| (Bytes (v_bytes)) ->
(Done (v_bytes))
| (NamedCall (v_key)) ->
(match (f_lookup_symbol ((f_symbol_entries (v_symbols))) (v_key)) with
| Fail __error -> Fail __error
| Done v_index ->
(Done (((Base.W32 0x10) :: (f_unsigned_leb ((Base.nat_add 3 (Base.nat_add (v_imports) (v_index)))))))))
| Allocate ->
(Done (((Base.W32 0x10) :: (f_unsigned_leb (v_imports)))))
| Collect ->
(Done (((Base.W32 0x10) :: (f_unsigned_leb ((Base.nat_add 2 v_imports))))))
| (EntryIndex (v_key)) ->
(match (f_lookup_symbol ((f_symbol_entries (v_symbols))) (v_key)) with
| Fail __error -> Fail __error
| Done v_index ->
(Done ((f_i32_constant ((Base.u32_from_nat (v_index)))))))
| (ConstantReference (v_name)) ->
(f_constant_reference ((f_runtime_global (v_symbols) (v_name))) (v_name) (v_symbols) (v_imports))
| (ConstructorIndex (v_name)) ->
(match (f_required_symbol ((f_constructor_word ((E.f_constructor_get ((f_symbol_constructors (v_symbols))) (v_name))))) (v_name)) with
| Fail __error -> Fail __error
| Done v_tag ->
(Done ((f_i32_constant ((Base.u32_from_nat (v_tag)))))))
| (OperationIndex (v_identity)) ->
(match (f_lookup_symbol ((f_symbol_operations (v_symbols))) ((I.f_operation_key (v_identity)))) with
| Fail __error -> Fail __error
| Done v_index ->
(Done ((f_i32_constant ((Base.u32_from_nat (v_index))))))))
and (* wasm.bend:1598 *)
f_relocation_chunk : (M.t_Diagnostic, (Base.word32) list) Base.result_ -> t_BytePlan -> (M.t_Diagnostic, t_BytePlan) Base.result_ =
fun v_result v_accumulated ->
(match v_result with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done (v_bytes)) ->
(let (BytePlan (v_length, v_reversed)) = v_accumulated in
(Done ((BytePlan ((Base.nat_add (v_length) ((f_byte_length (v_bytes) (0)))), (v_bytes :: v_reversed)))))))
and (* wasm.bend:1608 *)
f_resolve_fragments : (t_Fragment) list -> t_Catalog -> int -> (M.t_Diagnostic, t_BytePlan) Base.result_ -> (M.t_Diagnostic, t_BytePlan) Base.result_ =
fun v_fragments v_symbols v_imports v_accumulated ->
(match (v_fragments, v_accumulated) with
| (_, (Fail (v_error))) ->
(Fail (v_error))
| ([], (Done ((BytePlan (v_length, v_reversed))))) ->
(Done ((BytePlan (v_length, (Base.list_reverse (v_reversed))))))
| (((Bytes ([])) :: v_tail), (Done (v_plan))) ->
(f_resolve_fragments (v_tail) (v_symbols) (v_imports) ((Done (v_plan))))
| ((v_head :: v_tail), (Done (v_plan))) ->
(f_resolve_fragments (v_tail) (v_symbols) (v_imports) ((f_relocation_chunk ((f_resolve_fragment (v_head) (v_symbols) (v_imports))) (v_plan)))))
and (* wasm.bend:1619 *)
f_matching_entry : bool -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_same v_key ->
(match v_same with
| true ->
(Done (()))
| false ->
(Fail ((M.Diagnostic (s_9, v_key, s_42)))))
and (* wasm.bend:1633 *)
f_relocation_cost : (t_Fragment) list -> int -> int =
fun v_fragments v_cost ->
(match v_fragments with
| [] ->
v_cost
| ((Bytes (v_bytes)) :: v_tail) ->
(f_relocation_cost (v_tail) ((Base.nat_add (v_cost) (1))))
| (v_head :: v_tail) ->
(f_relocation_cost (v_tail) ((Base.nat_add (v_cost) (8)))))
and (* wasm.bend:1642 *)
f_link_tasks : (t_CodegenJob) list -> (t_EntryCode) list -> ((t_LinkTask) B.t_Weighted) list =
fun v_jobs v_entries ->
(match (v_jobs, v_entries) with
| ([], []) ->
[]
| (((CodegenJob (v_key, v_parameter, v_body, v_captures)) :: v_tail), ((EntryCode (v_found, (Code (v_fragments, v_locals)))) :: v_rest)) ->
((B.Weighted ((LinkBody (v_key, (EntryCode (v_found, (Code (v_fragments, v_locals)))))), (f_relocation_cost (v_fragments) (8)))) :: (f_link_tasks (v_tail) (v_rest)))
| (_, _) ->
[(B.Weighted (LinkCountMismatch, 1))])
and (* wasm.bend:1651 *)
f_link_body : t_LinkTask -> t_LinkContext -> (M.t_Diagnostic, t_BytePlan) Base.result_ =
fun v_task v_context ->
(match (v_task, v_context) with
| ((LinkBody (v_key, (EntryCode (v_found, (Code (v_fragments, v_locals)))))), (LinkContext (v_symbols, v_imports))) ->
(match (f_matching_entry ((M.f_name_equal (v_key) (v_found))) (v_key)) with
| Fail __error -> Fail __error
| Done v_matched ->
(match (f_resolve_fragments (v_fragments) (v_symbols) (v_imports) ((Done ((BytePlan (0, [])))))) with
| Fail __error -> Fail __error
| Done v_instructions ->
(Done ((f_body_plan (v_instructions) (v_locals) (3))))))
| (LinkCountMismatch, _) ->
(Fail ((M.Diagnostic (s_9, s_43, s_44)))))
and (* wasm.bend:1661 *)
f_collect_bodies : ((M.t_Diagnostic, t_BytePlan) Base.result_) list -> (M.t_Diagnostic, (t_BytePlan) list) Base.result_ =
fun v_results ->
(match v_results with
| [] ->
(Done ([]))
| ((Fail (v_error)) :: v_tail) ->
(Fail (v_error))
| ((Done (v_body)) :: v_tail) ->
(match (f_collect_bodies (v_tail)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_body :: v_rest)))))
and (* wasm.bend:1672 *)
f_link_bodies_with_grain : int -> (t_CodegenJob) list -> (t_EntryCode) list -> t_Catalog -> int -> (M.t_Diagnostic, (t_BytePlan) list) Base.result_ =
fun v_grain v_jobs v_entries v_symbols v_imports ->
(f_collect_bodies ((B.f_execute (f_link_body) ((B.f_plan ((f_link_tasks (v_jobs) (v_entries))) (v_grain))) ((LinkContext (v_symbols, v_imports))))))
and (* wasm.bend:1675 *)
f_link_bodies : (t_CodegenJob) list -> (t_EntryCode) list -> t_Catalog -> int -> (M.t_Diagnostic, (t_BytePlan) list) Base.result_ =
fun v_jobs v_entries v_symbols v_imports ->
(f_link_bodies_with_grain (256) (v_jobs) (v_entries) (v_symbols) (v_imports))
and (* wasm.bend:1680 *)
f_allocator : unit -> (Base.word32) list =
fun () ->
(f_sized ((Arena.f_allocate (0))))
and (* wasm.bend:1683 *)
f_scalar_tag : t_AbiScalar -> Base.word32 =
fun v_scalar ->
(match v_scalar with
| UnitScalar ->
(Base.W32 0x0)
| U32Scalar ->
(Base.W32 0x1)
| BoolScalar ->
(Base.W32 0x2)
| F32Scalar ->
(Base.W32 0x3))
and (* wasm.bend:1694 *)
f_scalar_name : t_AbiScalar -> Base.text =
fun v_scalar ->
(match v_scalar with
| UnitScalar ->
s_45
| U32Scalar ->
s_46
| BoolScalar ->
s_47
| F32Scalar ->
s_48)
and (* wasm.bend:1705 *)
f_scalar_wasm : t_AbiScalar -> Base.word32 =
fun v_scalar ->
(match v_scalar with
| F32Scalar ->
(Base.W32 0x7d)
| _ ->
(Base.W32 0x7f))
and (* wasm.bend:1712 *)
f_abi_from_word : t_AbiScalar -> (Base.word32) list =
fun v_scalar ->
(match v_scalar with
| UnitScalar ->
[(Base.W32 0x1a); (Base.W32 0x41); (Base.W32 0x0)]
| BoolScalar ->
[(Base.W32 0x45); (Base.W32 0x45)]
| F32Scalar ->
[(Base.W32 0xbe)]
| U32Scalar ->
[])
and (* wasm.bend:1723 *)
f_abi_to_word : t_AbiScalar -> (Base.word32) list =
fun v_scalar ->
(match v_scalar with
| UnitScalar ->
[(Base.W32 0x1a); (Base.W32 0x41); (Base.W32 0x0)]
| BoolScalar ->
[(Base.W32 0x45); (Base.W32 0x45)]
| F32Scalar ->
[(Base.W32 0xbc)]
| U32Scalar ->
[])
and (* wasm.bend:1734 *)
f_value_tag : t_AbiValue -> Base.word32 =
fun v_value ->
(match v_value with
| (ScalarValue (v_scalar)) ->
(f_scalar_tag (v_scalar))
| U32ArrayValue ->
(Base.W32 0x5)
| F32ArrayValue ->
(Base.W32 0x6))
and (* wasm.bend:1743 *)
f_value_from_word : t_AbiValue -> (Base.word32) list =
fun v_value ->
(match v_value with
| (ScalarValue (v_scalar)) ->
(f_abi_from_word (v_scalar))
| _ ->
[])
and (* wasm.bend:1750 *)
f_value_to_word : t_AbiValue -> (Base.word32) list =
fun v_value ->
(match v_value with
| (ScalarValue (v_scalar)) ->
(f_abi_to_word (v_scalar))
| _ ->
[])
and (* wasm.bend:1757 *)
f_value_name : t_AbiValue -> Base.text =
fun v_value ->
(match v_value with
| (ScalarValue (v_scalar)) ->
(f_scalar_name (v_scalar))
| U32ArrayValue ->
s_49
| F32ArrayValue ->
s_50)
and (* wasm.bend:1766 *)
f_value_wasm : t_AbiValue -> Base.word32 =
fun v_value ->
(match v_value with
| (ScalarValue (v_scalar)) ->
(f_scalar_wasm (v_scalar))
| _ ->
(Base.W32 0x7f))
and (* wasm.bend:1773 *)
f_callback_equal : t_Callback -> t_Callback -> bool =
fun v_left v_right ->
(let (Callback (v_lp, v_lr)) = v_left in
(let (Callback (v_rp, v_rr)) = v_right in
(Base.bool_and ((Base.u32_is_eq ((f_value_tag (v_lp))) ((f_value_tag (v_rp))))) ((Base.u32_is_eq ((f_value_tag (v_lr))) ((f_value_tag (v_rr))))))))
and (* wasm.bend:1778 *)
f_callback_contains : (t_Callback) list -> t_Callback -> bool =
fun v_callbacks v_wanted ->
(match v_callbacks with
| [] ->
false
| (v_first :: v_tail) ->
(Base.bool_or ((f_callback_equal (v_first) (v_wanted))) ((f_callback_contains (v_tail) (v_wanted)))))
and (* wasm.bend:1785 *)
f_callback_catalog : (t_AbiFunction) list -> (t_Callback) list -> (t_Callback) list =
fun v_functions v_reversed ->
(match v_functions with
| [] ->
(Base.list_reverse (v_reversed))
| ((AbiFunction (v_name, (ValueParameter (v_value)), v_result)) :: v_tail) ->
(f_callback_catalog (v_tail) (v_reversed))
| ((AbiFunction (v_name, (CallbackParameter (v_signature)), v_result)) :: v_tail) ->
(let v_found = (f_callback_contains (v_reversed) (v_signature)) in
(f_callback_catalog (v_tail) ((Base.bool_pick (v_found) (v_reversed) ((v_signature :: v_reversed)))))))
and (* wasm.bend:1795 *)
f_abi_functions : (M.t_CheckedFunction) list -> (M.t_Diagnostic, (t_AbiFunction) list) Base.result_ =
fun v_functions ->
(match v_functions with
| [] ->
(Done ([]))
| ((M.CheckedFunction ((M.Function (v_name, false, v_parameter, v_param_ann, v_result_ann, v_body)), v_signature, v_effects)) :: v_tail) ->
(f_abi_functions (v_tail))
| ((M.CheckedFunction ((M.Function (v_name, true, v_parameter, v_param_ann, v_result_ann, v_body)), v_signature, v_effects)) :: v_tail) ->
(match (f_function_abi (v_signature)) with
| Fail __error -> Fail __error
| Done v_head ->
(match (f_abi_functions (v_tail)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_head :: v_rest))))))
and (* wasm.bend:1807 *)
f_abi_constants : (t_ExportedConstant) list -> (M.t_Diagnostic, (t_AbiConstant) list) Base.result_ =
fun v_constants ->
(match v_constants with
| [] ->
(Done ([]))
| ((ExportedConstant (v_name, v_ty)) :: v_tail) ->
(match (f_abi_scalar (v_ty) (v_name)) with
| Fail __error -> Fail __error
| Done v_scalar ->
(match (f_abi_constants (v_tail)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((AbiConstant (v_name, v_scalar)) :: v_rest))))))
and (* wasm.bend:1817 *)
f_module_abi : (M.t_CheckedFunction) list -> (t_ExportedConstant) list -> (M.t_Diagnostic, t_Abi) Base.result_ =
fun v_functions v_constants ->
(match (f_abi_functions (v_functions)) with
| Fail __error -> Fail __error
| Done v_exports ->
(match (f_abi_constants (v_constants)) with
| Fail __error -> Fail __error
| Done v_names ->
(Done ((Abi (v_exports, v_names, (f_callback_catalog (v_exports) ([]))))))))
and (* wasm.bend:1823 *)
f_abi_exports : t_Abi -> (t_AbiFunction) list =
fun v_abi ->
(let (Abi (v_functions, v_constants, v_callbacks)) = v_abi in
v_functions)
and (* wasm.bend:1827 *)
f_abi_callbacks : t_Abi -> (t_Callback) list =
fun v_abi ->
(let (Abi (v_functions, v_constants, v_callbacks)) = v_abi in
v_callbacks)
and (* wasm.bend:1831 *)
f_value_is_array : t_AbiValue -> bool =
fun v_value ->
(match v_value with
| (ScalarValue (v_scalar)) ->
false
| _ ->
true)
and (* wasm.bend:1838 *)
f_array_parameter : t_AbiParameter -> bool =
fun v_parameter ->
(match v_parameter with
| (ValueParameter (v_value)) ->
(f_value_is_array (v_value))
| (CallbackParameter (v_signature)) ->
false)
and (* wasm.bend:1845 *)
f_callback_arrays : t_AbiParameter -> bool =
fun v_parameter ->
(match v_parameter with
| (CallbackParameter ((Callback (v_input, v_output)))) ->
(Base.bool_or ((f_value_is_array (v_input))) ((f_value_is_array (v_output))))
| _ ->
false)
and (* wasm.bend:1852 *)
f_array_exports : (t_AbiFunction) list -> bool =
fun v_functions ->
(match v_functions with
| [] ->
false
| ((AbiFunction (v_name, v_parameter, v_result)) :: v_tail) ->
(Base.bool_or ((Base.bool_or ((Base.bool_or ((f_array_parameter (v_parameter))) ((f_callback_arrays (v_parameter))))) ((f_value_is_array (v_result))))) ((f_array_exports (v_tail)))))
and (* wasm.bend:1860 *)
f_arena_floor : bool -> int -> (Base.word32) list =
fun v_initialized v_heap_start ->
(match v_initialized with
| false ->
(f_i32_constant ((Base.u32_from_nat (v_heap_start))))
| true ->
[(Base.W32 0x41); (Base.W32 0x0); (Base.W32 0x28); (Base.W32 0x2); (Base.W32 0x0)])
and (* wasm.bend:1870 *)
f_clear_free_bins : unit -> (Base.word32) list =
fun () ->
(f_join ([(f_i32_constant ((Base.W32 0x20))); [(Base.W32 0x41); (Base.W32 0x0)]; (f_i32_constant ((Base.W32 0x84))); [(Base.W32 0xfc); (Base.W32 0xb); (Base.W32 0x0)]]))
and (* wasm.bend:1873 *)
f_wrapper_reset : t_AbiParameter -> int -> bool -> (Base.word32) list =
fun v_parameter v_heap_start v_initialized ->
(Base.bool_pick ((f_array_parameter (v_parameter))) ([]) ((f_join ([(f_arena_floor (v_initialized) (v_heap_start)); [(Base.W32 0x24); (Base.W32 0x0)]; (f_clear_free_bins ())]))))
and (* wasm.bend:1876 *)
f_abi_parameter_bytes : t_AbiParameter -> (Base.word32) list =
fun v_parameter ->
(match v_parameter with
| (ValueParameter (v_value)) ->
[(f_value_tag (v_value))]
| (CallbackParameter ((Callback (v_input, v_output)))) ->
[(Base.W32 0x4); (f_value_tag (v_input)); (f_value_tag (v_output))])
and (* wasm.bend:1883 *)
f_abi_function_bytes : (t_AbiFunction) list -> ((Base.word32) list) list =
fun v_functions ->
(match v_functions with
| [] ->
[]
| ((AbiFunction (v_name, v_parameter, v_result)) :: v_tail) ->
((f_join ([(f_sized ((f_utf8 ((Public.f_export_name (v_name)))))); (f_abi_parameter_bytes (v_parameter)); [(f_value_tag (v_result))]])) :: (f_abi_function_bytes (v_tail))))
and (* wasm.bend:1890 *)
f_abi_constant_bytes : (t_AbiConstant) list -> ((Base.word32) list) list =
fun v_constants ->
(match v_constants with
| [] ->
[]
| ((AbiConstant (v_name, v_scalar)) :: v_tail) ->
((f_concat ((f_sized ((f_utf8 (v_name))))) ([(f_scalar_tag (v_scalar))])) :: (f_abi_constant_bytes (v_tail))))
and (* wasm.bend:1897 *)
f_abi_section : t_Abi -> t_BytePlan =
fun v_abi ->
(let (Abi (v_functions, v_constants, v_callbacks)) = v_abi in
(f_byte_plan ((f_section ((Base.W32 0x0)) ((f_join ([(f_sized ((f_utf8 (s_51)))); [(Base.W32 0x2)]; (f_vector ((f_abi_function_bytes (v_functions)))); (f_vector ((f_abi_constant_bytes (v_constants))))])))))))
and (* wasm.bend:1901 *)
f_callback_slot : bool -> int -> (unit -> (M.t_Diagnostic, int) Base.result_) -> (M.t_Diagnostic, int) Base.result_ =
fun v_found v_index v_fallback ->
(match v_found with
| true ->
(Done (v_index))
| false ->
(v_fallback (())))
and (* wasm.bend:1908 *)
f_callback_index : (t_Callback) list -> t_Callback -> int -> (M.t_Diagnostic, int) Base.result_ =
fun v_callbacks v_wanted v_index ->
(match v_callbacks with
| [] ->
(Fail ((M.Diagnostic (s_0, s_52, s_53))))
| (v_first :: v_tail) ->
(f_callback_slot ((f_callback_equal (v_first) (v_wanted))) (v_index) ((fun v_ignored ->
(f_callback_index (v_tail) (v_wanted) ((Base.nat_add 1 v_index)))))))
and (* wasm.bend:1915 *)
f_wrapper_type : t_AbiFunction -> Base.word32 =
fun v_function ->
(match v_function with
| (AbiFunction (v_name, (CallbackParameter (v_signature)), (ScalarValue (F32Scalar)))) ->
(Base.W32 0x6)
| (AbiFunction (v_name, (CallbackParameter (v_signature)), v_result)) ->
(Base.W32 0x5)
| (AbiFunction (v_name, (ValueParameter ((ScalarValue (F32Scalar)))), (ScalarValue (F32Scalar)))) ->
(Base.W32 0x4)
| (AbiFunction (v_name, (ValueParameter ((ScalarValue (F32Scalar)))), v_result)) ->
(Base.W32 0x2)
| (AbiFunction (v_name, v_parameter, (ScalarValue (F32Scalar)))) ->
(Base.W32 0x3)
| _ ->
(Base.W32 0x1))
and (* wasm.bend:1930 *)
f_wrapper_types : (t_AbiFunction) list -> (Base.word32) list =
fun v_functions ->
(match v_functions with
| [] ->
[]
| (v_head :: v_tail) ->
((f_wrapper_type (v_head)) :: (f_wrapper_types (v_tail))))
and (* wasm.bend:1937 *)
f_wrapper_argument : t_AbiParameter -> (t_Callback) list -> int -> (M.t_Diagnostic, (Base.word32) list) Base.result_ =
fun v_parameter v_callbacks v_entries ->
(match v_parameter with
| (ValueParameter (v_value)) ->
(let v_return_bytes = (f_join ([[(Base.W32 0x41); (Base.W32 0x0); (Base.W32 0x20); (Base.W32 0x0)]; (f_value_to_word (v_value))])) in
(Done ((f_concat ((Base.bool_pick ((Base.list_is_empty (v_callbacks))) ([]) ([(Base.W32 0xd0); (Base.W32 0x6f); (Base.W32 0x24); (Base.W32 0x1)]))) (v_return_bytes)))))
| (CallbackParameter (v_signature)) ->
(let v_imports = (Base.list_length (v_callbacks)) in
(match (f_callback_index (v_callbacks) (v_signature) (v_entries)) with
| Fail __error -> Fail __error
| Done v_slot ->
(Done ((f_join ([[(Base.W32 0x20); (Base.W32 0x0); (Base.W32 0x24); (Base.W32 0x1); (Base.W32 0x41); (Base.W32 0x0); (Base.W32 0x41); (Base.W32 0x4); (Base.W32 0x10)]; (f_unsigned_leb (v_imports)); [(Base.W32 0x22); (Base.W32 0x1)]; (f_i32_constant ((Base.u32_from_nat (v_slot)))); [(Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x0); (Base.W32 0x20); (Base.W32 0x1)]])))))))
and (* wasm.bend:1948 *)
f_wrapper_return : (t_Callback) list -> t_AbiValue -> (Base.word32) list =
fun v_callbacks v_result ->
(match v_callbacks with
| [] ->
(f_value_from_word (v_result))
| (v_head :: v_tail) ->
(f_concat ([(Base.W32 0x21); (Base.W32 0x1); (Base.W32 0xd0); (Base.W32 0x6f); (Base.W32 0x24); (Base.W32 0x1); (Base.W32 0x20); (Base.W32 0x1)]) ((f_value_from_word (v_result)))))
and (* wasm.bend:1955 *)
f_wrapper_bodies : (t_AbiFunction) list -> ((int) option) Base.map -> int -> (t_Callback) list -> int -> bool -> (M.t_Diagnostic, (t_BytePlan) list) Base.result_ =
fun v_functions v_slots v_heap_start v_callbacks v_entries v_initialized ->
(match v_functions with
| [] ->
(Done ([]))
| ((AbiFunction (v_name, v_parameter, v_result)) :: v_tail) ->
(let v_imports = (Base.list_length (v_callbacks)) in
(match (f_lookup_symbol (v_slots) ((Base.string_append s_5 v_name))) with
| Fail __error -> Fail __error
| Done v_index ->
(match (f_wrapper_argument (v_parameter) (v_callbacks) (v_entries)) with
| Fail __error -> Fail __error
| Done v_argument ->
(match (f_wrapper_bodies (v_tail) (v_slots) (v_heap_start) (v_callbacks) (v_entries) (v_initialized)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((f_byte_plan ((f_body_bytes ((f_join ([(f_wrapper_reset (v_parameter) (v_heap_start) (v_initialized)); v_argument; [(Base.W32 0x41); (Base.W32 0x0); (Base.W32 0x10)]; (f_unsigned_leb ((Base.nat_add 3 (Base.nat_add (v_imports) (v_index))))); (f_wrapper_return (v_callbacks) (v_result))]))) ((Base.bool_pick ((Base.nat_is_eq (v_imports) (0))) (1) (2))) (1)))) :: v_rest))))))))
and (* wasm.bend:1967 *)
f_function_exports : (t_AbiFunction) list -> int -> ((Base.word32) list) list =
fun v_functions v_index ->
(match v_functions with
| [] ->
[]
| ((AbiFunction (v_name, v_parameter, v_result)) :: v_tail) ->
(let v_slot = v_index in
((f_concat ((f_sized ((f_utf8 ((Public.f_export_name (v_name))))))) (((Base.W32 0x0) :: (f_unsigned_leb (v_slot))))) :: (f_function_exports (v_tail) ((Base.nat_add 1 v_slot))))))
and (* wasm.bend:1975 *)
f_global_exports : (t_ExportedConstant) list -> int -> ((Base.word32) list) list =
fun v_names v_index ->
(match v_names with
| [] ->
[]
| ((ExportedConstant (v_name, v_value_type)) :: v_tail) ->
(let v_slot = v_index in
((f_concat ((f_sized ((f_utf8 (v_name))))) (((Base.W32 0x3) :: (f_unsigned_leb (v_slot))))) :: (f_global_exports (v_tail) ((Base.nat_add 1 v_slot))))))
and (* wasm.bend:1983 *)
f_global_initializer : M.t_Ty -> Base.word32 -> bool -> (Base.word32) list =
fun v_ty v_word v_mutable ->
(match v_ty with
| M.F32Ty ->
(f_join ([[(Base.W32 0x7d); (Base.bool_pick (v_mutable) ((Base.W32 0x1)) ((Base.W32 0x0))); (Base.W32 0x43)]; (f_word_bytes (v_word)); [(Base.W32 0xb)]]))
| _ ->
(f_join ([[(Base.W32 0x7f); (Base.bool_pick (v_mutable) ((Base.W32 0x1)) ((Base.W32 0x0)))]; (f_i32_constant (v_word)); [(Base.W32 0xb)]])))
and (* wasm.bend:1990 *)
f_exported_initializer : (t_RuntimeGlobal) option -> Base.text -> M.t_Ty -> t_Catalog -> (M.t_Diagnostic, (Base.word32) list) Base.result_ =
fun v_runtime v_name v_ty v_symbols ->
(match v_runtime with
| (Some (v_slot)) ->
(Done ((f_global_initializer (v_ty) ((Base.W32 0x0)) (true))))
| None ->
(match (f_lookup_symbol ((f_symbol_constants (v_symbols))) (v_name)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((f_global_initializer (v_ty) ((Base.u32_from_nat (v_value))) (false))))))
and (* wasm.bend:1999 *)
f_globals : (t_ExportedConstant) list -> t_Catalog -> (M.t_Diagnostic, ((Base.word32) list) list) Base.result_ =
fun v_names v_symbols ->
(match v_names with
| [] ->
(Done ([]))
| ((ExportedConstant (v_name, v_value_type)) :: v_tail) ->
(match (f_exported_initializer ((f_runtime_global (v_symbols) (v_name))) (v_name) (v_value_type) (v_symbols)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_globals (v_tail) (v_symbols)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_value :: v_rest))))))
and (* wasm.bend:2010 *)
f_table_indices : int -> int -> (Base.word32) list =
fun v_count v_start ->
(match v_count with
| 0 ->
[]
| __nat_69 when __nat_69 >= 1 ->
(let v_rest = (__nat_69 - 1) in
(let v_index = v_start in
(f_concat ((f_unsigned_leb (v_index))) ((f_table_indices (v_rest) ((Base.nat_add 1 v_index))))))))
and (* wasm.bend:2018 *)
f_data_section : t_Heap -> t_BytePlan =
fun v_heap ->
(let (Heap (v_heap_start, v_chunks)) = v_heap in
(f_plan_section ((Base.W32 0xb)) ((f_plan_prefix ([(Base.W32 0x1); (Base.W32 0x0); (Base.W32 0x41); (Base.W32 0x0); (Base.W32 0xb)]) ((f_plan_sized ((BytePlan (v_heap_start, (Base.list_reverse (v_chunks)))))))))))
and (* wasm.bend:2022 *)
f_callback_types : (t_Callback) list -> ((Base.word32) list) list =
fun v_callbacks ->
(match v_callbacks with
| [] ->
[]
| ((Callback (v_parameter, v_result)) :: v_tail) ->
([(Base.W32 0x60); (Base.W32 0x2); (Base.W32 0x6f); (f_value_wasm (v_parameter)); (Base.W32 0x1); (f_value_wasm (v_result))] :: (f_callback_types (v_tail))))
and (* wasm.bend:2029 *)
f_extra_types : (t_Callback) list -> ((Base.word32) list) list =
fun v_callbacks ->
(match v_callbacks with
| [] ->
[]
| (v_head :: v_tail) ->
([(Base.W32 0x60); (Base.W32 0x1); (Base.W32 0x6f); (Base.W32 0x1); (Base.W32 0x7f)] :: ([(Base.W32 0x60); (Base.W32 0x1); (Base.W32 0x6f); (Base.W32 0x1); (Base.W32 0x7d)] :: (f_callback_types ((v_head :: v_tail))))))
and (* wasm.bend:2036 *)
f_type_section : (t_Callback) list -> bool -> t_BytePlan =
fun v_callbacks v_initialized ->
(f_byte_plan ((f_section ((Base.W32 0x1)) ((f_vector ((Base.list_append ([[(Base.W32 0x60); (Base.W32 0x3); (Base.W32 0x7f); (Base.W32 0x7f); (Base.W32 0x7f); (Base.W32 0x1); (Base.W32 0x7f)]; [(Base.W32 0x60); (Base.W32 0x1); (Base.W32 0x7f); (Base.W32 0x1); (Base.W32 0x7f)]; [(Base.W32 0x60); (Base.W32 0x1); (Base.W32 0x7d); (Base.W32 0x1); (Base.W32 0x7f)]; [(Base.W32 0x60); (Base.W32 0x1); (Base.W32 0x7f); (Base.W32 0x1); (Base.W32 0x7d)]; [(Base.W32 0x60); (Base.W32 0x1); (Base.W32 0x7d); (Base.W32 0x1); (Base.W32 0x7d)]]) ((Base.list_append ((f_extra_types (v_callbacks))) ((Base.bool_pick (v_initialized) ([[(Base.W32 0x60); (Base.W32 0x0); (Base.W32 0x0)]]) ([]))))))))))))
and (* wasm.bend:2045 *)
f_callback_imports : (t_Callback) list -> int -> ((Base.word32) list) list =
fun v_callbacks v_index ->
(match v_callbacks with
| [] ->
[]
| ((Callback (v_parameter, v_result)) :: v_tail) ->
(let v_slot = v_index in
((f_join ([(f_sized ((f_utf8 (s_54)))); (f_sized ((f_utf8 ((Base.string_append s_55 (Base.string_append (f_value_name (v_parameter)) (Base.string_append s_56 (f_value_name (v_result))))))))); [(Base.W32 0x0)]; (f_unsigned_leb ((Base.nat_add 7 v_slot)))])) :: (f_callback_imports (v_tail) ((Base.nat_add 1 v_slot))))))
and (* wasm.bend:2053 *)
f_import_section : (t_Callback) list -> t_BytePlan =
fun v_callbacks ->
(match v_callbacks with
| [] ->
(f_byte_plan ([]))
| (v_head :: v_tail) ->
(f_byte_plan ((f_section ((Base.W32 0x2)) ((f_vector ((f_callback_imports ((v_head :: v_tail)) (0)))))))))
and (* wasm.bend:2062 *)
f_callback_bodies : (t_Callback) list -> int -> (t_BytePlan) list =
fun v_callbacks v_index ->
(match v_callbacks with
| [] ->
[]
| ((Callback (v_parameter, v_result)) :: v_tail) ->
(let v_slot = v_index in
((f_byte_plan ((f_body_bytes ((f_join ([[(Base.W32 0x23); (Base.W32 0x1); (Base.W32 0x20); (Base.W32 0x1)]; (f_value_from_word (v_parameter)); [(Base.W32 0x10)]; (f_unsigned_leb (v_slot)); (f_value_to_word (v_result))]))) (3) (3)))) :: (f_callback_bodies (v_tail) ((Base.nat_add 1 v_slot))))))
and (* wasm.bend:2070 *)
f_callback_globals : (t_Callback) list -> ((Base.word32) list) list -> ((Base.word32) list) list =
fun v_callbacks v_values ->
(match v_callbacks with
| [] ->
v_values
| (v_head :: v_tail) ->
([(Base.W32 0x6f); (Base.W32 0x1); (Base.W32 0xd0); (Base.W32 0x6f); (Base.W32 0xb)] :: v_values))
and (* wasm.bend:2077 *)
f_arena_exports : bool -> int -> int -> ((Base.word32) list) list =
fun v_enabled v_allocator_index v_reset_index ->
(match v_enabled with
| false ->
[]
| true ->
[(f_concat ((f_sized ((f_utf8 (s_57))))) ([(Base.W32 0x2); (Base.W32 0x0)])); (f_concat ((f_sized ((f_utf8 (s_58))))) (((Base.W32 0x0) :: (f_unsigned_leb (v_allocator_index))))); (f_concat ((f_sized ((f_utf8 (s_59))))) (((Base.W32 0x0) :: (f_unsigned_leb (v_reset_index)))))])
and (* wasm.bend:2089 *)
f_arena_reset_body : bool -> int -> bool -> (t_BytePlan) list =
fun v_enabled v_heap_start v_initialized ->
(match v_enabled with
| false ->
[]
| true ->
[(f_byte_plan ((f_body_bytes ((f_join ([(f_arena_floor (v_initialized) (v_heap_start)); [(Base.W32 0x24); (Base.W32 0x0)]; (f_clear_free_bins ()); (f_arena_floor (v_initialized) (v_heap_start))]))) (1) (1))))])
and (* wasm.bend:2096 *)
f_assemble : t_Abi -> (t_BytePlan) list -> (t_BytePlan) list -> (t_ExportedConstant) list -> ((Base.word32) list) list -> t_Heap -> (t_BytePlan) list -> t_BytePlan =
fun v_abi v_bodies v_wrappers v_names v_values v_heap v_startup ->
(let (Abi (v_functions, v_constants, v_callbacks)) = v_abi in
(let (Heap (v_heap_start, v_chunks)) = v_heap in
(let v_count = (Base.list_length (v_bodies)) in
(let v_imports = (Base.list_length (v_callbacks)) in
(let v_wrapper_count = (Base.list_length (v_wrappers)) in
(let v_arrays = (f_array_exports (v_functions)) in
(let v_reset_count = (Base.bool_pick (v_arrays) (1) (0)) in
(let v_initialized = (Base.bool_not ((Base.list_is_empty (v_startup)))) in
(let v_start_count = (Base.list_length (v_startup)) in
(let v_start_type = (Base.bool_pick ((Base.nat_is_eq (v_imports) (0))) (5) ((Base.nat_add 7 v_imports))) in
(let v_start_index = (Base.nat_add 3 (Base.nat_add (v_imports) ((Base.nat_add (v_count) ((Base.nat_add (v_wrapper_count) (v_reset_count))))))) in
(let v_pages = (Base.nat_max (1) ((Base.u32_to_nat ((Base.u32_shrn ((Base.u32_add ((Base.u32_from_nat (v_heap_start))) ((Base.W32 0xffff)))) (16)))))) in
(f_plan_sequence ([(f_byte_plan ([(Base.W32 0x0); (Base.W32 0x61); (Base.W32 0x73); (Base.W32 0x6d); (Base.W32 0x1); (Base.W32 0x0); (Base.W32 0x0); (Base.W32 0x0)])); (f_type_section (v_callbacks) (v_initialized)); (f_import_section (v_callbacks)); (f_byte_plan ((f_section ((Base.W32 0x3)) ((f_join ([(f_unsigned_leb ((Base.nat_add 3 (Base.nat_add (v_count) ((Base.nat_add (v_wrapper_count) ((Base.nat_add (v_reset_count) (v_start_count))))))))); [(Base.W32 0x1); (Base.W32 0x0); (Base.W32 0x0)]; (Base.list_replicate (v_count) ((Base.W32 0x0))); (f_wrapper_types (v_functions)); (Base.list_replicate (v_reset_count) ((Base.W32 0x1))); (Base.bool_pick (v_initialized) ((f_unsigned_leb (v_start_type))) ([]))])))))); (f_byte_plan ((f_section ((Base.W32 0x4)) ((f_join ([[(Base.W32 0x1); (Base.W32 0x70); (Base.W32 0x0)]; (f_unsigned_leb (v_count))])))))); (f_byte_plan ((f_section ((Base.W32 0x5)) ((f_join ([[(Base.W32 0x1); (Base.W32 0x1)]; (f_unsigned_leb (v_pages)); (f_unsigned_leb ((f_runtime_memory_max_pages ())))])))))); (f_byte_plan ((f_section ((Base.W32 0x6)) ((f_vector (((f_join ([[(Base.W32 0x7f); (Base.W32 0x1)]; (f_i32_constant ((Base.u32_from_nat (v_heap_start)))); [(Base.W32 0xb)]])) :: (f_callback_globals (v_callbacks) (v_values))))))))); (f_byte_plan ((f_section ((Base.W32 0x7)) ((f_vector ((Base.list_append ((f_function_exports (v_functions) ((Base.nat_add 3 (Base.nat_add (v_imports) (v_count)))))) ((Base.list_append ((f_global_exports (v_names) ((Base.bool_pick ((Base.nat_is_eq (v_imports) (0))) (1) (2))))) ((f_arena_exports (v_arrays) (v_imports) ((Base.nat_add 3 (Base.nat_add (v_imports) ((Base.nat_add (v_count) (v_wrapper_count))))))))))))))))); (f_byte_plan ((Base.bool_pick (v_initialized) ((f_section ((Base.W32 0x8)) ((f_unsigned_leb (v_start_index))))) ([])))); (f_byte_plan ((f_section ((Base.W32 0x9)) ((f_join ([[(Base.W32 0x1); (Base.W32 0x0); (Base.W32 0x41); (Base.W32 0x0); (Base.W32 0xb)]; (f_unsigned_leb (v_count)); (f_table_indices (v_count) ((Base.nat_add 3 v_imports)))])))))); (f_plan_section ((Base.W32 0xa)) ((f_plan_vector (((f_byte_plan ((f_allocator ()))) :: ((f_byte_plan ((f_sized ((Arena.f_mark (v_imports)))))) :: ((f_byte_plan ((f_sized ((Arena.f_collect (v_imports)))))) :: (Base.list_append (v_bodies) ((Base.list_append (v_wrappers) ((Base.list_append ((f_arena_reset_body (v_arrays) (v_heap_start) (v_initialized))) (v_startup))))))))))))); (f_data_section ((Heap (v_heap_start, v_chunks)))); (f_abi_section (v_abi))]))))))))))))))
and (* wasm.bend:2134 *)
f_preparation_weight : int -> (t_PreparationWeightWork) list -> int -> int =
fun v_fuel v_pending v_weight ->
(match (v_fuel, v_pending) with
| (_, []) ->
v_weight
| (0, _) ->
v_weight
| (__nat_70, ((PreparationExpressions ([])) :: v_tail)) when __nat_70 >= 1 ->
(let v_rest = (__nat_70 - 1) in
(f_preparation_weight (v_rest) (v_tail) (v_weight)))
| (__nat_71, ((PreparationExpressions ((v_head :: v_following))) :: v_tail)) when __nat_71 >= 1 ->
(let v_rest = (__nat_71 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_head)) :: ((PreparationExpressions (v_following)) :: v_tail))) (v_weight)))
| (__nat_72, ((PreparationArms ([])) :: v_tail)) when __nat_72 >= 1 ->
(let v_rest = (__nat_72 - 1) in
(f_preparation_weight (v_rest) (v_tail) (v_weight)))
| (__nat_73, ((PreparationArms (((M.MatchArm (v_patterns, v_body)) :: v_following))) :: v_tail)) when __nat_73 >= 1 ->
(let v_rest = (__nat_73 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_body)) :: ((PreparationArms (v_following)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_74, ((PreparationExpression ((M.ConstructExpr (v_constructor, (Some (v_payload)))))) :: v_tail)) when __nat_74 >= 1 ->
(let v_rest = (__nat_74 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_payload)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_75, ((PreparationExpression ((M.ApplyExpr (v_callee, v_argument)))) :: v_tail)) when __nat_75 >= 1 ->
(let v_rest = (__nat_75 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_callee)) :: ((PreparationExpression (v_argument)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_76, ((PreparationExpression ((M.CallExpr (v_callee, v_argument)))) :: v_tail)) when __nat_76 >= 1 ->
(let v_rest = (__nat_76 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_argument)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_77, ((PreparationExpression ((M.ScalarExpr (v_operator, v_left, v_right)))) :: v_tail)) when __nat_77 >= 1 ->
(let v_rest = (__nat_77 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_left)) :: ((PreparationExpression (v_right)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_78, ((PreparationExpression ((M.UnaryExpr (v_operator, v_value)))) :: v_tail)) when __nat_78 >= 1 ->
(let v_rest = (__nat_78 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_value)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_79, ((PreparationExpression ((M.LetExpr (v_name, v_value, v_body)))) :: v_tail)) when __nat_79 >= 1 ->
(let v_rest = (__nat_79 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_value)) :: ((PreparationExpression (v_body)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_80, ((PreparationExpression ((M.UseExpr (v_name, v_value, v_body)))) :: v_tail)) when __nat_80 >= 1 ->
(let v_rest = (__nat_80 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_value)) :: ((PreparationExpression (v_body)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_81, ((PreparationExpression ((M.IfExpr (v_condition, v_consequent, v_alternative)))) :: v_tail)) when __nat_81 >= 1 ->
(let v_rest = (__nat_81 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_condition)) :: ((PreparationExpression (v_consequent)) :: ((PreparationExpression (v_alternative)) :: v_tail)))) ((Base.nat_add 1 v_weight))))
| (__nat_82, ((PreparationExpression ((M.SequenceExpr (v_first, v_next)))) :: v_tail)) when __nat_82 >= 1 ->
(let v_rest = (__nat_82 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_first)) :: ((PreparationExpression (v_next)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_83, ((PreparationExpression ((M.MatchExpr (v_values, v_arms)))) :: v_tail)) when __nat_83 >= 1 ->
(let v_rest = (__nat_83 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpressions (v_values)) :: ((PreparationArms (v_arms)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_84, ((PreparationExpression ((M.GuardExpr (v_pattern, v_value, v_alternative, v_body)))) :: v_tail)) when __nat_84 >= 1 ->
(let v_rest = (__nat_84 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_value)) :: ((PreparationExpression (v_alternative)) :: ((PreparationExpression (v_body)) :: v_tail)))) ((Base.nat_add 1 v_weight))))
| (__nat_85, ((PreparationExpression ((M.BlockExpr (v_label, v_body)))) :: v_tail)) when __nat_85 >= 1 ->
(let v_rest = (__nat_85 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_body)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_86, ((PreparationExpression ((M.ReturnExpr (v_label, v_value)))) :: v_tail)) when __nat_86 >= 1 ->
(let v_rest = (__nat_86 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_value)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_87, ((PreparationExpression ((M.SourceExpr (v_offset, v_annotation, v_value)))) :: v_tail)) when __nat_87 >= 1 ->
(let v_rest = (__nat_87 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_value)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_88, ((PreparationExpression ((M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value)))) :: v_tail)) when __nat_88 >= 1 ->
(let v_rest = (__nat_88 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_value)) :: v_tail)) (v_weight)))
| (__nat_89, ((PreparationExpression ((M.InstantiationExpr (v_site, v_value)))) :: v_tail)) when __nat_89 >= 1 ->
(let v_rest = (__nat_89 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_value)) :: v_tail)) (v_weight)))
| (__nat_90, ((PreparationExpression ((M.TagExpr (v_offset, v_callee, v_argument)))) :: v_tail)) when __nat_90 >= 1 ->
(let v_rest = (__nat_90 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_callee)) :: ((PreparationExpression (v_argument)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_91, ((PreparationExpression ((M.StateProviderExpr (v_read, v_write, v_initial)))) :: v_tail)) when __nat_91 >= 1 ->
(let v_rest = (__nat_91 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_initial)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_92, ((PreparationExpression ((M.ProviderExpr (v_identity, v_implementation)))) :: v_tail)) when __nat_92 >= 1 ->
(let v_rest = (__nat_92 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_implementation)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_93, ((PreparationExpression ((M.HandleExpr (v_provider, v_body)))) :: v_tail)) when __nat_93 >= 1 ->
(let v_rest = (__nat_93 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_provider)) :: ((PreparationExpression (v_body)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_94, ((PreparationExpression ((M.EffectHasExpr (v_set, v_operation)))) :: v_tail)) when __nat_94 >= 1 ->
(let v_rest = (__nat_94 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_set)) :: ((PreparationExpression (v_operation)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_95, ((PreparationExpression ((M.EffectCountExpr (v_set)))) :: v_tail)) when __nat_95 >= 1 ->
(let v_rest = (__nat_95 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_set)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_96, ((PreparationExpression ((M.EffectSameExpr (v_left, v_right)))) :: v_tail)) when __nat_96 >= 1 ->
(let v_rest = (__nat_96 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_left)) :: ((PreparationExpression (v_right)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_97, ((PreparationExpression ((M.ProductExpr (v_elements)))) :: v_tail)) when __nat_97 >= 1 ->
(let v_rest = (__nat_97 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpressions (v_elements)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_98, ((PreparationExpression ((M.ProjectExpr (v_value, v_index)))) :: v_tail)) when __nat_98 >= 1 ->
(let v_rest = (__nat_98 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_value)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_99, ((PreparationExpression ((M.ArrayExpr (v_elements)))) :: v_tail)) when __nat_99 >= 1 ->
(let v_rest = (__nat_99 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpressions (v_elements)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_100, ((PreparationExpression ((M.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body)))) :: v_tail)) when __nat_100 >= 1 ->
(let v_rest = (__nat_100 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpressions ([v_start; v_end; v_initial; v_body])) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_101, ((PreparationExpression ((M.ForeverExpr (v_state, v_initial, v_body)))) :: v_tail)) when __nat_101 >= 1 ->
(let v_rest = (__nat_101 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpressions ([v_initial; v_body])) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_102, ((PreparationExpression ((M.ArrayGenerateExpr (v_count, v_generator)))) :: v_tail)) when __nat_102 >= 1 ->
(let v_rest = (__nat_102 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_count)) :: ((PreparationExpression (v_generator)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_103, ((PreparationExpression ((M.ArrayFillExpr (v_count, v_value)))) :: v_tail)) when __nat_103 >= 1 ->
(let v_rest = (__nat_103 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_count)) :: ((PreparationExpression (v_value)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_104, ((PreparationExpression ((M.ArrayGetExpr (v_array, v_index)))) :: v_tail)) when __nat_104 >= 1 ->
(let v_rest = (__nat_104 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_array)) :: ((PreparationExpression (v_index)) :: v_tail))) ((Base.nat_add 1 v_weight))))
| (__nat_105, ((PreparationExpression ((M.ArraySetExpr (v_array, v_index, v_value)))) :: v_tail)) when __nat_105 >= 1 ->
(let v_rest = (__nat_105 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_array)) :: ((PreparationExpression (v_index)) :: ((PreparationExpression (v_value)) :: v_tail)))) ((Base.nat_add 1 v_weight))))
| (__nat_106, ((PreparationExpression ((M.ArrayLengthExpr (v_array)))) :: v_tail)) when __nat_106 >= 1 ->
(let v_rest = (__nat_106 - 1) in
(f_preparation_weight (v_rest) (((PreparationExpression (v_array)) :: v_tail)) ((Base.nat_add 1 v_weight))))
| (__nat_107, ((PreparationExpression (v_expression)) :: v_tail)) when __nat_107 >= 1 ->
(let v_rest = (__nat_107 - 1) in
(f_preparation_weight (v_rest) (v_tail) ((Base.nat_add 1 v_weight)))))
and (* wasm.bend:2217 *)
f_weigh_preparations : (t_Entry) list -> ((t_Entry) t_WeightedEntry) list -> int -> (t_Entry) t_EntryWorkload =
fun v_entries v_reversed v_weight ->
(match v_entries with
| [] ->
(EntryWorkload ((Base.list_reverse (v_reversed)), v_weight))
| ((Entry (v_key, v_parameter, v_body, v_captures)) :: v_tail) ->
(let v_estimated = (f_preparation_weight (65536) ([(PreparationExpression (v_body))]) (8)) in
(f_weigh_preparations (v_tail) (((WeightedEntry ((Entry (v_key, v_parameter, v_body, v_captures)), v_estimated)) :: v_reversed)) ((Base.nat_add (v_weight) (v_estimated))))))
and (* wasm.bend:2225 *)
f_prepare_job_leaf : ((t_Entry) t_WeightedEntry) list -> I.t_Metadata -> (t_CodegenJob) list -> (M.t_Diagnostic, (t_CodegenJob) list) Base.result_ =
fun v_entries v_projection v_reversed ->
(match v_entries with
| [] ->
(Done ((Base.list_reverse (v_reversed))))
| ((WeightedEntry ((Entry (v_key, v_parameter, v_body, v_captures)), v_weight)) :: v_tail) ->
(match (I.f_prepare_scoped (v_body) (v_projection) ((I.f_safe_loop_entry (v_projection) (v_key)))) with
| Fail __error -> Fail __error
| Done v_projected ->
(match (Reuse.f_prepare (v_projected)) with
| Fail __error -> Fail __error
| Done v_prepared ->
(f_prepare_job_leaf (v_tail) (v_projection) (((CodegenJob (v_key, v_parameter, v_prepared, v_captures)) :: v_reversed))))))
and (* wasm.bend:2235 *)
f_merge_prepared : (M.t_Diagnostic, (t_CodegenJob) list) Base.result_ -> (M.t_Diagnostic, (t_CodegenJob) list) Base.result_ -> (M.t_Diagnostic, (t_CodegenJob) list) Base.result_ =
fun v_left v_right ->
(match (v_left, v_right) with
| ((Fail (v_error)), _) ->
(Fail (v_error))
| ((Done (v_first)), (Fail (v_error))) ->
(Fail (v_error))
| ((Done (v_first)), (Done (v_second))) ->
(Done ((Base.list_reverse_go ((Base.list_reverse (v_first))) (v_second)))))
and (* wasm.bend:2244 *)
f_prepare_job_batch : (t_Entry) t_EntryBatch -> I.t_Metadata -> (M.t_Diagnostic, (t_CodegenJob) list) Base.result_ =
fun v_batch v_projection ->
(match v_batch with
| (SequentialEntries (v_entries)) ->
(f_prepare_job_leaf (v_entries) (v_projection) ([]))
| (ParallelEntries ((ParallelEntries ((ParallelEntries (v_a, v_b)), (ParallelEntries (v_c, v_d)))), (ParallelEntries ((ParallelEntries (v_e, v_f)), (ParallelEntries (v_g, v_h)))))) ->
(let (v_ra, v_rb, v_rc, v_rd, v_re, v_rf, v_rg, v_rh) = Native_parallel.eight (fun () -> (f_prepare_job_batch (v_a) (v_projection))) (fun () -> (f_prepare_job_batch (v_b) (v_projection))) (fun () -> (f_prepare_job_batch (v_c) (v_projection))) (fun () -> (f_prepare_job_batch (v_d) (v_projection))) (fun () -> (f_prepare_job_batch (v_e) (v_projection))) (fun () -> (f_prepare_job_batch (v_f) (v_projection))) (fun () -> (f_prepare_job_batch (v_g) (v_projection))) (fun () -> (f_prepare_job_batch (v_h) (v_projection))) in
(f_merge_prepared ((f_merge_prepared ((f_merge_prepared (v_ra) (v_rb))) ((f_merge_prepared (v_rc) (v_rd))))) ((f_merge_prepared ((f_merge_prepared (v_re) (v_rf))) ((f_merge_prepared (v_rg) (v_rh)))))))
| (ParallelEntries ((ParallelEntries (v_a, v_b)), (ParallelEntries (v_c, v_d)))) ->
(let (v_ra, v_rb, v_rc, v_rd) = Native_parallel.four (fun () -> (f_prepare_job_batch (v_a) (v_projection))) (fun () -> (f_prepare_job_batch (v_b) (v_projection))) (fun () -> (f_prepare_job_batch (v_c) (v_projection))) (fun () -> (f_prepare_job_batch (v_d) (v_projection))) in
(f_merge_prepared ((f_merge_prepared (v_ra) (v_rb))) ((f_merge_prepared (v_rc) (v_rd)))))
| (ParallelEntries (v_left, v_right)) ->
(let (v_a, v_b) = Native_parallel.two (fun () -> (f_prepare_job_batch (v_left) (v_projection))) (fun () -> (f_prepare_job_batch (v_right) (v_projection))) in
(f_merge_prepared (v_a) (v_b))))
and (* wasm.bend:2258 *)
f_preparation_grain : unit -> int =
fun () ->
512
and (* wasm.bend:2261 *)
f_plan_preparations : (t_Entry) list -> int -> (t_Entry) t_EntryBatch =
fun v_entries v_grain ->
(f_entry_batches (64) ((f_entry_partition ((f_weigh_preparations (v_entries) ([]) (0))) (v_grain))) (v_grain))
and (* wasm.bend:2264 *)
f_prepare_jobs_with_grain : int -> (t_Entry) list -> I.t_Metadata -> (M.t_Diagnostic, (t_CodegenJob) list) Base.result_ =
fun v_grain v_entries v_projection ->
(f_prepare_job_batch ((f_plan_preparations (v_entries) (v_grain))) (v_projection))
and (* wasm.bend:2267 *)
f_prepare_jobs : (t_Entry) list -> I.t_Metadata -> (M.t_Diagnostic, (t_CodegenJob) list) Base.result_ =
fun v_entries v_projection ->
(f_prepare_jobs_with_grain ((f_preparation_grain ())) (v_entries) (v_projection))
and (* wasm.bend:2270 *)
f_operation_jobs : (M.t_Operation) list -> (t_CodegenJob) list =
fun v_operations ->
(match v_operations with
| [] ->
[]
| ((M.Operation (v_identity, v_parameter, v_result)) :: v_tail) ->
((CodegenJob ((I.f_operation_key (v_identity)), s_60, (I.InvokeOperationExpr (v_identity, (I.LocalExpr (s_60)))), [])) :: (f_operation_jobs (v_tail)))
| (v_head :: v_tail) ->
(f_operation_jobs (v_tail)))
and (* wasm.bend:2279 *)
f_used_operations : (M.t_Operation) list -> Base.set -> (M.t_Operation) list =
fun v_operations v_used ->
(match v_operations with
| [] ->
[]
| ((M.Operation (v_identity, v_parameter, v_result)) :: v_tail) ->
(let v_rest = (f_used_operations (v_tail) (v_used)) in
(Base.bool_pick ((Base.maybe_is_some ((Index.f_find (v_used) ((I.f_operation_key (v_identity))))))) (((M.Operation (v_identity, v_parameter, v_result)) :: v_rest)) (v_rest)))
| (v_head :: v_tail) ->
(f_used_operations (v_tail) (v_used)))
and (* wasm.bend:2289 *)
f_job_slots : (t_CodegenJob) list -> int -> (t_Slot) list =
fun v_jobs v_index ->
(match v_jobs with
| [] ->
[]
| ((CodegenJob (v_key, v_parameter, v_body, v_captures)) :: v_tail) ->
(let v_position = v_index in
((Slot (v_key, v_position)) :: (f_job_slots (v_tail) ((Base.nat_add 1 v_position))))))
and (* wasm.bend:2297 *)
f_initializer_entries : (Init.t_Initializer) list -> (t_Entry) list =
fun v_initializers ->
(match v_initializers with
| [] ->
[]
| ((Init.Initializer (v_name, v_value)) :: v_tail) ->
((Entry ((Base.string_append s_61 v_name), s_62, v_value, [])) :: (f_initializer_entries (v_tail))))
and (* wasm.bend:2304 *)
f_exported_global : (t_ExportedConstant) list -> Base.text -> int -> (t_RuntimeGlobal) option =
fun v_names v_wanted v_index ->
(match v_names with
| [] ->
None
| ((ExportedConstant (v_name, v_ty)) :: v_tail) ->
(let v_slot = v_index in
(Base.bool_pick ((M.f_name_equal (v_name) (v_wanted))) ((Some ((RuntimeGlobal (v_slot, v_ty))))) ((f_exported_global (v_tail) (v_wanted) ((Base.nat_add 1 v_slot)))))))
and (* wasm.bend:2312 *)
f_runtime_position : (t_RuntimeGlobal) option -> int -> t_RuntimeGlobal =
fun v_found v_fallback ->
(match v_found with
| (Some (v_slot)) ->
v_slot
| None ->
(RuntimeGlobal (v_fallback, M.U32Ty)))
and (* wasm.bend:2319 *)
f_runtime_global_index : t_RuntimeGlobal -> int =
fun v_global ->
(let (RuntimeGlobal (v_index, v_ty)) = v_global in
v_index)
and (* wasm.bend:2323 *)
f_runtime_globals : (Init.t_Initializer) list -> (t_ExportedConstant) list -> int -> (t_RuntimeGlobal) Base.map -> (t_RuntimeGlobal) Base.map =
fun v_initializers v_names v_next v_indexed ->
(match v_initializers with
| [] ->
v_indexed
| ((Init.Initializer (v_name, v_value)) :: v_tail) ->
(let v_global = (f_runtime_position ((f_exported_global (v_names) (v_name) (1))) (v_next)) in
(f_runtime_globals (v_tail) (v_names) ((Base.nat_add (v_next) ((Base.bool_pick ((Base.nat_is_eq ((f_runtime_global_index (v_global))) (v_next))) (1) (0))))) ((Base.map_set (v_indexed) (v_name) (v_global))))))
and (* wasm.bend:2331 *)
f_required_runtime : (t_RuntimeGlobal) option -> Base.text -> (M.t_Diagnostic, t_RuntimeGlobal) Base.result_ =
fun v_found v_name ->
(match v_found with
| None ->
(Fail ((M.Diagnostic (s_9, v_name, s_63))))
| (Some (v_global)) ->
(Done (v_global)))
and (* wasm.bend:2338 *)
f_private_global : t_RuntimeGlobal -> int -> ((Base.word32) list) list -> ((Base.word32) list) list =
fun v_global v_first v_rest ->
(let (RuntimeGlobal (v_index, v_ty)) = v_global in
(Base.bool_pick ((Base.nat_is_ge (v_index) (v_first))) (((f_global_initializer (v_ty) ((Base.W32 0x0)) (true)) :: v_rest)) (v_rest)))
and (* wasm.bend:2342 *)
f_private_globals : (Init.t_Initializer) list -> t_Catalog -> int -> (M.t_Diagnostic, ((Base.word32) list) list) Base.result_ =
fun v_initializers v_symbols v_first ->
(match v_initializers with
| [] ->
(Done ([]))
| ((Init.Initializer (v_name, v_value)) :: v_tail) ->
(match (f_required_runtime ((f_runtime_global (v_symbols) (v_name))) (v_name)) with
| Fail __error -> Fail __error
| Done v_global ->
(match (f_private_globals (v_tail) (v_symbols) (v_first)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((f_private_global (v_global) (v_first) (v_rest)))))))
and (* wasm.bend:2352 *)
f_initializer_call : t_RuntimeGlobal -> int -> int -> (Base.word32) list =
fun v_global v_entry v_imports ->
(let (RuntimeGlobal (v_index, v_ty)) = v_global in
(f_join ([[(Base.W32 0x41); (Base.W32 0x0); (Base.W32 0x41); (Base.W32 0x0); (Base.W32 0x41); (Base.W32 0x0); (Base.W32 0x10)]; (f_unsigned_leb ((Base.nat_add 3 (Base.nat_add (v_imports) (v_entry))))); (f_runtime_from_word (v_ty)); [(Base.W32 0x24)]; (f_unsigned_leb ((f_global_index (v_index) (v_imports))))])))
and (* wasm.bend:2356 *)
f_initializer_calls : (Init.t_Initializer) list -> t_Catalog -> int -> (M.t_Diagnostic, ((Base.word32) list) list) Base.result_ =
fun v_initializers v_symbols v_imports ->
(match v_initializers with
| [] ->
(Done ([[(Base.W32 0x41); (Base.W32 0x0); (Base.W32 0x23); (Base.W32 0x0); (Base.W32 0x36); (Base.W32 0x2); (Base.W32 0x0)]]))
| ((Init.Initializer (v_name, v_value)) :: v_tail) ->
(match (f_required_runtime ((f_runtime_global (v_symbols) (v_name))) (v_name)) with
| Fail __error -> Fail __error
| Done v_global ->
(match (f_lookup_symbol ((f_symbol_entries (v_symbols))) ((Base.string_append s_61 v_name))) with
| Fail __error -> Fail __error
| Done v_entry ->
(match (f_initializer_calls (v_tail) (v_symbols) (v_imports)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((f_initializer_call (v_global) (v_entry) (v_imports)) :: v_rest)))))))
and (* wasm.bend:2367 *)
f_initializer_body : (Init.t_Initializer) list -> t_Catalog -> int -> (M.t_Diagnostic, (t_BytePlan) list) Base.result_ =
fun v_initializers v_symbols v_imports ->
(match v_initializers with
| [] ->
(Done ([]))
| v_initializers ->
(match (f_initializer_calls (v_initializers) (v_symbols) (v_imports)) with
| Fail __error -> Fail __error
| Done v_calls ->
(Done ([(f_byte_plan ((f_body_bytes ((f_join (v_calls))) (0) (0))))]))))
and (* wasm.bend:2376 *)
f_prepare_catalog : Reachable.t_Runtime -> Base.set -> (M.t_Diagnostic, t_Prepared) Base.result_ =
fun v_runtime v_safe_loops ->
(let (Reachable.Runtime ((M.CheckedModule (v_checked_constants, v_functions, v_types, v_operations)), v_constants, v_lambdas, v_constructors, v_used)) = v_runtime in
(let v_needed_operations = (f_used_operations (v_operations) (v_used)) in
(let v_declarations = (E.f_type_catalog (v_types)) in
(let v_entries = (Base.list_append ((f_function_entries (v_functions))) ((Base.list_append ((f_lambda_entries (v_lambdas))) ((f_constructor_entries ((E.f_catalog_variants (v_declarations))) (v_constructors)))))) in
(let v_projection = (I.f_with_safe_loops ((I.f_with_functions ((I.f_metadata (v_lambdas) ((E.f_catalog_constructors (v_declarations))))) (v_functions))) (v_safe_loops)) in
(match (f_check_functions (v_functions)) with
| Fail __error -> Fail __error
| Done v_supported ->
(match (f_exported_constants (v_checked_constants)) with
| Fail __error -> Fail __error
| Done v_names ->
(match (Init.f_plan ((Init.f_bindings (v_checked_constants))) (v_checked_constants) (v_functions)) with
| Fail __error -> Fail __error
| Done v_initializers ->
(match (f_prepare_jobs ((Base.list_append (v_entries) ((f_initializer_entries (v_initializers))))) (v_projection)) with
| Fail __error -> Fail __error
| Done v_normal ->
(let v_jobs = (Base.list_append (v_normal) ((f_operation_jobs (v_needed_operations)))) in
(let v_slots = (f_slot_index ((f_job_slots (v_jobs) (0)))) in
(let v_operation_ids = (f_slot_index ((f_operation_slots (v_needed_operations) (0)))) in
(match (f_serialize_constants (v_constants) ((StaticCatalog (v_slots, v_projection, v_operation_ids))) ((Heap (256, [(Base.list_replicate (256) ((Base.W32 0x0)))])))) with
| Fail __error -> Fail __error
| Done v_serialized ->
(Done ((Prepared (v_jobs, (Catalog (v_slots, (E.f_catalog_constructors (v_declarations)), (f_slot_index ((f_static_slots (v_serialized)))), v_operation_ids, (f_runtime_globals (v_initializers) (v_names) ((Base.nat_add 1 (Base.list_length (v_names)))) (MTip)))), v_functions, v_names, (f_static_heap (v_serialized)), v_initializers)))))))))))))))))
and (* wasm.bend:2393 *)
f_prepare : M.t_CheckedModule -> ((C.t_Value) C.t_Binding) list -> (M.t_Diagnostic, t_Prepared) Base.result_ =
fun v_checked v_constants ->
(let (M.CheckedModule (v_checked_constants, v_functions, v_types, v_operations)) = v_checked in
(let v_safe_loops = (LoopMemory.f_eligible (v_checked_constants) (v_functions)) in
(match (Reachable.f_prepare (v_checked) (v_constants)) with
| Fail __error -> Fail __error
| Done v_runtime ->
(f_prepare_catalog (v_runtime) (v_safe_loops)))))
and (* wasm.bend:2400 *)
f_prepared_jobs : t_Prepared -> (t_CodegenJob) list =
fun v_prepared ->
(let (Prepared (v_jobs, v_catalog, v_functions, v_names, v_heap, v_initializers)) = v_prepared in
v_jobs)
and (* wasm.bend:2404 *)
f_link_plan : t_Prepared -> (t_EntryCode) list -> (M.t_Diagnostic, t_BytePlan) Base.result_ =
fun v_prepared v_entries ->
(let (Prepared (v_jobs, v_symbols, v_functions, v_names, v_heap, v_initializers)) = v_prepared in
(match (f_module_abi (v_functions) (v_names)) with
| Fail __error -> Fail __error
| Done v_abi ->
(let v_callbacks = (f_abi_callbacks (v_abi)) in
(match (f_link_bodies (v_jobs) (v_entries) (v_symbols) ((Base.list_length (v_callbacks)))) with
| Fail __error -> Fail __error
| Done v_bodies ->
(match (f_wrapper_bodies ((f_abi_exports (v_abi))) ((f_symbol_entries (v_symbols))) ((f_heap_end (v_heap))) (v_callbacks) ((Base.list_length (v_bodies))) ((Base.bool_not ((Base.list_is_empty (v_initializers)))))) with
| Fail __error -> Fail __error
| Done v_wrappers ->
(match (f_globals (v_names) (v_symbols)) with
| Fail __error -> Fail __error
| Done v_values ->
(match (f_private_globals (v_initializers) (v_symbols) ((Base.nat_add 1 (Base.list_length (v_names))))) with
| Fail __error -> Fail __error
| Done v_hidden ->
(match (f_initializer_body (v_initializers) (v_symbols) ((Base.list_length (v_callbacks)))) with
| Fail __error -> Fail __error
| Done v_startup ->
(Done ((f_assemble (v_abi) ((Base.list_append (v_bodies) ((f_callback_bodies (v_callbacks) (0))))) (v_wrappers) (v_names) ((Base.list_append (v_values) (v_hidden))) (v_heap) (v_startup))))))))))))
and (* wasm.bend:2416 *)
f_link : t_Prepared -> (t_EntryCode) list -> (M.t_Diagnostic, (Base.word32) list) Base.result_ =
fun v_prepared v_entries ->
(match (f_link_plan (v_prepared) (v_entries)) with
| Fail __error -> Fail __error
| Done v_plan ->
(Done ((f_plan_finish (v_plan)))))
and (* wasm.bend:2421 *)
f_emit_plan : M.t_CheckedModule -> ((C.t_Value) C.t_Binding) list -> (M.t_Diagnostic, t_BytePlan) Base.result_ =
fun v_checked v_constants ->
(match (f_prepare (v_checked) (v_constants)) with
| Fail __error -> Fail __error
| Done v_prepared ->
(match (f_compile_entries ((f_prepared_jobs (v_prepared)))) with
| Fail __error -> Fail __error
| Done v_entries ->
(f_link_plan (v_prepared) (v_entries))))
and (* wasm.bend:2427 *)
f_emit : M.t_CheckedModule -> ((C.t_Value) C.t_Binding) list -> (M.t_Diagnostic, (Base.word32) list) Base.result_ =
fun v_checked v_constants ->
(match (f_emit_plan (v_checked) (v_constants)) with
| Fail __error -> Fail __error
| Done v_plan ->
(Done ((f_plan_finish (v_plan)))))
