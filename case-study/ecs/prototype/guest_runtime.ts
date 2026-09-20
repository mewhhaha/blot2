// Archived compiler-coupled prototype; not part of the current compiler.
import type { EcsArtifact, EcsStorage, TypeId } from "./host.ts";
import type { EcsWorldSeed } from "./ecs_runtime.ts";

export const guestAbiVersion = 1;
export const guestEntityCapacity = 4096;
export const guestDrawCapacity = 8192;
export const guestCommandCapacity = 64;
export const noGuestEntity = 0xffffffff;
const worldBase = 0x01000000;
const bankPrefix = 16 + guestEntityCapacity * 4;
const align64 = (value: number) => Math.ceil(value / 64) * 64;
const identityKey = (identity: TypeId) =>
  JSON.stringify([identity.module_name, identity.declaration]);

export interface GuestInput {
  readonly event_kind?: number;
  readonly key?: number;
  readonly button?: number;
  readonly picked?: number;
  readonly pick_valid?: boolean;
  readonly pointer_x?: number;
  readonly pointer_y?: number;
  readonly wheel_delta?: number;
  readonly delta_time?: number;
  readonly viewport_width?: number;
  readonly viewport_height?: number;
  readonly alpha?: number;
  readonly hit_x?: number;
  readonly hit_y?: number;
  readonly hit_z?: number;
}

export type GuestCommand =
  | { readonly kind: "title"; readonly title: string }
  | { readonly kind: "save" | "load" };

interface GuestVector {
  readonly x: number;
  readonly y: number;
  readonly z: number;
}

export interface GuestFrame {
  readonly ambient: GuestVector;
  readonly clear: {
    readonly r: number;
    readonly g: number;
    readonly b: number;
    readonly a: number;
  };
  readonly draws: readonly {
    readonly mesh: string;
    readonly material: string;
    readonly transform: readonly number[];
    readonly entity?: number;
  }[];
  readonly light_color: GuestVector;
  readonly light_direction: GuestVector;
  readonly projection: readonly number[];
  readonly view: readonly number[];
  readonly commands: readonly GuestCommand[];
}

declare const guestWorldIdentity: unique symbol;
/** Opaque, immutable ABI banks; never compiler-private heap pointers. */
export interface GuestWorld {
  readonly entityCount: number;
  readonly [guestWorldIdentity]: true;
}

interface WorldBanks {
  readonly current: Uint8Array<ArrayBuffer>;
  readonly previous: Uint8Array<ArrayBuffer>;
  readonly revision: number;
}

interface StorageSlot {
  readonly binding: EcsStorage;
  readonly offset: number;
  readonly size: number;
}

export interface GuestTransition {
  readonly world: GuestWorld;
  readonly commands: readonly GuestCommand[];
}

export interface GuestReloadPlan {
  apply(
    world: GuestWorld,
  ): { readonly runtime: GuestRuntime; readonly world: GuestWorld };
}

export class GuestRuntimeError extends Error {
  constructor(
    message: string,
    readonly fault?: number,
    options?: ErrorOptions,
  ) {
    super(message, options);
    this.name = "GuestRuntimeError";
  }
}

interface Manifest {
  readonly assets: readonly {
    readonly kind: "mesh" | "material";
    readonly path: string;
  }[];
  readonly titles: readonly string[];
  readonly panics: readonly string[];
}

