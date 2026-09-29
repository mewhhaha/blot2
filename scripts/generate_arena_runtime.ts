// Maintainer tool only; ordinary compiler builds do not require WABT.
// Keep the readable WAT and checked-in Bend encoding in sync.
const root = new URL("../", import.meta.url);
const temporary = await Deno.makeTempFile({ suffix: ".wasm" });
try {
  const process = await new Deno.Command("wat2wasm", {
    args: [
      new URL("compiler/arena_runtime.wat", root).pathname,
      "-o",
      temporary,
    ],
  }).output();
  if (!process.success) {
    throw new Error(new TextDecoder().decode(process.stderr));
  }
  const bytes = await Deno.readFile(temporary);
  let at = 8;
  const unsigned = () => {
    let value = 0, shift = 0, part;
    do {
      part = bytes[at++];
      value += (part & 127) * 2 ** shift;
      shift += 7;
    } while (part & 128);
    return value;
  };
  const bodies: string[] = [];
  while (at < bytes.length) {
    const section = bytes[at++], size = unsigned(), end = at + size;
    if (section !== 10) {
      at = end;
      continue;
    }
    const count = unsigned();
    for (let body = 0; body < count; body++) {
      const size = unsigned(), end = at + size, start = at;
      const groups = unsigned();
      for (let i = 0; i < groups; i++) {
        unsigned();
        at++;
      }
      const chunks: string[] = [];
      let chunk = start;
      while (at < end) {
        const opcodeAt = at, opcode = bytes[at++];
        if (opcode === 0x10) {
          chunks.push(`[${[...bytes.subarray(chunk, at)].join(", ")}]`);
          const callee = unsigned();
          chunks.push(`leb(Nat.add(imports, ${callee}n))`);
          chunk = at;
        } else if (
          [
            0x02,
            0x03,
            0x04,
            0x0c,
            0x0d,
            0x20,
            0x21,
            0x22,
            0x23,
            0x24,
            0x3f,
            0x40,
            0x41,
          ].includes(opcode)
        ) {
          unsigned();
        } else if (opcode === 0xfc) {
          const extended = unsigned();
          if (extended !== 11 || unsigned() !== 0) {
            throw new Error(`Unsupported bulk-memory opcode at ${opcodeAt}`);
          }
        } else if ([0x28, 0x36].includes(opcode)) {
          unsigned();
          unsigned();
        } else if (
          ![
            0x00,
            0x05,
            0x0b,
            0x0f,
            0x1a,
            0x45,
            0x46,
            0x47,
            0x49,
            0x4b,
            0x4f,
            0x67,
            0x68,
            0x6a,
            0x6b,
            0x71,
            0x72,
            0x74,
            0x76,
          ].includes(opcode)
        ) {
          throw new Error(
            `Unsupported arena opcode 0x${opcode.toString(16)} at ${opcodeAt}`,
          );
        }
      }
      if (chunk < end) {
        chunks.push(`[${[...bytes.subarray(chunk, end)].join(", ")}]`);
      }
      bodies.push(
        `def ${
          ["allocate", "mark", "collect"][body]
        }(+imports: Nat) -> List<&2, U32>:\n  join([\n    ${
          chunks.join(",\n    ")
        }\n  ])\n`,
      );
    }
  }
  const header =
    `# Generated from arena_runtime.wat by scripts/generate_arena_runtime.ts.\n# Do not edit the byte encoding manually. Runtime calls remain relocatable.\nimport Base\n\ndef leb_go(fuel: Nat, +value: U32) -> List<&2, U32>:\n  match fuel:\n    case 0n:\n      Nil{}\n    case 1n+rest:\n      Bool.pick(List<&2, U32>, U32.is_lt(value, 128), [value], U32.or(U32.and(value, 127), 128) <> leb_go(rest, U32.shrn(value, 7n)))\n\ndef leb(value: Nat) -> List<&2, U32>:\n  leb_go(5n, U32.from_nat(value))\n\ndef join(chunks: List<&2, List<&2, U32>>) -> List<&2, U32>:\n  match chunks:\n    case Nil{}:\n      Nil{}\n    case head <> tail:\n      List.append(&2, U32, head, join(tail))\n\n`;
  await Deno.writeTextFile(
    new URL("compiler/arena_runtime.bend", root),
    header + bodies.join("\n"),
  );
} finally {
  await Deno.remove(temporary);
}
