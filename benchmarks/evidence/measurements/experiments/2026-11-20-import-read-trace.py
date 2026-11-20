"""Record the baseline's read masks; columns are module, import class, phase mask and node count.
Run from Blot revision 666605eb after building the release compiler, with a fresh output directory.
The private diagnostic C copy only adds counters. Phase bits and classes are in the measurement JSON.
"""
from pathlib import Path
import argparse
import json
import re
import subprocess
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("--compiler-build", type=Path, default=Path("compiler-goose/build"))
parser.add_argument("--gdev-root", type=Path, default=Path("../gdev"))
args = parser.parse_args()
output = args.output.resolve()
build = args.compiler_build.resolve()
identity = json.loads((build / "source-identity.json").read_text())
if identity["digest"] != "ee25a69a989d7edbc92b4fab54d211896f9749b8343952addc977e3b305cda2c":
    raise SystemExit("This diagnostic targets the generated types and call sites of 666605eb.")
output.mkdir(parents=True, exist_ok=False)
source = (build / "blot_goose.c").read_text()

h = r'''

#include <unistd.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
enum { TCAP = 131072 };
static _Thread_local uint8_t imported[TCAP], used[TCAP], owned[TCAP];
static _Thread_local unsigned unit, stage, copylevel, cl, high, forwarded;
static _Thread_local blot_check_types_Table_nodes_g16 *tab;
static _Thread_local void *core_base;
static void trrestore(unsigned *save) { stage = *save; }
static void fwrestore(unsigned *x) { forwarded = *x; }
static void clrestore(unsigned *save) { cl = *save; }
static void depthrestore(unsigned *save) { copylevel = *save; }
#define STAGE(n)                                                                                   \
    unsigned trsave __attribute__((cleanup(trrestore))) = stage;                                   \
    stage = n
#define CLASS(n)                                                                                   \
    unsigned trclass __attribute__((cleanup(clrestore))) = cl;                                     \
    cl = n
static void begintr(unsigned u, blot_check_types_Table_nodes_g16 *t) {
    unit = u;
    tab = t;
    high = 0;
    stage = 1;
    core_base = NULL;
    memset(imported, 0, TCAP);
    memset(used, 0, TCAP);
    memset(owned, 0, TCAP);
}
static void addtr(unsigned lo, unsigned hi) {
    if (!unit)
        return;
    if (hi >= TCAP)
        abort();
    if (high < hi)
        high = hi;
    for (unsigned i = lo; i < hi; i++) {
        if (imported[i])
            abort();
        imported[i] = 3;
        if (cl)
            imported[i] = cl;
    }
}
static int64_t readtr(void *base, int64_t id) {
    if (!unit || id < 0 || id >= TCAP)
        return id;
    if (stage == 32) {
        if (base == core_base)
            owned[id] = 1;
    } else if (stage && !copylevel && (unsigned)id < high && imported[id] &&
               base == tab->items_g.data)
        used[id] |= stage;
    return id;
}
static void endtr(uint32_t *map, int64_t n) {
    unsigned counts[6][128] = {0};
    for (unsigned i = 0; i < high; i++)
        if (imported[i]) {
            if (i < n && map[i] != 0 && map[i] < TCAP && owned[map[i]])
                used[i] |= 32;
            counts[imported[i]][used[i]]++;
        }
    char p[256];
    snprintf(p, sizeof p, "%s/import-reads-%u.tsv", TRACE_DIRECTORY, getpid());
    FILE *f = fopen(p, "a");
    for (unsigned c = 1; c <= 5; c++)
        for (unsigned mask = 0; mask < 128; mask++)
            if (counts[c][mask])
                fprintf(f, "%u %u %u %u\n", unit, c, mask, counts[c][mask]);
    fclose(f);
    unit = 0;
    stage = 0;
}
'''
h = h.replace("TRACE_DIRECTORY", json.dumps(str(output)))
# Goose inlines the type store accessor into its callers. The observer also
# compares the backing pointer, so AST node tables with the same ID are ignored.
access = r"(\b(\w+)\[GS_IDX\()\(int64_t\)\((\w+)\)(, [^\n;]*?nodes_g[^\n;]*?, gs_file\d+, \d+\)\])"
source, sites = re.subn(access, r"\1readtr(\2,\3)\4", source)
assert sites == 1979, f"Expected 1,979 baseline indexed access sites, got {sites}"


