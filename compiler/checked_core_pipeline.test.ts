import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";
import { createSourceFrontend } from "./source_frontend.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: Node;
};
type Maybe<T> = { readonly $: "Some"; readonly value: T } | {
  readonly $: "None";
};
const api = compiled as unknown as {
  "source_modules.source_module_core"(
    project: boolean,
    root: unknown,
    prelude: unknown,
    fuel: bigint,
  ): Result<Node>;
  "checked_core.prepared_module"(prepared: Node): Node;
  "checked_core.prepared_certificates"(prepared: Node): BendList<Node>;
  "checked_core.index_for"(module: Node, certificates: BendList<Node>): Node;
  "checked_core.lookup"(
    indexed: Node,
    job: Node,
    subset: Node,
    imports: BendList<Node>,
  ): Maybe<Node>;
  "check_scheduler.check_module_core"(
    module: Node,
    certificates: BendList<Node>,
  ): Result<Node>;
  "check_scheduler.catalog"(module: Node): Node;
  "check_scheduler.group_module"(catalog: Node, job: Node): Node;
  "groups.plan"(module: Node): Result<BendList<Node>>;
  "groups.checked_group"(checked: Node): Result<Node>;
};

Deno.test("real specialization certificates produce checked groups with the same interfaces", async () => {
  const frontend = await createSourceFrontend();
  const cases = [
    `const untouched = fn (value: U32) => @u32.add value 1
const twice = fn value => value + value
const run = fn (value: F32) => do:
  let ignored = untouched 42
  return twice value
`,
    `data Cell = Cell U32
const pick = fn values => @array.get values 0
const run = fn () => case pick [Cell 42] of
  Cell answer => answer
`,
    `data Cell = Cell U32
const read = fn witness => @state.get witness
const run = fn () => do:
  let (_, Cell answer) = @state.run (Cell 42) (fn () => read Cell)
  return answer
`,
  ];
  let totalHits = 0;
  const hitNames = new Set<string>();
  try {
    for (const source of cases) {
      const prepared = frontend.prepare(source);
      const lowered = api["source_modules.source_module_core"](
        false,
        prepared.root,
        prepared.prelude,
        prepared.nodeCount,
      );
      equal(lowered.$, "Done", source);
      if (lowered.$ !== "Done") continue;
      const module = api["checked_core.prepared_module"](lowered.value);
      const certificates = api["checked_core.prepared_certificates"](
        lowered.value,
      );
      const retained = api["check_scheduler.check_module_core"](
        module,
        certificates,
      );
      const independent = api["check_scheduler.check_module_core"](
        module,
        bendList([]),
      );
      equal(retained.$, independent.$, source);
      if (retained.$ === "Fail" || independent.$ === "Fail") {
        equal(retained, independent, source);
        continue;
      }
      const retainedGroup = api["groups.checked_group"](retained.value);
      const independentGroup = api["groups.checked_group"](independent.value);
      equal(retainedGroup.$, "Done", source);
      equal(independentGroup.$, "Done", source);
      if (retainedGroup.$ !== "Done" || independentGroup.$ !== "Done") continue;
      equal(
        retainedGroup.value.interfaces,
        independentGroup.value.interfaces,
        source,
      );

      const planned = api["groups.plan"](module);
      equal(planned.$, "Done", source);
      if (planned.$ !== "Done") continue;
      const indexed = api["checked_core.index_for"](module, certificates);
      const catalog = api["check_scheduler.catalog"](module);
      const interfaces = new Map(
        bendArray(independentGroup.value.interfaces as BendList<Node>).map((
          entry,
        ) => [entry.name as string, entry] as const),
      );
      for (const job of bendArray(planned.value)) {
        const dependencies = bendArray(job.dependencies as BendList<string>);
        const imports = dependencies.map((name) => interfaces.get(name));
        ok(imports.every((entry) => entry !== undefined), source);
        const subset = api["check_scheduler.group_module"](catalog, job);
        const hit = api["checked_core.lookup"](
          indexed,
          job,
          subset,
          bendList(imports as Node[]),
        );
        if (hit.$ === "Some") {
          totalHits++;
          for (const name of bendArray(job.members as BendList<string>)) {
            hitNames.add(name);
          }
        }
      }
    }
    ok(
      totalHits > 0,
      "the real specialized module must accept at least one certificate",
    );
    ok(
      hitNames.has("untouched"),
      "the unchanged source function must accept its SCC certificate",
    );
  } finally {
    frontend.dispose();
  }
});
