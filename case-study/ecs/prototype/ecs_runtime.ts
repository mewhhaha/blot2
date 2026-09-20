// Archived compiler-coupled prototype; not part of the current compiler.
import type {
  Access,
  EcsArtifact,
  EcsStorage,
  SystemPlan,
  TypeId,
} from "./host.ts";

declare const worldIdentity: unique symbol;

/** An immutable snapshot belonging to the runtime that created it. */
export interface EcsWorld {
  readonly entityCount: number;
  readonly [worldIdentity]: true;
}

export interface EcsWorldSeed {
  readonly entityCount: number;
  /** Omitted means all allocated entity IDs are alive. Removed IDs are not reused. */
  readonly alive?: ArrayLike<boolean>;
  readonly components?: readonly {
    readonly identity: TypeId;
    /** Exactly one slot per entity; null means the component is absent. */
    readonly values: ArrayLike<number | null>;
  }[];
  readonly resources?: readonly {
    readonly identity: TypeId;
    readonly value: number;
  }[];
}

export interface EcsRunOptions {
  /** Selects systems without changing their declaration order. */
  readonly systems?: readonly string[];
}

export interface EcsReloadOptions {
  /** Initializes newly added resources; existing resource state is preserved. */
  readonly resources?: EcsWorldSeed["resources"];
}

export interface EcsReloadResult {
  readonly runtime: EcsRuntime;
  readonly world: EcsWorld;
}

export interface EcsReloadPlan {
  /** Synchronous transfer of the latest snapshot, after asynchronous Wasm preparation. */
  apply(world: EcsWorld, options?: EcsReloadOptions): EcsReloadResult;
}

export interface EcsRuntime {
  createWorld(seed: EcsWorldSeed): EcsWorld;
  /** Returns detached public values suitable for a validated save boundary. */
  exportWorld(world: EcsWorld): EcsWorldSeed;
  isAlive(world: EcsWorld, entity: number): boolean;
  /** Supplies platform resources atomically without mutating an earlier snapshot. */
  withResources(
    world: EcsWorld,
    resources: NonNullable<EcsWorldSeed["resources"]>,
  ): EcsWorld;
  spawn(
    world: EcsWorld,
    seed: Pick<EcsWorldSeed, "entityCount" | "components">,
  ): { readonly world: EcsWorld; readonly entities: readonly number[] };
  despawn(world: EcsWorld, entity: number): EcsWorld;
  /** Prepares a candidate without capturing or pausing the live world. */
  prepareReload(artifact: EcsArtifact): Promise<EcsReloadPlan>;
  /** Retains nominal storage identities; added components start absent. */
  reload(
    world: EcsWorld,
    artifact: EcsArtifact,
    options?: EcsReloadOptions,
  ): Promise<EcsReloadResult>;
  run(world: EcsWorld, options?: EcsRunOptions): EcsWorld;
  /** Skips systems whose required components are absent from this entity. */
  runEntity(world: EcsWorld, entity: number, options?: EcsRunOptions): EcsWorld;
  readComponent(
    world: EcsWorld,
    identity: TypeId,
    entity: number,
  ): number | null;
  readResource(world: EcsWorld, identity: TypeId): number;
}

export type EcsRuntimeErrorCode =
  | "invalid_artifact"
  | "unknown_storage"
  | "storage_kind"
  | "foreign_world"
  | "duplicate_seed"
  | "unknown_system"
  | "duplicate_system"
  | "entity_scope"
  | "effect_scope"
  | "missing_component"
  | "missing_entity"
  | "missing_resource"
  | "incompatible_reload"
  | "reentrant_run";

export class EcsRuntimeError extends Error {
  constructor(readonly code: EcsRuntimeErrorCode, message: string) {
    super(message);
    this.name = "EcsRuntimeError";
  }
}

interface StorageIdentity {
  readonly tag: number;
  readonly key: string;
  readonly label: string;
  readonly identity: TypeId;
  readonly scalar: EcsStorage["scalar"]["$"];
}

type StorageSlot =
  | StorageIdentity & { readonly kind: "Component" }
  | StorageIdentity & {
    readonly kind: "Resource";
    readonly resourceIndex: number;
  };

