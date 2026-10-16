import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest, readGuestAbi } from "../../compiler/guest.ts";
import { ResourceJournal } from "../../compiler/resource_journal.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = `type Ask is effect = {ask: Unit -> U32}
entry const cancel = fn () => do:
  let computation = @computation (fn () => do:
    use outer <- @resource.acquire (fn () => 9) (fn resource => ())
    use inner <- @resource.acquire (fn () => 7) (fn resource => ())
    use value <- Ask.ask ()
    return @usage.borrow outer (fn loan => @u32.add value (@usage.read loan))
  )
  for request in @requests computation:
    case request of
      effect Ask.ask () =>
        return 42
      complete value =>
        return value
entry const scope_cancel = fn () => do:
  let computation = @computation (fn () => @resource.scope (fn () => 11) (fn resource => ()) (fn loan => do:
    use value <- Ask.ask ()
    return @u32.add value (@usage.read loan)
  ))
  for request in @requests computation:
    case request of
      effect Ask.ask () =>
        return 42
      complete value =>
        return value
entry const resume = fn () => do:
  let computation = @computation (fn () => do:
    use owner <- @resource.acquire (fn () => 9) (fn resource => ())
    use value <- Ask.ask ()
    return @usage.borrow owner (fn loan => @u32.add value (@usage.read loan))
  )
  for request in @requests computation:
    case request of
      effect Ask.ask () =>
        yield 33
      complete value =>
        return value
const keep = fn ~value => fn () => @force value
entry const retry = fn () => do:
  let delayed = keep (do:
    use owner <- @resource.acquire (fn () => 9) (fn resource => ())
    use value <- Ask.ask ()
    return @usage.borrow owner (fn loan => @u32.add value (@usage.read loan))
  )
  let computation = @computation (fn () => delayed ())
  use first <- do:
    for request in @requests computation:
      case request of
        effect Ask.ask () =>
          return 40
        complete value =>
          return value
  use second <- do:
    for request in @requests computation:
      case request of
        effect Ask.ask () =>
          yield 33
        complete value =>
          return value
  return @u32.add first second
entry const suspend_cancel = fn (host: Unit -> U32 ! {Foreign}) => do:
  let computation = @computation (fn () => do:
    use owner <- @resource.acquire (fn () => 13) (fn resource => ())
    use value <- Ask.ask ()
    return @usage.borrow owner (fn loan => @u32.add value (@usage.read loan))
  )
  for request in @requests computation:
    case request of
      effect Ask.ask () =>
        return host ()
      complete value =>
        return value
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`resource request cancellation retires owned frames and preserves exact cleanup order (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-resource-request-",
    });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const first = await compiler.build({ sources: { [entry]: source } });
      assert(first.success, JSON.stringify(first));
      const module = new WebAssembly.Module(first.bytes);
      const trace: string[] = [];
      const raw = new WebAssembly.Instance(module, {
        "blot:host/1": { call_unit_u32: () => 42 },
        "blot:resource/1": {
          reserve: () => journal.reserve(),
          register: (
            token: number,
            adapter: number,
            payload: number,
            callable: number,
            provider: number,
          ) =>
            journal.register(
              token >>> 0,
              adapter,
              payload >>> 0,
              callable >>> 0,
              provider >>> 0,
            ),
          release: (token: number) => journal.release(token >>> 0),
        },
        "blot:resource/2": {
          register_owned(
            token: number,
            adapter: number,
            payload: number,
            callable: number,
            provider: number,
            owner: number,
          ) {
            const words = new Uint32Array(memory.buffer);
            const slot = (owner >>> 0) / 4;
            assert.equal(words[slot + 1], 0);
            journal.registerOwned(
              token >>> 0,
              adapter,
              payload >>> 0,
              callable >>> 0,
              provider >>> 0,
              owner >>> 0,
            );
            words[slot + 1] = token;
            words[slot - 6] |= 2048;
          },
          retire: (token: number) => journal.retire(token >>> 0),
          drain: () => journal.drain(),
        },
      }).exports;
      const memory = raw["blot:memory"] as WebAssembly.Memory;
      const journal = new ResourceJournal(
        Array.from(
          { length: readGuestAbi(module).resourceAdapterCount! },
          (_, index) => ({
            cleanup(payload, callable, provider) {
              trace.push(`cleanup:${payload}`);
              (raw[`blot:resource_cleanup/${index}`] as CallableFunction)(
                payload,
                callable,
                provider,
              );
            },
            drop(payload, callable, provider) {
              trace.push(`drop:${payload}`);
              (raw[`blot:resource_drop/${index}`] as CallableFunction)(
                payload,
                callable,
                provider,
              );
            },
          }),
        ),
        (owner, token) => {
          const words = new Uint32Array(memory.buffer);
          assert.equal(words[owner / 4 + 1], token);
          words[owner / 4 + 1] = 0;
        },
      );
      for (let iteration = 0; iteration < 128; iteration++) {
        for (const name of ["cancel", "resume", "scope_cancel", "retry"]) {
          trace.length = 0;
          (raw["blot:ownership_enter"] as CallableFunction)();
          journal.begin();
          try {
            let expected = 42;
            if (name === "retry") expected = 82;
            assert.equal((raw[name] as CallableFunction)(0), expected);
          } finally {
            try {
              journal.finish();
            } finally {
              (raw["blot:ownership_leave"] as CallableFunction)(0);
              (raw["blot:reset"] as CallableFunction)(0);
            }
          }
          if (name === "cancel") {
            assert.deepEqual(trace, [
              "cleanup:7",
              "drop:7",
              "cleanup:9",
              "drop:9",
            ]);
          } else if (name === "scope_cancel") {
            assert.deepEqual(trace, ["cleanup:11", "drop:11"]);
          } else if (name === "retry") {
            assert.deepEqual(trace, [
              "cleanup:9",
              "drop:9",
              "cleanup:9",
              "drop:9",
            ]);
          } else assert.deepEqual(trace, ["cleanup:9", "drop:9"]);
          for (const counter of ["roots", "leases"]) {
            assert.equal(
              Number((raw[`blot:rc_${counter}`] as WebAssembly.Global).value),
              0,
            );
          }
        }
      }
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(first.bytes, { asynchronous });
        try {
          if (asynchronous) {
            assert.equal(await guest.callAsync("cancel", null), 42);
            let settle: ((value: number) => void) | undefined;
            const host = guest.capabilityAsync({
              parameter: "Unit",
              result: "U32",
              call: () =>
                new Promise<number>((resolve) => {
                  settle = resolve;
                }),
            });
            const pending = guest.callAsync("suspend_cancel", host);
            await Promise.resolve();
            assert(settle);
            assert.throws(
              () => guest.dispose(),
              (error) =>
                error instanceof Error && error.message.includes("active"),
            );
            settle(42);
            assert.equal(await pending, 42);
          } else {
            assert.equal(guest.call("cancel", null), 42);
            const host = guest.capability({
              parameter: "Unit",
              result: "U32",
              call: () => 42,
            });
            assert.equal(guest.call("suspend_cancel", host), 42);
          }
        } finally {
          guest.dispose();
        }
      }
      const checkpoint = await compiler.exportCheckpoint();
      const restored = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
        checkpoint,
      });
      try {
        const rebuilt = await restored.build({ sources: { [entry]: source } });
        assert(rebuilt.success, JSON.stringify(rebuilt));
        assert.deepEqual(rebuilt.bytes, first.bytes);
      } finally {
        await restored.dispose();
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
