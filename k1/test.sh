#!/bin/sh
# Tests only the experimental scalar fixture. This is not K1 qualification.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
: "${GOOSE:=goose}"
: "${GOOSE_HOME:=$script_dir/build/goose-home}"
export GOOSE_HOME
export GOOSE
"$script_dir/build.sh"
"$GOOSE" --debug "$script_dir/lexer_test.goose"
"$GOOSE" --debug "$script_dir/syntax_test.goose"
"$GOOSE" --debug "$script_dir/frontend_test.goose"
"$GOOSE" --debug "$script_dir/test_validate.goose"
"$GOOSE" --debug "$script_dir/artifact_test.goose"
"$GOOSE" --debug "$script_dir/artifact_v2_test.goose"
"$GOOSE" --debug "$script_dir/core_test.goose"
"$GOOSE" --debug "$script_dir/layout_test.goose"
"$GOOSE" --debug "$script_dir/scalar_core_test.goose"
"$GOOSE" --debug "$script_dir/scalar_plan_test.goose"
"$GOOSE" --debug "$script_dir/catalog_test.goose"
python3 "$script_dir/abi_fixed_oracle.py"
python3 "$script_dir/source_resolver_test.py"
python3 "$script_dir/particle_expr_oracle_test.py"
python3 "$script_dir/graph_oracle_test.py"
python3 "$script_dir/bounds_oracle_test.py"
python3 "$script_dir/loop_oracle_test.py"
python3 "$script_dir/loop_prefix_oracle_test.py"
python3 "$script_dir/proofgraph_inspect_test.py"
python3 "$script_dir/ownership_oracle_test.py"
for level in 0 2; do
    "$GOOSE" --debug "-O$level" "$script_dir/abi_fixed_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/blake3_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/public_frontend_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/public_interface_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/source_identity_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/retained_observations_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/retained_review_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/public_artifact_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/public_function_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/public_plan_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/interface_candidate_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/manifest_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/manifest_metered_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/fixture_geometry_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/fixture_geometry_metered_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/wasm_scalar_validation_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/work_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/work_schedule_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/proof_scopes_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/frontend_work_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/scalar_work_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/parser_work_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/scalar_core_metered_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/scalar_core_metered_fuzz_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/wasm_scalar_validation_metered_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/add_proof_metered_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/add_scoped_adversarial_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/add_source_metered_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/parser_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/module_core_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/core_adversarial_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/target_adversarial_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/name_index_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/verifier_optimization_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/verifier_adversarial_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/module_frontend_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/host_bridge_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/host_bridge_copy_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/host_bridge_copy_adversarial_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/builder_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/pool_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/proof_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/add_proof_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/add_frontend_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/add_parser_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/add_core_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/control_frontend_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/flow_parse_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/flow_mutation_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/flow_adversarial_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/flow_reachability_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/particle_expr_adversarial_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/graph_adversarial_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/owned_scalar_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/owned_scalar_source_mutation_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/owned_program_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/owned_program_mutation_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/owned_program_adversarial_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/closure_audit_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/locals_adversarial_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/locals_limits_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/affine_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/affine_runtime_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/affine_generated_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/affine_forgery_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/facts_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/facts_graph_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/facts_sequence_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/session_retained_adversarial_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/iteration_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/iteration_verify_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/iteration_verify_boundary_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/iteration_verify_smoke_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/ownership_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/ownership_runtime_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/ownership_adversarial_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/ownership_generated_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/ownership_scope_negative_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/proofgraph_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/proofgraph_random_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/proofgraph_oracle_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/proofgraph_contradiction_budget_test.goose"
