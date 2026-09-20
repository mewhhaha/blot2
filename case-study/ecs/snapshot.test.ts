import assert from "node:assert/strict";
import { join } from "node:path";
import {
  createEcsRuntime,
  type EcsRuntime,
} from "../../compiler/ecs_runtime.ts";
import type { EcsArtifact, EcsStorage, TypeId } from "../../compiler/host.ts";
import { createNativeCompiler } from "../../compiler/native.ts";
import { createGame, renderGame, stepGame } from "./game.ts";
import { validateFrame } from "./renderer.ts";
import {
  MAX_SNAPSHOT_BYTES,
  MAX_SNAPSHOT_ENTITIES,
  readWorldSnapshot,
  writeWorldSnapshot,
} from "./snapshot.ts";

const position: TypeId = {
  $: "TypeId",
  module_name: "main",
  declaration: "Position",
};
const otherPosition: TypeId = { ...position, module_name: "other" };
const counter: TypeId = {
  $: "TypeId",
  module_name: "main",
  declaration: "Counter",
};
const optional: TypeId = {
  $: "TypeId",
  module_name: "main",
  declaration: "Optional",
};
const storage: readonly EcsStorage[] = [
  {
    identity: otherPosition,
    storage: { $: "Component" },
    scalar: { $: "U32Scalar" },
    tag: 12,
    constructor: "OtherPosition",
  },
  {
    identity: optional,
    storage: { $: "Resource" },
    scalar: { $: "F32Scalar" },
    tag: 7,
    constructor: "Optional",
  },
  {
    identity: counter,
    storage: { $: "Resource" },
    scalar: { $: "U32Scalar" },
    tag: 3,
    constructor: "Counter",
  },
  {
    identity: position,
    storage: { $: "Component" },
    scalar: { $: "F32Scalar" },
    tag: 1,
    constructor: "Position",
  },
];

Deno.test("snapshot round-trips a source-owned guest world and preserves entity allocation after load", async () => {
  const compiler = await createNativeCompiler();
  const root = await Deno.makeTempDir({ prefix: "blot-guest-snapshot-" });
  try {
    const source = await Deno.readTextFile(
      new URL("./fixtures/lanterns.blot", import.meta.url),
    );
    const artifact = await compiler.compileApp(source);
    const initial = await createGame(artifact);
    const viewport = { width: 640, height: 480 };
    const retired = stepGame(initial, {
      viewport,
      dt: 0.1,
      events: [{ tag: "KeyDown", value: "x" }],
      pick: () => undefined,
    });
    const before = retired.runtime.exportWorld(retired.world);
    const path = join(root, "guest.json");
    await writeWorldSnapshot(path, retired);
    const restored = await readWorldSnapshot(path, artifact, retired.runtime);
    assert.deepEqual(retired.runtime.exportWorld(restored), before);
    assert.equal(retired.runtime.isAlive(restored, 0), false);
    assert.equal(restored.entityCount, 3);
    const spawned = retired.runtime.event(restored, {
      event_kind: 1,
      key: "n".codePointAt(0),
    }).world;
    assert.equal(spawned.entityCount, 4);
    assert.equal(retired.runtime.isAlive(spawned, 0), false);
    assert.equal(retired.runtime.isAlive(spawned, 3), true);
    validateFrame(renderGame({ ...retired, world: spawned }, viewport));
    assert.deepEqual(retired.runtime.exportWorld(retired.world), before);
    assert.deepEqual(retired.runtime.exportWorld(restored), before);
    assert.equal(initial.world.entityCount, 3);
    assert.equal(initial.runtime.isAlive(initial.world, 0), true);
  } finally {
    await compiler.dispose();
    await Deno.remove(root, { recursive: true });
  }
});

function artifact(columns: readonly EcsStorage[] = storage): EcsArtifact {
  return {
    // No systems are needed to exercise the actual immutable world store.
    bytes: new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0]),
    storage: columns,
    analysis: {
      functions: [],
      constants: [],
      remaining_steps: 0n,
      world: {
        registrations: columns.map((entry) => ({
          $: "Descriptor",
          identity: entry.identity,
          storage: entry.storage,
        })),
        systems: [],
        batches: [],
      },
    },
  };
}

