import {
  copyData,
  type DataNode,
  type DataValue,
  readDataSchemas,
  validateDataRoots,
} from "./cleanup_data.ts";
import {
  type ResourceAdapter,
  type ResourceBindings,
  ResourceJournal,
  ResourceTokens,
} from "./resource_journal.ts";

import {
  taskExports,
  TaskGuest,
  taskImports,
  typedTaskFunctions,
} from "./task_guest.ts";

const littleEndian = new Uint8Array(new Uint32Array([1]).buffer)[0] === 1;

const scalarTypes = ["Unit", "U32", "Bool", "F32"] as const;
export type ScalarType = typeof scalarTypes[number];
export type ScalarValue<T extends ScalarType = ScalarType> = T extends "Unit"
  ? null
  : T extends "Bool" ? boolean
  : number;

export type ArrayType = "Array U32" | "Array F32";
export type ValueType = ScalarType | ArrayType;
export type ValueOf<T extends ValueType> = T extends "Array U32" ? Uint32Array
  : T extends "Array F32" ? Float32Array
  : T extends ScalarType ? ScalarValue<T>
  : never;
export type GuestValue = ValueOf<ValueType>;

function isArrayType(type: ValueType): type is ArrayType {
  return type === "Array U32" || type === "Array F32";
}

export interface CallbackType {
  readonly kind: "callback" | "cleanup";
  readonly concurrent?: true;
  readonly lifetime?: "owned";
  readonly dataSchema?: number;
  readonly parameter: ValueType;
  readonly result: ValueType;
}

export interface OwnerType {
  readonly kind: "owner";
  readonly usage: "unique" | "shared";
  readonly schema: number;
  readonly fresh?: ValueType;
}
const ownerBrand = Symbol("GuestOwner");
export interface GuestOwner {
  readonly [ownerBrand]: true;
  readonly usage: "unique" | "shared";
}
export interface GuestFunction {
  readonly name: string;
  readonly multiplicity?: "once";
  readonly parameter: ValueType | CallbackType | OwnerType;
  readonly result: ValueType | OwnerType;
}

export interface GuestConstant {
  readonly name: string;
  readonly type: ScalarType;
}

export interface GuestAbi {
  readonly version: 2 | 3 | 4 | 5 | 6 | 7 | 8;
  readonly functions: readonly GuestFunction[];
  readonly constants: readonly GuestConstant[];
  readonly taskDescriptorCount?: number;
  readonly resourceAdapterCount?: number;
  readonly resourceTransfer?: boolean;
  readonly publicOwners?: boolean;
}

const dataTypeBrand = Symbol("CleanupDataType");
export interface CleanupDataType {
  readonly [dataTypeBrand]: true;
  readonly name: string;
}
export interface CleanupDataDefinition {
  readonly type: CleanupDataType;
  readonly maxSteps: number;
  readonly maxCalls: number;
  readonly call: (value: DataValue) => null;
}
const dataTypeOwners = new WeakMap<
  object,
  { lifetime: Lifetime; schema: number }
>();
const abiDataSchemas = new WeakMap<GuestAbi, ReadonlyMap<number, DataNode>>();
export type { DataValue } from "./cleanup_data.ts";
const capabilityBrand = Symbol("HostCapability");
export interface HostCapability {
  readonly [capabilityBrand]: true;
  readonly parameter: ValueType;
  readonly result: ValueType;
}

export interface HostCallback<P extends ValueType, R extends ValueType> {
  readonly concurrent?: true;
  readonly parameter: P;
  readonly result: R;
  readonly call: (value: ValueOf<P>) => ValueOf<R>;
}

/** Trusted host promise: each call completes synchronously within maxSteps.
 * maxCalls is independently enforced for each guest invocation. */
export interface HostCleanup<P extends ValueType>
  extends HostCallback<P, "Unit"> {
  readonly maxSteps: number;
  readonly maxCalls: number;
}

export interface AsyncHostCallback<P extends ValueType, R extends ValueType> {
  readonly concurrent?: true;
  readonly parameter: P;
  readonly result: R;
  readonly call: (value: ValueOf<P>) => ValueOf<R> | PromiseLike<ValueOf<R>>;
}

export type GuestErrorCode =
  | "invalid_abi"
  | "invalid_argument"
  | "invalid_capability"
  | "foreign_capability"
  | "stale_capability"
  | "capability_signature"
  | "host_exception"
  | "host_result"
  | "async_host_call"
  | "unsupported_async"
  | "reentrant_call"
  | "disposed_guest"
  | "unknown_export"
  | "once_reused"
  | "invalid_owner"
  | "foreign_owner"
  | "stale_owner"
  | "use_after_move"
  | "owner_type";

export class GuestError extends Error {
  constructor(
    readonly code: GuestErrorCode,
    message: string,
    options?: ErrorOptions,
  ) {
    super(message, options);
    this.name = "GuestError";
  }
}

class AbiReader {
  #offset = 0;
  tasks = false;
  constructor(
    readonly bytes: Uint8Array,
    public owners = false,
    public structured = false,
  ) {}

