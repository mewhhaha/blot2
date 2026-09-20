import compiled from "../generated/compiler/compiler.js";
import type { Cst } from "./syntax.ts";
import { CompilerError, type Diagnostic } from "./diagnostics.ts";
export { CompilerError } from "./diagnostics.ts";

// The FFI vocabulary mirrors model.bend. This module only marshals core values;
// it does not parse Blot, resolve names, infer types, evaluate consts, or emit Wasm.
export interface TypeId {
  readonly $: "TypeId";
  readonly module_name: string;
  readonly declaration: string;
}

export type RowTail =
  | { readonly $: "ClosedRow" }
  | { readonly $: "RowVariable" | "RowParameter"; readonly index: bigint };
export interface EffectRow {
  readonly $: "EffectRow";
  readonly operations: readonly TypeId[];
  readonly tail: RowTail;
}
export function emptyRow(): EffectRow {
  return { $: "EffectRow", operations: [], tail: { $: "ClosedRow" } };
}

export type Type =
  | {
    readonly $:
      | "UnitTy"
      | "U32Ty"
      | "F32Ty"
      | "BoolTy"
      | "NeverTy"
      | "EffectDescriptorTy"
      | "EffectSetTy";
  }
  | {
    readonly $: "ProviderTy";
    readonly identity: TypeId;
    readonly effects: EffectRow;
  }
  | {
    readonly $: "AppliedTy";
    readonly identity: TypeId;
    readonly arguments: readonly Type[];
  }
  | { readonly $: "ProductTy"; readonly elements: readonly Type[] }
  | { readonly $: "ArrayTy"; readonly element: Type }
  | {
    readonly $: "FunctionTy";
    readonly parameter: Type;
    readonly result: Type;
    readonly effects: EffectRow;
  }
  | { readonly $: "ParameterTy" | "VariableTy"; readonly index: bigint };
export type InferredType = Type;
export type ScalarOp = {
  readonly $:
    | "Add"
    | "Subtract"
    | "Multiply"
    | "Equal"
    | "LessThan"
    | "F32Add"
    | "F32Subtract"
    | "F32Multiply"
    | "F32Divide"
    | "F32Equal"
    | "F32NotEqual"
    | "F32LessThan"
    | "F32LessEqual"
    | "F32GreaterThan"
    | "F32GreaterEqual";
};
export type UnaryOp = {
  readonly $:
    | "F32Negate"
    | "F32Absolute"
    | "F32SquareRoot"
    | "F32Floor"
    | "F32Ceiling"
    | "F32Truncate"
    | "U32ToF32"
    | "F32ToU32";
};
export interface Effect {
  readonly $: "OperationEffect";
  readonly identity: TypeId;
}
export interface Operation {
  readonly identity: TypeId;
  readonly parameter: Type;
  readonly result: Type;
}

export interface DataType {
  readonly identity: TypeId;
  readonly parameters: bigint;
  readonly constructors: readonly {
    readonly name: string;
    readonly payload: Type | null;
  }[];
}

export type Pattern =
  | { readonly $: "WildcardPattern" | "UnitPattern" }
  | { readonly $: "BindingPattern"; readonly name: string }
  | { readonly $: "U32Pattern"; readonly value: number }
  | { readonly $: "BoolPattern"; readonly value: boolean }
  | {
    readonly $: "ConstructorPattern";
    readonly constructor: string;
    readonly payload: Pattern | null;
  }
  | { readonly $: "ProductPattern"; readonly elements: readonly Pattern[] };

export interface MatchArm {
  readonly patterns: readonly Pattern[];
  readonly body: Expr;
}