function seed(runtime: EcsRuntime) {
  return runtime.createWorld({
    entityCount: 4,
    alive: [true, false, true, true],
    components: [
      { identity: position, values: [1.25, null, -0, null] },
      { identity: otherPosition, values: [0xffff_ffff, null, null, 0] },
    ],
    resources: [{ identity: counter, value: 13 }],
  });
}

Deno.test("snapshot round-trips nominal columns, missing resources, removed IDs, and negative zero", async () => {
  const root = await Deno.makeTempDir({ prefix: "blot-ecs-snapshot-" });
  const compiled = artifact();
  const runtime = await createEcsRuntime(compiled);
  const initial = seed(runtime);
  const before = runtime.exportWorld(initial);
  const path = join(root, "world.json");
  try {
    await writeWorldSnapshot(path, {
      artifact: compiled,
      runtime,
      world: initial,
    });
    const encoded = await Deno.readTextFile(path);
    assert.match(encoded, /"\$f32":"-0"/);
    assert.doesNotMatch(encoded, /"tag"|"constructor"/);
    const restored = await readWorldSnapshot(path, compiled, runtime);
    assert.notEqual(restored, initial);
    assert.deepEqual(runtime.exportWorld(restored), before);
    assert.equal(runtime.isAlive(restored, 1), false);
    assert.equal(
      runtime.readComponent(restored, otherPosition, 0),
      0xffff_ffff,
    );
    assert.ok(Object.is(runtime.readComponent(restored, position, 2), -0));
    assert.throws(
      () => runtime.readResource(restored, optional),
      /not been seeded/,
    );
    const added = runtime.spawn(restored, { entityCount: 1 });
    assert.deepEqual(
      added.entities,
      [4],
      "removed IDs are not reused after load",
    );
    assert.deepEqual(runtime.exportWorld(initial), before);
    assert.deepEqual(runtime.exportWorld(restored), before);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("snapshot schema ignores tag order and constructor spellings but not nominal identities", async () => {
  const root = await Deno.makeTempDir({ prefix: "blot-ecs-snapshot-schema-" });
  const original = artifact();
  const changed = artifact(
    storage.toReversed().map((entry, index) => ({
      ...entry,
      tag: index + 100,
      constructor: `Changed${index}`,
    })),
  );
  const firstRuntime = await createEcsRuntime(original);
  const secondRuntime = await createEcsRuntime(changed);
  const path = join(root, "world.json");
  try {
    await writeWorldSnapshot(path, {
      artifact: original,
      runtime: firstRuntime,
      world: seed(firstRuntime),
    });
    const firstBytes = await Deno.readTextFile(path);
    const restored = await readWorldSnapshot(path, changed, secondRuntime);
    assert.equal(secondRuntime.readComponent(restored, position, 0), 1.25);
    assert.equal(
      secondRuntime.readComponent(restored, otherPosition, 0),
      0xffff_ffff,
    );
    await writeWorldSnapshot(path, {
      artifact: changed,
      runtime: secondRuntime,
      world: restored,
    });
    assert.equal(
      await Deno.readTextFile(path),
      firstBytes,
      "canonical bytes do not depend on compiler tags or registration order",
    );
    const mismatch = artifact(
      storage.map((entry) =>
        entry.identity === position
          ? { ...entry, scalar: { $: "U32Scalar" } }
          : entry
      ),
    );
    await assert.rejects(
      () => readWorldSnapshot(path, mismatch, secondRuntime),
      /schema differs/,
    );
    const missing = artifact(storage.slice(1));
    await assert.rejects(
      () => readWorldSnapshot(path, missing, secondRuntime),
      /schema differs/,
    );
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("snapshot rejects malformed JSON, schema, dimensions, identities, and scalar values before creating a world", async () => {
  const root = await Deno.makeTempDir({ prefix: "blot-ecs-snapshot-invalid-" });
  const compiled = artifact();
  const runtime = await createEcsRuntime(compiled);
  const initial = seed(runtime);
  const unchanged = runtime.exportWorld(initial);
  const path = join(root, "world.json");
  let creates = 0;
  const observing: EcsRuntime = {
    ...runtime,
    createWorld(value) {
      creates++;
      return runtime.createWorld(value);
    },
  };
  try {
    await writeWorldSnapshot(path, {
      artifact: compiled,
      runtime,
      world: initial,
    });
    const valid = await Deno.readTextFile(path);
    const invalid: [string, RegExp][] = [
      ["not JSON", /valid JSON/],
      ["null", /object/],
      ["[]", /object/],
    ];
    let document = JSON.parse(valid);
    document.version = 2;
    invalid.push([JSON.stringify(document), /version/]);
    document = JSON.parse(valid);
    document.unexpected = true;
    invalid.push([JSON.stringify(document), /exactly/]);
    document = JSON.parse(valid);
    document.schema[0].scalar = "OtherScalar";
    invalid.push([JSON.stringify(document), /scalar layout/]);
    document = JSON.parse(valid);
    document.schema[0].kind = "Component";
    invalid.push([JSON.stringify(document), /schema differs/]);
    document = JSON.parse(valid);
    document.schema.push(document.schema[0]);
    invalid.push([JSON.stringify(document), /duplicate/]);
    document = JSON.parse(valid);
    document.schema[0].identity.module_name = "\ud800";
    invalid.push([JSON.stringify(document), /Unicode/]);
    document = JSON.parse(valid);
    document.world.entityCount = MAX_SNAPSHOT_ENTITIES + 1;
    invalid.push([JSON.stringify(document), /entityCount/]);
    document = JSON.parse(valid);
    document.world.alive.pop();
    invalid.push([JSON.stringify(document), /booleans/]);
    document = JSON.parse(valid);
    document.world.alive[0] = 1;
    invalid.push([JSON.stringify(document), /booleans/]);
    document = JSON.parse(valid);
    document.world.components[0].values.pop();
    invalid.push([JSON.stringify(document), /exactly 4/]);
    document = JSON.parse(valid);
    document.world.components[0].values[1] = 10;
    invalid.push([JSON.stringify(document), /removed entity/]);
    document = JSON.parse(valid);
    document.world.components[0].values[0] = { $f32: "NaN" };
    invalid.push([JSON.stringify(document), /F32 scalar tag/]);
    document = JSON.parse(valid);
    document.world.components[0].values[0] = 1e100;
    invalid.push([JSON.stringify(document), /finite F32 range/]);
    document = JSON.parse(valid);
    document.world.components[1].values[0] = -1;
    invalid.push([JSON.stringify(document), /U32/]);
    document = JSON.parse(valid);
    document.world.components[1].values[0] = { $f32: "-0" };
    invalid.push([JSON.stringify(document), /U32/]);
    document = JSON.parse(valid);
    document.world.components[0].identity.module_name = "missing";
    invalid.push([JSON.stringify(document), /unknown snapshot Component/]);
    document = JSON.parse(valid);
    document.world.components.pop();
    invalid.push([JSON.stringify(document), /every registered component/]);
    document = JSON.parse(valid);
    document.world.resources.push(document.world.resources[0]);
    invalid.push([JSON.stringify(document), /duplicate/]);
    document = JSON.parse(valid);
    document.world.resources[0].value = "13";
    invalid.push([JSON.stringify(document), /finite U32 number/]);
    invalid.push([
      valid.replace('"value":13', '"value":1e999'),
      /finite U32 number/,
    ]);
    for (const [contents, expected] of invalid) {
      await Deno.writeTextFile(path, contents);
      await assert.rejects(
        () => readWorldSnapshot(path, compiled, observing),
        expected,
      );
      assert.deepEqual(runtime.exportWorld(initial), unchanged);
    }
    assert.equal(creates, 0);
    await Deno.writeFile(path, new Uint8Array([255, 254, 128]));
    await assert.rejects(
      () => readWorldSnapshot(path, compiled, observing),
      TypeError,
    );
    assert.equal(creates, 0);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("snapshot write rejects nonfinite worlds and entity overflow without replacing the old file", async () => {
  const root = await Deno.makeTempDir({ prefix: "blot-ecs-snapshot-write-" });
  const compiled = artifact();
  const runtime = await createEcsRuntime(compiled);
  const initial = seed(runtime);
  const path = join(root, "world.json");
  try {
    await writeWorldSnapshot(path, {
      artifact: compiled,
      runtime,
      world: initial,
    });
    const previous = await Deno.readTextFile(path);
    for (const value of [NaN, Infinity, -Infinity]) {
      const invalid = runtime.withResources(initial, [{
        identity: optional,
        value,
      }]);
      await assert.rejects(
        () =>
          writeWorldSnapshot(path, {
            artifact: compiled,
            runtime,
            world: invalid,
          }),
        /finite F32/,
      );
      assert.equal(await Deno.readTextFile(path), previous);
    }
    const tooMany = runtime.createWorld({
      entityCount: MAX_SNAPSHOT_ENTITIES + 1,
    });
    await assert.rejects(
      () =>
        writeWorldSnapshot(path, {
          artifact: compiled,
          runtime,
          world: tooMany,
        }),
      /entityCount/,
    );
    assert.equal(await Deno.readTextFile(path), previous);
    assert.deepEqual(
      Array.from(Deno.readDirSync(root), (entry) => entry.name),
      ["world.json"],
    );
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("snapshot bounds reads and writes to 8 MiB and cleans a failed adjacent rename", async () => {
  const root = await Deno.makeTempDir({ prefix: "blot-ecs-snapshot-bounds-" });
  const compiled = artifact();
  const runtime = await createEcsRuntime(compiled);
  const path = join(root, "world.json");
  try {
    const oversized = await Deno.open(path, { create: true, write: true });
    await oversized.truncate(MAX_SNAPSHOT_BYTES + 1);
    oversized.close();
    await assert.rejects(
      () => readWorldSnapshot(path, compiled, runtime),
      /8 MiB/,
    );
    const denseArtifact = artifact(Array.from({ length: 18 }, (_, index) => ({
      identity: { ...position, declaration: `Column${index}` },
      storage: { $: "Component" },
      scalar: { $: "U32Scalar" },
      tag: index,
      constructor: `Column${index}`,
    })));
    const denseRuntime = await createEcsRuntime(denseArtifact);
    const dense = denseRuntime.createWorld({
      entityCount: MAX_SNAPSHOT_ENTITIES,
    });
    await assert.rejects(
      () =>
        writeWorldSnapshot(path, {
          artifact: denseArtifact,
          runtime: denseRuntime,
          world: dense,
        }),
      /8 MiB/,
    );
    assert.equal(
      (await Deno.stat(path)).size,
      MAX_SNAPSHOT_BYTES + 1,
      "failed encoding leaves the original path alone",
    );
    const directory = join(root, "existing-directory");
    await Deno.mkdir(directory);
    await Deno.writeTextFile(join(directory, "keep"), "untouched");
    await assert.rejects(() =>
      writeWorldSnapshot(directory, {
        artifact: compiled,
        runtime,
        world: seed(runtime),
      })
    );
    assert.equal(await Deno.readTextFile(join(directory, "keep")), "untouched");
    assert.deepEqual(
      Array.from(Deno.readDirSync(root), (entry) => entry.name).sort(),
      ["existing-directory", "world.json"],
    );
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("snapshot supports empty worlds and preserves a missing-file error", async () => {
  const root = await Deno.makeTempDir({ prefix: "blot-ecs-snapshot-empty-" });
  const compiled = artifact([]);
  const runtime = await createEcsRuntime(compiled);
  const initial = runtime.createWorld({ entityCount: 0 });
  const path = join(root, "world.json");
  try {
    await assert.rejects(
      () => readWorldSnapshot(path, compiled, runtime),
      Deno.errors.NotFound,
    );
    await writeWorldSnapshot(path, {
      artifact: compiled,
      runtime,
      world: initial,
    });
    const restored = await readWorldSnapshot(path, compiled, runtime);
    assert.deepEqual(runtime.exportWorld(restored), {
      entityCount: 0,
      alive: [],
      components: [],
      resources: [],
    });
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});
