// Platform event/presentation values. Render frames are decoded from the
// versioned guest memory ABI; no component or system names cross this boundary.
import type { GuestCommand } from "../../compiler/guest_runtime.ts";
export interface Vector {
  readonly x: number;
  readonly y: number;
  readonly z: number;
}

export interface Point {
  readonly x: number;
  readonly y: number;
}

export interface Viewport {
  readonly width: number;
  readonly height: number;
}

export type AssetKind = "mesh" | "material" | "shader" | "texture";

export type GameEvent =
  | { readonly tag: "KeyDown" | "KeyUp"; readonly value: string }
  | { readonly tag: "FocusLost" }
  | { readonly tag: "PointerMove"; readonly value: Point }
  | {
    readonly tag: "PointerDown" | "PointerUp";
    readonly value: Point & { readonly button: number };
  }
  | {
    readonly tag: "Wheel";
    readonly value: Point & { readonly delta: number };
  }
  | {
    readonly tag: "AssetReady";
    readonly value: {
      readonly key: string;
      readonly kind: AssetKind;
      readonly revision: number;
    };
  }
  | {
    readonly tag: "AssetFailed";
    readonly value: {
      readonly key: string;
      readonly kind: AssetKind;
      readonly revision: number;
      readonly message: string;
    };
  };

export interface Frame {
  readonly events: readonly GameEvent[];
  readonly timestamp: number;
  readonly viewport: Viewport;
}

export interface RenderDraw {
  readonly mesh: string;
  readonly material: string;
  // Column-major affine model matrix. Omitted entity means noneditable geometry.
  readonly transform: readonly number[];
  readonly entity?: number;
}

export interface RenderFrame {
  readonly commands?: readonly GuestCommand[];
  readonly ambient: Vector;
  readonly clear: {
    readonly r: number;
    readonly g: number;
    readonly b: number;
    readonly a: number;
  };
  readonly draws: readonly RenderDraw[];
  readonly light_color: Vector;
  readonly light_direction: Vector;
  readonly projection: readonly number[];
  readonly view: readonly number[];
}

export interface PickHit {
  readonly entity?: number;
  readonly draw_index: number;
  // World-space distance from the ray's near clipping plane, not the camera.
  readonly distance: number;
  readonly position: Vector;
}