export type Expr =
  | { readonly $: "UnitExpr" }
  | { readonly $: "U32Expr"; readonly value: number }
  | { readonly $: "F32Expr"; readonly value: number }
  | { readonly $: "BoolExpr"; readonly value: boolean }
  | {
    readonly $: "LocalExpr" | "ConstantExpr" | "FunctionExpr";
    readonly name: string;
  }
  | { readonly $: "ConstructorRefExpr"; readonly constructor: string }
  | {
    readonly $: "ConstructExpr";
    readonly constructor: string;
    readonly payload: Expr | null;
  }
  | {
    readonly $: "LambdaExpr";
    readonly identity: bigint;
    readonly parameter: string;
    readonly parameter_type: Type | null;
    readonly result_type: Type | null;
    readonly body: Expr;
  }
  | { readonly $: "ApplyExpr"; readonly callee: Expr; readonly argument: Expr }
  | { readonly $: "CallExpr"; readonly callee: string; readonly argument: Expr }
  | {
    readonly $: "ScalarExpr";
    readonly operator: ScalarOp;
    readonly left: Expr;
    readonly right: Expr;
  }
  | {
    readonly $: "UnaryExpr";
    readonly operator: UnaryOp;
    readonly value: Expr;
  }
  | {
    readonly $: "LetExpr" | "UseExpr";
    readonly name: string;
    readonly value: Expr;
    readonly body: Expr;
  }
  | {
    readonly $: "IfExpr";
    readonly condition: Expr;
    readonly consequent: Expr;
    readonly alternative: Expr;
  }
  | { readonly $: "SequenceExpr"; readonly first: Expr; readonly next: Expr }
  | {
    readonly $: "MatchExpr";
    readonly values: readonly Expr[];
    readonly arms: readonly MatchArm[];
  }
  | {
    readonly $: "GuardExpr";
    readonly pattern: Pattern;
    readonly value: Expr;
    readonly alternative: Expr;
    readonly body: Expr;
  }
  | { readonly $: "BlockExpr"; readonly label: bigint; readonly body: Expr }
  | { readonly $: "ReturnExpr"; readonly label: bigint; readonly value: Expr }
  | {
    readonly $: "SourceExpr";
    readonly offset: bigint;
    readonly annotation: Maybe<Type>;
    readonly value: Expr;
  }
  | { readonly $: "PanicExpr"; readonly message: string }
  | {
    readonly $: "OperationExpr" | "OperationDescriptorExpr";
    readonly identity: TypeId;
  }
  | {
    readonly $: "ProviderExpr";
    readonly identity: TypeId;
    readonly implementation: Expr;
  }
  | { readonly $: "HandleExpr"; readonly provider: Expr; readonly body: Expr }
  | { readonly $: "FunctionEffectsExpr"; readonly callee: string }
  | {
    readonly $: "EffectHasExpr";
    readonly set: Expr;
    readonly operation: Expr;
  }
  | { readonly $: "EffectCountExpr"; readonly set: Expr }
  | { readonly $: "EffectSameExpr"; readonly left: Expr; readonly right: Expr }
  | { readonly $: "ProductExpr"; readonly elements: readonly Expr[] }
  | { readonly $: "ProjectExpr"; readonly value: Expr; readonly index: bigint }
  | { readonly $: "ArrayExpr"; readonly elements: readonly Expr[] }
  | { readonly $: "ArrayGetExpr"; readonly array: Expr; readonly index: Expr }
  | {
    readonly $: "ArraySetExpr";
    readonly array: Expr;
    readonly index: Expr;
    readonly value: Expr;
  }
  | { readonly $: "ArrayLengthExpr"; readonly array: Expr };

export interface FunctionDefinition {
  readonly name: string;
  readonly exported: boolean;
  readonly parameter: string;
  readonly parameter_type: Type | null;
  readonly result_type: Type | null;
  readonly body: Expr;
}

export interface ConstantDefinition {
  readonly name: string;
  readonly exported: boolean;
  readonly annotation: Type | null;
  readonly value: Expr;
}

export interface CoreModule {
  readonly constants: readonly ConstantDefinition[];
  readonly functions: readonly FunctionDefinition[];
  readonly data_types?: readonly DataType[];
  readonly operations?: readonly Operation[];
}

export type ConstantValue =
  | { readonly $: "UnitValue" }
  | { readonly $: "U32Value"; readonly value: number }
  | { readonly $: "F32Value"; readonly value: number }
  | { readonly $: "BoolValue"; readonly value: boolean }
  | { readonly $: "FunctionValue"; readonly name: string }
  | { readonly $: "ConstructorFunctionValue"; readonly constructor: string }
  | {
    readonly $: "DataValue";
    readonly constructor: string;
    readonly payload: ConstantValue | null;
  }
  | {
    readonly $: "ClosureValue";
    readonly identity: bigint;
    readonly parameter: string;
    readonly body: Expr;
    readonly environment: readonly {
      readonly name: string;
      readonly value: ConstantValue;
    }[];
  }
  | {
    readonly $: "OperationValue" | "EffectDescriptorValue";
    readonly identity: TypeId;
  }
  | {
    readonly $: "ProviderValue";
    readonly identity: TypeId;
    readonly implementation: ConstantValue;
  }
  | { readonly $: "EffectSetValue"; readonly operations: readonly TypeId[] }
  | { readonly $: "ProductValue"; readonly elements: readonly ConstantValue[] }
  | { readonly $: "ArrayValue"; readonly elements: readonly ConstantValue[] };

export type EffectDescriptorValue = {
  readonly $: "EffectDescriptorValue";
  readonly identity: TypeId;
};

export interface FunctionAnalysis {
  readonly name: string;
  readonly parameter: InferredType;
  readonly result: InferredType;
  readonly variables: readonly bigint[];
  readonly effects: readonly Effect[];
  readonly effect_row: EffectRow;
}

export interface Analysis {
  readonly functions: readonly FunctionAnalysis[];
  readonly constants: readonly {
    readonly name: string;
    readonly value: ConstantValue;
  }[];
  readonly remaining_steps: bigint;
}

export interface Artifact {
  readonly analysis: Analysis;
  readonly bytes: Uint8Array<ArrayBuffer>;
}

type List<A> = { readonly $: "Nil" } | {
  readonly $: "Con";
  readonly head: A;
  readonly tail: List<A>;
};
type Maybe<A> = { readonly $: "None" } | {
  readonly $: "Some";
  readonly value: A;
};
type Result<A> = { readonly $: "Done"; readonly value: A } | {
  readonly $: "Fail";
  readonly error: Diagnostic;
};

