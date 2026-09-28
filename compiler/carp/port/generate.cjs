#!/usr/bin/env node
/** Translate the pinned Bend pure semantic output into native Carp functions.
 * This is a regeneration tool, never part of compiler execution. Unknown syntax
 * is rejected instead of emitted approximately. Requires acorn 8.15.0 (MIT).
 */
"use strict";
const fs = require("node:fs"),
  path = require("node:path"),
  crypto = require("node:crypto");
const { parse, version: acornVersion } = require("./vendor/acorn.cjs");
const loops = require("./loops.cjs");
const carpNotice =
  "; Generated and modified from the pinned Blot/Bend semantic input.\n; See ../NOTICE and ../licenses for origin and license notices.\n";
const lock = JSON.parse(
  fs.readFileSync(path.join(__dirname, "reference.lock.json"), "utf8"),
);
if (acornVersion !== lock.acornVersion) {
  throw Error("generator requires Acorn " + lock.acornVersion);
}
const sha256 = (data) => crypto.createHash("sha256").update(data).digest("hex");
const input = process.argv[2], out = process.argv[3];
if (!input || !out) {
  throw Error("usage: node generate.cjs reference.mjs OUTPUT_DIRECTORY");
}
const source = fs.readFileSync(input, "utf8");
if (sha256(source) !== lock.semanticSha256) {
  throw Error("semantic input hash does not match reference.lock.json");
}
const ast = parse(source, { ecmaVersion: 2022, sourceType: "module" });
fs.mkdirSync(out, { recursive: true });
for (let i = 0; i < ast.body.length; i++) {
  const node = ast.body[i];
  if (node.type === "FunctionDeclaration" && loops[node.id.name]) {
    ast.body[i] = parse(loops[node.id.name], { ecmaVersion: 2022 }).body[0];
  }
}
const declarations = new Map(
  ast.body.filter((n) => n.type === "FunctionDeclaration").map(
    (n) => [n.id.name, n],
  ),
);
const primitiveNames = [
  "word_to_u32",
  "u32_to_word",
  "cmp_new",
  "nat_divmod",
  "nat_chk",
  "f32_bits",
  "f32_from_bits",
  "f32_read",
  "char_new",
  "array_new",
  "run_tail",
  "run_clo",
  "run_loop",
];
const primitives = new Set(primitiveNames);
const roots = ["$exchange$", "$initial$", "$protocol_version$"];
function walk(n, f) {
  if (!n || typeof n !== "object") return;
  if (n.type) f(n);
  for (const [k, v] of Object.entries(n)) {
    if (k === "type") continue;
    if (Array.isArray(v)) v.forEach((x) => walk(x, f));
    else walk(v, f);
  }
}
const reachable = new Set(), todo = [...roots];
while (todo.length) {
  const name = todo.pop();
  if (reachable.has(name) || primitives.has(name)) continue;
  const f = declarations.get(name);
  if (!f) throw Error(`missing function ${name}`);
  reachable.add(name);
  walk(f.body, (n) => {
    if (
      n.type === "Identifier" && declarations.has(n.name) &&
      !primitives.has(n.name)
    ) todo.push(n.name);
  });
}
const functions = ast.body.filter((n) =>
  n.type === "FunctionDeclaration" && reachable.has(n.id.name)
).map((n) => ({
  name: n.id.name,
  node: n,
  captures: [],
  arity: n.params.length,
}));
const names = new Map(functions.map((f, i) => [f.name, i]));
functions.forEach((f, i) => f.id = i);
const strings = [],
  strmap = new Map(),
  keys = [],
  keymap = new Map(),
  shapes = [],
  shapemap = new Map();
