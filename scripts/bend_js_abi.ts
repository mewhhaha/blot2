/**
 * Bend 2.0.27's js_expr(Ctr) and js_match use name_own(k, adt type), yielding
 * the constructor's short name in this compiler. Bend 2.0.28 emits k itself.
 * The compiler's existing JS FFI and pure regression fixtures use the 2.0.27
 * tags. Short names may collide across modules; the generated matches are
 * type directed, exactly as they were in 2.0.27.
 *
 * This lexer changes only emitted Data tag literals (`{$: "module.Ctor"}`)
 * and tag comparisons (`value.$ === "module.Ctor"`). It leaves ordinary
 * strings, regexes, templates, comments, function export names and fields
 * untouched. New emitter syntax fails closed instead of silently producing a
 * mixed ABI.
 */

interface Token {
  readonly kind: "identifier" | "string" | "punct" | "barrier";
  readonly text: string;
  readonly start: number;
  readonly end: number;
}

interface Edit {
  readonly start: number;
  readonly end: number;
  readonly replacement: string;
}

export interface NormalizedBendJs {
  readonly source: string;
  readonly constructors: number;
  readonly matches: number;
}

function fail(message: string): never {
  throw new Error(`Unsupported Bend JS Data tag syntax: ${message}`);
}

function identifierStart(character: string | undefined): boolean {
  return character !== undefined && /[A-Za-z_$]/.test(character);
}

function identifierPart(character: string | undefined): boolean {
  return character !== undefined && /[A-Za-z0-9_$]/.test(character);
}

function digit(character: string | undefined): boolean {
  return character !== undefined && /[0-9]/.test(character);
}

function regexCanStart(previous: Token | undefined): boolean {
  if (!previous) return true;
  if (previous.kind === "barrier") return true;
  if (previous.kind === "identifier") {
    return ["return", "throw", "case", "yield", "await", "else", "do"].includes(
      previous.text,
    );
  }
  return ["=", "(", "[", "{", ",", ":", ";", "=>", "!", "?", "&&", "||"]
    .includes(
      previous.text,
    );
}

function tokenize(
  source: string,
  inspect: (token: Token, recent: readonly Token[]) => void,
) {
  const recent: Token[] = [];
  const controlParentheses: boolean[] = [];
  let afterControlClose = false;
  let cursor = 0;

  function emit(token: Token) {
    inspect(token, recent);
    if (token.text === "(") {
      controlParentheses.push(
        recent.at(-1)?.kind === "identifier" &&
          ["if", "while", "for", "with", "catch", "switch"].includes(
            recent.at(-1)?.text ?? "",
          ),
      );
      afterControlClose = false;
    } else if (token.text === ")") {
      afterControlClose = controlParentheses.pop() === true;
    } else {
      afterControlClose = false;
    }
    recent.push(token);
    if (recent.length > 3) recent.shift();
  }

  function barrier(start: number, end: number) {
    emit({ kind: "barrier", text: "", start, end });
  }

  function quoted(quote: "'" | '"') {
    const start = cursor++;
    while (cursor < source.length) {
      if (source[cursor] === "\\") {
        cursor += 2;
      } else if (source[cursor++] === quote) {
        emit({
          kind: "string",
          text: source.slice(start, cursor),
          start,
          end: cursor,
        });
        return;
      }
    }
    fail("unterminated string literal");
  }

  function regex() {
    const start = cursor++;
    let inClass = false;
    while (cursor < source.length) {
      const character = source[cursor++];
      if (character === "\\") {
        cursor++;
      } else if (character === "[") {
        inClass = true;
      } else if (character === "]") {
        inClass = false;
      } else if (character === "/" && !inClass) {
        while (identifierPart(source[cursor])) cursor++;
        barrier(start, cursor);
        return;
      }
    }
    fail("unterminated regular expression literal");
  }

  function template() {
    const start = cursor++;
    barrier(start, cursor);
    while (cursor < source.length) {
      if (source[cursor] === "\\") {
        cursor += 2;
      } else if (source[cursor] === "`") {
        cursor++;
        barrier(start, cursor);
        return;
      } else if (source[cursor] === "$" && source[cursor + 1] === "{") {
        cursor += 2;
        barrier(start, cursor);
        code(true);
        barrier(start, cursor);
      } else {
        cursor++;
      }
    }
    fail("unterminated template literal");
  }

  function code(interpolation: boolean) {
    let depth = 0;
    while (cursor < source.length) {
      const start = cursor;
      const character = source[cursor];
      if (/\s/.test(character)) {
        cursor++;
      } else if (character === "/" && source[cursor + 1] === "/") {
        cursor += 2;
        while (cursor < source.length && source[cursor] !== "\n") cursor++;
      } else if (character === "/" && source[cursor + 1] === "*") {
        cursor += 2;
        const close = source.indexOf("*/", cursor);
        if (close < 0) fail("unterminated block comment");
        cursor = close + 2;
      } else if (character === "'" || character === '"') {
        quoted(character);
      } else if (character === "`") {
        template();
      } else if (character === "/" && afterControlClose) {
        regex();
      } else if (
        character === "/" && ["]", "}"].includes(recent.at(-1)?.text ?? "")
      ) {
        // These ambiguous positions do not occur in the supported emitter.
        // Reject them rather than interpreting regex contents as JS code.
        fail("ambiguous slash after closing delimiter");
      } else if (character === "/" && regexCanStart(recent.at(-1))) {
        regex();
      } else if (interpolation && character === "}" && depth === 0) {
        cursor++;
        return;
      } else if (identifierStart(character)) {
        cursor++;
        while (identifierPart(source[cursor])) cursor++;
        emit({
          kind: "identifier",
          text: source.slice(start, cursor),
          start,
          end: cursor,
        });
      } else if (digit(character)) {
        cursor++;
        while (/[A-Za-z0-9_.]/.test(source[cursor] ?? "")) cursor++;
        emit({
          kind: "punct",
          text: source.slice(start, cursor),
          start,
          end: cursor,
        });
      } else {
        const operator = ["===", "!==", "=>", "==", "!=", "&&", "||"]
          .find((candidate) => source.startsWith(candidate, cursor));
        cursor += operator?.length ?? 1;
        const text = operator ?? character;
        emit({ kind: "punct", text, start, end: cursor });
        if (interpolation && text === "{") depth++;
        if (interpolation && text === "}") depth--;
      }
    }
    if (interpolation) fail("unterminated template interpolation");
  }

  code(false);
}

