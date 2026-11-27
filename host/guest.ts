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

/** Default logical transport packet ceiling in bytes (2 MiB). */
export const DEFAULT_TRANSPORT_BUDGET = 2_097_152;
/** `blot:kernels` flag bit 0: kernel has a prepared context (`prepare`). */
export const KERNEL_FLAG_HAS_CONTEXT = 1 << 0;
/** `blot:kernels` flag bit 1: kernel emits variable-length `[len, words...]` output. */
export const KERNEL_FLAG_VARIABLE_OUTPUT = 1 << 1;
/** Page-0 byte offset of the zero-export `arena_oom_flag` (`u32`). */
export const ARENA_OOM_OFFSET = 640;
/** Page-0 byte offset of the 1-based `trap_site_id` (`u32 LE`) for `blot:traps`. */
export const TRAP_SITE_OFFSET = 772;

export type TrapKind = "panic" | "bounds" | "unreachable";

export interface TrapMetadataEntry {
  readonly kind: TrapKind;
  readonly unit: number;
  readonly start: number;
  readonly end: number;
  readonly message: string;
}

export interface GuestTrapInfo extends TrapMetadataEntry {
  readonly id: number;
  readonly formatted: string;
}

// Captured intrinsics for side-effect-free private byte copying.
const TypedArrayProto = Object.getPrototypeOf(Uint8Array.prototype);
const TypedArrayPrototypeIndexOf = TypedArrayProto.indexOf as (
  searchElement: number,
  fromIndex?: number,
) => number;
const TypedArrayPrototypeBuffer = Object.getOwnPropertyDescriptor(
  TypedArrayProto,
  "buffer",
)!.get as () => ArrayBufferLike;
const TypedArrayPrototypeByteOffset = Object.getOwnPropertyDescriptor(
  TypedArrayProto,
  "byteOffset",
)!.get as () => number;
const TypedArrayPrototypeByteLength = Object.getOwnPropertyDescriptor(
  TypedArrayProto,
  "byteLength",
)!.get as () => number;
const DataViewPrototypeBuffer = Object.getOwnPropertyDescriptor(
  DataView.prototype,
  "buffer",
)!.get as () => ArrayBufferLike;
const DataViewPrototypeByteOffset = Object.getOwnPropertyDescriptor(
  DataView.prototype,
  "byteOffset",
)!.get as () => number;
const DataViewPrototypeByteLength = Object.getOwnPropertyDescriptor(
  DataView.prototype,
  "byteLength",
)!.get as () => number;
const ArrayBufferPrototypeByteLength = Object.getOwnPropertyDescriptor(
  ArrayBuffer.prototype,
  "byteLength",
)!.get as () => number;
const Uint8ArrayPrototypeSet = Uint8Array.prototype.set;

/**
 * Copy caller-provided bytes into a brand-new private unshared `Uint8Array`.
 * Uses captured ECMAScript primordials:
 * - O(1) `ValidateTypedArray` rejects detached AND shrunk out-of-bounds
 *   resizable `ArrayBuffer` views with `TypeError`.
 * - `ArrayBuffer.prototype.byteLength` getter rejects `SharedArrayBuffer`
 *   views with `TypeError`.
 * - Avoids caller-overridable `.slice()`, `Symbol.species`, and `Symbol.iterator`.
 */
export function copyPrivateBytes(
  view: ArrayBufferView,
): Uint8Array<ArrayBuffer> {
  if (!ArrayBuffer.isView(view)) {
    throw new TypeError(
      "Expected an ArrayBufferView backed by an unshared ArrayBuffer",
    );
  }
  let buf: ArrayBufferLike;
  let offset: number;
  let byteLen: number;
  if (view instanceof DataView) {
    buf = Reflect.apply(DataViewPrototypeBuffer, view, []);
    offset = Reflect.apply(DataViewPrototypeByteOffset, view, []);
    byteLen = Reflect.apply(DataViewPrototypeByteLength, view, []);
  } else {
    // O(1) ECMAScript ValidateTypedArray check (rejects detached & OOB RAB).
    Reflect.apply(TypedArrayPrototypeIndexOf, view, [0, Infinity]);
    buf = Reflect.apply(TypedArrayPrototypeBuffer, view, []);
    offset = Reflect.apply(TypedArrayPrototypeByteOffset, view, []);
    byteLen = Reflect.apply(TypedArrayPrototypeByteLength, view, []);
  }
  // Reject SharedArrayBuffer (and any non-ArrayBuffer) using primordial getter.
  const totalBufBytes = Reflect.apply(ArrayBufferPrototypeByteLength, buf, []);
  if (offset < 0 || byteLen < 0 || offset + byteLen > totalBufBytes) {
    throw new TypeError("ArrayBufferView lies outside its backing ArrayBuffer");
  }
  const out = new Uint8Array(new ArrayBuffer(byteLen));
  if (byteLen > 0) {
    Reflect.apply(Uint8ArrayPrototypeSet, out, [
      new Uint8Array(buf as ArrayBuffer, offset, byteLen),
    ]);
  }
  return out;
}

export type WireSchemaKind = "Unit" | "FlatFixed" | "VarU32" | "VarF32";

export interface WireSchema {
  readonly kind: WireSchemaKind;
  readonly wireTag: ValueType;
  readonly wireTagCode: number;
  readonly stride: number;
  readonly wordTags: readonly ScalarType[];
  readonly schemaHash: bigint;
}

export interface KernelManifest {
  readonly id: number;
  readonly name: string;
  readonly flags: number;
  readonly hasContext: boolean;
  readonly variableOutput: boolean;
  readonly inSchema: WireSchema;
  readonly outSchema: WireSchema;
  readonly ioSchemaHash: bigint;
  readonly implHash: bigint;
  readonly bindingHash: bigint;
  readonly ctxSchema?: WireSchema;
  readonly ctxExport?: string;
  readonly clearExport?: string;
}

export interface ProcessManifest {
  readonly name: string;
  readonly initExport: string;
  readonly stepExport: string;
  readonly configSchema: WireSchema;
  readonly cmdSchema: WireSchema;
  readonly replySchema: WireSchema;
}

export interface MemoryShape {
  readonly sectionPresent: boolean;
  readonly hasMemory: boolean;
  readonly memory64: boolean;
  readonly shared: boolean;
  readonly pageSizeLog2: number;
  readonly initialPages: number;
  readonly maximumPages?: number;
}

