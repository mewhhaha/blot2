import { basename, dirname, resolve } from "node:path";
import type { EcsArtifact, EcsStorage, TypeId } from "../../compiler/host.ts";
import type { EcsWorldSeed } from "../../compiler/ecs_runtime.ts";

export const MAX_SNAPSHOT_BYTES = 8 * 1024 * 1024;
export const MAX_SNAPSHOT_ENTITIES = 100_000;

interface StorageSchema {
  readonly identity: TypeId;
  readonly kind: EcsStorage["storage"]["$"];
  readonly scalar: EcsStorage["scalar"]["$"];
}

function record(
  value: unknown,
  keys: readonly string[],
  label: string,
): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError(`${label} must be an object`);
  }
  if (
    Object.keys(value).length !== keys.length ||
    keys.some((key) => !Object.hasOwn(value, key))
  ) {
    throw new TypeError(
      `${label} must have exactly these fields: ${keys.join(", ")}`,
    );
  }
  return value as Record<string, unknown>;
}

function identity(value: unknown, label: string): TypeId {
  const fields = record(value, ["$", "module_name", "declaration"], label);
  if (
    fields.$ !== "TypeId" ||
    typeof fields.module_name !== "string" ||
    !fields.module_name.isWellFormed() ||
    typeof fields.declaration !== "string" || !fields.declaration.isWellFormed()
  ) {
    throw new TypeError(
      `${label} must be a nominal TypeId with valid Unicode names`,
    );
  }
  return {
    $: "TypeId",
    module_name: fields.module_name,
    declaration: fields.declaration,
  };
}

const identityKey = (type: TypeId): string =>
  JSON.stringify([type.module_name, type.declaration]);
const identityLabel = (type: TypeId): string =>
  `${type.module_name}::${type.declaration}`;
function byIdentity(
  a: { readonly identity: TypeId },
  b: { readonly identity: TypeId },
): number {
  for (const field of ["module_name", "declaration"] as const) {
    if (a.identity[field] < b.identity[field]) return -1;
    if (a.identity[field] > b.identity[field]) return 1;
  }
  return 0;
}

function schema(value: unknown): StorageSchema[] {
  if (!Array.isArray(value)) {
    throw new TypeError("snapshot schema must be an array");
  }
  const seen = new Set<string>();
  return value.map((entry, index): StorageSchema => {
    const fields = record(
      entry,
      ["identity", "kind", "scalar"],
      `snapshot schema[${index}]`,
    );
    const type = identity(
      fields.identity,
      `snapshot schema[${index}].identity`,
    );
    const key = identityKey(type);
    if (seen.has(key)) {
      throw new TypeError(
        `duplicate snapshot schema identity ${identityLabel(type)}`,
      );
    }
    seen.add(key);
    if (fields.kind !== "Component" && fields.kind !== "Resource") {
      throw new TypeError(`invalid storage kind for ${identityLabel(type)}`);
    }
    if (fields.scalar !== "U32Scalar" && fields.scalar !== "F32Scalar") {
      throw new TypeError(`invalid scalar layout for ${identityLabel(type)}`);
    }
    return { identity: type, kind: fields.kind, scalar: fields.scalar };
  }).sort(byIdentity);
}

function artifactSchema(artifact: EcsArtifact): StorageSchema[] {
  return schema(artifact.storage.map((entry) => ({
    identity: entry.identity,
    kind: entry.storage.$,
    scalar: entry.scalar.$,
  })));
}

function sameSchema(
  actual: readonly StorageSchema[],
  expected: readonly StorageSchema[],
): void {
  if (actual.length !== expected.length) {
    throw new TypeError(
      "snapshot storage schema differs from this build; a migration is required",
    );
  }
  for (const [index, entry] of actual.entries()) {
    const required = expected[index];
    if (
      identityKey(entry.identity) !== identityKey(required.identity) ||
      entry.kind !== required.kind || entry.scalar !== required.scalar
    ) {
      throw new TypeError(
        `snapshot storage schema differs at ${
          identityLabel(entry.identity)
        }; a migration is required`,
      );
    }
  }
}

