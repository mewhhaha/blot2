"""Compare two Squid type checkers on independent programs. Writes JSON lines."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def programs(directory):
    cases = {}
    families = [
        ("generics", [32, 256, 1024], "func equal_{i} left -> right => return left == right",
         "io answer (n: U32): Bool => return equal_{i} n n"),
        ("callbacks", [32, 256], "func twice_{i} apply -> value => return apply (apply value)",
         "io answer (n: U32): U32 => return twice_{i} (func (v: U32) => return v + 1) n"),
    ]
    for family, sizes, declaration, entry in families:
        for size in sizes:
            name = f"{family}-{size}"
            source = directory / (name + ".sq")
            lines = [declaration.format(i=i) for i in range(size)]
            lines.append(entry.format(i=size - 1))
            source.write_text("\n".join(lines) + "\n")
            cases[name] = source
    for width in [8, 64, 256]:
        name = f"fields-{width}"
        source = directory / (name + ".sq")
        fields = ", ".join(f"f{i}: U32" for i in range(width))
        record = ", ".join(f"f{i}: n" for i in range(width))
        source.write_text(f"type Row = {{{fields}}}\n"
                          f"func pick (row: Row) => return row.f{width - 1}\n"
                          f"io answer (n: U32): U32 => return pick {{{record}}}\n")
        cases[name] = source
    for depth in [3, 6, 9]:
        name = f"shared-pair-{depth}"
        source = directory / (name + ".sq")
        lines = ["func layer0 x => return x"]
        for i in range(1, depth + 1):
            lines.append(f"func layer{i} x => return (layer{i - 1} x, layer{i - 1} x)")
        lines.append("io const answer = 42")
        source.write_text("\n".join(lines) + "\n")
        cases[name] = source
    for fanout in [2, 8, 32]:
        name = f"imports-{fanout}"
        folder = directory / name
        folder.mkdir()
        (folder / "shared.sq").write_text("func identity value => return value\n")
        imports, calls = [], []
        for i in range(fanout):
            (folder / f"leaf{i}.sq").write_text(
                'import { identity } from "./shared"\n'
                'func read (n: U32): U32 => return identity n\n')
            imports.append(f'import {{ read as read{i} }} from "./leaf{i}"')
            calls.append(f"read{i} n")
        entry = "io answer (n: U32): U32 => return " + " + ".join(calls)
        source = folder / "main.sq"
        source.write_text("\n".join([*imports, entry]) + "\n")
        cases[name] = source
    # The caller sees Point only through carry's inferred return type.
    # Vary the public catalog around it while keeping the caller identical.
    for width in [1, 16, 128]:
        name = f"indirect-nominals-{width}"
        folder = directory / name
        folder.mkdir()
        types = ["type Point is data = $Point { x: U32 }"]
        for index in range(1, width):
            types.append(f"type Extra{index} is data = $Extra{index} {{ x: U32 }}")
        (folder / "producer.sq").write_text("\n".join([
            *types, "func make (x: U32): Point => return $Point { x: x }", "",
        ]))
        (folder / "bridge.sq").write_text(
            'import { make } from "./producer"\n'
            "func carry (n: U32) => return make n\n")
        source = folder / "main.sq"
        source.write_text('import { carry } from "./bridge"\n'
                          "io answer (n: U32): U32 => return (carry n).x\n")
        cases[name] = source
    fixtures = ROOT / "compiler-goose/tests/fixtures"
    cases["imported-generics"] = fixtures / "closure-fixtures/main.sq"
    cases["owned-reads"] = fixtures / "direct/terminal_scratch_reads.sq"
    for sort in ["merge", "quick"]:
        cases["sort-" + sort] = ROOT / f"benchmarks/goose/ports/sort_{sort}.sq"
    invalid = directory / "invalid.sq"
    invalid.write_text("func add x -> y => return x + y\n"
                       "io answer (a: U32): Bool => return add a true\n")
    cases["rejected-generic"] = invalid
    return cases


def compile_case(compiler, source, output, reject):
    output.unlink(missing_ok=True)
    process = subprocess.run(
        [compiler, "build-project", source, output, "--std-root", ROOT / "std",
         "--prelude", ROOT / "std/prelude.sq", "--profile"],
        capture_output=True, text=True, timeout=12,
    )
    records = [json.loads(line) for line in process.stdout.splitlines()]
    diagnostics = [{key: item[key] for key in ("code", "start", "end", "message")}
                   for item in records if item["kind"] == "diagnostic"]
    if not records or records[-1]["kind"] != "compilation":
        raise RuntimeError(f"{source.name}: no build result\n{process.stderr}")
    build = records[-1]
    if build["success"] == reject or (process.returncode == 0) != build["success"]:
        raise RuntimeError(f"{source.name}: unexpected build outcome {diagnostics}")
    if reject and [d["code"] for d in diagnostics] != ["missing_associated"]:
        raise RuntimeError(f"{source.name}: unexpected diagnostics {diagnostics}")
    digest = None
    if build["success"]:
        digest = hashlib.sha256(output.read_bytes()).hexdigest()
    checking = build["phase_profile"]["checking"]
    normalization = checking["normalization"]
    return {
        "checkUs": build["check_us"], "totalUs": build["total_us"],
        "typeNodes": build["type_nodes"], "bodies": build["body_elaborations"],
        "resolveVisits": normalization["resolve_depth_entries"],
        "unifyPairs": normalization["unify_pairs"],
        "importVisits": normalization["import_depth_entries"],
        "importedSchemes": checking["imported_schemes"],
        "wasmSha256": digest, "diagnostics": diagnostics,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("control", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--pairs", type=int, default=12)
    args = parser.parse_args()
    if args.pairs < 1:
        parser.error("--pairs must be positive")
    variants = [("control", args.control.resolve()), ("candidate", args.candidate.resolve())]
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        cases = programs(folder)
        for pair in range(args.pairs):
            for name, source in cases.items():
                results = {}
                for label, compiler in variants:
                    results[label] = compile_case(compiler, source, folder / "out.wasm",
                                                  name == "rejected-generic")
                for key in ("wasmSha256", "diagnostics"):
                    if results["control"][key] != results["candidate"][key]:
                        raise RuntimeError(f"{name}: changed {key}")
                print(json.dumps({"pair": pair, "case": name, **results}), flush=True)
            variants.reverse()


if __name__ == "__main__":
    main()
