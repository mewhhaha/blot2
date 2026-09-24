const scalarTypes = ["Unit", "U32", "Bool", "F32"] as const;
export type ScalarType = typeof scalarTypes[number];
export type ScalarValue<T extends ScalarType = ScalarType> = T extends "Unit"
  ? null
  : T extends "Bool" ? boolean
  : number;

export type ArrayType = "Array U32" | "Array F32";
export type ValueType = ScalarType | ArrayType;
export type GuestValue = ScalarValue | Uint32Array | Float32Array;

function isArrayType(type: ValueType): type is ArrayType {
  return type === "Array U32" || type === "Array F32";
}

export interface CallbackType {
  readonly kind: "callback";
  readonly parameter: ScalarType;
  readonly result: ScalarType;
}

export interface GuestFunction {
  readonly name: string;
  readonly parameter: ValueType | CallbackType;
  readonly result: ValueType;
}

export interface GuestConstant {
  readonly name: string;
  readonly type: ScalarType;
}

export interface GuestAbi {
  readonly version: 2;
  readonly functions: readonly GuestFunction[];
  readonly constants: readonly GuestConstant[];
}

const capabilityBrand = Symbol("HostCapability");
export interface HostCapability {
  readonly [capabilityBrand]: true;
  readonly parameter: ScalarType;
  readonly result: ScalarType;
}

export interface HostCallback<P extends ScalarType, R extends ScalarType> {
  readonly parameter: P;
  readonly result: R;
  readonly call: (value: ScalarValue<P>) => ScalarValue<R>;
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
  | "reentrant_call"
  | "disposed_guest"
  | "unknown_export";

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
  constructor(readonly bytes: Uint8Array) {}

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

  parameter(): ValueType | CallbackType {
    const tag = this.byte();
    return tag === 4
      ? Object.freeze({
        kind: "callback",
        parameter: this.scalar(),
        result: this.scalar(),
      })
      : this.value(tag);
  }

  end(): void {
    if (this.#offset !== this.bytes.length) {
      throw new GuestError("invalid_abi", "Trailing bytes in blot:abi section");
    }
  }
}