type WireRow = {
  readonly $: "EffectRow";
  readonly operations: List<TypeId>;
  readonly tail: RowTail;
};
type WireType =
  | Exclude<
    Type,
    {
      readonly $:
        | "AppliedTy"
        | "FunctionTy"
        | "ProviderTy"
        | "ProductTy"
        | "ArrayTy";
    }
  >
  | { readonly $: "ProductTy"; readonly elements: List<WireType> }
  | { readonly $: "ArrayTy"; readonly element: WireType }
  | {
    readonly $: "ProviderTy";
    readonly identity: TypeId;
    readonly effects: WireRow;
  }
  | {
    readonly $: "AppliedTy";
    readonly identity: TypeId;
    readonly arguments: List<WireType>;
  }
  | {
    readonly $: "FunctionTy";
    readonly parameter: WireType;
    readonly result: WireType;
    readonly effects: WireRow;
  };

type WirePattern =
  | Exclude<Pattern, { readonly $: "ConstructorPattern" | "ProductPattern" }>
  | { readonly $: "ProductPattern"; readonly elements: List<WirePattern> }
  | {
    readonly $: "ConstructorPattern";
    readonly constructor: string;
    readonly payload: Maybe<WirePattern>;
  };

type WireExpr =
  | { readonly $: "ProductExpr"; readonly elements: List<WireExpr> }
  | { readonly $: "ArrayExpr"; readonly elements: List<WireExpr> }
  | {
    readonly $: "ArrayGetExpr";
    readonly array: WireExpr;
    readonly index: WireExpr;
  }
  | {
    readonly $: "ArraySetExpr";
    readonly array: WireExpr;
    readonly index: WireExpr;
    readonly value: WireExpr;
  }
  | { readonly $: "ArrayLengthExpr"; readonly array: WireExpr }
  | {
    readonly $: "ProjectExpr";
    readonly value: WireExpr;
    readonly index: bigint;
  }
  | Extract<Expr, {
    readonly $:
      | "UnitExpr"
      | "U32Expr"
      | "F32Expr"
      | "BoolExpr"
      | "LocalExpr"
      | "ConstantExpr"
      | "FunctionExpr"
      | "ConstructorRefExpr"
      | "PanicExpr"
      | "OperationExpr"
      | "OperationDescriptorExpr"
      | "FunctionEffectsExpr";
  }>
  | {
    readonly $: "ConstructExpr";
    readonly constructor: string;
    readonly payload: Maybe<WireExpr>;
  }
  | {
    readonly $: "LambdaExpr";
    readonly identity: bigint;
    readonly parameter: string;
    readonly parameter_type: Maybe<WireType>;
    readonly result_type: Maybe<WireType>;
    readonly body: WireExpr;
  }
  | {
    readonly $: "ApplyExpr";
    readonly callee: WireExpr;
    readonly argument: WireExpr;
  }
  | {
    readonly $: "CallExpr";
    readonly callee: string;
    readonly argument: WireExpr;
  }
  | {
    readonly $: "ScalarExpr";
    readonly operator: ScalarOp;
    readonly left: WireExpr;
    readonly right: WireExpr;
  }
  | {
    readonly $: "UnaryExpr";
    readonly operator: UnaryOp;
    readonly value: WireExpr;
  }
  | {
    readonly $: "LetExpr" | "UseExpr";
    readonly name: string;
    readonly value: WireExpr;
    readonly body: WireExpr;
  }
  | {
    readonly $: "IfExpr";
    readonly condition: WireExpr;
    readonly consequent: WireExpr;
    readonly alternative: WireExpr;
  }
  | {
    readonly $: "SequenceExpr";
    readonly first: WireExpr;
    readonly next: WireExpr;
  }
  | {
    readonly $: "MatchExpr";
    readonly values: List<WireExpr>;
    readonly arms: List<
      {
        readonly $: "MatchArm";
        readonly patterns: List<WirePattern>;
        readonly body: WireExpr;
      }
    >;
  }
  | {
    readonly $: "GuardExpr";
    readonly pattern: WirePattern;
    readonly value: WireExpr;
    readonly alternative: WireExpr;
    readonly body: WireExpr;
  }
  | { readonly $: "BlockExpr"; readonly label: bigint; readonly body: WireExpr }
  | {
    readonly $: "ReturnExpr";
    readonly label: bigint;
    readonly value: WireExpr;
  }
  | {
    readonly $: "SourceExpr";
    readonly offset: bigint;
    readonly annotation: Maybe<WireType>;
    readonly value: WireExpr;
  }
  | {
    readonly $: "ProviderExpr";
    readonly identity: TypeId;
    readonly implementation: WireExpr;
  }
  | {
    readonly $: "HandleExpr";
    readonly provider: WireExpr;
    readonly body: WireExpr;
  }
  | {
    readonly $: "EffectHasExpr";
    readonly set: WireExpr;
    readonly operation: WireExpr;
  }
  | { readonly $: "EffectCountExpr"; readonly set: WireExpr }
  | {
    readonly $: "EffectSameExpr";
    readonly left: WireExpr;
    readonly right: WireExpr;
  };

