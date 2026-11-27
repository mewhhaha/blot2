import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url).pathname;

{
  Deno.test(`selected numeric result operands preserve exact bodies imports edits and restart`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "squid-proof-operands-",
    });
    const entry = `${directory}/main.sq`;
    const dependency = `${directory}/index.sq`;
    const archive = `${directory}/index.sqdep`;
    const library = `const selected = func (unused: U32) => return func (index: U32) => return do:
  let copied = index
  break copied
const forwarded = func (index: U32) => return selected 42 index
const count = func (values: Array U32) => return do:
  let copied = values
  break @array.length copied
`;
    const main = `import {forwarded, count} from "./index"
io const lookup = func (index: U32) => return do:
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

{
  Deno.test(`prepared associated numeric operands preserve exact methods imports edits and restart`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "squid-associated-proof-",
    });
    const entry = `${directory}/main.sq`;
    const dependency = `${directory}/index.sq`;
    const archive = `${directory}/index.sqdep`;
    const library = `type Probe is data = $Probe U32
const Probe.choose = func (unused: Probe) => return func (index: U32) => return do:
  let copied = index
  break copied
const Probe.within = func (unused: Probe) => return func (index: U32) => return @u32.lt index 2
const access = func probe => return func (index: U32) => return do:
  let values = #[8, 13]
  if @type.call "within" probe index:
    break @array.get values (@type.call "choose" probe index)
  break 0
`;
    const main = `import {access, Probe} from "./index"
io const lookup = func (index: U32) => return access ($Probe 42) index
io const ordered = func (host: U32 -> U32 ! {Foreign}) => return do:
  use first <- host 1
  let selected = access ($Probe first) 1
  use final <- host 2
  break @u32.add selected final
`;
    const sources = { [entry]: main, [dependency]: library };
    const options = {
      executable,
      entry,
      prelude: null,
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

{
  Deno.test(`selected arithmetic identities preserve boundaries exact methods imports edits and restart`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "squid-identity-proof-",
    });
    const entry = `${directory}/main.sq`;
    const dependency = `${directory}/index.sq`;
    const archive = `${directory}/index.sqdep`;
    const library = `type Probe is data = $Probe U32
const Probe.choose = func (unused: Probe) => return func (index: U32) => return do:
  let zero = @u32.sub index index
  let copied = @u32.add 0 index
  break @u32.sub copied zero
const Probe.within = func (unused: Probe) => return func (index: U32) => return @u32.lt (@u32.sub index 0) 2
const decode = func probe => return func (index: U32) => return @type.call "choose" probe index
const access = func probe => return func (index: U32) => return do:
  let values = #[8, 13]
  if @type.call "within" probe index:
    break @array.get values (@type.call "choose" probe index)
  break 0
`;
    const main = `import {access, decode, Probe} from "./index"
io const lookup = func (index: U32) => return access ($Probe 42) index
io const identity = func (index: U32) => return decode ($Probe 42) index
io const ordered = func (host: U32 -> U32 ! {Foreign}) => return do:
  use first <- host 1
  let selected = access ($Probe first) 1
  use final <- host 2
  break @u32.add selected final
`;
    const sources = { [entry]: main, [dependency]: library };
    const options = {
      executable,
      entry,
      prelude: null,
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

{
  Deno.test(`conditional numeric identities preserve condition traps and invalidate edited branches`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "squid-conditional-proof-",
    });
    const entry = `${directory}/main.sq`;
    const dependency = `${directory}/index.sq`;
    const library =
      `const selected = func (index: U32) => return if @u32.eq (@u32.div 1 index) 0 then index else index
`;
    const main = `import {selected} from "./index"
io const lookup = func (index: U32) => return do:
  let values = #[8, 13, 21, 34]
  if @u32.lt index (@array.length values):
    break @array.get values (selected index)
  break 0
`;
    const options = {
      executable,
      entry,
      prelude: null,
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