done
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
for level in 0 2; do
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/pool_guest_emit.goose" && node "$script_dir/pool_guest_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/pool_builder_guest_emit.goose" && node "$script_dir/pool_builder_guest_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/particle_guest_emit.goose" && node "$script_dir/particle_guest_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/particle_expr_test.goose" && node "$script_dir/particle_expr_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/graph_test.goose" && node "$script_dir/graph_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/bounds_test.goose" && node "$script_dir/bounds_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/increment_test.goose" && node "$script_dir/increment_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/locals_test.goose" && node "$script_dir/locals_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/unified_test.goose" && node "$script_dir/unified_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/unified_guard_test.goose" && node "$script_dir/unified_guard_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/unified_guard_adversarial_test.goose" && node "$script_dir/unified_guard_adversarial_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/session_retained_test.goose" && node "$script_dir/session_retained_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/loop_test.goose" && node "$script_dir/loop_test.mjs" && node "$script_dir/loop_exhaustive_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/closure_test.goose" && node "$script_dir/closure_test.mjs" && node "$script_dir/closure_audit_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/generic_identity_test.goose" && node "$script_dir/generic_identity_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/bridge_wasm_fixture_emit.goose" && node "$script_dir/bridge_wasm_fixture_test.mjs" && node "$script_dir/bridge_wasm_restoration_test.mjs" && node "$script_dir/bridge_host_fixture_test.mjs")
done
for level in 0 2; do
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/module_wasm_test.goose" && node "$script_dir/module_wasm_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/add_wasm_test.goose" && node "$script_dir/add_wasm_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/add_scoped_test.goose" && node "$script_dir/add_scoped_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/scalar_thin_test.goose" && node "$script_dir/scalar_thin_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/public_fixture_test.goose" && node "$script_dir/public_fixture_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/public_snapshot_test.goose" && node "$script_dir/public_snapshot_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/retained_scalar_test.goose" && node "$script_dir/retained_scalar_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/control_wasm_test.goose" && node "$script_dir/control_wasm_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/flow_typed_test.goose" && node "$script_dir/flow_typed_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/flow_decl_test.goose" && node "$script_dir/flow_decl_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/scalar_plan_metered_test.goose" && node "$script_dir/scalar_plan_metered_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/scalar_pipeline_work_test.goose" && node "$script_dir/scalar_pipeline_work_test.mjs")
    (cd "$test_dir" && "$GOOSE" --debug "-O$level" "$script_dir/scalar_scheduled_test.goose" && node "$script_dir/scalar_scheduled_test.mjs")
done
(cd "$test_dir" && "$GOOSE" --debug "$script_dir/wasm_test.goose" && node "$script_dir/wasm_test.mjs")
(cd "$test_dir" && "$GOOSE" --debug "$script_dir/wasm_v2_test.goose" && node "$script_dir/wasm_v2_test.mjs")
cat > "$test_dir/control.blot" <<'CONTROL'
let f: Bool -> U32 = fn x => do:
  if x && #True:
    return 4294967295
  else:
    return 7
CONTROL
"$script_dir/build/blot-k1" control-fixture "$test_dir/control.blot" --trace > "$test_dir/control.hex" 2> "$test_dir/trace"
grep -q 'control fixture: validated source and control targets' "$test_dir/trace"
node -e 'const fs=require("node:fs");const b=Buffer.from(fs.readFileSync(process.argv[1],"utf8").trim(),"hex");WebAssembly.instantiate(b).then(({instance})=>{const f=instance.exports.f;if((f(0,0)>>>0)!==7||(f(0,1)>>>0)!==4294967295)process.exit(1)}).catch(()=>process.exit(1))' "$test_dir/control.hex"
printf 'let f: Bool -> U32 = fn x => do:\n  if x:\n    return 1\n' > "$test_dir/control.blot"
if "$script_dir/build/blot-k1" control-fixture "$test_dir/control.blot" > "$test_dir/rejected" 2> "$test_dir/error"; then
    echo 'missing control return was accepted' >&2; exit 1
fi
test ! -s "$test_dir/rejected"
grep -q 'k1_missing_return' "$test_dir/error"
cat > "$test_dir/flow.blot" <<'FLOW'
let choose: Bool -> U32 = fn flag => do:
  if flag && #True:
    if #False:
      return 1
    else:
      return 42
  return 17