const intern = (s) => {
  if (!strmap.has(s)) {
    strmap.set(s, strings.length);
    strings.push(s);
  }
  return strmap.get(s);
};
const key = (s) => {
  if (!keymap.has(s)) {
    keymap.set(s, keys.length);
    keys.push(s);
  }
  return keymap.get(s);
};
const shape = (tag, fields) => {
  const v = JSON.stringify([tag, ...fields]);
  if (!shapemap.has(v)) {
    shapemap.set(v, shapes.length);
    shapes.push({ tag: intern(tag), keys: fields.map(key) });
  }
  return shapemap.get(v);
};
// Runtime primitives construct these ordinary data representations too.
for (
  const k of [
    "$",
    "length",
    "state",
    "packet",
    "word_count",
    "header",
    "blocks",
    "head",
    "tail",
    "words",
    "fst",
    "snd",
    "value",
  ]
) key(k);
for (
  const [tag, fields] of [
    ["Nil", []],
    ["Con", ["head", "tail"]],
    ["LT", []],
    ["EQ", []],
    ["GT", []],
    ["Tuple", ["fst", "snd"]],
    ["Some", ["value"]],
    ["None", []],
    ["WNil", []],
    ["WCon", ["head", "tail"]],
  ]
) shape(tag, fields);
intern("");
const opNames = [
  "+",
  "-",
  "*",
  "/",
  "%",
  "===",
  "!==",
  "==",
  "!=",
  "<",
  "<=",
  ">",
  ">=",
  "&",
  "|",
  "^",
  "<<",
  ">>",
  ">>>",
  "**",
];
const opId = new Map(opNames.map((v, i) => [v, i]));
const maximum = {
  call: 0,
  apply: 0,
  closure: 0,
  record: 0,
  tailcall: 0,
  tailapply: 0,
  callthen: 0,
};
function bits(n) {
  const b = Buffer.alloc(8);
  b.writeDoubleLE(n);
  return b.readBigInt64LE() + "l";
}
const TRUE = BigInt("0x7ffb000000000001") + "l",
  FALSE = BigInt("0x7ffb000000000000") + "l",
  NULL = BigInt("0x7ffa000000000000") + "l";
