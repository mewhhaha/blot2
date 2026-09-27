import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [key: string]: unknown };

const core = compiled as unknown as {
  "constraints.canonical_predicates"(
    pending: BendList<Node>,
    seen: BendList<Node>,
  ): BendList<Node>;
};

const closed = { $: "model.ClosedRow" };
const emptyRow = {
  $: "model.EffectRow",
  operations: bendList([]),
  tail: closed,
};
const u32 = { $: "model.U32Ty" };
const f32 = { $: "model.F32Ty" };

function nested(result: Node): Node {
  let type = result;
  for (let depth = 0; depth < 4; depth++) {
    type = {
      $: "model.FunctionTy",
      parameter: u32,
      result: type,
      effects: emptyRow,
    };
  }
  return type;
}

const typeRep = (represented: Node): Node => ({
  $: "model.TypeRepPredicate",
  represented,
});

const effectRep = (names: readonly string[]): Node => ({
  $: "model.EffectRepPredicate",
  row: {
    $: "model.EffectRow",
    operations: bendList(
      names.map((declaration) => ({
        $: "model.TypeId",
        module_name: "example",
        declaration,
      })),
    ),
    tail: closed,
  },
});

Deno.test("canonical predicate buckets retain deep collisions and initial seen order", () => {
  const first = typeRep(nested(u32));
  const duplicate = typeRep(nested(u32));
  const deepCollision = typeRep(nested(f32));
  const other = typeRep({ $: "model.VariableTy", index: 17n });

  equal(
    bendArray(core["constraints.canonical_predicates"](
      bendList([duplicate, deepCollision, duplicate, other, deepCollision]),
      bendList([first, other]),
    )),
    [other, first, deepCollision],
  );
});

Deno.test("canonical predicate buckets compare full effect multisets after tail collisions", () => {
  const one = effectRep(["Tick"]);
  const two = effectRep(["Tick", "Tick"]);
  const twoAgain = effectRep(["Tick", "Tick"]);
  const other = effectRep(["Tap"]);

  equal(
    bendArray(core["constraints.canonical_predicates"](
      bendList([one, two, twoAgain, other, one]),
      bendList([]),
    )),
    [one, two, other],
  );
});
