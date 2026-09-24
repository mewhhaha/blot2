# Build, test, and install Blot syntax highlighting for Helix.
install:
  deno task helix:install

# Build the native Bend compiler executable used by Deno.
build:
  deno task build:compiler

# Print the compact executable-language reference for people and LLMs.
guide:
  deno task blot guide

# Compile and execute the headless source-defined ECS example.
study:
  deno task study:ecs

# Check formatting, types, Bend laws, and compiler/editor regressions.
check:
  deno task check

# Execute the generic-prelude Wasm example.
demo:
  deno task demo

# Execute explicit host callbacks and a source-defined effect provider.
demo-host:
  deno task demo:host

# Measure the JS reference with the generic prelude and a wide module.
bench:
  deno task bench

# Compare clean compilation, native declaration edits, and cache reuse.
bench-native samples="7" report="build/native-bench.json" threads="1,2,3,4,5,6,7,8" warmups="2":
  deno task bench:native {{quote(samples)}} {{quote(report)}} {{quote(threads)}} {{quote(warmups)}}

# Linux physical-core affinity, fresh samples, retained-process controls, optional baseline project.
bench-cpu samples="9" report="build/cpu-scaling.json" projects="." threads="1,2,3,4,5,6,7,8" workloads="balanced_64,uneven_64,clustered_64,chain_64,reader_8,reader_64" regimes="full,incremental,reuse":
  deno task bench:cpu {{quote(report)}} {{quote(projects)}} {{quote(samples)}} {{quote(threads)}} {{quote(workloads)}} {{quote(regimes)}}

# Calibrate compiler task grains, checking every result against a serial run.
bench-grains iterations="32" samples="3" phases="codegen,check,prepare":
  deno task build:compiler:js
  mkdir -p build
  BEND_NO_TELEMETRY=1 bend compiler/parallel_grain_bench.bend -o build/parallel-grain-bench
  deno run --allow-read=build/parallel-grain-bench,generated/compiler/compiler.js --allow-write=build --allow-run=build/parallel-grain-bench compiler/parallel_grain_bench.ts build/parallel-grain-bench build/parallel-grains.json {{quote(iterations)}} {{quote(samples)}} {{quote(phases)}}

# Compile the implemented source-language core to Wasm.
compile source="examples/prelude.blot" output="build/example.wasm":
  deno task blot build {{quote(source)}} {{quote(output)}}
