// Inventory the actual registered names without executing or modifying their
// bodies. All four heavy cases are scheduled separately by tools/partition.py.
// A new/renamed case must fail this check, never be silently filtered out.
const expected = [1, 2, 4, 8].map((threads) =>
  `native ${threads}-thread codegen compiles only independent cache misses`
);
const names: string[] = [];
Object.defineProperty(Deno, "test", {
  value(name: unknown, body: unknown) {
    if (typeof name !== "string" || typeof body !== "function") {
      throw new Error(
        "Update the codegen partition inventory for the new test registration",
      );
    }
    names.push(name);
  },
});
const workload = new URL(
  "../compiler/codegen_native_parallel.test.ts",
  import.meta.url,
);
await import(workload.href);
if (JSON.stringify(names.toSorted()) !== JSON.stringify(expected.toSorted())) {
  throw new Error(
    `Codegen partition must cover every registered case: ${
      JSON.stringify(names)
    }`,
  );
}
console.log(`Verified all ${names.length} separately scheduled codegen cases.`);