function entityCount(value: unknown): number {
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < 0 ||
    value > MAX_SNAPSHOT_ENTITIES
  ) {
    throw new RangeError(
      `snapshot entityCount must be an integer in 0..${MAX_SNAPSHOT_ENTITIES}`,
    );
  }
  return value === 0 ? 0 : value;
}

function scalar(
  value: unknown,
  layout: StorageSchema["scalar"],
  label: string,
): number {
  // JSON's numeric encoding loses negative zero. This is the only scalar tag,
  // and it is accepted only in F32 component/resource positions, never U32.
  if (layout === "F32Scalar" && value !== null && typeof value === "object") {
    const fields = record(value, ["$f32"], label);
    if (fields.$f32 !== "-0") {
      throw new TypeError(`${label} has an invalid F32 scalar tag`);
    }
    return -0;
  }
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new TypeError(
      `${label} must be a finite ${
        layout === "F32Scalar" ? "F32" : "U32"
      } number`,
    );
  }
  if (layout === "U32Scalar") {
    if (!Number.isInteger(value) || value < 0 || value > 0xffff_ffff) {
      throw new RangeError(`${label} must be a U32 in 0..2^32-1`);
    }
    return value === 0 ? 0 : value;
  }
  if (!Number.isFinite(Math.fround(value))) {
    throw new RangeError(`${label} exceeds finite F32 range`);
  }
  return value;
}

function worldSeed(
  value: unknown,
  storage: readonly StorageSchema[],
): EcsWorldSeed {
  const fields = record(value, [
    "entityCount",
    "alive",
    "components",
    "resources",
  ], "snapshot world");
  const count = entityCount(fields.entityCount);
  if (
    !Array.isArray(fields.alive) || fields.alive.length !== count ||
    fields.alive.some((alive) => typeof alive !== "boolean")
  ) {
    throw new TypeError(
      `snapshot alive must contain exactly ${count} booleans`,
    );
  }
  const alive: boolean[] = fields.alive.slice();
  if (!Array.isArray(fields.components) || !Array.isArray(fields.resources)) {
    throw new TypeError("snapshot components and resources must be arrays");
  }
  const byKey = new Map(
    storage.map((entry) => [identityKey(entry.identity), entry]),
  );
  const seen = new Set<string>();
  const lookup = (
    value: unknown,
    kind: StorageSchema["kind"],
  ): StorageSchema => {
    const type = identity(value, `snapshot ${kind} identity`);
    const key = identityKey(type);
    const entry = byKey.get(key);
    if (entry === undefined || entry.kind !== kind) {
      throw new TypeError(`unknown snapshot ${kind} ${identityLabel(type)}`);
    }
    if (seen.has(key)) {
      throw new TypeError(`duplicate snapshot storage ${identityLabel(type)}`);
    }
    seen.add(key);
    return entry;
  };
  const components = fields.components.map((value, index) => {
    const column = record(
      value,
      ["identity", "values"],
      `snapshot components[${index}]`,
    );
    const entry = lookup(column.identity, "Component");
    const label = identityLabel(entry.identity);
    if (!Array.isArray(column.values) || column.values.length !== count) {
      throw new TypeError(
        `snapshot component ${label} needs exactly ${count} entity slots`,
      );
    }
    const values = column.values.map((value, entity): number | null => {
      if (value === null) return null;
      if (!alive[entity]) {
        throw new TypeError(
          `snapshot component ${label} is present on removed entity ${entity}`,
        );
      }
      return scalar(
        value,
        entry.scalar,
        `snapshot component ${label}[${entity}]`,
      );
    });
    return { identity: entry.identity, values };
  }).sort(byIdentity);
  if (
    components.length !==
      storage.filter((entry) => entry.kind === "Component").length
  ) {
    throw new TypeError(
      "snapshot must contain every registered component column",
    );
  }
  const resources = fields.resources.map((value, index) => {
    const cell = record(
      value,
      ["identity", "value"],
      `snapshot resources[${index}]`,
    );
    const entry = lookup(cell.identity, "Resource");
    return {
      identity: entry.identity,
      value: scalar(
        cell.value,
        entry.scalar,
        `snapshot resource ${identityLabel(entry.identity)}`,
      ),
    };
  }).sort(byIdentity);
  return { entityCount: count, alive, components, resources };
}

