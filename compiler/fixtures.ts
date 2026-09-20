import type {
  CoreModule,
  Descriptor,
  Expr,
  FunctionDefinition,
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
    descriptors: [],
    constants: [],
    functions,
    data_types: [],
    ...options,
  };
}

export function descriptor(
  declaration: string,
  storage: "Component" | "Resource" = "Component",
  module_name = "game/components",
): Descriptor {
  return {
    $: "Descriptor",
    identity: { $: "TypeId", module_name, declaration },
    storage: { $: storage },
  };
}

export const read = (identity: TypeId): Expr => ({ $: "ReadExpr", identity });

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

export const position = descriptor("Position");
export const velocity = descriptor("Velocity");
export const time = descriptor("Time", "Resource");
export const ghost = descriptor("Ghost");

// The typed core corresponding to the small effects-only ECS regression case.
export const ecsExample = module([
  fn("read_position", read(position.identity), { exported: false }),
  fn("move", {
    $: "UseExpr",
    name: "position",
    value: call("read_position"),
    body: {
      $: "SequenceExpr",
      first: read(velocity.identity),
      next: {
        $: "SequenceExpr",
        first: read(time.identity),
        next: {
          $: "WriteExpr",
          value: local("position"),
        },
      },
    },
  }),
  fn("insert_ghost", { $: "InsertExpr", value: local("value") }, {
    parameter_type: { $: "NominalTy", identity: ghost.identity },
  }),
], { descriptors: [position, velocity, time, ghost] });
