//! Exact structural comparisons over the existing immutable core graph.
//! Flat native work frames replace allocated semantic work/list cells. A cached
//! successful pair records its full reference cost: sharing never bypasses fuel.
const std = @import("std");
const r = @import("runtime.zig");
const V = r.Value;
const Tag = r.Tag;
const Allocator = std.mem.Allocator;
const Pair = struct { left: V, right: V, kind: Tag };
const Frame = struct { pair: Pair, before: u64 = 0 };
const Shape = struct { kind: Tag, fields: []const Tag };

// This describes the source's typed fields, not runtime object memory layouts.
// A type's offset, annotation, labels, and floating bits are all significant.
fn modelShape(tag: Tag) ?Shape {
    return switch (tag) {
        .model_TypeId => .{ .kind = .core_compare_TypeIdPair, .fields = &.{ .core_compare_StringPair, .core_compare_StringPair } },
        .model_ClosedRow => .{ .kind = .core_compare_RowTailPair, .fields = &.{} },
        .model_RowVariable => .{ .kind = .core_compare_RowTailPair, .fields = &.{.core_compare_NatPair} },
        .model_RowParameter => .{ .kind = .core_compare_RowTailPair, .fields = &.{.core_compare_NatPair} },
        .model_FreeRow => .{ .kind = .core_compare_RowTailPair, .fields = &.{ .core_compare_StringPair, .core_compare_StringPair } },
        .model_EffectRow => .{ .kind = .core_compare_EffectRowPair, .fields = &.{ .core_compare_TypeIdListPair, .core_compare_RowTailPair } },
        .model_UnitTy => .{ .kind = .core_compare_TyPair, .fields = &.{} },
        .model_U32Ty => .{ .kind = .core_compare_TyPair, .fields = &.{} },
        .model_BoolTy => .{ .kind = .core_compare_TyPair, .fields = &.{} },
        .model_AppliedTy => .{ .kind = .core_compare_TyPair, .fields = &.{ .core_compare_TypeIdPair, .core_compare_TyListPair } },
        .model_FunctionTy => .{ .kind = .core_compare_TyPair, .fields = &.{ .core_compare_TyPair, .core_compare_TyPair, .core_compare_EffectRowPair } },
        .model_ParameterTy => .{ .kind = .core_compare_TyPair, .fields = &.{.core_compare_NatPair} },
        .model_VariableTy => .{ .kind = .core_compare_TyPair, .fields = &.{.core_compare_NatPair} },
        .model_NeverTy => .{ .kind = .core_compare_TyPair, .fields = &.{} },
        .model_F32Ty => .{ .kind = .core_compare_TyPair, .fields = &.{} },
        .model_ProviderTy => .{ .kind = .core_compare_TyPair, .fields = &.{ .core_compare_TypeIdPair, .core_compare_EffectRowPair } },
        .model_StateProviderTy => .{ .kind = .core_compare_TyPair, .fields = &.{ .core_compare_TypeIdPair, .core_compare_TypeIdPair, .core_compare_TyPair } },
        .model_EffectDescriptorTy => .{ .kind = .core_compare_TyPair, .fields = &.{} },
        .model_EffectSetTy => .{ .kind = .core_compare_TyPair, .fields = &.{} },
        .model_ProductTy => .{ .kind = .core_compare_TyPair, .fields = &.{.core_compare_TyListPair} },
        .model_ArrayTy => .{ .kind = .core_compare_TyPair, .fields = &.{.core_compare_TyPair} },
        .model_FreeTy => .{ .kind = .core_compare_TyPair, .fields = &.{ .core_compare_StringPair, .core_compare_StringPair } },
        .model_AssociatedPredicate => .{ .kind = .core_compare_PredicatePair, .fields = &.{ .core_compare_StringPair, .core_compare_TypeIdListPair, .core_compare_TyPair, .core_compare_TyPair, .core_compare_TyPair, .core_compare_EffectRowPair } },
        .model_ReceiverPredicate => .{ .kind = .core_compare_PredicatePair, .fields = &.{ .core_compare_StringPair, .core_compare_TypeIdListPair, .core_compare_TyPair, .core_compare_TyPair, .core_compare_TyPair, .core_compare_EffectRowPair } },
        .model_FieldPredicate => .{ .kind = .core_compare_PredicatePair, .fields = &.{ .core_compare_StringPair, .core_compare_TyPair, .core_compare_TyPair } },
        .model_UpdatePredicate => .{ .kind = .core_compare_PredicatePair, .fields = &.{ .core_compare_StringPair, .core_compare_TyPair, .core_compare_TyPair, .core_compare_TyPair, .core_compare_EffectRowPair } },
        .model_OperationPredicate => .{ .kind = .core_compare_PredicatePair, .fields = &.{ .core_compare_TypeIdPair, .core_compare_TyListPair, .core_compare_TyPair } },
        .model_TypeRepPredicate => .{ .kind = .core_compare_PredicatePair, .fields = &.{.core_compare_TyPair} },
        .model_EffectRepPredicate => .{ .kind = .core_compare_PredicatePair, .fields = &.{.core_compare_EffectRowPair} },
        .model_Operation => .{ .kind = .core_compare_OperationPair, .fields = &.{ .core_compare_TypeIdPair, .core_compare_TyPair, .core_compare_TyPair } },
        .model_OperationTemplate => .{ .kind = .core_compare_OperationPair, .fields = &.{ .core_compare_TypeIdPair, .core_compare_NatPair, .core_compare_TyPair, .core_compare_TyPair } },
        .model_OperationInstance => .{ .kind = .core_compare_OperationPair, .fields = &.{ .core_compare_TypeIdPair, .core_compare_TyListPair } },
        .model_Constructor => .{ .kind = .core_compare_ConstructorPair, .fields = &.{ .core_compare_StringPair, .core_compare_TyMaybePair, .core_compare_StringListPair } },
        .model_DataType => .{ .kind = .core_compare_DataTypePair, .fields = &.{ .core_compare_TypeIdPair, .core_compare_NatPair, .core_compare_ConstructorListPair } },
        .model_LocalReference => .{ .kind = .core_compare_ValueReferencePair, .fields = &.{.core_compare_StringPair} },
        .model_ConstantReference => .{ .kind = .core_compare_ValueReferencePair, .fields = &.{.core_compare_StringPair} },
        .model_WildcardPattern => .{ .kind = .core_compare_PatternPair, .fields = &.{} },
        .model_BindingPattern => .{ .kind = .core_compare_PatternPair, .fields = &.{.core_compare_StringPair} },
        .model_UnitPattern => .{ .kind = .core_compare_PatternPair, .fields = &.{} },
        .model_U32Pattern => .{ .kind = .core_compare_PatternPair, .fields = &.{.core_compare_U32Pair} },
        .model_BoolPattern => .{ .kind = .core_compare_PatternPair, .fields = &.{.core_compare_BoolPair} },
        .model_ValuePattern => .{ .kind = .core_compare_PatternPair, .fields = &.{.core_compare_ValueReferencePair} },
        .model_ConstructorPattern => .{ .kind = .core_compare_PatternPair, .fields = &.{ .core_compare_StringPair, .core_compare_PatternMaybePair } },
        .model_ProductPattern => .{ .kind = .core_compare_PatternPair, .fields = &.{.core_compare_PatternListPair} },
        .model_MatchArm => .{ .kind = .core_compare_MatchArmPair, .fields = &.{ .core_compare_PatternListPair, .core_compare_ExprPair } },
        .model_U32Divide => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_U32Remainder => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_U32BitAnd => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_U32BitOr => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_U32BitXor => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_U32ShiftLeft => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_U32ShiftRight => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_Add => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_Subtract => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_Multiply => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_Equal => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_LessThan => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_F32Add => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_F32Subtract => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_F32Multiply => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_F32Divide => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_F32Equal => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_F32NotEqual => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_F32LessThan => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_F32LessEqual => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_F32GreaterThan => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_F32GreaterEqual => .{ .kind = .core_compare_ScalarOpPair, .fields = &.{} },
        .model_F32Negate => .{ .kind = .core_compare_UnaryOpPair, .fields = &.{} },
        .model_F32Absolute => .{ .kind = .core_compare_UnaryOpPair, .fields = &.{} },
        .model_F32SquareRoot => .{ .kind = .core_compare_UnaryOpPair, .fields = &.{} },
        .model_F32Floor => .{ .kind = .core_compare_UnaryOpPair, .fields = &.{} },
        .model_F32Ceiling => .{ .kind = .core_compare_UnaryOpPair, .fields = &.{} },
        .model_F32Truncate => .{ .kind = .core_compare_UnaryOpPair, .fields = &.{} },
        .model_U32ToF32 => .{ .kind = .core_compare_UnaryOpPair, .fields = &.{} },
        .model_F32ToU32 => .{ .kind = .core_compare_UnaryOpPair, .fields = &.{} },
        .model_BinaryDispatch => .{ .kind = .core_compare_DispatchPair, .fields = &.{} },
        .model_MemberDispatch => .{ .kind = .core_compare_DispatchPair, .fields = &.{} },
        .model_FieldUpdateDispatch => .{ .kind = .core_compare_DispatchPair, .fields = &.{} },
        .model_UnitExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{} },
        .model_U32Expr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_U32Pair} },
        .model_BoolExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_BoolPair} },
        .model_LocalExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_StringPair} },
        .model_ConstantExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_StringPair} },
        .model_FunctionExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_StringPair} },
        .model_ConstructorRefExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_StringPair} },
        .model_ConstructExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_StringPair, .core_compare_ExprMaybePair } },
        .model_LambdaExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_NatPair, .core_compare_StringPair, .core_compare_TyMaybePair, .core_compare_TyMaybePair, .core_compare_ExprPair } },
        .model_ApplyExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_CallExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_StringPair, .core_compare_ExprPair } },
        .model_ScalarExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_ScalarOpPair, .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_LetExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_StringPair, .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_UseExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_StringPair, .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_IfExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_ExprPair, .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_SequenceExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_MatchExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_ExprListPair, .core_compare_MatchArmListPair } },
        .model_GuardExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_PatternPair, .core_compare_ExprPair, .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_BlockExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_NatPair, .core_compare_ExprPair } },
        .model_ReturnExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_NatPair, .core_compare_ExprPair } },
        .model_SourceExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_NatPair, .core_compare_TyMaybePair, .core_compare_ExprPair } },
        .model_QualifiedExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_NatPair, .core_compare_TyPair, .core_compare_PredicateListPair, .core_compare_ExprPair } },
        .model_InstantiationExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_NatPair, .core_compare_ExprPair } },
        .model_TagExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_NatPair, .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_RuntimeInitExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_ExprPair} },
        .model_F32Expr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_F32Pair} },
        .model_UnaryExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_UnaryOpPair, .core_compare_ExprPair } },
        .model_OperationExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_TypeIdPair} },
        .model_SpecializeOperationExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_TypeIdPair, .core_compare_TyListPair, .core_compare_ExprPair } },
        .model_ProviderExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_TypeIdPair, .core_compare_ExprPair } },
        .model_StateProviderExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_TypeIdPair, .core_compare_TypeIdPair, .core_compare_ExprPair } },
        .model_HandleExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_OperationDescriptorExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_TypeIdPair} },
        .model_FunctionEffectsExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_StringPair} },
        .model_EffectHasExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_EffectCountExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_ExprPair} },
        .model_EffectSameExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_PanicExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_StringPair} },
        .model_ProductExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_ExprListPair} },
        .model_ProjectExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_ExprPair, .core_compare_NatPair } },
        .model_ArrayExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_ExprListPair} },
        .model_ForExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_StringPair, .core_compare_ExprPair, .core_compare_ExprPair, .core_compare_StringPair, .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_ForeverExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_StringPair, .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_ArrayGenerateExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_ArrayFillExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_ArrayGetExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_ArraySetExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_ExprPair, .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_MemoExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_ExprPair} },
        .model_ForceExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_ExprPair} },
        .model_ArrayLengthExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{.core_compare_ExprPair} },
        .model_AssociatedExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_NatPair, .core_compare_DispatchPair, .core_compare_StringPair, .core_compare_TypeIdListPair, .core_compare_ExprPair, .core_compare_ExprPair } },
        .model_GenericOperationExpr => .{ .kind = .core_compare_ExprPair, .fields = &.{ .core_compare_NatPair, .core_compare_TypeIdPair, .core_compare_TyListPair } },
        .model_Function => .{ .kind = .core_compare_FunctionPair, .fields = &.{ .core_compare_StringPair, .core_compare_BoolPair, .core_compare_StringPair, .core_compare_TyMaybePair, .core_compare_TyMaybePair, .core_compare_ExprPair } },
        .model_Constant => .{ .kind = .core_compare_ConstantPair, .fields = &.{ .core_compare_StringPair, .core_compare_BoolPair, .core_compare_TyMaybePair, .core_compare_ExprPair } },
        .model_Module => .{ .kind = .core_compare_ModulePair, .fields = &.{ .core_compare_ConstantListPair, .core_compare_FunctionListPair, .core_compare_DataTypeListPair, .core_compare_OperationListPair } },
        else => null,
    };
}
fn children(kind: Tag, tag: Tag) ?[]const Tag {
    switch (kind) {
        .core_compare_TypeIdListPair => return switch (tag) {
            .Nil => &.{},
            .Cons => &.{ .core_compare_TypeIdPair, .core_compare_TypeIdListPair },
            else => null,
        },
        .core_compare_TyListPair => return switch (tag) {
            .Nil => &.{},
            .Cons => &.{ .core_compare_TyPair, .core_compare_TyListPair },
            else => null,
        },
        .core_compare_PredicateListPair => return switch (tag) {
            .Nil => &.{},
            .Cons => &.{ .core_compare_PredicatePair, .core_compare_PredicateListPair },
            else => null,
        },
        .core_compare_StringListPair => return switch (tag) {
            .Nil => &.{},
            .Cons => &.{ .core_compare_StringPair, .core_compare_StringListPair },
            else => null,
        },
        .core_compare_ConstructorListPair => return switch (tag) {
            .Nil => &.{},
            .Cons => &.{ .core_compare_ConstructorPair, .core_compare_ConstructorListPair },
            else => null,
        },
        .core_compare_PatternListPair => return switch (tag) {
            .Nil => &.{},
            .Cons => &.{ .core_compare_PatternPair, .core_compare_PatternListPair },
            else => null,
        },
        .core_compare_ExprListPair => return switch (tag) {
            .Nil => &.{},
            .Cons => &.{ .core_compare_ExprPair, .core_compare_ExprListPair },
            else => null,
        },
        .core_compare_MatchArmListPair => return switch (tag) {
            .Nil => &.{},
            .Cons => &.{ .core_compare_MatchArmPair, .core_compare_MatchArmListPair },
            else => null,
        },
        .core_compare_ConstantListPair => return switch (tag) {
            .Nil => &.{},
            .Cons => &.{ .core_compare_ConstantPair, .core_compare_ConstantListPair },
            else => null,
        },
        .core_compare_FunctionListPair => return switch (tag) {
            .Nil => &.{},
            .Cons => &.{ .core_compare_FunctionPair, .core_compare_FunctionListPair },
            else => null,
        },
        .core_compare_DataTypeListPair => return switch (tag) {
            .Nil => &.{},
            .Cons => &.{ .core_compare_DataTypePair, .core_compare_DataTypeListPair },
            else => null,
        },
        .core_compare_OperationListPair => return switch (tag) {
            .Nil => &.{},
            .Cons => &.{ .core_compare_OperationPair, .core_compare_OperationListPair },
            else => null,
        },
        .core_compare_TyMaybePair => return switch (tag) {
            .None => &.{},
            .Some => &.{.core_compare_TyPair},
            else => null,
        },
        .core_compare_PatternMaybePair => return switch (tag) {
            .None => &.{},
            .Some => &.{.core_compare_PatternPair},
            else => null,
        },
        .core_compare_ExprMaybePair => return switch (tag) {
            .None => &.{},
            .Some => &.{.core_compare_ExprPair},
            else => null,
        },
        else => {
            const shape = modelShape(tag) orelse return null;
            return if (shape.kind == kind) shape.fields else null;
        },
    }
}
pub const State = struct {
    allocator: Allocator,
    work: std.ArrayList(Frame) = .empty,
    equal_cost: std.AutoHashMapUnmanaged(Pair, u64) = .empty,
    visits: usize = 0,
    hits: usize = 0,
    child_cache: std.AutoHashMapUnmanaged(V, V) = .empty,
    child_work: std.ArrayList(V) = .empty,

    pub fn deinit(self: *State) void {
        self.work.deinit(self.allocator);
        self.equal_cost.deinit(self.allocator);
        self.child_cache.deinit(self.allocator);
        self.child_work.deinit(self.allocator);
    }
    fn compare(self: *State, input: Pair, fuel: *u64) Allocator.Error!bool {
        self.work.clearRetainingCapacity();
        try self.work.append(self.allocator, .{ .pair = input });
        while (self.work.pop()) |frame| {
            const pair = frame.pair;
            if (frame.before != 0) {
                try self.equal_cost.put(self.allocator, pair, frame.before - fuel.*);
                continue;
            }
            if (fuel.* == 0) return false;
            switch (pair.kind) {
                .core_compare_StringPair => {
                    fuel.* -= 1;
                    if (!r.stringEqual(pair.left, pair.right)) return false;
                    continue;
                },
                .core_compare_NatPair, .core_compare_U32Pair, .core_compare_F32Pair, .core_compare_BoolPair => {
                    fuel.* -= 1;
                    // Scalar representations are canonical; F32 compares bits,
                    // including signed zero and NaN payload, not IEEE equality.
                    if (pair.left != pair.right) return false;
                    continue;
                },
                else => {},
            }
            const tag = r.tag(pair.left);
            if (tag != r.tag(pair.right)) return false;
            const fields = children(pair.kind, tag) orelse return false;
            if (fields.len == 0) {
                fuel.* -= 1;
                continue;
            }
            if (self.equal_cost.get(pair)) |cost| {
                self.hits += 1;
                if (cost > fuel.*) return false;
                fuel.* -= cost;
                continue;
            }
            self.visits += 1;
            try self.work.ensureUnusedCapacity(self.allocator, fields.len + 1);
            self.work.appendAssumeCapacity(.{ .pair = pair, .before = fuel.* });
            fuel.* -= 1;
            var i = fields.len;
            while (i > 0) {
                i -= 1;
                self.work.appendAssumeCapacity(.{ .pair = .{ .left = r.field(pair.left, i), .right = r.field(pair.right, i), .kind = fields[i] } });
            }
        }
        return true;
    }
};
fn state(ctx: *r.Context) Allocator.Error!*State {
    if (ctx.core_compare_state) |s| return s;
    const s = try ctx.arena.allocator().create(State);
    s.* = .{ .allocator = ctx.arena.child_allocator };
    ctx.core_compare_state = s;
    return s;
}
fn run(ctx: *r.Context, fuel: u64, pending: V) Allocator.Error!bool {
    const s = try state(ctx);
    // Bound retained memo capacity between operations, never midway through an
    // operation whose finish frames still rely on the earlier subgraph costs.
    if (s.equal_cost.count() > 65536) s.equal_cost.clearRetainingCapacity();
    var remaining = fuel;
    var cursor = pending;
    while (r.tag(cursor) == .Cons) : (cursor = r.field(cursor, 1)) {
        const pair = r.field(cursor, 0);
        if (!try s.compare(.{ .kind = r.tag(pair), .left = r.field(pair, 0), .right = r.field(pair, 1) }, &remaining)) return false;
    }
    return r.tag(cursor) == .Nil;
}
pub fn compareWork(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len == 3);
    if (!r.truth(args[1])) return r.boolean(false);
    // Preserve the reference precedence: empty pending succeeds even at zero.
    if (r.tag(args[2]) == .Nil) return r.boolean(true);
    if (r.toNat(args[0]) == 0) return r.boolean(false);
    return r.boolean(run(ctx, r.toNat(args[0]), args[2]) catch @panic("Zig compiler ran out of memory"));
}

