import { deepStrictEqual as equal, match, throws } from "node:assert/strict";
import { normalizeBendJsAbi } from "./bend_js_abi.ts";

Deno.test("Bend 2.0.28 constructor and typed match tags keep the 2.0.27 ABI", () => {
  const source = [
    'const a = {$: "model.UnitExpr"};',
    'const b = {$: "cst.Cst", kind: "root"};',
    'const c = {$: "check_scheduler.Task"};',
    'if (a.$ === "model.UnitExpr" && b.$ === "cst.Cst" && c.$ === "check_scheduler.Task") return a;',
    'const base = {$: "Some", value: {$: "Nil"}};',
  ].join("\n");
  const actual = normalizeBendJsAbi(source, "bend 2.0.28");
  equal(actual, {
    source: [
      'const a = {$: "UnitExpr"};',
      'const b = {$: "Cst", kind: "root"};',
      'const c = {$: "Task"};',
      'if (a.$ === "UnitExpr" && b.$ === "Cst" && c.$ === "Task") return a;',
      'const base = {$: "Some", value: {$: "Nil"}};',
    ].join("\n"),
    constructors: 3,
    matches: 3,
  });
});

Deno.test("same short constructor in two modules retains 2.0.27 typed-match semantics", () => {
  const source = [
    'const left = {$: "first.Binding"};',
    'const right = {$: "second.Binding"};',
    'if (left.$ === "first.Binding" && right.$ === "second.Binding") return left;',
  ].join("\n");
  const actual = normalizeBendJsAbi(source, "bend 2.0.28");
  equal(actual.source.match(/"Binding"/g)?.length, 4);
  equal([actual.constructors, actual.matches], [2, 2]);
});

Deno.test("ordinary strings, comments, regexes and template text are never tags", () => {
  const source = [
    'const x = {$: "model.UnitExpr"};',
    'if (x.$ === "model.UnitExpr") return x;',
    'const payload = "model.UnitExpr";',
    'const exportName = {"model.UnitExpr": 1};',
    'const quoted = \'{$: "model.UnitExpr"; x.$ === "model.UnitExpr"}\';',
    'const escaped = "\\"{$: \\"model.UnitExpr\\"}\\"";',
    'const re = /\\{\\$: "model.UnitExpr"\\}/;',
    'if (x) /\\{\\$: "model.UnitExpr"\\}/.test("x");',
    "const ratio = call() / 2;",
    'if (x.$ !== "$JMP") return x;',
    'const template = `{$: "model.UnitExpr"}`;',
    '// {$: "model.UnitExpr"}; x.$ === "model.UnitExpr"',
    '/* {$: "model.UnitExpr"}; x.$ === "model.UnitExpr" */',
  ].join("\n");
  const actual = normalizeBendJsAbi(source, "bend 2.0.28");
  equal(
    actual.source,
    source.replaceAll(
      '{$: "model.UnitExpr"};\nif (x.$ === "model.UnitExpr")',
      '{$: "UnitExpr"};\nif (x.$ === "UnitExpr")',
    ),
  );
  equal([actual.constructors, actual.matches], [1, 1]);
});

Deno.test("template interpolation code is normalized while template text stays raw", () => {
  const source = [
    'const x = {$: "model.UnitExpr"};',
    'const label = `fake {$: "model.UnitExpr"} ${x.$ === "model.UnitExpr"}`;',
  ].join("\n");
  const actual = normalizeBendJsAbi(source, "bend 2.0.28");
  match(
    actual.source,
    /`fake \{\$: "model\.UnitExpr"\} \$\{x\.\$ === "UnitExpr"\}`/,
  );
  equal([actual.constructors, actual.matches], [1, 1]);
});

Deno.test("version and emitter syntax changes fail closed", () => {
  const ordinary =
    'const x = {$: "UnitExpr"}; if (x.$ === "UnitExpr") return x;';
  equal(normalizeBendJsAbi(ordinary, "bend 2.0.27").source, ordinary);
  throws(
    () => normalizeBendJsAbi(ordinary, "bend 2.0.28"),
    /lacks the expected/,
  );
  throws(
    () => normalizeBendJsAbi(ordinary, "bend 2.0.29"),
    /Unsupported Bend JS ABI version/,
  );
  const changed = [
    'const x = {$: "model.UnitExpr"}; if (x.$ === "model.UnitExpr") return x;',
  ].join("\n");
  throws(() => normalizeBendJsAbi(changed, "bend 2.0.27"), /2\.0\.27 emitted/);
  throws(
    () =>
      normalizeBendJsAbi(
        changed.replace('"model.UnitExpr"', "'model.UnitExpr'"),
        "bend 2.0.28",
      ),
    /single-quoted/,
  );
  throws(
    () =>
      normalizeBendJsAbi(changed.replace("x.$ ===", "x.$ =="), "bend 2.0.28"),
    /invalid match Data tag form/,
  );
  throws(
    () =>
      normalizeBendJsAbi(
        changed.replace("x.$ ===", 'x["$"] ==='),
        "bend 2.0.28",
      ),
    /invalid match Data tag form/,
  );
  throws(
    () =>
      normalizeBendJsAbi(
        changed.replaceAll("model.UnitExpr", "model.inner.UnitExpr"),
        "bend 2.0.28",
      ),
    /qualified constructor/,
  );
  throws(
    () =>
      normalizeBendJsAbi(
        `${changed}\nconst ambiguous = [] /\\{\\$: "model.UnitExpr"\\}/;`,
        "bend 2.0.28",
      ),
    /ambiguous slash/,
  );
});