const scalarTypes = [
  "Unit",
  "U32",
  "Bool",
  "F32",
  "U8",
  "I32",
  "U64",
  "I64",
  "F64",
] as const;
export type ScalarType = typeof scalarTypes[number];
export type ScalarValue<T extends ScalarType = ScalarType> = T extends "Unit"
  ? null
  : T extends "Bool" ? boolean
  : T extends "U64" | "I64" ? bigint
  : number;

export type ArrayType =
  | "Array U32"
  | "Array F32"
  | "Array U8"
  | "Array I32"
  | "Array U64"
  | "Array I64"
  | "Array F64";
export type ValueType = ScalarType | ArrayType;
export type ValueOf<T extends ValueType> = T extends "Array U32" ? Uint32Array
  : T extends "Array F32" ? Float32Array
  : T extends "Array U8" ? Uint8Array
  : T extends "Array I32" ? Int32Array
  : T extends "Array U64" ? BigUint64Array
  : T extends "Array I64" ? BigInt64Array
  : T extends "Array F64" ? Float64Array
  : T extends ScalarType ? ScalarValue<T>
  : never;
export type GuestValue = ValueOf<ValueType>;

function isArrayType(type: ValueType | OwnerType): type is ArrayType {
  return typeof type === "string" && type.startsWith("Array ");
}

function scalarTypeFromTag(tag: number): ScalarType | undefined {
  switch (tag) {
    case 0:
      return "Unit";
    case 1:
      return "U32";
    case 2:
      return "Bool";
    case 3:
      return "F32";
    case 14:
      return "U8";
    case 15:
      return "I32";
    case 16:
      return "U64";
    case 17:
      return "I64";
    case 18:
      return "F64";
    default:
      return undefined;
  }
}

function arrayTypeFromTag(tag: number): ArrayType | undefined {
  switch (tag) {
    case 5:
      return "Array U32";
    case 6:
      return "Array F32";
    case 19:
      return "Array U8";
    case 20:
      return "Array I32";
    case 21:
      return "Array U64";
    case 22:
      return "Array I64";
    case 23:
      return "Array F64";
    default:
      return undefined;
  }
}

function arrayElementBytes(type: ArrayType): 1 | 4 | 8 {
  switch (type) {
    case "Array U8":
      return 1;
    case "Array U32":
    case "Array I32":
    case "Array F32":
      return 4;
    case "Array U64":
    case "Array I64":
    case "Array F64":
      return 8;
  }
}

