import { reachedSource } from "./fixtures.ts";
import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
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
  "source_modules.sourced_prepared"(sourced: Node): Node;
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
  "groups.plan"(module: Node): Result<BendList<Node>>;
  "groups.job_module"(module: Node, job: Node): Result<Node>;
  "groups.checked_group"(checked: Node): Result<Node>;
  "groups.check_group_planned"(
    module: Node,
    imports: BendList<Node>,
  ): Result<Node>;
  "members.function"(
    constructors: BendList<Node>,
    dispatch: Node,
    member: string,
    name: string,
    identity: bigint,
  ): Result<Node>;
  compile_source(
    root: unknown,
    prelude: unknown,
    fuel: bigint,
    steps: bigint,
  ): Result<Node>;
};

const cases = [
  {
    name: "type changing generic setter",
    source: `type Box a is data = Box { value: a }
entry const run = fn () => do:
  let box = Box { value: 40 }
  box.value := True
  return case box.value of
    True => 42
    False => 0
`,
  },
  {
    name: "nested nominal field",
    source: `type Inner a is data = Inner { value: a }
type Outer a is data = Outer { inner: Inner a }
entry const run = fn () => (Outer { inner: Inner { value: 42 } }).inner.value
`,
  },
  {
    name: "shared field across variants",
    source:
      `type Choice a is data = Low { value: a } | High { value: a, tag: U32 }
entry const run = fn () => do:
  let item = High { value: 40, tag: 1 }
  item.value := @u32.add self 2
  return item.value
`,
  },
  {
    name: "latent effect row in field payload",
    source: `effect Reader.ask: Unit -> U32
type Holder is data = Holder { callback: Unit -> U32 ! {Reader.ask} }
const read = fn holder => holder.callback
const provider = @effect.provider Reader.ask (fn () => 42)
entry const run = fn () => do provider:
  return (read (Holder { callback: fn () => Reader.ask () })) ()
`,
  },
];

