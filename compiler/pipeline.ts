import compiled from "../generated/compiler/compiler.js";
import { CompilerError, type TypeId } from "./host.ts";
import type { BendList } from "./bend_list.ts";
export { bendArray, type BendList, bendList } from "./bend_list.ts";

export interface Declaration {
  readonly name: string;
  readonly exported: boolean;
}

export interface NominalDeclaration {
  readonly identity: TypeId;
}

export interface RawModule {
  readonly $: "Module";
  readonly operations: BendList<NominalDeclaration>;
  readonly data_types: BendList<NominalDeclaration>;
  readonly constants: BendList<Declaration>;
  readonly functions: BendList<Declaration>;
}

export interface CheckedConstant {
  readonly constant: Declaration;
}

export interface CheckedFunction {
  readonly function: Declaration;
  readonly signature: unknown;
  readonly effects: BendList<unknown>;
}

export interface CheckedModule {
  readonly $: "CheckedModule";
  readonly constants: BendList<CheckedConstant>;
  readonly functions: BendList<CheckedFunction>;
  readonly data_types: BendList<unknown>;
  readonly operations: BendList<NominalDeclaration>;
}

export interface GroupJob {
  readonly members: BendList<string>;
  readonly dependencies: BendList<string>;
  readonly type_dependencies: BendList<TypeId>;
}

export interface GroupInterface {
  readonly name: string;
  readonly kind: unknown;
  readonly template: unknown;
  readonly parameters: bigint;
  readonly effects: BendList<unknown>;
}

export interface CheckedGroup {
  readonly checked: CheckedModule;
  readonly interfaces: BendList<GroupInterface>;
}

export interface ConstantBinding {
  readonly name: string;
  readonly value: unknown;
}

export interface Constants {
  readonly bindings: BendList<ConstantBinding>;
  readonly remaining: bigint;
}

export interface CodegenJob {
  readonly key: unknown;
}

export interface EntryCode {
  readonly key: unknown;
}

export interface Prepared {
  readonly jobs: BendList<CodegenJob>;
}

// All language decisions live in Bend. This boundary only transports its
// immutable terms; names and signatures below are exported by main.bend.
export function invoke<T>(name: string, ...args: readonly unknown[]): T {
  const fn = (compiled as unknown as Record<string, unknown>)[name];
  if (typeof fn !== "function") {
    throw new Error(
      `Missing Bend export ${name}; run deno task build:compiler:js`,
    );
  }
  return Reflect.apply(fn, undefined, args) as T;
}

export function result<T>(name: string, ...args: readonly unknown[]): T {
  const value = invoke<
    { readonly $: "Done"; readonly value: T } | {
      readonly $: "Fail";
      readonly error: {
        readonly code: string;
        readonly subject: string;
        readonly message: string;
      };
    }
  >(name, ...args);
  if (value.$ === "Fail") {
    throw new CompilerError(value.error);
  }
  return value.value;
}

// Exact structural keys avoid hash collisions and do not recurse through
// potentially long Bend lists. Cache lifetimes are confined to one session.
export function structuralKey(value: unknown): string {
  const parts: string[] = [];
  const pending: unknown[] = [value];
  const numberBits = new DataView(new ArrayBuffer(8));
  while (pending.length) {
    const current = pending.pop();
    if (current === null) {
      parts.push("null;");
    } else if (typeof current === "object") {
      const entries = Object.entries(current).sort(([a], [b]) =>
        a < b ? -1 : a > b ? 1 : 0
      );
      parts.push(`o${entries.length}:`);
      for (let index = entries.length - 1; index >= 0; index--) {
        pending.push(entries[index][1], entries[index][0]);
      }
    } else if (typeof current === "bigint") {
      parts.push(`n${current};`);
    } else if (
      typeof current === "number" &&
      (Object.is(current, -0) || !Number.isFinite(current))
    ) {
      // JSON collapses signed zero and all non-finite numbers. Preserve IEEE
      // bits, including a NaN payload, before keys reach const/code caches.
      numberBits.setFloat64(0, current);
      parts.push(
        `number:bits${numberBits.getUint32(0).toString(16).padStart(8, "0")}${
          numberBits.getUint32(4).toString(16).padStart(8, "0")
        };`,
      );
    } else {
      parts.push(`${typeof current}:${JSON.stringify(current)};`);
    }
  }
  return parts.join("");
}

export type CompilerJob = {
  readonly kind: "check";
  readonly module: RawModule;
  readonly dependencies: BendList<GroupInterface>;
} | { readonly kind: "codegen"; readonly job: CodegenJob };

export function executeJob(job: CompilerJob): CheckedGroup | EntryCode {
  return job.kind === "check"
    ? result<CheckedGroup>("groups.check_group", job.module, job.dependencies)
    : result<EntryCode>("wasm.compile_entry", job.job);
}
