import assert from "node:assert/strict";
import candidate from "../generated/compiler/compiler.js";
import { bendArray, bendList } from "./bend_list.ts";
import { createSourceFrontend } from "./source_frontend.ts";
import { createSourceProjectLoader } from "./source_project.ts";

type Node = { $: string; [key: string]: any };
const api = candidate as any;
const source = `type End is data = End
type Entry { head, tail } is data = Entry { head, tail }
const End.contains = fn (end: End) => fn witness => False
const Entry.contains = fn entry => fn witness => do:
  let Entry { head, tail } = entry
  if Type head == Type witness:
    return True
  return tail.contains(witness)
const run = fn () => Entry { head: True, tail: End }.contains(True)
`;
const row = {
  $: "EffectRow",
  operations: bendList([]),
  tail: { $: "ClosedRow" },
};
const applied = (identity: Node, args: Node[]): Node => ({
  $: "AppliedTy",
  identity,
  arguments: bendList(args),
});
const result = (witness: Node): Node => ({
  $: "FunctionTy",
  parameter: witness,
  result: { $: "BoolTy" },
  effects: row,
});
const bool: Node = { $: "BoolTy" }, u32: Node = { $: "U32Ty" };

function checkedSource(input: string) {
  return async () => {
    const frontend = await createSourceFrontend();
    try {
      const prepared = frontend.prepare(input);
      const lowered = api["lower.source_module"](
        prepared.root,
        prepared.prelude,
        prepared.nodeCount,
      );
      assert.equal(lowered.$, "Done", Deno.inspect(lowered.error));
      const initial = api["check_scheduler.check_module_evidenced"](
        lowered.value,
      );
      assert.equal(initial.$, "Done", Deno.inspect(initial.error));
      const checked = api["check_scheduler.initial_checked"](initial.value);
      return { module: lowered.value, checked };
    } finally {
      frontend.dispose();
    }
  };
}

Deno.test("independently checked linked schema reduces concrete chains only", async () => {
  const { module, checked } = await checkedSource(source)();
  const proofs = api["schema_stage.capture"](
    module.functions,
    module.data_types,
    checked,
    "main",
  );
  assert.equal(proofs.$, "Con");
  assert.equal(proofs.tail.$, "Nil");
  const proof = proofs.head;
  const end = applied(proof.terminal_identity, []);
  const entry = (head: Node, tail: Node) =>
    applied(proof.node_identity, [head, tail]);
  const chain = entry(bool, entry(u32, end));
  const decide = (left: Node, witness: Node) =>
    api["schema_stage.decide"](
      proofs,
      proof.node_method.name,
      proof.member,
      left,
      result(witness),
      module.functions,
      module.data_types,
    );
  assert.deepEqual(decide(chain, bool), { $: "Some", value: true });
  assert.deepEqual(decide(chain, u32), { $: "Some", value: true });
  assert.deepEqual(decide(chain, { $: "F32Ty" }), { $: "Some", value: false });
  assert.equal(
    decide(
      entry(
        bool,
        applied({ ...proof.terminal_identity, declaration: "Other" }, []),
      ),
      bool,
    ).$,
    "None",
    "early match still validates the tail",
  );
  assert.equal(
    decide(entry(bool, entry({ $: "VariableTy", index: 987n }, end)), bool).$,
    "None",
    "later open head falls back",
  );
  assert.equal(
    decide(entry(bool, { $: "VariableTy", index: 988n }), bool).$,
    "None",
    "open tail falls back",
  );
  const functions = bendArray(module.functions) as Node[];
  for (
    const target of [
      proof.node_method.name,
      proof.equality.name,
      proof.type_equality.name,
    ]
  ) {
    const changed = functions.map((fn) =>
      fn.name === target ? { ...fn, body: { $: "BoolExpr", value: false } } : fn
    );
    assert.equal(
      api["schema_stage.decide"](
        proofs,
        proof.node_method.name,
        proof.member,
        chain,
        result(bool),
        bendList(changed),
        module.data_types,
      ).$,
      "None",
      target,
    );
  }
  const types = (bendArray(module.data_types) as Node[]).map((ty) =>
    ty.identity.declaration === "End" && ty.identity.module_name === "main"
      ? { ...ty, parameters: 1n }
      : ty
  );
  assert.equal(
    api["schema_stage.decide"](
      proofs,
      proof.node_method.name,
      proof.member,
      chain,
      result(bool),
      module.functions,
      bendList(types),
    ).$,
    "None",
    "nominal catalog revision",
  );
});

