import { strict as assert } from "node:assert";
import { instantiateGuest, readGuestAbi } from "../../compiler/guest.ts";
import { ResourceJournal } from "../../compiler/resource_journal.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const source = `
entry const normal = func (host: Unit -> U32 ! {Foreign}) => return @resource.scope (func () => return #[7, 9]) (func owner => return ()) (func loan => return @u32.add (@usage.length loan) (host ()))
entry const nested = func (host: Unit -> U32 ! {Foreign}) => return @resource.scope (func () => return #[7, 9]) (func owner => return ()) (func outer => return @resource.scope (func () => return [1.5, 2.5, 3.5]) (func owner => return ()) (func inner => return @u32.add (@usage.length outer) (@u32.add (@usage.length inner) (host ()))))
entry const early = func () => return @resource.scope (func () => return #[1, 2]) (func owner => return ()) (func loan => return do:
  break @usage.length loan
)
entry const trapped = func () => return @resource.scope (func () => return #[1, 2]) (func owner => return ()) (func loan => return @u32.div (@usage.length loan) 0)
entry const cleanup_failed = func () => return @resource.scope (func () => return #[1, 2]) (func owner => return ()) (func outer => return @resource.scope (func () => return [1.5, 2.5, 3.5]) (func owner => return @panic "cleanup") (func inner => return @usage.length inner))
entry const acquire_failed = func () => return @resource.scope (func () : unique (Array U32) => return @panic "acquire") (func owner => return ()) (func loan => return @usage.length loan)
entry const surviving = func (value: U32) => return @resource.scope (func () => return #[value, @u32.add value 1]) (func owner => return ()) (func loan => return #[value, @usage.length loan])
entry const scalar = func () => return @resource.scope (func () => return 1.5) (func owner => return ()) (func loan => return @usage.read loan)
entry const memory = func () : Array U32 => return #[]
`;

Deno.test("reference resource journals own payload roots through cleanup traps host rejection and suspension", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-resource-reference-",
  });
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
      });
      let bytes: Uint8Array<ArrayBuffer>;
      try {
        const built = await compiler.build({ sources: { [entry]: source } });
        assert(built.success, JSON.stringify(built));
        bytes = built.bytes;
      } finally {
        await compiler.dispose();
      }
      const module = new WebAssembly.Module(bytes);
      const abi = readGuestAbi(module);
      assert.equal(abi.version, 4);
      assert.equal(abi.resourceAdapterCount, 3);
      for (const asynchronous of [false, true]) {
        const jspi = WebAssembly as unknown as {
          Suspending: new (
            fn: () => Promise<number>,
          ) => WebAssembly.ImportValue;
          promising(
            fn: CallableFunction,
          ): (...args: unknown[]) => Promise<number>;
        };
        let failure = false;
        let suspended = false;
        let settle: ((value: number) => void) | undefined;
        let decline: ((error: Error) => void) | undefined;
        const host = () => {
          if (failure) throw new Error("host rejection");
          return 7;
        };
        let hostImport: WebAssembly.ImportValue = host;
        if (asynchronous) {
          hostImport = new jspi.Suspending(async () => {
            if (suspended) {
              return await new Promise<number>((resolve, reject) => {
                settle = resolve;
                decline = reject;
              });
            }
            await Promise.resolve();
            return host();
          });
        }
        const raw = new WebAssembly.Instance(module, {
          "blot:host/1": { call_unit_u32: hostImport },
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
        }).exports;
        const trace: string[] = [];
        const journal = new ResourceJournal(
          Array.from({ length: 3 }, (_, index) => ({
            cleanup(payload, callable, provider) {
              trace.push(`cleanup:${index}`);
              (raw[`blot:resource_cleanup/${index}`] as CallableFunction)(
                payload,
                callable,
                provider,
              );
            },
            drop(payload, callable, provider) {
              trace.push(`drop:${index}`);
              (raw[`blot:resource_drop/${index}`] as CallableFunction)(
                payload,
                callable,
                provider,
              );
            },
          })),
        );
        const count = (name: string) =>
          Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value);
        const memory = raw["blot:memory"] as WebAssembly.Memory;
        const begin = () => {
          (raw["blot:ownership_enter"] as CallableFunction)();
          journal.begin();
          trace.length = 0;
        };
        const finish = (outcome: number) => {
          journal.finish();
          (raw["blot:ownership_leave"] as CallableFunction)(outcome);
          (raw["blot:reset"] as CallableFunction)(0);
          for (const name of ["roots", "leases", "host_refs"]) {
            assert.equal(count(name), 0, name);
          }
        };
        const invoke = (name: string, ...args: unknown[]) => {
          if (asynchronous) {
            return jspi.promising(raw[name] as CallableFunction)(...args);
          }
          return Promise.resolve().then(() =>
            (raw[name] as CallableFunction)(...args)
          );
        };
        begin();
        assert.equal(await invoke("normal", {}), 9);
        finish(0);
        assert.deepEqual(trace, ["cleanup:2", "drop:2"]);
        begin();
        assert.equal(await invoke("early"), 2);
        finish(0);
        assert.deepEqual(trace, ["cleanup:2", "drop:2"]);
        const warmed = memory.buffer.byteLength;
        for (let index = 0; index < 128; index++) {
          for (
            const name of [
              "trapped",
              "cleanup_failed",
              "acquire_failed",
              "nested",
            ]
          ) {
            begin();
            failure = name === "nested";
            await assert.rejects(() => invoke(name, {}));
            finish(1);
            let expected = ["cleanup:2", "drop:2"];
            if (name === "cleanup_failed" || name === "nested") {
              expected = [...expected, ...expected];
            }
            if (name === "acquire_failed") expected = [];
            assert.deepEqual(trace, expected);
            failure = false;
            begin();
            assert.equal(await invoke("normal", {}), 9);
            finish(0);
            assert.equal(memory.buffer.byteLength, warmed);
          }
        }
        if (asynchronous) {
          suspended = true;
          for (const rejectHost of [false, true]) {
            begin();
            const pending = invoke("nested", {});
            assert(count("roots") > 0);
            assert(count("leases") > 0);
            assert.equal(count("host_refs"), 1);
            assert.deepEqual(
              trace,
              [],
              "reference owners stay live until settlement",
            );
            if (rejectHost) {
              decline!(new Error("cancelled host"));
              await assert.rejects(pending, /cancelled host/);
              finish(1);
            } else {
              settle!(7);
              assert.equal(await pending, 12);
              finish(0);
            }
            assert.deepEqual(trace, [
              "cleanup:2",
              "drop:2",
              "cleanup:2",
              "drop:2",
            ]);
          }
        }
      }
      const guest = await instantiateGuest(bytes);
      try {
        const saved = guest.call("surviving", 41);
        assert(saved instanceof Uint32Array);
        assert.deepEqual([...saved], [41, 2]);
        for (let index = 0; index < 16; index++) guest.call("surviving", index);
        const warmed = guest.memoryBytes();
        for (let index = 0; index < 128; index++) {
          assert.deepEqual(
            guest.call("surviving", index),
            new Uint32Array([index, 2]),
          );
          assert.deepEqual([...saved], [41, 2]);
          assert.equal(guest.memoryBytes(), warmed);
        }
        assert.equal(guest.call("scalar", null), 1.5);
      } finally {
        guest.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("reference resources preserve source archive checkpoint restart and failed revisions", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-reference-import-",
  });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/scope.blot`;
  const dependencies = `${directory}/scope.blotdep`;
  const producer =
    `const run = func (value: U32) => return @resource.scope (func () => return #[value, @u32.add value 1]) (func owner => return ()) (func loan => return @usage.length loan)\n`;
  const consumer =
    `import {run} from "./scope"\nentry const answer = func (value: U32) => return run value\n`;
  try {
    await Deno.writeTextFile(entry, consumer);
    await Deno.writeTextFile(dependency, producer);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, dependencies, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        cacheDirectory: false as const,
        codegenTier,
      };
      const compiler = await createZigProjectCompiler(options);
      const imported = await createZigProjectCompiler({
        ...options,
        dependencies,
      });
      try {
        const first = await compiler.build();
        const archived = await imported.build();
        assert(first.success, JSON.stringify(first));
        assert(archived.success, JSON.stringify(archived));
        assert(archived.stats.cachedModules > 0);
        assert.deepEqual(archived.bytes, first.bytes);
        for (const bytes of [first.bytes, archived.bytes]) {
          for (const asynchronous of [false, true]) {
            const guest = await instantiateGuest(bytes, { asynchronous });
            try {
              if (asynchronous) {
                assert.equal(await guest.callAsync("answer", 42), 2);
              } else assert.equal(guest.call("answer", 42), 2);
            } finally {
              guest.dispose();
            }
          }
        }
        const checkpoint = await compiler.exportCheckpoint();
        const bad = await compiler.build({
          sources: {
            [entry]: consumer,
            [dependency]: producer.replace("@usage.length loan", "loan"),
          },
        });
        assert(!bad.success);
        assert(
          bad.diagnostics.some((diagnostic) =>
            diagnostic.code === "borrow_escape"
          ),
          JSON.stringify(bad),
        );
        const recovered = await compiler.build();
        assert(recovered.success, JSON.stringify(recovered));
        assert.deepEqual(recovered.bytes, first.bytes);
        const resumed = await createZigProjectCompiler({
          ...options,
          checkpoint,
        });
        try {
          const restart = await resumed.build();
          assert(restart.success, JSON.stringify(restart));
          assert.deepEqual(restart.bytes, first.bytes);
        } finally {
          await resumed.dispose();
        }
      } finally {
        await compiler.dispose();
        await imported.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
