import { equal, match, ok, rejects } from "node:assert/strict";
import {
  optimizeNativeCompilerKernelProbe,
  optimizeNativeCompilerKernels,
} from "./native_compiler_kernels.ts";

const fixture = await Deno.readTextFile(
  new URL("./fixtures/native_compiler_kernels_2_0_27.c", import.meta.url),
);
const sources = {
  index: await Deno.readTextFile(
    new URL("../compiler/index.bend", import.meta.url),
  ),
  types: await Deno.readTextFile(
    new URL("../compiler/types.bend", import.meta.url),
  ),
  model: await Deno.readTextFile(
    new URL("../compiler/model.bend", import.meta.url),
  ),
};
const transform = (
  generated = fixture,
  inputs = sources,
  version = "bend 2.0.27",
) => optimizeNativeCompilerKernels(generated, inputs, version);

Deno.test("native compiler kernels retain native fallback and transfer owned results", async () => {
  const output = await transform();
  match(
    output,
    /Term fields\[3\];\n      Loc span = ctr_take\(e, index, 3, fields\);/,
  );
  match(output, /term_sink\(e, high \? left : right\);/);
  match(
    output,
    /Term compact_list = compact_free_list\(e, &compact_result\);\n      term_sink\(e, _work_1\);/,
  );
  match(
    output,
    /Term compact_result = compact_closed_result\(e, _work_0, _work_1\);/,
  );
  match(output, /if \(_substitutions_3 != 0 && compact_closed_work/);
  match(
    output,
    /if \(err_seen\(e\.mem\)\) return 0;\n    if \(_substitutions_3/,
  );
  ok(output.includes("if (_fuel_0 == 0)"));
  ok(output.includes("spin_413(e, _o_0, _substitutions_0"));
  equal(
    (output.match(/static inline bool compact_free_work/g) ?? []).length,
    1,
  );
  equal(
    (output.match(/static inline bool compact_closed_work/g) ?? []).length,
    1,
  );
  await rejects(() => transform(output), /already patched/);
});

Deno.test("native compiler kernels fail closed on Bend and semantic changes", async () => {
  await rejects(
    () => transform(fixture, sources, "bend 2.0.28"),
    /require bend 2\.0\.27/,
  );
  for (
    const [part, before, after] of [
      ["index", "Nat.div(position, 33n)", "Nat.div(position, 32n)"],
      [
        "types",
        "return union(row_free(effects), union(p, r))",
        "return union(p, union(row_free(effects), r))",
      ],
      ["types", "flat_step(1048576n", "flat_step(1048575n"],
      [
        "model",
        "  ArrayTy{element: Ty}",
        "  ArrayTy{element: Ty}\n  FutureTy{child: Ty}",
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
});

Deno.test("native compiler kernels reject changed ownership and generated field layouts", async () => {
  for (
    const [before, after, expected] of [
      ["return term_loc(t);", "return 0;", /runtime helper changed: term_peek/],
      [
        "return rfc_wrap(e, t, 2);",
        "return t;",
        /runtime helper changed: term_keep/,
      ],
      [
        "span_fade(e, t, src, n);",
        "term_drop(e, t);",
        /runtime helper changed: ctr_take/,
      ],
      [
        "#define err_spun(H, n) ((++*(n) & 4095) == 0 && err_seen(H))",
        "#define err_spun(H, n) false",
        /runtime macro layout changed/,
      ],
      [
        "#define CID_MODEL_VARIABLETY 106",
        "#define CID_MODEL_VARIABLETY 106\n#define CID_MODEL_FUTURETY 900",
        /constructor set changed/,
      ],
      [
        "ctr_take(e, _index_0, 3,",
        "ctr_take(e, _index_0, 4,",
        /Index\.find generated shape changed/,
      ],
      ["33ull", "32ull", /Index\.find generated shape changed/],
      [
        "Term _f_1 = _fb_1[0];",
        "Term _f_1 = _fb_1[1];",
        /free_work generated field shape changed: FUNCTIONTY/,
      ],
      [
        "Term _f_5 = _fb_1[4];",
        "Term _f_5 = _fb_1[2];",
        /free_work generated field shape changed: FUNCTIONTY/,
      ],
      [
        "Term _f_41 = _fb_5[2];",
        "Term _f_41 = _fb_5[1];",
        /free_work generated field shape changed: APPLIEDTY/,
      ],
      [
        "Term _f_33 = _fb_3[4];",
        "Term _f_33 = _fb_3[3];",
        /free_work generated field shape changed: STATEPROVIDERTY/,
      ],
      [
        "ctr_take(e, _work_1, 5,",
        "ctr_take(e, _work_1, 4,",
        /free_work generated field shape changed/,
      ],
      [
        "term_keep(e, _work_1)",
        "_work_1",
        /resolve_work generated shape changed/,
      ],
      [
        "Term _substitutions_3 = r3;",
        "Term _substitutions_3 = r2;",
        /resolve_work generated shape changed/,
      ],
      [
        "WL_CASE(FID_INDEX_FIND_WORK)",
        "WL_CASE(FID_INDEX_FIND_WORK_BROKEN)",
        /missing or ambiguous/,
      ],
    ] as const
  ) {
    const changed = fixture.replace(before, after);
    ok(changed !== fixture, `fixture must contain ${before}`);
    await rejects(() => transform(changed), expected);
  }
});

Deno.test("standalone probe mode normalizes imported symbol namespaces", async () => {
  const namespaced = fixture.replaceAll(
    "FID_INDEX_",
    "FID__________COMPILER_INDEX_",
  )
    .replaceAll("FID_TYPES_", "FID__________COMPILER_TYPES_")
    .replaceAll("CID_MODEL_", "CID__________COMPILER_MODEL_");
  for (const kernel of ["index", "free", "closed"] as const) {
    const output = await optimizeNativeCompilerKernelProbe(
      namespaced,
      sources,
      "bend 2.0.27",
      kernel,
    );
    ok(output.includes("WL_CASE(FID_INDEX_FIND_WORK)"));
    ok(output.includes("#define CID_MODEL_FUNCTIONTY 104"));
    ok(output !== namespaced);
  }
});
