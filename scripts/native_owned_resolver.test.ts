import { match, ok, rejects } from "node:assert/strict";
import { optimizeNativeOwnedResolver } from "./native_owned_resolver.ts";

const fixture = await Deno.readTextFile(
  new URL("./fixtures/native_owned_resolver_2_0_27.c", import.meta.url),
);
const bend28Fixture = await Deno.readTextFile(
  new URL(
    "./fixtures/native_owned_resolver_2_0_28_after_closed.c",
    import.meta.url,
  ),
);
const sources = {
  types: await Deno.readTextFile(
    new URL("../compiler/types.bend", import.meta.url),
  ),
  natIndex: await Deno.readTextFile(
    new URL("../compiler/nat_index.bend", import.meta.url),
  ),
  model: await Deno.readTextFile(
    new URL("../compiler/model.bend", import.meta.url),
  ),
};
const transform = (c = fixture, input = sources, version = "bend 2.0.27") =>
  optimizeNativeOwnedResolver(c, input, version);

Deno.test("owned resolver accepts reviewed Bend 2.0.28 Version construction", async () => {
  const output = await transform(bend28Fixture, sources, "bend 2.0.28");
  match(output, /OwnedTypePlan owned_plan_scratch/);
  const altered = bend28Fixture.replace(
    "_substitutions_0 = term_keep(e, _substitutions_0);",
    "_substitutions_0 = _substitutions_0;",
  );
  ok(altered !== bend28Fixture);
  await rejects(
    () => transform(altered, sources, "bend 2.0.28"),
    /generated field shape changed: FID_TYPES_RESOLVE_WORK/,
  );
});

function prekeepResolveCase(generated: string): string {
  const early = "    Term _v_0 = 0;\n    Term _v_1 = 0;";
  const kept = "    _substitutions_0 = term_keep(e, _substitutions_0);\n" +
    "    _substitutions_1 = term_keep(e, _substitutions_1);\n" +
    "    _substitutions_2 = term_keep(e, _substitutions_2);\n";
  ok(generated.includes(early));
  return generated.replace(
    early,
    "    Term _v_0 = 0;\n" + kept + "    Term _v_1 = 0;",
  );
}

Deno.test("owned resolver inserts after closed path and transfers only certified owned results", async () => {
  const output = await transform();
  match(
    output,
    /compact_closed_work\(e, _work_0, _work_1, _fuel_0\)[\s\S]*?WL_RETN\(4\);\n    }\n\n    OwnedTypePlan owned_plan_scratch/,
  );
  match(
    output,
    /if \(_work_0 == 0 && owned_plan\(e, _work_1, _substitutions_1, _substitutions_3,/,
  );
  match(output, /if \(owned_changed\) term_sink\(e, _work_1\);/);
  match(
    output,
    /term_sink\(e, _substitutions_0\);\n      term_sink\(e, _substitutions_1\);\n      term_sink\(e, _substitutions_2\);/,
  );
  match(output, /return term_triv\(value\) \|\| term_rfc\(value\);/);
  ok(output.includes("WL_CASE(FID_TYPES_RESOLVE_WORK_K_TEST)"));
  await rejects(() => transform(output), /already patched/);
});

Deno.test("owned resolver accepts exact pre-spin keeps and rejects an altered owned field", async () => {
  const prekept = prekeepResolveCase(fixture);
  const output = await transform(prekept);
  match(output, /OwnedTypePlan owned_plan_scratch/);
  const keep = "    _substitutions_1 = term_keep(e, _substitutions_1);";
  const marker = "#if !DEVICE\n  WL_CASE(FID_TYPES_RESOLVE_WORK)\n";
  const at = prekept.indexOf(marker);
  ok(at >= 0);
  const altered = prekept.slice(0, at) + prekept.slice(at).replace(
    keep,
    "    _substitutions_1 = _substitutions_1;",
  );
  ok(altered !== prekept);
  await rejects(
    () => transform(altered),
    /generated field shape changed: FID_TYPES_RESOLVE_WORK/,
  );
});

Deno.test("owned resolver rejects semantic and runtime-domain changes", async () => {
  await rejects(
    () => transform(fixture, sources, "bend 2.0.29"),
    /requires bend 2\.0\.27 or 2\.0\.28/,
  );
  for (
    const [part, before, after] of [
      [
        "types",
        "Version{count, replacement} <> versions",
        "Version{1n+count, replacement} <> versions",
      ],
      ["types", "Nat.is_ge(position, cursor)", "Nat.is_gt(position, cursor)"],
      ["types", "flat_step(1048576n", "flat_step(1048575n"],
      [
        "natIndex",
        "Nat.div(Nat.div(key, mask), 2n)",
        "Nat.div(Nat.div(key, mask), 3n)",
      ],
      [
        "model",
        "  FunctionTy{parameter: Ty, result: Ty, effects: EffectRow}",
        "  FunctionTy{result: Ty, parameter: Ty, effects: EffectRow}",
      ],
    ] as const
  ) {
    const changed = {
      ...sources,
      [part]: sources[part].replace(before, after),
    };
    ok(changed[part] !== sources[part]);
    await rejects(() => transform(fixture, changed), /source contract changed/);
  }
  for (
    const [before, after, expected] of [
      [
        "#define NAT_IMM ((1ull << 48) - 1)",
        "#define NAT_IMM ((1ull << 49) - 1)",
        /runtime macro changed/,
      ],
      ["return NAT_IMM;", "return n;", /runtime helper changed: nat_chk/],
      [
        "return (t & RFC_BIT) != 0;",
        "return false;",
        /runtime helper changed: term_rfc/,
      ],
      [
        "return rfc_wrap(e, t, 2);",
        "return t;",
        /runtime helper changed: term_keep/,
      ],
    ] as const
  ) {
    const changed = fixture.replace(before, after);
    ok(changed !== fixture);
    await rejects(() => transform(changed), expected);
  }
});

Deno.test("owned resolver rejects NatIndex, Version, split-argument and predecessor layout drift", async () => {
  for (
    const [before, after, expected] of [
      [
        "ctr_take(e, _index_0, 4,",
        "ctr_take(e, _index_0, 3,",
        /generated field shape changed: FID_NAT_INDEX_FIND/,
      ],
      [
        "e.mem[_nd_0 + 0] = rfc_seal(e, _substitutions_7);",
        "e.mem[_nd_0 + 0] = rfc_seal(e, _substitution_5);",
        /Version\/Substitutions construction shape changed/,
      ],
      [
        "term_ctr(CID_TYPES_VERSION, _nd_0)",
        "term_ctr(CID_TYPES_SUBSTITUTIONS, _nd_0)",
        /Version\/Substitutions construction shape changed/,
      ],
      [
        "Term _fuel_0 = r4;",
        "Term _fuel_0 = r3;",
        /generated field shape changed: FID_TYPES_RESOLVE_WORK/,
      ],
      [
        "compact_closed_work(e, _work_0",
        "missing_closed_work(e, _work_0",
        /generated field shape changed: FID_TYPES_RESOLVE_WORK/,
      ],
      [
        "if (err_seen(e.mem)) return 0;",
        "if (0) return 0;",
        /generated field shape changed: FID_TYPES_RESOLVE_WORK/,
      ],
    ] as const
  ) {
    const changed = fixture.replace(before, after);
    ok(changed !== fixture, `fixture must include ${before}`);
    await rejects(() => transform(changed), expected);
  }
});
