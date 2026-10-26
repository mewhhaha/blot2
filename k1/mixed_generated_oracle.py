#!/usr/bin/env python3
"""Independent numerical oracle for the private mixed scalar/loop subset.

Run from any directory with GOOSE set to the Goose executable and GOOSE_HOME
set as required by that executable. All generated sources and Wasm stay in a
temporary directory. This does not qualify full K1 or its public ABI.
"""

import json
import os
from pathlib import Path
import random
import shutil
import subprocess
import tempfile


def programs():
    rng = random.Random(5436991)
    results = []
    for _ in range(90):
        initial = rng.choice([0, 1, 4294967295, 4294967290, rng.randrange(100)])
        increment = rng.choice([0, 1, 17, 4294967295])
        final = rng.randrange(12)
        threshold = rng.randrange(8)
        nested = rng.randrange(2)
        if nested:
            source = (
                "let f: U32 -> U32 = fn x => do:\n"
                f"  let sum = for i in 0..x carry (a={initial}) do:\n"
                f"    let part = for j in 0..{threshold} carry (b=a) do:\n"
                "      next (U32.wrapping_add(b, i))\n"
                f"    next (U32.wrapping_add(part, {increment}))\n"
                f"  return U32.wrapping_add(sum, {final})\n"
            )
        else:
            source = (
                "let f: U32 -> U32 = fn x => do:\n"
                f"  let sum = for i in 0..x carry (a={initial}) do:\n"
                f"    let v = U32.wrapping_add(a, {increment})\n"
                f"    if i < {threshold}:\n"
                "      next (U32.wrapping_add(v, i))\n"
                "    else:\n"
                "      stop (U32.wrapping_add(v, x))\n"
                f"  return U32.wrapping_add(sum, {final})\n"
            )

        expected = []
        for x in range(13):
            accumulator = initial
            for i in range(x):
                if nested:
                    for _ in range(threshold):
                        accumulator = (accumulator + i) & 0xFFFFFFFF
                    accumulator = (accumulator + increment) & 0xFFFFFFFF
                else:
                    value = (accumulator + increment) & 0xFFFFFFFF
                    if i < threshold:
                        accumulator = (value + i) & 0xFFFFFFFF
                    else:
                        accumulator = (value + x) & 0xFFFFFFFF
                        break
            expected.append((accumulator + final) & 0xFFFFFFFF)
        results.append((source, expected))
    return results


def main():
    fixture = Path(__file__).resolve().parent
    goose = os.environ.get("GOOSE", "goose")
    specs = programs()
    with tempfile.TemporaryDirectory(prefix="k1-mixed-oracle-") as temp:
        root = Path(temp)
        shutil.copytree(fixture, root / "k1")
        lines = [
            "import os; import mixed_frontend; import mixed_validate; import mixed_wasm; fn main() {"
        ]
        for i, (source, _) in enumerate(specs):
            lines.append(
                "{let s=" + json.dumps(source) + ";var p=mixed_frontend::parse(s);"
                "assert(p.status==0 && p.program.variant==2 && mixed_validate::verify(s,p.program));"
                "let b=mixed_wasm::emit(s,p.program);assert(b.len>0 && write_file("
                + json.dumps(f"case-{i}.wasm") + ",b));}"
            )
        lines.append('print("generated mixed programs emitted");}')
        test_file = root / "k1" / "mixed_generated_driver.goose"
        test_file.write_text("\n".join(lines), encoding="utf-8")
        (root / "expected.json").write_text(json.dumps([v for _, v in specs]), encoding="utf-8")
        script = root / "oracle.mjs"
        script.write_text(
            "import {readFileSync} from 'node:fs';\n"
            "import {strict as assert} from 'node:assert';\n"
            "const expected=JSON.parse(readFileSync(process.argv[2]));\n"
            "for(let i=0;i<expected.length;i++){\n"
            " const bytes=readFileSync(`case-${i}.wasm`);assert(WebAssembly.validate(bytes));\n"
            " const f=new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports.f;\n"
            " for(let x=0;x<expected[i].length;x++) "
            "assert.equal(f(0,x)>>>0,expected[i][x],`case ${i}, input ${x}`);\n"
            "}\n"
            "console.log(`independent mixed oracle: ${expected.length * 13} calls passed`);\n",
            encoding="utf-8",
        )
        for optimization in ("-O0", "-O2"):
            out = root / optimization[1:]
            out.mkdir()
            subprocess.run([goose, "--debug", optimization, str(test_file)], cwd=out, check=True)
            subprocess.run(["node", str(script), str(root / "expected.json")], cwd=out, check=True)


if __name__ == "__main__":
    main()
