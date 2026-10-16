import { ResourceJournal } from "./resource_journal.ts";
import { type TaskContext, TaskError, TaskRuntime } from "./task_runtime.ts";

export const taskImports = [
  ["open", 0, true],
  ["close", 1, false],
  ["spawn", 3, true],
  ["join", 2, true],
  ["cancel", 1, false],
  ["poll", 2, true],
  ["drop", 2, false],
  ["drain", 0, false],
  ["checkpoint", 0, false],
  ["current", 0, true],
  ["resume", 1, false],
  ["transfer", 1, false],
] as const;
export function taskExports(count: number): string[] {
  const names = [
    "blot:task_context/create",
    "blot:task_context/save",
    "blot:task_context/restore",
    "blot:task_context/drop",
    "blot:task_retain",
    "blot:task_release",
  ];
  for (let id = 0; id < count; id++) {
    for (const role of ["start", "move_captures", "move_result"]) {
      names.push(`blot:task_${role}/${id}`);
    }
  }
  return names;
}

function invalid(message: string): never {
  throw new TaskError("task_host_contract", message);
}
/** Link through an exact Wasm signature instead of trusting JS .length or a
 * name that happens to resemble a compiler adapter. */
export function typedTaskFunctions(
  functions: Record<string, CallableFunction | WebAssembly.ImportValue>,
  signatures: readonly (readonly [string, number, boolean])[] = taskImports,
): WebAssembly.Exports {
  const uleb = (value: number): number[] => {
    const bytes: number[] = [];
    do {
      let byte = value & 127;
      value >>>= 7;
      if (value !== 0) byte |= 128;
      bytes.push(byte);
    } while (value !== 0);
    return bytes;
  };
  const name = (text: string): number[] => {
    const bytes = [...new TextEncoder().encode(text)];
    return [...uleb(bytes.length), ...bytes];
  };
  const section = (id: number, bytes: number[]): number[] => [
    id,
    ...uleb(bytes.length),
    ...bytes,
  ];
  const types = [...uleb(signatures.length)];
  const imports = [...uleb(signatures.length)];
  const exports = [...uleb(signatures.length)];
  for (const [index, [key, parameters, result]] of signatures.entries()) {
    types.push(96, ...uleb(parameters), ...Array(parameters).fill(127));
    types.push(Number(result));
    if (result) types.push(127);
    imports.push(...name("task"), ...name(key), 0, ...uleb(index));
    exports.push(...name(key), 0, ...uleb(index));
  }
  const module = new WebAssembly.Module(
    new Uint8Array([
      0,
      97,
      115,
      109,
      1,
      0,
      0,
      0,
      ...section(1, types),
      ...section(2, imports),
      ...section(7, exports),
    ]),
  );
  return new WebAssembly.Instance(module, {
    task: functions as WebAssembly.ModuleImports,
  }).exports;
}

type Completion<T> = T | Promise<T>;
interface Entry {
  id?: number;
  readonly native: number;
  readonly group: number;
  context: TaskContext;
  readonly resources: ResourceJournal;
  readonly results: ResourceJournal;
  readonly descriptor: number;
  readonly captures: number;
  entered: boolean;
  capturesLive: boolean;
  closed: boolean;
}

/** One instance owns one scheduler, identity budget and native-root catalog.
 * Each task keeps separate lexical and returned-resource journals. */
