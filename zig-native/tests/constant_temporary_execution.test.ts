import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const bodies = [
  `  let metadata = @effect.of described
  let cost = @effect.count metadata`,
  `  let provider = @effect.provider Read (func () => return base)
  let cost = base`,
  `  let cost = do (@effect.provider Read (func () => return base)):
    break base`,
  `  let cost = base
  for request in @requests (@computation (func () => return base)):
    case request of
      effect Read () =>
        yield base
      complete result =>
        cost := result
        break`,
  `  let wrapped = do (@do.monad Box):
    break base
  let cost = case wrapped of
    $Box value => value`,
  `  let (_, cost) = @state.run base (func () => return base)`,
  `  let cost = do (@effect.provider Read (func () => return base)):
    use result <- Read ()
    break result`,
  `  let pending = delayed base
  let cost = @demand pending
  let again = @demand pending`,
  `  let cost = @effect.scope (func (state: State U32) => return base)`,
  `  let cost = @code.run (@code.quote (@code.lift base))`,
];
function logic(base = "1", row = "Read") {
  return `effect Read: Unit -> U32
effect Other: Unit -> U32
type State a is effect = {get: Unit -> a, set: a -> Unit}
const described: Unit -> U32 ! {${row}} = func () => return Read ()
type Box a is data = $Box a
const Box.pure = func (value: U32) => return $Box value
const delayed = func ~value => return value
const base = ${base}
${
    bodies.map((body, index) =>
      `const expensive_${index} = do:
${body}
  for index in 0..256:
    cost := @u32.add self 1
  break cost
`
    ).join("\n")
  }
const values = #[${bodies.map((_, index) => `expensive_${index}`).join(", ")}]
`;
}
Deno.test("constant receipts transport dead immutable temporaries while actual Scope demand provider and stage execution stay fresh", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-constant-temporary-",
  });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/logic.blot`;
  const archive = `${directory}/deps.blotdep`;
  const sources = (seed = "2", base = "1", row = "Read") => ({
    [entry]: `import {values} from "./logic"
entry const answer = func () => return values
entry const sibling = ${seed}
`,
    [dependency]: logic(base, row),
  });
  async function run(
    bytes: Uint8Array<ArrayBuffer>,
    base: string,
    row: string,
  ) {
    const expected = new Uint32Array(bodies.length).fill(Number(base) + 256);
    expected[0] = 257;
    if (row === "Read,Other") expected[0] = 258;
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(bytes, { asynchronous });
      try {
        if (asynchronous) {
          assert.deepEqual(await guest.callAsync("answer", null), expected);
        } else assert.deepEqual(guest.call("answer", null), expected);
      } finally {
        guest.dispose();
      }
    }
  }
  try {
    for (const [path, text] of Object.entries(sources())) {
      await Deno.writeTextFile(path, text);
    }
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, archive, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
      } as const;
      for (const dependencies of [undefined, archive]) {
        const retained = await createZigProjectCompiler({
          ...options,
          dependencies,
        });
        let checkpoint: Uint8Array<ArrayBuffer> | undefined;
        let finalBytes: Uint8Array<ArrayBuffer> | undefined;
        try {
          const revisions = [
            ["2", "1", "Read"],
            ["3", "1", "Read"],
            ["4", "2", "Read"],
            ["missing", "2", "Read"],
            ["5", "missing", "Read"],
            ["6", "2", "Read,Other"],
            ["7", "1", "Read"],
            ["8", "1", "Read"],
          ] as const;
          for (const [revision, [seed, base, row]] of revisions.entries()) {
            const fresh = await createZigProjectCompiler(options);
            try {
              const text = sources(seed, base, row);
              const expected = await fresh.build({ sources: text });
              const actual = await retained.build({ sources: text });
              assert.equal(actual.success, expected.success);
              if (!actual.success || !expected.success) {
                assert.ok(!actual.success && !expected.success);
                assert.ok(seed === "missing" || base === "missing");
                assert.deepEqual(actual.diagnostics, expected.diagnostics);
                assert.deepEqual(await retained.exportCheckpoint(), checkpoint);
                continue;
              }
              assert.deepEqual(actual.bytes, expected.bytes);
              assert.equal(
                actual.stats.nativeWorkSteps,
                expected.stats.nativeWorkSteps,
              );
              if (revision === 1 || revision === 7) {
                const receipts = actual.stats.constantReceipts as Record<
                  string,
                  number
                >;
                assert.equal(receipts.reused, 5, JSON.stringify(receipts));
                assert.ok(
                  receipts.source_steps_replayed > 8000,
                  JSON.stringify(receipts),
                );
              }
              await run(actual.bytes, base, row);
              checkpoint = await retained.exportCheckpoint();
              finalBytes = actual.bytes;
            } finally {
              await fresh.dispose();
            }
          }
        } finally {
          await retained.dispose();
        }
        assert.ok(checkpoint && finalBytes);
        const restarted = await createZigProjectCompiler({
          ...options,
          checkpoint,
        });
        try {
          const actual = await restarted.build({ sources: sources("8") });
          assert.ok(actual.success, JSON.stringify(actual));
          assert.deepEqual(actual.bytes, finalBytes);
          await run(actual.bytes, "1", "Read");
        } finally {
          await restarted.dispose();
        }
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