interface WireDataType {
  readonly $: "DataType";
  readonly identity: TypeId;
  readonly parameters: bigint;
  readonly constructors: List<{
    readonly $: "Constructor";
    readonly name: string;
    readonly payload: Maybe<WireType>;
  }>;
}

type WireValue =
  | { readonly $: "MatchValuesValue"; readonly values: List<WireValue> }
  | Exclude<
    ConstantValue,
    {
      readonly $:
        | "DataValue"
        | "ClosureValue"
        | "ProviderValue"
        | "EffectSetValue"
        | "ProductValue"
        | "ArrayValue";
    }
  >
  | { readonly $: "ProductValue"; readonly elements: List<WireValue> }
  | { readonly $: "ArrayValue"; readonly elements: List<WireValue> }
  | {
    readonly $: "ProviderValue";
    readonly identity: TypeId;
    readonly implementation: WireValue;
  }
  | { readonly $: "EffectSetValue"; readonly operations: List<TypeId> }
  | {
    readonly $: "DataValue";
    readonly constructor: string;
    readonly payload: Maybe<WireValue>;
  }
  | {
    readonly $: "ClosureValue";
    readonly identity: bigint;
    readonly parameter: string;
    readonly body: WireExpr;
    readonly environment: List<
      { readonly name: string; readonly value: WireValue }
    >;
  }
  | {
    readonly $: "ReturnValue";
    readonly label: bigint;
    readonly value: WireValue;
  };

interface WireModule {
  readonly $: "Module";
  readonly constants: List<
    Omit<ConstantDefinition, "annotation" | "value"> & {
      readonly $: "Constant";
      readonly annotation: Maybe<WireType>;
      readonly value: WireExpr;
    }
  >;
  readonly functions: List<
    Omit<FunctionDefinition, "parameter_type" | "result_type" | "body"> & {
      readonly $: "Function";
      readonly parameter_type: Maybe<WireType>;
      readonly result_type: Maybe<WireType>;
      readonly body: WireExpr;
    }
  >;
  readonly data_types: List<WireDataType>;
  readonly operations: List<
    {
      readonly $: "Operation";
      readonly identity: TypeId;
      readonly parameter: WireType;
      readonly result: WireType;
    }
  >;
}
interface WireAnalysis {
  readonly checked: {
    readonly functions: List<{
      readonly signature: {
        readonly name: string;
        readonly parameter: WireType;
        readonly result: WireType;
        readonly variables: List<bigint>;
        readonly effects: WireRow;
      };
      readonly effects: List<Effect>;
    }>;
  };
  readonly constants: List<
    { readonly name: string; readonly value: WireValue }
  >;
  readonly remaining_steps: bigint;
}
const bend = compiled as unknown as {
  analyze(module: unknown, steps: bigint): unknown;
  compile(module: unknown, steps: bigint): unknown;
  analyze_source(
    root: Cst,
    preludeRoot: Cst,
    nodeCount: bigint,
    steps: bigint,
  ): unknown;
  compile_source(
    root: Cst,
    preludeRoot: Cst,
    nodeCount: bigint,
    steps: bigint,
  ): unknown;
};

function list<A>(values: readonly A[]): List<A> {
  let result: List<A> = { $: "Nil" };
  for (let index = values.length - 1; index >= 0; index--) {
    result = { $: "Con", head: values[index], tail: result };
  }
  return result;
}

function array<A>(values: List<A>): A[] {
  const result: A[] = [];
  for (let cursor = values; cursor.$ === "Con"; cursor = cursor.tail) {
    result.push(cursor.head);
  }
  return result;
}

function maybe<A>(value: A | null): Maybe<A> {
  return value === null ? { $: "None" } : { $: "Some", value };
}

function nat(value: bigint, label: string): bigint {
  if (typeof value !== "bigint" || value < 0n || value > 0xFFFFFFFFFFFFn) {
    throw new RangeError(`${label} must be a Nat (0..2^48-1)`);
  }
  return value;
}

function u32(value: number): number {
  if (!Number.isInteger(value) || value < 0 || value > 0xFFFFFFFF) {
    throw new TypeError(`U32 literal out of range: ${value}`);
  }
  return value;
}

function f32(value: number): number {
  if (typeof value !== "number") {
    throw new TypeError("F32 literal must be a number");
  }
  return Math.fround(value);
}

function unicode(value: string, label: string): string {
  if (typeof value !== "string" || !value.isWellFormed()) {
    throw new TypeError(`${label} is not valid Unicode`);
  }
  return value;
}

function bool(value: boolean, label: string): boolean {
  if (typeof value !== "boolean") {
    throw new TypeError(`${label} must be a Bool`);
  }
  return value;
}

function encodeIdentity(identity: TypeId): TypeId {
  return {
    $: "TypeId",
    module_name: unicode(identity.module_name, "Type module"),
    declaration: unicode(identity.declaration, "Type name"),
  };
}

