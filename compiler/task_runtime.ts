/** Cooperative task ownership. This module never schedules simultaneous guest
 * reentry: an adapter returns or suspends before another adapter is entered. */
export type TaskState =
  | "runnable"
  | "running"
  | "suspended"
  | "succeeded"
  | "failed"
  | "cancelled";

export type TaskErrorCode =
  | "task_escape"
  | "task_handle_consumed"
  | "task_host_contract"
  | "task_budget";

export class TaskError extends Error {
  constructor(readonly code: TaskErrorCode, message: string) {
    super(message);
    this.name = "TaskError";
  }
}

export class TaskFailure extends Error {
  constructor(readonly failures: readonly unknown[]) {
    super("Structured task failed", { cause: failures[0] });
    this.name = "TaskFailure";
  }
}

class Cancelled extends Error {}
type Completion<T> = T | Promise<T>;
function promise<T>(value: Completion<T>): value is Promise<T> {
  return value instanceof Promise;
}
function after<T, R>(
  value: Completion<T>,
  next: (value: T) => Completion<R>,
): Completion<R> {
  if (promise(value)) return value.then(next);
  return next(value);
}

/** Compiler-owned adapters bind an exact descriptor and typed root context.
 * They switch ownership context on entry and JSPI resume, and finish result
 * publication and root retention before run returns. */
export interface TaskAdapter {
  run(context: TaskContext, captures: number): Completion<number>;
  dropCaptures(captures: number): void;
  dropResult(result: number): void;
}

interface Group {
  readonly id: number;
  readonly owner: Task;
  readonly children: Task[];
  state: "open" | "closing" | "closed";
}
interface Task {
  readonly id: number;
  readonly group?: Group;
  readonly parent?: Task;
  readonly ordinal: number;
  readonly adapter?: TaskAdapter;
  readonly captures: number;
  readonly groups: Set<Group>;
  readonly cleanups: (() => void)[];
  state: TaskState;
  consumed: boolean;
  cancel: boolean;
  result?: number;
  failures: unknown[];
  completion?: Promise<void>;
}

/** A context is private to one task and cannot be manufactured from an ID. */
export interface TaskContext {
  readonly id: number;
  checkpoint(): void;
  scope(): number;
  cleanup(action: () => void): void;
}

/** IDs never recycle. A task ID is meaningful only to the instance that owns
 * this runtime; the guest adapter must also validate its instance generation.
 * The live-record bound is independent of the monotonic identity budget. */
