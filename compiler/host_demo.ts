import { instantiateGuest } from "./guest.ts";
import { createNativeCompiler } from "./native.ts";

const compiler = await createNativeCompiler();
let artifact;
try {
  artifact = await compiler.compile(
    await Deno.readTextFile(
      new URL("../examples/host_io.blot", import.meta.url),
    ),
  );
} finally {
  await compiler.dispose();
}

const guest = await instantiateGuest(artifact.bytes);
try {
  const advance = guest.capability({
    parameter: "U32",
    result: "U32",
    call: (value) => value + 1,
  });
  const answer = guest.call("main", advance);
  const mocked = guest.call("mocked", null);
  if (answer !== 42 || mocked !== 42 || guest.read("uses_host") !== true) {
    throw new Error(
      "Host callback, source provider, and effect descriptor disagree",
    );
  }
  console.log(`main(host callback) = ${answer}; mocked(Unit) = ${mocked}`);
} finally {
  guest.dispose();
}
