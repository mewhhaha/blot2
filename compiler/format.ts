import { createFrontend, type Cst } from "./syntax.ts";

function children(node: Cst): Cst[] {
  const result: Cst[] = [];
  for (let list = node.children; list.$ === "Con"; list = list.tail) {
    result.push(list.head);
  }
  return result;
}

const wrappers = new Set([
  "expression",
  "atom",
  "prefix_expression",
  "infix_expression",
  "application",
]);

function expressionCore(node: Cst): Cst {
  const nested = children(node);
  const values = nested.filter((child) => child.field === "value");
  if (node.kind === "group" && values.length === 1) {
    return expressionCore(values[0]);
  }
  return wrappers.has(node.kind) && nested.length === 1
    ? expressionCore(nested[0])
    : node;
}

// These parentheses form an application or operator boundary in the CST.
// Removing them cannot pass the structural check below. Excluding them first
// avoids repeatedly parsing a whole file to rediscover the same boundary.
function needsGrouping(group: Cst, parents: Map<Cst, Cst>): boolean {
  const kind = expressionCore(group).kind;
  const compound = [
    "application",
    "infix_expression",
    "prefix_expression",
    "lambda",
    "if_expression",
    "case_expression",
    "do_block",
  ].includes(kind);
  if (!compound) return false;
  for (let node = parents.get(group); node; node = parents.get(node)) {
    const nested = children(node);
    if (node.kind === "group") return false;
    if (node.kind === "type_witness") return true;
    if (node.kind === "application") {
      if (nested.some((child) => child.field === "arguments")) return true;
    } else if (node.kind === "infix_expression") {
      if (nested.some((child) => child.field === "tails")) {
        return kind !== "application";
      }
    } else if (wrappers.has(node.kind)) {
      if (nested.length > 1) return true;
    } else return false;
  }
  return false;
}

// Ignore wrappers that carry no grouping information. Keep application,
// indexing and infix tree boundaries so removing parentheses cannot change
// argument binding or arithmetic evaluation order.
function structure(node: Cst): unknown {
  const nested = children(node).filter((child) =>
    !child.kind.startsWith("LAYOUT_") &&
    !(node.kind === "data_type" && child.text === "|")
  );
  const values = nested.filter((child) => child.field === "value");
  if (node.kind === "group" && values.length === 1) return structure(values[0]);
  if (wrappers.has(node.kind) && nested.length === 1) {
    return structure(nested[0]);
  }
  return [
    node.kind,
    node.text,
    nested.map((child) => [child.field, structure(child)]),
  ];
}

function span(node: Cst): [number, number] {
  const nested = children(node).filter((child) =>
    !child.kind.startsWith("LAYOUT_")
  );
  if (!nested.length) {
    return [Number(node.offset), Number(node.offset) + node.text.length];
  }
  const ranges = nested.map(span);
  return [
    Math.min(...ranges.map(([start]) => start)),
    Math.max(...ranges.map(([, end]) => end)),
  ];
}

