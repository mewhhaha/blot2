# Portable optional helper-contract audit

`m12_audit_emit.py` requires Python 3's standard library and Node.js. It decodes the separately source-checked, exact guarded target through the existing byte pin, symbolically constructs 49 deterministic QF_AUFBV SMT-LIB queries, and writes a hash manifest. It does not run or require a solver and says so explicitly. Source/target validation must first run through the shared Goose `m12_helper_source_test.goose`; a byte pin on its own is not source authority.

An independent audit may run `m12_audit_check.py --target PATH --queries DIR --solver /path/to/solver`, with repeated `--solver-arg` if that solver needs CLI options. The checker regenerates the complete expected target-bound query set, verifies all names, expected statuses and content hashes, and requires each explicit solver invocation to return exactly the expected `sat` or `unsat`. Unknown, timeout, solver failure, target mismatch and missing/altered queries fail closed. This optional check requires the user-selected SMT-LIB solver and trusts that solver; generating queries is not equivalent to proving them. A solver is not bundled or used by the generator. No undeclared library is used by generation or checking.

The queries cover conditional path-by-path semantic equivalence for helper functions 1, 4, 5, 6, 8, 11, 12 and 13, owner-premise composition, explicit satisfiability controls, and deliberate instruction mutations. They model word-aligned 32-bit metadata, abstract calls to separately checked helpers, and require private protected memory and globally consistent allocation state. They do not verify arbitrary Wasm, initialize input bytes, establish source-level loans or owner provenance, ensure trap recovery, or qualify public ABI, M11 or C09. This audit imports an SMT solver only for optional external checking; it is not the K1 compiler's required closed proof algebra.

The separate scratch `cross_owner_counterexample.mjs` shows that forging a second raw owner record for the same occupied run can fool local owner checks. Hiding raw memory and establishing the global pool invariant are essential; integers and raw records do not grant authority. The newer global invariant and actual finder/reserve composition work remains separately reviewed scratch, not included in these 49 queries.

For a private developer audit, from an empty artifact directory first run the source and target check:

```sh
"$GOOSE" --debug -O2 "$script_dir/m12_helper_source_test.goose"
python3 "$script_dir/m12_audit_emit.py" --target private-invoke.wasm --out audit-queries
python3 "$script_dir/m12_audit_negative_test.py" private-invoke.wasm audit-queries
```

To actually solve the generated queries, explicitly supply an installed solver that accepts one SMT-LIB file as an argument, for example:

```sh
python3 "$script_dir/m12_audit_check.py" --target private-invoke.wasm \
  --queries audit-queries --solver /path/to/z3 --solver-arg=-smt2
```

The first command sequence works without a solver and proves only that query generation and negative checks ran. There is no solver-dependent mandatory test registration or automatic success when a solver is absent.
