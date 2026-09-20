# Proposal: explicit host functions, source-defined services

This is the broader target API, not the current complete FFI. The compiler
rejects game/GUI intrinsics and implements generic operations/providers, sealed
`Foreign` effects and scalar host callbacks through [guest ABI 1](guest-abi.md).
Records, arrays, runtime Text, persistent guest values and the record-bundle
entrypoint adapter below still need implementation. The full Blot specimen is
[examples/host_capabilities.blot](../examples/host_capabilities.blot).

## Source contract

`io` is an ordinary record of functions supplied by the caller. `main` is an
ordinary exported function selected by the host, not a privileged declaration.
The compiler knows neither name and does not inject capabilities.

```blot
data WindowIo = WindowIo {
  set_title: Text -> Result Unit IoError ! {Foreign},
}

data RenderIo = RenderIo {
  submit: RenderFrame -> Result Unit IoError ! {Foreign},
}

data Io = Io {
  window: WindowIo,
  render: RenderIo,
}

export fn main (io: Io) => do:
  use titled <- io.window.set_title "Blot sandbox"
  return case titled of
    Err error => Err error
    Ok () => Ok (Application {
      create: create_world,
      update: update io.render,
    })
```

`WindowIo`, `RenderIo`, `Io`, `Application` and `IoError` belong to source
libraries. Add audio or networking by defining another record and passing its
functions, without editing the compiler. Pass a narrower record to a subsystem;
the update callback above captures rendering authority, not window authority.
There is no default global IO object, capability lookup by name, or fallback.

`Foreign` is the implemented, sealed generic foreign-call effect, currently a
built-in annotation label; it is not a window/render effect or an authority
token. Calling a host-backed function contributes it to the inferred row and is
forbidden in const evaluation or a pure `let` RHS. Merely receiving/storing a
callback is pure. A safe Blot program cannot turn an integer, string, cast, or
descriptor into a host callable. Pure tests can mock the source effect through a
provider, as shown below, without invoking a foreign function.

## Host contract

The following is proposed adapter pseudocode; `instantiate_record_guest`, plain
record arguments, `expect_ok`, and the platform staging functions are not
current runtime APIs. They illustrate the boundary, not a new dependency to
install.

```ts
const guest = await instantiate_record_guest(wasm);

const io = {
  window: {
    set_title: (title) => platform.stage_title(title),
  },
  render: {
    submit: (frame) => renderer.stage_frame(frame),
  },
};

// stage_* validate/enqueue a command and return Ok(Unit) or Err(IoError).
// The engine wraps initialization in a transaction, committing only on success.
const app = expect_ok(guest.call("main", io));

let world = app.create(null); // Unit is null; world is an opaque guest value.
// Within a frame transaction:
const next_world = app.update(world)(frame_input);
// On Ok: publish the successor world and validated queued commands together.
// On Err/trap: discard candidate state/commands and keep the previous world.
```

The generic adapter checks the selected export's schema and encodes the record
and callbacks. This is not `instance.exports.main(a_js_object)` against the
current scalar Wasm ABI. A callback has a validated argument/result schema;
expected failures use `Result`, while unexpected JS exceptions abort the call
with a diagnostic. The implemented scalar ABI is synchronous: a returned Promise
is rejected, not silently treated as a value. Async IO needs an explicit later
protocol.

The host handles platform resources, GPU submission and reloading. It does not
register components, execute system policy, or inspect the world. The ECS lives
in Blot; world values stay guest-owned behind opaque handles. The `Application`
frame convention is an engine-library protocol, not compiler knowledge.

## Effects remain composable

Explicit callback invocation is sufficient for simple code. A library can add
named, source-declared effects when code should be independent of its provider:

```blot
effect Window.set_title: Text -> Result Unit IoError

fn window_provider (window_io: WindowIo) =>
  @effect.provider Window.set_title window_io.set_title

fn announce () => Window.set_title "Blot sandbox"

export fn configured (io: Io) => do (window_provider io.window):
  use result <- announce ()
  return result
```

`announce` requires the ordinary nominal `Window.set_title` operation. The
provider handles that requirement but retains its implementation's `Foreign`
effect. Declaring the operation does not create a host import or grant access.
Pure tests can install a pure provider instead. Generic effect reflection sees
the source operation; it does not need a compiler list of platform operations.