fn specimen(ctx: *r.Context, kind: Tag, different: bool) V {
    return switch (kind) {
        .core_compare_StringPair => if (different) r.literal("😀e\u{301}") else r.literal(""),
        .core_compare_NatPair => r.nat(if (different) r.mask else 0),
        .core_compare_U32Pair => r.word(if (different) 0xffffffff else 0),
        .core_compare_F32Pair => r.float(@bitCast(@as(u32, if (different) 0x80000000 else 0))),
        .core_compare_BoolPair => r.boolean(different),
        .core_compare_TypeIdPair => ctx.node(.model_TypeId, &.{ specimen(ctx, .core_compare_StringPair, different), specimen(ctx, .core_compare_StringPair, false) }),
        .core_compare_RowTailPair => ctx.node(.model_RowVariable, &.{specimen(ctx, .core_compare_NatPair, different)}),
        .core_compare_EffectRowPair => ctx.node(.model_EffectRow, &.{ specimen(ctx, .core_compare_TypeIdListPair, different), specimen(ctx, .core_compare_RowTailPair, false) }),
        .core_compare_TyPair => ctx.node(.model_VariableTy, &.{specimen(ctx, .core_compare_NatPair, different)}),
        .core_compare_PredicatePair => ctx.node(.model_TypeRepPredicate, &.{specimen(ctx, .core_compare_TyPair, different)}),
        .core_compare_OperationPair => ctx.node(.model_Operation, &.{ specimen(ctx, .core_compare_TypeIdPair, different), specimen(ctx, .core_compare_TyPair, false), specimen(ctx, .core_compare_TyPair, false) }),
        .core_compare_ConstructorPair => ctx.node(.model_Constructor, &.{ specimen(ctx, .core_compare_StringPair, different), specimen(ctx, .core_compare_TyMaybePair, false), specimen(ctx, .core_compare_StringListPair, false) }),
        .core_compare_DataTypePair => ctx.node(.model_DataType, &.{ specimen(ctx, .core_compare_TypeIdPair, different), specimen(ctx, .core_compare_NatPair, false), specimen(ctx, .core_compare_ConstructorListPair, false) }),
        .core_compare_ValueReferencePair => ctx.node(.model_LocalReference, &.{specimen(ctx, .core_compare_StringPair, different)}),
        .core_compare_PatternPair => ctx.node(.model_BindingPattern, &.{specimen(ctx, .core_compare_StringPair, different)}),
        .core_compare_MatchArmPair => ctx.node(.model_MatchArm, &.{ specimen(ctx, .core_compare_PatternListPair, different), specimen(ctx, .core_compare_ExprPair, false) }),
        .core_compare_ScalarOpPair => if (different) r.empty(.model_U32Divide) else r.empty(.model_Add),
        .core_compare_UnaryOpPair => if (different) r.empty(.model_F32Absolute) else r.empty(.model_F32Negate),
        .core_compare_DispatchPair => if (different) r.empty(.model_MemberDispatch) else r.empty(.model_BinaryDispatch),
        .core_compare_ExprPair => ctx.node(.model_U32Expr, &.{specimen(ctx, .core_compare_U32Pair, different)}),
        .core_compare_FunctionPair => ctx.node(.model_Function, &.{ specimen(ctx, .core_compare_StringPair, different), specimen(ctx, .core_compare_BoolPair, false), specimen(ctx, .core_compare_StringPair, false), specimen(ctx, .core_compare_TyMaybePair, false), specimen(ctx, .core_compare_TyMaybePair, false), specimen(ctx, .core_compare_ExprPair, false) }),
        .core_compare_ConstantPair => ctx.node(.model_Constant, &.{ specimen(ctx, .core_compare_StringPair, different), specimen(ctx, .core_compare_BoolPair, false), specimen(ctx, .core_compare_TyMaybePair, false), specimen(ctx, .core_compare_ExprPair, false) }),
        .core_compare_ModulePair => ctx.node(.model_Module, &.{ specimen(ctx, .core_compare_ConstantListPair, different), specimen(ctx, .core_compare_FunctionListPair, false), specimen(ctx, .core_compare_DataTypeListPair, false), specimen(ctx, .core_compare_OperationListPair, false) }),
        .core_compare_TypeIdListPair => if (different) ctx.node(.Cons, &.{ specimen(ctx, .core_compare_TypeIdPair, false), r.empty(.Nil) }) else r.empty(.Nil),
        .core_compare_TyListPair => if (different) ctx.node(.Cons, &.{ specimen(ctx, .core_compare_TyPair, false), r.empty(.Nil) }) else r.empty(.Nil),
        .core_compare_PredicateListPair => if (different) ctx.node(.Cons, &.{ specimen(ctx, .core_compare_PredicatePair, false), r.empty(.Nil) }) else r.empty(.Nil),
        .core_compare_StringListPair => if (different) ctx.node(.Cons, &.{ specimen(ctx, .core_compare_StringPair, false), r.empty(.Nil) }) else r.empty(.Nil),
        .core_compare_ConstructorListPair => if (different) ctx.node(.Cons, &.{ specimen(ctx, .core_compare_ConstructorPair, false), r.empty(.Nil) }) else r.empty(.Nil),
        .core_compare_PatternListPair => if (different) ctx.node(.Cons, &.{ specimen(ctx, .core_compare_PatternPair, false), r.empty(.Nil) }) else r.empty(.Nil),
        .core_compare_ExprListPair => if (different) ctx.node(.Cons, &.{ specimen(ctx, .core_compare_ExprPair, false), r.empty(.Nil) }) else r.empty(.Nil),
        .core_compare_MatchArmListPair => if (different) ctx.node(.Cons, &.{ specimen(ctx, .core_compare_MatchArmPair, false), r.empty(.Nil) }) else r.empty(.Nil),
        .core_compare_ConstantListPair => if (different) ctx.node(.Cons, &.{ specimen(ctx, .core_compare_ConstantPair, false), r.empty(.Nil) }) else r.empty(.Nil),
        .core_compare_FunctionListPair => if (different) ctx.node(.Cons, &.{ specimen(ctx, .core_compare_FunctionPair, false), r.empty(.Nil) }) else r.empty(.Nil),
        .core_compare_DataTypeListPair => if (different) ctx.node(.Cons, &.{ specimen(ctx, .core_compare_DataTypePair, false), r.empty(.Nil) }) else r.empty(.Nil),
        .core_compare_OperationListPair => if (different) ctx.node(.Cons, &.{ specimen(ctx, .core_compare_OperationPair, false), r.empty(.Nil) }) else r.empty(.Nil),
        .core_compare_TyMaybePair => if (different) ctx.node(.Some, &.{specimen(ctx, .core_compare_TyPair, false)}) else r.empty(.None),
        .core_compare_PatternMaybePair => if (different) ctx.node(.Some, &.{specimen(ctx, .core_compare_PatternPair, false)}) else r.empty(.None),
        .core_compare_ExprMaybePair => if (different) ctx.node(.Some, &.{specimen(ctx, .core_compare_ExprPair, false)}) else r.empty(.None),
        else => unreachable,
    };
}
fn oracle(ctx: *r.Context, fuel: u64, pending: V) V {
    return ctx.call(@import("generated/functions.zig").oracle_core_compare_compare_work, &.{ r.nat(fuel), r.boolean(true), pending });
}
fn comparison(ctx: *r.Context, comptime kind: Tag, a: V, b: V) V {
    return ctx.node(.Cons, &.{ ctx.node(kind, &.{ a, b }), r.empty(.Nil) });
}
fn expectComparison(ctx: *r.Context, fuel: u64, pending: V) !void {
    try std.testing.expectEqual(oracle(ctx, fuel, pending), compareWork(ctx, &.{ r.nat(fuel), r.boolean(true), pending }));
}
test "native core equality checks all constructor fields and exact cached fuel" {
    @setEvalBranchQuota(20000);
    inline for (.{
        Tag.model_TypeId,
        Tag.model_ClosedRow,
        Tag.model_RowVariable,
        Tag.model_RowParameter,
        Tag.model_FreeRow,
        Tag.model_EffectRow,
        Tag.model_UnitTy,
        Tag.model_U32Ty,
        Tag.model_BoolTy,
        Tag.model_AppliedTy,
        Tag.model_FunctionTy,
        Tag.model_ParameterTy,
        Tag.model_VariableTy,
        Tag.model_NeverTy,
        Tag.model_F32Ty,
        Tag.model_ProviderTy,
        Tag.model_StateProviderTy,
        Tag.model_EffectDescriptorTy,
        Tag.model_EffectSetTy,
        Tag.model_ProductTy,
        Tag.model_ArrayTy,
        Tag.model_FreeTy,
        Tag.model_AssociatedPredicate,
        Tag.model_ReceiverPredicate,
        Tag.model_FieldPredicate,
        Tag.model_UpdatePredicate,
        Tag.model_OperationPredicate,
        Tag.model_TypeRepPredicate,
        Tag.model_EffectRepPredicate,
        Tag.model_Operation,
        Tag.model_OperationTemplate,
        Tag.model_OperationInstance,
        Tag.model_Constructor,
        Tag.model_DataType,
        Tag.model_LocalReference,
        Tag.model_ConstantReference,
        Tag.model_WildcardPattern,
        Tag.model_BindingPattern,
        Tag.model_UnitPattern,
        Tag.model_U32Pattern,
        Tag.model_BoolPattern,
        Tag.model_ValuePattern,
        Tag.model_ConstructorPattern,
        Tag.model_ProductPattern,
        Tag.model_MatchArm,
        Tag.model_U32Divide,
        Tag.model_U32Remainder,
        Tag.model_U32BitAnd,
        Tag.model_U32BitOr,
        Tag.model_U32BitXor,
        Tag.model_U32ShiftLeft,
        Tag.model_U32ShiftRight,
        Tag.model_Add,
        Tag.model_Subtract,
        Tag.model_Multiply,
        Tag.model_Equal,
        Tag.model_LessThan,
        Tag.model_F32Add,
        Tag.model_F32Subtract,
        Tag.model_F32Multiply,
        Tag.model_F32Divide,
        Tag.model_F32Equal,
        Tag.model_F32NotEqual,
        Tag.model_F32LessThan,
        Tag.model_F32LessEqual,
        Tag.model_F32GreaterThan,
        Tag.model_F32GreaterEqual,
        Tag.model_F32Negate,
        Tag.model_F32Absolute,
        Tag.model_F32SquareRoot,
        Tag.model_F32Floor,
        Tag.model_F32Ceiling,
        Tag.model_F32Truncate,
        Tag.model_U32ToF32,
        Tag.model_F32ToU32,
        Tag.model_BinaryDispatch,
        Tag.model_MemberDispatch,
        Tag.model_FieldUpdateDispatch,
        Tag.model_UnitExpr,
        Tag.model_U32Expr,
        Tag.model_BoolExpr,
        Tag.model_LocalExpr,
        Tag.model_ConstantExpr,
        Tag.model_FunctionExpr,
        Tag.model_ConstructorRefExpr,
        Tag.model_ConstructExpr,
        Tag.model_LambdaExpr,
        Tag.model_ApplyExpr,
        Tag.model_CallExpr,
        Tag.model_ScalarExpr,
        Tag.model_LetExpr,
        Tag.model_UseExpr,
        Tag.model_IfExpr,
        Tag.model_SequenceExpr,
        Tag.model_MatchExpr,
        Tag.model_GuardExpr,
        Tag.model_BlockExpr,
        Tag.model_ReturnExpr,
        Tag.model_SourceExpr,
        Tag.model_QualifiedExpr,
        Tag.model_InstantiationExpr,
        Tag.model_TagExpr,
        Tag.model_RuntimeInitExpr,
        Tag.model_F32Expr,
        Tag.model_UnaryExpr,
        Tag.model_OperationExpr,
        Tag.model_SpecializeOperationExpr,
        Tag.model_ProviderExpr,
        Tag.model_StateProviderExpr,
        Tag.model_HandleExpr,
        Tag.model_OperationDescriptorExpr,
        Tag.model_FunctionEffectsExpr,
        Tag.model_EffectHasExpr,
        Tag.model_EffectCountExpr,
        Tag.model_EffectSameExpr,
        Tag.model_PanicExpr,
        Tag.model_ProductExpr,
        Tag.model_ProjectExpr,
        Tag.model_ArrayExpr,
        Tag.model_ForExpr,
        Tag.model_ForeverExpr,
        Tag.model_ArrayGenerateExpr,
        Tag.model_ArrayFillExpr,
        Tag.model_ArrayGetExpr,
        Tag.model_ArraySetExpr,
        Tag.model_MemoExpr,
        Tag.model_ForceExpr,
        Tag.model_ArrayLengthExpr,
        Tag.model_AssociatedExpr,
        Tag.model_GenericOperationExpr,
        Tag.model_Function,
        Tag.model_Constant,
        Tag.model_Module,
    }) |tag| {
        var ctx = r.Context.init(std.testing.allocator);
        defer ctx.deinit();
        const shape = comptime modelShape(tag).?;
        var fields: [shape.fields.len]V = undefined;
        for (shape.fields, &fields) |kind, *value| value.* = specimen(&ctx, kind, false);
        const left = ctx.node(tag, &fields);
        const right = ctx.node(tag, &fields);
        const pending = comparison(&ctx, shape.kind, left, right);
        try std.testing.expectEqual(r.boolean(true), oracle(&ctx, 256, pending));
        try expectComparison(&ctx, 256, pending);
        // Populate the native memo first, then prove exact exhaustion still
        // agrees for every budget up to and including the successful one.
        var cost: u64 = 0;
        while (!r.truth(oracle(&ctx, cost, pending))) : (cost += 1) {
            try expectComparison(&ctx, cost, pending);
            try std.testing.expect(cost < 256);
        }
        try expectComparison(&ctx, cost, pending);
        try expectComparison(&ctx, cost + 1, pending);
        for (shape.fields, 0..) |kind, i| {
            var changed = fields;
            changed[i] = specimen(&ctx, kind, true);
            const mismatch = comparison(&ctx, shape.kind, left, ctx.node(tag, &changed));
            try std.testing.expectEqual(r.boolean(false), oracle(&ctx, 256, mismatch));
            try expectComparison(&ctx, 256, mismatch);
        }
    }
}
test "native core comparison keeps float bits, list order and source identity" {
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    const bits = [_]u32{ 0, 0x80000000, 0x7fc00000, 0x7fc00001, 0x7f800000, 0xff800000, 0xffffffff };
    for (bits) |a| for (bits) |b| {
        const p = comparison(&ctx, .core_compare_F32Pair, r.float(@bitCast(a)), r.float(@bitCast(b)));
        try expectComparison(&ctx, 1, p);
        try std.testing.expectEqual(r.boolean(a == b), compareWork(&ctx, &.{ r.nat(1), r.boolean(true), p }));
    };
    const shared = ctx.node(.model_U32Expr, &.{r.word(42)});
    const p = comparison(&ctx, .core_compare_ExprPair, shared, shared);
    const twice = ctx.node(.Cons, &.{ r.field(p, 0), p });
    for ([_]u64{ 100, 0, 1, 2, 3, 4, 5 }) |fuel| try expectComparison(&ctx, fuel, twice);
    try std.testing.expectEqual(r.boolean(false), compareWork(&ctx, &.{ r.nat(100), r.boolean(false), r.empty(.Nil) }));
    try std.testing.expectEqual(r.boolean(true), compareWork(&ctx, &.{ r.nat(0), r.boolean(true), r.empty(.Nil) }));
    const linked = ctx.node(.SCon, &.{ r.character('a'), ctx.node(.SCon, &.{ r.character(0x1f600), r.empty(.SNil) }) });
    try expectComparison(&ctx, 1, comparison(&ctx, .core_compare_StringPair, linked, r.literal("a😀")));
}
test "native equality visits shared graphs once without changing the tree budget" {
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    var left = ctx.node(.model_U32Expr, &.{r.word(1)});
    var right = ctx.node(.model_U32Expr, &.{r.word(1)});
    // A comparison costs 2 for the leaf, and 1 + twice the child cost for each
    // sequence node. Depth 40 is cheap as a graph but not as a semantic tree.
    var cost: u64 = 2;
    for (0..40) |_| {
        left = ctx.node(.model_SequenceExpr, &.{ left, left });
        right = ctx.node(.model_SequenceExpr, &.{ right, right });
        cost = 1 + 2 * cost;
    }
    const pending = comparison(&ctx, .core_compare_ExprPair, left, right);
    try std.testing.expectEqual(r.boolean(true), compareWork(&ctx, &.{ r.nat(cost), r.boolean(true), pending }));
    try std.testing.expectEqual(@as(usize, 41), ctx.core_compare_state.?.visits);
    try std.testing.expectEqual(r.boolean(false), compareWork(&ctx, &.{ r.nat(cost - 1), r.boolean(true), pending }));
    // Never invoke the reference at the astronomical budget; a small exhausted
    // comparison still checks that it remains a cache miss, not pointer equality.
    try expectComparison(&ctx, 10, pending);
    var deep = r.empty(.model_UnitExpr);
    for (0..4096) |_| deep = ctx.node(.model_RuntimeInitExpr, &.{deep});
    try std.testing.expectEqual(r.boolean(true), compareWork(&ctx, &.{ r.nat(4097), r.boolean(true), comparison(&ctx, .core_compare_ExprPair, deep, deep) }));
}

