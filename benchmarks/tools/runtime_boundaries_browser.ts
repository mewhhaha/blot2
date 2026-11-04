/** Isolated headless Firefox replay of the exact pinned kernel binaries. */
import { parseArgs } from "node:util";
import { resolve } from "node:path";

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    firefox: { type: "string", default: "firefox" },
    samples: { type: "string", default: "31" },
    batch: { type: "string", default: "5" },
  },
});
if (positionals.length !== 1) {
  throw new Error("Pass the runtime_boundaries.ts output directory");
}
const directory = resolve(positionals[0]);
const reference = JSON.parse(
  await Deno.readTextFile(`${directory}/results.json`),
);
if (!reference.complete) throw new Error("Kernel qualification is incomplete");
const samples = Number(values.samples), batch = Number(values.batch);
if (
  !Number.isSafeInteger(samples) || samples < 3 ||
  !Number.isSafeInteger(batch) || batch < 1
) throw new Error("Invalid samples/batch");
const profile = await Deno.makeTempDir({ prefix: "blot-firefox-benchmark-" });
await Deno.writeTextFile(
  `${profile}/user.js`,
  'user_pref("privacy.reduceTimerPrecision", false);\nuser_pref("browser.shell.checkDefaultBrowser", false);\n',
);
let finish!: (report: Record<string, unknown>) => void;
const completed = new Promise<Record<string, unknown>>((resolve) => {
  finish = resolve;
});
const html =
  `<!doctype html><meta charset="utf-8"><title>Blot runtime benchmark</title><pre id="status">Running…</pre><script type="module">
const check = (condition, message) => { if (!condition) throw Error(message); };
try {
  const reference = await (await fetch("/reference")).json();
  const guests = {};
  for (const side of ["baseline", "candidate"]) {
    const bytes = await (await fetch("/" + side + ".wasm")).arrayBuffer();
    const digest = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(x => x.toString(16).padStart(2, "0")).join("");
    check(digest === reference.builds.find(x => x.side === side).wasm_sha256, "Wasm hash mismatch");
    guests[side] = (await WebAssembly.instantiate(bytes)).instance.exports;
  }
  const invoke = (side, row) => {
    const raw = guests[side]; raw["blot:ownership_enter"]();
    let outcome = 1;
    try { check((raw[row.name](row.argument) >>> 0) === (row.expected >>> 0), row.name + " result"); outcome = 0; }
    finally { raw["blot:ownership_leave"](outcome); }
    check(raw["blot:rc_roots"].value === 0 and raw["blot:rc_leases"].value === 0, "Owners remain");
  };
  const report = {format: 1, complete: false, engine: navigator.userAgent, scope: "Headless Firefox, isolated profile with timer rounding disabled. Uninstrumented Wasm and ownership enter/leave. Same pinned binaries and counter budgets as the native-host suite.", samples: ${samples}, batch: ${batch}, builds: reference.builds, rows: []};
  for (const row of reference.rows) {
    const measured = {};
    for (const side of ["baseline", "candidate"]) {
      for (let i = 0; i < 10; i++) invoke(side, row);
      const before = Object.fromEntries(Object.keys(row[side].counts).map(key => [key, guests[side]["blot:" + key].value]));
      invoke(side, row);
      const counts = Object.fromEntries(Object.entries(before).map(([key, value]) => [key, (guests[side]["blot:" + key].value - value) >>> 0]));
      check(JSON.stringify(counts) === JSON.stringify(row[side].counts), row.name + " counters");
      measured[side] = {counts, samples_ms: []};
    }
    // Headless browser clocks can still quantize very short samples. Use the
    // same calibrated batch for both sides, targeting 10 ms on the faster one.
    let rowBatch = ${batch};
    for (let attempt = 0; attempt < 8; attempt++) {
      const elapsed = [];
      for (const side of ["baseline", "candidate"]) {
        const start = performance.now();
        for (let i = 0; i < rowBatch; i++) invoke(side, row);
        elapsed.push(performance.now() - start);
      }
      const fastest = Math.min(...elapsed);
      if (fastest >= 10 or rowBatch >= 100000) break;
      rowBatch = Math.min(100000, Math.max(rowBatch + 1, Math.ceil(rowBatch * Math.min(10, 12 / Math.max(fastest, 0.01)))));
    }
    for (let round = 0; round < ${samples}; round++) {
      for (const side of round % 2 ? ["candidate", "baseline"] : ["baseline", "candidate"]) {
        const start = performance.now();
        for (let i = 0; i < rowBatch; i++) invoke(side, row);
        measured[side].samples_ms.push((performance.now() - start) / rowBatch);
      }
    }
    for (const side of ["baseline", "candidate"]) measured[side].median_ms = [...measured[side].samples_ms].sort((a, b) => a - b)[Math.floor(${samples} / 2)];
    report.rows.push({name: row.name, argument: row.argument, expected: row.expected, batch: rowBatch, ...measured});
    document.querySelector("#status").textContent = row.name + " " + row.argument;
  }
  report.complete = true;
  await fetch("/result", {method: "POST", body: JSON.stringify(report)});
} catch (error) { await fetch("/result", {method: "POST", body: JSON.stringify({complete: false, error: String(error), stack: error.stack})}); }
</script>`;
const server = Deno.serve(
  { hostname: "127.0.0.1", port: 0 },
  async (request) => {
    const path = new URL(request.url).pathname;
    if (path === "/result" && request.method === "POST") {
      finish(await request.json());
      return new Response("ok");
    }
    if (path === "/reference") return Response.json(reference);
    if (path === "/baseline.wasm" || path === "/candidate.wasm") {
      return new Response(await Deno.readFile(directory + path), {
        headers: { "Content-Type": "application/wasm" },
      });
    }
    if (path === "/") {
      return new Response(html, {
        headers: { "Content-Type": "text/html; charset=utf-8" },
      });
    }
    return new Response("Not found", { status: 404 });
  },
);
const child = new Deno.Command(values.firefox!, {
  args: [
    "--headless",
    "--no-remote",
    "--profile",
    profile,
    `http://127.0.0.1:${server.addr.port}/`,
  ],
  stdout: "null",
  stderr: "piped",
}).spawn();
const output = child.output();
const timeout = setTimeout(
  () =>
    finish({
      complete: false,
      error: "Firefox benchmark timed out after five minutes",
    }),
  300_000,
);
try {
  const report = await Promise.race([
    completed,
    output.then((result) => ({
      complete: false,
      error: `Firefox exited ${result.code}`,
      stderr: new TextDecoder().decode(result.stderr),
    })),
  ]);
  await Deno.writeTextFile(
    `${directory}/firefox.json`,
    JSON.stringify(report, null, 2) + "\n",
  );
  if (!report.complete) throw new Error(JSON.stringify(report));
  console.log(`${directory}/firefox.json: complete`);
} finally {
  clearTimeout(timeout);
  try {
    child.kill("SIGTERM");
  } catch { /* Already exited. */ }
  await output;
  await server.shutdown();
  await Deno.remove(profile, { recursive: true });
}