Deno.test("changed checked source does not establish schema evidence", async () => {
  const changed = source.replace("fn witness => False", "fn witness => True");
  assert.notEqual(changed, source);
  const { module, checked } = await checkedSource(changed)();
  assert.equal(
    api["schema_stage.capture"](
      module.functions,
      module.data_types,
      checked,
      "main",
    ).$,
    "Nil",
  );
});

Deno.test("shadowed schema binder and colliding constructor fields reject capture", async () => {
  const { module, checked } = await checkedSource(source)();
  const original = bendArray(module.data_types) as Node[];
  for (const declaration of ["Entry", "End"]) {
    const changed = original.map((ty) => {
      if (
        ty.identity.module_name !== "main" ||
        ty.identity.declaration !== declaration
      ) return ty;
      const copy = structuredClone(ty);
      const constructor = copy.constructors.head;
      constructor.fields = bendList([
        ...bendArray(constructor.fields),
        "contains",
      ]);
      return copy;
    });
    const catalog = bendList(changed);
    const checkedCatalog = { ...checked, data_types: catalog };
    assert.equal(
      api["schema_stage.capture"](
        module.functions,
        catalog,
        checkedCatalog,
        "main",
      ).$,
      "Nil",
      declaration,
    );
  }
  const shadowed = source.replace(
    "let Entry { head, tail } = entry",
    "let Entry { head: witness, tail } = entry",
  ).replace(
    "if Type head == Type witness:",
    "if Type witness == Type witness:",
  );
  assert.notEqual(shadowed, source);
  const lowered = await checkedSource(shadowed)();
  assert.equal(
    api["schema_stage.capture"](
      lowered.module.functions,
      lowered.module.data_types,
      lowered.checked,
      "main",
    ).$,
    "Nil",
  );
});

Deno.test("optional helper guards Nat48 counters, fresh IDs, and generated names", () => {
  const max = (1n << 48n) - 1n;
  assert.equal(api["monomorph.schema_space"](max, 2n, 1n), false);
  assert.equal(api["monomorph.schema_space"](max, 1n, 1n), false);
  assert.equal(api["monomorph.schema_space"](max - 1n, 1n, 1n), true);
  assert.equal(api["monomorph.schema_space"](1n, 0n, 1n), false);
  const environment = (next: bigint) => ({
    $: "Environment",
    bindings: bendList([]),
    definitions: bendList([]),
    state: {
      $: "State",
      substitutions: api["types.empty"](),
      next,
      annotations: { $: "MTip" },
    },
  });
  assert.equal(api["monomorph.schema_fresh_space"](environment(max)), false);
  assert.equal(
    api["monomorph.schema_fresh_space"](environment(max - 65536n)),
    true,
  );
  assert.equal(
    api["monomorph.schema_name_free"]({
      $: "Done",
      value: {
        $: "Function",
        name: "$schema[1].contains",
        exported: false,
        parameter: "x",
        parameter_type: { $: "None" },
        result_type: { $: "None" },
        body: { $: "UnitExpr" },
      },
    }),
    false,
  );
  assert.equal(
    api["monomorph.schema_name_free"]({
      $: "Fail",
      error: {
        $: "Diagnostic",
        code: "unknown_function",
        subject: "x",
        message: "missing",
      },
    }),
    true,
  );
});

Deno.test("source evidence follows a different project module identity", async () => {
  const loader = await createSourceProjectLoader({
    readSource: async () => source,
  });
  const frontend = await createSourceFrontend();
  try {
    const project = await loader.load("/virtual/staged-schema/custom.blot");
    const prepared = frontend.prepare(project);
    const lowered = api["source_modules.prepared_project"](
      api["lower.prepare_prelude"](prepared.prelude, prepared.nodeCount),
      prepared.root,
      prepared.nodeCount,
    );
    assert.equal(lowered.$, "Done", Deno.inspect(lowered.error));
    const initial = api["check_scheduler.check_module_evidenced"](
      lowered.value,
    );
    assert.equal(initial.$, "Done", Deno.inspect(initial.error));
    const checked = api["check_scheduler.initial_checked"](initial.value);
    const proofs = api["schema_stage.capture"](
      lowered.value.functions,
      lowered.value.data_types,
      checked,
      project.entry,
    );
    assert.equal(proofs.$, "Con");
    assert.equal(proofs.head.node_identity.module_name, project.entry);
  } finally {
    frontend.dispose();
    loader.dispose();
  }
});
