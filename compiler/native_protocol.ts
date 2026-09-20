import { CompilerError } from "./diagnostics.ts";
import type {
  Access,
  Analysis,
  ConstantValue,
  Descriptor,
  EcsArtifact,
  EcsStorage,
  Effect,
  Expr,
  FunctionAnalysis,
  MatchArm,
  Pattern,
  ScalarOp,
  SystemPlan,
  Type,
  TypeId,
} from "./host.ts";
import type { Cst, CstList } from "./syntax.ts";

export const nativeProtocolMagic = 0x424C4F54;
export const nativeProtocolVersion = 1;
export const nativeProtocolMaxWords = 16 * 1024 * 1024;

export type NativeOperation = "analyze" | "compile" | "compileEcs";

export interface NativeRequest {
  readonly operation: NativeOperation;
  readonly root: Cst;
  readonly prelude: Cst;
  readonly fuel: bigint;
  readonly const_steps: bigint;
}

export type NativeResponse =
  | { readonly operation: "analyze"; readonly analysis: Analysis }
  | {
    readonly operation: "compile";
    readonly artifact: {
      readonly analysis: Analysis;
      readonly bytes: Uint8Array<ArrayBuffer>;
    };
  }
  | { readonly operation: "compileEcs"; readonly artifact: EcsArtifact };

export class NativeProtocolError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "NativeProtocolError";
  }
}

// Payload words are little-endian U32s; the process transport owns framing.
// Strings contain scalar counts followed by Unicode scalars. Nat uses low32,
// high16 words. Lists use U32 counts; optionals and Booleans use 0/1 tags.
// Response kinds: 0 diagnostic, 1 analysis, 2 Wasm artifact, 3 ECS artifact.
// Type/Pattern/Expr/Value tags follow declaration order in model/const_eval.
// Wasm is a byte count followed by packed words, with zero final padding.
class WordWriter {
  #bytes = new Uint8Array(4096);
  #view = new DataView(this.#bytes.buffer);
  #length = 0;

