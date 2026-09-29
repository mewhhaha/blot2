import Base
import ./model.bend as M

# Exact core equality preserves source offsets, annotations, nominal identities,
# ordered duplicate effect labels, and floating-point bit patterns. A mismatch
# or exhausted traversal budget is always a cache miss. The explicit worklist
# avoids host recursion on deeply nested expressions and temporary byte keys.
type Work is Data:
  TypeIdPair{left: M.TypeId, right: M.TypeId}
  RowTailPair{left: M.RowTail, right: M.RowTail}
  EffectRowPair{left: M.EffectRow, right: M.EffectRow}
  TyPair{left: M.Ty, right: M.Ty}
  PredicatePair{left: M.Predicate, right: M.Predicate}
  OperationPair{left: M.Operation, right: M.Operation}
  ConstructorPair{left: M.Constructor, right: M.Constructor}
  DataTypePair{left: M.DataType, right: M.DataType}
  ValueReferencePair{left: M.ValueReference, right: M.ValueReference}
  PatternPair{left: M.Pattern, right: M.Pattern}
  MatchArmPair{left: M.MatchArm<M.Expr>, right: M.MatchArm<M.Expr>}
  ScalarOpPair{left: M.ScalarOp, right: M.ScalarOp}
  UnaryOpPair{left: M.UnaryOp, right: M.UnaryOp}
  DispatchPair{left: M.Dispatch, right: M.Dispatch}
  ExprPair{left: M.Expr, right: M.Expr}
  FunctionPair{left: M.Function, right: M.Function}
  ConstantPair{left: M.Constant, right: M.Constant}
  ModulePair{left: M.Module, right: M.Module}
  StringPair{left: String, right: String}
  NatPair{left: Nat, right: Nat}
  TypeIdListPair{left: List<&2, M.TypeId>, right: List<&2, M.TypeId>}
  TyListPair{left: List<&2, M.Ty>, right: List<&2, M.Ty>}
  PredicateListPair{left: List<&2, M.Predicate>, right: List<&2, M.Predicate>}
  TyMaybePair{left: Maybe<&2, M.Ty>, right: Maybe<&2, M.Ty>}
  StringListPair{left: List<&2, String>, right: List<&2, String>}
  ConstructorListPair{left: List<&2, M.Constructor>, right: List<&2, M.Constructor>}
  U32Pair{left: U32, right: U32}
  BoolPair{left: Bool, right: Bool}
  PatternMaybePair{left: Maybe<&2, M.Pattern>, right: Maybe<&2, M.Pattern>}
  PatternListPair{left: List<&2, M.Pattern>, right: List<&2, M.Pattern>}
  ExprMaybePair{left: Maybe<&2, M.Expr>, right: Maybe<&2, M.Expr>}
  ExprListPair{left: List<&2, M.Expr>, right: List<&2, M.Expr>}
  MatchArmListPair{left: List<&2, M.MatchArm<M.Expr>>, right: List<&2, M.MatchArm<M.Expr>>}
  F32Pair{left: F32, right: F32}
  ConstantListPair{left: List<&2, M.Constant>, right: List<&2, M.Constant>}
  FunctionListPair{left: List<&2, M.Function>, right: List<&2, M.Function>}
  DataTypeListPair{left: List<&2, M.DataType>, right: List<&2, M.DataType>}
  OperationListPair{left: List<&2, M.Operation>, right: List<&2, M.Operation>}