function encodeRow(row: EffectRow): WireRow {
  const tail = row.tail.$ === "ClosedRow"
    ? row.tail
    : { $: row.tail.$, index: nat(row.tail.index, "Row index") };
  if (!["ClosedRow", "RowVariable", "RowParameter"].includes(tail.$)) {
    throw new TypeError(`Unknown effect row tail: ${tail.$}`);
  }
  return {
    $: "EffectRow",
    operations: list(row.operations.map(encodeIdentity)),
    tail,
  };
}
function decodeRow(row: WireRow): EffectRow {
  return { ...row, operations: array(row.operations) };
}

function encodeType(type: Type): WireType {
  switch (type.$) {
    case "UnitTy":
    case "U32Ty":
    case "F32Ty":
    case "BoolTy":
    case "NeverTy":
    case "EffectDescriptorTy":
    case "EffectSetTy":
      return { $: type.$ };
    case "ProviderTy":
      return {
        $: type.$,
        identity: encodeIdentity(type.identity),
        effects: encodeRow(type.effects),
      };
    case "AppliedTy":
      return {
        $: type.$,
        identity: encodeIdentity(type.identity),
        arguments: list(type.arguments.map(encodeType)),
      };
    case "ProductTy":
      return { $: type.$, elements: list(type.elements.map(encodeType)) };
    case "ArrayTy":
      return { $: type.$, element: encodeType(type.element) };
    case "FunctionTy":
      return {
        $: type.$,
        parameter: encodeType(type.parameter),
        result: encodeType(type.result),
        effects: encodeRow(type.effects),
      };
    case "ParameterTy":
    case "VariableTy":
      return { $: type.$, index: nat(type.index, `${type.$} index`) };
    default: {
      const invalid: never = type;
      throw new TypeError(`Unknown core type: ${String(invalid)}`);
    }
  }
}

function decodeType(type: WireType): Type {
  switch (type.$) {
    case "ProviderTy":
      return { ...type, effects: decodeRow(type.effects) };
    case "AppliedTy":
      return { ...type, arguments: array(type.arguments).map(decodeType) };
    case "ProductTy":
      return { ...type, elements: array(type.elements).map(decodeType) };
    case "ArrayTy":
      return { ...type, element: decodeType(type.element) };
    case "FunctionTy":
      return {
        ...type,
        parameter: decodeType(type.parameter),
        result: decodeType(type.result),
        effects: decodeRow(type.effects),
      };
    default:
      return type;
  }
}

function encodeOptionalType(type: Type | null): Maybe<WireType> {
  return maybe(type === null ? null : encodeType(type));
}

function decodeOptionalType(type: Maybe<WireType>): Type | null {
  return type.$ === "None" ? null : decodeType(type.value);
}

function encodePattern(pattern: Pattern): WirePattern {
  switch (pattern.$) {
    case "WildcardPattern":
    case "UnitPattern":
      return { $: pattern.$ };
    case "BindingPattern":
      return { $: pattern.$, name: unicode(pattern.name, "Pattern binding") };
    case "U32Pattern":
      return { $: pattern.$, value: u32(pattern.value) };
    case "BoolPattern":
      return { $: pattern.$, value: bool(pattern.value, "Pattern value") };
    case "ConstructorPattern":
      return {
        $: pattern.$,
        constructor: unicode(pattern.constructor, "Pattern constructor"),
        payload: maybe(
          pattern.payload === null ? null : encodePattern(pattern.payload),
        ),
      };
    case "ProductPattern":
      return {
        $: pattern.$,
        elements: list(pattern.elements.map(encodePattern)),
      };
    default: {
      const invalid: never = pattern;
      throw new TypeError(`Unknown core pattern: ${String(invalid)}`);
    }
  }
}

function decodePattern(pattern: WirePattern): Pattern {
  if (pattern.$ === "ProductPattern") {
    return {
      $: pattern.$,
      elements: array(pattern.elements).map(decodePattern),
    };
  }
  if (pattern.$ !== "ConstructorPattern") return pattern;
  return {
    ...pattern,
    payload: pattern.payload.$ === "None"
      ? null
      : decodePattern(pattern.payload.value),
  };
}

