// Capture the read-only timing WebSocket of Zig 0.17.0's `--time-report`
// web UI. The server remains alive after building; stop its build command
// separately after this collector reports success. Never sends a rebuild.
// Usage: deno run -A scripts/bench/zig_time_report.ts ws://[::1]:PORT/ NEW_OUTPUT
// Layout follows lib/std/Build/abi.zig and lib/build-web/time_report.zig.
const [url, out] = Deno.args;
if (!url || !out) {
  throw new Error("Expected WebSocket URL and a new output directory");
}
try {
  await Deno.stat(out);
  throw new Error("Choose a new output directory");
} catch (error) {
  if (!(error instanceof Deno.errors.NotFound)) throw error;
}
type Report = {
  step: number;
  name: string;
  total_ns: number;
  llvm?: boolean;
  stats?: Record<string, number>;
  decls?: number;
};
await Deno.mkdir(out, { recursive: true });
const ws = new WebSocket(url);
ws.binaryType = "arraybuffer";
const reports: Report[] = [];
let names: string[] = [];
let statuses: number[] = [];
let idle = false;
let completed = false;
let timer: ReturnType<typeof setTimeout> | undefined;
const enc = new TextDecoder();
let serial = 0;
function done() {
  if (!idle) return;
  const reported = new Set(reports.map((report) => report.step));
  const success = names.length > 0 && statuses.length === names.length &&
    statuses.every((status) => status === 2) &&
    reports.length === names.length && reported.size === names.length &&
    names.every((_, step) => reported.has(step));
  completed = true;
  ws.close();
  Deno.writeTextFileSync(
    out + "/report.json",
    JSON.stringify(
      {
        zig: "0.17.0",
        steps: names.map((name, i) => ({ name, status: statuses[i] })),
        reports,
        success,
      },
      null,
      2,
    ) + "\n",
  );
  console.log(
    JSON.stringify({
      steps: names.length,
      reports: reports.length,
      success,
    }),
  );
  Deno.exit(success ? 0 : 1);
}
ws.onmessage = (e) => {
  const b = new Uint8Array(e.data);
  const v = new DataView(b.buffer);
  if (b.length === 0) throw new Error("Empty timing message");
  const u32 = (at: number) => v.getUint32(at, true);
  const u64 = (at: number) => Number(v.getBigUint64(at, true));
  Deno.writeFileSync(
    `${out}/${String(serial++).padStart(3, "0")}-tag${b[0]}.bin`,
    b,
  );
  if (b[0] === 0) {
    idle = b[1] === 0 || b[1] === 1;
    let p = 16;
    const lengths = Array.from({ length: u32(12) }, () => {
      const n = u32(p);
      p += 4;
      return n;
    });
    names = lengths.map((n) => {
      const s = enc.decode(b.slice(p, p + n));
      p += n;
      return s;
    });
    statuses = names.map((_, i) => (b[p + (i >> 2)] >> (2 * (i % 4))) & 3);
  }
  if (b[0] === 1) idle = b[1] === 0 || b[1] === 1;
  if (b[0] === 2) statuses[u32(1)] = b[5] & 3;
  if (b[0] === 6) {
    reports.push({ step: u32(1), name: names[u32(1)], total_ns: u64(5) });
  }
  if (b[0] === 7) {
    let p = 6;
    const stats: Record<string, number> = {};
    for (
      const k of [
        "n_reachable_files",
        "n_imported_files",
        "n_generic_instances",
        "n_inline_calls",
      ]
    ) {
      stats[k] = u32(p);
      p += 4;
    }
    for (
      const k of [
        "cpu_ns_parse",
        "cpu_ns_astgen",
        "cpu_ns_sema",
        "cpu_ns_codegen",
        "cpu_ns_link",
        "real_ns_files",
        "real_ns_decls",
        "real_ns_llvm_emit",
        "real_ns_link_flush",
      ]
    ) {
      stats[k] = u64(p);
      p += 8;
    }
    const total_ns = u64(p);
    p += 8;
    const llvmLen = u32(p), filesLen = u32(p + 4), declsLen = u32(p + 8);
    p += 12;
    const llvm = enc.decode(b.slice(p, p + llvmLen));
    p += llvmLen;
    function string() {
      const end = b.indexOf(0, p);
      if (end < 0) throw Error("truncated string");
      const value = enc.decode(b.slice(p, end));
      p = end + 1;
      return value;
    }
    const files = Array.from({ length: filesLen }, string);
    const decls = Array.from({ length: declsLen }, () => {
      const name = string();
      const file = files[u32(p)],
        sema_count = u32(p + 4),
        sema_ns = u64(p + 8),
        codegen_ns = u64(p + 16),
        link_ns = u64(p + 24);
      p += 32;
      return { name, file, sema_count, sema_ns, codegen_ns, link_ns };
    });
    if (p !== b.length) throw Error(`unparsed bytes ${p}/${b.length}`);
    Deno.writeTextFileSync(`${out}/step-${u32(1)}-llvm.txt`, llvm);
    Deno.writeTextFileSync(
      `${out}/step-${u32(1)}-decls.json`,
      JSON.stringify(decls),
    );
    reports.push({
      step: u32(1),
      name: names[u32(1)],
      llvm: !!(b[5] & 1),
      total_ns,
      stats,
      decls: decls.length,
    });
  }
  if (timer !== undefined) clearTimeout(timer);
  if (idle) timer = setTimeout(done, 1000);
};
ws.onerror = (e) => {
  console.error(e);
  Deno.exit(1);
};
ws.onclose = () => {
  if (!completed) {
    console.error("Timing server closed before a complete report was captured");
    Deno.exit(1);
  }
};
