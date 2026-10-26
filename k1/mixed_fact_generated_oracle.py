#!/usr/bin/env python3
"""Independent U32 boundary oracle for the private mixed loop fact slice.

Set GOOSE and GOOSE_HOME for the local Goose compiler. Generated source and
Wasm are written only to a temporary directory. This is not a full K1 gate.
"""
import json
import os
from pathlib import Path
import random
import shutil
import subprocess
import tempfile

INPUTS = [0, 1, 7, 4294967293, 4294967294, 4294967295]


def programs():
    rng = random.Random(152396)
    results = []
    for _ in range(90):
        count, inner = rng.randrange(8), rng.randrange(6)
        kind, delta = rng.randrange(3), rng.randrange(4)
        prefix = (
            "let f: U32 -> U32 = fn x => do:\n"
            f"  let sum = for i in 0..{count} carry (a=U32.wrapping_add(x,{delta})) do:\n"
        )
        if kind == 0:
            body = (
                "    let b = a\n"
                "    if b < 4294967295:\n"
                "      next (a + 1)\n"
                "    else:\n"
                "      stop (a)\n"
            )
        elif kind == 1:
            body = (
                "    let y = U32.wrapping_add(a,1)\n"
                "    if y < a:\n"
                "      stop (a)\n"
                "    else:\n"
                "      if y < 4294967295:\n"
                "        next (a + 1)\n"
                "      else:\n"
                "        stop (a)\n"
            )
        else:
            body = (
                f"    let inner = for j in 0..{inner} carry (b=a) do:\n"
                "      if b < 4294967295:\n"
                "        next (b + 1)\n"
                "      else:\n"
                "        stop (b)\n"
                "    next (inner)\n"
            )
        source = prefix + body + "  return sum\n"
        expected = []
        for x in INPUTS:
            a = (x + delta) & 0xFFFFFFFF
            for _ in range(count):
                if kind == 2:
                    for _ in range(inner):
                        if a < 0xFFFFFFFF:
                            a += 1
                        else:
                            break
                elif kind == 0:
                    if a < 0xFFFFFFFF:
                        a += 1
                    else:
                        break
                else:
                    y = (a + 1) & 0xFFFFFFFF
                    if y < a:
                        break
                    if y < 0xFFFFFFFF:
                        a += 1
                    else:
                        break
            expected.append(a)
        results.append((source, expected))
    return results


def main():
    fixture = Path(__file__).resolve().parent
    goose = os.environ.get("GOOSE", "goose")
    cases = programs()
    with tempfile.TemporaryDirectory(prefix="k1-loop-fact-oracle-") as temp:
        root = Path(temp)
        shutil.copytree(fixture, root / "k1")
        lines = ["import os; import mixed_frontend; import mixed_validate; import mixed_wasm; fn main() {"]
        for i, (source, _) in enumerate(cases):
            lines.append(
                "{let s=" + json.dumps(source) + ";var p=mixed_frontend::parse(s);"
                "assert(p.status==0 && p.program.variant==2 && mixed_validate::verify(s,p.program));"
                "let b=mixed_wasm::emit(s,p.program);assert(b.len>0 && write_file("
                + json.dumps(f"case-{i}.wasm") + ",b));}"
            )
        lines.append('print("generated loop-fact programs emitted");}')
        test = root / "k1" / "mixed_fact_generated_driver.goose"
        test.write_text("\n".join(lines), encoding="utf-8")
        (root / "expected.json").write_text(json.dumps([v for _, v in cases]), encoding="utf-8")
        script = root / "oracle.mjs"
        script.write_text(
            "import {readFileSync} from 'node:fs';\n"
            "import {strict as assert} from 'node:assert';\n"
            "const expected=JSON.parse(readFileSync(process.argv[2]));\n"
            "const inputs=" + json.dumps(INPUTS) + ";\n"
            "for(let i=0;i<expected.length;i++){\n"
            " const b=readFileSync(`case-${i}.wasm`);assert(WebAssembly.validate(b));\n"
            " const f=new WebAssembly.Instance(new WebAssembly.Module(b)).exports.f;\n"
            " for(let j=0;j<inputs.length;j++) "
            "assert.equal(f(0,inputs[j])>>>0,expected[i][j],`case ${i}, input ${inputs[j]}`);\n"
            "}\n"
            "console.log(`independent loop-fact oracle: ${expected.length * inputs.length} calls passed`);\n",
            encoding="utf-8",
        )
        for optimization in ("-O0", "-O2"):
            out = root / optimization[1:]
            out.mkdir()
            subprocess.run([goose, "--debug", optimization, str(test)], cwd=out, check=True)
            subprocess.run(["node", str(script), str(root / "expected.json")], cwd=out, check=True)


if __name__ == "__main__":
    main()
