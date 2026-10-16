import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = (seed: string, delta: number, prefix = "") =>
  `infixl 60 (%%) = both
infixl 60 (??) = ignore
${prefix}const seed = ${seed}
type Number is data = #Number U32
const Number.next = fn (#Number value) => @u32.add value ${delta}
type State a is effect = {get: Unit -> a, set: a -> Unit}
effect Read: U32 -> U32
const state = fn (initial: U32) => @effect.run State.get State.set initial (fn () => do:
  use State.set 40
  return State.get ()
)
const scoped = fn () => @effect.scope (fn (state: State U32) => do:
  let capability = state
  let read = capability.get
  let write = capability.set
  let local = fn () => read ()
  let (successor, result) = do (@effect.state read write seed):
    return local ()
  return result
)
const borrow = fn (owner: unique U32) => @usage.borrow owner (fn loan => @usage.read loan)
const resource = fn () => @resource.scope (fn () => #[seed, 40]) (fn owner => ()) (fn loan => @usage.length loan)
const request = fn (host: U32 -> U32 ! {Foreign}) => do:
  let count = 0
  for request in @requests (@computation (fn () => Read seed)):
    case request of
      effect Read value =>
        count := @u32.add count 1
        yield host value
      complete value =>
        return @u32.add count value
const effect_count = fn () => @effect.count (@effect.of scoped)
const count = effect_count ()
const rich = fn (host: U32 -> U32 ! {Foreign}) => @u32.add (@product.get (state seed) 1) (@u32.add (scoped ()) (@u32.add (borrow 40) (@u32.add (resource ()) (@u32.add (request host) count))))
const both = fn ~(left: U32) => fn ~(right: U32) => @u32.add (@u32.add (@force left) (@force left)) (@force right)
const ignore = fn ~(left: U32) => fn ~(right: U32) => 7
const operate = fn (host: U32 -> U32 ! {Foreign}) => @u32.add ((host seed) %% (host (@u32.add seed 1))) ((host 999) ?? (host 998))
const selected = fn (flag: Bool) => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  let choose = fn () => if flag then left else right
  let chosen = choose ()
  let alias = chosen
  let (state, result) = do (@effect.state chosen.get chosen.set seed):
    use alias.set 42
    return alias.get ()
  return result
))
const witness: (values: Array U32) -> (index: U32) -> @proof.Index values index = fn values => fn index => @proof.index values index
const at: (values: Array U32) -> (index: U32) -> (@proof.Index values index) -> U32 = fn values => fn index => fn proof => @array.get values index
const lookup = fn (index: U32) => do:
  let values = #[seed, 13]
  let valid = witness values index
  return at values index valid
type Render a is contract = {const show: a -> U32}
impl RenderU32 : Render U32 = {const show = fn value => value}
type Item = exists [a] where {Render a} => a
const item: Item = pack [U32] seed as Item
const package_read = fn (item: Item) => unpack item as [a] value in Render.show value
const decorate = fn (value: U32) => fn () => @u32.add value seed
@[fn (callback: Unit -> U32) => fn () => @u32.add (callback ()) 1] @[decorate] const tagged: Unit -> U32 = 40
type Maybe a is data = #Some a | #Nothing
type Counter is data = #Counter U32
const Counter.iter = fn (cursor: Counter) => cursor
const Counter.next = fn (#Counter value) => if @u32.lt value 4 then #Some (value, #Counter (@u32.add value 1)) else #Nothing
const iterator_total = fn (first: U32) => do:
  let result = seed
  for value in #Counter first:
    result := @u32.add self value
  return result
const describe = fn (value: U32) => do:
  let record = {value, values: #[value, seed]}
  record.value := @u32.add self 1
  return @record.merge record {next: (#Number value).next}
`;
const main =
  `import {operate, describe, rich, selected, lookup, item, package_read, tagged, iterator_total} from "./logic"
entry const run = fn (host: U32 -> U32 ! {Foreign}) => operate host
entry const method = fn (value: U32) => do:
  let record = describe value
  return @u32.add record.value record.next
entry const deep = fn (host: U32 -> U32 ! {Foreign}) => rich host
entry const owned = fn (value: U32) => (describe value).values
entry const proof = fn (index: U32) => lookup index
entry const package = fn () => package_read item
entry const tag = fn () => tagged ()
entry const iteration = fn (first: U32) => iterator_total first
entry const chosen = fn (flag: Bool) => selected flag
`;
async function observe(
  bytes: Uint8Array<ArrayBuffer>,
  seed: number,
  delta: number,
) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    const trace: number[] = [];
    let fail = false;
    const failure = new Error("binary demand host failed");
    const implementation = {
      parameter: "U32" as const,
      result: "U32" as const,
      call(value: number) {
        trace.push(value);
        if (fail) throw failure;
        return value + 10;
      },
    };
    let host = guest.capability(implementation);
    if (asynchronous) host = guest.capabilityAsync(implementation);
    const call = async () => {
      if (asynchronous) return await guest.callAsync("run", host);
      return guest.call("run", host);
    };
    try {
      assert.equal(await call(), 3 * seed + 38);
      assert.deepEqual(trace, [seed, seed + 1]);
      fail = true;
      await assert.rejects(
        call,
        (error: unknown) => error instanceof Error && error.cause === failure,
      );
      fail = false;
      trace.length = 0;
      assert.equal(await call(), 3 * seed + 38);
      assert.deepEqual(trace, [seed, seed + 1]);
      const scalar = async (name: string, value: number | boolean | null) => {
        if (asynchronous) return await guest.callAsync(name, value);
        return guest.call(name, value);
      };
      assert.equal(await scalar("proof", 0), seed);
      assert.equal(await scalar("proof", 1), 13);
      await assert.rejects(() => scalar("proof", 2));
      assert.equal(await scalar("proof", 0), seed);
      assert.equal(await scalar("package", null), seed);
      assert.equal(await scalar("tag", null), seed + 41);
      assert.equal(await scalar("iteration", 1), seed + 6);
      assert.equal(await scalar("chosen", true), 42);
      assert.equal(await scalar("chosen", false), 42);
      const deep = async () => {
        if (asynchronous) return await guest.callAsync("deep", host);
        return guest.call("deep", host);
      };
      trace.length = 0;
      assert.equal(await deep(), 93 + 2 * seed);
      assert.deepEqual(trace, [seed]);
      fail = true;
      await assert.rejects(
        deep,
        (error: unknown) => error instanceof Error && error.cause === failure,
      );
      fail = false;
      trace.length = 0;
      assert.equal(await deep(), 93 + 2 * seed);
      assert.deepEqual(trace, [seed]);
      for (let value = 0; value < 16; value++) {
        let method;
        let owned;
        if (asynchronous) {
          method = await guest.callAsync("method", value);
          owned = await guest.callAsync("owned", value);
        } else {
          method = guest.call("method", value);
          owned = guest.call("owned", value);
        }
        assert.equal(method, 2 * value + 1 + delta);
        assert.deepEqual(owned, Uint32Array.of(value, seed));
      }
    } finally {
      guest.dispose();
    }
  }
}
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`general body receipts preserve binary demand effects method edits and owning records (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-general-bodies-",
    });
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/logic.blot`;
    const archive = `${directory}/logic.blotdep`;
    await Deno.writeTextFile(entry, main);
    await Deno.writeTextFile(dependency, library("2", 1));
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, archive, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(packed.success, new TextDecoder().decode(packed.stdout) + new TextDecoder().decode(packed.stderr));
    const options = {
      executable,
      entry,
      prelude: null,
      cacheDirectory: false as const,
      codegenTier,
    };
    const retained = await createZigProjectCompiler(options);
    const compiled = await createZigProjectCompiler({
      ...options,
      dependencies: archive,
    });
    const prefix = "const earlier = fn (value: F32) => @f32.add value 1.0\n";
    try {
      for (
        const [seed, delta, inserted] of [
          ["2", 1, ""],
          ["3", 1, prefix],
          ["3", 2, prefix],
          ["missing_name", 2, prefix],
          ["2", 1, ""],
        ] as const
      ) {
        const fresh = await createZigProjectCompiler(options);
        try {
          const sources = {
            [entry]: main,
            [dependency]: library(seed, delta, inserted),
          };
          const expected = await fresh.build({ sources });
          for (const compiler of [retained, compiled]) {
            let checkpoint: Uint8Array<ArrayBuffer> | undefined;
            if (seed === "missing_name") {
              checkpoint = await compiler.exportCheckpoint();
            }
            const actual = await compiler.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert(!actual.success && !expected.success);
              assert.equal(
                seed,
                "missing_name",
                JSON.stringify(actual.diagnostics),
              );
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            assert.equal(
              actual.stats.nativeWorkSteps,
              expected.stats.nativeWorkSteps,
            );
            await observe(actual.bytes, Number(seed), delta);
          }
        } finally {
          await fresh.close();
        }
      }
    } finally {
      await retained.close();
      await compiled.close();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
