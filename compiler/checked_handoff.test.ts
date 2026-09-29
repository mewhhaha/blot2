import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { toBendCst } from "./bend_abi.ts";
import { bendArray, type BendList, bendList } from "./bend_list.ts";
import { createSourceFrontend } from "./source_frontend.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: Node;
};
const api = compiled as unknown as Record<
  string,
  (...args: unknown[]) => unknown
>;
const call = (name: string, ...args: unknown[]) => api[name](...args);
function done(name: string, ...args: unknown[]): Node {
  const result = call(name, ...args) as Result<Node>;
  ok(result.$ === "Done", `${name}: ${Deno.inspect(result)}`);
  return result.value;
}
const nil = bendList([]);

async function preparedSource(
  source: string,
  prelude: "none" | "default" = "none",
) {
  const frontend = await createSourceFrontend({ prelude });
  try {
    const parsed = frontend.prepare(source);
    const sourced = done(
      "source_modules.source_module_core",
      false,
      toBendCst(parsed.root),
      toBendCst(parsed.prelude),
      parsed.nodeCount,
    );
    return call("source_modules.sourced_prepared", sourced) as Node;
  } finally {
    frontend.dispose();
  }
}

Deno.test("checked handoff carries real source results without rebuilding their final plan", async () => {
  const sources = [
    "entry const run = fn (x: U32) => @u32.add x 1",
    "const id = fn x => x\nentry const run = fn (x: U32) => id x",
    "data Cell = #Cell U32\nentry const run = fn (x: U32) => case #Cell x of\n  #Cell y => y",
    "entry const run = fn (x: U32) => @array.get (@array.fill 4 x) 2",
    "const a = fn (x: U32) => @u32.add x 1\nconst b = fn (x: U32) => a x\nentry const run = fn (x: U32) => b x",
  ];
  let carried = 0;
  for (const source of sources) {
    const prepared = await preparedSource(source);
    const module = call("checked_core.prepared_module", prepared);
    const certificates = call("checked_core.prepared_certificates", prepared);
    const retained = call("check_scheduler.check_prepared", prepared);
    const previous = call(
      "check_scheduler.check_module_core",
      module,
      certificates,
    );
    equal(retained, previous, source);
    if (call("checked_core.prepared_is_checked", prepared)) carried++;
  }
  ok(
    carried >= 3,
    `the handoff must execute, not silently use fallback (${carried})`,
  );
});

Deno.test("checked handoff rejects stale bodies, locations and nominal/operation catalogs", async () => {
  const prepared = await preparedSource(
    "entry const run = fn (x: U32) => @u32.add x 1",
  );
  ok(call("checked_core.prepared_is_checked", prepared));
  const original = call("checked_core.prepared_module", prepared) as Node;
  const certificates = call("checked_core.prepared_certificates", prepared);
  const checked = done("check_scheduler.check_prepared", prepared);
  const functions = bendArray(original.functions as BendList<Node>);
  for (
    const changed of [
      {
        ...original,
        functions: bendList(
          functions.map((fn) => ({
            ...fn,
            body: { $: "model.U32Expr", value: 99 },
          })),
        ),
      },
      {
        ...original,
        functions: bendList(
          functions.map((fn) => ({ ...fn, exported: !fn.exported })),
        ),
      },
      {
        ...original,
        functions: bendList(
          functions.map((fn) => ({
            ...fn,
            body: {
              $: "model.SourceExpr",
              offset: 987n,
              annotation: { $: "None" },
              value: fn.body,
            },
          })),
        ),
      },
      {
        ...original,
        data_types: bendList([{
          $: "model.DataType",
          identity: {
            $: "model.TypeId",
            module_name: "other",
            declaration: "Cell",
          },
          parameters: 0n,
          constructors: nil,
        }]),
      },
      {
        ...original,
        operations: bendList([{
          $: "model.Operation",
          identity: {
            $: "model.TypeId",
            module_name: "other",
            declaration: "read",
          },
          parameter: { $: "model.UnitTy" },
          result: { $: "model.U32Ty" },
        }]),
      },
    ]
  ) {
    const handoff = call(
      "checked_core.retain_unchanged",
      changed,
      checked,
      certificates,
    );
    equal(call("checked_core.prepared_is_checked", handoff), false);
  }
});

Deno.test("checked handoff rejects unresolved use and interface requirements", async () => {
  const prepared = await preparedSource(
    "entry const run = fn (x: U32) => @u32.add x 1",
  );
  const module = call("checked_core.prepared_module", prepared);
  const checked = done("check_scheduler.check_prepared", prepared);
  const predicate = {
    $: "model.TypeRepPredicate",
    represented: { $: "model.VariableTy", index: 0n },
  };
  for (
    const [interfaces, uses] of [
      [
        nil,
        bendList([{
          $: "constraints.UsePlan",
          site: 1n,
          subject: "run",
          ty: { $: "model.U32Ty" },
          predicates: bendList([predicate]),
        }]),
      ],
      [
        bendList([{
          $: "groups.Interface",
          name: "run",
          kind: { $: "groups.FunctionInterface" },
          template: { $: "model.U32Ty" },
          parameters: 1n,
          effects: nil,
          predicates: bendList([predicate]),
        }]),
        nil,
      ],
    ]
  ) {
    const certificates = bendList([{
      $: "checked_core.Certificate",
      module,
      checked: { $: "groups.CheckedGroup", checked, interfaces, uses },
      imports: nil,
    }]);
    const handoff = call(
      "checked_core.retain_unchanged",
      module,
      checked,
      certificates,
    );
    equal(call("checked_core.prepared_is_checked", handoff), false);
  }
});

Deno.test("checked handoff and ordinary finalization agree for dispatch, closures, effects and demand", async () => {
  for (
    const source of [
      "const twice = fn x => x + x\nentry const run = fn (x: U32) => twice x",
      "data Cell = #Cell U32\nconst get = fn x => @array.get x 0\nentry const run = fn () => case get [#Cell 42] of\n  #Cell x => x",
      "data Cell = #Cell U32\nconst read = fn witness => @state.get witness\nentry const run = fn () => do:\n  let (_, #Cell value) = @state.run (#Cell 42) (fn () => read #Cell)\n  return value",
      "const make = fn (x: U32) => fn (y: U32) => @u32.add x y\nentry const run = fn (x: U32) => (make x) 2",
    ]
  ) {
    const prepared = await preparedSource(source, "default");
    const module = call("checked_core.prepared_module", prepared);
    const certificates = call("checked_core.prepared_certificates", prepared);
    equal(
      call("check_scheduler.check_prepared", prepared),
      call("check_scheduler.check_module_core", module, certificates),
      source,
    );
  }
});
