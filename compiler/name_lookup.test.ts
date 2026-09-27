import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Result = { readonly $: "Done"; readonly value: Node } | {
  readonly $: "Fail";
  readonly error: Node;
};
type Lookup = (bindings: BendList<Node>, name: string) => Result;
const backend = compiled as unknown as {
  "wasm.lookup_local": Lookup;
  "const_eval.lookup_local": Lookup;
  "const_eval.lookup_constant": Lookup;
  "const_eval.lookup_function": Lookup;
};
const lookups = [
  {
    name: "Wasm locals",
    lookup: backend["wasm.lookup_local"],
    binding(name: string, value: number): Node {
      return {
        $: "wasm.Local",
        name,
        location: {
          $: "wasm.Location",
          local: BigInt(value),
          offsets: bendList([]),
        },
      };
    },
    value(binding: Node): Node {
      return binding.location as Node;
    },
    message: "Wasm lowering lost a lexical local",
  },
  {
    name: "constant evaluator locals",
    lookup: backend["const_eval.lookup_local"],
    binding(name: string, value: number): Node {
      return {
        $: "const_eval.Binding",
        name,
        value: { $: "const_eval.U32Value", value },
      };
    },
    value(binding: Node): Node {
      return binding.value as Node;
    },
    message: "const evaluator lost a checked local",
  },
  {
    name: "constant declarations",
    lookup: backend["const_eval.lookup_constant"],
    binding(name: string, value: number): Node {
      return {
        $: "model.Constant",
        name,
        exported: { $: "False" },
        annotation: { $: "None" },
        value: { $: "model.U32Expr", value },
      };
    },
    value(binding: Node): Node {
      return binding.value as Node;
    },
    message: "const evaluator lost a checked constant",
  },
  {
    name: "constant evaluator functions",
    lookup: backend["const_eval.lookup_function"],
    binding(name: string, value: number): Node {
      return {
        $: "model.Function",
        name,
        exported: { $: "False" },
        parameter: "argument",
        parameter_type: { $: "None" },
        result_type: { $: "None" },
        body: { $: "model.U32Expr", value },
      };
    },
    value(binding: Node): Node {
      return binding;
    },
    message: "const evaluator lost a checked function",
  },
];

for (const scan of lookups) {
  Deno.test(`${scan.name} retain first-match semantics and missing-name diagnostics in deep scopes`, () => {
    const first = scan.binding("target", 42);
    const last = scan.binding("target", 99);
    const middle = Array.from(
      { length: 10000 },
      (_, index) => scan.binding(`binding_${index}`, index),
    );
    const bindings = bendList([first, ...middle, last]);
    equal(scan.lookup(bindings, "target"), {
      $: "Done",
      value: scan.value(first),
    });
    equal(scan.lookup(bindings, "binding_9999"), {
      $: "Done",
      value: scan.value(middle[9999]),
    });
    equal(scan.lookup(bindings, "missing"), {
      $: "Fail",
      error: {
        $: "model.Diagnostic",
        code: "internal_error",
        subject: "missing",
        message: scan.message,
      },
    });
  });
}
