import { equal, ok, throws } from "node:assert/strict";
import { optimizeNativeStringComparison } from "./native_string_compare.ts";

const fixture = await Deno.readTextFile(
  new URL("./fixtures/native_string_compare_2_0_24.c", import.meta.url),
);
const model = await Deno.readTextFile(
  new URL("../compiler/model.bend", import.meta.url),
);
const version = "bend 2.0.24";
const currentFixture = await Deno.readTextFile(
  new URL("./fixtures/native_string_compare_2_0_27.c", import.meta.url),
);
const bend28Fixture = await Deno.readTextFile(
  new URL("./fixtures/native_string_compare_2_0_28.c", import.meta.url),
);

Deno.test("native String specialization accepts reviewed Bend 2.0.28 ownership", () => {
  const { source, wrapper, helper } = optimizeNativeStringComparison(
    bend28Fixture,
    model,
    "bend 2.0.28",
  );
  equal(wrapper, "spin_13");
  equal(helper, "spin_14");
  ok(source.includes("term_sink(e, r0);\n  term_sink(e, r1);"));
  const altered = bend28Fixture.replace(
    "ctr_take(e, _left_1, 2,",
    "ctr_take(e, _left_1, 1,",
  );
  ok(altered !== bend28Fixture);
  throws(
    () => optimizeNativeStringComparison(altered, model, "bend 2.0.28"),
    /Expected one generated model\.name_equal/,
  );
});

Deno.test("native String specialization accepts the verified Bend 2.0.27 emission", () => {
  const { source, wrapper, helper } = optimizeNativeStringComparison(
    currentFixture,
    model,
    "bend 2.0.27",
  );
  equal(wrapper, "spin_13");
  equal(helper, "spin_14");
  ok(source.includes("Loc left_loc = term_peek(e, left);"));
  ok(source.includes("term_sink(e, r0);\n  term_sink(e, r1);"));
  ok(!source.includes("spin_14(e, _o_1, _left_0, _right_0, 1)"));
});

Deno.test("Bend 2.0.27 specialization still rejects altered ownership and equality", () => {
  for (
    const altered of [
      currentFixture.replace("term_sink(e, _f_7);", ""),
      currentFixture.replace(
        "U32_BIN(_a_0, ==, _b_0)",
        "U32_BIN(_a_0, !=, _b_0)",
      ),
    ]
  ) {
    ok(altered !== currentFixture);
    throws(
      () => optimizeNativeStringComparison(altered, model, "bend 2.0.27"),
      /Expected one generated model\.name_equal/,
    );
  }
  throws(
    () => optimizeNativeStringComparison(currentFixture, model, "bend 2.0.29"),
    /requires bend 2\.0\.24 or bend 2\.0\.27 or bend 2\.0\.28/,
  );
});

Deno.test("native String specialization selects the generated String comparator by shape", () => {
  const { source, wrapper, helper } = optimizeNativeStringComparison(
    fixture,
    model,
    version,
  );
  equal(wrapper, "spin_2");
  equal(helper, "spin_3");
  ok(source.includes("Loc left_loc = term_peek(e, left);"));
  ok(source.includes("term_sink(e, r0);\n  term_sink(e, r1);"));
  ok(!source.includes("spin_3(e, o_1, left_5, right_5, 1)"));

  const renumbered = fixture.replaceAll("spin_2", "spin_102")
    .replaceAll("spin_3", "spin_103")
    .replaceAll("spin_4", "spin_104");
  equal(
    optimizeNativeStringComparison(renumbered, model, version).wrapper,
    "spin_102",
  );
});

Deno.test("native String specialization rejects changed language or ownership contracts", () => {
  throws(
    () => optimizeNativeStringComparison(fixture, model, "bend 2.0.25"),
    /requires bend 2\.0\.24/,
  );
  throws(
    () =>
      optimizeNativeStringComparison(
        fixture,
        model.replace("Char.is_eq(a, b)", "Char.is_ne(a, b)"),
        version,
      ),
    /String comparison semantics changed/,
  );
  throws(
    () =>
      optimizeNativeStringComparison(
        fixture.replace(
          "return rfc_view(e, term_loc(t)) >> 24;",
          "return term_loc(t);",
        ),
        model,
        version,
      ),
    /runtime helper changed/,
  );
  throws(
    () =>
      optimizeNativeStringComparison(
        fixture.replace("U32_BIN(a_0, ==, b_0)", "U32_BIN(a_0, !=, b_0)"),
        model,
        version,
      ),
    /Expected one generated model\.name_equal/,
  );

  const spins = fixture.slice(
    fixture.indexOf("INLINE Term spin_4"),
    fixture.indexOf("// Work"),
  )
    .replaceAll("spin_2", "spin_102")
    .replaceAll("spin_3", "spin_103")
    .replaceAll("spin_4", "spin_104");
  throws(
    () =>
      optimizeNativeStringComparison(
        fixture.replace("// Work", `${spins}\n// Work`),
        model,
        version,
      ),
    /found 2/,
  );
});
