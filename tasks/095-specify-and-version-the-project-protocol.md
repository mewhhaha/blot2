# 095 — Specify and version the project protocol

## Status, dependencies, and originating requirements

- **Status:** Complete.
- **Dependencies:** None.
- **Originating requirements:** the owner's decision of 11 October 2026, relayed
  by the gdev session and recorded in gdev's `PEN_MIGRATION.md` ("Decisions",
  phase 1): pen drives `blotc serve-project` from Rust to keep incremental
  rebuilds, so the frame protocol becomes a public, versioned contract that pen
  pins.
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

A written specification of the `serve-project` protocol that a non-Deno host can
implement, with an explicit version that both sides check.

## Starting point

Only [zig_project_server.zig](../zig-native/src/reuse/zig_project_server.zig)
and [compiler/zig_project_client.ts](../compiler/zig_project_client.ts) know the
length-prefixed frames (JSON metadata plus a binary payload), the request kinds
(open, build with source overlays, dispose), the reply shapes (build success
with Wasm, stats and assets; diagnostics with `details`) and the failure rules.
Nothing names a version.

## Implementation checklist

- [x] Write the specification: framing and limits, every request and reply
      field, ordering and epochs, revisions, cancellation, diagnostics
      (including `details` payloads), stats, and process failure behavior.
- [x] Add a protocol version to the handshake or first reply; reject mismatches
      with a defined error on both sides.
- [x] Make the TypeScript client and the server follow the specification
      exactly, with tests that check every documented field and error.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- A conformance test drives `blotc serve-project` from a minimal client written
  only from the specification, outside the TypeScript client.
- Version mismatch, malformed frames, oversized frames and cancellation each
  produce their specified behavior.

## Acceptance criteria

- [x] A host can implement the protocol from the specification alone, and a
      mismatched version fails clearly on both sides.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Implementation: `4eabecb`; explicit client-version admission, a complete
  protocol contract and an independent raw-wire conformance host.
- Validation: Zig 0.17.0; `deno task test:compiler` passes the full native suite
  and 690 guest/client tests. Analyzer: zero findings across 318 files,
  including three unregistered asset files under development. Deno type/format
  checks and local-link review pass.
- Comparison: public examples, synthetic fresh/retained phases and frozen gdev
  preserve Wasm in the jointly qualified 095/097 candidate; no protocol
  throughput improvement is claimed.
- Remaining limitations: raw conformance does not force native OOM, 2^53
  revision exhaustion or a naturally oversized successful output. Existing
  integer/enum coercions are documented and pinned; hosts emit canonical types.
- Durable record: [project protocol](../zig-native/PROJECT_PROTOCOL.md),
  including qualification and the final executable pin.
