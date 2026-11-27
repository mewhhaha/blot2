# Replaying a structural Gdev edit

This Linux experiment retains a direct-backend generator, then measures how
much work it takes to emit complete Wasm after a named function changes.
The runner checks each result against a separate fresh Gdev build.

From the Squid repository root, with the patched Goose toolchain and profiled
Squid compiler already built, run

```sh
python3 benchmarks/tools/structural_body/build.py
deno run -A benchmarks/tools/structural_body/capture.ts
python3 benchmarks/tools/structural_body/run.py --rounds 12
```

The build copies compiler sources and the Goose standard library to scratch
storage, instruments the copy, and fingerprints the inputs and executables.
Capture reads Git archives from the existing Squid, Gdev and Ink repositories.
The 293-module graph uses Squid std from `bdd1f678`, Gdev `cc4bbbf` and Ink
`77697fe`. Source overlays apply only to the captured project. Set
`SQUID_COMPILER` to select the reference executable. The capture library
requires its matching native worker queue layout. Each capture builds with
and without that library and validates the resulting Wasm.

The checkpoint records lookup events while emitting named instances. After
it writes its baseline Wasm and signals readiness, the runner sends the edit
locations. Each edit runs in a forked child of the same unmodified checkpoint.
The runner checks the baseline, every full reference emission and every
accepted image against independent compiler output. Each rejected child must
leave its candidate file absent. Alternating order exercises accepted edits
after a rejected edit.

The runner writes `build/structural-body/summary.json` and `runs.json.gz`.
The raw records contain per-checkpoint setup and per-edit timings.

| Measurement | Timed work |
| --- | --- |
| `buildNs` | Initial direct emission and assembly, with or without lookup recording, after decoding the baseline |
| `decodeNs` | Read and decode 293 edited Core packets in the child |
| `compareNs` | Compare decoded modules and select the edited declaration from its source offset |
| `replayNs` | Rebuild type mappings, check instance lookups, emit the selected body and assemble accepted Wasm |
| `fullNs` | Full emission from decoded edited Core in the same binary with recording disabled |
| `forkToDecisionNs` | From just before fork through writing and closing the candidate file, or through deciding to decline. Recorded when replay runs first |

The runner releases results after independent byte comparison. The measurements
exclude source loading and type checking. The trace storage counter includes
reserved array capacity. The parent retains a full generator plus its baseline
image in addition to those arrays.
