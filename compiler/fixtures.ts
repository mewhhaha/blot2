import type {
  CoreModule,
  Expr,
  FunctionDefinition,
  Operation,
  Type,
  TypeId,
} from "./host.ts";

export const unit: Expr = { $: "UnitExpr" };
export const unitType: Type = { $: "UnitTy" };
export const u32Type: Type = { $: "U32Ty" };
export const boolType: Type = { $: "BoolTy" };

export const integer = (value: number): Expr => ({ $: "U32Expr", value });
export const local = (name: string): Expr => ({ $: "LocalExpr", name });
export const call = (callee: string, argument: Expr = unit): Expr => ({
  $: "CallExpr",
  callee,
  argument,
});
export const add = (left: Expr, right: Expr): Expr => ({
  $: "ScalarExpr",
  operator: { $: "Add" },
  left,
  right,
});
export function fn(
  name: string,
  body: Expr,
  options: Partial<Omit<FunctionDefinition, "name" | "body">> = {},
): FunctionDefinition {
  return {
    name,
    body,
    exported: true,
    parameter: "value",
    parameter_type: unitType,
    result_type: null,
    ...options,
  };
}

export function module(
  functions: readonly FunctionDefinition[],
  options: Partial<Omit<CoreModule, "functions">> = {},
): CoreModule {
  return {
    operations: [],
    constants: [],
    functions,
    data_types: [],
    ...options,
  };
}

export function operation(
  declaration: string,
  options: { module_name?: string; parameter?: Type; result?: Type } = {},
): Operation {
  return {
    identity: {
      $: "TypeId",
      module_name: options.module_name ?? "test",
      declaration,
    },
    parameter: options.parameter ?? unitType,
    result: options.result ?? u32Type,
  };
}

export const invoke = (identity: TypeId, argument: Expr = unit): Expr => ({
  $: "ApplyExpr",
  callee: { $: "OperationExpr", identity },
  argument,
});

export const scalarExample = module([
  fn("increment", add(local("value"), integer(1)), { parameter_type: null }),
  fn("answer", call("increment", { $: "ConstantExpr", name: "base" })),
], {
  constants: [{
    name: "base",
    exported: false,
    annotation: null,
    value: add(integer(20), integer(21)),
  }],
});

/**
 * Appends an entry that keeps every top-level `const`/`let` of `source`
 * reachable without calling it. Singleton array lengths consume the references
 * without constraining their element types; unused local lets would be erased
 * by lowering before reachability. Only reachable declarations are specialized,
 * const-evaluated and emitted, so diagnostics from those phases need one; the
 * probe goes last so existing source offsets stay put.
 */
export function reachedSource(source: string): string {
  const names = [
    ...source.matchAll(
      /^(?:entry )?(?:const|let) ([A-Za-z_][A-Za-z0-9_.]*)/gm,
    ),
  ].map((match) => match[1]);
  return `${source}${source.endsWith("\n") ? "" : "\n"}` +
    "entry const probe = fn () => " +
    names.reduceRight(
      (rest, name) => `@u32.add (@array.length [${name}]) (${rest})`,
      "0",
    ) + "\n";
}
