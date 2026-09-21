import { CompilerError } from "./diagnostics.ts";
import { bendList } from "./bend_list.ts";
import type { SourceInput, SourceModule } from "./source_project.ts";
import { SyntaxWorkers } from "./syntax_workers.ts";
import {
  encodeCstChunk,
  encodeNativeChunks,
  encodeNativeRequest,
  type NativeCstChunk,
  type NativeOperation,
} from "./native_protocol.ts";
import {
  createFrontend,
  type Cst,
  type CstList,
  SourceError,
} from "./syntax.ts";

export function declarationOffsets(root: Cst): Map<string, number> {
  const offsets = new Map<string, number>();
  const field = (node: Cst, label: string): Cst | undefined => {
    for (let child = node.children; child.$ === "Con"; child = child.tail) {
      if (child.head.field === label) return child.head;
    }
    return undefined;
  };
  for (
    let declaration = root.children;
    declaration.$ === "Con";
    declaration = declaration.tail
  ) {
    const value = field(declaration.head, "value");
    const node = value && field(value, "name");
    if (!node) continue;
    let name = node.text;
    for (let child = node.children; child.$ === "Con"; child = child.tail) {
      name += child.head.text;
    }
    if (!offsets.has(name)) offsets.set(name, Number(node.offset));
  }
  return offsets;
}

function shifted(node: Cst, offset: bigint): Cst {
  const children: Cst[] = [];
  for (let child = node.children; child.$ === "Con"; child = child.tail) {
    children.push(shifted(child.head, offset));
  }
  let list: CstList = { $: "Nil" };
  for (let index = children.length - 1; index >= 0; index--) {
    list = { $: "Con", head: children[index], tail: list };
  }
  return { ...node, offset: node.offset + offset, children: list };
}

export interface SourceCompilerOptions {
  readonly prelude?: "default" | "none";
}

interface SourceOrigin {
  readonly name: string;
  readonly filename: string;
  readonly source: string;
  readonly base: number;
  readonly declarations: ReadonlyMap<string, number>;
}

