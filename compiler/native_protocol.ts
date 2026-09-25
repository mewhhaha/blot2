import { CompilerError } from "./diagnostics.ts";
import type {
  Analysis,
  ConstantValue,
  Effect,
  EffectRow,
  Expr,
  FunctionAnalysis,
  MatchArm,
  Pattern,
  RowTail,
  ScalarOp,
  Type,
  TypeId,
  UnaryOp,
} from "./host.ts";
import type { Cst, CstList } from "./syntax.ts";

export const nativeProtocolMagic = 0x424C4F54;
export const nativeProtocolVersion = 12;
export const nativeProtocolMaxWords = 16 * 1024 * 1024;
const littleEndian = new Uint8Array(new Uint32Array([1]).buffer)[0] === 1;

/** `emit` compiles like `compile` but replies with the Wasm bytes only. */
export type NativeOperation = "analyze" | "compile" | "emit";

const statelessOpcodes = { analyze: 0, compile: 1, emit: 7 } as const;
const sessionOpcodes = { analyze: 3, compile: 4, emit: 8 } as const;
const patchOpcodes = { analyze: 5, compile: 6, emit: 9 } as const;

function opcode(
  opcodes: Readonly<Record<NativeOperation, number>>,
  operation: NativeOperation,
  label: string,
): number {
  if (!Object.hasOwn(opcodes, operation)) {
    throw new NativeProtocolError(`Unknown ${label}: ${operation}`);
  }
  return opcodes[operation];
}

export interface NativeRequest {
  readonly operation: NativeOperation;
  readonly root: Cst;
  readonly prelude: Cst;
  readonly fuel: bigint;
  readonly const_steps: bigint;
}

export interface NativeCstChunk {
  readonly strings: readonly string[];
  readonly words: Uint32Array<ArrayBuffer>;
}

export type NativeSessionRequest =
  | { readonly operation: "open"; readonly prelude: Cst; readonly fuel: bigint }
  | Omit<NativeRequest, "prelude">
  | (Omit<NativeRequest, "prelude" | "root"> & {
    readonly declarations: readonly NativeDeclaration[];
  });

export type NativeDeclaration =
  | { readonly kind: "retained"; readonly identity: bigint }
  | { readonly kind: "replaced"; readonly node: Cst };

export interface NativeCacheStats {
  readonly declarations_lowered: number;
  readonly declarations_reused: number;
  readonly groups_checked: number;
  readonly groups_reused: number;
  readonly constants_evaluated: number;
  readonly constants_reused: number;
  readonly entries_compiled: number;
  readonly entries_reused: number;
}

export type NativeSessionResponse =
  | { readonly operation: "open" }
  | { readonly result: NativeResponse; readonly stats: NativeCacheStats };

export type NativeResponse =
  | { readonly operation: "analyze"; readonly analysis: Analysis }
  | {
    readonly operation: "compile";
    readonly artifact: {
      readonly analysis: Analysis;
      readonly bytes: Uint8Array<ArrayBuffer>;
    };
  }
  | { readonly operation: "emit"; readonly bytes: Uint8Array<ArrayBuffer> };

export class NativeProtocolError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "NativeProtocolError";
  }
}

// Payload words are little-endian U32s; the process transport owns framing.
// Strings contain scalar counts followed by Unicode scalars. Nat uses low32,
// high16 words. Lists use U32 counts; optionals and Booleans use 0/1 tags.
// Response kinds: 0 diagnostic, 1 analysis, 2 artifact, 3 opened, 4 cached,
// 5 Wasm only. Requests: 0/1 stateless analyze/compile, 2 open, 3/4 full
// session, 5/6 declaration patches, 7/8/9 emit (stateless, full session,
// patch). Emit compiles like compile and replies with kind 5: the Wasm bytes
// without the analysis. After the scalar request header: dictionary count,
// scalar strings, then the CST/patch body. CST strings are dictionary IDs.
// Dictionary IDs are first-seen preorder across the whole request.
// Cached results carry eight Nat counts and an inner
// kind 1/2/5. Core tags match native_response.bend (not constructor order).
// Wasm is a byte count followed by packed words, with zero final padding.
class WordWriter {
  #bytes = new Uint8Array(4096);
  #view = new DataView(this.#bytes.buffer);
  #length = 0;
  readonly #strings = new Map<string, number>();
  readonly #dictionary: { value: string; scalars: number }[] = [];
  #dictionaryWords = 0;
  #bodyStart: number | undefined;