function readManifest(module: WebAssembly.Module): Manifest {
  const sections = WebAssembly.Module.customSections(module, "blot:app");
  if (sections.length !== 1) {
    throw new GuestRuntimeError("Expected exactly one blot:app ABI manifest");
  }
  const bytes = new Uint8Array(sections[0]);
  const view = new DataView(bytes.buffer);
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let offset = 0;
  const word = () => {
    if (offset + 4 > bytes.length) {
      throw new GuestRuntimeError("Truncated application manifest");
    }
    const value = view.getUint32(offset, true);
    offset += 4;
    return value;
  };
  const count = () => {
    const length = word();
    if (length > (bytes.length - offset) / 4) {
      throw new GuestRuntimeError("Manifest count exceeds remaining bytes");
    }
    return length;
  };
  const text = () => {
    const length = word();
    const padded = Math.ceil(length / 4) * 4;
    if (padded > bytes.length - offset) {
      throw new GuestRuntimeError("Manifest string exceeds remaining bytes");
    }
    const value = decoder.decode(bytes.subarray(offset, offset + length));
    if (
      bytes.subarray(offset + length, offset + padded).some((byte) =>
        byte !== 0
      )
    ) {
      throw new GuestRuntimeError("Manifest string padding must be zero");
    }
    offset += padded;
    return value;
  };
  if (word() !== guestAbiVersion) {
    throw new GuestRuntimeError("Unsupported application manifest version");
  }
  const assets = Array.from({ length: count() }, () => {
    const kind = word();
    if (kind > 1) throw new GuestRuntimeError("Unknown application asset kind");
    const path = text();
    if (!path.length || path.includes("\0")) {
      throw new GuestRuntimeError("Invalid application asset path");
    }
    return { kind: kind === 0 ? "mesh" as const : "material" as const, path };
  });
  const titles = Array.from({ length: count() }, text);
  const panics = Array.from({ length: count() }, text);
  if (offset !== bytes.length) {
    throw new GuestRuntimeError("Trailing bytes after application manifest");
  }
  return { assets, titles, panics };
}

function u32(value: number, label: string): number {
  if (!Number.isInteger(value) || value < 0 || value > 0xffffffff) {
    throw new GuestRuntimeError(`${label} must be a U32`);
  }
  return value;
}

function scalar(value: number, binding: EcsStorage): number {
  if (binding.scalar.$ === "U32Scalar") {
    return u32(value, binding.identity.declaration);
  }
  if (!Number.isFinite(value) || !Number.isFinite(Math.fround(value))) {
    throw new GuestRuntimeError(
      `${binding.identity.declaration} must be a finite F32`,
    );
  }
  return Math.fround(value);
}

function storageSlots(artifact: EcsArtifact): Map<string, StorageSlot> {
  const result = new Map<string, StorageSlot>();
  let offset = bankPrefix;
  for (const binding of artifact.storage) {
    const key = identityKey(binding.identity);
    if (result.has(key)) {
      throw new GuestRuntimeError(`Duplicate storage identity ${key}`);
    }
    if (binding.storage.$ !== "Component" && binding.storage.$ !== "Resource") {
      throw new GuestRuntimeError(`Unknown storage kind for ${key}`);
    }
    if (binding.scalar.$ !== "U32Scalar" && binding.scalar.$ !== "F32Scalar") {
      throw new GuestRuntimeError(`Unknown scalar kind for ${key}`);
    }
    const size = binding.storage.$ === "Component"
      ? guestEntityCapacity * 8
      : 8;
    result.set(key, { binding, offset, size });
    offset += size;
  }
  return result;
}

/** No ECS callbacks: source entrypoints own startup, dispatch, queries and writes. */
export class GuestRuntime {
  readonly #instance: WebAssembly.Instance;
  readonly #memory: WebAssembly.Memory;
  readonly #slots: ReadonlyMap<string, StorageSlot>;
  readonly #manifest: Manifest;
  readonly #stride: number;
  readonly #input: number;
  readonly #render: number;
  readonly #commands: number;
  readonly #worlds = new WeakMap<GuestWorld, WorldBanks>();
  #resident:
    | { readonly world: GuestWorld; readonly previous?: GuestWorld }
    | undefined;
  #started = false;