interface ComponentColumn {
  readonly values: Uint32Array;
  readonly present: Uint32Array;
}

interface ResourceCells {
  readonly values: Uint32Array;
  readonly present: Uint32Array;
}

interface WorldState {
  readonly entityCount: number;
  readonly alive: Uint32Array;
  readonly columns: ReadonlyMap<number, ComponentColumn>;
  readonly resources: ResourceCells;
}

interface WorldDraft {
  readonly source: WorldState;
  readonly changedColumns: Map<number, ComponentColumn>;
  resources: ResourceCells | null;
}

interface SystemScope {
  readonly name: string;
  readonly query: readonly number[];
  readonly requiresEntity: boolean;
  readonly capabilities: ReadonlyMap<number, ReadonlySet<Access["$"]>>;
}

interface Invocation {
  readonly draft: WorldDraft;
  readonly system: SystemScope;
  readonly entity: number | null;
}

interface LoadedRuntime {
  readonly runtime: EcsRuntime;
  readonly slots: ReadonlyMap<string, StorageSlot>;
  readonly resourceCount: number;
  readonly snapshot: (state: WorldState) => EcsWorld;
}

function u32(value: number, label: string): number {
  if (!Number.isInteger(value) || value < 0 || value > 0xffff_ffff) {
    throw new RangeError(`${label} must be a U32 (0..2^32-1)`);
  }
  return value;
}

// Reinterpret one word without allocating per entity read. These views never
// escape, and conversion has no callback or asynchronous boundary.
const floatWord = new Uint32Array(1);
const floatValue = new Float32Array(floatWord.buffer);

function scalarWord(value: number, slot: StorageSlot): number {
  if (slot.scalar === "U32Scalar") return u32(value, slot.label);
  if (typeof value !== "number") {
    throw new TypeError(`${slot.label} must be an F32 number`);
  }
  floatValue[0] = value;
  return floatWord[0];
}

function scalarNumber(word: number, slot: StorageSlot): number {
  if (slot.scalar === "U32Scalar") return word;
  floatWord[0] = word;
  return floatValue[0];
}

function identityKey(identity: TypeId): string {
  if (
    identity.$ !== "TypeId" || typeof identity.module_name !== "string" ||
    typeof identity.declaration !== "string" ||
    !identity.module_name.isWellFormed() ||
    !identity.declaration.isWellFormed()
  ) {
    throw new TypeError(
      "Storage identity must contain valid Unicode module and declaration names",
    );
  }
  return JSON.stringify([identity.module_name, identity.declaration]);
}

function presence(size: number): Uint32Array {
  return new Uint32Array(Math.ceil(size / 32));
}

function present(bits: Uint32Array, index: number): boolean {
  return (bits[index >>> 5] & (1 << (index & 31))) !== 0;
}

function setPresent(bits: Uint32Array, index: number): void {
  bits[index >>> 5] |= 1 << (index & 31);
}

function clearPresent(bits: Uint32Array, index: number): void {
  bits[index >>> 5] &= ~(1 << (index & 31));
}

function entityIndex(entity: number, entityCount: number): number {
  if (!Number.isInteger(entity) || entity < 0 || entity >= entityCount) {
    throw new RangeError(
      `Entity ${entity} is outside this world's range 0..${entityCount - 1}`,
    );
  }
  return entity;
}

function column(draft: WorldDraft, tag: number): ComponentColumn {
  const result = draft.changedColumns.get(tag) ?? draft.source.columns.get(tag);
  if (!result) {
    throw new EcsRuntimeError(
      "invalid_artifact",
      `Component column for tag ${tag} is missing`,
    );
  }
  return result;
}

function writableColumn(draft: WorldDraft, tag: number): ComponentColumn {
  const existing = draft.changedColumns.get(tag);
  if (existing) return existing;
  const original = column(draft, tag);
  const copied = {
    values: original.values.slice(),
    present: original.present.slice(),
  };
  draft.changedColumns.set(tag, copied);
  return copied;
}

function writableResources(draft: WorldDraft): ResourceCells {
  if (draft.resources) return draft.resources;
  const original = draft.source.resources;
  draft.resources = {
    values: original.values.slice(),
    present: original.present.slice(),
  };
  return draft.resources;
}