  byte(): number {
    if (this.#offset === this.bytes.length) {
      throw new GuestError("invalid_abi", "Truncated blot:abi section");
    }
    return this.bytes[this.#offset++];
  }

  count(): number {
    let value = 0;
    for (let shift = 0; shift <= 28; shift += 7) {
      const byte = this.byte();
      if (shift === 28 && byte > 15) break;
      value += (byte & 127) * 2 ** shift;
      if (byte < 128) {
        if (shift !== 0 && byte === 0) break;
        return value;
      }
    }
    throw new GuestError(
      "invalid_abi",
      "Non-canonical U32 in blot:abi section",
    );
  }

  name(): string {
    const length = this.count();
    if (length > this.bytes.length - this.#offset) {
      throw new GuestError("invalid_abi", "Truncated export name in blot:abi");
    }
    const bytes = this.bytes.subarray(this.#offset, this.#offset + length);
    this.#offset += length;
    try {
      return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(
        bytes,
      );
    } catch (cause) {
      throw new GuestError("invalid_abi", "Invalid UTF-8 export name", {
        cause,
      });
    }
  }

  scalar(tag = this.byte()): ScalarType {
    const type = scalarTypes[tag];
    if (type === undefined) {
      throw new GuestError("invalid_abi", `Unknown scalar ABI tag ${tag}`);
    }
    return type;
  }

  value(tag = this.byte()): ValueType {
    if (tag === 5) return "Array U32";
    if (tag === 6) return "Array F32";
    return this.scalar(tag);
  }

  publicValue(tag = this.byte()): ValueType | OwnerType {
    if (tag !== 8 && tag !== 9) return this.value(tag);
    if (!this.owners) {
      throw new GuestError("invalid_abi", "Owner type requires ABI 6");
    }
    const schema = this.count();
    if (schema === 0) {
      throw new GuestError("invalid_abi", "Invalid owner schema");
    }
    const fresh = this.byte();
    let usage: OwnerType["usage"] = "unique";
    if (tag === 9) usage = "shared";
    if (fresh === 255) return Object.freeze({ kind: "owner", usage, schema });
    return Object.freeze({
      kind: "owner",
      usage,
      schema,
      fresh: this.value(fresh),
    });
  }
  parameter(): ValueType | CallbackType | OwnerType {
    const tag = this.byte();
    if ((tag === 11 || tag === 12 && this.owners) && this.structured) {
      const schema = this.count();
      if (schema === 0) {
        throw new GuestError("invalid_abi", "Empty cleanup data schema");
      }
      if (tag === 12) {
        return Object.freeze({
          kind: "cleanup",
          parameter: "U32",
          result: "Unit",
          lifetime: "owned",
          dataSchema: schema,
        });
      }
      return Object.freeze({
        kind: "cleanup",
        parameter: "U32",
        result: "Unit",
        dataSchema: schema,
      });
    }
    if (
      tag === 4 || tag === 7 || tag === 10 && this.owners ||
      tag === 13 && this.tasks
    ) {
      const parameter = this.value();
      const result = this.value();
      if ((tag === 7 || tag === 10) && result !== "Unit") {
        throw new GuestError(
          "invalid_abi",
          "Cleanup callback must return Unit",
        );
      }
      let kind: CallbackType["kind"] = "callback";
      if (tag === 7 || tag === 10) kind = "cleanup";
      if (tag === 10) {
        return Object.freeze({ kind, parameter, result, lifetime: "owned" });
      }
      if (tag === 13) {
        return Object.freeze({ kind, parameter, result, concurrent: true });
      }
      return Object.freeze({ kind, parameter, result });
    }
    return this.publicValue(tag);
  }

  end(): void {
    if (this.#offset !== this.bytes.length) {
      throw new GuestError("invalid_abi", "Trailing bytes in blot:abi section");
    }
  }
}

function importModule(signature: CallbackType): string {
  if (signature.dataSchema !== undefined) {
    if (signature.lifetime === "owned") return "blot:cleanup_data/2";
    return "blot:cleanup_data/1";
  }
  if (signature.lifetime === "owned") return "blot:cleanup/2";
  if (signature.kind === "cleanup") return "blot:cleanup/1";
  return "blot:host/1";
}
function importKey(signature: CallbackType): string {
  return `${importModule(signature)}/${importName(signature)}`;
}
function importName(signature: CallbackType): string {
  if (signature.dataSchema !== undefined) return "call_data_unit";
  return `call_${signature.parameter.toLowerCase().replaceAll(" ", "_")}_${
    signature.result.toLowerCase().replaceAll(" ", "_")
  }`;
}

export function readGuestAbi(module: WebAssembly.Module): GuestAbi {
  const sections = WebAssembly.Module.customSections(module, "blot:abi");
  if (sections.length !== 1) {
    throw new GuestError(
      "invalid_abi",
      "Expected exactly one blot:abi section",
    );
  }
  const reader = new AbiReader(new Uint8Array(sections[0]));
  const version = reader.count();
  if (
    version !== 2 && version !== 3 && version !== 4 && version !== 5 &&
    version !== 6 && version !== 7 && version !== 8
  ) {
    throw new GuestError(
      "invalid_abi",
      `Unsupported guest ABI version ${version}`,
    );
  }
  const countedOwnership = version >= 3 && version <= 7;
  reader.owners = version === 6;
  reader.structured = version === 7;
  let publicOwners = reader.owners;
  let dataSchemas: ReadonlyMap<number, DataNode> | undefined;
  try {
    dataSchemas = readDataSchemas(module);
  } catch (cause) {
    throw new GuestError("invalid_abi", "Invalid cleanup data schemas", {
      cause,
    });
  }
  if ((version === 7) !== (dataSchemas !== undefined)) {
    throw new GuestError(
      "invalid_abi",
      "Cleanup data feature differs from ABI version",
    );
  }
  const functions: GuestFunction[] = [];
  const constants: GuestConstant[] = [];
  const exports = new Map<string, "function" | "global" | "memory">();
  const signatures = new Set<string>();
  const declare = (name: string, kind: "function" | "global" | "memory") => {
    if (exports.has(name)) {
      throw new GuestError("invalid_abi", `Duplicate ABI export ${name}`);
    }
    exports.set(name, kind);
  };
  if (countedOwnership) {
    declare("blot:ownership_enter", "function");
    declare("blot:ownership_leave", "function");
    declare("blot:rc_roots", "global");
  }
  const taskSections = WebAssembly.Module.customSections(module, "blot:tasks");
  let taskCount: number | undefined;
  if (taskSections.length > 1) {
    throw new GuestError("invalid_abi", "Duplicate task feature section");
  }
  if (taskSections.length === 1) {
    const feature = new AbiReader(new Uint8Array(taskSections[0]));
    if (!countedOwnership || feature.byte() !== 2) {
      throw new GuestError(
        "invalid_abi",
        "Unsupported task ownership contract",
      );
    }
    reader.tasks = true;
    taskCount = feature.count();
    if (taskCount > 4096) {
      throw new GuestError("invalid_abi", "Invalid task descriptor count");
    }
    feature.end();
    for (const name of taskExports(taskCount)) declare(name, "function");
  }
  let resources = 0;
  if (version >= 4 && version <= 7) {
    resources = reader.count();
    if ((resources === 0 && version < 6) || resources > 4096) {
      throw new GuestError("invalid_abi", "Invalid resource adapter count");
    }
  }
  let transfer = version === 5;
  if (version === 6 || version === 7) {
    const flags = reader.byte();
    let limit = 1;
    if (version === 7) limit = 3;
    if (flags > limit || (resources === 0 && (flags & 1) !== 0)) {
      throw new GuestError("invalid_abi", "Invalid owner ABI flags");
    }
    transfer = (flags & 1) !== 0;
    if (version === 7) publicOwners = (flags & 2) !== 0;
    reader.owners = publicOwners;
    if (publicOwners) {
      declare("blot:owner_release", "function");
      declare("blot:owner_token", "function");
    }
  }

  const functionCount = reader.count();
  for (let index = 0; index < functionCount; index++) {
    const name = reader.name();
    declare(name, "function");
    const parameter = reader.parameter();
    if (
      version === 8 && typeof parameter !== "string" &&
      (parameter.kind !== "callback" || parameter.concurrent ||
        parameter.lifetime !== undefined || parameter.dataSchema !== undefined)
    ) {
      throw new GuestError(
        "invalid_abi",
        "Data-stack ABI accepts only Foreign callbacks",
      );
    }
    if (typeof parameter !== "string" && parameter.kind !== "owner") {
      signatures.add(importKey(parameter));
      if (parameter.lifetime === "owned") {
        let binder = "blot:cleanup_bind/1";
        if (parameter.dataSchema !== undefined) {
          binder = "blot:cleanup_data_bind/1";
        }
        signatures.add(`${binder}/${importName(parameter)}`);
      }
    }
    const result = reader.publicValue();
    if (typeof result !== "string" && result.fresh !== undefined) {
      throw new GuestError(
        "invalid_abi",
        "Owner results cannot declare fresh arguments",
      );
    }
    if (
      typeof parameter !== "string" && parameter.kind === "owner" &&
      parameter.fresh !== undefined
    ) declare(`blot:owner_call/${name}`, "function");
    functions.push(Object.freeze({ name, parameter, result }));
  }
  const constantCount = reader.count();
  for (let index = 0; index < constantCount; index++) {
    const name = reader.name();
    declare(name, "global");
    constants.push(Object.freeze({ name, type: reader.scalar() }));
  }
  reader.end();
  try {
    validateDataRoots(
      dataSchemas,
      functions.flatMap((fn) => {
        if (
          typeof fn.parameter === "string" || fn.parameter.kind === "owner" ||
          fn.parameter.dataSchema === undefined
        ) return [];
        return [fn.parameter.dataSchema];
      }),
    );
  } catch (cause) {
    throw new GuestError("invalid_abi", "Invalid cleanup data schema roots", {
      cause,
    });
  }
  const multiplicity = WebAssembly.Module.customSections(
    module,
    "blot:multiplicity",
  );
  if (multiplicity.length > 1) {
    throw new GuestError("invalid_abi", "Duplicate multiplicity section");
  }
  if (multiplicity.length === 1) {
    const usage = new AbiReader(new Uint8Array(multiplicity[0]));
    if (usage.count() !== 1) {
      throw new GuestError("invalid_abi", "Unsupported multiplicity version");
    }
    const count = usage.count();
    if (count === 0 || count > functions.length) {
      throw new GuestError("invalid_abi", "Invalid multiplicity count");
    }
    const seen = new Set<string>();
    const positions = new Map(functions.map((fn, index) => [fn.name, index]));
    for (let index = 0; index < count; index++) {
      const name = usage.name();
      const position = positions.get(name);
      if (position === undefined || seen.has(name) || usage.byte() !== 1) {
        throw new GuestError("invalid_abi", "Invalid once function entry");
      }
      seen.add(name);
      functions[position] = Object.freeze({
        ...functions[position],
        multiplicity: "once",
      });
    }
    usage.end();
  }
  if (
    version === 5 || version >= 6 && resources !== 0 ||
    functions.some((fn) =>
      (typeof fn.parameter === "string" && isArrayType(fn.parameter)) ||
      (typeof fn.result === "string" && isArrayType(fn.result)) ||
      (typeof fn.parameter !== "string" && fn.parameter.kind === "owner" &&
        fn.parameter.fresh !== undefined && isArrayType(fn.parameter.fresh)) ||
      (typeof fn.parameter !== "string" && fn.parameter.kind !== "owner" &&
        (fn.parameter.dataSchema !== undefined ||
          isArrayType(fn.parameter.parameter) ||
          isArrayType(fn.parameter.result)))
    )
  ) {
    declare("blot:memory", "memory");
    declare("blot:allocate", "function");
    declare("blot:reset", "function");
  }
  if (countedOwnership && (signatures.size !== 0 || taskCount !== undefined)) {
    declare("blot:rc_host_refs", "global");
  }
  if (resources !== 0) {
    for (let index = 0; index < resources; index++) {
      declare(resourceExport(index, false), "function");
      declare(resourceExport(index, true), "function");
    }
  }
  if (taskCount !== undefined && !exports.has("blot:memory")) {
    declare("blot:memory", "memory");
  }
  const expectedTaskImports = new Set<string>();
  if (taskCount !== undefined) {
    for (const [name] of taskImports) expectedTaskImports.add(name);
  }
  const resourceImports = new Set<string>();
  if (resources !== 0) {
    resourceImports.add("reserve");
    resourceImports.add("register");
    resourceImports.add("release");
  }
  const transferImports = new Set<string>();
  if (transfer) {
    transferImports.add("register_owned");
    transferImports.add("retire");
    transferImports.add("drain");
  }
  const actualExports = WebAssembly.Module.exports(module);
  const ownership = WebAssembly.Module.customSections(module, "blot:ownership");
  if (version === 8 && ownership.length !== 0) {
    throw new GuestError(
      "invalid_abi",
      "Data-stack ABI cannot declare counted ownership",
    );
  }
  if (ownership.length > 1) {
    throw new GuestError("invalid_abi", "Duplicate ownership section");
  }
  if (ownership.length === 1) {
    const state = new Uint8Array(ownership[0]);
    if (
      state.length !== 3 || (state[0] !== 1 && state[0] !== 2) ||
      state[1] > state[0] || state[2] > 7 ||
      (state[1] !== 0) !== (state[2] === 0) ||
      countedOwnership !== (state[0] === 2 && state[1] === 2)
    ) throw new GuestError("invalid_abi", "Invalid ownership section");
    if (state[2] !== 1) {
      // Optional raw-allocator identity for development instrumentation. Older
      // modules remain valid; unknown exports and wrong export kinds still fail.
      if (actualExports.some((entry) => entry.name === "blot:allocation")) {
        declare("blot:allocation", "function");
      }
      for (const counter of ["leases", "retains", "releases", "destroyed"]) {
        declare(`blot:rc_${counter}`, "global");
      }
    }
  }
  const cycles = WebAssembly.Module.customSections(module, "blot:cycles");
  if (cycles.length > 1) {
    throw new GuestError("invalid_abi", "Duplicate cycle section");
  }
  if (cycles.length === 1) {
    const state = new Uint8Array(cycles[0]);
    if (
      state.length !== 2 || state[0] !== 1 || state[1] > 1 ||
      ownership.length !== 1 ||
      state[1] !== Number(new Uint8Array(ownership[0])[1] !== 0)
    ) {
      throw new GuestError("invalid_abi", "Invalid cycle section");
    }
    for (const counter of ["passes", "vertices", "edges", "bytes"]) {
      declare(`blot:cycle_${counter}`, "global");
    }
  }
  if (countedOwnership && ownership.length !== 1) {
    throw new GuestError("invalid_abi", "Missing root ownership section");
  }
  const memoryProfile = WebAssembly.Module.customSections(
    module,
    "blot:memory-profile",
  );
  if (version === 8 && memoryProfile.length !== 0) {
    throw new GuestError(
      "invalid_abi",
      "Data-stack ABI cannot declare a counted memory profile",
    );
  }
  if (memoryProfile.length > 1) {
    throw new GuestError("invalid_abi", "Duplicate memory profile section");
  }
  if (memoryProfile.length === 1) {
    for (let word = 0; word < 8; word++) {
      declare(`blot:profile_identity_${word}`, "global");
    }
    // Instrumentation exposes its diagnostic counters through the same memory
    // as ordinary numeric results, even for scalar-only source exports.
    if (!exports.has("blot:memory")) declare("blot:memory", "memory");
  }
  if (
    actualExports.length !== exports.size ||
    actualExports.some((entry) => exports.get(entry.name) !== entry.kind)
  ) {
    throw new GuestError("invalid_abi", "Wasm exports differ from blot:abi");
  }
  for (const entry of WebAssembly.Module.imports(module)) {
    if (
      entry.module === "blot:task/1" && entry.kind === "function" &&
      expectedTaskImports.delete(entry.name)
    ) continue;
    if (
      entry.module === "blot:resource/1" && entry.kind === "function" &&
      resourceImports.delete(entry.name)
    ) continue;
    if (
      entry.module === "blot:resource/2" && entry.kind === "function" &&
      transferImports.delete(entry.name)
    ) continue;
    if (
      (entry.module !== "blot:host/1" && entry.module !== "blot:cleanup/1" &&
        entry.module !== "blot:cleanup/2" &&
        entry.module !== "blot:cleanup_bind/1" &&
        entry.module !== "blot:cleanup_data/1" &&
        entry.module !== "blot:cleanup_data/2" &&
        entry.module !== "blot:cleanup_data_bind/1") ||
      entry.kind !== "function" ||
      !signatures.delete(`${entry.module}/${entry.name}`)
    ) {
      throw new GuestError(
        "invalid_abi",
        `Unexpected Wasm import ${entry.module}/${entry.name}`,
      );
    }
  }
  // Collect extends the private task protocol; older task modules only use
  // the original single-receiver operations.
  expectedTaskImports.delete("collect");
  if (expectedTaskImports.size !== 0) {
    throw new GuestError("invalid_abi", "Missing task protocol import");
  }
  if (resourceImports.size !== 0 || transferImports.size !== 0) {
    throw new GuestError("invalid_abi", "Missing resource journal import");
  }
  if (signatures.size !== 0) {
    throw new GuestError("invalid_abi", "Missing generic callback import");
  }
  const result: GuestAbi = {
    version,
    functions: Object.freeze(functions),
    constants: Object.freeze(constants),
  };
  if (taskCount !== undefined) {
    Object.assign(result, {
      taskDescriptorCount: taskCount,
    });
  }
  if (resources !== 0) {
    Object.assign(result, { resourceAdapterCount: resources });
  }
  if (version === 6 || version === 7) {
    Object.assign(result, { resourceTransfer: transfer, publicOwners });
  }
  if (dataSchemas) abiDataSchemas.set(result, dataSchemas);
  return Object.freeze(result);
}

function scalarToWasm(
  type: ScalarType,
  value: unknown,
  code: "invalid_argument" | "host_result",
  label: string,
): number {
  switch (type) {
    case "Unit":
      if (value === null) return 0;
      break;
    case "Bool":
      if (typeof value === "boolean") return value ? 1 : 0;
      break;
    case "U32":
      if (
        typeof value === "number" && Number.isInteger(value) && value >= 0 &&
        value <= 0xFFFFFFFF
      ) return value;
      break;
    case "F32":
      if (typeof value === "number") return Math.fround(value);
      break;
  }
  throw new GuestError(code, `${label} must be ${type}`);
}

function scalarFromWasm(type: ScalarType, value: unknown): ScalarValue {
  if (typeof value !== "number") {
    throw new GuestError("invalid_abi", `Wasm ${type} value is not a number`);
  }
  switch (type) {
    case "Unit":
      if (value === 0) return null;
      break;
    case "Bool":
      if (value === 0 || value === 1) return value === 1;
      break;
    case "U32":
      if (
        Number.isInteger(value) && value >= -0x80000000 && value <= 0x7FFFFFFF
      ) {
        return value >>> 0;
      }
      break;
    case "F32":
      return Math.fround(value);
  }
  throw new GuestError("invalid_abi", `Non-canonical Wasm ${type} value`);
}

interface GuestArena {
  readonly memory: WebAssembly.Memory;
  readonly allocate: CallableFunction;
  readonly reset: CallableFunction;
}

function arrayRange(
  arena: GuestArena,
  pointer: unknown,
  length: number,
): number {
  if (
    typeof pointer !== "number" || !Number.isInteger(pointer) ||
    pointer < -0x8000_0000 || pointer > 0xffff_ffff
  ) {
    throw new GuestError("invalid_abi", "Array lies outside the guest arena");
  }
  // Wasm exposes i32 results as signed JS numbers, including valid addresses
  // in the upper half of its 4 GiB address space.
  const address = pointer >>> 0;
  if (
    address < 4 || address % 4 !== 0 ||
    address > arena.memory.buffer.byteLength - 4 ||
    length > (arena.memory.buffer.byteLength - address - 4) / 4
  ) {
    throw new GuestError("invalid_abi", "Array lies outside the guest arena");
  }
  return address;
}

function arrayToWasm(
  arena: GuestArena,
  type: ArrayType,
  argument: unknown,
  name: string,
  code: "invalid_argument" | "host_result" = "invalid_argument",
): number {
  if (
    !(type === "Array U32"
      ? argument instanceof Uint32Array
      : argument instanceof Float32Array)
  ) {
    throw new GuestError(
      code,
      `${name} argument must be ${
        type === "Array U32" ? "Uint32Array" : "Float32Array"
      }`,
    );
  }
  const values = argument as Uint32Array | Float32Array;
  const length = values.length;
  const byteLength = length * 4;
  if (length >= 1_073_741_823) {
    throw new GuestError(
      code,
      `${name} array byte count exceeds the Wasm32 address range`,
    );
  }
  const pointer = arrayRange(
    arena,
    arena.allocate((length + 1) * 4),
    length,
  );
  // Allocation may grow memory, so acquire a fresh view only afterwards.
  const view = new DataView(arena.memory.buffer);
  view.setUint32(pointer, length, true);
  if (
    littleEndian && length > 32 && values.buffer instanceof ArrayBuffer
  ) {
    // Byte copies avoid boxing every element and preserve F32 payload bits.
    // Use the view's range, not its entire possibly shared backing buffer.
    new Uint8Array(arena.memory.buffer, pointer + 4, byteLength).set(
      new Uint8Array(values.buffer, values.byteOffset, byteLength),
    );
  } else {
    // Small packets avoid extra byte views. Shared inputs retain no-tear U32
    // reads instead of observing a word as four independently changing bytes.
    // This is not a coherent snapshot of a concurrently modified whole array.
    // Raw words also preserve F32 payloads and handle big-endian hosts.
    const input = type === "Array U32"
      ? values as Uint32Array
      : new Uint32Array(values.buffer, values.byteOffset, length);
    for (let index = 0; index < length; index++) {
      view.setUint32(pointer + 4 + index * 4, input[index], true);
    }
  }
  return pointer;
}

function arrayFromWasm(
  arena: GuestArena,
  type: ArrayType,
  result: unknown,
): Uint32Array | Float32Array {
  const pointer = arrayRange(arena, result, 0);
  // Guest execution may also grow memory; never retain the input view.
  const view = new DataView(arena.memory.buffer);
  const length = view.getUint32(pointer, true);
  arrayRange(arena, pointer, length);
  const values = type === "Array U32"
    ? new Uint32Array(length)
    : new Float32Array(length);
  if (littleEndian && length > 32) {
    // Still copy out: the arena is reset/reused after the invocation, and a
    // host callback must never receive a mutable alias into guest storage.
    new Uint8Array(values.buffer).set(
      new Uint8Array(arena.memory.buffer, pointer + 4, values.byteLength),
    );
  } else {
    const output = type === "Array U32"
      ? values as Uint32Array
      : new Uint32Array(values.buffer);
    for (let index = 0; index < length; index++) {
      output[index] = view.getUint32(pointer + 4 + index * 4, true);
    }
  }
  return values;
}

interface Lifetime {
  disposed: boolean;
}
interface CapabilityOwner {
  readonly lifetime: Lifetime;
  readonly signature: CallbackType;
  readonly asynchronous: boolean;
  readonly maxCalls?: number;
}
const capabilityOwners = new WeakMap<object, CapabilityOwner>();
interface PublicOwnerState {
  readonly lifetime: Lifetime;
  readonly schema: number;
  readonly usage: "unique" | "shared";
  readonly token: number;
  live: boolean;
}
const publicOwnerStates = new WeakMap<object, PublicOwnerState>();
type InvokeCallback = (value: GuestValue | DataValue) => unknown;

export interface Guest {
  /** Committed linear-memory bytes, including temporary allocation capacity. */
  memoryBytes(): number;
  readonly abi: GuestAbi;
  capability<P extends ValueType, R extends ValueType>(
    callback: HostCallback<P, R>,
  ): HostCapability;
  cleanupCapability<P extends ValueType>(
    callback: HostCleanup<P>,
  ): HostCapability;
  capabilityAsync<P extends ValueType, R extends ValueType>(
    callback: AsyncHostCallback<P, R>,
  ): HostCapability;
  call(name: string, argument: unknown): GuestValue | GuestOwner;
  callAsync(name: string, argument: unknown): Promise<GuestValue | GuestOwner>;
  read(name: string): ScalarValue;
  cleanupDataType(name: string): CleanupDataType;
  cleanupDataCapability(definition: CleanupDataDefinition): HostCapability;
  releaseOwner(owner: GuestOwner): void;
  dispose(): void;
}

// JSPI is optional for synchronous guests. Keep this structural definition until
// TypeScript's WebAssembly declarations include the standardized API.
interface PromiseIntegration {
  Suspending: new (callback: CallableFunction) => WebAssembly.ImportValue;
  promising: (
    exported: CallableFunction,
  ) => (value: unknown) => Promise<unknown>;
}

function resourceExport(index: number, drop: boolean): string {
  if (drop) return `blot:resource_drop/${index}`;
  return `blot:resource_cleanup/${index}`;
}
function resourceU32(value: number): number[] {
  const bytes: number[] = [];
  do {
    let byte = value & 127;
    value >>>= 7;
    if (value !== 0) byte |= 128;
    bytes.push(byte);
  } while (value !== 0);
  return bytes;
}
function resourceName(value: string): number[] {
  const bytes = [...new TextEncoder().encode(value)];
  return [...resourceU32(bytes.length), ...bytes];
}
function resourceModule(
  sections: readonly (readonly number[])[],
): WebAssembly.Module {
  return new WebAssembly.Module(
    new Uint8Array([
      0,
      97,
      115,
      109,
      1,
      0,
      0,
      0,
      ...sections.flatMap((section, index) => {
        if (section.length === 0) return [];
        return [index + 1, ...resourceU32(section.length), ...section];
      }),
    ]),
  );
}
function typedCleanupImport(
  signature: CallbackType,
  callback: CallableFunction,
): WebAssembly.ImportValue {
  let parameter = 127;
  if (signature.parameter === "F32") parameter = 125;
  let handle = 111;
  if (signature.lifetime === "owned") handle = 127;
  let parameters = [2, handle, parameter];
  if (signature.dataSchema !== undefined) parameters = [3, handle, 127, 127];
  const module = resourceModule([
    [1, 96, ...parameters, 1, 127],
    [1, ...resourceName("h"), ...resourceName("c"), 0, 0],
    [],
    [],
    [],
    [],
    [1, ...resourceName("c"), 0, 0],
  ]);
  return new WebAssembly.Instance(module, { h: { c: callback } }).exports.c;
}
function typedCleanupBind(
  callback: CallableFunction,
  data = false,
): WebAssembly.ImportValue {
  let parameters = [1, 111];
  if (data) parameters = [2, 111, 127];
  const module = resourceModule([
    [1, 96, ...parameters, 1, 127],
    [1, ...resourceName("h"), ...resourceName("c"), 0, 0],
    [],
    [],
    [],
    [],
    [1, ...resourceName("c"), 0, 0],
  ]);
  return new WebAssembly.Instance(module, { h: { c: callback } }).exports.c;
}
function typedResourceImports(
  imports: Record<string, WebAssembly.ImportValue>,
  transfers = false,
): Record<string, WebAssembly.ImportValue> {
  let names = ["reserve", "register", "release"];
  let parameters = [0, 5, 1];
  if (transfers) {
    names = ["register_owned", "retire", "drain"];
    parameters = [6, 1, 0];
  }
  const types: number[] = [names.length];
  for (let index = 0; index < names.length; index++) {
    types.push(96, parameters[index]);
    for (let count = 0; count < parameters[index]; count++) types.push(127);
    if (!transfers && index === 0) types.push(1, 127);
    else types.push(0);
  }
  const linked = [names.length];
  const exports = [names.length];
  for (const [index, name] of names.entries()) {
    linked.push(...resourceName("j"), ...resourceName(name), 0, index);
    exports.push(...resourceName(name), 0, index);
  }
  // Typed re-exports independently check actual import signatures before use.
  const module = resourceModule([types, linked, [], [], [], [], exports]);
  return new WebAssembly.Instance(module, { j: imports }).exports;
}
function resourceAdapters(
  instance: WebAssembly.Instance,
  count: number,
): ResourceAdapter[] {
  const adapters: ResourceAdapter[] = [];
  const imported: Record<string, WebAssembly.ExportValue> = {};
  const imports = resourceU32(count * 2);
  for (let index = 0; index < count; index++) {
    const cleanup = instance.exports[resourceExport(index, false)];
    const drop = instance.exports[resourceExport(index, true)];
    if (typeof cleanup !== "function" || typeof drop !== "function") {
      throw new GuestError("invalid_abi", "Missing resource adapter");
    }
    for (const [suffix, fn] of [["c", cleanup], ["d", drop]] as const) {
      const name = `${suffix}${index}`;
      imported[name] = fn;
      imports.push(...resourceName("o"), ...resourceName(name), 0, 0);
    }
    adapters.push({
      cleanup: cleanup as ResourceAdapter["cleanup"],
      drop: drop as ResourceAdapter["drop"],
    });
  }
  // Link exact (i32,i32,i32)->Unit exports without invoking cleanup.
  try {
    new WebAssembly.Instance(
      resourceModule([[1, 96, 3, 127, 127, 127, 0], imports]),
      { o: imported },
    );
  } catch (cause) {
    throw new GuestError("invalid_abi", "Invalid resource adapter signature", {
      cause,
    });
  }
  return adapters;
}

/** Invocation-scoped capabilities. Async invocations retain memory while suspended. */
export async function instantiateGuest(
  bytes: Uint8Array<ArrayBuffer> | WebAssembly.Module,
  options: { readonly asynchronous?: boolean } = {},
): Promise<Guest> {
  const module = bytes instanceof WebAssembly.Module
    ? bytes
    : await WebAssembly.compile(bytes);
  const abi = readGuestAbi(module);
  const dataSchemas = abiDataSchemas.get(abi);
  const functions = new Map(abi.functions.map((fn) => [fn.name, fn]));
  const constants = new Map(
    abi.constants.map((constant) => [constant.name, constant]),
  );
  const jspi = WebAssembly as unknown as Partial<PromiseIntegration>;
  function requireAsync(): PromiseIntegration {
    if (!jspi.Suspending || !jspi.promising) {
      throw new GuestError(
        "unsupported_async",
        "Async guests require WebAssembly.Suspending and WebAssembly.promising",
      );
    }
    return jspi as PromiseIntegration;
  }
  if (options.asynchronous) requireAsync();
  const lifetime: Lifetime = { disposed: false };
  let callbacks = new WeakMap<object, InvokeCallback>();
  let active: {
    readonly reference: object;
    readonly signature: CallbackType;
    readonly invoke: InvokeCallback;
    readonly exportName: string;
    readonly asynchronous: boolean;
    readonly maxCalls?: number;
    calls: number;
    binding?: number;
  } | undefined;
  let epoch = 0;
  let nextBinding = 1;
  let bindings:
    | Map<number, {
      reference: object;
      signature: CallbackType;
      invoke: InvokeCallback;
      exportName: string;
      asynchronous: boolean;
      maxCalls: number;
      calls: number;
      epoch: number;
      refs: number;
    }>
    | undefined;
  let running = false;

  function idle(): void {
    if (lifetime.disposed) {
      throw new GuestError("disposed_guest", "Guest instance is disposed");
    }
    if (running) {
      throw new GuestError(
        "reentrant_call",
        "Cannot reenter an active guest instance",
      );
    }
  }

  let arena: GuestArena | undefined;
  function fromWasm(type: ValueType, value: unknown): GuestValue {
    if (!isArrayType(type)) return scalarFromWasm(type, value);
    if (!arena) {
      throw new GuestError("invalid_abi", "Array callback requires an arena");
    }
    return arrayFromWasm(arena, type, value);
  }
  function hostResult(type: ValueType, value: unknown, name: string): number {
    const label = `Host callback result during ${name}`;
    if (!isArrayType(type)) {
      return scalarToWasm(type, value, "host_result", label);
    }
    if (!arena) {
      throw new GuestError("invalid_abi", "Array callback requires an arena");
    }
    return arrayToWasm(arena, type, value, label, "host_result");
  }
  async function asynchronousResult(
    type: ValueType,
    result: unknown,
    name: string,
    taskContext: number | undefined,
  ): Promise<number> {
    let value: unknown;
    try {
      value = await result;
    } catch (cause) {
      if (taskContext !== undefined) tasks!.imports.resume(taskContext);
      throw new GuestError(
        "host_exception",
        `Host callback rejected during ${name}`,
        { cause },
      );
    }
    if (taskContext !== undefined) tasks!.imports.resume(taskContext);
    return hostResult(type, value, name);
  }
  const imports: Record<string, WebAssembly.ImportValue> = {};
  const cleanupImports: Record<string, WebAssembly.ImportValue> = {};
  const ownedCleanupImports: Record<string, WebAssembly.ImportValue> = {};
  const cleanupBindImports: Record<string, WebAssembly.ImportValue> = {};
  const dataCleanupImports: Record<string, WebAssembly.ImportValue> = {};
  const ownedDataCleanupImports: Record<string, WebAssembly.ImportValue> = {};
  const dataBindImports: Record<string, WebAssembly.ImportValue> = {};
  for (const fn of abi.functions) {
    if (typeof fn.parameter === "string" || fn.parameter.kind === "owner") {
      continue;
    }
    const signature = fn.parameter;
    if (signature.lifetime === "owned") bindings ??= new Map();
    const invokeImport = (
      reference: unknown,
      value: number,
      data?: number,
    ): number | Promise<number> => {
      let invocation: NonNullable<typeof active> | undefined = active;
      if (signature.lifetime === "owned") {
        const binding = bindings!.get(Number(reference) >>> 0);
        invocation = binding;
        if (!running || !binding) invocation = undefined;
        if (binding && binding.epoch !== epoch) {
          binding.epoch = epoch;
          binding.calls = 0;
        }
      }
      if (
        !invocation ||
        signature.lifetime !== "owned" && reference !== invocation.reference
      ) {
        throw new GuestError(
          "stale_capability",
          "Host call has no active capability reference",
        );
      }
      if (
        signature.dataSchema !== undefined &&
          (value >>> 0) !== invocation.signature.dataSchema ||
        signature.dataSchema === undefined &&
          invocation.signature.dataSchema !== undefined
      ) {
        throw new GuestError(
          "capability_signature",
          "Cleanup data call differs from its exact schema",
        );
      }
      if (
        signature.kind !== invocation.signature.kind ||
        signature.parameter !== invocation.signature.parameter ||
        signature.result !== invocation.signature.result
      ) {
        throw new GuestError(
          "capability_signature",
          "Host call signature does not match its capability",
        );
      }
      if (signature.kind === "cleanup") {
        if (
          invocation.maxCalls === undefined ||
          invocation.calls >= invocation.maxCalls
        ) {
          throw new GuestError(
            "host_exception",
            "Cleanup invocation limit exceeded",
          );
        }
        invocation.calls++;
      }
      let argument: GuestValue | DataValue;
      if (signature.dataSchema !== undefined) {
        if (!arena || !dataSchemas || data === undefined) {
          throw new GuestError("invalid_abi", "Missing cleanup data memory");
        }
        try {
          argument = copyData(
            arena.memory,
            dataSchemas,
            value >>> 0,
            data >>> 0,
          );
        } catch (cause) {
          throw new GuestError("invalid_abi", "Invalid cleanup data value", {
            cause,
          });
        }
      } else argument = fromWasm(signature.parameter, value);
      const taskContext = tasks?.imports.current();
      let result: unknown;
      try {
        result = invocation.invoke(argument);
      } catch (cause) {
        throw new GuestError(
          "host_exception",
          `Host callback threw during ${invocation.exportName}`,
          { cause },
        );
      }
      if (
        (typeof result === "object" && result !== null ||
          typeof result === "function") &&
        "then" in result
      ) {
        if (invocation.asynchronous) {
          return asynchronousResult(
            signature.result,
            result,
            invocation.exportName,
            taskContext,
          );
        }
        let message =
          `Host callback returned a Promise/thenable during ${invocation.exportName}; use capabilityAsync() and callAsync()`;
        if (signature.kind === "cleanup") {
          message =
            `Cleanup callback must complete synchronously during ${invocation.exportName}`;
        }
        const failure = new GuestError(
          "async_host_call",
          message,
        );
        // The intrinsic checks Promise identity across realms without calling
        // a user-supplied then/catch. Non-Promise thenables throw here; report
        // that cause with the already-failed synchronous contract.
        try {
          Promise.prototype.then.call(result, undefined, () => {});
        } catch (cause) {
          failure.cause = cause;
        }
        throw failure;
      }
      return hostResult(signature.result, result, invocation.exportName);
    };
    if (signature.lifetime === "owned") {
      let invocationImports = ownedCleanupImports;
      let bindingImports = cleanupBindImports;
      if (signature.dataSchema !== undefined) {
        invocationImports = ownedDataCleanupImports;
        bindingImports = dataBindImports;
      }
      invocationImports[importName(signature)] = typedCleanupImport(
        signature,
        invokeImport,
      );
      bindingImports[importName(signature)] = typedCleanupBind(
        (reference: unknown, schema?: number) => {
          const invocation = active;
          if (
            !running || !invocation || reference !== invocation.reference ||
            invocation.signature.kind !== "cleanup" ||
            (signature.dataSchema !== undefined &&
              invocation.signature.dataSchema !== (schema! >>> 0)) ||
            (signature.dataSchema === undefined &&
              invocation.signature.dataSchema !== undefined) ||
            invocation.signature.parameter !== signature.parameter ||
            invocation.signature.result !== "Unit" || invocation.asynchronous ||
            invocation.maxCalls === undefined
          ) {
            throw new GuestError(
              "stale_capability",
              "Owned cleanup binding requires an active synchronous cleanup capability",
            );
          }
          if (
            bindings!.size === 4096 || nextBinding > 0xFFFFFFFF ||
            invocation.binding !== undefined
          ) {
            throw new GuestError("host_exception", "Cleanup binding limit");
          }
          const binding = nextBinding++;
          bindings!.set(binding, {
            ...invocation,
            maxCalls: invocation.maxCalls,
            refs: 0,
            epoch,
          });
          invocation.binding = binding;
          return binding;
        },
        signature.dataSchema !== undefined,
      );
    } else if (signature.kind === "cleanup") {
      let invocationImports = cleanupImports;
      if (signature.dataSchema !== undefined) {
        invocationImports = dataCleanupImports;
      }
      invocationImports[importName(signature)] = typedCleanupImport(
        signature,
        invokeImport,
      );
    } else if (options.asynchronous) {
      imports[importName(signature)] = new (requireAsync().Suspending)(
        invokeImport,
      );
    } else {
      imports[importName(signature)] = invokeImport;
    }
  }
  let resources: ResourceJournal | undefined;
  let rootResources: ResourceJournal | undefined;
  let makeTaskJournal: (() => ResourceJournal) | undefined;
  let tasks: TaskGuest | undefined;
  let initializing = true;
  const modules: WebAssembly.Imports = {
    "blot:host/1": imports,
    "blot:cleanup/1": cleanupImports,
    "blot:cleanup/2": ownedCleanupImports,
    "blot:cleanup_bind/1": cleanupBindImports,
    "blot:cleanup_data/1": dataCleanupImports,
    "blot:cleanup_data/2": ownedDataCleanupImports,
    "blot:cleanup_data_bind/1": dataBindImports,
  };
  if (abi.taskDescriptorCount !== undefined) {
    const callbacks: Record<string, WebAssembly.ImportValue> = {};
    for (const [name] of taskImports) {
      const invoke = (...args: number[]) => {
        if (!tasks) {
          throw new GuestError("invalid_abi", "Task runtime is not active");
        }
        return (tasks.imports[name] as (...values: number[]) => unknown)(
          ...args,
        );
      };
      if (
        options.asynchronous &&
        ["close", "join", "collect", "cancel", "drop", "drain"].includes(name)
      ) callbacks[name] = new (requireAsync().Suspending)(invoke);
      else callbacks[name] = invoke;
    }
    modules["blot:task/1"] = typedTaskFunctions(callbacks);
  }
  const count = abi.resourceAdapterCount ?? 0;
  if (count !== 0) {
    modules["blot:resource/1"] = typedResourceImports({
      reserve: () => {
        if (!resources) {
          throw new GuestError("invalid_abi", "Resource journal is not active");
        }
        return resources.reserve();
      },
      register: (
        token: number,
        adapter: number,
        payload: number,
        callable: number,
        provider: number,
      ) => {
        if (!resources) {
          throw new GuestError("invalid_abi", "Resource journal is not active");
        }
        resources.register(
          token >>> 0,
          adapter >>> 0,
          payload >>> 0,
          callable >>> 0,
          provider >>> 0,
        );
      },
      release: (token: number) => {
        if (!resources) {
          throw new GuestError("invalid_abi", "Resource journal is not active");
        }
        resources.release(token >>> 0);
      },
    });
  }
  if (abi.version === 5 || abi.version >= 6 && abi.resourceTransfer) {
    modules["blot:resource/2"] = typedResourceImports({
      register_owned: (
        token: number,
        adapter: number,
        payload: number,
        callable: number,
        provider: number,
        owner: number,
      ) => {
        if (!resources) {
          throw new GuestError("invalid_abi", "Resource journal is not active");
        }
        token >>>= 0;
        owner >>>= 0;
        adapter >>>= 0;
        payload >>>= 0;
        callable >>>= 0;
        provider >>>= 0;
        let words: Uint32Array;
        const memory = instance.exports["blot:memory"];
        if (
          !(memory instanceof WebAssembly.Memory) || owner < 32 ||
          owner % 4 !== 0 || owner > memory.buffer.byteLength - 8
        ) throw new GuestError("invalid_abi", "Invalid resource owner address");
        try {
          words = new Uint32Array(memory.buffer);
        } catch (cause) {
          // Acquisition has already succeeded. Unexpected host allocation
          // failure still transfers the retained roots to one cleanup attempt.
          resources.register(token, adapter, payload, callable, provider);
          try {
            resources.release(token);
          } catch {
            // Preserve failed publication after consuming the cleanup attempt.
          }
          throw cause;
        }
        const slot = owner / 4;
        let layout = 0;
        if (adapter === 2) layout = 1;
        if (
          adapter > 2 || words[slot - 7] !== 8 ||
          (words[slot - 6] & 3092) !== 4 || words[slot - 4] === 0 ||
          words[slot - 3] !== layout || words[slot] !== payload ||
          words[slot + 1] !== 0
        ) {
          throw new GuestError(
            "invalid_abi",
            "Resource owner identity changed",
          );
        }
        resources.registerOwned(
          token,
          adapter,
          payload,
          callable,
          provider,
          owner,
        );
        // Journal capacity, identity and retained roots are established before
        // this allocation-free publication. No user code runs between stores.
        words[slot + 1] = token;
        words[slot - 6] |= 2048;
      },
      retire: (token: number) => {
        if (!resources) {
          throw new GuestError("invalid_abi", "Resource journal is not active");
        }
        resources.retire(token >>> 0);
      },
      drain: () => {
        // Startup cannot reserve/register a resource. A typed root initializer
        // may still emit its empty deferred-retirement safe point.
        if (!resources && initializing) return;
        if (!resources) {
          throw new GuestError("invalid_abi", "Resource journal is not active");
        }
        resources.drain();
      },
    }, true);
  }
  let instance: WebAssembly.Instance;
  try {
    instance = await WebAssembly.instantiate(module, modules);
    initializing = false;
  } catch (cause) {
    if (
      count !== 0 || Object.keys(cleanupImports).length !== 0 ||
      Object.keys(ownedCleanupImports).length !== 0 ||
      Object.keys(dataCleanupImports).length !== 0 ||
      Object.keys(ownedDataCleanupImports).length !== 0
    ) {
      throw new GuestError(
        "invalid_abi",
        "Invalid checked guest import signature",
        { cause },
      );
    }
    throw cause;
  }
  if (count !== 0 || abi.taskDescriptorCount !== undefined) {
    let invalidate: ((owner: number, token: number) => void) | undefined;
    if (abi.version === 5 || abi.version >= 6 && abi.resourceTransfer) {
      const memory = instance.exports["blot:memory"];
      if (!(memory instanceof WebAssembly.Memory)) {
        throw new GuestError(
          "invalid_abi",
          "Resource transfer requires owned memory",
        );
      }
      invalidate = (owner, token) => {
        if (
          owner < 32 || owner % 4 !== 0 || owner > memory.buffer.byteLength - 8
        ) throw new GuestError("invalid_abi", "Invalid resource owner address");
        const words = new Uint32Array(memory.buffer);
        const slot = owner / 4;
        // ABI 5's owning box is eight bytes after the 32-byte counted header.
        // A live weak edge must still name this exact registration, not a
        // recycled allocation or a host-provided scalar that resembles a pointer.
        if (
          words[slot - 7] !== 8 || (words[slot - 6] & 3092) !== 2052 ||
          words[slot - 4] === 0 || words[slot + 1] !== token
        ) {
          throw new GuestError(
            "invalid_abi",
            "Resource owner identity changed",
          );
        }
        words[slot + 1] = 0;
      };
    }
    let resourceBindings: ResourceBindings | undefined;
    if (bindings) {
      resourceBindings = {
        capture: () => active?.binding ?? 0,
        retain: (id) => {
          const binding = bindings!.get(id);
          if (!binding) {
            throw new GuestError("stale_capability", "Missing cleanup binding");
          }
          binding.refs++;
        },
        release: (id) => {
          const binding = bindings!.get(id);
          if (!binding || binding.refs === 0) {
            throw new GuestError(
              "stale_capability",
              "Cleanup binding is not owned",
            );
          }
          binding.refs--;
        },
      };
    }
    const adapters = resourceAdapters(instance, count).map((adapter) => ({
      drop: adapter.drop,
      cleanup: (payload: number, callable: number, provider: number) => {
        const invoke = () => adapter.cleanup(payload, callable, provider);
        if (tasks) tasks.cleanup(invoke);
        else invoke();
      },
    }));
    const tokens = new ResourceTokens();
    makeTaskJournal = () =>
      new ResourceJournal(adapters, invalidate, resourceBindings, tokens);
    rootResources = makeTaskJournal();
    resources = rootResources;
  }

  let ownership: { enter(): void; leave(outcome: number): void } | undefined;
  if (abi.version >= 3 && abi.version <= 7) {
    const enter = instance.exports["blot:ownership_enter"];
    const leave = instance.exports["blot:ownership_leave"];
    if (typeof enter !== "function" || typeof leave !== "function") {
      throw new GuestError("invalid_abi", "Missing ownership exports");
    }
    // The Wasm linker checks exact export signatures without invoking them.
    const validator = new WebAssembly.Module(
      new Uint8Array([
        0,
        97,
        115,
        109,
        1,
        0,
        0,
        0,
        1,
        8,
        2,
        96,
        0,
        0,
        96,
        1,
        127,
        0,
        2,
        13,
        2,
        1,
        111,
        1,
        101,
        0,
        0,
        1,
        111,
        1,
        108,
        0,
        1,
      ]),
    );
    try {
      new WebAssembly.Instance(validator, { o: { e: enter, l: leave } });
    } catch (cause) {
      throw new GuestError(
        "invalid_abi",
        "Invalid ownership export signatures",
        { cause },
      );
    }
    ownership = {
      enter: enter as () => void,
      leave: leave as (outcome: number) => void,
    };
  }
  if (abi.taskDescriptorCount !== undefined) {
    try {
      tasks = new TaskGuest(
        instance.exports,
        abi.taskDescriptorCount,
        makeTaskJournal!,
        (journal) => {
          resources = journal;
        },
        ownership!,
        options.asynchronous ? requireAsync().promising : undefined,
      );
    } catch (cause) {
      throw new GuestError("invalid_abi", "Invalid task adapter signatures", {
        cause,
      });
    }
  }
  let entered = false;
  const memory = instance.exports["blot:memory"];
  const allocate = instance.exports["blot:allocate"];
  const reset = instance.exports["blot:reset"];
  const profiling =
    WebAssembly.Module.customSections(module, "blot:memory-profile").length ===
      1;
  if (
    memory !== undefined &&
    (allocate !== undefined || reset !== undefined ||
      (abi.taskDescriptorCount === undefined && !profiling))
  ) {
    if (
      !(memory instanceof WebAssembly.Memory) ||
      typeof allocate !== "function" || typeof reset !== "function"
    ) {
      throw new GuestError("invalid_abi", "Missing array arena exports");
    }
    arena = { memory, allocate, reset };
  }

  const valueTypes: readonly ValueType[] = [
    ...scalarTypes,
    "Array U32",
    "Array F32",
  ];
  function createCapability<P extends ValueType, R extends ValueType>(
    definition: AsyncHostCallback<P, R>,
    asynchronous: boolean,
    cleanup?: HostCleanup<P>,
  ): HostCapability {
    idle();
    if (typeof definition !== "object" || definition === null) {
      throw new GuestError(
        "invalid_capability",
        "Expected a callback definition",
      );
    }
    const { parameter, result, call, concurrent } = definition;
    if (
      !valueTypes.includes(parameter) || !valueTypes.includes(result) ||
      typeof call !== "function" ||
      (concurrent !== undefined && concurrent !== true)
    ) {
      throw new GuestError(
        "invalid_capability",
        "A capability needs supported value types and a callable",
      );
    }
    let kind: CallbackType["kind"] = "callback";
    let maxCalls: number | undefined;
    if (cleanup) {
      const maxSteps = cleanup.maxSteps;
      maxCalls = cleanup.maxCalls;
      if (
        result !== "Unit" || !Number.isSafeInteger(maxSteps) ||
        maxSteps <= 0 || maxSteps > 65_536 ||
        !Number.isSafeInteger(maxCalls) || maxCalls <= 0 ||
        maxCalls > 65_536
      ) {
        throw new GuestError(
          "invalid_capability",
          "Cleanup needs finite positive maxSteps and maxCalls up to 65536 and Unit result",
        );
      }
      kind = "cleanup";
    }
    const selected: CallbackType = { kind, parameter, result };
    if (concurrent) Object.assign(selected, { concurrent: true });
    const signature = Object.freeze(selected);
    const capability: HostCapability = Object.freeze({
      [capabilityBrand]: true as const,
      parameter,
      result,
    });
    capabilityOwners.set(capability, {
      lifetime,
      signature,
      asynchronous,
      maxCalls,
    });
    callbacks.set(capability, (value) => call(value as ValueOf<P>));
    return capability;
  }

  let ownerHooks: {
    release: (id: number) => void;
    token: (id: number, schema: number, kind: number) => number;
  } | undefined;
  let liveOwners: Map<number, PublicOwnerState> | undefined;
  let pendingOwner: PublicOwnerState | undefined;
  if (abi.publicOwners) {
    const release = instance.exports["blot:owner_release"];
    const token = instance.exports["blot:owner_token"];
    if (typeof release !== "function" || typeof token !== "function") {
      throw new GuestError("invalid_abi", "Missing public owner hooks");
    }
    const types: number[] = [2, 96, 1, 127, 0, 96, 3, 127, 127, 127, 1, 127];
    const imported: Record<string, WebAssembly.ImportValue> = {
      r: release,
      t: token,
    };
    try {
      new WebAssembly.Instance(
        resourceModule([types, [
          2,
          ...resourceName("o"),
          ...resourceName("r"),
          0,
          0,
          ...resourceName("o"),
          ...resourceName("t"),
          0,
          1,
        ]]),
        { o: imported },
      );
    } catch (cause) {
      throw new GuestError(
        "invalid_abi",
        "Invalid public owner hook signatures",
        { cause },
      );
    }
    // Validate every public owner entry against its exact physical signature.
    for (const fn of abi.functions) {
      const ownerInput = typeof fn.parameter !== "string" &&
        fn.parameter.kind === "owner";
      if (!ownerInput && typeof fn.result === "string") continue;
      let parameter = 127;
      if (typeof fn.parameter === "string") {
        if (fn.parameter === "F32") parameter = 125;
      } else if (fn.parameter.kind === "owner") {
        if (fn.parameter.fresh === "F32") parameter = 125;
      } else parameter = 111;
      let result = 127;
      if (fn.result === "F32") result = 125;
      const entries: [string, number][] = [[fn.name, parameter]];
      if (ownerInput && (fn.parameter as OwnerType).fresh !== undefined) {
        entries.push([`blot:owner_call/${fn.name}`, 127]);
      }
      for (const [name, argument] of entries) {
        try {
          new WebAssembly.Instance(
            resourceModule([
              [1, 96, 1, argument, 1, result],
              [1, ...resourceName("o"), ...resourceName("f"), 0, 0],
            ]),
            { o: { f: instance.exports[name] } },
          );
        } catch (cause) {
          throw new GuestError(
            "invalid_abi",
            `Invalid public owner entry signature ${name}`,
            { cause },
          );
        }
      }
    }
    ownerHooks = {
      release: release as (id: number) => void,
      token: token as (id: number, schema: number, kind: number) => number,
    };
    liveOwners = new Map();
  }
  function checkedOwner(value: unknown): PublicOwnerState {
    const state = typeof value === "object" && value !== null
      ? publicOwnerStates.get(value)
      : undefined;
    if (!state) {
      throw new GuestError("invalid_owner", "Expected a guest owner handle");
    }
    if (state.lifetime.disposed) {
      throw new GuestError("stale_owner", "Owner belongs to a disposed guest");
    }
    if (state.lifetime !== lifetime) {
      throw new GuestError("foreign_owner", "Owner belongs to another guest");
    }
    if (!state.live) {
      throw new GuestError("use_after_move", "Owner has already been consumed");
    }
    return state;
  }
  function publicResult(
    type: ValueType | OwnerType,
    value: unknown,
  ): GuestValue | GuestOwner {
    if (typeof type === "string") return fromWasm(type, value);
    if (
      !ownerHooks || !liveOwners || typeof value !== "number" ||
      !Number.isInteger(value) || value < -2147483648 || value > 4294967295
    ) throw new GuestError("invalid_abi", "Invalid public owner result");
    const token = value >>> 0;
    if (token === 0 || liveOwners.has(token)) {
      throw new GuestError(
        "invalid_owner",
        "Owner result is not a fresh lease",
      );
    }
    let kind = 1;
    if (type.usage === "shared") kind = 2;
    try {
      const resource = ownerHooks.token(token, type.schema, kind) >>> 0;
      const handle: GuestOwner = Object.freeze({
        [ownerBrand]: true as const,
        usage: type.usage,
      });
      const state: PublicOwnerState = {
        lifetime,
        schema: type.schema,
        usage: type.usage,
        token,
        live: true,
      };
      if (resource !== 0) {
        if (!resources) {
          throw new GuestError(
            "invalid_abi",
            "Owner resource has no cleanup journal",
          );
        }
        resources.promote(resource);
      }
      publicOwnerStates.set(handle, state);
      liveOwners.set(token, state);
      pendingOwner = state;
      return handle;
    } catch (cause) {
      try {
        ownerHooks.release(token);
      } catch { /* Preserve publication failure. */ }
      liveOwners.delete(token);
      throw cause;
    }
  }
  let consumedOnce: Set<string> | undefined;
  if (abi.functions.some((fn) => fn.multiplicity === "once")) {
    consumedOnce = new Set<string>();
  }
  function begin(
    name: string,
    argument: unknown,
    asynchronous: boolean,
  ): { fn: GuestFunction; value: unknown; exported: CallableFunction } {
    idle();
    const fn = functions.get(name);
    if (!fn) {
      throw new GuestError(
        "unknown_export",
        `Unknown function export ${name}`,
      );
    }
    if (fn.multiplicity === "once" && consumedOnce!.has(name)) {
      throw new GuestError("once_reused", `${name} has already been invoked`);
    }
    let value: number | object;
    let exportedName = name;
    let movedOwner: PublicOwnerState | undefined;
    let argumentType: ValueType | undefined;
    if (typeof fn.parameter === "string") {
      value = isArrayType(fn.parameter) ? 0 : scalarToWasm(
        fn.parameter,
        argument,
        "invalid_argument",
        `${name} argument`,
      );
    } else if (fn.parameter.kind === "owner") {
      const state = typeof argument === "object" && argument !== null
        ? publicOwnerStates.get(argument)
        : undefined;
      if (state) {
        const owned = checkedOwner(argument);
        if (
          owned.schema !== fn.parameter.schema ||
          owned.usage !== fn.parameter.usage
        ) {
          throw new GuestError(
            "owner_type",
            "Owner does not match the entry's exact type",
          );
        }
        value = owned.token;
        if (fn.parameter.fresh !== undefined) {
          exportedName = `blot:owner_call/${name}`;
        }
        if (owned.usage === "unique") movedOwner = owned;
      } else {
        if (fn.parameter.fresh === undefined) {
          throw new GuestError(
            "invalid_owner",
            "Entry requires an existing owner handle",
          );
        }
        argumentType = fn.parameter.fresh;
        value = 0;
        if (!isArrayType(argumentType)) {
          value = scalarToWasm(
            argumentType,
            argument,
            "invalid_argument",
            `${name} argument`,
          );
        }
      }
    } else {
      const owner = typeof argument === "object" && argument !== null
        ? capabilityOwners.get(argument)
        : undefined;
      if (!owner) {
        throw new GuestError(
          "invalid_capability",
          `${name} requires a capability created by guest.capability()`,
        );
      }
      if (owner.lifetime.disposed) {
        throw new GuestError(
          "stale_capability",
          `${name} received a disposed instance's capability`,
        );
      }
      if (owner.lifetime !== lifetime) {
        throw new GuestError(
          "foreign_capability",
          `${name} received another instance's capability`,
        );
      }
      if (
        owner.signature.kind !== fn.parameter.kind ||
        fn.parameter.concurrent === true &&
          owner.signature.concurrent !== true ||
        owner.signature.dataSchema !== fn.parameter.dataSchema ||
        owner.signature.parameter !== fn.parameter.parameter ||
        owner.signature.result !== fn.parameter.result
      ) {
        throw new GuestError(
          "capability_signature",
          `${name} requires ${fn.parameter.parameter} -> ${fn.parameter.result}`,
        );
      }
      if (owner.asynchronous && !asynchronous) {
        throw new GuestError(
          "async_host_call",
          `${name} requires callAsync() for this capability`,
        );
      }
      const invoke = callbacks.get(argument as object);
      if (!invoke) throw new Error("Live capability has no callback binding");
      value = Object.freeze({});
      active = {
        reference: value,
        signature: owner.signature,
        invoke,
        exportName: name,
        asynchronous: asynchronous && owner.asynchronous,
        maxCalls: owner.maxCalls,
        calls: 0,
      };
    }
    pendingOwner = undefined;
    epoch++;
    running = true;
    try {
      entered = ownership !== undefined;
      ownership?.enter();
      resources?.begin();
      if (rootResources) tasks?.begin(rootResources, asynchronous);
      arena?.reset(0);
      if (typeof fn.parameter === "string" && isArrayType(fn.parameter)) {
        if (!arena) throw new Error("Validated array export has no arena");
        value = arrayToWasm(arena, fn.parameter, argument, name);
      }
      if (argumentType !== undefined && isArrayType(argumentType)) {
        if (!arena) throw new Error("Validated owner input has no arena");
        value = arrayToWasm(arena, argumentType, argument, name);
      }
      const exported = instance.exports[exportedName];
      if (typeof exported !== "function") {
        throw new Error("Validated function export disappeared");
      }
      if (fn.multiplicity === "once") consumedOnce!.add(name);
      if (movedOwner) {
        movedOwner.live = false;
        liveOwners!.delete(movedOwner.token);
      }
      return { fn, value, exported };
    } catch (cause) {
      finish(1, true);
      throw cause;
    }
  }
  function finish(outcome: number, priorFailure = false): void {
    if (rootResources) resources = rootResources;
    let failed = false;
    let failure: unknown;
    try {
      try {
        resources?.finish();
      } catch (cause) {
        failed = true;
        failure = cause;
      }
      try {
        if (entered) {
          ownership!.leave(outcome);
          entered = false;
        }
      } catch (cause) {
        if (!failed) {
          failed = true;
          failure = cause;
        }
      }
      try {
        arena?.reset(0);
      } catch (cause) {
        if (!failed) {
          failed = true;
          failure = cause;
        }
      }
    } finally {
      if (bindings) {
        for (const [id, binding] of bindings) {
          if (binding.refs === 0) bindings!.delete(id);
        }
      }
      active = undefined;
      running = false;
    }
    if (failed && pendingOwner) {
      const owner = pendingOwner;
      owner.live = false;
      liveOwners!.delete(owner.token);
      pendingOwner = undefined;
      try {
        epoch++;
        running = true;
        entered = ownership !== undefined;
        ownership?.enter();
        resources?.begin();
        ownerHooks!.release(owner.token);
      } catch {
        /* Preserve the earlier invocation failure. */
      } finally {
        finish(1, true);
      }
    }
    pendingOwner = undefined;
    if (failed && !priorFailure) throw failure;
  }

  return {
    abi,
    memoryBytes: () => {
      if (memory instanceof WebAssembly.Memory) return memory.buffer.byteLength;
      return 0;
    },
    cleanupDataType(name) {
      idle();
      const parameter = functions.get(name)?.parameter;
      if (
        typeof parameter !== "object" || parameter.kind !== "cleanup" ||
        parameter.dataSchema === undefined || !dataSchemas
      ) {
        throw new GuestError(
          "capability_signature",
          "Export has no structured cleanup parameter",
        );
      }
      const root = dataSchemas.get(parameter.dataSchema)!;
      let description = root.tag as string;
      if (root.name !== "") description = root.name;
      const type: CleanupDataType = Object.freeze({
        [dataTypeBrand]: true as const,
        name: description,
      });
      dataTypeOwners.set(type, { lifetime, schema: parameter.dataSchema });
      return type;
    },
    cleanupDataCapability(definition) {
      idle();
      if (typeof definition !== "object" || definition === null) {
        throw new GuestError(
          "invalid_capability",
          "Expected structured cleanup definition",
        );
      }
      const { type, maxSteps, maxCalls, call } = definition;
      let owner: { lifetime: Lifetime; schema: number } | undefined;
      if (typeof type === "object" && type !== null) {
        owner = dataTypeOwners.get(type);
      }
      if (
        !owner || owner.lifetime !== lifetime || owner.lifetime.disposed ||
        typeof call !== "function"
      ) {
        throw new GuestError(
          "invalid_capability",
          "Cleanup data type belongs to another lifetime",
        );
      }
      const capability = createCapability(
        {
          parameter: "U32",
          result: "Unit",
          call: () => null,
        },
        false,
        {
          parameter: "U32",
          result: "Unit",
          call: () => null,
          maxSteps,
          maxCalls,
        },
      );
      const state = capabilityOwners.get(capability)!;
      capabilityOwners.set(capability, {
        ...state,
        signature: Object.freeze({
          kind: "cleanup",
          parameter: "U32",
          result: "Unit",
          dataSchema: owner.schema,
        }),
      });
      callbacks.set(capability, (value) => call(value));
      return capability;
    },
    capability: (definition) => createCapability(definition, false),
    cleanupCapability: (definition) =>
      createCapability(definition, false, definition),
    capabilityAsync: (definition) => {
      requireAsync();
      if (!options.asynchronous) {
        throw new GuestError(
          "unsupported_async",
          "Create the guest with { asynchronous: true } to bind async capabilities",
        );
      }
      return createCapability(definition, true);
    },
    call(name, argument) {
      if (options.asynchronous) {
        throw new GuestError(
          "async_host_call",
          "An asynchronous guest requires callAsync()",
        );
      }
      const { fn, value, exported } = begin(name, argument, false);
      let outcome = 1;
      try {
        const result = publicResult(fn.result, exported(value));
        outcome = 0;
        return result;
      } finally {
        try {
          const completion = tasks?.finish(outcome !== 0);
          if (completion instanceof Promise) {
            throw new GuestError(
              "async_host_call",
              "Synchronous task cleanup suspended",
            );
          }
        } finally {
          finish(outcome, outcome !== 0);
        }
      }
    },
    async callAsync(name, argument) {
      const integration = requireAsync();
      const { fn, value, exported } = begin(name, argument, true);
      let outcome = 1;
      try {
        const result = publicResult(
          fn.result,
          await integration.promising(exported)(value),
        );
        outcome = 0;
        return result;
      } finally {
        try {
          await tasks?.finish(outcome !== 0);
        } finally {
          finish(outcome, outcome !== 0);
        }
      }
    },
    read(name) {
      idle();
      const constant = constants.get(name);
      if (!constant) {
        throw new GuestError(
          "unknown_export",
          `Unknown constant export ${name}`,
        );
      }
      const exported = instance.exports[name];
      if (!(exported instanceof WebAssembly.Global)) {
        throw new Error("Validated constant export disappeared");
      }
      return scalarFromWasm(constant.type, exported.value);
    },
    releaseOwner(handle) {
      idle();
      const owner = checkedOwner(handle);
      pendingOwner = undefined;
      epoch++;
      running = true;
      let outcome = 1;
      try {
        entered = ownership !== undefined;
        ownership?.enter();
        resources?.begin();
        owner.live = false;
        liveOwners!.delete(owner.token);
        ownerHooks!.release(owner.token);
        outcome = 0;
      } finally {
        finish(outcome, outcome !== 0);
      }
    },
    dispose() {
      if (lifetime.disposed) return;
      idle();
      let failed = false;
      let failure: unknown;
      if (abi.publicOwners) {
        pendingOwner = undefined;
        epoch++;
        running = true;
        try {
          entered = ownership !== undefined;
          ownership?.enter();
          resources?.begin();
          resources?.dispose();
        } catch (cause) {
          failed = true;
          failure = cause;
        } finally {
          try {
            finish(0, failed);
          } catch (cause) {
            if (!failed) {
              failed = true;
              failure = cause;
            }
          }
        }
      }
      try {
        ownership?.leave(2);
        tasks?.dispose();
        if (ownership) arena?.reset(0);
      } catch (cause) {
        if (!failed) {
          failed = true;
          failure = cause;
        }
      } finally {
        lifetime.disposed = true;
        liveOwners?.clear();
        callbacks = new WeakMap();
        bindings?.clear();
      }
      if (failed) throw failure;
    },
  };
}
