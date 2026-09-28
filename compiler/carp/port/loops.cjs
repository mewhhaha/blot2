/** Representation-aware implementations of pure structural operations.
 * The semantic input is hash-locked before these transformations are selected.
 * These are regenerated as Carp, not implemented in the C runtime. */
"use strict";
module.exports = {
  // String is a flat UTF-16 value in this port. Scalar-by-scalar equality of
  // valid strings is exactly code-unit equality (without normalization). Avoid
  // allocating head/tail views and a NameComparison record for each lookup.
  // Kept here, in generated Carp, rather than as a Blot rule in the C runtime.
  "$$$$047model$name_equal$": `function $$$$047model$name_equal$(left, right) {
    return left === right;
  }`,
  "$List$length$": `function $List$length$(xs) {
    let count = 0;
    for (;;) {
      if (xs.$ === "Nil") return count;
      xs = xs.tail;
      count = nat_chk(count + 1);
      continue;
    }
  }`,
  "$List$append$": `function $List$append$(xs, ys) {
    let rest = $List$reverse$(xs);
    for (;;) {
      if (rest.$ === "Nil") return ys;
      ys = {$: "Con", head: rest.head, tail: ys};
      rest = rest.tail;
      continue;
    }
  }`,
  "$List$take$": `function $List$take$(xs, n) {
    let reversed = {$: "Nil"};
    for (;;) {
      if (xs.$ === "Nil" || n === 0) return $List$reverse$(reversed);
      reversed = {$: "Con", head: xs.head, tail: reversed};
      xs = xs.tail;
      n = n - 1;
      continue;
    }
  }`,
  "$List$replicate$": `function $List$replicate$(n, x) {
    let result = {$: "Nil"};
    for (;;) {
      if (n === 0) return result;
      result = {$: "Con", head: x, tail: result};
      n = n - 1;
      continue;
    }
  }`,
  "$List$sort$runs$": `function $List$sort$runs$(xs) {
    let reversed = {$: "Nil"};
    for (;;) {
      if (xs.$ === "Nil") return $List$reverse$(reversed);
      reversed = {$: "Con", head: {$: "Con", head: xs.head, tail: {$: "Nil"}}, tail: reversed};
      xs = xs.tail;
      continue;
    }
  }`,
  "$List$concat$": `function $List$concat$(xss) {
    let reversed = {$: "Nil"};
    for (;;) {
      if (xss.$ === "Nil") return $List$reverse$(reversed);
      reversed = $List$reverse$go$(xss.head, reversed);
      xss = xss.tail;
      continue;
    }
  }`,
  // The native decoder validates a scalar before it can become string data.
  // Bend's JS emitter constructs Chr eagerly here; reproducing that eagerness
  // would abort a malformed request instead of returning its protocol diagnostic.
  "$$$$047native_request$character_read$":
    `function $$$$047native_request$character_read$(read, offset, remaining, reversed, strings, string_count) {
    const code = read.snd;
    const valid = code <= 1114111 && (code < 55296 || code > 57343);
    return {$: "../native_request.CharacterScan",
      cursor: {$: "../native_request.Cursor", words: read.fst, offset: offset,
        remaining: remaining, strings: strings, string_count: string_count},
      reversed: valid ? char_new(code) + reversed : reversed,
      valid: valid};
  }`,
};
