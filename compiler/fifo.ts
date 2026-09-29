/** Amortized O(1) FIFO; consumed jobs do not retain their payloads. */
export class Fifo<T> {
  #items: (T | undefined)[] = [];
  #head = 0;

  get length(): number {
    return this.#items.length - this.#head;
  }

  push(value: T): void {
    this.#items.push(value);
  }

  shift(): T | undefined {
    if (this.#head === this.#items.length) return undefined;
    const value = this.#items[this.#head];
    this.#items[this.#head++] = undefined;
    if (this.#head === this.#items.length) {
      this.clear();
    } else if (this.#head >= 1024 && this.#head * 2 >= this.#items.length) {
      // Copy only after consuming at least as much as remains. This bounds
      // both total copying and retained backing capacity for long-lived pools.
      this.#items = this.#items.slice(this.#head);
      this.#head = 0;
    }
    return value;
  }

  clear(): void {
    this.#items = [];
    this.#head = 0;
  }
}