FLOW
"$script_dir/build/blot-k1" flow-fixture "$test_dir/flow.blot" --trace > "$test_dir/flow.hex" 2> "$test_dir/trace"
grep -q 'source and typed control flow validated' "$test_dir/trace"
node -e 'const fs=require("node:fs");const b=Buffer.from(fs.readFileSync(process.argv[1],"utf8").trim(),"hex");WebAssembly.instantiate(b).then(({instance})=>{const f=instance.exports.choose;if((f(0,0)>>>0)!==17||(f(0,1)>>>0)!==42)process.exit(1)}).catch(()=>process.exit(1))' "$test_dir/flow.hex"
printf 'let f: Bool -> U32 = fn x => do:\n  return y\n' > "$test_dir/flow.blot"
if "$script_dir/build/blot-k1" flow-fixture "$test_dir/flow.blot" > "$test_dir/rejected" 2> "$test_dir/error"; then
    echo 'unbound flow name was accepted' >&2; exit 1
fi
test ! -s "$test_dir/rejected"
grep -q 'k1_unbound_name' "$test_dir/error"
cat > "$test_dir/locals.blot" <<'LOCALS'
let f: U32 -> U32 = fn x => do:
  let y = x & 255
  if y < 10:
    return U32.wrapping_add(y,1)
  else:
    return y
LOCALS
"$script_dir/build/blot-k1" locals-fixture "$test_dir/locals.blot" --trace > "$test_dir/locals.hex" 2> "$test_dir/trace"
grep -q 'bindings and checked arithmetic validated' "$test_dir/trace"
node -e 'const fs=require("node:fs");const b=Buffer.from(fs.readFileSync(process.argv[1],"utf8").trim(),"hex");WebAssembly.instantiate(b).then(({instance})=>{const f=instance.exports.f;if((f(0,9)>>>0)!==10||(f(0,256)>>>0)!==1||(f(0,10)>>>0)!==10)process.exit(1)}).catch(()=>process.exit(1))' "$test_dir/locals.hex"
cat > "$test_dir/locals.blot" <<'NESTED'
let f: U32 -> U32 = fn x => do:
  if x < 10 && #True:
    let y = U32.wrapping_add(x,1)
    if y < 5:
      return y
    else:
      return x
  return 99
NESTED
"$script_dir/build/blot-k1" locals-fixture "$test_dir/locals.blot" > "$test_dir/locals.hex"
node -e 'const fs=require("node:fs");const b=Buffer.from(fs.readFileSync(process.argv[1],"utf8").trim(),"hex");WebAssembly.instantiate(b).then(({instance})=>{const f=instance.exports.f;if((f(0,2)>>>0)!==3||(f(0,7)>>>0)!==7||(f(0,10)>>>0)!==99)process.exit(1)}).catch(()=>process.exit(1))' "$test_dir/locals.hex"
cat > "$test_dir/locals.blot" <<'GUARDED'
let f: U32 -> U32 = fn x => do:
  if x < 4294967295:
    return x + 1
  else:
    return x
GUARDED
"$script_dir/build/blot-k1" locals-fixture "$test_dir/locals.blot" > "$test_dir/locals.hex"
node -e 'const fs=require("node:fs");const b=Buffer.from(fs.readFileSync(process.argv[1],"utf8").trim(),"hex");WebAssembly.instantiate(b).then(({instance})=>{const f=instance.exports.f;if((f(0,0)>>>0)!==1||(f(0,4294967294)>>>0)!==4294967295||(f(0,4294967295)>>>0)!==4294967295)process.exit(1)}).catch(()=>process.exit(1))' "$test_dir/locals.hex"
printf 'let f: U32 -> U32 = fn x => do:\n  return x + 1\n' > "$test_dir/locals.blot"
if "$script_dir/build/blot-k1" locals-fixture "$test_dir/locals.blot" > "$test_dir/rejected" 2> "$test_dir/error"; then
    echo 'unproved local addition was accepted' >&2; exit 1