fn collectChildren(s: *State, ctx: *r.Context, expression: V) Allocator.Error!V {
    if (s.child_cache.get(expression)) |cached| return cached;
    s.child_work.clearRetainingCapacity();
    switch (r.tag(expression)) {
        .model_ProductExpr, .model_ArrayExpr => return r.field(expression, 0),
        .model_ConstructExpr => {
            const payload = r.field(expression, 1);
            if (r.tag(payload) == .Some) try s.child_work.append(s.allocator, r.field(payload, 0));
        },
        .model_MatchExpr => {
            var values = r.field(expression, 0);
            while (r.tag(values) == .Cons) : (values = r.field(values, 1)) try s.child_work.append(s.allocator, r.field(values, 0));
            var arms = r.field(expression, 1);
            while (r.tag(arms) == .Cons) : (arms = r.field(arms, 1)) try s.child_work.append(s.allocator, r.field(r.field(arms, 0), 1));
        },
        else => if (modelShape(r.tag(expression))) |shape| {
            if (shape.kind == .core_compare_ExprPair) {
                for (shape.fields, 0..) |kind, i| {
                    if (kind == .core_compare_ExprPair) try s.child_work.append(s.allocator, r.field(expression, i));
                }
            }
        },
    }
    var result = r.empty(.Nil);
    var i = s.child_work.items.len;
    while (i > 0) {
        i -= 1;
        result = ctx.node(.Cons, &.{ s.child_work.items[i], result });
    }
    // Leaf scans are already cheap and require no result allocation.
    if (s.child_work.items.len != 0) try s.child_cache.put(s.allocator, expression, result);
    return result;
}
pub fn expressionChildren(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len == 1);
    return collectChildren(state(ctx) catch @panic("Zig compiler ran out of memory"), ctx, args[0]) catch @panic("Zig compiler ran out of memory");
}
fn expectChildren(ctx: *r.Context, expression: V) !void {
    const oracle_id = @import("generated/functions.zig").oracle_closures_children;
    var expected = ctx.call(oracle_id, &.{expression});
    const result = expressionChildren(ctx, &.{expression});
    var actual = result;
    while (r.tag(expected) == .Cons and r.tag(actual) == .Cons) {
        try std.testing.expectEqual(r.field(expected, 0), r.field(actual, 0));
        expected = r.field(expected, 1);
        actual = r.field(actual, 1);
    }
    try std.testing.expectEqual(r.Tag.Nil, r.tag(expected));
    try std.testing.expectEqual(r.Tag.Nil, r.tag(actual));
    try std.testing.expectEqual(result, expressionChildren(ctx, &.{expression}));
}
test "native child views cover every expression and retain exact ordering" {
    @setEvalBranchQuota(20000);
    inline for (.{
        Tag.model_UnitExpr,
        Tag.model_U32Expr,
        Tag.model_BoolExpr,
        Tag.model_LocalExpr,
        Tag.model_ConstantExpr,
        Tag.model_FunctionExpr,
        Tag.model_ConstructorRefExpr,
        Tag.model_ConstructExpr,
        Tag.model_LambdaExpr,
        Tag.model_ApplyExpr,
        Tag.model_CallExpr,
        Tag.model_ScalarExpr,
        Tag.model_LetExpr,
        Tag.model_UseExpr,
        Tag.model_IfExpr,
        Tag.model_SequenceExpr,
        Tag.model_MatchExpr,
        Tag.model_GuardExpr,
        Tag.model_BlockExpr,
        Tag.model_ReturnExpr,
        Tag.model_SourceExpr,
        Tag.model_QualifiedExpr,
        Tag.model_InstantiationExpr,
        Tag.model_TagExpr,
        Tag.model_RuntimeInitExpr,
        Tag.model_F32Expr,
        Tag.model_UnaryExpr,
        Tag.model_OperationExpr,
        Tag.model_SpecializeOperationExpr,
        Tag.model_ProviderExpr,
        Tag.model_StateProviderExpr,
        Tag.model_HandleExpr,
        Tag.model_OperationDescriptorExpr,
        Tag.model_FunctionEffectsExpr,
        Tag.model_EffectHasExpr,
        Tag.model_EffectCountExpr,
        Tag.model_EffectSameExpr,
        Tag.model_PanicExpr,
        Tag.model_ProductExpr,
        Tag.model_ProjectExpr,
        Tag.model_ArrayExpr,
        Tag.model_ForExpr,
        Tag.model_ForeverExpr,
        Tag.model_ArrayGenerateExpr,
        Tag.model_ArrayFillExpr,
        Tag.model_ArrayGetExpr,
        Tag.model_ArraySetExpr,
        Tag.model_MemoExpr,
        Tag.model_ForceExpr,
        Tag.model_ArrayLengthExpr,
        Tag.model_AssociatedExpr,
        Tag.model_GenericOperationExpr,
    }) |tag| {
        var ctx = r.Context.init(std.testing.allocator);
        defer ctx.deinit();
        const shape = comptime modelShape(tag).?;
        var fields: [shape.fields.len]V = undefined;
        for (shape.fields, &fields) |kind, *value| value.* = specimen(&ctx, kind, false);
        try expectChildren(&ctx, ctx.node(tag, &fields));
        for (shape.fields, 0..) |kind, i| {
            var changed = fields;
            changed[i] = specimen(&ctx, kind, true);
            try expectChildren(&ctx, ctx.node(tag, &changed));
        }
    }
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    const a = ctx.node(.model_U32Expr, &.{r.word(1)});
    const b = ctx.node(.model_U32Expr, &.{r.word(2)});
    const arm = ctx.node(.model_MatchArm, &.{ r.empty(.Nil), b });
    const expr = ctx.node(.model_MatchExpr, &.{ ctx.node(.Cons, &.{ a, r.empty(.Nil) }), ctx.node(.Cons, &.{ arm, ctx.node(.Cons, &.{ arm, r.empty(.Nil) }) }) });
    try expectChildren(&ctx, expr);
}

fn allocationTrial(allocator: Allocator) !void {
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    var s: State = .{ .allocator = allocator };
    defer s.deinit();
    const leaf = ctx.node(.model_U32Expr, &.{r.word(42)});
    var a = leaf;
    var b = leaf;
    for (0..8) |_| {
        a = ctx.node(.model_SequenceExpr, &.{ a, a });
        b = ctx.node(.model_SequenceExpr, &.{ b, b });
    }
    var fuel: u64 = 4096;
    try std.testing.expect(try s.compare(.{ .kind = .core_compare_ExprPair, .left = a, .right = b }, &fuel));
    _ = try collectChildren(&s, &ctx, a);
    _ = try collectChildren(&s, &ctx, b);
}
test "native core buffers clean up after all allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationTrial, .{});
}
