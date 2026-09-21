// Linux retained-process control: compare every artifact and report mappings,
// so queue residency can be distinguished from live heap/cache growth.
import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { arithmeticSource } from "./benchmark_workloads.ts";
import { createSourceFrontend } from "./source_frontend.ts";
import { NativeProcess } from "./native_process.ts";
import { decodeNativeResponse } from "./native_protocol.ts";

const [
  report = "build/native-memory.json",
  executable = "generated/compiler/blotc",
  count = "200",
  cores = "8",
] = Deno.args;
const requests = Number(count);
const threads = Number(cores);
ok(Deno.build.os === "linux", "Memory mapping accounting requires Linux");
ok(
  Deno.args.length <= 4,
  "Usage: native_memory_bench.ts [report executable requests threads]",
);
ok(Number.isInteger(requests) && requests >= 50);
ok(Number.isInteger(threads) && threads >= 1 && threads <= 64);
const frontend = await createSourceFrontend({ prelude: "none" });
const prepared = await frontend.prepareNative(
  arithmeticSource("balanced", false),
);
const payload = prepared.encode("compile", 10000n);
frontend.dispose();
const native = await NativeProcess.start({
  threads,
  executable: pathToFileURL(resolve(executable)),
});
const snapshots = [];
const checkpoints = new Set([1, 3, 10, 50, 100, requests]);
let expected: ReturnType<typeof decodeNativeResponse> | undefined;
try {
  for (let request = 1; request <= requests; request++) {
    const actual = decodeNativeResponse(await native.request(payload));
    ok(actual.operation === "compile");
    if (expected) equal(actual, expected);
    else expected = actual;
    if (!checkpoints.has(request)) continue;
    const smaps = await Deno.readTextFile(`/proc/${native.pid}/smaps`);
    const regions = smaps.split(/(?=^[\da-f]+-[\da-f]+ )/m).filter(Boolean).map(
      (region) => ({
        mapping: region.split("\n")[0],
        rss_kib: Number(/^Rss:\s+(\d+)/m.exec(region)?.[1] ?? 0),
      }),
    ).filter((region) => region.rss_kib > 0).sort((a, b) =>
      b.rss_kib - a.rss_kib
    );
    const rss_kib = regions.reduce((sum, region) => sum + region.rss_kib, 0);
    snapshots.push({ request, rss_kib, regions });
    console.log(`request ${request}: ${(rss_kib / 1024).toFixed(2)} MiB`);
  }
  await Deno.mkdir(resolve(report, ".."), { recursive: true });
  await Deno.writeTextFile(
    report,
    JSON.stringify(
      { executable, threads, requests, artifact_parity: true, snapshots },
      null,
      2,
    ) + "\n",
  );
} finally {
  await native.dispose();
}
