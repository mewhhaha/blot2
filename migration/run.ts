import { Blot } from "../host/blot.ts";
const host = await Blot.load(
  await Deno.readFile(Deno.args[0] ?? "build/migrated.wasm"),
);
const result = host.invoke("copy_identity", { src: [0, 42, 4294967295] });
if (result.status !== "Ok") throw new Error(`copy failed: ${result.status}`);
console.log(result.items);