function encodeExpr(expression: Expr): WireExpr {
  switch (expression.$) {
    case "U32Expr":
      return { $: expression.$, value: u32(expression.value) };
    case "F32Expr":
      return { $: expression.$, value: f32(expression.value) };
    case "UnitExpr":
      return { $: expression.$ };
    case "ProductExpr":
    case "ArrayExpr":
      return {
        $: expression.$,
        elements: list(expression.elements.map(encodeExpr)),
      };
    case "ArrayGetExpr":
      return {
        $: expression.$,
        array: encodeExpr(expression.array),
        index: encodeExpr(expression.index),
      };
    case "ArraySetExpr":
      return {
        $: expression.$,
        array: encodeExpr(expression.array),
        index: encodeExpr(expression.index),
        value: encodeExpr(expression.value),
      };
    case "ArrayLengthExpr":
      return { $: expression.$, array: encodeExpr(expression.array) };
    case "ProjectExpr":
      return {
        $: expression.$,
        value: encodeExpr(expression.value),
        index: nat(expression.index, "Product projection index"),
      };
    case "BoolExpr":
      return {
        $: expression.$,
        value: bool(expression.value, "Boolean literal"),
      };
    case "LocalExpr":
    case "ConstantExpr":
    case "FunctionExpr":
      return {
        $: expression.$,
        name: unicode(expression.name, "Reference name"),
      };
    case "OperationExpr":
    case "OperationDescriptorExpr":
      return { $: expression.$, identity: encodeIdentity(expression.identity) };
    case "ConstructorRefExpr":
      return {
        $: expression.$,
        constructor: unicode(expression.constructor, "Constructor name"),
      };
    case "ConstructExpr":
      return {
        $: expression.$,
        constructor: unicode(expression.constructor, "Constructor name"),
        payload: maybe(
          expression.payload === null ? null : encodeExpr(expression.payload),
        ),
      };
    case "LambdaExpr":
      return {
        $: expression.$,
        identity: nat(expression.identity, "Lambda identity"),
        parameter: unicode(expression.parameter, "Lambda parameter"),
        parameter_type: encodeOptionalType(expression.parameter_type),
        result_type: encodeOptionalType(expression.result_type),
        body: encodeExpr(expression.body),
      };
    case "ApplyExpr":
      return {
        $: expression.$,
        callee: encodeExpr(expression.callee),
        argument: encodeExpr(expression.argument),
      };
    case "CallExpr":
      return {
        $: expression.$,
        callee: unicode(expression.callee, "Callee name"),
        argument: encodeExpr(expression.argument),
      };
    case "ScalarExpr":
      if (
        ![
          "Add",
          "Subtract",
          "Multiply",
          "Equal",
          "LessThan",
          "F32Add",
          "F32Subtract",
          "F32Multiply",
          "F32Divide",
          "F32Equal",
          "F32NotEqual",
          "F32LessThan",
          "F32LessEqual",
          "F32GreaterThan",
          "F32GreaterEqual",
        ].includes(
          expression.operator.$,
        )
      ) {
        throw new TypeError(
          `Unknown scalar operator: ${expression.operator.$}`,
        );
      }
      return {
        ...expression,
        left: encodeExpr(expression.left),
        right: encodeExpr(expression.right),
      };
    case "UnaryExpr":
      if (
        ![
          "F32Negate",
          "F32Absolute",
          "F32SquareRoot",
          "F32Floor",
          "F32Ceiling",
          "F32Truncate",
          "U32ToF32",
          "F32ToU32",
        ].includes(expression.operator.$)
      ) {
        throw new TypeError(`Unknown unary operator: ${expression.operator.$}`);
      }
      return { ...expression, value: encodeExpr(expression.value) };
    case "LetExpr":
    case "UseExpr":
      return {
        $: expression.$,
        name: unicode(expression.name, "Binding name"),
        value: encodeExpr(expression.value),
        body: encodeExpr(expression.body),
      };
    case "IfExpr":
      return {
        $: expression.$,
        condition: encodeExpr(expression.condition),
        consequent: encodeExpr(expression.consequent),
        alternative: encodeExpr(expression.alternative),
      };
    case "SequenceExpr":
      return {
        $: expression.$,
        first: encodeExpr(expression.first),
        next: encodeExpr(expression.next),
      };
    case "MatchExpr":
      return {
        $: expression.$,
        values: list(expression.values.map(encodeExpr)),
        arms: list(expression.arms.map((arm) => ({
          $: "MatchArm" as const,
          patterns: list(arm.patterns.map(encodePattern)),
          body: encodeExpr(arm.body),
        }))),
      };
    case "GuardExpr":
      return {
        $: expression.$,
        pattern: encodePattern(expression.pattern),
        value: encodeExpr(expression.value),
        alternative: encodeExpr(expression.alternative),
        body: encodeExpr(expression.body),
      };
    case "BlockExpr":
      return {
        $: expression.$,
        label: nat(expression.label, "Block label"),
        body: encodeExpr(expression.body),
      };
    case "ReturnExpr":
      return {
        $: expression.$,
        label: nat(expression.label, "Return label"),
        value: encodeExpr(expression.value),
      };
    case "PanicExpr":
      return {
        $: expression.$,
        message: unicode(expression.message, "Panic message"),
      };
    case "FunctionEffectsExpr":
      return {
        $: expression.$,
        callee: unicode(expression.callee, "Reflected function name"),
      };
    case "ProviderExpr":
      return {
        $: expression.$,
        identity: encodeIdentity(expression.identity),
        implementation: encodeExpr(expression.implementation),
      };
    case "HandleExpr":
      return {
        $: expression.$,
        provider: encodeExpr(expression.provider),
        body: encodeExpr(expression.body),
      };
    case "EffectHasExpr":
      return {
        $: expression.$,
        set: encodeExpr(expression.set),
        operation: encodeExpr(expression.operation),
      };
    case "EffectCountExpr":
      return { $: expression.$, set: encodeExpr(expression.set) };
    case "EffectSameExpr":
      return {
        $: expression.$,
        left: encodeExpr(expression.left),
        right: encodeExpr(expression.right),
      };
    case "SourceExpr":
      return {
        $: expression.$,
        offset: nat(expression.offset, "Source offset"),
        annotation: expression.annotation.$ === "None"
          ? { $: "None" }
          : { $: "Some", value: encodeType(expression.annotation.value) },
        value: encodeExpr(expression.value),
      };
    default: {
      const invalid: never = expression;
      throw new TypeError(`Unknown core expression: ${String(invalid)}`);
    }
  }
}