export class TaskRuntime {
  readonly #tasks = new Map<number, Task>();
  readonly #groups = new Map<number, Group>();
  #next = 1;
  #disposed = false;
  readonly #root: Task;
  constructor(readonly limit = 4096) {
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 4096) {
      throw new TaskError("task_budget", "Invalid task budget");
    }
    this.#root = {
      id: 0,
      ordinal: 0,
      captures: 0,
      groups: new Set(),
      cleanups: [],
      state: "running",
      consumed: false,
      cancel: false,
      failures: [],
    };
  }

  #identity(): number {
    if (this.#disposed) {
      throw new TaskError("task_host_contract", "Disposed task runtime");
    }
    if (
      this.#next > 0xFFFFFFFF ||
      this.#tasks.size + this.#groups.size >= this.limit
    ) {
      throw new TaskError(
        "task_budget",
        "Task identity or live-record budget exceeded",
      );
    }
    return this.#next++;
  }
  #task(id: number, consume = false): Task {
    if (this.#disposed || !Number.isInteger(id) || id <= 0) {
      throw new TaskError("task_host_contract", "Invalid task identity");
    }
    const task = this.#tasks.get(id);
    if (!task) {
      throw new TaskError("task_host_contract", "Stale task generation");
    }
    if (consume) {
      if (task.consumed) {
        throw new TaskError("task_handle_consumed", "Task handle was consumed");
      }
      task.consumed = true;
    }
    return task;
  }
  #group(id: number): Group {
    if (this.#disposed || !Number.isInteger(id) || id <= 0) {
      throw new TaskError("task_host_contract", "Invalid task group identity");
    }
    const group = this.#groups.get(id);
    if (!group) {
      throw new TaskError("task_escape", "Task group is closed or foreign");
    }
    return group;
  }
  #context(task: Task): TaskContext {
    return Object.freeze({
      id: task.id,
      checkpoint: () => {
        if (task.cancel) throw new Cancelled();
        for (const group of task.groups) {
          const failures = this.#failures(group);
          if (failures.length !== 0) throw new TaskFailure(failures);
        }
        if (task.state !== "running" && task.state !== "suspended") {
          throw new TaskError(
            "task_host_contract",
            "Task context has terminated",
          );
        }
      },
      scope: () => {
        if (task.cancel) throw new Cancelled();
        if (task.state !== "running" && task.state !== "suspended") {
          throw new TaskError("task_escape", "Task context has terminated");
        }
        return this.#open(task);
      },
      cleanup: (action: () => void) => {
        if (task.state !== "running" && task.state !== "suspended") {
          throw new TaskError(
            "task_escape",
            "Cleanup registered after task termination",
          );
        }
        if (typeof action !== "function") {
          throw new TaskError("task_host_contract", "Invalid task cleanup");
        }
        if (task.cleanups.length >= this.limit) {
          throw new TaskError("task_budget", "Task cleanup budget exceeded");
        }
        task.cleanups.push(action);
      },
    });
  }
  #open(owner: Task): number {
    const id = this.#identity();
    const group: Group = { id, owner, children: [], state: "open" };
    this.#groups.set(id, group);
    try {
      owner.groups.add(group);
    } catch (cause) {
      this.#groups.delete(id);
      throw cause;
    }
    return id;
  }
  open(): number {
    return this.#open(this.#root);
  }
  spawn(
    groupId: number,
    adapter: TaskAdapter,
    captures: number,
    callerId = 0,
  ): number {
    const group = this.#group(groupId);
    let caller = this.#root;
    if (callerId !== 0) caller = this.#task(callerId);
    if (
      (caller.state !== "running" && caller.state !== "suspended") ||
      caller.cancel || group.owner.cancel
    ) {
      throw new TaskError("task_escape", "Task owner is terminating");
    }
    if (group.state !== "open") {
      let child: Task | undefined = caller;
      let descendant = false;
      while (child?.group) {
        if (child.group === group) descendant = true;
        child = child.group.owner;
      }
      if (group.state !== "closing" || !descendant) {
        throw new TaskError(
          "task_escape",
          "Cannot spawn outside the group's live descendants",
        );
      }
    }
    if (
      !Number.isInteger(captures) || captures < 0 || captures > 0xFFFFFFFF ||
      typeof adapter?.run !== "function" ||
      typeof adapter.dropCaptures !== "function" ||
      typeof adapter.dropResult !== "function"
    ) {
      throw new TaskError("task_host_contract", "Invalid task adapter");
    }
    const id = this.#identity();
    const task: Task = {
      id,
      group,
      parent: caller,
      ordinal: group.children.length,
      adapter,
      captures,
      groups: new Set(),
      cleanups: [],
      state: "runnable",
      consumed: false,
      cancel: false,
      failures: [],
    };
    // Publication is the transfer point. Failed validation or budget admission
    // above never calls a drop adapter or changes the group's ownership.
    this.#tasks.set(id, task);
    try {
      group.children.push(task);
    } catch (cause) {
      this.#tasks.delete(id);
      throw cause;
    }
    return id;
  }
  /** Undo publication that failed before the compiler exposed its handle.
   * The caller still owns captures; no thunk or cleanup may have started. */
  rollbackSpawn(id: number): void {
    const task = this.#task(id);
    const group = task.group!;
    if (
      task.state !== "runnable" || task.consumed || group.state === "closed" ||
      group.children.at(-1) !== task
    ) {
      throw new TaskError(
        "task_host_contract",
        "Task publication cannot roll back after execution",
      );
    }
    group.children.pop();
    this.#tasks.delete(id);
  }
  poll(id: number): TaskState {
    return this.#task(id).state;
  }
  #terminal(task: Task): boolean {
    return task.state === "succeeded" || task.state === "failed" ||
      task.state === "cancelled";
  }
  #failure(task: Task, cause: unknown): void {
    if (cause instanceof Cancelled) task.cancel = true;
    else if (cause instanceof TaskFailure) {
      // A child waiting in its enclosing group must unwind on that group's
      // failure without reporting the same independently observed cause twice.
      for (const failure of cause.failures) {
        if (
          task.group?.children.some((sibling) =>
            sibling !== task && sibling.failures.includes(failure)
          )
        ) continue;
        if (!task.failures.includes(failure)) task.failures.push(failure);
      }
      if (task.failures.length === 0) task.cancel = true;
    } else task.failures.push(cause);
    if (task.failures.length !== 0 && task.group) {
      for (const sibling of task.group.children) {
        if (sibling !== task) this.#request(sibling);
      }
    }
  }
  #request(task: Task): void {
    if (this.#terminal(task)) return;
    task.cancel = true;
    for (const group of task.groups) {
      for (const child of group.children) this.#request(child);
    }
  }
  #discard(task: Task): void {
    if (task.result === undefined) return;
    const value = task.result;
    task.result = undefined;
    try {
      task.adapter!.dropResult(value);
    } catch (cause) {
      this.#failure(task, cause);
    }
  }
  #finish(task: Task): Completion<void> {
    const groups = [...task.groups];
    const closeNext = (index: number): Completion<void> => {
      if (index === groups.length) return;
      const group = groups[index];
      if (group.state === "closed") return closeNext(index + 1);
      return after(this.#close(group), () => {
        const failures = this.#failures(group);
        for (const cause of failures) this.#failure(task, cause);
        return closeNext(index + 1);
      });
    };
    return after(closeNext(0), () => {
      for (let index = task.cleanups.length - 1; index >= 0; index--) {
        try {
          task.cleanups[index]();
        } catch (cause) {
          this.#failure(task, cause);
        }
      }
      task.cleanups.length = 0;
      try {
        task.adapter!.dropCaptures(task.captures);
      } catch (cause) {
        this.#failure(task, cause);
      }
      if (task.cancel || task.failures.length !== 0) this.#discard(task);
      if (task.failures.length !== 0) task.state = "failed";
      else if (task.cancel) task.state = "cancelled";
      else task.state = "succeeded";
    });
  }
  #start(task: Task): Completion<void> {
    if (this.#terminal(task)) return;
    if (task.state !== "runnable") return task.completion;
    task.state = "running";
    let result: Completion<number>;
    try {
      if (task.cancel) throw new Cancelled();
      result = task.adapter!.run(this.#context(task), task.captures);
      // Adapters return an actual Promise, never an arbitrary user thenable.
      if (
        !promise(result) &&
        (!Number.isInteger(result) || result < 0 || result > 0xFFFFFFFF)
      ) {
        throw new TaskError(
          "task_host_contract",
          "Invalid task result envelope",
        );
      }
    } catch (cause) {
      this.#failure(task, cause);
      const completion = this.#finish(task);
      if (promise(completion)) task.completion = completion;
      return completion;
    }
    const publish = (value: number): Completion<void> => {
      if (!Number.isInteger(value) || value < 0 || value > 0xFFFFFFFF) {
        this.#failure(
          task,
          new TaskError("task_host_contract", "Invalid task result envelope"),
        );
      } else task.result = value;
      return this.#finish(task);
    };
    if (promise(result)) {
      task.state = "suspended";
      task.completion = result.then(publish, (cause) => {
        this.#failure(task, cause);
        return this.#finish(task);
      });
      return task.completion;
    }
    const completion = publish(result);
    if (promise(completion)) {
      task.state = "suspended";
      task.completion = completion;
    }
    return completion;
  }
  #run(group: Group, caller?: Task): Completion<void> {
    const pending: Promise<void>[] = [];
    for (const child of group.children) {
      let ancestor = caller;
      let waitingOnSelf = false;
      while (ancestor) {
        if (child === ancestor) waitingOnSelf = true;
        ancestor = ancestor.parent;
      }
      if (waitingOnSelf) continue;
      const completion = this.#start(child);
      if (promise(completion)) pending.push(completion);
    }
    if (pending.length !== 0) {
      return Promise.all(pending).then(() => {
        // A suspended descendant may publish more work after this pass. Scope
        // closure must run that work before retiring any captures or group owner.
        if (
          group.children.some((child) => child.state === "runnable")
        ) return this.#run(group, caller);
      });
    }
  }
  #failures(group: Group): unknown[] {
    const failures: unknown[] = [];
    for (const child of group.children) failures.push(...child.failures);
    return failures;
  }
  join(id: number, callerId = 0): Completion<number> {
    let caller = this.#root;
    if (callerId !== 0) caller = this.#task(callerId);
    const task = this.#task(id, true);
    if (task === caller) {
      throw new TaskError("task_host_contract", "A task cannot join itself");
    }
    this.#run(task.group!, caller);
    return after(task.completion, () => {
      const failures = this.#failures(task.group!);
      if (failures.length !== 0) {
        return after(this.#run(task.group!, caller), () => {
          throw new TaskFailure(this.#failures(task.group!));
        });
      }
      if (task.state === "cancelled") throw new Cancelled();
      if (task.result === undefined) {
        throw new TaskError("task_host_contract", "Missing terminal result");
      }
      const value = task.result;
      task.result = undefined;
      return value;
    });
  }
  cancel(id: number): Completion<void> {
    const task = this.#task(id, true);
    this.#request(task);
    return after(this.#start(task), () => {
      this.#discard(task);
      if (task.failures.length !== 0) throw new TaskFailure([...task.failures]);
    });
  }
  #close(group: Group): Completion<void> {
    if (group.state === "closed") return;
    group.state = "closing";
    return after(this.#run(group), () => {
      for (const task of group.children) {
        this.#discard(task);
        this.#tasks.delete(task.id);
      }
      group.state = "closed";
      this.#groups.delete(group.id);
      group.owner.groups.delete(group);
    });
  }
  close(id: number): Completion<void> {
    const group = this.#group(id);
    return after(this.#close(group), () => {
      const failures = this.#failures(group);
      if (failures.length !== 0) throw new TaskFailure(failures);
    });
  }
  /** Complete children before an enclosing lexical resource is retired. The
   * group remains open and its affine handles remain available for joining. */
  drain(owner = 0): Completion<void> {
    const task = owner === 0 ? this.#root : this.#task(owner);
    const groups = [...task.groups];
    const next = (index: number): Completion<void> => {
      if (index === groups.length) return;
      const group = groups[index];
      return after(this.#run(group), () => {
        const failures = this.#failures(group);
        if (failures.length !== 0) throw new TaskFailure(failures);
        return next(index + 1);
      });
    };
    return next(0);
  }
  finishInvocation(cancel = false): Completion<void> {
    const groups = [...this.#root.groups];
    if (cancel) {
      for (const group of groups) {
        for (const child of group.children) this.#request(child);
      }
    }
    const next = (index: number): Completion<void> => {
      if (index === groups.length) return;
      return after(this.#close(groups[index]), () => next(index + 1));
    };
    return after(next(0), () => {
      const failures = groups.flatMap((group) => this.#failures(group));
      if (failures.length !== 0) throw new TaskFailure(failures);
    });
  }
  get rootContext(): TaskContext {
    return this.#context(this.#root);
  }
  /** Teardown retains every suspended child until its Promise settles. */
  dispose(): Completion<void> {
    if (this.#disposed) return;
    this.#root.cancel = true;
    const groups = [...this.#root.groups];
    for (const group of groups) {
      for (const task of group.children) this.#request(task);
    }
    const drain = (index: number): Completion<void> => {
      if (index === groups.length) return;
      return after(
        this.#close(groups[index]),
        () => drain(index + 1),
      );
    };
    return after(drain(0), () => {
      this.#disposed = true;
      const failures: unknown[] = [];
      for (const group of groups) {
        failures.push(...this.#failures(group));
      }
      if (failures.length !== 0) throw new TaskFailure(failures);
    });
  }
  get liveRecords(): number {
    return this.#tasks.size + this.#groups.size;
  }
}