  #reserve(words: number): void {
    if (
      words >
        nativeProtocolMaxWords - this.#length - this.#dictionaryWords -
          (this.#bodyStart === undefined ? 0 : 1)
    ) {
      throw new NativeProtocolError("Native request exceeds 16M words");
    }
    const required = (this.#length + words) * 4;
    if (required > this.#bytes.length) {
      const next = new Uint8Array(Math.min(
        Math.max(this.#bytes.length * 2, required),
        nativeProtocolMaxWords * 4,
      ));
      next.set(this.#bytes);
      this.#bytes = next;
      this.#view = new DataView(next.buffer);
    }
  }

  word(value: number): void {
    if (!Number.isInteger(value) || value < 0 || value > 0xFFFFFFFF) {
      throw new NativeProtocolError(`Not a U32 protocol word: ${value}`);
    }
    this.#reserve(1);
    this.#view.setUint32(this.#length * 4, value, true);
    this.#length++;
  }

  nat(value: bigint, label: string): void {
    if (typeof value !== "bigint" || value < 0n || value > 0xFFFFFFFFFFFFn) {
      throw new NativeProtocolError(`${label} must be a Nat (0..2^48-1)`);
    }
    this.word(Number(value & 0xFFFFFFFFn));
    this.word(Number(value >> 32n));
  }

  beginBody(): void {
    this.#bodyStart = this.#length;
    this.#reserve(0);
  }

  string(value: string, label: string): void {
    this.word(this.identity(value, label));
  }

  identity(value: string, label: string): number {
    const prior = this.#strings.get(value);
    if (prior !== undefined) return prior;
    if (typeof value !== "string" || !value.isWellFormed()) {
      throw new NativeProtocolError(`${label} is not valid Unicode`);
    }
    let scalars = 0;
    for (const _ of value) scalars++;
    const identity = this.#dictionary.length;
    this.#dictionaryWords += scalars + 1;
    this.#reserve(0);
    this.#strings.set(value, identity);
    this.#dictionary.push({ value, scalars });
    return identity;
  }

  chunk(
    chunk: NativeCstChunk,
    options: { omitRoot?: boolean; children?: number } = {},
  ) {
    const identities = chunk.strings.map((value) =>
      this.identity(value, "CST string")
    );
    const start = options.omitRoot ? 6 : 0;
    if (chunk.words.length < 6 || chunk.words.length % 6) {
      throw new NativeProtocolError("Malformed encoded CST chunk");
    }
    this.#reserve(chunk.words.length - start);
    const target = littleEndian
      ? new Uint32Array(this.#bytes.buffer)
      : undefined;
    const unchanged = identities.every((identity, index) => identity === index);
    // Copy offsets/counts in bulk; only dictionary references need rewriting.
    target?.set(chunk.words.subarray(start), this.#length);
    for (let index = start; index < chunk.words.length; index += 6) {
      const kind = identities[chunk.words[index]];
      const field = identities[chunk.words[index + 1]];
      const text = identities[chunk.words[index + 2]];
      if (kind === undefined || field === undefined || text === undefined) {
        throw new NativeProtocolError("Unknown CST dictionary identity");
      }
      if (target) {
        if (!unchanged) {
          target[this.#length] = kind;
          target[this.#length + 1] = field;
          target[this.#length + 2] = text;
        }
      } else {
        const at = this.#length * 4;
        this.#view.setUint32(at, kind, true);
        this.#view.setUint32(at + 4, field, true);
        this.#view.setUint32(at + 8, text, true);
        this.#view.setUint32(at + 12, chunk.words[index + 3], true);
        this.#view.setUint32(at + 16, chunk.words[index + 4], true);
        this.#view.setUint32(at + 20, chunk.words[index + 5], true);
      }
      if (index === 0 && options.children !== undefined) {
        this.#view.setUint32((this.#length + 5) * 4, options.children, true);
      }
      this.#length += 6;
    }
  }

  fragment(): NativeCstChunk {
    const words = new Uint32Array(this.#length);
    for (let index = 0; index < words.length; index++) {
      words[index] = this.#view.getUint32(index * 4, true);
    }
    return { words, strings: this.#dictionary.map(({ value }) => value) };
  }

  finish(): Uint8Array<ArrayBuffer> {
    if (this.#bodyStart === undefined) {
      throw new Error("Missing native request body");
    }
    const bytes = new Uint8Array(
      (this.#length + this.#dictionaryWords + 1) * 4,
    );
    bytes.set(this.#bytes.subarray(0, this.#bodyStart * 4));
    const view = new DataView(bytes.buffer);
    let position = this.#bodyStart;
    view.setUint32(position++ * 4, this.#dictionary.length, true);
    for (const { value, scalars } of this.#dictionary) {
      view.setUint32(position++ * 4, scalars, true);
      for (const scalar of value) {
        view.setUint32(position++ * 4, scalar.codePointAt(0)!, true);
      }
    }
    bytes.set(
      this.#bytes.subarray(this.#bodyStart * 4, this.#length * 4),
      position * 4,
    );
    return bytes;
  }
}

function childrenOf(node: Cst): Cst[] {
  const children: Cst[] = [];
  const visited = new Set<CstList>();
  let cursor = node.children;
  for (;;) {
    if (typeof cursor !== "object" || cursor === null) {
      throw new NativeProtocolError("CST children must be a Bend list");
    }
    if (cursor.$ === "Nil") return children;
    if (cursor.$ !== "Con") {
      throw new NativeProtocolError("Unknown CST list constructor");
    }
    if (visited.has(cursor)) {
      throw new NativeProtocolError("Cyclic CST child list");
    }
    visited.add(cursor);
    children.push(cursor.head);
    if (children.length > nativeProtocolMaxWords) {
      throw new NativeProtocolError("CST child count exceeds protocol limit");
    }
    cursor = cursor.tail;
  }
}

export function encodeNativeRequest(
  request: NativeRequest,
): Uint8Array<ArrayBuffer> {
  const operation = opcode(
    statelessOpcodes,
    request.operation,
    "native operation",
  );
  const writer = new WordWriter();
  writer.word(nativeProtocolMagic);
  writer.word(nativeProtocolVersion);
  writer.word(operation);
  writer.nat(request.fuel, "Lowering fuel");
  writer.nat(request.const_steps, "Const steps");
  writer.beginBody();
  writeTrees(writer, [request.root, request.prelude]);
  return writer.finish();
}

export function encodeCstChunk(root: Cst): NativeCstChunk {
  const writer = new WordWriter();
  writer.beginBody();
  writeTrees(writer, [root]);
  return writer.fragment();
}

export function encodeNativeChunks(request: {
  readonly operation: NativeOperation;
  readonly chunks: readonly NativeCstChunk[];
  readonly prelude: NativeCstChunk;
  readonly const_steps: bigint;
}): Uint8Array<ArrayBuffer> {
  const operation = opcode(
    statelessOpcodes,
    request.operation,
    "native operation",
  );
  if (!request.chunks.length) {
    throw new NativeProtocolError("Missing source CST");
  }
  const writer = new WordWriter();
  const sourceNodes = request.chunks.reduce(
    (sum, chunk) => sum + chunk.words.length / 6 - 1,
    1,
  );
  writer.word(nativeProtocolMagic);
  writer.word(nativeProtocolVersion);
  writer.word(operation);
  writer.nat(
    BigInt(sourceNodes + request.prelude.words.length / 6 + 4),
    "Lowering fuel",
  );
  writer.nat(request.const_steps, "Const steps");
  writer.beginBody();
  const children = request.chunks.reduce(
    (sum, chunk) => sum + chunk.words[5],
    0,
  );
  request.chunks.forEach((chunk, index) =>
    writer.chunk(chunk, index === 0 ? { children } : { omitRoot: true })
  );
  writer.chunk(request.prelude);
  return writer.finish();
}

export function encodeNativeSessionRequest(
  request: NativeSessionRequest,
): Uint8Array<ArrayBuffer> {
  const writer = new WordWriter();
  writer.word(nativeProtocolMagic);
  writer.word(nativeProtocolVersion);
  if (request.operation === "open") {
    writer.word(2);
    writer.nat(request.fuel, "Prelude fuel");
    writer.beginBody();
    writeTrees(writer, [request.prelude]);
  } else {
    writer.word(opcode(
      "declarations" in request ? patchOpcodes : sessionOpcodes,
      request.operation,
      "session operation",
    ));
    writer.nat(request.fuel, "Lowering fuel");
    writer.nat(request.const_steps, "Const steps");
    writer.beginBody();
    if ("declarations" in request) {
      if (!Array.isArray(request.declarations)) {
        throw new NativeProtocolError("Session declarations must be an array");
      }
      writer.word(request.declarations.length);
      for (const declaration of request.declarations) {
        if (typeof declaration !== "object" || declaration === null) {
          throw new NativeProtocolError("Invalid session declaration");
        }
        if (declaration.kind === "retained") {
          writer.word(0);
          writer.nat(declaration.identity, "Retained declaration identity");
        } else if (declaration.kind === "replaced") {
          writer.word(1);
          writeTrees(writer, [declaration.node]);
        } else {
          throw new NativeProtocolError("Unknown session declaration kind");
        }
      }
    } else {
      writeTrees(writer, [request.root]);
    }
  }
  return writer.finish();
}

function writeTrees(writer: WordWriter, roots: readonly Cst[]): void {
  const pending: ({ node: Cst } | { leave: Cst })[] = roots.toReversed().map(
    (node) => ({ node }),
  );
  const active = new Set<Cst>();
  for (let task = pending.pop(); task; task = pending.pop()) {
    if ("leave" in task) {
      active.delete(task.leave);
      continue;
    }
    const node = task.node;
    if (typeof node !== "object" || node === null || node.$ !== "Cst") {
      throw new NativeProtocolError("Unknown CST node constructor");
    }
    if (active.has(node)) throw new NativeProtocolError("Cyclic CST tree");
    active.add(node);
    writer.string(node.kind, "CST kind");
    writer.string(node.field, "CST field");
    writer.string(node.text, "CST text");
    writer.nat(node.offset, "CST offset");
    const children = childrenOf(node);
    writer.word(children.length);
    pending.push({ leave: node });
    for (let index = children.length - 1; index >= 0; index--) {
      pending.push({ node: children[index] });
    }
  }
}

type Read<T> = (receive: (value: T) => void) => void;

class WordReader {
  readonly #view: DataView;
  readonly #words: number;
  readonly #jobs: (() => void)[] = [];
  #offset = 0;

  constructor(payload: Uint8Array) {
    if (payload.byteLength % 4 !== 0) {
      throw new NativeProtocolError("Native response is not word aligned");
    }
    if (payload.byteLength > nativeProtocolMaxWords * 4) {
      throw new NativeProtocolError("Native response exceeds 16M words");
    }
    this.#view = new DataView(
      payload.buffer,
      payload.byteOffset,
      payload.byteLength,
    );
    this.#words = payload.byteLength / 4;
  }

  word(): number {
    if (this.#offset === this.#words) {
      throw new NativeProtocolError("Truncated native response");
    }
    return this.#view.getUint32(this.#offset++ * 4, true);
  }

  f32(): number {
    this.word();
    return this.#view.getFloat32((this.#offset - 1) * 4, true);
  }

  tag<const Tags extends readonly string[]>(tags: Tags): Tags[number] {
    const tag = this.word();
    if (tag >= tags.length) {
      throw new NativeProtocolError(`Unknown ${tags.join("/")} tag: ${tag}`);
    }
    return tags[tag];
  }

  boolean(): boolean {
    return this.tag(["False", "True"]) === "True";
  }

  nat(): bigint {
    const low = this.word();
    const high = this.word();
    if (high > 0xFFFF) {
      throw new NativeProtocolError("Native Nat exceeds 2^48-1");
    }
    return (BigInt(high) << 32n) | BigInt(low);
  }

  count(): number {
    const count = this.word();
    if (count > this.#words - this.#offset) {
      throw new NativeProtocolError("Native collection length exceeds payload");
    }
    return count;
  }

  string(): string {
    const count = this.count();
    const chunks: string[] = [];
    const scalars: number[] = [];
    for (let index = 0; index < count; index++) {
      const scalar = this.word();
      if (scalar > 0x10FFFF || (scalar >= 0xD800 && scalar <= 0xDFFF)) {
        throw new NativeProtocolError(`Invalid Unicode scalar: ${scalar}`);
      }
      scalars.push(scalar);
      if (scalars.length === 4096) {
        chunks.push(String.fromCodePoint(...scalars));
        scalars.length = 0;
      }
    }
    if (scalars.length) chunks.push(String.fromCodePoint(...scalars));
    return chunks.join("");
  }

  bytes(): Uint8Array<ArrayBuffer> {
    const count = this.word();
    const words = Math.ceil(count / 4);
    if (words > this.#words - this.#offset) {
      throw new NativeProtocolError("Native Wasm length exceeds payload");
    }
    const bytes = new Uint8Array(count);
    for (let index = 0; index < words; index++) {
      const word = this.word();
      const width = Math.min(4, count - index * 4);
      for (let byte = 0; byte < width; byte++) {
        bytes[index * 4 + byte] = word >>> (byte * 8);
      }
      if (width < 4 && word >>> (width * 8) !== 0) {
        throw new NativeProtocolError("Native Wasm padding must be zero");
      }
    }
    return bytes;
  }

  finish(): void {
    if (this.#offset !== this.#words) {
      throw new NativeProtocolError("Trailing words after native response");
    }
  }

  read<T>(reader: Read<T>): T {
    let result: { value: T } | undefined;
    this.#jobs.push(() => reader((value) => result = { value }));
    for (let job = this.#jobs.pop(); job; job = this.#jobs.pop()) job();
    if (!result) throw new Error("Native decoder did not produce its result");
    return result.value;
  }

  fields<Fields extends readonly unknown[], Output>(
    readers: { readonly [Key in keyof Fields]: Read<Fields[Key]> },
    construct: (...fields: Fields) => Output,
    receive: (value: Output) => void,
  ): void {
    const values: unknown[] = [];
    // Each typed reader fills its corresponding tuple slot before this job.
    this.#jobs.push(() => receive(construct(...values as unknown as Fields)));
    for (let index = readers.length - 1; index >= 0; index--) {
      this.#jobs.push(() => readers[index]((value) => values[index] = value));
    }
  }

  array<T>(reader: Read<T>): Read<readonly T[]> {
    return (receive) => {
      const count = this.count();
      const values: T[] = [];
      const next = () => {
        if (values.length === count) {
          receive(values);
          return;
        }
        this.#jobs.push(next);
        this.#jobs.push(() => reader((value) => values.push(value)));
      };
      next();
    };
  }

  optional<T>(reader: Read<T>): Read<T | null> {
    return (receive) => {
      if (this.boolean()) this.#jobs.push(() => reader(receive));
      else receive(null);
    };
  }

  readonly readString: Read<string> = (receive) => receive(this.string());
  readonly readNat: Read<bigint> = (receive) => receive(this.nat());
  readonly readBytes: Read<Uint8Array<ArrayBuffer>> = (receive) =>
    receive(this.bytes());

  readonly identity: Read<TypeId> = (receive) =>
    receive({
      $: "TypeId",
      module_name: this.string(),
      declaration: this.string(),
    });

  readonly rowTail: Read<RowTail> = (receive) => {
    const $ = this.tag(["ClosedRow", "RowVariable", "RowParameter"]);
    receive($ === "ClosedRow" ? { $ } : { $, index: this.nat() });
  };
  readonly row: Read<EffectRow> = (receive) =>
    this.fields(
      [this.array(this.identity), this.rowTail],
      (operations, tail) => ({ $: "EffectRow" as const, operations, tail }),
      receive,
    );
  readonly effect: Read<Effect> = (receive) =>
    this.fields(
      [this.identity],
      (identity) => ({ $: "OperationEffect" as const, identity }),
      receive,
    );

  readonly type: Read<Type> = (receive) => {
    const $ = this.tag([
      "UnitTy",
      "U32Ty",
      "BoolTy",
      "AppliedTy",
      "FunctionTy",
      "ParameterTy",
      "VariableTy",
      "NeverTy",
      "F32Ty",
      "ProviderTy",
      "EffectDescriptorTy",
      "EffectSetTy",
      "ProductTy",
      "ArrayTy",
      "StateProviderTy",
      "FreeTy",
    ]);
    switch ($) {
      case "StateProviderTy":
        this.fields(
          [this.identity, this.identity, this.type],
          (read, write, state) => ({ $, read, write, state }),
          receive,
        );
        return;
      case "UnitTy":
      case "U32Ty":
      case "BoolTy":
      case "NeverTy":
      case "F32Ty":
      case "EffectDescriptorTy":
      case "EffectSetTy":
        receive({ $ });
        return;
      case "AppliedTy":
        this.fields(
          [this.identity, this.array(this.type)],
          (identity, arguments_) => ({ $, identity, arguments: arguments_ }),
          receive,
        );
        return;
      case "ProductTy":
        this.fields(
          [this.array(this.type)],
          (elements) => ({ $, elements }),
          receive,
        );
        return;
      case "ArrayTy":
        this.fields([this.type], (element) => ({ $, element }), receive);
        return;
      case "ProviderTy":
        this.fields(
          [this.identity, this.row],
          (identity, effects) => ({ $, identity, effects }),
          receive,
        );
        return;
      case "FunctionTy":
        this.fields(
          [this.type, this.type, this.row],
          (parameter, result, effects) => ({ $, parameter, result, effects }),
          receive,
        );
        return;
      case "FreeTy":
        receive({ $, scope: this.string(), name: this.string() });
        return;
      case "ParameterTy":
      case "VariableTy":
        receive({ $, index: this.nat() });
    }
  };

  readonly pattern: Read<Pattern> = (receive) => {
    const $ = this.tag([
      "WildcardPattern",
      "BindingPattern",
      "UnitPattern",
      "U32Pattern",
      "BoolPattern",
      "ConstructorPattern",
      "ProductPattern",
      "ValuePattern",
    ]);
    switch ($) {
      case "WildcardPattern":
      case "UnitPattern":
        receive({ $ });
        return;
      case "BindingPattern":
        receive({ $, name: this.string() });
        return;
      case "U32Pattern":
        receive({ $, value: this.word() });
        return;
      case "BoolPattern":
        receive({ $, value: this.boolean() });
        return;
      case "ConstructorPattern":
        this.fields(
          [this.readString, this.optional(this.pattern)],
          (constructor, payload) => ({ $, constructor, payload }),
          receive,
        );
        return;
      case "ValuePattern":
        receive({
          $,
          reference: {
            $: this.tag(["LocalReference", "ConstantReference"]),
            name: this.string(),
          },
        });
        return;
      case "ProductPattern":
        this.fields(
          [this.array(this.pattern)],
          (elements) => ({ $, elements }),
          receive,
        );
    }
  };

  readonly operator: Read<ScalarOp> = (receive) =>
    receive({
      $: this.tag([
        "Add",
        "Subtract",
        "Multiply",
        "Equal",
        "LessThan",
        "F32Add",
        "F32Subtract",
        "F32Multiply",
        "F32Divide",
        "F32Equal",
        "F32NotEqual",
        "F32LessThan",
        "F32LessEqual",
        "F32GreaterThan",
        "F32GreaterEqual",
      ]),
    });

  readonly unaryOperator: Read<UnaryOp> = (receive) =>
    receive({
      $: this.tag([
        "F32Negate",
        "F32Absolute",
        "F32SquareRoot",
        "F32Floor",
        "F32Ceiling",
        "F32Truncate",
        "U32ToF32",
        "F32ToU32",
      ]),
    });

  readonly arm: Read<MatchArm> = (receive) =>
    this.fields(
      [this.array(this.pattern), this.expression],
      (patterns, body) => ({ patterns, body }),
      receive,
    );

  readonly expression: Read<Expr> = (receive) => {
    const $ = this.tag([
      "UnitExpr",
      "U32Expr",
      "BoolExpr",
      "LocalExpr",
      "ConstantExpr",
      "FunctionExpr",
      "ConstructorRefExpr",
      "ConstructExpr",
      "LambdaExpr",
      "ApplyExpr",
      "CallExpr",
      "ScalarExpr",
      "LetExpr",
      "UseExpr",
      "IfExpr",
      "SequenceExpr",
      "MatchExpr",
      "GuardExpr",
      "BlockExpr",
      "ReturnExpr",
      "SourceExpr",
      "F32Expr",
      "UnaryExpr",
      "PanicExpr",
      "OperationExpr",
      "ProviderExpr",
      "HandleExpr",
      "OperationDescriptorExpr",
      "FunctionEffectsExpr",
      "EffectHasExpr",
      "EffectCountExpr",
      "EffectSameExpr",
      "ProductExpr",
      "ProjectExpr",
      "ArrayExpr",
      "ArrayGetExpr",
      "ArraySetExpr",
      "ArrayLengthExpr",
      "ArrayFillExpr",
      "ArrayGenerateExpr",
      "UnresolvedAssociatedExpr",
      "ForExpr",
      "StateProviderExpr",
      "UnresolvedGenericOperationExpr",
      "RuntimeInitExpr",
      "TagExpr",
      "ForeverExpr",
    ]);
    switch ($) {
      case "StateProviderExpr":
        this.fields(
          [this.identity, this.identity, this.expression],
          (read, write, initial) => ({ $, read, write, initial }),
          receive,
        );
        return;
      case "UnitExpr":
        receive({ $ });
        return;
      case "ProductExpr":
      case "ArrayExpr":
        this.fields(
          [this.array(this.expression)],
          (elements) => ({ $, elements }),
          receive,
        );
        return;
      case "UnresolvedAssociatedExpr":
        throw new NativeProtocolError(
          "Unresolved associated call in compiler response",
        );
      case "UnresolvedGenericOperationExpr":
        throw new NativeProtocolError(
          "Unresolved generic effect operation in compiler response",
        );
      case "ForExpr":
        this.fields(
          [
            this.readString,
            this.expression,
            this.expression,
            this.readString,
            this.expression,
            this.expression,
          ],
          (index, start, end, state, initial, body) => ({
            $,
            index,
            start,
            end,
            state,
            initial,
            body,
          }),
          receive,
        );
        return;
      case "ForeverExpr":
        this.fields(
          [this.readString, this.expression, this.expression],
          (state, initial, body) => ({ $, state, initial, body }),
          receive,
        );
        return;
      case "ArrayGenerateExpr":
        this.fields(
          [this.expression, this.expression],
          (count, generator) => ({ $, count, generator }),
          receive,
        );
        return;
      case "ArrayFillExpr":
        this.fields(
          [this.expression, this.expression],
          (count, value) => ({ $, count, value }),
          receive,
        );
        return;
      case "ArrayGetExpr":
        this.fields(
          [this.expression, this.expression],
          (array, index) => ({ $, array, index }),
          receive,
        );
        return;
      case "ArraySetExpr":
        this.fields(
          [this.expression, this.expression, this.expression],
          (array, index, value) => ({ $, array, index, value }),
          receive,
        );
        return;
      case "ArrayLengthExpr":
        this.fields([this.expression], (array) => ({ $, array }), receive);
        return;
      case "ProjectExpr":
        this.fields(
          [this.expression, this.readNat],
          (value, index) => ({ $, value, index }),
          receive,
        );
        return;
      case "U32Expr":
        receive({ $, value: this.word() });
        return;
      case "F32Expr":
        receive({ $, value: this.f32() });
        return;
      case "UnaryExpr":
        this.fields(
          [this.unaryOperator, this.expression],
          (operator, value) => ({ $, operator, value }),
          receive,
        );
        return;
      case "BoolExpr":
        receive({ $, value: this.boolean() });
        return;
      case "LocalExpr":
      case "ConstantExpr":
      case "FunctionExpr":
        receive({ $, name: this.string() });
        return;
      case "ConstructorRefExpr":
        receive({ $, constructor: this.string() });
        return;
      case "ConstructExpr":
        this.fields(
          [this.readString, this.optional(this.expression)],
          (constructor, payload) => ({ $, constructor, payload }),
          receive,
        );
        return;
      case "LambdaExpr":
        this.fields(
          [
            this.readNat,
            this.readString,
            this.optional(this.type),
            this.optional(this.type),
            this.expression,
          ],
          (identity, parameter, parameter_type, result_type, body) => ({
            $,
            identity,
            parameter,
            parameter_type,
            result_type,
            body,
          }),
          receive,
        );
        return;
      case "ApplyExpr":
        this.fields(
          [this.expression, this.expression],
          (callee, argument) => ({ $, callee, argument }),
          receive,
        );
        return;
      case "CallExpr":
        this.fields(
          [this.readString, this.expression],
          (callee, argument) => ({ $, callee, argument }),
          receive,
        );
        return;
      case "ScalarExpr":
        this.fields(
          [this.operator, this.expression, this.expression],
          (operator, left, right) => ({ $, operator, left, right }),
          receive,
        );
        return;
      case "LetExpr":
      case "UseExpr":
        this.fields(
          [this.readString, this.expression, this.expression],
          (name, value, body) => ({ $, name, value, body }),
          receive,
        );
        return;
      case "IfExpr":
        this.fields(
          [this.expression, this.expression, this.expression],
          (condition, consequent, alternative) => ({
            $,
            condition,
            consequent,
            alternative,
          }),
          receive,
        );
        return;
      case "SequenceExpr":
        this.fields(
          [this.expression, this.expression],
          (first, next) => ({ $, first, next }),
          receive,
        );
        return;
      case "MatchExpr":
        this.fields(
          [this.array(this.expression), this.array(this.arm)],
          (values, arms) => ({ $, values, arms }),
          receive,
        );
        return;
      case "GuardExpr":
        this.fields(
          [this.pattern, this.expression, this.expression, this.expression],
          (pattern, value, alternative, body) => ({
            $,
            pattern,
            value,
            alternative,
            body,
          }),
          receive,
        );
        return;
      case "BlockExpr":
        this.fields(
          [this.readNat, this.expression],
          (label, body) => ({ $, label, body }),
          receive,
        );
        return;
      case "ReturnExpr":
        this.fields(
          [this.readNat, this.expression],
          (label, value) => ({ $, label, value }),
          receive,
        );
        return;
      case "RuntimeInitExpr":
        this.fields([this.expression], (value) => ({ $, value }), receive);
        return;
      case "TagExpr":
        this.fields(
          [this.readNat, this.expression, this.expression],
          (offset, callee, argument) => ({ $, offset, callee, argument }),
          receive,
        );
        return;
      case "SourceExpr":
        this.fields(
          [this.readNat, this.optional(this.type), this.expression],
          (offset, annotation, value) => ({
            $,
            offset,
            value,
            annotation: annotation === null
              ? { $: "None" as const }
              : { $: "Some" as const, value: annotation },
          }),
          receive,
        );
        return;
      case "OperationExpr":
      case "OperationDescriptorExpr":
        this.fields([this.identity], (identity) => ({ $, identity }), receive);
        return;
      case "PanicExpr":
        receive({ $, message: this.string() });
        return;
      case "FunctionEffectsExpr":
        receive({ $, callee: this.string() });
        return;
      case "ProviderExpr":
        this.fields(
          [this.identity, this.expression],
          (identity, implementation) => ({ $, identity, implementation }),
          receive,
        );
        return;
      case "HandleExpr":
        this.fields(
          [this.expression, this.expression],
          (provider, body) => ({ $, provider, body }),
          receive,
        );
        return;
      case "EffectHasExpr":
        this.fields(
          [this.expression, this.expression],
          (set, operation) => ({ $, set, operation }),
          receive,
        );
        return;
      case "EffectCountExpr":
        this.fields([this.expression], (set) => ({ $, set }), receive);
        return;
      case "EffectSameExpr":
        this.fields(
          [this.expression, this.expression],
          (left, right) => ({ $, left, right }),
          receive,
        );
    }
  };

  readonly binding: Read<Analysis["constants"][number]> = (receive) =>
    this.fields(
      [this.readString, this.value],
      (name, value) => ({ name, value }),
      receive,
    );

  readonly value: Read<ConstantValue> = (receive) => {
    const $ = this.tag([
      "UnitValue",
      "U32Value",
      "BoolValue",
      "FunctionValue",
      "ConstructorFunctionValue",
      "DataValue",
      "ClosureValue",
      "F32Value",
      "OperationValue",
      "ProviderValue",
      "EffectDescriptorValue",
      "EffectSetValue",
      "ProductValue",
      "ArrayValue",
      "StateProviderValue",
    ]);
    switch ($) {
      case "StateProviderValue":
        this.fields(
          [this.identity, this.identity, this.value],
          (read, write, initial) => ({ $, read, write, initial }),
          receive,
        );
        return;
      case "UnitValue":
        receive({ $ });
        return;
      case "ProductValue":
      case "ArrayValue":
        this.fields(
          [this.array(this.value)],
          (elements) => ({ $, elements }),
          receive,
        );
        return;
      case "OperationValue":
      case "EffectDescriptorValue":
        this.fields([this.identity], (identity) => ({ $, identity }), receive);
        return;
      case "ProviderValue":
        this.fields(
          [this.identity, this.value],
          (identity, implementation) => ({ $, identity, implementation }),
          receive,
        );
        return;
      case "EffectSetValue":
        this.fields(
          [this.array(this.identity)],
          (operations) => ({ $, operations }),
          receive,
        );
        return;
      case "U32Value":
        receive({ $, value: this.word() });
        return;
      case "F32Value":
        receive({ $, value: this.f32() });
        return;
      case "BoolValue":
        receive({ $, value: this.boolean() });
        return;
      case "FunctionValue":
        receive({ $, name: this.string() });
        return;
      case "ConstructorFunctionValue":
        receive({ $, constructor: this.string() });
        return;
      case "DataValue":
        this.fields(
          [this.readString, this.optional(this.value)],
          (constructor, payload) => ({ $, constructor, payload }),
          receive,
        );
        return;
      case "ClosureValue":
        this.fields(
          [
            this.readNat,
            this.readString,
            this.expression,
            this.array(this.binding),
          ],
          (identity, parameter, body, environment) => ({
            $,
            identity,
            parameter,
            body,
            environment,
          }),
          receive,
        );
    }
  };

  readonly function: Read<FunctionAnalysis> = (receive) =>
    this.fields(
      [
        this.readString,
        this.type,
        this.type,
        this.array(this.readNat),
        this.array(this.effect),
        this.row,
      ],
      (name, parameter, result, variables, effects, effect_row) => ({
        name,
        parameter,
        result,
        variables,
        effects,
        effect_row,
      }),
      receive,
    );

  readonly analysis: Read<Analysis> = (receive) =>
    this.fields(
      [
        this.array(this.function),
        this.array(this.binding),
        this.readNat,
      ],
      (functions, constants, remaining_steps) => ({
        functions,
        constants,
        remaining_steps,
      }),
      receive,
    );

  readonly artifact: Read<
    Extract<NativeResponse, { operation: "compile" }>["artifact"]
  > = (receive) =>
    this.fields(
      [this.analysis, this.readBytes],
      (analysis, bytes) => ({ analysis, bytes }),
      receive,
    );

  header(): void {
    if (this.word() !== nativeProtocolMagic) {
      throw new NativeProtocolError("Invalid native response magic");
    }
    if (this.word() !== nativeProtocolVersion) {
      throw new NativeProtocolError("Unsupported native response version");
    }
  }

  diagnostic(): never {
    const diagnostic = {
      code: this.string(),
      subject: this.string(),
      message: this.string(),
    };
    this.finish();
    throw new CompilerError(diagnostic);
  }

  result(): NativeResponse {
    const kind = this.tag([
      "diagnostic",
      "analyze",
      "compile",
      "open",
      "cached",
      "emit",
    ]);
    switch (kind) {
      case "diagnostic":
        return this.diagnostic();
      case "analyze":
        return { operation: kind, analysis: this.read(this.analysis) };
      case "compile":
        return { operation: kind, artifact: this.read(this.artifact) };
      case "emit":
        return { operation: kind, bytes: this.bytes() };
      case "open":
      case "cached":
        throw new NativeProtocolError(
          `Unexpected nested response kind: ${kind}`,
        );
    }
  }
}

export function decodeNativeResponse(payload: Uint8Array): NativeResponse {
  const reader = new WordReader(payload);
  reader.header();
  const response = reader.result();
  reader.finish();
  return response;
}

export function decodeNativeSessionResponse(
  payload: Uint8Array,
): NativeSessionResponse {
  const reader = new WordReader(payload);
  reader.header();
  const kind = reader.word();
  if (kind === 0) return reader.diagnostic();
  if (kind === 3) {
    reader.finish();
    return { operation: "open" };
  }
  if (kind !== 4) {
    throw new NativeProtocolError(`Unknown session response kind: ${kind}`);
  }
  // Nat's 48-bit bound is exactly representable by a JavaScript number.
  const stats: NativeCacheStats = {
    declarations_lowered: Number(reader.nat()),
    declarations_reused: Number(reader.nat()),
    groups_checked: Number(reader.nat()),
    groups_reused: Number(reader.nat()),
    constants_evaluated: Number(reader.nat()),
    constants_reused: Number(reader.nat()),
    entries_compiled: Number(reader.nat()),
    entries_reused: Number(reader.nat()),
  };
  const result = reader.result();
  reader.finish();
  return { result, stats };
}