fi
test ! -s "$test_dir/rejected"
grep -q 'source error 5' "$test_dir/error"
grep -q 'k1_arithmetic_not_established' "$test_dir/error"
cat > "$test_dir/module.blot" <<'MODULE'
let a: U32 -> U32 = fn x => return b(x)
let c: U32 -> U32 = fn x => return b(4294967295)
let b: U32 -> U32 = fn x => return x & 2147483648
let d: U32 -> U32 = fn x => return a(x)
MODULE
"$script_dir/build/blot-k1" module-fixture "$test_dir/module.blot" --trace > "$test_dir/module.hex" 2> "$test_dir/trace"
grep -q 'module fixture: validated source' "$test_dir/trace"
grep -q 'module fixture: validated Core' "$test_dir/trace"
node "$script_dir/module_driver_test.mjs" "$test_dir/module.hex"
printf 'pub let answer: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n' > "$test_dir/public.blot"
"$script_dir/build/blot-k1" public-fixture "$test_dir/public.blot" --trace > "$test_dir/public.hex" 2> "$test_dir/trace"
grep -q 'source-bound snapshot validated and Wasm emitted' "$test_dir/trace"
node "$script_dir/driver_test.mjs" "$test_dir/public.hex" answer 42
printf 'pub let answer: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x + 1\n' > "$test_dir/public.blot"
if "$script_dir/build/blot-k1" public-fixture "$test_dir/public.blot" > "$test_dir/rejected" 2> "$test_dir/error"; then
    echo 'unsupported public fixture was accepted' >&2; exit 1
fi
test ! -s "$test_dir/rejected"
grep -q 'source error' "$test_dir/error"
printf 'let a: U32 -> U32 = fn x => return b(x)\nlet b: U32 -> U32 = fn x => return a(x)\n' > "$test_dir/module.blot"
if "$script_dir/build/blot-k1" module-fixture "$test_dir/module.blot" > "$test_dir/rejected" 2> "$test_dir/error"; then
    echo 'recursive module was accepted' >&2; exit 1
fi
test ! -s "$test_dir/rejected"
grep -q 'k1_recursive_call' "$test_dir/error"
printf 'let a: U32 -> U32 = fn x => return missing(x)\n' > "$test_dir/module.blot"
if "$script_dir/build/blot-k1" module-fixture "$test_dir/module.blot" > "$test_dir/rejected" 2> "$test_dir/error"; then
    echo 'unbound callee was accepted' >&2; exit 1
fi
test ! -s "$test_dir/rejected"
grep -q 'k1_unbound_name' "$test_dir/error"
printf 'let f: U32 -> U32 = fn x => return x + 0\n' > "$test_dir/add.blot"
"$script_dir/build/blot-k1" add-fixture "$test_dir/add.blot" --trace > "$test_dir/add.hex" 2> "$test_dir/trace"
grep -q 'add fixture: validated source and syntax' "$test_dir/trace"
grep -q 'add fixture: validated Core and evidence' "$test_dir/trace"
grep -q 'add fixture: revalidated plan and emitted Wasm module' "$test_dir/trace"
node -e 'const fs=require("node:fs");fs.writeFileSync(process.argv[2],Buffer.from(fs.readFileSync(process.argv[1],"utf8").trim(),"hex"));' "$test_dir/add.hex" "$test_dir/add_v4_0.wasm"
printf 'let f: U32 -> U32 = fn x => do:\n  return x + 0\n' > "$test_dir/add.blot"
"$script_dir/build/blot-k1" add-fixture "$test_dir/add.blot" > "$test_dir/add.hex"
node -e 'const fs=require("node:fs");fs.writeFileSync(process.argv[2],Buffer.from(fs.readFileSync(process.argv[1],"utf8").trim(),"hex"));' "$test_dir/add.hex" "$test_dir/add_v4_1.wasm"
printf 'let f: U32 -> U32 = fn x => return do:\n  break x + 0\n' > "$test_dir/add.blot"
"$script_dir/build/blot-k1" add-fixture "$test_dir/add.blot" > "$test_dir/add.hex"
node -e 'const fs=require("node:fs");fs.writeFileSync(process.argv[2],Buffer.from(fs.readFileSync(process.argv[1],"utf8").trim(),"hex"));' "$test_dir/add.hex" "$test_dir/add_v4_2.wasm"
(cd "$test_dir" && node "$script_dir/add_wasm_test.mjs")
if "$script_dir/build/blot-k1" fixture "$test_dir/add.blot" > "$test_dir/rejected" 2> "$test_dir/error"; then
    echo 'legacy scalar fixture accepted addition' >&2; exit 1