  private constructor(
    instance: WebAssembly.Instance,
    module: WebAssembly.Module,
    artifact: EcsArtifact,
  ) {
    this.#instance = instance;
    this.#slots = storageSlots(artifact);
    this.#manifest = readManifest(module);
    this.#stride = align64(
      bankPrefix +
        [...this.#slots.values()].reduce((sum, slot) => sum + slot.size, 0),
    );
    this.#input = align64(worldBase + 256 + 3 * this.#stride);
    this.#render = this.#input + 64;
    this.#commands = align64(this.#render + 256 + guestDrawCapacity * 80);
    const expected = {
      abi_version: guestAbiVersion,
      world_base: worldBase,
      bank_stride: this.#stride,
      input_base: this.#input,
      render_base: this.#render,
      command_base: this.#commands,
      entity_capacity: guestEntityCapacity,
      draw_capacity: guestDrawCapacity,
      command_capacity: guestCommandCapacity,
    };
    for (const [name, value] of Object.entries(expected)) {
      const exported = instance.exports[`__blot_${name}`];
      if (
        !(exported instanceof WebAssembly.Global) || exported.value !== value
      ) {
        throw new GuestRuntimeError(
          `Invalid __blot_${name}; expected ${value}`,
        );
      }
      let immutable = false;
      try {
        exported.value = value;
      } catch (error) {
        if (!(error instanceof TypeError)) throw error;
        immutable = true;
      }
      if (!immutable) {
        throw new GuestRuntimeError(
          `ABI global __blot_${name} must be immutable`,
        );
      }
    }
    const memory = instance.exports.memory;
    if (
      !(memory instanceof WebAssembly.Memory) ||
      memory.buffer instanceof SharedArrayBuffer ||
      memory.buffer.byteLength < this.#commands + 16 + guestCommandCapacity * 8
    ) {
      throw new GuestRuntimeError(
        "Application memory does not contain the declared ABI regions",
      );
    }
    this.#memory = memory;
    for (const name of ["start", "event", "update", "render"]) {
      if (typeof instance.exports[name] !== "function") {
        throw new GuestRuntimeError(`Missing application entrypoint ${name}`);
      }
    }
  }

  static async create(artifact: EcsArtifact): Promise<GuestRuntime> {
    const module = await WebAssembly.compile(artifact.bytes);
    if (WebAssembly.Module.imports(module).length !== 0) {
      throw new GuestRuntimeError(
        "A guest application must not import host ECS functions",
      );
    }
    const instance = await WebAssembly.instantiate(module);
    return new GuestRuntime(instance, module, artifact);
  }

