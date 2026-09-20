import type { Frame, GameEvent, Viewport } from "./protocol.ts";

interface EventWindow {
  addEventListener(type: string, listener: (event: Event) => unknown): void;
  removeEventListener(type: string, listener: (event: Event) => unknown): void;
}

export function createEventPump(window: EventWindow) {
  const pending: GameEvent[] = [];
  const listeners = new Map<string, (event: Event) => void>();
  let closed = false;
  const listen = (type: string, listener: (event: Event) => void): void => {
    listeners.set(type, listener);
    window.addEventListener(type, listener);
  };
  const enqueue = (event: GameEvent): void => {
    if (!closed) pending.push(event);
  };
  for (
    const [type, tag] of [["keydown", "KeyDown"], ["keyup", "KeyUp"]] as const
  ) {
    listen(type, (event) => {
      if (!("key" in event) || typeof event.key !== "string") {
        throw new TypeError("keyboard event omitted key");
      }
      if (type === "keydown" && "repeat" in event && event.repeat === true) {
        return;
      }
      // Raw Deno Desktop exposes key names, including the Arrow keys.
      enqueue({ tag, value: event.key });
    });
  }
  listen(
    "mousemove",
    (event) => enqueue({ tag: "PointerMove", value: point(event) }),
  );
  for (
    const [type, tag] of [["mousedown", "PointerDown"], [
      "mouseup",
      "PointerUp",
    ]] as const
  ) {
    listen(
      type,
      (event) =>
        enqueue({
          tag,
          value: {
            ...point(event),
            button: integerProperty(event, "button"),
          },
        }),
    );
  }
  listen(
    "wheel",
    (event) =>
      enqueue({
        tag: "Wheel",
        value: { ...point(event), delta: numberProperty(event, "deltaY") },
      }),
  );
  listen("blur", () => enqueue({ tag: "FocusLost" }));
  return {
    enqueue,
    nextFrame(timestamp: number, viewport: Viewport): Frame {
      if (closed) throw new Error("event pump is closed");
      if (
        !Number.isFinite(timestamp) ||
        !Number.isSafeInteger(viewport.width) || viewport.width < 1 ||
        !Number.isSafeInteger(viewport.height) || viewport.height < 1
      ) throw new RangeError("invalid frame clock or viewport");
      return {
        timestamp,
        viewport: { ...viewport },
        events: pending.splice(0),
      };
    },
    close(): void {
      if (closed) return;
      closed = true;
      for (const [type, listener] of listeners) {
        window.removeEventListener(type, listener);
      }
      pending.length = 0;
    },
  };
}

function numberProperty(event: Event, field: string): number {
  const value: unknown = Reflect.get(event, field);
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new TypeError(`window event omitted finite ${field}`);
  }
  return value;
}
function integerProperty(event: Event, field: string): number {
  const value = numberProperty(event, field);
  if (!Number.isSafeInteger(value)) {
    throw new TypeError(`window event ${field} must be an integer`);
  }
  return value;
}
function point(event: Event): { x: number; y: number } {
  return {
    x: numberProperty(event, "clientX"),
    y: numberProperty(event, "clientY"),
  };
}