function decodeExpr(expression: WireExpr): Expr {
  switch (expression.$) {
    case "ProductExpr":
    case "ArrayExpr":
      return {
        ...expression,
        elements: array(expression.elements).map(decodeExpr),
      };
    case "ArrayGetExpr":
      return {
        ...expression,
        array: decodeExpr(expression.array),
        index: decodeExpr(expression.index),
      };
    case "ArraySetExpr":
      return {
        ...expression,
        array: decodeExpr(expression.array),
        index: decodeExpr(expression.index),
        value: decodeExpr(expression.value),
      };
    case "ArrayLengthExpr":
      return { ...expression, array: decodeExpr(expression.array) };
    case "ProjectExpr":
      return { ...expression, value: decodeExpr(expression.value) };
    case "UnitExpr":
    case "U32Expr":
    case "F32Expr":
    case "BoolExpr":
    case "LocalExpr":
    case "ConstantExpr":
    case "FunctionExpr":
    case "ConstructorRefExpr":
    case "OperationExpr":
    case "OperationDescriptorExpr":
    case "PanicExpr":
    case "FunctionEffectsExpr":
      return expression;
    case "ConstructExpr":
      return {
        ...expression,
        payload: expression.payload.$ === "None"
          ? null
          : decodeExpr(expression.payload.value),
      };
    case "LambdaExpr":
      return {
        ...expression,
        parameter_type: decodeOptionalType(expression.parameter_type),
        result_type: decodeOptionalType(expression.result_type),
        body: decodeExpr(expression.body),
      };
    case "ApplyExpr":
      return {
        ...expression,
        callee: decodeExpr(expression.callee),
        argument: decodeExpr(expression.argument),
      };
    case "CallExpr":
      return { ...expression, argument: decodeExpr(expression.argument) };
    case "ScalarExpr":
      return {
        ...expression,
        left: decodeExpr(expression.left),
        right: decodeExpr(expression.right),
      };
    case "LetExpr":
    case "UseExpr":
      return {
        ...expression,
        value: decodeExpr(expression.value),
        body: decodeExpr(expression.body),
      };
    case "IfExpr":
      return {
        ...expression,
        condition: decodeExpr(expression.condition),
        consequent: decodeExpr(expression.consequent),
        alternative: decodeExpr(expression.alternative),
      };
    case "SequenceExpr":
      return {
        ...expression,
        first: decodeExpr(expression.first),
        next: decodeExpr(expression.next),
      };
    case "MatchExpr":
      return {
        ...expression,
        values: array(expression.values).map(decodeExpr),
        arms: array(expression.arms).map((arm) => ({
          patterns: array(arm.patterns).map(decodePattern),
          body: decodeExpr(arm.body),
        })),
      };
    case "GuardExpr":
      return {
        ...expression,
        pattern: decodePattern(expression.pattern),
        value: decodeExpr(expression.value),
        alternative: decodeExpr(expression.alternative),
        body: decodeExpr(expression.body),
      };
    case "BlockExpr":
      return { ...expression, body: decodeExpr(expression.body) };
    case "ReturnExpr":
    case "UnaryExpr":
      return { ...expression, value: decodeExpr(expression.value) };
    case "ProviderExpr":
      return {
        ...expression,
        implementation: decodeExpr(expression.implementation),
      };
    case "HandleExpr":
      return {
        ...expression,
        provider: decodeExpr(expression.provider),
        body: decodeExpr(expression.body),
      };
    case "EffectHasExpr":
      return {
        ...expression,
        set: decodeExpr(expression.set),
        operation: decodeExpr(expression.operation),
      };
    case "EffectCountExpr":
      return { ...expression, set: decodeExpr(expression.set) };
    case "EffectSameExpr":
      return {
        ...expression,
        left: decodeExpr(expression.left),
        right: decodeExpr(expression.right),
      };
    case "SourceExpr":
      return {
        ...expression,
        annotation: expression.annotation.$ === "None"
          ? { $: "None" }
          : { $: "Some", value: decodeType(expression.annotation.value) },
        value: decodeExpr(expression.value),
      };
  }
}

function decodeValue(value: WireValue): ConstantValue {
  switch (value.$) {
    case "ProductValue":
    case "ArrayValue":
      return { ...value, elements: array(value.elements).map(decodeValue) };
    case "UnitValue":
    case "U32Value":
    case "F32Value":
    case "BoolValue":
    case "FunctionValue":
    case "ConstructorFunctionValue":
    case "OperationValue":
    case "EffectDescriptorValue":
      return value;
    case "ProviderValue":
      return { ...value, implementation: decodeValue(value.implementation) };
    case "EffectSetValue":
      return { ...value, operations: array(value.operations) };
    case "DataValue":
      return {
        ...value,
        payload: value.payload.$ === "None"
          ? null
          : decodeValue(value.payload.value),
      };
    case "ClosureValue":
      return {
        ...value,
        body: decodeExpr(value.body),
        environment: array(value.environment).map((binding) => ({
          name: binding.name,
          value: decodeValue(binding.value),
        })),
      };
    case "MatchValuesValue":
      throw new CompilerError({
        code: "internal_error",
        subject: "const",
        message: "A checked constant leaked internal match values",
      });
    case "ReturnValue":
      throw new CompilerError({
        code: "internal_error",
        subject: "const",
        message: "A checked constant leaked a block return",
      });
  }
}

