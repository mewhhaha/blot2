import { isAbsolute, relative, resolve, sep } from "node:path";
import type { AssetKind, GameEvent } from "./protocol.ts";

export type { AssetKind } from "./protocol.ts";
export interface PreparedAsset {
  readonly kind: AssetKind;
  destroy(): void;
}
export interface Mesh {
  readonly vertices: Float32Array<ArrayBuffer>;
  readonly indices: Uint32Array<ArrayBuffer>;
}
export interface Material {
  readonly shader: string;
  readonly texture: string | null;
  readonly color: readonly number[];
  readonly lighting: "unlit" | "lit";
}

export function parseMesh(bytes: Uint8Array): Mesh {
  const mesh = jsonRecord(bytes);
  const positions = numbers(mesh.positions, "positions");
  const normals = numbers(mesh.normals, "normals");
  const uvs = numbers(mesh.uvs, "uvs");
  const indices = numbers(mesh.indices, "indices");
  const count = positions.length / 3;
  if (
    !Number.isInteger(count) || count === 0 ||
    normals.length !== positions.length || uvs.length !== count * 2 ||
    indices.length === 0 || indices.length % 3 !== 0
  ) {
    throw new TypeError(
      "mesh requires matching position/normal/UV vertices and triangle indices",
    );
  }
  if (
    indices.some((index) =>
      !Number.isSafeInteger(index) || index < 0 || index >= count
    )
  ) throw new RangeError("mesh index is outside its vertex array");
  const vertices = new Float32Array(count * 8);
  for (let index = 0; index < count; index++) {
    const normal = normals.slice(index * 3, index * 3 + 3);
    if (Math.hypot(...normal) < 1e-8) {
      throw new RangeError("mesh normal must be nonzero");
    }
    vertices.set([
      ...positions.slice(index * 3, index * 3 + 3),
      ...normal,
      ...uvs.slice(index * 2, index * 2 + 2),
    ], index * 8);
  }
  if (vertices.some((value) => !Number.isFinite(value))) {
    throw new RangeError("mesh coordinates exceed float32 range");
  }
  return { vertices, indices: new Uint32Array(indices) };
}

export function parseMaterial(bytes: Uint8Array): Material {
  const material = jsonRecord(bytes);
  const shader = assetKey(material.shader, "shader");
  const texture = material.texture === undefined || material.texture === null
    ? null
    : assetKey(material.texture, "texture");
  const color = numbers(material.color, "color");
  if (
    color.length !== 4 || color.some((channel) => channel < 0 || channel > 1) ||
    color[3] !== 1
  ) {
    throw new RangeError(
      "opaque material color must be four 0..1 channels with alpha 1",
    );
  }
  if (material.lighting !== "lit" && material.lighting !== "unlit") {
    throw new TypeError("material lighting must be lit or unlit");
  }
  return { shader, texture, color, lighting: material.lighting };
}

function jsonRecord(bytes: Uint8Array): Record<string, unknown> {
  const value: unknown = JSON.parse(
    new TextDecoder("utf-8", { fatal: true }).decode(bytes),
  );
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError("asset JSON must be an object");
  }
  return value as Record<string, unknown>;
}
function numbers(value: unknown, field: string): number[] {
  if (
    !Array.isArray(value) ||
    value.some((entry) => typeof entry !== "number" || !Number.isFinite(entry))
  ) throw new TypeError(`asset ${field} must be an array of finite numbers`);
  return value;
}
function assetKey(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`material ${field} must be an asset key`);
  }
  return value;
}
export function resolveAssetPath(root: string, key: string): string {
  const path = resolve(root, key);
  const within = relative(root, path);
  if (
    key.length === 0 || isAbsolute(key) || within.length === 0 ||
    within === ".." || within.startsWith(`..${sep}`) || isAbsolute(within)
  ) throw new RangeError(`asset key must stay inside assets: ${key}`);
  return path;
}

function inside(root: string, path: string): boolean {
  const within = relative(root, path);
  return within.length > 0 && within !== ".." &&
    !within.startsWith(`..${sep}`) && !isAbsolute(within);
}