/** Format Blot while checking that application and evaluation order stay intact. */
export async function formatSource(source: string): Promise<string> {
  const frontend = await createFrontend();
  try {
    source = source.replace(/\r\n|\r/g, "\n");
    let original = frontend.parse(source).root;
    const expected = JSON.stringify(structure(original));
    const equivalent = (candidate: string) => {
      try {
        return JSON.stringify(structure(frontend.parse(candidate).root)) ===
          expected;
      } catch {
        return false;
      }
    };
    // Break long data alternatives into one visible group per constructor.
    const declarations: { start: number; end: number; text: string }[] = [];
    const groups: [number, number][] = [];
    const work = [original];
    const parents = new Map<Cst, Cst>();
    for (let node = work.pop(); node; node = work.pop()) {
      const nested = children(node);
      for (const child of nested) parents.set(child, node);
      work.push(...nested);
      if (
        node.kind === "group" &&
        nested.filter((child) => child.field === "value").length === 1
      ) {
        const [start, end] = span(node);
        if (
          !source.slice(start, end).includes("\n") &&
          !needsGrouping(node, parents)
        ) {
          groups.push([start, end - 1]);
        }
      }
      if (node.kind !== "data_type") continue;
      const variants = nested.filter((child) => child.field === "constructors");
      const [start, end] = span(node);
      const text = source.slice(start, end);
      if (variants.length < 2 || (!text.includes("\n") && text.length <= 80)) {
        continue;
      }
      const first = span(variants[0])[0];
      const header = source.slice(start, first).replace(/\s*\|?\s*$/, "");
      const lines = variants.map((variant) => {
        const [a, b] = span(variant);
        const base =
          /^ */.exec(source.slice(source.lastIndexOf("\n", a - 1) + 1, a))![0]
            .length;
        const parts = source.slice(a, b).split("\n");
        return "  | " + parts[0] +
          parts.slice(1).map((line) =>
            "\n" + "  " +
            line.slice(Math.min(base, /^ */.exec(line)![0].length))
          ).join("");
      });
      // Comments between variants retain their original placement.
      if (text.includes("//")) continue;
      declarations.push({ start, end, text: header + "\n" + lines.join("\n") });
    }
    // Try removals in batches. Failed batches split until only parentheses
    // that change the parsed expression are left, avoiding a parse per pair
    // when a file contains many redundant wrappers.
    const removed = new Set<number>();
    const without = (positions: Set<number>) => {
      let result = "", cursor = 0;
      for (const at of [...positions].sort((a, b) => a - b)) {
        result += source.slice(cursor, at);
        cursor = at + 1;
      }
      return result + source.slice(cursor);
    };
    const simplify = (pairs: [number, number][]) => {
      if (!pairs.length) return;
      const candidate = new Set(removed);
      for (const [open, close] of pairs) {
        candidate.add(open);
        candidate.add(close);
      }
      if (equivalent(without(candidate))) {
        for (const at of candidate) removed.add(at);
      } else if (pairs.length > 1) {
        const half = Math.floor(pairs.length / 2);
        simplify(pairs.slice(0, half));
        simplify(pairs.slice(half));
      }
    };
    simplify(groups);
    // Apply the edits against the same original offsets.
    for (const edit of declarations.sort((a, b) => b.start - a.start)) {
      for (const at of removed) {
        if (at >= edit.start && at < edit.end) removed.delete(at);
      }
    }
    const edits = [
      ...declarations,
      ...[...removed].map((start) => ({ start, end: start + 1, text: "" })),
    ];
    let laidOut = source;
    for (const edit of edits.sort((a, b) => b.start - a.start)) {
      laidOut = laidOut.slice(0, edit.start) + edit.text +
        laidOut.slice(edit.end);
    }
    if (equivalent(laidOut)) source = laidOut;
    original = frontend.parse(source).root;
    const tightAfter = new Set<number>();
    const witness = new Set<number>();
    const pending = [original];
    for (let node = pending.pop(); node; node = pending.pop()) {
      const nested = children(node);
      pending.push(...nested);
      if (["type_witness", "value_pattern"].includes(node.kind)) {
        tightAfter.add(Number(node.offset));
        witness.add(Number(node.offset));
      }
      if (node.kind === "prefix_expression") {
        for (const child of nested) {
          if (child.field === "operator") tightAfter.add(Number(child.offset));
        }
      }
      if (node.kind === "named_operator") {
        for (const child of nested) {
          if (child.text === "`") tightAfter.add(Number(child.offset));
        }
      }
    }
    const lexed = frontend.lex(source);
    const lines = source.replace(/\r\n|\r/g, "\n").split("\n");
    const output: string[] = [];
    let cursor = 0;
    let line = 0;
    let text = "";
    let previous: { text: string; start: number; end: number } | undefined;
    let backtick = false;
    for (let index = 0; index < lexed.tokenTape.length; index++) {
      const token = lexed.tokenTape.token(index)!;
      if (
        token.type === "eof" ||
        (token.type === "named" && token.kind === "WHITESPACE")
      ) continue;
      const breaks =
        (source.slice(cursor, token.span.start).match(/\r\n|\r|\n/g) ?? [])
          .length;
      if (breaks) {
        if (text.trim()) output.push(text.trimEnd());
        if (breaks > 1 && output.length && output.at(-1) !== "") {
          output.push("");
        }
        line += breaks;
        text = "";
        previous = undefined;
      }
      if (!text) text = /^[ ]*/.exec(lines[line] ?? "")![0];
      const value = token.text;
      const comment = token.type === "named" && token.kind === "COMMENT";
      let space = previous !== undefined;
      if (previous) {
        const adjacent = previous.end === token.span.start;
        if (comment) {
          text = text.trimEnd() + "  ";
          space = false;
        } else if ([")", "]", ","].includes(value)) space = false;
        else if (value === ":" && !witness.has(token.span.start)) space = false;
        else if (["(", "["].includes(previous.text)) space = false;
        else if (["(", "["].includes(value)) space = !adjacent;
        else if (value === ".") space = !adjacent;
        else if (
          previous.text === "." || previous.text === "~" ||
          previous.text === "#"
        ) space = false;
        else if (tightAfter.has(previous.start)) space = false;
        else if (value === "}" && previous.text === "{") space = false;
        if (value === "`") {
          if (backtick) space = false;
          backtick = !backtick;
        } else if (backtick) space = false;
      }
      if (space) text += " ";
      text += value;
      previous = { text: value, start: token.span.start, end: token.span.end };
      cursor = token.span.end;
    }
    if (text.trim()) output.push(text.trimEnd());
    const formatted = output.join("\n").trimEnd() + "\n";
    if (
      !equivalent(formatted)
    ) {
      throw new Error(
        "Formatting would change the parsed program; the source was left unchanged",
      );
    }
    return formatted;
  } finally {
    frontend.dispose();
  }
}
