/** Invocation-owned cleanup. A reservation is made before acquisition, so
 * registration performs no allocation and exposes no resource before ownership
 * has moved to the journal. Adapter calls must be finite and synchronous. */
export interface ResourceAdapter {
  cleanup(payload: number, callable: number, provider: number): void;
  drop(payload: number, callable: number, provider: number): void;
}
export interface ResourceBindings {
  capture(): number;
  retain(binding: number): void;
  release(binding: number): void;
}
/** One instance owns token identity and the live-resource budget across tasks.
 * Transfers preserve the token and consume no additional live reservation. */
export class ResourceTokens {
  #next = 1;
  #live = 0;
  reserve(): number {
    if (this.#live === 4096 || this.#next > 0xFFFFFFFF) {
      throw new Error("Resource journal limit");
    }
    this.#live++;
    return this.#next++;
  }
  release(): void {
    if (this.#live === 0) throw new Error("Resource token has no owner");
    this.#live--;
  }
}
export class ResourceJournal {
  readonly #bindings?: Uint32Array;
  readonly #entries = new Uint32Array(4096 * 7);
  #count = 0;
  #phase: "idle" | "active" | "draining" = "idle";
  constructor(
    readonly adapters: readonly ResourceAdapter[],
    readonly invalidate?: (owner: number, token: number) => void,
    readonly bindings?: ResourceBindings,
    readonly tokens = new ResourceTokens(),
  ) {
    if (bindings) this.#bindings = new Uint32Array(4096);
  }