function wasmValTypeCode(type: ValueType): number {
  switch (type) {
    case "F32":
      return 125;
    case "F64":
      return 124;
    case "U64":
    case "I64":
      return 126;
    default:
      return 127;
  }
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
  readonly invocationFinish?: true;
  readonly kernels?: readonly KernelManifest[];
  readonly processes?: readonly ProcessManifest[];
  readonly transportBudget?: number;
  readonly hostInternal?: readonly string[];
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

const guestTrapMap = new WeakMap<object, GuestTrapInfo>();

export function formatGuestTrap(entry: TrapMetadataEntry): string {
  switch (entry.kind) {
    case "panic":
      return entry.message ? `panic: "${entry.message}"` : "panic";
    case "bounds":
      return entry.message || "index out of bounds";
    case "unreachable":
      return entry.message ? `unreachable: ${entry.message}` : "unreachable";
  }
}

export function guestTrapOf(error: unknown): GuestTrapInfo | undefined {
  if (typeof error !== "object" || error === null) return undefined;
  return guestTrapMap.get(error);
}

/** Decode the optional `blot:traps` v1 custom section. */
export function readTrapMetadata(
  wasm: WebAssembly.Module | Uint8Array<ArrayBuffer>,
): readonly TrapMetadataEntry[] | undefined {
  const module = wasm instanceof WebAssembly.Module
    ? wasm
    : new WebAssembly.Module(wasm);
  const sections = WebAssembly.Module.customSections(module, "blot:traps");
  if (sections.length === 0) return undefined;
  if (sections.length > 1) {
    throw new GuestError("invalid_abi", "Duplicate blot:traps section");
  }
  const bytes = new Uint8Array(sections[0]);
  if (bytes.length < 5) {
    throw new GuestError("invalid_abi", "Truncated blot:traps section");
  }
  const version = bytes[0];
  if (version !== 1) {
    throw new GuestError(
      "invalid_abi",
      `Unsupported blot:traps version ${version}`,
    );
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const count = view.getUint32(1, true);
  let offset = 5;
  if (count > Math.floor((bytes.length - offset) / 17)) {
    throw new GuestError("invalid_abi", "Truncated blot:traps entries");
  }
  const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
  const entries: TrapMetadataEntry[] = [];
  for (let i = 0; i < count; i++) {
    if (bytes.length - offset < 17) {
      throw new GuestError("invalid_abi", "Truncated blot:traps entry");
    }
    const kindByte = bytes[offset++];
    let kind: TrapKind;
    if (kindByte === 1) kind = "panic";
    else if (kindByte === 2) kind = "bounds";
    else if (kindByte === 3) kind = "unreachable";
    else {
      throw new GuestError(
        "invalid_abi",
        `Invalid blot:traps kind ${kindByte}`,
      );
    }
    const unit = view.getUint32(offset, true);
    offset += 4;
    const start = view.getUint32(offset, true);
    offset += 4;
    const end = view.getUint32(offset, true);
    offset += 4;
    const messageLen = view.getUint32(offset, true);
    offset += 4;
    if (messageLen > bytes.length - offset) {
      throw new GuestError("invalid_abi", "Truncated blot:traps message");
    }
    const messageBytes = bytes.subarray(offset, offset + messageLen);
    offset += messageLen;
    let message: string;
    try {
      message = decoder.decode(messageBytes);
    } catch (cause) {
      throw new GuestError("invalid_abi", "Invalid UTF-8 in blot:traps", {
        cause,
      });
    }
    entries.push(Object.freeze({ kind, unit, start, end, message }));
  }
  if (offset !== bytes.length) {
    throw new GuestError("invalid_abi", "Trailing bytes in blot:traps section");
  }
  return Object.freeze(entries);
}

function enrichGuestTrap(
  error: unknown,
  trapTable: readonly TrapMetadataEntry[] | undefined,
  memory: WebAssembly.ExportValue | undefined,
): unknown {
  if (
    !(error instanceof WebAssembly.RuntimeError) ||
    !trapTable || trapTable.length === 0 ||
    !(memory instanceof WebAssembly.Memory) ||
    memory.buffer.byteLength < TRAP_SITE_OFFSET + 4
  ) {
    return error;
  }
  const trapId = new DataView(memory.buffer).getUint32(TRAP_SITE_OFFSET, true);
  if (trapId < 1 || trapId > trapTable.length) return error;
  const entry = trapTable[trapId - 1];
  const info: GuestTrapInfo = Object.freeze({
    ...entry,
    id: trapId,
    formatted: formatGuestTrap(entry),
  });
  const enriched = new WebAssembly.RuntimeError(
    `${info.formatted} (${error.message})`,
  );
  Object.defineProperty(enriched, "cause", {
    value: error,
    enumerable: false,
    writable: true,
    configurable: true,
  });
  if (error.stack !== undefined) {
    try {
      enriched.stack = error.stack;
    } catch {
      // Preserve default stack if non-writable.
    }
  }
  Object.defineProperty(enriched, "blotTrap", {
    value: info,
    enumerable: false,
    writable: false,
    configurable: false,
  });
  guestTrapMap.set(enriched, info);
  return enriched;
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
    const type = scalarTypeFromTag(tag);
    if (type === undefined) {
      throw new GuestError("invalid_abi", `Unknown scalar ABI tag ${tag}`);
    }
    return type;
  }

  value(tag = this.byte()): ValueType {
    return arrayTypeFromTag(tag) ?? this.scalar(tag);
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

  u64Le(): bigint {
    if (this.bytes.length - this.#offset < 8) {
      throw new GuestError("invalid_abi", "Truncated u64 in custom section");
    }
    const view = new DataView(
      this.bytes.buffer,
      this.bytes.byteOffset + this.#offset,
      8,
    );
    this.#offset += 8;
    return view.getBigUint64(0, true);
  }

  end(): void {
    if (this.#offset !== this.bytes.length) {
      throw new GuestError("invalid_abi", "Trailing bytes in blot:abi section");
    }
  }
}

const wireSchemaKinds: readonly WireSchemaKind[] = [
  "Unit",
  "FlatFixed",
  "VarU32",
  "VarF32",
];

function valueTypeFromTag(tag: number): ValueType {
  const type = arrayTypeFromTag(tag) ?? scalarTypeFromTag(tag);
  if (type === undefined) {
    throw new GuestError("invalid_abi", `Unknown value ABI tag ${tag}`);
  }
  return type;
}

function parseWireSchema(
  reader: AbiReader,
  transportBudget: number,
): WireSchema {
  const kindByte = reader.byte();
  const kind = wireSchemaKinds[kindByte];
  if (kind === undefined) {
    throw new GuestError(
      "invalid_abi",
      `Unknown wire schema kind ${kindByte}`,
    );
  }
  const wireTagCode = reader.byte();
  const wireTag = valueTypeFromTag(wireTagCode);
  const stride = reader.count();
  const wordTags: ScalarType[] = [];
  if (kind === "Unit") {
    if (wireTag !== "Unit" || stride !== 0) {
      throw new GuestError("invalid_abi", "Malformed Unit wire schema");
    }
  } else if (kind === "FlatFixed") {
    if (stride < 1 || stride * 4 + 4 > transportBudget) {
      throw new GuestError(
        "invalid_abi",
        `FlatFixed stride ${stride} exceeds transport budget ${transportBudget}`,
      );
    }
    for (let i = 0; i < stride; i++) {
      const tag = reader.scalar();
      if (tag !== "U32" && tag !== "Bool" && tag !== "F32") {
        throw new GuestError(
          "invalid_abi",
          `FlatFixed word_tag must be U32, Bool, or F32, got ${tag}`,
        );
      }
      wordTags.push(tag);
    }
    if (stride === 1) {
      if (wireTag !== wordTags[0] && !isArrayType(wireTag)) {
        throw new GuestError(
          "invalid_abi",
          `1-word FlatFixed wire_tag ${wireTag} incompatible with ${
            wordTags[0]
          }`,
        );
      }
    } else if (!isArrayType(wireTag)) {
      throw new GuestError(
        "invalid_abi",
        "Multi-word FlatFixed wire_tag must be an array",
      );
    }
  } else if (kind === "VarU32") {
    if (stride !== 0 || wireTag !== "Array U32") {
      throw new GuestError("invalid_abi", "Malformed VarU32 wire schema");
    }
  } else if (kind === "VarF32") {
    if (stride !== 0 || (wireTag !== "Array U32" && wireTag !== "Array F32")) {
      throw new GuestError("invalid_abi", "Malformed VarF32 wire schema");
    }
  }
  const schemaHash = reader.u64Le();
  return Object.freeze({
    kind,
    wireTag,
    wireTagCode,
    stride,
    wordTags: Object.freeze(wordTags),
    schemaHash,
  });
}

function parseKernelsSection(
  payload: Uint8Array,
  functionsByName: ReadonlyMap<string, GuestFunction>,
): { transportBudget: number; kernels: readonly KernelManifest[] } {
  const reader = new AbiReader(payload);
  const version = reader.count();
  if (version !== 1) {
    throw new GuestError(
      "invalid_abi",
      `Unsupported blot:kernels version ${version}`,
    );
  }
  const transportBudget = reader.count();
  if (transportBudget < 8 || transportBudget % 4 !== 0) {
    throw new GuestError(
      "invalid_abi",
      `Invalid blot:kernels transport_budget ${transportBudget}`,
    );
  }
  const count = reader.count();
  const kernels: KernelManifest[] = [];
  const seen = new Set<string>();
  for (let id = 0; id < count; id++) {
    const name = reader.name();
    if (seen.has(name)) {
      throw new GuestError("invalid_abi", `Duplicate kernel ${name}`);
    }
    seen.add(name);
    const flags = reader.byte();
    if ((flags & ~0x03) !== 0) {
      throw new GuestError(
        "invalid_abi",
        `Kernel ${name} has unknown flags 0x${flags.toString(16)}`,
      );
    }
    const hasContext = (flags & KERNEL_FLAG_HAS_CONTEXT) !== 0;
    const variableOutput = (flags & KERNEL_FLAG_VARIABLE_OUTPUT) !== 0;
    const inSchema = parseWireSchema(reader, transportBudget);
    if (inSchema.kind !== "FlatFixed" || !isArrayType(inSchema.wireTag)) {
      throw new GuestError(
        "invalid_abi",
        `Kernel ${name} input must be FlatFixed array wire`,
      );
    }
    const outSchema = parseWireSchema(reader, transportBudget);
    if (variableOutput) {
      if (
        (outSchema.kind !== "VarU32" && outSchema.kind !== "VarF32") ||
        outSchema.wireTag !== "Array U32"
      ) {
        throw new GuestError(
          "invalid_abi",
          `Variable-output kernel ${name} must have VarU32/VarF32 schema with Array U32 wire`,
        );
      }
    } else if (
      outSchema.kind !== "FlatFixed" || !isArrayType(outSchema.wireTag)
    ) {
      throw new GuestError(
        "invalid_abi",
        `Fixed-output kernel ${name} must have FlatFixed array wire`,
      );
    }
    const entry = functionsByName.get(name);
    if (
      !entry || entry.parameter !== inSchema.wireTag ||
      entry.result !== outSchema.wireTag
    ) {
      throw new GuestError(
        "invalid_abi",
        `Kernel ${name} signature mismatch against blot:abi`,
      );
    }
    const ioSchemaHash = reader.u64Le();
    const implHash = reader.u64Le();
    const bindingHash = reader.u64Le();
    let ctxSchema: WireSchema | undefined;
    let ctxExport: string | undefined;
    let clearExport: string | undefined;
    if (hasContext) {
      ctxSchema = parseWireSchema(reader, transportBudget);
      if (ctxSchema.kind === "Unit") {
        throw new GuestError(
          "invalid_abi",
          `Kernel ${name} context schema cannot be Unit`,
        );
      }
      ctxExport = reader.name();
      clearExport = reader.name();
      const ctxFn = functionsByName.get(ctxExport);
      if (
        !ctxFn || ctxFn.parameter !== ctxSchema.wireTag ||
        ctxFn.result !== "Unit"
      ) {
        throw new GuestError(
          "invalid_abi",
          `Kernel ${name} ctx_export ${ctxExport} signature mismatch`,
        );
      }
      const clearFn = functionsByName.get(clearExport);
      if (
        !clearFn || clearFn.parameter !== "Unit" || clearFn.result !== "Unit"
      ) {
        throw new GuestError(
          "invalid_abi",
          `Kernel ${name} clear_export ${clearExport} signature mismatch`,
        );
      }
    }
    kernels.push(Object.freeze({
      id,
      name,
      flags,
      hasContext,
      variableOutput,
      inSchema,
      outSchema,
      ioSchemaHash,
      implHash,
      bindingHash,
      ...(hasContext ? { ctxSchema, ctxExport, clearExport } : {}),
    }));
  }
  reader.end();
  return { transportBudget, kernels: Object.freeze(kernels) };
}

function parseProcessesSection(
  payload: Uint8Array,
  functionsByName: ReadonlyMap<string, GuestFunction>,
): { transportBudget: number; processes: readonly ProcessManifest[] } {
  const reader = new AbiReader(payload);
  const version = reader.count();
  if (version !== 1) {
    throw new GuestError(
      "invalid_abi",
      `Unsupported blot:processes version ${version}`,
    );
  }
  const transportBudget = reader.count();
  if (transportBudget < 8 || transportBudget % 4 !== 0) {
    throw new GuestError(
      "invalid_abi",
      `Invalid blot:processes transport_budget ${transportBudget}`,
    );
  }
  const count = reader.count();
  const processes: ProcessManifest[] = [];
  const seen = new Set<string>();
  for (let i = 0; i < count; i++) {
    const name = reader.name();
    if (seen.has(name)) {
      throw new GuestError("invalid_abi", `Duplicate process ${name}`);
    }
    seen.add(name);
    const initExport = reader.name();
    const stepExport = reader.name();
    const configSchema = parseWireSchema(reader, transportBudget);
    const cmdSchema = parseWireSchema(reader, transportBudget);
    const replySchema = parseWireSchema(reader, transportBudget);
    const initFn = functionsByName.get(initExport);
    if (
      !initFn || initFn.parameter !== configSchema.wireTag ||
      initFn.result !== "Unit"
    ) {
      throw new GuestError(
        "invalid_abi",
        `Process ${name} init_export ${initExport} signature mismatch`,
      );
    }
    const stepFn = functionsByName.get(stepExport);
    if (
      !stepFn || stepFn.parameter !== cmdSchema.wireTag ||
      stepFn.result !== replySchema.wireTag
    ) {
      throw new GuestError(
        "invalid_abi",
        `Process ${name} step_export ${stepExport} signature mismatch`,
      );
    }
    processes.push(Object.freeze({
      name,
      initExport,
      stepExport,
      configSchema,
      cmdSchema,
      replySchema,
    }));
  }
  reader.end();
  return { transportBudget, processes: Object.freeze(processes) };
}

function readUleb(bytes: Uint8Array, state: { at: number }): number {
  let result = 0;
  let shift = 0;
  for (let i = 0; i < 10; i++) {
    if (state.at >= bytes.length) {
      throw new GuestError("invalid_abi", "Truncated ULEB128 in Wasm module");
    }
    const byte = bytes[state.at++];
    result += (byte & 0x7f) * 2 ** shift;
    if ((byte & 0x80) === 0) return result;
    shift += 7;
  }
  throw new GuestError("invalid_abi", "ULEB128 overflow in Wasm module");
}

/**
 * Parse Wasm Section ID 5 (`MemorySection`) directly from raw Wasm bytes.
 * Handles 32-bit, shared (`0x02`), memory64 (`0x04`), and custom page size (`0x08`).
 */
export function readMemoryShape(bytes: Uint8Array): MemoryShape {
  if (
    bytes.length < 8 ||
    bytes[0] !== 0x00 || bytes[1] !== 0x61 ||
    bytes[2] !== 0x73 || bytes[3] !== 0x6d ||
    bytes[4] !== 0x01 || bytes[5] !== 0x00 ||
    bytes[6] !== 0x00 || bytes[7] !== 0x00
  ) {
    throw new GuestError("invalid_abi", "Invalid WebAssembly module header");
  }
  const state = { at: 8 };
  let memorySection: Uint8Array | undefined;
  while (state.at < bytes.length) {
    const id = bytes[state.at++];
    const size = readUleb(bytes, state);
    if (size < 0 || state.at + size > bytes.length) {
      throw new GuestError("invalid_abi", "Truncated Wasm section");
    }
    if (id === 5) {
      if (memorySection !== undefined) {
        throw new GuestError("invalid_abi", "Duplicate Wasm MemorySection");
      }
      memorySection = bytes.subarray(state.at, state.at + size);
    }
    state.at += size;
  }
  if (memorySection === undefined) {
    return Object.freeze({
      sectionPresent: false,
      hasMemory: false,
      memory64: false,
      shared: false,
      pageSizeLog2: 16,
      initialPages: 0,
    });
  }
  const ms = { at: 0 };
  const count = readUleb(memorySection, ms);
  if (count === 0) {
    if (ms.at !== memorySection.length) {
      throw new GuestError("invalid_abi", "Trailing bytes in MemorySection");
    }
    return Object.freeze({
      sectionPresent: true,
      hasMemory: false,
      memory64: false,
      shared: false,
      pageSizeLog2: 16,
      initialPages: 0,
    });
  }
  if (count > 1) {
    throw new GuestError(
      "invalid_abi",
      `Wasm module defines ${count} linear memories; at most 1 is permitted`,
    );
  }
  if (ms.at >= memorySection.length) {
    throw new GuestError("invalid_abi", "Truncated MemorySection entry");
  }
  const flags = memorySection[ms.at++];
  if ((flags & ~0x0f) !== 0) {
    throw new GuestError(
      "invalid_abi",
      `Unknown MemorySection flags 0x${flags.toString(16)}`,
    );
  }
  const hasMax = (flags & 0x01) !== 0;
  const shared = (flags & 0x02) !== 0;
  const memory64 = (flags & 0x04) !== 0;
  const hasPageSize = (flags & 0x08) !== 0;
  const initialPages = readUleb(memorySection, ms);
  const maximumPages = hasMax ? readUleb(memorySection, ms) : undefined;
  const pageSizeLog2 = hasPageSize ? readUleb(memorySection, ms) : 16;
  if (ms.at !== memorySection.length) {
    throw new GuestError("invalid_abi", "Trailing bytes in MemorySection");
  }
  return Object.freeze({
    sectionPresent: true,
    hasMemory: true,
    memory64,
    shared,
    pageSizeLog2,
    initialPages,
    ...(maximumPages !== undefined ? { maximumPages } : {}),
  });
}

export function validateMemoryShape(shape: MemoryShape): void {
  if (!shape.hasMemory) return;
  if (shape.shared) {
    throw new GuestError(
      "invalid_abi",
      "Shared Wasm linear memory is unsupported",
    );
  }
  if (shape.memory64) {
    throw new GuestError(
      "invalid_abi",
      "Memory64 Wasm linear memory is unsupported",
    );
  }
  if (shape.pageSizeLog2 !== 16) {
    throw new GuestError(
      "invalid_abi",
      `Unsupported Wasm page size 2^${shape.pageSizeLog2}; expected 64 KiB (2^16)`,
    );
  }
}

const compiledReceiptBrand = Symbol("CompiledModuleReceipt");

export interface CompiledModuleReceipt {
  readonly [compiledReceiptBrand]: true;
  readonly module: WebAssembly.Module;
  readonly abi: GuestAbi;
  readonly memoryShape: MemoryShape;
}

export interface ValidatedModuleMeta {
  readonly module: WebAssembly.Module;
  readonly snapshot: Uint8Array<ArrayBuffer>;
  readonly abi: GuestAbi;
  readonly memoryShape: MemoryShape;
}

const validatedModuleMetaMap = new WeakMap<
  WebAssembly.Module,
  ValidatedModuleMeta
>();
const validatedReceiptMetaMap = new WeakMap<object, ValidatedModuleMeta>();

/**
 * Copy raw Wasm bytes into an immutable private unshared snapshot, validate
 * its `MemoryShape` and ABI 8 manifest, and compile an unforgeable receipt
 * accepted by `KernelPool.open` and `Processes`.
 */
export function compileKernelModule(
  bytes: Uint8Array,
): CompiledModuleReceipt {
  const snapshot = copyPrivateBytes(bytes);
  const memoryShape = readMemoryShape(snapshot);
  validateMemoryShape(memoryShape);
  const module = new WebAssembly.Module(snapshot);
  const abi = readGuestAbi(module);
  const meta: ValidatedModuleMeta = Object.freeze({
    module,
    snapshot,
    abi,
    memoryShape,
  });
  validatedModuleMetaMap.set(module, meta);
  const receipt: CompiledModuleReceipt = Object.freeze({
    [compiledReceiptBrand]: true as const,
    module,
    abi,
    memoryShape,
  });
  validatedReceiptMetaMap.set(receipt, meta);
  return receipt;
}

/**
 * Resolve either raw Wasm `Uint8Array` bytes or an unforgeable
 * `CompiledModuleReceipt`. Arbitrary opaque `WebAssembly.Module` objects are
 * explicitly rejected so memory-shape validation can never be bypassed.
 */
export function resolveValidatedModule(
  source: Uint8Array | CompiledModuleReceipt,
): ValidatedModuleMeta {
  if (typeof source === "object" && source !== null) {
    const fromReceipt = validatedReceiptMetaMap.get(source);
    if (fromReceipt !== undefined) return fromReceipt;
  }
  if (source instanceof Uint8Array) {
    const receipt = compileKernelModule(source);
    return validatedReceiptMetaMap.get(receipt)!;
  }
  throw new TypeError(
    "Expected raw Wasm Uint8Array bytes or a CompiledModuleReceipt from compileKernelModule()",
  );
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
  const invocation = WebAssembly.Module.customSections(
    module,
    "blot:invocation",
  );
  if (invocation.length !== 0) {
    const versionBytes = new Uint8Array(invocation[0]);
    if (
      version !== 8 || invocation.length !== 1 ||
      versionBytes.length !== 1 || versionBytes[0] !== 1
    ) {
      throw new GuestError("invalid_abi", "Invalid invocation finish section");
    }
    declare("blot:finish_invocation", "function");
  }
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
  const trapsSections = WebAssembly.Module.customSections(
    module,
    "blot:traps",
  );
  if (trapsSections.length > 1) {
    throw new GuestError("invalid_abi", "Duplicate traps section");
  }
  if (
    trapsSections.length === 1 && !exports.has("blot:memory") &&
    actualExports.some((entry) =>
      entry.name === "blot:memory" && entry.kind === "memory"
    )
  ) {
    declare("blot:memory", "memory");
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
  const kernelsSections = WebAssembly.Module.customSections(
    module,
    "blot:kernels",
  );
  if (kernelsSections.length > 1) {
    throw new GuestError("invalid_abi", "Duplicate blot:kernels section");
  }
  if (kernelsSections.length === 1 && version !== 8) {
    throw new GuestError("invalid_abi", "blot:kernels requires ABI 8");
  }
  const processesSections = WebAssembly.Module.customSections(
    module,
    "blot:processes",
  );
  if (processesSections.length > 1) {
    throw new GuestError("invalid_abi", "Duplicate blot:processes section");
  }
  if (processesSections.length === 1 && version !== 8) {
    throw new GuestError("invalid_abi", "blot:processes requires ABI 8");
  }
  const functionsByName = new Map(functions.map((fn) => [fn.name, fn]));
  const hostInternal: string[] = [];
  let kernels: readonly KernelManifest[] | undefined;
  let processes: readonly ProcessManifest[] | undefined;
  let transportBudget: number | undefined;
  if (kernelsSections.length === 1) {
    const parsed = parseKernelsSection(
      new Uint8Array(kernelsSections[0]),
      functionsByName,
    );
    transportBudget = parsed.transportBudget;
    kernels = parsed.kernels;
    for (const kernel of kernels) {
      if (kernel.ctxExport !== undefined) hostInternal.push(kernel.ctxExport);
      if (kernel.clearExport !== undefined) {
        hostInternal.push(kernel.clearExport);
      }
    }
  }
  if (processesSections.length === 1) {
    const parsed = parseProcessesSection(
      new Uint8Array(processesSections[0]),
      functionsByName,
    );
    if (
      transportBudget !== undefined &&
      transportBudget !== parsed.transportBudget
    ) {
      throw new GuestError(
        "invalid_abi",
        `blot:kernels transport_budget (${transportBudget}) != blot:processes transport_budget (${parsed.transportBudget})`,
      );
    }
    transportBudget = parsed.transportBudget;
    processes = parsed.processes;
    for (const proc of processes) {
      hostInternal.push(proc.initExport);
      hostInternal.push(proc.stepExport);
    }
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
  if (invocation.length !== 0) {
    Object.assign(result, { invocationFinish: true });
  }
  if (kernels !== undefined) {
    Object.assign(result, { kernels });
  }
  if (processes !== undefined) {
    Object.assign(result, { processes });
  }
  if (transportBudget !== undefined) {
    Object.assign(result, { transportBudget });
  }
  if (hostInternal.length > 0) {
    Object.assign(result, { hostInternal: Object.freeze(hostInternal) });
  }
  if (dataSchemas) abiDataSchemas.set(result, dataSchemas);
  return Object.freeze(result);
}

function scalarToWasm(
  type: ScalarType,
  value: unknown,
  code: "invalid_argument" | "host_result",
  label: string,
): number | bigint {
  switch (type) {
    case "Unit":
      if (value === null) return 0;
      break;
    case "Bool":
      if (typeof value === "boolean") return value ? 1 : 0;
      break;
    case "U8":
      if (
        typeof value === "number" && Number.isInteger(value) && value >= 0 &&
        value <= 0xFF
      ) return value;
      break;
    case "U32":
      if (
        typeof value === "number" && Number.isInteger(value) && value >= 0 &&
        value <= 0xFFFFFFFF
      ) return value;
      break;
    case "I32":
      if (
        typeof value === "number" && Number.isInteger(value) &&
        value >= -0x80000000 && value <= 0x7FFFFFFF
      ) return value;
      break;
    case "U64":
      if (
        typeof value === "bigint" && value >= 0n &&
        value <= 0xFFFF_FFFF_FFFF_FFFFn
      ) return BigInt.asIntN(64, value);
      break;
    case "I64":
      if (
        typeof value === "bigint" && value >= -0x8000_0000_0000_0000n &&
        value <= 0x7FFF_FFFF_FFFF_FFFFn
      ) return value;
      break;
    case "F32":
      if (typeof value === "number") return Math.fround(value);
      break;
    case "F64":
      if (typeof value === "number") return value;
      break;
  }
  throw new GuestError(code, `${label} must be ${type}`);
}

function scalarFromWasm(type: ScalarType, value: unknown): ScalarValue {
  if (type === "U64" || type === "I64") {
    if (typeof value !== "bigint") {
      throw new GuestError("invalid_abi", `Wasm ${type} value is not a bigint`);
    }
    return type === "U64"
      ? BigInt.asUintN(64, value)
      : BigInt.asIntN(64, value);
  }
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
    case "U8":
      if (Number.isInteger(value) && value >= 0 && value <= 0xFF) return value;
      break;
    case "U32":
      if (
        Number.isInteger(value) && value >= -0x80000000 && value <= 0x7FFFFFFF
      ) {
        return value >>> 0;
      }
      break;
    case "I32":
      if (
        Number.isInteger(value) && value >= -0x80000000 && value <= 0x7FFFFFFF
      ) {
        return value | 0;
      }
      break;
    case "F32":
      return Math.fround(value);
    case "F64":
      return value;
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
  elemBytes: 1 | 4 | 8 = 4,
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
    length > (arena.memory.buffer.byteLength - address - 4) / elemBytes
  ) {
    throw new GuestError("invalid_abi", "Array lies outside the guest arena");
  }
  return address;
}

type GuestTypedArray =
  | Uint8Array
  | Uint32Array
  | Int32Array
  | Float32Array
  | BigUint64Array
  | BigInt64Array
  | Float64Array;

function arrayClassName(type: ArrayType): string {
  switch (type) {
    case "Array U8":
      return "Uint8Array";
    case "Array U32":
      return "Uint32Array";
    case "Array I32":
      return "Int32Array";
    case "Array F32":
      return "Float32Array";
    case "Array U64":
      return "BigUint64Array";
    case "Array I64":
      return "BigInt64Array";
    case "Array F64":
      return "Float64Array";
  }
}

function isMatchingTypedArray(
  type: ArrayType,
  value: unknown,
): value is GuestTypedArray {
  switch (type) {
    case "Array U8":
      return value instanceof Uint8Array;
    case "Array U32":
      return value instanceof Uint32Array;
    case "Array I32":
      return value instanceof Int32Array;
    case "Array F32":
      return value instanceof Float32Array;
    case "Array U64":
      return value instanceof BigUint64Array;
    case "Array I64":
      return value instanceof BigInt64Array;
    case "Array F64":
      return value instanceof Float64Array;
  }
}

function arrayToWasm(
  arena: GuestArena,
  type: ArrayType,
  argument: unknown,
  name: string,
  code: "invalid_argument" | "host_result" = "invalid_argument",
  batch?: NumericArrayCall,
): number {
  if (!isMatchingTypedArray(type, argument)) {
    throw new GuestError(
      code,
      `${name} argument must be ${arrayClassName(type)}`,
    );
  }
  const values = argument;
  const elemBytes = arrayElementBytes(type);
  const prefix = batch?.prefix;
  const prefixLength = prefix?.length ?? 0;
  const length = prefixLength + values.length;
  const payloadBytes = length * elemBytes;
  if (payloadBytes > 0xFFFF_FFF8) {
    throw new GuestError(
      code,
      `${name} array byte count exceeds the Wasm32 address range`,
    );
  }
  const allocBytes = payloadBytes + 4 + ((4 - (payloadBytes & 3)) & 3);
  const pointer = arrayRange(
    arena,
    arena.allocate(allocBytes),
    length,
    elemBytes,
  );
  // Allocation may grow memory, so acquire a fresh view only afterwards.
  const view = new DataView(arena.memory.buffer);
  view.setUint32(pointer, length, true);
  batch?.observeCopy?.("guestInput", payloadBytes);
  if (prefixLength && prefix) copyArrayWords(view, pointer + 4, prefix);
  const dataStart = pointer + 4 + prefixLength * 4;
  if (elemBytes === 1) {
    const bytes = values as Uint8Array;
    if (bytes.buffer instanceof ArrayBuffer) {
      new Uint8Array(view.buffer, dataStart, bytes.length).set(bytes);
    } else {
      for (let index = 0; index < bytes.length; index++) {
        view.setUint8(dataStart + index, bytes[index]);
      }
    }
  } else if (elemBytes === 4) {
    const words = values instanceof Uint32Array
      ? values
      : new Uint32Array(values.buffer, values.byteOffset, values.length);
    copyArrayWords(view, dataStart, words);
  } else {
    const words = values instanceof BigUint64Array
      ? values
      : new BigUint64Array(values.buffer, values.byteOffset, values.length);
    copyArrayWords64(view, dataStart, words);
  }
  return pointer;
}

function copyArrayWords(view: DataView, start: number, words: Uint32Array) {
  const { length, byteLength } = words;
  if (
    littleEndian && length > 32 && words.buffer instanceof ArrayBuffer
  ) {
    // Byte copies avoid boxing every element and preserve F32 payload bits.
    // Use the view's range, not its entire possibly shared backing buffer.
    new Uint8Array(view.buffer, start, byteLength).set(
      new Uint8Array(words.buffer, words.byteOffset, byteLength),
    );
  } else {
    // Small packets avoid extra byte views. Shared inputs retain no-tear U32
    // reads instead of observing a word as four independently changing bytes.
    // This is not a coherent snapshot of a concurrently modified whole array.
    // Raw words also preserve F32 payloads and handle big-endian hosts.
    for (let index = 0; index < length; index++) {
      view.setUint32(start + index * 4, words[index], true);
    }
  }
}

function copyArrayWords64(
  view: DataView,
  start: number,
  words: BigUint64Array,
) {
  const { length, byteLength } = words;
  if (littleEndian && length > 16 && words.buffer instanceof ArrayBuffer) {
    new Uint8Array(view.buffer, start, byteLength).set(
      new Uint8Array(words.buffer, words.byteOffset, byteLength),
    );
  } else {
    for (let index = 0; index < length; index++) {
      view.setBigUint64(start + index * 8, words[index], true);
    }
  }
}

function allocateTypedArray(type: ArrayType, length: number): GuestTypedArray {
  switch (type) {
    case "Array U8":
      return new Uint8Array(length);
    case "Array U32":
      return new Uint32Array(length);
    case "Array I32":
      return new Int32Array(length);
    case "Array F32":
      return new Float32Array(length);
    case "Array U64":
      return new BigUint64Array(length);
    case "Array I64":
      return new BigInt64Array(length);
    case "Array F64":
      return new Float64Array(length);
  }
}

function arrayFromWasm(
  arena: GuestArena,
  type: ArrayType,
  result: unknown,
  batch?: NumericArrayCall,
): GuestTypedArray {
  const elemBytes = arrayElementBytes(type);
  const pointer = arrayRange(arena, result, 0, elemBytes);
  // Guest execution may also grow memory; never retain the input view.
  const view = new DataView(arena.memory.buffer);
  const length = view.getUint32(pointer, true);
  arrayRange(arena, pointer, length, elemBytes);
  const payloadBytes = length * elemBytes;
  // The ABI wrapper has already packed this payload, even if its length is
  // wrong for the registered batch. Refuse before the additional host copy.
  batch?.observeCopy?.("guestPack", payloadBytes);
  if (batch && length !== batch.resultLength) {
    throw new GuestError(
      "invalid_abi",
      "Numeric batch result has the wrong length",
    );
  }
  const values = allocateTypedArray(type, length);
  batch?.observeCopy?.("guestOutput", payloadBytes);
  if (elemBytes === 1) {
    (values as Uint8Array).set(
      new Uint8Array(arena.memory.buffer, pointer + 4, length),
    );
  } else if (littleEndian && length > (elemBytes === 8 ? 16 : 32)) {
    // Still copy out: the arena is reset/reused after the invocation, and a
    // host callback must never receive a mutable alias into guest storage.
    new Uint8Array(values.buffer).set(
      new Uint8Array(arena.memory.buffer, pointer + 4, values.byteLength),
    );
  } else if (elemBytes === 4) {
    const output = values instanceof Uint32Array
      ? values
      : new Uint32Array(values.buffer);
    for (let index = 0; index < length; index++) {
      output[index] = view.getUint32(pointer + 4 + index * 4, true);
    }
  } else {
    const output = values instanceof BigUint64Array
      ? values
      : new BigUint64Array(values.buffer);
    for (let index = 0; index < length; index++) {
      output[index] = view.getBigUint64(pointer + 4 + index * 8, true);
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
  /** Upper bound on one ABI 8 numeric payload in the transport bank. */
  numericPacketCapacity(overrideBytes?: number): number;
  /** Temporary owners reclaimed by the previous invocation's finish hook. */
  lastReclaimedOwners(): number | undefined;
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
  call(
    name: string,
    argument: unknown,
    batch?: NumericArrayCall,
  ): GuestValue | GuestOwner;
  callAsync(name: string, argument: unknown): Promise<GuestValue | GuestOwner>;
  read(name: string): ScalarValue;
  cleanupDataType(name: string): CleanupDataType;
  cleanupDataCapability(definition: CleanupDataDefinition): HostCapability;
  releaseOwner(owner: GuestOwner): void;
  dispose(): void;
}

/** Fixed-width numeric array transport for an explicitly registered host batch. */
export const numericArrayCopySites = [
  "guestInput",
  "guestUnpack",
  "guestPack",
  "guestOutput",
] as const;
export type NumericArrayCopySite = typeof numericArrayCopySites[number];

export interface NumericArrayCall {
  readonly resultLength: number;
  readonly prefix?: Uint32Array;
  readonly observeCopy?: (site: NumericArrayCopySite, bytes: number) => void;
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
  const parameter = wasmValTypeCode(signature.parameter);
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
  const trapTable = readTrapMetadata(module);
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
  function hostResult(
    type: ValueType,
    value: unknown,
    name: string,
  ): number | bigint {
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
  ): Promise<number | bigint> {
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
      value: number | bigint,
      data?: number,
    ): number | bigint | Promise<number | bigint> => {
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
          ((value as number) >>> 0) !== invocation.signature.dataSchema ||
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
            (value as number) >>> 0,
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
  let finishInvocation: (() => number) | undefined;
  let reclaimedOwners: number | undefined;
  if (abi.invocationFinish) {
    const exit = instance.exports["blot:finish_invocation"];
    if (typeof exit !== "function") {
      throw new GuestError("invalid_abi", "Missing invocation finish hook");
    }
    try {
      new WebAssembly.Instance(
        resourceModule([[1, 96, 0, 1, 127], [
          1,
          ...resourceName("g"),
          ...resourceName("f"),
          0,
          0,
        ]]),
        { g: { f: exit } },
      );
    } catch (cause) {
      throw new GuestError(
        "invalid_abi",
        "Invalid invocation finish signature",
        { cause },
      );
    }
    finishInvocation = exit as () => number;
  }
  let entered = false;
  const memory = instance.exports["blot:memory"];
  const allocate = instance.exports["blot:allocate"];
  const reset = instance.exports["blot:reset"];
  const profiling =
    WebAssembly.Module.customSections(module, "blot:memory-profile").length ===
      1;
  const hasTraps = trapTable !== undefined;
  if (
    memory !== undefined &&
    (allocate !== undefined || reset !== undefined ||
      (abi.taskDescriptorCount === undefined && !profiling && !hasTraps))
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
    "Array U8",
    "Array I32",
    "Array U64",
    "Array I64",
    "Array F64",
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
        parameter = wasmValTypeCode(fn.parameter);
      } else if (fn.parameter.kind === "owner") {
        if (fn.parameter.fresh !== undefined) {
          parameter = wasmValTypeCode(fn.parameter.fresh);
        }
      } else parameter = 111;
      let result = 127;
      if (typeof fn.result === "string") result = wasmValTypeCode(fn.result);
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
    batch?: NumericArrayCall,
  ): { fn: GuestFunction; value: unknown; exported: CallableFunction } {
    idle();
    const fn = functions.get(name);
    if (!fn) {
      throw new GuestError(
        "unknown_export",
        `Unknown function export ${name}`,
      );
    }
    if (
      batch &&
      (!isArrayType(fn.result) || fn.parameter !== "Array U32" ||
        !Number.isSafeInteger(batch.resultLength) || batch.resultLength < 0)
    ) {
      throw new GuestError(
        "invalid_argument",
        "Expected a fixed numeric array batch",
      );
    }
    if (fn.multiplicity === "once" && consumedOnce!.has(name)) {
      throw new GuestError("once_reused", `${name} has already been invoked`);
    }
    let value: number | bigint | object;
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
        value = arrayToWasm(
          arena,
          fn.parameter,
          argument,
          name,
          "invalid_argument",
          batch,
        );
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
      reclaimedOwners = undefined;
      try {
        reclaimedOwners = finishInvocation?.();
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

  function clearTrapSite(): void {
    if (
      memory instanceof WebAssembly.Memory &&
      memory.buffer.byteLength >= TRAP_SITE_OFFSET + 4
    ) {
      new DataView(memory.buffer).setUint32(TRAP_SITE_OFFSET, 0, true);
    }
  }

  return {
    abi,
    lastReclaimedOwners: () => reclaimedOwners,
    memoryBytes: () => {
      if (memory instanceof WebAssembly.Memory) return memory.buffer.byteLength;
      return 0;
    },
    numericPacketCapacity(overrideBytes?: number) {
      idle();
      if (abi.version !== 8 || !arena) {
        throw new GuestError(
          "invalid_abi",
          "Expected an ABI 8 numeric transport bank",
        );
      }
      if (overrideBytes !== undefined) {
        if (
          !Number.isSafeInteger(overrideBytes) || overrideBytes < 8 ||
          overrideBytes % 4 !== 0
        ) {
          throw new RangeError(
            "numericPacketCapacity override must be a safe positive multiple of 4",
          );
        }
        return overrideBytes;
      }
      return abi.transportBudget ?? DEFAULT_TRANSPORT_BUDGET;
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
      callbacks.set(capability, (value) => call(value as DataValue));
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
    call(name, argument, batch) {
      if (options.asynchronous) {
        throw new GuestError(
          "async_host_call",
          "An asynchronous guest requires callAsync()",
        );
      }
      const { fn, value, exported } = begin(name, argument, false, batch);
      let outcome = 1;
      try {
        // ABI 8 zero-copy array entries read the transport bank directly.
        if (batch?.observeCopy) {
          const length = abi.version === 8
            ? 0
            : (argument as Uint32Array).length + (batch.prefix?.length ?? 0);
          batch.observeCopy("guestUnpack", length * 4);
        }
        clearTrapSite();
        let raw: unknown;
        try {
          raw = exported(value);
        } catch (error) {
          throw enrichGuestTrap(error, trapTable, memory);
        }
        let result: GuestValue | GuestOwner;
        if (batch) {
          result = arrayFromWasm(arena!, fn.result as ArrayType, raw, batch);
        } else result = publicResult(fn.result, raw);
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
        clearTrapSite();
        let raw: unknown;
        try {
          raw = await integration.promising(exported)(value);
        } catch (error) {
          throw enrichGuestTrap(error, trapTable, memory);
        }
        const result = publicResult(fn.result, raw);
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