  #state(world: GuestWorld): WorldBanks {
    const state = this.#worlds.get(world);
    if (!state) {
      throw new GuestRuntimeError("World belongs to a different guest runtime");
    }
    return state;
  }

  #snapshot(
    current: Uint8Array<ArrayBuffer>,
    previous: Uint8Array<ArrayBuffer>,
    revision: number,
  ): GuestWorld {
    const extent = new DataView(current.buffer).getUint32(0, true);
    if (extent > guestEntityCapacity) {
      throw new GuestRuntimeError("Guest entity extent exceeds ABI capacity");
    }
    const world = Object.freeze({ entityCount: extent }) as GuestWorld;
    this.#worlds.set(world, { current, previous, revision });
    return world;
  }

  #load(world: GuestWorld, previous?: GuestWorld): WorldBanks {
    const state = this.#state(world);
    if (
      this.#resident?.world === world && this.#resident.previous === previous
    ) return state;
    const bytes = new Uint8Array(this.#memory.buffer);
    const view = new DataView(bytes.buffer);
    const currentPtr = worldBase + 256;
    const previousPtr = currentPtr + this.#stride;
    bytes.set(state.current, currentPtr);
    bytes.set(
      previous ? this.#state(previous).current : state.previous,
      previousPtr,
    );
    view.setUint32(worldBase + 16, currentPtr, true);
    view.setUint32(worldBase + 20, previousPtr, true);
    view.setUint32(worldBase + 24, previousPtr + this.#stride, true);
    view.setUint32(worldBase + 40, 1, true);
    view.setUint32(worldBase + 44, state.revision, true);
    this.#resident = { world, previous };
    return state;
  }

  #inputPacket(input: GuestInput): void {
    if (
      input.pick_valid !== undefined && typeof input.pick_valid !== "boolean"
    ) {
      throw new GuestRuntimeError("Input pick_valid must be Boolean");
    }
    const view = new DataView(this.#memory.buffer, this.#input, 64);
    [
      input.event_kind ?? 0,
      input.key ?? 0,
      input.button ?? 0,
      input.picked ?? noGuestEntity,
      input.pick_valid === true ? 1 : 0,
    ].forEach((value, index) =>
      view.setUint32(index * 4, u32(value, "Input word"), true)
    );
    [
      input.pointer_x ?? 0,
      input.pointer_y ?? 0,
      input.wheel_delta ?? 0,
      input.delta_time ?? 0,
      input.viewport_width ?? 1,
      input.viewport_height ?? 1,
      input.alpha ?? 1,
      input.hit_x ?? 0,
      input.hit_y ?? 0,
      input.hit_z ?? 0,
    ].forEach((value, index) => {
      if (!Number.isFinite(value) || !Number.isFinite(Math.fround(value))) {
        throw new GuestRuntimeError("Input scalar must be a finite F32");
      }
      view.setFloat32((index + 5) * 4, value, true);
    });
    view.setUint32(60, 0, true);
  }

  #call(
    name: "start" | "event" | "update" | "render",
    input: GuestInput,
  ): readonly GuestCommand[] {
    this.#inputPacket(input);
    const entry = this.#instance.exports[name];
    if (typeof entry !== "function") {
      throw new GuestRuntimeError(`Missing entrypoint ${name}`);
    }
    this.#resident = undefined;
    try {
      entry(0);
    } catch (cause) {
      const fault = new DataView(this.#memory.buffer).getUint32(
        worldBase + 36,
        true,
      );
      const message = fault >= 0x10000
        ? this.#manifest.panics[fault - 0x10000]
        : undefined;
      throw new GuestRuntimeError(
        message ?? `Guest ${name} trapped (fault ${fault})`,
        fault,
        { cause },
      );
    }
    const header = new DataView(this.#memory.buffer, worldBase, 256);
    if (
      header.getUint32(28, true) !== 0 ||
      header.getUint32(32, true) !== noGuestEntity ||
      header.getUint32(36, true) !== 0
    ) {
      throw new GuestRuntimeError(
        `Guest ${name} returned with an unfinished entry scope`,
      );
    }
    return this.#readCommands();
  }

  #readCommands(): readonly GuestCommand[] {
    const view = new DataView(this.#memory.buffer, this.#commands);
    const count = view.getUint32(0, true);
    const title = view.getUint32(4, true);
    if (count > guestCommandCapacity) {
      throw new GuestRuntimeError("Guest command count exceeds ABI capacity");
    }
    const result: GuestCommand[] = [];
    if (title !== noGuestEntity) {
      const value = this.#manifest.titles[title];
      if (value === undefined) {
        throw new GuestRuntimeError(
          "Guest title reference is outside the manifest",
        );
      }
      result.push({ kind: "title", title: value });
    }
    for (let index = 0; index < count; index++) {
      const kind = view.getUint32(16 + index * 8, true);
      if (
        (kind !== 1 && kind !== 2) || view.getUint32(20 + index * 8, true) !== 0
      ) throw new GuestRuntimeError("Invalid guest platform command");
      result.push({ kind: kind === 1 ? "save" : "load" });
    }
    return result;
  }

  #capture(previous?: Uint8Array<ArrayBuffer>): GuestWorld {
    const view = new DataView(this.#memory.buffer);
    const base = view.getUint32(worldBase + 16, true);
    const banks = [
      worldBase + 256,
      worldBase + 256 + this.#stride,
      worldBase + 256 + this.#stride * 2,
    ];
    if (!banks.includes(base)) {
      throw new GuestRuntimeError(
        "Guest current bank pointer is outside the ABI banks",
      );
    }
    const current = new Uint8Array(this.#memory.buffer).slice(
      base,
      base + this.#stride,
    );
    const world = this.#snapshot(
      current,
      previous ?? current,
      view.getUint32(worldBase + 44, true),
    );
    this.#resident = { world };
    return world;
  }

  start(input: GuestInput = {}): GuestTransition {
    if (this.#started) {
      throw new GuestRuntimeError("Guest startup has already run");
    }
    const commands = this.#call("start", input);
    const world = this.#capture();
    this.#started = true;
    return { world, commands };
  }

  event(world: GuestWorld, input: GuestInput): GuestTransition {
    const state = this.#load(world);
    const commands = this.#call("event", input);
    return { world: this.#capture(state.previous), commands };
  }

  update(world: GuestWorld, input: GuestInput): GuestTransition {
    const state = this.#load(world);
    const commands = this.#call("update", input);
    return { world: this.#capture(state.current), commands };
  }

  render(
    world: GuestWorld,
    input: GuestInput,
    previous?: GuestWorld,
  ): GuestFrame {
    this.#load(world, previous);
    const commands = this.#call("render", input);
    const view = new DataView(this.#memory.buffer, this.#render);
    const count = view.getUint32(0, true);
    if (count > guestDrawCapacity) {
      throw new GuestRuntimeError("Guest draw count exceeds ABI capacity");
    }
    const floats = (offset: number, length: number) =>
      Array.from({ length }, (_, index) => {
        const value = view.getFloat32(offset + index * 4, true);
        if (!Number.isFinite(value)) {
          throw new GuestRuntimeError(
            "Guest render packet contains a nonfinite F32",
          );
        }
        return value;
      });
    const vector = (offset: number): GuestVector => {
      const [x, y, z] = floats(offset, 3);
      return { x, y, z };
    };
    const [r, g, b, a] = floats(8, 4);
    const draws = Array.from({ length: count }, (_, index) => {
      const offset = 256 + index * 80;
      const mesh = this.#manifest.assets[view.getUint32(offset, true)];
      const material = this.#manifest.assets[view.getUint32(offset + 4, true)];
      const pickable = view.getUint32(offset + 8, true);
      if (
        mesh?.kind !== "mesh" || material?.kind !== "material" || pickable > 1
      ) {
        throw new GuestRuntimeError(
          "Invalid asset reference or pickability in render packet",
        );
      }
      return {
        mesh: mesh.path,
        material: material.path,
        transform: floats(offset + 16, 16),
        ...(pickable ? { entity: view.getUint32(offset + 12, true) } : {}),
      };
    });
    this.#resident = { world, previous };
    return {
      clear: { r, g, b, a },
      ambient: vector(24),
      light_direction: vector(36),
      light_color: vector(48),
      view: floats(64, 16),
      projection: floats(128, 16),
      draws,
      commands,
    };
  }

  #slot(identity: TypeId, kind: "Component" | "Resource"): StorageSlot {
    const slot = this.#slots.get(identityKey(identity));
    if (!slot || slot.binding.storage.$ !== kind) {
      throw new GuestRuntimeError(`Unknown ${kind} ${identityKey(identity)}`);
    }
    return slot;
  }

  #value(bytes: Uint8Array, slot: StorageSlot, entity = 0): number | null {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const component = slot.binding.storage.$ === "Component";
    const present = slot.offset +
      (component ? guestEntityCapacity * 4 + entity * 4 : 4);
    if (view.getUint32(present, true) === 0) return null;
    const offset = slot.offset + entity * 4;
    return slot.binding.scalar.$ === "F32Scalar"
      ? view.getFloat32(offset, true)
      : view.getUint32(offset, true);
  }

  isAlive(world: GuestWorld, entity: number): boolean {
    const state = this.#state(world);
    u32(entity, "Entity");
    return entity < world.entityCount &&
      new DataView(state.current.buffer).getUint32(16 + entity * 4, true) === 1;
  }

  readComponent(
    world: GuestWorld,
    identity: TypeId,
    entity: number,
  ): number | null {
    const state = this.#state(world);
    const slot = this.#slot(identity, "Component");
    if (!this.isAlive(world, entity)) return null;
    return this.#value(state.current, slot, entity);
  }

  readResource(world: GuestWorld, identity: TypeId): number {
    const value = this.#value(
      this.#state(world).current,
      this.#slot(identity, "Resource"),
    );
    if (value === null) {
      throw new GuestRuntimeError(`Missing resource ${identityKey(identity)}`);
    }
    return value;
  }

  exportWorld(world: GuestWorld): EcsWorldSeed {
    const state = this.#state(world);
    const components: NonNullable<EcsWorldSeed["components"]>[number][] = [];
    const resources: NonNullable<EcsWorldSeed["resources"]>[number][] = [];
    for (const slot of this.#slots.values()) {
      const identity = { ...slot.binding.identity };
      if (slot.binding.storage.$ === "Component") {
        components.push({
          identity,
          values: Array.from(
            { length: world.entityCount },
            (_, entity) =>
              this.isAlive(world, entity)
                ? this.#value(state.current, slot, entity)
                : null,
          ),
        });
      } else {
        const value = this.#value(state.current, slot);
        if (value !== null) resources.push({ identity, value });
      }
    }
    return {
      entityCount: world.entityCount,
      alive: Array.from(
        { length: world.entityCount },
        (_, entity) => this.isAlive(world, entity),
      ),
      components,
      resources,
    };
  }

  /** Validated save import; it never runs startup or source system code. */
  createWorld(seed: EcsWorldSeed): GuestWorld {
    const count = u32(seed.entityCount, "Entity count");
    if (count > guestEntityCapacity) {
      throw new GuestRuntimeError("Saved world exceeds guest entity capacity");
    }
    if (seed.alive && seed.alive.length !== count) {
      throw new GuestRuntimeError(
        "Saved alive column length differs from entity count",
      );
    }
    const bytes = new Uint8Array(this.#stride);
    const view = new DataView(bytes.buffer);
    view.setUint32(0, count, true);
    for (let entity = 0; entity < count; entity++) {
      const alive = seed.alive === undefined ? true : seed.alive[entity];
      if (typeof alive !== "boolean") {
        throw new GuestRuntimeError("Saved entity liveness must be Boolean");
      }
      view.setUint32(16 + entity * 4, +alive, true);
    }
    const seen = new Set<string>();
    const assign = (
      identity: TypeId,
      kind: "Component" | "Resource",
      values: ArrayLike<number | null>,
    ) => {
      const key = identityKey(identity);
      if (seen.has(key)) {
        throw new GuestRuntimeError(`Duplicate saved storage ${key}`);
      }
      seen.add(key);
      const slot = this.#slot(identity, kind);
      const length = kind === "Component" ? count : 1;
      if (values.length !== length) {
        throw new GuestRuntimeError(
          `Saved storage ${key} has the wrong length`,
        );
      }
      for (let entity = 0; entity < length; entity++) {
        const value = values[entity];
        if (value === null) continue;
        if (
          kind === "Component" && view.getUint32(16 + entity * 4, true) === 0
        ) {
          throw new GuestRuntimeError(
            `Saved component ${key} exists on a removed entity`,
          );
        }
        const checked = scalar(value, slot.binding);
        const offset = slot.offset + entity * 4;
        if (slot.binding.scalar.$ === "F32Scalar") {
          view.setFloat32(offset, checked, true);
        } else view.setUint32(offset, checked, true);
        view.setUint32(
          slot.offset +
            (kind === "Component" ? guestEntityCapacity * 4 + entity * 4 : 4),
          1,
          true,
        );
      }
    };
    for (const component of seed.components ?? []) {
      assign(component.identity, "Component", component.values);
    }
    for (const resource of seed.resources ?? []) {
      assign(resource.identity, "Resource", [resource.value]);
    }
    this.#started = true;
    return this.#snapshot(bytes, bytes, 0);
  }

  async prepareReload(artifact: EcsArtifact): Promise<GuestReloadPlan> {
    const runtime = await GuestRuntime.create(artifact);
    for (const key of this.#slots.keys()) {
      if (!runtime.#slots.has(key)) {
        throw new GuestRuntimeError(
          `Reload removes storage ${key}; an explicit migration is required`,
        );
      }
    }
    for (const [key, slot] of runtime.#slots) {
      const previous = this.#slots.get(key);
      if (
        previous &&
        (previous.binding.storage.$ !== slot.binding.storage.$ ||
          previous.binding.scalar.$ !== slot.binding.scalar.$)
      ) {
        throw new GuestRuntimeError(
          `Incompatible reload storage ${key}; an explicit migration is required`,
        );
      }
    }
    const transfer = (source: Uint8Array) => {
      const result = new Uint8Array(runtime.#stride);
      result.set(source.subarray(0, bankPrefix));
      for (const [key, slot] of runtime.#slots) {
        const old = this.#slots.get(key);
        if (old) {
          result.set(
            source.subarray(old.offset, old.offset + old.size),
            slot.offset,
          );
        }
      }
      return result;
    };
    return {
      apply: (world) => {
        const state = this.#state(world);
        runtime.#started = true;
        return {
          runtime,
          world: runtime.#snapshot(
            transfer(state.current),
            transfer(state.previous),
            state.revision,
          ),
        };
      },
    };
  }
}
