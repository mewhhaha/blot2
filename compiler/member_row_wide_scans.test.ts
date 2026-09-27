import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Maybe<T> = { readonly $: "None" } | {
  readonly $: "Some";
  readonly value: T;
};

const api = compiled as unknown as {
  "types.empty": () => Node;
  "monomorph.member_definition_count": (
    definitions: BendList<Node>,
    name: string,
  ) => bigint;
  "monomorph.first_recheckable_member": (
    candidates: BendList<bigint>,
    fixed: BendList<bigint>,
    hardFixed: BendList<bigint>,
    owned: BendList<string>,
    pending: BendList<Node>,
    substitutions: Node,
    definitions: BendList<Node>,
  ) => Maybe<bigint>;
  "monomorph.recheckable_member_answers": (
    answers: BendList<Node>,
    substitutions: Node,
    index: bigint,
    owned: BendList<string>,
    definitions: BendList<Node>,
  ) => boolean;
};

const nil = bendList<Node>([]);
const u32: Node = { $: "model.U32Ty" };
const empty = api["types.empty"]();

function definition(name: string, type: Node = u32): Node {
  return {
    $: "infer.Definition",
    name,
    inference: {
      $: "infer.Inference",
      inferred_type: type,
      coverage: nil,
      exits: nil,
      reflections: nil,
      predicates: nil,
      uses: nil,
    },
  };
}

function row(index: bigint): Node {
  return {
    $: "model.EffectRow",
    operations: nil,
    tail: { $: "model.RowVariable", index },
  };
}

function arrow(parameter: Node, result: Node, effects: Node): Node {
  return { $: "model.FunctionTy", parameter, result, effects };
}

function signature(index: bigint): Node {
  return arrow(u32, arrow(u32, u32, row(index)), row(index));
}

function selected(name: string, index: bigint): Node {
  return { $: "monomorph.FunctionChoice", name, signature: signature(index) };
}

function answer(name: string, index: bigint): Node {
  return {
    $: "constraints.EvidenceAnswer",
    predicate: {
      $: "model.ReceiverPredicate",
      member: "plus",
      templates: nil,
      receiver: u32,
      argument: u32,
      result: u32,
      invocation: row(index),
    },
    evidence: {
      $: "constraints.SelectedFunction",
      name,
      signature: signature(index),
    },
  };
}

Deno.test("member definition count keeps exact multiplicity across a wide list", () => {
  const one = Array.from(
    { length: 12_000 },
    (_, index) => definition(index === 6_000 ? "target" : "other"),
  );
  const many = Array.from(
    { length: 12_000 },
    (_, index) => definition(index % 3 === 0 ? "target" : "other"),
  );
  equal(api["monomorph.member_definition_count"](bendList(one), "target"), 1n);
  equal(
    api["monomorph.member_definition_count"](bendList(many), "target"),
    4_000n,
  );
});

Deno.test("first recheckable member keeps candidate order and handles a wide miss", () => {
  const definitions = bendList([
    definition("seven", signature(7n)),
    definition("eight", signature(8n)),
  ]);
  const owned = bendList(["seven", "eight"]);
  const pending = bendList([selected("seven", 7n), selected("eight", 8n)]);
  const fixed = bendList([7n, 8n]);
  equal(
    api["monomorph.first_recheckable_member"](
      bendList([8n, 7n]),
      fixed,
      bendList([]),
      owned,
      pending,
      empty,
      definitions,
    ),
    { $: "Some", value: 8n },
  );
  equal(
    api["monomorph.first_recheckable_member"](
      bendList([7n, 8n]),
      fixed,
      bendList([]),
      owned,
      pending,
      empty,
      definitions,
    ),
    { $: "Some", value: 7n },
  );
  equal(
    api["monomorph.first_recheckable_member"](
      bendList(Array<bigint>(12_000).fill(7n)),
      bendList([7n]),
      bendList([7n]),
      bendList([]),
      bendList([]),
      empty,
      bendList([]),
    ),
    { $: "None" },
  );
});

Deno.test("receiver answers stop at a matching selection in a wide list", () => {
  const named = "seven";
  const definitions = bendList([definition(named, signature(7n))]);
  const owned = bendList([named]);
  equal(
    api["monomorph.recheckable_member_answers"](
      bendList([answer("absent", 7n)]),
      empty,
      7n,
      owned,
      definitions,
    ),
    false,
  );
  const unrelated: Node = {
    $: "constraints.EvidenceAnswer",
    predicate: { $: "model.TypeRepPredicate", represented: u32 },
    evidence: { $: "constraints.RepresentedType", represented: u32 },
  };
  equal(
    api["monomorph.recheckable_member_answers"](
      bendList(Array<Node>(12_000).fill(unrelated)),
      empty,
      7n,
      owned,
      definitions,
    ),
    false,
  );
  equal(
    api["monomorph.recheckable_member_answers"](
      bendList(Array<Node>(12_000).fill(answer("absent", 7n))),
      empty,
      7n,
      owned,
      definitions,
    ),
    false,
  );
  const matching = answer(named, 7n);
  equal(
    api["monomorph.recheckable_member_answers"](
      bendList(Array<Node>(12_000).fill(matching)),
      empty,
      7n,
      owned,
      definitions,
    ),
    true,
  );
});