def instrument(match):
    signature, body = match.groups()
    if "blot_check_check_collectModuleHeaders_" in signature:
        body = "    begintr(self__g->unit_g,self__g->types_g.nodes_g);\n" + body
    if "blot_check_check_copyForwardedNominal_" in signature:
        body = "    unsigned fw __attribute__((cleanup(fwrestore)))=forwarded;forwarded=1;\n" + body
    if "blot_check_check_copyNominalBody_" in signature:
        body = ("    unsigned kind=2;\n"
                "    if (!source_g.private_g && !source_g.is_opaque_g && !source_g.variables_g.len_g"
                " && !source_g.parameters_g.len_g && !source_g.alias_g) {kind=1;"
                "if (forwarded && source_g.closed_storage_g) kind=4;}\n    CLASS(kind);\n" + body)
        copy_payload = r"(?m)^( +)(t\d+ = blot_check_check_scheme_import_copy_g30\(copier_g, ctor_g\.payload_g,[^\n]+)"
        body = re.sub(copy_payload, r"\1{ CLASS(cl); if(cl==4) cl=5; \2 }", body)
    if "blot_check_check_scheme_import_copy_" in signature:
        body = "    unsigned dl __attribute__((cleanup(depthrestore)))=copylevel;copylevel++;\n" + body
        count = "        blot_check_check_scheme_import_saturatingAdd_g30(&(*(*self__g).destination_g.normalization_g).import_nodes_added_g"
        body = body.replace(count, "        if(self__g->destination_g.nodes_g==tab)"
                            "addtr(before_g,self__g->destination_g.nodes_g->len_g);\n" + count)
    for function, bit in [("blot_check_check_validateModuleBodies_", 2),
                          ("blot_check_check_finishNormalized_", 4),
                          ("blot_check_usage_check_validate_", 64)]:
        if function in signature:
            body = f"    STAGE({bit});\n" + body
    if "blot_reuse_project_check_publishPersistentUnit_" in signature:
        body = "    stage=8;\n" + body
    if "blot_check_core_builder_lowerWithOrigins_" in signature:
        body = "    if(unit)stage=16;\n" + body
    ownership = re.search(r"        blot_check_uniqueness_check_g21\(&result_g,[^\n]+", body)
    if ownership:
        call = ownership.group()
        body = body.replace(call, "        core_base=result_g.types_g.nodes_g.data; stage=32;\n" + call
                            + "\n        if(unit)endtr(builder_g->scratch_g.type_map_g.data,"
                              "builder_g->scratch_g.type_map_g.len);")
    return signature + body


source = re.sub(r"(?m)^(static [^\n;]+\) \{\n)([\s\S]*?^\})", instrument, source)
position = source.index("/* ==== runtime_ext.h ==== */")
generated = output / "trace.c"
generated.write_text(source[:position] + h + source[position:])
command = json.loads((build / "stages/compile-and-link-program.json").read_text())["command"]
command[command.index("-O2")] = "-O0"
index = next(i for i, arg in enumerate(command) if Path(arg).name == "blot_goose.c")
include_directory = Path(command[index]).parent
command[index] = str(generated)
command.insert(1, "-I" + str(include_directory))
command[-1] = str(output / "trace")
with (output / "compile.log").open("w") as log:
    subprocess.run(command, stdout=log, stderr=log, check=True, timeout=120)
with (output / "build.json").open("w") as log:
    subprocess.run(["deno", "run", "-A", "scripts/integration/build_gdev.ts", "--compiler",
                    command[-1], "--gdev-root", args.gdev_root, "--frontend-workers", "8",
                    "--timeout-ms", "20000", output / "wasm"], stdout=log, check=True, timeout=25)
