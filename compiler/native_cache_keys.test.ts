import {
  deepStrictEqual as equal,
  notDeepStrictEqual as notEqual,
} from "node:assert/strict";
import compiled from "../generated/compiler/native_session.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: Node;
};
const backend = compiled as unknown as {
  "native_cache_keys.module"(module: Node): Result<BendList<number>>;
  "native_cache_keys.operations"(
    operations: BendList<Node>,
  ): Result<BendList<number>>;
  "native_cache_keys.group_module"(
    module: Node,
    operationKey: BendList<number>,
  ): Result<BendList<number>>;
  "native_cache_keys.planning"(plan: Node): Result<BendList<number>>;
  "native_cache_keys.encode"(work: BendList<Node>): Result<BendList<number>>;
};

Deno.test("native planning keys include shared operation nominal requirements", () => {
  const planning = (shared: readonly Node[]): Node => ({
    $: "groups.Planning",
    nodes: bendList([]),
    usages: bendList([]),
    type_dependencies: bendList([]),
    shared_operation_types: bendList(shared),
  });
  const key = (shared: readonly Node[]) =>
    words(backend["native_cache_keys.planning"](planning(shared)));
  notEqual(key([]), key([id("Box")]));
  notEqual(key([id("Box")]), key([id("Wrap")]));
});
const id = (declaration: string): Node => ({
  $: "model.TypeId",
  module_name: "main",
  declaration,
});
const unit: Node = { $: "model.UnitTy" };
const u32: Node = { $: "model.U32Ty" };
const empty = { $: "model.UnitExpr" };

function words(result: Result<BendList<number>>): number[] {
  equal(result.$, "Done");
  if (result.$ !== "Done") throw new Error("native key encoding failed");
  return bendArray(result.value);
}

function moduleWith(operations: readonly Node[], body: Node = empty): Node {
  return {
    $: "model.Module",
    constants: bendList([{
      $: "model.Constant",
      name: "answer",
      exported: false,
      annotation: { $: "None" },
      value: body,
    }]),
    functions: bendList([]),
    data_types: bendList([]),
    operations: bendList(operations),
  };
}

function moduleKey(operations: readonly Node[], body: Node = empty): number[] {
  const module = moduleWith(operations, body);
  const suffix = backend["native_cache_keys.operations"](bendList(operations));
  equal(suffix.$, "Done");
  if (suffix.$ !== "Done") throw new Error("operation key encoding failed");
  const direct = words(backend["native_cache_keys.module"](module));
  equal(
    words(backend["native_cache_keys.group_module"](module, suffix.value)),
    direct,
  );
  return direct;
}

Deno.test("native module keys encode concrete, template, and instance operations exactly", () => {
  const get = id("Get");
  const concrete = {
    $: "model.Operation",
    identity: get,
    parameter: unit,
    result: u32,
  };
  const template = {
    $: "model.OperationTemplate",
    identity: get,
    parameters: 1n,
    parameter: unit,
    result: { $: "model.ParameterTy", index: 0n },
  };
  const instance = {
    $: "model.OperationInstance",
    template: get,
    arguments: bendList([u32]),
  };
  const keys = [
    moduleKey([concrete]),
    moduleKey([template]),
    moduleKey([instance]),
  ];
  notEqual(keys[0], keys[1]);
  notEqual(keys[0], keys[2]);
  notEqual(keys[1], keys[2]);
  notEqual(keys[1], moduleKey([{ ...template, parameters: 2n }]));
  notEqual(
    keys[2],
    moduleKey([{
      ...instance,
      arguments: bendList([unit]),
    }]),
  );
  notEqual(keys[2], moduleKey([instance, instance]));
});

Deno.test("native module keys include nested specialization and associated dispatch fields", () => {
  const get = id("Get");
  const specialized = {
    $: "model.SpecializeOperationExpr",
    template: get,
    arguments: bendList([u32]),
    body: { $: "model.OperationExpr", identity: get },
  };
  notEqual(
    moduleKey([], specialized),
    moduleKey([], {
      ...specialized,
      arguments: bendList([unit]),
    }),
  );
  notEqual(
    moduleKey([], specialized),
    moduleKey([], {
      ...specialized,
      body: { $: "model.OperationExpr", identity: id("Set") },
    }),
  );
  const associated = {
    $: "model.AssociatedExpr",
    identity: 3n,
    dispatch: { $: "model.MemberDispatch" },
    member: "field",
    templates: bendList([get]),
    left: empty,
    right: empty,
  };
  notEqual(
    moduleKey([], associated),
    moduleKey([], {
      ...associated,
      dispatch: { $: "model.FieldUpdateDispatch" },
    }),
  );
  notEqual(
    moduleKey([], associated),
    moduleKey([], {
      ...associated,
      templates: bendList([id("Set")]),
    }),
  );
});

Deno.test("runtime cache tags distinguish state providers from array reuse", () => {
  const empty = { $: "codegen_ir.UnitExpr" };
  const state = words(backend["native_cache_keys.encode"](bendList([{
    $: "native_cache_keys.Runtime",
    value: {
      $: "codegen_ir.StateProviderExpr",
      read: id("Read"),
      write: id("Write"),
      initial: empty,
    },
  }])));
  const reuse = words(backend["native_cache_keys.encode"](bendList([{
    $: "native_cache_keys.Runtime",
    value: {
      $: "codegen_ir.ArrayReuseExpr",
      array: empty,
      index: empty,
      value: empty,
    },
  }])));
  equal(state[0], 32);
  equal(reuse[0], 33);
});
