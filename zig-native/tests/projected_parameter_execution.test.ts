import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const source =
  `type RootRow is data = $RootRow {clips: &[U32], selected: Ref U32}
const make_callback = func (counter: Ref U32) -> state => return do:
  @storage.write counter (@u32.add (@storage.load counter) 1)
  return func (argument: U32): U32 => return @u32.add state.value argument
const read_state = func (access: {editor: Array RootRow, editor_clips: Array RootRow, tick: U32 -> U32, draw: U32 -> U32, save: U32 -> U32, close: U32 -> U32}) => return do:
  let editor: RootRow = access.editor[0]
  let clips: RootRow = access.editor_clips[0]
  return @u32.add editor.clips[0] (@storage.load clips.selected)
entry const answer = func (input: U32): Array U32 => return do:
  let counter: Array U32 = #[0]
  let counted = @storage.at counter 0
  let first: Array U32 = #[input]
  let second: Array U32 = #[10]
  let first_rows: Array RootRow = #[$RootRow {clips: &first[0..1], selected: @storage.at second 0}]
  let second_rows: Array RootRow = #[$RootRow {clips: &second[0..1], selected: @storage.at first 0}]
  let left = {editor: first_rows, editor_clips: second_rows, tick: make_callback counted {value: input}, draw: make_callback counted {value: 3}, save: make_callback counted {value: 5}, close: make_callback counted {value: 7}}
  let right = {editor: second_rows, editor_clips: first_rows, tick: make_callback counted {value: 11}, draw: make_callback counted {value: 13}, save: make_callback counted {value: 17}, close: make_callback counted {value: 19}}
  return #[@u32.add (read_state left) (read_state right), counter[0]]
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`projected anonymous parameters preserve nested owners and unused callback evaluation (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-projected-parameter-",
    });
    const entry = `${directory}/main.blot`;
    let compiler:
      | Awaited<ReturnType<typeof createZigProjectCompiler>>
      | undefined;
    try {
      compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
        startupTimeoutMs: 5_000,
      });
      const built = await compiler.build({
        sources: { [entry]: source },
        signal: AbortSignal.timeout(5_000),
      });
      assert(built.success, JSON.stringify(built));
      const work = built.stats.workCounters as Record<string, number>;
      assert(work.scoped_owner_graph_definitions >= 1, JSON.stringify(work));
      assert(work.scoped_owner_graph_hits >= 1, JSON.stringify(work));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        try {
          for (const input of [0, 1, 42, 0x7fffffff, 0xffffffff, 0]) {
            let actual;
            if (asynchronous) actual = await guest.callAsync("answer", input);
            else actual = guest.call("answer", input);
            assert.deepEqual(actual, new Uint32Array([input * 2 + 20, 8]));
          }
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler?.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

const selectedCallbackBody = `
const read_state = func (access: {editor: Ref U32, editor_clips: Ref U32, tick: U32 -> U32, draw: U32 -> U32, save: U32 -> U32, close: U32 -> U32}) => return do:
  let editor: Ref U32 = access.editor
  return @u32.add (@storage.load editor) (access.tick 1)

entry const answer = func (input: U32): U32 => return do:
  let first: Array U32 = #[input]
  let second: Array U32 = #[10]
  let left = {editor: @storage.at first 0, editor_clips: @storage.at second 0, tick: make_callback {value: input}, draw: make_callback {value: 3}, save: make_callback {value: 5}, close: make_callback {value: 7}}
  let right = {editor: @storage.at second 0, editor_clips: @storage.at first 0, tick: make_callback {value: 11}, draw: make_callback {value: 13}, save: make_callback {value: 17}, close: make_callback {value: 19}}

  return @u32.add (read_state left) (read_state right)
`;

const selectedCallbacks = [
  {
    name: "named source-checked partial",
    factory:
      "const make_callback = func state => return func (argument: U32): U32 => return @u32.add state.value argument",
    shared: true,
  },
  {
    name: "literal with captured source goals",
    factory: `const make_callback = func state => return do:
  let captured = state
  return func (argument: U32): U32 => return @u32.add captured.value argument`,
    shared: false,
  },
];
for (const codegenTier of ["development", "optimized"] as const) {
  for (const fixture of selectedCallbacks) {
    Deno.test(`projected selected callback ${fixture.name} preserves source proof (${codegenTier})`, async () => {
      const directory = await Deno.makeTempDir({
        prefix: "blot-selected-callback-",
      });
      const entry = `${directory}/main.blot`;
      const compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
        profileTrace: true,
      });
      try {
        const built = await compiler.build({
          sources: { [entry]: `${fixture.factory}\n${selectedCallbackBody}` },
        });
        assert(built.success, JSON.stringify(built));
        assert(WebAssembly.validate(built.bytes));
        const work = built.stats.workCounters as Record<string, number>;
        if (fixture.shared) {
          assert.equal(work.scoped_owner_graph_definitions, 1);
          assert.equal(work.scoped_plain_plan_definitions, 1);
          assert.equal(work.scoped_completed_plan_definitions, 2);
          assert(work.scoped_owner_graph_hits >= 1);
        } else {
          assert.equal(work.scoped_owner_graph_definitions, 0);
          assert.equal(work.scoped_plain_plan_definitions, 1);
          assert.equal(work.scoped_completed_plan_attempts, 1);
          assert(
            compiler.profileProgress?.events.some((event) =>
              event.kind === "detail" &&
              event.stage === "descriptor.shared.callback-evidence"
            ),
          );
        }
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            for (const input of [0, 7, 42, 0xffffffff, 0]) {
              let actual;
              if (asynchronous) actual = await guest.callAsync("answer", input);
              else actual = guest.call("answer", input);
              assert.equal(actual, (input * 2 + 23) >>> 0);
            }
          } finally {
            guest.dispose();
          }
        }
      } finally {
        await compiler.dispose();
        await Deno.remove(directory, { recursive: true });
      }
    });
  }
}