fi
test ! -s "$test_dir/rejected"
for expression in 'x + 1' 'x + 4294967295' 'x + x' '0 + x'; do
    printf 'let f: U32 -> U32 = fn x => return %s\n' "$expression" > "$test_dir/add.blot"
    if "$script_dir/build/blot-k1" add-fixture "$test_dir/add.blot" > "$test_dir/rejected" 2> "$test_dir/error"; then
        echo 'unproved addition was accepted' >&2; exit 1
    fi
    test ! -s "$test_dir/rejected"
    grep -q 'k1_arithmetic_not_established' "$test_dir/error"
done
for case_id in name type overflow; do
    case "$case_id" in
        name) expression='let f: U32 -> U32 = fn x => return y + 0'; category=k1_unbound_name ;;
        type) expression='let f: U32 -> Bool = fn x => return x + 0'; category=k1_type_mismatch ;;
        overflow) expression='let f: U32 -> U32 = fn x => return x + 4294967296'; category=k1_syntax ;;
    esac
    printf '%s\n' "$expression" > "$test_dir/add.blot"
    if "$script_dir/build/blot-k1" add-fixture "$test_dir/add.blot" > "$test_dir/rejected" 2> "$test_dir/error"; then
        echo 'invalid checked-add source was accepted' >&2; exit 1
    fi
    test ! -s "$test_dir/rejected"
    grep -q "$category" "$test_dir/error"
done
printf 'let id: U32 -> U32 = fn x => return x\n' > "$test_dir/input.blot"
"$script_dir/build/blot-k1" fixture "$test_dir/input.blot" --trace > "$test_dir/module.hex" 2> "$test_dir/trace"
grep -q 'validated scalar structure' "$test_dir/trace"
grep -q 'validated scalar Wasm structure' "$test_dir/trace"
grep -q 'validated owned scalar syntax' "$test_dir/trace"
grep -q 'completed metered scalar Core' "$test_dir/trace"
grep -q 'validated typed scalar lowering plan' "$test_dir/trace"
node "$script_dir/driver_test.mjs" "$test_dir/module.hex"
printf 'let value: U32 -> U32 = fn x => return 4294967295\n' > "$test_dir/input.blot"
"$script_dir/build/blot-k1" fixture "$test_dir/input.blot" > "$test_dir/module.hex"
node "$script_dir/driver_test.mjs" "$test_dir/module.hex" value 4294967295
printf 'let id: U32 -> U32 = fn x => do:\n  return x\n' > "$test_dir/input.blot"
"$script_dir/build/blot-k1" fixture "$test_dir/input.blot" > "$test_dir/module.hex"
node "$script_dir/block_test.mjs" "$test_dir/module.hex" identity
printf 'let id: U32 -> U32 = fn x => return do:\n  break x\n' > "$test_dir/input.blot"
"$script_dir/build/blot-k1" fixture "$test_dir/input.blot" > "$test_dir/module.hex"
node "$script_dir/block_test.mjs" "$test_dir/module.hex" identity
printf 'let id: U32 -> U32 = fn x => do:\n  return do:\n    break 42\n' > "$test_dir/input.blot"
"$script_dir/build/blot-k1" fixture "$test_dir/input.blot" > "$test_dir/module.hex"
node "$script_dir/block_test.mjs" "$test_dir/module.hex" constant
printf 'let id: U32 -> U32 = fn x => do:\n  break x\n' > "$test_dir/input.blot"
if "$script_dir/build/blot-k1" fixture "$test_dir/input.blot" > "$test_dir/rejected" 2> "$test_dir/error"; then
    echo 'invalid break was accepted' >&2; exit 1