function marshal(module: CoreModule): WireModule {
  return {
    $: "Module",
    operations: list((module.operations ?? []).map((operation) => ({
      $: "Operation" as const,
      identity: encodeIdentity(operation.identity),
      parameter: encodeType(operation.parameter),
      result: encodeType(operation.result),
    }))),
    constants: list(module.constants.map((constant) => ({
      $: "Constant" as const,
      name: unicode(constant.name, "Constant name"),
      exported: bool(constant.exported, "Constant export flag"),
      annotation: encodeOptionalType(constant.annotation),
      value: encodeExpr(constant.value),
    }))),
    functions: list(module.functions.map((fn) => ({
      $: "Function" as const,
      name: unicode(fn.name, "Function name"),
      exported: bool(fn.exported, "Function export flag"),
      parameter: unicode(fn.parameter, "Function parameter"),
      parameter_type: encodeOptionalType(fn.parameter_type),
      result_type: encodeOptionalType(fn.result_type),
      body: encodeExpr(fn.body),
    }))),
    data_types: list((module.data_types ?? []).map((type) => ({
      $: "DataType" as const,
      identity: encodeIdentity(type.identity),
      parameters: nat(type.parameters, "Data type parameter count"),
      constructors: list(type.constructors.map((constructor) => ({
        $: "Constructor" as const,
        name: unicode(constructor.name, "Constructor name"),
        payload: encodeOptionalType(constructor.payload),
      }))),
    }))),
  };
}

function decodeAnalysis(analysis: WireAnalysis): Analysis {
  // Decoded leaves can still reference shared Bend cache terms. Detach only
  // the public result, not the internal checked function bodies.
  return structuredClone({
    functions: array(analysis.checked.functions).map((fn) => ({
      name: fn.signature.name,
      parameter: decodeType(fn.signature.parameter),
      result: decodeType(fn.signature.result),
      variables: array(fn.signature.variables),
      effects: array(fn.effects),
      effect_row: decodeRow(fn.signature.effects),
    })),
    constants: array(analysis.constants).map(({ name, value }) => ({
      name,
      value: decodeValue(value),
    })),
    remaining_steps: analysis.remaining_steps,
  });
}

function unwrap<A>(result: Result<A>): A {
  if (result.$ === "Fail") throw new CompilerError(result.error);
  return result.value;
}

export interface CompileOptions {
  readonly const_steps?: bigint;
}

export function constSteps(options: CompileOptions): bigint {
  return nat(options.const_steps ?? 10_000n, "const_steps");
}

// Internal pipeline boundary: intermediate Bend terms stay opaque until the
// final artifact, avoiding repeated traversal of every expression between jobs.
export function decodePipelineArtifact(value: unknown): Artifact {
  const artifact = value as {
    readonly analysis: WireAnalysis;
    readonly bytes: List<number>;
  };
  return {
    analysis: decodeAnalysis(artifact.analysis),
    bytes: Uint8Array.from(array(artifact.bytes)),
  };
}

export function analyze(
  module: CoreModule,
  options: CompileOptions = {},
): Analysis {
  const result = bend.analyze(marshal(module), constSteps(options));
  return decodeAnalysis(unwrap(result as Result<WireAnalysis>));
}

export function compile(module: CoreModule, options: CompileOptions = {}) {
  const result = bend.compile(marshal(module), constSteps(options));
  const artifact = unwrap(
    result as Result<{
      readonly analysis: WireAnalysis;
      readonly bytes: List<number>;
    }>,
  );
  return {
    analysis: decodeAnalysis(artifact.analysis),
    bytes: Uint8Array.from(array(artifact.bytes)),
  };
}

export function analyzeSourceTree(
  root: Cst,
  nodeCount: bigint,
  preludeRoot: Cst,
  options: CompileOptions = {},
): Analysis {
  const result = bend.analyze_source(
    root,
    preludeRoot,
    nat(nodeCount, "CST node count"),
    constSteps(options),
  );
  return decodeAnalysis(unwrap(result as Result<WireAnalysis>));
}

export function compileSourceTree(
  root: Cst,
  nodeCount: bigint,
  preludeRoot: Cst,
  options: CompileOptions = {},
) {
  const result = bend.compile_source(
    root,
    preludeRoot,
    nat(nodeCount, "CST node count"),
    constSteps(options),
  );
  const artifact = unwrap(
    result as Result<{
      readonly analysis: WireAnalysis;
      readonly bytes: List<number>;
    }>,
  );
  return {
    analysis: decodeAnalysis(artifact.analysis),
    bytes: Uint8Array.from(array(artifact.bytes)),
  };
}
