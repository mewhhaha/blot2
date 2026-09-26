import { match, ok, rejects, strictEqual as equal } from "node:assert/strict";
import { optimizeNativeBorrowedStrings } from "./native_borrowed_strings.ts";

const fixture = await Deno.readTextFile(
  new URL("./fixtures/native_borrowed_strings_2_0_27.c", import.meta.url),
);
const bend28Fixture = await Deno.readTextFile(
  new URL("./fixtures/native_borrowed_strings_2_0_28.c", import.meta.url),
);
const baseSource = await Deno.readTextFile(
  new URL("../generated/compiler/bend-2.0.27/base.bend", import.meta.url),
);
const base = { map: baseSource, string: baseSource, char: baseSource };
const bend28Base = {
  map: await Deno.readTextFile(
    new URL("./fixtures/native_borrowed_base_map_2_0_28.bend", import.meta.url),
  ),
  string: await Deno.readTextFile(
    new URL(
      "./fixtures/native_borrowed_base_string_2_0_28.bend",
      import.meta.url,
    ),
  ),
  char: await Deno.readTextFile(
    new URL(
      "./fixtures/native_borrowed_base_char_2_0_28.bend",
      import.meta.url,
    ),
  ),
};
const transform = (source = fixture, sources = base, version = "bend 2.0.27") =>
  optimizeNativeBorrowedStrings(source, sources, version);

Deno.test("borrowed String accepts reviewed Bend 2.0.28 cases and Base sections", async () => {
  const output = await transform(bend28Fixture, bend28Base, "bend 2.0.28");
  match(output, /Term key = r0;[\s\S]*character_index = r1 \/ 33ull/);
  match(output, /Term root_a = r0, root_b = r1;/);
  ok(output.includes("WL_CASE(FID_MAP_BIT_GO_K9775)"));
  ok(output.includes("WL_CASE(FID_STRING_CMP_K10892)"));
  equal((output.match(/WL_CASE\(FID_MAP_BIT\)/g) ?? []).length, 1);
  equal((output.match(/WL_CASE\(FID_STRING_CMP\)/g) ?? []).length, 1);
  await rejects(
    () => transform(output, bend28Base, "bend 2.0.28"),
    /generated case changed/,
  );

  const changedGo = bend28Fixture.replace(
    "ctr_take(e, _key_0, 2, _fb_0)",
    "ctr_take(e, _key_0, 1, _fb_0)",
  );
  ok(changedGo !== bend28Fixture);
  await rejects(
    () => transform(changedGo, bend28Base, "bend 2.0.28"),
    /generated case changed: Map\.bit\.go/,
  );
  const changedBase = bend28Base.map.replace(
    "Nat.divmod(pos, 33n)",
    "Nat.divmod(pos, 34n)",
  );
  ok(changedBase !== bend28Base.map);
  await rejects(
    () =>
      transform(
        bend28Fixture,
        { ...bend28Base, map: changedBase },
        "bend 2.0.28",
      ),
    /Base semantics changed: Map\.bit/,
  );
});

Deno.test("borrowed String replaces only Map.bit and String.cmp host entries", async () => {
  const output = await transform();
  match(output, /Term key = r0;[\s\S]*character_index = r1 \/ 33ull/);
  match(output, /Term root_a = r0, root_b = r1;/);
  match(output, /if \(err_spun\(e\.mem, &cmp_poll\)\) return 0;/);
  match(output, /if \(err_spun\(e\.mem, &wpoll\)\) return 0;/);
  ok(output.includes("WL_CASE(FID_MAP_BIT_GO)"));
  ok(output.includes("WL_CASE(FID_STRING_CMP_K7685)"));
  equal((output.match(/WL_CASE\(FID_MAP_BIT\)/g) ?? []).length, 1);
  equal((output.match(/WL_CASE\(FID_STRING_CMP\)/g) ?? []).length, 1);
  await rejects(() => transform(output), /generated case changed/);
});