const arities = new Map(), arrows = new WeakMap();
function api(name, args) {
  arities.set(name, args.length);
  return `(${name}${args.length ? " " + args.join(" ") : ""})`;
}
function quote(s) {
  return JSON.stringify(s);
}
function localDecls(body) {
  let result = [];
  function go(n) {
    if (!n || typeof n !== "object") return;
    if (
      n.type === "ArrowFunctionExpression" || n.type === "FunctionExpression"
    ) return;
    if (n.type === "VariableDeclarator") {
      if (n.id.type !== "Identifier") {
        throw Error("destructuring not supported");
      }
      result.push(n.id.name);
    }
    for (const v of Object.values(n)) Array.isArray(v) ? v.forEach(go) : go(v);
  }
  go(body);
  return result;
}
function freeVars(fn) {
  const free = new Set();
  function go(n, bound) {
    if (!n || typeof n !== "object") return;
    if (n.type === "Identifier") {
      if (
        !bound.has(n.name) && !names.has(n.name) && !primitives.has(n.name) &&
        !["Math", "Infinity", "NaN", "undefined"].includes(n.name)
      ) free.add(n.name);
      return;
    }
    if (
      n.type === "FunctionDeclaration" ||
      n.type === "ArrowFunctionExpression" || n.type === "FunctionExpression"
    ) {
      const b = new Set(bound);
      for (const p of n.params) b.add(p.name);
      for (const v of localDecls(n.body)) b.add(v);
      go(n.body, b);
      return;
    }
    if (n.type === "MemberExpression") {
      go(n.object, bound);
      if (n.computed) go(n.property, bound);
      return;
    }
    if (n.type === "Property") {
      if (n.computed) go(n.key, bound);
      go(n.value, bound);
      return;
    }
    if (n.type === "VariableDeclarator") {
      go(n.init, bound);
      return;
    }
    for (const v of Object.values(n)) {
      if (Array.isArray(v)) v.forEach((x) => go(x, bound));
      else go(v, bound);
    }
  }
  go(fn, new Set());
  return [...free].sort();
}
let parallelSites = 0;
const parallelFunctions = new Set();
function emitFunction(info) {
  const env = new Map();
  let slots = 0, temp = 0;
  for (
    const name of [
      ...info.captures,
      ...info.node.params.map((p) => p.name),
    ]
  ) {
    if (env.has(name)) throw Error(`shadowed parameter ${name}`);
    env.set(name, slots++);
  }
  // Frames store owned values. Reuse slots across lexical scopes/alternative
  // branches, never across simultaneously live bindings. A closure copies its
  // captured values; it cannot retain the address of a frame slot. v-put drops
  // the previous value when a recycled slot is entered again (including loops).
  const addslot = (e) => {
    const slot = Math.max(-1, ...e.values()) + 1;
    slots = Math.max(slots, slot + 1);
    return slot;
  };
  function fail(n) {
    throw Error(
      `unsupported ${n.type} in ${info.name}: ${
        source.slice(n.start, n.end).slice(0, 240)
      }`,
    );
  }
  const read = (slot) => api("v-get", ["frame", String(slot)]);
  function expr(n, e) {
    if (!n) return NULL;
    switch (n.type) {
      case "Literal":
        if (typeof n.value === "number") return bits(n.value);
        if (typeof n.value === "boolean") return n.value ? TRUE : FALSE;
        if (typeof n.value === "string") {
          return api("v-literal", [String(intern(n.value))]);
        }
        if (n.value === null) return NULL;
        return fail(n);
      case "Identifier":
        if (e.has(n.name)) return read(e.get(n.name));
        if (names.has(n.name)) {
          return api("v-function", [String(names.get(n.name))]);
        }
        if (n.name === "Infinity") return bits(Infinity);
        if (n.name === "NaN") return bits(NaN);
        if (n.name === "undefined") return BigInt("0x7ffc000000000000") + "l";
        throw Error(`unknown identifier ${n.name} in ${info.name}`);
      case "BinaryExpression": {
        if (!opId.has(n.operator)) return fail(n);
        if (["===", "!==", "==", "!="].includes(n.operator)) {
          const pairs = [[n.left, n.right], [n.right, n.left]];
          for (const [field, literal] of pairs) {
            if (field.type === "MemberExpression" &&
                ((!field.computed && field.property.name === "$") ||
                 (field.computed && field.property.type === "Literal" && field.property.value === "$")) &&
                field.object.type === "Identifier" && e.has(field.object.name) &&
                literal.type === "Literal" && typeof literal.value === "string") {
              const test = api("v-local-tag", ["frame", String(e.get(field.object.name)),
                                                String(intern(literal.value))]);
              return n.operator === "!==" || n.operator === "!=" ? api("v-not", [test]) : test;
            }
          }
        }
        return api("v-binary", [
          String(opId.get(n.operator)),
          expr(n.left, e),
          expr(n.right, e),
        ]);
      }
      case "UnaryExpression":
        if (n.operator === "!") return api("v-not", [expr(n.argument, e)]);
        if (n.operator === "-") return api("v-neg", [expr(n.argument, e)]);
        if (n.operator === "~") return api("v-bitnot", [expr(n.argument, e)]);
        return fail(n);
      case "LogicalExpression": {
        if (!["&&", "||"].includes(n.operator)) return fail(n);
        const t = "logical" + temp++;
        const right = `(do (v-drop ${t}) ${expr(n.right, e)})`;
        return `(let [${t} ${expr(n.left, e)}] (if (v-truthy (v-keep ${t})) ${
          n.operator === "&&" ? right : t
        } ${n.operator === "&&" ? t : right}))`;
      }
      case "ConditionalExpression":
        return `(if (v-truthy ${expr(n.test, e)}) ${expr(n.consequent, e)} ${
          expr(n.alternate, e)
        })`;
      case "MemberExpression":
        if (
          !n.computed ||
          n.property.type === "Literal" && typeof n.property.value === "string"
        ) {
          const k = n.computed ? n.property.value : n.property.name;
          if (n.object.type === "Identifier" && e.has(n.object.name)) {
            return api("v-local-field", ["frame", String(e.get(n.object.name)), String(key(k))]);
          }
          return api("v-field", [expr(n.object, e), String(key(k))]);
        }
        return api("v-index", [expr(n.object, e), expr(n.property, e)]);
      case "ObjectExpression": {
        const props = n.properties;
        if (
          props.some((p) =>
            p.type !== "Property" || p.computed || p.kind !== "init" || p.method
          )
        ) return fail(n);
        const pairs = props.map(
          (p) => [
            p.key.type === "Identifier" ? p.key.name : p.key.value,
            p.value,
          ],
        );
        const tag = pairs.find(([k]) => k === "$");
        if (
          !tag || tag[1].type !== "Literal" || typeof tag[1].value !== "string"
        ) return fail(n);
        const rest = pairs.filter(([k]) => k !== "$"),
          id = shape(tag[1].value, rest.map(([k]) => k));
        maximum.record = Math.max(maximum.record, rest.length);
        return api(`v-record${rest.length}`, [
          String(id),
          ...rest.map(([, v]) => expr(v, e)),
        ]);
      }
      case "ArrowFunctionExpression": {
        if (n.async || n.params.some((p) => p.type !== "Identifier")) {
          return fail(n);
        }
        let id = arrows.get(n);
        if (id === undefined) {
          id = functions.length;
          const captures = freeVars(n);
          for (const k of captures) {
            if (!e.has(k)) throw Error(`bad capture ${k} in ${info.name}`);
          }
          const f = {
            name: `${info.name}/lambda@${n.start}`,
            id,
            node: n,
            captures,
            arity: n.params.length,
          };
          functions.push(f);
          arrows.set(n, id);
        }
        const f = functions[id];
        maximum.closure = Math.max(maximum.closure, f.captures.length);
        return api(`v-closure${f.captures.length}`, [
          String(id),
          ...f.captures.map((k) => expr({ type: "Identifier", name: k }, e)),
        ]);
      }
      case "CallExpression": {
        const c = n.callee;
        if (c.type === "Identifier" && names.has(c.name)) {
          const target = functions[names.get(c.name)];
          if (n.arguments.length > target.arity) {
            throw Error(
              `arity ${c.name} expected ${target.arity}, got ${n.arguments.length}`,
            );
          }
          maximum.call = Math.max(maximum.call, n.arguments.length);
          return api(`v-call${n.arguments.length}`, [
            String(target.id),
            ...n.arguments.map((v) => expr(v, e)),
          ]);
        }
        if (c.type === "Identifier" && primitives.has(c.name)) {
          return api(
            "v-" + c.name.replaceAll("_", "-"),
            n.arguments.map((v) => expr(v, e)),
          );
        }
        if (c.type === "MemberExpression" && !c.computed) {
          if (c.object.type === "Identifier" && c.object.name === "Math") {
            return api(
              "v-math-" + c.property.name,
              n.arguments.map((v) => expr(v, e)),
            );
          }
          if (c.property.name === "slice") {
            return api(`v-slice${n.arguments.length}`, [
              expr(c.object, e),
              ...n.arguments.map((v) => expr(v, e)),
            ]);
          }
          if (c.property.name === "codePointAt") {
            return api("v-codepoint", [
              expr(c.object, e),
              ...n.arguments.map((v) => expr(v, e)),
            ]);
          }
        }
        maximum.apply = Math.max(maximum.apply, n.arguments.length);
        return api(`v-apply${n.arguments.length}`, [
          expr(c, e),
          ...n.arguments.map((v) => expr(v, e)),
        ]);
      }
      case "ArrayExpression":
        if (n.elements.length === 1 && n.elements[0].type === "SpreadElement") {
          return api("v-spread", [expr(n.elements[0].argument, e)]);
        }
        return fail(n);
      case "SequenceExpression":
        return `(do ${
          n.expressions.slice(0, -1).map((v) => `(v-drop ${expr(v, e)})`).join(
            " ",
          )
        } ${expr(n.expressions.at(-1), e)})`;
      case "AssignmentExpression": {
        if (n.operator !== "=") return fail(n);
        if (n.left.type === "Identifier") {
          if (!e.has(n.left.name)) return fail(n);
          return api("v-assign", [
            "frame",
            String(e.get(n.left.name)),
            expr(n.right, e),
          ]);
        }
        if (n.left.type === "MemberExpression" && n.left.computed) {
          return api("v-set-index", [
            expr(n.left.object, e),
            expr(n.left.property, e),
            expr(n.right, e),
          ]);
        }
        return fail(n);
      }
      default:
        return fail(n);
    }
  }
  // Terminal applications transfer their owned arguments back to the native
  // dispatcher. Both static and captured-function tail calls keep a bounded
  // C stack, without interpreting bytecode or retaining a discarded frame.
  function tailExpr(n, e) {
    if (n?.type === "ConditionalExpression") {
      return `(if (v-truthy ${expr(n.test, e)}) ${tailExpr(n.consequent, e)} ${
        tailExpr(n.alternate, e)
      })`;
    }
    if (
      n?.type === "CallExpression" && n.callee.type === "Identifier" &&
      n.callee.name === "$Result$bind$" && n.arguments.length === 2
    ) {
      const first = n.arguments[0];
      const body = first?.type === "CallExpression" &&
          first.callee.type === "Identifier" &&
          first.callee.name === "run_loop" && first.arguments.length === 1
        ? first.arguments[0]
        : null;
      const continuation = n.arguments[1];
      const closure = continuation?.type === "CallExpression" &&
        continuation.callee.type === "Identifier" &&
        continuation.callee.name === "run_clo" &&
        continuation.arguments.length === 1 &&
        continuation.arguments[0].type === "ArrowFunctionExpression";
      if (
        body?.type === "CallExpression" && body.callee.type === "Identifier" &&
        names.has(body.callee.name) && closure
      ) {
        const target = functions[names.get(body.callee.name)];
        if (body.arguments.length > target.arity) {
          throw Error("deferred call arity mismatch");
        }
        maximum.callthen = Math.max(maximum.callthen, body.arguments.length);
        return api(`v-callthen${body.arguments.length}`, [
          String(target.id),
          String(names.get("$Result$bind$")),
          expr(continuation, e),
          ...body.arguments.map((argument) => expr(argument, e)),
        ]);
      }
    }
    if (n?.type === "CallExpression") {
      const callee = n.callee;
      if (callee.type === "Identifier" && names.has(callee.name)) {
        const target = functions[names.get(callee.name)];
        if (n.arguments.length > target.arity) {
          throw Error(`tail-call arity mismatch: ${callee.name}`);
        }
        maximum.tailcall = Math.max(maximum.tailcall, n.arguments.length);
        return api(`v-tailcall${n.arguments.length}`, [
          String(target.id),
          ...n.arguments.map((argument) => expr(argument, e)),
        ]);
      }
      if (callee.type === "Identifier" && e.has(callee.name)) {
        maximum.tailapply = Math.max(maximum.tailapply, n.arguments.length);
        return api(`v-tailapply${n.arguments.length}`, [
          expr(callee, e),
          ...n.arguments.map((argument) => expr(argument, e)),
        ]);
      }
    }
    return expr(n, e);
  }
  function sequence(nodes, e, mode, after) {
    if (!nodes.length) return after;
    const [n, ...rest] = nodes;
    // Restore the explicit fork/join boundaries of inference_batch.execute.
    // Only independent recursive calls cut by its weighted planner are scheduled.
    if (info.name.includes("inference_batch$execute$")) {
      const group = [];
      for (const node of nodes) {
        const d =
          node.type === "VariableDeclaration" && node.declarations.length === 1
            ? node.declarations[0]
            : null;
        if (
          !d || d.init?.type !== "CallExpression" ||
          d.init.callee.type !== "Identifier" ||
          d.init.callee.name !== info.name || d.init.arguments.length !== 2
        ) break;
        group.push(d);
      }
      if (group.length >= 2) {
        const bound = new Set(group.map((d) => d.id.name));
        for (const d of group) {
          for (const argument of d.init.arguments) {
            walk(argument, (x) => {
              if (x.type === "Identifier" && bound.has(x.name)) {
                throw Error("parallel argument depends on a sibling result");
              }
            });
          }
        }
        const ne = new Map(e), ops = [], pending = [];
        for (const d of group) {
          const slot = addslot(ne);
          pending.push(slot);
          ne.set(d.id.name, slot);
          ops.push(
            `(v-put frame ${slot} ${
              api("v-future2", [
                String(info.id),
                ...d.init.arguments.map((x) => expr(x, e)),
              ])
            })`,
          );
        }
        for (const slot of pending) {
          ops.push(`(v-put frame ${slot} ${api("v-await", [read(slot)])})`);
        }
        parallelSites++;
        parallelFunctions.add(info.id);
        return `(do ${ops.join(" ")} ${
          sequence(nodes.slice(group.length), ne, mode, after)
        })`;
      }
    }
    // Declarations must extend scope before compiling the following statements.
    if (n.type === "VariableDeclaration") {
      const ne = new Map(e), ops = [];
      for (const d of n.declarations) {
        const x = expr(d.init, ne), s = addslot(ne);
        ne.set(d.id.name, s);
        ops.push(`(v-put frame ${s} ${x})`);
      }
      return `(do ${ops.join(" ")} ${sequence(rest, ne, mode, after)})`;
    }
    // A continuation can be requested by both arms of a branch. Construct it
    // once: recomputing even an ultimately unused arm makes a sequence of
    // early-return conditions take exponential time during regeneration.
    let continuation;
    const next = () => continuation ??= sequence(rest, e, mode, after);
    switch (n.type) {
      case "BlockStatement":
        return sequence(n.body, new Map(e), mode, next());
      case "ReturnStatement":
        return mode
          ? `(do (set! result ${tailExpr(n.argument, e)}) (set! running false))`
          : tailExpr(n.argument, e);
      case "ContinueStatement":
        if (!mode || n.label) return fail(n);
        return "()";
      case "IfStatement":
        return `(if (v-truthy ${expr(n.test, e)}) ${
          sequence([n.consequent], new Map(e), mode, next())
        } ${
          n.alternate
            ? sequence([n.alternate], new Map(e), mode, next())
            : next()
        })`;
      case "ExpressionStatement":
        return `(do (v-drop ${expr(n.expression, e)}) ${next()})`;
      case "ForStatement":
        if (n.init || n.test || n.update || mode) return fail(n);
        return `(let [result ${NULL} running true] (do (while running ${
          sequence([n.body], new Map(e), true, "(v-unreachable-unit)")
        }) result))`;
      case "SwitchStatement": {
        const val = "switch" + temp++;
        let body = after;
        for (const c of [...n.cases].reverse()) {
          const arm = sequence(c.consequent, new Map(e), mode, after);
          if (c.test === null) body = arm;
          else {body = `(if (v-truthy (v-binary 5 (v-keep ${val}) ${
              expr(c.test, e)
            })) ${arm} ${body})`;}
        }
        const result = "switchResult" + temp++;
        return `(let [${val} ${
          expr(n.discriminant, e)
        } ${result} ${body}] (do (v-drop ${val}) ${result}))`;
      }
      case "EmptyStatement":
        return next();
      default:
        return fail(n);
    }
  }
  let body;
  if (info.node.body.type === "BlockStatement") {
    body = sequence(info.node.body.body, env, false, "(v-unreachable)");
  } else body = tailExpr(info.node.body, env);
  info.slots = slots;
  info.code =
    `; ${info.name}\n(meta-set! port${info.id} "sig" (Fn [(Ptr Long)] Long))\n(defn port${info.id} [frame]\n  ${body})\n`;
}
for (let i = 0; i < functions.length; i++) emitFunction(functions[i]);
// Include primitive/driver operations that can be absent from a given graph.
for (
  const [n, a] of [
    ["v-get", 2],
    ["v-put", 3],
    ["v-assign", 3],
    ["v-keep", 1],
    ["v-drop", 1],
    ["v-truthy", 1],
    ["v-unreachable", 0],
    ["v-unreachable-unit", 0],
    ["v-handshake", 1],
    ["v-receive", 0],
    ["v-request-length", 0],
    ["v-send", 1],
    ["v-has-frame", 1],
  ]
) arities.set(n, a);
for (let i = 0; i <= 3; i++) maximum.call = Math.max(maximum.call, i);
const returns = {
  "v-put": "()",
  "v-drop": "()",
  "v-truthy": "Bool",
  "v-unreachable-unit": "()",
  "v-handshake": "()",
  "v-send": "()",
  "v-has-frame": "Bool",
};
const reg = [];
function register(n, types, result) {
  reg.push(
    `(register ${n} (Fn [${types.join(" ")}] ${result}) "bp_${
      n.slice(2).replaceAll("-", "_")
    }")`,
  );
}
const fixedInt = {
  "v-get": [0, 1],
  "v-put": [0, 1],
  "v-assign": [0, 1],
  "v-local-field": [0, 1, 2],
  "v-local-tag": [0, 1, 2],
  "v-literal": [0],
  "v-function": [0],
  "v-binary": [0],
  "v-field": [1],
  "v-future2": [0],
};
for (const [n, a] of arities) {
  if (
    /^v-(call|apply|closure|record|tailcall|tailapply|callthen)\d+$/.test(n)
  ) continue;
  let types = Array(a).fill("Long");
  if (["v-get", "v-put", "v-assign", "v-local-field", "v-local-tag"].includes(n)) {
    types[0] = "(Ptr Long)";
  }
  for (const p of fixedInt[n] ?? []) {
    if (p !== 0 || !["v-get", "v-put", "v-assign", "v-local-field", "v-local-tag"].includes(n)) {
      types[p] = "Int";
    }
  }
  register(n, types, returns[n] ?? "Long");
}
for (
  const k of ["call", "apply", "closure", "record", "tailcall", "tailapply"]
) {
  for (let n = 0; n <= maximum[k]; n++) {
    register(`v-${k}${n}`, [
      ["apply", "tailapply"].includes(k) ? "Long" : "Int",
      ...Array(n).fill("Long"),
    ], "Long");
  }
}
for (let n = 0; n <= maximum.callthen; n++) {
  register(
    `v-callthen${n}`,
    ["Int", "Int", "Long", ...Array(n).fill("Long")],
    "Long",
  );
}
fs.writeFileSync(
  path.join(out, "bindings.carp"),
  carpNotice + '(system-include "runtime.h")\n' + reg.join("\n") + "\n",
);
// Modest translation units keep Carp's own type-checking/rebuild latency bounded.
const chunks = [];
let chunk = [], size = 0;
for (const f of functions) {
  if (size > 75000 && chunk.length) {
    chunks.push(chunk);
    chunk = [];
    size = 0;
  }
  chunk.push(f);
  size += f.code.length;
}
if (chunk.length) chunks.push(chunk);
for (const name of fs.readdirSync(out)) {
  if (/^unit[0-9]+\.carp$/.test(name)) fs.unlinkSync(path.join(out, name));
}
chunks.forEach((fs_, i) =>
  fs.writeFileSync(
    path.join(out, `unit${String(i).padStart(3, "0")}.carp`),
    carpNotice + `(load "bindings.carp")\n` + fs_.map((f) => f.code).join("\n"),
  )
);
let h = [
  "/* Generated and modified from Blot/Bend. See ../NOTICE. */",
  "#ifndef BLOT_PORT_TABLES_H",
  "#define BLOT_PORT_TABLES_H",
  `#define BP_FUNCTIONS ${functions.length}`,
  `#define BP_LITERALS ${strings.length}`,
  `#define BP_SHAPES ${shapes.length}`,
  `#define BP_MAX_ARGUMENTS ${
    Math.max(
      maximum.call,
      maximum.apply,
      maximum.tailcall,
      maximum.tailapply,
      maximum.callthen,
    )
  }`,
];
for (const [i, name] of keys.entries()) {
  h.push(
    `#define BP_KEY_${
      name === "$" ? "DOLLAR" : name.toUpperCase().replace(/[^A-Z0-9]/g, "_")
    } ${i}`,
  );
}
for (
  const tag of [
    "Nil",
    "Con",
    "LT",
    "EQ",
    "GT",
    "Tuple",
    "Some",
    "None",
    "WNil",
    "WCon",
  ]
) {
  const id = shapes.findIndex((s) => strings[s.tag] === tag);
  h.push(`#define BP_SHAPE_${tag.toUpperCase()} ${id}`);
}
for (
  const [n, name] of [["EXCHANGE", "$exchange$"], ["INITIAL", "$initial$"], [
    "VERSION",
    "$protocol_version$",
  ]]
) h.push(`#define BP_${n} ${names.get(name)}`);
h.push("#endif");
fs.writeFileSync(path.join(out, "tables.h"), h.join("\n") + "\n");
let table = [
  "/* Generated and modified from Blot/Bend. See ../NOTICE. */",
  '#include "runtime.h"',
];
functions.forEach((f) => table.push(`extern Long port${f.id}(Long *frame);`));
table.push("const BPFunction bp_functions[BP_FUNCTIONS] = {");
for (const f of functions) {
  table.push(
    `{port${f.id}, ${f.slots}, ${f.arity}, ${f.captures.length}, ${
      quote(f.name)
    }},`,
  );
}
table.push("};");
for (let i = 0; i < strings.length; i++) {
  const units = [];
  for (let j = 0; j < strings[i].length; j++) {
    units.push(strings[i].charCodeAt(j));
  }
  table.push(
    `static const uint16_t bp_text_${i}[] = {${
      units.length ? units.join(",") : 0
    }};`,
  );
}
table.push("BPLiteral bp_literals[BP_LITERALS] = {");
strings.forEach((s, i) => table.push(`{bp_text_${i}, ${s.length}, NULL},`));
table.push("};");
shapes.forEach((s, i) =>
  table.push(
    `static const uint32_t bp_keys_${i}[] = {${
      s.keys.length ? s.keys.join(",") : 0
    }};`,
  )
);
table.push("BPShape bp_shapes[BP_SHAPES] = {");
shapes.forEach((s, i) =>
  table.push(`{${s.tag}, ${s.keys.length}, bp_keys_${i}, NULL},`)
);
table.push("};");
fs.writeFileSync(path.join(out, "tables.c"), table.join("\n") + "\n");
const apih = ["/* Generated Blot/Bend calling convention. See ../NOTICE. */"],
  apic = ["/* Generated Blot/Bend calling convention. See ../NOTICE. */"];
