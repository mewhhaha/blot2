// Cooperative ABI 8 processes. Each admitted child gets a private Wasm instance.
// Only registered init/step pairs with bounded work belong on a frame thread.
import { type Guest, instantiateGuest, readGuestAbi } from "./guest.ts";

export interface ProcessProgram {
  readonly name: string;
  readonly initWork: number;
  readonly stepWork: number;
}

export type ProcessStatus = "starting" | "ready" | "failed" | "closed";
export type ProcessEvent =
  | { ticket: number; status: "done"; value: number }
  | { ticket: number; status: "cancelled" | "failed" };

interface Child {
  program: ProcessProgram;
  config: number;
  status: ProcessStatus;
  state: number;
  guest?: Guest;
  pending: Map<number, number>;
  events: ProcessEvent[];
}

function positive(n: number) {
  if (!Number.isSafeInteger(n) || n <= 0) {
    throw new RangeError("Expected a positive integer");
  }
}

let nextEndpoint = 1;
export class ProcessHost {
  readonly #programs = new Map<string, ProcessProgram>();
  readonly #children = new Map<number, Child>();
  readonly #order: number[] = [];
  #cursor = 0;
  #nextTicket = 1;
  #running = false;
  #generation = 0;

  constructor(
    readonly module: WebAssembly.Module,
    programs: readonly ProcessProgram[],
    readonly slots: number = 4,
    readonly mailbox: number = 8,
  ) {
    positive(slots);
    positive(mailbox);
    const abi = readGuestAbi(module);
    for (const p of programs) {
      positive(p.initWork);
      positive(p.stepWork);
      const init = abi.functions.find((f) => f.name === p.name);
      const step = abi.functions.find((f) => f.name === p.name + "_step");
      if (
        !/^[A-Za-z_][A-Za-z0-9_]{0,63}$/.test(p.name) ||
        this.#programs.has(p.name) || init?.parameter !== "U32" ||
        init.result !== "U32" ||
        step?.parameter !== "Array U32" || step.result !== "U32" ||
        init.multiplicity === "once" || step.multiplicity === "once"
      ) {
        throw new Error("Invalid process entry pair: " + p.name);
      }
      this.#programs.set(p.name, { ...p });
    }
  }

  /** A start effect packet contains one configuration word followed by ASCII name bytes. */
  admit(packet: Uint32Array): number {
    if (
      packet.length < 2 || packet.length > 65 ||
      this.#children.size === this.slots ||
      nextEndpoint > 0xffff_ffff
    ) return 0;
    let name = "";
    for (const byte of packet.subarray(1)) {
      if (byte > 127) return 0;
      name += String.fromCharCode(byte);
    }
    const program = this.#programs.get(name);
    if (!program) return 0;
    const id = nextEndpoint++;
    this.#children.set(id, {
      program,
      config: packet[0],
      status: "starting",
      state: 0,
      pending: new Map(),
      events: [],
    });
    this.#order.push(id);
    return id;
  }

  status(id: number): ProcessStatus {
    return this.#children.get(id)?.status ?? "closed";
  }

  send(id: number, command: number): number | "starting" | "full" | "closed" {
    if ((command >>> 0) !== command) {
      throw new RangeError("Expected a U32 command");
    }
    const child = this.#children.get(id);
    if (!child || child.status === "failed" || child.status === "closed") {
      return "closed";
    }
    if (child.status === "starting") return "starting";
    // A ticket owns one terminal slot until its caller consumes the event.
    if (child.pending.size + child.events.length >= this.mailbox) return "full";
    positive(this.#nextTicket);
    const ticket = this.#nextTicket++;
    child.pending.set(ticket, command);
    return ticket;
  }

  poll(id: number): ProcessEvent | undefined {
    return this.#children.get(id)?.events.shift();
  }

  cancel(id: number, ticket: number): boolean {
    const child = this.#children.get(id);
    if (!child?.pending.delete(ticket)) return false;
    child.events.push({ ticket, status: "cancelled" });
    return true;
  }

  /** Budget is shared by all children. Initialization is a turn of its own. */
  async advance(budget: number): Promise<number> {
    if (!Number.isSafeInteger(budget) || budget < 0) {
      throw new RangeError("Invalid turn budget");
    }
    if (this.#running) {
      throw new Error("Process scheduler is already advancing");
    }
    this.#running = true;
    const generation = this.#generation;
    let spent = 0;
    try {
      let skipped = 0;
      while (
        generation === this.#generation && spent < budget &&
        skipped < this.#order.length
      ) {
        const id = this.#order[this.#cursor];
        this.#cursor = (this.#cursor + 1) % this.#order.length;
        const c = this.#children.get(id)!;
        const starting = c.status === "starting";
        let cost = c.program.stepWork;
        if (starting) cost = c.program.initWork;
        if (
          (!starting && (c.status !== "ready" || !c.pending.size)) ||
          cost > budget - spent
        ) {
          skipped++;
          continue;
        }
        skipped = 0;
        spent += cost;
        try {
          if (starting) {
            const guest = await instantiateGuest(this.module);
            if (this.#children.get(id) !== c || c.status !== "starting") {
              guest.dispose();
              continue;
            }
            c.guest = guest;
            c.state = guest.call(c.program.name, c.config) as number;
            c.status = "ready";
          } else {
            const [ticket, command] = c.pending.entries().next().value!;
            c.state = c.guest!.call(
              c.program.name + "_step",
              Uint32Array.of(c.state, command),
            ) as number;
            c.pending.delete(ticket);
            c.events.push({ ticket, status: "done", value: c.state });
          }
        } catch {
          if (
            this.#children.get(id) === c &&
            (c.status === "ready" || c.status === "starting")
          ) {
            this.#settle(c, "failed");
          }
        }
      }
      return spent;
    } finally {
      this.#running = false;
    }
  }

  #settle(c: Child, status: "closed" | "failed") {
    c.status = status;
    c.guest?.dispose();
    c.guest = undefined;
    let terminal: "failed" | "cancelled" = "cancelled";
    if (status === "failed") terminal = "failed";
    for (const ticket of c.pending.keys()) {
      c.events.push({ ticket, status: terminal });
    }
    c.pending.clear();
  }

  close(id: number): void {
    const c = this.#children.get(id);
    if (c?.status === "starting" || c?.status === "ready") {
      this.#settle(c, "closed");
    }
  }

  /** Reclaim a terminal child after its accepted tickets have been observed. */
  release(id: number): boolean {
    const c = this.#children.get(id);
    if (
      !c || c.status === "ready" || c.status === "starting" || c.events.length
    ) return false;
    const i = this.#order.indexOf(id);
    this.#order.splice(i, 1);
    if (i < this.#cursor) this.#cursor--;
    if (this.#cursor >= this.#order.length) this.#cursor = 0;
    return this.#children.delete(id);
  }

  /** Fence all old endpoints and give their owner its undelivered terminal events. */
  restore(): ReadonlyMap<number, readonly ProcessEvent[]> {
    this.#generation++;
    const retired = new Map<number, readonly ProcessEvent[]>();
    for (const [id, child] of this.#children) {
      this.close(id);
      if (child.events.length) retired.set(id, child.events);
    }
    this.#children.clear();
    this.#order.length = 0;
    this.#cursor = 0;
    return retired;
  }
}
