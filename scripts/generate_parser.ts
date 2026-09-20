import {
  applyBundle,
  generate,
  type GrammarExpression,
  parseGrammar,
  parseMetadata,
} from "@mewhhaha/baba";

const grammar = parseGrammar(await Deno.readTextFile("grammar.baba"));
const metadata = parseMetadata(await Deno.readTextFile("baba.json"));
const fields = new Set<string>();

function collectFields(expression: GrammarExpression): void {
  switch (expression.kind) {
    case "field":
      fields.add(expression.name);
      collectFields(expression.expression);
      return;
    case "sequence":
      expression.items.forEach(collectFields);
      return;
    case "choice":
      expression.options.forEach(collectFields);
      return;
    case "optional":
    case "repeat":
    case "repeat1":
    case "constructor":
      collectFields(expression.expression);
      return;
    case "separated":
      collectFields(expression.item);
      collectFields(expression.separator);
      return;
    case "expressionIsland":
      collectFields(expression.atom);
      return;
    case "ref":
    case "literal":
      return;
  }
}

for (const declaration of grammar.declarations) {
  if (declaration.kind === "rule") collectFields(declaration.expression);
}
const bundle = generate(grammar, {
  name: "blot",
  rootRule: "program",
  metadata,
  targets: ["wasm"],
});
await applyBundle(bundle, { root: "generated" });
// Baba 9.0.1 uses dense, alphabetically sorted field IDs in its compact CST.
const schema = {
  fields: [...fields].sort(),
  tokens: grammar.declarations.flatMap((declaration) =>
    declaration.kind === "token" || declaration.kind === "skip"
      ? [declaration.name]
      : []
  ),
};
await Deno.writeTextFile(
  "generated/wasm/cst-schema.json",
  JSON.stringify(schema, null, 2) + "\n",
);
console.log("Generated Baba lexer, parser plan, and CST schema.");
