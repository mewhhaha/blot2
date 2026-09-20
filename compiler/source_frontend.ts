import { CompilerError } from "./diagnostics.ts";
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

export async function createSourceFrontend(
  options: SourceCompilerOptions = {},
) {
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
  return {
    prepare(source: string) {
      const parsed = frontend.parse(source);
      return {
        root: shifted(parsed.root, BigInt(sourceBase)),
        nodeCount: parsed.nodeCount + prelude.nodeCount,
        prelude: prelude.root,
        translate(error: unknown): never {
          if (!(error instanceof CompilerError)) throw error;
          if (error.subject.startsWith("offset:")) {
            const offset = Number(error.subject.slice(7));
            if (offset < sourceBase) {
              throw new SourceError(error.code, error.detail, offset, offset, {
                filename: "std/prelude.blot",
                source: preludeSource,
              });
            }
            throw new SourceError(
              error.code,
              error.detail,
              offset - sourceBase,
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
          throw new SourceError(
            error.code,
            error.detail,
            declarationOffsets(parsed.root).get(
              error.subject.startsWith("main::")
                ? error.subject.slice(6)
                : error.subject,
            ) ?? 0,
          );
        },
      };
    },
    dispose() {
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