export class TaskGuest {
  readonly #runtime = new TaskRuntime();
  readonly #entries = new Map<number, Entry>();
  readonly #handles = new Map<number, Entry>();
  readonly #hooks: WebAssembly.Exports;
  #root?: Entry;
  #active?: Entry;
  #source?: ResourceJournal;
  #destination?: ResourceJournal;
  #moves?: number[];
  #asynchronous = false;
  #cleaning = 0;
  constructor(
    exports: WebAssembly.Exports,
    readonly descriptors: number,
    readonly journal: () => ResourceJournal,
    readonly select: (journal: ResourceJournal) => void,
    readonly ownership: { enter(): void; leave(outcome: number): void },
    readonly promising?: (
      fn: CallableFunction,
    ) => (value: number) => Promise<unknown>,
  ) {
    const signatures: [string, number, boolean][] = [
      ["blot:task_context/create", 1, true],
      ["blot:task_context/save", 1, true],
      ["blot:task_context/restore", 1, true],
      ["blot:task_context/drop", 1, true],
      ["blot:task_retain", 1, false],
      ["blot:task_release", 1, false],
    ];
    for (let id = 0; id < descriptors; id++) {
      signatures.push([`blot:task_start/${id}`, 1, true]);
      signatures.push([`blot:task_move_captures/${id}`, 1, false]);
      signatures.push([`blot:task_move_result/${id}`, 1, false]);
    }
    this.#hooks = typedTaskFunctions(exports, signatures);
  }
  #call(name: string, value: number): number {
    return (this.#hooks[name] as (value: number) => number)(value) >>> 0;
  }
  #activate(entry: Entry): void {
    if (entry.closed) invalid("Task context has terminated");
    this.#call("blot:task_context/restore", entry.native);
    this.#active = entry;
    this.select(entry.resources);
  }
  begin(resources: ResourceJournal, asynchronous: boolean): void {
    if (!this.#root) {
      const native = this.#call("blot:task_context/create", 0);
      this.#root = {
        id: 0,
        native,
        group: 0,
        context: this.#runtime.rootContext,
        resources,
        results: resources,
        descriptor: -1,
        captures: 0,
        entered: true,
        capturesLive: false,
        closed: false,
      };
      this.#entries.set(0, this.#root);
      this.#call("blot:task_context/save", native);
    }
    this.#active = this.#root;
    this.select(resources);
    this.#asynchronous = asynchronous;
  }
  #owner(): Entry {
    return this.#active ?? invalid("No active task invocation");
  }
  #restore<T>(owner: Entry, result: Completion<T>): Completion<T> {
    if (result instanceof Promise) {
      return result.then((value) => {
        this.#activate(owner);
        return value;
      }, (cause) => {
        this.#activate(owner);
        throw cause;
      });
    }
    this.#activate(owner);
    return result;
  }
  #move(
    source: ResourceJournal,
    destination: ResourceJournal,
    adapter: string,
    value: number,
  ): void {
    if (this.#destination) invalid("Reentrant task transfer");
    const prior = this.#owner();
    const moved: number[] = [];
    this.#source = source;
    this.#destination = destination;
    this.#moves = moved;
    this.select(source);
    try {
      this.#call(adapter, value);
    } catch (cause) {
      for (let index = moved.length - 1; index >= 0; index--) {
        destination.transfer(moved[index], source);
      }
      throw cause;
    } finally {
      this.#source = undefined;
      this.#destination = undefined;
      this.#moves = undefined;
      this.select(prior.resources);
    }
  }
  #retire(entry: Entry): void {
    if (entry.closed) return;
    const prior = this.#owner();
    this.#activate(entry);
    let failed = false;
    let failure: unknown;
    const attempt = (action: () => void): void => {
      try {
        action();
      } catch (cause) {
        if (!failed) {
          failed = true;
          failure = cause;
        }
      }
    };
    try {
      if (!entry.entered) {
        entry.entered = true;
        attempt(() => this.ownership.enter());
      }
      if (entry.capturesLive) {
        entry.capturesLive = false;
        attempt(() => {
          this.#call("blot:task_release", entry.captures);
        });
      }
      attempt(() => this.cleanup(() => entry.resources.finish()));
      attempt(() => this.ownership.leave(Number(failed)));
      entry.entered = false;
      attempt(() => {
        this.#call("blot:task_context/drop", entry.native);
      });
      entry.closed = true;
      if (entry.id !== undefined) this.#entries.delete(entry.id);
    } finally {
      if (!prior.closed) this.#activate(prior);
      else if (this.#root) this.#activate(this.#root);
    }
    if (failed) throw failure;
  }
  readonly imports = {
    open: (): number => this.#owner().context.scope(),
    close: (group: number): Completion<void> => {
      const owner = this.#owner();
      const forget = (): void => {
        for (const [id, entry] of this.#handles) {
          if (entry.group === (group >>> 0)) this.#handles.delete(id);
        }
      };
      try {
        const completion = this.#restore(
          owner,
          this.#runtime.close(group >>> 0),
        );
        if (completion instanceof Promise) return completion.finally(forget);
        forget();
        return completion;
      } catch (cause) {
        forget();
        throw cause;
      }
    },
    spawn: (group: number, descriptor: number, captures: number): number => {
      const parent = this.#owner();
      descriptor >>>= 0;
      captures >>>= 0;
      if (descriptor >= this.descriptors) invalid("Unknown task descriptor");
      const resources = this.journal();
      const results = this.journal();
      resources.begin();
      results.begin();
      const native = this.#call("blot:task_context/create", 1);
      const entry: Entry = {
        native,
        group: group >>> 0,
        context: parent.context,
        resources,
        results,
        descriptor,
        captures,
        entered: false,
        capturesLive: true,
        closed: false,
      };
      this.#call("blot:task_retain", captures);
      let moved = false;
      let published: number | undefined;
      try {
        this.#move(
          parent.resources,
          resources,
          `blot:task_move_captures/${descriptor}`,
          captures,
        );
        moved = true;
        const id = this.#runtime.spawn(
          group >>> 0,
          {
            run: (context) => {
              entry.context = context;
              this.#activate(entry);
              entry.entered = true;
              context.cleanup(() => this.#retire(entry));
              this.ownership.enter();
              const fn = this.#hooks[`blot:task_start/${descriptor}`] as (
                value: number,
              ) => number;
              const publish = (result: number): number => {
                this.#activate(entry);
                try {
                  this.#move(
                    resources,
                    results,
                    `blot:task_move_result/${descriptor}`,
                    result,
                  );
                } catch (cause) {
                  this.#call("blot:task_release", result);
                  throw cause;
                }
                return result >>> 0;
              };
              if (this.#asynchronous) {
                return this.promising!(fn)(captures).then((value) => {
                  if (typeof value !== "number") {
                    invalid("Invalid task result envelope");
                  }
                  return publish(value);
                });
              }
              return publish(fn(captures));
            },
            dropCaptures: () => this.#retire(entry),
            dropResult: (result) => {
              this.select(results);
              try {
                this.#call("blot:task_release", result);
                this.cleanup(() => results.finish());
              } finally {
                this.select(this.#owner().resources);
              }
            },
          },
          captures,
          parent.context.id,
        );
        published = id;
        entry.id = id;
        this.#entries.set(id, entry);
        this.#handles.set(id, entry);
        return id;
      } catch (cause) {
        if (published !== undefined) this.#runtime.rollbackSpawn(published);
        if (moved) {
          this.#move(
            resources,
            parent.resources,
            `blot:task_move_captures/${descriptor}`,
            captures,
          );
        }
        this.#retire(entry);
        throw cause;
      }
    },
    join: (handle: number, descriptor: number): Completion<number> => {
      const owner = this.#owner();
      const entry = this.#handles.get(handle >>> 0);
      if (!entry || entry.descriptor !== (descriptor >>> 0)) {
        invalid("Task descriptor changed");
      }
      this.#handles.delete(handle >>> 0);
      const publish = (result: number): number => {
        this.#activate(owner);
        try {
          this.#move(
            entry.results,
            owner.resources,
            `blot:task_move_result/${entry.descriptor}`,
            result,
          );
        } catch (cause) {
          // Join consumed the host envelope. A failed destination reservation
          // still owns its lease and the child's returned cleanup journal.
          try {
            this.#call("blot:task_release", result);
          } finally {
            this.cleanup(() => entry.results.finish());
          }
          throw cause;
        }
        entry.results.finish();
        return result;
      };
      const result = this.#runtime.join(handle >>> 0, owner.context.id);
      if (result instanceof Promise) return result.then(publish);
      return publish(result);
    },
    cancel: (handle: number): Completion<void> => {
      const owner = this.#owner();
      this.#handles.delete(handle >>> 0);
      return this.#restore(owner, this.#runtime.cancel(handle >>> 0));
    },
    poll: (handle: number, descriptor: number): number => {
      const entry = this.#handles.get(handle >>> 0);
      if (!entry || entry.descriptor !== (descriptor >>> 0)) {
        invalid("Stale task generation or descriptor");
      }
      return [
        "runnable",
        "running",
        "suspended",
        "succeeded",
        "failed",
        "cancelled",
      ].indexOf(this.#runtime.poll(handle >>> 0));
    },
    drop: (handle: number, descriptor: number): Completion<void> => {
      const entry = this.#handles.get(handle >>> 0);
      if (!entry || entry.descriptor !== (descriptor >>> 0)) {
        invalid("Stale task generation or descriptor");
      }
      return this.imports.cancel(handle);
    },
    drain: (): Completion<void> => {
      const owner = this.#owner();
      return this.#restore(owner, this.#runtime.drain(owner.context.id));
    },
    checkpoint: (): void => {
      if (this.#cleaning === 0) this.#owner().context.checkpoint();
    },
    current: (): number => {
      const id = this.#owner().id;
      if (id === undefined) invalid("Task publication is incomplete");
      return id;
    },
    resume: (generation: number): void => {
      const entry = this.#entries.get(generation >>> 0);
      if (!entry) invalid("Stale task ownership context");
      this.#activate(entry);
    },
    transfer: (token: number): void => {
      if (!this.#destination || !this.#moves) {
        invalid("No checked task transfer");
      }
      // A ready demand can retain the same owner in its old environment and
      // memo. Both edges denote one obligation in this checked transfer.
      token >>>= 0;
      if (this.#moves.includes(token)) return;
      // Record allocation precedes the allocation-free journal transaction.
      this.#moves.push(token);
      try {
        this.#source!.transfer(token >>> 0, this.#destination);
      } catch (cause) {
        this.#moves.pop();
        throw cause;
      }
    },
  };
  cleanup<T>(action: () => T): T {
    this.#cleaning++;
    try {
      return action();
    } finally {
      this.#cleaning--;
    }
  }
  dispose(): void {
    if (!this.#root) return;
    this.#activate(this.#root);
    this.#call("blot:task_context/drop", this.#root.native);
    this.#root.closed = true;
    this.#entries.clear();
    this.#handles.clear();
  }
  finish(cancel: boolean): Completion<void> {
    const root = this.#root!;
    const completion = this.#restore(
      root,
      this.#runtime.finishInvocation(cancel),
    );
    if (completion instanceof Promise) {
      return completion.finally(() => this.#handles.clear());
    }
    this.#handles.clear();
    return completion;
  }
}
