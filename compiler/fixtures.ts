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
