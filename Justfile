# Build, test, and install Blot 2 syntax highlighting for Helix.
install:
  deno task helix:install

# Build the native Bend compiler executable used by Deno.
build:
  deno task build:compiler

# Check formatting, types, Bend laws, and compiler/editor-config regressions.
check:
  deno task check

# Execute the generic-prelude Wasm example, then print the inferred ECS plan.
demo:
  deno task demo

# Measure the JS reference with the generic prelude and a wide module.
bench:
  deno task bench

# Compile and execute the scalar gdev-style ECS port with an explicit provider.
ecs:
  deno task demo:ecs

# Measure JS reference ECS workloads, excluding Bend bootstrap.
bench-ecs samples="7" report="build/ecs-bench.json":
  deno task bench:ecs {{quote(samples)}} {{quote(report)}}

# Compare native subprocess compilation against the JavaScript reference.
bench-native samples="7" report="build/native-bench.json" threads="1,2,4,8":
  deno task bench:native {{quote(samples)}} {{quote(report)}} {{quote(threads)}}

# Measure clean builds, semantic edits, cache reuse, and state-preserving reload.
bench-incremental samples="5" report="build/incremental-bench.json" workers="1,2,4,8":
  deno task bench:incremental {{quote(samples)}} {{quote(report)}} {{quote(workers)}}

# Save a CPU profile of full ECS compiles; use bench-ecs for unprofiled timings.
profile-ecs systems="64" iterations="3" output="build/ecs.cpuprofile":
  deno task profile:ecs {{quote(systems)}} {{quote(iterations)}} {{quote(output)}}

# Compile the implemented source-language slice to Wasm.
compile source="examples/prelude.blot" output="build/example.wasm":
  deno task blot build {{quote(source)}} {{quote(output)}}