fi
test ! -s "$test_dir/rejected"
grep -q 'source error 6' "$test_dir/error"
printf 'let f: U32 -> U32 = fn x => return x & 2147483648\n' > "$test_dir/input.blot"
"$script_dir/build/blot-k1" fixture "$test_dir/input.blot" > "$test_dir/module.hex"
node "$script_dir/driver_v2_test.mjs" "$test_dir/module.hex" and
printf 'let f: U32 -> Bool = fn x => return 2147483648 < x\n' > "$test_dir/input.blot"
"$script_dir/build/blot-k1" fixture "$test_dir/input.blot" > "$test_dir/module.hex"
node "$script_dir/driver_v2_test.mjs" "$test_dir/module.hex" lt
printf 'let f: U32 -> U32 = fn x => return x < 1\n' > "$test_dir/input.blot"
if "$script_dir/build/blot-k1" fixture "$test_dir/input.blot" > "$test_dir/rejected" 2> "$test_dir/error"; then
    echo 'type mismatch was accepted' >&2; exit 1
fi
test ! -s "$test_dir/rejected"
grep -q 'k1_type_mismatch' "$test_dir/error"
printf 'let id: U32 -> U32 = fn x => return y\n' > "$test_dir/input.blot"
if "$script_dir/build/blot-k1" fixture "$test_dir/input.blot" > "$test_dir/rejected" 2> "$test_dir/error"; then
    echo 'unsupported input was accepted' >&2; exit 1
fi
test ! -s "$test_dir/rejected"
grep -q 'source error' "$test_dir/error"
if "$script_dir/build/blot-k1" build "$test_dir/input.blot" "$test_dir/out.wasm" > "$test_dir/rejected" 2> "$test_dir/error"; then
    echo 'public build was accepted' >&2; exit 1
fi
test ! -e "$test_dir/out.wasm"
grep -q 'not qualified' "$test_dir/error"
if "$script_dir/build/blot-k1" check "$test_dir/input.blot" > "$test_dir/rejected" 2> "$test_dir/error"; then
    echo 'public check was accepted' >&2; exit 1
fi
grep -q 'not qualified' "$test_dir/error"
# A complete read at the exact limit is allowed to reach parsing; one byte
# more must be rejected before parsing, and read failures must be reported.
node -e 'const fs = require("node:fs"); const source = Buffer.alloc(16777216, 32); source.write("let id: U32 -> U32 = fn x => return x\n"); fs.writeFileSync(process.argv[1], source);' "$test_dir/limit.blot"
"$script_dir/build/blot-k1" fixture "$test_dir/limit.blot" > "$test_dir/limit.hex"
node "$script_dir/driver_test.mjs" "$test_dir/limit.hex"
node -e 'require("node:fs").appendFileSync(process.argv[1], Buffer.from([0]));' "$test_dir/limit.blot"
if "$script_dir/build/blot-k1" fixture "$test_dir/limit.blot" > "$test_dir/rejected" 2> "$test_dir/error"; then
    echo 'oversized fixture was accepted' >&2; exit 1
fi
test ! -s "$test_dir/rejected"
grep -q 'source exceeds the 16 MiB limit' "$test_dir/error"
if "$script_dir/build/blot-k1" fixture "$test_dir/missing.blot" > "$test_dir/rejected" 2> "$test_dir/error"; then
    echo 'missing fixture was accepted' >&2; exit 1
fi
test ! -s "$test_dir/rejected"
grep -q 'cannot read source file' "$test_dir/error"
echo 'bounded source input passed'
