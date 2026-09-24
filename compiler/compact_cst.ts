import type { CompactFrontendProgram } from "@mewhhaha/baba/runtime/webgpu";
import schema from "../generated/wasm/cst-schema.json" with { type: "json" };
import type { NativeCstChunk } from "./native_protocol.ts";

// Adjacency is lexical information: incremental offsets become stable identities.
// Record it before remapping positions, for both object and compact CST paths.
export function postfixStarts(program: CompactFrontendProgram, source: string) {
  const starts = new Set<number>();
  let previousEnd = -1;
  for (let token = 0; token < program.tokens.length; token += 4) {
    const kind = schema.tokens[program.tokens[token + 3]];
    if (kind === "WHITESPACE" || kind === "COMMENT") continue;
    const start = program.tokens[token + 1];
    if (
      previousEnd === start &&
      (source[start] === "[" || source[start] === "(")
    ) starts.add(start);
    previousEnd = program.tokens[token + 2];
  }
  return starts;
}

export interface EncodedSyntax {
  readonly cst: NativeCstChunk;
  readonly declarations: readonly (readonly [string, number])[];
  readonly hasImports: boolean;
  readonly hasDeclarations: boolean;
}

// Baba already owns a validated compact tree. Walk it directly into protocol
// words rather than allocating an object and a Bend list cell for every edge.
export function encodeCompactCst(
  program: CompactFrontendProgram,
  rules: ReadonlyMap<number, string>,
  source: string,
  offsets: ArrayLike<number>,
  sourceBase: number,
): EncodedSyntax {
  const adjacent = postfixStarts(program, source);
  let leaves = 0;
  for (let edge = 0; edge < program.edges.length; edge += 4) {
    if (program.edges[edge + 2] === 0) leaves++;
  }
  const words = new Uint32Array((program.nodes.length / 8 + leaves) * 6);
  const strings: string[] = [];
  const identities = new Map<string, number>();
  const identity = (text: string) => {
    let found = identities.get(text);
    if (found === undefined) {
      found = strings.length;
      identities.set(text, found);
      strings.push(text);
    }
    return found;
  };
  const offsetAt = (at: number) => {
    const offset = offsets[at];
    if (offset === undefined) throw new Error(`Missing source offset ${at}`);
    return offset + sourceBase;
  };
  const tokenText = (token: number) =>
    source.slice(program.tokens[token * 4 + 1], program.tokens[token * 4 + 2]);
  const fieldName = (field: number) => {
    const name = field < 0 ? "" : schema.fields[field];
    if (name === undefined) throw new Error(`Unknown Baba field ${field}`);
    return name;
  };
  const pending = [1, 0, -1];
  let position = 0;
  while (pending.length) {
    const field = fieldName(pending.pop()!);
    const target = pending.pop()!;
    const category = pending.pop()!;
    let kind: string;
    let text = "";
    let offset: number;
    let count = 0;
    if (category === 1) {
      const base = target * 8;
      const rule = rules.get(program.nodes[base]);
      if (rule === undefined) {
        throw new Error(`Unknown Baba rule ${program.nodes[base]}`);
      }
      const start = program.nodes[base + 2];
      kind = rule === "atom" && field === "arguments" && adjacent.has(start)
        ? "postfix_argument"
        : rule;
      offset = offsetAt(start);
      count = program.nodes[base + 5];
      for (let index = count - 1; index >= 0; index--) {
        const edge = (program.nodes[base + 4] + index) * 4;
        pending.push(
          program.edges[edge + 2],
          program.edges[edge + 3],
          program.edges[edge],
        );
      }
    } else if (category === 0) {
      text = tokenText(target);
      kind = schema.tokens[program.tokens[target * 4 + 3]] ?? text;
      offset = offsetAt(program.tokens[target * 4 + 1]);
    } else throw new Error(`Unknown Baba edge category ${category}`);
    words[position++] = identity(kind);
    words[position++] = identity(field);
    words[position++] = identity(text);
    words[position++] = offset >>> 0;
    words[position++] = Math.floor(offset / 0x100000000);
    words[position++] = count;
  }
  if (position !== words.length) {
    throw new Error("Baba compact tree node count mismatch");
  }

  const child = (node: number, field: string) => {
    const base = node * 8;
    for (let index = 0; index < program.nodes[base + 5]; index++) {
      const edge = (program.nodes[base + 4] + index) * 4;
      if (fieldName(program.edges[edge]) === field) return edge;
    }
    return undefined;
  };
  const declarations: [string, number][] = [];
  let hasImports = false;
  let hasDeclarations = false;
  for (let index = 0; index < program.nodes[5]; index++) {
    const edge = (program.nodes[4] + index) * 4;
    const field = fieldName(program.edges[edge]);
    hasImports ||= field === "imports";
    hasDeclarations ||= field === "declarations";
    if (program.edges[edge + 2] !== 1) continue;
    const value = child(program.edges[edge + 3], "value");
    if (value === undefined || program.edges[value + 2] !== 1) continue;
    const name = child(program.edges[value + 3], "name");
    if (name === undefined) continue;
    const target = program.edges[name + 3];
    if (program.edges[name + 2] === 0) {
      declarations.push([
        tokenText(target),
        offsetAt(program.tokens[target * 4 + 1]),
      ]);
    } else {
      const base = target * 8;
      let text = "";
      for (let at = 0; at < program.nodes[base + 5]; at++) {
        const part = (program.nodes[base + 4] + at) * 4;
        if (program.edges[part + 2] === 0) {
          text += tokenText(program.edges[part + 3]);
        }
      }
      declarations.push([text, offsetAt(program.nodes[base + 2])]);
    }
  }
  return { cst: { strings, words }, declarations, hasImports, hasDeclarations };
}
