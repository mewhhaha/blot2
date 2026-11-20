"""Trace constructor signature reads in Gdev after a fresh parent receives Core.

Use the optimized Goose C emission of either measured compiler. The trace
writes one file per process. M records a module and its Core packet size.
C records a constructor (unit, local ordinal, identity, nominal, tag,
payload and scheme). T counts Core type nodes, type words and executable
nodes. R records a signature read (consumer, module, identity and root).
The optional erasure is a diagnostic on the parent's private decoded data.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("--compiler-build", type=Path, default=Path("compiler-goose/build"))
parser.add_argument("--gdev-root", type=Path, default=Path("../gdev"))
parser.add_argument("--erase-imports", action="store_true")
args = parser.parse_args()
build = args.compiler_build.resolve()
output = args.output.resolve()
identity = json.loads((build / "source-identity.json").read_text())
emissions = {
    "c70f881340adda24f7b4a22d659783fa195e0042e16cc833208bded7fd346117",
    "de1f36fb453905bcdbec27f583cc272164346ba4b3365dc4c52bbe22d2dc53e4",
}
if identity["digest"] not in emissions:
    raise SystemExit("Use a compiler emission fingerprinted in the measurement.")
output.mkdir(parents=True, exist_ok=False)
source = (build / "blot_goose.c").read_text()

OBSERVER = r'''
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
static int traced_parent;
static FILE *trace_file(void) {
    static FILE *file;
    static int pid;
    if (pid != getpid()) {
        char path[4096];
        pid = getpid();
        snprintf(path,sizeof(path),TRACE_DIR"/events-%d.tsv",pid);
        file = fopen(path,"a");
        if (!file) abort();
        setlinebuf(file);
    }
    return file;
}
static void received(const blot_check_core_Module_g15 *m, long packet) {
    traced_parent=1;
    if (ERASE_SIGNATURES) {
        for (int64_t i=1; i<m->constructors_g.len; i++) {
            blot_check_core_Constructor_g15 *c=&m->constructors_g.data[i];
            if (c->identity_g.unit_g != m->unit_g) memset(&c->scheme_g,0,sizeof(c->scheme_g));
        }
    }
    FILE *f=trace_file();
    fprintf(f,"M %u %ld %ld %zu\n",m->unit_g,packet,(long)m->constructors_g.len,sizeof(blot_check_core_Constructor_g15));
    fprintf(f,"T %u %ld %ld %ld\n",m->unit_g,(long)m->types_g.nodes_g.len,(long)m->types_g.extra_g.len,(long)m->nodes_g.len);
    for (int64_t i=1; i<m->constructors_g.len; i++) {
        blot_check_core_Constructor_g15 c=m->constructors_g.data[i];
        blot_check_types_Scheme_g16 x=c.scheme_g;
        fprintf(f,"C %u %ld %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u\n",
          m->unit_g,(long)i,c.identity_g.unit_g,c.identity_g.decl_g,c.nominal_g,c.tag_g,c.payload_g,x.root_g,x.variables_g.start_g,x.variables_g.len_g,
          x.row_variables_g.start_g,x.row_variables_g.len_g,x.closed_rows_g.start_g,x.closed_rows_g.len_g,x.obligations_g.start_g,x.obligations_g.len_g,x.generative_g.start_g,x.generative_g.len_g);
    }
}
static void consumed(const blot_check_core_Module_g15 *m, blot_check_core_Constructor_g15 c, const char *stage) {
    if (traced_parent) fprintf(trace_file(),"R %s %u %u %u %u\n",stage,m->unit_g,c.identity_g.unit_g,c.identity_g.decl_g,c.scheme_g.root_g);
}
'''

position = source.index("/* ==== runtime_ext.h ==== */")
observer = OBSERVER.replace("TRACE_DIR", json.dumps(str(output)))
observer = observer.replace("ERASE_SIGNATURES", str(int(args.erase_imports)))
source = source[:position] + observer + source[position:]
sites = {}


def instrument(match):
    signature, body = match.groups()
    name = signature.split("(")[0].split()[-1]
    if name == "blot_reuse_partial_dependency_readPersistentCore_g29":
        install = r"(?m)^( +t\d+\[GS_IDX[^\n]+ = core_g;)"
        body, count = re.subn(install, r"    received(&core_g,bytes_g_len);\n\1", body)
        assert count == 1
    variable = "constructor_g"
    if name.startswith("blot_direct_"):
        owner = "owner_g"
        if "constructedType_" in name:
            variable = "declared_g"
    elif name.startswith("blot_check_package_core_"):
        owner = "self__g->module_g"
    elif name.startswith("blot_check_staging_core_"):
        owner = "self__g->m_g"
        if "descriptorFields_" in name:
            owner = "module_g"
    elif name.startswith("blot_eval_implementation_evidence_nominalFields_"):
        owner = "module_g"
    elif name.startswith("blot_check_frozen_core_validation_"):
        owner = "m_g"
        variable = "value_g_5"
        if "listRoles_" in name:
            variable = "c_g"
    elif name.startswith("blot_reuse_dependency_symbol_slots_coreRoles_"):
        owner = "ir_g"
        variable = "value_g_4"
    else:
        return signature + body
    if not re.search(r"\bblot_check_core_Constructor_g15 " + variable + r"\b", signature + body):
        return signature + body
    field = r"(?m)^( +)([^\n]*?\b" + variable + r"\.scheme_g[^\n]+)"
    observe = lambda m: m[1] + f'consumed({owner},{variable},"{name}");\n' + m[0]
    body, count = re.subn(field, observe, body)
    if count:
        sites[name] = count
    return signature + body


source = re.sub(r"(?m)^(static [^\n;]+\) \{\n)([\s\S]*?^\})", instrument, source)
assert len(sites) == 27
(output / "sites.json").write_text(json.dumps(sites, indent=2) + "\n")
generated = output / "trace.c"
generated.write_text(source)
command = json.loads((build / "stages/compile-and-link-program.json").read_text())["command"]
command[command.index("-O2")] = "-O0"
index = next(i for i, arg in enumerate(command) if Path(arg).name == "blot_goose.c")
includes = Path(command[index]).parent
command[index] = str(generated)
command.insert(1, "-I" + str(includes))
command[-1] = str(output / "trace")
with (output / "compile.log").open("w") as log:
    subprocess.run(command, check=True, stdout=log, stderr=log, timeout=120)
with (output / "gdev.json").open("w") as log:
    subprocess.run(["deno", "run", "-A", "scripts/integration/build_gdev.ts", "--compiler",
                    command[-1], "--gdev-root", args.gdev_root, "--frontend-workers", "8",
                    "--timeout-ms", "20000", output / "wasm"], check=True, stdout=log, timeout=25)