  word(value: number): void {
    if (!Number.isInteger(value) || value < 0 || value > 0xFFFFFFFF) {
      throw new NativeProtocolError(`Not a U32 protocol word: ${value}`);
    }
    if (this.#length === nativeProtocolMaxWords) {
      throw new NativeProtocolError("Native request exceeds 16M words");
    }
    const offset = this.#length * 4;
    if (offset === this.#bytes.length) {
      const next = new Uint8Array(Math.min(
        this.#bytes.length * 2,
        nativeProtocolMaxWords * 4,
      ));
      next.set(this.#bytes);
      this.#bytes = next;
      this.#view = new DataView(next.buffer);
    }
    this.#view.setUint32(offset, value, true);
    this.#length++;
  }

  nat(value: bigint, label: string): void {
    if (typeof value !== "bigint" || value < 0n || value > 0xFFFFFFFFFFFFn) {
      throw new NativeProtocolError(`${label} must be a Nat (0..2^48-1)`);
    }
    this.word(Number(value & 0xFFFFFFFFn));
    this.word(Number(value >> 32n));
  }

  string(value: string, label: string): void {
    if (typeof value !== "string" || !value.isWellFormed()) {
      throw new NativeProtocolError(`${label} is not valid Unicode`);
    }
    let count = 0;
    for (const _ of value) count++;
    this.word(count);
    for (const scalar of value) this.word(scalar.codePointAt(0)!);
  }

  finish(): Uint8Array<ArrayBuffer> {
    return this.#bytes.slice(0, this.#length * 4);
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
  const operations = { analyze: 0, compile: 1, compileEcs: 2 } as const;
  if (!Object.hasOwn(operations, request.operation)) {
    throw new NativeProtocolError(
      `Unknown native operation: ${request.operation}`,
    );
  }
  const writer = new WordWriter();
  writer.word(nativeProtocolMagic);
  writer.word(nativeProtocolVersion);
  writer.word(operations[request.operation]);
  writer.nat(request.fuel, "Lowering fuel");
  writer.nat(request.const_steps, "Const steps");
  const pending: ({ node: Cst } | { leave: Cst })[] = [
    { node: request.prelude },
    { node: request.root },
  ];
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
  return writer.finish();
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

  readonly storage: Read<Descriptor["storage"]> = (receive) =>
    receive({ $: this.tag(["Component", "Resource"]) });

  readonly descriptor: Read<Descriptor> = (receive) =>
    this.fields(
      [this.identity, this.storage],
      (identity, storage) => ({ $: "Descriptor" as const, identity, storage }),
      receive,
    );

  readonly access: Read<Access> = (receive) =>
    receive({ $: this.tag(["Read", "Write", "Insert"]) });

  readonly effect: Read<Effect> = (receive) =>
    this.fields(
      [this.access, this.descriptor],
      (access, descriptor) => ({ $: "Effect" as const, access, descriptor }),
      receive,
    );

  readonly type: Read<Type> = (receive) => {
    const $ = this.tag([
      "UnitTy",
      "U32Ty",
      "BoolTy",
      "NominalTy",
      "AppliedTy",
      "FunctionTy",
      "ParameterTy",
      "VariableTy",
      "NeverTy",
    ]);
    switch ($) {
      case "UnitTy":
      case "U32Ty":
      case "BoolTy":
      case "NeverTy":
        receive({ $ });
        return;
      case "NominalTy":
        this.fields([this.identity], (identity) => ({ $, identity }), receive);
        return;
      case "AppliedTy":
        this.fields(
          [this.identity, this.array(this.type)],
          (identity, arguments_) => ({ $, identity, arguments: arguments_ }),
          receive,
        );
        return;
      case "FunctionTy":
        this.fields(
          [this.type, this.type],
          (parameter, result) => ({ $, parameter, result }),
          receive,
        );
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
    }
  };

  readonly operator: Read<ScalarOp> = (receive) =>
    receive({
      $: this.tag(["Add", "Subtract", "Multiply", "Equal", "LessThan"]),
    });

  readonly arm: Read<MatchArm> = (receive) =>
    this.fields(
      [this.pattern, this.expression],
      (pattern, body) => ({ pattern, body }),
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
      "ReadExpr",
      "WriteExpr",
      "InsertExpr",
    ]);
    switch ($) {
      case "UnitExpr":
        receive({ $ });
        return;
      case "U32Expr":
        receive({ $, value: this.word() });
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
          [this.expression, this.array(this.arm)],
          (value, arms) => ({ $, value, arms }),
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
      case "ReadExpr":
        this.fields([this.identity], (identity) => ({ $, identity }), receive);
        return;
      case "WriteExpr":
      case "InsertExpr":
        this.fields([this.expression], (value) => ({ $, value }), receive);
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
    ]);
    switch ($) {
      case "UnitValue":
        receive({ $ });
        return;
      case "U32Value":
        receive({ $, value: this.word() });
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
      ],
      (name, parameter, result, variables, effects) => ({
        name,
        parameter,
        result,
        variables,
        effects,
      }),
      receive,
    );

  readonly system: Read<SystemPlan> = (receive) =>
    this.fields(
      [this.readString, this.array(this.effect), this.array(this.descriptor)],
      (name, effects, query) => ({ name, effects, query }),
      receive,
    );

  readonly world: Read<Analysis["world"]> = (receive) =>
    this.fields(
      [
        this.array(this.descriptor),
        this.array(this.system),
        this.array(this.array(this.readString)),
      ],
      (registrations, systems, batches) => ({
        registrations,
        systems,
        batches,
      }),
      receive,
    );

  readonly analysis: Read<Analysis> = (receive) =>
    this.fields(
      [
        this.array(this.function),
        this.array(this.binding),
        this.world,
        this.readNat,
      ],
      (functions, constants, world, remaining_steps) => ({
        functions,
        constants,
        world,
        remaining_steps,
      }),
      receive,
    );

  readonly ecsStorage: Read<EcsStorage> = (receive) =>
    this.fields(
      [this.identity, this.storage, this.readString, this.readNat],
      (identity, storage, constructor, tag) => {
        if (tag > 0xFFFFFFFFn) {
          throw new NativeProtocolError("ECS storage tag exceeds U32");
        }
        return { identity, storage, constructor, tag: Number(tag) };
      },
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

  readonly ecsArtifact: Read<EcsArtifact> = (receive) =>
    this.fields(
      [this.analysis, this.array(this.ecsStorage), this.readBytes],
      (analysis, storage, bytes) => ({ analysis, storage, bytes }),
      receive,
    );
}

export function decodeNativeResponse(payload: Uint8Array): NativeResponse {
  const reader = new WordReader(payload);
  if (reader.word() !== nativeProtocolMagic) {
    throw new NativeProtocolError("Invalid native response magic");
  }
  if (reader.word() !== nativeProtocolVersion) {
    throw new NativeProtocolError("Unsupported native response version");
  }
  const kind = reader.tag(["diagnostic", "analyze", "compile", "compileEcs"]);
  let response: NativeResponse;
  switch (kind) {
    case "diagnostic": {
      const diagnostic = {
        code: reader.string(),
        subject: reader.string(),
        message: reader.string(),
      };
      reader.finish();
      throw new CompilerError(diagnostic);
    }
    case "analyze":
      response = { operation: kind, analysis: reader.read(reader.analysis) };
      break;
    case "compile":
      response = { operation: kind, artifact: reader.read(reader.artifact) };
      break;
    case "compileEcs":
      response = { operation: kind, artifact: reader.read(reader.ecsArtifact) };
      break;
  }
  reader.finish();
  return response;
}
