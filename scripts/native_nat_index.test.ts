import { match, ok, rejects, strictEqual as equal } from "node:assert/strict";
import {
  optimizeNativeNatIndex,
  optimizeNativeNatIndexProbe,
} from "./native_nat_index.ts";

const fixture = await Deno.readTextFile(
  new URL("./fixtures/native_nat_index_2_0_27.c", import.meta.url),
);
const natIndex = await Deno.readTextFile(
  new URL("../compiler/nat_index.bend", import.meta.url),
);
const transform = (c = fixture, source = natIndex, version = "bend 2.0.27") =>
  optimizeNativeNatIndex(c, { natIndex: source }, version);

Deno.test("native NatIndex replaces only find and transfers owned paths", async () => {
  const output = await transform();
  const changed = output.slice(
    output.indexOf("WL_CASE(FID_NAT_INDEX_FIND)"),
    output.indexOf("WL_CASE(FID_NAT_INDEX_FIND_C"),
  );
  match(changed, /Loc span = ctr_take\(e, index, 4, fields\);/);
  match(changed, /term_sink\(e, upper \? low : high\);/);
  match(changed, /term_sink\(e, value\);/);
  match(changed, /spare_free\(e, cls_fit\(4\), span\);/);
  match(changed, /u32 upper = mask \? \(u32\)\(\(key \/ mask\) & 1\) : 0;/);
  ok(!changed.includes("FID_CLO_APPLY"));
  ok(output.includes("WL_CASE(FID_TYPES_RESOLVE_WORK)"));
  await rejects(() => transform(output), /already patched/);
});

Deno.test("native NatIndex rejects source, version, predecessor, and ownership drift", async () => {
  await rejects(
    () => transform(fixture, natIndex, "bend 2.0.28"),
    /requires bend 2\.0\.27/,
  );
  for (
    const [before, after] of [
      ["Nat.div(Nat.div(key, mask), 2n)", "Nat.div(Nat.div(key, mask), 3n)"],
      ["case Leaf{found, value}:", "case Leaf{value, found}:"],
    ] as const
  ) {
    const changed = natIndex.replace(before, after);
    ok(changed !== natIndex);
    await rejects(() => transform(fixture, changed), /source contract changed/);
  }
  for (
    const [before, after, expected] of [
      [
        "#define NAT_IMM ((1ull << 48) - 1)",
        "#define NAT_IMM ((1ull << 49) - 1)",
        /runtime macro changed/,
      ],
      [
        "#define err_spun(H, n) ((++*(n) & 4095) == 0 && err_seen(H))",
        "#define err_spun(H, n) false",
        /runtime macro changed/,
      ],
      [
        "span_fade(e, t, src, n);",
        "term_drop(e, t);",
        /runtime helper changed: ctr_take/,
      ],
      [
        "heap_free(e, cls, loc);",
        "return;",
        /runtime helper changed: spare_free/,
      ],
      ["term_drop(e, t);", "return;", /runtime helper changed: term_sink/],
      [
        "static bool owned_plan(",
        "static bool missing_plan(",
        /requires compiler kernels and owned resolver first/,
      ],
      [
        "ctr_take(e, _index_0, 4, _fb_2)",
        "ctr_take(e, _index_0, 3, _fb_2)",
        /generated find shape changed/,
      ],
      [
        "Term _f_4 = _fb_2[1];",
        "Term _f_4 = _fb_2[2];",
        /generated find shape changed/,
      ],
      [
        "#define CID_NAT_INDEX_BRANCH 489",
        "#define CID_NAT_INDEX_BRANCH_ALT 489",
        /generated symbol changed/,
      ],
    ] as const
  ) {
    const changed = fixture.replace(before, after);
    ok(changed !== fixture, `fixture must contain ${before}`);
    await rejects(() => transform(changed), expected);
  }
});

Deno.test("standalone NatIndex probe normalizes its qualified symbols", async () => {
  const namespaced = fixture.replaceAll(
    "FID_NAT_INDEX_",
    "FID__________COMPILER_NAT_INDEX_",
  )
    .replaceAll("CID_NAT_INDEX_", "CID__________COMPILER_NAT_INDEX_");
  const output = await optimizeNativeNatIndexProbe(
    namespaced,
    { natIndex },
    "bend 2.0.27",
  );
  ok(output.includes("WL_CASE(FID_NAT_INDEX_FIND)"));
  equal((output.match(/WL_CASE\(FID_NAT_INDEX_FIND\)/g) ?? []).length, 1);
});