for (
  const kind of ["call", "apply", "closure", "record", "tailcall", "tailapply"]
) {
  for (let n = 0; n <= maximum[kind]; n++) {
    const params = [
      `${["apply", "tailapply"].includes(kind) ? "Long" : "int"} id`,
      ...Array.from({ length: n }, (_, i) => `Long a${i}`),
    ].join(", ");
    apih.push(`Long bp_${kind}${n}(${params});`);
    apic.push(
      `Long bp_${kind}${n}(${params}) { Long values[${Math.max(1, n)}] = {${
        Array.from({ length: n }, (_, i) => "a" + i).join(",") || 0
      }}; return bp_${kind}(id, ${n}, values); }`,
    );
  }
}
for (let n = 0; n <= maximum.callthen; n++) {
  const params = [
    "int id",
    "int after",
    "Long continuation",
    ...Array.from({ length: n }, (_, i) => `Long a${i}`),
  ].join(", ");
  apih.push(`Long bp_callthen${n}(${params});`);
  apic.push(
    `Long bp_callthen${n}(${params}) { Long values[${Math.max(1, n)}] = {${
      Array.from({ length: n }, (_, i) => "a" + i).join(",") || 0
    }}; return bp_callthen(id, after, continuation, ${n}, values); }`,
  );
}
fs.writeFileSync(path.join(out, "calls.h"), apih.join("\n") + "\n");
fs.writeFileSync(path.join(out, "calls.inc"), apic.join("\n") + "\n");
const manifest = {
  format: 1,
  inputSha256: sha256(source),
  sourceCommit: lock.sourceCommit,
  sourceRewrites: Object.keys(loops),
  roots: Object.fromEntries(roots.map((k) => [k, names.get(k)])),
  functions: functions.length,
  topLevel: reachable.size,
  lambdas: functions.length - reachable.size,
  units: chunks.length,
  literals: strings.length,
  shapes: shapes.length,
  maximum,
  parallelSites,
  parallelFunctions: [...parallelFunctions],
};
fs.writeFileSync(
  path.join(out, "manifest.json"),
  JSON.stringify(manifest, null, 2) + "\n",
);
fs.writeFileSync(
  path.join(out, "driver.carp"),
  carpNotice +
    `(load "bindings.carp")\n; The transport owns bytes; all request decoding and language semantics are Carp.\n(defn port-serve []\n (let [state (v-call0 ${
      names.get("$initial$")
    }) incoming (v-receive)]\n  (do\n   (while (v-has-frame incoming)\n    (let [reply (v-run-loop (v-call3 ${
      names.get("$exchange$")
    } state incoming (v-request-length)))]\n     (do (set! state (v-field (v-keep reply) ${
      keymap.get("state")
    }))\n         (v-send (v-field reply ${
      keymap.get("packet")
    }))\n         (set! incoming (v-receive)))))\n   (v-drop state))))\n`,
);
manifest.generatorSha256 = sha256(fs.readFileSync(__filename));
manifest.vendorSha256 = sha256(
  fs.readFileSync(path.join(__dirname, "vendor/acorn.cjs")),
);
manifest.loopsSha256 = sha256(
  fs.readFileSync(path.join(__dirname, "loops.cjs")),
);
manifest.files = Object.fromEntries(
  fs.readdirSync(out).filter((name) => name !== "manifest.json").sort().map(
    (name) => [name, sha256(fs.readFileSync(path.join(out, name)))],
  ),
);
fs.writeFileSync(
  path.join(out, "manifest.json"),
  JSON.stringify(manifest, null, 2) + "\n",
);
console.log(
  JSON.stringify(
    { ...manifest, files: Object.keys(manifest.files).length },
    null,
    2,
  ),
);