The ABI may terminate the generic `Foreign` effect only by invoking an actual
supplied callable. It must still reject unresolved ordinary operations at an
entrypoint. The scalar callback backend now enforces this boundary; it does not
make every effect at an export implicitly handled.

Likewise, `ecs.get`, `ecs.set`, `ecs.build` and `ecs.run` must implement their
own source-defined operations, descriptors and state handling. Current
Reader-style providers alone are insufficient for a pure State interpreter;
state-threading/handler support remains a prerequisite, not hidden host storage.

## Stable ABI boundaries

Keep three contracts separate:

- **Blot ABI version:** generic scalars, records, variants, text, arrays,
  callable signatures, ownership and resource lifetimes. No game opcodes.
- **Library schemas:** `RenderFrame`, window services, filesystem services, etc.
  The source library and its host implementation version these together.
- **State schema:** nominal identities and layouts used to retain/migrate a
  world across code reload. Matching transport versions alone is insufficient.

The scalar JS/Wasm implementation uses opaque reference-backed host callables
and generic signature-specific call adapters under `blot:host/1`. Each call
passes an actual capability reference; there is no `call("window.title", ...)`,
implicit receiver, or `get_capability(number)` API. Verify ownership, lifetime
and signature before invocation. A forged or stale reference must not become a
host operation.

The compiler may emit generic marshalling/adapters from ordinary type schemas;
it must not branch on `Io`, `WindowIo`, field names or engine effect identities.
The entrypoint manifest describes ordinary types, not permissions. The host
chooses which function values to provide. A module receives only the supplied
capabilities; this does not claim isolation between malicious code and other
code inside that same module.

Text is length-delimited UTF-8; numeric arrays use contiguous typed storage, not
JSON or one host call per element. The first buffer boundary should borrow for a
call: the adapter validates lengths/alignment, and callbacks copy any bytes they
retain. No borrowed view survives a call, arena reset, memory growth, or module
reload. Do not expose transient pointers as persistent guest-value handles. Fix
exact layouts and test vectors before publishing a composite ABI version. The
implemented ABI 1 fixes only scalar/callback layouts; it does not reserve a
buffer layout or authorize treating guest arena pointers as persistent values.

Prefer a single `RenderFrame` submission with clear color, camera data, and
arrays of draws carrying geometry/shader references. `render.clear` and
`render.draw` can build that value in source. Host-side submission resolves only
resources belonging to the supplied rendering capability. Render packets are an
engine schema, not part of `blot:host/1`.

Geometry/shader references are stable library-level resource IDs, not GPU
pointers or foreign callables. The rendering capability validates their scope;
resource reload can replace backing GPU objects without rewriting world state.

Opaque host references and generic host function calls build on the
[WebAssembly JavaScript interface](https://www.w3.org/TR/wasm-js-api-2/). The
Component Model's
[typed interfaces and resource handles](https://component-model.bytecodealliance.org/design/wit.html)
are useful design precedents, but this proposal does not claim WIT/Canonical ABI
compatibility or require adopting the entire Component Model.

## Reload and verification boundary

Instantiate candidate code with newly bound capabilities, compare its state
schema, then run a candidate frame against a successor snapshot. `main` returns
callbacks; the engine calls `create` only on first launch, not every reload.
Compatible state is retained, or an explicit source migration is required.
Capabilities, closures and guest pointers are generation-bound and must be
rebound, never copied as persistent world bytes. Revoked callbacks must fail.

Window changes and render submissions are staged by engine-owned host callbacks.
Validate the full batch/resources before publishing candidate state and
commands. The compiler does not implement a render transaction or guarantee
rollback of arbitrary IO. Filesystem/network capabilities are withheld during
speculative frames unless their host implementations provide the required
staging policy.

The smaller host callback milestone is implemented: pass
`U32 -> U32 ! {Foreign}` into an export, call it through ordinary function
application, and return the result. Tests cover missing/wrong-type callbacks,
signature mismatch, expired references, const rejection, exceptions and Promise
rejection. Add record/Text/buffer codecs and persistent guest values next; test
reload across failure and schema changes before reconnecting the sandbox.
