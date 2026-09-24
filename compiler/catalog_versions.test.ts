import {
  deepStrictEqual as equal,
  notDeepStrictEqual as differs,
  ok,
} from "node:assert/strict";
import compiled from "../generated/compiler/native_session.js";
import { type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: Node;
};
type Prepared = { readonly revision: Node; readonly same_operations: boolean };

const backend = compiled as unknown as {
  "catalog_versions.prepare"(
    types: BendList<Node>,
    operations: BendList<Node>,
    previous: Node,
  ): Result<Prepared>;
  "catalog_versions.group_key"(
    module: Node,
    revision: Node,
  ): Result<BendList<number>>;
  "catalog_versions.original_matches"(
    module: Node,
    revision: Node,
  ): boolean;
};

function unwrap<T>(result: Result<T>): T {
  ok(
    result.$ === "Done",
    result.$ === "Fail" ? result.error.message as string : undefined,
  );
  return result.value;
}

const identity = (module_name: string, declaration: string): Node => ({
  $: "TypeId",
  module_name,
  declaration,
});
const scalar = (name: "U32Ty" | "BoolTy"): Node => ({ $: name });
const dataType = (
  module_name: string,
  declaration: string,
  payload: Node,
): Node => ({
  $: "DataType",
  identity: identity(module_name, declaration),
  parameters: 0n,
  constructors: bendList([{
    $: "Constructor",
    name: `Make${declaration}`,
    payload: { $: "Some", value: payload },
    fields: bendList([]),
  }]),
});
const operation = (name: string): Node => ({
  $: "Operation",
  identity: identity("effects", name),
  parameter: scalar("U32Ty"),
  result: scalar("BoolTy"),
});
const module = (types: Node[], operations: Node[] = []): Node => ({
  $: "Module",
  constants: bendList([]),
  functions: bendList([]),
  data_types: bendList(types),
  operations: bendList(operations),
});
const prepare = (types: Node[], operations: Node[], previous?: Node) =>
  unwrap(backend["catalog_versions.prepare"](
    bendList(types),
    bendList(operations),
    previous ? { $: "Some", value: previous } : { $: "None" },
  ));
const key = (subset: Node, revision: Node) =>
  unwrap(backend["catalog_versions.group_key"](subset, revision));

Deno.test("nominal version tokens retain exact unchanged schemas and distinguish edits", () => {
  const a = dataType("one", "A", scalar("U32Ty"));
  const changedA = dataType("one", "A", scalar("BoolTy"));
  const b = dataType("one", "B", scalar("U32Ty"));
  const first = prepare([a, b], []);
  const unchanged = prepare([a, b], [], first.revision);
  equal(unchanged.same_operations, true);
  equal(
    key(module([a, b]), unchanged.revision),
    key(module([a, b]), first.revision),
  );

  const changed = prepare([changedA, b], [], first.revision);
  equal(changed.same_operations, true);
  differs(
    key(module([changedA]), changed.revision),
    key(module([a]), first.revision),
  );
  equal(key(module([b]), changed.revision), key(module([b]), first.revision));
  differs(
    key(module([b, changedA]), changed.revision),
    key(module([changedA, b]), changed.revision),
  );

  const restored = prepare([a, b], [], changed.revision);
  differs(
    key(module([a]), restored.revision),
    key(module([a]), first.revision),
  );

  const discarded = prepare([changedA, b], [], first.revision);
  const afterFailure = prepare([a, b], [], first.revision);
  equal(
    key(module([a]), afterFailure.revision),
    key(module([a]), first.revision),
  );
  differs(
    key(module([changedA]), discarded.revision),
    key(module([a]), afterFailure.revision),
  );
});

Deno.test("operation gates and shape seeds compare exact ordered catalogs", () => {
  const a = dataType("one", "A", scalar("U32Ty"));
  const op = operation("Ask");
  const first = prepare([a], [op]);
  equal(
    backend["catalog_versions.original_matches"](
      module([a], [op]),
      first.revision,
    ),
    true,
  );
  const addedOperation = prepare([a], [op, operation("Other")], first.revision);
  equal(addedOperation.same_operations, false);
  const removedOperation = prepare([a], [], first.revision);
  equal(removedOperation.same_operations, false);
  const reorderedOperation = prepare(
    [a],
    [operation("Other"), op],
    addedOperation.revision,
  );
  equal(reorderedOperation.same_operations, false);
  const retryAfterRejectedEdit = prepare([a], [op], first.revision);
  equal(retryAfterRejectedEdit.same_operations, true);
  equal(
    key(module([a], [op]), retryAfterRejectedEdit.revision),
    key(module([a], [op]), first.revision),
  );
  equal(
    key(module([a], [op]), first.revision),
    key(module([a], [op, operation("Other")]), addedOperation.revision),
  );
  equal(
    backend["catalog_versions.original_matches"](
      module([a], [op]),
      addedOperation.revision,
    ),
    false,
  );
  equal(
    backend["catalog_versions.original_matches"](
      module([], [op]),
      first.revision,
    ),
    false,
  );

  const b = dataType("one", "B", scalar("BoolTy"));
  const reordered = prepare([b, a], [op], prepare([a, b], [op]).revision);
  equal(
    backend["catalog_versions.original_matches"](
      module([a, b], [op]),
      reordered.revision,
    ),
    false,
  );
});

Deno.test("nominal identities stay distinct across separator-like names", () => {
  const left = dataType("a", "b.c", scalar("U32Ty"));
  const right = dataType("a.b", "c", scalar("U32Ty"));
  const revision = prepare([left, right], []).revision;
  differs(key(module([left]), revision), key(module([right]), revision));
});
