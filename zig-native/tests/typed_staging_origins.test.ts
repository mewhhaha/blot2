import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out-dev/bin/blotc", import.meta.url).pathname;
const producerSource =
  "const make = func (divisor: U32) => return @code.quote (@u32.div 42 (@code.lift divisor))\n";
const consumerSource = `import {make} from "./producer"
const first = make 1
const second = make 0
const choices = {good: first, bad: second}
entry const answer = func () => return @code.run choices.good
`;

Deno.test("generated diagnostics retain the selected generator through imports records and recovery", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-code-origins-" });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/producer.blot`;
  try {
    await Deno.writeTextFile(entry, consumerSource);
    await Deno.writeTextFile(producer, producerSource);
    for (const codegenTier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
      });
      try {
        const sources = { [entry]: consumerSource, [producer]: producerSource };
        const good = await compiler.build({ sources });
        assert(good.success, JSON.stringify(good));
        const guest = await instantiateGuest(good.bytes);
        try {
          assert.equal(guest.call("answer", null), 42);
        } finally {
          guest.dispose();
        }
        const failingSource = consumerSource.replace(
          "choices.good",
          "choices.bad",
        );
        const bad = await compiler.build({
          sources: { ...sources, [entry]: failingSource },
        });
        assert(!bad.success);
        const issue = bad.diagnostics.find((item) => item.origins?.length);
        assert(issue, JSON.stringify(bad.diagnostics));
        const origins = issue.origins!;
        const generator = origins.find((item) => item.kind === "generator");
        assert(generator, JSON.stringify(origins));
        assert.equal(generator.filename, entry);
        assert.equal(generator.start, failingSource.indexOf("make 0"));
        const quote = origins.find((item) => item.kind === "quote");
        assert(quote, JSON.stringify(origins));
        assert.equal(quote.filename, producer);
        assert.equal(quote.start, producerSource.indexOf("@code.quote"));
        const invocation = origins.find((item) => item.kind === "invocation");
        assert(invocation, JSON.stringify(origins));
        assert.equal(invocation.filename, entry);
        assert.equal(invocation.start, failingSource.indexOf("@code.run"));
        const recovered = await compiler.build({ sources });
        assert(recovered.success, JSON.stringify(recovered));
        assert.deepEqual(recovered.bytes, good.bytes);
        const checkpoint = await compiler.exportCheckpoint();
        const archive = `${directory}/producer.blotdep`;
        const packed = await new Deno.Command(executable, {
          args: ["dependencies", entry, archive, "--prelude", "none"],
          stdout: "piped",
          stderr: "piped",
        }).output();
        assert(
          packed.success,
          new TextDecoder().decode(packed.stdout) +
            new TextDecoder().decode(packed.stderr),
        );
        const options = {
          executable,
          entry,
          prelude: null,
          cacheDirectory: false as const,
          codegenTier,
        };
        for (
          const replay of [{ ...options, checkpoint }, {
            ...options,
            dependencies: archive,
          }]
        ) {
          const restarted = await createZigProjectCompiler(replay);
          try {
            const resumed = await restarted.build({ sources });
            assert(resumed.success, JSON.stringify(resumed));
            assert.deepEqual(resumed.bytes, good.bytes);
            const failed = await restarted.build({
              sources: { ...sources, [entry]: failingSource },
            });
            assert(!failed.success);
            const resumedIssue = failed.diagnostics.find((item) =>
              item.origins?.length
            );
            assert(resumedIssue, JSON.stringify(failed.diagnostics));
            assert.deepEqual(resumedIssue.origins, origins);
            const corrected = await restarted.build({ sources });
            assert(corrected.success, JSON.stringify(corrected));
            assert.deepEqual(corrected.bytes, good.bytes);
          } finally {
            await restarted.dispose();
          }
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
