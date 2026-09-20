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

export type Type =
  | { readonly $: "UnitTy" | "U32Ty" | "BoolTy" | "NeverTy" }
  | { readonly $: "NominalTy"; readonly identity: TypeId }
  | {
    readonly $: "AppliedTy";
    readonly identity: TypeId;
    readonly arguments: readonly Type[];
  }
  | {
    readonly $: "FunctionTy";
    readonly parameter: Type;
    readonly result: Type;
  }
  | { readonly $: "ParameterTy" | "VariableTy"; readonly index: bigint };
export type InferredType = Type;
export type ScalarOp = {
  readonly $: "Add" | "Subtract" | "Multiply" | "Equal" | "LessThan";
};
export type Access = { readonly $: "Read" | "Write" | "Insert" };
export interface Descriptor {
  readonly $: "Descriptor";
  readonly identity: TypeId;
  readonly storage: { readonly $: "Component" | "Resource" };
}
export interface Effect {
  readonly $: "Effect";
  readonly access: Access;
  readonly descriptor: Descriptor;
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
  };

export interface MatchArm {
  readonly pattern: Pattern;
  readonly body: Expr;
}

export type Expr =
  | { readonly $: "UnitExpr" }
  | { readonly $: "U32Expr"; readonly value: number }
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
    readonly value: Expr;
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
  | { readonly $: "ReadExpr"; readonly identity: TypeId }
  | { readonly $: "WriteExpr" | "InsertExpr"; readonly value: Expr };

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
  readonly descriptors: readonly Descriptor[];
  readonly constants: readonly ConstantDefinition[];
  readonly functions: readonly FunctionDefinition[];
  readonly data_types?: readonly DataType[];
}

export type ConstantValue =
  | { readonly $: "UnitValue" }
  | { readonly $: "U32Value"; readonly value: number }
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
  };

export interface FunctionAnalysis {
  readonly name: string;
  readonly parameter: InferredType;
  readonly result: InferredType;
  readonly variables: readonly bigint[];
  readonly effects: readonly Effect[];
}

export interface SystemPlan {
  readonly name: string;
  readonly effects: readonly Effect[];
  readonly query: readonly Descriptor[];
}

export interface Analysis {
  readonly functions: readonly FunctionAnalysis[];
  readonly constants: readonly {
    readonly name: string;
    readonly value: ConstantValue;
  }[];
  readonly world: {
    readonly registrations: readonly Descriptor[];
    readonly systems: readonly SystemPlan[];
    readonly batches: readonly (readonly string[])[];
  };
  readonly remaining_steps: bigint;
}

export interface EcsStorage {
  readonly identity: TypeId;
  readonly storage: Descriptor["storage"];
  readonly constructor: string;
  readonly tag: number;
}

