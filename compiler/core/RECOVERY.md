# Native core checkpoint

This checkpoint attaches the previously uploaded native storage and bootstrap
sources to PR #7 so progress is durable. It is not a completed compiler build.
The lost local checkout's full implementation and test results have not yet been
reproduced from these recovered files. The bootstrap generator needs verification;
remaining build/runtime support is being restored in subsequent commits.

The default Bend compiler and its source semantics are unchanged. The native
compiler will remain an explicit experimental path until its clean build and
compatibility checks pass. The broader level solver, typed-body specialization,
and semantic dependency redesign remain work in progress.

The Core checkpoint workflow archives the exact committed source at every push,
including commits whose subsequent validation fails. Build outputs and test logs
are workflow artifacts rather than opaque blobs checked into source control.