export function createAssetStore<T extends PreparedAsset>(options: {
  readonly rootDirectory: string;
  readonly prepare: (
    kind: AssetKind,
    key: string,
    bytes: Uint8Array,
    requireAsset: (kind: AssetKind, key: string) => Promise<T>,
  ) => T | Promise<T>;
  readonly event: (event: GameEvent) => void;
}) {
  const root = resolve(options.rootDirectory);
  interface AssetSlot {
    readonly kind: AssetKind;
    readonly key: string;
    readonly path: string;
    revision: number;
    current?: T;
    loading?: Promise<void>;
    failure?: string;
    readonly dependencies: Set<AssetSlot>;
    readonly dependents: Set<AssetSlot>;
  }
  const slots = new Map<string, AssetSlot>();
  const pending = new Set<Promise<void>>();
  let closed = false;
  let watcher: Deno.FsWatcher | undefined;
  let watching: Promise<void> | undefined;
  let debounce: ReturnType<typeof setTimeout> | undefined;
  let closing: Promise<void> | undefined;
  let canonicalRoot: string | undefined;
  let failure: { readonly error: unknown } | undefined;

  const healthy = (): void => {
    if (failure !== undefined) throw failure.error;
  };

  const open = (): void => {
    if (closed) throw new Error("asset store is closed");
    healthy();
  };

  const load = (slot: AssetSlot): void => {
    const revision = ++slot.revision;
    slot.failure = undefined;
    for (const dependency of slot.dependencies) {
      dependency.dependents.delete(slot);
    }
    slot.dependencies.clear();
    const work = (async () => {
      let prepared: T;
      try {
        canonicalRoot ??= await Deno.realPath(root);
        const actual = await Deno.realPath(slot.path);
        if (!inside(canonicalRoot, actual)) {
          throw new RangeError(
            `asset symlink leaves asset directory: ${slot.key}`,
          );
        }
        const bytes = await Deno.readFile(actual);
        if (closed || revision !== slot.revision) return;
        prepared = await options.prepare(
          slot.kind,
          slot.key,
          bytes,
          (kind, key) => {
            const dependency = slotFor(kind, key);
            const unseen = [dependency];
            const seen = new Set<AssetSlot>();
            while (unseen.length > 0) {
              const next = unseen.pop()!;
              if (next === slot) {
                throw new Error(
                  `cyclic asset dependency: ${slot.key} -> ${key}`,
                );
              }
              if (seen.has(next)) continue;
              seen.add(next);
              unseen.push(...next.dependencies);
            }
            if (revision === slot.revision) {
              slot.dependencies.add(dependency);
              dependency.dependents.add(slot);
            }
            return ready(dependency);
          },
        );
      } catch (error) {
        if (!closed && revision === slot.revision) {
          slot.failure = error instanceof Error ? error.message : String(error);
          options.event({
            tag: "AssetFailed",
            value: {
              kind: slot.kind,
              key: slot.key,
              revision,
              message: slot.failure,
            },
          });
        }
        return;
      }
      if (prepared.kind !== slot.kind) {
        prepared.destroy();
        throw new Error(
          `asset preparation returned ${prepared.kind} for ${slot.kind}`,
        );
      }
      if (closed || revision !== slot.revision) {
        prepared.destroy();
        return;
      }
      const previous = slot.current;
      slot.current = prepared;
      previous?.destroy();
      options.event({
        tag: "AssetReady",
        value: { kind: slot.kind, key: slot.key, revision },
      });
    })();
    slot.loading = work;
    pending.add(work);
    // Observe both outcomes without making a rejected, unobserved finally()
    // promise. Preparation errors are AssetFailed; invariant/callback errors
    // remain fatal and are rethrown by the next operation or watcher.
    void work.then(
      () => {
        pending.delete(work);
        if (slot.loading === work) slot.loading = undefined;
      },
      (error) => {
        pending.delete(work);
        if (slot.loading === work) slot.loading = undefined;
        failure ??= { error };
        watcher?.close();
      },
    );
  };

  const slotFor = (kind: AssetKind, key: string): AssetSlot => {
    open();
    const path = resolveAssetPath(root, key);
    const identity = `${kind}:${path}`;
    let slot = slots.get(identity);
    if (slot === undefined) {
      slot = {
        kind,
        key,
        path,
        revision: 0,
        dependencies: new Set(),
        dependents: new Set(),
      };
      slots.set(identity, slot);
      load(slot);
    }
    return slot;
  };

  const ready = async (slot: AssetSlot): Promise<T> => {
    while (slot.current === undefined && slot.loading !== undefined) {
      await slot.loading;
      open();
    }
    if (slot.current === undefined) {
      throw new Error(
        `asset dependency ${slot.key} is unavailable: ${slot.failure}`,
      );
    }
    return slot.current;
  };

  const reload = (paths: readonly string[]): void => {
    open();
    const changed = new Set(paths.map((path) => resolve(path)));
    const affected = new Set<AssetSlot>();
    for (const slot of slots.values()) {
      if (
        [...changed].some((path) =>
          path === slot.path || inside(path, slot.path)
        )
      ) {
        affected.add(slot);
      }
    }
    // Collect the closure before load() replaces any dependency edges.
    for (const slot of affected) {
      for (const dependent of slot.dependents) affected.add(dependent);
    }
    for (const slot of affected) load(slot);
  };

  return {
    get(kind: AssetKind, key: string): T | undefined {
      return slotFor(kind, key).current;
    },
    reload,
    async idle(): Promise<void> {
      healthy();
      while (pending.size > 0) await Promise.all([...pending]);
      healthy();
    },
    stats() {
      return {
        resident:
          [...slots.values()].filter((slot) => slot.current !== undefined)
            .length,
        pending: pending.size,
      };
    },
    watch(): Promise<void> {
      open();
      if (watching !== undefined) return watching;
      watcher = Deno.watchFs(root, { recursive: true });
      const current = watcher;
      watching = (async () => {
        const changed = new Set<string>();
        try {
          for await (const event of current) {
            if (closed) break;
            for (const path of event.paths) changed.add(path);
            if (debounce !== undefined) clearTimeout(debounce);
            debounce = setTimeout(() => {
              const paths = [...changed];
              changed.clear();
              debounce = undefined;
              if (!closed) reload(paths);
            }, 75);
          }
        } catch (error) {
          healthy();
          if (!closed) throw error;
        } finally {
          if (debounce !== undefined) clearTimeout(debounce);
          current.close();
        }
        healthy();
      })();
      return watching;
    },
    close(): Promise<void> {
      if (closing !== undefined) return closing;
      closed = true;
      if (debounce !== undefined) clearTimeout(debounce);
      watcher?.close();
      closing = (async () => {
        const errors: unknown[] = [];
        try {
          await watching;
        } catch (error) {
          errors.push(error);
        } finally {
          await Promise.allSettled([...pending]);
          for (const slot of slots.values()) {
            try {
              slot.current?.destroy();
            } catch (error) {
              errors.push(error);
            }
          }
          slots.clear();
        }
        if (failure !== undefined && !errors.includes(failure.error)) {
          errors.push(failure.error);
        }
        if (errors.length > 0) {
          throw new AggregateError(errors, "asset shutdown failed");
        }
      })();
      return closing;
    },
  };
}
