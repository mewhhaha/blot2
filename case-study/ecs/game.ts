import {
  type GuestCommand,
  type GuestFrame,
  type GuestInput,
  GuestRuntime,
  type GuestWorld,
  noGuestEntity,
} from "../../compiler/guest_runtime.ts";
import type { EcsArtifact } from "../../compiler/host.ts";
import type { GameEvent, PickHit, Point, Viewport } from "./protocol.ts";

export interface Game {
  readonly artifact: EcsArtifact;
  readonly runtime: GuestRuntime;
  readonly world: GuestWorld;
  readonly commands?: readonly GuestCommand[];
}

// Named platform keys occupy a range above Unicode. Character keys
// retain their exact scalar value, so binding decisions remain in the guest.
export function encodeKey(value: string): number {
  const characters = [...value];
  if (characters.length === 1) return value.codePointAt(0)!;
  const names: Readonly<Record<string, number>> = {
    arrowleft: 0x100,
    arrowright: 0x101,
    arrowup: 0x102,
    arrowdown: 0x103,
    tab: 0x104,
    escape: 0x105,
    enter: 0x106,
    space: 32,
    backspace: 0x107,
    delete: 0x108,
    home: 0x109,
    end: 0x10a,
    pageup: 0x10b,
    pagedown: 0x10c,
  };
  const normalized = value.toLowerCase();
  if (Object.hasOwn(names, normalized)) {
    const code = names[normalized];
    return code === 32 ? code : code + 0x110000;
  }
  const functionKey = /^f([1-9]|1[0-9]|2[0-4])$/.exec(normalized);
  return functionKey ? 0x110200 + Number(functionKey[1]) : 0;
}

function eventInput(event: GameEvent): GuestInput {
  switch (event.tag) {
    case "KeyDown":
      return { event_kind: 1, key: encodeKey(event.value) };
    case "KeyUp":
      return { event_kind: 2, key: encodeKey(event.value) };
    case "FocusLost":
      return { event_kind: 3 };
    case "PointerDown":
    case "PointerUp":
      return {
        event_kind: event.tag === "PointerDown" ? 4 : 5,
        pointer_x: event.value.x,
        pointer_y: event.value.y,
        button: event.value.button,
      };
    case "PointerMove":
      return {
        event_kind: 6,
        pointer_x: event.value.x,
        pointer_y: event.value.y,
      };
    case "Wheel":
      return {
        event_kind: 7,
        pointer_x: event.value.x,
        pointer_y: event.value.y,
        wheel_delta: event.value.delta,
      };
    case "AssetReady":
      return { event_kind: 8 };
    case "AssetFailed":
      return { event_kind: 9 };
  }
}

export async function createGame(
  artifact: EcsArtifact,
  viewport: Viewport = { width: 1, height: 1 },
): Promise<Game> {
  const runtime = await GuestRuntime.create(artifact);
  const started = runtime.start({
    viewport_width: viewport.width,
    viewport_height: viewport.height,
  });
  return { artifact, runtime, ...started };
}

export function stepGame(game: Game, options: {
  readonly dt: number;
  readonly viewport: Viewport;
  readonly events: readonly GameEvent[];
  readonly pick: (game: Game, point: Point) => PickHit | undefined;
}): Game {
  let world = game.world;
  const commands = [...game.commands ?? []];
  const frameInput = {
    delta_time: options.dt,
    viewport_width: options.viewport.width,
    viewport_height: options.viewport.height,
  };
  for (const event of options.events) {
    const input = eventInput(event);
    const hit = event.tag === "PointerDown"
      ? options.pick({ ...game, world }, event.value)
      : undefined;
    const next = game.runtime.event(world, {
      ...frameInput,
      ...input,
      picked: hit?.entity ?? noGuestEntity,
      pick_valid: hit !== undefined,
      hit_x: hit?.position.x,
      hit_y: hit?.position.y,
      hit_z: hit?.position.z,
    });
    world = next.world;
    commands.push(...next.commands);
  }
  const updated = game.runtime.update(world, frameInput);
  return {
    ...game,
    world: updated.world,
    commands: [...commands, ...updated.commands],
  };
}

export function renderGame(game: Game, viewport: Viewport, options: {
  readonly previous?: Game;
  readonly alpha?: number;
} = {}): GuestFrame {
  const previous = options.previous?.runtime === game.runtime
    ? options.previous.world
    : undefined;
  const frame = game.runtime.render(game.world, {
    viewport_width: viewport.width,
    viewport_height: viewport.height,
    alpha: options.alpha ?? 1,
  }, previous);
  return { ...frame, commands: [...game.commands ?? [], ...frame.commands] };
}
