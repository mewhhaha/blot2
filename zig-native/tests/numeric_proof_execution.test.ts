import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = `data Maybe = #Some U32 | #None
const witness: (values: Array U32) -> (index: U32) -> @proof.Index values index = fn values => fn index => @proof.index values index
const at: (values: Array U32) -> (index: U32) -> (@proof.Index values index) -> U32 = fn values => fn index => fn proof => @array.get values index
const later: (values: Array U32) -> (index: U32) -> (@proof.Index values index) -> Unit -> U32 = fn values => fn index => fn proof => fn unused => @array.get values index
const invoke = fn callback => callback ()
const within = fn (index: U32) => fn (values: Array U32) => @u32.lt index (@array.length values)
entry const lookup = fn (index: U32) => do:
  let values = #[8, 13]
  let valid = witness values index
  break at values index valid
entry const partial = fn (index: U32) => do:
  let values = #[8, 13]
  let valid = witness values index
  let ready = later values index valid
  break invoke ready
entry const equal = fn (value: U32) => do:
  let valid = @proof.eq value 7
  break value
entry const less = fn (value: U32) => do:
  let valid = @proof.lt value 8
  break value
entry const weak = fn (value: U32) => do:
  let valid = @proof.le value 8
  break value
entry const addition = fn (value: U32) => do:
  let valid = @proof.add_fits value 1
  break value
entry const subtraction = fn (value: U32) => do:
  let valid = @proof.sub_fits value 1
  break value
entry const guarded = fn (index: U32) => do:
  let values = #[8, 13]
  if @u32.lt index (@array.length values):
    break @array.get values index
  break 0
entry const named_guarded = fn (index: U32) => do:
  let values = #[8, 13]
  if within index values:
    break @array.get values index
  break 0
entry const false_edges = fn (index: U32) => do:
  let values = #[8, 13]
  let length = @array.length values
  if @u32.lt length index:
    break 0
  if @u32.eq index length:
    break 0
  break @array.get values index
entry const rebound = fn (index: U32) => do:
  let values = #[8, 13]
  if @u32.lt index (@array.length values):
    index := @u32.add self 1
    break @array.get values index
  break 0
entry const changed = fn (index: U32) => do:
  let values = #[8, 13]
  let valid = @proof.index values index
  let after = @array.set values index 21
  break @array.get after index
entry const ranges = fn (index: U32) => do:
  let values = #[8, 13]
  let result = index
  for cursor in 0..@array.length values:
    result := @u32.add self (@array.get values cursor)
  break result
entry const predecessor = fn (index: U32) => do:
  let values = #[8, 13]
  let bounded = @proof.index values index
  let fits = @proof.sub_fits index 1
  break @array.get values (@u32.sub index 1)
entry const fallback = fn (index: U32) => do:
  let values = #[8]
  let #Some selected = if @u32.eq index 0 then #None else #Some 42 else:
    let valid = @proof.index values index
    break 0
  break @array.get values index
entry const ordered = fn (host: U32 -> U32 ! {Foreign}) => do:
  use left <- host 1
  use right <- host 2
  let valid = @proof.lt left right
  use result <- host 3
  break result
`;

