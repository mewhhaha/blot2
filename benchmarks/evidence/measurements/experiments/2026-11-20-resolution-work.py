"""Count nested type resolutions by module/caller and actual cache work.

Run from the Blot repository after a release build. Supply a fresh output
directory and an immutable Gdev checkout. Only the diagnostic copies of the
emitted C are instrumented. Compare release binaries for elapsed time.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("--compiler-build", type=Path, default=Path("compiler-goose/build"))
parser.add_argument("--gdev-root", type=Path, required=True)
args = parser.parse_args()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
build = args.compiler_build.resolve()
source = (build / "blot_goose.c").read_text()
sites = {"outside-checker": 0}
insertions = Counter()


def site(label):
    return sites.setdefault(label, len(sites))


def instrument(match):
    signature, body = match.groups()
    name = signature.split("(")[0].split()[-1]
    prefix = ""
    if name.startswith("blot_phase_profile_traceModule_"):
        prefix = '    record_name(unit_g,filename_g_data,filename_g_len);\n'
    elif re.fullmatch(r"blot_reuse_project_check_checkModule_g\d+", name):
        prefix = "    begin_counts(unit_g); int unit_scope __attribute__((cleanup(end_counts)))=unit_g;\n"
    elif name.startswith("blot_check_types_resolveDepth_"):
        prefix = "    ++visits[caller];\n"
        insertions["resolve"] += 1
    elif "Map_projection_resolutions_g" in signature and name.startswith("blot_check_types_clear_"):
        prefix = "    ++resets; live+=map_g->count_g;\n"
        body, writes = re.subn(r"(?m)^([ ]+)([^\n;]*\.tag_g = 0;)$", r"\1++cleared; \2", body)
        assert writes in (1, 2), writes
        insertions["clear"] += 1
    elif "Map_projection_resolutions_g" in signature and name.startswith("blot_check_types_grow_"):
        prefix = "    initialized+=capacity_g; rehashed+=map_g->slots_g.len; ++grows;\n"
        insertions["grow"] += 1
    elif name.startswith(("blot_check_check_", "blot_check_types_unify")):
        label = re.sub(r"_g\d+(?:_\d+)?$", "", name.removeprefix("blot_check_"))
        prefix = f"    int previous __attribute__((cleanup(restore_caller)))=caller; caller={site(label)};\n"
        if label == "check_finishNormalized":
            def field(m):
                field_name = m[1].replace("(*", "").replace(")", "").replace("_g", "")
                return f"    caller={site('finish.' + field_name)};\n" + m[0]
            body = re.sub(r"(?m)^ +t\d+ = blot_check_types_resolve_g[^\n]+?types_g, ([^,]+)", field, body)
    return signature + prefix + body


source = re.sub(r"(?m)^(static [^\n;]+\) \{\n)([\s\S]*?^\})", instrument, source)
assert all(insertions[k] >= 1 for k in ["resolve", "clear", "grow"]), insertions
observer = r'''
#include <stdio.h>
#include <unistd.h>
static int caller;
static unsigned long visits[NSITES], resets, live, cleared, grows, initialized, rehashed;
static FILE *events(void) {
    static int pid;
    static FILE *out;
    if (pid!=getpid()) {
        char path[4096];
        pid=getpid(); snprintf(path,sizeof(path),DIRECTORY"/worker-%d",pid);
        out=fopen(path,"a"); if (!out) abort();
        setlinebuf(out);
    }
    return out;
}
static void record_name(unsigned unit,const char *name,long len) {
    fprintf(events(),"N %u %.*s\n",unit,(int)len,name);
}
static void restore_caller(int *previous) { caller=*previous; }
static void begin_counts(unsigned unit) {
    memset(visits,0,sizeof(visits));
    resets=live=cleared=grows=initialized=rehashed=0;
}
static void end_counts(int *unit) {
    FILE *out=events();
    for (unsigned i=0;i<NSITES;i++) if(visits[i]) fprintf(out,"V %d %u %lu\n",*unit,i,visits[i]);
    fprintf(out,"C %d %lu %lu %lu %lu %lu %lu\n",*unit,resets,live,cleared,grows,initialized,rehashed);
}
'''.replace("NSITES", str(len(sites))).replace("DIRECTORY", json.dumps(str(output)))
marker = source.index("/* ==== runtime_ext.h ==== */")
emission = output / "trace.c"
emission.write_text(source[:marker] + observer + source[marker:])
command = json.loads((build / "stages/compile-and-link-program.json").read_text())["command"]
index = next(i for i, arg in enumerate(command) if Path(arg).name == "blot_goose.c")
command.insert(1, "-I" + str(Path(command[index]).parent))
command[index + 1] = str(emission)
command[command.index("-O2")] = "-O0"
command[-1] = str(output / "trace")
with (output / "compile.log").open("w") as log:
    subprocess.run(command, check=True, stdout=log, stderr=log, timeout=120)
with (output / "build.json").open("w") as log:
    subprocess.run(["deno", "run", "-A", "scripts/integration/build_gdev.ts", "--compiler", command[-1],
                    "--gdev-root", args.gdev_root, "--frontend-workers", "8", "--profile",
                    "--timeout-ms", "20000", output / "wasm"], stdout=log, check=True, timeout=30)
report = json.loads((output / "build.json").read_text())
labels = {v: k for k, v in sites.items()}
counts = defaultdict(Counter)
cache = {}
names = {}
for log in output.glob("worker-*"):
    for line in log.read_text().splitlines():
        kind, raw_unit, rest = line.split(" ", 2)
        unit = int(raw_unit)
        if kind == "N":
            assert unit not in names
            names[unit] = rest
        elif kind == "V":
            key, value = map(int, rest.split())
            counts[unit][labels[key]] += value
        elif kind == "C":
            assert unit not in cache
            cache[unit] = dict(zip(["resets", "live", "cleared", "grows", "initialized", "rehashScans"],
                                   map(int, rest.split()), strict=True))
assert set(names) == set(cache) and len(names) == report["stats"]["freshModules"]
total = sum(count.total() for count in counts.values())
assert total == report["stats"]["frontend"]["normalization"]["resolve_depth_entries"]
wasm = Path(report["evidence"]) / "main.wasm"
result = dict(wasmSha256=hashlib.sha256(wasm.read_bytes()).hexdigest(), counts=counts, cache=cache, names=names)
(output / "work.json").write_text(json.dumps(result, indent=1) + "\n")
