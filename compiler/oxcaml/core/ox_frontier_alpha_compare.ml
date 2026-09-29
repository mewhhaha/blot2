(* Native semantic port of compiler/frontier_alpha_compare.bend.

   Source SHA-256: 3a565adbf4c6e39ed005bc8c0ae22b6ef37b6a3374421f24424a68b2ec746bcb

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

type t_Work =
  | TypeIdPair of M.t_TypeId * M.t_TypeId
  | RowTailPair of M.t_RowTail * M.t_RowTail
  | EffectRowPair of M.t_EffectRow * M.t_EffectRow
  | TyPair of M.t_Ty * M.t_Ty
  | PredicatePair of M.t_Predicate * M.t_Predicate
  | OperationPair of M.t_Operation * M.t_Operation
  | ConstructorPair of M.t_Constructor * M.t_Constructor
  | DataTypePair of M.t_DataType * M.t_DataType
  | ValueReferencePair of M.t_ValueReference * M.t_ValueReference
  | PatternPair of M.t_Pattern * M.t_Pattern
  | MatchArmPair of (M.t_Expr) M.t_MatchArm * (M.t_Expr) M.t_MatchArm
  | ScalarOpPair of M.t_ScalarOp * M.t_ScalarOp
  | UnaryOpPair of M.t_UnaryOp * M.t_UnaryOp
  | DispatchPair of M.t_Dispatch * M.t_Dispatch
  | ExprPair of M.t_Expr * M.t_Expr
  | FunctionPair of M.t_Function * M.t_Function
  | ConstantPair of M.t_Constant * M.t_Constant
  | ModulePair of M.t_Module * M.t_Module
  | StringPair of Base.text * Base.text
  | NatPair of int * int
  | AlphaNatPair of int * int
  | TypeIdListPair of (M.t_TypeId) list * (M.t_TypeId) list
  | TyListPair of (M.t_Ty) list * (M.t_Ty) list
  | PredicateListPair of (M.t_Predicate) list * (M.t_Predicate) list
  | TyMaybePair of (M.t_Ty) option * (M.t_Ty) option
  | StringListPair of (Base.text) list * (Base.text) list
  | ConstructorListPair of (M.t_Constructor) list * (M.t_Constructor) list
  | U32Pair of int32 * int32
  | BoolPair of bool * bool
  | PatternMaybePair of (M.t_Pattern) option * (M.t_Pattern) option
  | PatternListPair of (M.t_Pattern) list * (M.t_Pattern) list
  | ExprMaybePair of (M.t_Expr) option * (M.t_Expr) option
  | ExprListPair of (M.t_Expr) list * (M.t_Expr) list
  | MatchArmListPair of ((M.t_Expr) M.t_MatchArm) list * ((M.t_Expr) M.t_MatchArm) list
  | F32Pair of int32 * int32
  | ConstantListPair of (M.t_Constant) list * (M.t_Constant) list
  | FunctionListPair of (M.t_Function) list * (M.t_Function) list
  | DataTypeListPair of (M.t_DataType) list * (M.t_DataType) list
  | OperationListPair of (M.t_Operation) list * (M.t_Operation) list
and t_Offset =
  | Offset of int * int

let rec (* frontier_alpha_compare.bend:53 *)
f_compare_work : int -> bool -> (t_Work) list -> (t_Offset) option -> bool =
fun v_fuel v_matching v_pending v_delta ->
(match (v_fuel, v_matching, v_pending) with
| (_, false, _) ->
false
| (_, true, []) ->
true
| (0, true, _) ->
false
| (__nat_1, true, ((TypeIdPair ((M.TypeId (v_a0, v_a1)), (M.TypeId (v_b0, v_b1)))) :: v_tail)) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: ((StringPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_2, true, ((RowTailPair (M.ClosedRow, M.ClosedRow)) :: v_tail)) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_3, true, ((RowTailPair ((M.RowVariable (v_a0)), (M.RowVariable (v_b0)))) :: v_tail)) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_compare_work (v_rest) (true) (((NatPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_4, true, ((RowTailPair ((M.RowParameter (v_a0)), (M.RowParameter (v_b0)))) :: v_tail)) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_compare_work (v_rest) (true) (((NatPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_5, true, ((RowTailPair ((M.FreeRow (v_a0, v_a1)), (M.FreeRow (v_b0, v_b1)))) :: v_tail)) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: ((StringPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_6, true, ((EffectRowPair ((M.EffectRow (v_a0, v_a1)), (M.EffectRow (v_b0, v_b1)))) :: v_tail)) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(f_compare_work (v_rest) (true) (((TypeIdListPair (v_a0, v_b0)) :: ((RowTailPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_7, true, ((TyPair (M.UnitTy, M.UnitTy)) :: v_tail)) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_8, true, ((TyPair (M.U32Ty, M.U32Ty)) :: v_tail)) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_9, true, ((TyPair (M.BoolTy, M.BoolTy)) :: v_tail)) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_10, true, ((TyPair ((M.AppliedTy (v_a0, v_a1)), (M.AppliedTy (v_b0, v_b1)))) :: v_tail)) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(f_compare_work (v_rest) (true) (((TypeIdPair (v_a0, v_b0)) :: ((TyListPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_11, true, ((TyPair ((M.FunctionTy (v_a0, v_a1, v_a2)), (M.FunctionTy (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(f_compare_work (v_rest) (true) (((TyPair (v_a0, v_b0)) :: ((TyPair (v_a1, v_b1)) :: ((EffectRowPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_12, true, ((TyPair ((M.ParameterTy (v_a0)), (M.ParameterTy (v_b0)))) :: v_tail)) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(f_compare_work (v_rest) (true) (((NatPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_13, true, ((TyPair ((M.VariableTy (v_a0)), (M.VariableTy (v_b0)))) :: v_tail)) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(f_compare_work (v_rest) (true) (((NatPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_14, true, ((TyPair (M.NeverTy, M.NeverTy)) :: v_tail)) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_15, true, ((TyPair (M.F32Ty, M.F32Ty)) :: v_tail)) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_16, true, ((TyPair ((M.ProviderTy (v_a0, v_a1)), (M.ProviderTy (v_b0, v_b1)))) :: v_tail)) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(f_compare_work (v_rest) (true) (((TypeIdPair (v_a0, v_b0)) :: ((EffectRowPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_17, true, ((TyPair ((M.StateProviderTy (v_a0, v_a1, v_a2)), (M.StateProviderTy (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(f_compare_work (v_rest) (true) (((TypeIdPair (v_a0, v_b0)) :: ((TypeIdPair (v_a1, v_b1)) :: ((TyPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_18, true, ((TyPair (M.EffectDescriptorTy, M.EffectDescriptorTy)) :: v_tail)) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_19, true, ((TyPair (M.EffectSetTy, M.EffectSetTy)) :: v_tail)) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_20, true, ((TyPair ((M.ProductTy (v_a0)), (M.ProductTy (v_b0)))) :: v_tail)) when __nat_20 >= 1 ->
(let v_rest = (__nat_20 - 1) in
(f_compare_work (v_rest) (true) (((TyListPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_21, true, ((TyPair ((M.ArrayTy (v_a0)), (M.ArrayTy (v_b0)))) :: v_tail)) when __nat_21 >= 1 ->
(let v_rest = (__nat_21 - 1) in
(f_compare_work (v_rest) (true) (((TyPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_22, true, ((TyPair ((M.FreeTy (v_a0, v_a1)), (M.FreeTy (v_b0, v_b1)))) :: v_tail)) when __nat_22 >= 1 ->
(let v_rest = (__nat_22 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: ((StringPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_23, true, ((PredicatePair ((M.AssociatedPredicate (v_a0, v_a1, v_a2, v_a3, v_a4, v_a5)), (M.AssociatedPredicate (v_b0, v_b1, v_b2, v_b3, v_b4, v_b5)))) :: v_tail)) when __nat_23 >= 1 ->
(let v_rest = (__nat_23 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: ((TypeIdListPair (v_a1, v_b1)) :: ((TyPair (v_a2, v_b2)) :: ((TyPair (v_a3, v_b3)) :: ((TyPair (v_a4, v_b4)) :: ((EffectRowPair (v_a5, v_b5)) :: v_tail))))))) (v_delta)))
| (__nat_24, true, ((PredicatePair ((M.ReceiverPredicate (v_a0, v_a1, v_a2, v_a3, v_a4, v_a5)), (M.ReceiverPredicate (v_b0, v_b1, v_b2, v_b3, v_b4, v_b5)))) :: v_tail)) when __nat_24 >= 1 ->
(let v_rest = (__nat_24 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: ((TypeIdListPair (v_a1, v_b1)) :: ((TyPair (v_a2, v_b2)) :: ((TyPair (v_a3, v_b3)) :: ((TyPair (v_a4, v_b4)) :: ((EffectRowPair (v_a5, v_b5)) :: v_tail))))))) (v_delta)))
| (__nat_25, true, ((PredicatePair ((M.FieldPredicate (v_a0, v_a1, v_a2)), (M.FieldPredicate (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_25 >= 1 ->
(let v_rest = (__nat_25 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: ((TyPair (v_a1, v_b1)) :: ((TyPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_26, true, ((PredicatePair ((M.UpdatePredicate (v_a0, v_a1, v_a2, v_a3, v_a4)), (M.UpdatePredicate (v_b0, v_b1, v_b2, v_b3, v_b4)))) :: v_tail)) when __nat_26 >= 1 ->
(let v_rest = (__nat_26 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: ((TyPair (v_a1, v_b1)) :: ((TyPair (v_a2, v_b2)) :: ((TyPair (v_a3, v_b3)) :: ((EffectRowPair (v_a4, v_b4)) :: v_tail)))))) (v_delta)))
| (__nat_27, true, ((PredicatePair ((M.OperationPredicate (v_a0, v_a1, v_a2)), (M.OperationPredicate (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_27 >= 1 ->
(let v_rest = (__nat_27 - 1) in
(f_compare_work (v_rest) (true) (((TypeIdPair (v_a0, v_b0)) :: ((TyListPair (v_a1, v_b1)) :: ((TyPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_28, true, ((PredicatePair ((M.TypeRepPredicate (v_a0)), (M.TypeRepPredicate (v_b0)))) :: v_tail)) when __nat_28 >= 1 ->
(let v_rest = (__nat_28 - 1) in
(f_compare_work (v_rest) (true) (((TyPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_29, true, ((PredicatePair ((M.EffectRepPredicate (v_a0)), (M.EffectRepPredicate (v_b0)))) :: v_tail)) when __nat_29 >= 1 ->
(let v_rest = (__nat_29 - 1) in
(f_compare_work (v_rest) (true) (((EffectRowPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_30, true, ((OperationPair ((M.Operation (v_a0, v_a1, v_a2)), (M.Operation (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_30 >= 1 ->
(let v_rest = (__nat_30 - 1) in
(f_compare_work (v_rest) (true) (((TypeIdPair (v_a0, v_b0)) :: ((TyPair (v_a1, v_b1)) :: ((TyPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_31, true, ((OperationPair ((M.OperationTemplate (v_a0, v_a1, v_a2, v_a3)), (M.OperationTemplate (v_b0, v_b1, v_b2, v_b3)))) :: v_tail)) when __nat_31 >= 1 ->
(let v_rest = (__nat_31 - 1) in
(f_compare_work (v_rest) (true) (((TypeIdPair (v_a0, v_b0)) :: ((NatPair (v_a1, v_b1)) :: ((TyPair (v_a2, v_b2)) :: ((TyPair (v_a3, v_b3)) :: v_tail))))) (v_delta)))
| (__nat_32, true, ((OperationPair ((M.OperationInstance (v_a0, v_a1)), (M.OperationInstance (v_b0, v_b1)))) :: v_tail)) when __nat_32 >= 1 ->
(let v_rest = (__nat_32 - 1) in
(f_compare_work (v_rest) (true) (((TypeIdPair (v_a0, v_b0)) :: ((TyListPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_33, true, ((ConstructorPair ((M.Constructor (v_a0, v_a1, v_a2)), (M.Constructor (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_33 >= 1 ->
(let v_rest = (__nat_33 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: ((TyMaybePair (v_a1, v_b1)) :: ((StringListPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_34, true, ((DataTypePair ((M.DataType (v_a0, v_a1, v_a2)), (M.DataType (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_34 >= 1 ->
(let v_rest = (__nat_34 - 1) in
(f_compare_work (v_rest) (true) (((TypeIdPair (v_a0, v_b0)) :: ((NatPair (v_a1, v_b1)) :: ((ConstructorListPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_35, true, ((ValueReferencePair ((M.LocalReference (v_a0)), (M.LocalReference (v_b0)))) :: v_tail)) when __nat_35 >= 1 ->
(let v_rest = (__nat_35 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_36, true, ((ValueReferencePair ((M.ConstantReference (v_a0)), (M.ConstantReference (v_b0)))) :: v_tail)) when __nat_36 >= 1 ->
(let v_rest = (__nat_36 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_37, true, ((PatternPair (M.WildcardPattern, M.WildcardPattern)) :: v_tail)) when __nat_37 >= 1 ->
(let v_rest = (__nat_37 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_38, true, ((PatternPair ((M.BindingPattern (v_a0)), (M.BindingPattern (v_b0)))) :: v_tail)) when __nat_38 >= 1 ->
(let v_rest = (__nat_38 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_39, true, ((PatternPair (M.UnitPattern, M.UnitPattern)) :: v_tail)) when __nat_39 >= 1 ->
(let v_rest = (__nat_39 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_40, true, ((PatternPair ((M.U32Pattern (v_a0)), (M.U32Pattern (v_b0)))) :: v_tail)) when __nat_40 >= 1 ->
(let v_rest = (__nat_40 - 1) in
(f_compare_work (v_rest) (true) (((U32Pair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_41, true, ((PatternPair ((M.BoolPattern (v_a0)), (M.BoolPattern (v_b0)))) :: v_tail)) when __nat_41 >= 1 ->
(let v_rest = (__nat_41 - 1) in
(f_compare_work (v_rest) (true) (((BoolPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_42, true, ((PatternPair ((M.ValuePattern (v_a0)), (M.ValuePattern (v_b0)))) :: v_tail)) when __nat_42 >= 1 ->
(let v_rest = (__nat_42 - 1) in
(f_compare_work (v_rest) (true) (((ValueReferencePair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_43, true, ((PatternPair ((M.ConstructorPattern (v_a0, v_a1)), (M.ConstructorPattern (v_b0, v_b1)))) :: v_tail)) when __nat_43 >= 1 ->
(let v_rest = (__nat_43 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: ((PatternMaybePair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_44, true, ((PatternPair ((M.ProductPattern (v_a0)), (M.ProductPattern (v_b0)))) :: v_tail)) when __nat_44 >= 1 ->
(let v_rest = (__nat_44 - 1) in
(f_compare_work (v_rest) (true) (((PatternListPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_45, true, ((MatchArmPair ((M.MatchArm (v_a0, v_a1)), (M.MatchArm (v_b0, v_b1)))) :: v_tail)) when __nat_45 >= 1 ->
(let v_rest = (__nat_45 - 1) in
(f_compare_work (v_rest) (true) (((PatternListPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_46, true, ((ScalarOpPair (M.Add, M.Add)) :: v_tail)) when __nat_46 >= 1 ->
(let v_rest = (__nat_46 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_47, true, ((ScalarOpPair (M.Subtract, M.Subtract)) :: v_tail)) when __nat_47 >= 1 ->
(let v_rest = (__nat_47 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_48, true, ((ScalarOpPair (M.Multiply, M.Multiply)) :: v_tail)) when __nat_48 >= 1 ->
(let v_rest = (__nat_48 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_49, true, ((ScalarOpPair (M.Equal, M.Equal)) :: v_tail)) when __nat_49 >= 1 ->
(let v_rest = (__nat_49 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_50, true, ((ScalarOpPair (M.LessThan, M.LessThan)) :: v_tail)) when __nat_50 >= 1 ->
(let v_rest = (__nat_50 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_51, true, ((ScalarOpPair (M.F32Add, M.F32Add)) :: v_tail)) when __nat_51 >= 1 ->
(let v_rest = (__nat_51 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_52, true, ((ScalarOpPair (M.F32Subtract, M.F32Subtract)) :: v_tail)) when __nat_52 >= 1 ->
(let v_rest = (__nat_52 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_53, true, ((ScalarOpPair (M.F32Multiply, M.F32Multiply)) :: v_tail)) when __nat_53 >= 1 ->
(let v_rest = (__nat_53 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_54, true, ((ScalarOpPair (M.F32Divide, M.F32Divide)) :: v_tail)) when __nat_54 >= 1 ->
(let v_rest = (__nat_54 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_55, true, ((ScalarOpPair (M.F32Equal, M.F32Equal)) :: v_tail)) when __nat_55 >= 1 ->
(let v_rest = (__nat_55 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_56, true, ((ScalarOpPair (M.F32NotEqual, M.F32NotEqual)) :: v_tail)) when __nat_56 >= 1 ->
(let v_rest = (__nat_56 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_57, true, ((ScalarOpPair (M.F32LessThan, M.F32LessThan)) :: v_tail)) when __nat_57 >= 1 ->
(let v_rest = (__nat_57 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_58, true, ((ScalarOpPair (M.F32LessEqual, M.F32LessEqual)) :: v_tail)) when __nat_58 >= 1 ->
(let v_rest = (__nat_58 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_59, true, ((ScalarOpPair (M.F32GreaterThan, M.F32GreaterThan)) :: v_tail)) when __nat_59 >= 1 ->
(let v_rest = (__nat_59 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_60, true, ((ScalarOpPair (M.F32GreaterEqual, M.F32GreaterEqual)) :: v_tail)) when __nat_60 >= 1 ->
(let v_rest = (__nat_60 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_61, true, ((UnaryOpPair (M.F32Negate, M.F32Negate)) :: v_tail)) when __nat_61 >= 1 ->
(let v_rest = (__nat_61 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_62, true, ((UnaryOpPair (M.F32Absolute, M.F32Absolute)) :: v_tail)) when __nat_62 >= 1 ->
(let v_rest = (__nat_62 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_63, true, ((UnaryOpPair (M.F32SquareRoot, M.F32SquareRoot)) :: v_tail)) when __nat_63 >= 1 ->
(let v_rest = (__nat_63 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_64, true, ((UnaryOpPair (M.F32Floor, M.F32Floor)) :: v_tail)) when __nat_64 >= 1 ->
(let v_rest = (__nat_64 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_65, true, ((UnaryOpPair (M.F32Ceiling, M.F32Ceiling)) :: v_tail)) when __nat_65 >= 1 ->
(let v_rest = (__nat_65 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_66, true, ((UnaryOpPair (M.F32Truncate, M.F32Truncate)) :: v_tail)) when __nat_66 >= 1 ->
(let v_rest = (__nat_66 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_67, true, ((UnaryOpPair (M.U32ToF32, M.U32ToF32)) :: v_tail)) when __nat_67 >= 1 ->
(let v_rest = (__nat_67 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_68, true, ((UnaryOpPair (M.F32ToU32, M.F32ToU32)) :: v_tail)) when __nat_68 >= 1 ->
(let v_rest = (__nat_68 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_69, true, ((DispatchPair (M.BinaryDispatch, M.BinaryDispatch)) :: v_tail)) when __nat_69 >= 1 ->
(let v_rest = (__nat_69 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_70, true, ((DispatchPair (M.MemberDispatch, M.MemberDispatch)) :: v_tail)) when __nat_70 >= 1 ->
(let v_rest = (__nat_70 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_71, true, ((DispatchPair (M.FieldUpdateDispatch, M.FieldUpdateDispatch)) :: v_tail)) when __nat_71 >= 1 ->
(let v_rest = (__nat_71 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_72, true, ((ExprPair (M.UnitExpr, M.UnitExpr)) :: v_tail)) when __nat_72 >= 1 ->
(let v_rest = (__nat_72 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_73, true, ((ExprPair ((M.U32Expr (v_a0)), (M.U32Expr (v_b0)))) :: v_tail)) when __nat_73 >= 1 ->
(let v_rest = (__nat_73 - 1) in
(f_compare_work (v_rest) (true) (((U32Pair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_74, true, ((ExprPair ((M.BoolExpr (v_a0)), (M.BoolExpr (v_b0)))) :: v_tail)) when __nat_74 >= 1 ->
(let v_rest = (__nat_74 - 1) in
(f_compare_work (v_rest) (true) (((BoolPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_75, true, ((ExprPair ((M.LocalExpr (v_a0)), (M.LocalExpr (v_b0)))) :: v_tail)) when __nat_75 >= 1 ->
(let v_rest = (__nat_75 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_76, true, ((ExprPair ((M.ConstantExpr (v_a0)), (M.ConstantExpr (v_b0)))) :: v_tail)) when __nat_76 >= 1 ->
(let v_rest = (__nat_76 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_77, true, ((ExprPair ((M.FunctionExpr (v_a0)), (M.FunctionExpr (v_b0)))) :: v_tail)) when __nat_77 >= 1 ->
(let v_rest = (__nat_77 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_78, true, ((ExprPair ((M.ConstructorRefExpr (v_a0)), (M.ConstructorRefExpr (v_b0)))) :: v_tail)) when __nat_78 >= 1 ->
(let v_rest = (__nat_78 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_79, true, ((ExprPair ((M.ConstructExpr (v_a0, v_a1)), (M.ConstructExpr (v_b0, v_b1)))) :: v_tail)) when __nat_79 >= 1 ->
(let v_rest = (__nat_79 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: ((ExprMaybePair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_80, true, ((ExprPair ((M.LambdaExpr (v_a0, v_a1, v_a2, v_a3, v_a4)), (M.LambdaExpr (v_b0, v_b1, v_b2, v_b3, v_b4)))) :: v_tail)) when __nat_80 >= 1 ->
(let v_rest = (__nat_80 - 1) in
(f_compare_work (v_rest) (true) (((AlphaNatPair (v_a0, v_b0)) :: ((StringPair (v_a1, v_b1)) :: ((TyMaybePair (v_a2, v_b2)) :: ((TyMaybePair (v_a3, v_b3)) :: ((ExprPair (v_a4, v_b4)) :: v_tail)))))) (v_delta)))
| (__nat_81, true, ((ExprPair ((M.ApplyExpr (v_a0, v_a1)), (M.ApplyExpr (v_b0, v_b1)))) :: v_tail)) when __nat_81 >= 1 ->
(let v_rest = (__nat_81 - 1) in
(f_compare_work (v_rest) (true) (((ExprPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_82, true, ((ExprPair ((M.CallExpr (v_a0, v_a1)), (M.CallExpr (v_b0, v_b1)))) :: v_tail)) when __nat_82 >= 1 ->
(let v_rest = (__nat_82 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_83, true, ((ExprPair ((M.ScalarExpr (v_a0, v_a1, v_a2)), (M.ScalarExpr (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_83 >= 1 ->
(let v_rest = (__nat_83 - 1) in
(f_compare_work (v_rest) (true) (((ScalarOpPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: ((ExprPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_84, true, ((ExprPair ((M.LetExpr (v_a0, v_a1, v_a2)), (M.LetExpr (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_84 >= 1 ->
(let v_rest = (__nat_84 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: ((ExprPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_85, true, ((ExprPair ((M.UseExpr (v_a0, v_a1, v_a2)), (M.UseExpr (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_85 >= 1 ->
(let v_rest = (__nat_85 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: ((ExprPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_86, true, ((ExprPair ((M.IfExpr (v_a0, v_a1, v_a2)), (M.IfExpr (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_86 >= 1 ->
(let v_rest = (__nat_86 - 1) in
(f_compare_work (v_rest) (true) (((ExprPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: ((ExprPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_87, true, ((ExprPair ((M.SequenceExpr (v_a0, v_a1)), (M.SequenceExpr (v_b0, v_b1)))) :: v_tail)) when __nat_87 >= 1 ->
(let v_rest = (__nat_87 - 1) in
(f_compare_work (v_rest) (true) (((ExprPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_88, true, ((ExprPair ((M.MatchExpr (v_a0, v_a1)), (M.MatchExpr (v_b0, v_b1)))) :: v_tail)) when __nat_88 >= 1 ->
(let v_rest = (__nat_88 - 1) in
(f_compare_work (v_rest) (true) (((ExprListPair (v_a0, v_b0)) :: ((MatchArmListPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_89, true, ((ExprPair ((M.GuardExpr (v_a0, v_a1, v_a2, v_a3)), (M.GuardExpr (v_b0, v_b1, v_b2, v_b3)))) :: v_tail)) when __nat_89 >= 1 ->
(let v_rest = (__nat_89 - 1) in
(f_compare_work (v_rest) (true) (((PatternPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: ((ExprPair (v_a2, v_b2)) :: ((ExprPair (v_a3, v_b3)) :: v_tail))))) (v_delta)))
| (__nat_90, true, ((ExprPair ((M.BlockExpr (v_a0, v_a1)), (M.BlockExpr (v_b0, v_b1)))) :: v_tail)) when __nat_90 >= 1 ->
(let v_rest = (__nat_90 - 1) in
(f_compare_work (v_rest) (true) (((AlphaNatPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_91, true, ((ExprPair ((M.ReturnExpr (v_a0, v_a1)), (M.ReturnExpr (v_b0, v_b1)))) :: v_tail)) when __nat_91 >= 1 ->
(let v_rest = (__nat_91 - 1) in
(f_compare_work (v_rest) (true) (((AlphaNatPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_92, true, ((ExprPair ((M.SourceExpr (v_a0, v_a1, v_a2)), (M.SourceExpr (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_92 >= 1 ->
(let v_rest = (__nat_92 - 1) in
(f_compare_work (v_rest) (true) (((NatPair (v_a0, v_b0)) :: ((TyMaybePair (v_a1, v_b1)) :: ((ExprPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_93, true, ((ExprPair ((M.QualifiedExpr (v_a0, v_a1, v_a2, v_a3)), (M.QualifiedExpr (v_b0, v_b1, v_b2, v_b3)))) :: v_tail)) when __nat_93 >= 1 ->
(let v_rest = (__nat_93 - 1) in
(f_compare_work (v_rest) (true) (((NatPair (v_a0, v_b0)) :: ((TyPair (v_a1, v_b1)) :: ((PredicateListPair (v_a2, v_b2)) :: ((ExprPair (v_a3, v_b3)) :: v_tail))))) (v_delta)))
| (__nat_94, true, ((ExprPair ((M.InstantiationExpr (v_a0, v_a1)), (M.InstantiationExpr (v_b0, v_b1)))) :: v_tail)) when __nat_94 >= 1 ->
(let v_rest = (__nat_94 - 1) in
(f_compare_work (v_rest) (true) (((AlphaNatPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_95, true, ((ExprPair ((M.TagExpr (v_a0, v_a1, v_a2)), (M.TagExpr (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_95 >= 1 ->
(let v_rest = (__nat_95 - 1) in
(f_compare_work (v_rest) (true) (((NatPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: ((ExprPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_96, true, ((ExprPair ((M.RuntimeInitExpr (v_a0)), (M.RuntimeInitExpr (v_b0)))) :: v_tail)) when __nat_96 >= 1 ->
(let v_rest = (__nat_96 - 1) in
(f_compare_work (v_rest) (true) (((ExprPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_97, true, ((ExprPair ((M.F32Expr (v_a0)), (M.F32Expr (v_b0)))) :: v_tail)) when __nat_97 >= 1 ->
(let v_rest = (__nat_97 - 1) in
(f_compare_work (v_rest) (true) (((F32Pair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_98, true, ((ExprPair ((M.UnaryExpr (v_a0, v_a1)), (M.UnaryExpr (v_b0, v_b1)))) :: v_tail)) when __nat_98 >= 1 ->
(let v_rest = (__nat_98 - 1) in
(f_compare_work (v_rest) (true) (((UnaryOpPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_99, true, ((ExprPair ((M.OperationExpr (v_a0)), (M.OperationExpr (v_b0)))) :: v_tail)) when __nat_99 >= 1 ->
(let v_rest = (__nat_99 - 1) in
(f_compare_work (v_rest) (true) (((TypeIdPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_100, true, ((ExprPair ((M.SpecializeOperationExpr (v_a0, v_a1, v_a2)), (M.SpecializeOperationExpr (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_100 >= 1 ->
(let v_rest = (__nat_100 - 1) in
(f_compare_work (v_rest) (true) (((TypeIdPair (v_a0, v_b0)) :: ((TyListPair (v_a1, v_b1)) :: ((ExprPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_101, true, ((ExprPair ((M.ProviderExpr (v_a0, v_a1)), (M.ProviderExpr (v_b0, v_b1)))) :: v_tail)) when __nat_101 >= 1 ->
(let v_rest = (__nat_101 - 1) in
(f_compare_work (v_rest) (true) (((TypeIdPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_102, true, ((ExprPair ((M.StateProviderExpr (v_a0, v_a1, v_a2)), (M.StateProviderExpr (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_102 >= 1 ->
(let v_rest = (__nat_102 - 1) in
(f_compare_work (v_rest) (true) (((TypeIdPair (v_a0, v_b0)) :: ((TypeIdPair (v_a1, v_b1)) :: ((ExprPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_103, true, ((ExprPair ((M.HandleExpr (v_a0, v_a1)), (M.HandleExpr (v_b0, v_b1)))) :: v_tail)) when __nat_103 >= 1 ->
(let v_rest = (__nat_103 - 1) in
(f_compare_work (v_rest) (true) (((ExprPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_104, true, ((ExprPair ((M.OperationDescriptorExpr (v_a0)), (M.OperationDescriptorExpr (v_b0)))) :: v_tail)) when __nat_104 >= 1 ->
(let v_rest = (__nat_104 - 1) in
(f_compare_work (v_rest) (true) (((TypeIdPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_105, true, ((ExprPair ((M.FunctionEffectsExpr (v_a0)), (M.FunctionEffectsExpr (v_b0)))) :: v_tail)) when __nat_105 >= 1 ->
(let v_rest = (__nat_105 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_106, true, ((ExprPair ((M.EffectHasExpr (v_a0, v_a1)), (M.EffectHasExpr (v_b0, v_b1)))) :: v_tail)) when __nat_106 >= 1 ->
(let v_rest = (__nat_106 - 1) in
(f_compare_work (v_rest) (true) (((ExprPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_107, true, ((ExprPair ((M.EffectCountExpr (v_a0)), (M.EffectCountExpr (v_b0)))) :: v_tail)) when __nat_107 >= 1 ->
(let v_rest = (__nat_107 - 1) in
(f_compare_work (v_rest) (true) (((ExprPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_108, true, ((ExprPair ((M.EffectSameExpr (v_a0, v_a1)), (M.EffectSameExpr (v_b0, v_b1)))) :: v_tail)) when __nat_108 >= 1 ->
(let v_rest = (__nat_108 - 1) in
(f_compare_work (v_rest) (true) (((ExprPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_109, true, ((ExprPair ((M.PanicExpr (v_a0)), (M.PanicExpr (v_b0)))) :: v_tail)) when __nat_109 >= 1 ->
(let v_rest = (__nat_109 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_110, true, ((ExprPair ((M.ProductExpr (v_a0)), (M.ProductExpr (v_b0)))) :: v_tail)) when __nat_110 >= 1 ->
(let v_rest = (__nat_110 - 1) in
(f_compare_work (v_rest) (true) (((ExprListPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_111, true, ((ExprPair ((M.ProjectExpr (v_a0, v_a1)), (M.ProjectExpr (v_b0, v_b1)))) :: v_tail)) when __nat_111 >= 1 ->
(let v_rest = (__nat_111 - 1) in
(f_compare_work (v_rest) (true) (((ExprPair (v_a0, v_b0)) :: ((NatPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_112, true, ((ExprPair ((M.ArrayExpr (v_a0)), (M.ArrayExpr (v_b0)))) :: v_tail)) when __nat_112 >= 1 ->
(let v_rest = (__nat_112 - 1) in
(f_compare_work (v_rest) (true) (((ExprListPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_113, true, ((ExprPair ((M.ForExpr (v_a0, v_a1, v_a2, v_a3, v_a4, v_a5)), (M.ForExpr (v_b0, v_b1, v_b2, v_b3, v_b4, v_b5)))) :: v_tail)) when __nat_113 >= 1 ->
(let v_rest = (__nat_113 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: ((ExprPair (v_a2, v_b2)) :: ((StringPair (v_a3, v_b3)) :: ((ExprPair (v_a4, v_b4)) :: ((ExprPair (v_a5, v_b5)) :: v_tail))))))) (v_delta)))
| (__nat_114, true, ((ExprPair ((M.ForeverExpr (v_a0, v_a1, v_a2)), (M.ForeverExpr (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_114 >= 1 ->
(let v_rest = (__nat_114 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: ((ExprPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_115, true, ((ExprPair ((M.ArrayGenerateExpr (v_a0, v_a1)), (M.ArrayGenerateExpr (v_b0, v_b1)))) :: v_tail)) when __nat_115 >= 1 ->
(let v_rest = (__nat_115 - 1) in
(f_compare_work (v_rest) (true) (((ExprPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_116, true, ((ExprPair ((M.ArrayFillExpr (v_a0, v_a1)), (M.ArrayFillExpr (v_b0, v_b1)))) :: v_tail)) when __nat_116 >= 1 ->
(let v_rest = (__nat_116 - 1) in
(f_compare_work (v_rest) (true) (((ExprPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_117, true, ((ExprPair ((M.ArrayGetExpr (v_a0, v_a1)), (M.ArrayGetExpr (v_b0, v_b1)))) :: v_tail)) when __nat_117 >= 1 ->
(let v_rest = (__nat_117 - 1) in
(f_compare_work (v_rest) (true) (((ExprPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: v_tail))) (v_delta)))
| (__nat_118, true, ((ExprPair ((M.ArraySetExpr (v_a0, v_a1, v_a2)), (M.ArraySetExpr (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_118 >= 1 ->
(let v_rest = (__nat_118 - 1) in
(f_compare_work (v_rest) (true) (((ExprPair (v_a0, v_b0)) :: ((ExprPair (v_a1, v_b1)) :: ((ExprPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_119, true, ((ExprPair ((M.ArrayLengthExpr (v_a0)), (M.ArrayLengthExpr (v_b0)))) :: v_tail)) when __nat_119 >= 1 ->
(let v_rest = (__nat_119 - 1) in
(f_compare_work (v_rest) (true) (((ExprPair (v_a0, v_b0)) :: v_tail)) (v_delta)))
| (__nat_120, true, ((ExprPair ((M.AssociatedExpr (v_a0, v_a1, v_a2, v_a3, v_a4, v_a5)), (M.AssociatedExpr (v_b0, v_b1, v_b2, v_b3, v_b4, v_b5)))) :: v_tail)) when __nat_120 >= 1 ->
(let v_rest = (__nat_120 - 1) in
(f_compare_work (v_rest) (true) (((NatPair (v_a0, v_b0)) :: ((DispatchPair (v_a1, v_b1)) :: ((StringPair (v_a2, v_b2)) :: ((TypeIdListPair (v_a3, v_b3)) :: ((ExprPair (v_a4, v_b4)) :: ((ExprPair (v_a5, v_b5)) :: v_tail))))))) (v_delta)))
| (__nat_121, true, ((ExprPair ((M.GenericOperationExpr (v_a0, v_a1, v_a2)), (M.GenericOperationExpr (v_b0, v_b1, v_b2)))) :: v_tail)) when __nat_121 >= 1 ->
(let v_rest = (__nat_121 - 1) in
(f_compare_work (v_rest) (true) (((NatPair (v_a0, v_b0)) :: ((TypeIdPair (v_a1, v_b1)) :: ((TyListPair (v_a2, v_b2)) :: v_tail)))) (v_delta)))
| (__nat_122, true, ((FunctionPair ((M.Function (v_a0, v_a1, v_a2, v_a3, v_a4, v_a5)), (M.Function (v_b0, v_b1, v_b2, v_b3, v_b4, v_b5)))) :: v_tail)) when __nat_122 >= 1 ->
(let v_rest = (__nat_122 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: ((BoolPair (v_a1, v_b1)) :: ((StringPair (v_a2, v_b2)) :: ((TyMaybePair (v_a3, v_b3)) :: ((TyMaybePair (v_a4, v_b4)) :: ((ExprPair (v_a5, v_b5)) :: v_tail))))))) (v_delta)))
| (__nat_123, true, ((ConstantPair ((M.Constant (v_a0, v_a1, v_a2, v_a3)), (M.Constant (v_b0, v_b1, v_b2, v_b3)))) :: v_tail)) when __nat_123 >= 1 ->
(let v_rest = (__nat_123 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a0, v_b0)) :: ((BoolPair (v_a1, v_b1)) :: ((TyMaybePair (v_a2, v_b2)) :: ((ExprPair (v_a3, v_b3)) :: v_tail))))) (v_delta)))
| (__nat_124, true, ((ModulePair ((M.Module (v_a0, v_a1, v_a2, v_a3)), (M.Module (v_b0, v_b1, v_b2, v_b3)))) :: v_tail)) when __nat_124 >= 1 ->
(let v_rest = (__nat_124 - 1) in
(f_compare_work (v_rest) (true) (((ConstantListPair (v_a0, v_b0)) :: ((FunctionListPair (v_a1, v_b1)) :: ((DataTypeListPair (v_a2, v_b2)) :: ((OperationListPair (v_a3, v_b3)) :: v_tail))))) (v_delta)))
| (__nat_125, true, ((StringPair (v_a, v_b)) :: v_tail)) when __nat_125 >= 1 ->
(let v_rest = (__nat_125 - 1) in
(f_compare_work (v_rest) ((M.f_name_equal (v_a) (v_b))) (v_tail) (v_delta)))
| (__nat_126, true, ((AlphaNatPair (v_left, v_right)) :: v_tail)) when __nat_126 >= 1 ->
(let v_rest = (__nat_126 - 1) in
(match v_delta with
| None ->
(f_compare_work (v_rest) (true) (v_tail) ((Some ((Offset (v_left, v_right))))))
| (Some ((Offset (v_first_left, v_first_right)))) ->
(f_compare_work (v_rest) ((Base.bool_and ((Base.nat_is_eq ((Base.nat_sub (v_left) (v_first_left))) ((Base.nat_sub (v_right) (v_first_right))))) ((Base.nat_is_eq ((Base.nat_sub (v_first_left) (v_left))) ((Base.nat_sub (v_first_right) (v_right))))))) (v_tail) ((Some ((Offset (v_first_left, v_first_right))))))))
| (__nat_127, true, ((NatPair (v_a, v_b)) :: v_tail)) when __nat_127 >= 1 ->
(let v_rest = (__nat_127 - 1) in
(f_compare_work (v_rest) ((Base.nat_is_eq (v_a) (v_b))) (v_tail) (v_delta)))
| (__nat_128, true, ((TypeIdListPair ([], [])) :: v_tail)) when __nat_128 >= 1 ->
(let v_rest = (__nat_128 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_129, true, ((TypeIdListPair ((v_a :: v_at), (v_b :: v_bt))) :: v_tail)) when __nat_129 >= 1 ->
(let v_rest = (__nat_129 - 1) in
(f_compare_work (v_rest) (true) (((TypeIdPair (v_a, v_b)) :: ((TypeIdListPair (v_at, v_bt)) :: v_tail))) (v_delta)))
| (__nat_130, true, ((TyListPair ([], [])) :: v_tail)) when __nat_130 >= 1 ->
(let v_rest = (__nat_130 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_131, true, ((TyListPair ((v_a :: v_at), (v_b :: v_bt))) :: v_tail)) when __nat_131 >= 1 ->
(let v_rest = (__nat_131 - 1) in
(f_compare_work (v_rest) (true) (((TyPair (v_a, v_b)) :: ((TyListPair (v_at, v_bt)) :: v_tail))) (v_delta)))
| (__nat_132, true, ((PredicateListPair ([], [])) :: v_tail)) when __nat_132 >= 1 ->
(let v_rest = (__nat_132 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_133, true, ((PredicateListPair ((v_a :: v_at), (v_b :: v_bt))) :: v_tail)) when __nat_133 >= 1 ->
(let v_rest = (__nat_133 - 1) in
(f_compare_work (v_rest) (true) (((PredicatePair (v_a, v_b)) :: ((PredicateListPair (v_at, v_bt)) :: v_tail))) (v_delta)))
| (__nat_134, true, ((TyMaybePair (None, None)) :: v_tail)) when __nat_134 >= 1 ->
(let v_rest = (__nat_134 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_135, true, ((TyMaybePair ((Some (v_a)), (Some (v_b)))) :: v_tail)) when __nat_135 >= 1 ->
(let v_rest = (__nat_135 - 1) in
(f_compare_work (v_rest) (true) (((TyPair (v_a, v_b)) :: v_tail)) (v_delta)))
| (__nat_136, true, ((StringListPair ([], [])) :: v_tail)) when __nat_136 >= 1 ->
(let v_rest = (__nat_136 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_137, true, ((StringListPair ((v_a :: v_at), (v_b :: v_bt))) :: v_tail)) when __nat_137 >= 1 ->
(let v_rest = (__nat_137 - 1) in
(f_compare_work (v_rest) (true) (((StringPair (v_a, v_b)) :: ((StringListPair (v_at, v_bt)) :: v_tail))) (v_delta)))
| (__nat_138, true, ((ConstructorListPair ([], [])) :: v_tail)) when __nat_138 >= 1 ->
(let v_rest = (__nat_138 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_139, true, ((ConstructorListPair ((v_a :: v_at), (v_b :: v_bt))) :: v_tail)) when __nat_139 >= 1 ->
(let v_rest = (__nat_139 - 1) in
(f_compare_work (v_rest) (true) (((ConstructorPair (v_a, v_b)) :: ((ConstructorListPair (v_at, v_bt)) :: v_tail))) (v_delta)))
| (__nat_140, true, ((U32Pair (v_a, v_b)) :: v_tail)) when __nat_140 >= 1 ->
(let v_rest = (__nat_140 - 1) in
(f_compare_work (v_rest) ((Base.u32_is_eq (v_a) (v_b))) (v_tail) (v_delta)))
| (__nat_141, true, ((BoolPair (v_a, v_b)) :: v_tail)) when __nat_141 >= 1 ->
(let v_rest = (__nat_141 - 1) in
(f_compare_work (v_rest) ((Base.bool_not ((Base.bool_xor (v_a) (v_b))))) (v_tail) (v_delta)))
| (__nat_142, true, ((PatternMaybePair (None, None)) :: v_tail)) when __nat_142 >= 1 ->
(let v_rest = (__nat_142 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_143, true, ((PatternMaybePair ((Some (v_a)), (Some (v_b)))) :: v_tail)) when __nat_143 >= 1 ->
(let v_rest = (__nat_143 - 1) in
(f_compare_work (v_rest) (true) (((PatternPair (v_a, v_b)) :: v_tail)) (v_delta)))
| (__nat_144, true, ((PatternListPair ([], [])) :: v_tail)) when __nat_144 >= 1 ->
(let v_rest = (__nat_144 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_145, true, ((PatternListPair ((v_a :: v_at), (v_b :: v_bt))) :: v_tail)) when __nat_145 >= 1 ->
(let v_rest = (__nat_145 - 1) in
(f_compare_work (v_rest) (true) (((PatternPair (v_a, v_b)) :: ((PatternListPair (v_at, v_bt)) :: v_tail))) (v_delta)))
| (__nat_146, true, ((ExprMaybePair (None, None)) :: v_tail)) when __nat_146 >= 1 ->
(let v_rest = (__nat_146 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_147, true, ((ExprMaybePair ((Some (v_a)), (Some (v_b)))) :: v_tail)) when __nat_147 >= 1 ->
(let v_rest = (__nat_147 - 1) in
(f_compare_work (v_rest) (true) (((ExprPair (v_a, v_b)) :: v_tail)) (v_delta)))
| (__nat_148, true, ((ExprListPair ([], [])) :: v_tail)) when __nat_148 >= 1 ->
(let v_rest = (__nat_148 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_149, true, ((ExprListPair ((v_a :: v_at), (v_b :: v_bt))) :: v_tail)) when __nat_149 >= 1 ->
(let v_rest = (__nat_149 - 1) in
(f_compare_work (v_rest) (true) (((ExprPair (v_a, v_b)) :: ((ExprListPair (v_at, v_bt)) :: v_tail))) (v_delta)))
| (__nat_150, true, ((MatchArmListPair ([], [])) :: v_tail)) when __nat_150 >= 1 ->
(let v_rest = (__nat_150 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_151, true, ((MatchArmListPair ((v_a :: v_at), (v_b :: v_bt))) :: v_tail)) when __nat_151 >= 1 ->
(let v_rest = (__nat_151 - 1) in
(f_compare_work (v_rest) (true) (((MatchArmPair (v_a, v_b)) :: ((MatchArmListPair (v_at, v_bt)) :: v_tail))) (v_delta)))
| (__nat_152, true, ((F32Pair (v_a, v_b)) :: v_tail)) when __nat_152 >= 1 ->
(let v_rest = (__nat_152 - 1) in
(f_compare_work (v_rest) ((Base.u32_is_eq ((Base.f32_bits (v_a))) ((Base.f32_bits (v_b))))) (v_tail) (v_delta)))
| (__nat_153, true, ((ConstantListPair ([], [])) :: v_tail)) when __nat_153 >= 1 ->
(let v_rest = (__nat_153 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_154, true, ((ConstantListPair ((v_a :: v_at), (v_b :: v_bt))) :: v_tail)) when __nat_154 >= 1 ->
(let v_rest = (__nat_154 - 1) in
(f_compare_work (v_rest) (true) (((ConstantPair (v_a, v_b)) :: ((ConstantListPair (v_at, v_bt)) :: v_tail))) (v_delta)))
| (__nat_155, true, ((FunctionListPair ([], [])) :: v_tail)) when __nat_155 >= 1 ->
(let v_rest = (__nat_155 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_156, true, ((FunctionListPair ((v_a :: v_at), (v_b :: v_bt))) :: v_tail)) when __nat_156 >= 1 ->
(let v_rest = (__nat_156 - 1) in
(f_compare_work (v_rest) (true) (((FunctionPair (v_a, v_b)) :: ((FunctionListPair (v_at, v_bt)) :: v_tail))) (v_delta)))
| (__nat_157, true, ((DataTypeListPair ([], [])) :: v_tail)) when __nat_157 >= 1 ->
(let v_rest = (__nat_157 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_158, true, ((DataTypeListPair ((v_a :: v_at), (v_b :: v_bt))) :: v_tail)) when __nat_158 >= 1 ->
(let v_rest = (__nat_158 - 1) in
(f_compare_work (v_rest) (true) (((DataTypePair (v_a, v_b)) :: ((DataTypeListPair (v_at, v_bt)) :: v_tail))) (v_delta)))
| (__nat_159, true, ((OperationListPair ([], [])) :: v_tail)) when __nat_159 >= 1 ->
(let v_rest = (__nat_159 - 1) in
(f_compare_work (v_rest) (true) (v_tail) (v_delta)))
| (__nat_160, true, ((OperationListPair ((v_a :: v_at), (v_b :: v_bt))) :: v_tail)) when __nat_160 >= 1 ->
(let v_rest = (__nat_160 - 1) in
(f_compare_work (v_rest) (true) (((OperationPair (v_a, v_b)) :: ((OperationListPair (v_at, v_bt)) :: v_tail))) (v_delta)))
| (_, _, _) ->
false)
and (* frontier_alpha_compare.bend:388 *)
f_same_alpha_module : M.t_Module -> M.t_Module -> bool =
fun v_left v_right ->
(f_compare_work (1048576) (true) ([(ModulePair (v_left, v_right))]) (None))
