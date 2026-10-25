// Independent output witnesses; no witness executes inside timed code.
const add = (a: number, b: number) => (a + b) >>> 0;
const mul = (a: number, b: number) => Math.imul(a, b) >>> 0;
const sum = (xs: number[]) => xs.reduce(add, 0);
const values = (seed: number, n: number, stride: number, modulus: number) =>
  Array.from({ length: n }, (_, i) => add(seed, mul(i, stride)) % modulus);
export const workloads: Record<string, (seed: number) => number> = {
  fibonacci(seed) {
    return sum(Array.from({ length: 2048 }, (_, i) => {
      let a = 0, b = 1;
      for (let j = 0; j < 24 + add(seed, i) % 16; j++) [a, b] = [b, add(a, b)];
      return a;
    }));
  },
  gcd(seed) {
    return sum(Array.from({ length: 4096 }, (_, i) => {
      let a = add(seed, i * 7919), b = i * 104729 + 1;
      while (b) [a, b] = [b, a % b];
      return a;
    }));
  },
  prime_sieve(seed) {
    const n = 16384 + seed % 1024, prime = new Uint8Array(n).fill(1);
    prime[0] = prime[1] = 0;
    for (let p = 2; p * p < n; p++) {
      if (prime[p]) { for (let i = p * p; i < n; i += p) prime[i] = 0; }
    }
    return prime.reduce((sum, yes, i) => sum + yes * i, 0);
  },
  integer_recurrence(seed) {
    let state = seed, total = 0;
    for (let i = 0; i < 65536; i++) {
      state = add(mul(state, 1664525), 1013904223);
      total = add(total, state >>> 16);
    }
    return total;
  },
  array_map_reduce: (seed) =>
    sum(values(seed, 8192, 7919, 65536).map((x) => add(mul(x, x), 3))),
  array_filter: (seed) =>
    sum(values(seed, 8192, 7919, 65536).filter((x) => x % 3 === 0)),
  prefix_scan(seed) {
    let total = 0;
    return sum(values(seed, 8192, 1, 256).map((x) => total = add(total, x)));
  },
  histogram(seed) {
    const bins = new Uint32Array(256);
    let state = seed;
    for (let i = 0; i < 16384; i++) {
      state = add(mul(state, 1664525), 1013904223);
      bins[(state >>> 16) % 256]++;
    }
    return bins.reduce((sum, n, i) => sum + n * (i + 1), 0);
  },
  dot_product(seed) {
    const a = values(seed, 8192, 17, 1024), b = values(seed, 8192, 31, 1024);
    return sum(a.map((x, i) => mul(x, b[i])));
  },
  matrix_multiply(seed) {
    const n = 24,
      a = values(seed, n * n, 17, 256),
      b = values(seed, n * n, 31, 256);
    let total = 0;
    for (let i = 0; i < n; i++) {
      for (let j = 0; j < n; j++) {
        for (let k = 0; k < n; k++) {
          total = add(total, mul(a[i * n + k], b[k * n + j]));
        }
      }
    }
    return total;
  },
  binary_search: (seed) =>
    sum(
      values(seed, 4096, 7919, 16384).map((x) =>
        x % 3 === 0 && x / 3 < 4096 ? x / 3 + 1 : 0
      ),
    ),
  list_pipeline: (seed) =>
    sum(
      values(seed, 4096, 1, 1024).map((x) => x * 3).filter((x) => x % 2 === 0),
    ),
  option_pipeline: (seed) =>
    sum(
      Array.from({ length: 16384 }, (_, i) => add(seed, i)).filter((x) =>
        x % 5 !== 0
      ).map((x) => add(mul(x, 3), 1)),
    ),
  decimal_format(seed) {
    const text = Array.from(
      { length: 512 },
      (_, i) => `${add(seed, i * 7919)},`,
    ).join("");
    return [...text].reduce(
      (total, char) => add(mul(total, 31), char.charCodeAt(0)),
      0,
    );
  },
  csv_numbers: (seed) => sum(values(seed, 512, 7919, 65536)),
  tree_reduce(seed) {
    const reduce = (depth: number, value: number): number =>
      depth === 0 ? value : add(
        reduce(depth - 1, add(mul(value, 3), 1)),
        reduce(depth - 1, add(mul(value, 5), 7)),
      );
    return reduce(10, seed);
  },
  expression_eval(seed) {
    const evaluate = (depth: number, value: number): number => {
      if (depth === 0) return value % 16;
      const a = evaluate(depth - 1, add(mul(value, 3), 1));
      const b = evaluate(depth - 1, add(mul(value, 5), 7));
      return value % 2 === 0 ? add(a, b) : mul(a, b);
    };
    return evaluate(9, seed);
  },
  run_length(seed) {
    const input = Array.from(
      { length: 8192 },
      (_, i) => add(seed, Math.floor(i / 7)) % 16,
    );
    let total = 0;
    for (let i = 0; i < input.length;) {
      let j = i + 1;
      while (j < input.length && input[j] === input[i]) j++;
      total = add(mul(total, 31), mul(input[i], j - i));
      i = j;
    }
    return total;
  },
};
