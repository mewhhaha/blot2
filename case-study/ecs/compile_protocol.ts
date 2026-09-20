import type { EcsArtifact } from "../../compiler/host.ts";
import type { NativeIncrementalStats } from "../../compiler/native_incremental.ts";

export interface CompiledGame {
  readonly artifact: EcsArtifact;
  readonly stats: NativeIncrementalStats;
}

export type CompileRequest =
  | { readonly kind: "initialize"; readonly executable?: string }
  | {
    readonly kind: "compile";
    readonly id: number;
    readonly source: string;
    readonly filename: string;
  }
  | { readonly kind: "close" };

export type CompileReply =
  | { readonly kind: "listening" }
  | { readonly kind: "ready" }
  | { readonly kind: "closed" }
  | {
    readonly kind: "compiled";
    readonly id: number;
    readonly compiled: CompiledGame;
  }
  | {
    readonly kind: "failed";
    readonly id: number;
    readonly diagnostic: boolean;
    readonly message: string;
    readonly stack?: string;
  };

export class CompilationFailure extends Error {
  constructor(message: string, readonly diagnostic: boolean) {
    super(message);
    this.name = "CompilationFailure";
  }
}