export async function createSourceFrontend(
  options: SourceCompilerOptions & { readonly threads?: number } = {},
) {
  const workers = new SyntaxWorkers(options.threads ?? 1);
  const frontend = await createFrontend();
  let preludeSource = "";
  let prelude: ReturnType<typeof frontend.parse>;
  try {
    preludeSource = options.prelude === "none" ? "" : await Deno.readTextFile(
      new URL("../std/prelude.blot", import.meta.url),
    );
    prelude = frontend.parse(preludeSource);
  } catch (error) {
    frontend.dispose();
    if (error instanceof SourceError) {
      throw new SourceError(error.code, error.message, error.start, error.end, {
        filename: "std/prelude.blot",
        source: preludeSource,
      });
    }
    throw error;
  }
  const sourceBase = preludeSource.length + 1;
  const preludeOffsets = declarationOffsets(prelude.root);
  let nativePrelude: NativeCstChunk | undefined;
  let closed = false;
  function prepare(input: SourceInput) {
    if (closed) throw new Error("Source frontend is disposed");
    let units: readonly SourceModule[];
    if (typeof input === "string") {
      const prepared = frontend.prepare(input);
      units = [{
        name: "main",
        filename: "",
        source: input,
        ...frontend.parsePrepared(prepared, {
          offsetAt: (position) =>
            BigInt(prepared.originalOffsets[position] + sourceBase),
        }),
      }];
    } else {
      units = input.modules;
    }
    return finish(input, units);
  }
  function finish(input: SourceInput, units: readonly SourceModule[]) {
    let offset = sourceBase;
    const origins = units.map((unit) => {
      const declarations = declarationOffsets(unit.root);
      if (typeof input === "string") {
        for (const [name, position] of declarations) {
          declarations.set(name, position - sourceBase);
        }
      }
      const origin = {
        ...unit,
        base: offset,
        declarations,
      };
      offset += unit.source.length + 1;
      return origin;
    });
    const root: Cst = typeof input === "string" ? origins[0].root : {
      $: "Cst",
      kind: "source_project",
      field: "",
      text: input.entry,
      offset: BigInt(sourceBase),
      children: bendList(origins.map((unit) => ({
        $: "Cst" as const,
        kind: "source_module",
        field: "modules",
        text: unit.name,
        offset: BigInt(unit.base),
        children: bendList([{
          ...shifted(unit.root, BigInt(unit.base)),
          field: "body",
        }]),
      }))),
    };
    return {
      root,
      nodeCount: units.reduce(
        (count, unit) => count + unit.nodeCount + 2n,
        prelude.nodeCount,
      ),
      prelude: prelude.root,
      translate: translator(input, origins),
    };
  }
  function translator(input: SourceInput, origins: readonly SourceOrigin[]) {
    return (error: unknown): never => {
      if (!(error instanceof CompilerError)) throw error;
      if (error.subject.startsWith("offset:")) {
        const offset = Number(error.subject.slice(7));
        if (offset < sourceBase) {
          throw new SourceError(error.code, error.detail, offset, offset, {
            filename: "std/prelude.blot",
            source: preludeSource,
          });
        }
        const origin = origins.findLast((unit) => unit.base <= offset);
        if (!origin) {
          throw new Error(`Missing source origin for offset ${offset}`);
        }
        const local = offset - origin.base;
        throw new SourceError(
          error.code,
          error.detail,
          local,
          local,
          origin.filename
            ? { filename: origin.filename, source: origin.source }
            : undefined,
        );
      }
      const preludeDeclaration = error.subject.startsWith("$prelude.")
        ? error.subject.slice(9)
        : error.subject.startsWith("std/prelude::")
        ? error.subject.slice(13)
        : undefined;
      if (preludeDeclaration !== undefined) {
        const offset = preludeOffsets.get(preludeDeclaration) ?? 0;
        throw new SourceError(error.code, error.detail, offset, offset, {
          filename: "std/prelude.blot",
          source: preludeSource,
        });
      }
      for (const unit of origins) {
        const prefix = typeof input === "string" || unit.name === input.entry
          ? ""
          : `$module[${unit.name}].`;
        const declaration = error.subject.startsWith(`${unit.name}::`)
          ? error.subject.slice(unit.name.length + 2)
          : error.subject.startsWith(prefix)
          ? error.subject.slice(prefix.length)
          : undefined;
        const local = declaration === undefined
          ? undefined
          : unit.declarations.get(declaration);
        if (local !== undefined) {
          throw new SourceError(
            error.code,
            error.detail,
            local,
            local,
            unit.filename
              ? { filename: unit.filename, source: unit.source }
              : undefined,
          );
        }
      }
      throw new SourceError(error.code, error.detail, 0);
    };
  }
  return {
    prepare,
    async prepareNative(input: SourceInput) {
      if (closed) throw new Error("Source frontend is disposed");
      if (typeof input !== "string") {
        const prepared = prepare(input);
        return {
          encode: (operation: NativeOperation, const_steps: bigint) =>
            encodeNativeRequest({
              operation,
              const_steps,
              ...prepared,
              fuel: prepared.nodeCount,
            }),
          translate: prepared.translate,
        };
      }
      const parallel = await workers.encode(
        input,
        sourceBase,
        (range) =>
          frontend.encodePrepared(
            frontend.prepare(input.slice(range.start, range.end)),
            sourceBase + range.start,
          ),
      );
      if (closed) throw new Error("Source frontend is disposed");
      const chunks = parallel ??
        [frontend.encodePrepared(frontend.prepare(input), sourceBase)];
      nativePrelude ??= encodeCstChunk(prelude.root);
      const encodedPrelude = nativePrelude;
      const declarations = new Map<string, number>();
      for (const chunk of chunks) {
        for (const [name, offset] of chunk.declarations) {
          if (!declarations.has(name)) {
            declarations.set(name, offset - sourceBase);
          }
        }
      }
      return {
        encode: (operation: NativeOperation, const_steps: bigint) =>
          encodeNativeChunks({
            operation,
            const_steps,
            chunks: chunks.map((chunk) => chunk.cst),
            prelude: encodedPrelude,
          }),
        translate: translator(input, [{
          name: "main",
          filename: "",
          source: input,
          base: sourceBase,
          declarations,
        }]),
      };
    },
    dispose() {
      if (closed) return;
      closed = true;
      workers.dispose();
      frontend.dispose();
    },
  };
}

export function formatDiagnostic(
  filename: string,
  source: string,
  error: SourceError,
): string {
  if (error.origin) {
    filename = error.origin.filename;
    source = error.origin.source;
  }
  const prefix = source.slice(0, error.start);
  const lines = prefix.split(/\r\n|\r|\n/);
  return `${filename}:${lines.length}:${
    lines.at(-1)!.length + 1
  }: ${error.code}: ${error.message}`;
}
