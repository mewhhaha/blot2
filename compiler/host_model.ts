// Backend-independent public compiler model and option validation.
// Kept separate so the native Carp host never loads generated Bend JavaScript.
type Maybe<A> = { readonly $: "None" } | {
  readonly $: "Some";
  readonly value: A;
};

export interface TypeId {
  readonly $: "TypeId";
  readonly module_name: string;
  readonly declaration: string;
}

export type RowTail =
  | { readonly $: "ClosedRow" }
  | { readonly $: "RowVariable" | "RowParameter"; readonly index: bigint }
  | { readonly $: "FreeRow"; readonly scope: string; readonly name: string };
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
    readonly $: "StateProviderTy";
    readonly read: TypeId;
    readonly write: TypeId;
    readonly state: Type;
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
  | { readonly $: "FreeTy"; readonly scope: string; readonly name: string }
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
export type Predicate =
  | {
    readonly $: "AssociatedPredicate";
    readonly member: string;
    readonly templates: readonly TypeId[];
    readonly left: Type;
    readonly right: Type;
    readonly result: Type;
    readonly invocation: EffectRow;
  }
  | {
    readonly $: "ReceiverPredicate";
    readonly member: string;
    readonly templates: readonly TypeId[];
    readonly receiver: Type;
    readonly argument: Type;
    readonly result: Type;
    readonly invocation: EffectRow;
  }
  | {
    readonly $: "FieldPredicate";
    readonly member: string;
    readonly receiver: Type;
    readonly result: Type;
  }
  | {
    readonly $: "UpdatePredicate";
    readonly member: string;
    readonly receiver: Type;
    readonly assigned: Type;
    readonly result: Type;
    readonly invocation: EffectRow;
  }
  | {
    readonly $: "OperationPredicate";
    readonly template: TypeId;
    readonly arguments: readonly Type[];
    readonly function_type: Type;
  }
  | { readonly $: "TypeRepPredicate"; readonly represented: Type }
  | { readonly $: "EffectRepPredicate"; readonly row: EffectRow };

export interface DataType {
  readonly identity: TypeId;
  readonly parameters: bigint;
  readonly constructors: readonly {
    readonly name: string;
    readonly payload: Type | null;
    readonly fields?: readonly string[];
  }[];
}

export type ValueReference = {
  readonly $: "LocalReference" | "ConstantReference";
  readonly name: string;
};

export type Pattern =
  | { readonly $: "WildcardPattern" | "UnitPattern" }
  | { readonly $: "BindingPattern"; readonly name: string }
  | { readonly $: "ValuePattern"; readonly reference: ValueReference }
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
  | { readonly $: "RuntimeInitExpr"; readonly value: Expr }
  | {
    readonly $: "TagExpr";
    readonly offset: bigint;
    readonly callee: Expr;
    readonly argument: Expr;
  }
  | {
    readonly $: "SourceExpr";
    readonly offset: bigint;
    readonly annotation: Maybe<Type>;
    readonly value: Expr;
  }
  | {
    readonly $: "QualifiedExpr";
    readonly offset: bigint;
    readonly annotation: Type;
    readonly predicates: readonly Predicate[];
    readonly value: Expr;
  }
  | {
    readonly $: "InstantiationExpr";
    readonly site: bigint;
    readonly value: Expr;
  }
  | { readonly $: "PanicExpr"; readonly message: string }
  | {
    readonly $: "OperationExpr" | "OperationDescriptorExpr";
    readonly identity: TypeId;
  }
  | {
    readonly $: "StateProviderExpr";
    readonly read: TypeId;
    readonly write: TypeId;
    readonly initial: Expr;
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
  | {
    readonly $: "ForExpr";
    readonly index: string;
    readonly start: Expr;
    readonly end: Expr;
    readonly state: string;
    readonly initial: Expr;
    readonly body: Expr;
  }
  | {
    readonly $: "ForeverExpr";
    readonly state: string;
    readonly initial: Expr;
    readonly body: Expr;
  }
  | {
    readonly $: "ArrayGenerateExpr";
    readonly count: Expr;
    readonly generator: Expr;
  }
  | { readonly $: "ArrayFillExpr"; readonly count: Expr; readonly value: Expr }
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
    readonly $: "StateProviderValue";
    readonly read: TypeId;
    readonly write: TypeId;
    readonly initial: ConstantValue;
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

/** A compiled guest module. Its Wasm carries the guest ABI (`blot:abi`). */
export interface Artifact {
  readonly bytes: Uint8Array<ArrayBuffer>;
  /** Absent when compiled with `analysis: false`. */
  readonly analysis?: Analysis;
}

/** An artifact compiled with its analysis (the default). */
export interface AnalyzedArtifact extends Artifact {
  readonly analysis: Analysis;
}

export interface CompileOptions {
  readonly const_steps?: bigint;
}

/** Options for `compile`. */
export interface ArtifactOptions extends CompileOptions {
  /**
   * `false` returns only the Wasm bytes; guests read their ABI from them.
   * The native compiler then neither encodes nor sends the analysis.
   */
  readonly analysis?: boolean;
}

/** `compile` options that keep the analysis (the default). */
export type AnalyzedArtifactOptions = CompileOptions & {
  readonly analysis?: true;
};

export function constSteps(options: CompileOptions): bigint {
  const value = options.const_steps ?? 10_000n;
  if (typeof value !== "bigint" || value < 0n || value > 0xFFFFFFFFFFFFn) {
    throw new RangeError("const_steps must be a Nat (0..2^48-1)");
  }
  return value;
}

/** Whether `compile` returns the analysis beside the Wasm bytes. */
export function includesAnalysis(options: ArtifactOptions): boolean {
  if (options.analysis === undefined) return true;
  if (typeof options.analysis !== "boolean") {
    throw new TypeError("analysis must be a boolean");
  }
  return options.analysis;
}