function tag(token: Token): string | undefined {
  if (token.kind !== "string") return undefined;
  if (token.text[0] !== '"') {
    // A qualified single-quoted tag is an unsupported emitter form.
    return token.text.slice(1, -1).includes(".")
      ? token.text.slice(1, -1)
      : undefined;
  }
  let value: string;
  try {
    value = JSON.parse(token.text) as string;
  } catch {
    fail("invalid double-quoted string literal");
  }
  return value.includes(".") ? value : undefined;
}

function form(recent: readonly Token[]):
  | { readonly shape: "constructor" | "match"; readonly valid: boolean }
  | undefined {
  if (recent.at(-1)?.text === ":" && recent.at(-2)?.text === "$") {
    return {
      shape: "constructor",
      valid: ["{", ","].includes(recent.at(-3)?.text ?? ""),
    };
  }
  if (recent.at(-2)?.text === "$" && recent.at(-3)?.text === ".") {
    return { shape: "match", valid: recent.at(-1)?.text === "===" };
  }
  if (
    recent.at(-1)?.text === ":" && recent.at(-2)?.text === '"$"' ||
    ["===", "==", "!==", "!="].includes(recent.at(-1)?.text ?? "") &&
      recent.at(-2)?.text === "]" &&
      recent.at(-3)?.text === '"$"'
  ) {
    return { shape: "match", valid: false };
  }
  return undefined;
}

function shortName(qualified: string): string {
  const pieces = qualified.split(".");
  if (
    pieces.length !== 2 ||
    !/^[a-z_][A-Za-z0-9_]*$/.test(pieces[0]) ||
    !/^[A-Z][A-Za-z0-9_]*$/.test(pieces[1])
  ) {
    fail(`qualified constructor ${JSON.stringify(qualified)}`);
  }
  return pieces[1];
}

/** Normalize an upstream JS module before publication, without running it. */
export function normalizeBendJsAbi(
  source: string,
  version: string,
): NormalizedBendJs {
  if (version !== "bend 2.0.27" && version !== "bend 2.0.28") {
    throw new Error(`Unsupported Bend JS ABI version: ${version}`);
  }
  const edits: Edit[] = [];
  let constructors = 0;
  let matches = 0;
  tokenize(source, (token, recent) => {
    if (token.kind !== "string") return;
    const found = form(recent);
    if (!found) return;
    const qualified = tag(token);
    if (!qualified) return;
    if (!found.valid) fail(`invalid ${found.shape} Data tag form`);
    if (version === "bend 2.0.27") {
      fail(`2.0.27 emitted a qualified ${found.shape}`);
    }
    if (token.text[0] !== '"' || token.text !== JSON.stringify(qualified)) {
      fail(`escaped or single-quoted ${found.shape} tag`);
    }
    edits.push({
      start: token.start,
      end: token.end,
      replacement: JSON.stringify(shortName(qualified)),
    });
    if (found.shape === "constructor") constructors++;
    else matches++;
  });
  if (version === "bend 2.0.28" && (constructors === 0 || matches === 0)) {
    fail(
      "2.0.28 module lacks the expected qualified constructor and match forms",
    );
  }
  let result = "";
  let cursor = 0;
  for (const edit of edits) {
    result += source.slice(cursor, edit.start) + edit.replacement;
    cursor = edit.end;
  }
  result += source.slice(cursor);
  return { source: result, constructors, matches };
}
