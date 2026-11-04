/** Diagnostic memory-traffic instrumentation; never use its output for timing. */
import { strict as assert } from "node:assert";
import wabt from "npm:wabt@1.0.39";

const factory = await wabt();
const names = ["copy", "fill", "read", "write"] as const;
export function instrumentMemoryTraffic(
  bytes: Uint8Array<ArrayBuffer>,
): Uint8Array<ArrayBuffer> {
  const module = factory.readWasm(bytes, { readDebugNames: false });
  let text: string;
  try {
    text = module.toText({ foldExprs: false, inlineExport: false });
  } finally {
    module.destroy();
  }
  assert(!text.includes("$__qual_"));
  const lines = text.trimEnd().split("\n"), result: string[] = [];
  let functionStart = -1, declarations = false, hasCopyLocal = false;
  function local() {
    if (hasCopyLocal) return;
    result.splice(functionStart, 0, "    (local $__qual_length i32)");
    hasCopyLocal = true;
  }
  function add(counter: typeof names[number], bytes: number | null) {
    if (bytes === null) {
      local();
      result.push(
        "    local.tee $__qual_length",
        "    local.get $__qual_length",
        "    i64.extend_i32_u",
      );
    } else result.push(`    i64.const ${bytes}`);
    result.push(
      `    global.get $__qual_${counter}`,
      "    i64.add",
      `    global.set $__qual_${counter}`,
    );
  }
  for (const line of lines) {
    if (/^  \(func\b/.test(line)) {
      result.push(line);
      functionStart = result.length;
      declarations = true;
      hasCopyLocal = false;
      continue;
    }
    if (functionStart >= 0 && declarations) {
      if (/^    \(local\b/.test(line)) {
        result.push(line);
        functionStart = result.length;
        continue;
      }
      declarations = false;
    }
    const op = /^\s+([\w.]+)(?:\s|\)|$)/.exec(line)?.[1];
    if (op === "memory.copy") add("copy", null);
    else if (op === "memory.fill") add("fill", null);
    else if (op && /^(i32|i64|f32|f64|v128)\.(load|store)/.test(op)) {
      const match =
        /^(i32|i64|f32|f64|v128)\.(load|store)(?:(8|16|32)(?:_s|_u))?$/.exec(
          op,
        );
      assert(match, `Unaccounted memory instruction ${op}`);
      add(
        match[2] === "load" ? "read" : "write",
        Number(match[3] ?? match[1].slice(1)) / 8,
      );
    }
    result.push(line);
  }
  // Append declarations just before the module's closing delimiter, preserving
  // any closing function/type delimiter on the same last line.
  const last = result.pop()!;
  assert(last.endsWith(")"));
  result.push(last.slice(0, -1));
  for (const name of names) {
    result.push(
      `  (global $__qual_${name} (export "qual:${name}") (mut i64) (i64.const 0))`,
    );
  }
  result.push(")");
  const parsed = factory.parseWat("memory-traffic", result.join("\n"));
  try {
    parsed.validate();
    const output = new Uint8Array(
      parsed.toBinary({ canonicalize_lebs: true }).buffer,
    );
    assert(WebAssembly.validate(output));
    return output;
  } finally {
    parsed.destroy();
  }
}

export function traffic(exports: WebAssembly.Exports) {
  return Object.fromEntries(
    names.map(
      (name) => [
        name,
        Number((exports[`qual:${name}`] as WebAssembly.Global).value),
      ],
    ),
  );
}

if (import.meta.main) {
  const parsed = factory.parseWat(
    "control",
    `(module
    (memory 1)
    (func (export "check") (param i32) (result i32) (local i32)
      i32.const 0 local.get 0 i32.store
      i32.const 4 i32.const 0 i32.const 4 memory.copy
      i32.const 8 i32.const 0 i32.const 8 memory.fill
      i32.const 4 i32.load))`,
  );
  const original = new Uint8Array(parsed.toBinary({}).buffer);
  parsed.destroy();
  const instance = new WebAssembly.Instance(
    new WebAssembly.Module(instrumentMemoryTraffic(original)),
  );
  assert.equal((instance.exports.check as (n: number) => number)(17), 17);
  assert.deepEqual(traffic(instance.exports), {
    copy: 4,
    fill: 8,
    read: 4,
    write: 4,
  });
  console.log("Memory traffic instrumentation control passed");
}