for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`numeric guards preserve unsigned boundaries ordered traps erased calls and retained recovery (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-numeric-proof-" });
    const entry = `${directory}/main.blot`;
    const options = {
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false as const,
    };
    await Deno.writeTextFile(entry, source);
    const compiler = await createZigProjectCompiler(options);
    try {
      const built = await compiler.build({ sources: { [entry]: source } });
      assert(built.success, JSON.stringify(built));
      const guest = await instantiateGuest(built.bytes);
      try {
        for (
          const [name, value, expected] of [
            ["lookup", 0, 8],
            ["lookup", 1, 13],
            ["partial", 1, 13],
            ["equal", 7, 7],
            ["less", 7, 7],
            ["weak", 8, 8],
            ["addition", 4294967294, 4294967294],
            ["subtraction", 1, 1],
            ["guarded", 0, 8],
            ["guarded", 1, 13],
            ["guarded", 2, 0],
            ["guarded", 4294967295, 0],
            ["named_guarded", 0, 8],
            ["named_guarded", 1, 13],
            ["named_guarded", 2, 0],
            ["named_guarded", 4294967295, 0],
            ["false_edges", 0, 8],
            ["false_edges", 2, 0],
            ["false_edges", 4294967295, 0],
            ["rebound", 0, 13],
            ["changed", 1, 21],
            ["ranges", 1, 22],
            ["predecessor", 1, 8],
            ["fallback", 0, 0],
          ] as const
        ) assert.equal(guest.call(name, value), expected);
        for (
          const [name, value] of [
            ["lookup", 2],
            ["lookup", 4294967295],
            ["partial", 2],
            ["equal", 6],
            ["less", 8],
            ["weak", 9],
            ["addition", 4294967295],
            ["subtraction", 0],
            ["rebound", 1],
            ["changed", 2],
            ["predecessor", 0],
            ["fallback", 1],
          ] as const
        ) assert.throws(() => guest.call(name, value));
        const calls: number[] = [];
        const host = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => {
            calls.push(Number(value));
            return 9;
          },
        });
        assert.throws(() => guest.call("ordered", host));
        assert.deepEqual(calls, [1, 2]);
      } finally {
        guest.dispose();
      }
      const failed = await compiler.build({
        sources: {
          [entry]: source.replace(
            "at values index valid",
            "at values (@u32.add index 1) valid",
          ),
        },
      });
      assert(!failed.success);
      const restored = await compiler.build({ sources: { [entry]: source } });
      assert(restored.success, JSON.stringify(restored));
      const fresh = await createZigProjectCompiler(options);
      try {
        const independent = await fresh.build({ sources: { [entry]: source } });
        assert(independent.success, JSON.stringify(independent));
        assert.deepEqual(restored.bytes, independent.bytes);
        assert.deepEqual(restored.bytes, built.bytes);
      } finally {
        await fresh.close();
      }
    } finally {
      await compiler.close();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

Deno.test("numeric public proof helpers survive source and compiled dependency boundaries", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-proof-import-" });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/proof.blot`;
  const archive = `${directory}/proof.blotdep`;
  const boundary = source.indexOf("entry const lookup");
  const library = source.slice(0, boundary).replace(
    "data Maybe = #Some U32 | #None\n",
    "",
  );
  const main = 'import {witness, at, later, invoke, within} from "./proof"\n' +
    "data Maybe = #Some U32 | #None\n" +
    source.slice(boundary);
  try {
    await Deno.writeTextFile(entry, main);
    await Deno.writeTextFile(dependency, library);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, archive, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(
      packed.success,
      new TextDecoder().decode(packed.stderr) +
        new TextDecoder().decode(packed.stdout),
    );
    for (const dependencies of [undefined, archive]) {
      for (const codegenTier of ["optimized", "development"] as const) {
        const compiler = await createZigProjectCompiler({
          executable,
          entry,
          prelude: null,
          dependencies,
          codegenTier,
          cacheDirectory: false,
        });
        try {
          const built = await compiler.build({
            sources: { [entry]: main, [dependency]: library },
          });
          assert(built.success, JSON.stringify(built));
          const guest = await instantiateGuest(built.bytes);
          try {
            assert.equal(guest.call("lookup", 1), 13);
            assert.throws(() => guest.call("lookup", 2));
            assert.equal(guest.call("named_guarded", 1), 13);
            assert.equal(guest.call("named_guarded", 2), 0);
          } finally {
            guest.dispose();
          }
        } finally {
          await compiler.close();
        }
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`selected numeric result operands preserve exact bodies imports edits and restart (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-proof-operands-",
    });
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/index.blot`;
    const archive = `${directory}/index.blotdep`;
    const library = `const selected = fn (unused: U32) => fn (index: U32) => do:
  let copied = index
  break copied
const forwarded = fn (index: U32) => selected 42 index
const count = fn (values: Array U32) => do:
  let copied = values
  break @array.length copied
`;
    const main = `import {forwarded, count} from "./index"
entry const lookup = fn (index: U32) => do:
  let values = #[8, 13]
  if @u32.lt index (count values):
    break @array.get values (forwarded index)
  break 0
`;
    const sources = { [entry]: main, [dependency]: library };
    const options = {
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: `${directory}/cache`,
    };
    const observe = async (bytes: Uint8Array<ArrayBuffer>, changed = false) => {
      const guest = await instantiateGuest(bytes);
      try {
        if (changed) {
          assert.equal(guest.call("lookup", 0), 13);
          assert.throws(
            () => guest.call("lookup", 1),
            WebAssembly.RuntimeError,
          );
        } else {
          assert.equal(guest.call("lookup", 0), 8);
          assert.equal(guest.call("lookup", 1), 13);
        }
        assert.equal(guest.call("lookup", 2), 0);
        assert.equal(guest.call("lookup", 4294967295), 0);
      } finally {
        guest.dispose();
      }
    };
    const compiler = await createZigProjectCompiler(options);
    try {
      await Deno.writeTextFile(entry, main);
      await Deno.writeTextFile(dependency, library);
      const first = await compiler.build({ sources });
      assert(first.success, JSON.stringify(first));
      await observe(first.bytes);
      const changedSources = {
        ...sources,
        [dependency]: library.replace(
          "let copied = index",
          "let copied = @u32.add index 1",
        ),
      };
      const changed = await compiler.build({ sources: changedSources });
      assert(changed.success, JSON.stringify(changed));
      await observe(changed.bytes, true);
      const independent = await createZigProjectCompiler({
        ...options,
        cacheDirectory: false,
      });
      try {
        const fresh = await independent.build({ sources: changedSources });
        assert(fresh.success, JSON.stringify(fresh));
        assert.deepEqual(changed.bytes, fresh.bytes);
      } finally {
        await independent.dispose();
      }
      const failed = await compiler.build({
        sources: {
          ...sources,
          [dependency]: library.replace("break copied", "break missing"),
        },
      });
      assert(!failed.success);
      const restored = await compiler.build({ sources });
      assert(restored.success, JSON.stringify(restored));
      assert.deepEqual(restored.bytes, first.bytes);
      await observe(restored.bytes);
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, archive, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(
        packed.success,
        new TextDecoder().decode(packed.stderr) +
          new TextDecoder().decode(packed.stdout),
      );
      for (const dependencies of [undefined, archive]) {
        const restarted = await createZigProjectCompiler({
          ...options,
          dependencies,
        });
        try {
          const result = await restarted.build({ sources });
          assert(result.success, JSON.stringify(result));
          assert.deepEqual(result.bytes, first.bytes);
          await observe(result.bytes);
        } finally {
          await restarted.dispose();
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`prepared associated numeric operands preserve exact methods imports edits and restart (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-associated-proof-",
    });
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/index.blot`;
    const archive = `${directory}/index.blotdep`;
    const library = `type Probe is data = #Probe U32
const Probe.choose = fn (unused: Probe) => fn (index: U32) => do:
  let copied = index
  break copied
const Probe.within = fn (unused: Probe) => fn (index: U32) => @u32.lt index 2
const access = fn probe => fn (index: U32) => do:
  let values = #[8, 13]
  if @type.call "within" probe index:
    break @array.get values (@type.call "choose" probe index)
  break 0
`;
    const main = `import {access, Probe} from "./index"
entry const lookup = fn (index: U32) => access (#Probe 42) index
entry const ordered = fn (host: U32 -> U32 ! {Foreign}) => do:
  use first <- host 1
  let selected = access (#Probe first) 1
  use final <- host 2
  break @u32.add selected final
`;
    const sources = { [entry]: main, [dependency]: library };
    const options = {
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: `${directory}/cache`,
    };
    const observe = async (bytes: Uint8Array<ArrayBuffer>, changed = false) => {
      const guest = await instantiateGuest(bytes);
      try {
        if (changed) {
          assert.equal(guest.call("lookup", 0), 13);
          assert.throws(
            () => guest.call("lookup", 1),
            WebAssembly.RuntimeError,
          );
        } else {
          assert.equal(guest.call("lookup", 0), 8);
          assert.equal(guest.call("lookup", 1), 13);
        }
        assert.equal(guest.call("lookup", 2), 0);
        assert.equal(guest.call("lookup", 4294967295), 0);
        const calls: number[] = [];
        const host = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => {
            calls.push(Number(value));
            return 9;
          },
        });
        if (changed) {
          assert.throws(
            () => guest.call("ordered", host),
            WebAssembly.RuntimeError,
          );
          assert.deepEqual(calls, [1]);
        } else {
          assert.equal(guest.call("ordered", host), 22);
          assert.deepEqual(calls, [1, 2]);
        }
      } finally {
        guest.dispose();
      }
    };
    const compiler = await createZigProjectCompiler(options);
    try {
      await Deno.writeTextFile(entry, main);
      await Deno.writeTextFile(dependency, library);
      const first = await compiler.build({ sources });
      assert(first.success, JSON.stringify(first));
      await observe(first.bytes);
      const changedSources = {
        ...sources,
        [dependency]: library.replace(
          "let copied = index",
          "let copied = @u32.add index 1",
        ),
      };
      const changed = await compiler.build({ sources: changedSources });
      assert(changed.success, JSON.stringify(changed));
      await observe(changed.bytes, true);
      const independent = await createZigProjectCompiler({
        ...options,
        cacheDirectory: false,
      });
      try {
        const fresh = await independent.build({ sources: changedSources });
        assert(fresh.success, JSON.stringify(fresh));
        assert.deepEqual(changed.bytes, fresh.bytes);
      } finally {
        await independent.dispose();
      }
      const failed = await compiler.build({
        sources: {
          ...sources,
          [dependency]: library.replace("break copied", "break missing"),
        },
      });
      assert(!failed.success);
      const restored = await compiler.build({ sources });
      assert(restored.success, JSON.stringify(restored));
      assert.deepEqual(restored.bytes, first.bytes);
      await observe(restored.bytes);
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, archive, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(
        packed.success,
        new TextDecoder().decode(packed.stderr) +
          new TextDecoder().decode(packed.stdout),
      );
      for (const dependencies of [undefined, archive]) {
        const restarted = await createZigProjectCompiler({
          ...options,
          dependencies,
        });
        try {
          const result = await restarted.build({ sources });
          assert(result.success, JSON.stringify(result));
          assert.deepEqual(result.bytes, first.bytes);
          await observe(result.bytes);
        } finally {
          await restarted.dispose();
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`selected arithmetic identities preserve boundaries exact methods imports edits and restart (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-identity-proof-",
    });
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/index.blot`;
    const archive = `${directory}/index.blotdep`;
    const library = `type Probe is data = #Probe U32
const Probe.choose = fn (unused: Probe) => fn (index: U32) => do:
  let zero = @u32.sub index index
  let copied = @u32.add 0 index
  break @u32.sub copied zero
const Probe.within = fn (unused: Probe) => fn (index: U32) => @u32.lt (@u32.sub index 0) 2
const decode = fn probe => fn (index: U32) => @type.call "choose" probe index
const access = fn probe => fn (index: U32) => do:
  let values = #[8, 13]
  if @type.call "within" probe index:
    break @array.get values (@type.call "choose" probe index)
  break 0
`;
    const main = `import {access, decode, Probe} from "./index"
entry const lookup = fn (index: U32) => access (#Probe 42) index
entry const identity = fn (index: U32) => decode (#Probe 42) index
entry const ordered = fn (host: U32 -> U32 ! {Foreign}) => do:
  use first <- host 1
  let selected = access (#Probe first) 1
  use final <- host 2
  break @u32.add selected final
`;
    const sources = { [entry]: main, [dependency]: library };
    const options = {
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: `${directory}/cache`,
    };
    const observe = async (bytes: Uint8Array<ArrayBuffer>, changed = false) => {
      const guest = await instantiateGuest(bytes);
      try {
        if (changed) {
          assert.equal(guest.call("identity", 4294967295), 0);
          assert.equal(guest.call("identity", 0), 1);
          assert.equal(guest.call("lookup", 0), 13);
          assert.throws(
            () => guest.call("lookup", 1),
            WebAssembly.RuntimeError,
          );
        } else {
          assert.equal(guest.call("identity", 4294967295), 4294967295);
          assert.equal(guest.call("identity", 0), 0);
          assert.equal(guest.call("lookup", 0), 8);
          assert.equal(guest.call("lookup", 1), 13);
        }
        assert.equal(guest.call("lookup", 2), 0);
        assert.equal(guest.call("lookup", 4294967295), 0);
        const calls: number[] = [];
        const host = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => {
            calls.push(Number(value));
            return 9;
          },
        });
        if (changed) {
          assert.throws(
            () => guest.call("ordered", host),
            WebAssembly.RuntimeError,
          );
          assert.deepEqual(calls, [1]);
        } else {
          assert.equal(guest.call("ordered", host), 22);
          assert.deepEqual(calls, [1, 2]);
        }
      } finally {
        guest.dispose();
      }
    };
    const compiler = await createZigProjectCompiler(options);
    try {
      await Deno.writeTextFile(entry, main);
      await Deno.writeTextFile(dependency, library);
      const first = await compiler.build({ sources });
      assert(first.success, JSON.stringify(first));
      await observe(first.bytes);
      const changedSources = {
        ...sources,
        [dependency]: library.replace(
          "let copied = @u32.add 0 index",
          "let copied = @u32.add index 1",
        ),
      };
      const changed = await compiler.build({ sources: changedSources });
      assert(changed.success, JSON.stringify(changed));
      await observe(changed.bytes, true);
      const independent = await createZigProjectCompiler({
        ...options,
        cacheDirectory: false,
      });
      try {
        const fresh = await independent.build({ sources: changedSources });
        assert(fresh.success, JSON.stringify(fresh));
        assert.deepEqual(changed.bytes, fresh.bytes);
      } finally {
        await independent.dispose();
      }
      const failed = await compiler.build({
        sources: {
          ...sources,
          [dependency]: library.replace(
            "break @u32.sub copied zero",
            "break missing",
          ),
        },
      });
      assert(!failed.success);
      const restored = await compiler.build({ sources });
      assert(restored.success, JSON.stringify(restored));
      assert.deepEqual(restored.bytes, first.bytes);
      await observe(restored.bytes);
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, archive, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(
        packed.success,
        new TextDecoder().decode(packed.stderr) +
          new TextDecoder().decode(packed.stdout),
      );
      for (const dependencies of [undefined, archive]) {
        const restarted = await createZigProjectCompiler({
          ...options,
          dependencies,
        });
        try {
          const result = await restarted.build({ sources });
          assert(result.success, JSON.stringify(result));
          assert.deepEqual(result.bytes, first.bytes);
          await observe(result.bytes);
        } finally {
          await restarted.dispose();
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`conditional numeric identities preserve condition traps and invalidate edited branches (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-conditional-proof-",
    });
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/index.blot`;
    const library =
      `const selected = fn (index: U32) => if @u32.eq (@u32.div 1 index) 0 then index else index
`;
    const main = `import {selected} from "./index"
entry const lookup = fn (index: U32) => do:
  let values = #[8, 13, 21, 34]
  if @u32.lt index (@array.length values):
    break @array.get values (selected index)
  break 0
`;
    const options = {
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: `${directory}/cache`,
    };
    const compiler = await createZigProjectCompiler(options);
    const sources = { [entry]: main, [dependency]: library };
    const observe = async (bytes: Uint8Array<ArrayBuffer>, changed = false) => {
      const guest = await instantiateGuest(bytes);
      try {
        assert.throws(() => guest.call("lookup", 0), WebAssembly.RuntimeError);
        assert.equal(guest.call("lookup", 1), 13);
        if (changed) assert.equal(guest.call("lookup", 2), 34);
        else assert.equal(guest.call("lookup", 2), 21);
        if (changed) {
          assert.throws(
            () => guest.call("lookup", 3),
            WebAssembly.RuntimeError,
          );
        } else assert.equal(guest.call("lookup", 3), 34);
        assert.equal(guest.call("lookup", 4), 0);
        assert.equal(guest.call("lookup", 4294967295), 0);
      } finally {
        guest.dispose();
      }
    };
    try {
      await Deno.writeTextFile(entry, main);
      await Deno.writeTextFile(dependency, library);
      const built = await compiler.build({ sources });
      assert(built.success, JSON.stringify(built));
      await observe(built.bytes);
      const edited = {
        ...sources,
        [dependency]: library.replace("then index", "then @u32.add index 1"),
      };
      const changed = await compiler.build({ sources: edited });
      assert(changed.success, JSON.stringify(changed));
      await observe(changed.bytes, true);
      const fresh = await createZigProjectCompiler({
        ...options,
        cacheDirectory: false,
      });
      try {
        const independent = await fresh.build({ sources: edited });
        assert(independent.success, JSON.stringify(independent));
        assert.deepEqual(changed.bytes, independent.bytes);
      } finally {
        await fresh.dispose();
      }
      const failed = await compiler.build({
        sources: {
          ...sources,
          [dependency]: library.replace("else index", "else missing"),
        },
      });
      assert(!failed.success);
      const restored = await compiler.build({ sources });
      assert(restored.success, JSON.stringify(restored));
      assert.deepEqual(restored.bytes, built.bytes);
      await observe(restored.bytes);
      await compiler.dispose();
      const restarted = await createZigProjectCompiler(options);
      try {
        const replay = await restarted.build({ sources });
        assert(replay.success, JSON.stringify(replay));
        assert.deepEqual(replay.bytes, built.bytes);
        await observe(replay.bytes);
      } finally {
        await restarted.dispose();
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