Deno.test("field helpers retain principal checked groups across generic, nominal, variant and effect payloads", async () => {
  const frontend = await createSourceFrontend({ prelude: "none" });
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none", threads: 1 });
  try {
    for (const fixture of cases) {
      const input = frontend.prepare(fixture.source);
      const prepared = api["source_modules.source_module_core"](
        false,
        input.root,
        input.prelude,
        input.nodeCount,
      );
      equal(prepared.$, "Done", fixture.name);
      if (prepared.$ !== "Done") continue;
      const module = api["checked_core.prepared_module"](
        api["source_modules.sourced_prepared"](prepared.value),
      );
      const certificates = api["checked_core.prepared_certificates"](
        api["source_modules.sourced_prepared"](prepared.value),
      );
      const helperNames = bendArray(module.functions as BendList<Node>)
        .map((fn) => fn.name as string)
        .filter((name) => name.startsWith("$member["));
      ok(helperNames.length > 0, fixture.name);
      const certifiedNames = new Set(
        bendArray(certificates).flatMap((certificate) =>
          bendArray((certificate.module as Node).functions as BendList<Node>)
            .map((fn) => fn.name as string)
        ),
      );
      for (const name of helperNames) {
        ok(
          certifiedNames.has(name),
          `${fixture.name}: ${name} lacks a certificate`,
        );
      }

      const retained = api["check_scheduler.check_module_core"](
        module,
        certificates,
      );
      const independent = api["check_scheduler.check_module_core"](
        module,
        bendList([]),
      );
      equal(retained.$, "Done", fixture.name);
      equal(independent.$, "Done", fixture.name);
      if (retained.$ !== "Done" || independent.$ !== "Done") continue;
      const retainedGroup = api["groups.checked_group"](retained.value);
      const independentGroup = api["groups.checked_group"](independent.value);
      equal(retainedGroup.$, "Done", fixture.name);
      equal(independentGroup.$, "Done", fixture.name);
      if (retainedGroup.$ === "Done" && independentGroup.$ === "Done") {
        equal(
          retainedGroup.value.interfaces,
          independentGroup.value.interfaces,
          fixture.name,
        );
      }

      const plan = api["groups.plan"](module);
      equal(plan.$, "Done", fixture.name);
      if (plan.$ !== "Done") continue;
      const jobs: Node[] = bendArray(plan.value);
      const indexed = api["checked_core.index_for"](module, certificates);
      for (const name of helperNames) {
        const job: Node | undefined = jobs.find((candidate) =>
          bendArray(candidate.members as BendList<string>).includes(name)
        );
        ok(job, `${fixture.name}: ${name} lacks a final job`);
        equal(bendArray(job.members as BendList<string>), [name]);
        equal(bendArray(job.dependencies as BendList<string>), []);
        const subset = api["groups.job_module"](module, job);
        equal(subset.$, "Done", fixture.name);
        if (subset.$ !== "Done") continue;
        equal(
          api["checked_core.lookup"](indexed, job, subset.value, bendList([]))
            .$,
          "Some",
          `${fixture.name}: ${name} must use its certificate`,
        );
      }

      const artifact = api.compile_source(
        input.root,
        input.prelude,
        input.nodeCount,
        100_000n,
      );
      equal(artifact.$, "Done", fixture.name);
      if (artifact.$ !== "Done") continue;
      const bytes = Uint8Array.from(
        bendArray(artifact.value.bytes as BendList<number>),
      );
      const { instance } = await WebAssembly.instantiate(bytes);
      const run = instance.exports.run;
      ok(typeof run === "function", fixture.name);
      equal(run(), 42, fixture.name);
      equal(
        await native.compile(fixture.source),
        reference.compile(fixture.source),
        `${fixture.name}: native artifact differs from JavaScript`,
      );
    }
  } finally {
    frontend.dispose();
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("minimal field evidence preserves provider types and latent operation rows", () => {
  const id = (declaration: string): Node => ({
    $: "TypeId",
    module_name: "probe",
    declaration,
  });
  const operation = id("Reader.ask");
  const owner: Node = {
    $: "DataType",
    identity: id("Holder"),
    parameters: 0n,
    constructors: bendList([{
      $: "Constructor",
      name: "Holder",
      payload: {
        $: "Some",
        value: {
          $: "ProviderTy",
          identity: operation,
          effects: {
            $: "EffectRow",
            operations: bendList([operation]),
            tail: { $: "ClosedRow" },
          },
        },
      },
      fields: bendList(["provider"]),
    }]),
  };
  const functionResult = api["members.function"](
    owner.constructors as BendList<Node>,
    { $: "MemberDispatch" },
    "provider",
    "$member[1]",
    1n,
  );
  equal(functionResult.$, "Done");
  if (functionResult.$ !== "Done") return;
  const makeModule = (operations: readonly Node[]): Node => ({
    $: "Module",
    constants: bendList([]),
    functions: bendList([functionResult.value]),
    data_types: bendList([owner]),
    operations: bendList(operations),
  });
  const minimal = makeModule([]);
  const final = makeModule([{
    $: "Operation",
    identity: operation,
    parameter: { $: "UnitTy" },
    result: { $: "U32Ty" },
  }]);
  const independent = api["groups.check_group_planned"](
    minimal,
    bendList([]),
  );
  const ordinary = api["groups.check_group_planned"](
    final,
    bendList([]),
  );
  equal(independent.$, "Done");
  equal(ordinary.$, "Done");
  if (independent.$ !== "Done" || ordinary.$ !== "Done") return;
  equal(independent.value.interfaces, ordinary.value.interfaces);
  const certificate = {
    $: "Certificate",
    module: minimal,
    checked: independent.value,
    imports: bendList([]),
  };
  const plan = api["groups.plan"](final);
  equal(plan.$, "Done");
  if (plan.$ !== "Done") return;
  const job = bendArray(plan.value)[0];
  const subset = api["groups.job_module"](final, job);
  equal(subset.$, "Done");
  if (subset.$ !== "Done") return;
  equal(
    api["checked_core.lookup"](
      api["checked_core.index_for"](final, bendList([certificate])),
      job,
      subset.value,
      bendList([]),
    ).$,
    "Some",
  );
});

Deno.test("field helper capture preserves ambiguity and incompatible variant diagnostics", async () => {
  const frontend = await createSourceFrontend({ prelude: "none" });
  try {
    for (
      const [source, expected] of [
        [
          `type Box is data = Box { value: U32 }
const Box.value = fn box => 0
const run = fn () => (Box { value: 1 }).value
`,
          {
            $: "Diagnostic",
            code: "ambiguous_member",
            subject: "offset:109",
            message: "field and associated function share the name value",
          },
        ],
        [
          `type Choice is data = Left { value: U32 } | Right { value: Bool }
const run = fn item => item.value
const test = run (Left { value: 42 })
`,
          {
            $: "Diagnostic",
            code: "type_mismatch",
            // The retaining entry also references `run`, adding one instance.
            subject: "$member[3]",
            message: "cannot unify U32 with Bool",
          },
        ],
      ] as const
    ) {
      const input = frontend.prepare(reachedSource(source));
      const result = api.compile_source(
        input.root,
        input.prelude,
        input.nodeCount,
        100_000n,
      );
      equal(result, { $: "Fail", error: expected });
    }
  } finally {
    frontend.dispose();
  }
});
