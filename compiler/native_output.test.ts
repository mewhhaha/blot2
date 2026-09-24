import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/native_output.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";
import { NativeProcess } from "./native_process.ts";
import {
  encodeNativeRequest,
  nativeProtocolVersion,
} from "./native_protocol.ts";
import { createSourceFrontend } from "./source_frontend.ts";
import { arithmeticSource } from "./benchmark_workloads.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: Node;
};
interface Block {
  readonly $: "Block";
  readonly length: bigint;
  readonly words: BendList<number>;
}
interface Packet {
  readonly $: "Packet";
  readonly word_count: number;
  readonly header: BendList<number>;
  readonly blocks: BendList<Block>;
}
const backend = compiled as unknown as {
  encode_plan(
    fields: BendList<Node>,
    plan: Node,
    maximum: bigint,
    grain: bigint,
  ): Result<Packet>;
  "native_response.encode_work"(
    fuel: bigint,
    fields: BendList<Node>,
    maximum: bigint,
    reversed: BendList<number>,
  ): Result<BendList<number>>;
  "main.compile_source"(
    root: unknown,
    prelude: unknown,
    fuel: bigint,
    steps: bigint,
  ): Result<Node>;
};
const fields: Node[] = [1112297300, nativeProtocolVersion, 2].map((value) => ({
  $: "Word",
  value,
}));
function wordsBytes(words: readonly number[]) {
  const bytes = new Uint8Array(words.length * 4);
  const view = new DataView(bytes.buffer);
  words.forEach((word, index) => view.setUint32(index * 4, word, true));
  return bytes;
}
function packetBytes(packet: Packet) {
  const bytes = new Uint8Array(packet.word_count * 4);
  const header = wordsBytes(bendArray(packet.header));
  bytes.set(header);
  let offset = header.length;
  for (const block of bendArray(packet.blocks)) {
    const packed = wordsBytes(bendArray(block.words));
    const length = Number(block.length);
    equal(packed.length, Math.ceil(length / 4) * 4);
    ok(packed.subarray(length).every((byte) => byte === 0));
    bytes.set(packed.subarray(0, length), offset);
    offset += length;
  }
  ok(bytes.length - offset < 4);
  return bytes;
}
function plan(chunks: number[][], length = chunks.flat().length): Node {
  return {
    $: "BytePlan",
    length: BigInt(length),
    chunks: bendList(chunks.map(bendList)),
  };
}
function legacy(chunks: number[][], maximum: bigint, prefix = fields) {
  return backend["native_response.encode_work"](
    10000000n,
    bendList([...prefix, { $: "Bytes", values: bendList(chunks.flat()) }]),
    maximum,
    bendList([]),
  );
}

Deno.test("chunked output preserves every padding boundary and coarse packing grain", () => {
  for (const count of [0, 1, 2, 3, 4, 5, 127, 128, 255, 256, 513, 1025]) {
    const chunks = Array.from(
      { length: count },
      (_, index) =>
        Array.from(
          { length: index % 9 },
          (_, byte) => (index * 17 + byte) & 255,
        ),
    );
    const expected = legacy(chunks, 1000000n);
    ok(expected.$ === "Done");
    for (const grain of [0n, 1n, 16n, 128n, 2048n, 1000000n]) {
      const actual = backend.encode_plan(
        bendList(fields),
        plan(chunks),
        1000000n,
        grain,
      );
      ok(actual.$ === "Done");
      equal(packetBytes(actual.value), wordsBytes(bendArray(expected.value)));
    }
  }
});

Deno.test("chunked output preserves size and invalid-byte error precedence", () => {
  for (const count of [0, 1, 3, 4, 5, 8, 17]) {
    for (const bad of [-1, 0, count - 1]) {
      const bytes = Array.from(
        { length: count },
        (_, index) => index === bad ? 256 : index,
      );
      const chunks = [bytes.slice(0, 3), [], bytes.slice(3)];
      for (let maximum = 0n; maximum <= 10n; maximum++) {
        const expected = legacy(chunks, maximum);
        const actual = backend.encode_plan(
          bendList(fields),
          plan(chunks),
          maximum,
          1n,
        );
        if (expected.$ === "Fail") equal(actual, expected);
        else {
          ok(actual.$ === "Done");
          equal(
            packetBytes(actual.value),
            wordsBytes(bendArray(expected.value)),
          );
        }
      }
    }
  }
  for (const length of [0, 2, 100]) {
    const result = backend.encode_plan(
      bendList(fields),
      plan([[42]], length),
      1000n,
      1n,
    );
    ok(result.$ === "Fail");
    equal(result.error.code, "internal_error");
  }
  const malformed: Node[] = [{ $: "Length", value: 16777217n }];
  equal(
    backend.encode_plan(bendList(malformed), plan([[256]]), 1000n, 1n),
    legacy([[256]], 1000n, malformed),
  );
});

Deno.test("native chunk writer matches the original complete response byte for byte", async () => {
  const frontend = await createSourceFrontend({ prelude: "none" });
  try {
    for (const threads of [1, 8]) {
      const native = await NativeProcess.start({ threads });
      try {
        for (
          const source of [
            "const answer = fn () => 42\n",
            arithmeticSource("balanced", false),
          ]
        ) {
          const prepared = frontend.prepare(source);
          const request = {
            operation: "compile" as const,
            root: prepared.root,
            prelude: prepared.prelude,
            fuel: prepared.nodeCount,
            const_steps: 10000000n,
          };
          const artifact = backend["main.compile_source"](
            request.root,
            request.prelude,
            request.fuel,
            request.const_steps,
          );
          ok(artifact.$ === "Done");
          const bytes = artifact.value.bytes as BendList<number>;
          // The old encoder's List.length over a whole Wasm artifact overflows
          // the JS stack. Supply that length, then use its unchanged word packer.
          const expected = backend["native_response.encode_work"](
            10000000n,
            bendList([
              ...fields,
              { $: "Analysis", value: artifact.value.analysis },
              { $: "ByteLength", value: BigInt(bendArray(bytes).length) },
              { $: "ByteWords", values: bytes },
            ]),
            16777216n,
            bendList([]),
          );
          ok(expected.$ === "Done");
          equal(
            await native.request(encodeNativeRequest(request)),
            wordsBytes(bendArray(expected.value)),
          );
        }
      } finally {
        await native.dispose();
      }
    }
  } finally {
    frontend.dispose();
  }
});