function matches(
  draft: WorldDraft,
  system: SystemScope,
  entity: number,
): boolean {
  return system.query.every((tag) =>
    present(column(draft, tag).present, entity)
  );
}

/** Resolves checked ECS imports against an explicit world/entity invocation. */
export async function createEcsRuntime(
  artifact: EcsArtifact,
): Promise<EcsRuntime> {
  return (await instantiateRuntime(artifact)).runtime;
}

async function instantiateRuntime(
  artifact: EcsArtifact,
): Promise<LoadedRuntime> {
  const byIdentity = new Map<string, StorageSlot>();
  const byTag = new Map<number, StorageSlot>();
  let resourceCount = 0;
  for (const storage of artifact.storage) {
    const key = identityKey(storage.identity);
    const tag = u32(storage.tag, "Storage tag");
    if (byIdentity.has(key) || byTag.has(tag)) {
      throw new EcsRuntimeError(
        "invalid_artifact",
        `Duplicate storage identity or tag: ${key}`,
      );
    }
    if (
      typeof storage.constructor !== "string" ||
      !storage.constructor.isWellFormed()
    ) {
      throw new EcsRuntimeError(
        "invalid_artifact",
        "Storage constructor must be valid Unicode",
      );
    }
    if (
      storage.scalar?.$ !== "U32Scalar" && storage.scalar?.$ !== "F32Scalar"
    ) {
      throw new EcsRuntimeError(
        "invalid_artifact",
        `Invalid scalar layout for ${key}`,
      );
    }
    const common = {
      key,
      tag,
      label: `${storage.identity.module_name}::${storage.identity.declaration}`,
      identity: Object.freeze({ ...storage.identity }),
      scalar: storage.scalar.$,
    };
    let slot: StorageSlot;
    switch (storage.storage.$) {
      case "Component":
        slot = { ...common, kind: "Component" };
        break;
      case "Resource":
        slot = { ...common, kind: "Resource", resourceIndex: resourceCount++ };
        break;
      default:
        throw new EcsRuntimeError(
          "invalid_artifact",
          `Invalid storage kind for ${common.label}`,
        );
    }
    byIdentity.set(key, slot);
    byTag.set(tag, slot);
  }

  function storageFor(identity: TypeId): StorageSlot {
    const key = identityKey(identity);
    const slot = byIdentity.get(key);
    if (!slot) {
      throw new EcsRuntimeError(
        "unknown_storage",
        `Unknown storage identity ${key}`,
      );
    }
    return slot;
  }

  function checkedDescriptor(
    descriptor: Pick<EcsStorage, "identity" | "storage">,
  ): StorageSlot {
    const slot = storageFor(descriptor.identity);
    if (slot.kind !== descriptor.storage.$) {
      throw new EcsRuntimeError(
        "invalid_artifact",
        `Storage kind mismatch for ${slot.label}`,
      );
    }
    return slot;
  }

  for (const registration of artifact.analysis.world.registrations) {
    checkedDescriptor(registration);
  }

  function systemScope(plan: SystemPlan): SystemScope {
    const signature = artifact.analysis.functions.find((fn) =>
      fn.name === plan.name
    );
    if (
      !signature || signature.parameter.$ !== "UnitTy" ||
      signature.result.$ !== "UnitTy"
    ) {
      throw new EcsRuntimeError(
        "invalid_artifact",
        `ECS system ${plan.name} must have type Unit -> Unit`,
      );
    }
    const capabilities = new Map<number, Set<Access["$"]>>();
    const expectedQuery = new Set<number>();
    let requiresEntity = false;
    for (const effect of plan.effects) {
      if (effect.$ !== "Effect") {
        throw new EcsRuntimeError(
          "invalid_artifact",
          "Application capabilities require the guest runtime",
        );
      }
      const slot = checkedDescriptor(effect.descriptor);
      if (!["Read", "Write", "Insert"].includes(effect.access.$)) {
        throw new EcsRuntimeError(
          "invalid_artifact",
          `Unknown access in system ${plan.name}`,
        );
      }
      if (slot.kind === "Resource" && effect.access.$ === "Insert") {
        throw new EcsRuntimeError(
          "invalid_artifact",
          `System ${plan.name} cannot insert a resource`,
        );
      }
      const accesses = capabilities.get(slot.tag) ?? new Set<Access["$"]>();
      accesses.add(effect.access.$);
      capabilities.set(slot.tag, accesses);
      if (slot.kind === "Component") {
        requiresEntity = true;
        if (effect.access.$ !== "Insert") expectedQuery.add(slot.tag);
      }
    }
    const query = plan.query.map((descriptor) => {
      const slot = checkedDescriptor(descriptor);
      if (slot.kind !== "Component") {
        throw new EcsRuntimeError(
          "invalid_artifact",
          `System ${plan.name} has a resource in its entity query`,
        );
      }
      return slot.tag;
    });
    if (
      query.length !== expectedQuery.size ||
      query.some((tag) => !expectedQuery.delete(tag))
    ) {
      throw new EcsRuntimeError(
        "invalid_artifact",
        `System ${plan.name} query does not match its read/write capabilities`,
      );
    }
    return { name: plan.name, query, requiresEntity, capabilities };
  }

  const systems = artifact.analysis.world.systems.map(systemScope);
  const bySystem = new Map(systems.map((system) => [system.name, system]));
  if (bySystem.size !== systems.length) {
    throw new EcsRuntimeError(
      "invalid_artifact",
      "Duplicate system names in world plan",
    );
  }
  const worlds = new WeakMap<EcsWorld, WorldState>();
  let invocation: Invocation | null = null;
  let running = false;

  function active(
    tag: number,
    access: Access["$"],
  ): { scope: Invocation; slot: StorageSlot } {
    const scope = invocation;
    if (!scope) {
      throw new EcsRuntimeError(
        "effect_scope",
        "An ECS effect needs an active world invocation",
      );
    }
    const slot = byTag.get(tag >>> 0);
    if (!slot) {
      throw new EcsRuntimeError(
        "unknown_storage",
        `Unknown ECS storage tag ${tag >>> 0}`,
      );
    }
    if (!scope.system.capabilities.get(slot.tag)?.has(access)) {
      throw new EcsRuntimeError(
        "effect_scope",
        `System ${scope.system.name} did not declare ${access} ${slot.label}`,
      );
    }
    return { scope, slot };
  }

  function currentEntity(scope: Invocation, slot: StorageSlot): number {
    if (scope.entity === null) {
      throw new EcsRuntimeError(
        "entity_scope",
        `${slot.label} requires an explicit entity invocation`,
      );
    }
    return scope.entity;
  }

  function requireResource(
    cells: ResourceCells,
    slot: StorageSlot & { kind: "Resource" },
  ): number {
    if (!present(cells.present, slot.resourceIndex)) {
      throw new EcsRuntimeError(
        "missing_resource",
        `Resource ${slot.label} has not been seeded`,
      );
    }
    return cells.values[slot.resourceIndex];
  }

  const module = await WebAssembly.compile(artifact.bytes);
  for (const imported of WebAssembly.Module.imports(module)) {
    if (
      imported.module !== "blot:ecs" || imported.kind !== "function" ||
      !["read", "write", "insert"].includes(imported.name)
    ) {
      throw new EcsRuntimeError(
        "invalid_artifact",
        `Unexpected Wasm import ${imported.module}.${imported.name}`,
      );
    }
  }
  const instance = await WebAssembly.instantiate(module, {
    "blot:ecs": {
      read(tag: number): number {
        const { scope, slot } = active(tag, "Read");
        if (slot.kind === "Resource") {
          return requireResource(
            scope.draft.resources ?? scope.draft.source.resources,
            slot,
          );
        }
        const entity = currentEntity(scope, slot);
        const values = column(scope.draft, slot.tag);
        if (!present(values.present, entity)) {
          throw new EcsRuntimeError(
            "missing_component",
            `Component ${slot.label} is absent from entity ${entity}`,
          );
        }
        return values.values[entity];
      },
      write(tag: number, value: number): number {
        const { scope, slot } = active(tag, "Write");
        if (slot.kind === "Resource") {
          requireResource(
            scope.draft.resources ?? scope.draft.source.resources,
            slot,
          );
          writableResources(scope.draft).values[slot.resourceIndex] = value >>>
            0;
          return 0;
        }
        const entity = currentEntity(scope, slot);
        if (!present(column(scope.draft, slot.tag).present, entity)) {
          throw new EcsRuntimeError(
            "missing_component",
            `Cannot write absent ${slot.label} on entity ${entity}; use insert`,
          );
        }
        writableColumn(scope.draft, slot.tag).values[entity] = value >>> 0;
        return 0;
      },
      insert(tag: number, value: number): number {
        const { scope, slot } = active(tag, "Insert");
        if (slot.kind !== "Component") {
          throw new EcsRuntimeError(
            "storage_kind",
            `Cannot insert resource ${slot.label}`,
          );
        }
        const entity = currentEntity(scope, slot);
        const values = writableColumn(scope.draft, slot.tag);
        values.values[entity] = value >>> 0;
        setPresent(values.present, entity);
        return 0;
      },
    },
  });
  const functions = new Map<string, CallableFunction>();
  for (const system of systems) {
    const exported = instance.exports[system.name];
    if (typeof exported !== "function") {
      throw new EcsRuntimeError(
        "invalid_artifact",
        `System ${system.name} is not a Wasm function export`,
      );
    }
    functions.set(system.name, exported);
  }

  function stateOf(world: EcsWorld): WorldState {
    const state = worlds.get(world);
    if (!state) {
      throw new EcsRuntimeError(
        "foreign_world",
        "World belongs to another ECS runtime or is not a world snapshot",
      );
    }
    return state;
  }

  function snapshot(state: WorldState): EcsWorld {
    const world = Object.freeze({ entityCount: state.entityCount }) as EcsWorld;
    worlds.set(world, state);
    return world;
  }

  function selectedSystems(options: EcsRunOptions): readonly SystemScope[] {
    if (options.systems === undefined) return systems;
    const selected = new Set<string>();
    for (const name of options.systems) {
      if (!bySystem.has(name)) {
        throw new EcsRuntimeError(
          "unknown_system",
          `Unknown ECS system ${name}`,
        );
      }
      if (selected.has(name)) {
        throw new EcsRuntimeError(
          "duplicate_system",
          `System ${name} was selected more than once`,
        );
      }
      selected.add(name);
    }
    return systems.filter((system) => selected.has(system.name));
  }

  function execute(
    world: EcsWorld,
    entity: number | null,
    options: EcsRunOptions,
  ): EcsWorld {
    if (running) {
      throw new EcsRuntimeError(
        "reentrant_run",
        "An ECS runtime cannot run another world during an active transition",
      );
    }
    running = true;
    try {
      const source = stateOf(world);
      if (entity !== null) {
        entityIndex(entity, source.entityCount);
        if (!present(source.alive, entity)) {
          throw new EcsRuntimeError(
            "missing_entity",
            `Entity ${entity} was removed`,
          );
        }
      }
      const selected = selectedSystems(options);
      for (const system of selected) {
        if (
          entity === null && system.requiresEntity && system.query.length === 0
        ) {
          throw new EcsRuntimeError(
            "entity_scope",
            `System ${system.name} has no entity query; select an entity with runEntity`,
          );
        }
      }
      const draft: WorldDraft = {
        source,
        changedColumns: new Map(),
        resources: null,
      };
      function invoke(system: SystemScope, entity: number | null) {
        invocation = { draft, system, entity };
        try {
          functions.get(system.name)!(0);
        } finally {
          invocation = null;
        }
      }
      // Batches describe potential independence. This bootstrap host executes
      // declaration order sequentially, so later queries observe prior inserts.
      for (const system of selected) {
        if (entity !== null) {
          if (matches(draft, system, entity)) invoke(system, entity);
        } else if (system.query.length === 0) {
          invoke(system, null);
        } else {
          for (let candidate = 0; candidate < source.entityCount; candidate++) {
            if (
              present(source.alive, candidate) &&
              matches(draft, system, candidate)
            ) {
              invoke(system, candidate);
            }
          }
        }
      }
      if (draft.changedColumns.size === 0 && draft.resources === null) {
        return world;
      }
      const columns = new Map(source.columns);
      for (const [tag, values] of draft.changedColumns) {
        columns.set(tag, values);
      }
      return snapshot({
        entityCount: source.entityCount,
        alive: source.alive,
        columns,
        resources: draft.resources ?? source.resources,
      });
    } finally {
      invocation = null;
      running = false;
    }
  }

  const runtime: EcsRuntime = Object.freeze({
    createWorld(seed: EcsWorldSeed): EcsWorld {
      const entityCount = u32(seed.entityCount, "Entity count");
      if (seed.alive !== undefined && seed.alive.length !== entityCount) {
        throw new RangeError(
          `Entity presence needs exactly ${entityCount} slots`,
        );
      }
      const alive = presence(entityCount);
      for (let entity = 0; entity < entityCount; entity++) {
        const living = seed.alive === undefined ? true : seed.alive[entity];
        if (typeof living !== "boolean") {
          throw new TypeError(`Entity presence at ${entity} must be Boolean`);
        }
        if (living) setPresent(alive, entity);
      }
      const columns = new Map<number, ComponentColumn>();
      for (const slot of byTag.values()) {
        if (slot.kind === "Component") {
          columns.set(slot.tag, {
            values: new Uint32Array(entityCount),
            present: presence(entityCount),
          });
        }
      }
      const resources: ResourceCells = {
        values: new Uint32Array(resourceCount),
        present: presence(resourceCount),
      };
      const seeded = new Set<number>();
      for (const component of seed.components ?? []) {
        const slot = storageFor(component.identity);
        if (slot.kind !== "Component") {
          throw new EcsRuntimeError(
            "storage_kind",
            `${slot.label} is not a component`,
          );
        }
        if (seeded.has(slot.tag)) {
          throw new EcsRuntimeError(
            "duplicate_seed",
            `Component ${slot.label} was seeded twice`,
          );
        }
        seeded.add(slot.tag);
        if (component.values.length !== entityCount) {
          throw new RangeError(
            `Component ${slot.label} needs exactly ${entityCount} entity slots`,
          );
        }
        const values = columns.get(slot.tag)!;
        for (let entity = 0; entity < entityCount; entity++) {
          const value = component.values[entity];
          if (value === null) continue;
          if (!present(alive, entity)) {
            throw new EcsRuntimeError(
              "missing_entity",
              `Cannot seed ${slot.label} on removed entity ${entity}`,
            );
          }
          values.values[entity] = scalarWord(value, slot);
          setPresent(values.present, entity);
        }
      }
      for (const resource of seed.resources ?? []) {
        const slot = storageFor(resource.identity);
        if (slot.kind !== "Resource") {
          throw new EcsRuntimeError(
            "storage_kind",
            `${slot.label} is not a resource`,
          );
        }
        if (seeded.has(slot.tag)) {
          throw new EcsRuntimeError(
            "duplicate_seed",
            `Resource ${slot.label} was seeded twice`,
          );
        }
        seeded.add(slot.tag);
        resources.values[slot.resourceIndex] = scalarWord(resource.value, slot);
        setPresent(resources.present, slot.resourceIndex);
      }
      return snapshot({ entityCount, alive, columns, resources });
    },
    exportWorld(world: EcsWorld): EcsWorldSeed {
      const source = stateOf(world);
      const components: NonNullable<EcsWorldSeed["components"]>[number][] = [];
      const resources: NonNullable<EcsWorldSeed["resources"]>[number][] = [];
      for (const slot of byIdentity.values()) {
        const identity = { ...slot.identity };
        if (slot.kind === "Component") {
          const column = source.columns.get(slot.tag)!;
          components.push({
            identity,
            values: Array.from(
              { length: source.entityCount },
              (_, entity) =>
                present(column.present, entity)
                  ? scalarNumber(column.values[entity], slot)
                  : null,
            ),
          });
        } else if (present(source.resources.present, slot.resourceIndex)) {
          resources.push({
            identity,
            value: scalarNumber(
              source.resources.values[slot.resourceIndex],
              slot,
            ),
          });
        }
      }
      return {
        entityCount: source.entityCount,
        alive: Array.from(
          { length: source.entityCount },
          (_, entity) => present(source.alive, entity),
        ),
        components,
        resources,
      };
    },
    isAlive(world: EcsWorld, entity: number): boolean {
      const source = stateOf(world);
      entityIndex(entity, source.entityCount);
      return present(source.alive, entity);
    },
    withResources(
      world: EcsWorld,
      updates: NonNullable<EcsWorldSeed["resources"]>,
    ): EcsWorld {
      const source = stateOf(world);
      const seen = new Set<number>();
      const resources = {
        values: source.resources.values.slice(),
        present: source.resources.present.slice(),
      };
      for (const update of updates) {
        const slot = storageFor(update.identity);
        if (slot.kind !== "Resource") {
          throw new EcsRuntimeError(
            "storage_kind",
            `${slot.label} is not a resource`,
          );
        }
        if (seen.has(slot.tag)) {
          throw new EcsRuntimeError(
            "duplicate_seed",
            `Resource ${slot.label} was supplied twice`,
          );
        }
        seen.add(slot.tag);
        resources.values[slot.resourceIndex] = scalarWord(update.value, slot);
        setPresent(resources.present, slot.resourceIndex);
      }
      return seen.size === 0 ? world : snapshot({ ...source, resources });
    },
    spawn(
      world: EcsWorld,
      seed: Pick<EcsWorldSeed, "entityCount" | "components">,
    ) {
      const source = stateOf(world);
      const added = stateOf(
        runtime.createWorld({
          entityCount: seed.entityCount,
          components: seed.components,
        }),
      );
      const entityCount = u32(
        source.entityCount + added.entityCount,
        "Entity count after spawn",
      );
      if (added.entityCount === 0) return { world, entities: [] };
      const columns = new Map<number, ComponentColumn>();
      for (const [tag, original] of source.columns) {
        const extra = added.columns.get(tag)!;
        const values = new Uint32Array(entityCount);
        values.set(original.values);
        values.set(extra.values, source.entityCount);
        const bits = presence(entityCount);
        bits.set(original.present);
        for (let entity = 0; entity < added.entityCount; entity++) {
          if (present(extra.present, entity)) {
            setPresent(bits, source.entityCount + entity);
          }
        }
        columns.set(tag, { values, present: bits });
      }
      const alive = presence(entityCount);
      alive.set(source.alive);
      const entities = Array.from(
        { length: added.entityCount },
        (_, index) => source.entityCount + index,
      );
      for (const entity of entities) setPresent(alive, entity);
      return {
        world: snapshot({ ...source, entityCount, alive, columns }),
        entities: Object.freeze(entities),
      };
    },
    despawn(world: EcsWorld, entity: number): EcsWorld {
      const source = stateOf(world);
      entityIndex(entity, source.entityCount);
      if (!present(source.alive, entity)) {
        throw new EcsRuntimeError(
          "missing_entity",
          `Entity ${entity} was removed`,
        );
      }
      const alive = source.alive.slice();
      clearPresent(alive, entity);
      const columns = new Map(source.columns);
      for (const [tag, original] of source.columns) {
        if (!present(original.present, entity)) continue;
        const values = original.values.slice();
        const bits = original.present.slice();
        values[entity] = 0;
        clearPresent(bits, entity);
        columns.set(tag, { values, present: bits });
      }
      return snapshot({ ...source, alive, columns });
    },
    async prepareReload(artifact: EcsArtifact): Promise<EcsReloadPlan> {
      const next = await instantiateRuntime(artifact);
      // Tags and constructor spellings may change, but changing a scalar's
      // interpretation would silently corrupt preserved bits.
      for (const previous of byIdentity.values()) {
        const replacement = next.slots.get(previous.key);
        if (!replacement || replacement.kind !== previous.kind) {
          throw new EcsRuntimeError(
            "incompatible_reload",
            `Reload ${
              replacement ? "changes the storage kind of" : "removes"
            } ${previous.label}; an explicit migration is required`,
          );
        }
        if (replacement.scalar !== previous.scalar) {
          throw new EcsRuntimeError(
            "incompatible_reload",
            `Reload changes the scalar layout of ${previous.label}; an explicit migration is required`,
          );
        }
      }
      return Object.freeze({
        apply(
          world: EcsWorld,
          options: EcsReloadOptions = {},
        ): EcsReloadResult {
          if (running) {
            throw new EcsRuntimeError(
              "reentrant_run",
              "An ECS runtime cannot reload during an active transition",
            );
          }
          const source = stateOf(world);
          const initialized = new Map<string, number>();
          for (const resource of options.resources ?? []) {
            const key = identityKey(resource.identity);
            if (initialized.has(key)) {
              throw new EcsRuntimeError(
                "duplicate_seed",
                `Reload resource ${key} was initialized twice`,
              );
            }
            initialized.set(key, resource.value);
          }
          for (const key of initialized.keys()) {
            const slot = next.slots.get(key);
            if (!slot) {
              throw new EcsRuntimeError(
                "unknown_storage",
                `Unknown reload resource identity ${key}`,
              );
            }
            if (slot.kind !== "Resource") {
              throw new EcsRuntimeError(
                "storage_kind",
                `${slot.label} is not a resource`,
              );
            }
            if (byIdentity.has(key)) {
              throw new EcsRuntimeError(
                "incompatible_reload",
                `Reload initialization cannot overwrite preserved resource ${slot.label}`,
              );
            }
          }
          const columns = new Map<number, ComponentColumn>();
          const resources: ResourceCells = {
            values: new Uint32Array(next.resourceCount),
            present: presence(next.resourceCount),
          };
          for (const slot of next.slots.values()) {
            const previous = byIdentity.get(slot.key);
            if (slot.kind === "Component") {
              // Snapshots only write through copy-on-write drafts, so shared columns
              // stay immutable even when old and reloaded runtimes both advance.
              columns.set(
                slot.tag,
                previous ? source.columns.get(previous.tag)! : {
                  values: new Uint32Array(source.entityCount),
                  present: presence(source.entityCount),
                },
              );
            } else if (previous?.kind === "Resource") {
              resources.values[slot.resourceIndex] =
                source.resources.values[previous.resourceIndex];
              if (present(source.resources.present, previous.resourceIndex)) {
                setPresent(resources.present, slot.resourceIndex);
              }
            } else {
              if (!initialized.has(slot.key)) {
                throw new EcsRuntimeError(
                  "missing_resource",
                  `New resource ${slot.label} needs an explicit reload initializer`,
                );
              }
              resources.values[slot.resourceIndex] = scalarWord(
                initialized.get(slot.key)!,
                slot,
              );
              setPresent(resources.present, slot.resourceIndex);
            }
          }
          return Object.freeze({
            runtime: next.runtime,
            world: next.snapshot({
              entityCount: source.entityCount,
              alive: source.alive,
              columns,
              resources,
            }),
          });
        },
      });
    },
    async reload(
      world: EcsWorld,
      artifact: EcsArtifact,
      options: EcsReloadOptions = {},
    ): Promise<EcsReloadResult> {
      // Snapshot caller-owned options before yielding to Wasm preparation.
      const resources = options.resources?.map(({ identity, value }) => ({
        identity: { ...identity },
        value,
      }));
      const prepared = await runtime.prepareReload(artifact);
      return prepared.apply(world, { resources });
    },
    run(world: EcsWorld, options: EcsRunOptions = {}): EcsWorld {
      return execute(world, null, options);
    },
    runEntity(
      world: EcsWorld,
      entity: number,
      options: EcsRunOptions = {},
    ): EcsWorld {
      return execute(world, entity, options);
    },
    readComponent(
      world: EcsWorld,
      identity: TypeId,
      entity: number,
    ): number | null {
      const state = stateOf(world);
      entityIndex(entity, state.entityCount);
      const slot = storageFor(identity);
      if (slot.kind !== "Component") {
        throw new EcsRuntimeError(
          "storage_kind",
          `${slot.label} is not a component`,
        );
      }
      const values = state.columns.get(slot.tag)!;
      return present(values.present, entity)
        ? scalarNumber(values.values[entity], slot)
        : null;
    },
    readResource(world: EcsWorld, identity: TypeId): number {
      const state = stateOf(world);
      const slot = storageFor(identity);
      if (slot.kind !== "Resource") {
        throw new EcsRuntimeError(
          "storage_kind",
          `${slot.label} is not a resource`,
        );
      }
      return scalarNumber(requireResource(state.resources, slot), slot);
    },
  });
  return { runtime, slots: byIdentity, resourceCount, snapshot };
}
