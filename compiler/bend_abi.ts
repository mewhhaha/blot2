// Bend's JavaScript emitter uses the source-qualified names of Data
// constructors. The public Blot API uses short names, so translate values only
// as they cross that API boundary. Bend's emitted module stays untouched.
const baseTags = new Set(["Nil", "Con", "None", "Some", "Done", "Fail"]);
// Constructors declared by compiler/model.bend. The explicit set prevents a
// similarly named constructor from another Bend module acquiring model's name.
const modelTags = new Set([
  "Add",
  "AppliedTy",
  "ApplyExpr",
  "ArrayExpr",
  "ArrayFillExpr",
  "ArrayGenerateExpr",
  "ArrayGetExpr",
  "ArrayLengthExpr",
  "ArraySetExpr",
  "ArrayTy",
  "AssociatedExpr",
  "AssociatedPredicate",
  "BinaryDispatch",
  "BindingPattern",
  "BlockExpr",
  "BoolExpr",
  "BoolPattern",
  "BoolTy",
  "CallExpr",
  "CheckedConstant",
  "CheckedFunction",
  "CheckedModule",
  "ClosedRow",
  "Constant",
  "ConstantExpr",
  "ConstantReference",
  "ConstructExpr",
  "Constructor",
  "ConstructorPattern",
  "ConstructorRefExpr",
  "DataType",
  "Diagnostic",
  "DisplayArguments",
  "DisplayElements",
  "DisplayType",
  "EffectCountExpr",
  "EffectDescriptorTy",
  "EffectHasExpr",
  "EffectRepPredicate",
  "EffectRow",
  "EffectSameExpr",
  "EffectSetTy",
  "Equal",
  "F32Absolute",
  "F32Add",
  "F32Ceiling",
  "F32Divide",
  "F32Equal",
  "F32Expr",
  "F32Floor",
  "F32GreaterEqual",
  "F32GreaterThan",
  "F32LessEqual",
  "F32LessThan",
  "F32Multiply",
  "F32Negate",
  "F32NotEqual",
  "F32SquareRoot",
  "F32Subtract",
  "F32ToU32",
  "F32Truncate",
  "F32Ty",
  "FieldUpdateDispatch",
  "FieldPredicate",
  "ForExpr",
  "ForeverExpr",
  "FreeRow",
  "FreeTy",
  "Function",
  "FunctionEffectsExpr",
  "FunctionExpr",
  "FunctionTy",
  "GenericOperationExpr",
  "GuardExpr",
  "HandleExpr",
  "IfExpr",
  "InstantiationExpr",
  "MemoExpr",
  "ForceExpr",
  "LambdaExpr",
  "LessThan",
  "LetExpr",
  "LocalExpr",
  "LocalReference",
  "MatchArm",
  "MatchExpr",
  "MemberDispatch",
  "Module",
  "Multiply",
  "NeverTy",
  "Operation",
  "OperationDescriptorExpr",
  "OperationEffect",
  "OperationExpr",
  "OperationInstance",
  "OperationPredicate",
  "OperationTemplate",
  "PanicExpr",
  "ParameterTy",
  "ProductExpr",
  "ProductPattern",
  "ProductTy",
  "ProjectExpr",
  "ProviderExpr",
  "ProviderTy",
  "QualifiedExpr",
  "ReceiverPredicate",
  "ReturnExpr",
  "RowParameter",
  "RowVariable",
  "RuntimeInitExpr",
  "ScalarExpr",
  "SequenceExpr",
  "Signature",
  "SourceExpr",
  "SpecializeOperationExpr",
  "StateProviderExpr",
  "StateProviderTy",
  "Subtract",
  "TagExpr",
  "TypeId",
  "TypeRepPredicate",
  "U32Expr",
  "U32Pattern",
  "U32Divide",
  "U32Remainder",
  "U32BitAnd",
  "U32BitOr",
  "U32BitXor",
  "U32ShiftLeft",
  "U32ShiftRight",
  "U32ToF32",
  "U32Ty",
  "UnaryExpr",
  "UnitExpr",
  "UnitPattern",
  "UnitTy",
  "UseExpr",
  "UpdatePredicate",
  "ValuePattern",
  "VariableTy",
  "WildcardPattern",
]);
const constValueTags = new Set([
  "UnitValue",
  "U32Value",
  "BoolValue",
  "FunctionValue",
  "ConstructorFunctionValue",
  "DataValue",
  "ClosureValue",
  "ReturnValue",
  "F32Value",
  "OperationValue",
  "ProviderValue",
  "StateProviderValue",
  "DemandValue",
  "MemoValue",
  "StateReadValue",
  "StateWriteValue",
  "EffectDescriptorValue",
  "EffectSetValue",
  "MatchValuesValue",
  "PatternBindingsValue",
  "ProductValue",
  "ArrayValue",
  "PatternValue",
  "HandleValue",
  "Binding",
]);

function mapTags<T>(value: T, tag: (name: string) => string): T {
  if (value === null || typeof value !== "object") return value;
  const copies = new WeakMap<object, Record<string, unknown> | unknown[]>();
  const pending: Array<[object, Record<string, unknown> | unknown[]]> = [];
  const copy = (source: object): Record<string, unknown> | unknown[] => {
    if (ArrayBuffer.isView(source) || source instanceof ArrayBuffer) {
      return source as unknown as Record<string, unknown>;
    }
    const previous = copies.get(source);
    if (previous) return previous;
    const result: Record<string, unknown> | unknown[] = Array.isArray(source)
      ? []
      : {};
    copies.set(source, result);
    pending.push([source, result]);
    return result;
  };
  const root = copy(value);
  while (pending.length) {
    const [source, result] = pending.pop()!;
    for (const [key, child] of Object.entries(source)) {
      const next = key === "$" && typeof child === "string"
        ? tag(child)
        : child !== null && typeof child === "object"
        ? copy(child)
        : child;
      (result as Record<string, unknown>)[key] = next;
    }
  }
  return root as T;
}

export function toBendModel<T>(value: T): T {
  return mapTags(value, (name) => {
    if (name.includes(".") || baseTags.has(name)) return name;
    if (!modelTags.has(name)) {
      throw new TypeError(
        `Unknown model constructor at Bend boundary: ${name}`,
      );
    }
    return `model.${name}`;
  });
}

export function fromBendModel<T>(value: T): T {
  return mapTags(
    value,
    (name) => name.startsWith("model.") ? name.slice("model.".length) : name,
  );
}

export function fromBendValue<T>(value: T): T {
  return mapTags(value, (name) => {
    if (name.startsWith("model.")) return name.slice("model.".length);
    if (!name.startsWith("const_eval.")) return name;
    const short = name.slice("const_eval.".length);
    if (!constValueTags.has(short)) {
      throw new TypeError(`Unknown const value from Bend: ${name}`);
    }
    return short;
  });
}

export function toBendCst<T>(value: T): T {
  return mapTags(value, (name) => name === "Cst" ? "cst.Cst" : name);
}