function importName(signature: CallbackType): string {
  return `call_${signature.parameter.toLowerCase()}_${signature.result.toLowerCase()}`;
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
  if (version !== 2) {
    throw new GuestError(
      "invalid_abi",
      `Unsupported guest ABI version ${version}`,
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
  const functionCount = reader.count();
  for (let index = 0; index < functionCount; index++) {
    const name = reader.name();
    declare(name, "function");
    const parameter = reader.parameter();
    if (typeof parameter !== "string") signatures.add(importName(parameter));
    functions.push(Object.freeze({ name, parameter, result: reader.value() }));
  }
  const constantCount = reader.count();
  for (let index = 0; index < constantCount; index++) {
    const name = reader.name();
    declare(name, "global");
    constants.push(Object.freeze({ name, type: reader.scalar() }));
  }
  reader.end();
  if (
    functions.some((fn) =>
      (typeof fn.parameter === "string" && isArrayType(fn.parameter)) ||
      isArrayType(fn.result)
    )
  ) {
    declare("blot:memory", "memory");
    declare("blot:allocate", "function");
    declare("blot:reset", "function");
  }
  const actualExports = WebAssembly.Module.exports(module);
  if (
    actualExports.length !== exports.size ||
    actualExports.some((entry) => exports.get(entry.name) !== entry.kind)
  ) {
    throw new GuestError("invalid_abi", "Wasm exports differ from blot:abi");
  }
  for (const entry of WebAssembly.Module.imports(module)) {
    if (
      entry.module !== "blot:host/1" || entry.kind !== "function" ||
      !signatures.delete(entry.name)
    ) {
      throw new GuestError(
        "invalid_abi",
        `Unexpected Wasm import ${entry.module}/${entry.name}`,
      );
    }
  }
  if (signatures.size !== 0) {
    throw new GuestError("invalid_abi", "Missing generic callback import");
  }
  return Object.freeze({
    version,
    functions: Object.freeze(functions),
    constants: Object.freeze(constants),
  });
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
    typeof pointer !== "number" || !Number.isInteger(pointer) || pointer < 4 ||
    pointer % 4 !== 0 || pointer > arena.memory.buffer.byteLength - 4 ||
    length > (arena.memory.buffer.byteLength - pointer - 4) / 4
  ) {
    throw new GuestError("invalid_abi", "Array lies outside the guest arena");
  }
  return pointer;
}

function arrayToWasm(
  arena: GuestArena,
  type: ArrayType,
  argument: unknown,
  name: string,
): number {
  if (
    !(type === "Array U32"
      ? argument instanceof Uint32Array
      : argument instanceof Float32Array)
  ) {
    throw new GuestError(
      "invalid_argument",
      `${name} argument must be ${
        type === "Array U32" ? "Uint32Array" : "Float32Array"
      }`,
    );
  }
  const values = argument as Uint32Array | Float32Array;
  if (values.length >= 4_194_304) {
    throw new GuestError(
      "invalid_argument",
      `${name} array exceeds the 16 MiB arena`,
    );
  }
  const pointer = arrayRange(
    arena,
    arena.allocate((values.length + 1) * 4),
    values.length,
  );
  // Allocation may grow memory, so acquire a fresh view only afterwards.
  const view = new DataView(arena.memory.buffer);
  view.setUint32(pointer, values.length, true);
  for (let index = 0; index < values.length; index++) {
    const offset = pointer + 4 + index * 4;
    if (type === "Array U32") view.setUint32(offset, values[index], true);
    else view.setFloat32(offset, values[index], true);
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
  for (let index = 0; index < length; index++) {
    const offset = pointer + 4 + index * 4;
    values[index] = type === "Array U32"
      ? view.getUint32(offset, true)
      : view.getFloat32(offset, true);
  }
  return values;
}

interface Lifetime {
  disposed: boolean;
}
interface CapabilityOwner {
  readonly lifetime: Lifetime;
  readonly signature: CallbackType;
}
const capabilityOwners = new WeakMap<object, CapabilityOwner>();
type InvokeCallback = (value: ScalarValue) => unknown;

export interface Guest {
  readonly abi: GuestAbi;
  capability<P extends ScalarType, R extends ScalarType>(
    callback: HostCallback<P, R>,
  ): HostCapability;
  call(name: string, argument: unknown): GuestValue;
  read(name: string): ScalarValue;
  dispose(): void;
}

/** Synchronous, invocation-scoped ABI. No instance, memory, or handles escape. */
export async function instantiateGuest(
  bytes: Uint8Array<ArrayBuffer> | WebAssembly.Module,
): Promise<Guest> {
  const module = bytes instanceof WebAssembly.Module
    ? bytes
    : await WebAssembly.compile(bytes);
  const abi = readGuestAbi(module);
  const functions = new Map(abi.functions.map((fn) => [fn.name, fn]));
  const constants = new Map(
    abi.constants.map((constant) => [constant.name, constant]),
  );
  const lifetime: Lifetime = { disposed: false };
  let callbacks = new WeakMap<object, InvokeCallback>();
  let active: {
    readonly reference: object;
    readonly signature: CallbackType;
    readonly invoke: InvokeCallback;
    readonly exportName: string;
  } | undefined;
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

  const imports: Record<string, (reference: unknown, value: number) => number> =
    {};
  for (const fn of abi.functions) {
    if (typeof fn.parameter === "string") continue;
    const signature = fn.parameter;
    imports[importName(signature)] = (reference, value) => {
      const invocation = active;
      if (!invocation || reference !== invocation.reference) {
        throw new GuestError(
          "stale_capability",
          "Host call has no active capability reference",
        );
      }
      if (
        signature.parameter !== invocation.signature.parameter ||
        signature.result !== invocation.signature.result
      ) {
        throw new GuestError(
          "capability_signature",
          "Host call signature does not match its capability",
        );
      }
      const argument = scalarFromWasm(signature.parameter, value);
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
        const failure = new GuestError(
          "async_host_call",
          `Host callback returned a Promise/thenable during ${invocation.exportName}; ABI 2 is synchronous`,
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
      return scalarToWasm(
        signature.result,
        result,
        "host_result",
        `Host callback result during ${invocation.exportName}`,
      );
    };
  }
  const instance = await WebAssembly.instantiate(module, {
    "blot:host/1": imports,
  });

  const memory = instance.exports["blot:memory"];
  const allocate = instance.exports["blot:allocate"];
  const reset = instance.exports["blot:reset"];
  let arena: GuestArena | undefined;
  if (memory !== undefined) {
    if (
      !(memory instanceof WebAssembly.Memory) ||
      typeof allocate !== "function" || typeof reset !== "function"
    ) {
      throw new GuestError("invalid_abi", "Missing array arena exports");
    }
    arena = { memory, allocate, reset };
  }

  return {
    abi,
    capability<P extends ScalarType, R extends ScalarType>(
      definition: HostCallback<P, R>,
    ): HostCapability {
      idle();
      if (typeof definition !== "object" || definition === null) {
        throw new GuestError(
          "invalid_capability",
          "Expected a callback definition",
        );
      }
      const { parameter, result, call } = definition;
      if (
        !scalarTypes.includes(parameter) || !scalarTypes.includes(result) ||
        typeof call !== "function"
      ) {
        throw new GuestError(
          "invalid_capability",
          "A capability needs scalar parameter/result types and a callable",
        );
      }
      const signature: CallbackType = Object.freeze({
        kind: "callback",
        parameter,
        result,
      });
      const capability: HostCapability = Object.freeze({
        [capabilityBrand]: true as const,
        parameter,
        result,
      });
      capabilityOwners.set(capability, { lifetime, signature });
      callbacks.set(capability, (value) => call(value as ScalarValue<P>));
      return capability;
    },
    call(name, argument) {
      idle();
      const fn = functions.get(name);
      if (!fn) {
        throw new GuestError(
          "unknown_export",
          `Unknown function export ${name}`,
        );
      }
      let value: number | object;
      if (typeof fn.parameter === "string") {
        value = isArrayType(fn.parameter) ? 0 : scalarToWasm(
          fn.parameter,
          argument,
          "invalid_argument",
          `${name} argument`,
        );
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
          owner.signature.parameter !== fn.parameter.parameter ||
          owner.signature.result !== fn.parameter.result
        ) {
          throw new GuestError(
            "capability_signature",
            `${name} requires ${fn.parameter.parameter} -> ${fn.parameter.result}`,
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
        };
      }
      running = true;
      try {
        arena?.reset(0);
        if (typeof fn.parameter === "string" && isArrayType(fn.parameter)) {
          if (!arena) throw new Error("Validated array export has no arena");
          value = arrayToWasm(arena, fn.parameter, argument, name);
        }
        const exported = instance.exports[name];
        if (typeof exported !== "function") {
          throw new Error("Validated function export disappeared");
        }
        const result = exported(value);
        if (!isArrayType(fn.result)) return scalarFromWasm(fn.result, result);
        if (!arena) throw new Error("Validated array export has no arena");
        return arrayFromWasm(arena, fn.result, result);
      } finally {
        try {
          arena?.reset(0);
        } finally {
          active = undefined;
          running = false;
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
    dispose() {
      if (lifetime.disposed) return;
      idle();
      lifetime.disposed = true;
      callbacks = new WeakMap();
    },
  };
}
