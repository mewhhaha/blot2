import { strict as assert } from "node:assert";
import { compilerLease } from "./compiler_lease.ts";
import {
  devCheckAreas,
  type NativeTestRecord,
  verifyGuestResults,
  verifyNativeSelection,
} from "./dev_check_areas.ts";

Deno.test("guest evidence rejects zero-test filters, skipped tests and missing files", () => {
  const xml =
    '<testsuites><testsuite><testcase name="selected client" classname="./client.test.ts"></testcase></testsuite></testsuites>';
  assert.equal(
    verifyGuestResults(xml, ["client.test.ts"], ["selected client"]).length,
    1,
  );
  assert.throws(() =>
    verifyGuestResults('<testsuites tests="0"/>', ["client.test.ts"])
  );
  assert.throws(() =>
    verifyGuestResults(xml.replace("</testcase>", "<skipped/></testcase>"), [
      "client.test.ts",
    ])
  );
  assert.throws(() => verifyGuestResults(xml, ["missing.test.ts"]));
  assert.throws(() =>
    verifyGuestResults(xml, ["client.test.ts"], ["missing client"])
  );
  const filtered = xml.replace(
    "</testsuite>",
    '<testcase name="other client" classname="./client.test.ts"><skipped/></testcase></testsuite>',
  );
  assert.equal(
    verifyGuestResults(filtered, ["client.test.ts"], ["selected client"])
      .length,
    1,
  );
  assert.throws(() =>
    verifyGuestResults(filtered, ["client.test.ts"], ["other client"])
  );
});

Deno.test("development results reject omissions, skips, duplicates, wrong fault mode and resource errors", () => {
  const record: NativeTestRecord = {
    name: "law",
    duration_ns: 1,
    status: "passed",
    leaks: 0,
    logged_errors: 0,
    allocation_failures: "sampled",
    sweeps: {
      full_sweeps: 0,
      sampled_sweeps: 1,
      discovered_allocations: 9,
      fault_runs: 3,
    },
  };
  verifyNativeSelection([record], ["law"], "sampled");
  for (
    const records of [
      [],
      [record, record],
      [{ ...record, name: "other" }],
      [{ ...record, status: "skipped" }],
      [{ ...record, leaks: 1 }],
      [{ ...record, logged_errors: 1 }],
      [{ ...record, allocation_failures: "full" }],
      [{ ...record, duration_ns: NaN }],
    ]
  ) {
    assert.throws(() => verifyNativeSelection(records, ["law"], "sampled"));
  }
  // Keep the positive executable-reuse contract that rejected the earlier fix.
  assert(
    devCheckAreas["static-sharing"].native.some((name) =>
      name.includes(
        "static captured value graphs admit executable closure replay independently of principal mappings",
      )
    ),
  );
});

Deno.test("compiler artifact leases fail immediately when busy and release after use", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-compiler-lease-" });
  try {
    {
      await using lease = await compilerLease(directory);
      await assert.rejects(
        compilerLease(directory),
        /busy.*no build was queued/,
      );
    }
    await using next = await compilerLease(directory);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("concurrent stale-lease recovery grants only one compiler artifact owner", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-stale-lease-" });
  try {
    const child = new Deno.Command(Deno.execPath(), {
      args: ["eval", ""],
      stdout: "null",
      stderr: "null",
    }).spawn();
    await child.status;
    await Deno.mkdir(`${directory}/.zig-cache/compiler-check.lock`, {
      recursive: true,
    });
    await Deno.writeTextFile(
      `${directory}/.zig-cache/compiler-check.lock/owner.json`,
      JSON.stringify({ pid: child.pid, started: "stale fixture" }),
    );
    const results = await Promise.allSettled([
      compilerLease(directory),
      compilerLease(directory),
    ]);
    const owners = results.flatMap((result) =>
      result.status === "fulfilled" ? [result.value] : []
    );
    try {
      assert.equal(owners.length, 1);
    } finally {
      for (const owner of owners) await owner[Symbol.asyncDispose]();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
