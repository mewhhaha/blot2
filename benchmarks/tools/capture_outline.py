# GDB script for capture_outline.ts. Captures private, compiler-produced IR only.
# Replay through compiler/src/bench_outline.zig and the fingerprinted compiler;
# this format is not an authority for caller-supplied or untrusted IR.
import gdb
import hashlib
import json
import os
import time

output = os.environ["OUTLINE_CAPTURE"]
control = os.path.join(output, "control")


def wait_for(name, timeout=8):
    path = os.path.join(control, name)
    deadline = time.monotonic() + timeout
    while not os.path.exists(path):
        if time.monotonic() >= deadline:
            raise RuntimeError("timed out waiting for " + name)
        pid_path = os.path.join(control, "pid")
        if os.path.exists(pid_path):
            try:
                os.kill(int(open(pid_path).read().strip()), 0)
            except ProcessLookupError:
                raise RuntimeError("compiler exited while waiting for " + name)
        time.sleep(0.01)


def value_pointer(value):
    if value.type.strip_typedefs().code == gdb.TYPE_CODE_PTR:
        return value.dereference()
    return value


def array_items(value):
    return value["items"]


def capture_span(binary_file, inferior, value):
    global offset
    count = int(value["len"])
    item_size = int(value["ptr"].type.target().sizeof)
    size = count * item_size
    start = offset
    if size:
        binary_file.write(inferior.read_memory(int(value["ptr"]), size))
        offset += size
    return {"offset": start, "bytes": size, "count": count}


gdb.execute("set pagination off")
gdb.execute("set confirm off")
gdb.execute("set print elements 0")
gdb.execute("set debuginfod enabled off")
attached = False
try:
    wait_for("pid")
    compiler = os.environ["OUTLINE_BINARY"]
    gdb.execute('file "' + compiler.replace('\\', '\\\\').replace('"', '\\"') + '"')
    pid = int(open(os.path.join(control, "pid")).read().strip())
    gdb.execute("attach " + str(pid))
    attached = True
    breakpoint = gdb.Breakpoint(
        "backend.wasm_scope_outline.Context.finalize", internal=True
    )
    open(os.path.join(control, "attached"), "w").write("1")
    wait_for("start")
    gdb.execute("continue")

    frame = gdb.newest_frame()
    frame_name = frame.name() or ""
    if "wasm_scope_outline.Context.finalize" in frame_name:
        context = value_pointer(frame.read_var("self"))
    elif "scoped_backend.compileWithOptions" in frame_name:
        context = value_pointer(frame.read_var("outlining"))
    else:
        raise RuntimeError("unexpected compiler stop frame: " + frame_name)

    module = value_pointer(context["module"])
    inferior = gdb.selected_inferior()
    metadata = {
        "format": 1,
        "compiler": compiler,
        "compiler_sha256": os.environ["OUTLINE_COMPILER_SHA256"],
        "source_sha256": os.environ["OUTLINE_SOURCE_SHA256"],
        "functions": [],
        "roots": [],
        "helpers": [],
        "signatures": [],
        "imports": [],
    }
    offset = 0
    with open(os.path.join(output, "ir.bin"), "wb") as binary_file:
        functions = array_items(module["functions"])
        for index in range(int(functions["len"])):
            function = functions["ptr"][index]
            metadata["functions"].append(
                {
                    "id": index,
                    "parameters": capture_span(
                        binary_file, inferior, function["parameters"]
                    ),
                    "locals": capture_span(
                        binary_file, inferior, array_items(function["locals"])
                    ),
                    "instructions": capture_span(
                        binary_file,
                        inferior,
                        array_items(function["instructions"]),
                    ),
                    "result": int(function["result"]),
                    "signature": int(function["signature"]),
                }
            )

        roots = array_items(context["roots"])
        for index in range(int(roots["len"])):
            metadata["roots"].append(
                {"function": int(roots["ptr"][index]["function"])}
            )

        helpers = array_items(context["helpers"])
        for index in range(int(helpers["len"])):
            helper = helpers["ptr"][index]
            metadata["helpers"].append(
                {
                    "function": int(helper["function"]),
                    "root": int(helper["root"]),
                    "rbd": capture_span(
                        binary_file, inferior, helper["read_before_def"]
                    ),
                    "expressions": int(helper["credit"]["expressions"]),
                    "layouts": int(helper["credit"]["layouts"]),
                }
            )

        signatures = array_items(module["signatures"])
        for index in range(int(signatures["len"])):
            signature = signatures["ptr"][index]
            metadata["signatures"].append(
                {
                    "parameters": capture_span(
                        binary_file, inferior, signature["parameters"]
                    ),
                    "result": int(signature["result"]),
                }
            )

        imports = array_items(module["imports"])
        for index in range(int(imports["len"])):
            metadata["imports"].append(
                int(imports["ptr"][index]["signature"])
            )
        metadata["globals"] = int(array_items(module["globals"])["len"])

    with open(os.path.join(output, "ir.bin"), "rb") as binary_file:
        metadata["binary_bytes"] = offset
        metadata["binary_sha256"] = hashlib.sha256(binary_file.read()).hexdigest()
    with open(os.path.join(output, "ir.json"), "w") as metadata_file:
        json.dump(metadata, metadata_file, indent=2)
        metadata_file.write("\n")

    breakpoint.delete()
    gdb.execute("detach")
    attached = False
    open(os.path.join(control, "detached"), "w").write("1")
except Exception as error:
    gdb.write("outline capture failed: " + str(error) + "\n", gdb.STDERR)
    if attached:
        try:
            gdb.execute("detach")
        except gdb.error:
            pass
    gdb.execute("quit 1")