/**
 * Version 1 stores sorted nominal schemas and detached world seeds. An F32 -0
 * uses {"$f32":"-0"}; NaN and infinities are rejected instead of becoming null.
 * The adjacent temporary is fully written and synced before atomic rename.
 */
export async function writeWorldSnapshot<
  World extends { readonly entityCount: number },
>(
  path: string,
  options: {
    readonly artifact: EcsArtifact;
    readonly runtime: { exportWorld(world: World): EcsWorldSeed };
    readonly world: World;
  },
): Promise<void> {
  entityCount(options.world.entityCount);
  const storage = artifactSchema(options.artifact);
  const world = worldSeed(options.runtime.exportWorld(options.world), storage);
  const bytes = new TextEncoder().encode(JSON.stringify({
    format: "blot-ecs-world",
    version: 1,
    schema: storage,
    world,
  }, (_key, value) => Object.is(value, -0) ? { $f32: "-0" } : value));
  if (bytes.length > MAX_SNAPSHOT_BYTES) {
    throw new RangeError(
      `snapshot exceeds ${MAX_SNAPSHOT_BYTES} bytes (8 MiB)`,
    );
  }
  const destination = resolve(path);
  const temporary = await Deno.makeTempFile({
    dir: dirname(destination),
    prefix: `.${basename(destination)}.tmp-`,
  });
  try {
    const file = await Deno.open(temporary, { write: true, truncate: true });
    try {
      let written = 0;
      while (written < bytes.length) {
        const count = await file.write(bytes.subarray(written));
        if (count === 0) {
          throw new Error("snapshot temporary write made no progress");
        }
        written += count;
      }
      await file.sync();
    } finally {
      file.close();
    }
    await Deno.rename(temporary, destination);
  } catch (cause) {
    try {
      await Deno.remove(temporary);
    } catch (cleanup) {
      throw new AggregateError(
        [cause, cleanup],
        "snapshot publication and temporary cleanup both failed",
      );
    }
    throw cause;
  }
}

export async function readWorldSnapshot<World>(
  path: string,
  artifact: EcsArtifact,
  runtime: { createWorld(seed: EcsWorldSeed): World },
): Promise<World> {
  const expected = artifactSchema(artifact);
  const file = await Deno.open(path, { read: true });
  let text: string;
  try {
    const stat = await file.stat();
    if (!stat.isFile) {
      throw new TypeError("snapshot path must be a regular file");
    }
    if (stat.size > MAX_SNAPSHOT_BYTES) {
      throw new RangeError("snapshot exceeds 8 MiB");
    }
    // An extra byte detects a file that grew after stat() without unbounded reads.
    const bytes = new Uint8Array(MAX_SNAPSHOT_BYTES + 1);
    let length = 0;
    while (true) {
      const read = await file.read(bytes.subarray(length));
      if (read === null) break;
      length += read;
      if (length > MAX_SNAPSHOT_BYTES) {
        throw new RangeError("snapshot exceeds 8 MiB");
      }
    }
    text = new TextDecoder("utf-8", { fatal: true }).decode(
      bytes.subarray(0, length),
    );
  } finally {
    file.close();
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (cause) {
    throw new TypeError(`snapshot ${path} is not valid JSON`, { cause });
  }
  const fields = record(
    parsed,
    ["format", "version", "schema", "world"],
    "snapshot",
  );
  if (fields.format !== "blot-ecs-world" || fields.version !== 1) {
    throw new TypeError(
      "snapshot format/version is not supported (expected blot-ecs-world version 1)",
    );
  }
  sameSchema(schema(fields.schema), expected);
  return runtime.createWorld(worldSeed(fields.world, expected));
}