  begin(): void {
    if (this.#phase !== "idle") {
      throw new Error("Resource invocation is active");
    }
    this.#phase = "active";
  }
  reserve(): number {
    if (this.#phase !== "active") {
      throw new Error("No active resource invocation");
    }
    if (this.#count === 4096) {
      throw new Error("Resource journal limit");
    }
    const token = this.tokens.reserve();
    const offset = this.#count++ * 7;
    this.#entries[offset] = token;
    this.#entries[offset + 1] = 0;
    return token;
  }
  register(
    token: number,
    adapter: number,
    payload: number,
    callable: number,
    provider: number,
  ): void {
    this.#register(token, adapter, payload, callable, provider, 0);
  }
  registerOwned(
    token: number,
    adapter: number,
    payload: number,
    callable: number,
    provider: number,
    owner: number,
  ): void {
    if (
      !this.invalidate || !Number.isInteger(owner) || owner <= 0 ||
      owner > 0xFFFFFFFF
    ) throw new Error("Invalid resource owner registration");
    this.#register(token, adapter, payload, callable, provider, owner);
  }
  #register(
    token: number,
    adapter: number,
    payload: number,
    callable: number,
    provider: number,
    owner: number,
  ): void {
    const offset = this.#find(token);
    if (
      this.#phase !== "active" || this.#entries[offset + 1] !== 0 ||
      !Number.isInteger(adapter) || adapter < 0 ||
      adapter >= this.adapters.length
    ) throw new Error("Invalid resource registration");
    const binding = this.bindings?.capture() ?? 0;
    if (binding !== 0) this.bindings!.retain(binding);
    if (this.#bindings) this.#bindings[offset / 7] = binding;
    this.#entries[offset + 2] = adapter;
    this.#entries[offset + 3] = payload;
    this.#entries[offset + 4] = callable;
    this.#entries[offset + 5] = provider;
    // The owner is weak; retirement clears it before storage can be reused.
    this.#entries[offset + 6] = owner;
    this.#entries[offset + 1] = 1;
  }
  release(token: number): void {
    if (this.#phase !== "active") {
      throw new Error("No active resource invocation");
    }
    try {
      this.#release(this.#find(token));
    } finally {
      this.#reclaim();
    }
  }
  /** Move an exact cleanup obligation with its typed owner/captures. Capacity
   * and adapter domains are admitted before either journal changes. */
  transfer(token: number, destination: ResourceJournal): void {
    if (
      this.#phase !== "active" || destination.#phase !== "active" ||
      destination === this || this.tokens !== destination.tokens ||
      this.adapters !== destination.adapters ||
      this.bindings !== destination.bindings ||
      this.invalidate !== destination.invalidate
    ) throw new Error("Resource transfer crosses an ownership domain");
    const offset = this.#find(token);
    const state = this.#entries[offset + 1];
    if (state !== 1 && state !== 4) {
      throw new Error("Resource is not owned");
    }
    if (destination.#count === 4096) throw new Error("Resource journal limit");
    const target = destination.#count * 7;
    for (let index = 0; index < 7; index++) {
      destination.#entries[target + index] = this.#entries[offset + index];
    }
    if (this.#bindings) {
      destination.#bindings![destination.#count] = this.#bindings[offset / 7];
      this.#bindings[offset / 7] = 0;
    }
    destination.#count++;
    this.#entries[offset + 1] = 2;
    this.#entries[offset + 6] = 0;
    this.#reclaim();
  }
  /** Counted destruction queues an attempt without running user code inside
   * the heap transaction. The next safe point drains these retired owners. */
  retire(token: number): void {
    if (this.#phase === "idle") {
      throw new Error("No active resource invocation");
    }
    const offset = this.#find(token);
    if (this.#entries[offset + 1] !== 1 && this.#entries[offset + 1] !== 4) {
      throw new Error("Resource is not owned");
    }
    this.#entries[offset + 6] = 0;
    this.#entries[offset + 1] = 3;
  }
  drain(): void {
    // Compiler safe points inside an adapter's root-drop cannot start a nested
    // user attempt. The outer scan observes their newly retired captures.
    if (this.#phase === "draining") return;
    if (this.#phase !== "active") {
      throw new Error("No active resource invocation");
    }
    this.#phase = "draining";
    try {
      this.#drain(false);
    } finally {
      this.#reclaim();
      this.#phase = "active";
    }
  }
  #reclaim(): void {
    // Transfers can retire an older owner while a newer one remains live.
    // Compact stable registration order without allocating or reusing tokens.
    let target = 0;
    for (let index = 0; index < this.#count; index++) {
      const offset = index * 7;
      if (this.#entries[offset + 1] === 2) continue;
      if (target !== index) {
        this.#entries.copyWithin(target * 7, offset, offset + 7);
        if (this.#bindings) this.#bindings[target] = this.#bindings[index];
      }
      target++;
    }
    this.#count = target;
  }
  #find(token: number): number {
    if (!Number.isInteger(token) || token <= 0 || token > 0xFFFFFFFF) {
      throw new Error("Invalid resource token");
    }
    for (let index = this.#count - 1; index >= 0; index--) {
      if (this.#entries[index * 7] === token) return index * 7;
    }
    throw new Error("Stale resource token");
  }
  #release(offset: number): void {
    if (
      this.#entries[offset + 1] !== 1 && this.#entries[offset + 1] !== 3 &&
      this.#entries[offset + 1] !== 4
    ) {
      throw new Error("Resource is not owned");
    }
    const phase = this.#phase;
    this.#phase = "draining";
    // Take before calling arbitrary code: traps and reentrancy cannot retry it.
    this.#entries[offset + 1] = 2;
    this.tokens.release();
    const adapter = this.adapters[this.#entries[offset + 2]];
    const payload = this.#entries[offset + 3];
    const callable = this.#entries[offset + 4];
    const provider = this.#entries[offset + 5];
    const owner = this.#entries[offset + 6];
    const token = this.#entries[offset];
    this.#entries[offset + 6] = 0;
    const binding = this.#bindings?.[offset / 7] ?? 0;
    if (this.#bindings) this.#bindings[offset / 7] = 0;
    let failed = false;
    let failure: unknown;
    try {
      if (owner !== 0) this.invalidate!(owner, token);
      adapter.cleanup(payload, callable, provider);
    } catch (cause) {
      failed = true;
      failure = cause;
    }
    try {
      adapter.drop(payload, callable, provider);
    } catch (cause) {
      if (!failed) {
        failed = true;
        failure = cause;
      }
    }
    if (binding !== 0) {
      try {
        this.bindings!.release(binding);
      } catch (cause) {
        if (!failed) {
          failed = true;
          failure = cause;
        }
      }
    }
    this.#phase = phase;
    if (failed) throw failure;
  }
  /** Native typed leases have already published a strong owner edge. */
  promote(token: number): void {
    if (this.#phase !== "active") {
      throw new Error("No active resource invocation");
    }
    const offset = this.#find(token);
    const state = this.#entries[offset + 1];
    if ((state !== 1 && state !== 4) || this.#entries[offset + 6] === 0) {
      throw new Error("Resource has no live owning lease");
    }
    this.#entries[offset + 1] = 4;
  }
  #drain(all: boolean, persistent = false): void {
    let failed = false;
    let failure: unknown;
    // A drop can retire an owning capture registered later than its parent.
    // Restart the reverse scan so newly queued obligations also complete here.
    while (true) {
      let selected = -1;
      for (let index = this.#count - 1; index >= 0; index--) {
        const state = this.#entries[index * 7 + 1];
        if (state === 3 || all && state === 1 || persistent && state === 4) {
          selected = index * 7;
          break;
        }
      }
      if (selected === -1) break;
      try {
        this.#release(selected);
      } catch (cause) {
        if (!failed) {
          failed = true;
          failure = cause;
        }
      }
    }
    if (failed) throw failure;
  }
  finish(): void {
    if (this.#phase === "idle") return;
    if (this.#phase !== "active") throw new Error("Resource cleanup is active");
    this.#phase = "draining";
    try {
      this.#drain(true);
    } finally {
      for (let index = 0; index < this.#count; index++) {
        const offset = index * 7;
        if (this.#entries[offset + 1] === 0) {
          this.#entries[offset + 1] = 2;
          this.tokens.release();
        }
      }
      this.#reclaim();
      this.#phase = "idle";
    }
  }
  dispose(): void {
    if (this.#phase !== "active") {
      throw new Error("No active resource invocation");
    }
    this.#phase = "draining";
    try {
      this.#drain(true, true);
    } finally {
      for (let index = 0; index < this.#count; index++) {
        if (this.#entries[index * 7 + 1] === 0) this.tokens.release();
      }
      this.#count = 0;
      this.#phase = "active";
    }
  }
}
