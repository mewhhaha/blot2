(* Native semantic port of compiler/model.bend.

   Source SHA-256: 91037a8c8be43b930351e880d1d7a3161cc421f8b58267c50bfff21894c31150

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

type t_TypeId =
  | TypeId of Base.text * Base.text
and t_RowTail =
  | ClosedRow
  | RowVariable of int
  | RowParameter of int
  | FreeRow of Base.text * Base.text
and t_EffectRow =
  | EffectRow of (t_TypeId) list * t_RowTail
and t_Ty =
  | UnitTy
  | U32Ty
  | BoolTy
  | AppliedTy of t_TypeId * (t_Ty) list
  | FunctionTy of t_Ty * t_Ty * t_EffectRow
  | ParameterTy of int
  | VariableTy of int
  | NeverTy
  | F32Ty
  | ProviderTy of t_TypeId * t_EffectRow
  | StateProviderTy of t_TypeId * t_TypeId * t_Ty
  | EffectDescriptorTy
  | EffectSetTy
  | ProductTy of (t_Ty) list
  | ArrayTy of t_Ty
  | FreeTy of Base.text * Base.text
and t_Operation =
  | Operation of t_TypeId * t_Ty * t_Ty
  | OperationTemplate of t_TypeId * int * t_Ty * t_Ty
  | OperationInstance of t_TypeId * (t_Ty) list
and t_Constructor =
  | Constructor of Base.text * (t_Ty) option * (Base.text) list
and t_DataType =
  | DataType of t_TypeId * int * (t_Constructor) list
and t_ValueReference =
  | LocalReference of Base.text
  | ConstantReference of Base.text
and t_Pattern =
  | WildcardPattern
  | BindingPattern of Base.text
  | UnitPattern
  | U32Pattern of int32
  | BoolPattern of bool
  | ValuePattern of t_ValueReference
  | ConstructorPattern of Base.text * (t_Pattern) option
  | ProductPattern of (t_Pattern) list
and 'e t_MatchArm =
  | MatchArm of (t_Pattern) list * 'e
and t_ScalarOp =
  | Add
  | Subtract
  | Multiply
  | Equal
  | LessThan
  | F32Add
  | F32Subtract
  | F32Multiply
  | F32Divide
  | F32Equal
  | F32NotEqual
  | F32LessThan
  | F32LessEqual
  | F32GreaterThan
  | F32GreaterEqual
and t_UnaryOp =
  | F32Negate
  | F32Absolute
  | F32SquareRoot
  | F32Floor
  | F32Ceiling
  | F32Truncate
  | U32ToF32
  | F32ToU32
and t_Dispatch =
  | BinaryDispatch
  | MemberDispatch
  | FieldUpdateDispatch
and t_Predicate =
  | AssociatedPredicate of Base.text * (t_TypeId) list * t_Ty * t_Ty * t_Ty * t_EffectRow
  | ReceiverPredicate of Base.text * (t_TypeId) list * t_Ty * t_Ty * t_Ty * t_EffectRow
  | FieldPredicate of Base.text * t_Ty * t_Ty
  | UpdatePredicate of Base.text * t_Ty * t_Ty * t_Ty * t_EffectRow
  | OperationPredicate of t_TypeId * (t_Ty) list * t_Ty
  | TypeRepPredicate of t_Ty
  | EffectRepPredicate of t_EffectRow
and t_Expr =
  | UnitExpr
  | U32Expr of int32
  | BoolExpr of bool
  | LocalExpr of Base.text
  | ConstantExpr of Base.text
  | FunctionExpr of Base.text
  | ConstructorRefExpr of Base.text
  | ConstructExpr of Base.text * (t_Expr) option
  | LambdaExpr of int * Base.text * (t_Ty) option * (t_Ty) option * t_Expr
  | ApplyExpr of t_Expr * t_Expr
  | CallExpr of Base.text * t_Expr
  | ScalarExpr of t_ScalarOp * t_Expr * t_Expr
  | LetExpr of Base.text * t_Expr * t_Expr
  | UseExpr of Base.text * t_Expr * t_Expr
  | IfExpr of t_Expr * t_Expr * t_Expr
  | SequenceExpr of t_Expr * t_Expr
  | MatchExpr of (t_Expr) list * ((t_Expr) t_MatchArm) list
  | GuardExpr of t_Pattern * t_Expr * t_Expr * t_Expr
  | BlockExpr of int * t_Expr
  | ReturnExpr of int * t_Expr
  | SourceExpr of int * (t_Ty) option * t_Expr
  | RuntimeInitExpr of t_Expr
  | F32Expr of int32
  | UnaryExpr of t_UnaryOp * t_Expr
  | OperationExpr of t_TypeId
  | SpecializeOperationExpr of t_TypeId * (t_Ty) list * t_Expr
  | ProviderExpr of t_TypeId * t_Expr
  | StateProviderExpr of t_TypeId * t_TypeId * t_Expr
  | HandleExpr of t_Expr * t_Expr
  | OperationDescriptorExpr of t_TypeId
  | FunctionEffectsExpr of Base.text
  | EffectHasExpr of t_Expr * t_Expr
  | EffectCountExpr of t_Expr
  | EffectSameExpr of t_Expr * t_Expr
  | PanicExpr of Base.text
  | ProductExpr of (t_Expr) list
  | ProjectExpr of t_Expr * int
  | ArrayExpr of (t_Expr) list
  | ForExpr of Base.text * t_Expr * t_Expr * Base.text * t_Expr * t_Expr
  | ForeverExpr of Base.text * t_Expr * t_Expr
  | ArrayGenerateExpr of t_Expr * t_Expr
  | ArrayFillExpr of t_Expr * t_Expr
  | ArrayGetExpr of t_Expr * t_Expr
  | ArraySetExpr of t_Expr * t_Expr * t_Expr
  | ArrayLengthExpr of t_Expr
  | AssociatedExpr of int * t_Dispatch * Base.text * (t_TypeId) list * t_Expr * t_Expr
  | GenericOperationExpr of int * t_TypeId * (t_Ty) list
  | TagExpr of int * t_Expr * t_Expr
  | QualifiedExpr of int * t_Ty * (t_Predicate) list * t_Expr
  | InstantiationExpr of int * t_Expr
and t_Function =
  | Function of Base.text * bool * Base.text * (t_Ty) option * (t_Ty) option * t_Expr
and t_Constant =
  | Constant of Base.text * bool * (t_Ty) option * t_Expr
and t_Module =
  | Module of (t_Constant) list * (t_Function) list * (t_DataType) list * (t_Operation) list
and t_Diagnostic =
  | Diagnostic of Base.text * Base.text * Base.text
and t_Effect =
  | OperationEffect of t_TypeId
and t_Signature =
  | Signature of Base.text * t_Ty * t_Ty * (int) list * t_EffectRow
and t_CheckedFunction =
  | CheckedFunction of t_Function * t_Signature * (t_Effect) list
and t_CheckedConstant =
  | CheckedConstant of t_Constant * t_Ty * (int) list
and t_CheckedModule =
  | CheckedModule of (t_CheckedConstant) list * (t_CheckedFunction) list * (t_DataType) list * (t_Operation) list
and t_NameComparison =
  | NameComparison of bool * Base.text * Base.text
and t_TypeDisplay =
  | DisplayType of t_Ty
  | DisplayArguments of (t_Ty) list
  | DisplayElements of (t_Ty) list

let s_0 = Base.text_of_utf8 "blot:compiler"

let s_1 = Base.text_of_utf8 "Foreign"

let s_2 = Base.text_of_utf8 "::"

let s_3 = Base.text_of_utf8 ""

let s_4 = Base.text_of_utf8 "| ?e"

let s_5 = Base.text_of_utf8 "| 'e"

let s_6 = Base.text_of_utf8 "| "

let s_7 = Base.text_of_utf8 ", "

let s_8 = Base.text_of_utf8 " ! {"

let s_9 = Base.text_of_utf8 "}"

let s_10 = Base.text_of_utf8 "..."

let s_11 = Base.text_of_utf8 "Unit"

let s_12 = Base.text_of_utf8 "U32"

let s_13 = Base.text_of_utf8 "F32"

let s_14 = Base.text_of_utf8 "Bool"

let s_15 = Base.text_of_utf8 "("

let s_16 = Base.text_of_utf8 " -> "

let s_17 = Base.text_of_utf8 ")"

let s_18 = Base.text_of_utf8 "StateProvider "

let s_19 = Base.text_of_utf8 " "

let s_20 = Base.text_of_utf8 " ("

let s_21 = Base.text_of_utf8 "Provider "

let s_22 = Base.text_of_utf8 "EffectDescriptor"

let s_23 = Base.text_of_utf8 "EffectSet"

let s_24 = Base.text_of_utf8 "Array ("

let s_25 = Base.text_of_utf8 "'"

let s_26 = Base.text_of_utf8 "?"

let s_27 = Base.text_of_utf8 "Never"

let rec (* model.bend:179 *)
f_module_operations : t_Module -> (t_Operation) list =
fun v_module ->
(let (Module (v_constants, v_functions, v_data_types, v_operations)) = v_module in
v_operations)
and (* model.bend:206 *)
f_empty_row : unit -> t_EffectRow =
fun () ->
(EffectRow ([], ClosedRow))
and (* model.bend:211 *)
f_name_equal_tail : Base.text -> Base.text -> bool -> bool =
fun v_left v_right v_same ->
(match (v_left, v_right, v_same) with
| (_, _, false) ->
false
| (SNil, SNil, true) ->
true
| ((SCon (v_a, v_left_tail)), (SCon (v_b, v_right_tail)), true) ->
(f_name_equal_tail (v_left_tail) (v_right_tail) ((Base.char_is_eq (v_a) (v_b))))
| (_, _, true) ->
false)
and (* model.bend:227 *)
f_name_equal_walk : Base.text -> Base.text -> Base.text -> Base.text -> bool -> t_NameComparison =
fun v_left_root v_right_root v_left v_right v_same ->
(match (v_left, v_right, v_same) with
| (_, _, false) ->
(NameComparison (false, v_left_root, v_right_root))
| (SNil, SNil, true) ->
(NameComparison (true, v_left_root, v_right_root))
| ((SCon (v_a, v_left_tail)), (SCon (v_b, v_right_tail)), true) ->
(f_name_equal_walk (v_left_root) (v_right_root) (v_left_tail) (v_right_tail) ((Base.char_is_eq (v_a) (v_b))))
| (_, _, true) ->
(NameComparison (false, v_left_root, v_right_root)))
and (* model.bend:238 *)
f_name_equal_result : t_NameComparison -> bool =
fun v_result ->
(let (NameComparison (v_equal, v_left, v_right)) = v_result in
v_equal)
and (* model.bend:242 *)
f_name_equal : Base.text -> Base.text -> bool =
fun v_left v_right ->
(f_name_equal_result ((f_name_equal_walk (v_left) (v_right) (v_left) (v_right) (true))))
and (* model.bend:245 *)
f_type_id_equal : t_TypeId -> t_TypeId -> bool =
fun v_a v_b ->
(let (TypeId (v_am, v_an)) = v_a in
(let (TypeId (v_bm, v_bn)) = v_b in
(Base.bool_and ((f_name_equal (v_am) (v_bm))) ((f_name_equal (v_an) (v_bn))))))
and (* model.bend:250 *)
f_foreign_identity : unit -> t_TypeId =
fun () ->
(TypeId (s_0, s_1))
and (* model.bend:253 *)
f_is_foreign : t_TypeId -> bool =
fun v_identity ->
(f_type_id_equal (v_identity) ((f_foreign_identity ())))
and (* model.bend:256 *)
f_foreign_row : unit -> t_EffectRow =
fun () ->
(EffectRow ([(f_foreign_identity ())], ClosedRow))
and (* model.bend:259 *)
f_type_id_show : t_TypeId -> Base.text =
fun v_identity ->
(let (TypeId (v_module_name, v_declaration)) = v_identity in
(Base.string_append v_module_name (Base.string_append s_2 v_declaration)))
and (* model.bend:268 *)
f_row_tail_show : t_RowTail -> Base.text =
fun v_tail ->
(match v_tail with
| ClosedRow ->
s_3
| (RowVariable (v_index)) ->
(Base.string_append s_4 (Base.nat_show (v_index)))
| (RowParameter (v_index)) ->
(Base.string_append s_5 (Base.nat_show (v_index)))
| (FreeRow (v_scope, v_name)) ->
(Base.string_append s_6 v_name))
and (* model.bend:279 *)
f_row_operations_show : (t_TypeId) list -> Base.text =
fun v_operations ->
(match v_operations with
| [] ->
s_3
| (v_head :: []) ->
(f_type_id_show (v_head))
| (v_head :: (v_next :: v_tail)) ->
(Base.string_append (f_type_id_show (v_head)) (Base.string_append s_7 (f_row_operations_show ((v_next :: v_tail))))))
and (* model.bend:288 *)
f_row_show : t_EffectRow -> Base.text =
fun v_row ->
(match v_row with
| (EffectRow ([], ClosedRow)) ->
s_3
| (EffectRow (v_operations, v_tail)) ->
(Base.string_append s_8 (Base.string_append (f_row_operations_show (v_operations)) (Base.string_append (f_row_tail_show (v_tail)) s_9))))
and (* model.bend:295 *)
f_type_display : int -> t_TypeDisplay -> Base.text =
fun v_depth v_display ->
(match (v_depth, v_display) with
| (0, _) ->
s_10
| (__nat_1, (DisplayType (UnitTy))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
s_11)
| (__nat_2, (DisplayType (U32Ty))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
s_12)
| (__nat_3, (DisplayType (F32Ty))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
s_13)
| (__nat_4, (DisplayType (BoolTy))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
s_14)
| (__nat_5, (DisplayType ((AppliedTy (v_identity, v_arguments))))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(Base.string_append (f_type_id_show (v_identity)) (f_type_display (v_rest) ((DisplayArguments (v_arguments))))))
| (__nat_6, (DisplayType ((FunctionTy (v_parameter, v_result, v_effects))))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(Base.string_append s_15 (Base.string_append (f_type_display (v_rest) ((DisplayType (v_parameter)))) (Base.string_append s_16 (Base.string_append (f_type_display (v_rest) ((DisplayType (v_result)))) (Base.string_append (f_row_show (v_effects)) s_17))))))
| (__nat_7, (DisplayType ((StateProviderTy (v_read, v_write, v_state))))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(Base.string_append s_18 (Base.string_append (f_type_id_show (v_read)) (Base.string_append s_19 (Base.string_append (f_type_id_show (v_write)) (Base.string_append s_20 (Base.string_append (f_type_display (v_rest) ((DisplayType (v_state)))) s_17)))))))
| (__nat_8, (DisplayType ((ProviderTy (v_identity, v_effects))))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(Base.string_append s_21 (Base.string_append (f_type_id_show (v_identity)) (f_row_show (v_effects)))))
| (__nat_9, (DisplayType (EffectDescriptorTy))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
s_22)
| (__nat_10, (DisplayType (EffectSetTy))) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
s_23)
| (__nat_11, (DisplayType ((ProductTy (v_elements))))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(Base.string_append s_15 (Base.string_append (f_type_display (v_rest) ((DisplayElements (v_elements)))) s_17)))
| (__nat_12, (DisplayType ((ArrayTy (v_element))))) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(Base.string_append s_24 (Base.string_append (f_type_display (v_rest) ((DisplayType (v_element)))) s_17)))
| (__nat_13, (DisplayType ((FreeTy (v_scope, v_name))))) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
v_name)
| (__nat_14, (DisplayType ((ParameterTy (v_index))))) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(Base.string_append s_25 (Base.nat_show (v_index))))
| (__nat_15, (DisplayType ((VariableTy (v_index))))) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(Base.string_append s_26 (Base.nat_show (v_index))))
| (__nat_16, (DisplayType (NeverTy))) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
s_27)
| (__nat_17, (DisplayArguments ([]))) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
s_3)
| (__nat_18, (DisplayArguments ((v_head :: v_tail)))) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
(Base.string_append s_20 (Base.string_append (f_type_display (v_rest) ((DisplayType (v_head)))) (Base.string_append s_17 (f_type_display (v_rest) ((DisplayArguments (v_tail))))))))
| (__nat_19, (DisplayElements ([]))) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
s_3)
| (__nat_20, (DisplayElements ((v_head :: [])))) when __nat_20 >= 1 ->
(let v_rest = (__nat_20 - 1) in
(f_type_display (v_rest) ((DisplayType (v_head)))))
| (__nat_21, (DisplayElements ((v_head :: (v_next :: v_tail))))) when __nat_21 >= 1 ->
(let v_rest = (__nat_21 - 1) in
(Base.string_append (f_type_display (v_rest) ((DisplayType (v_head)))) (Base.string_append s_7 (f_type_display (v_rest) ((DisplayElements ((v_next :: v_tail)))))))))
and (* model.bend:342 *)
f_type_show : t_Ty -> Base.text =
fun v_ty ->
(f_type_display (64) ((DisplayType (v_ty))))
and (* model.bend:345 *)
f_scalar_result : t_ScalarOp -> t_Ty =
fun v_operator ->
(match v_operator with
| Add ->
U32Ty
| Subtract ->
U32Ty
| Multiply ->
U32Ty
| Equal ->
BoolTy
| LessThan ->
BoolTy
| F32Add ->
F32Ty
| F32Subtract ->
F32Ty
| F32Multiply ->
F32Ty
| F32Divide ->
F32Ty
| _ ->
BoolTy)
and (* model.bend:368 *)
f_scalar_parameter : t_ScalarOp -> t_Ty =
fun v_operator ->
(match v_operator with
| Add ->
U32Ty
| Subtract ->
U32Ty
| Multiply ->
U32Ty
| Equal ->
U32Ty
| LessThan ->
U32Ty
| _ ->
F32Ty)
and (* model.bend:383 *)
f_unary_parameter : t_UnaryOp -> t_Ty =
fun v_operator ->
(match v_operator with
| U32ToF32 ->
U32Ty
| _ ->
F32Ty)
and (* model.bend:390 *)
f_unary_result : t_UnaryOp -> t_Ty =
fun v_operator ->
(match v_operator with
| F32ToU32 ->
U32Ty
| _ ->
F32Ty)
and (* model.bend:397 *)
f_reference_expr : t_ValueReference -> t_Expr =
fun v_reference ->
(match v_reference with
| (LocalReference (v_name)) ->
(LocalExpr (v_name))
| (ConstantReference (v_name)) ->
(ConstantExpr (v_name)))
and (* model.bend:406 *)
f_max_nat : unit -> int =
fun () ->
(Base.nat_mul ((Base.u32_to_nat (0x00ffffffl))) ((Base.u32_to_nat (0x01000001l))))