const nominalHooks =
  `type Hooks is data = $Hooks {step: U32 -> U32 ! {}, spare: U32 -> U32 ! {}}
const make = func (counter: Ref U32) -> (state: U32) => return do:
  @storage.write counter (@u32.add (@storage.load counter) 1)
  return func (argument: U32): U32 => return @u32.add state argument
const read = func (access: {picked: Ref U32, other: Ref U32, unused: Ref U32, hooks: Hooks}): U32 => return
  @u32.add (access.hooks.step (@storage.load access.picked)) (@storage.load access.other)
entry const answer = func (input: U32): Array U32 => return do:
  let counted: Array U32 = #[0]
  let counter = @storage.at counted 0
  let first: Array U32 = #[input]
  let second: Array U32 = #[10]
  let left_hooks = $Hooks {step: make counter input, spare: make counter 3}
  let right_hooks = $Hooks {step: make counter 11, spare: make counter 17}
  let left = {picked: @storage.at first 0, other: @storage.at second 0, unused: @storage.at second 0, hooks: left_hooks}
  let right = {picked: @storage.at second 0, other: @storage.at first 0, unused: @storage.at first 0, hooks: right_hooks}
  return #[read left, read right, counted[0]]
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`nominal callback bundles retain captures evaluation and caller roots (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-nominal-hooks-" });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier,
      startupTimeoutMs: 5000,
    });
    try {
      const built = await compiler.build({
        sources: { [entry]: nominalHooks },
        signal: AbortSignal.timeout(5000),
      });
      assert(built.success, JSON.stringify(built));
      const work = built.stats.workCounters as Record<string, number>;
      assert(work.scoped_projected_parameter_fields >= 2, JSON.stringify(work));
      assert(work.scoped_owner_graph_hits >= 1, JSON.stringify(work));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        try {
          for (const input of [0, 7, 42, 0xffffffff]) {
            let actual;
            if (asynchronous) actual = await guest.callAsync("answer", input);
            else actual = guest.call("answer", input);
            assert.deepEqual(
              actual,
              new Uint32Array([(input * 2 + 10) >>> 0, (input + 21) >>> 0, 4]),
            );
          }
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
