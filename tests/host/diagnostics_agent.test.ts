import { equal, match } from "node:assert/strict";
import { join } from "node:path";
import { runCli } from "../../host/cli.ts";
import {
  canonicalDiagnosticCode,
  DIAGNOSTIC_CATALOG,
  formatDiagnostic,
  formatExplanation,
  type RawDiagnosticRecord,
} from "../../host/diagnostics.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;

async function runCapturedCli(
  args: string[],
): Promise<{ code: number; stdout: string; stderr: string }> {
  const stdoutLines: string[] = [];
  const stderrLines: string[] = [];
  const origLog = console.log;
  const origError = console.error;
  console.log = (...values: unknown[]) => {
    stdoutLines.push(values.map(String).join(" "));
  };
  console.error = (...values: unknown[]) => {
    stderrLines.push(values.map(String).join(" "));
  };
  try {
    const code = await runCli(executable, args);
    return {
      code,
      stdout: stdoutLines.join("\n"),
      stderr: stderrLines.join("\n"),
    };
  } finally {
    console.log = origLog;
    console.error = origError;
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
      new RegExp(`skills/blot-diagnostics/SKILL\\.md#${code}`),
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
  match(cheatsheetRun.stdout, /# Blot vNext Cheatsheet/);
  match(cheatsheetRun.stdout, /#\[1, 2, 3\]/);
});

Deno.test("diagnostics: UTF-8 byte offsets map to exact line and code-point column", () => {
  const source = "entry func main (): U32 =>\n  // café ✓\n  return bad_name\n";
  const bytes = new TextEncoder().encode(source);
  const start = new TextEncoder().encode(
    "entry func main (): U32 =>\n  // café ✓\n  return ",
  ).length;
  const end = start + "bad_name".length;
  equal(bytes.length > end, true);
  const record: RawDiagnosticRecord = {
    filename: "unicode.blot",
    code: "unknown_value",
    start,
    end,
    message: "Unknown value `bad_name`; did you mean `good_name`?",
  };
  const rendered = formatDiagnostic(record, { source });
  match(rendered, /\[UNKNOWN_VALUE\]/);
  match(rendered, /in unicode\.blot › entry func main/);
  match(rendered, /at unicode\.blot:3:10/);
  match(rendered, /3 \|   return bad_name/);
  match(rendered, /\^\^\^\^\^\^\^\^ did you mean `good_name`\?/);
  match(rendered, /fix: Replace `bad_name` with `good_name`\./);
  match(rendered, /doc: blot explain UNKNOWN_VALUE/);
});

Deno.test("diagnostics: real compiler CLI reports Solid-2 style blame and fixes across agent pitfalls", async () => {
  const tempDir = await Deno.makeTempDir({ prefix: "blot-diag-agent-" });
  try {
    const cases: {
      name: string;
      cmd: "check" | "build";
      source: string;
      patterns: RegExp[];
    }[] = [
      {
        name: "fn_keyword.blot",
        cmd: "check",
        source: "fn add (a: U32) -> (b: U32): U32 => return a + b\n",
        patterns: [
          /\[SYNTAX_ERROR\]/,
          /at .*fn_keyword\.blot:1:1/,
          /fix: Blot uses `func`, not `fn`/,
          /doc: blot explain SYNTAX_ERROR/,
        ],
      },
      {
        name: "bare_list.blot",
        cmd: "check",
        source: "entry func main (): #[U32] => return [1, 2, 3]\n",
        patterns: [
          /\[UNSUPPORTED_EXPRESSION\]/,
          /in bare_list\.blot › entry func main/,
          /at .*bare_list\.blot:1:38/,
          /use `#\[\.\.\.\]` here/,
          /fix: Replace bare `\[\.\.\.\]` with `#\[\.\.\.\]`/,
          /doc: blot explain UNSUPPORTED_EXPRESSION/,
        ],
      },
      {
        name: "missing_dollar.blot",
        cmd: "check",
        source:
          "type Opt is data = $Some U32 | $Nothing\nentry func main (): Opt => return Some 1\n",
        patterns: [
          /\[UNKNOWN_VALUE\]/,
          /in missing_dollar\.blot › entry func main/,
          /at .*missing_dollar\.blot:2:35/,
          /add `\$` -> `\$Some`/,
          /fix: Prefix the data constructor with `\$`: use `\$Some`/,
        ],
      },
      {
        name: "typo_name.blot",
        cmd: "check",
        source:
          "func compute_total (x: U32): U32 => return x + 1\nentry func main (): U32 => return compute_totla 5\n",
        patterns: [
          /\[UNKNOWN_VALUE\]/,
          /in typo_name\.blot › entry func main/,
          /at .*typo_name\.blot:2:35/,
          /did you mean `compute_total`\?/,
          /fix: Replace `compute_totla` with `compute_total`\./,
        ],
      },
      {
        name: "missing_field.blot",
        cmd: "check",
        source:
          "type Pt = { x: U32, y: U32 }\nentry func main (): U32 =>\n  let p: Pt = { x: 1, y: 2 }\n  return p.z\n",
        patterns: [
          /\[MISSING_MEMBER\]/,
          /Type `\{ x: U32, y: U32 \}` has no field or member `\.z`/,
          /in missing_field\.blot › entry func main/,
          /at .*missing_field\.blot:4:10/,
          /fix: Available fields on `\{ x: U32, y: U32 \}`: `x`, `y`\./,
        ],
      },
      {
        name: "type_mismatch.blot",
        cmd: "check",
        source: "entry func main (): U32 => return 1.5\n",
        patterns: [
          /\[TYPE_MISMATCH\]/,
          /F32.*U32|U32.*F32/,
          /fix: Blot has no implicit numeric conversions/,
          /doc: blot explain TYPE_MISMATCH/,
        ],
      },
      {
        name: "spent_value.blot",
        cmd: "build",
        source:
          "func consume (xs: own #[U32]): U32 => return xs.length\nentry func main (): U32 =>\n  let a = #[1, 2, 3]\n  let n = consume a\n  return n + a.length\n",
        patterns: [
          /\[SPENT_VALUE\] `a` was already moved at line 4/,
          /in spent_value\.blot › entry func main/,
          /at .*spent_value\.blot:5:14/,
          /--------- `a` moved here/,
          /\^\^\^\^\^\^\^\^ `a` used after move/,
          /fix: Pass `a\.copy` at line 4/,
          /doc: blot explain SPENT_VALUE/,
        ],
      },
      {
        name: "aliased_update.blot",
        cmd: "build",
        source:
          "entry func main (): U32 =>\n  let a = #[1, 2, 3]\n  let b = a\n  a[0] := 99\n  return a[0] + b[0]\n",
        patterns: [
          /\[ALIASED_UPDATE\] Cannot mutate `a` in place while `b` still borrows it/,
          /in aliased_update\.blot › entry func main/,
          /at .*aliased_update\.blot:4:3/,
          /--------- borrowed by `b` here/,
          /\^\^\^\^\^\^\^\^\^\^ mutated while borrowed/,
          /fix: Snapshot with `let b = a\.copy` \(line 3\)/,
          /doc: blot explain ALIASED_UPDATE/,
        ],
      },
      {
        name: "param_update.blot",
        cmd: "build",
        source:
          "func bad (a: #[U32]): #[U32] =>\n  a[0] := 99\n  return a\nentry func main (): U32 => return (bad #[1, 2])[0]\n",
        patterns: [
          /\[ALIASED_UPDATE\] Cannot mutate borrowed parameter `a` in place without `own`/,
          /in param_update\.blot › func bad/,
          /at .*param_update\.blot:2:3/,
          /----------- borrowed parameter \(not `own`\)/,
          /fix: Mark the parameter `own`/,
        ],
      },
      {
        name: "unhandled_effect.blot",
        cmd: "build",
        source:
          "type Clock is effect = { now: Unit -> U32 }\nentry func main (): U32 =>\n  use t <- Clock.now ()\n  return t\n",
        patterns: [
          /\[ENTRY_TYPE\] Entry function leaves effect `Clock\.now` unhandled/,
          /in unhandled_effect\.blot › entry func main/,
          /unhandled effect `Clock\.now`/,
          /fix: Handle `Clock\.now` inside the entry function with `with Clock = \{ now:/,
          /doc: blot explain ENTRY_TYPE/,
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
