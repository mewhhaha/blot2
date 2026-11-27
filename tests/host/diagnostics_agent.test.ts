import { deepStrictEqual, equal, match, ok } from "node:assert/strict";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { runCli } from "../../host/cli.ts";
import {
  analyzeDiagnostic,
  canonicalDiagnosticCode,
  DIAGNOSTIC_CATALOG,
  DIAGNOSTIC_SCHEMA_VERSION,
  enrichDiagnostic,
  formatDiagnostic,
  formatExplanation,
  humanizeToken,
  lookupDiagnosticExplanation,
  type RawDiagnosticRecord,
} from "../../host/diagnostics.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url).pathname;
const stdRoot = fileURLToPath(new URL("../../std", import.meta.url));
const prelude = fileURLToPath(
  new URL("../../std/prelude.sq", import.meta.url),
);
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

function applyUtf8Edit(
  source: string,
  edit: { startByte: number; endByte: number; newText: string },
): string {
  const bytes = textEncoder.encode(source);
  const replacement = textEncoder.encode(edit.newText);
  const out = new Uint8Array(
    edit.startByte + replacement.length + (bytes.length - edit.endByte),
  );
  out.set(bytes.subarray(0, edit.startByte), 0);
  out.set(replacement, edit.startByte);
  out.set(bytes.subarray(edit.endByte), edit.startByte + replacement.length);
  return textDecoder.decode(out);
}

async function runCompilerRaw(
  cmd: "check-project" | "build",
  file: string,
  wasmOut?: string,
): Promise<{
  code: number;
  diagnostics: RawDiagnosticRecord[];
  stdout: string;
  stderr: string;
}> {
  const args = cmd === "build"
    ? ["build", file, wasmOut!, "--prelude", prelude, "--std-root", stdRoot]
    : ["check-project", file, "--prelude", prelude, "--std-root", stdRoot];
  const output = await new Deno.Command(executable, {
    args,
    stdout: "piped",
    stderr: "piped",
  }).output();
  const stdout = textDecoder.decode(output.stdout);
  const stderr = textDecoder.decode(output.stderr);
  const diagnostics: RawDiagnosticRecord[] = [];
  for (const line of stdout.split("\n")) {
    if (!line.trim()) continue;
    const record = JSON.parse(line);
    if (record.kind === "diagnostic") {
      diagnostics.push(record as RawDiagnosticRecord);
    }
  }
  return { code: output.code, diagnostics, stdout, stderr };
}

async function runCapturedCli(
  args: string[],
): Promise<{ code: number; stdout: string; stderr: string }> {
  const stdoutChunks: string[] = [];
  const stderrLines: string[] = [];
  const origLog = console.log;
  const origError = console.error;
  const origStdoutWrite = Deno.stdout.write.bind(Deno.stdout);
  console.log = (...values: unknown[]) => {
    stdoutChunks.push(values.map(String).join(" ") + "\n");
  };
  console.error = (...values: unknown[]) => {
    stderrLines.push(values.map(String).join(" "));
  };
  Deno.stdout.write = (p: Uint8Array) => {
    stdoutChunks.push(textDecoder.decode(p));
    return Promise.resolve(p.length);
  };
  try {
    const code = await runCli(executable, args);
    return {
      code,
      stdout: stdoutChunks.join("").trimEnd(),
      stderr: stderrLines.join("\n"),
    };
  } finally {
    console.log = origLog;
    console.error = origError;
    Deno.stdout.write = origStdoutWrite;
  }
}