def compare_work(fuel: Nat, matching: Bool, pending: List<&2, Work>) -> Bool:
  match fuel matching pending:
    case _ False{} _:
      False{}
    case _ True{} Nil{}:
      True{}
    case 0n True{} _:
      False{}
    case 1n+rest True{} TypeIdPair{M.TypeId{a0, a1}, M.TypeId{b0, b1}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> StringPair{a1, b1} <> tail)
    case 1n+rest True{} RowTailPair{M.ClosedRow{}, M.ClosedRow{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} RowTailPair{M.RowVariable{a0}, M.RowVariable{b0}} <> tail:
      compare_work(rest, True{}, NatPair{a0, b0} <> tail)
    case 1n+rest True{} RowTailPair{M.RowParameter{a0}, M.RowParameter{b0}} <> tail:
      compare_work(rest, True{}, NatPair{a0, b0} <> tail)
    case 1n+rest True{} RowTailPair{M.FreeRow{a0, a1}, M.FreeRow{b0, b1}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> StringPair{a1, b1} <> tail)
    case 1n+rest True{} EffectRowPair{M.EffectRow{a0, a1}, M.EffectRow{b0, b1}} <> tail:
      compare_work(rest, True{}, TypeIdListPair{a0, b0} <> RowTailPair{a1, b1} <> tail)
    case 1n+rest True{} TyPair{M.UnitTy{}, M.UnitTy{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} TyPair{M.U32Ty{}, M.U32Ty{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} TyPair{M.BoolTy{}, M.BoolTy{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} TyPair{M.AppliedTy{a0, a1}, M.AppliedTy{b0, b1}} <> tail:
      compare_work(rest, True{}, TypeIdPair{a0, b0} <> TyListPair{a1, b1} <> tail)
    case 1n+rest True{} TyPair{M.FunctionTy{a0, a1, a2}, M.FunctionTy{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, TyPair{a0, b0} <> TyPair{a1, b1} <> EffectRowPair{a2, b2} <> tail)
    case 1n+rest True{} TyPair{M.ParameterTy{a0}, M.ParameterTy{b0}} <> tail:
      compare_work(rest, True{}, NatPair{a0, b0} <> tail)
    case 1n+rest True{} TyPair{M.VariableTy{a0}, M.VariableTy{b0}} <> tail:
      compare_work(rest, True{}, NatPair{a0, b0} <> tail)
    case 1n+rest True{} TyPair{M.NeverTy{}, M.NeverTy{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} TyPair{M.F32Ty{}, M.F32Ty{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} TyPair{M.ProviderTy{a0, a1}, M.ProviderTy{b0, b1}} <> tail:
      compare_work(rest, True{}, TypeIdPair{a0, b0} <> EffectRowPair{a1, b1} <> tail)
    case 1n+rest True{} TyPair{M.StateProviderTy{a0, a1, a2}, M.StateProviderTy{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, TypeIdPair{a0, b0} <> TypeIdPair{a1, b1} <> TyPair{a2, b2} <> tail)
    case 1n+rest True{} TyPair{M.EffectDescriptorTy{}, M.EffectDescriptorTy{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} TyPair{M.EffectSetTy{}, M.EffectSetTy{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} TyPair{M.ProductTy{a0}, M.ProductTy{b0}} <> tail:
      compare_work(rest, True{}, TyListPair{a0, b0} <> tail)
    case 1n+rest True{} TyPair{M.ArrayTy{a0}, M.ArrayTy{b0}} <> tail:
      compare_work(rest, True{}, TyPair{a0, b0} <> tail)
    case 1n+rest True{} TyPair{M.FreeTy{a0, a1}, M.FreeTy{b0, b1}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> StringPair{a1, b1} <> tail)
    case 1n+rest True{} PredicatePair{M.AssociatedPredicate{a0, a1, a2, a3, a4, a5}, M.AssociatedPredicate{b0, b1, b2, b3, b4, b5}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> TypeIdListPair{a1, b1} <> TyPair{a2, b2} <> TyPair{a3, b3} <> TyPair{a4, b4} <> EffectRowPair{a5, b5} <> tail)
    case 1n+rest True{} PredicatePair{M.ReceiverPredicate{a0, a1, a2, a3, a4, a5}, M.ReceiverPredicate{b0, b1, b2, b3, b4, b5}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> TypeIdListPair{a1, b1} <> TyPair{a2, b2} <> TyPair{a3, b3} <> TyPair{a4, b4} <> EffectRowPair{a5, b5} <> tail)
    case 1n+rest True{} PredicatePair{M.FieldPredicate{a0, a1, a2}, M.FieldPredicate{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> TyPair{a1, b1} <> TyPair{a2, b2} <> tail)
    case 1n+rest True{} PredicatePair{M.UpdatePredicate{a0, a1, a2, a3, a4}, M.UpdatePredicate{b0, b1, b2, b3, b4}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> TyPair{a1, b1} <> TyPair{a2, b2} <> TyPair{a3, b3} <> EffectRowPair{a4, b4} <> tail)
    case 1n+rest True{} PredicatePair{M.OperationPredicate{a0, a1, a2}, M.OperationPredicate{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, TypeIdPair{a0, b0} <> TyListPair{a1, b1} <> TyPair{a2, b2} <> tail)
    case 1n+rest True{} PredicatePair{M.TypeRepPredicate{a0}, M.TypeRepPredicate{b0}} <> tail:
      compare_work(rest, True{}, TyPair{a0, b0} <> tail)
    case 1n+rest True{} PredicatePair{M.EffectRepPredicate{a0}, M.EffectRepPredicate{b0}} <> tail:
      compare_work(rest, True{}, EffectRowPair{a0, b0} <> tail)
    case 1n+rest True{} OperationPair{M.Operation{a0, a1, a2}, M.Operation{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, TypeIdPair{a0, b0} <> TyPair{a1, b1} <> TyPair{a2, b2} <> tail)
    case 1n+rest True{} OperationPair{M.OperationTemplate{a0, a1, a2, a3}, M.OperationTemplate{b0, b1, b2, b3}} <> tail:
      compare_work(rest, True{}, TypeIdPair{a0, b0} <> NatPair{a1, b1} <> TyPair{a2, b2} <> TyPair{a3, b3} <> tail)
    case 1n+rest True{} OperationPair{M.OperationInstance{a0, a1}, M.OperationInstance{b0, b1}} <> tail:
      compare_work(rest, True{}, TypeIdPair{a0, b0} <> TyListPair{a1, b1} <> tail)
    case 1n+rest True{} ConstructorPair{M.Constructor{a0, a1, a2}, M.Constructor{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> TyMaybePair{a1, b1} <> StringListPair{a2, b2} <> tail)
    case 1n+rest True{} DataTypePair{M.DataType{a0, a1, a2}, M.DataType{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, TypeIdPair{a0, b0} <> NatPair{a1, b1} <> ConstructorListPair{a2, b2} <> tail)
    case 1n+rest True{} ValueReferencePair{M.LocalReference{a0}, M.LocalReference{b0}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> tail)
    case 1n+rest True{} ValueReferencePair{M.ConstantReference{a0}, M.ConstantReference{b0}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> tail)
    case 1n+rest True{} PatternPair{M.WildcardPattern{}, M.WildcardPattern{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} PatternPair{M.BindingPattern{a0}, M.BindingPattern{b0}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> tail)
    case 1n+rest True{} PatternPair{M.UnitPattern{}, M.UnitPattern{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} PatternPair{M.U32Pattern{a0}, M.U32Pattern{b0}} <> tail:
      compare_work(rest, True{}, U32Pair{a0, b0} <> tail)
    case 1n+rest True{} PatternPair{M.BoolPattern{a0}, M.BoolPattern{b0}} <> tail:
      compare_work(rest, True{}, BoolPair{a0, b0} <> tail)
    case 1n+rest True{} PatternPair{M.ValuePattern{a0}, M.ValuePattern{b0}} <> tail:
      compare_work(rest, True{}, ValueReferencePair{a0, b0} <> tail)
    case 1n+rest True{} PatternPair{M.ConstructorPattern{a0, a1}, M.ConstructorPattern{b0, b1}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> PatternMaybePair{a1, b1} <> tail)
    case 1n+rest True{} PatternPair{M.ProductPattern{a0}, M.ProductPattern{b0}} <> tail:
      compare_work(rest, True{}, PatternListPair{a0, b0} <> tail)
    case 1n+rest True{} MatchArmPair{M.MatchArm{a0, a1}, M.MatchArm{b0, b1}} <> tail:
      compare_work(rest, True{}, PatternListPair{a0, b0} <> ExprPair{a1, b1} <> tail)
    case 1n+rest True{} ScalarOpPair{M.U32Divide{}, M.U32Divide{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.U32Remainder{}, M.U32Remainder{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.U32BitAnd{}, M.U32BitAnd{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.U32BitOr{}, M.U32BitOr{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.U32BitXor{}, M.U32BitXor{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.U32ShiftLeft{}, M.U32ShiftLeft{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.U32ShiftRight{}, M.U32ShiftRight{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.Add{}, M.Add{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.Subtract{}, M.Subtract{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.Multiply{}, M.Multiply{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.Equal{}, M.Equal{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.LessThan{}, M.LessThan{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.F32Add{}, M.F32Add{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.F32Subtract{}, M.F32Subtract{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.F32Multiply{}, M.F32Multiply{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.F32Divide{}, M.F32Divide{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.F32Equal{}, M.F32Equal{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.F32NotEqual{}, M.F32NotEqual{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.F32LessThan{}, M.F32LessThan{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.F32LessEqual{}, M.F32LessEqual{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.F32GreaterThan{}, M.F32GreaterThan{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ScalarOpPair{M.F32GreaterEqual{}, M.F32GreaterEqual{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} UnaryOpPair{M.F32Negate{}, M.F32Negate{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} UnaryOpPair{M.F32Absolute{}, M.F32Absolute{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} UnaryOpPair{M.F32SquareRoot{}, M.F32SquareRoot{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} UnaryOpPair{M.F32Floor{}, M.F32Floor{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} UnaryOpPair{M.F32Ceiling{}, M.F32Ceiling{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} UnaryOpPair{M.F32Truncate{}, M.F32Truncate{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} UnaryOpPair{M.U32ToF32{}, M.U32ToF32{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} UnaryOpPair{M.F32ToU32{}, M.F32ToU32{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} DispatchPair{M.BinaryDispatch{}, M.BinaryDispatch{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} DispatchPair{M.MemberDispatch{}, M.MemberDispatch{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} DispatchPair{M.FieldUpdateDispatch{}, M.FieldUpdateDispatch{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ExprPair{M.UnitExpr{}, M.UnitExpr{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ExprPair{M.U32Expr{a0}, M.U32Expr{b0}} <> tail:
      compare_work(rest, True{}, U32Pair{a0, b0} <> tail)
    case 1n+rest True{} ExprPair{M.BoolExpr{a0}, M.BoolExpr{b0}} <> tail:
      compare_work(rest, True{}, BoolPair{a0, b0} <> tail)
    case 1n+rest True{} ExprPair{M.LocalExpr{a0}, M.LocalExpr{b0}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> tail)
    case 1n+rest True{} ExprPair{M.ConstantExpr{a0}, M.ConstantExpr{b0}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> tail)
    case 1n+rest True{} ExprPair{M.FunctionExpr{a0}, M.FunctionExpr{b0}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> tail)
    case 1n+rest True{} ExprPair{M.ConstructorRefExpr{a0}, M.ConstructorRefExpr{b0}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> tail)
    case 1n+rest True{} ExprPair{M.ConstructExpr{a0, a1}, M.ConstructExpr{b0, b1}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> ExprMaybePair{a1, b1} <> tail)
    case 1n+rest True{} ExprPair{M.LambdaExpr{a0, a1, a2, a3, a4}, M.LambdaExpr{b0, b1, b2, b3, b4}} <> tail:
      compare_work(rest, True{}, NatPair{a0, b0} <> StringPair{a1, b1} <> TyMaybePair{a2, b2} <> TyMaybePair{a3, b3} <> ExprPair{a4, b4} <> tail)
    case 1n+rest True{} ExprPair{M.ApplyExpr{a0, a1}, M.ApplyExpr{b0, b1}} <> tail:
      compare_work(rest, True{}, ExprPair{a0, b0} <> ExprPair{a1, b1} <> tail)
    case 1n+rest True{} ExprPair{M.CallExpr{a0, a1}, M.CallExpr{b0, b1}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> ExprPair{a1, b1} <> tail)
    case 1n+rest True{} ExprPair{M.ScalarExpr{a0, a1, a2}, M.ScalarExpr{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, ScalarOpPair{a0, b0} <> ExprPair{a1, b1} <> ExprPair{a2, b2} <> tail)
    case 1n+rest True{} ExprPair{M.LetExpr{a0, a1, a2}, M.LetExpr{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> ExprPair{a1, b1} <> ExprPair{a2, b2} <> tail)
    case 1n+rest True{} ExprPair{M.UseExpr{a0, a1, a2}, M.UseExpr{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> ExprPair{a1, b1} <> ExprPair{a2, b2} <> tail)
    case 1n+rest True{} ExprPair{M.IfExpr{a0, a1, a2}, M.IfExpr{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, ExprPair{a0, b0} <> ExprPair{a1, b1} <> ExprPair{a2, b2} <> tail)
    case 1n+rest True{} ExprPair{M.SequenceExpr{a0, a1}, M.SequenceExpr{b0, b1}} <> tail:
      compare_work(rest, True{}, ExprPair{a0, b0} <> ExprPair{a1, b1} <> tail)
    case 1n+rest True{} ExprPair{M.MatchExpr{a0, a1}, M.MatchExpr{b0, b1}} <> tail:
      compare_work(rest, True{}, ExprListPair{a0, b0} <> MatchArmListPair{a1, b1} <> tail)
    case 1n+rest True{} ExprPair{M.GuardExpr{a0, a1, a2, a3}, M.GuardExpr{b0, b1, b2, b3}} <> tail:
      compare_work(rest, True{}, PatternPair{a0, b0} <> ExprPair{a1, b1} <> ExprPair{a2, b2} <> ExprPair{a3, b3} <> tail)
    case 1n+rest True{} ExprPair{M.BlockExpr{a0, a1}, M.BlockExpr{b0, b1}} <> tail:
      compare_work(rest, True{}, NatPair{a0, b0} <> ExprPair{a1, b1} <> tail)
    case 1n+rest True{} ExprPair{M.ReturnExpr{a0, a1}, M.ReturnExpr{b0, b1}} <> tail:
      compare_work(rest, True{}, NatPair{a0, b0} <> ExprPair{a1, b1} <> tail)
    case 1n+rest True{} ExprPair{M.SourceExpr{a0, a1, a2}, M.SourceExpr{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, NatPair{a0, b0} <> TyMaybePair{a1, b1} <> ExprPair{a2, b2} <> tail)
    case 1n+rest True{} ExprPair{M.QualifiedExpr{a0, a1, a2, a3}, M.QualifiedExpr{b0, b1, b2, b3}} <> tail:
      compare_work(rest, True{}, NatPair{a0, b0} <> TyPair{a1, b1} <> PredicateListPair{a2, b2} <> ExprPair{a3, b3} <> tail)
    case 1n+rest True{} ExprPair{M.InstantiationExpr{a0, a1}, M.InstantiationExpr{b0, b1}} <> tail:
      compare_work(rest, True{}, NatPair{a0, b0} <> ExprPair{a1, b1} <> tail)
    case 1n+rest True{} ExprPair{M.TagExpr{a0, a1, a2}, M.TagExpr{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, NatPair{a0, b0} <> ExprPair{a1, b1} <> ExprPair{a2, b2} <> tail)
    case 1n+rest True{} ExprPair{M.RuntimeInitExpr{a0}, M.RuntimeInitExpr{b0}} <> tail:
      compare_work(rest, True{}, ExprPair{a0, b0} <> tail)
    case 1n+rest True{} ExprPair{M.F32Expr{a0}, M.F32Expr{b0}} <> tail:
      compare_work(rest, True{}, F32Pair{a0, b0} <> tail)
    case 1n+rest True{} ExprPair{M.UnaryExpr{a0, a1}, M.UnaryExpr{b0, b1}} <> tail:
      compare_work(rest, True{}, UnaryOpPair{a0, b0} <> ExprPair{a1, b1} <> tail)
    case 1n+rest True{} ExprPair{M.OperationExpr{a0}, M.OperationExpr{b0}} <> tail:
      compare_work(rest, True{}, TypeIdPair{a0, b0} <> tail)
    case 1n+rest True{} ExprPair{M.SpecializeOperationExpr{a0, a1, a2}, M.SpecializeOperationExpr{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, TypeIdPair{a0, b0} <> TyListPair{a1, b1} <> ExprPair{a2, b2} <> tail)
    case 1n+rest True{} ExprPair{M.ProviderExpr{a0, a1}, M.ProviderExpr{b0, b1}} <> tail:
      compare_work(rest, True{}, TypeIdPair{a0, b0} <> ExprPair{a1, b1} <> tail)
    case 1n+rest True{} ExprPair{M.StateProviderExpr{a0, a1, a2}, M.StateProviderExpr{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, TypeIdPair{a0, b0} <> TypeIdPair{a1, b1} <> ExprPair{a2, b2} <> tail)
    case 1n+rest True{} ExprPair{M.HandleExpr{a0, a1}, M.HandleExpr{b0, b1}} <> tail:
      compare_work(rest, True{}, ExprPair{a0, b0} <> ExprPair{a1, b1} <> tail)
    case 1n+rest True{} ExprPair{M.OperationDescriptorExpr{a0}, M.OperationDescriptorExpr{b0}} <> tail:
      compare_work(rest, True{}, TypeIdPair{a0, b0} <> tail)
    case 1n+rest True{} ExprPair{M.FunctionEffectsExpr{a0}, M.FunctionEffectsExpr{b0}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> tail)
    case 1n+rest True{} ExprPair{M.EffectHasExpr{a0, a1}, M.EffectHasExpr{b0, b1}} <> tail:
      compare_work(rest, True{}, ExprPair{a0, b0} <> ExprPair{a1, b1} <> tail)
    case 1n+rest True{} ExprPair{M.EffectCountExpr{a0}, M.EffectCountExpr{b0}} <> tail:
      compare_work(rest, True{}, ExprPair{a0, b0} <> tail)
    case 1n+rest True{} ExprPair{M.EffectSameExpr{a0, a1}, M.EffectSameExpr{b0, b1}} <> tail:
      compare_work(rest, True{}, ExprPair{a0, b0} <> ExprPair{a1, b1} <> tail)
    case 1n+rest True{} ExprPair{M.PanicExpr{a0}, M.PanicExpr{b0}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> tail)
    case 1n+rest True{} ExprPair{M.ProductExpr{a0}, M.ProductExpr{b0}} <> tail:
      compare_work(rest, True{}, ExprListPair{a0, b0} <> tail)
    case 1n+rest True{} ExprPair{M.ProjectExpr{a0, a1}, M.ProjectExpr{b0, b1}} <> tail:
      compare_work(rest, True{}, ExprPair{a0, b0} <> NatPair{a1, b1} <> tail)
    case 1n+rest True{} ExprPair{M.ArrayExpr{a0}, M.ArrayExpr{b0}} <> tail:
      compare_work(rest, True{}, ExprListPair{a0, b0} <> tail)
    case 1n+rest True{} ExprPair{M.ForExpr{a0, a1, a2, a3, a4, a5}, M.ForExpr{b0, b1, b2, b3, b4, b5}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> ExprPair{a1, b1} <> ExprPair{a2, b2} <> StringPair{a3, b3} <> ExprPair{a4, b4} <> ExprPair{a5, b5} <> tail)
    case 1n+rest True{} ExprPair{M.ForeverExpr{a0, a1, a2}, M.ForeverExpr{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> ExprPair{a1, b1} <> ExprPair{a2, b2} <> tail)
    case 1n+rest True{} ExprPair{M.ArrayGenerateExpr{a0, a1}, M.ArrayGenerateExpr{b0, b1}} <> tail:
      compare_work(rest, True{}, ExprPair{a0, b0} <> ExprPair{a1, b1} <> tail)
    case 1n+rest True{} ExprPair{M.ArrayFillExpr{a0, a1}, M.ArrayFillExpr{b0, b1}} <> tail:
      compare_work(rest, True{}, ExprPair{a0, b0} <> ExprPair{a1, b1} <> tail)
    case 1n+rest True{} ExprPair{M.ArrayGetExpr{a0, a1}, M.ArrayGetExpr{b0, b1}} <> tail:
      compare_work(rest, True{}, ExprPair{a0, b0} <> ExprPair{a1, b1} <> tail)
    case 1n+rest True{} ExprPair{M.ArraySetExpr{a0, a1, a2}, M.ArraySetExpr{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, ExprPair{a0, b0} <> ExprPair{a1, b1} <> ExprPair{a2, b2} <> tail)
    case 1n+rest True{} ExprPair{M.MemoExpr{a}, M.MemoExpr{b}} <> tail:
      compare_work(rest, True{}, ExprPair{a, b} <> tail)
    case 1n+rest True{} ExprPair{M.ForceExpr{a}, M.ForceExpr{b}} <> tail:
      compare_work(rest, True{}, ExprPair{a, b} <> tail)
    case 1n+rest True{} ExprPair{M.ArrayLengthExpr{a0}, M.ArrayLengthExpr{b0}} <> tail:
      compare_work(rest, True{}, ExprPair{a0, b0} <> tail)
    case 1n+rest True{} ExprPair{M.AssociatedExpr{a0, a1, a2, a3, a4, a5}, M.AssociatedExpr{b0, b1, b2, b3, b4, b5}} <> tail:
      compare_work(rest, True{}, NatPair{a0, b0} <> DispatchPair{a1, b1} <> StringPair{a2, b2} <> TypeIdListPair{a3, b3} <> ExprPair{a4, b4} <> ExprPair{a5, b5} <> tail)
    case 1n+rest True{} ExprPair{M.GenericOperationExpr{a0, a1, a2}, M.GenericOperationExpr{b0, b1, b2}} <> tail:
      compare_work(rest, True{}, NatPair{a0, b0} <> TypeIdPair{a1, b1} <> TyListPair{a2, b2} <> tail)
    case 1n+rest True{} FunctionPair{M.Function{a0, a1, a2, a3, a4, a5}, M.Function{b0, b1, b2, b3, b4, b5}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> BoolPair{a1, b1} <> StringPair{a2, b2} <> TyMaybePair{a3, b3} <> TyMaybePair{a4, b4} <> ExprPair{a5, b5} <> tail)
    case 1n+rest True{} ConstantPair{M.Constant{a0, a1, a2, a3}, M.Constant{b0, b1, b2, b3}} <> tail:
      compare_work(rest, True{}, StringPair{a0, b0} <> BoolPair{a1, b1} <> TyMaybePair{a2, b2} <> ExprPair{a3, b3} <> tail)
    case 1n+rest True{} ModulePair{M.Module{a0, a1, a2, a3}, M.Module{b0, b1, b2, b3}} <> tail:
      compare_work(rest, True{}, ConstantListPair{a0, b0} <> FunctionListPair{a1, b1} <> DataTypeListPair{a2, b2} <> OperationListPair{a3, b3} <> tail)
    case 1n+rest True{} StringPair{a, b} <> tail:
      compare_work(rest, M.name_equal(a, b), tail)
    case 1n+rest True{} NatPair{a, b} <> tail:
      compare_work(rest, Nat.is_eq(a, b), tail)
    case 1n+rest True{} TypeIdListPair{Nil{}, Nil{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} TypeIdListPair{a <> at, b <> bt} <> tail:
      compare_work(rest, True{}, TypeIdPair{a, b} <> TypeIdListPair{at, bt} <> tail)
    case 1n+rest True{} TyListPair{Nil{}, Nil{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} TyListPair{a <> at, b <> bt} <> tail:
      compare_work(rest, True{}, TyPair{a, b} <> TyListPair{at, bt} <> tail)
    case 1n+rest True{} PredicateListPair{Nil{}, Nil{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} PredicateListPair{a <> at, b <> bt} <> tail:
      compare_work(rest, True{}, PredicatePair{a, b} <> PredicateListPair{at, bt} <> tail)
    case 1n+rest True{} TyMaybePair{None{}, None{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} TyMaybePair{Some{a}, Some{b}} <> tail:
      compare_work(rest, True{}, TyPair{a, b} <> tail)
    case 1n+rest True{} StringListPair{Nil{}, Nil{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} StringListPair{a <> at, b <> bt} <> tail:
      compare_work(rest, True{}, StringPair{a, b} <> StringListPair{at, bt} <> tail)
    case 1n+rest True{} ConstructorListPair{Nil{}, Nil{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ConstructorListPair{a <> at, b <> bt} <> tail:
      compare_work(rest, True{}, ConstructorPair{a, b} <> ConstructorListPair{at, bt} <> tail)
    case 1n+rest True{} U32Pair{a, b} <> tail:
      compare_work(rest, U32.is_eq(a, b), tail)
    case 1n+rest True{} BoolPair{a, b} <> tail:
      compare_work(rest, Bool.not(Bool.xor(a, b)), tail)
    case 1n+rest True{} PatternMaybePair{None{}, None{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} PatternMaybePair{Some{a}, Some{b}} <> tail:
      compare_work(rest, True{}, PatternPair{a, b} <> tail)
    case 1n+rest True{} PatternListPair{Nil{}, Nil{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} PatternListPair{a <> at, b <> bt} <> tail:
      compare_work(rest, True{}, PatternPair{a, b} <> PatternListPair{at, bt} <> tail)
    case 1n+rest True{} ExprMaybePair{None{}, None{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ExprMaybePair{Some{a}, Some{b}} <> tail:
      compare_work(rest, True{}, ExprPair{a, b} <> tail)
    case 1n+rest True{} ExprListPair{Nil{}, Nil{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ExprListPair{a <> at, b <> bt} <> tail:
      compare_work(rest, True{}, ExprPair{a, b} <> ExprListPair{at, bt} <> tail)
    case 1n+rest True{} MatchArmListPair{Nil{}, Nil{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} MatchArmListPair{a <> at, b <> bt} <> tail:
      compare_work(rest, True{}, MatchArmPair{a, b} <> MatchArmListPair{at, bt} <> tail)
    case 1n+rest True{} F32Pair{a, b} <> tail:
      compare_work(rest, U32.is_eq(F32.bits(a), F32.bits(b)), tail)
    case 1n+rest True{} ConstantListPair{Nil{}, Nil{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} ConstantListPair{a <> at, b <> bt} <> tail:
      compare_work(rest, True{}, ConstantPair{a, b} <> ConstantListPair{at, bt} <> tail)
    case 1n+rest True{} FunctionListPair{Nil{}, Nil{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} FunctionListPair{a <> at, b <> bt} <> tail:
      compare_work(rest, True{}, FunctionPair{a, b} <> FunctionListPair{at, bt} <> tail)
    case 1n+rest True{} DataTypeListPair{Nil{}, Nil{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} DataTypeListPair{a <> at, b <> bt} <> tail:
      compare_work(rest, True{}, DataTypePair{a, b} <> DataTypeListPair{at, bt} <> tail)
    case 1n+rest True{} OperationListPair{Nil{}, Nil{}} <> tail:
      compare_work(rest, True{}, tail)
    case 1n+rest True{} OperationListPair{a <> at, b <> bt} <> tail:
      compare_work(rest, True{}, OperationPair{a, b} <> OperationListPair{at, bt} <> tail)
    case _ _ _:
      False{}

def compare(fuel: Nat, pending: List<&2, Work>, matching: Bool) -> Bool:
  compare_work(fuel, matching, pending)

def same_module(left: M.Module, right: M.Module) -> Bool:
  compare(1048576n, [ModulePair{left, right}], True{})

def same_type(left: M.DataType, right: M.DataType) -> Bool:
  compare(1048576n, [DataTypePair{left, right}], True{})

def same_predicate(left: M.Predicate, right: M.Predicate) -> Bool:
  compare(1048576n, [PredicatePair{left, right}], True{})

def same_operation(left: M.Operation, right: M.Operation) -> Bool:
  compare(1048576n, [OperationPair{left, right}], True{})

def same_ty(left: M.Ty, right: M.Ty) -> Bool:
  compare(1048576n, [TyPair{left, right}], True{})

def same_expr(left: M.Expr, right: M.Expr) -> Bool:
  compare(1048576n, [ExprPair{left, right}], True{})