Deno.test("borrowed String accepts only alpha-renamed generated locals and IDs", async () => {
  const shifted = fixture.replaceAll("_key_0", "_key_42")
    .replaceAll("FID_MAP_BIT_GO_K5788", "FID_MAP_BIT_GO_K9999")
    .replaceAll("spin_686", "spin_999");
  await transform(shifted);
  const splitContinuation = fixture.replace(
    "STK(1) = FID_MAP_BIT_GO_K5788;",
    "STK(1) = FID_MAP_BIT_GO_K9999;",
  );
  ok(splitContinuation !== fixture);
  await rejects(() => transform(splitContinuation), /generated case changed/);
  const goStart = fixture.indexOf("WL_CASE(FID_MAP_BIT_GO)\n");
  const goEnd = fixture.indexOf("\n#endif", goStart);
  ok(goStart >= 0 && goEnd > goStart);
  const changedGo = fixture.slice(goStart, goEnd).replaceAll(
    "FID_MAP_BIT_GO_K5788",
    "FID_MAP_BIT_GO_K9999",
  );
  ok(changedGo !== fixture.slice(goStart, goEnd));
  await rejects(
    () =>
      transform(fixture.slice(0, goStart) + changedGo + fixture.slice(goEnd)),
    /generated case changed: Map.bit.go continuation/,
  );
});

Deno.test("borrowed String fails closed on Base, runtime, and generated drift", async () => {
  await rejects(
    () => transform(fixture, base, "bend 2.0.29"),
    /requires bend 2\.0\.27 or bend 2\.0\.28/,
  );
  for (
    const [key, before, after] of [
      ["map", "Nat.divmod(pos, 33n)", "Nat.divmod(pos, 34n)"],
      ["string", "case SNil{} SCon{h, t}:", "case SNil{} SNil{}:"],
      ["char", "U32.cmp(x, y)", "U32.cmp(y, x)"],
    ] as const
  ) {
    const changed = base[key].replace(before, after);
    ok(changed !== base[key]);
    await rejects(
      () => transform(fixture, { ...base, [key]: changed }),
      /Base semantics changed/,
    );
  }
  for (
    const [before, after, reason] of [
      [
        "#define NAT_IMM ((1ull << 48) - 1)",
        "#define NAT_IMM ((1ull << 49) - 1)",
        /runtime contract/,
      ],
      [
        "#define RFC_CNT  ((1u << 24) - 1)",
        "#define RFC_CNT  ((1u << 25) - 1)",
        /runtime contract/,
      ],
      [
        "#define a32_load_acq(p)     __atomic_load_n(p, __ATOMIC_ACQUIRE)",
        "#define a32_load_acq(p)     __atomic_load_n(p, __ATOMIC_RELAXED)",
        /runtime contract/,
      ],
      [
        "return rfc_view(e, term_loc(t)) >> 24;",
        "return rfc_view(e, term_loc(t)) >> 25;",
        /runtime helper changed: term_peek/,
      ],
      [
        "#define err_spun(H, n) ((++*(n) & 4095) == 0 && err_seen(H))",
        "#define err_spun(H, n) false",
        /runtime contract/,
      ],
      [
        "Term _a_0 = 33ull;",
        "Term _a_0 = 34ull;",
        /generated case changed: Map.bit/,
      ],
      [
        "ctr_take(e, _key_0, 2, _fb_0)",
        "ctr_take(e, _key_0, 1, _fb_0)",
        /generated case changed: Map.bit.go/,
      ],
      [
        "Term _a_0 = 31ull;",
        "Term _a_0 = 30ull;",
        /generated U32\/Char helper changed/,
      ],
      ["r2 = 2;", "r2 = 1;", /generated case changed: String.cmp/],
    ] as const
  ) {
    const changed = fixture.replace(before, after);
    ok(changed !== fixture, `fixture must contain ${before}`);
    await rejects(() => transform(changed), reason);
  }
});