Deno.test("diagnostics: canonical codes and explain catalog", async () => {
  equal(canonicalDiagnosticCode("GPU_FRONTEND_SYNTAX_ERROR"), "SYNTAX_ERROR");
  equal(
    canonicalDiagnosticCode("GPU_FRONTEND_MALFORMED_DELIMITER"),
    "UNMATCHED_DELIMITER",
  );
  equal(canonicalDiagnosticCode("spent_value"), "SPENT_VALUE");
  equal(canonicalDiagnosticCode("unknown_name"), "UNKNOWN_VALUE");
  equal(canonicalDiagnosticCode("unknown_value"), "UNKNOWN_VALUE");

  // Every catalog entry renders a structured explanation with before/after/checklist
  for (const code of Object.keys(DIAGNOSTIC_CATALOG)) {
    const explanation = formatExplanation(code);
    match(explanation ?? "", new RegExp(`\\[${code}\\]`));
    match(explanation ?? "", /Before \(fails\):/);
    match(explanation ?? "", /After \(fixed\):/);
    match(
      explanation ?? "",
      new RegExp(`skills/squid-diagnostics/SKILL\\.md#${code}`),
    );
  }

  // CLI explain + explain --list + guide --cheatsheet
  const listRun = await runCapturedCli(["explain", "--list"]);
  equal(listRun.code, 0);
  match(listRun.stdout, /SPENT_VALUE/);
  match(listRun.stdout, /ALIASED_UPDATE/);

  const explainRun = await runCapturedCli(["explain", "spent_value"]);
  equal(explainRun.code, 0);
  match(explainRun.stdout, /\[SPENT_VALUE\]/);
  match(explainRun.stdout, /a\.copy/);

  const unknownExplain = await runCapturedCli(["explain", "DOES_NOT_EXIST"]);
  equal(unknownExplain.code, 1);
  match(unknownExplain.stderr, /Unknown diagnostic code: DOES_NOT_EXIST/);

  const cheatsheetRun = await runCapturedCli(["guide", "--cheatsheet"]);
  equal(cheatsheetRun.code, 0);
  match(cheatsheetRun.stdout, /# Squid vNext Cheatsheet/);
  match(cheatsheetRun.stdout, /#\[1, 2, 3\]/);
});

Deno.test("diagnostics: UTF-8 byte offsets map to exact line and code-point column", () => {
  const source = "io main (): U32 =>\n  // café ✓\n  return bad_name\n";
  const bytes = new TextEncoder().encode(source);
  const start = new TextEncoder().encode(
    "io main (): U32 =>\n  // café ✓\n  return ",
  ).length;
  const end = start + "bad_name".length;
  equal(bytes.length > end, true);
  const record: RawDiagnosticRecord = {
    filename: "unicode.sq",
    code: "unknown_value",
    start,
    end,
    message: "Unknown value `bad_name`; did you mean `good_name`?",
  };
  const rendered = formatDiagnostic(record, { source });
  match(rendered, /\[UNKNOWN_VALUE\]/);
  match(rendered, /in unicode\.sq › io main/);
  match(rendered, /at unicode\.sq:3:10/);
  match(rendered, /3 \|   return bad_name/);
  match(rendered, /\^\^\^\^\^\^\^\^ did you mean `good_name`\?/);
  match(rendered, /fix: Replace `bad_name` with `good_name`\./);
  match(rendered, /doc: squid explain UNKNOWN_VALUE/);
});

Deno.test("diagnostics: real compiler CLI reports Solid-2 style blame and fixes across agent pitfalls", async () => {
  const tempDir = await Deno.makeTempDir({ prefix: "squid-diag-agent-" });
  try {
    const cases: {
      name: string;
      cmd: "check" | "build";
      source: string;
      patterns: RegExp[];
    }[] = [
      {
        name: "fn_keyword.sq",
        cmd: "check",
        source: "fn add (a: U32) -> (b: U32): U32 => return a + b\n",
        patterns: [
          /\[SYNTAX_ERROR\]/,
          /at .*fn_keyword\.sq:1:1/,
          /fix: Squid uses `func`, not `fn`/,
          /doc: squid explain SYNTAX_ERROR/,
        ],
      },
      {
        name: "bare_list.sq",
        cmd: "check",
        source: "io main (): #[U32] => return [1, 2, 3]\n",
        patterns: [
          /\[UNSUPPORTED_EXPRESSION\]/,
          /in bare_list\.sq › io main/,
          /at .*bare_list\.sq:1:30/,
          /use `#\[\.\.\.\]` here/,
          /fix: Replace bare `\[\.\.\.\]` with `#\[\.\.\.\]`/,
          /doc: squid explain UNSUPPORTED_EXPRESSION/,
        ],
      },
      {
        name: "missing_dollar.sq",
        cmd: "check",
        source:
          "type Opt is data = $Some U32 | $Nothing\nio main (): Opt => return Some 1\n",
        patterns: [
          /\[UNKNOWN_VALUE\]/,
          /in missing_dollar\.sq › io main/,
          /at .*missing_dollar\.sq:2:27/,
          /add `\$` -> `\$Some`/,
          /fix: Prefix the data constructor with `\$`: use `\$Some`/,
        ],
      },
      {
        name: "typo_name.sq",
        cmd: "check",
        source:
          "func compute_total (x: U32): U32 => return x + 1\nio main (): U32 => return compute_totla 5\n",
        patterns: [
          /\[UNKNOWN_VALUE\]/,
          /in typo_name\.sq › io main/,
          /at .*typo_name\.sq:2:27/,
          /did you mean `compute_total`\?/,
          /fix: Replace `compute_totla` with `compute_total`\./,
        ],
      },
      {
        name: "missing_field.sq",
        cmd: "check",
        source:
          "type Pt = { x: U32, y: U32 }\nio main (): U32 =>\n  let p: Pt = { x: 1, y: 2 }\n  return p.z\n",
        patterns: [
          /\[MISSING_MEMBER\]/,
          /Type `\{ x: U32, y: U32 \}` has no field or member `\.z`/,
          /in missing_field\.sq › io main/,
          /at .*missing_field\.sq:4:10/,
          /fix: Available fields on `\{ x: U32, y: U32 \}`: `x`, `y`\./,
        ],
      },
      {
        name: "type_mismatch.sq",
        cmd: "check",
        source: "io main (): U32 => return 1.5\n",
        patterns: [
          /\[TYPE_MISMATCH\]/,
          /F32.*U32|U32.*F32/,
          /fix: Squid has no implicit numeric conversions/,
          /doc: squid explain TYPE_MISMATCH/,
        ],
      },
      {
        name: "spent_value.sq",
        cmd: "build",
        source:
          "func consume (xs: own #[U32]): U32 => return xs.length\nio main (): U32 =>\n  let a = #[1, 2, 3]\n  let n = consume a\n  return n + a.length\n",
        patterns: [
          /\[SPENT_VALUE\] `a` was already moved at line 4/,
          /in spent_value\.sq › io main/,
          /at .*spent_value\.sq:5:14/,
          /--------- `a` moved here/,
          /\^\^\^\^\^\^\^\^ `a` used after move/,
          /fix: Pass `a\.copy` at line 4/,
          /doc: squid explain SPENT_VALUE/,
        ],
      },
      {
        name: "aliased_update.sq",
        cmd: "build",
        source:
          "io main (): U32 =>\n  let a = #[1, 2, 3]\n  let b = a\n  a[0] := 99\n  return a[0] + b[0]\n",
        patterns: [
          /\[ALIASED_UPDATE\] Cannot mutate `a` in place while `b` still borrows it/,
          /in aliased_update\.sq › io main/,
          /at .*aliased_update\.sq:4:3/,
          /--------- borrowed by `b` here/,
          /\^\^\^\^\^\^\^\^\^\^ mutated while borrowed/,
          /fix: Snapshot with `let b = a\.copy` \(line 3\)/,
          /doc: squid explain ALIASED_UPDATE/,
        ],
      },
      {
        name: "param_update.sq",
        cmd: "build",
        source:
          "func bad (a: #[U32]): #[U32] =>\n  a[0] := 99\n  return a\nio main (): U32 => return (bad #[1, 2])[0]\n",
        patterns: [
          /\[ALIASED_UPDATE\] Cannot mutate borrowed parameter `a` in place without `own`/,
          /in param_update\.sq › func bad/,
          /at .*param_update\.sq:2:3/,
          /----------- borrowed parameter \(not `own`\)/,
          /fix: Mark the parameter `own`/,
        ],
      },
      {
        name: "unhandled_effect.sq",
        cmd: "build",
        source:
          "type Clock is effect = { now: Unit -> U32 }\nio main (): U32 =>\n  use t <- Clock.now ()\n  return t\n",
        patterns: [
          /\[ENTRY_TYPE\] Entry function leaves effect `Clock\.now` unhandled/,
          /in unhandled_effect\.sq › io main/,
          /unhandled effect `Clock\.now`/,
          /fix: Handle `Clock\.now` inside the entry function with `handler h: Clock => now /,
          /doc: squid explain ENTRY_TYPE/,
        ],
      },
    ];

    for (const c of cases) {
      const file = join(tempDir, c.name);
      await Deno.writeTextFile(file, c.source);
      const args = c.cmd === "build"
        ? ["build", file, join(tempDir, `${c.name}.wasm`)]
        : ["check", file];
      const run = await runCapturedCli(args);
      equal(run.code, 1, `expected failure for ${c.name}, got:\n${run.stderr}`);
      for (const pat of c.patterns) {
        match(
          run.stderr,
          pat,
          `${c.name} output did not match ${pat}:\n${run.stderr}`,
        );
      }
    }
  } finally {
    await Deno.remove(tempDir, { recursive: true });
  }
});

Deno.test("diagnostics: quick-fix replay compiles cleanly across all supported pitfalls", async () => {
  const tempDir = await Deno.makeTempDir({ prefix: "squid-qf-replay-" });
  try {
    const replayCases: Array<{
      name: string;
      cmd: "check-project" | "build";
      source: string;
      expectedSnippet?: RegExp;
    }> = [
      {
        name: "fn_simple.sq",
        cmd: "check-project",
        source: "fn add (a: U32): U32 => return a + 1\n",
        expectedSnippet: /^func add \(a: U32\): U32 => return a \+ 1/,
      },
      {
        name: "bare_list.sq",
        cmd: "build",
        source: "io main (): #[U32] => return [1, 2, 3]\n",
        expectedSnippet: /#\[1, 2, 3\]/,
      },
      {
        name: "missing_dollar.sq",
        cmd: "check-project",
        source:
          "type Opt is data = $Some U32 | $Nothing\nfunc main (): Opt => return Some 1\n",
        expectedSnippet: /\$Some 1/,
      },
      {
        name: "none_to_nothing.sq",
        cmd: "check-project",
        source: "func main (): Maybe U32 => return None\n",
        expectedSnippet: /return \$Nothing/,
      },
      {
        name: "typo_ident.sq",
        cmd: "build",
        source:
          "func compute_total (x: U32): U32 => return x + 1\nio main (): U32 => return compute_totla 5\n",
        expectedSnippet: /return compute_total 5/,
      },
      {
        name: "dot_len.sq",
        cmd: "build",
        source: "io main (): U32 =>\n  let xs = #[1, 2, 3]\n  return xs.len\n",
        expectedSnippet: /return xs\.length/,
      },
      {
        name: "spent_whole_local.sq",
        cmd: "build",
        source:
          "func consume (xs: own #[U32]): U32 => return xs.length\nio main (): U32 =>\n  let a = #[1, 2, 3]\n  let n = consume a\n  return n + a.length\n",
        expectedSnippet: /consume a\.copy/,
      },
      {
        name: "spent_field_projection.sq",
        cmd: "build",
        source:
          "type Row = { xs: #[U32] }\nfunc fill (xs: own #[U32]): U32 => return xs.length\nio main (): U32 =>\n  let row: Row = { xs: #[1, 2, 3] }\n  let n = fill row.xs\n  return n + row.xs.length\n",
        expectedSnippet: /fill \(row\.xs\.copy\)/,
      },
      {
        name: "aliased_local_borrow.sq",
        cmd: "build",
        source:
          "io main (): U32 =>\n  let a = #[1, 2, 3]\n  let b = a\n  a[0] := 99\n  return a[0] + b[0]\n",
        expectedSnippet: /let b = a\.copy/,
      },
      {
        name: "aliased_nested_param.sq",
        cmd: "build",
        source:
          "func f (xs: #[(U32, U32)]): #[(U32, U32)] =>\n  xs[0] := (1, 2)\n  return xs\nio main (): U32 =>\n  let out = f #[(0, 0)]\n  let (a, b) = out[0]\n  return a + b\n",
        expectedSnippet:
          /func f \(xs: own #\[\(U32, U32\)\]\): #\[\(U32, U32\)\]/,
      },
      {
        name: "own_argument_param.sq",
        cmd: "build",
        source:
          "func consume (xs: own #[U32]): #[U32] => return xs\nfunc forward (xs: #[U32]): #[U32] => return consume xs\nio main (): U32 => return (forward #[1, 2]).length\n",
        expectedSnippet: /func forward \(xs: own #\[U32\]\): #\[U32\]/,
      },
      {
        name: "result_not_owned.sq",
        cmd: "build",
        source:
          "func pick (xs: #[U32]): #[U32] => return xs\nio main (): U32 => return (pick #[1, 2]).length\n",
        expectedSnippet: /return xs\.copy/,
      },
    ];

    for (const c of replayCases) {
      const file = join(tempDir, c.name);
      const wasmOut = join(tempDir, `${c.name}.wasm`);
      await Deno.writeTextFile(file, c.source);
      const initial = await runCompilerRaw(c.cmd, file, wasmOut);
      equal(
        initial.code,
        1,
        `${c.name}: expected initial compile to fail`,
      );
      ok(
        initial.diagnostics.length > 0,
        `${c.name}: expected at least one diagnostic`,
      );
      const analyzed = analyzeDiagnostic(initial.diagnostics[0], c.source);
      ok(
        analyzed.quickFixes.length > 0,
        `${c.name}: expected quick-fix, got none (diag=${
          JSON.stringify(initial.diagnostics[0])
        })`,
      );
      const fix = analyzed.quickFixes[0];
      equal(fix.complete, true, `${c.name}: quick-fix should be complete`);
      const patched = applyUtf8Edit(c.source, fix);
      if (c.expectedSnippet) {
        match(
          patched,
          c.expectedSnippet,
          `${c.name}: patched source did not match:\n${patched}`,
        );
      }
      await Deno.writeTextFile(file, patched);
      const recompiled = await runCompilerRaw(c.cmd, file, wasmOut);
      equal(
        recompiled.code,
        0,
        `${c.name}: patched source failed to compile:\n${patched}\nDiagnostics:\n${
          JSON.stringify(recompiled.diagnostics, null, 2)
        }`,
      );
    }

    // Rust-style fn must NOT emit a broken auto-quick-fix
    const rustFile = join(tempDir, "rust_fn.sq");
    const rustSrc = "fn add (a: U32, b: U32) -> U32 { return a + b }\n";
    await Deno.writeTextFile(rustFile, rustSrc);
    const rustRun = await runCompilerRaw("check-project", rustFile);
    equal(rustRun.code, 1);
    const rustAnalyzed = analyzeDiagnostic(rustRun.diagnostics[0], rustSrc);
    equal(
      rustAnalyzed.quickFixes.length,
      0,
      `Rust-style fn must not emit a broken quick-fix: ${
        JSON.stringify(rustAnalyzed.quickFixes)
      }`,
    );
    match(rustAnalyzed.fix ?? "", /Squid uses `func`, not `fn`/);
  } finally {
    await Deno.remove(tempDir, { recursive: true });
  }
});

Deno.test("diagnostics: 1-to-1 sync between DIAGNOSTIC_CATALOG, SKILL.md, and all compiler enums", async () => {
  const skillText = await Deno.readTextFile(
    new URL("../../skills/squid-diagnostics/SKILL.md", import.meta.url),
  );
  const skillCodes = [...skillText.matchAll(/^## ([A-Z][A-Z0-9_]+)$/gm)].map(
    (m) => m[1],
  );
  const catalogCodes = Object.keys(DIAGNOSTIC_CATALOG);
  deepStrictEqual(
    [...skillCodes].sort(),
    [...catalogCodes].sort(),
    "skills/squid-diagnostics/SKILL.md headings must match DIAGNOSTIC_CATALOG 1-to-1",
  );
  equal(
    new Set(skillCodes).size,
    skillCodes.length,
    "SKILL.md must not contain duplicate ## CODE headings",
  );

  const enumFiles = [
    "../../compiler-goose/src/check/check.goose",
    "../../compiler-goose/src/check/core.goose",
    "../../compiler-goose/src/check/diagnostic_code.goose",
    "../../compiler-goose/src/reuse/project.goose",
    "../../compiler-goose/src/reuse/project_check.goose",
  ];
  const allCodes = new Set<string>([
    "asset_import",
    "Io",
    "GPU_FRONTEND_SYNTAX_ERROR",
    "GPU_FRONTEND_MALFORMED_DELIMITER",
    "GPU_FRONTEND_LEXICAL_ERROR",
  ]);
  for (const rel of enumFiles) {
    const text = await Deno.readTextFile(new URL(rel, import.meta.url));
    const m = /enum Code\s*\{([^}]+)\}/.exec(text);
    ok(m, `Could not find enum Code in ${rel}`);
    for (const part of m[1].split(",")) {
      const code = part.trim();
      if (code) allCodes.add(code);
    }
  }

  const missing: string[] = [];
  for (const code of allCodes) {
    if (!lookupDiagnosticExplanation(code)) {
      missing.push(code);
    }
  }
  deepStrictEqual(
    missing,
    [],
    `Unmapped compiler diagnostic codes: ${missing.join(", ")}`,
  );
});

Deno.test("diagnostics: unified v1 --json schema, virtual_source, provenance, and multi-file related", async () => {
  const tempDir = await Deno.makeTempDir({ prefix: "squid-diag-json-" });
  try {
    const checkFile = join(tempDir, "check_err.sq");
    await Deno.writeTextFile(
      checkFile,
      "io main (): U32 => return 1.5\n",
    );
    const checkRun = await runCapturedCli(["check", checkFile, "--json"]);
    equal(checkRun.code, 1);
    const checkRecords = checkRun.stdout.split("\n").filter(Boolean).map((l) =>
      JSON.parse(l)
    );
    const checkDiag = checkRecords.find((r) => r.kind === "diagnostic");
    ok(checkDiag, "Expected diagnostic record in squid check --json");
    equal(checkDiag.schemaVersion, DIAGNOSTIC_SCHEMA_VERSION);
    equal(checkDiag.severity, "error");
    equal(checkDiag.canonicalCode, "TYPE_MISMATCH");
    equal(checkDiag.rawCode, "type_mismatch");
    equal(checkDiag.code, "type_mismatch");
    equal(typeof checkDiag.start, "number");
    equal(typeof checkDiag.end, "number");
    equal(typeof checkDiag.message, "string");
    equal(typeof checkDiag.headline, "string");
    equal(checkDiag.scope, "io main");
    equal(checkDiag.primarySpan.line, 1);
    ok(checkDiag.primarySpan.col >= 1);
    ok(Array.isArray(checkDiag.related));
    ok(Array.isArray(checkDiag.quickFixes));
    match(checkDiag.docRef, /squid explain TYPE_MISMATCH/);

    const buildFile = join(tempDir, "build_err.sq");
    const buildWasm = join(tempDir, "build_err.wasm");
    await Deno.writeTextFile(
      buildFile,
      "type Row = { xs: #[U32] }\nfunc fill (xs: own #[U32]): U32 => return xs.length\nio main (): U32 =>\n  let row: Row = { xs: #[1, 2, 3] }\n  let n = fill row.xs\n  return n + row.xs.length\n",
    );
    const buildRun = await runCapturedCli([
      "build",
      buildFile,
      buildWasm,
      "--json",
    ]);
    equal(buildRun.code, 1);
    const buildRecords = buildRun.stdout.split("\n").filter(Boolean).map((l) =>
      JSON.parse(l)
    );
    const buildDiag = buildRecords.find((r) => r.kind === "diagnostic");
    ok(buildDiag, "Expected diagnostic record in squid build --json");
    equal(buildDiag.schemaVersion, 1);
    equal(buildDiag.canonicalCode, "SPENT_VALUE");
    equal(buildDiag.rawCode, "spent_value");
    equal(buildDiag.primarySpan.line, 6);
    equal(buildDiag.related.length, 1);
    equal(buildDiag.related[0].line, 5);
    equal(buildDiag.quickFixes.length, 1);
    equal(buildDiag.quickFixes[0].newText, "(row.xs.copy)");
    match(buildDiag.fix, /\(row\.xs\.copy\)/);
    ok(
      buildRecords.some((r) => r.kind === "compilation" && r.success === false),
      "Non-diagnostic compilation record should pass through unchanged",
    );

    // Stage-0 virtual_source, provenance, multi-file related, and humanizeToken
    const virtualRecord: RawDiagnosticRecord = {
      filename: "/virtual/shape.sq",
      stage: "check-project",
      code: "type_mismatch",
      start: 28,
      end: 31,
      message: "Types do not match; one side: F32; other side: U32",
      virtual_source: "func generated (): U32 => return 1.5\n",
      provenance: {
        stage: "stage0",
        phase: "generated_source",
        module: "shape",
        input: "shape.txt",
        generator: "generator.sq",
      },
      related: { filename: "/other/caller.sq", start: 10, end: 15 },
    };
    const renderedVirtual = formatDiagnostic(virtualRecord, {
      relatedSources: {
        "/other/caller.sq": "import a\nlet x = generated ()\n",
      },
    });
    match(
      renderedVirtual,
      /from shape\.txt via generator\.sq \(stage0 generated_source\)/,
    );
    match(renderedVirtual, /func generated \(\): U32 => return 1\.5/);
    match(renderedVirtual, /note: related at \/other\/caller\.sq:2:2/);

    const enrichedVirtual = enrichDiagnostic(virtualRecord, {
      relatedSources: {
        "/other/caller.sq": "import a\nlet x = generated ()\n",
      },
    });
    equal(enrichedVirtual.schemaVersion, 1);
    equal(enrichedVirtual.provenance?.phase, "generated_source");
    equal(enrichedVirtual.primarySpan.line, 1);
    equal(enrichedVirtual.related.length, 1);
    equal(enrichedVirtual.related[0].filename, "/other/caller.sq");
    equal(enrichedVirtual.related[0].line, 2);

    equal(humanizeToken("kw_func"), "'func'");
    equal(humanizeToken("fat_arrow"), "'=>'");
    equal(humanizeToken("colon_equal"), "':='");
    equal(humanizeToken("eof"), "end of file");
  } finally {
    await Deno.remove(tempDir, { recursive: true });
  }
});

Deno.test("diagnostics: generator-backed squid check succeeds on libraries without io entries and fails on real errors", async () => {
  const tempDir = await Deno.makeTempDir({ prefix: "squid-gen-lib-check-" });
  try {
    await Deno.writeTextFile(
      join(tempDir, "squid.json"),
      JSON.stringify({
        generators: [{
          module: "shape",
          input: "shape.txt",
          generator: "generator.sq",
        }],
      }),
    );
    await Deno.writeTextFile(
      join(tempDir, "generator.sq"),
      "io generate (bytes: #[U32]): #[U32] => return bytes\n",
    );
    await Deno.writeTextFile(
      join(tempDir, "shape.txt"),
      "type Shape is data = $Shape { width: U32 }\n",
    );
    const libFile = join(tempDir, "lib.sq");
    await Deno.writeTextFile(
      libFile,
      'import { Shape } from "./shape"\nfunc measure (s: Shape): U32 => return s.width\n',
    );

    const okCheck = await runCapturedCli(["check", libFile]);
    equal(
      okCheck.code,
      0,
      `Expected library check to succeed, stderr:\n${okCheck.stderr}`,
    );
    match(okCheck.stdout, /checked/);

    const okJson = await runCapturedCli(["check", libFile, "--json"]);
    equal(okJson.code, 0, `stderr:\n${okJson.stderr}`);
    const okRecords = okJson.stdout.split("\n").filter(Boolean).map((l) =>
      JSON.parse(l)
    );
    equal(okRecords.length, 1);
    equal(okRecords[0].kind, "compilation");
    equal(okRecords[0].stage, "check-project");
    equal(okRecords[0].success, true);
    equal(okRecords[0].wasm_bytes, 0);

    // Real type error in library must still fail with v1 enriched JSON
    await Deno.writeTextFile(
      libFile,
      'import { Shape } from "./shape"\nfunc measure (s: Shape): F32 => return s.width\n',
    );
    const badType = await runCapturedCli(["check", libFile, "--json"]);
    equal(badType.code, 1);
    const badTypeRecords = badType.stdout.split("\n").filter(Boolean).map((l) =>
      JSON.parse(l)
    );
    const typeDiag = badTypeRecords.find((r) => r.kind === "diagnostic");
    ok(typeDiag, "Expected diagnostic on type error in generator library");
    equal(typeDiag.schemaVersion, 1);
    equal(typeDiag.canonicalCode, "TYPE_MISMATCH");

    // Real uniqueness error in library must still fail
    await Deno.writeTextFile(
      libFile,
      'import { Shape } from "./shape"\nfunc consume (xs: own #[U32]): U32 => return xs[0]\nfunc measure (s: Shape): U32 =>\n  let a = #[s.width]\n  let n = consume a\n  return @u32.add n a[0]\n',
    );
    const badUniq = await runCapturedCli(["check", libFile]);
    equal(badUniq.code, 1);
    match(badUniq.stderr, /\[SPENT_VALUE\]/);
  } finally {
    await Deno.remove(tempDir, { recursive: true });
  }
});

Deno.test("diagnostics: misrouted-advice regressions (record fields, #kernel effects, Text, ENTRY_TYPE, handler alias)", () => {
  // 1. UNKNOWN_RECORD_FIELD and missing_field must never suggest `.length`
  const recField = analyzeDiagnostic({
    filename: "r.sq",
    code: "unknown_record_field",
    start: 0,
    end: 3,
    message: "Unknown record field z",
  }, "p.z");
  equal(recField.canonicalCode, "UNKNOWN_RECORD_FIELD");
  equal(recField.fix?.includes(".length") ?? false, false);
  match(recField.docRef, /UNKNOWN_RECORD_FIELD/);

  const recLen = analyzeDiagnostic({
    filename: "r.sq",
    code: "missing_member",
    start: 0,
    end: 5,
    message: "This receiver has no associated member with this name",
    details: {
      explanation: {
        member: "len",
        candidates: [{ side: "receiver", operand: "{ x: U32, y: U32 }" }],
      },
    },
  }, "p.len");
  equal(recLen.fix?.includes(".length") ?? false, false);
  equal(recLen.quickFixes.length, 0);
  match(recLen.fix ?? "", /Available fields/);

  // 2. KERNEL_EFFECTFUL must never suggest `use`
  const kernelEff = analyzeDiagnostic({
    filename: "k.sq",
    code: "kernel_effectful",
    start: 0,
    end: 10,
    message: "#kernel and #process functions must be pure (! {})",
  }, "#kernel func k (): U32 => return 0");
  equal(kernelEff.canonicalCode, "KERNEL_EFFECTFUL");
  equal(/\buse\b/.test(kernelEff.fix ?? ""), false);
  match(kernelEff.fix ?? "", /pure/);
  match(kernelEff.docRef, /KERNEL_EFFECTFUL/);

  // 3. String / str must suggest Text, never #[U8]
  for (const code of ["unknown_value", "unsupported_type"]) {
    const strDiag = analyzeDiagnostic({
      filename: "s.sq",
      code,
      start: 0,
      end: 6,
      message: "Unknown or unsupported `String`",
    }, "String");
    match(strDiag.fix ?? "", /`Text`/);
    equal(strDiag.fix?.includes("#[U8]") ?? false, false);
  }

  // 4. ENTRY_TYPE reflects raw io ABI-8 vs #kernel/#process
  const entryDiag = analyzeDiagnostic({
    filename: "e.sq",
    code: "entry_type",
    start: 0,
    end: 2,
    message: "Invalid io entry signature",
  }, "io");
  match(entryDiag.fix ?? "", /#\[U32\]/);
  match(entryDiag.fix ?? "", /#kernel/);

  // 5. ALIASED_UPDATE inside a `handler` or origin_kind === "aliased" gives distinct advice
  const handlerSrc = [
    "io main (): U32 =>",
    "  let xs = #[1, 2]",
    "  handler h: Eff =>",
    "    step () =>",
    "      xs[0] := 9",
    "      return xs[0]",
    "  return 0",
  ].join("\n");
  const handlerStart = handlerSrc.indexOf("xs[0] := 9");
  const handlerDiag = analyzeDiagnostic({
    filename: "w.sq",
    code: "aliased_update",
    start: handlerStart,
    end: handlerStart + 10,
    message: "This := writes through storage captured in a handler",
    origin_kind: "aliased",
    subject_start: handlerSrc.indexOf("xs ="),
    subject_end: handlerSrc.indexOf("xs =") + 2,
  }, handlerSrc);
  match(handlerDiag.fix ?? "", /`handler`/);
  equal(handlerDiag.fix?.includes("let b =") ?? false, false);
});

Deno.test("diagnostics: positive examples in CHEATSHEET.md and SKILL.md compile cleanly", async () => {
  const tempDir = await Deno.makeTempDir({ prefix: "squid-doc-snippets-" });
  try {
    const cheatsheet = await Deno.readTextFile(
      new URL("../../CHEATSHEET.md", import.meta.url),
    );
    const cheatsheetBlocks = [
      ...cheatsheet.matchAll(/```squid\n([\s\S]*?)```/g),
    ]
      .map((m) => m[1]);
    ok(
      cheatsheetBlocks.length >= 4,
      "Expected squid examples in CHEATSHEET.md",
    );

    for (let i = 0; i < cheatsheetBlocks.length; i++) {
      const file = join(tempDir, `cheatsheet_${i}.sq`);
      await Deno.writeTextFile(file, cheatsheetBlocks[i]);
      const res = await runCompilerRaw("check-project", file);
      equal(
        res.code,
        0,
        `CHEATSHEET.md block #${i} failed to compile:\n${
          cheatsheetBlocks[i]
        }\n${JSON.stringify(res.diagnostics, null, 2)}`,
      );
    }

    const skill = await Deno.readTextFile(
      new URL("../../skills/squid-diagnostics/SKILL.md", import.meta.url),
    );
    const afterBlocks: string[] = [];
    for (const m of skill.matchAll(/```squid\n([\s\S]*?)```/g)) {
      const idx = m[1].indexOf("// After\n");
      if (idx >= 0) {
        const after = m[1].slice(idx + "// After\n".length).trim() + "\n";
        if (
          /^(?:type|func|const|import|io|#kernel|#process)\b/.test(after)
        ) {
          afterBlocks.push(after);
        }
      }
    }
    ok(
      afterBlocks.length >= 15,
      `Expected full-module // After snippets in SKILL.md, got ${afterBlocks.length}`,
    );
    for (let i = 0; i < afterBlocks.length; i++) {
      const file = join(tempDir, `skill_after_${i}.sq`);
      await Deno.writeTextFile(file, afterBlocks[i]);
      const res = await runCompilerRaw("check-project", file);
      equal(
        res.code,
        0,
        `skills/squid-diagnostics/SKILL.md // After block #${i} failed to compile:\n${
          afterBlocks[i]
        }\n${JSON.stringify(res.diagnostics, null, 2)}`,
      );
    }
  } finally {
    await Deno.remove(tempDir, { recursive: true });
  }
});