export interface EcsArtifact {
  readonly analysis: Analysis;
  readonly storage: readonly EcsStorage[];
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

type WireType =
  | Exclude<Type, { readonly $: "AppliedTy" | "FunctionTy" }>
  | {
    readonly $: "AppliedTy";
    readonly identity: TypeId;
    readonly arguments: List<WireType>;
  }
  | {
    readonly $: "FunctionTy";
    readonly parameter: WireType;
    readonly result: WireType;
  };

type WirePattern =
  | Exclude<Pattern, { readonly $: "ConstructorPattern" }>
  | {
    readonly $: "ConstructorPattern";
    readonly constructor: string;
    readonly payload: Maybe<WirePattern>;
  };

type WireExpr =
  | Extract<Expr, {
    readonly $:
      | "UnitExpr"
      | "U32Expr"
      | "BoolExpr"
      | "LocalExpr"
      | "ConstantExpr"
      | "FunctionExpr"
      | "ConstructorRefExpr"
      | "ReadExpr";
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
    readonly value: WireExpr;
    readonly arms: List<
      {
        readonly $: "MatchArm";
        readonly pattern: WirePattern;
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
  | { readonly $: "WriteExpr" | "InsertExpr"; readonly value: WireExpr };

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
  | Exclude<ConstantValue, { readonly $: "DataValue" | "ClosureValue" }>
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
  readonly descriptors: List<Descriptor>;
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
}
interface WireAnalysis {
  readonly checked: {
    readonly functions: List<{
      readonly signature: {
        readonly name: string;
        readonly parameter: WireType;
        readonly result: WireType;
        readonly variables: List<bigint>;
      };
      readonly effects: List<Effect>;
    }>;
  };
  readonly constants: List<
    { readonly name: string; readonly value: WireValue }
  >;
  readonly world: {
    readonly registrations: List<Descriptor>;
    readonly systems: List<{
      readonly name: string;
      readonly effects: List<Effect>;
      readonly query: List<Descriptor>;
    }>;
    readonly batches: List<List<string>>;
  };
  readonly remaining_steps: bigint;
}
const bend = compiled as unknown as {
  analyze(module: unknown, steps: bigint): unknown;
  compile(module: unknown, steps: bigint): unknown;
  compile_ecs(module: unknown, steps: bigint): unknown;
  "effects.conflicts"(left: unknown, right: unknown): boolean;
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
  compile_ecs_source(
    root: Cst,
    preludeRoot: Cst,
    nodeCount: bigint,
    steps: bigint,
  ): unknown;
};

// Bend 2.0.5 qualifies imported nullary constructors, but not constructors
// with fields. Keep that release-specific ABI detail out of Blot's core API.
const constructorNames = new Map([
  ...[
    "UnitTy",
    "U32Ty",
    "BoolTy",
    "NeverTy",
    "UnitExpr",
    "WildcardPattern",
    "UnitPattern",
    "Add",
    "Subtract",
    "Multiply",
    "Equal",
    "LessThan",
    "Component",
    "Resource",
    "Read",
    "Write",
    "Insert",
  ].map((name) => [name, `model.${name}`] as const),
  ["UnitValue", "const_eval.UnitValue"],
]);
const publicNames = new Map(
  [...constructorNames].map(([name, wire]) => [wire, name]),
);

function mapConstructors(
  value: unknown,
  names: ReadonlyMap<string, string>,
): unknown {
  if (value === null || typeof value !== "object") return value;
  const result = Array.isArray(value) ? [] : {};
  const pending: { source: object; target: object }[] = [{
    source: value,
    target: result,
  }];
  for (let current = pending.pop(); current; current = pending.pop()) {
    for (const [key, field] of Object.entries(current.source)) {
      if (field !== null && typeof field === "object") {
        const target = Array.isArray(field) ? [] : {};
        Reflect.set(current.target, key, target);
        pending.push({ source: field, target });
      } else {
        Reflect.set(
          current.target,
          key,
          key === "$" && typeof field === "string"
            ? names.get(field) ?? field
            : field,
        );
      }
    }
  }
  return result;
}

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

function encodeType(type: Type): WireType {
  switch (type.$) {
    case "UnitTy":
    case "U32Ty":
    case "BoolTy":
    case "NeverTy":
      return { $: type.$ };
    case "NominalTy":
      return { $: type.$, identity: encodeIdentity(type.identity) };
    case "AppliedTy":
      return {
        $: type.$,
        identity: encodeIdentity(type.identity),
        arguments: list(type.arguments.map(encodeType)),
      };
    case "FunctionTy":
      return {
        $: type.$,
        parameter: encodeType(type.parameter),
        result: encodeType(type.result),
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
    case "AppliedTy":
      return { ...type, arguments: array(type.arguments).map(decodeType) };
    case "FunctionTy":
      return {
        ...type,
        parameter: decodeType(type.parameter),
        result: decodeType(type.result),
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
    default: {
      const invalid: never = pattern;
      throw new TypeError(`Unknown core pattern: ${String(invalid)}`);
    }
  }
}

function decodePattern(pattern: WirePattern): Pattern {
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
    case "UnitExpr":
      return { $: expression.$ };
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
    case "ReadExpr":
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
        !["Add", "Subtract", "Multiply", "Equal", "LessThan"].includes(
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
        value: encodeExpr(expression.value),
        arms: list(expression.arms.map((arm) => ({
          $: "MatchArm" as const,
          pattern: encodePattern(arm.pattern),
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
    case "WriteExpr":
    case "InsertExpr":
      return { $: expression.$, value: encodeExpr(expression.value) };
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
    case "UnitExpr":
    case "U32Expr":
    case "BoolExpr":
    case "LocalExpr":
    case "ConstantExpr":
    case "FunctionExpr":
    case "ConstructorRefExpr":
    case "ReadExpr":
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
        value: decodeExpr(expression.value),
        arms: array(expression.arms).map((arm) => ({
          pattern: decodePattern(arm.pattern),
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
    case "WriteExpr":
    case "InsertExpr":
      return { ...expression, value: decodeExpr(expression.value) };
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
    case "UnitValue":
    case "U32Value":
    case "BoolValue":
    case "FunctionValue":
    case "ConstructorFunctionValue":
      return value;
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
    descriptors: list(module.descriptors.map((descriptor) => {
      if (!["Component", "Resource"].includes(descriptor.storage.$)) {
        throw new TypeError(`Unknown storage: ${descriptor.storage.$}`);
      }
      return { ...descriptor, identity: encodeIdentity(descriptor.identity) };
    })),
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

function unmarshal(analysis: WireAnalysis): Analysis {
  return {
    functions: array(analysis.checked.functions).map((fn) => ({
      name: fn.signature.name,
      parameter: decodeType(fn.signature.parameter),
      result: decodeType(fn.signature.result),
      variables: array(fn.signature.variables),
      effects: array(fn.effects),
    })),
    constants: array(analysis.constants).map(({ name, value }) => ({
      name,
      value: decodeValue(value),
    })),
    world: {
      registrations: array(analysis.world.registrations),
      systems: array(analysis.world.systems).map((system) => ({
        name: system.name,
        effects: array(system.effects),
        query: array(system.query),
      })),
      batches: array(analysis.world.batches).map(array),
    },
    remaining_steps: analysis.remaining_steps,
  };
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

function decodeAnalysis(analysis: WireAnalysis): Analysis {
  const publicFields: WireAnalysis = {
    checked: {
      functions: list(
        array(analysis.checked.functions).map((fn) => ({
          signature: fn.signature,
          effects: fn.effects,
        })),
      ),
    },
    constants: analysis.constants,
    world: analysis.world,
    remaining_steps: analysis.remaining_steps,
  };
  return unmarshal(mapConstructors(publicFields, publicNames) as WireAnalysis);
}

// Internal pipeline boundary: intermediate Bend terms stay opaque until the
// final artifact, avoiding repeated traversal of every expression between jobs.
export function decodePipelineArtifact(value: unknown): EcsArtifact {
  const artifact = value as {
    readonly analysis: WireAnalysis;
    readonly storage: List<Omit<EcsStorage, "tag"> & { readonly tag: bigint }>;
    readonly bytes: List<number>;
  };
  return {
    analysis: decodeAnalysis(artifact.analysis),
    storage: array(
      mapConstructors(artifact.storage, publicNames) as typeof artifact.storage,
    ).map((binding) => ({
      identity: binding.identity,
      storage: binding.storage,
      constructor: binding.constructor,
      tag: u32(Number(binding.tag)),
    })),
    bytes: Uint8Array.from(array(artifact.bytes)),
  };
}

export function analyze(
  module: CoreModule,
  options: CompileOptions = {},
): Analysis {
  const result = bend.analyze(
    mapConstructors(marshal(module), constructorNames),
    constSteps(options),
  );
  return decodeAnalysis(unwrap(result as Result<WireAnalysis>));
}

export function compile(module: CoreModule, options: CompileOptions = {}) {
  const result = bend.compile(
    mapConstructors(marshal(module), constructorNames),
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

export function compileEcs(
  module: CoreModule,
  options: CompileOptions = {},
): EcsArtifact {
  const result = bend.compile_ecs(
    mapConstructors(marshal(module), constructorNames),
    constSteps(options),
  );
  const artifact = unwrap(
    result as Result<{
      readonly analysis: WireAnalysis;
      readonly storage: List<
        Omit<EcsStorage, "tag"> & { readonly tag: bigint }
      >;
      readonly bytes: List<number>;
    }>,
  );
  return decodePipelineArtifact(artifact);
}

export function effectsConflict(left: Effect, right: Effect): boolean {
  return bend["effects.conflicts"](
    mapConstructors(left, constructorNames),
    mapConstructors(right, constructorNames),
  );
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

export function compileEcsSourceTree(
  root: Cst,
  nodeCount: bigint,
  preludeRoot: Cst,
  options: CompileOptions = {},
): EcsArtifact {
  const result = bend.compile_ecs_source(
    root,
    preludeRoot,
    nat(nodeCount, "CST node count"),
    constSteps(options),
  );
  return decodePipelineArtifact(unwrap(result as Result<unknown>));
}
